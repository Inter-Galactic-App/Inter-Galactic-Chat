#ifndef INTERGALACTIC_WINDOWS_SHARE_CAPTURE_H_
#define INTERGALACTIC_WINDOWS_SHARE_CAPTURE_H_

#include <Windows.h>
#include <audioclient.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace intergalactic_windows_share {

enum class ShareTargetType {
  kDisplay = 0,
  kWindow = 1,
};

enum class SharedAudioMode {
  kNone = 0,
  kProcessTreeLoopback = 1,
  // Process loopback that *excludes* our own process tree. Keeps Inter
  // Galactic's own received call audio out of the capture, so it is preferred
  // over kEndpointLoopback whenever process loopback activates.
  kSystemLoopback = 2,
  kUnavailable = 3,
  // Classic WASAPI render-endpoint loopback (IMMDevice + AUDCLNT_STREAMFLAGS_
  // LOOPBACK). Available on every Windows version that has WASAPI at all, but
  // it captures the whole endpoint mix and therefore cannot exclude our own
  // call audio.
  kEndpointLoopback = 4,
  // Ordinary capture from a chosen capture endpoint, used for virtual audio
  // cables (VB-CABLE, VoiceMeeter) that the user has routed manually.
  kDeviceCapture = 5,
};

// Where a shared-audio attempt stopped. Reported alongside the HRESULT so a
// failure can be attributed without reading native logs.
enum class SharedAudioFailureStage {
  kNone = 0,
  kComInitialization = 1,
  kActivation = 2,
  kClientInitialize = 3,
  kServiceAcquire = 4,
  kEventHandle = 5,
  kStart = 6,
  kCapture = 7,
  kDeviceEnumeration = 8,
  kDeviceNotFound = 9,
  kActivationTimeout = 10,
};

// Result of actually attempting a process-loopback activation, as opposed to
// inferring support from the OS build number.
struct SharedAudioProbeResult {
  bool succeeded = false;
  HRESULT hresult = E_FAIL;
  SharedAudioFailureStage stage = SharedAudioFailureStage::kNone;
};

// A render or capture endpoint, annotated with virtual-device detection so the
// UI can offer known audio cables as an advanced routing choice.
struct AudioEndpointInfo {
  std::string id;
  std::string name;
  bool is_capture = false;
  bool is_default = false;
  bool is_likely_virtual = false;
  std::string virtual_family;  // "vb-cable", "voicemeeter", "vac", or "".
};

struct ShareSessionConfig {
  ShareTargetType target_type = ShareTargetType::kDisplay;
  SharedAudioMode audio_mode = SharedAudioMode::kNone;
  DWORD process_id = 0;
  bool request_shared_audio = false;
  // Endpoint id for kEndpointLoopback / kDeviceCapture. Empty selects the
  // current default endpoint for the relevant data flow.
  std::string device_id;
};

struct WindowTargetInfo {
  HWND window_handle = nullptr;
  DWORD process_id = 0;
  std::string title;
};

struct WindowsShareCapabilities {
  bool supported = true;
  // Determined by *attempting* an activation, never by comparing os_build
  // against a documented minimum. Microsoft documents build 20348, but process
  // loopback activates on a number of earlier Windows 10 servicing builds, and
  // it can also fail on builds that are new enough. Only the attempt is
  // authoritative.
  bool application_loopback_supported = false;
  bool process_tree_loopback_supported = false;
  bool wgc_supported = false;
  bool pcm_bridge_supported = false;
  // Classic render-endpoint loopback. Present wherever WASAPI is, which is
  // every Windows version this app runs on.
  bool endpoint_loopback_supported = false;
  bool device_capture_supported = false;
  bool has_virtual_audio_device = false;
  DWORD os_build = 0;
  // Build at which Microsoft documents process loopback as supported. Reported
  // for diagnostics only; it must not gate behaviour.
  DWORD documented_process_loopback_build = 0;
  HRESULT process_loopback_hresult = S_OK;
  SharedAudioFailureStage process_loopback_stage = SharedAudioFailureStage::kNone;
  std::string reason;
};

using SharedAudioSampleCallback = std::function<void(
    const BYTE* data,
    UINT32 frame_count,
    const WAVEFORMATEX& format,
    DWORD flags)>;

class ProcessLoopbackCapture {
 public:
  ProcessLoopbackCapture();
  ~ProcessLoopbackCapture();

  ProcessLoopbackCapture(const ProcessLoopbackCapture&) = delete;
  ProcessLoopbackCapture& operator=(const ProcessLoopbackCapture&) = delete;

  bool Start(SharedAudioMode mode, DWORD process_id, const std::string& device_id = "");
  void Stop();
  void SetSampleCallback(SharedAudioSampleCallback callback);
  std::string StatusJson() const;

 private:
  void CaptureThreadMain(SharedAudioMode mode,
                         DWORD process_id,
                         std::string device_id);
  HRESULT ActivateApplicationLoopbackAudioClient(SharedAudioMode mode,
                                                 DWORD process_id,
                                                 IAudioClient** audio_client);
  // Classic endpoint loopback / device capture activation via
  // IMMDeviceEnumerator. `device_id` selects an endpoint; empty means default.
  HRESULT ActivateEndpointAudioClient(SharedAudioMode mode,
                                      const std::string& device_id,
                                      IAudioClient** audio_client,
                                      SharedAudioFailureStage* stage);
  // Detects whether a process-tree loopback target runs at a higher integrity
  // level than this process (e.g. an elevated / anti-cheat-protected game).
  // Windows process-loopback cannot capture audio across that boundary, so the
  // capture would otherwise silently deliver only zeroed buffers.
  void EvaluateTargetElevation(SharedAudioMode mode, DWORD process_id);
  HRESULT InitializeAudioClient(IAudioClient* audio_client, bool loopback);
  HRESULT CaptureAvailablePackets();
  void EmitSamples(const BYTE* data, UINT32 frame_count, DWORD flags);
  void SetState(std::string state,
                std::string reason,
                HRESULT hr = S_OK,
                SharedAudioFailureStage stage = SharedAudioFailureStage::kNone);
  void ReleaseAudioObjects();

  mutable std::mutex mutex_;
  mutable std::mutex callback_mutex_;
  SharedAudioSampleCallback sample_callback_;
  std::thread capture_thread_;
  HANDLE stop_event_ = nullptr;
  HANDLE sample_ready_event_ = nullptr;
  IAudioClient* audio_client_ = nullptr;
  IAudioCaptureClient* audio_capture_client_ = nullptr;
  WAVEFORMATEX capture_format_{};
  UINT32 buffer_frames_ = 0;
  std::string state_ = "inactive";
  std::string reason_ = "not_started";
  HRESULT last_hresult_ = S_OK;
  SharedAudioFailureStage failure_stage_ = SharedAudioFailureStage::kNone;
  SharedAudioMode active_mode_ = SharedAudioMode::kNone;
  std::string active_device_id_;
  std::atomic<bool> running_{false};
  std::atomic<bool> target_elevated_{false};
  std::atomic<bool> target_elevation_known_{false};
  std::atomic<unsigned long long> packets_captured_{0};
  std::atomic<unsigned long long> frames_captured_{0};
  std::atomic<unsigned long long> bytes_captured_{0};
  std::atomic<unsigned long long> nonsilent_bytes_captured_{0};
};

struct PcmBridge;

class ShareSession {
 public:
  ShareSession(int session_id, ShareSessionConfig config);
  ~ShareSession();

  ShareSession(const ShareSession&) = delete;
  ShareSession& operator=(const ShareSession&) = delete;

  int session_id() const { return session_id_; }
  bool StartSharedAudio();
  void StopSharedAudio();
  std::string CreateSharedAudioStreamJson();
  void DisposeSharedAudioStream();
  std::string StatusJson() const;

 private:
  int session_id_;
  ShareSessionConfig config_;
  std::unique_ptr<ProcessLoopbackCapture> capture_;
  std::unique_ptr<PcmBridge> pcm_bridge_;
};

WindowsShareCapabilities GetCapabilities();
std::string CapabilitiesJson();
std::vector<WindowTargetInfo> EnumerateWindowTargets();
std::string WindowTargetsJson();
std::string EscapeJson(const std::string& value);

// Attempts a real process-loopback activation and immediately releases it.
// Cached after the first call because the answer cannot change without a
// reboot; pass `force` to re-probe.
SharedAudioProbeResult ProbeProcessLoopbackActivation(bool force = false);

std::vector<AudioEndpointInfo> EnumerateAudioEndpoints();
std::string AudioEndpointsJson();

// True when `name` matches a known virtual audio cable. Exposed for testing.
bool IsLikelyVirtualDeviceName(const std::string& name,
                               std::string* family_out);

const char* ToJsonString(ShareTargetType type);
const char* ToJsonString(SharedAudioMode mode);
const char* ToJsonString(SharedAudioFailureStage stage);

}  // namespace intergalactic_windows_share

#endif  // INTERGALACTIC_WINDOWS_SHARE_CAPTURE_H_
