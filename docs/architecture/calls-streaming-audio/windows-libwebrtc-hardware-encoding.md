# Windows Libwebrtc Hardware Encoding

Status: Active native streaming architecture reference
Owner: EXPERIMENTAL
Last reviewed: 2026-06-16 by DOCUMENTATION

This note tracks the native dependency work needed for smooth Windows gameplay
streaming.

## Current Boundary

Inter Galactic reaches LiveKit through `livekit_client` and `flutter_webrtc`.
The Windows Flutter WebRTC plugin uses a packaged `libwebrtc.dll`; Dart can
prefer H.264 and clamp sender limits, but the hardware/software encoder choice
still happens inside the native peer-connection factory and the WebRTC binary.

The original hardware-encoding investigation started because Windows gameplay
profiles requested hardware-first H.264 while diagnostics showed `OpenH264`
software encode on a clean direct network path. The current patched path has
moved beyond that initial mismatch: stream-lab and BG3 validation now depend on
the Inter Galactic patched libwebrtc artifact, Windows Media Foundation H.264,
native NV12 input, loaded-artifact hashing, and native encoder timing/fence
diagnostics.

Do not treat this doc as a bitrate/profile tuning guide. Current DX11 streaming
work should verify the loaded libwebrtc artifact, native NV12 input path,
Media Foundation timing, and sender diagnostics before changing app-side
profiles.

## Fork Workspace

Local fork workspace:

- `forks/libwebrtc`
- branch: `intergalactic/windows-hardware-h264`
- commit: `01a72ac Enable Windows hardware H264 encoder factory by default`

This branch enables the wrapper's existing Intel Media SDK / oneVPL-backed
Windows video encoder factory by default for Windows builds and adds explicit
native log lines for factory selection/fallback.

The initial fork patch is intentionally small:

- `BUILD.gn` defaults `libwebrtc_intel_media_sdk` to `is_win`
- `src/rtc_peerconnection_factory_impl.cc` logs whether the Intel Media SDK
  video encoder factory or WebRTC built-in encoder factory is selected
- video decode intentionally stays on WebRTC's built-in decoder factory for
  the first artifact, so stale Intel decoder wrapper code does not block the
  outgoing gameplay-stream encoder proof
- `README.md` documents `libwebrtc_intel_media_sdk=true` in the Windows GN args

This is a first hardware proof path, not the final all-GPU solution. Intel
Media SDK/oneVPL primarily proves Quick Sync style H.264. If a user's machine
has no compatible Intel hardware/runtime, the factory should fall back to the
built-in WebRTC encoder and diagnostics should still say why.

## Build/Packaging Path

The patched dependency cannot affect Inter Galactic until a replacement
`libwebrtc.zip` is built and supplied to Flutter WebRTC.

Expected build shape:

1. Build the patched `webrtc-sdk/libwebrtc` wrapper against the matching
   `webrtc-sdk/webrtc` release branch used by `flutter_webrtc`.
2. Use Windows GN args with H.264 and desktop capture enabled, including:
   `libwebrtc_intel_media_sdk=true`.
3. Produce a `libwebrtc.zip` with the same layout Flutter WebRTC expects:
   `libwebrtc/include/...`, `libwebrtc/lib/win64/libwebrtc.dll`, and
   `libwebrtc/lib/win64/libwebrtc.dll.lib`.
4. Replace Flutter WebRTC's downloaded `third_party/libwebrtc` package during a
   release build only after the strict build proves startup, calls, and screen
   sharing still work.

Current artifact:

- `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
- Native libwebrtc source commit: `e09a684`
- ZIP SHA-256:
  `002779B670C95050387B17D11FEC5864EA31F9C28B0808780651B68176CA4563`
- DLL SHA-256:
  `5D6B8FDF500F7427FA43B79063B985A582B28134117408615BB4E0A5482CA1F3`
- Native build verified with:
  targeted
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`
  rebuild
- Artifact validation checks the packaged
  `libwebrtc/include/rtc_desktop_capturer.h` for the Inter Galactic
  `StartWithMaxFrameSize`, `SetWindowsCaptureBackendMode`,
  `SetLatestFramePacingEnabled`, and
  `SetWindowsCaptureDirtyRegionMode` APIs before installing the zip into
  Flutter WebRTC. It also checks
  `libwebrtc/include/rtc_video_device.h` for `CreateGameCapture`, the
  debug-only Phase 4D game-capture source entry point. This catches stale staged
  headers before the generated bridge reaches a Windows C++ build.
- Current diagnostic additions:
  throttled Media Foundation H.264 encoder timing logs for input conversion,
  buffer copy, `ProcessInput`, drain/`ProcessOutput`, output copy, queue depth,
  and slow-frame detection. The desktop capturer and Media Foundation encoder
  also append these Inter Galactic native timing lines to the bounded sidecar
  `%TEMP%\intergalactic-native-webrtc-diagnostics.log`, which the debug stream
  test runner clears before a run and reads into the report marker section.
- Current desktop-capture acquisition diagnostics:
  `Inter Galactic desktop capture cadence` keeps its existing total
  `avg_capture_call_ms` / `max_capture_call_ms` fields and now appends
  `avg_result_callback_ms`, `max_result_callback_ms`,
  `avg_acquire_wait_ms`, `max_acquire_wait_ms`, and `callback_count`.
  Stream-test reports surface these in JSON and the Native Diagnostic Markers
  table as the `Acquire Wait` column, next to total capture-call time and
  callback frame-work timing.
- Current desktop-capture debug controls:
  stream-test runs can request `default`, `wgc-only`, or `directx-only`
  through an Inter Galactic-only media constraint. The patched Flutter WebRTC
  bridge passes that value to the native desktop capturer before
  `StartWithMaxFrameSize`, and native logs record the selected backend option
  flags so the next report can prove whether WGC or DirectX is carrying the
  low-FPS path. The old `window-crop` backend is hidden from stream tests and
  sanitized out of stream-test configs because BG3 validation showed wrong-
  monitor capture, shredded frames, and crashes at cleanup. The debug
  stream-test dialog can also compare all safe Windows backend overrides for
  every selected preset in one run. This comparison mode is measurement-only
  and does not persist a backend preference.
- Current desktop-capture frame-pacing control:
  normal Windows desktop/window publishes enable the native `latest` frame
  pacer through the Inter Galactic-only
  `intergalacticCaptureFramePacing` media constraint. The native capturer
  stores the newest scaled I420 frame and submits frames on the target cadence
  instead of calling `OnFrame` directly from the capture callback. Stream-test
  runs can still explicitly force the pacer off or on for A/B comparisons.
  Reports parse pacer submitted FPS, unique FPS, p95/max submit interval,
  frame age, `OnFrame` time, duplicate submissions, overwritten frames, and
  skipped ticks so BG3 comparisons can distinguish capture starvation,
  callback pacing, and downstream WebRTC send cadence.
- Current desktop-capture dirty-region diagnostics:
  frame-timing markers append updated-region rect count, max rect count,
  average/max dirty-area ratio, full-frame update count, and tiny-update count.
  Stream-test reports render these as `Dirty Shape` so capture-limited
  gameplay runs can separate full-frame source churn, fragmented dirty regions,
  tiny/no-op updates, and unexplained backend acquisition wait. Explicit Native
  default and WGC-only window/game comparison paths request Force full-frame
  dirty regions. Display paths and DirectX/window-GDI paths keep Auto
  dirty-region behavior.
- Current Windows capture default:
  normal Windows window/game shares now resolve App default to the
  `directx-only` media constraint, which selects WebRTC's `window-gdi` capturer
  for window sources in current builds. Display shares use the patched native
  app default when no debug override is provided. This default controls capture
  backend selection only; encoder choice still comes from the screen-share
  profile/publish path. Explicit Native default, WGC-only, and
  DirectX/window-GDI stream-test overrides remain the comparison path.
- Current Windows window-source publish guard:
  `SourceType.Window` shares publish single-layer when the chosen profile would
  otherwise use simulcast. The guard is app-side and codec-agnostic. The native
  capturer now also emits a stable preset-sized canvas for window sources, so a
  non-borderless client area such as `1920x1048` can publish as `1920x1080`
  with contain-fit content centered inside the canvas rather than crop/stretch
  or a fragile non-16:9 sender shape.
- Current Windows window-source native geometry rule:
  convert from the actual captured `DesktopFrame` buffer size. Log the HWND
  `window_rect` separately, but do not pass the outer rectangle dimensions to
  libyuv as the source buffer size. Borderless windows often make those values
  identical; normal windowed applications often do not.
- Current native encoder order:
  1. Media Foundation hardware H.264 MFT
  2. Intel Media SDK / oneVPL H.264
  3. WebRTC built-in OpenH264 software fallback
- Runtime validation is pending for this window-canvas artifact. A successful
  hardware-first stream should report `engine=MediaFoundationH264` and
  `hw:true` in Inter Galactic diagnostics; a successful normal windowed source
  should also show separate `source`, `window_rect`, contain-fit `content`, and
  preset-sized `pre_encode` native diagnostics.

## Build Script Wiring

The Windows release build path prepares the Windows Flutter WebRTC dependency
after `flutter pub get` and before code generation/build. The normal mode is
`require`: a standard release build must install the patched `libwebrtc.zip` or
fail before building. This keeps normal Windows builds on the hardware-encoder
WebRTC path now that runtime diagnostics have proven
`MediaFoundationH264 hw:true`.

Local maintainer automation may expose convenience flags for selecting a
specific patched `libwebrtc.zip`; keep those script-specific details in
workspace-private release notes unless the helper is part of the public repo.

Use `--no-patched-libwebrtc` only for an intentional stock Flutter
WebRTC/OpenH264 fallback build. `INTERGALACTIC_LIBWEBRTC_MODE=auto` remains a
best-effort escape hatch for unusual local troubleshooting, but it should not
be used for release validation.

The installer script lives at
`intergalactic/scripts/install_patched_libwebrtc.ps1`. It validates the zip
layout, backs up the previous cached Flutter WebRTC zip when hashes differ,
extracts the replacement, and writes
`intergalactic-patched-libwebrtc.json` beside the extracted native dependency.
It computes SHA-256 through `Get-FileHash` when available and falls back to
.NET SHA-256 when the batch-hosted PowerShell environment does not expose that
cmdlet.

The installer also owns Flutter WebRTC Windows source compatibility patches.
The patched Windows `libwebrtc.dll` does not expose flutter_webrtc's optional
media FrameCryptor sender/receiver constructors with the old ABI, and Inter
Galactic uses Matrix room E2EE rather than that optional media encryption path.
The installer therefore keeps `FrameCryptorFactoryCreateFrameCryptor` as a
Windows fail-open stub and clears stale `flutter_frame_cryptor.obj` plus plugin
DLL copies once per source hash when that stub is active. Without this cache
invalidation, a debug or release runner can keep an older
`flutter_webrtc_plugin.dll` that imports missing FrameCryptor entry points and
fails at process launch even though the source patch is already present.

The same installer also patches the resolved Flutter WebRTC Windows desktop
capture bridge after package resolution. `livekit_client` sends
`ScreenShareCaptureOptions` with width, height, and frame-rate constraints, but
Flutter WebRTC `1.2.1` only forwarded the selected desktop source and frame
rate before starting capture. Inter Galactic patches
`common/cpp/src/flutter_screen_capture.cc` so the bridge reads the requested
width/height as maximum pre-encode bounds and calls
`StartWithMaxFrameSize(fps, maxWidth, maxHeight)`. That native path captures
the full source frame, scales it down with contain-fit aspect preservation, and
does not use the `Start(fps, x, y, w, h)` crop-region overload. Display sources
emit exact contain-fit dimensions. Window sources use the requested max size as
a stable canvas and center the contain-fit content inside it. Without this
patch, Smooth can request 720p while the hardware encoder still receives
1440p game frames and reports a CPU limiter; without the window canvas rule,
normal windowed sources can fail when the client-area frame does not match the
outer HWND rectangle.

The native desktop capturer is also the only layer that can prove whether a
low-FPS stream is capture/scaler-limited before WebRTC encode. Its diagnostics
should include the full native source size, requested maximum size, pre-encode
output size, target FPS, emitted native FPS, scale state, and crop-region
state. Dart/LiveKit diagnostics then compare that native line with
`pre_encode_fps`, `encode_fps`, `send_fps`, receiver decode FPS, and render
FPS. The current artifact includes the
`Inter Galactic desktop capture pipeline` native log line for this purpose.
It also emits `Inter Galactic desktop capture frame timing` with average
ARGB-to-I420 conversion, contain-fit scaling, `OnFrame`, full callback, max
callback, and frame count values. The stream-test runner parses those fields so
remaining FPS loss can be assigned to capture acquisition, conversion, scaling,
WebRTC frame delivery, or encoder timing instead of another round of guessing.
The current artifact also emits `Inter Galactic desktop capture frame cadence`
with native submitted FPS, p95/max frame interval, duplicated-frame/stale-reuse
placeholders, wait timeouts, permanent errors, and frame counts. Stream-test
JSON/Markdown reports surface those counters beside the requested/native
backend labels and crop-region state.

As of Phase 4D, the installer also patches the same bridge with a debug-only
game-capture branch. When the app passes
`intergalacticCaptureBackend=game-d3d11-hook-experimental` and a selected
window process id, the bridge creates a normal WebRTC local video track from
`RTCVideoDevice::CreateGameCapture(...)` instead of the desktop capturer. This
branch is only for developer stream tests; normal display/window sharing still
uses the existing WGC/window-GDI desktop-capture path.

Do not use sender stats alone to validate this path. A previous crop-style
patch produced plausible capped sender dimensions while the remote viewer saw
only part of the shared window. Validation must include the visible remote
frame: `2560x1440` capped to `1920x1080` should show the full 16:9 source, and
ultrawide sources should fit inside the cap without crop or stretch.

Default artifact locations checked by the build helper:

- `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
- `{LOCAL_PATCHED_LIBWEBRTC_ZIP}`
- `forks/libwebrtc/artifacts/libwebrtc.zip`
- `intergalactic-app\inter-galactic\artifacts\libwebrtc\windows-hardware-h264\libwebrtc.zip`

## Validation

For the first hardware build, collect call diagnostics while streaming a game.
Pass criteria:

- encoder implementation is no longer `OpenH264`
- hardware flag reports `hw:true`, or native logs show a clear hardware factory
  init failure
- Task Manager shows GPU Video Encode activity during share
- direct UDP / low-loss sessions no longer fall back for software encoder CPU

If the Intel path still reports `OpenH264 hw:false` on a machine with compatible
Intel media hardware, inspect `MediaCapabilities::Get()` and Media SDK runtime
loading first.

If the machine is NVIDIA/AMD-only, the next native patch should add a generic
Windows Media Foundation H.264 encoder factory rather than continuing to tune
Dart sender settings.

## Media Foundation Native Patch

The Media Foundation fork step is now implemented in
`webrtc-build/src/libwebrtc`:

- enumerate H.264 encoders with `MFTEnumEx`
- prefer hardware MFTs before Intel/OpenH264 fallback
- feed NV12 input to the selected MFT
- unlock asynchronous Media Foundation MFTs and drain output from
  `METransformHaveOutput` events instead of calling `ProcessOutput`
  synchronously
- prefix available SPS/PPS sequence headers on keyframes
- convert 4-byte length-prefixed H.264 samples to Annex B when needed
- expose `MediaFoundationH264` and `is_hardware_accelerated=true` through
  WebRTC encoder info when the hardware path initializes
- fall back to WebRTC built-in OpenH264 through WebRTC's software-fallback
  wrapper when Media Foundation init or encode fails

Keep this work in the fork/native layer. Do not hide software fallback by
renaming diagnostics or forcing Dart to assume hardware.

Known first-pass limitations:

- The Media Foundation path is single-layer. Windows hardware-first streaming
  is opt-in through developer stream controls after 2026-05-20 black-stream
  logs showed Media Foundation H.264 senders publishing zero encoded frames.
  Normal presets default back to VP8 until that native timeout is fixed.
- If a future developer override forces simulcast, the Media Foundation encoder
  intentionally fails back to the software encoder rather than pretending it can
  encode multiple layers.
- Runtime validation must still confirm that the selected NVIDIA/AMD driver
  exposes a hardware H.264 MFT that accepts the current WebRTC frame cadence.
- The first Media Foundation artifact selected the patched DLL but still fell
  back to OpenH264 because NVIDIA's async H.264 MFT returned `0x8000FFFF` when
  driven through synchronous `ProcessOutput`. The current artifact fixes that
  boundary by using the async event queue.
