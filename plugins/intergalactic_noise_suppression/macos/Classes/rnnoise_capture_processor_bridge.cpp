// CocoaPods does not reliably compile source files outside the pod root.
// Keep the implementation shared with Windows by compiling it through this
// in-pod bridge instead of duplicating the processor.
#include "../../windows/deep_filter_net_runtime.h"

#include <filesystem>
#include <vector>

namespace intergalactic_noise_suppression {
namespace {

constexpr int kDeepFilterNetSampleRateHz = 48000;
constexpr int kHushSampleRateHz = 16000;
constexpr float kDeepFilterNetAttenuationLimitDb = 60.0f;
constexpr float kDeepFilterNetPostFilterBeta = 0.02f;

}  // namespace

const char* DeepFilterNetRuntimeReasonToString(int reason) {
  switch (reason) {
    case kDeepFilterNetRuntimeReasonNotInitialized:
      return "deepfilternet_not_initialized";
    case kDeepFilterNetRuntimeReasonReady:
      return "deepfilternet_ready";
    case kDeepFilterNetRuntimeReasonModelMissing:
      return "deepfilternet_model_missing";
    case kDeepFilterNetRuntimeReasonCreateFailed:
      return "deepfilternet_create_failed";
    case kDeepFilterNetRuntimeReasonUnsupportedRate:
      return "deepfilternet_unsupported_rate";
    case kDeepFilterNetRuntimeReasonFrameSizeMismatch:
      return "deepfilternet_frame_size_mismatch";
    case kDeepFilterNetRuntimeReasonProcessFailed:
      return "deepfilternet_process_failed";
    default:
      return "deepfilternet_unknown";
  }
}

DeepFilterNetRuntime::DeepFilterNetRuntime(DeepFilterNetRuntimeModel model)
    : model_(model) {}

DeepFilterNetRuntime::~DeepFilterNetRuntime() {
  Reset();
}

float DeepFilterNetRuntime::AttenuationLimitDb() {
  return kDeepFilterNetAttenuationLimitDb;
}

float DeepFilterNetRuntime::PostFilterBeta() {
  return kDeepFilterNetPostFilterBeta;
}

bool DeepFilterNetRuntime::EnsureInitialized(int sample_rate_hz) {
  if (sample_rate_hz != expected_sample_rate_hz()) {
    reason_ = kDeepFilterNetRuntimeReasonUnsupportedRate;
    return false;
  }

  reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
  frame_length_ = 0;
  model_path_.clear();
  return false;
}

bool DeepFilterNetRuntime::ProcessFrame(const std::vector<float>& input,
                                        std::vector<float>* output,
                                        float* local_snr) {
  (void)input;
  if (output != nullptr) {
    output->clear();
  }
  if (local_snr != nullptr) {
    *local_snr = 0.0f;
  }
  reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
  return false;
}

void DeepFilterNetRuntime::Reset() {
  state_ = nullptr;
  frame_length_ = 0;
  model_path_.clear();
  scratch_input_.clear();
  reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
}

int DeepFilterNetRuntime::expected_sample_rate_hz() const {
  return model_ == DeepFilterNetRuntimeModel::kHush ? kHushSampleRateHz
                                                    : kDeepFilterNetSampleRateHz;
}

std::filesystem::path DeepFilterNetRuntime::ResolveModelPath() const {
  return std::filesystem::path();
}

bool DeepFilterNetRuntime::FileExists(const std::filesystem::path& path) {
  (void)path;
  return false;
}

}  // namespace intergalactic_noise_suppression

#include "../../windows/rnnoise_capture_processor.cpp"
