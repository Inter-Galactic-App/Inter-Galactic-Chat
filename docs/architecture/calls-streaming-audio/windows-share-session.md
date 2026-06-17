# Windows ShareSession

Status: Active architecture reference
Owner: EXPERIMENTAL for shared-content media; AUDIO for microphone suppression
Last reviewed: 2026-06-16 by DOCUMENTATION

## Purpose

Windows ShareSession keeps screen/window video, shared-content audio, and
microphone audio as separate sources. It exists so Matrix direct calls,
LiveKit-backed calls, and future transports can receive distinct media inputs
instead of treating application audio as microphone audio.

## Current Shape

- Dart orchestration lives under
  `intergalactic/lib/client/components/voip/share_session/`.
- Windows native ownership lives in `plugins/intergalactic_windows_share/`.
- Existing desktop video publication still uses the current
  `flutter_webrtc` / LiveKit screen-share path.
- Windows Graphics Capture is represented as a capability/scaffold target; it
  does not replace video capture in this pass.
- Shared-content audio uses Windows Application Loopback as the native target.
  Process-tree loopback is used only when a window can be mapped to a process
  ID; display/system sharing uses system-loopback mode.
- Captured PCM is bridged into Flutter WebRTC through a custom native audio
  source owned by the Windows share plugin. Direct Matrix calls attach that
  track to the screenshare stream; LiveKit calls publish it as a separate
  `screenShareAudio` track.

## Ownership Rules

- RNNoise applies only to microphone capture.
- Shared-content audio must not be mixed into the microphone path by default.
- If shared audio fails, the share continues video-only and reports degraded
  status.
- If video initialization fails, native shared-audio capture must not start.
- Unsupported OS versions or ambiguous window-to-process mapping are safe
  video-only fallbacks.

## Native Plugin Contract

The Windows plugin exposes a narrow FFI surface:

- capability status for Application Loopback and WGC readiness
- visible window/process target enumeration
- explicit create/start/stop/dispose session ownership
- shared-audio capture counters and reason strings
- shared-audio WebRTC stream/track metadata for publication adapters

The publication bridge depends on the Flutter WebRTC Windows plugin being
registered in the same process. If that shared instance is unavailable, or if
Application Loopback is unsupported on the OS build, the session reports
video-only degraded status rather than mixing audio into the microphone path or
failing the whole screenshare.
