#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <sddl.h>
#include <tlhelp32.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "game_capture_protocol.h"

namespace fs = std::filesystem;
namespace iggc = intergalactic_game_capture;
using Microsoft::WRL::ComPtr;

namespace {

struct Options {
  DWORD pid = 0;
  int duration_ms = iggc::kDefaultDurationMs;
  int max_saved_frames = iggc::kDefaultSavedFrames;
  bool host_consume_frames = false;
  int host_proof_frames = iggc::kDefaultHostProofFrames;
  bool publication_handoff = false;
  bool external_consumer = false;
  int hook_target_fps = 0;
  int publication_handoff_max_width = iggc::kDefaultPublicationHandoffMaxWidth;
  int publication_handoff_max_height =
      iggc::kDefaultPublicationHandoffMaxHeight;
  int publication_handoff_target_fps =
      iggc::kDefaultPublicationHandoffTargetFps;
  int publication_handoff_proof_frames =
      iggc::kDefaultPublicationHandoffProofFrames;
  std::string publication_handoff_readback_mode = "all";
  std::string publication_handoff_output_format = "bgra";
  std::string publication_encoder_proof = "off";
  std::string session_id;
  fs::path output_root = iggc::kDefaultResultsRoot;
  fs::path hook_dll;
};

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

std::string NormalizeReadbackMode(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char c) {
    return static_cast<char>(
        std::tolower(static_cast<unsigned char>(c)));
  });
  std::replace(value.begin(), value.end(), '_', '-');
  if (value == "proof-only" || value == "proof") {
    return "proof-only";
  }
  return "all";
}

std::string NormalizePublicationOutputFormat(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char c) {
    return static_cast<char>(
        std::tolower(static_cast<unsigned char>(c)));
  });
  std::replace(value.begin(), value.end(), '_', '-');
  if (value == "nv12") {
    return "nv12";
  }
  if (value == "p010") {
    return "p010";
  }
  return "bgra";
}

std::string NormalizePublicationEncoderProof(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char c) {
    return static_cast<char>(
        std::tolower(static_cast<unsigned char>(c)));
  });
  std::replace(value.begin(), value.end(), '_', '-');
  if (value == "h264" || value == "h264-mf" || value == "mf-h264" ||
      value == "mediafoundation-h264") {
    return "h264-mf";
  }
  return "off";
}

std::string HResultHex(HRESULT hr) {
  std::ostringstream out;
  out << "0x" << std::hex << std::uppercase << static_cast<uint32_t>(hr);
  return out.str();
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

std::string TimestampForPath() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t t = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  localtime_s(&tm, &t);
  std::ostringstream out;
  out << std::put_time(&tm, "%Y%m%d-%H%M%S");
  return out.str();
}

std::string RandomHex(size_t bytes) {
  LARGE_INTEGER counter{};
  QueryPerformanceCounter(&counter);
  uint64_t state =
      static_cast<uint64_t>(std::chrono::high_resolution_clock::now()
                                .time_since_epoch()
                                .count()) ^
      (static_cast<uint64_t>(GetCurrentProcessId()) << 32) ^
      static_cast<uint64_t>(GetCurrentThreadId()) ^
      static_cast<uint64_t>(counter.QuadPart);
  std::ostringstream out;
  for (size_t i = 0; i < bytes; ++i) {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    out << std::hex << std::setw(2) << std::setfill('0')
        << (state & 0xffu);
  }
  return out.str();
}

uint64_t Fnv1a64(const std::string& value) {
  uint64_t hash = 1469598103934665603ull;
  for (unsigned char c : value) {
    hash ^= c;
    hash *= 1099511628211ull;
  }
  return hash;
}

std::string PidHash(DWORD pid, const std::string& session_id) {
  std::ostringstream input;
  input << session_id << ":" << pid;
  const uint64_t hash = Fnv1a64(input.str());
  std::ostringstream out;
  out << "fnv64-" << std::hex << std::setw(12) << std::setfill('0')
      << (hash & 0xffffffffffffull);
  return out.str();
}

void AppendLog(const fs::path& path, const std::string& line) {
  std::ofstream file(path, std::ios::app);
  file << NowIsoUtc() << " " << line << "\n";
}

bool EnsureDirectories(const fs::path& path) {
  const std::wstring value = path.wstring();
  if (value.empty()) {
    return false;
  }
  const DWORD attributes = GetFileAttributesW(value.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES &&
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return true;
  }
  const fs::path parent = path.parent_path();
  if (!parent.empty() && parent != path && !EnsureDirectories(parent)) {
    return false;
  }
  if (CreateDirectoryW(value.c_str(), nullptr)) {
    return true;
  }
  const DWORD error = GetLastError();
  return error == ERROR_ALREADY_EXISTS;
}

std::string LastErrorString(DWORD error = GetLastError()) {
  LPWSTR buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&buffer), 0, nullptr);
  std::wstring wide = length == 0 ? L"unknown" : std::wstring(buffer, length);
  if (buffer != nullptr) {
    LocalFree(buffer);
  }
  while (!wide.empty() && (wide.back() == L'\n' || wide.back() == L'\r')) {
    wide.pop_back();
  }
  return WideToUtf8(wide);
}

std::string BoolText(bool value) {
  return value ? "true" : "false";
}

std::string ArchitectureName(USHORT machine) {
  switch (machine) {
    case IMAGE_FILE_MACHINE_AMD64:
      return "x64";
    case IMAGE_FILE_MACHINE_I386:
      return "x86";
    case IMAGE_FILE_MACHINE_ARM64:
      return "arm64";
    case IMAGE_FILE_MACHINE_UNKNOWN:
      return "native";
    default:
      return "unknown";
  }
}

bool IsTarget64Bit(HANDLE process, std::string* architecture) {
  using IsWow64Process2Fn = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);
  auto* fn = reinterpret_cast<IsWow64Process2Fn>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsWow64Process2"));
  if (fn != nullptr) {
    USHORT process_machine = IMAGE_FILE_MACHINE_UNKNOWN;
    USHORT native_machine = IMAGE_FILE_MACHINE_UNKNOWN;
    if (fn(process, &process_machine, &native_machine)) {
      if (process_machine == IMAGE_FILE_MACHINE_UNKNOWN &&
          native_machine == IMAGE_FILE_MACHINE_AMD64) {
        *architecture = "x64";
        return true;
      }
      *architecture = ArchitectureName(process_machine);
      return false;
    }
  }

  BOOL wow64 = FALSE;
  if (IsWow64Process(process, &wow64) && wow64) {
    *architecture = "x86";
    return false;
  }
  *architecture = "x64";
  return true;
}

DWORD IntegrityRid(HANDLE process) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) {
    return 0;
  }

  DWORD bytes = 0;
  GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &bytes);
  std::vector<BYTE> data(bytes);
  DWORD rid = 0;
  if (GetTokenInformation(token, TokenIntegrityLevel, data.data(), bytes,
                          &bytes)) {
    auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(data.data());
    rid = *GetSidSubAuthority(
        label->Label.Sid,
        static_cast<DWORD>(*GetSidSubAuthorityCount(label->Label.Sid) - 1));
  }
  CloseHandle(token);
  return rid;
}

Options ParseOptions(int argc, wchar_t** argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::wstring arg = argv[i];
    auto next = [&]() -> std::wstring {
      if (i + 1 >= argc) {
        return {};
      }
      return argv[++i];
    };

    if (arg == L"--pid") {
      options.pid = static_cast<DWORD>(std::stoul(next()));
    } else if (arg == L"--duration-ms") {
      options.duration_ms = std::stoi(next());
    } else if (arg == L"--max-saved-frames") {
      options.max_saved_frames = std::stoi(next());
    } else if (arg == L"--host-consume-frames") {
      const std::wstring value = next();
      options.host_consume_frames =
          value.empty() || value == L"1" || value == L"true" ||
          value == L"yes";
    } else if (arg == L"--host-proof-frames") {
      options.host_proof_frames = std::stoi(next());
    } else if (arg == L"--publication-handoff") {
      const std::wstring value = next();
      options.publication_handoff =
          value.empty() || value == L"1" || value == L"true" ||
          value == L"yes";
    } else if (arg == L"--publication-handoff-max-width") {
      options.publication_handoff_max_width = std::stoi(next());
    } else if (arg == L"--publication-handoff-max-height") {
      options.publication_handoff_max_height = std::stoi(next());
    } else if (arg == L"--publication-handoff-target-fps") {
      options.publication_handoff_target_fps = std::stoi(next());
    } else if (arg == L"--publication-handoff-proof-frames") {
      options.publication_handoff_proof_frames = std::stoi(next());
    } else if (arg == L"--publication-handoff-readback-mode") {
      options.publication_handoff_readback_mode =
          NormalizeReadbackMode(WideToUtf8(next()));
    } else if (arg == L"--publication-handoff-output-format") {
      options.publication_handoff_output_format =
          NormalizePublicationOutputFormat(WideToUtf8(next()));
    } else if (arg == L"--publication-encoder-proof") {
      options.publication_encoder_proof =
          NormalizePublicationEncoderProof(WideToUtf8(next()));
    } else if (arg == L"--external-consumer") {
      const std::wstring value = next();
      options.external_consumer =
          value.empty() || value == L"1" || value == L"true" ||
          value == L"yes";
    } else if (arg == L"--hook-target-fps") {
      const std::wstring value = next();
      if (value.empty()) {
        std::wcerr << L"Missing value for --hook-target-fps\n";
        ExitProcess(2);
      }
      try {
        options.hook_target_fps = std::stoi(value);
      } catch (...) {
        std::wcerr << L"Invalid value for --hook-target-fps: " << value
                   << L"\n";
        ExitProcess(2);
      }
    } else if (arg == L"--session-id") {
      options.session_id = WideToUtf8(next());
    } else if (arg == L"--output-root") {
      options.output_root = next();
    } else if (arg == L"--hook-dll") {
      options.hook_dll = next();
    } else if (arg == L"--help" || arg == L"-h") {
      std::wcout
          << L"Usage: intergalactic_game_capture_helper.exe --pid <pid> "
          << L"[--duration-ms 10000] [--max-saved-frames 5] "
          << L"[--host-consume-frames true|false] "
          << L"[--host-proof-frames 0] "
          << L"[--publication-handoff true|false] "
          << L"[--publication-handoff-max-width 1280] "
          << L"[--publication-handoff-max-height 720] "
          << L"[--publication-handoff-target-fps 30] "
          << L"[--publication-handoff-proof-frames 0] "
          << L"[--publication-handoff-readback-mode all|proof-only] "
          << L"[--publication-handoff-output-format bgra|nv12|p010] "
          << L"[--publication-encoder-proof off|h264-mf] "
          << L"[--external-consumer true|false] "
          << L"[--hook-target-fps 0] "
          << L"[--session-id <debug-session-id>] "
          << L"[--output-root <path>] "
          << L"[--hook-dll <path>]\n";
      ExitProcess(0);
    }
  }

  if (options.duration_ms < 1000) {
    options.duration_ms = 1000;
  }
  if (options.duration_ms > iggc::kMaxDurationMs) {
    options.duration_ms = iggc::kMaxDurationMs;
  }
  options.max_saved_frames =
      std::clamp(options.max_saved_frames, 0, iggc::kMaxSavedFrames);
  options.host_proof_frames =
      std::clamp(options.host_proof_frames, 0, iggc::kMaxHostProofFrames);
  options.publication_handoff_max_width =
      std::clamp(options.publication_handoff_max_width, 2, 7680);
  options.publication_handoff_max_height =
      std::clamp(options.publication_handoff_max_height, 2, 4320);
  options.publication_handoff_target_fps = std::clamp(
      options.publication_handoff_target_fps,
      iggc::kMinPublicationHandoffTargetFps,
      iggc::kMaxPublicationHandoffTargetFps);
  options.hook_target_fps =
      std::clamp(options.hook_target_fps, 0,
                 iggc::kMaxPublicationHandoffTargetFps);
  options.publication_handoff_proof_frames = std::clamp(
      options.publication_handoff_proof_frames,
      iggc::kDefaultPublicationHandoffProofFrames,
      iggc::kMaxPublicationHandoffProofFrames);
  options.publication_handoff_readback_mode =
      NormalizeReadbackMode(options.publication_handoff_readback_mode);
  options.publication_handoff_output_format =
      NormalizePublicationOutputFormat(options.publication_handoff_output_format);
  options.publication_encoder_proof =
      NormalizePublicationEncoderProof(options.publication_encoder_proof);
  if (!options.session_id.empty()) {
    options.session_id.erase(
        std::remove_if(options.session_id.begin(), options.session_id.end(),
                       [](unsigned char c) {
                         return !std::isalnum(c) && c != '-' && c != '_';
                       }),
        options.session_id.end());
  }

  if (options.hook_dll.empty()) {
    wchar_t module_path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, module_path, MAX_PATH);
    options.hook_dll =
        fs::path(module_path).parent_path() /
        L"intergalactic_game_capture_hook64.dll";
  }

  return options;
}

void WriteFailureResult(const fs::path& output_dir,
                        const std::string& session_id,
                        const std::string& target_pid_hash,
                        iggc::AttachStatus status,
                        const std::string& reason,
                        const std::string& target_architecture) {
  EnsureDirectories(output_dir);
  const auto metadata_path = output_dir / L"metadata.json";
  const auto summary_path = output_dir / L"summary.md";

  {
    std::ofstream file(metadata_path);
    file << "{\n"
         << "  \"schema\": \"intergalactic.gameCapturePoc.v1\",\n"
         << "  \"sessionId\": \"" << JsonEscape(session_id) << "\",\n"
         << "  \"targetPidHash\": \"" << JsonEscape(target_pid_hash)
         << "\",\n"
         << "  \"targetArchitecture\": \""
         << JsonEscape(target_architecture) << "\",\n"
         << "  \"requestedBackend\": \"d3d11-present-hook\",\n"
         << "  \"backendContractVersion\": "
         << iggc::kSharedTextureStateVersion << ",\n"
         << "  \"sourceApi\": \""
         << iggc::CaptureBackendName(iggc::CaptureBackend::kD3D11PresentHook)
         << "\",\n"
         << "  \"sourceApiId\": "
         << static_cast<uint32_t>(iggc::CaptureBackend::kD3D11PresentHook)
         << ",\n"
         << "  \"sourceFormat\": \"unknown\",\n"
         << "  \"sourceFormatId\": "
         << static_cast<uint32_t>(iggc::SourceFormat::kUnknown) << ",\n"
         << "  \"colorSpace\": \"unknown\",\n"
         << "  \"syncKind\": \"unknown\",\n"
         << "  \"readyState\": \"failed\",\n"
         << "  \"failureReason\": \"attach_failed\",\n"
         << "  \"attachStatus\": \"" << iggc::AttachStatusName(status)
         << "\",\n"
         << "  \"detectedGraphicsApi\": \"unknown\",\n"
         << "  \"startedAt\": \"" << NowIsoUtc() << "\",\n"
         << "  \"endedAt\": \"" << NowIsoUtc() << "\",\n"
         << "  \"result\": \"" << JsonEscape(reason) << "\"\n"
         << "}\n";
  }

  {
    std::ofstream file(summary_path);
    file << "# D3D11 Game Capture POC\n\n"
         << "- Attach status: " << iggc::AttachStatusName(status) << "\n"
         << "- Backend contract: v" << iggc::kSharedTextureStateVersion
         << " api="
         << iggc::CaptureBackendName(iggc::CaptureBackend::kD3D11PresentHook)
         << " source_format=unknown color_space=unknown"
         << " sync=unknown ready=failed"
         << " failure=attach_failed\n"
         << "- Target PID hash: " << target_pid_hash << "\n"
         << "- Target architecture: " << target_architecture << "\n"
         << "- Result: " << reason << "\n";
  }
}

bool WriteHookConfig(const fs::path& config_path,
                     const std::string& session_id,
                     const fs::path& output_dir,
                     int duration_ms,
                     int max_saved_frames,
                     int hook_target_fps,
                     bool host_consume_frames,
                     const std::wstring& stop_event,
                     const std::wstring& stopped_event,
                     const std::wstring& frame_event,
                     const std::wstring& shared_state) {
  std::ofstream file(config_path);
  if (!file.is_open()) {
    return false;
  }
  file << "sessionId=" << session_id << "\n";
  file << "outputDir=" << WideToUtf8(output_dir.wstring()) << "\n";
  file << "durationMs=" << duration_ms << "\n";
  file << "stopEvent=" << WideToUtf8(stop_event) << "\n";
  file << "stoppedEvent=" << WideToUtf8(stopped_event) << "\n";
  file << "frameEvent=" << WideToUtf8(frame_event) << "\n";
  file << "sharedState=" << WideToUtf8(shared_state) << "\n";
  file << "maxSavedFrames=" << max_saved_frames << "\n";
  file << "hookTargetFps=" << hook_target_fps << "\n";
  file << "hostConsumerEnabled=" << (host_consume_frames ? "1" : "0") << "\n";
  return true;
}

bool InjectLoadLibrary(HANDLE process,
                       const fs::path& dll_path,
                       std::string* error) {
  const std::wstring path = dll_path.wstring();
  const size_t bytes = (path.size() + 1) * sizeof(wchar_t);

  void* remote_memory =
      VirtualAllocEx(process, nullptr, bytes, MEM_COMMIT | MEM_RESERVE,
                     PAGE_READWRITE);
  if (remote_memory == nullptr) {
    *error = "VirtualAllocEx failed: " + LastErrorString();
    return false;
  }

  if (!WriteProcessMemory(process, remote_memory, path.c_str(), bytes,
                          nullptr)) {
    *error = "WriteProcessMemory failed: " + LastErrorString();
    VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
    return false;
  }

  auto* load_library = reinterpret_cast<LPTHREAD_START_ROUTINE>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW"));
  if (load_library == nullptr) {
    *error = "LoadLibraryW address unavailable";
    VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
    return false;
  }

  HANDLE thread = CreateRemoteThread(process, nullptr, 0, load_library,
                                     remote_memory, 0, nullptr);
  if (thread == nullptr) {
    *error = "CreateRemoteThread LoadLibraryW failed: " + LastErrorString();
    VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
    return false;
  }

  const DWORD wait_result = WaitForSingleObject(thread, 10000);
  if (wait_result != WAIT_OBJECT_0) {
    *error = wait_result == WAIT_TIMEOUT
                 ? "remote LoadLibraryW timed out"
                 : "WaitForSingleObject LoadLibraryW failed: " +
                       LastErrorString();
    CloseHandle(thread);
    // The remote thread may still read the path buffer; do not free it here.
    return false;
  }

  DWORD exit_code = 0;
  if (!GetExitCodeThread(thread, &exit_code)) {
    *error = "GetExitCodeThread LoadLibraryW failed: " + LastErrorString();
    CloseHandle(thread);
    VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
    return false;
  }
  CloseHandle(thread);
  VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);

  if (exit_code == 0) {
    *error = "remote LoadLibraryW returned null or truncated to zero";
  }
  return true;
}

HMODULE FindRemoteModule(DWORD pid, const fs::path& dll_path) {
  const std::wstring wanted = fs::absolute(dll_path).wstring();
  HANDLE snapshot =
      CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return nullptr;
  }

  MODULEENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  HMODULE result = nullptr;
  if (Module32FirstW(snapshot, &entry)) {
    do {
      std::error_code ec;
      const auto current = fs::absolute(entry.szExePath, ec).wstring();
      if (!ec && _wcsicmp(current.c_str(), wanted.c_str()) == 0) {
        result = entry.hModule;
        break;
      }
      if (_wcsicmp(entry.szModule, dll_path.filename().c_str()) == 0) {
        result = entry.hModule;
        break;
      }
    } while (Module32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return result;
}

struct RemoteFreeLibraryStatus {
  bool attempted = false;
  bool completed = false;
  bool unloaded = false;
  DWORD wait_result = WAIT_FAILED;
  DWORD exit_code = 0;
  DWORD error = ERROR_SUCCESS;
};

std::string RemoteFreeLibraryStatusText(
    const RemoteFreeLibraryStatus& status) {
  std::ostringstream out;
  out << "attempted=" << BoolText(status.attempted)
      << " completed=" << BoolText(status.completed)
      << " unloaded=" << BoolText(status.unloaded)
      << " waitResult=" << status.wait_result
      << " exitCode=" << status.exit_code
      << " error=" << status.error;
  return out.str();
}

RemoteFreeLibraryStatus RemoteFreeLibrary(HANDLE process,
                                          HMODULE module,
                                          DWORD wait_ms = 10000) {
  RemoteFreeLibraryStatus status;
  if (process == nullptr || module == nullptr) {
    status.error = ERROR_INVALID_PARAMETER;
    return status;
  }
  status.attempted = true;
  auto* free_library = reinterpret_cast<LPTHREAD_START_ROUTINE>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "FreeLibrary"));
  if (free_library == nullptr) {
    status.error = GetLastError();
    return status;
  }
  HANDLE thread =
      CreateRemoteThread(process, nullptr, 0, free_library, module, 0, nullptr);
  if (thread == nullptr) {
    status.error = GetLastError();
    return status;
  }

  status.wait_result = WaitForSingleObject(thread, wait_ms);
  if (status.wait_result == WAIT_OBJECT_0) {
    status.completed = true;
    if (GetExitCodeThread(thread, &status.exit_code)) {
      status.unloaded = status.exit_code != 0;
    } else {
      status.error = GetLastError();
    }
  } else if (status.wait_result == WAIT_TIMEOUT) {
    status.error = WAIT_TIMEOUT;
  } else {
    status.error = GetLastError();
  }
  CloseHandle(thread);
  return status;
}

bool WaitForRemoteModuleGone(DWORD pid,
                             const fs::path& dll_path,
                             DWORD timeout_ms = 3000) {
  const DWORD start = GetTickCount();
  while (true) {
    if (FindRemoteModule(pid, dll_path) == nullptr) {
      return true;
    }
    if (GetTickCount() - start >= timeout_ms) {
      return false;
    }
    Sleep(100);
  }
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

double Percentile(std::vector<double> values, double percentile) {
  if (values.empty()) {
    return 0.0;
  }
  double normalized_percentile = percentile;
  if (normalized_percentile > 1.0) {
    normalized_percentile /= 100.0;
  }
  normalized_percentile = std::clamp(normalized_percentile, 0.0, 1.0);
  std::sort(values.begin(), values.end());
  const double index =
      normalized_percentile * static_cast<double>(values.size() - 1);
  const size_t lower = static_cast<size_t>(std::floor(index));
  const size_t upper = std::min(lower + 1, values.size() - 1);
  const double fraction = index - static_cast<double>(lower);
  return values[lower] + (values[upper] - values[lower]) * fraction;
}

double MaxValue(const std::vector<double>& values) {
  if (values.empty()) {
    return 0.0;
  }
  return *std::max_element(values.begin(), values.end());
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

bool CheckVideoProcessorFormatSupport(
    ID3D11VideoProcessorEnumerator* enumerator,
    DXGI_FORMAT format,
    UINT required_flag) {
  if (enumerator == nullptr) {
    return false;
  }
  UINT support = 0;
  const HRESULT hr = enumerator->CheckVideoProcessorFormat(format, &support);
  return SUCCEEDED(hr) && (support & required_flag) != 0;
}

uint8_t TenBitToEightBit(uint32_t value) {
  return static_cast<uint8_t>((value * 255u + 511u) / 1023u);
}

uint32_t EvenDimension(uint32_t value) {
  const uint32_t safe_value = std::max<uint32_t>(2, value);
  return safe_value % 2 == 0 ? safe_value : safe_value - 1;
}

struct OutputDimensions {
  uint32_t width = 0;
  uint32_t height = 0;
};

OutputDimensions FitWithin(uint32_t source_width,
                           uint32_t source_height,
                           uint32_t max_width,
                           uint32_t max_height) {
  if (source_width == 0 || source_height == 0 || max_width == 0 ||
      max_height == 0) {
    return {};
  }
  const double width_scale =
      static_cast<double>(max_width) / static_cast<double>(source_width);
  const double height_scale =
      static_cast<double>(max_height) / static_cast<double>(source_height);
  const double scale = std::min({1.0, width_scale, height_scale});
  return OutputDimensions{
      EvenDimension(static_cast<uint32_t>(
          std::round(static_cast<double>(source_width) * scale))),
      EvenDimension(static_cast<uint32_t>(
          std::round(static_cast<double>(source_height) * scale))),
  };
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

bool WriteBgraPng(const fs::path& path,
                  UINT width,
                  UINT height,
                  UINT stride,
                  const uint8_t* data) {
  if (width == 0 || height == 0 || data == nullptr) {
    return false;
  }
  if (!EnsureDirectories(path.parent_path())) {
    return false;
  }

  const HRESULT coinit = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool should_uninit = SUCCEEDED(coinit);
  if (FAILED(coinit) && coinit != RPC_E_CHANGED_MODE) {
    return false;
  }

  bool wrote = false;
  {
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr =
        CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&factory));
    if (SUCCEEDED(hr)) {
      ComPtr<IWICStream> stream;
      hr = factory->CreateStream(&stream);
      if (SUCCEEDED(hr)) {
        hr = stream->InitializeFromFilename(path.wstring().c_str(),
                                            GENERIC_WRITE);
      }
      ComPtr<IWICBitmapEncoder> encoder;
      if (SUCCEEDED(hr)) {
        hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    &encoder);
      }
      if (SUCCEEDED(hr)) {
        hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
      }
      ComPtr<IWICBitmapFrameEncode> frame;
      ComPtr<IPropertyBag2> property_bag;
      if (SUCCEEDED(hr)) {
        hr = encoder->CreateNewFrame(&frame, &property_bag);
      }
      if (SUCCEEDED(hr)) {
        hr = frame->Initialize(property_bag.Get());
      }
      if (SUCCEEDED(hr)) {
        hr = frame->SetSize(width, height);
      }
      WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
      if (SUCCEEDED(hr)) {
        hr = frame->SetPixelFormat(&pixel_format);
      }
      const UINT buffer_size = stride * height;
      if (SUCCEEDED(hr)) {
        hr = frame->WritePixels(height, stride, buffer_size,
                                const_cast<BYTE*>(data));
      }
      if (SUCCEEDED(hr)) {
        hr = frame->Commit();
      }
      if (SUCCEEDED(hr)) {
        hr = encoder->Commit();
      }
      wrote = SUCCEEDED(hr);
    }
  }
  if (should_uninit) {
    CoUninitialize();
  }
  return wrote;
}

struct HostConsumerStats {
  bool enabled = false;
  bool shared_state_available = false;
  bool d3d_device_created = false;
  bool opened_shared_texture = false;
  uint32_t backend_contract_version = 0;
  uint32_t source_api_id = 0;
  uint32_t source_format_id = 0;
  std::string source_api = "unknown";
  std::string source_format = "unknown";
  std::string color_space = "unknown";
  std::string sync_kind = "unknown";
  std::string ready_state = "unknown";
  std::string failure_reason = "none";
  uint64_t opened_texture_slots = 0;
  uint64_t shared_texture_open_failures = 0;
  uint64_t observed_frame_signals = 0;
  uint64_t consumed_frames = 0;
  uint64_t duplicate_signals = 0;
  uint64_t missed_frames = 0;
  uint64_t invalid_state_reads = 0;
  uint64_t proof_readback_count = 0;
  uint64_t visible_proof_frames = 0;
  std::vector<double> frame_age_ms;
  std::vector<double> consume_gap_ms;
  std::vector<double> proof_readback_ms;
  std::string last_error = "none";
};

struct PublicationHandoffStats {
  bool enabled = false;
  bool shared_state_available = false;
  bool d3d_device_created = false;
  bool opened_shared_texture = false;
  bool unsupported_format = false;
  uint32_t backend_contract_version = 0;
  uint32_t source_api_id = 0;
  uint32_t source_format_id = 0;
  std::string source_api = "unknown";
  std::string source_format = "unknown";
  std::string color_space = "unknown";
  std::string sync_kind = "unknown";
  std::string ready_state = "unknown";
  std::string failure_reason = "none";
  uint64_t opened_texture_slots = 0;
  uint64_t shared_texture_open_failures = 0;
  int requested_max_width = iggc::kDefaultPublicationHandoffMaxWidth;
  int requested_max_height = iggc::kDefaultPublicationHandoffMaxHeight;
  int requested_target_fps = iggc::kDefaultPublicationHandoffTargetFps;
  uint32_t source_width = 0;
  uint32_t source_height = 0;
  uint32_t output_width = 0;
  uint32_t output_height = 0;
  uint32_t dxgi_format = 0;
  uint64_t observed_frame_signals = 0;
  uint64_t input_frames_seen = 0;
  uint64_t duplicate_signals = 0;
  uint64_t missed_input_frames = 0;
  uint64_t paced_drop_frames = 0;
  uint64_t readback_frames = 0;
  uint64_t readback_failures = 0;
  uint64_t output_frames = 0;
  uint64_t repeated_output_frames = 0;
  uint64_t visible_output_frames = 0;
  uint64_t proof_output_frames = 0;
  uint64_t visible_proof_output_frames = 0;
  uint64_t proof_output_write_failures = 0;
  bool proof_readback_suppressed_for_encoder = false;
  uint64_t nv12_output_frames = 0;
  uint64_t nv12_convert_failures = 0;
  uint64_t nv12_proof_readback_frames = 0;
  uint64_t nv12_visible_proof_frames = 0;
  bool nv12_texture_created = false;
  bool p010_texture_created = false;
  uint64_t p010_output_frames = 0;
  uint64_t p010_convert_failures = 0;
  uint64_t p010_proof_readback_frames = 0;
  uint64_t p010_visible_proof_frames = 0;
  bool video_processor_probe_available = false;
  bool video_processor_bgra_input_supported = false;
  bool video_processor_r10_input_supported = false;
  bool video_processor_nv12_output_supported = false;
  bool video_processor_p010_output_supported = false;
  bool video_processor_bgra_to_nv12_supported = false;
  bool video_processor_r10_to_nv12_supported = false;
  bool video_processor_r10_to_p010_supported = false;
  bool encoder_proof_enabled = false;
  bool encoder_proof_initialized = false;
  bool encoder_proof_finalized = false;
  bool encoder_proof_hardware_transforms_requested = false;
  uint64_t encoder_proof_frames_submitted = 0;
  uint64_t encoder_proof_write_failures = 0;
  uint64_t encoder_proof_gpu_copy_frames = 0;
  uint64_t encoder_proof_output_bytes = 0;
  double encoder_proof_init_ms = 0.0;
  double encoder_proof_finalize_ms = 0.0;
  uint64_t invalid_state_reads = 0;
  int requested_proof_frames = iggc::kDefaultPublicationHandoffProofFrames;
  std::vector<double> frame_age_ms;
  std::vector<double> output_gap_ms;
  std::vector<double> readback_ms;
  std::vector<double> scale_ms;
  std::vector<double> nv12_convert_ms;
  std::vector<double> nv12_proof_readback_ms;
  std::vector<double> p010_convert_ms;
  std::vector<double> p010_proof_readback_ms;
  std::vector<double> encoder_proof_submit_ms;
  std::vector<double> encoder_proof_gpu_copy_ms;
  std::vector<double> total_frame_ms;
  std::string mode = "gpu_scaled_bgra_readback_probe";
  std::string scale_mode = "contain_fit_gpu_before_readback";
  std::string readback_mode = "all";
  std::string output_format = "bgra";
  std::string encoder_format = "none";
  std::string encoder_proof_mode = "off";
  std::string encoder_proof_codec = "none";
  std::string encoder_proof_container = "none";
  std::string encoder_proof_output_path;
  std::string proof_output_directory;
  std::string last_error = "none";
  std::string encoder_proof_first_error = "none";
  std::string encoder_proof_last_error = "none";
};

void UpdateBackendContractStats(const iggc::SharedTextureState* shared_state,
                                HostConsumerStats* stats,
                                PublicationHandoffStats* handoff_stats) {
  if (shared_state == nullptr || stats == nullptr) {
    return;
  }
  const auto source_api =
      static_cast<iggc::CaptureBackend>(shared_state->source_api);
  const auto source_format =
      static_cast<iggc::SourceFormat>(shared_state->source_format);
  const auto color_space =
      static_cast<iggc::ColorSpace>(shared_state->color_space);
  const auto sync_kind = static_cast<iggc::SyncKind>(shared_state->sync_kind);
  const auto ready_state =
      static_cast<iggc::FrameReadyState>(shared_state->ready_state);
  const auto failure_reason =
      static_cast<iggc::FailureReason>(shared_state->failure_reason);

  stats->backend_contract_version = shared_state->version;
  stats->source_api_id = shared_state->source_api;
  stats->source_format_id = shared_state->source_format;
  stats->source_api = iggc::CaptureBackendName(source_api);
  stats->source_format = iggc::SourceFormatName(source_format);
  stats->color_space = iggc::ColorSpaceName(color_space);
  stats->sync_kind = iggc::SyncKindName(sync_kind);
  stats->ready_state = iggc::FrameReadyStateName(ready_state);
  stats->failure_reason = iggc::FailureReasonName(failure_reason);

  if (handoff_stats == nullptr || !handoff_stats->enabled) {
    return;
  }
  handoff_stats->backend_contract_version =
      stats->backend_contract_version;
  handoff_stats->source_api_id = stats->source_api_id;
  handoff_stats->source_format_id = stats->source_format_id;
  handoff_stats->source_api = stats->source_api;
  handoff_stats->source_format = stats->source_format;
  handoff_stats->color_space = stats->color_space;
  handoff_stats->sync_kind = stats->sync_kind;
  handoff_stats->ready_state = stats->ready_state;
  handoff_stats->failure_reason = stats->failure_reason;
}

void SetEncoderProofError(PublicationHandoffStats* stats,
                          const std::string& error) {
  if (stats == nullptr) {
    return;
  }
  if (stats->encoder_proof_first_error == "none") {
    stats->encoder_proof_first_error = error;
  }
  stats->encoder_proof_last_error = error;
}

bool SampleTextureLooksVisible(ID3D11Device* device,
                               ID3D11DeviceContext* context,
                               ID3D11Texture2D* texture,
                               DXGI_FORMAT format,
                               HostConsumerStats* stats) {
  if (!IsBgra(format) && !IsRgba(format) && !IsR10G10B10A2(format)) {
    stats->last_error = "host_proof_unsupported_format";
    return false;
  }

  D3D11_TEXTURE2D_DESC desc{};
  texture->GetDesc(&desc);
  D3D11_TEXTURE2D_DESC staging = desc;
  staging.Usage = D3D11_USAGE_STAGING;
  staging.BindFlags = 0;
  staging.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging.MiscFlags = 0;

  ComPtr<ID3D11Texture2D> staging_texture;
  HRESULT hr = device->CreateTexture2D(&staging, nullptr, &staging_texture);
  if (FAILED(hr)) {
    stats->last_error = "host_staging_create_failed";
    return false;
  }

  LARGE_INTEGER frequency{};
  LARGE_INTEGER start{};
  LARGE_INTEGER end{};
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&start);
  context->CopyResource(staging_texture.Get(), texture);
  context->Flush();

  D3D11_MAPPED_SUBRESOURCE mapped{};
  hr = context->Map(staging_texture.Get(), 0, D3D11_MAP_READ, 0, &mapped);
  QueryPerformanceCounter(&end);
  stats->proof_readback_ms.push_back(
      static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
      static_cast<double>(frequency.QuadPart));
  if (FAILED(hr)) {
    stats->last_error = "host_staging_map_failed";
    return false;
  }

  const uint32_t step_x = std::max<uint32_t>(1, desc.Width / 32);
  const uint32_t step_y = std::max<uint32_t>(1, desc.Height / 32);
  int min_luma = 255;
  int max_luma = 0;
  uint64_t nonzero = 0;
  uint64_t samples = 0;
  for (uint32_t y = 0; y < desc.Height; y += step_y) {
    const auto* row =
        reinterpret_cast<const uint8_t*>(mapped.pData) + y * mapped.RowPitch;
    for (uint32_t x = 0; x < desc.Width; x += step_x) {
      uint8_t r = 0;
      uint8_t g = 0;
      uint8_t b = 0;
      ReadRgb8(row + x * 4, format, &r, &g, &b);
      const int luma = (static_cast<int>(r) + static_cast<int>(g) +
                        static_cast<int>(b)) /
                       3;
      min_luma = std::min(min_luma, luma);
      max_luma = std::max(max_luma, luma);
      if (luma > 4) {
        ++nonzero;
      }
      ++samples;
    }
  }
  context->Unmap(staging_texture.Get(), 0);
  return samples > 0 && nonzero > samples / 16 && max_luma - min_luma > 8;
}

bool SampleBgraBufferLooksVisible(const std::vector<uint8_t>& bgra,
                                  uint32_t width,
                                  uint32_t height) {
  if (bgra.empty() || width == 0 || height == 0) {
    return false;
  }
  const uint32_t step_x = std::max<uint32_t>(1, width / 32);
  const uint32_t step_y = std::max<uint32_t>(1, height / 32);
  int min_luma = 255;
  int max_luma = 0;
  uint64_t nonzero = 0;
  uint64_t samples = 0;
  for (uint32_t y = 0; y < height; y += step_y) {
    const size_t row_offset = static_cast<size_t>(y) * width * 4;
    for (uint32_t x = 0; x < width; x += step_x) {
      const size_t pixel_offset = row_offset + static_cast<size_t>(x) * 4;
      const uint8_t b = bgra[pixel_offset];
      const uint8_t g = bgra[pixel_offset + 1];
      const uint8_t r = bgra[pixel_offset + 2];
      const int luma = (static_cast<int>(r) + static_cast<int>(g) +
                        static_cast<int>(b)) /
                       3;
      min_luma = std::min(min_luma, luma);
      max_luma = std::max(max_luma, luma);
      if (luma > 4) {
        ++nonzero;
      }
      ++samples;
    }
  }
  return samples > 0 && nonzero > samples / 16 && max_luma - min_luma > 8;
}

bool SampleNv12LumaLooksVisible(const D3D11_MAPPED_SUBRESOURCE& mapped,
                                uint32_t width,
                                uint32_t height) {
  if (mapped.pData == nullptr || width == 0 || height == 0 ||
      mapped.RowPitch == 0) {
    return false;
  }
  const uint32_t step_x = std::max<uint32_t>(1, width / 32);
  const uint32_t step_y = std::max<uint32_t>(1, height / 32);
  int min_luma = 255;
  int max_luma = 0;
  uint64_t nonzero = 0;
  uint64_t samples = 0;
  for (uint32_t y = 0; y < height; y += step_y) {
    const auto* row =
        reinterpret_cast<const uint8_t*>(mapped.pData) +
        static_cast<size_t>(y) * mapped.RowPitch;
    for (uint32_t x = 0; x < width; x += step_x) {
      const int luma = row[x];
      min_luma = std::min(min_luma, luma);
      max_luma = std::max(max_luma, luma);
      if (luma > 4) {
        ++nonzero;
      }
      ++samples;
    }
  }
  return samples > 0 && nonzero > samples / 16 && max_luma - min_luma > 8;
}

bool SampleP010LumaLooksVisible(const D3D11_MAPPED_SUBRESOURCE& mapped,
                                uint32_t width,
                                uint32_t height) {
  if (mapped.pData == nullptr || width == 0 || height == 0 ||
      mapped.RowPitch == 0) {
    return false;
  }
  const uint32_t step_x = std::max<uint32_t>(1, width / 32);
  const uint32_t step_y = std::max<uint32_t>(1, height / 32);
  int min_luma = 1023;
  int max_luma = 0;
  uint64_t nonzero = 0;
  uint64_t samples = 0;
  for (uint32_t y = 0; y < height; y += step_y) {
    const auto* row =
        reinterpret_cast<const uint16_t*>(
            reinterpret_cast<const uint8_t*>(mapped.pData) +
            static_cast<size_t>(y) * mapped.RowPitch);
    for (uint32_t x = 0; x < width; x += step_x) {
      // P010 stores 10-bit luma in bits [15:6] of each 16-bit sample.
      const int luma = static_cast<int>(row[x] >> 6);
      min_luma = std::min(min_luma, luma);
      max_luma = std::max(max_luma, luma);
      if (luma > 16) {
        ++nonzero;
      }
      ++samples;
    }
  }
  return samples > 0 && nonzero > samples / 16 && max_luma - min_luma > 32;
}

class LocalH264EncoderProof {
 public:
  fs::path output_path;

  bool Enabled(const PublicationHandoffStats* stats) const {
    return stats != nullptr && stats->encoder_proof_enabled &&
           stats->encoder_proof_mode == "h264-mf";
  }

  bool Submit(ID3D11Device* device,
              ID3D11DeviceContext* context,
              ID3D11Texture2D* nv12_texture,
              const OutputDimensions& output,
              const LARGE_INTEGER& frequency,
              PublicationHandoffStats* stats) {
    if (!Enabled(stats)) {
      return true;
    }
    if (device == nullptr || context == nullptr || nv12_texture == nullptr) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats, "encoder_proof_missing_texture");
      return false;
    }
    if (stats->output_format != "nv12") {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats, "encoder_proof_requires_nv12");
      return false;
    }
    if (!Initialize(device, output, stats)) {
      return false;
    }
    if (!EnsureTextureRing(device, output, stats)) {
      return false;
    }

    LARGE_INTEGER start{};
    LARGE_INTEGER after_copy{};
    LARGE_INTEGER after_write{};
    QueryPerformanceCounter(&start);

    ID3D11Texture2D* sample_texture =
        encoder_textures[next_texture_index].Get();
    next_texture_index = (next_texture_index + 1) % encoder_textures.size();
    context->CopyResource(sample_texture, nv12_texture);
    QueryPerformanceCounter(&after_copy);
    stats->encoder_proof_gpu_copy_ms.push_back(
        static_cast<double>(after_copy.QuadPart - start.QuadPart) * 1000.0 /
        static_cast<double>(frequency.QuadPart));
    ++stats->encoder_proof_gpu_copy_frames;

    ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateDXGISurfaceBuffer(__uuidof(ID3D11Texture2D),
                                           sample_texture, 0, FALSE, &buffer);
    if (SUCCEEDED(hr)) {
      hr = buffer->SetCurrentLength(output.width * output.height * 3 / 2);
    }
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_dxgi_buffer_failed:" +
                               HResultHex(hr));
      return false;
    }

    ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) {
      hr = sample->AddBuffer(buffer.Get());
    }
    if (SUCCEEDED(hr)) {
      hr = sample->SetSampleTime(frame_index * frame_duration_100ns);
    }
    if (SUCCEEDED(hr)) {
      hr = sample->SetSampleDuration(frame_duration_100ns);
    }
    if (SUCCEEDED(hr)) {
      hr = sink_writer->WriteSample(stream_index, sample.Get());
    }
    QueryPerformanceCounter(&after_write);
    stats->encoder_proof_submit_ms.push_back(
        static_cast<double>(after_write.QuadPart - start.QuadPart) * 1000.0 /
        static_cast<double>(frequency.QuadPart));
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_write_sample_failed:" +
                               HResultHex(hr));
      return false;
    }

    ++frame_index;
    ++stats->encoder_proof_frames_submitted;
    stats->encoder_proof_last_error = "none";
    return true;
  }

  void Finalize(const LARGE_INTEGER& frequency,
                PublicationHandoffStats* stats) {
    if (!Enabled(stats)) {
      return;
    }
    if (sink_writer != nullptr && !finalized) {
      LARGE_INTEGER start{};
      LARGE_INTEGER end{};
      QueryPerformanceCounter(&start);
      const HRESULT hr = sink_writer->Finalize();
      QueryPerformanceCounter(&end);
      stats->encoder_proof_finalize_ms =
          static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
          static_cast<double>(frequency.QuadPart);
      finalized = true;
      if (SUCCEEDED(hr)) {
        stats->encoder_proof_finalized = true;
      } else {
        ++stats->encoder_proof_write_failures;
        SetEncoderProofError(stats,
                             "encoder_proof_finalize_failed:" + HResultHex(hr));
      }
    }
    sink_writer.Reset();
    device_manager.Reset();
    encoder_textures.clear();
    if (mf_started) {
      MFShutdown();
      mf_started = false;
    }
    if (!output_path.empty() && fs::exists(output_path)) {
      std::error_code ec;
      stats->encoder_proof_output_bytes = fs::file_size(output_path, ec);
      if (ec) {
        stats->encoder_proof_output_bytes = 0;
      }
    }
  }

 private:
  ComPtr<IMFSinkWriter> sink_writer;
  ComPtr<IMFDXGIDeviceManager> device_manager;
  std::vector<ComPtr<ID3D11Texture2D>> encoder_textures;
  DWORD stream_index = 0;
  UINT reset_token = 0;
  uint64_t frame_index = 0;
  LONGLONG frame_duration_100ns = 333333;
  size_t next_texture_index = 0;
  uint32_t texture_width = 0;
  uint32_t texture_height = 0;
  bool mf_started = false;
  bool finalized = false;

  bool Initialize(ID3D11Device* device,
                  const OutputDimensions& output,
                  PublicationHandoffStats* stats) {
    if (sink_writer != nullptr) {
      return true;
    }
    if (output.width == 0 || output.height == 0) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats, "encoder_proof_invalid_size");
      return false;
    }

    LARGE_INTEGER frequency{};
    LARGE_INTEGER init_start{};
    LARGE_INTEGER init_end{};
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&init_start);

    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_mfstartup_failed:" + HResultHex(hr));
      return false;
    }
    mf_started = true;

    hr = MFCreateDXGIDeviceManager(&reset_token, &device_manager);
    if (SUCCEEDED(hr)) {
      hr = device_manager->ResetDevice(device, reset_token);
    }
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_device_manager_failed:" +
                               HResultHex(hr));
      return false;
    }

    ComPtr<IMFAttributes> attributes;
    hr = MFCreateAttributes(&attributes, 4);
    if (SUCCEEDED(hr)) {
      hr = attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS,
                                 TRUE);
    }
    if (SUCCEEDED(hr)) {
      hr = attributes->SetUnknown(MF_SINK_WRITER_D3D_MANAGER,
                                  device_manager.Get());
    }
    if (SUCCEEDED(hr)) {
      hr = MFCreateSinkWriterFromURL(output_path.wstring().c_str(), nullptr,
                                     attributes.Get(), &sink_writer);
    }
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_sink_writer_failed:" +
                               HResultHex(hr));
      return false;
    }

    const UINT fps =
        static_cast<UINT>(std::max(1, stats->requested_target_fps));
    frame_duration_100ns =
        static_cast<LONGLONG>((10000000LL + fps / 2) / fps);
    const UINT32 bitrate =
        static_cast<UINT32>(std::max<uint64_t>(
            2000000ULL,
            std::min<uint64_t>(
                24000000ULL,
                static_cast<uint64_t>(output.width) * output.height *
                    static_cast<uint64_t>(fps) / 4ULL)));

    ComPtr<IMFMediaType> output_type;
    hr = MFCreateMediaType(&output_type);
    if (SUCCEEDED(hr)) {
      hr = output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    }
    if (SUCCEEDED(hr)) {
      hr = output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    }
    if (SUCCEEDED(hr)) {
      hr = output_type->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    }
    if (SUCCEEDED(hr)) {
      hr = output_type->SetUINT32(MF_MT_INTERLACE_MODE,
                                  MFVideoInterlace_Progressive);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeSize(output_type.Get(), MF_MT_FRAME_SIZE,
                              output.width, output.height);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeRatio(output_type.Get(), MF_MT_FRAME_RATE, fps, 1);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeRatio(output_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1,
                               1);
    }
    if (SUCCEEDED(hr)) {
      hr = sink_writer->AddStream(output_type.Get(), &stream_index);
    }

    ComPtr<IMFMediaType> input_type;
    if (SUCCEEDED(hr)) {
      hr = MFCreateMediaType(&input_type);
    }
    if (SUCCEEDED(hr)) {
      hr = input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    }
    if (SUCCEEDED(hr)) {
      hr = input_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    }
    if (SUCCEEDED(hr)) {
      hr = input_type->SetUINT32(MF_MT_INTERLACE_MODE,
                                 MFVideoInterlace_Progressive);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeSize(input_type.Get(), MF_MT_FRAME_SIZE,
                              output.width, output.height);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeRatio(input_type.Get(), MF_MT_FRAME_RATE, fps, 1);
    }
    if (SUCCEEDED(hr)) {
      hr = MFSetAttributeRatio(input_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1,
                               1);
    }
    if (SUCCEEDED(hr)) {
      hr = sink_writer->SetInputMediaType(stream_index, input_type.Get(),
                                          nullptr);
    }
    if (SUCCEEDED(hr)) {
      hr = sink_writer->BeginWriting();
    }
    if (FAILED(hr)) {
      ++stats->encoder_proof_write_failures;
      SetEncoderProofError(stats,
                           "encoder_proof_media_type_failed:" +
                               HResultHex(hr));
      QueryPerformanceCounter(&init_end);
      stats->encoder_proof_init_ms =
          static_cast<double>(init_end.QuadPart - init_start.QuadPart) *
          1000.0 / static_cast<double>(frequency.QuadPart);
      return false;
    }

    QueryPerformanceCounter(&init_end);
    stats->encoder_proof_init_ms =
        static_cast<double>(init_end.QuadPart - init_start.QuadPart) *
        1000.0 / static_cast<double>(frequency.QuadPart);
    stats->encoder_proof_initialized = true;
    stats->encoder_proof_hardware_transforms_requested = true;
    stats->encoder_proof_codec = "h264";
    stats->encoder_proof_container = "mp4";
    stats->encoder_proof_last_error = "none";
    return true;
  }

  bool EnsureTextureRing(ID3D11Device* device,
                         const OutputDimensions& output,
                         PublicationHandoffStats* stats) {
    if (texture_width == output.width && texture_height == output.height &&
        !encoder_textures.empty()) {
      return true;
    }
    encoder_textures.clear();
    next_texture_index = 0;
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = output.width;
    desc.Height = output.height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_NV12;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    for (int i = 0; i < 8; ++i) {
      ComPtr<ID3D11Texture2D> texture;
      const HRESULT hr = device->CreateTexture2D(&desc, nullptr, &texture);
      if (FAILED(hr)) {
        ++stats->encoder_proof_write_failures;
        SetEncoderProofError(stats,
                             "encoder_proof_texture_ring_create_failed:" +
                                 HResultHex(hr));
        encoder_textures.clear();
        return false;
      }
      encoder_textures.push_back(texture);
    }
    texture_width = output.width;
    texture_height = output.height;
    return true;
  }
};

struct PublicationHandoffProcessor {
  ComPtr<ID3D11VertexShader> vertex_shader;
  ComPtr<ID3D11PixelShader> pixel_shader;
  ComPtr<ID3D11SamplerState> sampler_state;
  ComPtr<ID3D11Texture2D> output_texture;
  ComPtr<ID3D11RenderTargetView> output_rtv;
  ComPtr<ID3D11Texture2D> output_staging_texture;
  ComPtr<ID3D11Texture2D> nv12_texture;
  ComPtr<ID3D11Texture2D> nv12_staging_texture;
  ComPtr<ID3D11Texture2D> p010_texture;
  ComPtr<ID3D11Texture2D> p010_staging_texture;
  ComPtr<ID3D11VideoDevice> video_device;
  ComPtr<ID3D11VideoContext> video_context;
  ComPtr<ID3D11VideoProcessorEnumerator> video_processor_enumerator;
  ComPtr<ID3D11VideoProcessor> video_processor;
  ComPtr<ID3D11VideoProcessorInputView> video_input_view;
  ComPtr<ID3D11VideoProcessorOutputView> video_output_view;
  std::map<ID3D11Texture2D*, ComPtr<ID3D11ShaderResourceView>>
      source_shader_views;
  uint32_t output_texture_width = 0;
  uint32_t output_texture_height = 0;
  std::vector<uint8_t> output_bgra;
  fs::path proof_output_dir;

  bool EnsureShaders(ID3D11Device* device, PublicationHandoffStats* stats) {
    if (vertex_shader != nullptr && pixel_shader != nullptr &&
        sampler_state != nullptr) {
      return true;
    }

    static constexpr char kShaderSource[] = R"(
struct VSOut {
  float4 pos : SV_POSITION;
  float2 uv : TEXCOORD0;
};

VSOut VSMain(uint vertexId : SV_VertexID) {
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(-1.0,  3.0),
    float2( 3.0, -1.0)
  };
  VSOut output;
  output.pos = float4(positions[vertexId], 0.0, 1.0);
  output.uv = float2(
    0.5 * (output.pos.x + 1.0),
    0.5 * (1.0 - output.pos.y)
  );
  return output;
}

Texture2D<float4> sourceTexture : register(t0);
SamplerState sourceSampler : register(s0);

float4 PSMain(VSOut input) : SV_TARGET {
  return sourceTexture.Sample(sourceSampler, input.uv);
}
)";

    ComPtr<ID3DBlob> vertex_blob;
    ComPtr<ID3DBlob> pixel_blob;
    ComPtr<ID3DBlob> errors;
    HRESULT hr = D3DCompile(kShaderSource, std::strlen(kShaderSource),
                            "publication_handoff_scale", nullptr, nullptr,
                            "VSMain", "vs_4_0", 0, 0, &vertex_blob, &errors);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_vertex_shader_compile_failed";
      return false;
    }
    errors.Reset();
    hr = D3DCompile(kShaderSource, std::strlen(kShaderSource),
                    "publication_handoff_scale", nullptr, nullptr, "PSMain",
                    "ps_4_0", 0, 0, &pixel_blob, &errors);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_pixel_shader_compile_failed";
      return false;
    }

    hr = device->CreateVertexShader(vertex_blob->GetBufferPointer(),
                                    vertex_blob->GetBufferSize(), nullptr,
                                    &vertex_shader);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_vertex_shader_create_failed";
      return false;
    }
    hr = device->CreatePixelShader(pixel_blob->GetBufferPointer(),
                                   pixel_blob->GetBufferSize(), nullptr,
                                   &pixel_shader);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_pixel_shader_create_failed";
      return false;
    }

    D3D11_SAMPLER_DESC sampler{};
    sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.ComparisonFunc = D3D11_COMPARISON_NEVER;
    sampler.MinLOD = 0.0f;
    sampler.MaxLOD = D3D11_FLOAT32_MAX;
    hr = device->CreateSamplerState(&sampler, &sampler_state);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_sampler_create_failed";
      return false;
    }
    return true;
  }

  bool EnsureOutputTextures(ID3D11Device* device,
                            const OutputDimensions& output,
                            PublicationHandoffStats* stats) {
    if (output_texture != nullptr && output_staging_texture != nullptr &&
        output_rtv != nullptr && output_texture_width == output.width &&
        output_texture_height == output.height) {
      return true;
    }

    output_texture.Reset();
    output_staging_texture.Reset();
    output_rtv.Reset();
    nv12_texture.Reset();
    nv12_staging_texture.Reset();
    p010_texture.Reset();
    p010_staging_texture.Reset();
    video_processor_enumerator.Reset();
    video_processor.Reset();
    video_input_view.Reset();
    video_output_view.Reset();

    D3D11_TEXTURE2D_DESC output_desc{};
    output_desc.Width = output.width;
    output_desc.Height = output.height;
    output_desc.MipLevels = 1;
    output_desc.ArraySize = 1;
    output_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    output_desc.SampleDesc.Count = 1;
    output_desc.Usage = D3D11_USAGE_DEFAULT;
    output_desc.BindFlags =
        D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    HRESULT hr = device->CreateTexture2D(&output_desc, nullptr,
                                         &output_texture);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_output_texture_create_failed";
      return false;
    }
    hr = device->CreateRenderTargetView(output_texture.Get(), nullptr,
                                        &output_rtv);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_output_rtv_create_failed";
      return false;
    }

    D3D11_TEXTURE2D_DESC staging_desc = output_desc;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.BindFlags = 0;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = device->CreateTexture2D(&staging_desc, nullptr,
                                 &output_staging_texture);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_output_staging_create_failed";
      return false;
    }

    output_texture_width = output.width;
    output_texture_height = output.height;
    return true;
  }

  bool EnsureNv12Output(ID3D11Device* device,
                        ID3D11DeviceContext* context,
                        const OutputDimensions& output,
                        PublicationHandoffStats* stats) {
    if (nv12_texture != nullptr && nv12_staging_texture != nullptr &&
        video_processor != nullptr && video_input_view != nullptr &&
        video_output_view != nullptr && output_texture_width == output.width &&
        output_texture_height == output.height) {
      return true;
    }

    nv12_texture.Reset();
    nv12_staging_texture.Reset();
    video_processor_enumerator.Reset();
    video_processor.Reset();
    video_input_view.Reset();
    video_output_view.Reset();

    if (video_device == nullptr) {
      HRESULT hr = device->QueryInterface(IID_PPV_ARGS(&video_device));
      if (FAILED(hr)) {
        stats->last_error = "publication_handoff_video_device_unavailable";
        return false;
      }
    }
    if (video_context == nullptr) {
      HRESULT hr = context->QueryInterface(IID_PPV_ARGS(&video_context));
      if (FAILED(hr)) {
        stats->last_error = "publication_handoff_video_context_unavailable";
        return false;
      }
    }

    D3D11_TEXTURE2D_DESC nv12_desc{};
    nv12_desc.Width = output.width;
    nv12_desc.Height = output.height;
    nv12_desc.MipLevels = 1;
    nv12_desc.ArraySize = 1;
    nv12_desc.Format = DXGI_FORMAT_NV12;
    nv12_desc.SampleDesc.Count = 1;
    nv12_desc.Usage = D3D11_USAGE_DEFAULT;
    nv12_desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    HRESULT hr = device->CreateTexture2D(&nv12_desc, nullptr, &nv12_texture);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_nv12_texture_create_failed";
      return false;
    }
    stats->nv12_texture_created = true;

    D3D11_TEXTURE2D_DESC nv12_staging_desc = nv12_desc;
    nv12_staging_desc.Usage = D3D11_USAGE_STAGING;
    nv12_staging_desc.BindFlags = 0;
    nv12_staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = device->CreateTexture2D(&nv12_staging_desc, nullptr,
                                 &nv12_staging_texture);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_nv12_staging_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_CONTENT_DESC content_desc{};
    content_desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    content_desc.InputWidth = output.width;
    content_desc.InputHeight = output.height;
    content_desc.OutputWidth = output.width;
    content_desc.OutputHeight = output.height;
    content_desc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    hr = video_device->CreateVideoProcessorEnumerator(
        &content_desc, &video_processor_enumerator);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_processor_enum_failed";
      return false;
    }
    stats->video_processor_probe_available = true;
    stats->video_processor_bgra_input_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_B8G8R8A8_UNORM,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT);
    stats->video_processor_r10_input_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_R10G10B10A2_UNORM,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT);
    stats->video_processor_nv12_output_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_NV12,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT);
    stats->video_processor_p010_output_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_P010,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT);
    stats->video_processor_bgra_to_nv12_supported =
        stats->video_processor_bgra_input_supported &&
        stats->video_processor_nv12_output_supported;
    stats->video_processor_r10_to_nv12_supported =
        stats->video_processor_r10_input_supported &&
        stats->video_processor_nv12_output_supported;
    stats->video_processor_r10_to_p010_supported =
        stats->video_processor_r10_input_supported &&
        stats->video_processor_p010_output_supported;
    hr = video_device->CreateVideoProcessor(video_processor_enumerator.Get(), 0,
                                            &video_processor);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_processor_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input_desc{};
    input_desc.FourCC = 0;
    input_desc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    input_desc.Texture2D.MipSlice = 0;
    input_desc.Texture2D.ArraySlice = 0;
    hr = video_device->CreateVideoProcessorInputView(
        output_texture.Get(), video_processor_enumerator.Get(), &input_desc,
        &video_input_view);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_input_view_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC output_desc{};
    output_desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    output_desc.Texture2D.MipSlice = 0;
    hr = video_device->CreateVideoProcessorOutputView(
        nv12_texture.Get(), video_processor_enumerator.Get(), &output_desc,
        &video_output_view);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_output_view_create_failed";
      return false;
    }
    return true;
  }

  bool ConvertOutputToNv12(ID3D11Device* device,
                           ID3D11DeviceContext* context,
                           const OutputDimensions& output,
                           bool proof_readback,
                           const LARGE_INTEGER& frequency,
                           PublicationHandoffStats* stats) {
    if (!EnsureNv12Output(device, context, output, stats)) {
      ++stats->nv12_convert_failures;
      return false;
    }

    LARGE_INTEGER start{};
    LARGE_INTEGER after_convert{};
    LARGE_INTEGER after_readback{};
    QueryPerformanceCounter(&start);

    RECT rect{
        0,
        0,
        static_cast<LONG>(output.width),
        static_cast<LONG>(output.height),
    };
    video_context->VideoProcessorSetStreamFrameFormat(
        video_processor.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
    video_context->VideoProcessorSetStreamSourceRect(video_processor.Get(), 0,
                                                     TRUE, &rect);
    video_context->VideoProcessorSetStreamDestRect(video_processor.Get(), 0,
                                                   TRUE, &rect);
    video_context->VideoProcessorSetOutputTargetRect(video_processor.Get(),
                                                     TRUE, &rect);

    D3D11_VIDEO_PROCESSOR_STREAM stream{};
    stream.Enable = TRUE;
    stream.pInputSurface = video_input_view.Get();
    HRESULT hr = video_context->VideoProcessorBlt(
        video_processor.Get(), video_output_view.Get(), 0, 1, &stream);
    QueryPerformanceCounter(&after_convert);
    stats->nv12_convert_ms.push_back(
        static_cast<double>(after_convert.QuadPart - start.QuadPart) *
        1000.0 / static_cast<double>(frequency.QuadPart));
    if (FAILED(hr)) {
      ++stats->nv12_convert_failures;
      stats->last_error = "publication_handoff_nv12_convert_failed";
      return false;
    }
    ++stats->nv12_output_frames;

    if (proof_readback) {
      context->CopyResource(nv12_staging_texture.Get(), nv12_texture.Get());
      context->Flush();
      D3D11_MAPPED_SUBRESOURCE mapped{};
      hr = context->Map(nv12_staging_texture.Get(), 0, D3D11_MAP_READ, 0,
                        &mapped);
      QueryPerformanceCounter(&after_readback);
      stats->nv12_proof_readback_ms.push_back(
          static_cast<double>(after_readback.QuadPart -
                              after_convert.QuadPart) *
          1000.0 / static_cast<double>(frequency.QuadPart));
      if (SUCCEEDED(hr)) {
        ++stats->nv12_proof_readback_frames;
        if (SampleNv12LumaLooksVisible(mapped, output.width, output.height)) {
          ++stats->nv12_visible_proof_frames;
        }
        context->Unmap(nv12_staging_texture.Get(), 0);
      } else {
        ++stats->readback_failures;
        stats->last_error = "publication_handoff_nv12_map_failed";
        return false;
      }
    }
    return true;
  }

  bool EnsureP010Output(ID3D11Device* device,
                        ID3D11DeviceContext* context,
                        const OutputDimensions& output,
                        PublicationHandoffStats* stats) {
    if (p010_texture != nullptr && p010_staging_texture != nullptr &&
        video_processor != nullptr && video_input_view != nullptr &&
        video_output_view != nullptr && output_texture_width == output.width &&
        output_texture_height == output.height) {
      return true;
    }

    p010_texture.Reset();
    p010_staging_texture.Reset();
    video_processor_enumerator.Reset();
    video_processor.Reset();
    video_input_view.Reset();
    video_output_view.Reset();

    if (video_device == nullptr) {
      HRESULT hr = device->QueryInterface(IID_PPV_ARGS(&video_device));
      if (FAILED(hr)) {
        stats->last_error = "publication_handoff_video_device_unavailable";
        return false;
      }
    }
    if (video_context == nullptr) {
      HRESULT hr = context->QueryInterface(IID_PPV_ARGS(&video_context));
      if (FAILED(hr)) {
        stats->last_error = "publication_handoff_video_context_unavailable";
        return false;
      }
    }

    D3D11_TEXTURE2D_DESC p010_desc{};
    p010_desc.Width = output.width;
    p010_desc.Height = output.height;
    p010_desc.MipLevels = 1;
    p010_desc.ArraySize = 1;
    p010_desc.Format = DXGI_FORMAT_P010;
    p010_desc.SampleDesc.Count = 1;
    p010_desc.Usage = D3D11_USAGE_DEFAULT;
    p010_desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    HRESULT hr = device->CreateTexture2D(&p010_desc, nullptr, &p010_texture);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_p010_texture_create_failed";
      return false;
    }
    stats->p010_texture_created = true;

    D3D11_TEXTURE2D_DESC p010_staging_desc = p010_desc;
    p010_staging_desc.Usage = D3D11_USAGE_STAGING;
    p010_staging_desc.BindFlags = 0;
    p010_staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = device->CreateTexture2D(&p010_staging_desc, nullptr,
                                 &p010_staging_texture);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_p010_staging_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_CONTENT_DESC content_desc{};
    content_desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    content_desc.InputWidth = output.width;
    content_desc.InputHeight = output.height;
    content_desc.OutputWidth = output.width;
    content_desc.OutputHeight = output.height;
    content_desc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    hr = video_device->CreateVideoProcessorEnumerator(
        &content_desc, &video_processor_enumerator);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_processor_enum_failed";
      return false;
    }
    stats->video_processor_probe_available = true;
    stats->video_processor_bgra_input_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_B8G8R8A8_UNORM,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT);
    stats->video_processor_r10_input_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_R10G10B10A2_UNORM,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT);
    stats->video_processor_nv12_output_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_NV12,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT);
    stats->video_processor_p010_output_supported =
        CheckVideoProcessorFormatSupport(
            video_processor_enumerator.Get(), DXGI_FORMAT_P010,
            D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT);
    stats->video_processor_bgra_to_nv12_supported =
        stats->video_processor_bgra_input_supported &&
        stats->video_processor_nv12_output_supported;
    stats->video_processor_r10_to_nv12_supported =
        stats->video_processor_r10_input_supported &&
        stats->video_processor_nv12_output_supported;
    stats->video_processor_r10_to_p010_supported =
        stats->video_processor_r10_input_supported &&
        stats->video_processor_p010_output_supported;
    hr = video_device->CreateVideoProcessor(video_processor_enumerator.Get(), 0,
                                            &video_processor);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_processor_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input_desc{};
    input_desc.FourCC = 0;
    input_desc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    input_desc.Texture2D.MipSlice = 0;
    input_desc.Texture2D.ArraySlice = 0;
    hr = video_device->CreateVideoProcessorInputView(
        output_texture.Get(), video_processor_enumerator.Get(), &input_desc,
        &video_input_view);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_input_view_create_failed";
      return false;
    }

    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC output_desc{};
    output_desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    output_desc.Texture2D.MipSlice = 0;
    hr = video_device->CreateVideoProcessorOutputView(
        p010_texture.Get(), video_processor_enumerator.Get(), &output_desc,
        &video_output_view);
    if (FAILED(hr)) {
      stats->last_error =
          "publication_handoff_video_output_view_create_failed";
      return false;
    }
    return true;
  }

  bool ConvertOutputToP010(ID3D11Device* device,
                           ID3D11DeviceContext* context,
                           const OutputDimensions& output,
                           bool proof_readback,
                           const LARGE_INTEGER& frequency,
                           PublicationHandoffStats* stats) {
    if (!EnsureP010Output(device, context, output, stats)) {
      ++stats->p010_convert_failures;
      return false;
    }

    LARGE_INTEGER start{};
    LARGE_INTEGER after_convert{};
    LARGE_INTEGER after_readback{};
    QueryPerformanceCounter(&start);

    RECT rect{
        0,
        0,
        static_cast<LONG>(output.width),
        static_cast<LONG>(output.height),
    };
    video_context->VideoProcessorSetStreamFrameFormat(
        video_processor.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
    video_context->VideoProcessorSetStreamSourceRect(video_processor.Get(), 0,
                                                     TRUE, &rect);
    video_context->VideoProcessorSetStreamDestRect(video_processor.Get(), 0,
                                                   TRUE, &rect);
    video_context->VideoProcessorSetOutputTargetRect(video_processor.Get(),
                                                     TRUE, &rect);

    D3D11_VIDEO_PROCESSOR_STREAM stream{};
    stream.Enable = TRUE;
    stream.pInputSurface = video_input_view.Get();
    HRESULT hr = video_context->VideoProcessorBlt(
        video_processor.Get(), video_output_view.Get(), 0, 1, &stream);
    QueryPerformanceCounter(&after_convert);
    stats->p010_convert_ms.push_back(
        static_cast<double>(after_convert.QuadPart - start.QuadPart) *
        1000.0 / static_cast<double>(frequency.QuadPart));
    if (FAILED(hr)) {
      ++stats->p010_convert_failures;
      stats->last_error = "publication_handoff_p010_convert_failed";
      return false;
    }
    ++stats->p010_output_frames;

    if (proof_readback) {
      context->CopyResource(p010_staging_texture.Get(), p010_texture.Get());
      context->Flush();
      D3D11_MAPPED_SUBRESOURCE mapped{};
      hr = context->Map(p010_staging_texture.Get(), 0, D3D11_MAP_READ, 0,
                        &mapped);
      QueryPerformanceCounter(&after_readback);
      stats->p010_proof_readback_ms.push_back(
          static_cast<double>(after_readback.QuadPart -
                              after_convert.QuadPart) *
          1000.0 /
          static_cast<double>(frequency.QuadPart));
      if (SUCCEEDED(hr)) {
        ++stats->p010_proof_readback_frames;
        if (SampleP010LumaLooksVisible(mapped, output.width, output.height)) {
          ++stats->p010_visible_proof_frames;
        }
        context->Unmap(p010_staging_texture.Get(), 0);
      } else {
        ++stats->readback_failures;
        stats->last_error = "publication_handoff_p010_map_failed";
        return false;
      }
    }
    return true;
  }

  ID3D11ShaderResourceView* SourceViewFor(ID3D11Device* device,
                                          ID3D11Texture2D* texture,
                                          PublicationHandoffStats* stats) {
    const auto existing = source_shader_views.find(texture);
    if (existing != source_shader_views.end()) {
      return existing->second.Get();
    }
    ComPtr<ID3D11ShaderResourceView> view;
    HRESULT hr = device->CreateShaderResourceView(texture, nullptr, &view);
    if (FAILED(hr)) {
      stats->last_error = "publication_handoff_source_srv_create_failed";
      return nullptr;
    }
    auto* raw = view.Get();
    source_shader_views[texture] = std::move(view);
    return raw;
  }

  bool Process(ID3D11Device* device,
               ID3D11DeviceContext* context,
               ID3D11Texture2D* texture,
               uint64_t frame_qpc,
               const LARGE_INTEGER& frequency,
               PublicationHandoffStats* stats,
               LocalH264EncoderProof* encoder_proof,
               uint64_t* output_qpc) {
    if (device == nullptr || context == nullptr || texture == nullptr ||
        stats == nullptr) {
      return false;
    }

    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    const auto format = static_cast<DXGI_FORMAT>(desc.Format);
    stats->source_width = desc.Width;
    stats->source_height = desc.Height;
    stats->dxgi_format = desc.Format;
    if (!IsBgra(format) && !IsRgba(format) && !IsR10G10B10A2(format)) {
      stats->unsupported_format = true;
      stats->last_error = "publication_handoff_unsupported_format";
      return false;
    }

    const OutputDimensions output = FitWithin(
        desc.Width, desc.Height,
        static_cast<uint32_t>(stats->requested_max_width),
        static_cast<uint32_t>(stats->requested_max_height));
    if (output.width == 0 || output.height == 0) {
      stats->last_error = "publication_handoff_invalid_output_size";
      return false;
    }
    stats->output_width = output.width;
    stats->output_height = output.height;
    if (!EnsureShaders(device, stats) ||
        !EnsureOutputTextures(device, output, stats)) {
      return false;
    }
    ID3D11ShaderResourceView* source_view =
        SourceViewFor(device, texture, stats);
    if (source_view == nullptr) {
      return false;
    }

    LARGE_INTEGER start{};
    LARGE_INTEGER after_scale_submit{};
    LARGE_INTEGER after_map{};
    LARGE_INTEGER end{};
    QueryPerformanceCounter(&start);
    if (frame_qpc > 0 && static_cast<uint64_t>(start.QuadPart) >= frame_qpc) {
      stats->frame_age_ms.push_back(
          static_cast<double>(static_cast<uint64_t>(start.QuadPart) -
                              frame_qpc) *
          1000.0 / static_cast<double>(frequency.QuadPart));
    }

    D3D11_VIEWPORT viewport{};
    viewport.TopLeftX = 0.0f;
    viewport.TopLeftY = 0.0f;
    viewport.Width = static_cast<float>(output.width);
    viewport.Height = static_cast<float>(output.height);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;

    ID3D11RenderTargetView* render_targets[] = {output_rtv.Get()};
    ID3D11ShaderResourceView* shader_resources[] = {source_view};
    ID3D11SamplerState* samplers[] = {sampler_state.Get()};
    context->RSSetViewports(1, &viewport);
    context->OMSetRenderTargets(1, render_targets, nullptr);
    context->IASetInputLayout(nullptr);
    context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context->VSSetShader(vertex_shader.Get(), nullptr, 0);
    context->PSSetShader(pixel_shader.Get(), nullptr, 0);
    context->PSSetShaderResources(0, 1, shader_resources);
    context->PSSetSamplers(0, 1, samplers);
    context->Draw(3, 0);
    ID3D11ShaderResourceView* null_srv[] = {nullptr};
    context->PSSetShaderResources(0, 1, null_srv);
    ID3D11RenderTargetView* null_rtv[] = {nullptr};
    context->OMSetRenderTargets(1, null_rtv, nullptr);
    QueryPerformanceCounter(&after_scale_submit);

    ++stats->output_frames;
    const bool readback_every_frame = stats->readback_mode != "proof-only";
    const bool needs_proof_readback =
        stats->proof_output_frames <
        static_cast<uint64_t>(std::max(0, stats->requested_proof_frames));
    const bool should_readback = readback_every_frame || needs_proof_readback;
    const bool wants_nv12_output = stats->output_format == "nv12";
    const bool wants_p010_output = stats->output_format == "p010";
    if (wants_nv12_output) {
      if (!ConvertOutputToNv12(device, context, output, needs_proof_readback,
                               frequency, stats)) {
        QueryPerformanceCounter(&end);
        stats->scale_ms.push_back(
            static_cast<double>(after_scale_submit.QuadPart - start.QuadPart) *
            1000.0 / static_cast<double>(frequency.QuadPart));
        stats->total_frame_ms.push_back(
            static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
            static_cast<double>(frequency.QuadPart));
        return false;
      }
      if (encoder_proof != nullptr &&
          !encoder_proof->Submit(device, context, nv12_texture.Get(), output,
                                 frequency, stats)) {
        QueryPerformanceCounter(&end);
        stats->scale_ms.push_back(
            static_cast<double>(after_scale_submit.QuadPart - start.QuadPart) *
            1000.0 / static_cast<double>(frequency.QuadPart));
        stats->total_frame_ms.push_back(
            static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
            static_cast<double>(frequency.QuadPart));
        return false;
      }
    }
    if (wants_p010_output) {
      if (!ConvertOutputToP010(device, context, output, needs_proof_readback,
                               frequency, stats)) {
        QueryPerformanceCounter(&end);
        stats->scale_ms.push_back(
            static_cast<double>(after_scale_submit.QuadPart - start.QuadPart) *
            1000.0 / static_cast<double>(frequency.QuadPart));
        stats->total_frame_ms.push_back(
            static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
            static_cast<double>(frequency.QuadPart));
        return false;
      }
    }

    if (should_readback) {
      const size_t output_bytes =
          static_cast<size_t>(output.width) * output.height * 4;
      if (output_bgra.size() != output_bytes) {
        output_bgra.assign(output_bytes, 0);
      }

      context->CopyResource(output_staging_texture.Get(), output_texture.Get());
      context->Flush();

      D3D11_MAPPED_SUBRESOURCE mapped{};
      HRESULT hr =
          context->Map(output_staging_texture.Get(), 0, D3D11_MAP_READ, 0,
                       &mapped);
      QueryPerformanceCounter(&after_map);
      stats->readback_ms.push_back(
          static_cast<double>(after_map.QuadPart -
                              after_scale_submit.QuadPart) *
              1000.0 /
          static_cast<double>(frequency.QuadPart));
      if (FAILED(hr)) {
        ++stats->readback_failures;
        stats->last_error = "publication_handoff_map_failed";
        QueryPerformanceCounter(&end);
      } else {
        ++stats->readback_frames;
        for (uint32_t y = 0; y < output.height; ++y) {
          const auto* source_row =
              reinterpret_cast<const uint8_t*>(mapped.pData) +
              static_cast<size_t>(y) * mapped.RowPitch;
          auto* dest_row = output_bgra.data() +
                           static_cast<size_t>(y) * output.width * 4;
          std::memcpy(dest_row, source_row,
                      static_cast<size_t>(output.width) * 4);
        }
        context->Unmap(output_staging_texture.Get(), 0);
        QueryPerformanceCounter(&end);

        const bool visible = SampleBgraBufferLooksVisible(
            output_bgra, output.width, output.height);
        if (readback_every_frame && visible) {
          ++stats->visible_output_frames;
        }
        if (needs_proof_readback) {
          std::wostringstream name;
          name << L"publication-frame-" << std::setw(6) << std::setfill(L'0')
               << (stats->proof_output_frames + 1) << L".png";
          if (WriteBgraPng(proof_output_dir / name.str(), output.width,
                           output.height, output.width * 4,
                           output_bgra.data())) {
            ++stats->proof_output_frames;
            if (visible) {
              ++stats->visible_proof_output_frames;
            }
          } else {
            ++stats->proof_output_write_failures;
          }
        }
      }
    } else {
      QueryPerformanceCounter(&end);
    }
    stats->scale_ms.push_back(
        static_cast<double>(after_scale_submit.QuadPart - start.QuadPart) *
        1000.0 / static_cast<double>(frequency.QuadPart));
    stats->total_frame_ms.push_back(
        static_cast<double>(end.QuadPart - start.QuadPart) * 1000.0 /
        static_cast<double>(frequency.QuadPart));
    if (output_qpc != nullptr) {
      *output_qpc = static_cast<uint64_t>(end.QuadPart);
    }
    stats->last_error = "none";
    return true;
  }
};

HostConsumerStats RunHostConsumer(HANDLE frame_event,
                                  iggc::SharedTextureState* shared_state,
                                  std::atomic<bool>* stop_requested,
                                  int max_proof_frames,
                                  const fs::path& output_dir,
                                  int publication_handoff_proof_frames,
                                  const std::string& publication_readback_mode,
                                  const std::string& publication_output_format,
                                  const std::string& publication_encoder_proof,
                                  PublicationHandoffStats* handoff_stats) {
  HostConsumerStats stats;
  stats.enabled = true;
  stats.shared_state_available = shared_state != nullptr;
  if (handoff_stats != nullptr && handoff_stats->enabled) {
    handoff_stats->shared_state_available = shared_state != nullptr;
  }
  if (frame_event == nullptr || shared_state == nullptr) {
    stats.last_error = "host_consumer_state_missing";
    if (handoff_stats != nullptr && handoff_stats->enabled) {
      handoff_stats->last_error = "publication_handoff_state_missing";
    }
    return stats;
  }

  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  D3D_FEATURE_LEVEL feature_level{};
  const D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                                 feature_levels, ARRAYSIZE(feature_levels),
                                 D3D11_SDK_VERSION, &device, &feature_level,
                                 &context);
  if (FAILED(hr)) {
    stats.last_error = "host_d3d11_device_create_failed";
    if (handoff_stats != nullptr && handoff_stats->enabled) {
      handoff_stats->last_error = "publication_handoff_d3d11_device_create_failed";
    }
    return stats;
  }
  stats.d3d_device_created = true;
  if (handoff_stats != nullptr && handoff_stats->enabled) {
    handoff_stats->d3d_device_created = true;
  }

  LARGE_INTEGER frequency{};
  QueryPerformanceFrequency(&frequency);
  auto qpc_to_ms = [&](uint64_t delta) {
    return static_cast<double>(delta) * 1000.0 /
           static_cast<double>(frequency.QuadPart);
  };

  std::map<uint32_t, ComPtr<ID3D11Texture2D>> textures;
  PublicationHandoffProcessor handoff_processor;
  LocalH264EncoderProof encoder_proof;
  if (handoff_stats != nullptr && handoff_stats->enabled) {
    handoff_stats->readback_mode = NormalizeReadbackMode(publication_readback_mode);
    handoff_stats->output_format =
        NormalizePublicationOutputFormat(publication_output_format);
    handoff_stats->encoder_format =
        handoff_stats->output_format == "nv12"
            ? "DXGI_FORMAT_NV12"
            : (handoff_stats->output_format == "p010" ? "DXGI_FORMAT_P010"
                                                       : "none");
    handoff_stats->encoder_proof_mode =
        NormalizePublicationEncoderProof(publication_encoder_proof);
    handoff_stats->encoder_proof_enabled =
        handoff_stats->encoder_proof_mode == "h264-mf";
    if (handoff_stats->encoder_proof_enabled) {
      handoff_stats->encoder_proof_codec = "h264";
      handoff_stats->encoder_proof_container = "mp4";
      encoder_proof.output_path = output_dir / L"publication-encoder-proof.mp4";
      handoff_stats->encoder_proof_output_path =
          WideToUtf8(encoder_proof.output_path.wstring());
      if (handoff_stats->output_format != "nv12") {
        SetEncoderProofError(handoff_stats, "encoder_proof_requires_nv12");
      }
    }
    if (handoff_stats->output_format == "nv12") {
      handoff_stats->mode = "gpu_scaled_nv12_handoff_probe";
      handoff_stats->scale_mode = "contain_fit_gpu_scale_then_video_processor_nv12";
    } else if (handoff_stats->output_format == "p010") {
      handoff_stats->mode = "gpu_scaled_p010_handoff_probe";
      handoff_stats->scale_mode =
          "contain_fit_gpu_scale_then_video_processor_p010";
    } else {
      handoff_stats->mode =
          handoff_stats->readback_mode == "proof-only"
              ? "gpu_scaled_texture_handoff_probe"
              : "gpu_scaled_bgra_readback_probe";
      handoff_stats->scale_mode = "contain_fit_gpu_before_readback";
    }
    handoff_stats->requested_proof_frames =
        std::clamp(publication_handoff_proof_frames,
                   iggc::kDefaultPublicationHandoffProofFrames,
                   iggc::kMaxPublicationHandoffProofFrames);
    if (handoff_stats->encoder_proof_enabled &&
        handoff_stats->requested_proof_frames > 0) {
      handoff_stats->proof_readback_suppressed_for_encoder = true;
      handoff_stats->requested_proof_frames = 0;
    }
    handoff_processor.proof_output_dir = output_dir / L"publication-frames";
    handoff_stats->proof_output_directory =
        WideToUtf8(handoff_processor.proof_output_dir.wstring());
  }
  uint64_t last_generation = 0;
  uint64_t last_frame_index = 0;
  uint64_t last_frame_qpc = 0;
  uint64_t last_handoff_output_qpc = 0;
  uint64_t next_handoff_due_qpc = 0;
  uint64_t last_handoff_output_frame_index = 0;
  uint64_t latest_handoff_frame_index = 0;
  uint64_t latest_handoff_frame_qpc = 0;
  ComPtr<ID3D11Texture2D> latest_handoff_texture;
  const bool handoff_enabled =
      handoff_stats != nullptr && handoff_stats->enabled;
  const uint64_t handoff_interval_qpc =
      handoff_enabled
          ? static_cast<uint64_t>(std::max<int64_t>(
                1, frequency.QuadPart /
                       std::max(1, handoff_stats->requested_target_fps)))
          : 0;
  const uint64_t handoff_early_tolerance_qpc =
      handoff_interval_qpc > 0
          ? std::max<uint64_t>(1, handoff_interval_qpc / 10)
          : 0;

  auto process_handoff_if_due = [&]() {
    if (!handoff_enabled || latest_handoff_texture == nullptr ||
        latest_handoff_frame_index == 0 || handoff_interval_qpc == 0) {
      return;
    }

    LARGE_INTEGER now{};
    QueryPerformanceCounter(&now);
    const auto now_qpc = static_cast<uint64_t>(now.QuadPart);
    if (next_handoff_due_qpc != 0 &&
        now_qpc + handoff_early_tolerance_qpc < next_handoff_due_qpc) {
      return;
    }
    const uint64_t previous_output_frame_index =
        last_handoff_output_frame_index;
    const bool repeated_output =
        latest_handoff_frame_index == previous_output_frame_index;
    uint64_t output_qpc = 0;
    if (handoff_processor.Process(device.Get(), context.Get(),
                                  latest_handoff_texture.Get(),
                                  latest_handoff_frame_qpc, frequency,
                                  handoff_stats, &encoder_proof,
                                  &output_qpc)) {
      if (repeated_output) {
        ++handoff_stats->repeated_output_frames;
      } else if (previous_output_frame_index != 0 &&
          latest_handoff_frame_index > previous_output_frame_index + 1) {
        handoff_stats->paced_drop_frames +=
            latest_handoff_frame_index - previous_output_frame_index - 1;
      }
      if (last_handoff_output_qpc != 0 &&
          output_qpc > last_handoff_output_qpc) {
        handoff_stats->output_gap_ms.push_back(
            qpc_to_ms(output_qpc - last_handoff_output_qpc));
      }
      last_handoff_output_qpc = output_qpc;
      if (!repeated_output) {
        last_handoff_output_frame_index = latest_handoff_frame_index;
      }
    }
    next_handoff_due_qpc = now_qpc + handoff_interval_qpc;
  };

  while (!stop_requested->load()) {
    DWORD wait_timeout_ms = 250;
    if (handoff_enabled && latest_handoff_texture != nullptr &&
        next_handoff_due_qpc != 0) {
      LARGE_INTEGER now{};
      QueryPerformanceCounter(&now);
      const auto now_qpc = static_cast<uint64_t>(now.QuadPart);
      if (now_qpc + handoff_early_tolerance_qpc >= next_handoff_due_qpc) {
        wait_timeout_ms = 0;
      } else {
        const uint64_t wake_qpc =
            next_handoff_due_qpc - handoff_early_tolerance_qpc;
        const uint64_t delta_qpc = wake_qpc - now_qpc;
        const uint64_t delta_ms =
            (delta_qpc * 1000ULL +
             static_cast<uint64_t>(frequency.QuadPart) - 1ULL) /
            static_cast<uint64_t>(frequency.QuadPart);
        wait_timeout_ms = static_cast<DWORD>(
            std::min<uint64_t>(250, std::max<uint64_t>(1, delta_ms)));
      }
    }

    const DWORD wait_result = WaitForSingleObject(frame_event, wait_timeout_ms);
    if (wait_result != WAIT_OBJECT_0) {
      process_handoff_if_due();
      continue;
    }
    ++stats.observed_frame_signals;
    if (handoff_stats != nullptr && handoff_stats->enabled) {
      ++handoff_stats->observed_frame_signals;
    }
    if (shared_state->magic != iggc::kProtocolMagic ||
        shared_state->version != iggc::kSharedTextureStateVersion) {
      ++stats.invalid_state_reads;
      stats.last_error = "host_shared_state_invalid";
      if (handoff_stats != nullptr && handoff_stats->enabled) {
        ++handoff_stats->invalid_state_reads;
        handoff_stats->last_error = "publication_handoff_shared_state_invalid";
      }
      continue;
    }
    UpdateBackendContractStats(shared_state, &stats, handoff_stats);
    if (shared_state->generation != last_generation) {
      textures.clear();
      latest_handoff_texture.Reset();
      latest_handoff_frame_index = 0;
      latest_handoff_frame_qpc = 0;
      last_handoff_output_frame_index = 0;
      next_handoff_due_qpc = 0;
      last_generation = shared_state->generation;
      const uint32_t ring_depth =
          std::min<uint32_t>(shared_state->ring_depth, iggc::kRingDepth);
      for (uint32_t i = 0; i < ring_depth; ++i) {
        const uint64_t handle_value = shared_state->slots[i].shared_handle;
        if (handle_value == 0) {
          continue;
        }
        ComPtr<ID3D11Texture2D> texture;
        HANDLE handle =
            reinterpret_cast<HANDLE>(static_cast<uintptr_t>(handle_value));
        hr = device->OpenSharedResource(handle, IID_PPV_ARGS(&texture));
        if (SUCCEEDED(hr)) {
          textures[i] = texture;
          ++stats.opened_texture_slots;
          stats.opened_shared_texture = true;
          if (handoff_stats != nullptr && handoff_stats->enabled) {
            ++handoff_stats->opened_texture_slots;
            handoff_stats->opened_shared_texture = true;
          }
        } else {
          ++stats.shared_texture_open_failures;
          stats.last_error = "host_open_shared_resource_failed";
          if (handoff_stats != nullptr && handoff_stats->enabled) {
            ++handoff_stats->shared_texture_open_failures;
            handoff_stats->last_error =
                "publication_handoff_open_shared_resource_failed";
          }
        }
      }
    }

    const uint64_t frame_index = shared_state->latest_frame_index;
    if (frame_index == 0 || frame_index == last_frame_index) {
      ++stats.duplicate_signals;
      if (handoff_enabled) {
        ++handoff_stats->duplicate_signals;
      }
      process_handoff_if_due();
      continue;
    }
    if (last_frame_index != 0 && frame_index > last_frame_index + 1) {
      stats.missed_frames += frame_index - last_frame_index - 1;
      if (handoff_stats != nullptr && handoff_stats->enabled) {
        handoff_stats->missed_input_frames += frame_index - last_frame_index - 1;
      }
    }
    if (last_frame_qpc != 0 && shared_state->latest_qpc > last_frame_qpc) {
      stats.consume_gap_ms.push_back(
          qpc_to_ms(shared_state->latest_qpc - last_frame_qpc));
    }
    LARGE_INTEGER now{};
    QueryPerformanceCounter(&now);
    if (shared_state->latest_qpc > 0 &&
        static_cast<uint64_t>(now.QuadPart) >= shared_state->latest_qpc) {
      stats.frame_age_ms.push_back(
          qpc_to_ms(static_cast<uint64_t>(now.QuadPart) -
                    shared_state->latest_qpc));
    }

    const uint32_t slot_index = shared_state->latest_slot_index;
    auto it = textures.find(slot_index);
    if (it != textures.end()) {
      ++stats.consumed_frames;
      if (handoff_enabled) {
        ++handoff_stats->input_frames_seen;
        latest_handoff_texture = it->second;
        latest_handoff_frame_index = frame_index;
        latest_handoff_frame_qpc = shared_state->latest_qpc;
      }
      if (stats.proof_readback_count <
          static_cast<uint64_t>(max_proof_frames)) {
        ++stats.proof_readback_count;
        const auto format =
            static_cast<DXGI_FORMAT>(shared_state->backbuffer_format);
        if (SampleTextureLooksVisible(device.Get(), context.Get(),
                                      it->second.Get(), format, &stats)) {
          ++stats.visible_proof_frames;
        }
      }
    }
    process_handoff_if_due();
    last_frame_index = frame_index;
    last_frame_qpc = shared_state->latest_qpc;
  }

  encoder_proof.Finalize(frequency, handoff_stats);
  return stats;
}

void WritePublicationHandoffResult(const fs::path& output_dir,
                                   const PublicationHandoffStats& stats) {
  const auto json_path = output_dir / L"publication-handoff.json";
  const auto summary_path = output_dir / L"publication-handoff.md";
  const double age_avg = Average(stats.frame_age_ms);
  const double age_p95 = Percentile(stats.frame_age_ms, 0.95);
  const double age_max = MaxValue(stats.frame_age_ms);
  const double gap_p50 = Percentile(stats.output_gap_ms, 0.50);
  const double gap_p95 = Percentile(stats.output_gap_ms, 0.95);
  const double gap_max = MaxValue(stats.output_gap_ms);
  const double gap_avg = Average(stats.output_gap_ms);
  const double output_fps = gap_avg > 0.0 ? 1000.0 / gap_avg : 0.0;
  const double readback_avg = Average(stats.readback_ms);
  const double readback_p95 = Percentile(stats.readback_ms, 0.95);
  const double readback_max = MaxValue(stats.readback_ms);
  const double scale_avg = Average(stats.scale_ms);
  const double scale_p95 = Percentile(stats.scale_ms, 0.95);
  const double scale_max = MaxValue(stats.scale_ms);
  const double nv12_convert_avg = Average(stats.nv12_convert_ms);
  const double nv12_convert_p95 = Percentile(stats.nv12_convert_ms, 0.95);
  const double nv12_convert_max = MaxValue(stats.nv12_convert_ms);
  const double nv12_proof_readback_avg =
      Average(stats.nv12_proof_readback_ms);
  const double nv12_proof_readback_p95 =
      Percentile(stats.nv12_proof_readback_ms, 0.95);
  const double nv12_proof_readback_max =
      MaxValue(stats.nv12_proof_readback_ms);
  const double p010_convert_avg = Average(stats.p010_convert_ms);
  const double p010_convert_p95 = Percentile(stats.p010_convert_ms, 0.95);
  const double p010_convert_max = MaxValue(stats.p010_convert_ms);
  const double p010_proof_readback_avg =
      Average(stats.p010_proof_readback_ms);
  const double p010_proof_readback_p95 =
      Percentile(stats.p010_proof_readback_ms, 0.95);
  const double p010_proof_readback_max =
      MaxValue(stats.p010_proof_readback_ms);
  const double encoder_submit_avg = Average(stats.encoder_proof_submit_ms);
  const double encoder_submit_p95 =
      Percentile(stats.encoder_proof_submit_ms, 0.95);
  const double encoder_submit_max = MaxValue(stats.encoder_proof_submit_ms);
  const double encoder_copy_avg = Average(stats.encoder_proof_gpu_copy_ms);
  const double encoder_copy_p95 =
      Percentile(stats.encoder_proof_gpu_copy_ms, 0.95);
  const double encoder_copy_max = MaxValue(stats.encoder_proof_gpu_copy_ms);
  const double total_avg = Average(stats.total_frame_ms);
  const double total_p95 = Percentile(stats.total_frame_ms, 0.95);
  const double total_max = MaxValue(stats.total_frame_ms);

  {
    std::ofstream file(json_path);
    file << "{\n"
         << "  \"schema\": \"intergalactic.gameCapturePublicationHandoff.v1\",\n"
         << "  \"enabled\": " << (stats.enabled ? "true" : "false") << ",\n"
         << "  \"mode\": \"" << JsonEscape(stats.mode) << "\",\n"
         << "  \"scaleMode\": \"" << JsonEscape(stats.scale_mode) << "\",\n"
         << "  \"backendContractVersion\": "
         << stats.backend_contract_version << ",\n"
         << "  \"sourceApi\": \"" << JsonEscape(stats.source_api) << "\",\n"
         << "  \"sourceApiId\": " << stats.source_api_id << ",\n"
         << "  \"sourceFormat\": \"" << JsonEscape(stats.source_format)
         << "\",\n"
         << "  \"sourceFormatId\": " << stats.source_format_id << ",\n"
         << "  \"colorSpace\": \"" << JsonEscape(stats.color_space)
         << "\",\n"
         << "  \"syncKind\": \"" << JsonEscape(stats.sync_kind) << "\",\n"
         << "  \"readyState\": \"" << JsonEscape(stats.ready_state)
         << "\",\n"
         << "  \"failureReason\": \"" << JsonEscape(stats.failure_reason)
         << "\",\n"
         << "  \"outputFormat\": \"" << JsonEscape(stats.output_format)
         << "\",\n"
         << "  \"encoderFormat\": \"" << JsonEscape(stats.encoder_format)
         << "\",\n"
         << "  \"encoderProofMode\": \""
         << JsonEscape(stats.encoder_proof_mode) << "\",\n"
         << "  \"encoderProofCodec\": \""
         << JsonEscape(stats.encoder_proof_codec) << "\",\n"
         << "  \"encoderProofContainer\": \""
         << JsonEscape(stats.encoder_proof_container) << "\",\n"
         << "  \"encoderProofOutputPath\": \""
         << JsonEscape(stats.encoder_proof_output_path) << "\",\n"
         << "  \"readbackMode\": \"" << JsonEscape(stats.readback_mode)
         << "\",\n"
         << "  \"proofOutputDirectory\": \""
         << JsonEscape(stats.proof_output_directory) << "\",\n"
         << "  \"sharedStateAvailable\": "
         << (stats.shared_state_available ? "true" : "false") << ",\n"
         << "  \"d3dDeviceCreated\": "
         << (stats.d3d_device_created ? "true" : "false") << ",\n"
         << "  \"openedSharedTexture\": "
         << (stats.opened_shared_texture ? "true" : "false") << ",\n"
         << "  \"openedTextureSlots\": " << stats.opened_texture_slots
         << ",\n"
         << "  \"sharedTextureOpenFailures\": "
         << stats.shared_texture_open_failures << ",\n"
         << "  \"unsupportedFormat\": "
         << (stats.unsupported_format ? "true" : "false") << ",\n"
         << "  \"requestedMaxWidth\": " << stats.requested_max_width << ",\n"
         << "  \"requestedMaxHeight\": " << stats.requested_max_height << ",\n"
         << "  \"requestedTargetFps\": " << stats.requested_target_fps
         << ",\n"
         << "  \"requestedProofFrames\": " << stats.requested_proof_frames
         << ",\n"
         << "  \"sourceWidth\": " << stats.source_width << ",\n"
         << "  \"sourceHeight\": " << stats.source_height << ",\n"
         << "  \"outputWidth\": " << stats.output_width << ",\n"
         << "  \"outputHeight\": " << stats.output_height << ",\n"
         << "  \"dxgiFormat\": " << stats.dxgi_format << ",\n"
         << "  \"observedFrameSignals\": " << stats.observed_frame_signals
         << ",\n"
         << "  \"inputFramesSeen\": " << stats.input_frames_seen << ",\n"
         << "  \"duplicateSignals\": " << stats.duplicate_signals << ",\n"
         << "  \"missedInputFrames\": " << stats.missed_input_frames
         << ",\n"
         << "  \"pacedDropFrames\": " << stats.paced_drop_frames << ",\n"
         << "  \"readbackFrames\": " << stats.readback_frames << ",\n"
         << "  \"readbackFailures\": " << stats.readback_failures << ",\n"
         << "  \"outputFrames\": " << stats.output_frames << ",\n"
         << "  \"repeatedOutputFrames\": " << stats.repeated_output_frames
         << ",\n"
         << "  \"visibleOutputFrames\": " << stats.visible_output_frames
         << ",\n"
         << "  \"proofOutputFrames\": " << stats.proof_output_frames
         << ",\n"
         << "  \"visibleProofOutputFrames\": "
         << stats.visible_proof_output_frames << ",\n"
         << "  \"proofOutputWriteFailures\": "
         << stats.proof_output_write_failures << ",\n"
         << "  \"proofReadbackSuppressedForEncoder\": "
         << (stats.proof_readback_suppressed_for_encoder ? "true" : "false")
         << ",\n"
         << "  \"nv12TextureCreated\": "
         << (stats.nv12_texture_created ? "true" : "false") << ",\n"
         << "  \"nv12OutputFrames\": " << stats.nv12_output_frames << ",\n"
         << "  \"nv12ConvertFailures\": " << stats.nv12_convert_failures
         << ",\n"
         << "  \"nv12ProofReadbackFrames\": "
         << stats.nv12_proof_readback_frames << ",\n"
         << "  \"nv12VisibleProofFrames\": "
         << stats.nv12_visible_proof_frames << ",\n"
         << "  \"p010TextureCreated\": "
         << (stats.p010_texture_created ? "true" : "false") << ",\n"
         << "  \"p010OutputFrames\": " << stats.p010_output_frames << ",\n"
         << "  \"p010ConvertFailures\": " << stats.p010_convert_failures
         << ",\n"
         << "  \"p010ProofReadbackFrames\": "
         << stats.p010_proof_readback_frames << ",\n"
         << "  \"p010VisibleProofFrames\": "
         << stats.p010_visible_proof_frames << ",\n"
         << "  \"videoProcessorProbeAvailable\": "
         << (stats.video_processor_probe_available ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorBgraInputSupported\": "
         << (stats.video_processor_bgra_input_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorR10InputSupported\": "
         << (stats.video_processor_r10_input_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorNv12OutputSupported\": "
         << (stats.video_processor_nv12_output_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorP010OutputSupported\": "
         << (stats.video_processor_p010_output_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorBgraToNv12Supported\": "
         << (stats.video_processor_bgra_to_nv12_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorR10ToNv12Supported\": "
         << (stats.video_processor_r10_to_nv12_supported ? "true" : "false")
         << ",\n"
         << "  \"videoProcessorR10ToP010Supported\": "
         << (stats.video_processor_r10_to_p010_supported ? "true" : "false")
         << ",\n"
         << "  \"encoderProofEnabled\": "
         << (stats.encoder_proof_enabled ? "true" : "false") << ",\n"
         << "  \"encoderProofInitialized\": "
         << (stats.encoder_proof_initialized ? "true" : "false") << ",\n"
         << "  \"encoderProofFinalized\": "
         << (stats.encoder_proof_finalized ? "true" : "false") << ",\n"
         << "  \"encoderProofHardwareTransformsRequested\": "
         << (stats.encoder_proof_hardware_transforms_requested ? "true"
                                                              : "false")
         << ",\n"
         << "  \"encoderProofFramesSubmitted\": "
         << stats.encoder_proof_frames_submitted << ",\n"
         << "  \"encoderProofWriteFailures\": "
         << stats.encoder_proof_write_failures << ",\n"
         << "  \"encoderProofGpuCopyFrames\": "
         << stats.encoder_proof_gpu_copy_frames << ",\n"
         << "  \"encoderProofOutputBytes\": "
         << stats.encoder_proof_output_bytes << ",\n"
         << "  \"invalidStateReads\": " << stats.invalid_state_reads << ",\n"
         << "  \"frameAgeAvgMs\": " << std::fixed << std::setprecision(3)
         << age_avg << ",\n"
         << "  \"frameAgeP95Ms\": " << age_p95 << ",\n"
         << "  \"frameAgeMaxMs\": " << age_max << ",\n"
         << "  \"outputFps\": " << output_fps << ",\n"
         << "  \"outputGapP50Ms\": " << gap_p50 << ",\n"
         << "  \"outputGapP95Ms\": " << gap_p95 << ",\n"
         << "  \"outputGapMaxMs\": " << gap_max << ",\n"
         << "  \"readbackAvgMs\": " << readback_avg << ",\n"
         << "  \"readbackP95Ms\": " << readback_p95 << ",\n"
         << "  \"readbackMaxMs\": " << readback_max << ",\n"
         << "  \"scaleAvgMs\": " << scale_avg << ",\n"
         << "  \"scaleP95Ms\": " << scale_p95 << ",\n"
         << "  \"scaleMaxMs\": " << scale_max << ",\n"
         << "  \"nv12ConvertAvgMs\": " << nv12_convert_avg << ",\n"
         << "  \"nv12ConvertP95Ms\": " << nv12_convert_p95 << ",\n"
         << "  \"nv12ConvertMaxMs\": " << nv12_convert_max << ",\n"
         << "  \"nv12ProofReadbackAvgMs\": " << nv12_proof_readback_avg
         << ",\n"
         << "  \"nv12ProofReadbackP95Ms\": " << nv12_proof_readback_p95
         << ",\n"
         << "  \"nv12ProofReadbackMaxMs\": " << nv12_proof_readback_max
         << ",\n"
         << "  \"p010ConvertAvgMs\": " << p010_convert_avg << ",\n"
         << "  \"p010ConvertP95Ms\": " << p010_convert_p95 << ",\n"
         << "  \"p010ConvertMaxMs\": " << p010_convert_max << ",\n"
         << "  \"p010ProofReadbackAvgMs\": " << p010_proof_readback_avg
         << ",\n"
         << "  \"p010ProofReadbackP95Ms\": " << p010_proof_readback_p95
         << ",\n"
         << "  \"p010ProofReadbackMaxMs\": " << p010_proof_readback_max
         << ",\n"
         << "  \"encoderProofSubmitAvgMs\": " << encoder_submit_avg << ",\n"
         << "  \"encoderProofSubmitP95Ms\": " << encoder_submit_p95 << ",\n"
         << "  \"encoderProofSubmitMaxMs\": " << encoder_submit_max << ",\n"
         << "  \"encoderProofGpuCopyAvgMs\": " << encoder_copy_avg << ",\n"
         << "  \"encoderProofGpuCopyP95Ms\": " << encoder_copy_p95 << ",\n"
         << "  \"encoderProofGpuCopyMaxMs\": " << encoder_copy_max << ",\n"
         << "  \"encoderProofInitMs\": " << stats.encoder_proof_init_ms
         << ",\n"
         << "  \"encoderProofFinalizeMs\": "
         << stats.encoder_proof_finalize_ms << ",\n"
         << "  \"totalFrameAvgMs\": " << total_avg << ",\n"
         << "  \"totalFrameP95Ms\": " << total_p95 << ",\n"
         << "  \"totalFrameMaxMs\": " << total_max << ",\n"
         << "  \"lastError\": \"" << JsonEscape(stats.last_error) << "\",\n"
         << "  \"encoderProofFirstError\": \""
         << JsonEscape(stats.encoder_proof_first_error) << "\",\n"
         << "  \"encoderProofLastError\": \""
         << JsonEscape(stats.encoder_proof_last_error) << "\"\n"
         << "}\n";
  }

  {
    std::ofstream file(summary_path);
    file << "# Publication Handoff Probe\n\n"
         << "- Enabled: " << (stats.enabled ? "true" : "false") << "\n"
         << "- Mode: " << stats.mode << "\n"
         << "- Scale mode: " << stats.scale_mode << "\n"
         << "- Backend contract: v" << stats.backend_contract_version
         << " api=" << stats.source_api
         << " source_format=" << stats.source_format
         << " color_space=" << stats.color_space
         << " sync=" << stats.sync_kind
         << " ready=" << stats.ready_state
         << " failure=" << stats.failure_reason << "\n"
         << "- Output format: " << stats.output_format << "\n"
         << "- Encoder format: " << stats.encoder_format << "\n"
         << "- Encoder proof: " << stats.encoder_proof_mode
         << " codec=" << stats.encoder_proof_codec
         << " container=" << stats.encoder_proof_container << "\n"
         << "- Encoder proof initialized/finalized/hw requested: "
         << (stats.encoder_proof_initialized ? "true" : "false") << " / "
         << (stats.encoder_proof_finalized ? "true" : "false") << " / "
         << (stats.encoder_proof_hardware_transforms_requested ? "true"
                                                              : "false")
         << "\n"
         << "- Encoder proof frames/failures/output bytes: "
         << stats.encoder_proof_frames_submitted << " / "
         << stats.encoder_proof_write_failures << " / "
         << stats.encoder_proof_output_bytes << "\n"
         << "- Encoder proof GPU copy avg/p95/max: " << encoder_copy_avg
         << " / " << encoder_copy_p95 << " / " << encoder_copy_max
         << " ms\n"
         << "- Encoder proof submit avg/p95/max: " << encoder_submit_avg
         << " / " << encoder_submit_p95 << " / " << encoder_submit_max
         << " ms\n"
         << "- Encoder proof init/finalize: "
         << stats.encoder_proof_init_ms << " / "
         << stats.encoder_proof_finalize_ms << " ms\n"
         << "- Encoder proof output: " << stats.encoder_proof_output_path
         << "\n"
         << "- Readback mode: " << stats.readback_mode << "\n"
         << "- Shared state available: "
         << (stats.shared_state_available ? "true" : "false") << "\n"
         << "- D3D11 device created: "
         << (stats.d3d_device_created ? "true" : "false") << "\n"
         << "- Opened shared texture: "
         << (stats.opened_shared_texture ? "true" : "false") << "\n"
         << "- Opened texture slots: " << stats.opened_texture_slots << "\n"
         << "- Open failures: " << stats.shared_texture_open_failures
         << "\n"
         << "- Requested target: " << stats.requested_max_width << "x"
         << stats.requested_max_height << "@"
         << stats.requested_target_fps << "fps\n"
         << "- Requested proof frames: " << stats.requested_proof_frames
         << "\n"
         << "- Source/output: " << stats.source_width << "x"
         << stats.source_height << " -> " << stats.output_width << "x"
         << stats.output_height << "\n"
         << "- Observed/input/output frames: "
         << stats.observed_frame_signals << " / " << stats.input_frames_seen
         << " / " << stats.output_frames << "\n"
         << "- Repeated output frames: " << stats.repeated_output_frames
         << "\n"
         << "- Output FPS: " << output_fps << "\n"
         << "- Output gaps p50/p95/max: " << gap_p50 << " / " << gap_p95
         << " / " << gap_max << " ms\n"
         << "- Readback avg/p95/max: " << readback_avg << " / "
         << readback_p95 << " / " << readback_max << " ms\n"
         << "- Readback frames/failures: " << stats.readback_frames << " / "
         << stats.readback_failures << "\n"
         << "- Scale avg/p95/max: " << scale_avg << " / " << scale_p95
         << " / " << scale_max << " ms\n"
         << "- Total frame avg/p95/max: " << total_avg << " / "
         << total_p95 << " / " << total_max << " ms\n"
         << "- Visible output frames: " << stats.visible_output_frames
         << "\n"
         << "- Proof output frames/visible/write failures: "
         << stats.proof_output_frames << " / "
         << stats.visible_proof_output_frames << " / "
         << stats.proof_output_write_failures << "\n"
         << "- Proof readback suppressed for encoder: "
         << (stats.proof_readback_suppressed_for_encoder ? "true" : "false")
         << "\n"
         << "- NV12 texture/output/convert failures: "
         << (stats.nv12_texture_created ? "true" : "false") << " / "
         << stats.nv12_output_frames << " / "
         << stats.nv12_convert_failures << "\n"
         << "- P010 texture/output/convert failures: "
         << (stats.p010_texture_created ? "true" : "false") << " / "
         << stats.p010_output_frames << " / "
         << stats.p010_convert_failures << "\n"
         << "- Video processor probe available: "
         << (stats.video_processor_probe_available ? "true" : "false")
         << "\n"
         << "- Video processor BGRA/R10 input support: "
         << (stats.video_processor_bgra_input_supported ? "true" : "false")
         << " / "
         << (stats.video_processor_r10_input_supported ? "true" : "false")
         << "\n"
         << "- Video processor NV12/P010 output support: "
         << (stats.video_processor_nv12_output_supported ? "true" : "false")
         << " / "
         << (stats.video_processor_p010_output_supported ? "true" : "false")
         << "\n"
         << "- Video processor BGRA->NV12 / R10->NV12 / R10->P010: "
         << (stats.video_processor_bgra_to_nv12_supported ? "true" : "false")
         << " / "
         << (stats.video_processor_r10_to_nv12_supported ? "true" : "false")
         << " / "
         << (stats.video_processor_r10_to_p010_supported ? "true" : "false")
         << "\n"
         << "- NV12 convert avg/p95/max: " << nv12_convert_avg << " / "
         << nv12_convert_p95 << " / " << nv12_convert_max << " ms\n"
         << "- NV12 proof readbacks/visible: "
         << stats.nv12_proof_readback_frames << " / "
         << stats.nv12_visible_proof_frames << "\n"
         << "- NV12 proof readback avg/p95/max: "
         << nv12_proof_readback_avg << " / " << nv12_proof_readback_p95
         << " / " << nv12_proof_readback_max << " ms\n"
         << "- P010 convert avg/p95/max: " << p010_convert_avg << " / "
         << p010_convert_p95 << " / " << p010_convert_max << " ms\n"
         << "- P010 proof readbacks/visible: "
         << stats.p010_proof_readback_frames << " / "
         << stats.p010_visible_proof_frames << "\n"
         << "- P010 proof readback avg/p95/max: "
         << p010_proof_readback_avg << " / " << p010_proof_readback_p95
         << " / " << p010_proof_readback_max << " ms\n"
         << "- Proof output directory: " << stats.proof_output_directory
         << "\n"
         << "- Paced drops: " << stats.paced_drop_frames << "\n"
         << "- Last error: " << stats.last_error << "\n"
         << "- Encoder proof first error: "
         << stats.encoder_proof_first_error << "\n"
         << "- Encoder proof last error: "
         << stats.encoder_proof_last_error << "\n";
  }
}

void WriteHostConsumerResult(const fs::path& output_dir,
                             const HostConsumerStats& stats) {
  const auto json_path = output_dir / L"host-consumer.json";
  const auto summary_path = output_dir / L"host-consumer.md";
  const double age_avg = Average(stats.frame_age_ms);
  const double age_p95 = Percentile(stats.frame_age_ms, 0.95);
  const double age_max = MaxValue(stats.frame_age_ms);
  const double gap_p50 = Percentile(stats.consume_gap_ms, 0.50);
  const double gap_p95 = Percentile(stats.consume_gap_ms, 0.95);
  const double gap_max = MaxValue(stats.consume_gap_ms);
  const double proof_avg = Average(stats.proof_readback_ms);
  const double proof_max = MaxValue(stats.proof_readback_ms);

  {
    std::ofstream file(json_path);
    file << "{\n"
         << "  \"schema\": \"intergalactic.gameCaptureHostConsumer.v1\",\n"
         << "  \"enabled\": " << (stats.enabled ? "true" : "false") << ",\n"
         << "  \"backendContractVersion\": "
         << stats.backend_contract_version << ",\n"
         << "  \"sourceApi\": \"" << JsonEscape(stats.source_api) << "\",\n"
         << "  \"sourceApiId\": " << stats.source_api_id << ",\n"
         << "  \"sourceFormat\": \"" << JsonEscape(stats.source_format)
         << "\",\n"
         << "  \"sourceFormatId\": " << stats.source_format_id << ",\n"
         << "  \"colorSpace\": \"" << JsonEscape(stats.color_space)
         << "\",\n"
         << "  \"syncKind\": \"" << JsonEscape(stats.sync_kind) << "\",\n"
         << "  \"readyState\": \"" << JsonEscape(stats.ready_state)
         << "\",\n"
         << "  \"failureReason\": \"" << JsonEscape(stats.failure_reason)
         << "\",\n"
         << "  \"sharedStateAvailable\": "
         << (stats.shared_state_available ? "true" : "false") << ",\n"
         << "  \"d3dDeviceCreated\": "
         << (stats.d3d_device_created ? "true" : "false") << ",\n"
         << "  \"openedSharedTexture\": "
         << (stats.opened_shared_texture ? "true" : "false") << ",\n"
         << "  \"openedTextureSlots\": " << stats.opened_texture_slots
         << ",\n"
         << "  \"sharedTextureOpenFailures\": "
         << stats.shared_texture_open_failures << ",\n"
         << "  \"observedFrameSignals\": " << stats.observed_frame_signals
         << ",\n"
         << "  \"consumedFrames\": " << stats.consumed_frames << ",\n"
         << "  \"duplicateSignals\": " << stats.duplicate_signals << ",\n"
         << "  \"missedFrames\": " << stats.missed_frames << ",\n"
         << "  \"invalidStateReads\": " << stats.invalid_state_reads << ",\n"
         << "  \"frameAgeAvgMs\": " << std::fixed << std::setprecision(3)
         << age_avg << ",\n"
         << "  \"frameAgeP95Ms\": " << age_p95 << ",\n"
         << "  \"frameAgeMaxMs\": " << age_max << ",\n"
         << "  \"consumerGapP50Ms\": " << gap_p50 << ",\n"
         << "  \"consumerGapP95Ms\": " << gap_p95 << ",\n"
         << "  \"consumerGapMaxMs\": " << gap_max << ",\n"
         << "  \"proofReadbackCount\": " << stats.proof_readback_count
         << ",\n"
         << "  \"visibleProofFrames\": " << stats.visible_proof_frames
         << ",\n"
         << "  \"proofReadbackAvgMs\": " << proof_avg << ",\n"
         << "  \"proofReadbackMaxMs\": " << proof_max << ",\n"
         << "  \"lastError\": \"" << JsonEscape(stats.last_error) << "\"\n"
         << "}\n";
  }

  {
    std::ofstream file(summary_path);
    file << "# Host Shared Texture Consumer\n\n"
         << "- Enabled: " << (stats.enabled ? "true" : "false") << "\n"
         << "- Backend contract: v" << stats.backend_contract_version
         << " api=" << stats.source_api
         << " source_format=" << stats.source_format
         << " color_space=" << stats.color_space
         << " sync=" << stats.sync_kind
         << " ready=" << stats.ready_state
         << " failure=" << stats.failure_reason << "\n"
         << "- Shared state available: "
         << (stats.shared_state_available ? "true" : "false") << "\n"
         << "- D3D11 device created: "
         << (stats.d3d_device_created ? "true" : "false") << "\n"
         << "- Opened shared texture: "
         << (stats.opened_shared_texture ? "true" : "false") << "\n"
         << "- Opened texture slots: " << stats.opened_texture_slots << "\n"
         << "- Open failures: " << stats.shared_texture_open_failures
         << "\n"
         << "- Observed/consumed frames: " << stats.observed_frame_signals
         << " / " << stats.consumed_frames << "\n"
         << "- Duplicate signals: " << stats.duplicate_signals << "\n"
         << "- Missed frames: " << stats.missed_frames << "\n"
         << "- Frame age avg/p95/max: " << age_avg << " / " << age_p95
         << " / " << age_max << " ms\n"
         << "- Consumer gaps p50/p95/max: " << gap_p50 << " / " << gap_p95
         << " / " << gap_max << " ms\n"
         << "- Proof readbacks/visible: " << stats.proof_readback_count
         << " / " << stats.visible_proof_frames << "\n"
         << "- Proof readback avg/max: " << proof_avg << " / " << proof_max
         << " ms\n"
         << "- Last error: " << stats.last_error << "\n";
  }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  const Options options = ParseOptions(argc, argv);
  const std::string session_id =
      options.session_id.empty() ? RandomHex(6) : options.session_id;
  const fs::path output_dir =
      options.output_root / Utf8ToWide(TimestampForPath() + "-" + session_id);
  const fs::path helper_log = output_dir / L"helper.log";
  const std::string pid_hash = PidHash(options.pid, session_id);

  EnsureDirectories(output_dir);
  AppendLog(helper_log, "helper_start session=" + session_id);

  if (options.pid == 0) {
    WriteFailureResult(output_dir, session_id, "none",
                       iggc::AttachStatus::kNoTargetPid, "no_target_pid",
                       "unknown");
    return 2;
  }

  if (!fs::exists(options.hook_dll)) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kInjectFailed,
                       "hook_dll_missing", "unknown");
    AppendLog(helper_log, "hook_dll_missing path=" +
                              WideToUtf8(options.hook_dll.wstring()));
    return 3;
  }

  HANDLE query_process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, options.pid);
  if (query_process == nullptr) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kBlockedByProcessSecurity,
                       "query_open_failed:" + LastErrorString(), "unknown");
    return 4;
  }

  std::string architecture = "unknown";
  const bool is_x64 = IsTarget64Bit(query_process, &architecture);
  const DWORD target_integrity = IntegrityRid(query_process);
  CloseHandle(query_process);

  if (!is_x64) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kUnsupportedArchitecture,
                       "target_is_not_x64", architecture);
    return 5;
  }

  HANDLE self_process = GetCurrentProcess();
  const DWORD self_integrity = IntegrityRid(self_process);
  if (target_integrity != 0 && self_integrity != 0 &&
      target_integrity > self_integrity) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kBlockedByProcessSecurity,
                       "target_integrity_higher_than_helper", architecture);
    return 6;
  }

  HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                                   PROCESS_VM_OPERATION | PROCESS_VM_WRITE |
                                   PROCESS_VM_READ,
                               FALSE, options.pid);
  if (process == nullptr) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kBlockedByProcessSecurity,
                       "inject_open_failed:" + LastErrorString(),
                       architecture);
    return 7;
  }

  const std::wstring session_wide = Utf8ToWide(session_id);
  const std::wstring stop_event_name =
      L"Local\\InterGalacticGameCapture." + session_wide + L".stop";
  const std::wstring stopped_event_name =
      L"Local\\InterGalacticGameCapture." + session_wide + L".stopped";
  const std::wstring frame_event_name =
      L"Local\\InterGalacticGameCapture." + session_wide + L".frame";
  const std::wstring shared_state_name =
      L"Local\\InterGalacticGameCapture." + session_wide + L".sharedState";
  HANDLE stop_event =
      CreateEventW(nullptr, TRUE, FALSE, stop_event_name.c_str());
  HANDLE stopped_event =
      CreateEventW(nullptr, TRUE, FALSE, stopped_event_name.c_str());
  HANDLE frame_event =
      CreateEventW(nullptr, FALSE, FALSE, frame_event_name.c_str());
  HANDLE shared_state_mapping =
      CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                         sizeof(iggc::SharedTextureState),
                         shared_state_name.c_str());
  auto* shared_state = reinterpret_cast<iggc::SharedTextureState*>(
      shared_state_mapping == nullptr
          ? nullptr
          : MapViewOfFile(shared_state_mapping, FILE_MAP_ALL_ACCESS, 0, 0,
                          sizeof(iggc::SharedTextureState)));
  if (shared_state != nullptr) {
    *shared_state = iggc::SharedTextureState{};
  }

  PublicationHandoffStats publication_handoff_stats;
  publication_handoff_stats.enabled = options.publication_handoff;
  publication_handoff_stats.requested_max_width =
      options.publication_handoff_max_width;
  publication_handoff_stats.requested_max_height =
      options.publication_handoff_max_height;
  publication_handoff_stats.requested_target_fps =
      options.publication_handoff_target_fps;
  const bool shared_texture_required = options.host_consume_frames ||
                                       options.publication_handoff ||
                                       options.external_consumer;

  const fs::path config_path =
      options.hook_dll.parent_path() /
      Utf8ToWide("intergalactic_game_capture_" + std::to_string(options.pid) +
                 ".cfg");
  if (!WriteHookConfig(config_path, session_id, output_dir, options.duration_ms,
                       options.max_saved_frames, options.hook_target_fps,
                       shared_texture_required, stop_event_name,
                       stopped_event_name, frame_event_name,
                       shared_state_name)) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kInjectFailed,
                       "config_write_failed", architecture);
    if (shared_state != nullptr) {
      UnmapViewOfFile(shared_state);
    }
    if (shared_state_mapping != nullptr) {
      CloseHandle(shared_state_mapping);
    }
    CloseHandle(frame_event);
    CloseHandle(stop_event);
    CloseHandle(stopped_event);
    CloseHandle(process);
    return 8;
  }

  AppendLog(helper_log,
            "inject_begin pidHash=" + pid_hash + " durationMs=" +
                std::to_string(options.duration_ms) +
                " maxSavedFrames=" +
                std::to_string(options.max_saved_frames) +
                " hostConsumeFrames=" +
                (options.host_consume_frames ? "true" : "false") +
                " hostProofFrames=" +
                std::to_string(options.host_proof_frames) +
                " externalConsumer=" +
                (options.external_consumer ? "true" : "false") +
                " hookTargetFps=" +
                std::to_string(options.hook_target_fps) +
                " publicationHandoff=" +
                (options.publication_handoff ? "true" : "false") +
                " publicationTarget=" +
                std::to_string(options.publication_handoff_max_width) + "x" +
                std::to_string(options.publication_handoff_max_height) + "@" +
                std::to_string(options.publication_handoff_target_fps) +
                " publicationProofFrames=" +
                std::to_string(options.publication_handoff_proof_frames) +
                " publicationReadbackMode=" +
                options.publication_handoff_readback_mode +
                " publicationOutputFormat=" +
                options.publication_handoff_output_format +
                " publicationEncoderProof=" +
                options.publication_encoder_proof +
                " hookDll=" +
                WideToUtf8(options.hook_dll.wstring()));

  auto cleanup_before_inject = [&]() {
    if (shared_state != nullptr) {
      UnmapViewOfFile(shared_state);
    }
    if (shared_state_mapping != nullptr) {
      CloseHandle(shared_state_mapping);
    }
    CloseHandle(frame_event);
    CloseHandle(stop_event);
    CloseHandle(stopped_event);
    CloseHandle(process);
    DeleteFileW(config_path.c_str());
  };

  std::string stale_cleanup_error;
  for (int attempt = 0; attempt < 3; ++attempt) {
    HMODULE stale_module = FindRemoteModule(options.pid, options.hook_dll);
    if (stale_module == nullptr) {
      break;
    }
    AppendLog(helper_log,
              "stale_hook_module_cleanup attempt=" + std::to_string(attempt + 1));
    const RemoteFreeLibraryStatus unload_status =
        RemoteFreeLibrary(process, stale_module);
    const bool module_gone =
        WaitForRemoteModuleGone(options.pid, options.hook_dll);
    AppendLog(helper_log,
              "stale_hook_module_cleanup_result " +
                  RemoteFreeLibraryStatusText(unload_status) +
                  " moduleGone=" + BoolText(module_gone));
    if (module_gone) {
      break;
    }
    stale_cleanup_error =
        "stale_hook_unload_failed:" +
        RemoteFreeLibraryStatusText(unload_status);
    Sleep(250);
  }

  if (FindRemoteModule(options.pid, options.hook_dll) != nullptr) {
    if (stale_cleanup_error.empty()) {
      stale_cleanup_error = "stale_hook_still_loaded_after_cleanup";
    }
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kInjectFailed,
                       stale_cleanup_error, architecture);
    AppendLog(helper_log, "inject_failed " + stale_cleanup_error);
    cleanup_before_inject();
    return 11;
  }

  HMODULE remote_module = nullptr;
  std::string inject_error;
  if (!InjectLoadLibrary(process, options.hook_dll, &inject_error)) {
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kInjectFailed, inject_error,
                       architecture);
    AppendLog(helper_log, "inject_failed " + inject_error);
    cleanup_before_inject();
    return 9;
  }

  remote_module = FindRemoteModule(options.pid, options.hook_dll);
  if (remote_module == nullptr) {
    const std::string reason =
        inject_error.empty() ? "remote_module_missing_after_inject"
                             : inject_error;
    WriteFailureResult(output_dir, session_id, pid_hash,
                       iggc::AttachStatus::kInjectFailed, reason,
                       architecture);
    AppendLog(helper_log, "inject_failed " + reason);
    cleanup_before_inject();
    return 10;
  }

  AppendLog(helper_log, "inject_loaded remoteModule=found");

  std::atomic<bool> host_consumer_stop = false;
  HostConsumerStats host_consumer_stats;
  std::thread host_consumer_thread;
  if (shared_texture_required && !options.external_consumer) {
    host_consumer_thread = std::thread([&]() {
      host_consumer_stats =
          RunHostConsumer(frame_event, shared_state, &host_consumer_stop,
                          options.host_proof_frames, output_dir,
                          options.publication_handoff_proof_frames,
                          options.publication_handoff_readback_mode,
                          options.publication_handoff_output_format,
                          options.publication_encoder_proof,
                          options.publication_handoff
                              ? &publication_handoff_stats
                              : nullptr);
    });
  }

  const DWORD wait_ms = static_cast<DWORD>(options.duration_ms + 5000);
  const DWORD wait_result = WaitForSingleObject(stopped_event, wait_ms);
  AppendLog(helper_log,
            "hook_wait_complete result=" + std::to_string(wait_result));
  if (wait_result == WAIT_TIMEOUT) {
    AppendLog(helper_log, "stop_timeout_signal");
    SetEvent(stop_event);
    WaitForSingleObject(stopped_event, 5000);
  }

  AppendLog(helper_log, "host_consumer_stop_begin");
  host_consumer_stop = true;
  if (frame_event != nullptr) {
    SetEvent(frame_event);
  }
  if (host_consumer_thread.joinable()) {
    AppendLog(helper_log, "host_consumer_join_begin");
    host_consumer_thread.join();
    AppendLog(helper_log, "host_consumer_join_done");
  } else {
    host_consumer_stats.enabled = options.host_consume_frames;
  }
  AppendLog(helper_log, "write_host_consumer_begin");
  WriteHostConsumerResult(output_dir, host_consumer_stats);
  AppendLog(helper_log, "write_host_consumer_done");
  AppendLog(helper_log, "write_publication_handoff_begin");
  WritePublicationHandoffResult(output_dir, publication_handoff_stats);
  AppendLog(helper_log, "write_publication_handoff_done");

  AppendLog(helper_log, "free_library_begin");
  const RemoteFreeLibraryStatus unload_status =
      RemoteFreeLibrary(process, remote_module);
  const bool module_gone =
      WaitForRemoteModuleGone(options.pid, options.hook_dll);
  AppendLog(helper_log,
            "free_library_done " + RemoteFreeLibraryStatusText(unload_status) +
                " moduleGone=" + BoolText(module_gone));

  DeleteFileW(config_path.c_str());
  if (shared_state != nullptr) {
    UnmapViewOfFile(shared_state);
  }
  if (shared_state_mapping != nullptr) {
    CloseHandle(shared_state_mapping);
  }
  CloseHandle(frame_event);
  CloseHandle(stop_event);
  CloseHandle(stopped_event);
  CloseHandle(process);

  AppendLog(helper_log, "helper_stop output=" + WideToUtf8(output_dir.wstring()));
  std::wcout << L"Inter Galactic game-capture POC output: "
             << output_dir.wstring() << L"\n";
  return 0;
}
