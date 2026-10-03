# Streaming Guidance Status

Status: Current implementation-decision summary for DX11 gameplay streaming

This is the volatile current-state companion for the streaming guidance plan.
Use `README.md` for folder routing, `streaming-pipeline.md` for stable
architecture, and `stream-optimization-report.md` for dated evidence.

Source plan: historical maintainer guidance; the current status and decisions
are summarized in this document and the linked architecture/evidence docs.
Dated closeout/evidence history that used to live in this file now lives in
`streaming-guidance-status/` - see its `README.md` for the index.

This document maps the current Inter Galactic streaming state against the
guidance plan. It records the active implementation boundary for
gameplay streaming. The latest 2026-06-21 Phase 4 branch adds receiver
presentation diagnostics only and is synthetic-green: receiver probes can now
carry renderer-callback, texture-ready, and Flutter UI-paint stage lineage for
the same diagnostic renderer surface. BG3 live validation is not green because
receiver presentation cadence still fails while receiver layer, dimensions,
bitrate, QP, and decoded/render cadence look healthy. It does not change
LiveKit publish options, TURN behavior, fallback policy, bitrate/profile
policy, codec, simulcast, server behavior, RNNoise, sender capture, native
capture, or non-game capture sources.

## Current Status

The entry below is the current decision baseline. Dated closeout history that
led here - June 7 through June 21, plus the May 28-June 6 window-capture/
native-NV12 evolution - moved to `streaming-guidance-status/`.

June 22 non-DX11 compatibility-routing addendum: this addendum tightened the
shared app-default Windows backend selector so renderer-labelled non-DX11 game
windows stay on the DirectX/window-GDI compatibility path unless a developer
explicitly selects the D3D11 diagnostic override. The guard covers DX12,
D3D12, Vulkan, and OpenGL markers in the window title, preserves the existing
browser/non-game title guard, preserves explicit backend overrides, and keeps
the current BG3 D3D11 test title on the D3D11 hook path. Focused
`stream_test_runner_test.dart` coverage now pins both the selector and
stream-runner envelope behavior for those cases. This was not a live/BG3 smoke
cycle; Live Testing Override was inactive. If a non-DX11 game does not expose
its renderer in the window title, that source is still not automatically
classifiable from current Dart metadata and should be validated before calling
the non-DX11 restoration complete.

See `streaming-guidance-status/README.md` for the full dated closeout log this
decision was reached against.

Treat average FPS as useful but incomplete. The next performance boundary is
frame pacing: native capture cadence, frame interval p95/max, and whether the
capture/scale/convert path delivers frames evenly enough for 30 FPS gameplay.

## Done From StreamingGuidance (historical)

### Network, SFU, Receiver, And Encoder Triage

Status: done for the current evidence set.

- Diagnostics and stream-lab reports now separate capture, encode, send,
  receive, decode/render, ICE route, and quality-limitation evidence.
- Recent receiver logs show the receiver is requesting HIGH and rendering what
  it receives. No current evidence points to receiver decode/render as the main
  FPS limiter.
- Recent sender logs show clean packet loss/RTT/NACK behavior for the tested
  scenarios, so bitrate and internet capacity are not the primary active
  tuning target.
- Hardware H.264 through Media Foundation is active in the current Windows
  gameplay path when the hardware-first preference is enabled.

### Resolution Cap And Crop/Stretch Repair

Status: done for Windows window/display release-candidate paths, with manual
visual validation still required after native changes.

- The patched Flutter WebRTC bridge passes requested screen-share dimensions
  as max pre-encode bounds to the native `StartWithMaxFrameSize(...)` path.
- Native capture no longer uses `Start(fps, x, y, w, h)` as a scaler, because
  that overload is a capture-region crop.
- Window sources now use the actual captured `DesktopFrame` buffer size and
  publish a stable preset-sized encoder canvas with contain-fit content.
- Display sources keep dynamic contain-fit dimensions.
- Normal validation must still inspect the visible remote frame, because prior
  sender stats looked plausible even while the image was cropped.

### Basic Frame-Cadence Measurement

Status: done for sampled report evidence.

- Native desktop-capture diagnostics now emit submitted FPS plus p95/max frame
  interval evidence.
- The debug stream-test runner can compare App default, Native default,
  WGC-only, DirectX-only, and window-crop diagnostic backends.
- Reports include native submitted FPS, p95/max interval, capture wait/permanent
  errors, crop-region state, observed native capturer label, dirty-region mode,
  dominant native capture delay phase, and a subjective-notes placeholder.
- Stream-test JSON and Markdown now include a Frame Pacing section. It derives
  sampled p50/p95/max intervals from cumulative WebRTC frame counters for
  capture, pre-encode proxy, encoded, sent, received, decoded, and rendered
  stages, counts zero-delta sampled counter windows as stale gaps so freezes
  are visible in p95/max and average FPS, and carries duplicate/stale native
  marker counts where available.
- The sampled stages are not true per-frame timestamps. They are interval
  estimates across the runner's one-second sample windows, enough to identify
  where 100 ms-class gaps begin before designing a native pacer.

### Avoid More LiveKit/Bitrate Guesswork

Status: done as current project posture.

- Smooth remains the default stability profile.
- Windows hardware-first Smooth now uses a release-candidate 3 Mbps ceiling with a
  2.5 Mbps floor, 30 FPS target, and 36 FPS sender cap.
- Balanced and High Quality remain opt-in higher-quality paths.
- LiveKit adaptive stream, dynacast, receive priority, and focused HIGH policy
  remain in place, but the current bottleneck is below LiveKit.
- DirectX/window-GDI is now the normal Windows window/game App default. Live
  switching away from that backend still remains a restart-boundary operation
  because prior tests showed in-place switches can poison the next sender until
  a full share restart.
- The app refreshes and rebinds the desktop source before each publish so
  stream-test batches can reuse the selected source without relying on stale
  `DesktopCapturerSource` ids.

### Do Not Add Artificial Playback Delay

Status: documented as current architecture.

- The current LiveKit/flutter_webrtc renderer path does not expose decoded
  frames for an app-level playout-delay buffer.
- Artificial UI delay would not create missing sender frames and could desync
  stream video from call audio or shared-content audio.
- Choppy gameplay should continue to be handled as a sender cadence,
  capture-path, receiver, network, or SFU diagnostics problem before any
  delay-buffer design is considered.

## Still Needed

### 1. Full Per-Stage Frame Pacing Evidence

Implemented for sampled WebRTC counter evidence.

Current report fields:

- native capture p95/max interval plus submitted FPS, duplicate/stale reuse,
  wait timeouts, and permanent errors when native markers are present
- sampled capture p50/p95/max interval from `framesCaptured`
- sampled pre-encode p50/p95/max interval from `framesCaptured` only when
  pre-encode dimensions are present, labeled as a proxy rather than a separate
  native counter
- sampled encoded p50/p95/max interval from `framesEncoded`
- sampled RTP send p50/p95/max interval from `framesSent`
- sampled receiver receive/decode/render p50/p95/max intervals from
  `framesReceived`, `framesDecoded`, and `framesRendered` when exposed


Native capture-call diagnostics (result-callback/acquisition-wait split,
dirty-region shape, WGC substage, GDI substage) are implemented and parsed
into stream-test JSON/Markdown; see
`streaming-guidance-status/2026-05-31-to-06-03-native-capture-call-diagnostics.md`
for the dated evidence this was built against.

Remaining precision gap:

- native capture markers do not yet emit p50 interval
- native dirty-region force mode is now normal for explicit Native default and
  WGC-only Windows window/game comparison paths, while App default
  DirectX/window-GDI and display shares stay on Auto
- native queue depth/latest-frame reuse markers still come from the
  latest-frame pacer counters, so pacer-off comparison runs have less native
  queue detail
- true per-frame pre-encode timing still requires a deeper native timestamp
  marker outside the current one-second sampled runner cadence
- if the WGC substage marker shows `map_texture`, `copy_rows`, or
  `zero_hertz_compare` dominating, the next implementation should optimize that
  concrete stage rather than touching bitrate or LiveKit
- if it shows repeated `frame_pool_empty`, startup sleeps, or
  `source_not_capturable`, the next implementation should target WGC frame
  availability/source-state behavior
- if WGC substage timing is small while wrapper-level callback-entry or
  unaccounted wait remains high, the next split should move to frame lifetime,
  callback dispatch, or outer capturer locking rather than deeper WGC copy work
- if the new GDI substage marker shows `print_full`, `print_fallback`,
  `bitblt`, `crop`, or `owned_capture` dominating, the next implementation
  should target that concrete window-GDI stage instead of changing stream
  profiles

The first success target remains Smooth 720p gameplay with sampled/native p95
near the 30 FPS frame budget and no repeated 100 ms-class gaps. Do not make
1080p30 the main target until 720p30 pacing is visibly stable.

### 2. Native Latest-Frame Pacer Design

Implemented and promoted to normal Windows desktop/window publish behavior.

The current pacer separates frame acquisition from submit cadence inside the
patched Windows desktop capturer:

- capture callback stores the latest frame and returns quickly
- pacer wakes on the target cadence
- pacer submits the newest available frame
- stale frames are dropped instead of queued
- queue size stays bounded at one frame

Normal Windows desktop/window screen-share publishes now pass the
`intergalacticCaptureFramePacing=latest` constraint by default. The debug
stream-test runner still exposes an `Enable latest-frame pacer` checkbox so
explicit off/on A/B runs remain possible; reports export submitted FPS, unique
FPS, p95/max submit gaps, frame age, `OnFrame` time, duplicate submissions,
overwritten frames, and skipped ticks.

The promotion was based on the 2026-05-28 BG3 paired evidence. In the clearest
Balanced DirectX-only pair, pacer off captured around 15.9 FPS but encoded and
sent only around 6 FPS with roughly 447 ms encode time and 560 ms packet send
delay. Pacer on kept capture, encode, and send aligned around 18.2 FPS with
roughly 56 ms encode time and 10 ms send delay. Network loss, RTT, and
quality-limitation evidence stayed clean. The remaining performance target is
therefore native capture acquisition/cadence, not WebRTC send queue collapse.

### 3. Capture Backend Policy By Source Type

Partly implemented as diagnostics, not as product policy.

Current state:

- App default/native default is still the normal path.
- WGC-only and DirectX-only are available as debug comparison modes.
- Fresh May 31 windowed BG3 one-at-a-time evidence favors App default and
  Native default. DirectX-only is currently capture-acquisition-limited on the
  user's test machine and should not become a default without newer proof.
- Display Smooth/Balanced shares now use the 30 FPS target as the
  sender/capture cap; window/game captures keep the 36 FPS cap headroom.

Remaining work:

- Re-run windowed BG3 Smooth/Balanced App default and Native default with the
  source-rebind patch, then run one display smoke to validate the display cap.
- If one path consistently wins for gameplay cadence, design an opt-in Game
  Streaming Mode rather than changing the global default.
- Keep privacy implications visible if any display-crop mode is considered.

### 4. GPU-First Scale/Convert Investigation

Partly implemented as a debug-only shared-texture consumer proof; not yet a
publishing path.

The current normal publish path still relies on the existing CPU-oriented
desktop/window capture boundary. The game-capture POC now has enough host-side
shared-texture diagnostics to inspect whether Windows gameplay capture can
preserve GPU surfaces longer:

- acquire/copy Direct3D frames quickly
- open shared D3D11 textures from the Inter Galactic-controlled host side
- measure host frame age, missed frames, and consumer gaps
- keep the proof-only GPU contain-fit texture handoff as the visual-validation
  boundary
- feed the debug-proven NV12/GPU output into an encoder-controlled path; the
  synthetic local Media Foundation proof is complete, and the next proof
  target is now WebRTC/LiveKit source integration from the live BG3-proven
  path
- avoid synchronous heavy work in the capture callback

This remains a post-release quality step for publication. The local helper has
now proven D3D11 attach, shared-texture consumption, proof-only GPU scale,
encoder-compatible NV12 conversion, synthetic-target proof output, local
synthetic H.264 encoder proof, color-correct BG3 proof output, and live BG3
local H.264 encoder proof at 720p30 and 1080p30. A real WebRTC/LiveKit
publication path is still being validated before remote users can rely on the
new backend. The current debug LiveKit path now reaches visible output and
cleans up helper sessions. The latest live Smooth run proved GPU scaling is
active (`gpuScaled=994`, `gpuScaleFailures=0`, `cpuFallback=0`) but still
settled around 24-26 FPS because synchronous scaled staging `mapMs` rose to
about 34.5 ms. The current Debug rebuild replaces that immediate blocking map
with a four-slot async scaled-readback ring and parsed readback counters.
Exact local WebRTC-source smoke against the rebuilt Debug runner cleared the
native source boundary with `gpuScaled=145`, `cpuFallback=0`,
`readbackReady=145`, `readbackNotReady=0`, `readbackOverwritten=0`,
`mapMs=0.00091 ms`, `convertMs=0.18044 ms`, and clean helper teardown.

### 5. Game Streaming Mode

Partially implemented for developer-mode Windows app-default window/game shares.
There is still no polished production-facing game-capture mode. The current
developer path auto-selects the D3D11 hook only for app-default window sources
when developer mode is enabled, the title is not classified as browser/app or
renderer-labelled DX12/D3D12/Vulkan/OpenGL, and the source otherwise remains a
likely D3D11 game window. Renderer-labelled non-DX11 game windows stay on the
DirectX/window-GDI compatibility path unless the developer explicitly selects
the D3D11 override. The D3D11 path also falls back to DirectX/window-GDI if the
hook cannot start.

The project has debug backend comparisons and a window-crop diagnostic path,
but no product-facing Game Mode. A future Game Mode should remain opt-in until
logs prove the best source policy. Candidate choices:

- Auto
- Window capture
- Display capture
- Display crop
- WGC diagnostic
- DirectX diagnostic

Do not expose display-crop as a silent default because it can capture overlays
or other visible desktop content.

### 6. Profile Selection Proof

Still needed as a small UX/diagnostic follow-up.

Recent testing exposed one confusing state where the user thought Balanced was
running but diagnostics showed Smooth. Add or verify an unmistakable in-call
active-profile readout before future tuning, so measurements cannot be
misattributed to the wrong profile or a stale saved preference.

## Next Step Plan

### Release-Candidate Validation

Status: true native-NV12 GPU continuity is proven in actual BG3 gameplay;
Smooth 720p30 pacing is still not complete as a non-developer production D3D11
game-hook default.

The earlier `stream-test-2026-06-05T19-18-37-975209Z` result remains useful
historical proof that BG3 can publish visible, color-correct 720p output through
the debug game-hook path. The June 10 actual-gameplay reports supersede the
older CPU-I420 fallback state as the current readiness state: native-NV12
continuity held, but the retained build was still not clean.

Current retained-build evidence:

- Retained native behavior is `1280x720@30` with a ring-slot native-NV12 frame
  handoff to Media Foundation/WebRTC.
- Rejected branches include 60/45/36 FPS helper feeds and WebRTC-side
  source/wall pacing; those either worsened jitter, hid source cadence, or did
  not solve the frame gaps.
- GPU scaling and native-NV12 handoff stayed active with `gpuScaleFailures=0`,
  `nativeNv12Failures=0`, and `cpuFallback=0`.
- Hardware H.264, LiveKit-facing sender stats, route, packet loss, RTT, and
  quality limitation evidence stayed clean.
- Final reports still classified as `frame_pacing_unstable`; repeated frames,
  delivery overwrites, source-to-submit tails, and occasional encoder input
  stalls remained below stable 720p30.

Therefore Smooth 720p30 is cleared only for developer-mode app-default
experimentation, not as a non-developer release-candidate gate for the D3D11
game hook. Normal release streaming should stay on the established
WGC/window-GDI paths while D3D11 remains experimental.

### Next Engineering Pass

1. Do not request another broad live BG3 preset batch until the native-NV12
   Smooth pacing boundary changes.
2. Use one source-local or Smooth 720p D3D11 game-hook run to bound
   `native_frame_ready`, delivery queue wait, `OnFrame`, and Media Foundation
   input stalls at the same timestamp grain as the report.
3. Treat the current best path as ring-slot native NV12 with bounded GPU
   readiness waits. Do not restore the rejected helper-feed, CPU-I420 fallback,
   or WebRTC-source pacer branches without paired evidence.
4. If `nativeNv12Failures`, `cpuFallback`, or `gameCaptureGpuHandoffUnproven`
   returns, fix the GPU resource path before investigating pacing.
5. Keep normal WGC/window-GDI publishing stable while the game-capture backend
   remains debug-only.
6. Continue classifying normal stream-test evidence by p95/max native gaps and
   capture-cause attribution. Do not tune bitrate, codec, or fallback unless a
   fresh report proves those are the limiter.

## Do Not Do Next

- Do not tune bitrate again without new frame-pacing evidence.
- Do not disable the Windows latest-frame pacer in normal publishing unless a
  paired regression proves it harms visibility, latency, or sender cadence.
- Do not switch the default back to VP8 solely because a hardware path had an
  older black-window symptom; that symptom was later narrowed to window
  geometry/source shape.
- Do not make DirectX-only the default while it remains a restart-boundary
  diagnostic backend.
- Do not add an app-level playout delay as a substitute for missing sender
  frames.
- Do not chase 1080p60 as the next goal; return to Smooth 720p30 stability
  before using 1080p30 as the controlled quality step.

## Architecture Docs Status

- `livekit-gameplay-streaming.md` remains the durable behavior reference for
  current presets, receiver policy, diagnostics, and native capture caveats.
- `stream-optimization-report.md` remains the evidence log and historical
  tuning report for the broader streaming-optimization effort.
- `streaming-pipeline.md` remains the concise cross-system map; this pass
  does not modify it.
- This document is the compact current-status/checklist companion; its
  own dated closeout history lives in `streaming-guidance-status/`.
