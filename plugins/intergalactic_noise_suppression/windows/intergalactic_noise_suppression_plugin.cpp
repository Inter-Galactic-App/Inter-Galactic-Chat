#include "include/intergalactic_noise_suppression/intergalactic_noise_suppression_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>

#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>

#include "rnnoise_capture_processor.h"
#include "wasapi_sidecar_capture.h"

namespace {

std::string EscapeJson(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size());

  for (const char ch : value) {
    switch (ch) {
      case '\\':
        escaped += "\\\\";
        break;
      case '"':
        escaped += "\\\"";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        escaped += ch;
        break;
    }
  }

  return escaped;
}

class NoiseSuppressionManager {
 public:
  static NoiseSuppressionManager& Instance() {
    static NoiseSuppressionManager instance;
    return instance;
  }

  bool Initialize() {
    std::lock_guard<std::mutex> lock(mutex_);
    initialized_ = true;
    return EnsureHookLocked();
  }

  bool Configure(double vad_threshold,
                 int speech_grace_frames,
                 double closed_gain,
                 double transient_sensitivity,
                 bool fast_close_enabled,
                 bool deepfilternet_transient_suppression_enabled,
                 bool deepfilternet_hush_suppression_enabled) {
    std::lock_guard<std::mutex> lock(mutex_);
    vad_threshold_ = ClampDouble(vad_threshold, 0.50, 0.999, 0.90);
    speech_grace_frames_ =
        (std::clamp)(speech_grace_frames, 0, 60);
    closed_gain_ = ClampDouble(closed_gain, 0.0, 1.0, 0.03);
    transient_sensitivity_ =
        ClampDouble(transient_sensitivity, 0.0, 1.0, 0.0);
    fast_close_enabled_ = fast_close_enabled;
    deepfilternet_transient_suppression_enabled_ =
        deepfilternet_transient_suppression_enabled;
    deepfilternet_hush_suppression_enabled_ =
        deepfilternet_hush_suppression_enabled;
    ApplyTuningLocked();
    return true;
  }

  bool SetPipelineMode(int mode) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (mode < intergalactic_noise_suppression::kRnnoisePipelineModeOff ||
        mode >
            intergalactic_noise_suppression::
                kRnnoisePipelineModeDeepFilterNet) {
      mode = intergalactic_noise_suppression::kRnnoisePipelineModeCleanRnnoise;
    }
    const int previous_mode = shared_state_->pipeline_mode.exchange(mode);
    if (previous_mode != mode &&
        mode !=
            intergalactic_noise_suppression::kRnnoisePipelineModeDeepFilterNet) {
      shared_state_->deepfilternet_runtime_available.store(false);
      shared_state_->deepfilternet_processing_applied.store(false);
      shared_state_->deepfilternet_frames_processed.store(0);
      shared_state_->deepfilternet_bypass_frames.store(0);
      shared_state_->deepfilternet_frame_length.store(0);
      shared_state_->deepfilternet_reason.store(
          intergalactic_noise_suppression::
              kDeepFilterNetRuntimeReasonNotInitialized);
      shared_state_->deepfilternet_last_local_snr.store(0.0);
      shared_state_->deepfilternet_speech_protected_frames.store(0);
      shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
      shared_state_->deepfilternet_transient_suppressed_frames.store(0);
      shared_state_->deepfilternet_transient_adjusted_samples.store(0);
      shared_state_->deepfilternet_last_transient_gain.store(1.0);
      ResetHushDiagnosticsLocked();
    }
    return true;
  }

  bool StartDiagnosticCapture(const char* directory,
                              int duration_ms,
                              int stage_mask) {
    return StartTapOrderCapture(
        directory, duration_ms, stage_mask, false, nullptr);
  }

  bool StartTapOrderCapture(const char* directory,
                            int duration_ms,
                            int stage_mask,
                            bool include_wasapi_sidecar,
                            const char* wasapi_device_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (directory == nullptr) {
      return false;
    }
    sidecar_capture_.Stop();
    const bool hook_capture_started =
        shared_state_->diagnostic_capture->Start(
        directory,
        duration_ms,
        stage_mask);
    if (include_wasapi_sidecar) {
      sidecar_capture_.Start(
          directory,
          duration_ms,
          wasapi_device_id == nullptr ? "" : wasapi_device_id);
    }
    return hook_capture_started;
  }

  bool StopDiagnosticCapture() {
    std::lock_guard<std::mutex> lock(mutex_);
    const bool hook_stopped = shared_state_->diagnostic_capture->Stop();
    sidecar_capture_.Stop();
    return hook_stopped;
  }

  bool SetEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(mutex_);
    desired_enabled_ = enabled;
    shared_state_->enabled_requested.store(enabled);
    // Do NOT call EnsureHookLocked() here.  Installing or touching the
    // capture-post-processing hook while the audio pipeline is already running
    // can stall or silently break capture on some libwebrtc builds.  The hook
    // is installed exactly once by Initialize().  If Initialize() failed
    // (e.g. flutter_webrtc was not yet registered at startup), the hook stays
    // absent, available == false, and shouldDisableBuiltInNoiseSuppression
    // stays false, so built-in NS is kept active.
    return hook_registered_ && !shared_state_->released.load();
  }

  void Shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);
    desired_enabled_ = false;
    shared_state_->enabled_requested.store(false);
  }

  std::string StatusJson() {
    std::lock_guard<std::mutex> lock(mutex_);

    const bool available =
        hook_registered_ && !shared_state_->released.load();
    const bool enabled = available && desired_enabled_;
    const bool format_mismatch =
        shared_state_->format_mismatch_detected.load();
    const bool suspicious_output =
        shared_state_->suspicious_output_detected.load();
    const int frames_processed = shared_state_->frames_processed.load();
    const bool active =
        enabled && frames_processed > 0 && !format_mismatch && !suspicious_output;

    std::ostringstream json;
    json << "{";
    json << "\"supported\":true,";
    json << "\"available\":" << (available ? "true" : "false") << ",";
    json << "\"requestedEnabled\":"
         << (desired_enabled_ ? "true" : "false") << ",";
    json << "\"enabled\":" << (enabled ? "true" : "false") << ",";
    json << "\"active\":" << (active ? "true" : "false") << ",";
    json << "\"formatMismatchDetected\":"
         << (format_mismatch ? "true" : "false") << ",";
    json << "\"suspiciousOutputDetected\":"
         << (suspicious_output ? "true" : "false") << ",";
    json << "\"formatMismatchReason\":\""
         << EscapeJson(
                intergalactic_noise_suppression::
                    RnnoiseFormatMismatchReasonToString(
                        shared_state_->format_mismatch_reason.load()))
         << "\",";
    json << "\"sampleRateHz\":" << shared_state_->sample_rate_hz.load() << ",";
    json << "\"numChannels\":" << shared_state_->num_channels.load() << ",";
    json << "\"expectedFramesPer10ms\":"
         << shared_state_->expected_frames_per_10ms.load() << ",";
    json << "\"lastNumBands\":" << shared_state_->last_num_bands.load() << ",";
    json << "\"lastNumFrames\":" << shared_state_->last_num_frames.load() << ",";
    json << "\"lastBufferSize\":"
         << shared_state_->last_buffer_size.load() << ",";
    json << "\"framesProcessed\":" << frames_processed << ",";
    json << "\"bypassFrames\":"
         << shared_state_->bypass_frames.load() << ",";
    json << "\"gatedFrames\":"
         << shared_state_->gated_frames.load() << ",";
    json << "\"resamplerUses\":"
         << shared_state_->resampler_uses.load() << ",";
    json << "\"resamplerInputUnderruns\":"
         << shared_state_->resampler_input_underruns.load() << ",";
    json << "\"resamplerOutputUnderruns\":"
         << shared_state_->resampler_output_underruns.load() << ",";
    json << "\"resamplerOverruns\":"
         << shared_state_->resampler_overruns.load() << ",";
    json << "\"resamplerMode\":\""
         << EscapeJson(
                intergalactic_noise_suppression::RnnoiseResamplerModeToString(
                    shared_state_->last_resampler_mode.load()))
         << "\",";
    json << "\"resamplerInputFrames\":"
         << shared_state_->last_resampler_input_frames.load() << ",";
    json << "\"resamplerOutputFrames\":"
         << shared_state_->last_resampler_output_frames.load() << ",";
    json << "\"resamplerSourceRateHz\":"
         << shared_state_->last_resampler_source_rate_hz.load() << ",";
    json << "\"resamplerTargetRateHz\":"
         << shared_state_->last_resampler_target_rate_hz.load() << ",";
    json << "\"pipelineMode\":\""
         << EscapeJson(
                intergalactic_noise_suppression::RnnoisePipelineModeToString(
                    shared_state_->pipeline_mode.load()))
         << "\",";
    json << "\"vadLowFrames\":"
         << shared_state_->vad_low_frames.load() << ",";
    json << "\"vadMidFrames\":"
         << shared_state_->vad_mid_frames.load() << ",";
    json << "\"vadHighFrames\":"
         << shared_state_->vad_high_frames.load() << ",";
    json << "\"referenceVadThreshold\":"
         << shared_state_->reference_vad_threshold.load() << ",";
    json << "\"recentVadAverage\":"
         << shared_state_->recent_vad_average.load() << ",";
    json << "\"speechGraceRemainingFrames\":"
         << shared_state_->speech_grace_remaining_frames.load() << ",";
    json << "\"referenceSpeechGraceFrames\":"
         << shared_state_->reference_speech_grace_frames.load() << ",";
    json << "\"noiseGateClosedGain\":"
         << shared_state_->noise_gate_closed_gain.load() << ",";
    json << "\"transientSensitivity\":"
         << shared_state_->transient_sensitivity.load() << ",";
    json << "\"fastCloseEnabled\":"
         << (shared_state_->fast_close_enabled.load() ? "true" : "false")
         << ",";
    json << "\"lastGateReason\":\""
         << EscapeJson(
                intergalactic_noise_suppression::RnnoiseGateReasonToString(
                    shared_state_->last_gate_reason.load()))
         << "\",";
    json << "\"lastGateGain\":"
         << shared_state_->last_gate_gain.load() << ",";
    json << "\"lastInputScaleFactor\":"
         << shared_state_->last_input_scale_factor.load() << ",";
    json << "\"lastVadProbability\":"
         << shared_state_->last_vad_probability.load() << ",";
    json << "\"lastInputRms\":"
         << shared_state_->last_input_rms.load() << ",";
    json << "\"lastOutputRms\":"
         << shared_state_->last_output_rms.load() << ",";
    json << "\"lastOutputRatio\":"
         << shared_state_->last_output_ratio.load() << ",";
    json << "\"lastInputPeak\":"
         << shared_state_->last_input_peak.load() << ",";
    json << "\"lastOutputPeak\":"
         << shared_state_->last_output_peak.load() << ",";
    json << "\"lastInputMin\":"
         << shared_state_->last_input_min.load() << ",";
    json << "\"lastInputMax\":"
         << shared_state_->last_input_max.load() << ",";
    json << "\"lastOutputMin\":"
         << shared_state_->last_output_min.load() << ",";
    json << "\"lastOutputMax\":"
         << shared_state_->last_output_max.load() << ",";
    json << "\"lastInputMaxDelta\":"
         << shared_state_->last_input_max_delta.load() << ",";
    json << "\"lastOutputMaxDelta\":"
         << shared_state_->last_output_max_delta.load() << ",";
    json << "\"processingApplied\":"
         << (shared_state_->processing_applied.load() ? "true" : "false")
         << ",";
    json << "\"identityFrames\":"
         << shared_state_->identity_frames.load() << ",";
    json << "\"prototypeStageFrames\":"
         << shared_state_->prototype_stage_frames.load() << ",";
    json << "\"prototypeTransientFrames\":"
         << shared_state_->prototype_transient_frames.load() << ",";
    json << "\"prototypeStationaryFrames\":"
         << shared_state_->prototype_stationary_frames.load() << ",";
    json << "\"prototypeSpeechProtectedFrames\":"
         << shared_state_->prototype_speech_protected_frames.load() << ",";
    json << "\"prototypeAdjustedSamples\":"
         << shared_state_->prototype_adjusted_samples.load() << ",";
    json << "\"prototypeNoiseFloorRms\":"
         << shared_state_->prototype_noise_floor_rms.load() << ",";
    json << "\"prototypeLastGain\":"
         << shared_state_->prototype_last_gain.load() << ",";
    json << "\"deepFilterNetRuntimeAvailable\":"
         << (shared_state_->deepfilternet_runtime_available.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetProcessingApplied\":"
         << (shared_state_->deepfilternet_processing_applied.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetFramesProcessed\":"
         << shared_state_->deepfilternet_frames_processed.load() << ",";
    json << "\"deepFilterNetBypassFrames\":"
         << shared_state_->deepfilternet_bypass_frames.load() << ",";
    json << "\"deepFilterNetFrameLength\":"
         << shared_state_->deepfilternet_frame_length.load() << ",";
    json << "\"deepFilterNetReason\":\""
         << EscapeJson(
                intergalactic_noise_suppression::
                    DeepFilterNetRuntimeReasonToString(
                        shared_state_->deepfilternet_reason.load()))
         << "\",";
    json << "\"deepFilterNetLastLocalSnr\":"
         << shared_state_->deepfilternet_last_local_snr.load() << ",";
    json << "\"deepFilterNetSpeechProtectedFrames\":"
         << shared_state_->deepfilternet_speech_protected_frames.load()
         << ",";
    json << "\"deepFilterNetLastSpeechProtectWetMix\":"
         << shared_state_->deepfilternet_last_speech_protect_wet_mix.load()
         << ",";
    json << "\"deepFilterNetAttenuationLimitDb\":"
         << intergalactic_noise_suppression::DeepFilterNetRuntime::
                AttenuationLimitDb()
         << ",";
    json << "\"deepFilterNetPostFilterBeta\":"
         << intergalactic_noise_suppression::DeepFilterNetRuntime::
                PostFilterBeta()
         << ",";
    json << "\"deepFilterNetTransientSuppressionEnabled\":"
         << (shared_state_->deepfilternet_transient_suppression_enabled.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetTransientSuppressedFrames\":"
         << shared_state_->deepfilternet_transient_suppressed_frames.load()
         << ",";
    json << "\"deepFilterNetTransientAdjustedSamples\":"
         << shared_state_->deepfilternet_transient_adjusted_samples.load()
         << ",";
    json << "\"deepFilterNetLastTransientGain\":"
         << shared_state_->deepfilternet_last_transient_gain.load() << ",";
    json << "\"deepFilterNetHushSuppressionEnabled\":"
         << (shared_state_->deepfilternet_hush_suppression_enabled.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetHushRuntimeAvailable\":"
         << (shared_state_->deepfilternet_hush_runtime_available.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetHushProcessingApplied\":"
         << (shared_state_->deepfilternet_hush_processing_applied.load()
                 ? "true"
                 : "false")
         << ",";
    json << "\"deepFilterNetHushFramesProcessed\":"
         << shared_state_->deepfilternet_hush_frames_processed.load() << ",";
    json << "\"deepFilterNetHushBypassFrames\":"
         << shared_state_->deepfilternet_hush_bypass_frames.load() << ",";
    json << "\"deepFilterNetHushFrameLength\":"
         << shared_state_->deepfilternet_hush_frame_length.load() << ",";
    json << "\"deepFilterNetHushReason\":\""
         << EscapeJson(
                intergalactic_noise_suppression::
                    DeepFilterNetRuntimeReasonToString(
                        shared_state_->deepfilternet_hush_reason.load()))
         << "\",";
    json << "\"deepFilterNetHushLastLocalSnr\":"
         << shared_state_->deepfilternet_hush_last_local_snr.load() << ",";
    json << "\"deepFilterNetHushRecoveryFrames\":"
         << shared_state_->deepfilternet_hush_recovery_frames.load() << ",";
    json << "\"deepFilterNetHushLastRecoveryGain\":"
         << shared_state_->deepfilternet_hush_last_recovery_gain.load()
         << ",";
    json << "\"deepFilterNetHushLastInputRms\":"
         << shared_state_->deepfilternet_hush_last_input_rms.load() << ",";
    json << "\"deepFilterNetHushLastOutputRms\":"
         << shared_state_->deepfilternet_hush_last_output_rms.load() << ",";
    json << "\"clippingSamples\":"
         << shared_state_->clipping_samples.load() << ",";
    json << "\"inputClippingSamples\":"
         << shared_state_->input_clipping_samples.load() << ",";
    json << "\"outputClippingSamples\":"
         << shared_state_->output_clipping_samples.load() << ",";
    json << "\"outputLimiterSamples\":"
         << shared_state_->output_limiter_samples.load() << ",";
    json << "\"outputAntiAliasUses\":"
         << shared_state_->output_antialias_uses.load() << ",";
    json << "\"nonFiniteSamples\":"
         << shared_state_->non_finite_samples.load() << ",";
    json << "\"callbackAverageProcessingMs\":"
         << shared_state_->callback_average_processing_ms.load() << ",";
    json << "\"callbackMaxProcessingMs\":"
         << shared_state_->callback_max_processing_ms.load() << ",";
    json << "\"callbackBudgetMisses\":"
         << shared_state_->callback_budget_misses.load() << ",";
    json << "\"rnnoiseStateResets\":"
         << shared_state_->rnnoise_state_resets.load() << ",";
    json << "\"captureGapEvents\":"
         << shared_state_->capture_gap_events.load() << ",";
    json << "\"lastCallbackIntervalMs\":"
         << shared_state_->last_callback_interval_ms.load() << ",";
    json << "\"maxCallbackIntervalMs\":"
         << shared_state_->max_callback_interval_ms.load() << ",";
    json << "\"framesSinceCaptureResume\":"
         << shared_state_->frames_since_capture_resume.load() << ",";
    json << "\"deepFilterNetGapRecoveries\":"
         << shared_state_->deepfilternet_gap_recoveries.load() << ",";
    json << "\"diagnosticCaptureActive\":"
         << (shared_state_->diagnostic_capture->active() ? "true" : "false")
         << ",";
    json << "\"diagnosticCaptureFrames\":"
         << shared_state_->diagnostic_capture->captured_frames() << ",";
    json << "\"diagnosticCaptureDroppedFrames\":"
         << shared_state_->diagnostic_capture->dropped_frames() << ",";
    json << "\"diagnosticCaptureWrittenFiles\":"
         << shared_state_->diagnostic_capture->written_files() << ",";
    json << "\"diagnosticCaptureLastError\":\""
         << EscapeJson(shared_state_->diagnostic_capture->last_error())
         << "\",";
    json << "\"diagnosticCaptureStageFiles\":\""
         << "webrtc_hook_input.wav,rnnoise_input_48k.wav,"
            "rnnoise_output_48k.wav,deepfilternet_output.wav,"
            "speech_protect_output.wav,transient_guard_output.wav,"
            "hush_input_16k.wav,hush_output_16k.wav,hush_output.wav,"
            "final_to_webrtc.wav,"
            "device_raw_wasapi.wav"
         << "\",";
    json << "\"wasapiSidecarActive\":"
         << (sidecar_capture_.active() ? "true" : "false") << ",";
    json << "\"wasapiSidecarFrames\":"
         << sidecar_capture_.captured_frames() << ",";
    json << "\"wasapiSidecarDroppedPackets\":"
         << sidecar_capture_.dropped_packets() << ",";
    json << "\"wasapiSidecarWrittenFiles\":"
         << sidecar_capture_.written_files() << ",";
    json << "\"wasapiSidecarSampleRateHz\":"
         << sidecar_capture_.sample_rate_hz() << ",";
    json << "\"wasapiSidecarChannels\":"
         << sidecar_capture_.num_channels() << ",";
    json << "\"wasapiSidecarDeviceResolution\":\""
         << EscapeJson(sidecar_capture_.device_resolution()) << "\",";
    json << "\"wasapiSidecarLastError\":\""
         << EscapeJson(sidecar_capture_.last_error()) << "\",";
    json << "\"reason\":\"" << EscapeJson(CurrentReasonLocked()) << "\"";
    json << "}";
    return json.str();
  }

 private:
  NoiseSuppressionManager() = default;

  static double ClampDouble(double value,
                            double min,
                            double max,
                            double fallback) {
    if (!std::isfinite(value)) {
      return fallback;
    }

    return (std::clamp)(value, min, max);
  }

  void ResetHushDiagnosticsLocked() {
    shared_state_->deepfilternet_hush_runtime_available.store(false);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_frames_processed.store(0);
    shared_state_->deepfilternet_hush_bypass_frames.store(0);
    shared_state_->deepfilternet_hush_frame_length.store(0);
    shared_state_->deepfilternet_hush_reason.store(
        intergalactic_noise_suppression::
            kDeepFilterNetRuntimeReasonNotInitialized);
    shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
    shared_state_->deepfilternet_hush_recovery_frames.store(0);
    shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
    shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
    shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
  }

  void ApplyTuningLocked() {
    shared_state_->reference_vad_threshold.store(vad_threshold_);
    shared_state_->reference_speech_grace_frames.store(
        speech_grace_frames_);
    shared_state_->noise_gate_closed_gain.store(closed_gain_);
    shared_state_->transient_sensitivity.store(transient_sensitivity_);
    shared_state_->fast_close_enabled.store(fast_close_enabled_);
    shared_state_->deepfilternet_transient_suppression_enabled.store(
        deepfilternet_transient_suppression_enabled_);
    shared_state_->deepfilternet_hush_suppression_enabled.store(
        deepfilternet_hush_suppression_enabled_);
    if (!deepfilternet_transient_suppression_enabled_) {
      shared_state_->deepfilternet_transient_suppressed_frames.store(0);
      shared_state_->deepfilternet_transient_adjusted_samples.store(0);
      shared_state_->deepfilternet_last_transient_gain.store(1.0);
    }
    if (!deepfilternet_hush_suppression_enabled_) {
      ResetHushDiagnosticsLocked();
    }
  }

  bool EnsureHookLocked() {
    if (hook_registered_ && !shared_state_->released.load()) {
      return true;
    }

    webrtc_instance_ = FlutterWebRTCPluginSharedInstance();
    if (webrtc_instance_ == nullptr) {
      hook_registered_ = false;
      reason_ = "flutter_webrtc_unavailable";
      return false;
    }

    audio_processing_ = webrtc_instance_->audio_processing();
    if (!audio_processing_) {
      hook_registered_ = false;
      reason_ = "audio_processing_unavailable";
      return false;
    }

    if (shared_state_->released.load()) {
      shared_state_ =
          std::make_shared<intergalactic_noise_suppression::ProcessorSharedState>();
      shared_state_->enabled_requested.store(desired_enabled_);
    }
    ApplyTuningLocked();

    auto* processor =
        new intergalactic_noise_suppression::RnnoiseCaptureProcessor(shared_state_);
    audio_processing_->SetCapturePostProcessing(processor);
    hook_registered_ = true;
    reason_ = "ready";
    return true;
  }

  std::string CurrentReasonLocked() const {
    if (!initialized_) {
      return "not_initialized";
    }

    if (!hook_registered_) {
      return reason_;
    }

    if (shared_state_->released.load()) {
      return "processor_released";
    }

    if (desired_enabled_ &&
        shared_state_->format_mismatch_detected.load()) {
      return "capture_format_mismatch";
    }

    if (desired_enabled_ &&
        shared_state_->suspicious_output_detected.load()) {
      return "suspicious_output_bypassed";
    }

    if (desired_enabled_ &&
        shared_state_->frames_processed.load() == 0) {
      return "waiting_for_audio";
    }

    return reason_;
  }

  std::shared_ptr<intergalactic_noise_suppression::ProcessorSharedState>
      shared_state_ =
          std::make_shared<intergalactic_noise_suppression::ProcessorSharedState>();
  flutter_webrtc_plugin::FlutterWebRTC* webrtc_instance_ = nullptr;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioProcessing> audio_processing_;
  std::mutex mutex_;
  bool initialized_ = false;
  bool hook_registered_ = false;
  bool desired_enabled_ = false;
  double vad_threshold_ = 0.90;
  int speech_grace_frames_ = 20;
  double closed_gain_ = 0.03;
  double transient_sensitivity_ = 0.0;
  bool fast_close_enabled_ = false;
  bool deepfilternet_transient_suppression_enabled_ = false;
  bool deepfilternet_hush_suppression_enabled_ = false;
  std::string reason_ = "not_initialized";
  intergalactic_noise_suppression::WasapiSidecarCapture sidecar_capture_;
};

class IntergalacticNoiseSuppressionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    registrar->AddPlugin(
        std::make_unique<IntergalacticNoiseSuppressionPlugin>());
  }

  ~IntergalacticNoiseSuppressionPlugin() override = default;
};

}  // namespace

void IntergalacticNoiseSuppressionPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  IntergalacticNoiseSuppressionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

int intergalactic_noise_suppression_initialize() {
  return NoiseSuppressionManager::Instance().Initialize() ? 1 : 0;
}

int intergalactic_noise_suppression_configure(double vad_threshold,
                                              int speech_grace_frames,
                                              double closed_gain,
                                              double transient_sensitivity,
                                              int fast_close_enabled,
                                              int deepfilternet_transient_enabled,
                                              int deepfilternet_hush_enabled) {
  return NoiseSuppressionManager::Instance()
      .Configure(vad_threshold,
                 speech_grace_frames,
                 closed_gain,
                 transient_sensitivity,
                 fast_close_enabled != 0,
                 deepfilternet_transient_enabled != 0,
                 deepfilternet_hush_enabled != 0)
      ? 1
      : 0;
}

int intergalactic_noise_suppression_set_pipeline_mode(int mode) {
  return NoiseSuppressionManager::Instance().SetPipelineMode(mode) ? 1 : 0;
}

int intergalactic_noise_suppression_start_diagnostic_capture(
    const char* directory,
    int duration_ms,
    int stage_mask) {
  return NoiseSuppressionManager::Instance().StartDiagnosticCapture(
             directory,
             duration_ms,
             stage_mask)
      ? 1
      : 0;
}

int intergalactic_noise_suppression_start_tap_order_capture(
    const char* directory,
    int duration_ms,
    int stage_mask,
    int include_wasapi_sidecar,
    const char* wasapi_device_id) {
  return NoiseSuppressionManager::Instance().StartTapOrderCapture(
             directory,
             duration_ms,
             stage_mask,
             include_wasapi_sidecar != 0,
             wasapi_device_id)
      ? 1
      : 0;
}

int intergalactic_noise_suppression_stop_diagnostic_capture() {
  return NoiseSuppressionManager::Instance().StopDiagnosticCapture() ? 1 : 0;
}

int intergalactic_noise_suppression_set_enabled(int enabled) {
  return NoiseSuppressionManager::Instance().SetEnabled(enabled != 0) ? 1 : 0;
}

int intergalactic_noise_suppression_shutdown() {
  NoiseSuppressionManager::Instance().Shutdown();
  return 1;
}

const char* intergalactic_noise_suppression_get_status_json() {
  thread_local std::string status_json;
  status_json = NoiseSuppressionManager::Instance().StatusJson();
  return status_json.c_str();
}
