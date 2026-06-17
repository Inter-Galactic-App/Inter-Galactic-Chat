#ifndef INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_

#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <rtc_audio_processing.h>

#include "rnnoise_wrapper.h"

namespace intergalactic_noise_suppression {

enum RnnoiseGateReason {
  kRnnoiseGateReasonPass = 0,
  kRnnoiseGateReasonVadGate = 1,
  kRnnoiseGateReasonImpulseGate = 2,
  kRnnoiseGateReasonSpeechGrace = 3,
  kRnnoiseGateReasonBypass = 4,
  kRnnoiseGateReasonUnsupportedFormat = 5,
};

enum RnnoiseFormatMismatchReason {
  kRnnoiseFormatMismatchNone = 0,
  kRnnoiseFormatMismatchInvalidBuffer = 1,
  kRnnoiseFormatMismatchSplitBands = 2,
  kRnnoiseFormatMismatchFrameCount = 3,
  kRnnoiseFormatMismatchBufferSize = 4,
  kRnnoiseFormatMismatchUnsupportedRate = 5,
};

enum RnnoiseResamplerMode {
  kRnnoiseResamplerModeNone = 0,
  kRnnoiseResamplerModeWindowedSinc = 1,
  kRnnoiseResamplerModeStatefulLinear = 2,
};

enum RnnoisePipelineMode {
  kRnnoisePipelineModeOff = 0,
  kRnnoisePipelineModeCleanRnnoise = 1,
  kRnnoisePipelineModeTunedGate = 2,
  kRnnoisePipelineModeIdentity = 3,
};

enum RnnoiseDiagnosticStageMask {
  kRnnoiseDiagnosticStageRawInput = 1 << 0,
  kRnnoiseDiagnosticStageRnnoiseInput = 1 << 1,
  kRnnoiseDiagnosticStageRnnoiseOutput = 1 << 2,
  kRnnoiseDiagnosticStageFinalOutput = 1 << 3,
  kRnnoiseDiagnosticStageAll =
      kRnnoiseDiagnosticStageRawInput |
      kRnnoiseDiagnosticStageRnnoiseInput |
      kRnnoiseDiagnosticStageRnnoiseOutput |
      kRnnoiseDiagnosticStageFinalOutput,
};

const char* RnnoiseGateReasonToString(int reason);
const char* RnnoiseFormatMismatchReasonToString(int reason);
const char* RnnoiseResamplerModeToString(int mode);
const char* RnnoisePipelineModeToString(int mode);

class DiagnosticCapture {
 public:
  bool Start(const std::string& directory, int duration_ms, int stage_mask);
  bool Stop();
  bool RecordRawInput(const std::vector<float>& samples, int sample_rate_hz);
  bool RecordRnnoiseInput(const std::vector<float>& samples);
  bool RecordRnnoiseOutput(const std::vector<float>& samples);
  bool RecordFinalOutput(const std::vector<float>& samples, int sample_rate_hz);
  bool RecordProcessedCallback(const std::vector<float>& raw_input,
                               int raw_sample_rate_hz,
                               const std::vector<float>& rnnoise_input,
                               const std::vector<float>& rnnoise_output,
                               const std::vector<float>& final_output,
                               int final_sample_rate_hz);

  bool active() const { return active_.load(); }
  int captured_frames() const { return captured_frames_.load(); }
  int dropped_frames() const { return dropped_frames_.load(); }
  int written_files() const { return written_files_.load(); }
  const std::string& last_error() const { return last_error_; }

 private:
  struct StageBuffer {
    std::vector<float> samples;
    int sample_rate_hz = 0;
    int write_index = 0;
    int max_write_samples = 0;
    bool enabled = false;
  };

  bool RecordStage(StageBuffer* stage,
                   const std::vector<float>& samples,
                   int sample_rate_hz);
  bool RecordStageLocked(StageBuffer* stage,
                         const std::vector<float>& samples,
                         int sample_rate_hz);
  bool AllEnabledStagesFullLocked() const;
  bool WriteStageLocked(const StageBuffer& stage,
                        const std::string& file_name);
  static bool WriteWavFile(const std::string& path,
                           const std::vector<float>& samples,
                           int sample_count,
                           int sample_rate_hz);

  mutable std::mutex mutex_;
  std::atomic<bool> active_{false};
  std::atomic<int> captured_frames_{0};
  std::atomic<int> dropped_frames_{0};
  std::atomic<int> written_files_{0};
  std::string directory_;
  std::string last_error_;
  int stage_mask_ = kRnnoiseDiagnosticStageAll;
  int max_samples_48k_ = 0;
  StageBuffer raw_input_;
  StageBuffer rnnoise_input_;
  StageBuffer rnnoise_output_;
  StageBuffer final_output_;
};

class StreamingLinearResampler {
 public:
  void Configure(int input_rate_hz, int output_rate_hz);
  void Reset();
  bool Append(const std::vector<float>& samples);
  int Produce(int output_frames, std::vector<float>* output);
  int queued_input_samples() const;

 private:
  void CompactQueue();

  int input_rate_hz_ = 0;
  int output_rate_hz_ = 0;
  double source_position_ = 0.0;
  double source_step_ = 1.0;
  std::vector<float> input_queue_;
};

struct ProcessorSharedState {
  std::atomic<bool> enabled_requested{false};
  std::atomic<bool> released{false};
  std::atomic<bool> format_mismatch_detected{false};
  std::atomic<bool> suspicious_output_detected{false};
  std::atomic<int> format_mismatch_reason{
      kRnnoiseFormatMismatchNone};
  std::atomic<int> sample_rate_hz{0};
  std::atomic<int> num_channels{0};
  std::atomic<int> expected_frames_per_10ms{0};
  std::atomic<int> last_num_bands{0};
  std::atomic<int> last_num_frames{0};
  std::atomic<int> last_buffer_size{0};
  std::atomic<int> frames_processed{0};
  std::atomic<int> bypass_frames{0};
  std::atomic<int> gated_frames{0};
  std::atomic<int> resampler_uses{0};
  std::atomic<int> resampler_input_underruns{0};
  std::atomic<int> resampler_output_underruns{0};
  std::atomic<int> resampler_overruns{0};
  std::atomic<int> last_resampler_mode{kRnnoiseResamplerModeNone};
  std::atomic<int> last_resampler_input_frames{0};
  std::atomic<int> last_resampler_output_frames{0};
  std::atomic<int> last_resampler_source_rate_hz{0};
  std::atomic<int> last_resampler_target_rate_hz{0};
  std::atomic<int> vad_low_frames{0};
  std::atomic<int> vad_mid_frames{0};
  std::atomic<int> vad_high_frames{0};
  std::atomic<int> speech_grace_remaining_frames{0};
  std::atomic<int> reference_speech_grace_frames{20};
  std::atomic<double> noise_gate_closed_gain{0.03};
  std::atomic<double> transient_sensitivity{0.0};
  std::atomic<bool> fast_close_enabled{false};
  std::atomic<int> last_gate_reason{kRnnoiseGateReasonPass};
  std::atomic<double> last_input_scale_factor{1.0};
  std::atomic<double> last_vad_probability{0.0};
  std::atomic<double> recent_vad_average{0.0};
  std::atomic<double> reference_vad_threshold{0.90};
  std::atomic<double> last_gate_gain{1.0};
  std::atomic<double> last_input_rms{0.0};
  std::atomic<double> last_output_rms{0.0};
  std::atomic<double> last_output_ratio{1.0};
  std::atomic<double> last_input_min{0.0};
  std::atomic<double> last_input_max{0.0};
  std::atomic<double> last_output_min{0.0};
  std::atomic<double> last_output_max{0.0};
  std::atomic<double> last_input_peak{0.0};
  std::atomic<double> last_output_peak{0.0};
  std::atomic<double> last_input_max_delta{0.0};
  std::atomic<double> last_output_max_delta{0.0};
  std::atomic<int> clipping_samples{0};
  std::atomic<int> input_clipping_samples{0};
  std::atomic<int> output_clipping_samples{0};
  std::atomic<int> output_limiter_samples{0};
  std::atomic<int> output_antialias_uses{0};
  std::atomic<int> non_finite_samples{0};
  std::atomic<double> callback_average_processing_ms{0.0};
  std::atomic<double> callback_max_processing_ms{0.0};
  std::atomic<int> callback_budget_misses{0};
  std::atomic<int> rnnoise_state_resets{0};
  std::atomic<bool> processing_applied{false};
  std::atomic<int> identity_frames{0};
  std::atomic<int> pipeline_mode{kRnnoisePipelineModeCleanRnnoise};
  std::shared_ptr<DiagnosticCapture> diagnostic_capture{
      std::make_shared<DiagnosticCapture>()};
};

class RnnoiseCaptureProcessor
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  explicit RnnoiseCaptureProcessor(
      std::shared_ptr<ProcessorSharedState> shared_state);
  ~RnnoiseCaptureProcessor() override;

  void Initialize(int sample_rate_hz, int num_channels) override;
  void Process(int num_bands,
               int num_frames,
               int buffer_size,
               float* buffer) override;
  void Reset(int new_rate) override;
  void Release() override;

 private:
  bool EnsureRnnoiseState();
  void ResetRnnoiseState();
  void SetFormatMismatch(int reason_code, const char* log_reason);
  void LogFormatMismatchOnce(const char* reason);
  static float ClampToUnit(float value);
  static float ClampToPcm(float value);
  static float ClampToInputScale(float value, float input_scale_factor);
  static float DetectInputScaleFactor(const std::vector<float>& samples);
  static double Rms(const std::vector<float>& samples);
  static double MinSample(const std::vector<float>& samples);
  static double MaxSample(const std::vector<float>& samples);
  static double PeakAbs(const std::vector<float>& samples);
  static double MaxDelta(const std::vector<float>& samples);
  static int CountClippingSamples(const std::vector<float>& samples);
  static int CountNonFiniteSamples(const std::vector<float>& samples);
  static void CopyScaled(const std::vector<float>& input,
                         float scale,
                         std::vector<float>* output);
  static bool HasNonFiniteSample(const std::vector<float>& samples);
  static double Sinc(double value);
  static double HannWindow(double distance, double radius);
  void ApplySmoothedNoiseGate(float target_gain,
                              bool fast_close_enabled,
                              std::vector<float>* samples);
  void ApplyDownsampleAntiAliasFilter(std::vector<float>* samples);
  int ApplyNonSpeechBurstGuard(float vad_probability,
                               double output_peak,
                               double output_max_delta,
                               std::vector<float>* samples);
  int ApplyPostSpeechResidualGuard(double input_rms,
                                   double output_rms,
                                   double output_peak,
                                   std::vector<float>* samples);
  int ApplyOutputSafetyLimiter(double input_max_delta,
                               std::vector<float>* samples);
  bool ProcessCleanRnnoise(int num_frames,
                           const std::vector<float>& mono_in_normalized,
                           std::vector<float>* mono_out_normalized,
                           float* vad_probability);
  void ResetAudioPipeline();
  void RecordDryDiagnosticCallback(
      const std::vector<float>& mono_in_normalized,
      int sample_rate_hz,
      int num_frames);
  void RampWetMix(std::vector<float>* processed,
                  const std::vector<float>& dry,
                  float target_wet_mix);
  void RecordCallbackTiming(double elapsed_ms, double budget_ms);
  void ResampleWindowedSinc(const std::vector<float>& input,
                            int output_frames,
                            std::vector<float>* output) const;

  std::shared_ptr<ProcessorSharedState> shared_state_;
  IntergalacticRnnoiseState* rnnoise_state_ = nullptr;
  int sample_rate_hz_ = 0;
  int num_channels_ = 0;
  bool logged_format_mismatch_ = false;
  int suspicious_output_streak_ = 0;
  int suspicious_output_recovery_frames_ = 0;
  int speech_hangover_frames_ = 0;
  int transient_gate_hold_frames_ = 0;
  int post_speech_residual_guard_frames_ = 0;
  int vad_average_sample_count_ = 0;
  float recent_vad_average_ = 0.0f;
  float gate_gain_ = 1.0f;
  float wet_mix_ = 0.0f;
  bool has_output_limiter_previous_sample_ = false;
  float output_limiter_previous_sample_ = 0.0f;
  std::array<float, 8> output_antialias_history_{};
  int output_antialias_history_count_ = 0;
  std::mutex mutex_;
  std::vector<float> mono_in_;
  std::vector<float> mono_in_normalized_;
  std::vector<float> mono_process_input_;
  std::vector<float> mono_process_output_;
  std::vector<float> mono_out_;
  std::vector<float> mono_out_normalized_;
  std::vector<float> rnnoise_input_pcm_;
  std::vector<float> rnnoise_output_normalized_;
  std::vector<float> rnnoise_output_antialias_;
  std::vector<float> rnnoise_input_fifo_;
  std::vector<float> dry_rnnoise_diagnostic_;
  StreamingLinearResampler capture_to_rnnoise_resampler_;
  StreamingLinearResampler rnnoise_to_capture_resampler_;
};

}  // namespace intergalactic_noise_suppression

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_
