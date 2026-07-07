#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "game_capture_protocol.h"

namespace fs = std::filesystem;
namespace iggc = intergalactic_game_capture;
using Microsoft::WRL::ComPtr;

namespace {

using PresentFn = HRESULT(STDMETHODCALLTYPE*)(IDXGISwapChain*, UINT, UINT);
using Present1Fn = HRESULT(STDMETHODCALLTYPE*)(
    IDXGISwapChain1*, UINT, UINT, const DXGI_PRESENT_PARAMETERS*);

HMODULE g_module = nullptr;
std::atomic<bool> g_stop_requested = false;
std::atomic<bool> g_hook_installed = false;
std::mutex g_log_mutex;
std::mutex g_capture_mutex;

PresentFn g_original_present = nullptr;
Present1Fn g_original_present1 = nullptr;
void** g_present_slot = nullptr;
void** g_present1_slot = nullptr;

struct Config {
  std::string session_id;
  fs::path output_dir;
  int duration_ms = iggc::kDefaultDurationMs;
  std::wstring stop_event_name;
  std::wstring stopped_event_name;
  std::wstring frame_event_name;
  std::wstring shared_state_name;
  int max_saved_frames = iggc::kDefaultSavedFrames;
  int target_capture_fps = 0;
  bool host_consumer_enabled = false;
};

struct RingSlot {
  ComPtr<ID3D11Texture2D> texture;
  HANDLE shared_handle = nullptr;
  bool has_frame = false;
  uint64_t frame_index = 0;
};

struct CaptureState {
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<ID3D11Texture2D> resolve_texture;
  RingSlot ring[iggc::kRingDepth];
  UINT width = 0;
  UINT height = 0;
  UINT sample_count = 1;
  DXGI_FORMAT format = DXGI_FORMAT_UNKNOWN;
  bool shared_texture_supported = false;
};

struct Stats {
  uint64_t present_count = 0;
  uint64_t captured_frame_count = 0;
  uint64_t copied_frames = 0;
  uint64_t dropped_frames = 0;
  uint64_t overwritten_frames = 0;
  uint64_t cpu_readback_count = 0;
  uint64_t proof_export_busy_frames = 0;
  uint64_t saved_frames = 0;
  uint64_t visible_frames = 0;
  uint64_t resize_count = 0;
  uint64_t throttled_frames = 0;
  int64_t first_qpc = 0;
  int64_t last_qpc = 0;
  int64_t last_capture_qpc = 0;
  int64_t next_capture_qpc = 0;
  int64_t previous_present_qpc = 0;
  uint64_t present_gap_qpc_total = 0;
  uint64_t present_gap_qpc_max = 0;
  uint64_t present_gap_samples = 0;
  uint64_t capture_gap_qpc_total = 0;
  uint64_t capture_gap_qpc_max = 0;
  uint64_t capture_gap_samples = 0;
  uint64_t present_to_publish_qpc_total = 0;
  uint64_t present_to_publish_qpc_max = 0;
  uint64_t present_to_publish_samples = 0;
  uint64_t copy_qpc_total = 0;
  uint64_t copy_qpc_max = 0;
  uint64_t copy_qpc_samples = 0;
  uint64_t resolve_qpc_total = 0;
  uint64_t resolve_qpc_max = 0;
  uint64_t resolve_qpc_samples = 0;
  uint64_t latest_publish_qpc = 0;
  std::vector<double> present_gaps_ms;
  std::vector<double> copy_ms;
  std::vector<double> resolve_ms;
  std::vector<double> export_ms;
  std::string detected_graphics_api = "unknown";
  std::string fallback_reason = "none";
  std::string hook_stop_reason = "unknown";
  std::string last_error = "none";
};

Config g_config;
CaptureState g_capture;
Stats g_stats;
LARGE_INTEGER g_qpc_frequency{};
HANDLE g_frame_event = nullptr;
HANDLE g_shared_state_mapping = nullptr;
iggc::SharedTextureState* g_shared_state = nullptr;

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string JsonEscape(const std::string& value) {
  std::ostringstream out;
  for (char c : value) {
    switch (c) {
      case '\\':
        out << "\\\\";
        break;
      case '"':
        out << "\\\"";
        break;
      case '\n':
        out << "\\n";
        break;
      case '\r':
        out << "\\r";
        break;
      case '\t':
        out << "\\t";
        break;
      default:
        out << c;
        break;
    }
  }
  return out.str();
}

int64_t NowQpc() {
  LARGE_INTEGER now{};
  QueryPerformanceCounter(&now);
  return now.QuadPart;
}

double QpcToMs(int64_t delta) {
  return static_cast<double>(delta) * 1000.0 /
         static_cast<double>(g_qpc_frequency.QuadPart);
}

void RecordQpcMetric(uint64_t delta_qpc,
                     uint64_t* total_qpc,
                     uint64_t* max_qpc,
                     uint64_t* samples) {
  if (total_qpc == nullptr || max_qpc == nullptr || samples == nullptr) {
    return;
  }
  *total_qpc += delta_qpc;
  *max_qpc = std::max(*max_qpc, delta_qpc);
  ++(*samples);
}

std::string NowIsoUtc() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t t = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  gmtime_s(&tm, &t);
  std::ostringstream out;
  out << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
  return out.str();
}

std::string FormatName(DXGI_FORMAT format) {
  switch (format) {
    case DXGI_FORMAT_B8G8R8A8_UNORM:
      return "B8G8R8A8_UNORM";
    case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
      return "B8G8R8A8_UNORM_SRGB";
    case DXGI_FORMAT_R8G8B8A8_UNORM:
      return "R8G8B8A8_UNORM";
    case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
      return "R8G8B8A8_UNORM_SRGB";
    case DXGI_FORMAT_R10G10B10A2_UNORM:
      return "R10G10B10A2_UNORM";
    case DXGI_FORMAT_R16G16B16A16_FLOAT:
      return "R16G16B16A16_FLOAT";
    default:
      return "DXGI_FORMAT_" + std::to_string(static_cast<int>(format));
  }
}

void AppendLog(const std::string& line) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  std::ofstream file(g_config.output_dir / L"hook.log", std::ios::app);
  file << NowIsoUtc() << " " << line << "\n";
}

void PublishRingState() {
  if (g_shared_state == nullptr) {
    return;
  }
  const iggc::SourceFormat source_format =
      iggc::SourceFormatFromDxgiFormat(static_cast<uint32_t>(g_capture.format));
  const iggc::FailureReason failure_reason =
      g_capture.shared_texture_supported
          ? iggc::FailureReason::kNone
          : iggc::FailureReason::kSharedTextureUnavailable;
  g_shared_state->magic = iggc::kProtocolMagic;
  g_shared_state->version = iggc::kSharedTextureStateVersion;
  g_shared_state->ring_depth = iggc::kRingDepth;
  ++g_shared_state->generation;
  g_shared_state->backbuffer_width = g_capture.width;
  g_shared_state->backbuffer_height = g_capture.height;
  g_shared_state->backbuffer_format = static_cast<uint32_t>(g_capture.format);
  g_shared_state->sample_count = g_capture.sample_count;
  g_shared_state->shared_texture_supported =
      g_capture.shared_texture_supported ? 1u : 0u;
  g_shared_state->source_api =
      static_cast<uint32_t>(iggc::CaptureBackend::kD3D11PresentHook);
  g_shared_state->source_format = static_cast<uint32_t>(source_format);
  g_shared_state->color_space =
      static_cast<uint32_t>(iggc::ColorSpace::kUnknown);
  g_shared_state->hdr_flags = 0;
  g_shared_state->sync_kind = static_cast<uint32_t>(iggc::SyncKind::kEvent);
  g_shared_state->ready_state =
      static_cast<uint32_t>(iggc::FrameReadyState::kEmpty);
  g_shared_state->failure_reason = static_cast<uint32_t>(failure_reason);
  g_shared_state->contract_reserved = 0;
  for (int i = 0; i < iggc::kRingDepth; ++i) {
    auto& state_slot = g_shared_state->slots[i];
    const auto& slot = g_capture.ring[i];
    state_slot.shared_handle =
        reinterpret_cast<uint64_t>(slot.shared_handle);
    state_slot.frame_index = slot.frame_index;
    state_slot.width = g_capture.width;
    state_slot.height = g_capture.height;
    state_slot.dxgi_format = static_cast<uint32_t>(g_capture.format);
    state_slot.sample_count = g_capture.sample_count;
  }
}

void PublishLatestFrameState(UINT slot_index, uint64_t capture_index) {
  if (g_shared_state == nullptr) {
    return;
  }
  const int64_t publish_qpc = NowQpc();
  if (g_stats.last_qpc > 0 && publish_qpc >= g_stats.last_qpc) {
    RecordQpcMetric(static_cast<uint64_t>(publish_qpc - g_stats.last_qpc),
                    &g_stats.present_to_publish_qpc_total,
                    &g_stats.present_to_publish_qpc_max,
                    &g_stats.present_to_publish_samples);
  }
  g_stats.latest_publish_qpc = static_cast<uint64_t>(publish_qpc);
  g_shared_state->latest_slot_index = slot_index;
  g_shared_state->latest_frame_index = capture_index;
  g_shared_state->latest_qpc = static_cast<uint64_t>(g_stats.last_qpc);
  g_shared_state->producer_latest_publish_qpc = g_stats.latest_publish_qpc;
  g_shared_state->present_count = g_stats.present_count;
  g_shared_state->copied_frames = g_stats.copied_frames;
  g_shared_state->dropped_frames = g_stats.dropped_frames;
  g_shared_state->overwritten_frames = g_stats.overwritten_frames;
  g_shared_state->producer_present_gap_qpc_total =
      g_stats.present_gap_qpc_total;
  g_shared_state->producer_present_gap_qpc_max = g_stats.present_gap_qpc_max;
  g_shared_state->producer_present_gap_samples = g_stats.present_gap_samples;
  g_shared_state->producer_capture_gap_qpc_total =
      g_stats.capture_gap_qpc_total;
  g_shared_state->producer_capture_gap_qpc_max = g_stats.capture_gap_qpc_max;
  g_shared_state->producer_capture_gap_samples = g_stats.capture_gap_samples;
  g_shared_state->producer_present_to_publish_qpc_total =
      g_stats.present_to_publish_qpc_total;
  g_shared_state->producer_present_to_publish_qpc_max =
      g_stats.present_to_publish_qpc_max;
  g_shared_state->producer_present_to_publish_samples =
      g_stats.present_to_publish_samples;
  g_shared_state->producer_copy_qpc_total = g_stats.copy_qpc_total;
  g_shared_state->producer_copy_qpc_max = g_stats.copy_qpc_max;
  g_shared_state->producer_copy_samples = g_stats.copy_qpc_samples;
  g_shared_state->producer_resolve_qpc_total = g_stats.resolve_qpc_total;
  g_shared_state->producer_resolve_qpc_max = g_stats.resolve_qpc_max;
  g_shared_state->producer_resolve_samples = g_stats.resolve_qpc_samples;
  g_shared_state->producer_throttled_frames = g_stats.throttled_frames;
  g_shared_state->ready_state =
      static_cast<uint32_t>(g_capture.shared_texture_supported
                                ? iggc::FrameReadyState::kReady
                                : iggc::FrameReadyState::kFailed);
  g_shared_state->failure_reason = static_cast<uint32_t>(
      g_capture.shared_texture_supported
          ? iggc::FailureReason::kNone
          : iggc::FailureReason::kSharedTextureUnavailable);
  if (slot_index < iggc::kRingDepth) {
    g_shared_state->slots[slot_index].frame_index = capture_index;
  }
  if (g_frame_event != nullptr) {
    SetEvent(g_frame_event);
  }
}

std::map<std::string, std::string> ReadConfigFile(const fs::path& path) {
  std::map<std::string, std::string> result;
  std::ifstream file(path);
  std::string line;
  while (std::getline(file, line)) {
    const auto eq = line.find('=');
    if (eq == std::string::npos) {
      continue;
    }
    result[line.substr(0, eq)] = line.substr(eq + 1);
  }
  return result;
}

bool LoadConfig() {
  wchar_t module_path[MAX_PATH] = {};
  GetModuleFileNameW(g_module, module_path, MAX_PATH);
  const fs::path dll_path(module_path);
  const fs::path config_path =
      dll_path.parent_path() /
      Utf8ToWide("intergalactic_game_capture_" +
                 std::to_string(GetCurrentProcessId()) + ".cfg");
  const auto values = ReadConfigFile(config_path);
  if (values.empty()) {
    return false;
  }

  auto get = [&](const char* key, const std::string& fallback) {
    const auto it = values.find(key);
    return it == values.end() ? fallback : it->second;
  };
  auto parse_int = [](const std::string& value, int fallback) {
    try {
      size_t consumed = 0;
      const int parsed = std::stoi(value, &consumed);
      return consumed == value.size() ? parsed : fallback;
    } catch (...) {
      return fallback;
    }
  };

  g_config.session_id = get("sessionId", "unknown");
  g_config.output_dir = Utf8ToWide(get("outputDir", ""));
  g_config.duration_ms =
      std::clamp(parse_int(get("durationMs", "10000"), 10000), 1000,
                 iggc::kMaxDurationMs);
  g_config.stop_event_name = Utf8ToWide(get("stopEvent", ""));
  g_config.stopped_event_name = Utf8ToWide(get("stoppedEvent", ""));
  g_config.frame_event_name = Utf8ToWide(get("frameEvent", ""));
  g_config.shared_state_name = Utf8ToWide(get("sharedState", ""));
  g_config.max_saved_frames =
      std::clamp(parse_int(get("maxSavedFrames", "5"), 5), 0,
                 iggc::kMaxSavedFrames);
  g_config.target_capture_fps =
      std::clamp(parse_int(get("hookTargetFps", "0"), 0), 0,
                 iggc::kMaxPublicationHandoffTargetFps);
  g_config.host_consumer_enabled = get("hostConsumerEnabled", "0") == "1";
  return !g_config.output_dir.empty();
}

bool OpenHostConsumerState() {
  if (!g_config.host_consumer_enabled) {
    return false;
  }
  if (!g_config.frame_event_name.empty()) {
    g_frame_event =
        OpenEventW(EVENT_MODIFY_STATE, FALSE, g_config.frame_event_name.c_str());
  }
  if (!g_config.shared_state_name.empty()) {
    g_shared_state_mapping =
        OpenFileMappingW(FILE_MAP_WRITE, FALSE, g_config.shared_state_name.c_str());
    if (g_shared_state_mapping != nullptr) {
      g_shared_state = reinterpret_cast<iggc::SharedTextureState*>(
          MapViewOfFile(g_shared_state_mapping, FILE_MAP_WRITE, 0, 0,
                        sizeof(iggc::SharedTextureState)));
    }
  }
  if (g_frame_event == nullptr || g_shared_state == nullptr) {
    AppendLog("host_consumer_state_unavailable frameEvent=" +
              std::string(g_frame_event != nullptr ? "true" : "false") +
              " sharedState=" +
              std::string(g_shared_state != nullptr ? "true" : "false"));
    return false;
  }
  AppendLog("host_consumer_state_ready");
  return true;
}

void CloseHostConsumerState() {
  if (g_shared_state != nullptr) {
    UnmapViewOfFile(g_shared_state);
    g_shared_state = nullptr;
  }
  if (g_shared_state_mapping != nullptr) {
    CloseHandle(g_shared_state_mapping);
    g_shared_state_mapping = nullptr;
  }
  if (g_frame_event != nullptr) {
    CloseHandle(g_frame_event);
    g_frame_event = nullptr;
  }
}

bool PatchVtableSlot(void** slot, void* replacement, void** original) {
  DWORD old_protect = 0;
  if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE,
                      &old_protect)) {
    return false;
  }
  *original = *slot;
  *slot = replacement;
  DWORD ignored = 0;
  VirtualProtect(slot, sizeof(void*), old_protect, &ignored);
  FlushInstructionCache(GetCurrentProcess(), slot, sizeof(void*));
  return true;
}

void RestoreVtableSlot(void** slot, void* replacement, void* original) {
  if (slot == nullptr || original == nullptr) {
    return;
  }
  DWORD old_protect = 0;
  if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE,
                      &old_protect)) {
    return;
  }
  if (*slot == replacement) {
    *slot = original;
  }
  DWORD ignored = 0;
  VirtualProtect(slot, sizeof(void*), old_protect, &ignored);
  FlushInstructionCache(GetCurrentProcess(), slot, sizeof(void*));
}

bool IsBgra(DXGI_FORMAT format) {
  return format == DXGI_FORMAT_B8G8R8A8_UNORM ||
         format == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
}

bool IsRgba(DXGI_FORMAT format) {
  return format == DXGI_FORMAT_R8G8B8A8_UNORM ||
         format == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
}

bool IsR10G10B10A2(DXGI_FORMAT format) {
  return format == DXGI_FORMAT_R10G10B10A2_UNORM;
}

bool IsProofExportSupported(DXGI_FORMAT format) {
  return IsBgra(format) || IsRgba(format) || IsR10G10B10A2(format);
}

uint8_t TenBitToEightBit(uint32_t value) {
  return static_cast<uint8_t>((value * 255u + 511u) / 1023u);
}

void ReadRgb8(const uint8_t* pixel,
              DXGI_FORMAT format,
              uint8_t* r,
              uint8_t* g,
              uint8_t* b) {
  if (IsBgra(format)) {
    *r = pixel[2];
    *g = pixel[1];
    *b = pixel[0];
    return;
  }
  if (IsR10G10B10A2(format)) {
    const uint32_t packed = *reinterpret_cast<const uint32_t*>(pixel);
    *r = TenBitToEightBit((packed >> 20) & 0x3ffu);
    *g = TenBitToEightBit((packed >> 10) & 0x3ffu);
    *b = TenBitToEightBit(packed & 0x3ffu);
    return;
  }
  *r = pixel[0];
  *g = pixel[1];
  *b = pixel[2];
}

bool WritePng(const fs::path& path,
              UINT width,
              UINT height,
              UINT stride,
              BYTE* data,
              DXGI_FORMAT format) {
  if (!IsBgra(format) && !IsRgba(format)) {
    g_stats.last_error = "png_export_unsupported_format";
    return false;
  }

  HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool should_uninit = SUCCEEDED(co);
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    if (should_uninit) {
      CoUninitialize();
    }
    g_stats.last_error = "wic_factory_failed";
    return false;
  }

  ComPtr<IWICStream> stream;
  hr = factory->CreateStream(&stream);
  if (FAILED(hr) ||
      FAILED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE))) {
    if (should_uninit) {
      CoUninitialize();
    }
    g_stats.last_error = "wic_stream_failed";
    return false;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (FAILED(hr) || FAILED(encoder->Initialize(stream.Get(),
                                               WICBitmapEncoderNoCache))) {
    if (should_uninit) {
      CoUninitialize();
    }
    g_stats.last_error = "wic_encoder_failed";
    return false;
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  hr = encoder->CreateNewFrame(&frame, nullptr);
  if (FAILED(hr) || FAILED(frame->Initialize(nullptr)) ||
      FAILED(frame->SetSize(width, height))) {
    if (should_uninit) {
      CoUninitialize();
    }
    g_stats.last_error = "wic_frame_failed";
    return false;
  }

  WICPixelFormatGUID pixel_format =
      IsBgra(format) ? GUID_WICPixelFormat32bppBGRA
                     : GUID_WICPixelFormat32bppRGBA;
  hr = frame->SetPixelFormat(&pixel_format);
  if (FAILED(hr) ||
      FAILED(frame->WritePixels(height, stride, stride * height, data)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    if (should_uninit) {
      CoUninitialize();
    }
    g_stats.last_error = "wic_write_failed";
    return false;
  }

  if (should_uninit) {
    CoUninitialize();
  }
  return true;
}

bool LooksVisible(const D3D11_MAPPED_SUBRESOURCE& mapped,
                  UINT width,
                  UINT height,
                  DXGI_FORMAT format) {
  if (!IsProofExportSupported(format)) {
    return false;
  }

  uint8_t min_luma = 255;
  uint8_t max_luma = 0;
  uint64_t sum = 0;
  uint64_t samples = 0;
  const UINT step_y = std::max<UINT>(1, height / 64);
  const UINT step_x = std::max<UINT>(1, width / 64);
  for (UINT y = 0; y < height; y += step_y) {
    const auto* row =
        static_cast<const uint8_t*>(mapped.pData) + y * mapped.RowPitch;
    for (UINT x = 0; x < width; x += step_x) {
      const auto* px = row + x * 4;
      uint8_t r = 0;
      uint8_t g = 0;
      uint8_t b = 0;
      ReadRgb8(px, format, &r, &g, &b);
      const uint8_t luma =
          static_cast<uint8_t>((static_cast<int>(r) * 30 +
                                static_cast<int>(g) * 59 +
                                static_cast<int>(b) * 11) /
                               100);
      min_luma = std::min(min_luma, luma);
      max_luma = std::max(max_luma, luma);
      sum += luma;
      ++samples;
    }
  }
  const double average = samples == 0 ? 0.0 : static_cast<double>(sum) / samples;
  return average > 3.0 && (max_luma - min_luma) > 8;
}

bool SaveFramePng(ID3D11Texture2D* texture, UINT slot_index) {
  if (g_stats.saved_frames >=
      static_cast<uint64_t>(g_config.max_saved_frames)) {
    return false;
  }

  D3D11_TEXTURE2D_DESC source_desc{};
  texture->GetDesc(&source_desc);
  if (!IsProofExportSupported(source_desc.Format)) {
    g_stats.last_error = "frame_export_unsupported_format";
    return false;
  }

  D3D11_TEXTURE2D_DESC staging_desc = source_desc;
  staging_desc.Usage = D3D11_USAGE_STAGING;
  staging_desc.BindFlags = 0;
  staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging_desc.MiscFlags = 0;

  ComPtr<ID3D11Texture2D> staging;
  HRESULT hr = g_capture.device->CreateTexture2D(&staging_desc, nullptr,
                                                 &staging);
  if (FAILED(hr)) {
    g_stats.last_error = "staging_texture_create_failed";
    return false;
  }

  const int64_t start = NowQpc();
  g_capture.context->CopyResource(staging.Get(), texture);
  D3D11_MAPPED_SUBRESOURCE mapped{};
  hr = g_capture.context->Map(staging.Get(), 0, D3D11_MAP_READ,
                              D3D11_MAP_FLAG_DO_NOT_WAIT, &mapped);
  if (FAILED(hr)) {
    if (hr == DXGI_ERROR_WAS_STILL_DRAWING) {
      ++g_stats.proof_export_busy_frames;
      return false;
    }
    g_stats.last_error = "staging_map_failed";
    return false;
  }

  ++g_stats.cpu_readback_count;
  const bool visible = LooksVisible(mapped, source_desc.Width,
                                    source_desc.Height, source_desc.Format);
  if (visible) {
    ++g_stats.visible_frames;
  }

  fs::create_directories(g_config.output_dir / L"frames");
  std::wostringstream name;
  name << L"frame-" << std::setw(6) << std::setfill(L'0')
       << (g_stats.saved_frames + 1) << L"-slot" << slot_index << L".png";
  bool wrote = false;
  if (IsR10G10B10A2(source_desc.Format)) {
    std::vector<BYTE> rgba8(static_cast<size_t>(source_desc.Width) *
                            static_cast<size_t>(source_desc.Height) * 4u);
    for (UINT y = 0; y < source_desc.Height; ++y) {
      const auto* src_row =
          static_cast<const uint8_t*>(mapped.pData) + y * mapped.RowPitch;
      auto* dst_row =
          rgba8.data() + static_cast<size_t>(y) * source_desc.Width * 4u;
      for (UINT x = 0; x < source_desc.Width; ++x) {
        const uint32_t packed =
            *reinterpret_cast<const uint32_t*>(src_row + x * 4u);
        BYTE* dst = dst_row + x * 4u;
        dst[0] = TenBitToEightBit((packed >> 20) & 0x3ffu);
        dst[1] = TenBitToEightBit((packed >> 10) & 0x3ffu);
        dst[2] = TenBitToEightBit(packed & 0x3ffu);
        dst[3] = static_cast<BYTE>(((packed >> 30) & 0x3u) * 85u);
      }
    }
    wrote = WritePng(g_config.output_dir / L"frames" / name.str(),
                     source_desc.Width, source_desc.Height,
                     source_desc.Width * 4u, rgba8.data(),
                     DXGI_FORMAT_R8G8B8A8_UNORM);
  } else {
    wrote = WritePng(g_config.output_dir / L"frames" / name.str(),
                     source_desc.Width, source_desc.Height, mapped.RowPitch,
                     static_cast<BYTE*>(mapped.pData), source_desc.Format);
  }
  g_capture.context->Unmap(staging.Get(), 0);
  const int64_t end = NowQpc();
  g_stats.export_ms.push_back(QpcToMs(end - start));
  if (wrote) {
    ++g_stats.saved_frames;
  }
  return wrote;
}

bool EnsureRing(ID3D11Device* device, const D3D11_TEXTURE2D_DESC& back_desc) {
  if (g_capture.device.Get() == device && g_capture.width == back_desc.Width &&
      g_capture.height == back_desc.Height &&
      g_capture.format == back_desc.Format &&
      g_capture.sample_count == back_desc.SampleDesc.Count) {
    return true;
  }

  ++g_stats.resize_count;
  g_capture = CaptureState{};
  g_capture.device = device;
  g_capture.device->GetImmediateContext(&g_capture.context);
  g_capture.width = back_desc.Width;
  g_capture.height = back_desc.Height;
  g_capture.format = back_desc.Format;
  g_capture.sample_count = back_desc.SampleDesc.Count;
  g_stats.detected_graphics_api = "d3d11";

  D3D11_TEXTURE2D_DESC texture_desc{};
  texture_desc.Width = back_desc.Width;
  texture_desc.Height = back_desc.Height;
  texture_desc.MipLevels = 1;
  texture_desc.ArraySize = 1;
  texture_desc.Format = back_desc.Format;
  texture_desc.SampleDesc.Count = 1;
  texture_desc.SampleDesc.Quality = 0;
  texture_desc.Usage = D3D11_USAGE_DEFAULT;
  texture_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  texture_desc.CPUAccessFlags = 0;
  texture_desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  bool created_shared = true;
  for (auto& slot : g_capture.ring) {
    HRESULT hr = device->CreateTexture2D(&texture_desc, nullptr, &slot.texture);
    if (FAILED(hr)) {
      created_shared = false;
      break;
    }
    ComPtr<IDXGIResource> resource;
    if (SUCCEEDED(slot.texture.As(&resource))) {
      resource->GetSharedHandle(&slot.shared_handle);
    }
  }

  if (!created_shared) {
    texture_desc.MiscFlags = 0;
    for (auto& slot : g_capture.ring) {
      slot = RingSlot{};
      HRESULT hr = device->CreateTexture2D(&texture_desc, nullptr,
                                           &slot.texture);
      if (FAILED(hr)) {
        g_stats.fallback_reason = "shared_texture_ring_create_failed";
        g_stats.last_error = "ring_texture_create_failed";
        return false;
      }
    }
  }
  g_capture.shared_texture_supported = created_shared;
  PublishRingState();

  if (back_desc.SampleDesc.Count > 1) {
    D3D11_TEXTURE2D_DESC resolve_desc = texture_desc;
    resolve_desc.MiscFlags = 0;
    HRESULT hr =
        device->CreateTexture2D(&resolve_desc, nullptr,
                                &g_capture.resolve_texture);
    if (FAILED(hr)) {
      g_stats.fallback_reason = "resolve_texture_create_failed";
      g_stats.last_error = "resolve_texture_create_failed";
      return false;
    }
  }

  AppendLog("ring_ready width=" + std::to_string(back_desc.Width) +
            " height=" + std::to_string(back_desc.Height) +
            " format=" + FormatName(back_desc.Format) +
            " shared=" + (created_shared ? "true" : "false"));
  return true;
}

void WritePresentEvent(uint64_t frame_index,
                       UINT slot_index,
                       double gap_ms,
                       double copy_ms,
                       double resolve_ms,
                       bool dropped,
                       bool overwritten,
                       bool saved) {
  std::ofstream file(g_config.output_dir / L"present-events.jsonl",
                     std::ios::app);
  const iggc::SourceFormat source_format =
      iggc::SourceFormatFromDxgiFormat(static_cast<uint32_t>(g_capture.format));
  const iggc::FailureReason failure_reason =
      g_capture.shared_texture_supported
          ? iggc::FailureReason::kNone
          : iggc::FailureReason::kSharedTextureUnavailable;
  file << "{\"schema\":\"intergalactic.gameCapturePresent.v1\","
       << "\"sessionId\":\"" << JsonEscape(g_config.session_id) << "\","
       << "\"frameIndex\":" << frame_index << ","
       << "\"qpc\":" << g_stats.last_qpc << ","
       << "\"gapMs\":" << std::fixed << std::setprecision(3) << gap_ms
       << ",\"slotIndex\":" << slot_index
       << ",\"dropped\":" << (dropped ? "true" : "false")
       << ",\"overwritten\":" << (overwritten ? "true" : "false")
       << ",\"saved\":" << (saved ? "true" : "false")
       << ",\"graphicsApi\":\"" << g_stats.detected_graphics_api << "\""
       << ",\"backendContractVersion\":" << iggc::kSharedTextureStateVersion
       << ",\"sourceApi\":\""
       << iggc::CaptureBackendName(iggc::CaptureBackend::kD3D11PresentHook)
       << "\""
       << ",\"sourceApiId\":"
       << static_cast<uint32_t>(iggc::CaptureBackend::kD3D11PresentHook)
       << ",\"sourceFormat\":\"" << iggc::SourceFormatName(source_format)
       << "\""
       << ",\"sourceFormatId\":" << static_cast<uint32_t>(source_format)
       << ",\"colorSpace\":\""
       << iggc::ColorSpaceName(iggc::ColorSpace::kUnknown) << "\""
       << ",\"syncKind\":\"" << iggc::SyncKindName(iggc::SyncKind::kEvent)
       << "\""
       << ",\"readyState\":\""
       << iggc::FrameReadyStateName(dropped ? iggc::FrameReadyState::kFailed
                                            : iggc::FrameReadyState::kReady)
       << "\""
       << ",\"failureReason\":\"" << iggc::FailureReasonName(failure_reason)
       << "\""
       << ",\"backbufferWidth\":" << g_capture.width
       << ",\"backbufferHeight\":" << g_capture.height
       << ",\"backbufferFormat\":\"" << FormatName(g_capture.format) << "\""
       << ",\"sampleCount\":" << g_capture.sample_count
       << ",\"sharedTextureRingDepth\":" << iggc::kRingDepth
       << ",\"sharedTextureSupported\":"
       << (g_capture.shared_texture_supported ? "true" : "false")
       << ",\"copyMs\":" << copy_ms << ",\"resolveMs\":" << resolve_ms
       << ",\"cpuReadbackCount\":" << g_stats.cpu_readback_count << "}\n";
}

void CaptureSwapChain(IDXGISwapChain* swap_chain) {
  if (g_stop_requested.load()) {
    return;
  }

  static thread_local bool inside_hook = false;
  if (inside_hook) {
    return;
  }
  inside_hook = true;

  std::lock_guard<std::mutex> lock(g_capture_mutex);
  const int64_t present_qpc = NowQpc();
  ++g_stats.present_count;
  if (g_stats.first_qpc == 0) {
    g_stats.first_qpc = present_qpc;
  }
  double gap_ms = 0.0;
  if (g_stats.previous_present_qpc != 0) {
    const int64_t present_delta_qpc =
        present_qpc - g_stats.previous_present_qpc;
    gap_ms = QpcToMs(present_delta_qpc);
    g_stats.present_gaps_ms.push_back(gap_ms);
    if (present_delta_qpc > 0) {
      RecordQpcMetric(static_cast<uint64_t>(present_delta_qpc),
                      &g_stats.present_gap_qpc_total,
                      &g_stats.present_gap_qpc_max,
                      &g_stats.present_gap_samples);
    }
  }
  g_stats.previous_present_qpc = present_qpc;
  g_stats.last_qpc = present_qpc;

  if (g_config.target_capture_fps > 0 && g_stats.last_capture_qpc != 0) {
    const int64_t interval_qpc =
        std::max<int64_t>(1, g_qpc_frequency.QuadPart /
                                 g_config.target_capture_fps);
    const int64_t tolerance_qpc =
        std::max<int64_t>(1, g_qpc_frequency.QuadPart / 1000);
    if (g_stats.next_capture_qpc > 0 &&
        present_qpc + tolerance_qpc < g_stats.next_capture_qpc) {
      ++g_stats.throttled_frames;
      inside_hook = false;
      return;
    }
  }

  ComPtr<ID3D11Texture2D> backbuffer;
  HRESULT hr = swap_chain->GetBuffer(0, IID_PPV_ARGS(&backbuffer));
  if (FAILED(hr)) {
    ++g_stats.dropped_frames;
    g_stats.last_error = "swapchain_getbuffer_failed";
    WritePresentEvent(g_stats.present_count, 0, gap_ms, 0.0, 0.0, true, false,
                      false);
    inside_hook = false;
    return;
  }

  ComPtr<ID3D11Device> device;
  hr = swap_chain->GetDevice(IID_PPV_ARGS(&device));
  if (FAILED(hr)) {
    ++g_stats.dropped_frames;
    g_stats.last_error = "swapchain_getdevice_d3d11_failed";
    WritePresentEvent(g_stats.present_count, 0, gap_ms, 0.0, 0.0, true, false,
                      false);
    inside_hook = false;
    return;
  }

  D3D11_TEXTURE2D_DESC back_desc{};
  backbuffer->GetDesc(&back_desc);
  if (!EnsureRing(device.Get(), back_desc)) {
    ++g_stats.dropped_frames;
    WritePresentEvent(g_stats.present_count, 0, gap_ms, 0.0, 0.0, true, false,
                      false);
    inside_hook = false;
    return;
  }

  const uint64_t capture_index = ++g_stats.captured_frame_count;
  const UINT slot_index =
      static_cast<UINT>((capture_index - 1) % iggc::kRingDepth);
  RingSlot& slot = g_capture.ring[slot_index];
  const bool overwritten = slot.has_frame;
  if (overwritten) {
    ++g_stats.overwritten_frames;
  }

  ID3D11Texture2D* copy_source = backbuffer.Get();
  double resolve_ms = 0.0;
  if (back_desc.SampleDesc.Count > 1 && g_capture.resolve_texture) {
    const int64_t resolve_start = NowQpc();
    g_capture.context->ResolveSubresource(g_capture.resolve_texture.Get(), 0,
                                          backbuffer.Get(), 0,
                                          back_desc.Format);
    const int64_t resolve_end = NowQpc();
    const int64_t resolve_delta_qpc = resolve_end - resolve_start;
    resolve_ms = QpcToMs(resolve_delta_qpc);
    g_stats.resolve_ms.push_back(resolve_ms);
    if (resolve_delta_qpc > 0) {
      RecordQpcMetric(static_cast<uint64_t>(resolve_delta_qpc),
                      &g_stats.resolve_qpc_total,
                      &g_stats.resolve_qpc_max,
                      &g_stats.resolve_qpc_samples);
    }
    copy_source = g_capture.resolve_texture.Get();
  }

  const int64_t copy_start = NowQpc();
  g_capture.context->CopyResource(slot.texture.Get(), copy_source);
  const int64_t copy_end = NowQpc();
  const int64_t copy_delta_qpc = copy_end - copy_start;
  const double copy_ms = QpcToMs(copy_delta_qpc);
  g_stats.copy_ms.push_back(copy_ms);
  if (copy_delta_qpc > 0) {
    RecordQpcMetric(static_cast<uint64_t>(copy_delta_qpc),
                    &g_stats.copy_qpc_total, &g_stats.copy_qpc_max,
                    &g_stats.copy_qpc_samples);
  }
  if (g_config.host_consumer_enabled || g_shared_state != nullptr) {
    g_capture.context->Flush();
  }
  ++g_stats.copied_frames;
  if (g_config.target_capture_fps > 0) {
    const int64_t interval_qpc =
        std::max<int64_t>(1, g_qpc_frequency.QuadPart /
                                 g_config.target_capture_fps);
    if (g_stats.next_capture_qpc == 0 ||
        present_qpc - g_stats.next_capture_qpc > interval_qpc * 4) {
      g_stats.next_capture_qpc = present_qpc + interval_qpc;
    } else {
      do {
        g_stats.next_capture_qpc += interval_qpc;
      } while (g_stats.next_capture_qpc <= present_qpc);
    }
  }
  if (g_stats.last_capture_qpc != 0 &&
      present_qpc > g_stats.last_capture_qpc) {
    RecordQpcMetric(static_cast<uint64_t>(present_qpc -
                                          g_stats.last_capture_qpc),
                    &g_stats.capture_gap_qpc_total,
                    &g_stats.capture_gap_qpc_max,
                    &g_stats.capture_gap_samples);
  }
  g_stats.last_capture_qpc = present_qpc;
  slot.has_frame = true;
  slot.frame_index = capture_index;

  PublishLatestFrameState(slot_index, capture_index);
  const bool saved = SaveFramePng(slot.texture.Get(), slot_index);
  WritePresentEvent(g_stats.present_count, slot_index, gap_ms, copy_ms,
                    resolve_ms, false, overwritten, saved);
  inside_hook = false;
}

HRESULT STDMETHODCALLTYPE HookPresent(IDXGISwapChain* swap_chain,
                                      UINT sync_interval,
                                      UINT flags) {
  CaptureSwapChain(swap_chain);
  return g_original_present(swap_chain, sync_interval, flags);
}

HRESULT STDMETHODCALLTYPE HookPresent1(IDXGISwapChain1* swap_chain,
                                       UINT sync_interval,
                                       UINT flags,
                                       const DXGI_PRESENT_PARAMETERS* params) {
  CaptureSwapChain(swap_chain);
  return g_original_present1(swap_chain, sync_interval, flags, params);
}

bool InstallHooks() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = DefWindowProcW;
  window_class.hInstance = g_module;
  window_class.lpszClassName = L"InterGalacticGameCaptureDummyWindow";
  RegisterClassW(&window_class);
  HWND hwnd = CreateWindowExW(0, window_class.lpszClassName, L"", WS_OVERLAPPED,
                              0, 0, 16, 16, nullptr, nullptr, g_module,
                              nullptr);
  if (hwnd == nullptr) {
    g_stats.last_error = "dummy_window_create_failed";
    return false;
  }

  DXGI_SWAP_CHAIN_DESC swap_desc{};
  swap_desc.BufferDesc.Width = 16;
  swap_desc.BufferDesc.Height = 16;
  swap_desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  swap_desc.SampleDesc.Count = 1;
  swap_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swap_desc.BufferCount = 1;
  swap_desc.OutputWindow = hwnd;
  swap_desc.Windowed = TRUE;
  swap_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

  D3D_FEATURE_LEVEL feature_level{};
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<IDXGISwapChain> swap_chain;
  HRESULT hr = D3D11CreateDeviceAndSwapChain(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
      D3D11_SDK_VERSION, &swap_desc, &swap_chain, &device, &feature_level,
      &context);
  if (FAILED(hr)) {
    DestroyWindow(hwnd);
    g_stats.last_error = "dummy_swapchain_create_failed";
    return false;
  }

  void** vtable = *reinterpret_cast<void***>(swap_chain.Get());
  bool ok = PatchVtableSlot(&vtable[8], reinterpret_cast<void*>(&HookPresent),
                            reinterpret_cast<void**>(&g_original_present));
  g_present_slot = &vtable[8];

  ComPtr<IDXGISwapChain1> swap_chain1;
  if (SUCCEEDED(swap_chain.As(&swap_chain1))) {
    void** vtable1 = *reinterpret_cast<void***>(swap_chain1.Get());
    if (PatchVtableSlot(&vtable1[22],
                        reinterpret_cast<void*>(&HookPresent1),
                        reinterpret_cast<void**>(&g_original_present1))) {
      g_present1_slot = &vtable1[22];
    }
  }

  DestroyWindow(hwnd);
  if (!ok) {
    g_stats.last_error = "present_hook_patch_failed";
    return false;
  }

  g_hook_installed = true;
  AppendLog("hooks_installed present=true present1=" +
            std::string(g_present1_slot != nullptr ? "true" : "false"));
  return true;
}

void UninstallHooks(bool write_log = true) {
  if (!g_hook_installed.exchange(false)) {
    return;
  }
  RestoreVtableSlot(g_present1_slot, reinterpret_cast<void*>(&HookPresent1),
                    reinterpret_cast<void*>(g_original_present1));
  RestoreVtableSlot(g_present_slot, reinterpret_cast<void*>(&HookPresent),
                    reinterpret_cast<void*>(g_original_present));
  if (write_log) {
    AppendLog("hooks_uninstalled");
  }
}

double Percentile(std::vector<double> values, double percentile) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  const double raw = percentile * static_cast<double>(values.size() - 1);
  const auto index = static_cast<size_t>(std::round(raw));
  return values[std::min(index, values.size() - 1)];
}

double Average(const std::vector<double>& values) {
  if (values.empty()) {
    return 0.0;
  }
  double sum = 0.0;
  for (double value : values) {
    sum += value;
  }
  return sum / static_cast<double>(values.size());
}

double MaxValue(const std::vector<double>& values) {
  if (values.empty()) {
    return 0.0;
  }
  return *std::max_element(values.begin(), values.end());
}

void WritePreviewHtml() {
  std::ofstream file(g_config.output_dir / L"preview.html");
  file << "<!doctype html><meta charset=\"utf-8\"><title>Inter Galactic Game "
          "Capture POC</title><body><h1>Inter Galactic Game Capture "
          "POC</h1>\n";
  for (uint64_t i = 1; i <= g_stats.saved_frames; ++i) {
    file << "<img style=\"max-width:480px;margin:8px;border:1px solid #444\" "
            "src=\"frames/frame-"
         << std::setw(6) << std::setfill('0') << i
         << "-slot" << ((i - 1) % iggc::kRingDepth) << ".png\">\n";
  }
  file << "</body>\n";
}

void WriteSummary() {
  const double duration_ms =
      g_stats.first_qpc == 0 || g_stats.last_qpc <= g_stats.first_qpc
          ? 0.0
          : QpcToMs(g_stats.last_qpc - g_stats.first_qpc);
  const double fps = duration_ms <= 0.0
                         ? 0.0
                         : (static_cast<double>(g_stats.present_count - 1) *
                            1000.0 / duration_ms);
  const double p50 = Percentile(g_stats.present_gaps_ms, 0.50);
  const double p95 = Percentile(g_stats.present_gaps_ms, 0.95);
  const double pmax = MaxValue(g_stats.present_gaps_ms);
  const double copy_avg = Average(g_stats.copy_ms);
  const double copy_max = MaxValue(g_stats.copy_ms);
  const double resolve_avg = Average(g_stats.resolve_ms);
  const double resolve_max = MaxValue(g_stats.resolve_ms);
  const iggc::SourceFormat source_format =
      iggc::SourceFormatFromDxgiFormat(static_cast<uint32_t>(g_capture.format));
  const iggc::FailureReason failure_reason =
      g_capture.shared_texture_supported
          ? iggc::FailureReason::kNone
          : iggc::FailureReason::kSharedTextureUnavailable;

  const auto metadata_path = g_config.output_dir / L"metadata.json";
  {
    std::ofstream file(metadata_path);
    file << "{\n"
         << "  \"schema\": \"intergalactic.gameCapturePoc.v1\",\n"
         << "  \"sessionId\": \"" << JsonEscape(g_config.session_id)
         << "\",\n"
         << "  \"requestedBackend\": \"d3d11-present-hook\",\n"
         << "  \"backendContractVersion\": "
         << iggc::kSharedTextureStateVersion << ",\n"
         << "  \"sourceApi\": \""
         << iggc::CaptureBackendName(iggc::CaptureBackend::kD3D11PresentHook)
         << "\",\n"
         << "  \"sourceApiId\": "
         << static_cast<uint32_t>(iggc::CaptureBackend::kD3D11PresentHook)
         << ",\n"
         << "  \"sourceFormat\": \"" << iggc::SourceFormatName(source_format)
         << "\",\n"
         << "  \"sourceFormatId\": " << static_cast<uint32_t>(source_format)
         << ",\n"
         << "  \"colorSpace\": \""
         << iggc::ColorSpaceName(iggc::ColorSpace::kUnknown) << "\",\n"
         << "  \"syncKind\": \"" << iggc::SyncKindName(iggc::SyncKind::kEvent)
         << "\",\n"
         << "  \"readyState\": \""
         << iggc::FrameReadyStateName(g_capture.shared_texture_supported
                                          ? iggc::FrameReadyState::kReady
                                          : iggc::FrameReadyState::kFailed)
         << "\",\n"
         << "  \"failureReason\": \""
         << iggc::FailureReasonName(failure_reason) << "\",\n"
         << "  \"attachStatus\": \"attached\",\n"
         << "  \"detectedGraphicsApi\": \""
         << JsonEscape(g_stats.detected_graphics_api) << "\",\n"
         << "  \"endedAt\": \"" << NowIsoUtc() << "\",\n"
         << "  \"presentFrameCount\": " << g_stats.present_count << ",\n"
         << "  \"presentFps\": " << std::fixed << std::setprecision(3) << fps
         << ",\n"
         << "  \"presentGapP50Ms\": " << p50 << ",\n"
         << "  \"presentGapP95Ms\": " << p95 << ",\n"
         << "  \"presentGapMaxMs\": " << pmax << ",\n"
         << "  \"backbufferWidth\": " << g_capture.width << ",\n"
         << "  \"backbufferHeight\": " << g_capture.height << ",\n"
         << "  \"backbufferFormat\": \"" << FormatName(g_capture.format)
         << "\",\n"
         << "  \"sharedTextureRingDepth\": " << iggc::kRingDepth << ",\n"
         << "  \"sharedTextureSupported\": "
         << (g_capture.shared_texture_supported ? "true" : "false") << ",\n"
         << "  \"copyAvgMs\": " << copy_avg << ",\n"
         << "  \"copyMaxMs\": " << copy_max << ",\n"
         << "  \"resolveAvgMs\": " << resolve_avg << ",\n"
         << "  \"resolveMaxMs\": " << resolve_max << ",\n"
         << "  \"copiedFrames\": " << g_stats.copied_frames << ",\n"
         << "  \"droppedFrames\": " << g_stats.dropped_frames << ",\n"
         << "  \"overwrittenFrames\": " << g_stats.overwritten_frames
         << ",\n"
         << "  \"throttledFrames\": " << g_stats.throttled_frames << ",\n"
         << "  \"cpuReadbackCount\": " << g_stats.cpu_readback_count
         << ",\n"
         << "  \"proofExportBusyFrames\": "
         << g_stats.proof_export_busy_frames << ",\n"
         << "  \"savedFrames\": " << g_stats.saved_frames << ",\n"
         << "  \"visibleFrames\": " << g_stats.visible_frames << ",\n"
         << "  \"resizeDeviceLossCount\": " << g_stats.resize_count << ",\n"
         << "  \"fallbackReason\": \"" << JsonEscape(g_stats.fallback_reason)
         << "\",\n"
         << "  \"hookStopReason\": \"" << JsonEscape(g_stats.hook_stop_reason)
         << "\",\n"
         << "  \"lastError\": \"" << JsonEscape(g_stats.last_error) << "\"\n"
         << "}\n";
  }

  {
    std::ofstream file(g_config.output_dir / L"summary.md");
    file << "# D3D11 Game Capture POC\n\n"
         << "- Attach status: attached\n"
         << "- Backend contract: v" << iggc::kSharedTextureStateVersion
         << " api="
         << iggc::CaptureBackendName(iggc::CaptureBackend::kD3D11PresentHook)
         << " source_format=" << iggc::SourceFormatName(source_format)
         << " color_space="
         << iggc::ColorSpaceName(iggc::ColorSpace::kUnknown)
         << " sync=" << iggc::SyncKindName(iggc::SyncKind::kEvent)
         << " ready="
         << iggc::FrameReadyStateName(g_capture.shared_texture_supported
                                          ? iggc::FrameReadyState::kReady
                                          : iggc::FrameReadyState::kFailed)
         << " failure=" << iggc::FailureReasonName(failure_reason) << "\n"
         << "- Detected graphics API: " << g_stats.detected_graphics_api
         << "\n"
         << "- Present FPS: " << std::fixed << std::setprecision(2) << fps
         << "\n"
         << "- Present gaps p50/p95/max: " << p50 << " / " << p95 << " / "
         << pmax << " ms\n"
         << "- Backbuffer: " << g_capture.width << "x" << g_capture.height
         << " " << FormatName(g_capture.format) << "\n"
         << "- Shared texture ring depth: " << iggc::kRingDepth << "\n"
         << "- Shared texture supported: "
         << (g_capture.shared_texture_supported ? "true" : "false") << "\n"
         << "- Copy avg/max: " << copy_avg << " / " << copy_max << " ms\n"
         << "- Resolve avg/max: " << resolve_avg << " / " << resolve_max
         << " ms\n"
         << "- Frames copied/dropped/overwritten: " << g_stats.copied_frames
         << " / " << g_stats.dropped_frames << " / "
         << g_stats.overwritten_frames << "\n"
         << "- Frames throttled: " << g_stats.throttled_frames << "\n"
         << "- CPU readback count: " << g_stats.cpu_readback_count
         << " (local PNG export only)\n"
         << "- Proof export busy frames: "
         << g_stats.proof_export_busy_frames << "\n"
         << "- Saved/visible frames: " << g_stats.saved_frames << " / "
         << g_stats.visible_frames << "\n"
         << "- Fallback reason: " << g_stats.fallback_reason << "\n"
         << "- Hook stop reason: " << g_stats.hook_stop_reason << "\n"
         << "- Last error: " << g_stats.last_error << "\n";
  }

  WritePreviewHtml();
}

DWORD WINAPI HookThreadMain(void*) {
  QueryPerformanceFrequency(&g_qpc_frequency);
  if (!LoadConfig()) {
    return 1;
  }

  fs::create_directories(g_config.output_dir / L"frames");
  AppendLog("hook_thread_start session=" + g_config.session_id);
  OpenHostConsumerState();
  HANDLE stop_event = nullptr;
  HANDLE stopped_event = nullptr;
  if (!g_config.stop_event_name.empty()) {
    stop_event = OpenEventW(SYNCHRONIZE, FALSE, g_config.stop_event_name.c_str());
  }
  if (!g_config.stopped_event_name.empty()) {
    stopped_event = OpenEventW(EVENT_MODIFY_STATE, FALSE,
                               g_config.stopped_event_name.c_str());
  }

  if (!InstallHooks()) {
    g_stats.hook_stop_reason = "install_failed";
    g_stats.fallback_reason = "hook_install_failed";
    WriteSummary();
    if (stopped_event != nullptr) {
      SetEvent(stopped_event);
      CloseHandle(stopped_event);
    }
    if (stop_event != nullptr) {
      CloseHandle(stop_event);
    }
    return 2;
  }

  AppendLog("hook_wait_begin durationMs=" +
            std::to_string(g_config.duration_ms) +
            " stopEvent=" +
            std::string(stop_event != nullptr ? "true" : "false"));
  DWORD wait_result = WAIT_TIMEOUT;
  if (stop_event == nullptr) {
    Sleep(static_cast<DWORD>(g_config.duration_ms));
  } else {
    wait_result =
        WaitForSingleObject(stop_event, static_cast<DWORD>(g_config.duration_ms));
  }
  AppendLog("hook_wait_done result=" + std::to_string(wait_result));
  g_stop_requested = true;
  g_stats.hook_stop_reason =
      wait_result == WAIT_TIMEOUT ? "duration_elapsed" : "stop_event";
  UninstallHooks();
  WriteSummary();
  CloseHostConsumerState();

  if (stopped_event != nullptr) {
    SetEvent(stopped_event);
    CloseHandle(stopped_event);
  }
  if (stop_event != nullptr) {
    CloseHandle(stop_event);
  }
  AppendLog("hook_thread_stop reason=" + g_stats.hook_stop_reason);
  return 0;
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
    HANDLE thread = CreateThread(nullptr, 0, HookThreadMain, nullptr, 0,
                                 nullptr);
    if (thread != nullptr) {
      CloseHandle(thread);
    }
  } else if (reason == DLL_PROCESS_DETACH) {
    g_stop_requested = true;
    UninstallHooks(false);
    CloseHostConsumerState();
  }
  return TRUE;
}
