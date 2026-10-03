#include "deep_filter_net_runtime.h"

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>
#include <vector>

#include <windows.h>

extern "C" {
struct DFState;
__declspec(dllimport) DFState* df_create(const char* path,
                                         float atten_lim,
                                         const char* log_level);
__declspec(dllimport) size_t df_get_frame_length(DFState* state);
__declspec(dllimport) float df_process_frame(DFState* state,
                                             float* input,
                                             float* output);
__declspec(dllimport) void df_set_post_filter_beta(DFState* state, float beta);
__declspec(dllimport) void df_free(DFState* state);
}

namespace intergalactic_noise_suppression {
namespace {

constexpr int kDeepFilterNetSampleRateHz = 48000;
constexpr int kHushSampleRateHz = 16000;
constexpr float kDeepFilterNetAttenuationLimitDb = 60.0f;
constexpr float kDeepFilterNetPostFilterBeta = 0.02f;
// Shipped archives are megabytes; anything this small is truncated or wrong.
constexpr std::uintmax_t kMinimumModelArchiveBytes = 1024;
constexpr wchar_t kModelEnvironmentVariable[] =
    L"INTERGALACTIC_DEEPFILTERNET_MODEL";
constexpr wchar_t kModelDirectoryEnvironmentVariable[] =
    L"INTERGALACTIC_ENHANCED_NOISE_SUPPRESSION_MODEL_DIR";
constexpr wchar_t kHushModelEnvironmentVariable[] =
    L"INTERGALACTIC_HUSH_MODEL";
constexpr wchar_t kHushModelDirectoryEnvironmentVariable[] =
    L"INTERGALACTIC_ENHANCED_NOISE_SUPPRESSION_HUSH_MODEL_DIR";
constexpr wchar_t kBundledModelFileName[] = L"DeepFilterNet3_onnx.tar.gz";
constexpr wchar_t kBundledHushModelFileName[] =
    L"advanced_dfnet16k_model_best_onnx.tar.gz";

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8,
                                      0,
                                      value.c_str(),
                                      static_cast<int>(value.size()),
                                      nullptr,
                                      0,
                                      nullptr,
                                      nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string output(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8,
                      0,
                      value.c_str(),
                      static_cast<int>(value.size()),
                      output.data(),
                      size,
                      nullptr,
                      nullptr);
  return output;
}

std::wstring ReadEnvironmentPath(const wchar_t* variable_name) {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD size = GetEnvironmentVariableW(
      variable_name,
      buffer.data(),
      static_cast<DWORD>(buffer.size()));
  if (size == 0) {
    return std::wstring();
  }
  if (size >= buffer.size()) {
    buffer.resize(size + 1);
    size = GetEnvironmentVariableW(
        variable_name,
        buffer.data(),
        static_cast<DWORD>(buffer.size()));
  }
  if (size == 0 || size >= buffer.size()) {
    return std::wstring();
  }
  return std::wstring(buffer.data(), size);
}

std::filesystem::path ExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD size = GetModuleFileNameW(
      nullptr,
      buffer.data(),
      static_cast<DWORD>(buffer.size()));
  while (size == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    size = GetModuleFileNameW(
        nullptr,
        buffer.data(),
        static_cast<DWORD>(buffer.size()));
  }
  if (size == 0) {
    return std::filesystem::current_path();
  }
  return std::filesystem::path(std::wstring(buffer.data(), size))
      .parent_path();
}

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
  if (state_ != nullptr && reason_ == kDeepFilterNetRuntimeReasonReady) {
    return true;
  }

  const std::filesystem::path resolved_model_path = ResolveModelPath();
  if (resolved_model_path.empty() || !FileExists(resolved_model_path)) {
    reason_ = kDeepFilterNetRuntimeReasonModelMissing;
    return false;
  }
  if (!LooksLikeModelArchive(resolved_model_path)) {
    // Present but not a usable archive. Reported as a create failure rather
    // than a missing model, because the path resolved and the file is there.
    reason_ = kDeepFilterNetRuntimeReasonCreateFailed;
    return false;
  }
  model_path_ = WideToUtf8(resolved_model_path.wstring());

  DFState* state = nullptr;
  try {
    state = df_create(
        model_path_.c_str(),
        kDeepFilterNetAttenuationLimitDb,
        nullptr);
  } catch (...) {
    reason_ = kDeepFilterNetRuntimeReasonCreateFailed;
    return false;
  }
  if (state == nullptr) {
    reason_ = kDeepFilterNetRuntimeReasonCreateFailed;
    return false;
  }

  state_ = state;
  frame_length_ = static_cast<int>(df_get_frame_length(state));
  if (frame_length_ <= 0) {
    Reset();
    reason_ = kDeepFilterNetRuntimeReasonCreateFailed;
    return false;
  }
  df_set_post_filter_beta(state, kDeepFilterNetPostFilterBeta);
  reason_ = kDeepFilterNetRuntimeReasonReady;
  return true;
}

bool DeepFilterNetRuntime::ProcessFrame(const std::vector<float>& input,
                                        std::vector<float>* output,
                                        float* local_snr) {
  if (output == nullptr || local_snr == nullptr) {
    reason_ = kDeepFilterNetRuntimeReasonProcessFailed;
    return false;
  }
  if (state_ == nullptr || reason_ != kDeepFilterNetRuntimeReasonReady) {
    reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
    return false;
  }
  if (static_cast<int>(input.size()) != frame_length_) {
    reason_ = kDeepFilterNetRuntimeReasonFrameSizeMismatch;
    return false;
  }

  scratch_input_ = input;
  output->assign(input.size(), 0.0f);
  try {
    *local_snr = df_process_frame(
        static_cast<DFState*>(state_),
        scratch_input_.data(),
        output->data());
  } catch (...) {
    output->clear();
    reason_ = kDeepFilterNetRuntimeReasonProcessFailed;
    return false;
  }
  if (!std::isfinite(*local_snr)) {
    *local_snr = 0.0f;
  }
  reason_ = kDeepFilterNetRuntimeReasonReady;
  return true;
}

void DeepFilterNetRuntime::Reset() {
  if (state_ != nullptr) {
    df_free(static_cast<DFState*>(state_));
  }
  state_ = nullptr;
  frame_length_ = 0;
  scratch_input_.clear();
  reason_ = kDeepFilterNetRuntimeReasonNotInitialized;
}

int DeepFilterNetRuntime::expected_sample_rate_hz() const {
  return model_ == DeepFilterNetRuntimeModel::kHush ? kHushSampleRateHz
                                                    : kDeepFilterNetSampleRateHz;
}

int DeepFilterNetRuntime::output_delay_frames() const {
  // delay = df_lookahead * hop + (fft_size - hop), in hop-sized frames:
  //   DeepFilterNet3: lookahead 2, fft 960, hop 480 -> 2 + 1 = 3 frames
  //   Hush (dfnet16k): lookahead 0, fft 320, hop 160 -> 0 + 1 = 1 frame
  return model_ == DeepFilterNetRuntimeModel::kHush ? 1 : 3;
}

std::filesystem::path DeepFilterNetRuntime::ResolveModelPath() const {
  const std::wstring override_path = ReadEnvironmentPath(
      model_ == DeepFilterNetRuntimeModel::kHush
          ? kHushModelEnvironmentVariable
          : kModelEnvironmentVariable);
  if (!override_path.empty()) {
    return std::filesystem::path(override_path);
  }

  if (model_ == DeepFilterNetRuntimeModel::kHush) {
    const std::wstring override_directories[] = {
        ReadEnvironmentPath(kHushModelDirectoryEnvironmentVariable),
        ReadEnvironmentPath(kModelDirectoryEnvironmentVariable),
    };
    for (const auto& override_directory : override_directories) {
      if (override_directory.empty()) {
        continue;
      }
      const std::filesystem::path directory(override_directory);
      const std::filesystem::path candidates[] = {
          directory / L"onnx" / kBundledHushModelFileName,
          directory / L"hush" / L"onnx" / kBundledHushModelFileName,
          directory / kBundledHushModelFileName,
      };
      for (const auto& candidate : candidates) {
        if (FileExists(candidate)) {
          return candidate;
        }
      }
    }

    const std::filesystem::path bundled =
        ExecutableDirectory() / kBundledHushModelFileName;
    return bundled;
  }

  const std::wstring override_directory =
      ReadEnvironmentPath(kModelDirectoryEnvironmentVariable);
  if (!override_directory.empty()) {
    const std::filesystem::path directory(override_directory);
    const std::filesystem::path candidates[] = {
        directory / kBundledModelFileName,
        directory / L"models" / kBundledModelFileName,
        directory / L"onnx" / kBundledModelFileName,
        directory / L"deepfilternet" / L"models" / kBundledModelFileName,
    };
    for (const auto& candidate : candidates) {
      if (FileExists(candidate)) {
        return candidate;
      }
    }
  }

  const std::filesystem::path bundled =
      ExecutableDirectory() / kBundledModelFileName;
  return bundled;
}

bool DeepFilterNetRuntime::FileExists(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary);
  return stream.good();
}

bool DeepFilterNetRuntime::LooksLikeModelArchive(
    const std::filesystem::path& path) {
  // df_create() hands the path to Rust, and a malformed archive makes that
  // side ABORT the process (0xC0000409, a fail-fast) rather than return null.
  // The try/catch around df_create cannot catch it because it is not a C++
  // exception, so a truncated or wrong file takes the whole app down from a
  // background prewarm thread. Screen the obvious cases here instead.
  //
  // This checks the container, not the contents: it rejects empty, truncated
  // and non-gzip files, which covers a failed download or a wrong path. A
  // well-formed gzip whose payload is not a model will still reach df_create.
  std::error_code ec;
  const auto size = std::filesystem::file_size(path, ec);
  if (ec || size < kMinimumModelArchiveBytes) {
    return false;
  }
  std::ifstream stream(path, std::ios::binary);
  if (!stream.good()) {
    return false;
  }
  unsigned char magic[2] = {0, 0};
  stream.read(reinterpret_cast<char*>(magic), sizeof(magic));
  if (stream.gcount() != static_cast<std::streamsize>(sizeof(magic))) {
    return false;
  }
  return magic[0] == 0x1f && magic[1] == 0x8b;  // gzip
}

}  // namespace intergalactic_noise_suppression
