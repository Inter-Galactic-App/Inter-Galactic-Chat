#include "rnnoise_capture_processor.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

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
constexpr double kDryFallbackInputPeakFloor = 0.985;
constexpr double kDryFallbackInputDeltaFloor = 0.35;
constexpr double kDryFallbackOutputRmsFloor = 0.05;
constexpr double kDryFallbackOutputRatioFloor = 3.0;
constexpr float kDryFallbackLowVadCeiling = 0.70f;
constexpr double kDryFallbackLowVadPeakFloor = 0.25;
constexpr double kDryFallbackLowVadDeltaFloor = 0.08;

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
    default:
      return "unknown";
  }
}

RnnoiseCaptureProcessor::RnnoiseCaptureProcessor(
    std::shared_ptr<ProcessorSharedState> shared_state)
    : shared_state_(std::move(shared_state)) {}

RnnoiseCaptureProcessor::~RnnoiseCaptureProcessor() {
  ResetRnnoiseState();
}

void RnnoiseCaptureProcessor::Initialize(int sample_rate_hz, int num_channels) {
  std::lock_guard<std::mutex> lock(mutex_);

  sample_rate_hz_ = sample_rate_hz;
  num_channels_ = num_channels;
  logged_format_mismatch_ = false;
  suspicious_output_streak_ = 0;
  suspicious_output_recovery_frames_ = 0;
  speech_hangover_frames_ = 0;
  transient_gate_hold_frames_ = 0;
  post_speech_residual_guard_frames_ = 0;
  vad_average_sample_count_ = 0;
  recent_vad_average_ = 0.0f;
  gate_gain_ = 1.0f;
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
  shared_state_->processing_applied.store(false);
  shared_state_->callback_average_processing_ms.store(0.0);
  shared_state_->callback_max_processing_ms.store(0.0);
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

  shared_state_->last_num_bands.store(num_bands);
  shared_state_->last_num_frames.store(num_frames);
  shared_state_->last_buffer_size.store(buffer_size);

  const int pipeline_mode = shared_state_->pipeline_mode.load();
  const bool identity_mode =
      pipeline_mode == kRnnoisePipelineModeIdentity;
  const bool processing_enabled =
      shared_state_->enabled_requested.load() &&
      pipeline_mode != kRnnoisePipelineModeOff;
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

  if (processing_enabled && !identity_mode && !EnsureRnnoiseState()) {
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
  const bool dry_fallback_frame =
      amplified_residual ||
      low_vad_output_burst;
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

  if (!dry_fallback_frame &&
      pipeline_mode == kRnnoisePipelineModeCleanRnnoise) {
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
  shared_state_->last_output_max_delta.store(
      std::isfinite(output_max_delta) ? output_max_delta : 0.0);

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
      pipeline_mode == kRnnoisePipelineModeTunedGate) {
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
  speech_hangover_frames_ = 0;
  transient_gate_hold_frames_ = 0;
  post_speech_residual_guard_frames_ = 0;
  vad_average_sample_count_ = 0;
  recent_vad_average_ = 0.0f;
  gate_gain_ = 1.0f;
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
  shared_state_->processing_applied.store(false);
  ResetRnnoiseState();
}

void RnnoiseCaptureProcessor::Release() {
  ResetRnnoiseState();
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
  OutputDebugStringA(stream.str().c_str());
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

void RnnoiseCaptureProcessor::ResetAudioPipeline() {
  wet_mix_ = 0.0f;
  has_output_limiter_previous_sample_ = false;
  output_limiter_previous_sample_ = 0.0f;
  output_antialias_history_count_ = 0;
  output_antialias_history_.fill(0.0f);
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
  if (processed == nullptr || processed->size() != dry.size()) {
    wet_mix_ = target_wet_mix;
    return;
  }

  const int sample_count = static_cast<int>(processed->size());
  const int ramp_samples = (std::min)(sample_count, kWetMixRampSamples);
  const float start_mix = wet_mix_;
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
  wet_mix_ = target_wet_mix;
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
