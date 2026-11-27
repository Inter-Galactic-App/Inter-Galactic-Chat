#import "IntergalacticNoiseSuppressionPlugin.h"

#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>
#import <flutter_webrtc/AudioManager.h>
#import <flutter_webrtc/AudioProcessingAdapter.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "rnnoise_capture_processor.h"

#define INTERGALACTIC_NOISE_SUPPRESSION_EXPORT __attribute__((visibility("default")))

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

}  // namespace

@interface IntergalacticNoiseSuppressionAudioProcessor
    : NSObject <ExternalAudioProcessingDelegate>
- (instancetype)initWithSharedState:
    (std::shared_ptr<intergalactic_noise_suppression::ProcessorSharedState>)
        sharedState;
@end

@implementation IntergalacticNoiseSuppressionAudioProcessor {
  std::shared_ptr<intergalactic_noise_suppression::ProcessorSharedState>
      _sharedState;
  intergalactic_noise_suppression::RnnoiseCaptureProcessor* _processor;
  std::mutex _mutex;
  std::vector<float> _captureBuffer;
  int _sampleRateHz;
  int _numChannels;
}

- (instancetype)initWithSharedState:
    (std::shared_ptr<intergalactic_noise_suppression::ProcessorSharedState>)
        sharedState {
  self = [super init];
  if (self) {
    _sharedState = std::move(sharedState);
    _processor = nullptr;
    _sampleRateHz = 0;
    _numChannels = 0;
  }
  return self;
}

- (void)dealloc {
  std::lock_guard<std::mutex> lock(_mutex);
  if (_processor != nullptr) {
    _processor->Release();
    _processor = nullptr;
  }
}

- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz
                                       channels:(size_t)channels {
  if (sampleRateHz == 0 ||
      sampleRateHz > static_cast<size_t>(std::numeric_limits<int>::max()) ||
      channels == 0 ||
      channels > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return;
  }

  std::lock_guard<std::mutex> lock(_mutex);
  if (_processor != nullptr) {
    _processor->Release();
    _processor = nullptr;
  }

  _sampleRateHz = static_cast<int>(sampleRateHz);
  _numChannels = static_cast<int>(channels);
  _processor =
      new intergalactic_noise_suppression::RnnoiseCaptureProcessor(
          _sharedState);
  _processor->Initialize(_sampleRateHz, _numChannels);
}

- (void)audioProcessingProcess:(RTC_OBJC_TYPE(RTCAudioBuffer)*)audioBuffer {
  if (audioBuffer == nil) {
    return;
  }

  const size_t frames = audioBuffer.frames;
  const size_t channels = audioBuffer.channels;
  if (frames == 0 ||
      channels == 0 ||
      frames > static_cast<size_t>(std::numeric_limits<int>::max()) ||
      channels > static_cast<size_t>(std::numeric_limits<int>::max()) ||
      frames >
          static_cast<size_t>(std::numeric_limits<int>::max()) / channels) {
    return;
  }

  std::lock_guard<std::mutex> lock(_mutex);
  if (_processor == nullptr) {
    const int inferredSampleRateHz =
        _sampleRateHz > 0 ? _sampleRateHz : static_cast<int>(frames * 100);
    _numChannels = static_cast<int>(channels);
    _sampleRateHz = inferredSampleRateHz;
    _processor =
        new intergalactic_noise_suppression::RnnoiseCaptureProcessor(
            _sharedState);
    _processor->Initialize(_sampleRateHz, _numChannels);
  }

  const int frameCount = static_cast<int>(frames);
  const int channelCount = static_cast<int>(channels);
  const int bufferSize = frameCount * channelCount;
  _captureBuffer.resize(static_cast<size_t>(bufferSize));

  for (int channel = 0; channel < channelCount; ++channel) {
    float* channelBuffer = [audioBuffer rawBufferForChannel:channel];
    if (channelBuffer == nullptr) {
      return;
    }
    std::copy(channelBuffer,
              channelBuffer + frameCount,
              _captureBuffer.data() +
                  (static_cast<size_t>(channel) * frames));
  }

  const int numBands = audioBuffer.bands > 0
                           ? static_cast<int>(audioBuffer.bands)
                           : (_sampleRateHz >= 48000 ? 3 : 1);
  _processor->Process(
      numBands, frameCount, bufferSize, _captureBuffer.data());

  for (int channel = 0; channel < channelCount; ++channel) {
    float* channelBuffer = [audioBuffer rawBufferForChannel:channel];
    if (channelBuffer == nullptr) {
      return;
    }
    std::copy(_captureBuffer.data() +
                  (static_cast<size_t>(channel) * frames),
              _captureBuffer.data() +
                  (static_cast<size_t>(channel + 1) * frames),
              channelBuffer);
  }
}

- (void)audioProcessingRelease {
  std::lock_guard<std::mutex> lock(_mutex);
  if (_processor != nullptr) {
    _processor->Release();
    _processor = nullptr;
  }
}

@end

namespace {

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
    (void)deepfilternet_transient_suppression_enabled;
    (void)deepfilternet_hush_suppression_enabled;
    std::lock_guard<std::mutex> lock(mutex_);
    vad_threshold_ = ClampDouble(vad_threshold, 0.50, 0.999, 0.90);
    speech_grace_frames_ = (std::clamp)(speech_grace_frames, 0, 60);
    closed_gain_ = ClampDouble(closed_gain, 0.0, 1.0, 0.03);
    transient_sensitivity_ =
        ClampDouble(transient_sensitivity, 0.0, 1.0, 0.0);
    fast_close_enabled_ = fast_close_enabled;
    ApplyTuningLocked();
    return true;
  }

  bool SetPipelineMode(int mode) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (mode < intergalactic_noise_suppression::kRnnoisePipelineModeOff ||
        mode >
            intergalactic_noise_suppression::
                kRnnoisePipelineModePrototypeSuppressionV2) {
      mode =
          intergalactic_noise_suppression::kRnnoisePipelineModeCleanRnnoise;
    }
    shared_state_->pipeline_mode.store(mode);
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
    (void)include_wasapi_sidecar;
    (void)wasapi_device_id;
    std::lock_guard<std::mutex> lock(mutex_);
    if (directory == nullptr) {
      return false;
    }
    return shared_state_->diagnostic_capture->Start(
        directory, duration_ms, stage_mask);
  }

  bool StopDiagnosticCapture() {
    std::lock_guard<std::mutex> lock(mutex_);
    return shared_state_->diagnostic_capture->Stop();
  }

  bool SetEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(mutex_);
    desired_enabled_ = enabled;
    shared_state_->enabled_requested.store(enabled);
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
        enabled && frames_processed > 0 && !format_mismatch &&
        !suspicious_output;

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
    json << "\"sampleRateHz\":" << shared_state_->sample_rate_hz.load()
         << ",";
    json << "\"numChannels\":" << shared_state_->num_channels.load() << ",";
    json << "\"expectedFramesPer10ms\":"
         << shared_state_->expected_frames_per_10ms.load() << ",";
    json << "\"lastNumBands\":" << shared_state_->last_num_bands.load()
         << ",";
    json << "\"lastNumFrames\":" << shared_state_->last_num_frames.load()
         << ",";
    json << "\"lastBufferSize\":"
         << shared_state_->last_buffer_size.load() << ",";
    json << "\"framesProcessed\":" << frames_processed << ",";
    json << "\"bypassFrames\":" << shared_state_->bypass_frames.load()
         << ",";
    json << "\"gatedFrames\":" << shared_state_->gated_frames.load() << ",";
    json << "\"resamplerUses\":" << shared_state_->resampler_uses.load()
         << ",";
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
    json << "\"vadLowFrames\":" << shared_state_->vad_low_frames.load()
         << ",";
    json << "\"vadMidFrames\":" << shared_state_->vad_mid_frames.load()
         << ",";
    json << "\"vadHighFrames\":" << shared_state_->vad_high_frames.load()
         << ",";
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
    json << "\"lastInputRms\":" << shared_state_->last_input_rms.load()
         << ",";
    json << "\"lastOutputRms\":" << shared_state_->last_output_rms.load()
         << ",";
    json << "\"lastOutputRatio\":"
         << shared_state_->last_output_ratio.load() << ",";
    json << "\"lastInputPeak\":"
         << shared_state_->last_input_peak.load() << ",";
    json << "\"lastOutputPeak\":"
         << shared_state_->last_output_peak.load() << ",";
    json << "\"lastInputMin\":" << shared_state_->last_input_min.load()
         << ",";
    json << "\"lastInputMax\":" << shared_state_->last_input_max.load()
         << ",";
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
            "rnnoise_output_48k.wav,final_to_webrtc.wav"
         << "\",";
    json << "\"wasapiSidecarActive\":false,";
    json << "\"wasapiSidecarFrames\":0,";
    json << "\"wasapiSidecarDroppedPackets\":0,";
    json << "\"wasapiSidecarWrittenFiles\":0,";
    json << "\"wasapiSidecarSampleRateHz\":0,";
    json << "\"wasapiSidecarChannels\":0,";
    json << "\"wasapiSidecarDeviceResolution\":\"not_supported\",";
    json << "\"wasapiSidecarLastError\":\"\",";
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

  void ApplyTuningLocked() {
    shared_state_->reference_vad_threshold.store(vad_threshold_);
    shared_state_->reference_speech_grace_frames.store(speech_grace_frames_);
    shared_state_->noise_gate_closed_gain.store(closed_gain_);
    shared_state_->transient_sensitivity.store(transient_sensitivity_);
    shared_state_->fast_close_enabled.store(fast_close_enabled_);
  }

  bool EnsureHookLocked() {
    if (hook_registered_) {
      return true;
    }

    AudioManager* audioManager = [AudioManager sharedInstance];
    if (audioManager == nil) {
      hook_registered_ = false;
      reason_ = "flutter_webrtc_audio_manager_unavailable";
      return false;
    }

    AudioProcessingAdapter* adapter =
        audioManager.capturePostProcessingAdapter;
    if (adapter == nil) {
      hook_registered_ = false;
      reason_ = "audio_processing_unavailable";
      return false;
    }

    if (processor_delegate_ == nil) {
      processor_delegate_ =
          [[IntergalacticNoiseSuppressionAudioProcessor alloc]
              initWithSharedState:shared_state_];
    }

    ApplyTuningLocked();
    [adapter addProcessing:processor_delegate_];
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
          std::make_shared<
              intergalactic_noise_suppression::ProcessorSharedState>();
  __strong IntergalacticNoiseSuppressionAudioProcessor* processor_delegate_ =
      nil;
  std::mutex mutex_;
  bool initialized_ = false;
  bool hook_registered_ = false;
  bool desired_enabled_ = false;
  double vad_threshold_ = 0.90;
  int speech_grace_frames_ = 20;
  double closed_gain_ = 0.03;
  double transient_sensitivity_ = 0.0;
  bool fast_close_enabled_ = false;
  std::string reason_ = "not_initialized";
};

}  // namespace

@implementation IntergalacticNoiseSuppressionPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  (void)registrar;
}

@end

extern "C" {

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_initialize() {
  return NoiseSuppressionManager::Instance().Initialize() ? 1 : 0;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_configure(double vad_threshold,
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

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_set_pipeline_mode(int mode) {
  return NoiseSuppressionManager::Instance().SetPipelineMode(mode) ? 1 : 0;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_start_diagnostic_capture(
    const char* directory,
    int duration_ms,
    int stage_mask) {
  return NoiseSuppressionManager::Instance().StartDiagnosticCapture(
             directory, duration_ms, stage_mask)
         ? 1
         : 0;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_start_tap_order_capture(
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

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_stop_diagnostic_capture() {
  return NoiseSuppressionManager::Instance().StopDiagnosticCapture() ? 1 : 0;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_set_enabled(int enabled) {
  return NoiseSuppressionManager::Instance().SetEnabled(enabled != 0) ? 1 : 0;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_shutdown() {
  NoiseSuppressionManager::Instance().Shutdown();
  return 1;
}

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT const char*
intergalactic_noise_suppression_get_status_json() {
  thread_local std::string status_json;
  status_json = NoiseSuppressionManager::Instance().StatusJson();
  return status_json.c_str();
}

}  // extern "C"
