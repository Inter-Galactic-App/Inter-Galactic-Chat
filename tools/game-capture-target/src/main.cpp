#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <shellapi.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <iomanip>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kWindowClassName[] = L"InterGalacticCaptureTargetWindow";
constexpr wchar_t kDefaultTitle[] = L"Inter Galactic Capture Target";

enum class WindowMode {
  kWindowed,
  kBorderless,
};

enum class SceneMode {
  kLowMotion,
  kHighMotion,
  kGameplay,
  kUiHeavy,
};

enum class SwapChainFormat {
  kR8G8B8A8,
  kR10G10B10A2,
};

struct Config {
  int width = 1920;
  int height = 1080;
  WindowMode windowMode = WindowMode::kWindowed;
  SceneMode scene = SceneMode::kGameplay;
  SwapChainFormat format = SwapChainFormat::kR8G8B8A8;
  bool hdrLike = false;
  int fps = 60;
  bool uncapped = false;
  int durationMs = 0;
  std::wstring title = kDefaultTitle;
  std::wstring outputDir;
};

struct Metrics {
  uint64_t frames = 0;
  uint64_t lateFrames = 0;
  uint64_t missedFrameIntervals = 0;
  double totalRenderMs = 0.0;
  double totalPresentMs = 0.0;
  double maxPresentGapMs = 0.0;
  std::vector<double> presentGapsMs;
};

struct FrameConstants {
  float resolution[2];
  float timeSeconds;
  float targetFps;
  uint32_t frame;
  uint32_t scene;
  uint32_t hdrLike;
  float padding[1];
};

bool g_running = true;

std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(towlower(c));
  });
  return value;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
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

std::wstring JoinPath(const std::wstring& a, const std::wstring& b) {
  if (a.empty()) {
    return b;
  }
  if (a.back() == L'\\' || a.back() == L'/') {
    return a + b;
  }
  return a + L"\\" + b;
}

bool DirectoryExists(const std::wstring& path) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool CreateDirectoryRecursive(const std::wstring& path) {
  if (path.empty() || DirectoryExists(path)) {
    return true;
  }
  const size_t slash = path.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    const std::wstring parent = path.substr(0, slash);
    if (!parent.empty() && parent.back() != L':' &&
        !CreateDirectoryRecursive(parent)) {
      return false;
    }
  }
  if (CreateDirectoryW(path.c_str(), nullptr) || DirectoryExists(path)) {
    return true;
  }
  return GetLastError() == ERROR_ALREADY_EXISTS;
}

std::wstring NowStamp() {
  SYSTEMTIME time;
  GetSystemTime(&time);
  wchar_t buffer[64];
  swprintf_s(buffer, L"%04u%02u%02u-%02u%02u%02u-%03u",
             time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute,
             time.wSecond, time.wMilliseconds);
  return buffer;
}

std::wstring DefaultOutputDir() {
  wchar_t appData[MAX_PATH] = {};
  const DWORD len = GetEnvironmentVariableW(L"APPDATA", appData, MAX_PATH);
  std::wstring root = len > 0 ? std::wstring(appData, len) : L".";
  return JoinPath(
      JoinPath(
          JoinPath(
              JoinPath(
                  JoinPath(root, L"Inter Galactic"),
                  L"Inter Galactic"),
              L"logs"),
          L"stream-tests"),
      JoinPath(L"capture-targets", NowStamp() + L"-" +
                                       std::to_wstring(GetCurrentProcessId())));
}

bool WriteTextFile(const std::wstring& path, const std::string& text) {
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || file == nullptr) {
    return false;
  }
  const size_t written = fwrite(text.data(), 1, text.size(), file);
  fclose(file);
  return written == text.size();
}

std::wstring StringValue(const std::map<std::wstring, std::wstring>& args,
                         const std::wstring& key,
                         const std::wstring& fallback) {
  const auto it = args.find(key);
  return it == args.end() ? fallback : it->second;
}

int IntValue(const std::map<std::wstring, std::wstring>& args,
             const std::wstring& key,
             int fallback) {
  const auto it = args.find(key);
  if (it == args.end()) {
    return fallback;
  }
  try {
    return std::stoi(it->second);
  } catch (...) {
    return fallback;
  }
}

std::map<std::wstring, std::wstring> ParseArgs() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::map<std::wstring, std::wstring> args;
  if (argv == nullptr) {
    return args;
  }
  for (int i = 1; i < argc; ++i) {
    std::wstring token = argv[i];
    if (token.rfind(L"--", 0) != 0) {
      continue;
    }
    token = token.substr(2);
    std::wstring key;
    std::wstring value;
    const size_t equals = token.find(L'=');
    if (equals == std::wstring::npos) {
      key = token;
      if (i + 1 < argc && std::wstring(argv[i + 1]).rfind(L"--", 0) != 0) {
        value = argv[++i];
      } else {
        value = L"true";
      }
    } else {
      key = token.substr(0, equals);
      value = token.substr(equals + 1);
    }
    args[ToLower(key)] = value;
  }
  LocalFree(argv);
  return args;
}

Config ParseConfig() {
  const auto args = ParseArgs();
  Config config;
  config.width = std::clamp(IntValue(args, L"width", config.width), 320, 7680);
  config.height =
      std::clamp(IntValue(args, L"height", config.height), 240, 4320);
  config.title = StringValue(args, L"title", config.title);
  config.outputDir = StringValue(args, L"output-dir", L"");

  const auto mode = ToLower(StringValue(args, L"mode", L"windowed"));
  config.windowMode =
      mode == L"borderless" ? WindowMode::kBorderless : WindowMode::kWindowed;

  const auto scene = ToLower(StringValue(args, L"scene", L"gameplay"));
  if (scene == L"low-motion") {
    config.scene = SceneMode::kLowMotion;
  } else if (scene == L"high-motion") {
    config.scene = SceneMode::kHighMotion;
  } else if (scene == L"ui-heavy") {
    config.scene = SceneMode::kUiHeavy;
  } else {
    config.scene = SceneMode::kGameplay;
  }

  const auto format = ToLower(StringValue(args, L"format", L"r8g8b8a8"));
  if (format == L"r10g10b10a2" || format == L"r10") {
    config.format = SwapChainFormat::kR10G10B10A2;
  } else {
    config.format = SwapChainFormat::kR8G8B8A8;
  }
  config.hdrLike = ToLower(StringValue(args, L"hdr-like", L"false")) == L"true";

  const auto fps = ToLower(StringValue(args, L"fps", L"60"));
  config.uncapped = fps == L"uncapped";
  config.fps = config.uncapped ? 0 : std::clamp(_wtoi(fps.c_str()), 1, 240);

  config.durationMs = IntValue(args, L"duration-ms", -1);
  if (config.durationMs < 0) {
    const int durationSeconds = IntValue(args, L"duration", 0);
    config.durationMs = std::max(0, durationSeconds * 1000);
  }
  if (config.outputDir.empty()) {
    config.outputDir = DefaultOutputDir();
  }
  return config;
}

const char* SceneName(SceneMode scene) {
  switch (scene) {
    case SceneMode::kLowMotion:
      return "low-motion";
    case SceneMode::kHighMotion:
      return "high-motion";
    case SceneMode::kGameplay:
      return "gameplay";
    case SceneMode::kUiHeavy:
      return "ui-heavy";
  }
  return "unknown";
}

const char* FormatName(SwapChainFormat format) {
  switch (format) {
    case SwapChainFormat::kR8G8B8A8:
      return "r8g8b8a8";
    case SwapChainFormat::kR10G10B10A2:
      return "r10g10b10a2";
  }
  return "unknown";
}

DXGI_FORMAT DxgiFormat(SwapChainFormat format) {
  switch (format) {
    case SwapChainFormat::kR8G8B8A8:
      return DXGI_FORMAT_R8G8B8A8_UNORM;
    case SwapChainFormat::kR10G10B10A2:
      return DXGI_FORMAT_R10G10B10A2_UNORM;
  }
  return DXGI_FORMAT_R8G8B8A8_UNORM;
}

const char* WindowModeName(WindowMode mode) {
  return mode == WindowMode::kBorderless ? "borderless" : "windowed";
}

double Percentile(std::vector<double> values, double percentile) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  const double clamped = std::clamp(percentile, 0.0, 1.0);
  const size_t index = static_cast<size_t>(
      std::round(clamped * static_cast<double>(values.size() - 1)));
  return values[index];
}

std::string BuildDiagnosticsJson(const Config& config,
                                 const Metrics& metrics,
                                 double elapsedSeconds,
                                 HWND hwnd) {
  RECT client{};
  RECT window{};
  GetClientRect(hwnd, &client);
  GetWindowRect(hwnd, &window);

  const double presentFps =
      elapsedSeconds > 0.0 ? metrics.frames / elapsedSeconds : 0.0;
  const double renderFps = presentFps;
  const double avgRenderMs =
      metrics.frames > 0 ? metrics.totalRenderMs / metrics.frames : 0.0;
  const double avgPresentMs =
      metrics.frames > 0 ? metrics.totalPresentMs / metrics.frames : 0.0;

  std::ostringstream out;
  out << std::fixed << std::setprecision(3);
  out << "{\n";
  out << "  \"schema\": \"intergalactic.captureTarget.v1\",\n";
  out << "  \"processId\": " << GetCurrentProcessId() << ",\n";
  out << "  \"windowTitle\": \"" << JsonEscape(WideToUtf8(config.title))
      << "\",\n";
  out << "  \"windowMode\": \"" << WindowModeName(config.windowMode)
      << "\",\n";
  out << "  \"scene\": \"" << SceneName(config.scene) << "\",\n";
  out << "  \"swapChainFormat\": \"" << FormatName(config.format) << "\",\n";
  out << "  \"swapChainDxgiFormat\": "
      << static_cast<int>(DxgiFormat(config.format)) << ",\n";
  out << "  \"hdrLike\": " << (config.hdrLike ? "true" : "false")
      << ",\n";
  out << "  \"requestedWidth\": " << config.width << ",\n";
  out << "  \"requestedHeight\": " << config.height << ",\n";
  out << "  \"requestedFps\": "
      << (config.uncapped ? std::string("\"uncapped\"")
                          : std::to_string(config.fps))
      << ",\n";
  out << "  \"durationMs\": " << config.durationMs << ",\n";
  out << "  \"elapsedSeconds\": " << elapsedSeconds << ",\n";
  out << "  \"framesPresented\": " << metrics.frames << ",\n";
  out << "  \"presentFps\": " << presentFps << ",\n";
  out << "  \"renderFps\": " << renderFps << ",\n";
  out << "  \"presentGapP50Ms\": "
      << Percentile(metrics.presentGapsMs, 0.50) << ",\n";
  out << "  \"presentGapP95Ms\": "
      << Percentile(metrics.presentGapsMs, 0.95) << ",\n";
  out << "  \"presentGapMaxMs\": " << metrics.maxPresentGapMs << ",\n";
  out << "  \"averageRenderMs\": " << avgRenderMs << ",\n";
  out << "  \"averagePresentMs\": " << avgPresentMs << ",\n";
  out << "  \"lateFrames\": " << metrics.lateFrames << ",\n";
  out << "  \"missedFrameIntervals\": " << metrics.missedFrameIntervals
      << ",\n";
  out << "  \"windowRect\": {\"x\": " << window.left << ", \"y\": "
      << window.top << ", \"width\": " << (window.right - window.left)
      << ", \"height\": " << (window.bottom - window.top) << "},\n";
  out << "  \"clientSize\": {\"width\": " << (client.right - client.left)
      << ", \"height\": " << (client.bottom - client.top) << "},\n";
  out << "  \"swapChainSize\": {\"width\": " << config.width
      << ", \"height\": " << config.height << "}\n";
  out << "}\n";
  return out.str();
}

std::string BuildDiagnosticsMarkdown(const Config& config,
                                     const Metrics& metrics,
                                     double elapsedSeconds,
                                     HWND hwnd) {
  const auto json = BuildDiagnosticsJson(config, metrics, elapsedSeconds, hwnd);
  std::ostringstream out;
  out << "# Inter Galactic Capture Target\n\n";
  out << "- Title: " << WideToUtf8(config.title) << "\n";
  out << "- PID: " << GetCurrentProcessId() << "\n";
  out << "- Mode: " << WindowModeName(config.windowMode) << "\n";
  out << "- Scene: " << SceneName(config.scene) << "\n";
  out << "- Swap-chain format: " << FormatName(config.format) << "\n";
  out << "- HDR-like shader mode: " << (config.hdrLike ? "true" : "false")
      << "\n";
  out << "- Resolution: " << config.width << "x" << config.height << "\n";
  out << "- FPS cap: "
      << (config.uncapped ? std::string("uncapped") : std::to_string(config.fps))
      << "\n";
  out << "- Frames presented: " << metrics.frames << "\n\n";
  out << "```json\n" << json << "```\n";
  return out.str();
}

void WriteDiagnostics(const Config& config,
                      const Metrics& metrics,
                      double elapsedSeconds,
                      HWND hwnd) {
  if (!CreateDirectoryRecursive(config.outputDir)) {
    return;
  }
  const auto json = BuildDiagnosticsJson(config, metrics, elapsedSeconds, hwnd);
  const auto markdown =
      BuildDiagnosticsMarkdown(config, metrics, elapsedSeconds, hwnd);
  WriteTextFile(JoinPath(config.outputDir, L"capture-target.json"), json);
  WriteTextFile(JoinPath(config.outputDir, L"capture-target.md"), markdown);
}

const char kShaderSource[] = R"(
cbuffer FrameConstants : register(b0) {
  float2 resolution;
  float timeSeconds;
  float targetFps;
  uint frame;
  uint scene;
  uint hdrLike;
  float padding;
};

struct VsOut {
  float4 position : SV_POSITION;
  float2 uv : TEXCOORD0;
};

VsOut VSMain(uint id : SV_VertexID) {
  VsOut output;
  float2 pos = float2((id == 2) ? 3.0 : -1.0, (id == 1) ? 3.0 : -1.0);
  output.position = float4(pos, 0.0, 1.0);
  output.uv = pos * 0.5 + 0.5;
  return output;
}

float hash21(float2 p) {
  p = frac(p * float2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return frac(p.x * p.y);
}

float rect(float2 p, float2 a, float2 b) {
  float2 lo = step(a, p);
  float2 hi = step(p, b);
  return lo.x * lo.y * hi.x * hi.y;
}

uint digitMask(uint d) {
  if (d == 0) return 0x3Fu;
  if (d == 1) return 0x06u;
  if (d == 2) return 0x5Bu;
  if (d == 3) return 0x4Fu;
  if (d == 4) return 0x66u;
  if (d == 5) return 0x6Du;
  if (d == 6) return 0x7Du;
  if (d == 7) return 0x07u;
  if (d == 8) return 0x7Fu;
  return 0x6Fu;
}

float segment(uint s, float2 p) {
  const float t = 0.11;
  if (s == 0) return rect(p, float2(0.18, 0.84), float2(0.82, 0.98));
  if (s == 1) return rect(p, float2(0.82 - t, 0.50), float2(0.96, 0.86));
  if (s == 2) return rect(p, float2(0.82 - t, 0.08), float2(0.96, 0.48));
  if (s == 3) return rect(p, float2(0.18, 0.00), float2(0.82, 0.14));
  if (s == 4) return rect(p, float2(0.04, 0.08), float2(0.18 + t, 0.48));
  if (s == 5) return rect(p, float2(0.04, 0.50), float2(0.18 + t, 0.86));
  return rect(p, float2(0.18, 0.42), float2(0.82, 0.58));
}

float digitShape(uint d, float2 p) {
  uint mask = digitMask(d);
  float on = 0.0;
  [unroll]
  for (uint i = 0; i < 7; ++i) {
    if ((mask & (1u << i)) != 0) {
      on = max(on, segment(i, p));
    }
  }
  return on;
}

uint pow10u(uint n) {
  uint value = 1u;
  for (uint i = 0; i < n; ++i) {
    value *= 10u;
  }
  return value;
}

float numberShape(uint value, float2 p, uint digits) {
  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
    return 0.0;
  }
  float x = p.x * digits;
  uint cell = min((uint)floor(x), digits - 1u);
  uint place = digits - 1u - cell;
  uint digit = (value / pow10u(place)) % 10u;
  return digitShape(digit, float2(frac(x), p.y));
}

float grid(float2 uv, float scale, float width) {
  float2 g = abs(frac(uv * scale) - 0.5);
  return step(0.5 - width, max(g.x, g.y));
}

float3 sceneColor(float2 uv) {
  float2 centered = uv - 0.5;
  float t = timeSeconds;
  float n = hash21(floor((uv + t * 0.07) * resolution.xy / 12.0));
  float3 base = float3(0.02, 0.025, 0.030);

  if (scene == 0u) {
    base += float3(0.05, 0.09, 0.12) + grid(uv + float2(t * 0.025, 0), 16.0, 0.025) * float3(0.20, 0.55, 0.80);
  } else if (scene == 1u) {
    float wave = sin((uv.x * 18.0 + t * 4.0)) * cos((uv.y * 13.0 - t * 2.8));
    base += float3(0.18 + 0.22 * wave, 0.05 + 0.45 * n, 0.35 + 0.35 * sin(t + uv.x * 7.0));
    base += grid(uv + float2(t * 0.18, -t * 0.09), 28.0, 0.018) * float3(0.85, 0.90, 0.15);
  } else if (scene == 3u) {
    base += float3(0.06, 0.09, 0.13);
    base = lerp(base, float3(0.16, 0.20, 0.24), rect(uv, float2(0.04, 0.10), float2(0.33, 0.88)));
    base = lerp(base, float3(0.12, 0.15, 0.20), rect(uv, float2(0.68, 0.14), float2(0.96, 0.84)));
    base += grid(uv + float2(0, t * 0.03), 22.0, 0.012) * float3(0.18, 0.45, 0.75);
  } else {
    float perspective = 1.0 / max(0.08, uv.y + 0.18);
    float2 roadUv = float2(centered.x * perspective * 1.8 + t * 0.12, perspective + t * 1.1);
    float road = grid(roadUv, 7.0, 0.020);
    float horizon = smoothstep(0.45, 0.52, uv.y);
    base = lerp(float3(0.08, 0.10, 0.13), float3(0.025, 0.030, 0.035), horizon);
    base += road * float3(0.55, 0.75, 0.92);
    float pulse = 0.5 + 0.5 * sin(t * 2.2 + length(centered) * 18.0);
    base += pulse * float3(0.08, 0.02, 0.16);
  }

  float marker = 0.0;
  marker = max(marker, rect(uv, float2(0.000, 0.000), float2(0.060, 0.060)));
  marker = max(marker, rect(uv, float2(0.940, 0.000), float2(1.000, 0.060)));
  marker = max(marker, rect(uv, float2(0.000, 0.940), float2(0.060, 1.000)));
  marker = max(marker, rect(uv, float2(0.940, 0.940), float2(1.000, 1.000)));
  marker = max(marker, rect(uv, float2(0.496, 0.42), float2(0.504, 0.58)));
  marker = max(marker, rect(uv, float2(0.42, 0.496), float2(0.58, 0.504)));
  base = lerp(base, float3(1.0, 0.95, 0.08), marker);

  if (hdrLike != 0u) {
    float glow = smoothstep(0.62, 1.00, max(max(base.r, base.g), base.b));
    base = pow(saturate(base), float3(0.72, 0.76, 0.70));
    base += glow * float3(0.42, 0.30, 0.18);
    base += grid(uv + float2(t * 0.11, t * 0.07), 64.0, 0.006) *
            float3(0.16, 0.10, 0.04);
  }

  return saturate(base);
}

float4 PSMain(VsOut input) : SV_TARGET {
  float2 uv = input.uv;
  float3 color = sceneColor(uv);

  float hud = rect(uv, float2(0.018, 0.020), float2(0.392, 0.112));
  color = lerp(color, float3(0.005, 0.015, 0.020), hud * 0.82);

  float frameDigits = numberShape(frame % 1000000u, (uv - float2(0.030, 0.030)) / float2(0.220, 0.055), 6u);
  float secondDigits = numberShape((uint)floor(timeSeconds) % 10000u, (uv - float2(0.255, 0.030)) / float2(0.145, 0.055), 4u);
  float fpsBar = rect(uv, float2(0.030, 0.092), float2(0.030 + min(targetFps, 120.0) / 120.0 * 0.350, 0.104));
  float hudInk = max(max(frameDigits, secondDigits), fpsBar);
  color = lerp(color, float3(0.20, 1.00, 0.68), hudInk);
  return float4(color, 1.0);
}
)";

class D3DTarget {
 public:
  bool Initialize(HWND hwnd, const Config& config) {
    DXGI_SWAP_CHAIN_DESC swap_desc{};
    swap_desc.BufferDesc.Width = config.width;
    swap_desc.BufferDesc.Height = config.height;
    swap_desc.BufferDesc.Format = DxgiFormat(config.format);
    swap_desc.BufferDesc.RefreshRate.Numerator = 0;
    swap_desc.BufferDesc.RefreshRate.Denominator = 1;
    swap_desc.SampleDesc.Count = 1;
    swap_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swap_desc.BufferCount = 2;
    swap_desc.OutputWindow = hwnd;
    swap_desc.Windowed = TRUE;
    swap_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    UINT flags = 0;
#if defined(_DEBUG)
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    D3D_FEATURE_LEVEL level{};
    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };
    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 2,
        D3D11_SDK_VERSION, &swap_desc, &swap_chain_, &device_, &level,
        &context_);
    if (FAILED(hr)) {
      flags &= ~D3D11_CREATE_DEVICE_DEBUG;
      hr = D3D11CreateDeviceAndSwapChain(
          nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 2,
          D3D11_SDK_VERSION, &swap_desc, &swap_chain_, &device_, &level,
          &context_);
    }
    if (FAILED(hr)) {
      fwprintf(stderr, L"D3D11CreateDeviceAndSwapChain failed: 0x%08X\n", hr);
      return false;
    }
    if (!CreateRenderTarget() || !CreateShaders() || !CreateConstantBuffer()) {
      return false;
    }
    viewport_.Width = static_cast<float>(config.width);
    viewport_.Height = static_cast<float>(config.height);
    viewport_.MinDepth = 0.0f;
    viewport_.MaxDepth = 1.0f;
    return true;
  }

  bool Render(const Config& config, uint32_t frame, double elapsedSeconds) {
    const float clear[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    context_->ClearRenderTargetView(render_target_.Get(), clear);
    context_->OMSetRenderTargets(1, render_target_.GetAddressOf(), nullptr);
    context_->RSSetViewports(1, &viewport_);
    context_->IASetInputLayout(nullptr);
    context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context_->VSSetShader(vertex_shader_.Get(), nullptr, 0);
    context_->PSSetShader(pixel_shader_.Get(), nullptr, 0);

    FrameConstants constants{};
    constants.resolution[0] = static_cast<float>(config.width);
    constants.resolution[1] = static_cast<float>(config.height);
    constants.timeSeconds = static_cast<float>(elapsedSeconds);
    constants.targetFps =
        config.uncapped ? 0.0f : static_cast<float>(config.fps);
    constants.frame = frame;
    constants.scene = static_cast<uint32_t>(config.scene);
    constants.hdrLike = config.hdrLike ? 1u : 0u;
    context_->UpdateSubresource(constant_buffer_.Get(), 0, nullptr, &constants,
                                0, 0);
    ID3D11Buffer* buffers[] = {constant_buffer_.Get()};
    context_->PSSetConstantBuffers(0, 1, buffers);
    context_->Draw(3, 0);
    return true;
  }

  HRESULT Present(bool uncapped) {
    return swap_chain_->Present(0, uncapped ? 0 : 0);
  }

 private:
  bool CreateRenderTarget() {
    ComPtr<ID3D11Texture2D> back_buffer;
    HRESULT hr = swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back_buffer));
    if (FAILED(hr)) {
      fwprintf(stderr, L"SwapChain GetBuffer failed: 0x%08X\n", hr);
      return false;
    }
    hr = device_->CreateRenderTargetView(back_buffer.Get(), nullptr,
                                         &render_target_);
    if (FAILED(hr)) {
      fwprintf(stderr, L"CreateRenderTargetView failed: 0x%08X\n", hr);
      return false;
    }
    return true;
  }

  bool CreateShaders() {
    ComPtr<ID3DBlob> vs;
    ComPtr<ID3DBlob> ps;
    ComPtr<ID3DBlob> errors;
    HRESULT hr = D3DCompile(kShaderSource, strlen(kShaderSource), nullptr,
                            nullptr, nullptr, "VSMain", "vs_5_0", 0, 0, &vs,
                            &errors);
    if (FAILED(hr)) {
      PrintShaderError(errors.Get(), L"vertex shader");
      return false;
    }
    hr = D3DCompile(kShaderSource, strlen(kShaderSource), nullptr, nullptr,
                    nullptr, "PSMain", "ps_5_0", 0, 0, &ps, &errors);
    if (FAILED(hr)) {
      PrintShaderError(errors.Get(), L"pixel shader");
      return false;
    }
    hr = device_->CreateVertexShader(vs->GetBufferPointer(),
                                     vs->GetBufferSize(), nullptr,
                                     &vertex_shader_);
    if (FAILED(hr)) {
      return false;
    }
    hr = device_->CreatePixelShader(ps->GetBufferPointer(),
                                    ps->GetBufferSize(), nullptr,
                                    &pixel_shader_);
    return SUCCEEDED(hr);
  }

  bool CreateConstantBuffer() {
    D3D11_BUFFER_DESC desc{};
    desc.ByteWidth = sizeof(FrameConstants);
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    const HRESULT hr = device_->CreateBuffer(&desc, nullptr, &constant_buffer_);
    if (FAILED(hr)) {
      fwprintf(stderr, L"CreateBuffer constants failed: 0x%08X\n", hr);
      return false;
    }
    return true;
  }

  void PrintShaderError(ID3DBlob* errors, const wchar_t* label) {
    if (errors == nullptr) {
      fwprintf(stderr, L"D3DCompile failed for %s\n", label);
      return;
    }
    const std::string text(static_cast<const char*>(errors->GetBufferPointer()),
                           errors->GetBufferSize());
    fprintf(stderr, "D3DCompile failed for %ls: %s\n", label, text.c_str());
  }

  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<IDXGISwapChain> swap_chain_;
  ComPtr<ID3D11RenderTargetView> render_target_;
  ComPtr<ID3D11VertexShader> vertex_shader_;
  ComPtr<ID3D11PixelShader> pixel_shader_;
  ComPtr<ID3D11Buffer> constant_buffer_;
  D3D11_VIEWPORT viewport_{};
};

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  switch (message) {
    case WM_CLOSE:
      g_running = false;
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      g_running = false;
      PostQuitMessage(0);
      return 0;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

HWND CreateTargetWindow(HINSTANCE instance, const Config& config) {
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = kWindowClassName;
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  RegisterClassExW(&wc);

  DWORD style = config.windowMode == WindowMode::kBorderless
                    ? WS_POPUP
                    : WS_OVERLAPPEDWINDOW;
  RECT rect{0, 0, config.width, config.height};
  AdjustWindowRectEx(&rect, style, FALSE, 0);
  const int window_width = rect.right - rect.left;
  const int window_height = rect.bottom - rect.top;
  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int screen_height = GetSystemMetrics(SM_CYSCREEN);
  const int x = std::max(0, (screen_width - window_width) / 2);
  const int y = std::max(0, (screen_height - window_height) / 2);

  HWND hwnd = CreateWindowExW(0, kWindowClassName, config.title.c_str(), style,
                              x, y, window_width, window_height, nullptr,
                              nullptr, instance, nullptr);
  if (hwnd != nullptr) {
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
  }
  return hwnd;
}

void PumpMessages() {
  MSG msg{};
  while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
}

void UpdateTitle(HWND hwnd,
                 const Config& config,
                 uint64_t frames,
                 double elapsedSeconds) {
  const double fps = elapsedSeconds > 0.0 ? frames / elapsedSeconds : 0.0;
  std::wostringstream title;
  title << config.title << L" | pid=" << GetCurrentProcessId()
        << L" | fps=" << std::fixed << std::setprecision(1) << fps;
  SetWindowTextW(hwnd, title.str().c_str());
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  const Config config = ParseConfig();
  if (!CreateDirectoryRecursive(config.outputDir)) {
    fwprintf(stderr, L"Could not create output directory: %s\n",
             config.outputDir.c_str());
  }

  HWND hwnd = CreateTargetWindow(instance, config);
  if (hwnd == nullptr) {
    fwprintf(stderr, L"CreateWindow failed: 0x%08X\n", GetLastError());
    return 2;
  }

  D3DTarget target;
  if (!target.Initialize(hwnd, config)) {
    return 3;
  }

  wprintf(L"InterGalacticCaptureTarget running title=\"%s\" pid=%lu "
          L"size=%dx%d mode=%S scene=%S format=%S hdrLike=%S fps=%s "
          L"output=\"%s\"\n",
          config.title.c_str(), GetCurrentProcessId(), config.width,
          config.height, WindowModeName(config.windowMode),
          SceneName(config.scene), FormatName(config.format),
          config.hdrLike ? "true" : "false",
          config.uncapped ? L"uncapped" : std::to_wstring(config.fps).c_str(),
          config.outputDir.c_str());

  Metrics metrics;
  const auto started = std::chrono::steady_clock::now();
  auto next_frame = started;
  auto last_present = started;
  auto last_diagnostic_write = started;
  auto last_title_update = started;
  const double target_interval_ms =
      config.uncapped || config.fps <= 0 ? 0.0 : 1000.0 / config.fps;
  const auto target_interval = config.uncapped || config.fps <= 0
                                   ? std::chrono::microseconds(0)
                                   : std::chrono::duration_cast<
                                         std::chrono::steady_clock::duration>(
                                         std::chrono::duration<double>(
                                             1.0 / config.fps));

  while (g_running) {
    PumpMessages();
    const auto now = std::chrono::steady_clock::now();
    if (config.durationMs > 0 &&
        std::chrono::duration_cast<std::chrono::milliseconds>(now - started)
                .count() >= config.durationMs) {
      break;
    }
    if (!config.uncapped && config.fps > 0 && now < next_frame) {
      std::this_thread::sleep_until(next_frame);
    }

    const auto frame_start = std::chrono::steady_clock::now();
    const double elapsed_seconds =
        std::chrono::duration<double>(frame_start - started).count();
    target.Render(config, static_cast<uint32_t>(metrics.frames),
                  elapsed_seconds);
    const auto render_done = std::chrono::steady_clock::now();
    const HRESULT present_result = target.Present(config.uncapped);
    const auto present_done = std::chrono::steady_clock::now();
    if (FAILED(present_result)) {
      fwprintf(stderr, L"Present failed: 0x%08X\n", present_result);
      break;
    }

    const double render_ms =
        std::chrono::duration<double, std::milli>(render_done - frame_start)
            .count();
    const double present_ms =
        std::chrono::duration<double, std::milli>(present_done - render_done)
            .count();
    const double gap_ms =
        std::chrono::duration<double, std::milli>(present_done - last_present)
            .count();
    if (metrics.frames > 0) {
      metrics.presentGapsMs.push_back(gap_ms);
      metrics.maxPresentGapMs = std::max(metrics.maxPresentGapMs, gap_ms);
      if (target_interval_ms > 0.0 && gap_ms > target_interval_ms * 1.5) {
        metrics.lateFrames += 1;
        const auto missed =
            static_cast<uint64_t>(std::floor(gap_ms / target_interval_ms));
        if (missed > 1) {
          metrics.missedFrameIntervals += missed - 1;
        }
      }
    }
    last_present = present_done;
    metrics.totalRenderMs += render_ms;
    metrics.totalPresentMs += present_ms;
    metrics.frames += 1;

    if (!config.uncapped && config.fps > 0) {
      next_frame += target_interval;
      while (next_frame < std::chrono::steady_clock::now()) {
        next_frame += target_interval;
      }
    }

    const auto after = std::chrono::steady_clock::now();
    if (after - last_title_update >= std::chrono::seconds(1)) {
      UpdateTitle(hwnd, config, metrics.frames,
                  std::chrono::duration<double>(after - started).count());
      last_title_update = after;
    }
    if (after - last_diagnostic_write >= std::chrono::seconds(1)) {
      WriteDiagnostics(config, metrics,
                       std::chrono::duration<double>(after - started).count(),
                       hwnd);
      last_diagnostic_write = after;
    }
  }

  const auto ended = std::chrono::steady_clock::now();
  const double elapsed_seconds =
      std::chrono::duration<double>(ended - started).count();
  WriteDiagnostics(config, metrics, elapsed_seconds, hwnd);
  DestroyWindow(hwnd);
  return 0;
}
