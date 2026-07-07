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
  kSystemLoopback = 2,
  kUnavailable = 3,
};

struct ShareSessionConfig {
  ShareTargetType target_type = ShareTargetType::kDisplay;
  SharedAudioMode audio_mode = SharedAudioMode::kNone;
  DWORD process_id = 0;
  bool request_shared_audio = false;
};

struct WindowTargetInfo {
  HWND window_handle = nullptr;
  DWORD process_id = 0;
  std::string title;
};

struct WindowsShareCapabilities {
  bool supported = true;
  bool application_loopback_supported = false;
  bool process_tree_loopback_supported = false;
  bool wgc_supported = false;
  bool pcm_bridge_supported = false;
  DWORD os_build = 0;
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

  bool Start(SharedAudioMode mode, DWORD process_id);
  void Stop();
  void SetSampleCallback(SharedAudioSampleCallback callback);
  std::string StatusJson() const;

 private:
  void CaptureThreadMain(SharedAudioMode mode, DWORD process_id);
  HRESULT ActivateApplicationLoopbackAudioClient(SharedAudioMode mode,
                                                 DWORD process_id,
                                                 IAudioClient** audio_client);
  HRESULT InitializeAudioClient(IAudioClient* audio_client);
  HRESULT CaptureAvailablePackets();
  void EmitSamples(const BYTE* data, UINT32 frame_count, DWORD flags);
  void SetState(std::string state, std::string reason, HRESULT hr = S_OK);
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
  std::atomic<bool> running_{false};
  std::atomic<unsigned long long> packets_captured_{0};
  std::atomic<unsigned long long> frames_captured_{0};
  std::atomic<unsigned long long> bytes_captured_{0};
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

const char* ToJsonString(ShareTargetType type);
const char* ToJsonString(SharedAudioMode mode);

}  // namespace intergalactic_windows_share

#endif  // INTERGALACTIC_WINDOWS_SHARE_CAPTURE_H_
