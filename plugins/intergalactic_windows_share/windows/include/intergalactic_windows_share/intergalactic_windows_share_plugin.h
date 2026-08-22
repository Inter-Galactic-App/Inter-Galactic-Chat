#ifndef FLUTTER_PLUGIN_INTERGALACTIC_WINDOWS_SHARE_PLUGIN_H_
#define FLUTTER_PLUGIN_INTERGALACTIC_WINDOWS_SHARE_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define INTERGALACTIC_WINDOWS_SHARE_EXPORT __declspec(dllexport)
#else
#define INTERGALACTIC_WINDOWS_SHARE_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

INTERGALACTIC_WINDOWS_SHARE_EXPORT void
IntergalacticWindowsSharePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

INTERGALACTIC_WINDOWS_SHARE_EXPORT const char*
intergalactic_windows_share_get_capabilities_json();

INTERGALACTIC_WINDOWS_SHARE_EXPORT const char*
intergalactic_windows_share_list_targets_json();

INTERGALACTIC_WINDOWS_SHARE_EXPORT const char*
intergalactic_windows_share_list_audio_endpoints_json();

// `device_id` selects the endpoint for the endpointLoopback / deviceCapture
// audio modes. Pass an empty string (or null) for the current default endpoint;
// it is ignored by the process-loopback modes.
INTERGALACTIC_WINDOWS_SHARE_EXPORT int
intergalactic_windows_share_create_session(int target_type,
                                           int audio_mode,
                                           unsigned int process_id,
                                           int request_shared_audio,
                                           const char* device_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT int
intergalactic_windows_share_start_shared_audio(int session_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT int
intergalactic_windows_share_stop_shared_audio(int session_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT const char*
intergalactic_windows_share_create_shared_audio_stream_json(int session_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT int
intergalactic_windows_share_dispose_shared_audio_stream(int session_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT const char*
intergalactic_windows_share_get_session_status_json(int session_id);

INTERGALACTIC_WINDOWS_SHARE_EXPORT int
intergalactic_windows_share_dispose_session(int session_id);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_INTERGALACTIC_WINDOWS_SHARE_PLUGIN_H_
