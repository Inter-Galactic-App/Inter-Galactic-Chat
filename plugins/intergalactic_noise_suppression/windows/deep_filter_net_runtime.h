#ifndef INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_DEEP_FILTER_NET_RUNTIME_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_DEEP_FILTER_NET_RUNTIME_H_

#include <filesystem>
#include <string>
#include <vector>

namespace intergalactic_noise_suppression {

enum DeepFilterNetRuntimeReason {
  kDeepFilterNetRuntimeReasonNotInitialized = 0,
  kDeepFilterNetRuntimeReasonReady = 1,
  kDeepFilterNetRuntimeReasonModelMissing = 2,
  kDeepFilterNetRuntimeReasonCreateFailed = 3,
  kDeepFilterNetRuntimeReasonUnsupportedRate = 4,
  kDeepFilterNetRuntimeReasonFrameSizeMismatch = 5,
  kDeepFilterNetRuntimeReasonProcessFailed = 6,
};

const char* DeepFilterNetRuntimeReasonToString(int reason);

enum class DeepFilterNetRuntimeModel {
  kDeepFilterNet,
  kHush,
};

class DeepFilterNetRuntime {
 public:
  explicit DeepFilterNetRuntime(
      DeepFilterNetRuntimeModel model = DeepFilterNetRuntimeModel::kDeepFilterNet);
  ~DeepFilterNetRuntime();

  DeepFilterNetRuntime(const DeepFilterNetRuntime&) = delete;
  DeepFilterNetRuntime& operator=(const DeepFilterNetRuntime&) = delete;

  bool EnsureInitialized(int sample_rate_hz);
  bool ProcessFrame(const std::vector<float>& input,
                    std::vector<float>* output,
                    float* local_snr);
  void Reset();

  bool ready() const { return state_ != nullptr && reason_ == kDeepFilterNetRuntimeReasonReady; }
  int reason() const { return reason_; }
  int frame_length() const { return frame_length_; }
  // Frames of algorithmic delay between ProcessFrame() input and output.
  // libdf delays enhanced output by the model's lookahead
  // (third_party/deepfilternet/libDF/src/tract.rs) but does not expose it
  // through the C API, so these constants mirror the shipped model configs
  // and the diagnostic stage-WAV cross-correlation measurements:
  // DeepFilterNet3 = 2 frames (20 ms at 48 kHz), Hush = 1 frame (10 ms at
  // 16 kHz, which is also one 10 ms capture callback). Post-model stages
  // must delay their dry reference by this many callbacks before blending
  // with or comparing against the model output.
  int lookahead_frames() const;
  const std::string& model_path() const { return model_path_; }
  int expected_sample_rate_hz() const;
  static float AttenuationLimitDb();
  static float PostFilterBeta();

 private:
  std::filesystem::path ResolveModelPath() const;
  static bool FileExists(const std::filesystem::path& path);

  DeepFilterNetRuntimeModel model_ = DeepFilterNetRuntimeModel::kDeepFilterNet;
  void* state_ = nullptr;
  int reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
  int frame_length_ = 0;
  std::string model_path_;
  std::vector<float> scratch_input_;
};

}  // namespace intergalactic_noise_suppression

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_DEEP_FILTER_NET_RUNTIME_H_
