#include "windows_share_capture.h"

#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <propidl.h>

#include <algorithm>
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

constexpr DWORD kMinimumProcessLoopbackBuild = 20348;
constexpr DWORD kMinimumWgcBuild = 18362;
constexpr int kBitsPerByte = 8;
constexpr char kSharedAudioLabel[] = "Windows shared audio";
constexpr char kSharedAudioDeviceId[] = "windows-shared-audio";

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
    case SharedAudioMode::kUnavailable:
    default:
      return "unavailable";
  }
}

WindowsShareCapabilities GetCapabilities() {
  WindowsShareCapabilities capabilities;
  capabilities.os_build = GetWindowsBuildNumber();
  capabilities.application_loopback_supported =
      capabilities.os_build >= kMinimumProcessLoopbackBuild;
  capabilities.process_tree_loopback_supported =
      capabilities.application_loopback_supported;
  capabilities.wgc_supported = capabilities.os_build >= kMinimumWgcBuild;
  capabilities.pcm_bridge_supported = capabilities.application_loopback_supported;
  capabilities.reason = capabilities.application_loopback_supported
                            ? "ready"
                            : "process_loopback_requires_windows_10_20348";
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
  json << "\"osBuild\":" << capabilities.os_build << ",";
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

bool ProcessLoopbackCapture::Start(SharedAudioMode mode, DWORD process_id) {
  if (running_.load()) {
    return true;
  }

  if (mode == SharedAudioMode::kNone) {
    SetState("inactive", "shared_audio_not_requested");
    return true;
  }

  const auto capabilities = GetCapabilities();
  if (!capabilities.application_loopback_supported) {
    SetState("unavailable", capabilities.reason, HRESULT_FROM_WIN32(ERROR_OLD_WIN_VERSION));
    return false;
  }

  if (mode == SharedAudioMode::kProcessTreeLoopback && process_id == 0) {
    SetState("unavailable", "target_process_unresolved", E_INVALIDARG);
    return false;
  }

  stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  sample_ready_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (stop_event_ == nullptr || sample_ready_event_ == nullptr) {
    SetState("failed", "event_creation_failed", HRESULT_FROM_WIN32(GetLastError()));
    return false;
  }

  packets_captured_.store(0);
  frames_captured_.store(0);
  bytes_captured_.store(0);
  running_.store(true);
  SetState("starting", "starting");
  capture_thread_ = std::thread(
      &ProcessLoopbackCapture::CaptureThreadMain, this, mode, process_id);
  return true;
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
                                               DWORD process_id) {
  HRESULT co_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool co_initialized = SUCCEEDED(co_result);
  if (FAILED(co_result) && co_result != RPC_E_CHANGED_MODE) {
    SetState("failed", "com_initialization_failed", co_result);
    running_.store(false);
    return;
  }

  HRESULT hr = ActivateApplicationLoopbackAudioClient(mode, process_id,
                                                      &audio_client_);
  if (FAILED(hr)) {
    SetState("failed", "activate_audio_interface_failed", hr);
    running_.store(false);
    if (co_initialized) {
      CoUninitialize();
    }
    return;
  }

  hr = InitializeAudioClient(audio_client_);
  if (FAILED(hr)) {
    SetState("failed", "audio_client_initialize_failed", hr);
    running_.store(false);
    if (co_initialized) {
      CoUninitialize();
    }
    return;
  }

  hr = audio_client_->Start();
  if (FAILED(hr)) {
    SetState("failed", "audio_client_start_failed", hr);
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
        SetState("failed", "wait_failed", HRESULT_FROM_WIN32(GetLastError()));
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
  prop_variant.blob.pBlobData =
      reinterpret_cast<BYTE*>(&activation_params);

  auto* handler = new AudioActivationHandler();
  if (handler->completed_event() == nullptr) {
    handler->Release();
    return HRESULT_FROM_WIN32(GetLastError());
  }

  IActivateAudioInterfaceAsyncOperation* operation = nullptr;
  HRESULT hr = ActivateAudioInterfaceAsync(
      VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
      &prop_variant, handler, &operation);
  if (SUCCEEDED(hr)) {
    WaitForSingleObject(handler->completed_event(), INFINITE);
    hr = handler->result();
    if (SUCCEEDED(hr)) {
      *audio_client = handler->DetachAudioClient();
    }
  }

  SafeRelease(&operation);
  handler->Release();
  return hr;
}

HRESULT ProcessLoopbackCapture::InitializeAudioClient(
    IAudioClient* audio_client) {
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

  HRESULT hr = audio_client->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
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
      SetState("failed", "audio_capture_get_buffer_failed", hr);
      return hr;
    }

    const auto bytes =
        static_cast<unsigned long long>(frames_available) *
        static_cast<unsigned long long>(capture_format_.nBlockAlign);
    packets_captured_.fetch_add(1);
    frames_captured_.fetch_add(frames_available);
    bytes_captured_.fetch_add(bytes);

    EmitSamples(data, frames_available, capture_flags);

    hr = audio_capture_client_->ReleaseBuffer(frames_available);
    if (FAILED(hr)) {
      SetState("failed", "audio_capture_release_buffer_failed", hr);
      return hr;
    }

    hr = audio_capture_client_->GetNextPacketSize(&frames_available);
  }

  if (FAILED(hr)) {
    SetState("failed", "audio_capture_next_packet_failed", hr);
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
                                      HRESULT hr) {
  std::lock_guard<std::mutex> lock(mutex_);
  state_ = std::move(state);
  reason_ = std::move(reason);
  last_hresult_ = hr;
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
  json << "\"lastHresult\":\"" << HResultToString(last_hresult_) << "\",";
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

  return capture_->Start(config_.audio_mode, config_.process_id);
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
