#include "include/intergalactic_windows_share/intergalactic_windows_share_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <mutex>

#include "windows_share_capture.h"

namespace {

using intergalactic_windows_share::ShareSession;
using intergalactic_windows_share::ShareSessionConfig;
using intergalactic_windows_share::SharedAudioMode;
using intergalactic_windows_share::ShareTargetType;

class WindowsShareManager {
 public:
  static WindowsShareManager& Instance() {
    static WindowsShareManager instance;
    return instance;
  }

  int CreateSession(int target_type,
                    int audio_mode,
                    unsigned int process_id,
                    int request_shared_audio,
                    const char* device_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    ShareSessionConfig config;
    config.target_type = target_type == 1 ? ShareTargetType::kWindow
                                          : ShareTargetType::kDisplay;
    config.audio_mode = ParseAudioMode(audio_mode);
    config.process_id = static_cast<DWORD>(process_id);
    config.request_shared_audio = request_shared_audio != 0;
    config.device_id = device_id == nullptr ? "" : device_id;

    const int session_id = next_session_id_++;
    sessions_[session_id] =
        std::make_unique<ShareSession>(session_id, config);
    return session_id;
  }

  int StartSharedAudio(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = FindSessionLocked(session_id);
    if (session == nullptr) {
      return 0;
    }

    return session->StartSharedAudio() ? 1 : 0;
  }

  int StopSharedAudio(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = FindSessionLocked(session_id);
    if (session == nullptr) {
      return 0;
    }

    session->StopSharedAudio();
    return 1;
  }

  std::string CreateSharedAudioStreamJson(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = FindSessionLocked(session_id);
    if (session == nullptr) {
      return "{\"sessionId\":0,\"supported\":false,\"streamId\":\"\","
             "\"trackId\":\"\",\"sampleRateHz\":0,\"numChannels\":0,"
             "\"bitsPerSample\":0,\"audioTracks\":[],\"videoTracks\":[],"
             "\"reason\":\"session_not_found\"}";
    }

    return session->CreateSharedAudioStreamJson();
  }

  int DisposeSharedAudioStream(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = FindSessionLocked(session_id);
    if (session == nullptr) {
      return 0;
    }

    session->DisposeSharedAudioStream();
    return 1;
  }

  std::string SessionStatusJson(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = FindSessionLocked(session_id);
    if (session == nullptr) {
      return "{\"sessionId\":0,\"supported\":false,\"requestedAudio\":false,"
             "\"targetType\":\"display\",\"audioMode\":\"unavailable\","
             "\"audioState\":\"unavailable\",\"active\":false,"
             "\"sampleRateHz\":0,\"numChannels\":0,\"bitsPerSample\":0,"
             "\"packetsCaptured\":0,\"framesCaptured\":0,"
             "\"bytesCaptured\":0,\"pcmBridgeSupported\":false,"
             "\"wgcReady\":false,\"reason\":\"session_not_found\"}";
    }

    return session->StatusJson();
  }

  int DisposeSession(int session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    return sessions_.erase(session_id) > 0 ? 1 : 0;
  }

 private:
  WindowsShareManager() = default;

  SharedAudioMode ParseAudioMode(int value) {
    switch (value) {
      case 0:
        return SharedAudioMode::kNone;
      case 1:
        return SharedAudioMode::kProcessTreeLoopback;
      case 2:
        return SharedAudioMode::kSystemLoopback;
      case 4:
        return SharedAudioMode::kEndpointLoopback;
      case 5:
        return SharedAudioMode::kDeviceCapture;
      case 3:
      default:
        return SharedAudioMode::kUnavailable;
    }
  }

  ShareSession* FindSessionLocked(int session_id) {
    const auto iterator = sessions_.find(session_id);
    if (iterator == sessions_.end()) {
      return nullptr;
    }

    return iterator->second.get();
  }

  std::mutex mutex_;
  int next_session_id_ = 1;
  std::map<int, std::unique_ptr<ShareSession>> sessions_;
};

class IntergalacticWindowsSharePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    registrar->AddPlugin(std::make_unique<IntergalacticWindowsSharePlugin>());
  }

  ~IntergalacticWindowsSharePlugin() override = default;
};

}  // namespace

void IntergalacticWindowsSharePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  IntergalacticWindowsSharePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

const char* intergalactic_windows_share_get_capabilities_json() {
  thread_local std::string json;
  json = intergalactic_windows_share::CapabilitiesJson();
  return json.c_str();
}

const char* intergalactic_windows_share_list_targets_json() {
  thread_local std::string json;
  json = intergalactic_windows_share::WindowTargetsJson();
  return json.c_str();
}

const char* intergalactic_windows_share_list_audio_endpoints_json() {
  thread_local std::string json;
  json = intergalactic_windows_share::AudioEndpointsJson();
  return json.c_str();
}

int intergalactic_windows_share_create_session(int target_type,
                                               int audio_mode,
                                               unsigned int process_id,
                                               int request_shared_audio,
                                               const char* device_id) {
  return WindowsShareManager::Instance().CreateSession(
      target_type, audio_mode, process_id, request_shared_audio, device_id);
}

int intergalactic_windows_share_start_shared_audio(int session_id) {
  return WindowsShareManager::Instance().StartSharedAudio(session_id);
}

int intergalactic_windows_share_stop_shared_audio(int session_id) {
  return WindowsShareManager::Instance().StopSharedAudio(session_id);
}

const char* intergalactic_windows_share_create_shared_audio_stream_json(
    int session_id) {
  thread_local std::string json;
  json =
      WindowsShareManager::Instance().CreateSharedAudioStreamJson(session_id);
  return json.c_str();
}

int intergalactic_windows_share_dispose_shared_audio_stream(int session_id) {
  return WindowsShareManager::Instance().DisposeSharedAudioStream(session_id);
}

const char* intergalactic_windows_share_get_session_status_json(
    int session_id) {
  thread_local std::string json;
  json = WindowsShareManager::Instance().SessionStatusJson(session_id);
  return json.c_str();
}

int intergalactic_windows_share_dispose_session(int session_id) {
  return WindowsShareManager::Instance().DisposeSession(session_id);
}
