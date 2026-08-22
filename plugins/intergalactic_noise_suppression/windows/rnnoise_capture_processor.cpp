#include "rnnoise_capture_processor.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace intergalactic_noise_suppression {

namespace {

constexpr float kPcmScale = 32768.0f;
constexpr int kRnnoiseSampleRateHz = 48000;
constexpr int kRnnoiseFrameSize = 480;
constexpr double kPi = 3.14159265358979323846;
constexpr int kResamplerFilterRadius = 12;
constexpr float kNormalizedPeakCeiling = 1.25f;
constexpr double kSuspiciousSpeechInputRmsFloor = 0.008;
constexpr float kSuspiciousSpeechVadThreshold = 0.78f;
constexpr double kSuspiciousOutputRmsCeiling = 0.001;
constexpr double kSuspiciousSpeechOutputRmsRatioCeiling = 0.08;
constexpr int kSuspiciousOutputBypassThreshold = 3;
constexpr int kSuspiciousOutputRecoveryFrames = 25;
constexpr double kSuspiciousTransientInputRmsCeiling = 0.045;
constexpr double kSuspiciousTransientOutputRmsFloor = 0.018;
constexpr double kSuspiciousTransientOutputRatioFloor = 2.0;
constexpr double kSuspiciousTransientOutputPeakFloor = 0.09;
constexpr double kSuspiciousTransientPeakGrowthFloor = 0.045;
constexpr double kSuspiciousTransientDeltaGrowthFloor = 0.012;
constexpr int kSuspiciousTransientResetThreshold = 2;
constexpr int kRnnoiseOutputInputDelayFrames = 2;
constexpr double kDelayedInputResidualRmsCeiling = 0.012;
constexpr double kDelayedInputResidualOutputRmsFloor = 0.010;
constexpr double kDelayedInputResidualOutputPeakFloor = 0.030;
constexpr double kDelayedInputResidualOutputRatioFloor = 5.0;
constexpr double kDelayedInputResidualPeakGrowthFloor = 0.024;
constexpr double kDelayedInputResidualDeltaGrowthFloor = 0.006;
constexpr double kCurrentInputResidualRmsCeiling = 0.014;
constexpr double kCurrentInputResidualPeakCeiling = 0.040;
constexpr double kCurrentInputResidualDeltaCeiling = 0.018;
constexpr float kReferenceVadThreshold = 0.90f;
constexpr float kNoiseGateImpulseVadCeiling = 0.96f;
constexpr float kNoiseGateMaxImpulseVadCeiling = 0.995f;
constexpr double kNoiseGateTransientInputRmsFloor = 0.006;
constexpr double kNoiseGateMinTransientInputRmsFloor = 0.0035;
constexpr double kNoiseGateImpulsePeakFloor = 0.012;
constexpr double kNoiseGateMinImpulsePeakFloor = 0.007;
constexpr double kNoiseGateImpulseCrestFactorFloor = 5.0;
constexpr double kNoiseGateMinImpulseCrestFactorFloor = 3.5;
constexpr double kNoiseGateTypingInputRmsFloor = 0.0015;
constexpr double kNoiseGateTypingInputRmsCeiling = 0.018;
constexpr double kNoiseGateMaxTypingInputRmsCeiling = 0.030;
constexpr double kNoiseGateTypingPeakFloor = 0.060;
constexpr double kNoiseGateMinTypingPeakFloor = 0.030;
constexpr double kNoiseGateTypingDeltaFloor = 0.035;
constexpr double kNoiseGateMinTypingDeltaFloor = 0.012;
constexpr double kNoiseGateTypingCrestFactorFloor = 5.0;
constexpr double kNoiseGateMinTypingCrestFactorFloor = 3.0;
constexpr double kNoiseGateSpeechProtectInputRmsFloor = 0.003;
constexpr float kNoiseGateSpeechProtectVadThreshold = 0.78f;
constexpr float kNoiseGateSpeechStrongVadProtectThreshold = 0.90f;
constexpr float kNoiseGateHarshTransientVadCeiling = 0.88f;
constexpr double kNoiseGateSpeechTransientRmsCeiling = 0.006;
constexpr double kNoiseGateDeskTapInputRmsCeiling = 0.040;
constexpr double kNoiseGateDeskTapPeakFloor = 0.018;
constexpr double kNoiseGateDeskTapDeltaFloor = 0.008;
constexpr double kNoiseGateDeskTapCrestFactorFloor = 2.4;
constexpr double kNoiseGateHarshTransientPeakFloor = 0.74;
constexpr double kNoiseGateHarshTransientMinPeakFloor = 0.55;
constexpr double kNoiseGateHarshTransientDeltaFloor = 0.18;
constexpr double kNoiseGateHarshTransientMinDeltaFloor = 0.10;
constexpr double kNoiseGateHarshTransientCrestFactorFloor = 4.2;
constexpr double kNoiseGateHarshTransientMinCrestFactorFloor = 2.8;
constexpr int kNoiseGateMinTransientHoldFrames = 3;
constexpr int kNoiseGateMaxTransientHoldFrames = 10;
constexpr float kNoiseGateClosedGain = 0.03f;
constexpr int kMaxDiagnosticCaptureMs = 30000;
constexpr int kDefaultDiagnosticCaptureMs = 10000;
constexpr int kMaxResamplerQueueSamples = 48000;
constexpr double kCallbackBudgetWarningRatio = 0.80;
constexpr int kWetMixRampSamples = 240;
// A capture callback normally fires every ~10 ms. Treat a gap beyond this as a
// capture interruption (mute/unmute, participant churn, renegotiation, or CPU
// starvation) rather than ordinary scheduling jitter. 40 ms tolerates several
// missed frames without false positives.
constexpr double kCaptureGapMinIntervalMs = 40.0;
// After a capture gap, crossfade DeepFilterNet output back in from dry over a
// few frames so stale-lookahead "layering" and the recovery pop are masked.
constexpr float kDeepFilterNetGapRecoveryStartWetMix = 0.0f;
constexpr float kDeepFilterNetGapRecoveryStepPerFrame = 0.2f;
constexpr float kDeepFilterNetGapRecoveryFullWetMix = 0.999f;
constexpr float kOutputLimiterPeakCeiling = 0.92f;
constexpr float kOutputLimiterMaxDelta = 0.35f;
constexpr float kOutputLimiterAdaptiveDeltaFloor = 0.04f;
constexpr float kOutputLimiterInputDeltaMultiplier = 1.20f;
constexpr float kNonSpeechBurstVadCeiling = 0.50f;
constexpr double kNonSpeechBurstPeakFloor = 0.70;
constexpr double kNonSpeechBurstDeltaFloor = 0.18;
constexpr float kNonSpeechBurstSoftCeiling = 0.18f;
constexpr float kNonSpeechBurstMaxDelta = 0.12f;
constexpr int kPostSpeechResidualGuardFrames = 24;
constexpr int kNoiseGateFastCloseRampMs = 4;
constexpr double kPostSpeechHotInputRmsFloor = 0.045;
constexpr double kPostSpeechQuietInputRmsCeiling = 0.010;
constexpr double kPostSpeechResidualRmsFloor = 0.010;
constexpr double kPostSpeechResidualPeakFloor = 0.030;
constexpr double kPostSpeechResidualRatioFloor = 3.5;
constexpr float kPostSpeechResidualSoftCeiling = 0.018f;
constexpr float kPostSpeechResidualMaxDelta = 0.018f;
constexpr float kPrototypeSpeechProtectVadThreshold = 0.82f;
constexpr float kPrototypeStrongSpeechProtectVadThreshold = 0.94f;
constexpr float kPrototypeNoiseVadCeiling = 0.55f;
constexpr double kPrototypeSpeechProtectInputRmsFloor = 0.0035;
constexpr double kPrototypeTransientInputRmsCeiling = 0.045;
constexpr double kPrototypeTransientPeakFloor = 0.030;
constexpr double kPrototypeTransientDeltaFloor = 0.010;
constexpr double kPrototypeTransientCrestFloor = 3.2;
constexpr double kPrototypeTransientOutputPeakFloor = 0.020;
constexpr double kPrototypeTransientOutputDeltaFloor = 0.008;
constexpr int kPrototypeTransientHoldFrames = 3;
constexpr float kPrototypeTransientGain = 0.16f;
constexpr float kPrototypeTransientSoftCeiling = 0.035f;
constexpr float kPrototypeTransientMaxDelta = 0.030f;
constexpr double kPrototypeStationaryInputRmsFloor = 0.0007;
constexpr double kPrototypeStationaryInputRmsCeiling = 0.030;
constexpr double kPrototypeStationaryInputPeakCeiling = 0.16;
constexpr double kPrototypeStationaryInputDeltaCeiling = 0.035;
constexpr double kPrototypeStationaryOutputRmsFloor = 0.0012;
constexpr double kPrototypeStationaryOutputPeakCeiling = 0.22;
constexpr double kPrototypeStationaryOutputDeltaCeiling = 0.065;
constexpr int kPrototypeStationaryNoiseFloorWarmupFrames = 3;
constexpr double kPrototypeStationaryNoiseFloorAlpha = 0.96;
constexpr double kPrototypeStationaryNoiseFloorRatioFloor = 0.55;
constexpr float kPrototypeStationaryGain = 0.46f;
constexpr float kPrototypeV2SpeechProtectVadThreshold = 0.72f;
constexpr float kPrototypeV2StrongSpeechProtectVadThreshold = 0.90f;
constexpr float kPrototypeV2RecentSpeechProtectVadThreshold = 0.70f;
constexpr float kPrototypeV2NoiseVadCeiling = 0.82f;
constexpr float kPrototypeV2RecentNoiseVadCeiling = 0.74f;
constexpr double kPrototypeV2SpeechProtectInputRmsFloor = 0.0025;
constexpr double kPrototypeV2SpeechShapeInputRmsFloor = 0.006;
constexpr double kPrototypeV2SpeechShapePeakFloor = 0.015;
constexpr double kPrototypeV2SpeechShapeDeltaFloor = 0.0035;
constexpr double kPrototypeV2SpeechShapeCrestCeiling = 7.5;
constexpr int kPrototypeV2SpeechHangoverFrames = 12;
constexpr int kPrototypeV2StationaryHistoryFrames = 4;
constexpr double kPrototypeV2StationaryRmsSpanFloor = 0.004;
constexpr double kPrototypeV2StationaryRmsSpanRatio = 0.35;
constexpr double kPrototypeV2StationaryPeakSpanFloor = 0.035;
constexpr double kPrototypeV2StationaryPeakSpanRatio = 0.45;
constexpr double kPrototypeV2StationaryDeltaSpanFloor = 0.010;
constexpr double kPrototypeV2StationaryDeltaSpanRatio = 0.55;
constexpr double kPrototypeV2TransientInputRmsCeiling = 0.038;
constexpr double kPrototypeV2TransientPeakFloor = 0.028;
constexpr double kPrototypeV2TransientDeltaFloor = 0.009;
constexpr double kPrototypeV2TransientCrestFloor = 3.8;
constexpr double kPrototypeV2TransientOutputPeakFloor = 0.014;
constexpr double kPrototypeV2TransientOutputDeltaFloor = 0.005;
constexpr int kPrototypeV2TransientHoldFrames = 1;
constexpr float kPrototypeV2TransientGain = 0.28f;
constexpr float kPrototypeV2TransientSoftCeiling = 0.045f;
constexpr float kPrototypeV2TransientMaxDelta = 0.032f;
constexpr double kPrototypeV2StationaryInputRmsFloor = 0.0006;
constexpr double kPrototypeV2StationaryInputRmsCeiling = 0.030;
constexpr double kPrototypeV2StationaryInputPeakCeiling = 0.15;
constexpr double kPrototypeV2StationaryInputDeltaCeiling = 0.030;
constexpr double kPrototypeV2StationaryOutputRmsFloor = 0.0010;
constexpr double kPrototypeV2StationaryOutputPeakCeiling = 0.20;
constexpr double kPrototypeV2StationaryOutputDeltaCeiling = 0.060;
constexpr int kPrototypeV2StationaryNoiseFloorWarmupFrames = 5;
constexpr double kPrototypeV2StationaryNoiseFloorAlpha = 0.97;
constexpr double kPrototypeV2StationaryNoiseFloorRatioFloor = 0.45;
constexpr float kPrototypeV2StationaryGain = 0.58f;
constexpr float kPrototypeV2ReleaseStep = 0.30f;
constexpr double kDryFallbackInputPeakFloor = 0.985;
constexpr double kDryFallbackInputDeltaFloor = 0.35;
constexpr double kDryFallbackOutputRmsFloor = 0.05;
constexpr double kDryFallbackOutputRatioFloor = 3.0;
constexpr float kDryFallbackLowVadCeiling = 0.70f;
constexpr double kDryFallbackLowVadPeakFloor = 0.25;
constexpr double kDryFallbackLowVadDeltaFloor = 0.08;
constexpr double kDeepFilterNetSpeechProtectInputRmsFloor = 0.035;
constexpr double kDeepFilterNetSpeechProtectInputRmsCeiling = 0.14;
constexpr double kDeepFilterNetSpeechProtectInputPeakFloor = 0.10;
constexpr double kDeepFilterNetSpeechProtectInputDeltaCeiling = 0.20;
constexpr double kDeepFilterNetSpeechProtectCrestCeiling = 8.5;
constexpr double kDeepFilterNetSpeechProtectLocalSnrFloor = 0.0;
constexpr double kDeepFilterNetSpeechProtectRatioCeiling = 0.72;
constexpr double kDeepFilterNetSpeechProtectStrongRatioCeiling = 0.42;
constexpr float kDeepFilterNetSpeechProtectMinWetMix = 0.58f;
constexpr float kDeepFilterNetSpeechProtectMaxWetMix = 0.86f;
constexpr double kDeepFilterNetTransientInputRmsFloor = 0.0008;
constexpr double kDeepFilterNetTransientInputRmsCeiling = 0.075;
constexpr double kDeepFilterNetTransientInputPeakFloor = 0.024;
constexpr double kDeepFilterNetTransientInputDeltaFloor = 0.008;
constexpr double kDeepFilterNetTransientInputCrestFloor = 4.6;
constexpr double kDeepFilterNetTransientOutputPeakFloor = 0.012;
constexpr double kDeepFilterNetTransientOutputDeltaFloor = 0.004;
constexpr double kDeepFilterNetTransientSpeechRmsFloor = 0.030;
constexpr double kDeepFilterNetTransientSpeechPeakFloor = 0.095;
constexpr double kDeepFilterNetTransientSpeechDeltaCeiling = 0.20;
constexpr double kDeepFilterNetTransientSpeechCrestCeiling = 8.5;
constexpr int kDeepFilterNetTransientWindowRadiusSamples = 48;
constexpr int kDeepFilterNetTransientMinCenterSpacingSamples = 28;
constexpr int kDeepFilterNetTransientMaxCentersPerFrame = 3;
constexpr double kDeepFilterNetTransientDeltaRatioFloor = 3.5;
constexpr double kDeepFilterNetTransientSpeechDeltaRatioFloor = 3.2;
constexpr double kDeepFilterNetTransientSpeechMixedRmsFloor = 0.010;
constexpr double kDeepFilterNetTransientSpeechProtectedPeakFloor = 0.040;
constexpr double kDeepFilterNetTransientSpeechProtectedDeltaFloor = 0.034;
constexpr double kDeepFilterNetTransientSpeechProtectedInputDeltaFloor = 0.030;
constexpr double kDeepFilterNetTransientSpeechProtectedCrestFloor = 2.6;
constexpr float kDeepFilterNetTransientMinGain = 0.36f;
constexpr float kDeepFilterNetTransientSpeechMinGain = 0.66f;
constexpr float kDeepFilterNetTransientSoftCeiling = 0.055f;
constexpr double kDeepFilterNetHushRecoveryInputRmsFloor = 0.006;
constexpr double kDeepFilterNetHushRecoveryOutputRmsFloor = 0.0015;
constexpr double kDeepFilterNetHushRecoveryMinDropRatio = 0.92;
constexpr float kDeepFilterNetHushRecoveryMaxGain = 2.0f;
constexpr float kDeepFilterNetHushRecoveryPeakCeiling = 0.82f;

float Clamp01(float value) {
  if (!std::isfinite(value)) {
    return 0.0f;
  }

  return (std::clamp)(value, 0.0f, 1.0f);
}

float LerpFloat(float start, float end, float progress) {
  return start + ((end - start) * progress);
}

double LerpDouble(double start, double end, double progress) {
  return start + ((end - start) * progress);
}

}  // namespace

bool DiagnosticCapture::Start(const std::string& directory,
                              int duration_ms,
                              int stage_mask) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (directory.empty()) {
    last_error_ = "directory_empty";
    return false;
  }

  const int clamped_duration_ms = (std::clamp)(
      duration_ms <= 0 ? kDefaultDiagnosticCaptureMs : duration_ms,
      1,
      kMaxDiagnosticCaptureMs);
  max_samples_48k_ =
      static_cast<int>((static_cast<int64_t>(kRnnoiseSampleRateHz) *
                        clamped_duration_ms) /
                       1000);
  stage_mask_ = stage_mask == 0 ? kRnnoiseDiagnosticStageAll : stage_mask;
  directory_ = directory;
  last_error_.clear();
  captured_frames_.store(0);
  dropped_frames_.store(0);
  written_files_.store(0);

  auto prepare_stage = [&](StageBuffer* stage, int bit) {
    stage->enabled = (stage_mask_ & bit) != 0;
    stage->sample_rate_hz = 0;
    stage->write_index = 0;
    stage->max_write_samples = 0;
    stage->samples.clear();
    if (stage->enabled) {
      stage->samples.assign(max_samples_48k_, 0.0f);
      stage->max_write_samples = max_samples_48k_;
    }
  };

  try {
    std::filesystem::create_directories(directory_);
    prepare_stage(&raw_input_, kRnnoiseDiagnosticStageRawInput);
    prepare_stage(&rnnoise_input_, kRnnoiseDiagnosticStageRnnoiseInput);
    prepare_stage(&rnnoise_output_, kRnnoiseDiagnosticStageRnnoiseOutput);
    prepare_stage(&deepfilternet_output_,
                  kRnnoiseDiagnosticStageDeepFilterNetOutput);
    prepare_stage(&speech_protect_output_,
                  kRnnoiseDiagnosticStageSpeechProtectOutput);
    prepare_stage(&transient_guard_output_,
                  kRnnoiseDiagnosticStageTransientGuardOutput);
    prepare_stage(&hush_input_16k_, kRnnoiseDiagnosticStageHushInput16k);
    prepare_stage(&hush_output_16k_, kRnnoiseDiagnosticStageHushOutput16k);
    prepare_stage(&hush_output_, kRnnoiseDiagnosticStageHushOutput);
    prepare_stage(&final_output_, kRnnoiseDiagnosticStageFinalOutput);
  } catch (const std::exception& error) {
    last_error_ = error.what();
    active_.store(false);
    return false;
  }

  active_.store(true);
  return true;
}

bool DiagnosticCapture::Stop() {
  std::lock_guard<std::mutex> lock(mutex_);
  active_.store(false);
  written_files_.store(0);
  last_error_.clear();

  try {
    if (raw_input_.enabled) {
      WriteStageLocked(raw_input_, "webrtc_hook_input.wav");
    }
    if (rnnoise_input_.enabled) {
      WriteStageLocked(rnnoise_input_, "rnnoise_input_48k.wav");
    }
    if (rnnoise_output_.enabled) {
      WriteStageLocked(rnnoise_output_, "rnnoise_output_48k.wav");
    }
    if (deepfilternet_output_.enabled) {
      WriteStageLocked(deepfilternet_output_, "deepfilternet_output.wav");
    }
    if (speech_protect_output_.enabled) {
      WriteStageLocked(speech_protect_output_, "speech_protect_output.wav");
    }
    if (transient_guard_output_.enabled) {
      WriteStageLocked(transient_guard_output_, "transient_guard_output.wav");
    }
    if (hush_input_16k_.enabled) {
      WriteStageLocked(hush_input_16k_, "hush_input_16k.wav");
    }
    if (hush_output_16k_.enabled) {
      WriteStageLocked(hush_output_16k_, "hush_output_16k.wav");
    }
    if (hush_output_.enabled) {
      WriteStageLocked(hush_output_, "hush_output.wav");
    }
    if (final_output_.enabled) {
      WriteStageLocked(final_output_, "final_to_webrtc.wav");
    }
  } catch (const std::exception& error) {
    last_error_ = error.what();
    return false;
  }

  return last_error_.empty();
}

bool DiagnosticCapture::RecordRawInput(const std::vector<float>& samples,
                                       int sample_rate_hz) {
  return RecordStage(&raw_input_, samples, sample_rate_hz);
}

bool DiagnosticCapture::RecordRnnoiseInput(const std::vector<float>& samples) {
  return RecordStage(&rnnoise_input_, samples, kRnnoiseSampleRateHz);
}

bool DiagnosticCapture::RecordRnnoiseOutput(const std::vector<float>& samples) {
  return RecordStage(&rnnoise_output_, samples, kRnnoiseSampleRateHz);
}

bool DiagnosticCapture::RecordFinalOutput(const std::vector<float>& samples,
                                          int sample_rate_hz) {
  return RecordStage(&final_output_, samples, sample_rate_hz);
}

bool DiagnosticCapture::RecordProcessedCallback(
    const std::vector<float>& raw_input,
    int raw_sample_rate_hz,
    const std::vector<float>& rnnoise_input,
    const std::vector<float>& rnnoise_output,
    const std::vector<float>& final_output,
    int final_sample_rate_hz) {
  if (!active_.load()) {
    return false;
  }

  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) {
    dropped_frames_.fetch_add(1);
    return false;
  }

  if (!active_.load()) {
    return false;
  }

  bool wrote_stage = false;
  wrote_stage |= RecordStageLocked(&raw_input_, raw_input, raw_sample_rate_hz);
  wrote_stage |=
      RecordStageLocked(&rnnoise_input_, rnnoise_input, kRnnoiseSampleRateHz);
  wrote_stage |=
      RecordStageLocked(&rnnoise_output_, rnnoise_output, kRnnoiseSampleRateHz);
  wrote_stage |=
      RecordStageLocked(&final_output_, final_output, final_sample_rate_hz);

  if (wrote_stage) {
    captured_frames_.fetch_add(1);
  }
  if (AllEnabledStagesFullLocked()) {
    active_.store(false);
  }
  return wrote_stage;
}

bool DiagnosticCapture::RecordEnhancedProcessedCallback(
    const std::vector<float>& raw_input,
    int raw_sample_rate_hz,
    const std::vector<float>& deepfilternet_output,
    const std::vector<float>& speech_protect_output,
    const std::vector<float>& transient_guard_output,
    const std::vector<float>& hush_input_16k,
    const std::vector<float>& hush_output_16k,
    const std::vector<float>& hush_output,
    const std::vector<float>& final_output,
    int final_sample_rate_hz) {
  if (!active_.load()) {
    return false;
  }

  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) {
    dropped_frames_.fetch_add(1);
    return false;
  }

  if (!active_.load()) {
    return false;
  }

  bool wrote_stage = false;
  wrote_stage |= RecordStageLocked(&raw_input_, raw_input, raw_sample_rate_hz);
  wrote_stage |= RecordStageLocked(
      &deepfilternet_output_, deepfilternet_output, final_sample_rate_hz);
  wrote_stage |= RecordStageLocked(
      &speech_protect_output_, speech_protect_output, final_sample_rate_hz);
  wrote_stage |= RecordStageLocked(
      &transient_guard_output_, transient_guard_output, final_sample_rate_hz);
  wrote_stage |=
      RecordStageLocked(&hush_input_16k_, hush_input_16k, 16000);
  wrote_stage |=
      RecordStageLocked(&hush_output_16k_, hush_output_16k, 16000);
  wrote_stage |=
      RecordStageLocked(&hush_output_, hush_output, final_sample_rate_hz);
  wrote_stage |=
      RecordStageLocked(&final_output_, final_output, final_sample_rate_hz);

  if (wrote_stage) {
    captured_frames_.fetch_add(1);
  }
  if (AllEnabledStagesFullLocked()) {
    active_.store(false);
  }
  return wrote_stage;
}

bool DiagnosticCapture::RecordStage(StageBuffer* stage,
                                    const std::vector<float>& samples,
                                    int sample_rate_hz) {
  if (!active_.load() || stage == nullptr || !stage->enabled ||
      samples.empty()) {
    return false;
  }

  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) {
    dropped_frames_.fetch_add(1);
    return false;
  }

  if (!active_.load() || !stage->enabled) {
    return false;
  }

  const bool wrote_stage = RecordStageLocked(stage, samples, sample_rate_hz);
  if (wrote_stage) {
    captured_frames_.fetch_add(1);
  }
  if (AllEnabledStagesFullLocked()) {
    active_.store(false);
  }
  return wrote_stage;
}

bool DiagnosticCapture::RecordStageLocked(StageBuffer* stage,
                                          const std::vector<float>& samples,
                                          int sample_rate_hz) {
  if (stage == nullptr || !stage->enabled || samples.empty()) {
    return false;
  }

  if (stage->sample_rate_hz == 0) {
    stage->sample_rate_hz = sample_rate_hz;
    stage->max_write_samples = (std::clamp)(
        static_cast<int>((static_cast<int64_t>(sample_rate_hz) *
                          max_samples_48k_) /
                         kRnnoiseSampleRateHz),
        0,
        static_cast<int>(stage->samples.size()));
  }

  if (stage->sample_rate_hz != sample_rate_hz) {
    dropped_frames_.fetch_add(1);
    return false;
  }

  if (stage->write_index >= stage->max_write_samples) {
    return false;
  }

  const int available = stage->max_write_samples - stage->write_index;
  const int samples_to_copy =
      (std::min)(available, static_cast<int>(samples.size()));
  std::copy_n(samples.begin(), samples_to_copy,
              stage->samples.begin() + stage->write_index);
  stage->write_index += samples_to_copy;
  if (samples_to_copy < static_cast<int>(samples.size())) {
    dropped_frames_.fetch_add(1);
  }

  return samples_to_copy > 0;
}

bool DiagnosticCapture::AllEnabledStagesFullLocked() const {
  const auto stage_full = [](const StageBuffer& stage) {
    return !stage.enabled ||
           stage.write_index >= stage.max_write_samples;
  };
  return stage_full(raw_input_) &&
         stage_full(rnnoise_input_) &&
         stage_full(rnnoise_output_) &&
         stage_full(deepfilternet_output_) &&
         stage_full(speech_protect_output_) &&
         stage_full(transient_guard_output_) &&
         stage_full(hush_input_16k_) &&
         stage_full(hush_output_16k_) &&
         stage_full(hush_output_) &&
         stage_full(final_output_);
}

bool DiagnosticCapture::WriteStageLocked(const StageBuffer& stage,
                                         const std::string& file_name) {
  if (!stage.enabled || stage.write_index <= 0 || stage.sample_rate_hz <= 0) {
    return true;
  }

  const std::filesystem::path path =
      std::filesystem::path(directory_) / file_name;
  if (!WriteWavFile(path.string(),
                    stage.samples,
                    stage.write_index,
                    stage.sample_rate_hz)) {
    last_error_ = "wav_write_failed";
    return false;
  }

  written_files_.fetch_add(1);
  return true;
}

bool DiagnosticCapture::WriteWavFile(const std::string& path,
                                     const std::vector<float>& samples,
                                     int sample_count,
                                     int sample_rate_hz) {
  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file.is_open() || sample_count < 0 || sample_rate_hz <= 0) {
    return false;
  }

  const int bytes_per_sample = 2;
  const int channel_count = 1;
  const int byte_rate = sample_rate_hz * channel_count * bytes_per_sample;
  const int block_align = channel_count * bytes_per_sample;
  const int data_bytes = sample_count * bytes_per_sample;
  const int riff_size = 36 + data_bytes;

  auto write_u16 = [&](std::uint16_t value) {
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
  };
  auto write_u32 = [&](std::uint32_t value) {
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
  };

  file.write("RIFF", 4);
  write_u32(static_cast<std::uint32_t>(riff_size));
  file.write("WAVE", 4);
  file.write("fmt ", 4);
  write_u32(16);
  write_u16(1);
  write_u16(static_cast<std::uint16_t>(channel_count));
  write_u32(static_cast<std::uint32_t>(sample_rate_hz));
  write_u32(static_cast<std::uint32_t>(byte_rate));
  write_u16(static_cast<std::uint16_t>(block_align));
  write_u16(16);
  file.write("data", 4);
  write_u32(static_cast<std::uint32_t>(data_bytes));

  for (int index = 0; index < sample_count; ++index) {
    const float normalized =
        (std::clamp)(samples[index], -1.0f, 1.0f);
    const auto pcm = static_cast<std::int16_t>(
        std::lrint(normalized * 32767.0f));
    file.write(reinterpret_cast<const char*>(&pcm), sizeof(pcm));
  }

  return file.good();
}

void StreamingLinearResampler::Configure(int input_rate_hz,
                                         int output_rate_hz) {
  if (input_rate_hz_ == input_rate_hz && output_rate_hz_ == output_rate_hz) {
    return;
  }

  input_rate_hz_ = input_rate_hz;
  output_rate_hz_ = output_rate_hz;
  source_step_ = output_rate_hz_ <= 0
      ? 1.0
      : static_cast<double>(input_rate_hz_) /
            static_cast<double>(output_rate_hz_);
  input_queue_.reserve(kMaxResamplerQueueSamples);
  Reset();
}

void StreamingLinearResampler::Reset() {
  source_position_ = 0.0;
  input_queue_.clear();
}

bool StreamingLinearResampler::Append(const std::vector<float>& samples) {
  if (samples.empty()) {
    return false;
  }

  bool overflowed = false;
  if (input_queue_.size() + samples.size() >
      static_cast<size_t>(kMaxResamplerQueueSamples)) {
    Reset();
    overflowed = true;
  }

  input_queue_.insert(input_queue_.end(), samples.begin(), samples.end());
  return overflowed;
}

int StreamingLinearResampler::Produce(int output_frames,
                                      std::vector<float>* output) {
  if (output == nullptr || output_frames <= 0 || input_rate_hz_ <= 0 ||
      output_rate_hz_ <= 0 || input_queue_.empty()) {
    return 0;
  }

  output->clear();
  output->reserve(output_frames);
  const double original_source_position = source_position_;

  while (static_cast<int>(output->size()) < output_frames) {
    const int base_index = static_cast<int>(std::floor(source_position_));
    const int next_index = base_index + 1;
    if (base_index < 0 ||
        next_index >= static_cast<int>(input_queue_.size())) {
      break;
    }

    const double fraction = source_position_ - base_index;
    const float start = input_queue_[base_index];
    const float end = input_queue_[next_index];
    output->push_back(static_cast<float>(
        static_cast<double>(start) +
        ((static_cast<double>(end) - static_cast<double>(start)) * fraction)));
    source_position_ += source_step_;
  }

  if (static_cast<int>(output->size()) != output_frames) {
    output->clear();
    source_position_ = original_source_position;
    return 0;
  }

  CompactQueue();
  return static_cast<int>(output->size());
}

int StreamingLinearResampler::queued_input_samples() const {
  return static_cast<int>(input_queue_.size());
}

void StreamingLinearResampler::CompactQueue() {
  const int removable =
      (std::max)(0, static_cast<int>(std::floor(source_position_)) - 1);
  if (removable <= 0) {
    return;
  }

  if (removable >= static_cast<int>(input_queue_.size())) {
    input_queue_.clear();
    source_position_ = 0.0;
    return;
  }

  input_queue_.erase(input_queue_.begin(), input_queue_.begin() + removable);
  source_position_ -= removable;
}

const char* RnnoiseGateReasonToString(int reason) {
  switch (reason) {
    case kRnnoiseGateReasonPass:
      return "pass";
    case kRnnoiseGateReasonVadGate:
      return "vad_gate";
    case kRnnoiseGateReasonImpulseGate:
      return "impulse_gate";
    case kRnnoiseGateReasonSpeechGrace:
      return "speech_grace";
    case kRnnoiseGateReasonBypass:
      return "bypass";
    case kRnnoiseGateReasonUnsupportedFormat:
      return "unsupported_format";
    default:
      return "unknown";
  }
}

const char* RnnoiseFormatMismatchReasonToString(int reason) {
  switch (reason) {
    case kRnnoiseFormatMismatchNone:
      return "none";
    case kRnnoiseFormatMismatchInvalidBuffer:
      return "invalid_buffer";
    case kRnnoiseFormatMismatchSplitBands:
      return "split_bands";
    case kRnnoiseFormatMismatchFrameCount:
      return "frame_count";
    case kRnnoiseFormatMismatchBufferSize:
      return "buffer_size";
    case kRnnoiseFormatMismatchUnsupportedRate:
      return "rnnoise_rate_unsupported";
    default:
      return "unknown";
  }
}

const char* RnnoiseResamplerModeToString(int mode) {
  switch (mode) {
    case kRnnoiseResamplerModeNone:
      return "none";
    case kRnnoiseResamplerModeWindowedSinc:
      return "windowed_sinc";
    case kRnnoiseResamplerModeStatefulLinear:
      return "stateful_linear";
    default:
      return "unknown";
  }
}

const char* RnnoisePipelineModeToString(int mode) {
  switch (mode) {
    case kRnnoisePipelineModeOff:
      return "off";
    case kRnnoisePipelineModeCleanRnnoise:
      return "clean_rnnoise";
    case kRnnoisePipelineModeTunedGate:
      return "tuned_gate";
    case kRnnoisePipelineModeIdentity:
      return "identity";
    case kRnnoisePipelineModePrototypeSuppression:
      return "prototype_suppression";
    case kRnnoisePipelineModePrototypeSuppressionV2:
      return "prototype_suppression_v2";
    case kRnnoisePipelineModeDeepFilterNet:
      return "deepfilternet";
    default:
      return "unknown";
  }
}

RnnoiseCaptureProcessor::RnnoiseCaptureProcessor(
    std::shared_ptr<ProcessorSharedState> shared_state)
    : shared_state_(std::move(shared_state)) {}

RnnoiseCaptureProcessor::~RnnoiseCaptureProcessor() {
  ResetRnnoiseState();
  if (deepfilternet_runtime_) {
    deepfilternet_runtime_->Reset();
  }
  if (hush_runtime_) {
    hush_runtime_->Reset();
  }
}

void PrewarmDeepFilterNetRuntimes(ProcessorSharedState* shared_state,
                                  bool include_deepfilternet,
                                  bool include_hush) {
  if (shared_state == nullptr) {
    return;
  }

  const auto load_runtime = [](DeepFilterNetRuntimeModel model,
                               std::atomic<double>* warmup_ms) {
    const auto started_at = std::chrono::steady_clock::now();
    auto runtime = std::make_unique<DeepFilterNetRuntime>(model);
    if (runtime->EnsureInitialized(runtime->expected_sample_rate_hz()) &&
        runtime->frame_length() > 0) {
      // The first inference call carries lazy graph-optimization cost well
      // beyond the 10 ms budget, so absorb it here with silent frames. This
      // is equivalent to a moment of silence before the stream and matches
      // the zero-filled dry-reference warm-up in the processor.
      const std::vector<float> silence(
          static_cast<size_t>(runtime->frame_length()), 0.0f);
      std::vector<float> discard;
      float local_snr = 0.0f;
      for (int i = 0; i < runtime->lookahead_frames() + 1; ++i) {
        if (!runtime->ProcessFrame(silence, &discard, &local_snr)) {
          break;
        }
      }
    }
    const double elapsed_ms =
        std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - started_at)
            .count();
    if (warmup_ms != nullptr && std::isfinite(elapsed_ms)) {
      warmup_ms->store(elapsed_ms);
    }
    return runtime;
  };

  // Skip slots that still hold an unclaimed runtime so a repeated trigger
  // (settings reapplication) does not reload models needlessly.
  const bool load_deepfilternet =
      include_deepfilternet &&
      !shared_state->prewarmed_deepfilternet_ready.load();
  const bool load_hush =
      include_hush && !shared_state->prewarmed_hush_ready.load();

  std::unique_ptr<DeepFilterNetRuntime> deepfilternet_runtime;
  std::unique_ptr<DeepFilterNetRuntime> hush_runtime;
  if (load_deepfilternet) {
    deepfilternet_runtime =
        load_runtime(DeepFilterNetRuntimeModel::kDeepFilterNet,
                     &shared_state->deepfilternet_warmup_ms);
  }
  if (load_hush) {
    hush_runtime = load_runtime(DeepFilterNetRuntimeModel::kHush,
                                &shared_state->deepfilternet_hush_warmup_ms);
  }

  std::lock_guard<std::mutex> lock(shared_state->prewarm_mutex);
  if (deepfilternet_runtime) {
    shared_state->prewarmed_deepfilternet = std::move(deepfilternet_runtime);
    shared_state->prewarmed_deepfilternet_ready.store(true);
  }
  if (hush_runtime) {
    shared_state->prewarmed_hush = std::move(hush_runtime);
    shared_state->prewarmed_hush_ready.store(true);
  }
}

void RnnoiseCaptureProcessor::Initialize(int sample_rate_hz, int num_channels) {
  std::lock_guard<std::mutex> lock(mutex_);

  sample_rate_hz_ = sample_rate_hz;
  num_channels_ = num_channels;
  logged_format_mismatch_ = false;
  suspicious_output_streak_ = 0;
  suspicious_output_recovery_frames_ = 0;
  suspicious_transient_streak_ = 0;
  speech_hangover_frames_ = 0;
  transient_gate_hold_frames_ = 0;
  post_speech_residual_guard_frames_ = 0;
  vad_average_sample_count_ = 0;
  recent_vad_average_ = 0.0f;
  gate_gain_ = 1.0f;
  prototype_gain_ = 1.0f;
  prototype_transient_hold_frames_ = 0;
  prototype_speech_hold_frames_ = 0;
  prototype_noise_floor_rms_ = 0.0;
  prototype_noise_floor_frames_ = 0;
  ResetRnnoiseState();
  ResetAudioPipeline();

  shared_state_->released.store(false);
  shared_state_->format_mismatch_detected.store(false);
  shared_state_->suspicious_output_detected.store(false);
  shared_state_->format_mismatch_reason.store(kRnnoiseFormatMismatchNone);
  shared_state_->sample_rate_hz.store(sample_rate_hz);
  shared_state_->num_channels.store(num_channels);
  shared_state_->expected_frames_per_10ms.store(sample_rate_hz / 100);
  shared_state_->speech_grace_remaining_frames.store(0);
  shared_state_->last_resampler_mode.store(kRnnoiseResamplerModeNone);
  shared_state_->last_resampler_input_frames.store(0);
  shared_state_->last_resampler_output_frames.store(0);
  shared_state_->last_resampler_source_rate_hz.store(sample_rate_hz);
  shared_state_->last_resampler_target_rate_hz.store(sample_rate_hz);
  shared_state_->last_gate_reason.store(kRnnoiseGateReasonPass);
  shared_state_->last_gate_gain.store(1.0);
  shared_state_->recent_vad_average.store(0.0);
  shared_state_->last_vad_probability.store(0.0);
  shared_state_->last_input_rms.store(0.0);
  shared_state_->last_output_rms.store(0.0);
  shared_state_->last_output_ratio.store(1.0);
  shared_state_->last_input_peak.store(0.0);
  shared_state_->last_output_peak.store(0.0);
  shared_state_->last_input_min.store(0.0);
  shared_state_->last_input_max.store(0.0);
  shared_state_->last_output_min.store(0.0);
  shared_state_->last_output_max.store(0.0);
  shared_state_->last_input_scale_factor.store(1.0);
  shared_state_->last_input_max_delta.store(0.0);
  shared_state_->last_output_max_delta.store(0.0);
  shared_state_->prototype_stage_frames.store(0);
  shared_state_->prototype_transient_frames.store(0);
  shared_state_->prototype_stationary_frames.store(0);
  shared_state_->prototype_speech_protected_frames.store(0);
  shared_state_->prototype_adjusted_samples.store(0);
  shared_state_->prototype_noise_floor_rms.store(0.0);
  shared_state_->prototype_last_gain.store(1.0);
  shared_state_->deepfilternet_runtime_available.store(false);
  shared_state_->deepfilternet_processing_applied.store(false);
  shared_state_->deepfilternet_frames_processed.store(0);
  shared_state_->deepfilternet_bypass_frames.store(0);
  shared_state_->deepfilternet_frame_length.store(0);
  shared_state_->deepfilternet_reason.store(
      kDeepFilterNetRuntimeReasonNotInitialized);
  shared_state_->deepfilternet_last_local_snr.store(0.0);
  shared_state_->deepfilternet_prewarm_pending_frames.store(0);
  shared_state_->deepfilternet_speech_protected_frames.store(0);
  shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
  shared_state_->deepfilternet_transient_suppressed_frames.store(0);
  shared_state_->deepfilternet_transient_adjusted_samples.store(0);
  shared_state_->deepfilternet_last_transient_gain.store(1.0);
  shared_state_->deepfilternet_hush_runtime_available.store(false);
  shared_state_->deepfilternet_hush_processing_applied.store(false);
  shared_state_->deepfilternet_hush_frames_processed.store(0);
  shared_state_->deepfilternet_hush_bypass_frames.store(0);
  shared_state_->deepfilternet_hush_frame_length.store(0);
  shared_state_->deepfilternet_hush_reason.store(
      kDeepFilterNetRuntimeReasonNotInitialized);
  shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
  shared_state_->deepfilternet_hush_recovery_frames.store(0);
  shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
  shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
  shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
  shared_state_->processing_applied.store(false);
  shared_state_->callback_average_processing_ms.store(0.0);
  shared_state_->callback_max_processing_ms.store(0.0);
  shared_state_->capture_gap_events.store(0);
  shared_state_->last_callback_interval_ms.store(0.0);
  shared_state_->max_callback_interval_ms.store(0.0);
  shared_state_->frames_since_capture_resume.store(0);
  shared_state_->deepfilternet_gap_recoveries.store(0);
}

void RnnoiseCaptureProcessor::Process(int num_bands,
                                      int num_frames,
                                      int buffer_size,
                                      float* buffer) {
  const auto started_at = std::chrono::steady_clock::now();
  const double callback_budget_ms =
      sample_rate_hz_ <= 0
          ? 10.0
          : (static_cast<double>(num_frames) * 1000.0) /
                static_cast<double>(sample_rate_hz_);
  auto finish_timing = [&]() {
    const auto finished_at = std::chrono::steady_clock::now();
    const double elapsed_ms =
        std::chrono::duration<double, std::milli>(
            finished_at - started_at)
            .count();
    RecordCallbackTiming(elapsed_ms, callback_budget_ms);
  };

  // Capture-callback continuity: measure the interval since the previous
  // callback and arm a DeepFilterNet recovery crossfade when a large gap
  // (capture interruption) is detected. The first callback after (re)start is
  // also treated as a resume so a call join crossfades in cleanly.
  bool arm_gap_recovery = false;
  if (!has_last_callback_time_) {
    arm_gap_recovery = true;
  } else {
    const double callback_interval_ms =
        std::chrono::duration<double, std::milli>(
            started_at - last_callback_time_)
            .count();
    if (std::isfinite(callback_interval_ms) && callback_interval_ms >= 0.0) {
      shared_state_->last_callback_interval_ms.store(callback_interval_ms);
      double previous_max = shared_state_->max_callback_interval_ms.load();
      while (callback_interval_ms > previous_max &&
             !shared_state_->max_callback_interval_ms.compare_exchange_weak(
                 previous_max, callback_interval_ms)) {
      }
      if (callback_interval_ms > kCaptureGapMinIntervalMs) {
        arm_gap_recovery = true;
        shared_state_->capture_gap_events.fetch_add(1);
      }
    }
  }
  last_callback_time_ = started_at;
  has_last_callback_time_ = true;
  if (arm_gap_recovery) {
    deepfilternet_gap_recovery_wet_mix_ = kDeepFilterNetGapRecoveryStartWetMix;
    shared_state_->frames_since_capture_resume.store(0);
  }

  shared_state_->last_num_bands.store(num_bands);
  shared_state_->last_num_frames.store(num_frames);
  shared_state_->last_buffer_size.store(buffer_size);

  const int pipeline_mode = shared_state_->pipeline_mode.load();
  const bool identity_mode =
      pipeline_mode == kRnnoisePipelineModeIdentity;
  const bool deepfilternet_mode =
      pipeline_mode == kRnnoisePipelineModeDeepFilterNet;
  const bool processing_enabled =
      shared_state_->enabled_requested.load() &&
      pipeline_mode != kRnnoisePipelineModeOff;
  if (!processing_enabled || !deepfilternet_mode) {
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
    shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
    shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
    shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
    deepfilternet_hush_recovery_gain_ = 1.0f;
  }
  const bool diagnostic_capture_active =
      shared_state_->diagnostic_capture->active();
  if (!processing_enabled && !diagnostic_capture_active) {
    finish_timing();
    return;
  }

  if (buffer == nullptr || sample_rate_hz_ <= 0 || num_channels_ <= 0) {
    SetFormatMismatch(kRnnoiseFormatMismatchInvalidBuffer,
                      "rnnoise processor received an invalid capture buffer");
    finish_timing();
    return;
  }

  // flutter_webrtc reports WebRTC's internal frequency-band count here. At
  // 48 kHz that count is normally 3, while the buffer pointer still references
  // the full-band channel data from the AudioBuffer. Treat non-positive counts
  // as invalid, but allow 48 kHz / 480-frame callbacks to reach RNNoise.
  if (num_bands <= 0) {
    SetFormatMismatch(kRnnoiseFormatMismatchSplitBands,
                      "expected at least one capture frequency band");
    finish_timing();
    return;
  }

  const int expected_frames = shared_state_->expected_frames_per_10ms.load();
  if (num_frames <= 0 || num_frames != expected_frames) {
    SetFormatMismatch(kRnnoiseFormatMismatchFrameCount,
                      "unexpected capture frame count for 10 ms audio");
    finish_timing();
    return;
  }

  const int expected_buffer_size = num_frames * num_channels_;
  if (buffer_size != expected_buffer_size) {
    SetFormatMismatch(kRnnoiseFormatMismatchBufferSize,
                      "unexpected capture buffer size for deinterleaved audio");
    finish_timing();
    return;
  }

  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) {
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonBypass);
    shared_state_->bypass_frames.fetch_add(1);
    shared_state_->processing_applied.store(false);
    finish_timing();
    return;
  }

  if (processing_enabled && !identity_mode && !deepfilternet_mode &&
      !EnsureRnnoiseState()) {
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonBypass);
    shared_state_->bypass_frames.fetch_add(1);
    shared_state_->processing_applied.store(false);
    finish_timing();
    return;
  }
  shared_state_->format_mismatch_detected.store(false);
  shared_state_->format_mismatch_reason.store(kRnnoiseFormatMismatchNone);

  mono_in_.resize(num_frames);
  std::fill(mono_in_.begin(), mono_in_.end(), 0.0f);

  for (int channel = 0; channel < num_channels_; ++channel) {
    const float* channel_data = buffer + (channel * num_frames);
    for (int sample = 0; sample < num_frames; ++sample) {
      mono_in_[sample] += channel_data[sample];
    }
  }

  const float inv_num_channels = 1.0f / static_cast<float>(num_channels_);
  for (float& sample : mono_in_) {
    sample *= inv_num_channels;
  }

  const float input_scale_factor = DetectInputScaleFactor(mono_in_);
  CopyScaled(mono_in_, 1.0f / input_scale_factor, &mono_in_normalized_);
  const double input_min = MinSample(mono_in_normalized_);
  const double input_max = MaxSample(mono_in_normalized_);
  shared_state_->last_input_scale_factor.store(input_scale_factor);
  shared_state_->last_input_max_delta.store(MaxDelta(mono_in_normalized_));
  shared_state_->last_input_min.store(
      std::isfinite(input_min) ? input_min : 0.0);
  shared_state_->last_input_max.store(
      std::isfinite(input_max) ? input_max : 0.0);
  const int input_non_finite = CountNonFiniteSamples(mono_in_normalized_);
  const int input_clipping = CountClippingSamples(mono_in_normalized_);
  if (input_non_finite > 0) {
    shared_state_->non_finite_samples.fetch_add(input_non_finite);
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonBypass);
    shared_state_->bypass_frames.fetch_add(1);
    shared_state_->processing_applied.store(false);
    finish_timing();
    return;
  }
  if (input_clipping > 0) {
    shared_state_->input_clipping_samples.fetch_add(input_clipping);
    shared_state_->clipping_samples.fetch_add(input_clipping);
  }

  if (identity_mode) {
    const double input_rms = Rms(mono_in_normalized_);
    const double input_peak = PeakAbs(mono_in_normalized_);
    const double input_delta = MaxDelta(mono_in_normalized_);
    shared_state_->last_vad_probability.store(0.0);
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonPass);
    shared_state_->last_gate_gain.store(1.0);
    shared_state_->speech_grace_remaining_frames.store(0);
    shared_state_->last_input_rms.store(
        std::isfinite(input_rms) ? input_rms : 0.0);
    shared_state_->last_output_rms.store(
        std::isfinite(input_rms) ? input_rms : 0.0);
    shared_state_->last_output_ratio.store(1.0);
    shared_state_->last_input_peak.store(
        std::isfinite(input_peak) ? input_peak : 0.0);
    shared_state_->last_output_peak.store(
        std::isfinite(input_peak) ? input_peak : 0.0);
    shared_state_->last_output_min.store(
        std::isfinite(input_min) ? input_min : 0.0);
    shared_state_->last_output_max.store(
        std::isfinite(input_max) ? input_max : 0.0);
    shared_state_->last_input_max_delta.store(
        std::isfinite(input_delta) ? input_delta : 0.0);
    shared_state_->last_output_max_delta.store(
        std::isfinite(input_delta) ? input_delta : 0.0);
    shared_state_->processing_applied.store(false);
    shared_state_->identity_frames.fetch_add(1);
    RecordDryDiagnosticCallback(
        mono_in_normalized_,
        sample_rate_hz_,
        num_frames);
    shared_state_->frames_processed.fetch_add(1);
    finish_timing();
    return;
  }

  if (!processing_enabled) {
    const double input_rms = Rms(mono_in_normalized_);
    const double input_peak = PeakAbs(mono_in_normalized_);
    const double input_delta = MaxDelta(mono_in_normalized_);
    shared_state_->last_vad_probability.store(0.0);
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonPass);
    shared_state_->last_gate_gain.store(1.0);
    shared_state_->speech_grace_remaining_frames.store(0);
    shared_state_->last_input_rms.store(
        std::isfinite(input_rms) ? input_rms : 0.0);
    shared_state_->last_output_rms.store(
        std::isfinite(input_rms) ? input_rms : 0.0);
    shared_state_->last_output_ratio.store(1.0);
    shared_state_->last_input_peak.store(
        std::isfinite(input_peak) ? input_peak : 0.0);
    shared_state_->last_output_peak.store(
        std::isfinite(input_peak) ? input_peak : 0.0);
    shared_state_->last_output_min.store(
        std::isfinite(input_min) ? input_min : 0.0);
    shared_state_->last_output_max.store(
        std::isfinite(input_max) ? input_max : 0.0);
    shared_state_->last_input_max_delta.store(
        std::isfinite(input_delta) ? input_delta : 0.0);
    shared_state_->last_output_max_delta.store(
        std::isfinite(input_delta) ? input_delta : 0.0);
    shared_state_->processing_applied.store(false);
    RecordDryDiagnosticCallback(
        mono_in_normalized_,
        sample_rate_hz_,
        num_frames);
    finish_timing();
    return;
  }

  if (deepfilternet_mode) {
    float local_snr = 0.0f;
    bool deepfilternet_processed = ProcessDeepFilterNet(
        num_frames,
        mono_in_normalized_,
        &mono_out_normalized_,
        &local_snr);
    std::vector<float> deepfilternet_output_for_capture;
    std::vector<float> speech_protect_output_for_capture;
    std::vector<float> transient_guard_output_for_capture;
    std::vector<float> hush_input_for_capture_16k;
    std::vector<float> hush_output_for_capture_16k;
    std::vector<float> hush_output_for_capture;
    int gate_reason = kRnnoiseGateReasonPass;
    if (!deepfilternet_processed) {
      mono_out_normalized_ = mono_in_normalized_;
      deepfilternet_wet_mix_ = 1.0f;
      shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
      shared_state_->deepfilternet_bypass_frames.fetch_add(1);
      shared_state_->bypass_frames.fetch_add(1);
      gate_reason = kRnnoiseGateReasonBypass;
    } else if (diagnostic_capture_active) {
      deepfilternet_output_for_capture = mono_out_normalized_;
    }

    const double input_rms = Rms(mono_in_normalized_);
    const double input_peak = PeakAbs(mono_in_normalized_);
    const double input_delta = MaxDelta(mono_in_normalized_);
    double output_rms = Rms(mono_out_normalized_);
    double output_peak = PeakAbs(mono_out_normalized_);
    double output_delta = MaxDelta(mono_out_normalized_);
    double output_ratio =
        input_rms <= 0.0 ? 1.0 : output_rms / input_rms;

    // Dry-reference alignment: the model output corresponds to the dry frame
    // from `lookahead_frames()` callbacks ago, so every post-model stage
    // blends/compares against that delayed frame instead of the current one.
    // While the history is still filling after a pipeline reset the delayed
    // reference is silence, which matches the model's warm-up output and
    // keeps the guards inactive for those frames.
    int dry_delay_frames = 0;
    if (deepfilternet_processed) {
      dry_delay_frames = deepfilternet_runtime_->lookahead_frames();
      const int hush_lookahead_frames =
          hush_runtime_ ? hush_runtime_->lookahead_frames() : 1;
      EnsureDryHistoryCapacity(num_frames,
                               dry_delay_frames + hush_lookahead_frames);
      CopyDelayedDryFrame(dry_delay_frames,
                          num_frames,
                          &deepfilternet_dry_delayed_);
    } else {
      deepfilternet_dry_delayed_.assign(num_frames, 0.0f);
    }
    shared_state_->deepfilternet_dry_delay_frames.store(
        deepfilternet_processed ? dry_delay_frames : 0);
    const double aligned_dry_rms = Rms(deepfilternet_dry_delayed_);
    const double aligned_dry_peak = PeakAbs(deepfilternet_dry_delayed_);
    const double aligned_dry_delta = MaxDelta(deepfilternet_dry_delayed_);

    const bool speech_protected_frame =
        deepfilternet_processed &&
        ApplyDeepFilterNetSpeechProtection(deepfilternet_dry_delayed_,
                                           aligned_dry_rms,
                                           aligned_dry_peak,
                                           aligned_dry_delta,
                                           output_rms,
                                           output_peak,
                                           output_delta,
                                           local_snr,
                                           &mono_out_normalized_);
    if (speech_protected_frame) {
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_delta = MaxDelta(mono_out_normalized_);
      output_ratio = input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
    } else if (deepfilternet_processed) {
      shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
    }
    if (deepfilternet_processed && diagnostic_capture_active) {
      speech_protect_output_for_capture = mono_out_normalized_;
    }

    const int transient_adjustments = deepfilternet_processed
        ? ApplyDeepFilterNetTransientSuppression(
              deepfilternet_dry_delayed_,
              aligned_dry_rms,
              aligned_dry_peak,
              aligned_dry_delta,
              output_rms,
              output_peak,
              output_delta,
              local_snr,
              speech_protected_frame,
              &mono_out_normalized_)
                                         : 0;
    if (transient_adjustments > 0) {
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_delta = MaxDelta(mono_out_normalized_);
      output_ratio = input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
    }
    if (deepfilternet_processed && diagnostic_capture_active) {
      transient_guard_output_for_capture = mono_out_normalized_;
    }

    bool hush_processed_this_frame = false;
    if (deepfilternet_processed &&
        shared_state_->deepfilternet_hush_suppression_enabled.load()) {
      float hush_local_snr = 0.0f;
      const double pre_hush_rms = output_rms;
      const double pre_hush_peak = output_peak;
      if (ProcessDeepFilterNetHushSupport(num_frames,
                                          mono_out_normalized_,
                                          &mono_out_normalized_,
                                          &hush_local_snr)) {
        hush_processed_this_frame = true;
        if (diagnostic_capture_active) {
          hush_input_for_capture_16k = hush_input_;
          hush_output_for_capture_16k = hush_output_;
          hush_output_for_capture = hush_output_for_capture_;
        }
        const double hush_output_rms = Rms(mono_out_normalized_);
        const double hush_output_peak = PeakAbs(mono_out_normalized_);
        // Hush output is one Hush frame (10 ms) late relative to its input,
        // so compare against the previous callback's pre-Hush level. The
        // first processed frame after a (re)start has no aligned reference
        // and applies no recovery.
        ApplyDeepFilterNetHushGainRecovery(
            has_previous_pre_hush_metrics_ ? previous_pre_hush_rms_ : 0.0,
            has_previous_pre_hush_metrics_ ? previous_pre_hush_peak_ : 0.0,
            hush_output_rms,
            hush_output_peak,
            &mono_out_normalized_);
        previous_pre_hush_rms_ = pre_hush_rms;
        previous_pre_hush_peak_ = pre_hush_peak;
        has_previous_pre_hush_metrics_ = true;
        output_rms = Rms(mono_out_normalized_);
        output_peak = PeakAbs(mono_out_normalized_);
        output_delta = MaxDelta(mono_out_normalized_);
        output_ratio = input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
      } else {
        shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
        shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
        shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
        deepfilternet_hush_recovery_gain_ = 1.0f;
        has_previous_pre_hush_metrics_ = false;
      }
    } else {
      shared_state_->deepfilternet_hush_processing_applied.store(false);
      shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
      shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
      shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
      shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
      deepfilternet_hush_recovery_gain_ = 1.0f;
      has_previous_pre_hush_metrics_ = false;
    }

    // The dry frame aligned with the CURRENT chain output: one extra frame
    // late when Hush processed this callback (its own 10 ms lookahead).
    const int post_delay_frames = hush_processed_this_frame
        ? dry_delay_frames +
              (hush_runtime_ ? hush_runtime_->lookahead_frames() : 1)
        : dry_delay_frames;
    if (deepfilternet_processed) {
      CopyDelayedDryFrame(post_delay_frames,
                          num_frames,
                          &deepfilternet_dry_delayed_post_);
    } else {
      deepfilternet_dry_delayed_post_.assign(num_frames, 0.0f);
    }

    // Recover from any capture-gap discontinuity by crossfading DeepFilterNet
    // output back in from the delay-aligned dry reference over a few frames,
    // masking stale-lookahead output and the recovery pop. Both crossfade
    // sources sit on the same timeline, so the ramp no longer combs. When
    // fully recovered the mix is 1.0 and this is a no-op. Skipped on bypassed
    // frames, which are already raw.
    if (deepfilternet_processed &&
        deepfilternet_gap_recovery_wet_mix_ <
            kDeepFilterNetGapRecoveryFullWetMix) {
      if (deepfilternet_gap_recovery_wet_mix_ <=
          kDeepFilterNetGapRecoveryStartWetMix) {
        shared_state_->deepfilternet_gap_recoveries.fetch_add(1);
      }
      const float recovery_target = (std::min)(
          1.0f,
          deepfilternet_gap_recovery_wet_mix_ +
              kDeepFilterNetGapRecoveryStepPerFrame);
      RampWetMixWithState(&mono_out_normalized_,
                          deepfilternet_dry_delayed_post_,
                          recovery_target,
                          &deepfilternet_gap_recovery_wet_mix_);
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_delta = MaxDelta(mono_out_normalized_);
      output_ratio = input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
    }

    // Bound output slew with the delta of the dry frame the output actually
    // corresponds to; the current dry frame is up to 30 ms ahead of it.
    const double limiter_reference_delta = deepfilternet_processed
        ? MaxDelta(deepfilternet_dry_delayed_post_)
        : input_delta;
    const int limiter_adjustments = ApplyOutputSafetyLimiter(
        limiter_reference_delta,
        &mono_out_normalized_);
    if (limiter_adjustments > 0) {
      shared_state_->output_limiter_samples.fetch_add(limiter_adjustments);
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_delta = MaxDelta(mono_out_normalized_);
      output_ratio = input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
    }

    shared_state_->last_vad_probability.store(0.0);
    shared_state_->recent_vad_average.store(0.0);
    shared_state_->last_gate_reason.store(gate_reason);
    shared_state_->last_gate_gain.store(1.0);
    shared_state_->speech_grace_remaining_frames.store(0);
    shared_state_->last_input_rms.store(
        std::isfinite(input_rms) ? input_rms : 0.0);
    shared_state_->last_output_rms.store(
        std::isfinite(output_rms) ? output_rms : 0.0);
    shared_state_->last_output_ratio.store(
        std::isfinite(output_ratio) ? output_ratio : 1.0);
    shared_state_->last_input_peak.store(
        std::isfinite(input_peak) ? input_peak : 0.0);
    shared_state_->last_output_peak.store(
        std::isfinite(output_peak) ? output_peak : 0.0);
    shared_state_->last_output_min.store(MinSample(mono_out_normalized_));
    shared_state_->last_output_max.store(MaxSample(mono_out_normalized_));
    shared_state_->last_input_max_delta.store(
        std::isfinite(input_delta) ? input_delta : 0.0);
    shared_state_->last_output_max_delta.store(
        std::isfinite(output_delta) ? output_delta : 0.0);
    shared_state_->deepfilternet_last_local_snr.store(local_snr);
    shared_state_->processing_applied.store(deepfilternet_processed);
    shared_state_->deepfilternet_processing_applied.store(
        deepfilternet_processed);

    mono_out_.resize(num_frames);
    for (int sample = 0; sample < num_frames; ++sample) {
      mono_out_[sample] = ClampToInputScale(
          mono_out_normalized_[sample] * input_scale_factor,
          input_scale_factor);
    }
    for (int channel = 0; channel < num_channels_; ++channel) {
      float* channel_data = buffer + (channel * num_frames);
      std::copy(mono_out_.begin(), mono_out_.end(), channel_data);
    }

    // The model consumed this frame, so it becomes history for the next
    // callbacks' aligned dry taps. Bypassed frames are not pushed: the model
    // never saw them, and pushing them would desynchronize the delay line
    // from the model's own frame timeline.
    if (deepfilternet_processed) {
      PushDryHistoryFrame(mono_in_normalized_);
    }

    shared_state_->diagnostic_capture->RecordEnhancedProcessedCallback(
        mono_in_normalized_,
        sample_rate_hz_,
        deepfilternet_output_for_capture,
        speech_protect_output_for_capture,
        transient_guard_output_for_capture,
        hush_input_for_capture_16k,
        hush_output_for_capture_16k,
        hush_output_for_capture,
        mono_out_normalized_,
        sample_rate_hz_);
    shared_state_->frames_processed.fetch_add(1);
    shared_state_->frames_since_capture_resume.fetch_add(1);
    finish_timing();
    return;
  }

  float vad_probability = 0.0f;
  if (!ProcessCleanRnnoise(num_frames,
                           mono_in_normalized_,
                           &mono_out_normalized_,
                           &vad_probability)) {
    shared_state_->diagnostic_capture->RecordRawInput(
        mono_in_normalized_,
        sample_rate_hz_);
    // RNNoise/resampler failure still fails open, but not past the final
    // limiter; otherwise a transient capture spike can become the call audio.
    mono_out_normalized_ = mono_in_normalized_;
    int failure_gate_reason = kRnnoiseGateReasonBypass;
    const double fallback_input_delta = MaxDelta(mono_out_normalized_);
    const int fallback_burst_adjustments = ApplyNonSpeechBurstGuard(
        0.0f,
        PeakAbs(mono_out_normalized_),
        fallback_input_delta,
        &mono_out_normalized_);
    if (fallback_burst_adjustments > 0) {
      shared_state_->gated_frames.fetch_add(1);
      shared_state_->output_limiter_samples.fetch_add(
          fallback_burst_adjustments);
      failure_gate_reason = kRnnoiseGateReasonImpulseGate;
    }
    const int fallback_limiter_adjustments =
        ApplyOutputSafetyLimiter(fallback_input_delta, &mono_out_normalized_);
    if (fallback_limiter_adjustments > 0) {
      shared_state_->output_limiter_samples.fetch_add(
          fallback_limiter_adjustments);
    }
    shared_state_->diagnostic_capture->RecordFinalOutput(
        mono_out_normalized_,
        sample_rate_hz_);
    const double fallback_input_rms = Rms(mono_in_normalized_);
    const double fallback_input_peak = PeakAbs(mono_in_normalized_);
    const double fallback_output_rms = Rms(mono_out_normalized_);
    const double fallback_output_peak = PeakAbs(mono_out_normalized_);
    const double fallback_output_delta = MaxDelta(mono_out_normalized_);
    const double fallback_output_min = MinSample(mono_out_normalized_);
    const double fallback_output_max = MaxSample(mono_out_normalized_);
    shared_state_->last_input_rms.store(std::isfinite(fallback_input_rms)
                                            ? fallback_input_rms
                                            : 0.0);
    shared_state_->last_output_rms.store(
        std::isfinite(fallback_output_rms) ? fallback_output_rms : 0.0);
    shared_state_->last_output_ratio.store(fallback_input_rms <= 0
                                               ? 1.0
                                               : fallback_output_rms /
                                                     fallback_input_rms);
    shared_state_->last_input_peak.store(
        std::isfinite(fallback_input_peak) ? fallback_input_peak : 0.0);
    shared_state_->last_output_peak.store(
        std::isfinite(fallback_output_peak) ? fallback_output_peak : 0.0);
    shared_state_->last_output_min.store(
        std::isfinite(fallback_output_min) ? fallback_output_min : 0.0);
    shared_state_->last_output_max.store(
        std::isfinite(fallback_output_max) ? fallback_output_max : 0.0);
    shared_state_->last_output_max_delta.store(
        std::isfinite(fallback_output_delta) ? fallback_output_delta : 0.0);
    shared_state_->processing_applied.store(true);
    mono_out_.resize(num_frames);
    for (int sample = 0; sample < num_frames; ++sample) {
      mono_out_[sample] = ClampToInputScale(
          mono_out_normalized_[sample] * input_scale_factor,
          input_scale_factor);
    }
    for (int channel = 0; channel < num_channels_; ++channel) {
      float* channel_data = buffer + (channel * num_frames);
      std::copy(mono_out_.begin(), mono_out_.end(), channel_data);
    }
    wet_mix_ = 0.0f;
    shared_state_->last_gate_reason.store(failure_gate_reason);
    shared_state_->last_gate_gain.store(1.0);
    shared_state_->bypass_frames.fetch_add(1);
    shared_state_->frames_processed.fetch_add(1);
    finish_timing();
    return;
  }

  const double input_rms = Rms(mono_in_normalized_);
  const double input_peak = PeakAbs(mono_in_normalized_);
  const double input_delta = MaxDelta(mono_in_normalized_);
  double output_rms = Rms(mono_out_normalized_);
  double output_peak = PeakAbs(mono_out_normalized_);
  double output_ratio =
      input_rms <= 0 ? 1.0 : output_rms / input_rms;
  double output_max_delta = MaxDelta(mono_out_normalized_);
  int gate_reason = kRnnoiseGateReasonPass;
  float target_gate_gain = 1.0f;
  double delayed_input_rms = input_rms;
  double delayed_input_peak = input_peak;
  double delayed_input_delta = input_delta;
  bool has_delayed_input_metrics = false;
  if (input_metric_history_count_ >= kRnnoiseOutputInputDelayFrames) {
    int delayed_index =
        input_metric_history_next_index_ - kRnnoiseOutputInputDelayFrames;
    while (delayed_index < 0) {
      delayed_index += static_cast<int>(input_rms_history_.size());
    }
    delayed_index %= static_cast<int>(input_rms_history_.size());
    delayed_input_rms = input_rms_history_[delayed_index];
    delayed_input_peak = input_peak_history_[delayed_index];
    delayed_input_delta = input_delta_history_[delayed_index];
    has_delayed_input_metrics = true;
  }
  const double delayed_output_ratio =
      delayed_input_rms <= 0 ? 1.0 : output_rms / delayed_input_rms;
  const double delayed_peak_growth = output_peak - delayed_input_peak;
  const double delayed_delta_growth = output_max_delta - delayed_input_delta;
  const bool distorted_input =
      input_clipping > 0 ||
      input_peak >= kDryFallbackInputPeakFloor ||
      input_delta >= kDryFallbackInputDeltaFloor;
  const bool amplified_residual =
      output_rms >= kDryFallbackOutputRmsFloor &&
      output_ratio >= kDryFallbackOutputRatioFloor;
  const bool low_vad_output_burst =
      vad_probability < kDryFallbackLowVadCeiling &&
      (output_peak >= kDryFallbackLowVadPeakFloor ||
       output_max_delta >= kDryFallbackLowVadDeltaFloor);
  const double output_peak_growth = output_peak - input_peak;
  const double output_delta_growth = output_max_delta - input_delta;
  // Post-pop field captures showed RNNoise occasionally turning moderate
  // transient frames into much larger spikes while hook input remained clean.
  const bool rnnoise_amplified_transient =
      input_rms > 0.0 &&
      input_rms <= kSuspiciousTransientInputRmsCeiling &&
      output_rms >= kSuspiciousTransientOutputRmsFloor &&
      output_ratio >= kSuspiciousTransientOutputRatioFloor &&
      output_peak >= kSuspiciousTransientOutputPeakFloor &&
      (output_peak_growth >= kSuspiciousTransientPeakGrowthFloor ||
       output_delta_growth >= kSuspiciousTransientDeltaGrowthFloor);
  const bool rnnoise_delayed_amplified_residual =
      has_delayed_input_metrics &&
      delayed_input_rms <= kDelayedInputResidualRmsCeiling &&
      input_rms <= kCurrentInputResidualRmsCeiling &&
      input_peak <= kCurrentInputResidualPeakCeiling &&
      input_delta <= kCurrentInputResidualDeltaCeiling &&
      output_rms >= kDelayedInputResidualOutputRmsFloor &&
      output_peak >= kDelayedInputResidualOutputPeakFloor &&
      delayed_output_ratio >= kDelayedInputResidualOutputRatioFloor &&
      (delayed_peak_growth >= kDelayedInputResidualPeakGrowthFloor ||
       delayed_delta_growth >= kDelayedInputResidualDeltaGrowthFloor);
  if (rnnoise_amplified_transient || rnnoise_delayed_amplified_residual) {
    suspicious_transient_streak_++;
  } else {
    suspicious_transient_streak_ = 0;
  }
  const bool reset_rnnoise_after_transient =
      suspicious_transient_streak_ >= kSuspiciousTransientResetThreshold;
  const bool dry_fallback_frame =
      amplified_residual ||
      low_vad_output_burst ||
      rnnoise_amplified_transient ||
      rnnoise_delayed_amplified_residual;
  if (dry_fallback_frame) {
    mono_out_normalized_ = mono_in_normalized_;
    wet_mix_ = 0.0f;
    gate_reason = kRnnoiseGateReasonBypass;
    shared_state_->bypass_frames.fetch_add(1);
    const int fallback_burst_adjustments = ApplyNonSpeechBurstGuard(
        vad_probability,
        input_peak,
        input_delta,
        &mono_out_normalized_);
    if (fallback_burst_adjustments > 0) {
      shared_state_->gated_frames.fetch_add(1);
      shared_state_->output_limiter_samples.fetch_add(
          fallback_burst_adjustments);
      gate_reason = kRnnoiseGateReasonImpulseGate;
    }
    if (rnnoise_amplified_transient || rnnoise_delayed_amplified_residual) {
      suspicious_output_recovery_frames_ = 0;
      if (reset_rnnoise_after_transient) {
        shared_state_->suspicious_output_detected.store(true);
        ResetRnnoiseState();
        ResetAudioPipeline();
        suspicious_transient_streak_ = 0;
      }
    }
  } else {
    RampWetMix(&mono_out_normalized_, mono_in_normalized_, 1.0f);
  }
  output_rms = Rms(mono_out_normalized_);
  output_peak = PeakAbs(mono_out_normalized_);
  output_ratio =
      input_rms <= 0 ? 1.0 : output_rms / input_rms;
  output_max_delta = MaxDelta(mono_out_normalized_);
  shared_state_->last_vad_probability.store(vad_probability);
  float vad_threshold =
      static_cast<float>(shared_state_->reference_vad_threshold.load());
  if (!std::isfinite(vad_threshold)) {
    vad_threshold = kReferenceVadThreshold;
  }
  vad_threshold = (std::clamp)(vad_threshold, 0.50f, 0.999f);
  const int speech_grace_frames =
      (std::max)(0, shared_state_->reference_speech_grace_frames.load());
  float closed_gate_gain =
      static_cast<float>(shared_state_->noise_gate_closed_gain.load());
  if (!std::isfinite(closed_gate_gain)) {
    closed_gate_gain = kNoiseGateClosedGain;
  }
  closed_gate_gain = Clamp01(closed_gate_gain);
  const float transient_sensitivity = Clamp01(
      static_cast<float>(shared_state_->transient_sensitivity.load()));
  const bool fast_close_enabled =
      shared_state_->fast_close_enabled.load();

  if (vad_probability < 0.5f) {
    shared_state_->vad_low_frames.fetch_add(1);
  } else if (vad_probability < vad_threshold) {
    shared_state_->vad_mid_frames.fetch_add(1);
  } else {
    shared_state_->vad_high_frames.fetch_add(1);
  }
  if (vad_average_sample_count_ == 0) {
    recent_vad_average_ = vad_probability;
  } else {
    recent_vad_average_ =
        (recent_vad_average_ * 0.95f) + (vad_probability * 0.05f);
  }
  vad_average_sample_count_++;
  shared_state_->recent_vad_average.store(recent_vad_average_);

  const bool prototype_suppression_v1_mode =
      pipeline_mode == kRnnoisePipelineModePrototypeSuppression;
  const bool prototype_suppression_v2_mode =
      pipeline_mode == kRnnoisePipelineModePrototypeSuppressionV2;
  const bool prototype_suppression_mode =
      prototype_suppression_v1_mode || prototype_suppression_v2_mode;
  if (!dry_fallback_frame &&
      (pipeline_mode == kRnnoisePipelineModeCleanRnnoise ||
       prototype_suppression_v1_mode)) {
    const bool hot_speech_input =
        distorted_input ||
        (input_rms > kPostSpeechHotInputRmsFloor &&
         (vad_probability >= kSuspiciousSpeechVadThreshold ||
          input_peak > 0.95));
    const int post_speech_residual_adjustments =
        ApplyPostSpeechResidualGuard(input_rms,
                                     output_rms,
                                     output_peak,
                                     &mono_out_normalized_);
    if (post_speech_residual_adjustments > 0) {
      shared_state_->gated_frames.fetch_add(1);
      shared_state_->output_limiter_samples.fetch_add(
          post_speech_residual_adjustments);
      gate_reason = kRnnoiseGateReasonImpulseGate;
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_ratio = input_rms <= 0 ? 1.0 : output_rms / input_rms;
      output_max_delta = MaxDelta(mono_out_normalized_);
    }
    if (hot_speech_input) {
      post_speech_residual_guard_frames_ = kPostSpeechResidualGuardFrames;
    } else if (post_speech_residual_guard_frames_ > 0) {
      post_speech_residual_guard_frames_--;
    }

    const int burst_guard_adjustments = ApplyNonSpeechBurstGuard(
        vad_probability,
        output_peak,
        output_max_delta,
        &mono_out_normalized_);
    if (burst_guard_adjustments > 0) {
      shared_state_->gated_frames.fetch_add(1);
      shared_state_->output_limiter_samples.fetch_add(
          burst_guard_adjustments);
      gate_reason = kRnnoiseGateReasonImpulseGate;
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_ratio = input_rms <= 0 ? 1.0 : output_rms / input_rms;
      output_max_delta = MaxDelta(mono_out_normalized_);
    }
  }

  if (!dry_fallback_frame && prototype_suppression_v1_mode) {
    const int transient_frames_before =
        shared_state_->prototype_transient_frames.load();
    const int stationary_frames_before =
        shared_state_->prototype_stationary_frames.load();
    const int prototype_adjustments =
        ApplyPrototypeSuppressionStage(vad_probability,
                                       input_rms,
                                       input_peak,
                                       input_delta,
                                       output_rms,
                                       output_peak,
                                       output_max_delta,
                                       &mono_out_normalized_);
    if (prototype_adjustments > 0) {
      const bool transient_adjusted =
          shared_state_->prototype_transient_frames.load() >
          transient_frames_before;
      const bool stationary_adjusted =
          shared_state_->prototype_stationary_frames.load() >
          stationary_frames_before;
      if (transient_adjusted) {
        gate_reason = kRnnoiseGateReasonImpulseGate;
      } else if (stationary_adjusted) {
        gate_reason = kRnnoiseGateReasonVadGate;
      }
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_ratio = input_rms <= 0 ? 1.0 : output_rms / input_rms;
      output_max_delta = MaxDelta(mono_out_normalized_);
    }
  }

  shared_state_->last_input_rms.store(
      std::isfinite(input_rms) ? input_rms : 0.0);
  shared_state_->last_output_rms.store(
      std::isfinite(output_rms) ? output_rms : 0.0);
  shared_state_->last_output_ratio.store(
      std::isfinite(output_ratio) ? output_ratio : 1.0);
  shared_state_->last_input_peak.store(
      std::isfinite(input_peak) ? input_peak : 0.0);
  shared_state_->last_output_peak.store(
      std::isfinite(output_peak) ? output_peak : 0.0);
  shared_state_->last_input_max_delta.store(
      std::isfinite(input_delta) ? input_delta : 0.0);
  shared_state_->last_output_min.store(MinSample(mono_out_normalized_));
  shared_state_->last_output_max.store(MaxSample(mono_out_normalized_));
  shared_state_->last_output_max_delta.store(
      std::isfinite(output_max_delta) ? output_max_delta : 0.0);
  input_rms_history_[input_metric_history_next_index_] = input_rms;
  input_peak_history_[input_metric_history_next_index_] = input_peak;
  input_delta_history_[input_metric_history_next_index_] = input_delta;
  input_metric_history_next_index_ =
      (input_metric_history_next_index_ + 1) %
      static_cast<int>(input_rms_history_.size());
  input_metric_history_count_ =
      (std::min)(input_metric_history_count_ + 1,
                 static_cast<int>(input_rms_history_.size()));

  const bool speech_like_input =
      input_rms > kSuspiciousSpeechInputRmsFloor &&
      vad_probability >= kSuspiciousSpeechVadThreshold;
  // Strong attenuation can be useful RNNoise output. Treat a low ratio as
  // suspicious only when the output is also effectively collapsed to silence.
  const bool output_collapsed =
      output_rms < kSuspiciousOutputRmsCeiling;
  const bool strong_relative_attenuation =
      output_ratio < kSuspiciousSpeechOutputRmsRatioCeiling;
  const bool collapsed_speech_output =
      speech_like_input && output_collapsed && strong_relative_attenuation;
  const bool suspicious_output =
      HasNonFiniteSample(mono_out_normalized_) || collapsed_speech_output;
  if (suspicious_output) {
    shared_state_->non_finite_samples.fetch_add(
        CountNonFiniteSamples(mono_out_normalized_));
    suspicious_output_streak_++;
    suspicious_output_recovery_frames_ = 0;
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonBypass);
    shared_state_->bypass_frames.fetch_add(1);
    if (suspicious_output_streak_ >= kSuspiciousOutputBypassThreshold) {
      shared_state_->suspicious_output_detected.store(true);
    }
    has_output_limiter_previous_sample_ = false;
    shared_state_->processing_applied.store(false);
    finish_timing();
    return;
  }

  suspicious_output_streak_ = 0;
  if (shared_state_->suspicious_output_detected.load()) {
    suspicious_output_recovery_frames_++;
    if (suspicious_output_recovery_frames_ >=
        kSuspiciousOutputRecoveryFrames) {
      shared_state_->suspicious_output_detected.store(false);
      suspicious_output_recovery_frames_ = 0;
    }
  } else {
    suspicious_output_recovery_frames_ = 0;
  }

  if (!dry_fallback_frame &&
      (pipeline_mode == kRnnoisePipelineModeTunedGate ||
       prototype_suppression_mode)) {
    const double input_crest_factor =
        input_rms <= 0 ? 0.0 : input_peak / input_rms;
    const float speech_protect_vad_threshold =
        (std::min)(vad_threshold, kNoiseGateSpeechProtectVadThreshold);
    const bool current_speech_frame =
        vad_probability >= speech_protect_vad_threshold &&
        input_rms >= kNoiseGateSpeechProtectInputRmsFloor;
    const bool strong_speech_frame =
        current_speech_frame &&
        vad_probability >= kNoiseGateSpeechStrongVadProtectThreshold;
    const float impulse_vad_ceiling = LerpFloat(
        kNoiseGateImpulseVadCeiling,
        kNoiseGateMaxImpulseVadCeiling,
        transient_sensitivity);
    const double transient_input_rms_floor = LerpDouble(
        kNoiseGateTransientInputRmsFloor,
        kNoiseGateMinTransientInputRmsFloor,
        transient_sensitivity);
    const double impulse_peak_floor = LerpDouble(
        kNoiseGateImpulsePeakFloor,
        kNoiseGateMinImpulsePeakFloor,
        transient_sensitivity);
    const double impulse_crest_factor_floor = LerpDouble(
        kNoiseGateImpulseCrestFactorFloor,
        kNoiseGateMinImpulseCrestFactorFloor,
        transient_sensitivity);
    const bool likelyImpulseNoise =
        vad_probability < impulse_vad_ceiling &&
        input_rms > transient_input_rms_floor &&
        input_peak > impulse_peak_floor &&
        input_crest_factor > impulse_crest_factor_floor;
    const double typing_input_rms_ceiling = LerpDouble(
        kNoiseGateTypingInputRmsCeiling,
        kNoiseGateMaxTypingInputRmsCeiling,
        transient_sensitivity);
    const double typing_peak_floor = LerpDouble(
        kNoiseGateTypingPeakFloor,
        kNoiseGateMinTypingPeakFloor,
        transient_sensitivity);
    const double typing_delta_floor = LerpDouble(
        kNoiseGateTypingDeltaFloor,
        kNoiseGateMinTypingDeltaFloor,
        transient_sensitivity);
    const double typing_crest_factor_floor = LerpDouble(
        kNoiseGateTypingCrestFactorFloor,
        kNoiseGateMinTypingCrestFactorFloor,
        transient_sensitivity);
    const double harsh_transient_peak_floor = LerpDouble(
        kNoiseGateHarshTransientPeakFloor,
        kNoiseGateHarshTransientMinPeakFloor,
        transient_sensitivity);
    const double harsh_transient_delta_floor = LerpDouble(
        kNoiseGateHarshTransientDeltaFloor,
        kNoiseGateHarshTransientMinDeltaFloor,
        transient_sensitivity);
    const double harsh_transient_crest_factor_floor = LerpDouble(
        kNoiseGateHarshTransientCrestFactorFloor,
        kNoiseGateHarshTransientMinCrestFactorFloor,
        transient_sensitivity);
    const bool harsh_transient_noise =
        transient_sensitivity > 0.0f &&
        vad_probability < kNoiseGateHarshTransientVadCeiling &&
        input_peak > harsh_transient_peak_floor &&
        input_delta > harsh_transient_delta_floor &&
        input_crest_factor > harsh_transient_crest_factor_floor;
    const bool speech_protected_transient =
        current_speech_frame &&
        (input_rms >= kNoiseGateSpeechTransientRmsCeiling ||
         strong_speech_frame);
    const bool likelyTypingNoise =
        transient_sensitivity > 0.0f &&
        !speech_protected_transient &&
        input_rms > kNoiseGateTypingInputRmsFloor &&
        input_rms < typing_input_rms_ceiling &&
        input_peak > typing_peak_floor &&
        input_delta > typing_delta_floor &&
        input_crest_factor > typing_crest_factor_floor;
    const bool likelyDeskTapNoise =
        transient_sensitivity > 0.0f &&
        vad_probability < speech_protect_vad_threshold &&
        input_rms > kNoiseGateTypingInputRmsFloor &&
        input_rms < kNoiseGateDeskTapInputRmsCeiling &&
        input_peak > kNoiseGateDeskTapPeakFloor &&
        input_delta > kNoiseGateDeskTapDeltaFloor &&
        input_crest_factor > kNoiseGateDeskTapCrestFactorFloor;
    const bool transient_noise_detected =
        !speech_protected_transient &&
        (likelyImpulseNoise ||
         likelyTypingNoise ||
         likelyDeskTapNoise ||
         harsh_transient_noise);
    if (transient_noise_detected) {
      const int hold_frames = (std::clamp)(
          static_cast<int>(std::round(
              LerpDouble(kNoiseGateMinTransientHoldFrames,
                         kNoiseGateMaxTransientHoldFrames,
                         transient_sensitivity))),
          kNoiseGateMinTransientHoldFrames,
          kNoiseGateMaxTransientHoldFrames);
      transient_gate_hold_frames_ =
          (std::max)(transient_gate_hold_frames_, hold_frames);
    }
    if (strong_speech_frame && transient_gate_hold_frames_ > 0) {
      transient_gate_hold_frames_ = 0;
    }
    const bool transient_gate_active = transient_gate_hold_frames_ > 0;

    bool speech_protected = false;
    if (current_speech_frame && !transient_gate_active) {
      speech_hangover_frames_ = speech_grace_frames;
      speech_protected = true;
    } else if (speech_hangover_frames_ > 0 && !transient_gate_active) {
      speech_protected = true;
      speech_hangover_frames_--;
      gate_reason = kRnnoiseGateReasonSpeechGrace;
    } else if (speech_hangover_frames_ > 0) {
      speech_hangover_frames_--;
    }

    if (!speech_protected &&
        (vad_probability < vad_threshold || transient_gate_active)) {
      target_gate_gain = closed_gate_gain;
      gate_reason = transient_gate_active
          ? kRnnoiseGateReasonImpulseGate
          : kRnnoiseGateReasonVadGate;
      shared_state_->gated_frames.fetch_add(1);
    }
    if (transient_gate_hold_frames_ > 0) {
      transient_gate_hold_frames_--;
    }
    ApplySmoothedNoiseGate(target_gate_gain,
                           fast_close_enabled,
                           &mono_out_normalized_);
  } else {
    speech_hangover_frames_ = 0;
    transient_gate_hold_frames_ = 0;
    gate_gain_ = 1.0f;
  }

  if (!dry_fallback_frame && prototype_suppression_v2_mode) {
    output_rms = Rms(mono_out_normalized_);
    output_peak = PeakAbs(mono_out_normalized_);
    output_ratio = input_rms <= 0 ? 1.0 : output_rms / input_rms;
    output_max_delta = MaxDelta(mono_out_normalized_);
    const int transient_frames_before =
        shared_state_->prototype_transient_frames.load();
    const int stationary_frames_before =
        shared_state_->prototype_stationary_frames.load();
    const int prototype_adjustments =
        ApplySpeechProtectedPrototypeSuppressionStage(
            vad_probability,
            input_rms,
            input_peak,
            input_delta,
            output_rms,
            output_peak,
            output_max_delta,
            &mono_out_normalized_);
    if (prototype_adjustments > 0) {
      const bool transient_adjusted =
          shared_state_->prototype_transient_frames.load() >
          transient_frames_before;
      const bool stationary_adjusted =
          shared_state_->prototype_stationary_frames.load() >
          stationary_frames_before;
      if (transient_adjusted) {
        gate_reason = kRnnoiseGateReasonImpulseGate;
      } else if (stationary_adjusted) {
        gate_reason = kRnnoiseGateReasonVadGate;
      }
      output_rms = Rms(mono_out_normalized_);
      output_peak = PeakAbs(mono_out_normalized_);
      output_ratio = input_rms <= 0 ? 1.0 : output_rms / input_rms;
      output_max_delta = MaxDelta(mono_out_normalized_);
    }
  }
  shared_state_->last_gate_reason.store(gate_reason);
  shared_state_->last_gate_gain.store(target_gate_gain);
  shared_state_->speech_grace_remaining_frames.store(speech_hangover_frames_);
  const int limiter_adjustments =
      ApplyOutputSafetyLimiter(input_delta, &mono_out_normalized_);
  if (limiter_adjustments > 0) {
    shared_state_->output_limiter_samples.fetch_add(limiter_adjustments);
  }
  const double final_output_rms = Rms(mono_out_normalized_);
  const double final_output_peak = PeakAbs(mono_out_normalized_);
  const double final_output_ratio =
      input_rms <= 0 ? 1.0 : final_output_rms / input_rms;
  shared_state_->last_output_rms.store(
      std::isfinite(final_output_rms) ? final_output_rms : 0.0);
  shared_state_->last_output_ratio.store(
      std::isfinite(final_output_ratio) ? final_output_ratio : 1.0);
  shared_state_->last_output_peak.store(
      std::isfinite(final_output_peak) ? final_output_peak : 0.0);
  shared_state_->last_output_min.store(MinSample(mono_out_normalized_));
  shared_state_->last_output_max.store(MaxSample(mono_out_normalized_));
  shared_state_->last_output_max_delta.store(MaxDelta(mono_out_normalized_));
  const int output_non_finite = CountNonFiniteSamples(mono_out_normalized_);
  const int output_clipping = CountClippingSamples(mono_out_normalized_);
  if (output_non_finite > 0) {
    shared_state_->non_finite_samples.fetch_add(output_non_finite);
    shared_state_->last_gate_reason.store(kRnnoiseGateReasonBypass);
    shared_state_->bypass_frames.fetch_add(1);
    has_output_limiter_previous_sample_ = false;
    shared_state_->processing_applied.store(false);
    finish_timing();
    return;
  }
  if (output_clipping > 0) {
    shared_state_->output_clipping_samples.fetch_add(output_clipping);
    shared_state_->clipping_samples.fetch_add(output_clipping);
  }

  shared_state_->diagnostic_capture->RecordProcessedCallback(
      mono_in_normalized_,
      sample_rate_hz_,
      mono_process_input_,
      rnnoise_output_normalized_,
      mono_out_normalized_,
      sample_rate_hz_);

  shared_state_->processing_applied.store(true);

  mono_out_.resize(num_frames);
  for (int sample = 0; sample < num_frames; ++sample) {
    mono_out_[sample] = ClampToInputScale(
        mono_out_normalized_[sample] * input_scale_factor,
        input_scale_factor);
  }

  for (int channel = 0; channel < num_channels_; ++channel) {
    float* channel_data = buffer + (channel * num_frames);
    std::copy(mono_out_.begin(), mono_out_.end(), channel_data);
  }

  shared_state_->frames_processed.fetch_add(1);
  finish_timing();
}

void RnnoiseCaptureProcessor::Reset(int new_rate) {
  std::lock_guard<std::mutex> lock(mutex_);

  sample_rate_hz_ = new_rate;
  suspicious_output_streak_ = 0;
  suspicious_output_recovery_frames_ = 0;
  suspicious_transient_streak_ = 0;
  speech_hangover_frames_ = 0;
  transient_gate_hold_frames_ = 0;
  post_speech_residual_guard_frames_ = 0;
  vad_average_sample_count_ = 0;
  recent_vad_average_ = 0.0f;
  gate_gain_ = 1.0f;
  prototype_gain_ = 1.0f;
  prototype_transient_hold_frames_ = 0;
  prototype_speech_hold_frames_ = 0;
  prototype_noise_floor_rms_ = 0.0;
  prototype_noise_floor_frames_ = 0;
  ResetAudioPipeline();
  shared_state_->format_mismatch_detected.store(false);
  shared_state_->suspicious_output_detected.store(false);
  shared_state_->format_mismatch_reason.store(kRnnoiseFormatMismatchNone);
  shared_state_->sample_rate_hz.store(new_rate);
  shared_state_->expected_frames_per_10ms.store(new_rate / 100);
  shared_state_->last_resampler_mode.store(kRnnoiseResamplerModeNone);
  shared_state_->last_resampler_input_frames.store(0);
  shared_state_->last_resampler_output_frames.store(0);
  shared_state_->last_resampler_source_rate_hz.store(new_rate);
  shared_state_->last_resampler_target_rate_hz.store(new_rate);
  shared_state_->speech_grace_remaining_frames.store(0);
  shared_state_->last_gate_reason.store(kRnnoiseGateReasonPass);
  shared_state_->last_gate_gain.store(1.0);
  shared_state_->recent_vad_average.store(0.0);
  shared_state_->last_vad_probability.store(0.0);
  shared_state_->last_input_rms.store(0.0);
  shared_state_->last_output_rms.store(0.0);
  shared_state_->last_output_ratio.store(1.0);
  shared_state_->last_input_peak.store(0.0);
  shared_state_->last_output_peak.store(0.0);
  shared_state_->last_input_min.store(0.0);
  shared_state_->last_input_max.store(0.0);
  shared_state_->last_output_min.store(0.0);
  shared_state_->last_output_max.store(0.0);
  shared_state_->last_input_scale_factor.store(1.0);
  shared_state_->last_input_max_delta.store(0.0);
  shared_state_->last_output_max_delta.store(0.0);
  shared_state_->deepfilternet_runtime_available.store(false);
  shared_state_->deepfilternet_processing_applied.store(false);
  shared_state_->deepfilternet_frames_processed.store(0);
  shared_state_->deepfilternet_bypass_frames.store(0);
  shared_state_->deepfilternet_frame_length.store(0);
  shared_state_->deepfilternet_reason.store(
      kDeepFilterNetRuntimeReasonNotInitialized);
  shared_state_->deepfilternet_last_local_snr.store(0.0);
  shared_state_->deepfilternet_prewarm_pending_frames.store(0);
  shared_state_->deepfilternet_speech_protected_frames.store(0);
  shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
  shared_state_->deepfilternet_transient_suppressed_frames.store(0);
  shared_state_->deepfilternet_transient_adjusted_samples.store(0);
  shared_state_->deepfilternet_last_transient_gain.store(1.0);
  shared_state_->deepfilternet_hush_runtime_available.store(false);
  shared_state_->deepfilternet_hush_processing_applied.store(false);
  shared_state_->deepfilternet_hush_frames_processed.store(0);
  shared_state_->deepfilternet_hush_bypass_frames.store(0);
  shared_state_->deepfilternet_hush_frame_length.store(0);
  shared_state_->deepfilternet_hush_reason.store(
      kDeepFilterNetRuntimeReasonNotInitialized);
  shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
  shared_state_->deepfilternet_hush_recovery_frames.store(0);
  shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
  shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
  shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
  shared_state_->processing_applied.store(false);
  // Mirror Initialize(): a sample-rate change restarts the capture pipeline,
  // so the capture-gap/timing continuity counters must not survive it.
  shared_state_->capture_gap_events.store(0);
  shared_state_->last_callback_interval_ms.store(0.0);
  shared_state_->max_callback_interval_ms.store(0.0);
  shared_state_->frames_since_capture_resume.store(0);
  shared_state_->deepfilternet_gap_recoveries.store(0);
  ResetRnnoiseState();
  // Deliberately keep the DeepFilterNet/Hush models loaded across a
  // rate/stream reset: the C API has no state-clear separate from a full
  // model unload+reload, and reloading would stall audio again. Stale
  // spectral state at stream restart is masked by the delay-aligned resume
  // crossfade that ResetAudioPipeline() arms.
}

void RnnoiseCaptureProcessor::Release() {
  ResetRnnoiseState();
  if (deepfilternet_runtime_) {
    deepfilternet_runtime_->Reset();
  }
  if (hush_runtime_) {
    hush_runtime_->Reset();
  }
  shared_state_->released.store(true);
  delete this;
}

bool RnnoiseCaptureProcessor::EnsureRnnoiseState() {
  if (rnnoise_state_ != nullptr) {
    return true;
  }

  rnnoise_state_ = intergalactic_rnnoise_create();
  return rnnoise_state_ != nullptr;
}

void RnnoiseCaptureProcessor::ResetRnnoiseState() {
  if (rnnoise_state_ == nullptr) {
    return;
  }

  shared_state_->rnnoise_state_resets.fetch_add(1);
  intergalactic_rnnoise_destroy(rnnoise_state_);
  rnnoise_state_ = nullptr;
}

void RnnoiseCaptureProcessor::SetFormatMismatch(int reason_code,
                                                const char* log_reason) {
  shared_state_->format_mismatch_detected.store(true);
  shared_state_->format_mismatch_reason.store(reason_code);
  shared_state_->last_gate_reason.store(kRnnoiseGateReasonUnsupportedFormat);
  shared_state_->last_gate_gain.store(1.0);
  shared_state_->bypass_frames.fetch_add(1);
  LogFormatMismatchOnce(log_reason);
}

void RnnoiseCaptureProcessor::LogFormatMismatchOnce(const char* reason) {
  if (logged_format_mismatch_) {
    return;
  }

  logged_format_mismatch_ = true;

  std::ostringstream stream;
  stream << "[InterGalactic][RNNoise] " << reason << "\n";
#if defined(_WIN32)
  OutputDebugStringA(stream.str().c_str());
#else
  (void)stream;
#endif
}

float RnnoiseCaptureProcessor::ClampToUnit(float value) {
  return (std::clamp)(value, -1.0f, 1.0f);
}

float RnnoiseCaptureProcessor::ClampToPcm(float value) {
  return (std::clamp)(value, -kPcmScale, kPcmScale - 1.0f);
}

float RnnoiseCaptureProcessor::ClampToInputScale(float value,
                                                 float input_scale_factor) {
  if (input_scale_factor <= kNormalizedPeakCeiling) {
    return ClampToUnit(value);
  }

  return ClampToPcm(value);
}

float RnnoiseCaptureProcessor::DetectInputScaleFactor(
    const std::vector<float>& samples) {
  (void)samples;
  // WebRTC AudioBuffer stores capture samples as FloatS16 internally. Peak
  // detection misclassifies quiet PCM frames as normalized floats, which turns
  // tiny room-noise values into full-scale hook/RNNoise artifacts.
  return kPcmScale;
}

double RnnoiseCaptureProcessor::Rms(const std::vector<float>& samples) {
  if (samples.empty()) {
    return 0.0;
  }

  double sum_squares = 0.0;
  for (const float sample : samples) {
    if (!std::isfinite(sample)) {
      return std::numeric_limits<double>::infinity();
    }
    sum_squares += static_cast<double>(sample) * static_cast<double>(sample);
  }

  return std::sqrt(sum_squares / static_cast<double>(samples.size()));
}

double RnnoiseCaptureProcessor::MinSample(
    const std::vector<float>& samples) {
  if (samples.empty()) {
    return 0.0;
  }

  double min_sample = std::numeric_limits<double>::infinity();
  for (const float sample : samples) {
    if (!std::isfinite(sample)) {
      return -std::numeric_limits<double>::infinity();
    }
    min_sample =
        (std::min)(min_sample, static_cast<double>(sample));
  }
  return std::isfinite(min_sample) ? min_sample : 0.0;
}

double RnnoiseCaptureProcessor::MaxSample(
    const std::vector<float>& samples) {
  if (samples.empty()) {
    return 0.0;
  }

  double max_sample = -std::numeric_limits<double>::infinity();
  for (const float sample : samples) {
    if (!std::isfinite(sample)) {
      return std::numeric_limits<double>::infinity();
    }
    max_sample =
        (std::max)(max_sample, static_cast<double>(sample));
  }
  return std::isfinite(max_sample) ? max_sample : 0.0;
}

double RnnoiseCaptureProcessor::PeakAbs(const std::vector<float>& samples) {
  double peak = 0.0;
  for (const float sample : samples) {
    if (!std::isfinite(sample)) {
      return std::numeric_limits<double>::infinity();
    }
    peak = (std::max)(peak, std::abs(static_cast<double>(sample)));
  }

  return peak;
}

double RnnoiseCaptureProcessor::MaxDelta(const std::vector<float>& samples) {
  if (samples.size() < 2) {
    return 0.0;
  }

  double max_delta = 0.0;
  for (size_t index = 1; index < samples.size(); ++index) {
    if (!std::isfinite(samples[index]) ||
        !std::isfinite(samples[index - 1])) {
      return std::numeric_limits<double>::infinity();
    }
    max_delta = (std::max)(
        max_delta,
        std::abs(static_cast<double>(samples[index]) -
                 static_cast<double>(samples[index - 1])));
  }
  return max_delta;
}

int RnnoiseCaptureProcessor::CountClippingSamples(
    const std::vector<float>& samples) {
  int count = 0;
  for (const float sample : samples) {
    if (std::isfinite(sample) && std::abs(sample) >= 0.9995f) {
      count++;
    }
  }
  return count;
}

int RnnoiseCaptureProcessor::CountNonFiniteSamples(
    const std::vector<float>& samples) {
  int count = 0;
  for (const float sample : samples) {
    if (!std::isfinite(sample)) {
      count++;
    }
  }
  return count;
}

void RnnoiseCaptureProcessor::CopyScaled(const std::vector<float>& input,
                                         float scale,
                                         std::vector<float>* output) {
  output->resize(input.size());
  for (size_t index = 0; index < input.size(); ++index) {
    (*output)[index] = input[index] * scale;
  }
}

bool RnnoiseCaptureProcessor::HasNonFiniteSample(
    const std::vector<float>& samples) {
  return std::any_of(samples.begin(), samples.end(), [](float sample) {
    return !std::isfinite(sample);
  });
}

double RnnoiseCaptureProcessor::Sinc(double value) {
  if (std::abs(value) < 1e-8) {
    return 1.0;
  }

  const double scaled = kPi * value;
  return std::sin(scaled) / scaled;
}

double RnnoiseCaptureProcessor::HannWindow(double distance, double radius) {
  if (radius <= 0.0) {
    return 0.0;
  }

  const double normalized = std::abs(distance) / radius;
  if (normalized >= 1.0) {
    return 0.0;
  }

  return 0.5 + (0.5 * std::cos(kPi * normalized));
}

void RnnoiseCaptureProcessor::ApplySmoothedNoiseGate(
    float target_gain,
    bool fast_close_enabled,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty()) {
    gate_gain_ = target_gain;
    return;
  }

  const float start_gain = gate_gain_;
  if (fast_close_enabled && target_gain < start_gain) {
    const int sample_count = static_cast<int>(samples->size());
    const int ramp_samples = (std::clamp)(
        sample_rate_hz_ > 0
            ? (sample_rate_hz_ * kNoiseGateFastCloseRampMs) / 1000
            : sample_count,
        1,
        sample_count);
    for (int index = 0; index < sample_count; ++index) {
      float gain = target_gain;
      if (index < ramp_samples) {
        const float progress =
            static_cast<float>(index + 1) / static_cast<float>(ramp_samples);
        gain = start_gain + ((target_gain - start_gain) * progress);
      }
      (*samples)[index] *= gain;
    }
    gate_gain_ = target_gain;
    return;
  }

  const int sample_count = static_cast<int>(samples->size());
  for (int index = 0; index < sample_count; ++index) {
    const float progress =
        static_cast<float>(index + 1) / static_cast<float>(sample_count);
    const float gain =
        start_gain + ((target_gain - start_gain) * progress);
    (*samples)[index] *= gain;
  }
  gate_gain_ = target_gain;
}

void RnnoiseCaptureProcessor::ApplyDownsampleAntiAliasFilter(
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty()) {
    output_antialias_history_count_ = 0;
    output_antialias_history_.fill(0.0f);
    return;
  }

  rnnoise_output_antialias_.resize(samples->size());
  for (size_t index = 0; index < samples->size(); ++index) {
    const float sample = (*samples)[index];
    double sum = std::isfinite(sample) ? sample : 0.0;
    int count = 1;
    for (int history_index = 0;
         history_index < output_antialias_history_count_;
         ++history_index) {
      sum += output_antialias_history_[history_index];
      count++;
    }
    rnnoise_output_antialias_[index] =
        static_cast<float>(sum / static_cast<double>(count));

    if (output_antialias_history_count_ <
        static_cast<int>(output_antialias_history_.size())) {
      output_antialias_history_[output_antialias_history_count_] =
          std::isfinite(sample) ? sample : 0.0f;
      output_antialias_history_count_++;
    } else {
      for (size_t history_index = 1;
           history_index < output_antialias_history_.size();
           ++history_index) {
        output_antialias_history_[history_index - 1] =
            output_antialias_history_[history_index];
      }
      output_antialias_history_.back() =
          std::isfinite(sample) ? sample : 0.0f;
    }
  }

  *samples = rnnoise_output_antialias_;
}

int RnnoiseCaptureProcessor::ApplyNonSpeechBurstGuard(
    float vad_probability,
    double output_peak,
    double output_max_delta,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty() ||
      !std::isfinite(vad_probability) ||
      !std::isfinite(output_peak) ||
      !std::isfinite(output_max_delta) ||
      vad_probability >= kNonSpeechBurstVadCeiling ||
      (output_peak < kNonSpeechBurstPeakFloor &&
       output_max_delta < kNonSpeechBurstDeltaFloor)) {
    return 0;
  }

  int adjusted_samples = 0;
  // A soft ceiling alone can still click when a low-VAD frame jumps between
  // opposite rails. Anchor the burst guard to the last emitted sample so
  // non-speech frames ramp instead of stepping.
  float previous =
      has_output_limiter_previous_sample_ ? output_limiter_previous_sample_
                                          : 0.0f;
  for (float& sample : *samples) {
    if (!std::isfinite(sample)) {
      continue;
    }

    const float original = sample;
    float guarded = kNonSpeechBurstSoftCeiling *
        static_cast<float>(
            std::tanh(sample / kNonSpeechBurstSoftCeiling));
    guarded = (std::clamp)(guarded,
                           previous - kNonSpeechBurstMaxDelta,
                           previous + kNonSpeechBurstMaxDelta);
    sample = guarded;
    previous = guarded;
    if (std::abs(sample - original) > 0.000001f) {
      adjusted_samples++;
    }
  }

  return adjusted_samples;
}

int RnnoiseCaptureProcessor::ApplyPostSpeechResidualGuard(
    double input_rms,
    double output_rms,
    double output_peak,
    std::vector<float>* samples) {
  if (post_speech_residual_guard_frames_ <= 0 ||
      samples == nullptr ||
      samples->empty() ||
      !std::isfinite(input_rms) ||
      !std::isfinite(output_rms) ||
      !std::isfinite(output_peak) ||
      input_rms > kPostSpeechQuietInputRmsCeiling) {
    return 0;
  }

  const double residual_ratio =
      output_rms / (std::max)(input_rms, 0.0005);
  if ((output_rms < kPostSpeechResidualRmsFloor &&
       output_peak < kPostSpeechResidualPeakFloor) ||
      residual_ratio < kPostSpeechResidualRatioFloor) {
    return 0;
  }

  int adjusted_samples = 0;
  float previous =
      has_output_limiter_previous_sample_ ? output_limiter_previous_sample_
                                          : 0.0f;
  for (float& sample : *samples) {
    if (!std::isfinite(sample)) {
      continue;
    }

    const float original = sample;
    float guarded = kPostSpeechResidualSoftCeiling *
        static_cast<float>(
            std::tanh(sample / kPostSpeechResidualSoftCeiling));
    guarded = (std::clamp)(guarded,
                           previous - kPostSpeechResidualMaxDelta,
                           previous + kPostSpeechResidualMaxDelta);
    sample = guarded;
    previous = guarded;
    if (std::abs(sample - original) > 0.000001f) {
      adjusted_samples++;
    }
  }

  return adjusted_samples;
}

int RnnoiseCaptureProcessor::ApplyPrototypeSuppressionStage(
    float vad_probability,
    double input_rms,
    double input_peak,
    double input_delta,
    double output_rms,
    double output_peak,
    double output_max_delta,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty() ||
      !std::isfinite(vad_probability) ||
      !std::isfinite(input_rms) ||
      !std::isfinite(input_peak) ||
      !std::isfinite(input_delta) ||
      !std::isfinite(output_rms) ||
      !std::isfinite(output_peak) ||
      !std::isfinite(output_max_delta)) {
    prototype_gain_ = 1.0f;
    shared_state_->prototype_last_gain.store(1.0);
    return 0;
  }

  shared_state_->prototype_stage_frames.fetch_add(1);

  const double input_crest_factor =
      input_rms <= 0.0 ? 0.0 : input_peak / input_rms;
  const bool narrow_transient_evidence =
      input_rms <= kPrototypeTransientInputRmsCeiling &&
      input_peak >= kPrototypeTransientPeakFloor &&
      input_delta >= kPrototypeTransientDeltaFloor &&
      input_crest_factor >= kPrototypeTransientCrestFloor &&
      (output_peak >= kPrototypeTransientOutputPeakFloor ||
       output_max_delta >= kPrototypeTransientOutputDeltaFloor);
  const bool strong_speech_frame =
      vad_probability >= kPrototypeStrongSpeechProtectVadThreshold &&
      input_rms >= kPrototypeSpeechProtectInputRmsFloor;
  const bool protected_speech_frame =
      (vad_probability >= kPrototypeSpeechProtectVadThreshold &&
       input_rms >= kPrototypeSpeechProtectInputRmsFloor &&
       !narrow_transient_evidence) ||
      strong_speech_frame;
  if (protected_speech_frame) {
    if (strong_speech_frame) {
      prototype_transient_hold_frames_ = 0;
    } else if (prototype_transient_hold_frames_ > 0) {
      prototype_transient_hold_frames_--;
    }
    shared_state_->prototype_speech_protected_frames.fetch_add(1);
    prototype_gain_ = (std::min)(1.0f, prototype_gain_ + 0.20f);
    shared_state_->prototype_last_gain.store(prototype_gain_);
    return 0;
  }

  const bool noise_floor_candidate =
      vad_probability < kPrototypeNoiseVadCeiling &&
      input_rms >= kPrototypeStationaryInputRmsFloor &&
      input_rms <= kPrototypeStationaryInputRmsCeiling &&
      input_peak <= kPrototypeStationaryInputPeakCeiling &&
      input_delta <= kPrototypeStationaryInputDeltaCeiling;
  if (noise_floor_candidate) {
    if (prototype_noise_floor_frames_ == 0) {
      prototype_noise_floor_rms_ = input_rms;
    } else {
      prototype_noise_floor_rms_ =
          (prototype_noise_floor_rms_ *
           kPrototypeStationaryNoiseFloorAlpha) +
          (input_rms * (1.0 - kPrototypeStationaryNoiseFloorAlpha));
    }
    prototype_noise_floor_frames_ =
        (std::min)(prototype_noise_floor_frames_ + 1, 1000);
    shared_state_->prototype_noise_floor_rms.store(
        prototype_noise_floor_rms_);
  }

  const bool transient_candidate =
      narrow_transient_evidence &&
      vad_probability < kNoiseGateHarshTransientVadCeiling;
  if (transient_candidate) {
    prototype_transient_hold_frames_ =
        (std::max)(prototype_transient_hold_frames_,
                   kPrototypeTransientHoldFrames);
  }

  const bool transient_active = prototype_transient_hold_frames_ > 0;
  const bool floor_ready =
      prototype_noise_floor_frames_ >=
      kPrototypeStationaryNoiseFloorWarmupFrames;
  const bool stationary_candidate =
      !transient_active &&
      floor_ready &&
      noise_floor_candidate &&
      output_rms >= kPrototypeStationaryOutputRmsFloor &&
      output_peak <= kPrototypeStationaryOutputPeakCeiling &&
      output_max_delta <= kPrototypeStationaryOutputDeltaCeiling &&
      output_rms >=
          (prototype_noise_floor_rms_ *
           kPrototypeStationaryNoiseFloorRatioFloor);

  float target_gain = 1.0f;
  if (transient_active) {
    target_gain = kPrototypeTransientGain;
    shared_state_->prototype_transient_frames.fetch_add(1);
    prototype_transient_hold_frames_--;
  } else if (stationary_candidate) {
    target_gain = kPrototypeStationaryGain;
    shared_state_->prototype_stationary_frames.fetch_add(1);
  } else {
    prototype_gain_ = (std::min)(1.0f, prototype_gain_ + 0.12f);
    shared_state_->prototype_last_gain.store(prototype_gain_);
    return 0;
  }

  int adjusted_samples = 0;
  const float start_gain = Clamp01(prototype_gain_);
  float previous =
      has_output_limiter_previous_sample_ ? output_limiter_previous_sample_
                                          : 0.0f;
  const float frame_size = static_cast<float>(samples->size());
  for (size_t index = 0; index < samples->size(); ++index) {
    float& sample = (*samples)[index];
    if (!std::isfinite(sample)) {
      continue;
    }

    const float original = sample;
    const float progress =
        frame_size <= 1.0f
            ? 1.0f
            : static_cast<float>(index + 1) / frame_size;
    const float gain =
        start_gain + ((target_gain - start_gain) * progress);
    float adjusted = sample * gain;
    if (transient_active) {
      adjusted = kPrototypeTransientSoftCeiling *
          static_cast<float>(
              std::tanh(adjusted / kPrototypeTransientSoftCeiling));
      adjusted = (std::clamp)(adjusted,
                              previous - kPrototypeTransientMaxDelta,
                              previous + kPrototypeTransientMaxDelta);
      previous = adjusted;
    }
    sample = adjusted;
    if (std::abs(sample - original) > 0.000001f) {
      adjusted_samples++;
    }
  }

  prototype_gain_ = target_gain;
  shared_state_->prototype_last_gain.store(prototype_gain_);
  if (adjusted_samples > 0) {
    shared_state_->prototype_adjusted_samples.fetch_add(adjusted_samples);
  }
  return adjusted_samples;
}

int RnnoiseCaptureProcessor::ApplySpeechProtectedPrototypeSuppressionStage(
    float vad_probability,
    double input_rms,
    double input_peak,
    double input_delta,
    double output_rms,
    double output_peak,
    double output_max_delta,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty() ||
      !std::isfinite(vad_probability) ||
      !std::isfinite(input_rms) ||
      !std::isfinite(input_peak) ||
      !std::isfinite(input_delta) ||
      !std::isfinite(output_rms) ||
      !std::isfinite(output_peak) ||
      !std::isfinite(output_max_delta)) {
    prototype_gain_ = 1.0f;
    prototype_speech_hold_frames_ = 0;
    shared_state_->prototype_last_gain.store(1.0);
    return 0;
  }

  shared_state_->prototype_stage_frames.fetch_add(1);

  const double input_crest_factor =
      input_rms <= 0.0 ? 0.0 : input_peak / input_rms;
  const bool narrow_transient_evidence =
      input_rms <= kPrototypeV2TransientInputRmsCeiling &&
      input_peak >= kPrototypeV2TransientPeakFloor &&
      input_delta >= kPrototypeV2TransientDeltaFloor &&
      input_crest_factor >= kPrototypeV2TransientCrestFloor &&
      (output_peak >= kPrototypeV2TransientOutputPeakFloor ||
       output_max_delta >= kPrototypeV2TransientOutputDeltaFloor);
  double history_rms_min = std::numeric_limits<double>::infinity();
  double history_rms_max = 0.0;
  double history_peak_min = std::numeric_limits<double>::infinity();
  double history_peak_max = 0.0;
  double history_delta_min = std::numeric_limits<double>::infinity();
  double history_delta_max = 0.0;
  double history_rms_sum = 0.0;
  double history_peak_sum = 0.0;
  double history_delta_sum = 0.0;
  const int history_frames = input_metric_history_count_;
  for (int index = 0; index < history_frames; ++index) {
    const double frame_rms = input_rms_history_[index];
    const double frame_peak = input_peak_history_[index];
    const double frame_delta = input_delta_history_[index];
    history_rms_min = (std::min)(history_rms_min, frame_rms);
    history_rms_max = (std::max)(history_rms_max, frame_rms);
    history_peak_min = (std::min)(history_peak_min, frame_peak);
    history_peak_max = (std::max)(history_peak_max, frame_peak);
    history_delta_min = (std::min)(history_delta_min, frame_delta);
    history_delta_max = (std::max)(history_delta_max, frame_delta);
    history_rms_sum += frame_rms;
    history_peak_sum += frame_peak;
    history_delta_sum += frame_delta;
  }
  const double history_rms_avg =
      history_frames <= 0 ? input_rms : history_rms_sum / history_frames;
  const double history_peak_avg =
      history_frames <= 0 ? input_peak : history_peak_sum / history_frames;
  const double history_delta_avg =
      history_frames <= 0 ? input_delta : history_delta_sum / history_frames;
  const bool stable_stationary_history =
      history_frames >= kPrototypeV2StationaryHistoryFrames &&
      (history_rms_max - history_rms_min) <=
          (std::max)(kPrototypeV2StationaryRmsSpanFloor,
                     history_rms_avg *
                         kPrototypeV2StationaryRmsSpanRatio) &&
      (history_peak_max - history_peak_min) <=
          (std::max)(kPrototypeV2StationaryPeakSpanFloor,
                     history_peak_avg *
                         kPrototypeV2StationaryPeakSpanRatio) &&
      (history_delta_max - history_delta_min) <=
          (std::max)(kPrototypeV2StationaryDeltaSpanFloor,
                     history_delta_avg *
                         kPrototypeV2StationaryDeltaSpanRatio);
  const bool stationary_shape_candidate =
      !narrow_transient_evidence &&
      input_rms >= kPrototypeV2StationaryInputRmsFloor &&
      input_rms <= kPrototypeV2StationaryInputRmsCeiling &&
      input_peak <= kPrototypeV2StationaryInputPeakCeiling &&
      input_delta <= kPrototypeV2StationaryInputDeltaCeiling;
  const bool stationary_history_candidate =
      stationary_shape_candidate && stable_stationary_history;
  const bool speech_shaped_input =
      input_rms >= kPrototypeV2SpeechShapeInputRmsFloor &&
      input_peak >= kPrototypeV2SpeechShapePeakFloor &&
      input_delta >= kPrototypeV2SpeechShapeDeltaFloor &&
      input_crest_factor <= kPrototypeV2SpeechShapeCrestCeiling &&
      !narrow_transient_evidence &&
      !stationary_history_candidate;
  const bool strong_speech_frame =
      vad_probability >= kPrototypeV2StrongSpeechProtectVadThreshold &&
      input_rms >= kPrototypeV2SpeechProtectInputRmsFloor &&
      !narrow_transient_evidence &&
      !stationary_history_candidate;
  const bool protected_speech_frame =
      strong_speech_frame ||
      (input_rms >= kPrototypeV2SpeechProtectInputRmsFloor &&
       speech_shaped_input &&
       (vad_probability >= kPrototypeV2SpeechProtectVadThreshold ||
        recent_vad_average_ >= kPrototypeV2RecentSpeechProtectVadThreshold));
  if (protected_speech_frame) {
    prototype_speech_hold_frames_ =
        (std::max)(prototype_speech_hold_frames_,
                   kPrototypeV2SpeechHangoverFrames);
    prototype_transient_hold_frames_ = 0;
    shared_state_->prototype_speech_protected_frames.fetch_add(1);
    prototype_gain_ =
        (std::min)(1.0f, prototype_gain_ + kPrototypeV2ReleaseStep);
    shared_state_->prototype_last_gain.store(prototype_gain_);
    return 0;
  }

  if (prototype_speech_hold_frames_ > 0 &&
      !narrow_transient_evidence &&
      !stationary_history_candidate) {
    prototype_speech_hold_frames_--;
    prototype_transient_hold_frames_ = 0;
    shared_state_->prototype_speech_protected_frames.fetch_add(1);
    prototype_gain_ =
        (std::min)(1.0f, prototype_gain_ + kPrototypeV2ReleaseStep);
    shared_state_->prototype_last_gain.store(prototype_gain_);
    return 0;
  }

  const bool noise_vad_window =
      vad_probability < kPrototypeV2NoiseVadCeiling &&
      recent_vad_average_ < kPrototypeV2RecentNoiseVadCeiling;
  const bool noise_floor_candidate =
      stationary_shape_candidate &&
      (noise_vad_window || stationary_history_candidate);
  if (noise_floor_candidate) {
    if (prototype_noise_floor_frames_ == 0) {
      prototype_noise_floor_rms_ = input_rms;
    } else {
      prototype_noise_floor_rms_ =
          (prototype_noise_floor_rms_ *
           kPrototypeV2StationaryNoiseFloorAlpha) +
          (input_rms * (1.0 - kPrototypeV2StationaryNoiseFloorAlpha));
    }
    prototype_noise_floor_frames_ =
        (std::min)(prototype_noise_floor_frames_ + 1, 1000);
    shared_state_->prototype_noise_floor_rms.store(
        prototype_noise_floor_rms_);
  }

  const bool transient_candidate =
      narrow_transient_evidence &&
      (noise_vad_window ||
       (vad_probability < kPrototypeV2StrongSpeechProtectVadThreshold &&
        input_crest_factor >= kPrototypeV2SpeechShapeCrestCeiling));
  if (transient_candidate) {
    prototype_transient_hold_frames_ =
        (std::max)(prototype_transient_hold_frames_,
                   kPrototypeV2TransientHoldFrames);
  }

  const bool transient_active = prototype_transient_hold_frames_ > 0;
  const bool floor_ready =
      prototype_noise_floor_frames_ >=
      kPrototypeV2StationaryNoiseFloorWarmupFrames;
  const bool stationary_candidate =
      !transient_active &&
      floor_ready &&
      noise_floor_candidate &&
      output_rms >= kPrototypeV2StationaryOutputRmsFloor &&
      output_peak <= kPrototypeV2StationaryOutputPeakCeiling &&
      output_max_delta <= kPrototypeV2StationaryOutputDeltaCeiling &&
      output_rms >=
          (prototype_noise_floor_rms_ *
           kPrototypeV2StationaryNoiseFloorRatioFloor);

  float target_gain = 1.0f;
  if (transient_active) {
    target_gain = kPrototypeV2TransientGain;
    shared_state_->prototype_transient_frames.fetch_add(1);
    prototype_transient_hold_frames_--;
  } else if (stationary_candidate) {
    target_gain = kPrototypeV2StationaryGain;
    shared_state_->prototype_stationary_frames.fetch_add(1);
  } else {
    prototype_gain_ =
        (std::min)(1.0f, prototype_gain_ + kPrototypeV2ReleaseStep);
    shared_state_->prototype_last_gain.store(prototype_gain_);
    return 0;
  }

  int adjusted_samples = 0;
  const float start_gain = Clamp01(prototype_gain_);
  float previous =
      has_output_limiter_previous_sample_ ? output_limiter_previous_sample_
                                          : 0.0f;
  const float frame_size = static_cast<float>(samples->size());
  for (size_t index = 0; index < samples->size(); ++index) {
    float& sample = (*samples)[index];
    if (!std::isfinite(sample)) {
      continue;
    }

    const float original = sample;
    const float progress =
        frame_size <= 1.0f
            ? 1.0f
            : static_cast<float>(index + 1) / frame_size;
    const float gain =
        start_gain + ((target_gain - start_gain) * progress);
    float adjusted = sample * gain;
    if (transient_active) {
      adjusted = kPrototypeV2TransientSoftCeiling *
          static_cast<float>(
              std::tanh(adjusted / kPrototypeV2TransientSoftCeiling));
      adjusted = (std::clamp)(adjusted,
                              previous - kPrototypeV2TransientMaxDelta,
                              previous + kPrototypeV2TransientMaxDelta);
      previous = adjusted;
    }
    sample = adjusted;
    if (std::abs(sample - original) > 0.000001f) {
      adjusted_samples++;
    }
  }

  prototype_gain_ = target_gain;
  shared_state_->prototype_last_gain.store(prototype_gain_);
  if (adjusted_samples > 0) {
    shared_state_->prototype_adjusted_samples.fetch_add(adjusted_samples);
  }
  return adjusted_samples;
}

bool RnnoiseCaptureProcessor::ApplyDeepFilterNetSpeechProtection(
    const std::vector<float>& dry,
    double input_rms,
    double input_peak,
    double input_delta,
    double output_rms,
    double output_peak,
    double output_max_delta,
    float local_snr,
    std::vector<float>* samples) {
  if (samples == nullptr ||
      samples->empty() ||
      samples->size() != dry.size() ||
      !std::isfinite(input_rms) ||
      !std::isfinite(input_peak) ||
      !std::isfinite(input_delta) ||
      !std::isfinite(output_rms) ||
      !std::isfinite(output_peak) ||
      !std::isfinite(output_max_delta)) {
    deepfilternet_wet_mix_ = 1.0f;
    shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
    return false;
  }

  const double output_ratio =
      input_rms <= 0.0 ? 1.0 : output_rms / input_rms;
  const double input_crest_factor =
      input_rms <= 0.0 ? 0.0 : input_peak / input_rms;
  const bool speech_shaped_input =
      input_rms >= kDeepFilterNetSpeechProtectInputRmsFloor &&
      input_peak >= kDeepFilterNetSpeechProtectInputPeakFloor &&
      input_delta <= kDeepFilterNetSpeechProtectInputDeltaCeiling &&
      input_crest_factor <= kDeepFilterNetSpeechProtectCrestCeiling &&
      (local_snr >= kDeepFilterNetSpeechProtectLocalSnrFloor ||
       input_rms >= kDeepFilterNetSpeechProtectInputRmsCeiling);
  const bool heavily_attenuated =
      output_ratio < kDeepFilterNetSpeechProtectRatioCeiling &&
      output_rms < input_rms &&
      output_peak <= (input_peak * 1.10) &&
      output_max_delta <=
          (std::max)(input_delta * 1.15, input_delta + 0.015);

  if (!speech_shaped_input || !heavily_attenuated) {
    const bool release_blend_active = deepfilternet_wet_mix_ < 0.999f;
    RampWetMixWithState(samples, dry, 1.0f, &deepfilternet_wet_mix_);
    shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
    return release_blend_active;
  }

  const double attenuation_depth = (std::clamp)(
      (kDeepFilterNetSpeechProtectRatioCeiling - output_ratio) /
          (kDeepFilterNetSpeechProtectRatioCeiling -
           kDeepFilterNetSpeechProtectStrongRatioCeiling),
      0.0,
      1.0);
  const double loudness = (std::clamp)(
      (input_rms - kDeepFilterNetSpeechProtectInputRmsFloor) /
          (kDeepFilterNetSpeechProtectInputRmsCeiling -
           kDeepFilterNetSpeechProtectInputRmsFloor),
      0.0,
      1.0);
  const float target_wet_mix = LerpFloat(
      kDeepFilterNetSpeechProtectMaxWetMix,
      kDeepFilterNetSpeechProtectMinWetMix,
      static_cast<float>((std::max)(attenuation_depth, loudness)));
  RampWetMixWithState(
      samples,
      dry,
      (std::clamp)(target_wet_mix,
                   kDeepFilterNetSpeechProtectMinWetMix,
                   kDeepFilterNetSpeechProtectMaxWetMix),
      &deepfilternet_wet_mix_);
  shared_state_->deepfilternet_speech_protected_frames.fetch_add(1);
  shared_state_->deepfilternet_last_speech_protect_wet_mix.store(
      deepfilternet_wet_mix_);
  return true;
}

int RnnoiseCaptureProcessor::ApplyDeepFilterNetTransientSuppression(
    const std::vector<float>& dry,
    double input_rms,
    double input_peak,
    double input_delta,
    double output_rms,
    double output_peak,
    double output_max_delta,
    float local_snr,
    bool speech_protected_frame,
    std::vector<float>* samples) {
  if (!shared_state_->deepfilternet_transient_suppression_enabled.load()) {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
    return 0;
  }

  if (samples == nullptr ||
      samples->empty() ||
      samples->size() != dry.size() ||
      !std::isfinite(input_rms) ||
      !std::isfinite(input_peak) ||
      !std::isfinite(input_delta) ||
      !std::isfinite(output_rms) ||
      !std::isfinite(output_peak) ||
      !std::isfinite(output_max_delta) ||
      !std::isfinite(local_snr)) {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
    return 0;
  }

  const double input_crest_factor =
      input_rms <= 0.0 ? 0.0 : input_peak / input_rms;
  const double output_crest_factor =
      output_rms <= 0.0 ? 0.0 : output_peak / output_rms;
  const bool loud_speech_shape =
      input_rms >= kDeepFilterNetTransientSpeechMixedRmsFloor &&
      input_peak >= kDeepFilterNetTransientSpeechPeakFloor &&
      input_delta <= kDeepFilterNetTransientSpeechDeltaCeiling &&
      input_crest_factor <= kDeepFilterNetTransientSpeechCrestCeiling &&
      (local_snr >= kDeepFilterNetSpeechProtectLocalSnrFloor ||
       input_rms >= kDeepFilterNetSpeechProtectInputRmsCeiling);
  const bool transient_shape =
      input_rms >= kDeepFilterNetTransientInputRmsFloor &&
      input_rms <= kDeepFilterNetTransientInputRmsCeiling &&
      input_peak >= kDeepFilterNetTransientInputPeakFloor &&
      input_delta >= kDeepFilterNetTransientInputDeltaFloor &&
      input_crest_factor >= kDeepFilterNetTransientInputCrestFloor &&
      (output_peak >= kDeepFilterNetTransientOutputPeakFloor ||
       output_max_delta >= kDeepFilterNetTransientOutputDeltaFloor);
  const bool speech_mixed_transient_shape =
      input_rms >= kDeepFilterNetTransientSpeechRmsFloor &&
      input_peak >= kDeepFilterNetTransientSpeechProtectedPeakFloor &&
      input_delta >= kDeepFilterNetTransientSpeechProtectedInputDeltaFloor &&
      input_crest_factor >=
          kDeepFilterNetTransientSpeechProtectedCrestFloor &&
      output_peak >= kDeepFilterNetTransientSpeechProtectedPeakFloor &&
      output_max_delta >=
          kDeepFilterNetTransientSpeechProtectedDeltaFloor &&
      output_crest_factor >=
          kDeepFilterNetTransientSpeechProtectedCrestFloor;
  const bool speech_safe_transient =
      speech_protected_frame || speech_mixed_transient_shape;

  if ((loud_speech_shape && !speech_mixed_transient_shape) ||
      (!transient_shape && !speech_mixed_transient_shape)) {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
    return 0;
  }

  double output_delta_sum = 0.0;
  double dry_delta_sum = 0.0;
  int delta_count = 0;
  for (size_t index = 1; index < samples->size(); ++index) {
    const float previous = (*samples)[index - 1];
    const float current = (*samples)[index];
    const float dry_previous = dry[index - 1];
    const float dry_current = dry[index];
    if (!std::isfinite(previous) || !std::isfinite(current)) {
      continue;
    }
    if (std::isfinite(dry_previous) && std::isfinite(dry_current)) {
      dry_delta_sum +=
          std::abs(static_cast<double>(dry_current) -
                   static_cast<double>(dry_previous));
    }
    output_delta_sum +=
        std::abs(static_cast<double>(current) -
                 static_cast<double>(previous));
    delta_count++;
  }

  if (delta_count <= 0) {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
    return 0;
  }

  const double average_output_delta =
      output_delta_sum / static_cast<double>(delta_count);
  const double average_dry_delta =
      dry_delta_sum / static_cast<double>(delta_count);
  const double output_delta_floor =
      speech_safe_transient
          ? (std::max)(
                kDeepFilterNetTransientSpeechProtectedDeltaFloor,
                (std::max)(average_output_delta *
                               kDeepFilterNetTransientSpeechDeltaRatioFloor,
                           output_rms * 1.25))
          : (std::max)(
                kDeepFilterNetTransientOutputDeltaFloor,
                average_output_delta *
                    kDeepFilterNetTransientDeltaRatioFloor);
  const double output_peak_floor =
      speech_safe_transient
          ? kDeepFilterNetTransientSpeechProtectedPeakFloor
          : kDeepFilterNetTransientOutputPeakFloor;
  const double dry_delta_floor =
      speech_safe_transient
          ? kDeepFilterNetTransientSpeechProtectedInputDeltaFloor
          : (std::max)(kDeepFilterNetTransientInputDeltaFloor,
                       average_dry_delta *
                           kDeepFilterNetTransientDeltaRatioFloor);
  const double ratio_floor =
      speech_safe_transient
          ? kDeepFilterNetTransientSpeechDeltaRatioFloor
          : kDeepFilterNetTransientDeltaRatioFloor;

  struct BurstCenter {
    size_t index;
    double score;
  };
  std::vector<BurstCenter> centers;
  centers.reserve(kDeepFilterNetTransientMaxCentersPerFrame);
  auto too_close_to_existing_center = [&](size_t index) {
    for (const BurstCenter& center : centers) {
      if (std::abs(static_cast<int>(index) -
                   static_cast<int>(center.index)) <
          kDeepFilterNetTransientMinCenterSpacingSamples) {
        return true;
      }
    }
    return false;
  };

  for (size_t index = 1; index < samples->size(); ++index) {
    const float previous = (*samples)[index - 1];
    const float current = (*samples)[index];
    const float dry_previous = dry[index - 1];
    const float dry_current = dry[index];
    if (!std::isfinite(previous) || !std::isfinite(current) ||
        !std::isfinite(dry_previous) || !std::isfinite(dry_current)) {
      continue;
    }

    const double output_delta =
        std::abs(static_cast<double>(current) -
                 static_cast<double>(previous));
    const double dry_delta =
        std::abs(static_cast<double>(dry_current) -
                 static_cast<double>(dry_previous));
    const double center_peak =
        (std::max)(std::abs(static_cast<double>(current)),
                   std::abs(static_cast<double>(previous)));
    const double delta_ratio =
        output_delta /
        (std::max)(average_output_delta, 0.000001);
    if (output_delta < output_delta_floor ||
        center_peak < output_peak_floor ||
        dry_delta < dry_delta_floor ||
        delta_ratio < ratio_floor) {
      continue;
    }

    const double score = (output_delta * delta_ratio) +
                         (center_peak * 0.25) +
                         (dry_delta * 0.5);
    bool inserted = false;
    for (BurstCenter& center : centers) {
      if (std::abs(static_cast<int>(index) -
                   static_cast<int>(center.index)) <
          kDeepFilterNetTransientMinCenterSpacingSamples) {
        if (score > center.score) {
          center = BurstCenter{index, score};
        }
        inserted = true;
        break;
      }
    }
    if (inserted) {
      continue;
    }
    if (static_cast<int>(centers.size()) <
        kDeepFilterNetTransientMaxCentersPerFrame) {
      centers.push_back(BurstCenter{index, score});
      continue;
    }
    auto weakest = std::min_element(
        centers.begin(),
        centers.end(),
        [](const BurstCenter& left, const BurstCenter& right) {
          return left.score < right.score;
        });
    if (weakest != centers.end() && score > weakest->score &&
        !too_close_to_existing_center(index)) {
      *weakest = BurstCenter{index, score};
    }
  }

  if (centers.empty()) {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
    return 0;
  }

  int adjusted_samples = 0;
  float min_gain = 1.0f;
  const float target_min_gain =
      speech_safe_transient ? kDeepFilterNetTransientSpeechMinGain
                            : kDeepFilterNetTransientMinGain;
  for (size_t index = 0; index < samples->size(); ++index) {
    double window = 0.0;
    for (const BurstCenter& center : centers) {
      const double distance =
          std::abs(static_cast<double>(index) -
                   static_cast<double>(center.index));
      window = (std::max)(
          window,
          HannWindow(
              distance,
              static_cast<double>(
                  kDeepFilterNetTransientWindowRadiusSamples)));
    }
    if (window <= 0.0) {
      continue;
    }

    float& sample = (*samples)[index];
    if (!std::isfinite(sample)) {
      continue;
    }

    const float gain = static_cast<float>(
        1.0 - ((1.0 - target_min_gain) * window));
    const float original = sample;
    float adjusted = original * gain;
    if (!speech_safe_transient &&
        std::abs(adjusted) > kDeepFilterNetTransientSoftCeiling) {
      adjusted = kDeepFilterNetTransientSoftCeiling *
                 std::tanh(adjusted / kDeepFilterNetTransientSoftCeiling);
    }

    if (std::abs(adjusted - original) > 1e-6f) {
      sample = adjusted;
      adjusted_samples++;
      min_gain = (std::min)(min_gain, gain);
    }
  }

  if (adjusted_samples > 0) {
    shared_state_->deepfilternet_transient_suppressed_frames.fetch_add(1);
    shared_state_->deepfilternet_transient_adjusted_samples.fetch_add(
        adjusted_samples);
    shared_state_->deepfilternet_last_transient_gain.store(min_gain);
  } else {
    shared_state_->deepfilternet_last_transient_gain.store(1.0);
  }

  return adjusted_samples;
}

int RnnoiseCaptureProcessor::ApplyOutputSafetyLimiter(
    double input_max_delta,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty()) {
    has_output_limiter_previous_sample_ = false;
    output_limiter_previous_sample_ = 0.0f;
    return 0;
  }

  int adjusted_samples = 0;
  bool has_previous = has_output_limiter_previous_sample_;
  float previous = output_limiter_previous_sample_;
  float max_delta = kOutputLimiterMaxDelta;
  if (std::isfinite(input_max_delta) && input_max_delta > 0.0) {
    max_delta = (std::min)(
        kOutputLimiterMaxDelta,
        (std::max)(kOutputLimiterAdaptiveDeltaFloor,
                   static_cast<float>(
                       input_max_delta *
                       static_cast<double>(
                           kOutputLimiterInputDeltaMultiplier))));
  }
  for (float& sample : *samples) {
    if (!std::isfinite(sample)) {
      has_previous = false;
      previous = 0.0f;
      continue;
    }

    const float original = sample;
    float limited = sample;
    if (has_previous) {
      limited = (std::clamp)(
          limited,
          previous - max_delta,
          previous + max_delta);
    }
    limited = (std::clamp)(
        limited,
        -kOutputLimiterPeakCeiling,
        kOutputLimiterPeakCeiling);
    if (limited != original) {
      adjusted_samples++;
    }
    sample = limited;
    previous = limited;
    has_previous = true;
  }

  has_output_limiter_previous_sample_ = has_previous;
  output_limiter_previous_sample_ = previous;
  return adjusted_samples;
}

bool RnnoiseCaptureProcessor::ProcessCleanRnnoise(
    int num_frames,
    const std::vector<float>& mono_in_normalized,
    std::vector<float>* mono_out_normalized,
    float* vad_probability) {
  if (mono_out_normalized == nullptr || vad_probability == nullptr ||
      mono_in_normalized.empty()) {
    return false;
  }

  const int rnnoise_frame_size = intergalactic_rnnoise_frame_size();
  if (rnnoise_frame_size != kRnnoiseFrameSize) {
    SetFormatMismatch(kRnnoiseFormatMismatchUnsupportedRate,
                      "rnnoise frame size did not match 48 kHz/10 ms");
    return false;
  }

  const bool native_shape =
      sample_rate_hz_ == kRnnoiseSampleRateHz &&
      num_frames == rnnoise_frame_size;
  if (native_shape) {
    mono_process_input_ = mono_in_normalized;
    shared_state_->last_resampler_mode.store(kRnnoiseResamplerModeNone);
    shared_state_->last_resampler_input_frames.store(num_frames);
    shared_state_->last_resampler_output_frames.store(rnnoise_frame_size);
    shared_state_->last_resampler_source_rate_hz.store(sample_rate_hz_);
    shared_state_->last_resampler_target_rate_hz.store(kRnnoiseSampleRateHz);
  } else {
    capture_to_rnnoise_resampler_.Configure(
        sample_rate_hz_,
        kRnnoiseSampleRateHz);
    if (capture_to_rnnoise_resampler_.Append(mono_in_normalized)) {
      shared_state_->resampler_overruns.fetch_add(1);
    }
    const int produced = capture_to_rnnoise_resampler_.Produce(
        rnnoise_frame_size,
        &mono_process_input_);
    shared_state_->last_resampler_mode.store(
        kRnnoiseResamplerModeStatefulLinear);
    shared_state_->last_resampler_input_frames.store(num_frames);
    shared_state_->last_resampler_output_frames.store(produced);
    shared_state_->last_resampler_source_rate_hz.store(sample_rate_hz_);
    shared_state_->last_resampler_target_rate_hz.store(kRnnoiseSampleRateHz);
    if (produced != rnnoise_frame_size) {
      shared_state_->resampler_input_underruns.fetch_add(1);
      return false;
    }
    shared_state_->resampler_uses.fetch_add(1);
  }

  rnnoise_input_pcm_.resize(rnnoise_frame_size);
  mono_process_output_.resize(rnnoise_frame_size);
  for (int index = 0; index < rnnoise_frame_size; ++index) {
    rnnoise_input_pcm_[index] =
        ClampToPcm(mono_process_input_[index] * kPcmScale);
  }

  *vad_probability = intergalactic_rnnoise_process_frame_with_vad(
      rnnoise_state_,
      rnnoise_input_pcm_.data(),
      mono_process_output_.data());
  if (!std::isfinite(*vad_probability) || *vad_probability < 0.0f) {
    shared_state_->suspicious_output_detected.store(true);
    return false;
  }

  rnnoise_output_normalized_.resize(rnnoise_frame_size);
  for (int index = 0; index < rnnoise_frame_size; ++index) {
    rnnoise_output_normalized_[index] =
        ClampToUnit(mono_process_output_[index] / kPcmScale);
  }
  if (native_shape) {
    *mono_out_normalized = rnnoise_output_normalized_;
    return true;
  }

  const std::vector<float>* rnnoise_output_for_capture =
      &rnnoise_output_normalized_;
  if (sample_rate_hz_ < kRnnoiseSampleRateHz) {
    rnnoise_output_antialias_ = rnnoise_output_normalized_;
    ApplyDownsampleAntiAliasFilter(&rnnoise_output_antialias_);
    rnnoise_output_for_capture = &rnnoise_output_antialias_;
    shared_state_->output_antialias_uses.fetch_add(1);
  }

  rnnoise_to_capture_resampler_.Configure(
      kRnnoiseSampleRateHz,
      sample_rate_hz_);
  if (rnnoise_to_capture_resampler_.Append(*rnnoise_output_for_capture)) {
    shared_state_->resampler_overruns.fetch_add(1);
  }
  const int produced =
      rnnoise_to_capture_resampler_.Produce(num_frames, mono_out_normalized);
  if (produced != num_frames) {
    shared_state_->resampler_output_underruns.fetch_add(1);
    return false;
  }
  shared_state_->resampler_uses.fetch_add(1);
  shared_state_->last_resampler_output_frames.store(produced);
  return true;
}

bool RnnoiseCaptureProcessor::ProcessDeepFilterNet(
    int num_frames,
    const std::vector<float>& mono_in_normalized,
    std::vector<float>* mono_out_normalized,
    float* local_snr) {
  if (mono_out_normalized == nullptr || local_snr == nullptr ||
      mono_in_normalized.empty()) {
    shared_state_->deepfilternet_reason.store(
        kDeepFilterNetRuntimeReasonProcessFailed);
    shared_state_->deepfilternet_runtime_available.store(false);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }

  // Never load a model on the audio callback thread: df_create() extracts a
  // model archive and builds the inference graph. Adopt a runtime the plugin
  // (or replay harness) prewarmed off-thread, and fail open until one is
  // ready. A runtime that failed to load keeps reporting its reason until a
  // new prewarm replaces it.
  if (!deepfilternet_runtime_ &&
      shared_state_->prewarmed_deepfilternet_ready.load()) {
    std::unique_lock<std::mutex> prewarm_lock(shared_state_->prewarm_mutex,
                                              std::try_to_lock);
    if (prewarm_lock.owns_lock() &&
        shared_state_->prewarmed_deepfilternet != nullptr) {
      deepfilternet_runtime_ =
          std::move(shared_state_->prewarmed_deepfilternet);
      shared_state_->prewarmed_deepfilternet_ready.store(false);
    }
  }
  if (!deepfilternet_runtime_) {
    shared_state_->deepfilternet_prewarm_pending_frames.fetch_add(1);
    shared_state_->deepfilternet_reason.store(
        kDeepFilterNetRuntimeReasonNotInitialized);
    shared_state_->deepfilternet_runtime_available.store(false);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }
  if (sample_rate_hz_ != deepfilternet_runtime_->expected_sample_rate_hz()) {
    shared_state_->deepfilternet_reason.store(
        kDeepFilterNetRuntimeReasonUnsupportedRate);
    shared_state_->deepfilternet_frame_length.store(
        deepfilternet_runtime_->frame_length());
    shared_state_->deepfilternet_runtime_available.store(false);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }
  if (!deepfilternet_runtime_->ready()) {
    shared_state_->deepfilternet_reason.store(
        deepfilternet_runtime_->reason());
    shared_state_->deepfilternet_frame_length.store(
        deepfilternet_runtime_->frame_length());
    shared_state_->deepfilternet_runtime_available.store(false);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }

  shared_state_->deepfilternet_frame_length.store(
      deepfilternet_runtime_->frame_length());
  if (num_frames != deepfilternet_runtime_->frame_length()) {
    shared_state_->deepfilternet_reason.store(
        kDeepFilterNetRuntimeReasonFrameSizeMismatch);
    shared_state_->deepfilternet_runtime_available.store(true);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }

  if (!deepfilternet_runtime_->ProcessFrame(
          mono_in_normalized,
          mono_out_normalized,
          local_snr)) {
    shared_state_->deepfilternet_reason.store(
        deepfilternet_runtime_->reason());
    shared_state_->deepfilternet_runtime_available.store(false);
    shared_state_->deepfilternet_processing_applied.store(false);
    return false;
  }

  shared_state_->deepfilternet_reason.store(
      deepfilternet_runtime_->reason());
  shared_state_->deepfilternet_runtime_available.store(true);
  shared_state_->deepfilternet_processing_applied.store(true);
  shared_state_->deepfilternet_frames_processed.fetch_add(1);
  return true;
}

bool RnnoiseCaptureProcessor::ProcessDeepFilterNetHushSupport(
    int num_frames,
    const std::vector<float>& mono_in_normalized,
    std::vector<float>* mono_out_normalized,
    float* local_snr) {
  if (mono_out_normalized == nullptr || local_snr == nullptr ||
      mono_in_normalized.empty()) {
    shared_state_->deepfilternet_hush_reason.store(
        kDeepFilterNetRuntimeReasonProcessFailed);
    shared_state_->deepfilternet_hush_runtime_available.store(false);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  // Same off-thread contract as the main model: adopt a prewarmed Hush
  // runtime, never load one on the audio callback.
  if (!hush_runtime_ && shared_state_->prewarmed_hush_ready.load()) {
    std::unique_lock<std::mutex> prewarm_lock(shared_state_->prewarm_mutex,
                                              std::try_to_lock);
    if (prewarm_lock.owns_lock() &&
        shared_state_->prewarmed_hush != nullptr) {
      hush_runtime_ = std::move(shared_state_->prewarmed_hush);
      shared_state_->prewarmed_hush_ready.store(false);
    }
  }
  if (!hush_runtime_ || !hush_runtime_->ready()) {
    shared_state_->deepfilternet_hush_reason.store(
        hush_runtime_ ? hush_runtime_->reason()
                      : kDeepFilterNetRuntimeReasonNotInitialized);
    shared_state_->deepfilternet_hush_frame_length.store(
        hush_runtime_ ? hush_runtime_->frame_length() : 0);
    shared_state_->deepfilternet_hush_runtime_available.store(false);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  const int hush_frame_length = hush_runtime_->frame_length();
  shared_state_->deepfilternet_hush_frame_length.store(hush_frame_length);
  if (hush_frame_length <= 0) {
    shared_state_->deepfilternet_hush_reason.store(
        kDeepFilterNetRuntimeReasonFrameSizeMismatch);
    shared_state_->deepfilternet_hush_runtime_available.store(true);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  ResampleWindowedSinc(mono_in_normalized, hush_frame_length, &hush_input_);
  if (static_cast<int>(hush_input_.size()) != hush_frame_length ||
      HasNonFiniteSample(hush_input_)) {
    shared_state_->deepfilternet_hush_reason.store(
        kDeepFilterNetRuntimeReasonProcessFailed);
    shared_state_->deepfilternet_hush_runtime_available.store(true);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  if (!hush_runtime_->ProcessFrame(hush_input_, &hush_output_, local_snr)) {
    shared_state_->deepfilternet_hush_reason.store(hush_runtime_->reason());
    shared_state_->deepfilternet_hush_runtime_available.store(false);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  ResampleWindowedSinc(hush_output_, num_frames, &hush_output_for_capture_);
  if (static_cast<int>(hush_output_for_capture_.size()) != num_frames ||
      HasNonFiniteSample(hush_output_for_capture_)) {
    shared_state_->deepfilternet_hush_reason.store(
        kDeepFilterNetRuntimeReasonProcessFailed);
    shared_state_->deepfilternet_hush_runtime_available.store(true);
    shared_state_->deepfilternet_hush_processing_applied.store(false);
    shared_state_->deepfilternet_hush_bypass_frames.fetch_add(1);
    return false;
  }

  *mono_out_normalized = hush_output_for_capture_;
  shared_state_->deepfilternet_hush_reason.store(hush_runtime_->reason());
  shared_state_->deepfilternet_hush_runtime_available.store(true);
  shared_state_->deepfilternet_hush_processing_applied.store(true);
  shared_state_->deepfilternet_hush_last_local_snr.store(*local_snr);
  shared_state_->deepfilternet_hush_frames_processed.fetch_add(1);
  return true;
}

bool RnnoiseCaptureProcessor::ApplyDeepFilterNetHushGainRecovery(
    double pre_hush_rms,
    double pre_hush_peak,
    double hush_rms,
    double hush_peak,
    std::vector<float>* samples) {
  if (samples == nullptr || samples->empty()) {
    deepfilternet_hush_recovery_gain_ = 1.0f;
    shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
    shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
    shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
    return false;
  }

  const double safe_pre_rms =
      std::isfinite(pre_hush_rms) ? (std::max)(0.0, pre_hush_rms) : 0.0;
  const double safe_pre_peak =
      std::isfinite(pre_hush_peak) ? (std::max)(0.0, pre_hush_peak) : 0.0;
  const double safe_hush_rms =
      std::isfinite(hush_rms) ? (std::max)(0.0, hush_rms) : 0.0;
  const double safe_hush_peak =
      std::isfinite(hush_peak) ? (std::max)(0.0, hush_peak) : 0.0;
  float target_gain = 1.0f;
  const bool recoverable =
      safe_pre_rms >= kDeepFilterNetHushRecoveryInputRmsFloor &&
      safe_hush_rms >= kDeepFilterNetHushRecoveryOutputRmsFloor &&
      safe_hush_rms < safe_pre_rms * kDeepFilterNetHushRecoveryMinDropRatio;
  if (recoverable) {
    const double raw_gain = safe_pre_rms / safe_hush_rms;
    const double peak_ceiling = (std::min)(
        static_cast<double>(kDeepFilterNetHushRecoveryPeakCeiling),
        (std::max)(safe_pre_peak, safe_hush_peak));
    const double peak_limited_gain =
        safe_hush_peak > 0.0 ? peak_ceiling / safe_hush_peak : raw_gain;
    target_gain = (std::clamp)(
        static_cast<float>((std::min)(raw_gain, peak_limited_gain)),
        1.0f,
        kDeepFilterNetHushRecoveryMaxGain);
  }

  const float start_gain =
      std::isfinite(deepfilternet_hush_recovery_gain_)
          ? deepfilternet_hush_recovery_gain_
          : 1.0f;
  const int sample_count = static_cast<int>(samples->size());
  const int ramp_samples = (std::min)(sample_count, kWetMixRampSamples);
  const bool recovery_active = target_gain > 1.001f;
  const bool release_active = start_gain > 1.001f;
  if (recovery_active || release_active) {
    for (int index = 0; index < sample_count; ++index) {
      float sample = (*samples)[index];
      if (!std::isfinite(sample)) {
        (*samples)[index] = 0.0f;
        continue;
      }
      const float progress =
          ramp_samples <= 0
              ? 1.0f
              : (std::min)(1.0f,
                           static_cast<float>(index + 1) /
                               static_cast<float>(ramp_samples));
      const float gain =
          start_gain + ((target_gain - start_gain) * progress);
      (*samples)[index] = sample * gain;
    }
  }

  deepfilternet_hush_recovery_gain_ = target_gain;
  if (recovery_active) {
    shared_state_->deepfilternet_hush_recovery_frames.fetch_add(1);
  }
  shared_state_->deepfilternet_hush_last_recovery_gain.store(target_gain);
  shared_state_->deepfilternet_hush_last_input_rms.store(safe_pre_rms);
  shared_state_->deepfilternet_hush_last_output_rms.store(Rms(*samples));
  return recovery_active || release_active;
}

void RnnoiseCaptureProcessor::EnsureDryHistoryCapacity(int frame_length,
                                                       int capacity_frames) {
  if (frame_length <= 0 || capacity_frames <= 0) {
    return;
  }
  if (deepfilternet_dry_history_frame_length_ == frame_length &&
      deepfilternet_dry_history_capacity_frames_ == capacity_frames) {
    return;
  }
  deepfilternet_dry_history_.assign(
      static_cast<size_t>(frame_length) * capacity_frames, 0.0f);
  deepfilternet_dry_history_frame_length_ = frame_length;
  deepfilternet_dry_history_capacity_frames_ = capacity_frames;
  deepfilternet_dry_history_size_frames_ = 0;
  deepfilternet_dry_history_next_frame_ = 0;
}

void RnnoiseCaptureProcessor::PushDryHistoryFrame(
    const std::vector<float>& frame) {
  if (deepfilternet_dry_history_capacity_frames_ <= 0 ||
      static_cast<int>(frame.size()) !=
          deepfilternet_dry_history_frame_length_) {
    return;
  }
  std::copy(frame.begin(),
            frame.end(),
            deepfilternet_dry_history_.begin() +
                static_cast<size_t>(deepfilternet_dry_history_next_frame_) *
                    deepfilternet_dry_history_frame_length_);
  deepfilternet_dry_history_next_frame_ =
      (deepfilternet_dry_history_next_frame_ + 1) %
      deepfilternet_dry_history_capacity_frames_;
  deepfilternet_dry_history_size_frames_ = (std::min)(
      deepfilternet_dry_history_size_frames_ + 1,
      deepfilternet_dry_history_capacity_frames_);
}

bool RnnoiseCaptureProcessor::CopyDelayedDryFrame(
    int frames_back,
    int frame_length,
    std::vector<float>* out) const {
  out->assign(frame_length, 0.0f);
  if (frames_back <= 0 ||
      frame_length != deepfilternet_dry_history_frame_length_ ||
      frames_back > deepfilternet_dry_history_size_frames_) {
    return false;
  }
  int index = deepfilternet_dry_history_next_frame_ - frames_back;
  index %= deepfilternet_dry_history_capacity_frames_;
  if (index < 0) {
    index += deepfilternet_dry_history_capacity_frames_;
  }
  const auto begin = deepfilternet_dry_history_.begin() +
                     static_cast<size_t>(index) * frame_length;
  std::copy(begin, begin + frame_length, out->begin());
  return true;
}

void RnnoiseCaptureProcessor::ResetAudioPipeline() {
  wet_mix_ = 0.0f;
  deepfilternet_wet_mix_ = 1.0f;
  deepfilternet_hush_recovery_gain_ = 1.0f;
  std::fill(deepfilternet_dry_history_.begin(),
            deepfilternet_dry_history_.end(),
            0.0f);
  deepfilternet_dry_history_size_frames_ = 0;
  deepfilternet_dry_history_next_frame_ = 0;
  has_previous_pre_hush_metrics_ = false;
  previous_pre_hush_rms_ = 0.0;
  previous_pre_hush_peak_ = 0.0;
  shared_state_->deepfilternet_dry_delay_frames.store(0);
  // Force the next callback to be treated as a capture resume so DeepFilterNet
  // output crossfades in cleanly after a (re)initialization or rate change.
  has_last_callback_time_ = false;
  deepfilternet_gap_recovery_wet_mix_ = 1.0f;
  shared_state_->deepfilternet_last_speech_protect_wet_mix.store(1.0);
  shared_state_->deepfilternet_last_transient_gain.store(1.0);
  shared_state_->deepfilternet_hush_processing_applied.store(false);
  shared_state_->deepfilternet_hush_last_local_snr.store(0.0);
  shared_state_->deepfilternet_hush_last_recovery_gain.store(1.0);
  shared_state_->deepfilternet_hush_last_input_rms.store(0.0);
  shared_state_->deepfilternet_hush_last_output_rms.store(0.0);
  has_output_limiter_previous_sample_ = false;
  output_limiter_previous_sample_ = 0.0f;
  output_antialias_history_count_ = 0;
  output_antialias_history_.fill(0.0f);
  prototype_gain_ = 1.0f;
  prototype_transient_hold_frames_ = 0;
  prototype_speech_hold_frames_ = 0;
  prototype_noise_floor_rms_ = 0.0;
  prototype_noise_floor_frames_ = 0;
  input_metric_history_count_ = 0;
  input_metric_history_next_index_ = 0;
  input_rms_history_.fill(0.0);
  input_peak_history_.fill(0.0);
  input_delta_history_.fill(0.0);
  capture_to_rnnoise_resampler_.Configure(sample_rate_hz_, kRnnoiseSampleRateHz);
  capture_to_rnnoise_resampler_.Reset();
  rnnoise_to_capture_resampler_.Configure(kRnnoiseSampleRateHz, sample_rate_hz_);
  rnnoise_to_capture_resampler_.Reset();
  mono_in_.reserve(kRnnoiseFrameSize);
  mono_in_normalized_.reserve(kRnnoiseFrameSize);
  mono_process_input_.reserve(kRnnoiseFrameSize);
  mono_process_output_.reserve(kRnnoiseFrameSize);
  mono_out_.reserve(kRnnoiseFrameSize);
  mono_out_normalized_.reserve(kRnnoiseFrameSize);
  rnnoise_input_pcm_.reserve(kRnnoiseFrameSize);
  rnnoise_output_normalized_.reserve(kRnnoiseFrameSize);
  rnnoise_output_antialias_.reserve(kRnnoiseFrameSize);
  hush_input_.reserve(kRnnoiseFrameSize);
  hush_output_.reserve(kRnnoiseFrameSize);
  hush_output_for_capture_.reserve(kRnnoiseFrameSize);
  dry_rnnoise_diagnostic_.reserve(kRnnoiseFrameSize);
}

void RnnoiseCaptureProcessor::RecordDryDiagnosticCallback(
    const std::vector<float>& mono_in_normalized,
    int sample_rate_hz,
    int num_frames) {
  if (!shared_state_->diagnostic_capture->active()) {
    return;
  }

  if (sample_rate_hz == kRnnoiseSampleRateHz &&
      num_frames == kRnnoiseFrameSize) {
    dry_rnnoise_diagnostic_ = mono_in_normalized;
    shared_state_->last_resampler_mode.store(kRnnoiseResamplerModeNone);
    shared_state_->last_resampler_input_frames.store(num_frames);
    shared_state_->last_resampler_output_frames.store(kRnnoiseFrameSize);
    shared_state_->last_resampler_source_rate_hz.store(sample_rate_hz);
    shared_state_->last_resampler_target_rate_hz.store(kRnnoiseSampleRateHz);
  } else {
    // RNNoise-off/identity diagnostics should not synthesize a fake 48 kHz
    // RNNoise stage from a non-48 kHz callback. Record the real hook input and
    // final passthrough output only; clean RNNoise still exercises the real
    // stateful 48 kHz bridge when enabled.
    dry_rnnoise_diagnostic_.clear();
    shared_state_->last_resampler_mode.store(kRnnoiseResamplerModeNone);
    shared_state_->last_resampler_input_frames.store(num_frames);
    shared_state_->last_resampler_output_frames.store(0);
    shared_state_->last_resampler_source_rate_hz.store(sample_rate_hz);
    shared_state_->last_resampler_target_rate_hz.store(kRnnoiseSampleRateHz);
  }

  shared_state_->diagnostic_capture->RecordProcessedCallback(
      mono_in_normalized,
      sample_rate_hz,
      dry_rnnoise_diagnostic_,
      dry_rnnoise_diagnostic_,
      mono_in_normalized,
      sample_rate_hz);
}

void RnnoiseCaptureProcessor::RampWetMix(std::vector<float>* processed,
                                         const std::vector<float>& dry,
                                         float target_wet_mix) {
  RampWetMixWithState(processed, dry, target_wet_mix, &wet_mix_);
}

void RnnoiseCaptureProcessor::RampWetMixWithState(
    std::vector<float>* processed,
    const std::vector<float>& dry,
    float target_wet_mix,
    float* wet_mix_state) {
  if (processed == nullptr || processed->size() != dry.size()) {
    if (wet_mix_state != nullptr) {
      *wet_mix_state = target_wet_mix;
    }
    return;
  }

  const int sample_count = static_cast<int>(processed->size());
  const int ramp_samples = (std::min)(sample_count, kWetMixRampSamples);
  const float start_mix =
      wet_mix_state == nullptr ? target_wet_mix : *wet_mix_state;
  for (int index = 0; index < sample_count; ++index) {
    const float progress = ramp_samples <= 0
        ? 1.0f
        : (std::min)(1.0f,
                     static_cast<float>(index + 1) /
                         static_cast<float>(ramp_samples));
    const float mix =
        start_mix + ((target_wet_mix - start_mix) * progress);
    (*processed)[index] =
        (dry[index] * (1.0f - mix)) + ((*processed)[index] * mix);
  }
  if (wet_mix_state != nullptr) {
    *wet_mix_state = target_wet_mix;
  }
}

void RnnoiseCaptureProcessor::RecordCallbackTiming(double elapsed_ms,
                                                   double budget_ms) {
  if (!std::isfinite(elapsed_ms) || elapsed_ms < 0.0) {
    return;
  }

  const double previous_average =
      shared_state_->callback_average_processing_ms.load();
  const double next_average = previous_average <= 0.0
      ? elapsed_ms
      : ((previous_average * 0.95) + (elapsed_ms * 0.05));
  shared_state_->callback_average_processing_ms.store(next_average);

  double previous_max = shared_state_->callback_max_processing_ms.load();
  while (elapsed_ms > previous_max &&
         !shared_state_->callback_max_processing_ms.compare_exchange_weak(
             previous_max,
             elapsed_ms)) {}

  if (budget_ms > 0.0 &&
      elapsed_ms > (budget_ms * kCallbackBudgetWarningRatio)) {
    shared_state_->callback_budget_misses.fetch_add(1);
  }
}

void RnnoiseCaptureProcessor::ResampleWindowedSinc(
    const std::vector<float>& input,
    int output_frames,
    std::vector<float>* output) const {
  output->clear();
  if (input.empty() || output_frames <= 0) {
    return;
  }

  output->resize(output_frames);
  if (input.size() == 1 || output_frames == 1) {
    std::fill(output->begin(), output->end(), input.front());
    return;
  }

  const double input_frames = static_cast<double>(input.size());
  const double output_frames_double = static_cast<double>(output_frames);
  const double output_to_input = input_frames / output_frames_double;
  const double cutoff_scale =
      (std::min)(1.0, output_frames_double / input_frames);

  for (int output_index = 0; output_index < output_frames; ++output_index) {
    const double source_position =
        ((static_cast<double>(output_index) + 0.5) * output_to_input) - 0.5;
    const int center = static_cast<int>(std::floor(source_position));
    double weighted_sum = 0.0;
    double weight_sum = 0.0;

    for (int tap = center - kResamplerFilterRadius + 1;
         tap <= center + kResamplerFilterRadius;
         ++tap) {
      const double distance = source_position - static_cast<double>(tap);
      if (std::abs(distance) >=
          static_cast<double>(kResamplerFilterRadius)) {
        continue;
      }

      const int clamped_index = (std::clamp)(
          tap,
          0,
          static_cast<int>(input.size() - 1));
      const double weight =
          cutoff_scale *
          Sinc(distance * cutoff_scale) *
          HannWindow(distance, static_cast<double>(kResamplerFilterRadius));
      weighted_sum += static_cast<double>(input[clamped_index]) * weight;
      weight_sum += weight;
    }

    if (std::abs(weight_sum) < 1e-8) {
      const int nearest = (std::clamp)(
          static_cast<int>(std::round(source_position)),
          0,
          static_cast<int>(input.size() - 1));
      (*output)[output_index] = input[nearest];
    } else {
      (*output)[output_index] =
          static_cast<float>(weighted_sum / weight_sum);
    }
  }
}

}  // namespace intergalactic_noise_suppression
