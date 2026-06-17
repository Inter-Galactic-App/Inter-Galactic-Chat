# Game Capture Backend Architecture

Status: Active debug architecture; DX11 BG3 Smooth 720p30 average gate met
twice through the developer-gated D3D11 native NV12 source-adapter branch;
productization remains review-gated by classifier and native-tail follow-up
Owner: EXPERIMENTAL
Date: 2026-06-13
Last reviewed: 2026-06-16 by DOCUMENTATION
Scope: Windows gameplay/window capture, with a BG3 DX11 proof of concept as the
first target.

This document responds to `docs/plans/ModernGameCapture.md`. It records the
debug-only game-capture backend direction. The current app integration promotes
the D3D11 path only for developer-mode Windows game-like app-default window
shares with safe fallback, or for the explicit developer GPU pipeline test mode
used by prolonged BG3 validation; obvious browser/non-game windows keep the
existing window-GDI compatibility path unless a developer explicitly chooses a
D3D11 diagnostic path. It does not change stream profiles, bitrate, codec,
fallback thresholds, receiver policy, or non-developer Windows window/display
capture defaults.

## Current Evidence Summary

As of 2026-06-16, the current DX11/BG3 branch has crossed the average Smooth
720p30 gate twice in live calls. The accepted branch is narrow: already-sized
Inter Galactic D3D11 native NV12 helper frames may bypass only the WebRTC
capturer-level framerate adapter drop when an active sink exists and no
resolution adaptation is required. Normal I420/window capture, dummy NV12
controls, bitrate, receiver policy, LiveKit/SFU, fallback policy, SDR/HDR
settings, queue-depth experiments, and custom encoded-frame handoff remain out
of scope for that branch.

Residual review risk is classifier/report nuance and native
BLT/source-to-submit tail-spike attribution. Earlier evidence below explains
why the D3D11 game-hook path was introduced and why WGC/window-GDI capture
could not be treated as the gameplay solution.

- BG3 window and display tests have clean enough encoder, bitrate, LiveKit,
  network, crop/scaling, and receiver evidence that those are not the current
  primary bottleneck.
- Display capture is not better for active gameplay in the current
  implementation. The WGC path is dominated by map/readback/synchronization
  timing and lands around the same choppy low-FPS band.
- The debug "DirectX" option in the app currently resolves to the observed
  `window-gdi` native capturer for window sources. It is not a true game
  swap-chain hook.
- Full-content `PrintWindow(PW_RENDERFULLCONTENT)` is the only tested
  window-GDI mode that produces visible BG3 content, but it costs roughly
  45-60 ms per native frame. A 30 FPS stream has a 33.3 ms total frame budget,
  so this path is already over budget before encode and send work.
- Plain `PrintWindow` and `BitBlt` variants can be faster, but they are invalid
  for BG3 because they produce black, pointer-only, or low-variance output.
- The contain-fit scaler fixed the previous crop class of bugs. It does not
  solve acquisition cadence because frames are still acquired through
  compositor/window capture into CPU-backed WebRTC desktop frames.

The architecture direction remains true game capture: capture at or near the
rendered backbuffer, keep frames GPU-side as long as possible, and hand a
stable scaled texture/frame into the encoder without a blocking CPU readback in
the hot path.

## Phase 4D Debug WebRTC Source Handoff

Phase 4D adds the first app-publishable handoff, but keeps it debug/developer
gated. The path is selected when a developer stream test requests the
`game-d3d11-hook-experimental` backend, or when developer mode is enabled and a
game-like Windows window share uses app default with no explicit backend
override. Both paths require a resolved process id before the game hook can
start.

Current implementation shape:

- Dart maps the backend to an Inter Galactic-only `getDisplayMedia` constraint:
  `intergalacticCaptureBackend=game-d3d11-hook-experimental` plus
  `intergalacticGameCaptureProcessId=<pid>`.
- App-default backend resolution is intentionally split: developer-mode
  game-like window sources may resolve to the D3D11 hook automatically, while
  obvious browser/non-game windows and non-developer app-default window sources
  resolve to DirectX/window-GDI for compatibility.
- Automatic developer-mode D3D11 selection retries DirectX/window-GDI when the
  target PID cannot be resolved or track creation fails. It also bypasses D3D11
  up front for known browser/non-game title patterns. Explicit
  `game-d3d11-hook-experimental` selections remain diagnostic and fail loudly.
- The developer-only GPU pipeline test mode is stricter than the automatic
  promotion path. For normal Windows window shares it locks Smooth 720p30,
  hardware-H.264 preference, D3D11 game-hook capture, native frame pacing, no
  adaptive fallback, and no stream live-tuning republish. Use it for prolonged
  manual BG3 validation when the run must prove the true GPU/native path rather
  than silently recovering to DirectX/window-GDI or a lower sender profile.
  Capture-request logs should include `gpuPipelineTestMode=true` when this hard
  path is active.
- The patched Flutter WebRTC Windows bridge detects that constraint before
  creating a normal desktop capturer. It creates an `RTCVideoCapturer` through
  `RTCVideoDevice::CreateGameCapture(...)`, starts it, wraps it in a normal
  WebRTC `RTCVideoSource`, creates a standard local video track, and stores the
  capturer in the plugin's existing `video_capturers_` cleanup map.
- The patched libwebrtc wrapper resolves and launches
  `intergalactic_game_capture_helper.exe` with `--external-consumer true`,
  opens the hook shared-texture IPC, samples the latest shared texture at the
  requested FPS, contain-fits to the requested max bounds, converts to I420,
  and emits frames through `VideoCapturer::OnFrame`.
- Normal WGC/window-GDI screen sharing remains unchanged unless this exact
  debug backend is requested or a developer-mode game-like app-default window
  share opts into the safe D3D11 promotion. There is no product-default switch
  in this pass.

Backend-neutral contract slice, 2026-06-13:

- The first `GAME_CAPTURE_MULTI_API_BACKEND_PLAN.md` implementation keeps D3D11
  as the only enabled game-capture source and extracts shared diagnostic
  vocabulary around it before any Vulkan or DX12 work starts.
- `SharedTextureState` now uses contract version `2` and appends
  backend-neutral fields after the existing ring-slot state:
  `sourceApi/sourceApiId`, `sourceFormat/sourceFormatId`, `colorSpace`,
  `syncKind`, `readyState`, and `failureReason`.
- The D3D11 hook publishes those fields from the current DXGI swapchain format
  and shared-texture readiness. The helper host-consumer and publication-handoff
  reports copy them from shared state. The libwebrtc game-capture source emits
  the same fields on `game_capture_webrtc_source` markers and source-smoke JSON.
- Stream-test reports parse the fields into
  `StreamTestNativeDiagnostics.toJson()`, the native frame summary label, and a
  `game-capture backend contract` Diagnostic Coverage Matrix row. A missing row
  on a game-hook run means the rebuilt native artifacts do not yet carry the
  v2 contract fields.
- This slice is diagnostic and compatibility scaffolding only. It does not
  alter stream profiles, fallback policy, bitrate/LiveKit behavior, receiver
  policy, native NV12 enablement, or production source defaults.

Known limitations for this first WebRTC handoff:

- The WebRTC source still keeps the CPU staging/map plus BGRA/R10G10B10A2 to
  I420 conversion as the safety fallback inside libwebrtc. That fallback is an
  intermediate validation path, not the final GPU texture-to-encoder design.
- The June 10 R10 native handoff patch lets BG3's `R10G10B10A2` source attempt
  the existing GPU scale -> BGRA intermediate -> D3D11 video-processor NV12 ->
  `IntergalacticD3D11Nv12Buffer` path after the warmup frames. The
  sync-guarded intro-menu smoke proved `nativeNv12Submitted > 0` and Media
  Foundation `input_path=native_nv12`; the first actual-gameplay smoke found a
  `gpu_nv12_failed reason=video_processor_blt_wait_timeout` fallback boundary,
  and the follow-up ring-slot handoff repaired that continuity issue. The
  latest actual-gameplay candidate sustains `nativeNv12Submitted=836`,
  `nativeNv12Failures=0`, `cpuFallback=0`, and Media Foundation
  `input_path=native_nv12`, but still classifies `frame_pacing_unstable` below
  stable 720p30. The SourceConversion follow-up then removed the remaining
  blocking `native_frame_ready` wait from the live WebRTC source by queuing
  native NV12 conversions into the ring and publishing only the newest slot
  whose event query is already ready. Reports now expose
  `nativeNv12Queued`, `nativeNv12Ready`, `nativeNv12NotReadyPolls`,
  `nativeNv12Overwritten`, and `nativeNv12ReadyDropped` so the next BG3 run
  can tell whether async GPU readiness or later delivery/encoder stages are
  still the first limiter.
- June 8 BG3 Smooth evidence shows the current best debug path feeds the helper
  at a minimum 60 FPS while WebRTC delivery stays at 30 FPS. That removes the
  earlier repeated-frame pattern for 30-second Smooth runs and keeps 60-second
  runs near 30 FPS, but it still crosses the CPU I420 boundary before WebRTC.
  Visible proof and lifecycle success therefore still do not equal full
  game-hook release readiness.
- June 8 Phase 2 diagnostics split those gaps inside the WebRTC source: reports
  now expose source-to-readback-ready, readback-queue-to-map, map-to-I420,
  source-to-I420-ready, and source-to-delivery-queue timings. Use those fields
  to decide whether the next patch belongs in async readback scheduling,
  CPU conversion removal, or delivery-thread handoff.
- The previous local NV12/Media Foundation proof remains the evidence that a
  more direct encoder-shaped GPU handoff is viable. Phase 4D is meant to prove
  LiveKit/WebRTC track semantics, lifecycle cleanup, and visible remote output.
- Helper resolution is debug-build oriented. Packaging the helper/hook beside
  production app artifacts is a later Phase 5/release-hardening task.
- This path currently supports D3D11/DXGI Present-hook targets. Other graphics
  APIs, protected/elevated processes, and anti-cheat-sensitive games must fail
  safely to the older window/display paths until broader API support and policy
  exist.
- The first live attempt published a black stream, so a proof boundary was
  added before changing behavior. The WebRTC source now writes up to two BMP
  proof frames and luma/visibility markers immediately before `ARGBToI420`.
  Proof output lives under `%TEMP%\intergalactic-game-capture-webrtc-proof`.
  The follow-up live test still produced black remote output while the
  pre-I420 proof BMP was visible, full-frame, and color-correct. The current
  native diagnostic boundary therefore adds one post-I420 proof frame by
  reconstructing the exact I420 buffer submitted to WebRTC back into a BMP.
  If the post-I420 proof is black while the pre-I420 proof is visible, the
  failure is in BGRA/R10-to-I420 conversion. If both proof frames are visible
  while the stream is black, the failure is after WebRTC frame submission,
  inside encoder delivery, transport publication, or receiver rendering.

Phase 4D validation status:

- Rebuilt the patched libwebrtc layer with the new game-capture wrapper API.
- Native libwebrtc source commit: `e09a684`.
- Repackaged the patched libwebrtc artifact for debug validation.
- Rebuilt the Debug helper/hook.
- Focused Flutter analyze passed for the Dart bridge files.
- Windows Debug build passed.
- Black-output proof follow-up passed after the first live attempt:
  - patched libwebrtc artifact refreshed
  - Debug runner libwebrtc DLL refreshed
  - focused stream-test runner tests passed
  - Windows Debug rebuild passed
  - stale helper cleanup via named stop event passed
  - inspected a pre-I420 proof BMP from the temporary proof output; the frame
    was visible, full-frame BG3, and color-correct at 1280x720
- Post-I420 proof follow-up implementation status:
  - native libwebrtc rebuild passed after adding the reconstructed-I420 proof
    marker
  - refreshed the patched artifact and staged DLL
  - Flutter WebRTC install passed, the Debug runner DLL matched the staged
    DLL, focused stream-test runner tests passed, and the Windows Debug app
    rebuilt successfully
- June 7 readback-delivery / live-harness follow-up status:
  - a mistaken/frozen BG3 test pair proved the helper lifecycle was clean but
    exposed head-of-line blocking in the scaled-readback ring
  - the retained source behavior submits the newest ready scaled readback
    instead of waiting behind the oldest staging slot, wakes delivery when a new
    scaled frame is ready, and keeps queue wait under the previous blocking
    boundary
  - rejected branches include 60/45/36 FPS helper feeds and WebRTC-side
    source/wall pacers because they did not resolve the visible jitter or they
    hid source cadence
  - final retained reports kept `gpuScaled > 0`, `gpuScaleFailures=0`,
    `cpuFallback=0`, clean hardware H.264, clean route/loss/RTT, and no WebRTC
    quality limitation
  - the final retained path is still not clean: it continues to classify as
    `frame_pacing_unstable` from 100 ms-class native delivery/source-to-submit
    gaps
  - Phase 2 native-stage proof is now implemented in the live WebRTC source and
    parsed by stream-test reports. Exact build fingerprints are kept in the
    private validation evidence bundle, not in this public architecture note.
  - June 8 helper-feed headroom follow-up:
    - native source feed now runs at a minimum `60 FPS` while Smooth delivery
      remains `1280x720@30`
    - patched artifact and Debug runner fingerprints were recorded in private
      validation evidence
    - 30-second BG3 Smooth internal validation report had `gpuScaled=1055`,
      `gpuScaleFailures=0`, `cpuFallback=0`, `repeated=0/1055`, and delivery
      wall gaps `29-37 ms`
    - 60-second BG3 Smooth internal validation report had score `90`,
      `gpuScaled=1962`, `gpuScaleFailures=0`, `cpuFallback=0`,
      `repeated=26/1962`, and no under-half or over-2x delivery gaps
    - next work is one Smooth 720p30 visual/receiver confirmation, then GPU
      NV12 or encoder-compatible handoff and classifier calibration; do not
      treat `gpuScaled > 0` as solved GPU encoder handoff because retained
      reports still show `encoderInput=cpu_i420` and `nativeNv12Submitted=0`
- June 8 app-default promotion:
  - user visual validation described the current D3D11 Smooth path as the best
    Inter Galactic gameplay stream so far
  - developer-mode app-default Windows game-like window sharing now tries the
    D3D11 hook first, then falls back to DirectX/window-GDI if PID resolution or
    track creation fails
  - obvious browser/non-game windows, validated with Opera GX, resolve to
    DirectX/window-GDI unless the D3D11 diagnostic override is explicit
  - stream-test reporting treats app-default Windows game-like window tests as
    an effective D3D11 envelope while preserving the requested backend value as
    `App default`; browser/non-game window tests keep the normal compatibility
    envelope
  - production/default user-facing game-capture UI, explicit consent, and
    GPU NV12 / encoder-compatible handoff remain future work

## Why PrintWindow/GDI Has Capped Out

The current valid window path depends on Windows asking a window/compositor path
to produce a capture image. For BG3, only full-content `PrintWindow` produces a
visually valid frame. The latest diagnostics split that path into GDI substages
and show the dominant cost inside the full-content print call itself, not in
the later scaler, WebRTC frame delivery, encoder, bitrate, or network path.

This is the wrong primitive for high-motion gameplay:

- It captures a window image after the game has already rendered and presented.
- It can require a compositor/app repaint or equivalent synchronization.
- It returns CPU-readable content for the existing WebRTC desktop-frame path.
- It cannot reliably observe all game content if the game renders through
  swap-chain surfaces that are not represented by ordinary GDI painting.

The invalid faster modes prove the boundary. `BitBlt` and plain `PrintWindow`
can make the numbers look better, but they do not capture the game. They should
remain diagnostic evidence, not production candidates.

## Why Current Display/WGC Is Not Enough

Windows Graphics Capture is a modern API, but Inter Galactic's current use of
it still flows through the patched WebRTC desktop-capture path and CPU-backed
frame delivery. Current diagnostics show WGC window/display work dominated by
`map_texture`/readback/synchronization timing for the tested gameplay cases.

WGC remains valuable:

- It is consent-based and does not require process injection.
- It is suitable for normal display sharing and many application windows.
- It is the safer fallback for unsupported games or protected processes.

It is not enough as the final answer for BG3-style active gameplay in the
current pipeline because the expensive part is not merely the API choice. The
current implementation still maps or copies captured GPU content into a CPU
frame before WebRTC publication. A future GPU-only WGC path may be useful for
display sharing, but it should be treated as a separate backend from game
swap-chain capture.

## What OBS And Modern Apps Do Differently

OBS's game-capture source architecture shows the shape Inter Galactic is
missing.

Relevant OBS source anchors:

- `plugins/win-capture/game-capture.c`
- `plugins/win-capture/inject-helper/inject-helper.c`
- `plugins/win-capture/graphics-hook/graphics-hook.h`
- `plugins/win-capture/graphics-hook/graphics-hook.c`
- `plugins/win-capture/graphics-hook/dxgi-capture.cpp`
- `plugins/win-capture/graphics-hook/d3d11-capture.cpp`
- `plugins/win-capture/graphics-hook/d3d12-capture.cpp`
- `plugins/win-capture/graphics-hook/vulkan-capture.c`
- `plugins/win-capture/graphics-hook/gl-capture.c`
- `shared/obs-hook-config/graphics-hook-info.h`
- `shared/obs-shared-memory-queue/shared-memory-queue.h`
- `plugins/obs-nvenc/nvenc-d3d11.c`
- `plugins/obs-ffmpeg/texture-amf.cpp`

The pattern is:

1. The app selects a target process/window and starts a helper/injector.
2. A hook DLL is loaded into the target process.
3. For DXGI/D3D11, the hook attaches to `IDXGISwapChain::Present`,
   `IDXGISwapChain1::Present1`, and resize paths.
4. On present, the hook grabs the swap-chain backbuffer.
5. The hook copies or resolves the backbuffer into a shared D3D11 texture.
6. The host app opens that shared texture and uses IPC/events/mutexes to know
   when a frame is ready.
7. A shared-memory fallback exists, but the preferred path is shared texture
   capture, not CPU readback.
8. Hardware encoder integrations can consume GPU textures through D3D11/DXGI
   interop patterns instead of forcing every frame through CPU memory.

That architecture is fundamentally different from asking the desktop capturer
to produce a CPU image of a window. It captures the game output at the swap
chain boundary.

## Candidate Backend Options

| Option | Fit | Benefits | Risks / Limits |
| --- | --- | --- | --- |
| D3D11 Present hook | Best MVP fit for BG3 DX11 | Captures the actual backbuffer, can use shared D3D11 textures, avoids `PrintWindow`, lower CPU readback risk | Requires injection/helper DLL, anti-cheat review, bitness/elevation handling, resize/device-loss handling |
| D3D12 hook | Future high-value path | Covers modern DX12 games, can share GPU surfaces through D3D11On12 or explicit interop | More complex queue/fence/backbuffer tracking; OBS uses extra queue hooks and D3D11On12 bridging |
| Vulkan hook/layer | Future broad game support | Covers Vulkan games and can use external-memory interop | Requires Vulkan layer/hook architecture, swapchain/image tracking, more packaging and compatibility work |
| OpenGL hook | Low priority | Covers older GL games | Smaller target set, WGL interop complexity, fallback likely enough for many cases |
| GPU-only WGC/DXGI path | Good display/window fallback candidate | No injection; consent-based; can improve display capture if kept GPU-side | Current Inter Galactic WGC maps/readbacks; does not directly capture game swap chains; may still be compositor-paced |
| Vendor capture APIs | Not MVP | Potentially fast on specific GPUs | Vendor-specific, licensing/support limitations, inconsistent availability, not a cross-vendor baseline |

## Recommended MVP

Build a debug-only D3D11 Present-hook proof of concept for BG3 DX11.

The MVP should be intentionally narrow:

- Windows only.
- Developer/debug only.
- Explicit user consent before injection.
- Target a selected window/process with a resolved PID.
- Start with D3D11/DXGI Present/Present1 and ResizeBuffers hooks.
- Prefer shared D3D11 texture transport.
- Keep current window-GDI/WGC paths as fallback.
- Do not make it a production default until security, compatibility, and crash
  behavior have been reviewed.

The first proof point is not "ship full game capture." The first proof point is
that the app can capture BG3 DX11 at a present-backed cadence with lower
p95/max frame gaps than full-content `PrintWindow` and current WGC.

## Phase 2 Local POC Status

Phase 2 implements the first native proof as a standalone local helper/hook
under:

```text
plugins/intergalactic_game_capture/
```

The prototype is intentionally not wired into the Flutter app package or
LiveKit. That avoids colliding with active package/generated-file work and keeps
the first validation focused on the game-capture boundary itself.

Current debug built artifacts:

```text
plugins/intergalactic_game_capture/windows/build/Debug/intergalactic_game_capture_helper.exe
plugins/intergalactic_game_capture/windows/build/Debug/intergalactic_game_capture_hook64.dll
```

The helper accepts a selected target PID, validates that the target is an
accessible 64-bit process, writes hook config, injects the hook DLL, signals
stop, waits for the hook to restore its vtable entries, and attempts remote
`FreeLibrary`. The hook patches `IDXGISwapChain::Present` and
`IDXGISwapChain1::Present1`, detects D3D11 by opening the swap-chain
backbuffer's D3D11 device, copies/resolves the backbuffer into a three-slot
D3D11 texture ring, saves a few local PNG frames plus `preview.html`, and
writes `metadata.json`, `present-events.jsonl`, `summary.md`, `hook.log`, and
`helper.log`.

The local PNG proof path supports ordinary BGRA/RGBA 8-bit backbuffers and
BG3's observed `R10G10B10A2_UNORM` backbuffer by converting the diagnostic
readback to 8-bit RGBA before writing PNGs. That conversion is deliberately
limited to proof-frame export; the shared texture ring remains in the source
backbuffer format for future GPU-side handoff work.

The local publication handoff probe also records D3D11 video-processor format
support for BGRA/R10 inputs and NV12/P010 outputs. On the 2026-06-10
SourceConversion pass, the local adapter reported support for BGRA -> NV12,
R10 -> NV12, and R10 -> P010; synthetic R10/HDR-like proof runs then produced
visible NV12 frames and Media Foundation H.264 output at 720p30 and 1080p30.

The helper also supports cadence-only runs with `--max-saved-frames 0`. That
keeps the hook path installed and still records Present cadence, copy/resolve
timing, dropped/overwritten frames, and metadata, but skips local PNG readback
so proof-frame export does not distort p95/max gap measurements. The default
remains five proof frames for "can we see the game?" validation.

Output lives under the configured local game-capture results directory. Keep
exact result paths and build hashes in private workspace evidence, not in this
public architecture note.

This is still a diagnostic prototype. It does not publish frames, replace
window-GDI/WGC, alter stream profiles, or change default capture behavior.

## Phase 3A Stream-Test Probe Status

Phase 3A wires the standalone helper into the app's debug stream-test reporting
path as a local probe only. When enabled from the developer Stream Test Runner
dialog, the runner uses the selected window source process id, launches
`intergalactic_game_capture_helper.exe` with `--max-saved-frames 0` by
default, points the helper at the app's normal `stream-tests` log area, parses
the emitted `metadata.json`, and adds a `Game Capture Probe` section to the
stream-test JSON, Markdown, and diagnostic coverage matrix.

This integration deliberately does not call the probe a publish backend. A
probe-only run can collect D3D11 Present cadence without calling the LiveKit
screen-share publish path. A normal stream-test run starts the probe
concurrently with the initial preset measurement window after source selection,
then includes the hook evidence beside WGC/window-GDI sender diagnostics. The
probe duration is extended to cover the first preset's warmup plus measured
sample window so the selected game's Present cadence and the published
desktop/window-capture cadence are comparable in the same time slice. If the
helper is missing, the selected source has no process id, the target is
unsupported/elevated, or the platform is not Windows, the report records
`unavailable` or `notApplicable` rather than crashing.

The interpretation boundary is:

- Healthy D3D11 Present cadence proves the game swap-chain itself can deliver
  frames smoothly enough for the requested cadence.
- It does not prove that Inter Galactic can publish those frames yet.
- If normal WGC/window-GDI stream diagnostics remain choppy while the local
  D3D11 probe is healthy, the next bottleneck is the desktop/window capture
  acquisition or future GPU-to-encoder handoff, not the game render cadence.

## Phase 3B Host Shared-Texture Consumer Status

Phase 3B adds a debug-only host consumer proof to the existing helper/hook
path. It still does not publish frames to LiveKit.

The helper now creates a frame-ready event plus a shared-state mapping before
injecting the hook. The hook writes the shared D3D11 texture ring handles,
latest frame index, slot index, QPC timestamp, copy/drop/overwrite counters,
and backbuffer metadata into that mapping after each Present copy, then signals
the frame-ready event. When enabled by the stream-test runner, the helper opens
those shared textures from the host side, observes frame signals, measures host
frame age and consumer gaps, records duplicate/missed frames, and writes
`host-consumer.json` / `host-consumer.md` beside the normal helper metadata.
The Dart stream-test parser merges that host-consumer result into the
`Game Capture Probe` JSON and Markdown sections.

This is the first proof that the Inter Galactic-controlled host side can open
and observe the D3D11 hook texture ring. It is intentionally not yet a Flutter
renderer, WebRTC video source, or encoder handoff. Optional proof readback is
limited to a small diagnostic count and is reported separately so CPU readback
does not get mistaken for the production path.

New report evidence includes:

- host consumer enabled/healthy state
- shared state and D3D11 host-device availability
- opened shared texture slots and open failures
- observed frame signals versus consumed frames
- duplicate and missed frame counts
- host frame age avg/p95/max
- host consumer gap p50/p95/max
- optional proof readback count, visible proof count, and readback timing

Interpretation boundary:

- Healthy Present cadence plus a healthy host texture consumer means Phase 3B
  is working and the next implementation target is a dedicated game-capture
  video source / encoder handoff.
- Healthy Present cadence with a failed host consumer means the next fix is
  shared-handle/device/synchronization compatibility, not LiveKit or bitrate.
- A healthy host consumer still does not prove remote stream quality until
  later phases prove a publication-shaped buffer, local encoder handoff, and
  then a real WebRTC/LiveKit video source.

## Phase 4A/4B Local Publication-Handoff Probe Status

Phase 4A adds a debug-only local handoff processor to the existing helper host
consumer. It is deliberately not a WebRTC source and it does not publish frames
to LiveKit.

When `--publication-handoff true` is enabled, the helper opens the shared D3D11
texture ring from Phase 3B, samples the latest frame at the requested target
FPS, scales the full source image with contain-fit rules into an
even-dimension BGRA output target, and records whether the output buffer has
non-flat visible content. Phase 4A originally read back the full source and
then CPU-scaled; Phase 4A.5 moved the diagnostic path to GPU scale first and
read back only the scaled output for proof. Phase 4B adds a debug-only NV12
probe: the helper converts the scaled BGRA output through the D3D11 video
processor into `DXGI_FORMAT_NV12`, records conversion/proof counters, and keeps
continuous CPU readback out of the measured handoff path. The stream-test
runner enables this probe by default when the game-capture probe is enabled and
sets the handoff target from the first tested preset: Smooth requests
1280x720 at 30 FPS, Balanced requests 1920x1080 at 30 FPS, and High Quality
requests 1920x1080 at 60 FPS.

New report evidence includes:

- publication handoff enabled/healthy state
- requested max width/height and target FPS
- source texture width/height/format
- contain-fit output width/height, output format, encoder format, and scale
  mode
- input frames observed, output frames produced, visible output frames, and
  paced-drop count
- output FPS and p50/p95/max output gaps
- frame age avg/p95/max
- readback, scale, and total handoff timing avg/p95/max
- NV12 texture creation, output frame count, conversion failures, conversion
  timing, and visible NV12 luma proof count
- handoff mode, shared-state/D3D/opened-texture state, and last error

Interpretation boundary:

- Healthy Present cadence, healthy host consumer, healthy publication handoff,
  and zero NV12 conversion failures means the game-hook path can produce
  encoder-shaped local frames at the requested preset cadence. The next
  implementation target is an encoder-fed local proof and then, only later, a
  real WebRTC/LiveKit video source.
- Failed publication handoff with healthy Present/host consumer means the next
  fix is local texture readback/scale/buffer pacing, not bitrate, LiveKit, or
  stream profiles.
- A healthy Phase 4A/4B/4C still does not prove remote stream quality because
  the normal sender remains WGC/window-GDI until a later WebRTC/LiveKit source
  publishes these frames.

First runtime validation note:

- The first user-run Phase 4A test proved healthy D3D11 Present cadence and a
  healthy host shared-texture consumer while the normal window-GDI sender
  stayed capture-limited. It did not prove publication handoff because the
  helper crashed or was stopped before writing `publication-handoff.json`.
  Follow-up code keeps the runner watchdog outside the native teardown budget,
  fixes the handoff writer's p95 percentile inputs, and adds helper shutdown
  breadcrumbs so missing handoff files identify the exact end-of-run boundary.
- The next user-run Phase 4A test proved the writer repair and showed visible
  handoff output, but only at about 10.7 FPS for a 30 FPS target. The measured
  cost was full-source CPU readback plus CPU scaling, not D3D11 Present or host
  shared-texture consumption. Phase 4A.5 now measures GPU contain-fit scale
  before scaled-output readback and reports visible-but-below-target handoff as
  `slow`, not `healthy`.
- Phase 4B synthetic NV12 validation repaired the target-side proof stall by
  publishing shared-frame state before optional hook PNG export and by making
  hook-side staging maps non-blocking. `local-capture-20260604-200640`
  produced about 31.9 handoff FPS at 1280x720@30, 154 NV12 output frames, zero
  conversion failures, one visible publication proof frame, and one visible
  NV12 luma proof.

## Phase 4C Local Encoder Proof Status

Phase 4C adds a debug-only local encoder proof to the same helper. It still
does not publish to LiveKit or replace normal WGC/window-GDI capture.

When `--publication-encoder-proof h264-mf` is enabled with NV12 output, the
helper creates a local Media Foundation H.264 MP4 sink writer, attaches the
D3D11 device manager, requests hardware transforms, copies the scaled NV12
handoff texture into an encoder-ring texture, wraps that texture in a DXGI
surface buffer, and calls `WriteSample` with explicit sample time and duration.
The helper writes encoder-proof lifecycle, error, frame-count, byte-count,
submit, GPU-copy, initialization, and finalize timing fields into
`publication-handoff.json`.

Visible proof frames and encoder proof are intentionally separate. The local
PowerShell harness rejects `PublicationEncoderProof=h264-mf` when
`PublicationProofFrames` is greater than zero, because PNG/readback proof work
would contaminate encoder timing. To inspect pixels, run a separate
non-encoder proof pass.

Synthetic validation:

- `local-capture-20260604-204405`: 1280x720 -> 1280x720@30 submitted 144
  encoder-proof frames, zero write failures, about 0.063 ms average submit
  time, and a 4.6 MB MP4 proof.
- `local-capture-20260604-204425`: 1920x1080 -> 1920x1080@30 submitted 145
  encoder-proof frames, zero write failures, about 0.065 ms average submit
  time, and a 9.6 MB MP4 proof.
- `local-capture-20260604-204446`: 1920x1080 -> 1920x1080@60 submitted 277
  encoder-proof frames, zero write failures, about 0.051 ms average submit
  time, and a 13.9 MB MP4 proof.
- `local-capture-20260604-204830`: separate non-encoder proof still wrote a
  visible NV12 publication proof frame after the encoder path was added.

Live BG3 validation:

- `local-capture-20260604-210942`: live BG3 DX11 proof-only validation
  produced 1280x720 NV12 output from the actual 2560x1440 source, wrote
  3 / 3 visible publication proof frames, wrote 3 / 3 visible NV12 luma proof
  frames, and recorded zero NV12 conversion failures. A proof image was
  inspected and remained full-frame and color-correct.
- `local-capture-20260604-210855`: live BG3 DX11 2560x1440 -> 1280x720@30
  local H.264 encoder proof submitted 281 frames, recorded zero write
  failures, produced about 29.9 handoff FPS, held output p95/max gaps near
  39.5/45.1 ms, and averaged about 0.069 ms per encoder submit.
- `local-capture-20260604-211322`: live BG3 DX11 2560x1440 -> 1920x1080@30
  local H.264 encoder proof submitted 281 frames, recorded zero write
  failures, produced about 30.1 handoff FPS, held output p95/max gaps near
  39.4/42.9 ms, and averaged about 0.068 ms per encoder submit.

Interpretation boundary:

- Healthy synthetic Phase 4C evidence proves scaled NV12 GPU output can feed a
  local H.264 encoder proof without the old continuous readback bottleneck.
- Healthy live BG3 Phase 4C evidence now proves the same local encoder
  boundary for the known 2560x1440 BG3 DX11 source at 720p30 and 1080p30.
- It does not prove remote stream quality until a later WebRTC/LiveKit video
  source consumes these frames.

## Where To Implement

### Native Patched Libwebrtc Layer

Current anchor files live in the patched libwebrtc fork around the desktop
capturer interface, desktop capturer implementation, and peer-connection
factory wrapper.

The existing `RTCDesktopCapturer` path is a desktop/window capturer. It should
not be stretched into a game-hook system by overloading `Start()` or
`StartWithMaxFrameSize()`.

Add a separate Windows game-capture native subsystem that can eventually feed a
WebRTC video source. Early prototypes may live near the patched libwebrtc
bridge for build/package simplicity, but the API boundary should say "game
capture" rather than "desktop capture."

### Flutter Bridge / API

Current anchor files:

- `intergalactic/lib/client/components/voip/windows_screen_capture_backend.dart`
- `intergalactic/lib/client/matrix/components/voip_room/matrix_livekit_voip_session.dart`
- `intergalactic/scripts/install_patched_libwebrtc.ps1`

Add a distinct backend mode for game capture, for example
`gameD3d11HookExperimental`. Do not reuse the current `directxOnly` name, since
that mode currently maps to native window-GDI for tested window sources.

The bridge should pass:

- target PID
- target window handle or source ID
- requested max width/height/FPS
- requested contain-fit behavior
- allowed fallback policy
- diagnostics/session ID

It should receive:

- attach status
- active graphics API
- source size and output size
- frame cadence
- fallback reason
- hook crash/device-loss status

### Source Picker / Backend Selection

Current anchor files:

- `intergalactic/lib/client/components/voip/webrtc_screencapture_source.dart`
- `intergalactic/lib/client/components/voip/share_session.dart`

The source picker already resolves window/display sources and often resolves a
window process ID. Game capture should be an explicit option for compatible
window sources, not an invisible replacement.

Proposed behavior:

- Keep ordinary screen/window share unchanged by default.
- Show a developer-only "Game capture experimental" backend choice when a
  source has a process ID and the platform is Windows.
- Redact titles/process details in normal logs; include them only when
  developer diagnostics are enabled.
- If attach fails or the target is protected/elevated/unsupported, fall back to
  current WGC/window-GDI only with a visible diagnostic reason.

### Stream-Test Runner Support

Current anchor file:

- `intergalactic/lib/client/components/voip/stream_test_runner.dart`

The runner should add a future backend mode for the D3D11 hook and parse the
new diagnostics into the existing JSON/Markdown coverage system.

Current implemented WebRTC-source behavior:

- The D3D11 game-hook WebRTC source publishes only unique source-frame indices.
  If the source has not presented a new frame on a scheduled sender tick, the
  source increments `duplicateSkipped` and drains any ready GPU readback without
  resubmitting the previous frame. This avoids manufactured repeated frames and
  the rubber-band/stale-frame look that showed up when a 30 FPS BG3 scene was
  driven by a higher sender tick rate.
- `repeated` is reserved for actual repeated submissions and should remain
  zero in the healthy game-hook path. `duplicateSkipped` may be nonzero when a
  preset requests a higher FPS than the game is presenting, especially High
  Quality `60 FPS` tests against 30 FPS game scenes.
- The stream-test runner parses `duplicateSkipped` into JSON/Markdown and uses
  it to distinguish source-present cadence limits from capture-backend
  failures. Healthy 30 FPS BG3 Smooth/Balanced runs should show
  `gpuScaled > 0`, `gpuScaleFailures=0`, `cpuFallback=0`, `repeated=0`,
  `sourceFrameDuplicates=0`, `sourceFrameRegressions=0`, and
  `sharedSlotMismatches=0`. The June 7 live-harness loop proved those counters
  are necessary but not sufficient: early/middle/late/tail windows, p95/max
  native delivery gaps, and source-to-submit latency must also stay clean.

Required future fields:

- requested game-capture backend
- hook attach status and error code
- target PID hash and process architecture
- detected graphics API
- present FPS and present p50/p95/max gaps
- backbuffer width/height/format
- shared texture ring depth
- frames copied, dropped, overwritten, or duplicated
- GPU copy/resolve/scale/convert timing
- CPU readback count, which should be zero on the target path
- fallback reason
- WebRTC/encoder handoff mode

## Proposed Native Architecture

### Controller

The Inter Galactic process owns the capture session lifecycle:

- validates user consent and selected target
- starts helper/injector
- opens IPC endpoints and shared resources
- watches keepalive and target process exit
- exposes diagnostics to Dart
- detaches on call end, stream stop, source switch, crash, or timeout

### Injector / Helper Process

The helper is responsible for loading the hook DLL into the target process.

Requirements:

- match target process architecture where needed
- avoid protected/elevated targets unless explicitly allowed and reviewed
- use narrow command arguments: target PID, session ID, IPC names, and flags
- report injection result through a redacted status channel
- never silently inject into unrelated processes

### Hook DLL

The D3D11 MVP hook DLL should:

- attach to DXGI Present/Present1 and ResizeBuffers paths
- detect D3D11 swap chains
- obtain the current backbuffer
- resolve multisampled buffers when required
- copy into a shared D3D11 texture ring
- signal frame availability through event/IPC
- track device lost, resize, format change, and process exit
- fail closed to "no game-hook frame" rather than returning corrupt content

### Shared Texture / Ring Buffer

Use a small ring, likely 2-3 textures, similar to OBS' multi-buffer design.

Each slot should contain:

- shared D3D11 texture handle
- keyed mutex or equivalent synchronization primitive
- frame index
- source timestamp / present timestamp
- source width/height
- texture width/height
- DXGI format
- color space / HDR flag when known
- dirty/full-frame flag if available
- valid/overwritten/dropped flags

Shared memory should be a fallback only. The target product path should keep
frames GPU-side.

### IPC / Control Channel

Use named pipe/events/shared mapping or a similar Windows IPC boundary.

Control messages should cover:

- start/stop
- target lost
- hook ready
- frame ready
- resize/device lost
- fallback requested
- diagnostics snapshot
- keepalive

IPC payloads must not include private window titles unless developer
diagnostics are enabled. Process IDs should be logged as short hashes in normal
diagnostics.

### Fallback Path

Fallback remains necessary and must be explicit:

- if the target uses an unsupported graphics API, fall back to WGC/window-GDI
  with a reason
- if injection is blocked, fall back with a reason
- if anti-cheat/protected process is detected, do not inject
- if the hook crashes or misses keepalive, detach and fall back or stop
- never silently switch to a faster but visually invalid `BitBlt`/plain
  `PrintWindow` path

## GPU-Side Frame Pipeline

The target pipeline should be:

```text
game swap chain present
-> hook obtains backbuffer
-> GPU resolve/copy to shared D3D11 texture
-> Inter Galactic opens shared texture
-> GPU contain-fit scale to profile bounds
-> GPU color convert to encoder-preferred format when possible
-> WebRTC / Media Foundation encoder handoff
-> RTP publish
```

### Texture Acquisition

For D3D11, the hook can obtain the swap-chain backbuffer on Present/Present1.
If the backbuffer is multisampled, resolve it before sharing. Otherwise copy
or copy-subresource into the ring texture.

### Scaling, Cropping, And Letterbox

The rules from the existing scaler remain:

- preserve aspect ratio
- do not crop normal gameplay capture
- do not stretch
- scale down before encode
- for 2560x1440 to 1920x1080, output 1920x1080
- for ultrawide, fit within the cap, such as 3440x1440 to 1920x804
- letterbox/pillarbox only if the encoder/publication path requires a fixed
  canvas

Scaling should be done by GPU shader or video processor before encode, not by
forcing the full source through CPU I420 conversion.

### Color Conversion

Most game backbuffers will be BGRA/RGBA or HDR formats. The encoder path
usually wants NV12/P010 or I420-like input.

Preferred order:

1. GPU convert to NV12/P010 for hardware encoder paths.
2. If WebRTC requires CPU I420 for an early POC, read back only the already
   scaled frame and mark the mode as CPU-readback POC.
3. Do not treat the CPU-readback POC as the production goal.

### WebRTC / Encoder Handoff

Current Inter Galactic WebRTC desktop capture hands CPU I420 frames into
WebRTC. The hardware H.264 work already improved encoder selection, but the
desktop capture source still reaches the encoder as CPU-backed frames.

The game-capture backend should move in two phases:

1. POC phase: D3D11 hook -> shared texture -> optional scaled CPU readback ->
   existing WebRTC video source. This proves capture cadence while still
   exposing readback cost.
2. Product phase: D3D11 hook -> shared texture -> GPU scale/convert ->
   hardware encoder or WebRTC texture-backed video frame path. This is the path
   expected to remove the current map/readback acquisition limiter.

The product phase likely needs native work beyond the existing
`RTCDesktopCapturer` interface, either by adding a texture-backed WebRTC video
source path or by handing D3D11 textures into Media Foundation with an encoder
device manager / DXGI device path.

As of the June 5 debug WebRTC source pass, the POC publication path has one
important optimization: the live `game-d3d11-hook-experimental` WebRTC source
uses shader-resource sampling to draw the source shared texture into the
requested output-sized BGRA render target before staging readback. The earlier
D3D11 video-processor input-view attempt failed on BG3 with
`input_view_create_failed hr=0x80070057`, so the source now follows the
helper-proven SRV/full-screen-triangle path instead. It still hands CPU I420
frames to WebRTC, so it is not the final product texture-backed path, but it
should avoid mapping and CPU-scaling the full 2560x1440 source for Smooth
720p. Reports must use the parsed `gpuScaled`, `gpuScaleFailures`,
`cpuFallback`, and `gpuScaleMs` fields to prove whether this path is active.
Local source smoke has proven the synthetic D3D11 case with nonzero
`gpuScaled` and zero `cpuFallback`; BG3 live validation remains the next gate.

## Security And Compatibility Risks

### Anti-Cheat

Injection and Present hooks are sensitive. They can be blocked or flagged by
anti-cheat systems. The feature must be opt-in, developer-gated at first, and
denylisted for known protected/competitive titles until reviewed.

### Admin / Elevation

A non-elevated app cannot safely inject into elevated targets. The MVP should
detect this and fail with a clear unsupported/elevation reason. It should not
request elevation automatically.

### Process Architecture

32-bit and 64-bit targets need matching helper/hook support. The MVP can start
with 64-bit only if diagnostics make that explicit.

### Overlays

OBS exposes overlay capture ordering because capturing before or after overlay
render changes what users see. Inter Galactic should record and eventually
surface whether overlays are included. MVP can default to the simplest stable
ordering as long as diagnostics say what happened.

### Crashes And Device Loss

The hook must survive or cleanly detach on:

- swap-chain resize
- fullscreen/windowed transition
- device lost / removed
- target process exit
- app stream stop
- call end
- helper process crash

The fallback must not leave hooks installed after the stream stops.

### Privacy / Consent

Game capture should require explicit user consent per session. Normal
diagnostics must hash source/process identifiers and avoid raw titles unless
developer diagnostics are enabled. Hook logs should not be automatically
attached to bug reports if they contain private process/window details.

## Validation Plan

### BG3 DX11 Proof Of Concept

Use BG3 DX11 as the first target because it is the known reproducible case where
`PrintWindow` is valid but too slow and WGC/display is not enough.

Required comparisons:

- current App default / observed `window-gdi`
- current WGC window path
- current display/WGC path
- new D3D11 hook backend

Required metrics:

- unique FPS
- submitted/captured FPS
- p50/p95/max frame gaps
- source present p50/p95/max gaps
- hook copy/resolve time
- shared texture queue depth
- dropped/overwritten frame counts
- CPU readback count and timing
- GPU scale/convert timing when present
- encoder FPS and encode time
- send FPS
- packet loss, RTT, jitter, NACK/PLI/FIR
- visible remote frame validation

Success for the MVP is not perfect 1080p60. The first success target is a
stable visible BG3 stream with capture p95/max gaps substantially lower than
full-content `PrintWindow`, no crop/stretch, and no network/encoder regression.

### Compare Against Current Window-GDI

The D3D11 hook should beat the valid full-content `PrintWindow` path on p95/max
capture gaps. Plain `PrintWindow` and `BitBlt` are invalid controls only.

### Compare Against Display/WGC

The hook should also beat current WGC map/readback dominated runs for active
gameplay. WGC can remain the safer fallback when hook capture is not allowed.

### Visual Validation

Sender stats alone are not enough. Each validation run must include remote or
loopback visual confirmation because previous fast paths produced pointer-only
or black output while numeric FPS looked better.

## Implementation Phases

### Phase 1: Architecture And Source Discovery

- Keep this report as the starting architecture record.
- Add game-capture fields to the stream diagnostic contract before native
  probes are added.
- Inventory exact build/package requirements for helper process and hook DLL.
- Decide whether the first prototype lives under patched libwebrtc or a
  sibling native Windows plugin that feeds a WebRTC source.
- Phase 1 readiness is captured in
  `docs/plans/D3D11_GAME_CAPTURE_POC.md`.

Exit criteria:

- No behavior changes.
- Diagnostic contract updated for game-capture fields.
- Prototype file ownership and build packaging agreed.

### Phase 2: Debug-Only D3D11 Hook Prototype

- Add a 64-bit debug-only helper and hook DLL.
- Attach to a selected BG3 DX11 process/window.
- Hook Present/Present1 and resize.
- Copy backbuffer into a shared D3D11 texture ring.
- Expose cadence/metadata diagnostics.
- Do not publish to LiveKit yet if local validation is easier first.

Exit criteria:

- Hook attaches and detaches cleanly.
- Captured frames are visible in a local debug preview or saved diagnostic
  frames.
- Present cadence and copy timing are measured.

### Phase 3: Shared Texture To App

- Open shared texture handles in the Inter Galactic process.
- Add synchronization/queue depth diagnostics.
- Add GPU scale/contain-fit prototype.
- Add optional CPU-readback POC only for measurement, clearly labeled as such.

Exit criteria:

- The app receives valid frames from the game process.
- The path can prove whether CPU readback is avoided or still present.

Current implementation note: Phase 3B proves shared-texture consumption in the
Inter Galactic-controlled helper/stream-test path and reports that evidence to
the app. Phase 4A adds a local paced BGRA publication-handoff buffer from that
texture ring. Phase 4D adds the first debug-only WebRTC video source that
consumes the hook shared-texture ring and publishes it as a normal local video
track when explicitly selected by a developer stream test.

### Phase 4: WebRTC Publication

Current implementation note: Phase 4A/4B/4C measured local
publication-handoff readiness. The helper can produce a paced contain-fit BGRA
buffer, convert it to an encoder-compatible NV12 texture, and feed that NV12
texture into a local Media Foundation H.264 proof sink. Phase 4D adds a
debug-only WebRTC video-source handoff through the patched Windows
Flutter WebRTC/libwebrtc bridge. This first handoff still stages/maps to CPU
I420 inside the custom capturer, so it is not the final direct GPU encoder
handoff.

Renderer compatibility note: the first native-NV12 in-app BG3 validation
crashed in Flutter's local video texture renderer because the renderer path was
handed native frames it could not safely convert. The current crash-guard build
preserves native frames for the sender/encoder path, but converts
renderer-bound native frames to I420 and guards failed native conversions before
they reach Flutter texture rendering. This does not change the GPU-first
production target; it keeps local preview/UI rendering from becoming the crash
boundary while encoder handoff is validated.

Native-frame lifetime note: the June 9 handoff repair keeps the GPU NV12
source path enabled but no longer wraps reusable scratch-ring textures directly
as WebRTC native frames. The D3D11 video processor writes to the scratch NV12
ring, then the source copies that surface into a per-frame-owned NV12 texture
before constructing `IntergalacticD3D11Nv12Buffer`. This keeps Media
Foundation/WebRTC encoder input GPU-resident while preventing asynchronous
encoder consumption from racing with later scratch-ring reuse.

- Feed frames into WebRTC/LiveKit through a dedicated game-capture video source.
- Prefer texture/hardware-encoder handoff.
- Keep current CPU I420 path only as an intermediate POC fallback.
- Preserve existing sender limits, aspect ratio rules, and diagnostics.

Exit criteria:

- BG3 DX11 can be published through LiveKit from the new backend.
- Reports include game-capture backend coverage and bottleneck classification.

### Phase 5: Fallback And UI

- Add explicit developer UI for backend selection and consent.
- Add clear failure reasons for unsupported/protected/elevated targets.
- Keep WGC/window-GDI fallback explicit and diagnosable.
- Do not silently switch to visually invalid fast modes.

Exit criteria:

- Users can understand why game capture did or did not start.
- Stopping the stream fully detaches the hook/helper.

### Phase 6: Broader API Support

After the D3D11 MVP proves value:

- add D3D12 support
- evaluate Vulkan layer support
- evaluate OpenGL hook support
- evaluate GPU-only WGC for display sharing
- evaluate vendor-specific paths only if cross-vendor backends remain
  insufficient

## Recommendations

1. Stop treating `PrintWindow` or current WGC tuning as the final gameplay
   capture solution.
2. Keep current window-GDI/WGC work as fallback and diagnostic baseline.
3. Build the next real prototype as a debug-only D3D11 Present-hook backend for
   BG3 DX11.
4. Keep frames GPU-side through shared D3D11 textures before scaling and
   encoding.
5. Update diagnostics before adding probes: the report JSON/Markdown should
   prove present cadence, hook copy time, queue pressure, CPU readback count,
   encoder timing, and fallback reason.
6. Require explicit consent and security review before any injection-based
   backend becomes user-facing or default.

## References

Source references:

- OBS game-capture controller, injection helper, graphics-hook code, and
  shared hook configuration.
- OBS DXGI/D3D11/D3D12/Vulkan/OpenGL capture implementations.
- OBS D3D11 NVENC and AMF texture paths.

Platform references:

- Microsoft `IDXGISwapChain::Present`:
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-present>
- Microsoft `ID3D11Device::OpenSharedResource`:
  <https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-opensharedresource>
- Microsoft `IDXGIResource::GetSharedHandle`:
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiresource-getsharedhandle>
- Microsoft Windows Graphics Capture overview:
  <https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture>
- Microsoft Desktop Duplication API overview:
  <https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api>
