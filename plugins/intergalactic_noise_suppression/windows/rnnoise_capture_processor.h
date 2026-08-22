#ifndef INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <rtc_audio_processing.h>

#include "deep_filter_net_runtime.h"
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
  kRnnoisePipelineModePrototypeSuppression = 4,
  kRnnoisePipelineModePrototypeSuppressionV2 = 5,
  kRnnoisePipelineModeDeepFilterNet = 6,
};

enum RnnoiseDiagnosticStageMask {
  kRnnoiseDiagnosticStageRawInput = 1 << 0,
  kRnnoiseDiagnosticStageRnnoiseInput = 1 << 1,
  kRnnoiseDiagnosticStageRnnoiseOutput = 1 << 2,
  kRnnoiseDiagnosticStageFinalOutput = 1 << 3,
  kRnnoiseDiagnosticStageDeepFilterNetOutput = 1 << 4,
  kRnnoiseDiagnosticStageSpeechProtectOutput = 1 << 5,
  kRnnoiseDiagnosticStageTransientGuardOutput = 1 << 6,
  kRnnoiseDiagnosticStageHushInput16k = 1 << 7,
  kRnnoiseDiagnosticStageHushOutput16k = 1 << 8,
  kRnnoiseDiagnosticStageHushOutput = 1 << 9,
  kRnnoiseDiagnosticStageAll =
      kRnnoiseDiagnosticStageRawInput |
      kRnnoiseDiagnosticStageRnnoiseInput |
      kRnnoiseDiagnosticStageRnnoiseOutput |
      kRnnoiseDiagnosticStageFinalOutput |
      kRnnoiseDiagnosticStageDeepFilterNetOutput |
      kRnnoiseDiagnosticStageSpeechProtectOutput |
      kRnnoiseDiagnosticStageTransientGuardOutput |
      kRnnoiseDiagnosticStageHushInput16k |
      kRnnoiseDiagnosticStageHushOutput16k |
      kRnnoiseDiagnosticStageHushOutput,
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
  bool RecordEnhancedProcessedCallback(
      const std::vector<float>& raw_input,
      int raw_sample_rate_hz,
      const std::vector<float>& deepfilternet_output,
      const std::vector<float>& speech_protect_output,
      const std::vector<float>& transient_guard_output,
      const std::vector<float>& hush_input_16k,
      const std::vector<float>& hush_output_16k,
      const std::vector<float>& hush_output,
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
  StageBuffer deepfilternet_output_;
  StageBuffer speech_protect_output_;
  StageBuffer transient_guard_output_;
  StageBuffer hush_input_16k_;
  StageBuffer hush_output_16k_;
  StageBuffer hush_output_;
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
  // Capture-callback continuity diagnostics. A large gap between consecutive
  // capture callbacks (mute/unmute, participant churn, renegotiation, or CPU
  // starvation in large calls) leaves stale spectral state in the stateful
  // DeepFilterNet lookahead, which is heard as brief "layered/distorted" audio
  // plus an end-of-recovery pop. These counters make that observable.
  std::atomic<int> capture_gap_events{0};
  std::atomic<double> last_callback_interval_ms{0.0};
  std::atomic<double> max_callback_interval_ms{0.0};
  std::atomic<int> frames_since_capture_resume{0};
  std::atomic<int> deepfilternet_gap_recoveries{0};
  std::atomic<bool> processing_applied{false};
  std::atomic<int> identity_frames{0};
  std::atomic<int> pipeline_mode{kRnnoisePipelineModeCleanRnnoise};
  std::atomic<int> prototype_stage_frames{0};
  std::atomic<int> prototype_transient_frames{0};
  std::atomic<int> prototype_stationary_frames{0};
  std::atomic<int> prototype_speech_protected_frames{0};
  std::atomic<int> prototype_adjusted_samples{0};
  std::atomic<double> prototype_noise_floor_rms{0.0};
  std::atomic<double> prototype_last_gain{1.0};
  std::atomic<bool> deepfilternet_runtime_available{false};
  std::atomic<bool> deepfilternet_processing_applied{false};
  std::atomic<int> deepfilternet_frames_processed{0};
  std::atomic<int> deepfilternet_bypass_frames{0};
  std::atomic<int> deepfilternet_frame_length{0};
  std::atomic<int> deepfilternet_reason{
      kDeepFilterNetRuntimeReasonNotInitialized};
  std::atomic<double> deepfilternet_last_local_snr{0.0};
  std::atomic<int> deepfilternet_speech_protected_frames{0};
  std::atomic<double> deepfilternet_last_speech_protect_wet_mix{1.0};
  std::atomic<bool> deepfilternet_transient_suppression_enabled{false};
  std::atomic<int> deepfilternet_transient_suppressed_frames{0};
  std::atomic<int> deepfilternet_transient_adjusted_samples{0};
  std::atomic<double> deepfilternet_last_transient_gain{1.0};
  std::atomic<bool> deepfilternet_hush_suppression_enabled{false};
  std::atomic<bool> deepfilternet_hush_runtime_available{false};
  std::atomic<bool> deepfilternet_hush_processing_applied{false};
  std::atomic<int> deepfilternet_hush_frames_processed{0};
  std::atomic<int> deepfilternet_hush_bypass_frames{0};
  std::atomic<int> deepfilternet_hush_frame_length{0};
  std::atomic<int> deepfilternet_hush_reason{
      kDeepFilterNetRuntimeReasonNotInitialized};
  std::atomic<double> deepfilternet_hush_last_local_snr{0.0};
  std::atomic<int64_t> deepfilternet_hush_recovery_frames{0};
  std::atomic<double> deepfilternet_hush_last_recovery_gain{1.0};
  std::atomic<double> deepfilternet_hush_last_input_rms{0.0};
  std::atomic<double> deepfilternet_hush_last_output_rms{0.0};
  // Applied dry-reference delay (in 10 ms callback frames) between the dry
  // signal and the model output inside the post-model stages. 0 until the
  // DeepFilterNet path has processed a frame.
  std::atomic<int> deepfilternet_dry_delay_frames{0};
  // Model runtimes loaded OFF the audio callback thread (plugin worker or
  // replay harness) and parked here until Process() adopts them with a
  // non-blocking try_lock. df_create() extracts a model archive and builds
  // the inference graph, which must never run on the capture callback.
  std::mutex prewarm_mutex;
  std::unique_ptr<DeepFilterNetRuntime> prewarmed_deepfilternet;
  std::unique_ptr<DeepFilterNetRuntime> prewarmed_hush;
  std::atomic<bool> prewarmed_deepfilternet_ready{false};
  std::atomic<bool> prewarmed_hush_ready{false};
  std::atomic<double> deepfilternet_warmup_ms{0.0};
  std::atomic<double> deepfilternet_hush_warmup_ms{0.0};
  std::atomic<int> deepfilternet_prewarm_pending_frames{0};
  std::shared_ptr<DiagnosticCapture> diagnostic_capture{
      std::make_shared<DiagnosticCapture>()};
};

// Synchronously load the requested model runtimes and deposit them in the
// shared prewarm slots for Process() to adopt. Must be called off the audio
// callback thread. Slots that are still marked ready are left untouched so a
// repeated trigger does not reload an unclaimed model.
void PrewarmDeepFilterNetRuntimes(ProcessorSharedState* shared_state,
                                  bool include_deepfilternet,
                                  bool include_hush);

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
  int ApplyPrototypeSuppressionStage(float vad_probability,
                                     double input_rms,
                                     double input_peak,
                                     double input_delta,
                                     double output_rms,
                                     double output_peak,
                                     double output_max_delta,
                                     std::vector<float>* samples);
  int ApplySpeechProtectedPrototypeSuppressionStage(
      float vad_probability,
      double input_rms,
      double input_peak,
      double input_delta,
      double output_rms,
      double output_peak,
      double output_max_delta,
      std::vector<float>* samples);
  bool ApplyDeepFilterNetSpeechProtection(
      const std::vector<float>& dry,
      double input_rms,
      double input_peak,
      double input_delta,
      double output_rms,
      double output_peak,
      double output_max_delta,
      float local_snr,
      std::vector<float>* samples);
  int ApplyDeepFilterNetTransientSuppression(const std::vector<float>& dry,
                                             double input_rms,
                                             double input_peak,
                                             double input_delta,
                                             double output_rms,
                                             double output_peak,
                                             double output_max_delta,
                                             float local_snr,
                                             bool speech_protected_frame,
                                             std::vector<float>* samples);
  int ApplyOutputSafetyLimiter(double input_max_delta,
                               std::vector<float>* samples);
  bool ProcessCleanRnnoise(int num_frames,
                           const std::vector<float>& mono_in_normalized,
                           std::vector<float>* mono_out_normalized,
                           float* vad_probability);
  bool ProcessDeepFilterNet(int num_frames,
                            const std::vector<float>& mono_in_normalized,
                            std::vector<float>* mono_out_normalized,
                            float* local_snr);
  bool ProcessDeepFilterNetHushSupport(
      int num_frames,
      const std::vector<float>& mono_in_normalized,
      std::vector<float>* mono_out_normalized,
      float* local_snr);
  bool ApplyDeepFilterNetHushGainRecovery(double pre_hush_rms,
                                          double pre_hush_peak,
                                          double hush_rms,
                                          double hush_peak,
                                          std::vector<float>* samples);
  void EnsureDryHistoryCapacity(int frame_length, int capacity_frames);
  void PushDryHistoryFrame(const std::vector<float>& frame);
  // Copies the dry frame from `frames_back` processed callbacks ago into
  // `out` (sized to frame_length). Returns false and fills zeros while the
  // history is still shorter than `frames_back` (model warm-up after a
  // pipeline reset).
  bool CopyDelayedDryFrame(int frames_back,
                           int frame_length,
                           std::vector<float>* out) const;
  void ResetAudioPipeline();
  void RecordDryDiagnosticCallback(
      const std::vector<float>& mono_in_normalized,
      int sample_rate_hz,
      int num_frames);
  void RampWetMix(std::vector<float>* processed,
                  const std::vector<float>& dry,
                  float target_wet_mix);
  void RampWetMixWithState(std::vector<float>* processed,
                           const std::vector<float>& dry,
                           float target_wet_mix,
                           float* wet_mix_state);
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
  int suspicious_transient_streak_ = 0;
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
  float prototype_gain_ = 1.0f;
  float deepfilternet_wet_mix_ = 1.0f;
  float deepfilternet_hush_recovery_gain_ = 1.0f;
  bool has_last_callback_time_ = false;
  std::chrono::steady_clock::time_point last_callback_time_{};
  // <1.0 while a post-capture-gap crossfade ramps DeepFilterNet output back in
  // from dry so stale-lookahead artifacts and the recovery pop are masked.
  float deepfilternet_gap_recovery_wet_mix_ = 1.0f;
  int prototype_transient_hold_frames_ = 0;
  int prototype_speech_hold_frames_ = 0;
  double prototype_noise_floor_rms_ = 0.0;
  int prototype_noise_floor_frames_ = 0;
  std::array<double, 6> input_rms_history_{};
  std::array<double, 6> input_peak_history_{};
  std::array<double, 6> input_delta_history_{};
  int input_metric_history_count_ = 0;
  int input_metric_history_next_index_ = 0;
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
  std::unique_ptr<DeepFilterNetRuntime> deepfilternet_runtime_;
  std::unique_ptr<DeepFilterNetRuntime> hush_runtime_;
  // Dry-reference delay line: ring buffer of the most recent dry frames so
  // post-model stages can blend/compare against the dry frame that
  // corresponds in time to the lookahead-delayed model output.
  std::vector<float> deepfilternet_dry_history_;
  int deepfilternet_dry_history_capacity_frames_ = 0;
  int deepfilternet_dry_history_frame_length_ = 0;
  int deepfilternet_dry_history_size_frames_ = 0;
  int deepfilternet_dry_history_next_frame_ = 0;
  std::vector<float> deepfilternet_dry_delayed_;
  std::vector<float> deepfilternet_dry_delayed_post_;
  // Hush output is one Hush frame (10 ms) late relative to its input, so the
  // gain-recovery comparison uses the previous callback's pre-Hush level.
  bool has_previous_pre_hush_metrics_ = false;
  double previous_pre_hush_rms_ = 0.0;
  double previous_pre_hush_peak_ = 0.0;
  std::vector<float> hush_input_;
  std::vector<float> hush_output_;
  std::vector<float> hush_output_for_capture_;
  StreamingLinearResampler capture_to_rnnoise_resampler_;
  StreamingLinearResampler rnnoise_to_capture_resampler_;
};

}  // namespace intergalactic_noise_suppression

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_CAPTURE_PROCESSOR_H_
