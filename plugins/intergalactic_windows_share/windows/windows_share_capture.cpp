#include "windows_share_capture.h"

#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <propidl.h>

// Must come after mmdeviceapi.h, which supplies DEFINE_PROPERTYKEY. This header
// includes nothing itself and uses that macro directly, so sorting it up with
// the rest of the block breaks the build with a wall of C2065/C2086 errors
// pointing inside the SDK. Keep it separate.
#include <functiondiscoverykeys_devpkey.h>

#include <algorithm>
#include <cctype>
#include <cwchar>
#include <iomanip>
#include <sstream>
#include <utility>

#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"

#define protected public
#include "flutter_webrtc.h"
#undef protected

#include "rtc_audio_source.h"
#include "rtc_audio_track.h"
#include "rtc_media_stream.h"

namespace intergalactic_windows_share {
namespace {

// Microsoft documents process loopback as requiring build 20348. That number is
// reported for diagnostics only and must NOT gate behaviour: the API activates
// on a number of earlier Windows 10 servicing builds (19045 among them), and it
// can equally fail on builds well past the documented minimum. Support is
// decided by ProbeProcessLoopbackActivation(), which performs a real
// activation.
constexpr DWORD kDocumentedProcessLoopbackBuild = 20348;
constexpr DWORD kMinimumWgcBuild = 18362;
constexpr int kBitsPerByte = 8;
constexpr char kSharedAudioLabel[] = "Windows shared audio";
constexpr char kSharedAudioDeviceId[] = "windows-shared-audio";

// Upper bound on how long we wait for ActivateAudioInterfaceAsync to call back.
// The callback is normally immediate; a bounded wait keeps a wedged audio
// service from hanging the capture thread (or the probe) forever.
constexpr DWORD kActivationTimeoutMs = 3000;

std::string UnsupportedSharedAudioStreamJson(int session_id,
                                             const std::string& reason) {
  std::ostringstream json;
  json << "{";
  json << "\"sessionId\":" << session_id << ",";
  json << "\"supported\":false,";
  json << "\"streamId\":\"\",";
  json << "\"trackId\":\"\",";
  json << "\"sampleRateHz\":0,";
  json << "\"numChannels\":0,";
  json << "\"bitsPerSample\":0,";
  json << "\"audioTracks\":[],";
  json << "\"videoTracks\":[],";
  json << "\"reason\":\"" << EscapeJson(reason) << "\"";
  json << "}";
  return json.str();
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }

  const int input_length = static_cast<int>(value.size());
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), input_length,
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return "";
  }

  std::string result(static_cast<size_t>(size), '\0');
  const int written = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                          input_length, result.data(), size,
                                          nullptr, nullptr);
  if (written <= 0) {
    return "";
  }
  return result;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }

  const int input_length = static_cast<int>(value.size());
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), input_length,
                                       nullptr, 0);
  if (size <= 0) {
    return L"";
  }

  std::wstring result(static_cast<size_t>(size), L'\0');
  const int written = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                          input_length, result.data(), size);
  if (written <= 0) {
    return L"";
  }
  return result;
}

std::string GenerateLocalId() {
  GUID guid = {};
  if (FAILED(CoCreateGuid(&guid))) {
    static std::atomic<unsigned long long> fallback_id{0};
    std::ostringstream fallback;
    fallback << "windows-shared-audio-" << fallback_id.fetch_add(1);
    return fallback.str();
  }

  std::wstringstream stream;
  stream << std::hex << std::setfill(L'0') << std::setw(8) << guid.Data1
         << L"-" << std::setw(4) << guid.Data2 << L"-" << std::setw(4)
         << guid.Data3 << L"-";
  for (int i = 0; i < 2; ++i) {
    stream << std::setw(2) << static_cast<int>(guid.Data4[i]);
  }
  stream << L"-";
  for (int i = 2; i < 8; ++i) {
    stream << std::setw(2) << static_cast<int>(guid.Data4[i]);
  }

  return WideToUtf8(stream.str());
}

DWORD GetWindowsBuildNumber() {
  using RtlGetVersionPtr = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return 0;
  }

  auto rtl_get_version = reinterpret_cast<RtlGetVersionPtr>(
      GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return 0;
  }

  RTL_OSVERSIONINFOW version = {};
  version.dwOSVersionInfoSize = sizeof(version);
  if (rtl_get_version(&version) != 0) {
    return 0;
  }

  return version.dwBuildNumber;
}

std::string HResultToString(HRESULT hr) {
  std::ostringstream stream;
  stream << "0x" << std::hex << static_cast<unsigned long>(hr);
  return stream.str();
}

template <typename T>
void SafeRelease(T** value) {
  if (value != nullptr && *value != nullptr) {
    (*value)->Release();
    *value = nullptr;
  }
}

class AudioActivationHandler
    : public IActivateAudioInterfaceCompletionHandler,
      public IAgileObject {
 public:
  AudioActivationHandler() : completed_event_(CreateEventW(nullptr, FALSE, FALSE, nullptr)) {}

  ~AudioActivationHandler() {
    SafeRelease(&audio_client_);
    if (completed_event_ != nullptr) {
      CloseHandle(completed_event_);
      completed_event_ = nullptr;
    }
  }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IActivateAudioInterfaceCompletionHandler)) {
      *object = static_cast<IActivateAudioInterfaceCompletionHandler*>(this);
    } else if (riid == __uuidof(IAgileObject)) {
      *object = static_cast<IAgileObject*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }

    AddRef();
    return S_OK;
  }

  IFACEMETHODIMP_(ULONG) AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
  }

  IFACEMETHODIMP_(ULONG) Release() override {
    ULONG count = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
    if (count == 0) {
      delete this;
    }
    return count;
  }

  IFACEMETHODIMP ActivateCompleted(
      IActivateAudioInterfaceAsyncOperation* operation) override {
    HRESULT activate_result = E_UNEXPECTED;
    IUnknown* audio_interface = nullptr;
    result_ = operation->GetActivateResult(&activate_result, &audio_interface);

    if (SUCCEEDED(result_)) {
      result_ = activate_result;
    }

    if (SUCCEEDED(result_) && audio_interface != nullptr) {
      result_ = audio_interface->QueryInterface(IID_PPV_ARGS(&audio_client_));
    }

    SafeRelease(&audio_interface);
    SetEvent(completed_event_);
    return S_OK;
  }

  HANDLE completed_event() const { return completed_event_; }
  HRESULT result() const { return result_; }

  IAudioClient* DetachAudioClient() {
    IAudioClient* result = audio_client_;
    audio_client_ = nullptr;
    return result;
  }

 private:
  volatile LONG ref_count_ = 1;
  HANDLE completed_event_ = nullptr;
  HRESULT result_ = E_UNEXPECTED;
  IAudioClient* audio_client_ = nullptr;
};

// Shared by the real capture path and by the capability probe, so that what we
// advertise as supported is exactly what we later attempt.
HRESULT ActivateProcessLoopbackClient(SharedAudioMode mode,
                                      DWORD process_id,
                                      IAudioClient** audio_client,
                                      SharedAudioFailureStage* stage) {
  *stage = SharedAudioFailureStage::kActivation;
  if (audio_client == nullptr) {
    return E_POINTER;
  }

  AUDIOCLIENT_ACTIVATION_PARAMS activation_params = {};
  activation_params.ActivationType =
      AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  activation_params.ProcessLoopbackParams.ProcessLoopbackMode =
      mode == SharedAudioMode::kProcessTreeLoopback
          ? PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE
          : PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;
  activation_params.ProcessLoopbackParams.TargetProcessId =
      mode == SharedAudioMode::kSystemLoopback ? GetCurrentProcessId()
                                               : process_id;

  PROPVARIANT prop_variant = {};
  prop_variant.vt = VT_BLOB;
  prop_variant.blob.cbSize = sizeof(activation_params);
  prop_variant.blob.pBlobData = reinterpret_cast<BYTE*>(&activation_params);

  auto* handler = new AudioActivationHandler();
  if (handler->completed_event() == nullptr) {
    handler->Release();
    *stage = SharedAudioFailureStage::kEventHandle;
    return HRESULT_FROM_WIN32(GetLastError());
  }

  IActivateAudioInterfaceAsyncOperation* operation = nullptr;
  HRESULT hr = ActivateAudioInterfaceAsync(
      VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
      &prop_variant, handler, &operation);
  if (SUCCEEDED(hr)) {
    const DWORD wait =
        WaitForSingleObject(handler->completed_event(), kActivationTimeoutMs);
    if (wait == WAIT_OBJECT_0) {
      hr = handler->result();
      if (SUCCEEDED(hr)) {
        *audio_client = handler->DetachAudioClient();
        *stage = SharedAudioFailureStage::kNone;
      }
    } else {
      // The handler holds a reference until the callback fires, so releasing
      // our reference here is safe even though the operation is outstanding.
      hr = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
      *stage = SharedAudioFailureStage::kActivationTimeout;
    }
  }

  SafeRelease(&operation);
  handler->Release();
  return hr;
}

std::string ToLowerAscii(const std::string& value) {
  std::string lowered;
  lowered.reserve(value.size());
  for (const unsigned char ch : value) {
    lowered += static_cast<char>(std::tolower(ch));
  }
  return lowered;
}

BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lparam) {
  if (!IsWindowVisible(hwnd)) {
    return TRUE;
  }

  const int title_length = GetWindowTextLengthW(hwnd);
  if (title_length <= 0) {
    return TRUE;
  }

  std::wstring title(static_cast<size_t>(title_length + 1), L'\0');
  GetWindowTextW(hwnd, title.data(), title_length + 1);
  title.resize(static_cast<size_t>(wcslen(title.c_str())));

  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) {
    return TRUE;
  }

  auto* results = reinterpret_cast<std::vector<WindowTargetInfo>*>(lparam);
  results->push_back(WindowTargetInfo{
      hwnd,
      process_id,
      WideToUtf8(title),
  });
  return TRUE;
}

// Returns the integrity-level RID (e.g. SECURITY_MANDATORY_MEDIUM_RID) for the
// given token, or 0 if it could not be read.
DWORD GetTokenIntegrityRid(HANDLE token) {
  DWORD size = 0;
  GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
  if (size == 0) {
    return 0;
  }

  std::vector<BYTE> buffer(size);
  if (!GetTokenInformation(token, TokenIntegrityLevel, buffer.data(), size,
                           &size)) {
    return 0;
  }

  auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buffer.data());
  if (label->Label.Sid == nullptr) {
    return 0;
  }

  const UCHAR* sub_authority_count =
      GetSidSubAuthorityCount(label->Label.Sid);
  if (sub_authority_count == nullptr || *sub_authority_count == 0) {
    return 0;
  }

  const DWORD* rid =
      GetSidSubAuthority(label->Label.Sid, *sub_authority_count - 1);
  return rid == nullptr ? 0 : *rid;
}

DWORD GetProcessIntegrityRid(HANDLE process, bool* ok) {
  *ok = false;
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) {
    return 0;
  }

  const DWORD rid = GetTokenIntegrityRid(token);
  CloseHandle(token);
  if (rid == 0) {
    return 0;
  }

  *ok = true;
  return rid;
}

// Best-effort determination of whether `process_id` runs at a strictly higher
// integrity level than this process (an elevated / anti-cheat-protected game).
// Windows process-loopback cannot capture audio across that boundary, so a
// capture against such a target delivers only silence. `*determined` is set
// when we could positively establish the relationship; when we could not, the
// caller should fall back to observing whether real (non-silent) audio arrives.
bool DetectTargetElevatedRelativeToSelf(DWORD process_id, bool* determined) {
  *determined = false;
  if (process_id == 0 || process_id == GetCurrentProcessId()) {
    *determined = true;
    return false;
  }

  bool self_ok = false;
  const DWORD self_rid = GetProcessIntegrityRid(GetCurrentProcess(), &self_ok);

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    // Being denied even limited-query access is a strong signal the target is
    // elevated or a protected process, which the loopback cannot hear.
    if (GetLastError() == ERROR_ACCESS_DENIED) {
      *determined = true;
      return true;
    }
    return false;
  }

  bool target_ok = false;
  const DWORD target_rid = GetProcessIntegrityRid(process, &target_ok);
  const DWORD open_token_error = GetLastError();
  CloseHandle(process);

  if (self_ok && target_ok) {
    *determined = true;
    return target_rid > self_rid;
  }

  if (!target_ok && open_token_error == ERROR_ACCESS_DENIED) {
    *determined = true;
    return true;
  }

  return false;
}

}  // namespace

struct PcmBridge {
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> source;
  libwebrtc::scoped_refptr<libwebrtc::RTCMediaStream> stream;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track;
  std::string stream_id;
  std::string track_id;
};

std::string EscapeJson(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size());

  for (const char ch : value) {
    switch (ch) {
      case '\\':
        escaped += "\\\\";
        break;
      case '"':
        escaped += "\\\"";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        escaped += ch;
        break;
    }
  }

  return escaped;
}

const char* ToJsonString(ShareTargetType type) {
  switch (type) {
    case ShareTargetType::kWindow:
      return "window";
    case ShareTargetType::kDisplay:
    default:
      return "display";
  }
}

const char* ToJsonString(SharedAudioMode mode) {
  switch (mode) {
    case SharedAudioMode::kNone:
      return "none";
    case SharedAudioMode::kProcessTreeLoopback:
      return "processTreeLoopback";
    case SharedAudioMode::kSystemLoopback:
      return "systemLoopback";
    case SharedAudioMode::kEndpointLoopback:
      return "endpointLoopback";
    case SharedAudioMode::kDeviceCapture:
      return "deviceCapture";
    case SharedAudioMode::kUnavailable:
    default:
      return "unavailable";
  }
}

const char* ToJsonString(SharedAudioFailureStage stage) {
  switch (stage) {
    case SharedAudioFailureStage::kComInitialization:
      return "comInitialization";
    case SharedAudioFailureStage::kActivation:
      return "activation";
    case SharedAudioFailureStage::kClientInitialize:
      return "clientInitialize";
    case SharedAudioFailureStage::kServiceAcquire:
      return "serviceAcquire";
    case SharedAudioFailureStage::kEventHandle:
      return "eventHandle";
    case SharedAudioFailureStage::kStart:
      return "start";
    case SharedAudioFailureStage::kCapture:
      return "capture";
    case SharedAudioFailureStage::kDeviceEnumeration:
      return "deviceEnumeration";
    case SharedAudioFailureStage::kDeviceNotFound:
      return "deviceNotFound";
    case SharedAudioFailureStage::kActivationTimeout:
      return "activationTimeout";
    case SharedAudioFailureStage::kNone:
    default:
      return "none";
  }
}

bool IsLikelyVirtualDeviceName(const std::string& name,
                               std::string* family_out) {
  const std::string lowered = ToLowerAscii(name);
  const auto contains = [&lowered](const char* needle) {
    return lowered.find(needle) != std::string::npos;
  };

  // Ordered most specific first: VoiceMeeter's own endpoints are also branded
  // "VB-Audio", so it has to win the VB-CABLE check.
  struct Pattern {
    const char* needle;
    const char* family;
  };
  static constexpr Pattern kPatterns[] = {
      {"voicemeeter", "voicemeeter"},
      {"vb-audio", "vb-cable"},
      {"vb audio", "vb-cable"},
      {"cable output", "vb-cable"},
      {"cable input", "vb-cable"},
      {"virtual audio cable", "vac"},
      {"virtual cable", "vac"},
  };

  for (const auto& pattern : kPatterns) {
    if (contains(pattern.needle)) {
      if (family_out != nullptr) {
        *family_out = pattern.family;
      }
      return true;
    }
  }

  if (family_out != nullptr) {
    family_out->clear();
  }
  return false;
}

SharedAudioProbeResult ProbeProcessLoopbackActivation(bool force) {
  static std::mutex probe_mutex;
  static bool probed = false;
  static SharedAudioProbeResult cached;

  std::lock_guard<std::mutex> lock(probe_mutex);
  if (probed && !force) {
    return cached;
  }

  HRESULT co_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool co_initialized = SUCCEEDED(co_result);
  if (FAILED(co_result) && co_result != RPC_E_CHANGED_MODE) {
    cached = {false, co_result, SharedAudioFailureStage::kComInitialization};
    probed = true;
    return cached;
  }

  // Activate against our own process tree in EXCLUDE mode. That is the same
  // activation the real capture performs, but it targets nothing sensitive and
  // is torn down immediately without ever being started.
  IAudioClient* audio_client = nullptr;
  SharedAudioFailureStage stage = SharedAudioFailureStage::kNone;
  HRESULT hr = ActivateProcessLoopbackClient(
      SharedAudioMode::kSystemLoopback, GetCurrentProcessId(), &audio_client,
      &stage);

  SafeRelease(&audio_client);
  if (co_initialized) {
    CoUninitialize();
  }

  cached = {SUCCEEDED(hr), hr, SUCCEEDED(hr) ? SharedAudioFailureStage::kNone
                                             : stage};
  probed = true;
  return cached;
}

std::vector<AudioEndpointInfo> EnumerateAudioEndpoints() {
  std::vector<AudioEndpointInfo> endpoints;

  HRESULT co_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool co_initialized = SUCCEEDED(co_result);
  if (FAILED(co_result) && co_result != RPC_E_CHANGED_MODE) {
    return endpoints;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) {
    if (co_initialized) {
      CoUninitialize();
    }
    return endpoints;
  }

  for (const EDataFlow flow : {eRender, eCapture}) {
    std::string default_id;
    IMMDevice* default_device = nullptr;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow, eConsole,
                                                      &default_device)) &&
        default_device != nullptr) {
      LPWSTR raw_id = nullptr;
      if (SUCCEEDED(default_device->GetId(&raw_id)) && raw_id != nullptr) {
        default_id = WideToUtf8(raw_id);
        CoTaskMemFree(raw_id);
      }
      SafeRelease(&default_device);
    }

    IMMDeviceCollection* collection = nullptr;
    if (FAILED(enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE,
                                              &collection)) ||
        collection == nullptr) {
      continue;
    }

    UINT count = 0;
    collection->GetCount(&count);
    for (UINT i = 0; i < count; ++i) {
      IMMDevice* device = nullptr;
      if (FAILED(collection->Item(i, &device)) || device == nullptr) {
        continue;
      }

      AudioEndpointInfo info;
      info.is_capture = flow == eCapture;

      LPWSTR raw_id = nullptr;
      if (SUCCEEDED(device->GetId(&raw_id)) && raw_id != nullptr) {
        info.id = WideToUtf8(raw_id);
        CoTaskMemFree(raw_id);
      }

      IPropertyStore* properties = nullptr;
      if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) &&
          properties != nullptr) {
        PROPVARIANT friendly_name;
        PropVariantInit(&friendly_name);
        if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName,
                                           &friendly_name)) &&
            friendly_name.vt == VT_LPWSTR && friendly_name.pwszVal != nullptr) {
          info.name = WideToUtf8(friendly_name.pwszVal);
        }
        PropVariantClear(&friendly_name);
        SafeRelease(&properties);
      }

      info.is_default = !info.id.empty() && info.id == default_id;
      info.is_likely_virtual =
          IsLikelyVirtualDeviceName(info.name, &info.virtual_family);

      if (!info.id.empty()) {
        endpoints.push_back(std::move(info));
      }
      SafeRelease(&device);
    }

    SafeRelease(&collection);
  }

  SafeRelease(&enumerator);
  if (co_initialized) {
    CoUninitialize();
  }

  return endpoints;
}

std::string AudioEndpointsJson() {
  const auto endpoints = EnumerateAudioEndpoints();
  std::ostringstream json;
  json << "[";
  for (size_t i = 0; i < endpoints.size(); ++i) {
    if (i > 0) {
      json << ",";
    }

    json << "{";
    json << "\"id\":\"" << EscapeJson(endpoints[i].id) << "\",";
    json << "\"name\":\"" << EscapeJson(endpoints[i].name) << "\",";
    json << "\"isCapture\":" << (endpoints[i].is_capture ? "true" : "false")
         << ",";
    json << "\"isDefault\":" << (endpoints[i].is_default ? "true" : "false")
         << ",";
    json << "\"isLikelyVirtual\":"
         << (endpoints[i].is_likely_virtual ? "true" : "false") << ",";
    json << "\"virtualFamily\":\"" << EscapeJson(endpoints[i].virtual_family)
         << "\"";
    json << "}";
  }
  json << "]";
  return json.str();
}

WindowsShareCapabilities GetCapabilities() {
  WindowsShareCapabilities capabilities;
  capabilities.os_build = GetWindowsBuildNumber();
  capabilities.documented_process_loopback_build =
      kDocumentedProcessLoopbackBuild;

  // Capability comes from an actual activation attempt, never from os_build.
  const SharedAudioProbeResult probe = ProbeProcessLoopbackActivation();
  capabilities.application_loopback_supported = probe.succeeded;
  capabilities.process_tree_loopback_supported = probe.succeeded;
  capabilities.process_loopback_hresult = probe.hresult;
  capabilities.process_loopback_stage = probe.stage;

  capabilities.wgc_supported = capabilities.os_build >= kMinimumWgcBuild;

  // Endpoint loopback rides plain WASAPI, which predates every build this app
  // supports, so it is gated on being able to reach the device enumerator at
  // all rather than on a version.
  const auto endpoints = EnumerateAudioEndpoints();
  const bool has_render_endpoint =
      std::any_of(endpoints.begin(), endpoints.end(),
                  [](const AudioEndpointInfo& e) { return !e.is_capture; });
  const bool has_capture_endpoint =
      std::any_of(endpoints.begin(), endpoints.end(),
                  [](const AudioEndpointInfo& e) { return e.is_capture; });
  capabilities.endpoint_loopback_supported = has_render_endpoint;
  capabilities.device_capture_supported = has_capture_endpoint;
  capabilities.has_virtual_audio_device =
      std::any_of(endpoints.begin(), endpoints.end(),
                  [](const AudioEndpointInfo& e) { return e.is_likely_virtual; });

  // The PCM bridge is a WebRTC-side concern and works for whichever capture
  // backend feeds it. It must not inherit the process-loopback verdict.
  capabilities.pcm_bridge_supported =
      capabilities.application_loopback_supported ||
      capabilities.endpoint_loopback_supported ||
      capabilities.device_capture_supported;

  if (capabilities.application_loopback_supported) {
    capabilities.reason = "ready";
  } else if (capabilities.endpoint_loopback_supported) {
    capabilities.reason = "process_loopback_activation_failed";
  } else {
    capabilities.reason = "no_shared_audio_backend";
  }

  return capabilities;
}

std::string CapabilitiesJson() {
  const auto capabilities = GetCapabilities();

  std::ostringstream json;
  json << "{";
  json << "\"supported\":" << (capabilities.supported ? "true" : "false")
       << ",";
  json << "\"applicationLoopbackSupported\":"
       << (capabilities.application_loopback_supported ? "true" : "false")
       << ",";
  json << "\"processTreeLoopbackSupported\":"
       << (capabilities.process_tree_loopback_supported ? "true" : "false")
       << ",";
  json << "\"wgcSupported\":"
       << (capabilities.wgc_supported ? "true" : "false") << ",";
  json << "\"pcmBridgeSupported\":"
       << (capabilities.pcm_bridge_supported ? "true" : "false") << ",";
  json << "\"endpointLoopbackSupported\":"
       << (capabilities.endpoint_loopback_supported ? "true" : "false") << ",";
  json << "\"deviceCaptureSupported\":"
       << (capabilities.device_capture_supported ? "true" : "false") << ",";
  json << "\"hasVirtualAudioDevice\":"
       << (capabilities.has_virtual_audio_device ? "true" : "false") << ",";
  json << "\"osBuild\":" << capabilities.os_build << ",";
  json << "\"documentedProcessLoopbackBuild\":"
       << capabilities.documented_process_loopback_build << ",";
  json << "\"processLoopbackHresult\":\""
       << HResultToString(capabilities.process_loopback_hresult) << "\",";
  json << "\"processLoopbackStage\":\""
       << ToJsonString(capabilities.process_loopback_stage) << "\",";
  json << "\"reason\":\"" << EscapeJson(capabilities.reason) << "\"";
  json << "}";
  return json.str();
}

std::vector<WindowTargetInfo> EnumerateWindowTargets() {
  std::vector<WindowTargetInfo> targets;
  EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&targets));
  return targets;
}

std::string WindowTargetsJson() {
  const auto targets = EnumerateWindowTargets();
  std::ostringstream json;
  json << "[";
  for (size_t i = 0; i < targets.size(); ++i) {
    if (i > 0) {
      json << ",";
    }

    json << "{";
    json << "\"windowHandle\":"
         << reinterpret_cast<unsigned long long>(targets[i].window_handle)
         << ",";
    json << "\"processId\":" << targets[i].process_id << ",";
    json << "\"title\":\"" << EscapeJson(targets[i].title) << "\"";
    json << "}";
  }
  json << "]";
  return json.str();
}

ProcessLoopbackCapture::ProcessLoopbackCapture() = default;

ProcessLoopbackCapture::~ProcessLoopbackCapture() {
  Stop();
}

bool ProcessLoopbackCapture::Start(SharedAudioMode mode,
                                   DWORD process_id,
                                   const std::string& device_id) {
  if (running_.load()) {
    return true;
  }

  if (mode == SharedAudioMode::kNone) {
    SetState("inactive", "shared_audio_not_requested");
    return true;
  }

  if (mode == SharedAudioMode::kUnavailable) {
    SetState("unavailable", "shared_audio_unavailable", E_INVALIDARG,
             SharedAudioFailureStage::kNone);
    return false;
  }

  // Deliberately no OS-version precondition here. Process-loopback support is
  // established by attempting the activation on the capture thread and
  // reporting the HRESULT and stage it fails at; the caller decides what to
  // offer next. Gating on GetWindowsBuildNumber() would deny the attempt on
  // builds (19045 among them) where the activation in fact succeeds.
  if (mode == SharedAudioMode::kProcessTreeLoopback && process_id == 0) {
    SetState("unavailable", "target_process_unresolved", E_INVALIDARG);
    return false;
  }

  stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  sample_ready_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (stop_event_ == nullptr || sample_ready_event_ == nullptr) {
    const HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
    // Whichever handle DID get created is still stored. Because running_ stays
    // false, a later Start() overwrites the member without closing it, leaking
    // one handle per failed attempt - so close them here.
    if (stop_event_ != nullptr) {
      CloseHandle(stop_event_);
      stop_event_ = nullptr;
    }
    if (sample_ready_event_ != nullptr) {
      CloseHandle(sample_ready_event_);
      sample_ready_event_ = nullptr;
    }
    SetState("failed", "event_creation_failed", hr,
             SharedAudioFailureStage::kEventHandle);
    return false;
  }

  packets_captured_.store(0);
  frames_captured_.store(0);
  bytes_captured_.store(0);
  nonsilent_bytes_captured_.store(0);
  running_.store(true);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    active_mode_ = mode;
    active_device_id_ = device_id;
  }
  EvaluateTargetElevation(mode, process_id);
  SetState("starting", "starting");
  capture_thread_ = std::thread(&ProcessLoopbackCapture::CaptureThreadMain,
                                this, mode, process_id, device_id);
  return true;
}

void ProcessLoopbackCapture::EvaluateTargetElevation(SharedAudioMode mode,
                                                     DWORD process_id) {
  if (mode != SharedAudioMode::kProcessTreeLoopback) {
    // System loopback captures the render endpoint mixer, which carries audio
    // from every process regardless of integrity level, so elevation is moot.
    target_elevated_.store(false);
    target_elevation_known_.store(true);
    return;
  }

  bool determined = false;
  const bool elevated =
      DetectTargetElevatedRelativeToSelf(process_id, &determined);
  target_elevated_.store(determined && elevated);
  target_elevation_known_.store(determined);
}

void ProcessLoopbackCapture::Stop() {
  if (stop_event_ != nullptr) {
    SetEvent(stop_event_);
  }

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  ReleaseAudioObjects();

  if (sample_ready_event_ != nullptr) {
    CloseHandle(sample_ready_event_);
    sample_ready_event_ = nullptr;
  }

  if (stop_event_ != nullptr) {
    CloseHandle(stop_event_);
    stop_event_ = nullptr;
  }

  if (running_.exchange(false)) {
    SetState("stopped", "stopped");
  }
}

void ProcessLoopbackCapture::SetSampleCallback(
    SharedAudioSampleCallback callback) {
  std::lock_guard<std::mutex> lock(callback_mutex_);
  sample_callback_ = std::move(callback);
}

void ProcessLoopbackCapture::CaptureThreadMain(SharedAudioMode mode,
                                               DWORD process_id,
                                               std::string device_id) {
  HRESULT co_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool co_initialized = SUCCEEDED(co_result);
  if (FAILED(co_result) && co_result != RPC_E_CHANGED_MODE) {
    SetState("failed", "com_initialization_failed", co_result,
             SharedAudioFailureStage::kComInitialization);
    running_.store(false);
    return;
  }

  const bool endpoint_backed = mode == SharedAudioMode::kEndpointLoopback ||
                               mode == SharedAudioMode::kDeviceCapture;

  HRESULT hr = S_OK;
  SharedAudioFailureStage endpoint_stage = SharedAudioFailureStage::kActivation;
  if (endpoint_backed) {
    hr = ActivateEndpointAudioClient(mode, device_id, &audio_client_,
                                     &endpoint_stage);
  } else {
    SharedAudioFailureStage stage = SharedAudioFailureStage::kNone;
    hr = ActivateProcessLoopbackClient(mode, process_id, &audio_client_,
                                       &stage);
    if (FAILED(hr)) {
      // The distinct reason lets the policy layer tell "this build cannot do
      // process loopback" apart from "the capture broke later", and offer the
      // endpoint/virtual-device alternatives only in the former case.
      SetState("failed", "process_loopback_activation_failed", hr, stage);
      running_.store(false);
      if (co_initialized) {
        CoUninitialize();
      }
      return;
    }
  }

  if (FAILED(hr)) {
    SetState("failed",
             endpoint_stage == SharedAudioFailureStage::kDeviceNotFound
                 ? "selected_audio_device_unavailable"
                 : "activate_audio_interface_failed",
             hr, endpoint_stage);
    running_.store(false);
    if (co_initialized) {
      CoUninitialize();
    }
    return;
  }

  // Device capture reads a capture endpoint directly, so it must not set the
  // loopback stream flag; every other mode is a loopback.
  hr = InitializeAudioClient(audio_client_,
                             mode != SharedAudioMode::kDeviceCapture);
  if (FAILED(hr)) {
    SetState("failed", "audio_client_initialize_failed", hr,
             SharedAudioFailureStage::kClientInitialize);
    running_.store(false);
    if (co_initialized) {
      CoUninitialize();
    }
    return;
  }

  hr = audio_client_->Start();
  if (FAILED(hr)) {
    SetState("failed", "audio_client_start_failed", hr,
             SharedAudioFailureStage::kStart);
    running_.store(false);
    if (co_initialized) {
      CoUninitialize();
    }
    return;
  }

  SetState("active", "capturing");

  HANDLE events[] = {stop_event_, sample_ready_event_};
  bool capture = true;
  while (capture) {
    DWORD wait = WaitForMultipleObjects(2, events, FALSE, INFINITE);
    switch (wait) {
      case WAIT_OBJECT_0:
        capture = false;
        break;
      case WAIT_OBJECT_0 + 1:
        if (FAILED(CaptureAvailablePackets())) {
          capture = false;
        }
        break;
      default:
        SetState("failed", "wait_failed", HRESULT_FROM_WIN32(GetLastError()),
                 SharedAudioFailureStage::kCapture);
        capture = false;
        break;
    }
  }

  audio_client_->Stop();
  ReleaseAudioObjects();
  running_.store(false);

  if (co_initialized) {
    CoUninitialize();
  }
}

HRESULT ProcessLoopbackCapture::ActivateApplicationLoopbackAudioClient(
    SharedAudioMode mode,
    DWORD process_id,
    IAudioClient** audio_client) {
  SharedAudioFailureStage stage = SharedAudioFailureStage::kNone;
  return ActivateProcessLoopbackClient(mode, process_id, audio_client, &stage);
}

HRESULT ProcessLoopbackCapture::ActivateEndpointAudioClient(
    SharedAudioMode mode,
    const std::string& device_id,
    IAudioClient** audio_client,
    SharedAudioFailureStage* stage) {
  *stage = SharedAudioFailureStage::kDeviceEnumeration;
  if (audio_client == nullptr) {
    return E_POINTER;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) {
    return hr;
  }

  // Endpoint loopback reads the render mix; device capture reads a capture
  // endpoint (the output side of a virtual cable the user has routed).
  const EDataFlow flow =
      mode == SharedAudioMode::kDeviceCapture ? eCapture : eRender;

  *stage = SharedAudioFailureStage::kDeviceNotFound;
  IMMDevice* device = nullptr;
  if (device_id.empty()) {
    hr = enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device);
  } else {
    const std::wstring wide_id = Utf8ToWide(device_id);
    hr = enumerator->GetDevice(wide_id.c_str(), &device);
  }

  SafeRelease(&enumerator);
  if (FAILED(hr) || device == nullptr) {
    return FAILED(hr) ? hr : E_FAIL;
  }

  *stage = SharedAudioFailureStage::kActivation;
  hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(audio_client));
  SafeRelease(&device);

  if (SUCCEEDED(hr)) {
    *stage = SharedAudioFailureStage::kNone;
  }
  return hr;
}

HRESULT ProcessLoopbackCapture::InitializeAudioClient(
    IAudioClient* audio_client,
    bool loopback) {
  if (audio_client == nullptr) {
    return E_POINTER;
  }

  capture_format_.wFormatTag = WAVE_FORMAT_PCM;
  capture_format_.nChannels = 2;
  capture_format_.nSamplesPerSec = 44100;
  capture_format_.wBitsPerSample = 16;
  capture_format_.nBlockAlign =
      capture_format_.nChannels * capture_format_.wBitsPerSample / kBitsPerByte;
  capture_format_.nAvgBytesPerSec =
      capture_format_.nSamplesPerSec * capture_format_.nBlockAlign;

  DWORD stream_flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                       AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                       AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
  if (loopback) {
    stream_flags |= AUDCLNT_STREAMFLAGS_LOOPBACK;
  }

  HRESULT hr = audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED, stream_flags,
                                        0, 0, &capture_format_, nullptr);
  if (FAILED(hr)) {
    return hr;
  }

  hr = audio_client->GetBufferSize(&buffer_frames_);
  if (FAILED(hr)) {
    return hr;
  }

  hr = audio_client->GetService(IID_PPV_ARGS(&audio_capture_client_));
  if (FAILED(hr)) {
    return hr;
  }

  return audio_client->SetEventHandle(sample_ready_event_);
}

HRESULT ProcessLoopbackCapture::CaptureAvailablePackets() {
  if (audio_capture_client_ == nullptr) {
    return E_POINTER;
  }

  UINT32 frames_available = 0;
  HRESULT hr = audio_capture_client_->GetNextPacketSize(&frames_available);
  while (SUCCEEDED(hr) && frames_available > 0) {
    BYTE* data = nullptr;
    DWORD capture_flags = 0;
    UINT64 device_position = 0;
    UINT64 qpc_position = 0;

    hr = audio_capture_client_->GetBuffer(
        &data, &frames_available, &capture_flags, &device_position,
        &qpc_position);
    if (FAILED(hr)) {
      SetState("failed", "audio_capture_get_buffer_failed", hr,
               SharedAudioFailureStage::kCapture);
      return hr;
    }

    const auto bytes =
        static_cast<unsigned long long>(frames_available) *
        static_cast<unsigned long long>(capture_format_.nBlockAlign);
    packets_captured_.fetch_add(1);
    frames_captured_.fetch_add(frames_available);
    bytes_captured_.fetch_add(bytes);
    if ((capture_flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
      nonsilent_bytes_captured_.fetch_add(bytes);
    }

    EmitSamples(data, frames_available, capture_flags);

    hr = audio_capture_client_->ReleaseBuffer(frames_available);
    if (FAILED(hr)) {
      SetState("failed", "audio_capture_release_buffer_failed", hr,
               SharedAudioFailureStage::kCapture);
      return hr;
    }

    hr = audio_capture_client_->GetNextPacketSize(&frames_available);
  }

  if (FAILED(hr)) {
    SetState("failed", "audio_capture_next_packet_failed", hr,
             SharedAudioFailureStage::kCapture);
  }

  return hr;
}

void ProcessLoopbackCapture::EmitSamples(const BYTE* data,
                                         UINT32 frame_count,
                                         DWORD flags) {
  SharedAudioSampleCallback callback;
  {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    callback = sample_callback_;
  }

  if (!callback || frame_count == 0 || capture_format_.nBlockAlign == 0) {
    return;
  }

  if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
    std::vector<BYTE> silence(
        static_cast<size_t>(frame_count) * capture_format_.nBlockAlign, 0);
    callback(silence.data(), frame_count, capture_format_, flags);
    return;
  }

  callback(data, frame_count, capture_format_, flags);
}

void ProcessLoopbackCapture::SetState(std::string state,
                                      std::string reason,
                                      HRESULT hr,
                                      SharedAudioFailureStage stage) {
  std::lock_guard<std::mutex> lock(mutex_);
  state_ = std::move(state);
  reason_ = std::move(reason);
  last_hresult_ = hr;
  failure_stage_ = stage;
}

void ProcessLoopbackCapture::ReleaseAudioObjects() {
  SafeRelease(&audio_capture_client_);
  SafeRelease(&audio_client_);
}

std::string ProcessLoopbackCapture::StatusJson() const {
  std::lock_guard<std::mutex> lock(mutex_);

  std::ostringstream json;
  json << "{";
  json << "\"audioState\":\"" << EscapeJson(state_) << "\",";
  json << "\"active\":" << (state_ == "active" ? "true" : "false") << ",";
  json << "\"sampleRateHz\":" << capture_format_.nSamplesPerSec << ",";
  json << "\"numChannels\":" << capture_format_.nChannels << ",";
  json << "\"bitsPerSample\":" << capture_format_.wBitsPerSample << ",";
  json << "\"packetsCaptured\":" << packets_captured_.load() << ",";
  json << "\"framesCaptured\":" << frames_captured_.load() << ",";
  json << "\"bytesCaptured\":" << bytes_captured_.load() << ",";
  json << "\"nonsilentBytesCaptured\":" << nonsilent_bytes_captured_.load()
       << ",";
  json << "\"targetElevated\":"
       << (target_elevated_.load() ? "true" : "false") << ",";
  json << "\"targetElevationKnown\":"
       << (target_elevation_known_.load() ? "true" : "false") << ",";
  json << "\"lastHresult\":\"" << HResultToString(last_hresult_) << "\",";
  json << "\"failureStage\":\"" << ToJsonString(failure_stage_) << "\",";
  json << "\"activeAudioMode\":\"" << ToJsonString(active_mode_) << "\",";
  json << "\"selectedDeviceId\":\"" << EscapeJson(active_device_id_) << "\",";
  json << "\"reason\":\"" << EscapeJson(reason_) << "\"";
  json << "}";
  return json.str();
}

ShareSession::ShareSession(int session_id, ShareSessionConfig config)
    : session_id_(session_id), config_(config), capture_(new ProcessLoopbackCapture()) {}

ShareSession::~ShareSession() {
  StopSharedAudio();
}

bool ShareSession::StartSharedAudio() {
  if (!config_.request_shared_audio) {
    return true;
  }

  return capture_->Start(config_.audio_mode, config_.process_id,
                         config_.device_id);
}

void ShareSession::StopSharedAudio() {
  DisposeSharedAudioStream();
  capture_->Stop();
}

std::string ShareSession::CreateSharedAudioStreamJson() {
  if (!config_.request_shared_audio) {
    return UnsupportedSharedAudioStreamJson(session_id_,
                                           "shared_audio_not_requested");
  }

  const auto capabilities = GetCapabilities();
  if (!capabilities.pcm_bridge_supported) {
    return UnsupportedSharedAudioStreamJson(session_id_, capabilities.reason);
  }

  auto* webrtc = FlutterWebRTCPluginSharedInstance();
  if (webrtc == nullptr || webrtc->factory_ == nullptr) {
    return UnsupportedSharedAudioStreamJson(session_id_,
                                           "flutter_webrtc_unavailable");
  }

  if (pcm_bridge_ == nullptr) {
    auto bridge = std::make_unique<PcmBridge>();
    bridge->stream_id = GenerateLocalId();
    bridge->track_id = GenerateLocalId();

    libwebrtc::RTCAudioOptions options;
    bridge->source = webrtc->factory_->CreateAudioSource(
        kSharedAudioLabel, libwebrtc::RTCAudioSource::SourceType::kCustom,
        options);
    bridge->track =
        webrtc->factory_->CreateAudioTrack(bridge->source,
                                           bridge->track_id.c_str());
    bridge->stream =
        webrtc->factory_->CreateStream(bridge->stream_id.c_str());

    if (bridge->source == nullptr || bridge->track == nullptr ||
        bridge->stream == nullptr) {
      return UnsupportedSharedAudioStreamJson(session_id_,
                                             "webrtc_track_creation_failed");
    }

    bridge->stream->AddTrack(bridge->track);
    {
      std::lock_guard<std::mutex> lock(webrtc->mutex_);
      webrtc->local_tracks_[bridge->track_id] = bridge->track;
      webrtc->local_streams_[bridge->stream_id] = bridge->stream;
    }

    auto audio_source = bridge->source;
    capture_->SetSampleCallback(
        [audio_source](const BYTE* data,
                       UINT32 frame_count,
                       const WAVEFORMATEX& format,
                       DWORD /*flags*/) {
          if (data == nullptr || frame_count == 0 || format.nChannels == 0 ||
              format.nSamplesPerSec == 0 || format.wBitsPerSample == 0) {
            return;
          }

          audio_source->CaptureFrame(data, format.wBitsPerSample,
                                     format.nSamplesPerSec, format.nChannels,
                                     frame_count);
        });

    pcm_bridge_ = std::move(bridge);
  }

  const auto& bridge = *pcm_bridge_;
  std::ostringstream json;
  json << "{";
  json << "\"sessionId\":" << session_id_ << ",";
  json << "\"supported\":true,";
  json << "\"streamId\":\"" << EscapeJson(bridge.stream_id) << "\",";
  json << "\"trackId\":\"" << EscapeJson(bridge.track_id) << "\",";
  json << "\"ownerTag\":\"local\",";
  json << "\"sampleRateHz\":" << 44100 << ",";
  json << "\"numChannels\":" << 2 << ",";
  json << "\"bitsPerSample\":" << 16 << ",";
  json << "\"audioTracks\":[{";
  json << "\"id\":\"" << EscapeJson(bridge.track_id) << "\",";
  json << "\"label\":\"" << EscapeJson(kSharedAudioLabel) << "\",";
  json << "\"kind\":\"audio\",";
  json << "\"enabled\":true,";
  json << "\"settings\":{";
  json << "\"deviceId\":\"" << EscapeJson(kSharedAudioDeviceId) << "\",";
  json << "\"kind\":\"audioinput\",";
  json << "\"channelCount\":2,";
  json << "\"sampleRate\":44100,";
  json << "\"autoGainControl\":false,";
  json << "\"echoCancellation\":false,";
  json << "\"noiseSuppression\":false";
  json << "}}],";
  json << "\"videoTracks\":[],";
  json << "\"reason\":\"ready\"";
  json << "}";
  return json.str();
}

void ShareSession::DisposeSharedAudioStream() {
  capture_->SetSampleCallback(nullptr);

  if (pcm_bridge_ == nullptr) {
    return;
  }

  auto* webrtc = FlutterWebRTCPluginSharedInstance();
  if (webrtc != nullptr) {
    std::lock_guard<std::mutex> lock(webrtc->mutex_);
    if (pcm_bridge_->stream != nullptr && pcm_bridge_->track != nullptr) {
      pcm_bridge_->stream->RemoveTrack(pcm_bridge_->track);
    }
    webrtc->local_tracks_.erase(pcm_bridge_->track_id);
    webrtc->local_streams_.erase(pcm_bridge_->stream_id);
  }

  pcm_bridge_.reset();
}

std::string ShareSession::StatusJson() const {
  const std::string capture_json = capture_->StatusJson();

  std::ostringstream json;
  json << "{";
  json << "\"sessionId\":" << session_id_ << ",";
  json << "\"supported\":true,";
  json << "\"requestedAudio\":"
       << (config_.request_shared_audio ? "true" : "false") << ",";
  json << "\"targetType\":\"" << ToJsonString(config_.target_type) << "\",";
  json << "\"audioMode\":\"" << ToJsonString(config_.audio_mode) << "\",";

  // capture_json is an object; splice its fields after the leading brace.
  if (capture_json.size() > 2) {
    json << capture_json.substr(1, capture_json.size() - 2) << ",";
  } else {
    json << "\"audioState\":\"unavailable\",";
    json << "\"active\":false,";
    json << "\"sampleRateHz\":0,";
    json << "\"numChannels\":0,";
    json << "\"bitsPerSample\":0,";
    json << "\"packetsCaptured\":0,";
    json << "\"framesCaptured\":0,";
    json << "\"bytesCaptured\":0,";
    json << "\"nonsilentBytesCaptured\":0,";
    json << "\"targetElevated\":false,";
    json << "\"targetElevationKnown\":false,";
    json << "\"reason\":\"status_unavailable\",";
  }

  const auto capabilities = GetCapabilities();
  json << "\"pcmBridgeSupported\":"
       << (capabilities.pcm_bridge_supported ? "true" : "false") << ",";
  json << "\"pcmBridgeReady\":" << (pcm_bridge_ != nullptr ? "true" : "false")
       << ",";
  json << "\"wgcReady\":false";
  json << "}";
  return json.str();
}

}  // namespace intergalactic_windows_share
