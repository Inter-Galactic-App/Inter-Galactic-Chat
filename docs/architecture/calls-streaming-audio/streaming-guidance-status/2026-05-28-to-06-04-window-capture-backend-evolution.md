# May 28 - June 4 Window Capture Backend Evolution

Date range: 2026-05-28 to 2026-06-04

Dated evidence history extracted from `../streaming-guidance-status.md`. Covers the May 28 latest-frame pacer promotion, the May 31 Roaming window/display backend comparison, the June 2 dirty-region diagnostics, the June 3 window-GDI promotion, and the early GPU-scaled source-handoff proof that led into the June 4-6 debugging chain in the next slice.

---

Before the June 7 duplicate-skip validation, the remaining release-candidate
problem was sender-side gameplay cadence, not network capacity, LiveKit/SFU
behavior, receiver decode, receiver render, or the resolution cap. The
historical evidence was:

- Smooth can now publish the actual 1280x720 target without crop/stretch.
- Windows window and display shares are visible and stable after the native
  geometry/canvas repair.
- Receiver logs show HIGH receive priority, decode/render matching incoming
  FPS, 0% packet loss, and 0 NACKs.
- High Quality reached about 56.9 FPS on a YouTube window share, so the app is
  not globally capped at 30 FPS or below.
- Heavier BG3 gameplay still shows cadence dips on a clean route, especially
  from a 2K game source.
- Normal publish logs now prove the Windows latest-frame pacer is active by
  default (`nativeFramePacing=true`). A normal app-started Balanced display
  share reached about 34-36 FPS at 1920x1080 with Media Foundation hardware
  H.264, clean transport, and no WebRTC quality limitation.
- The May 28 DirectX-only BG3 window tests with the pacer enabled landed around
  18 FPS at Smooth 720p and 17 FPS at Balanced 1080p. Pacer submitted FPS
  equaled unique FPS, with no duplicate submits or skipped ticks. Native
  capture calls averaged about 55-59 ms while frame work and native encoder
  time stayed low, so that bad path was native capture acquisition / cadence
  rather than bitrate, scaler cost, encoder selection, or send queue.
- The May 31 Roaming one-at-a-time windowed BG3 tests sharpened the source
  policy: Smooth App default and Native default reached roughly 29.5-32 FPS at
  1280x720 with clean transport and no quality limitation; WGC-only stayed
  around 26 FPS with unstable pacing; DirectX-only collapsed to roughly 11 FPS
  with capture acquisition dominating. The current release-candidate window
  baseline is therefore App default / Native default, not DirectX-only.
- The next May 31 Roaming window/display tests showed why the prior score was
  still too optimistic: Smooth window could average near 30 FPS, but native
  p95/max frame gaps still reached roughly 54/122 ms, and other window/display
  runs reached 65-93 ms p95 and 139-177 ms max gaps. That matches the visual
  stutter report and keeps the limiter at native capture acquisition/cadence.
- The June 2 dirty-region diagnostics build keeps the same conclusion and adds
  the next proof layer: native frame-timing markers now report updated-region
  rect counts, dirty-area ratios, full-frame update counts, tiny-update counts,
  the actual native `DesktopFrame.capturer_id` label, and the active
  dirty-region mode. Follow-up Auto versus Force full-frame runs showed that
  Force full-frame improves the WGC window dirty-region path without solving
  all p95/max gaps. After the June 3 window-GDI promotion, Force full-frame
  dirty regions apply to explicit Native default and WGC-only comparison paths.
  Display, App default after it resolves to DirectX/window-GDI,
  DirectX/window-GDI diagnostics, and crop-diagnostic paths remain on Auto.
- App default is capture-backend policy, not encoder policy. Encoder selection
  still comes from the screen-share profile/publish path, with Windows normal
  presets preferring hardware-first H.264. As of the June 3 window-GDI
  promotion, App default resolves Windows window/game sources to the
  DirectX/window-GDI backend while display sources remain on the patched native
  default.
- The latest Force full-frame BG3 window reports narrowed the remaining gap:
  Smooth App default held about 27.5 sent FPS at 1280x720 and Balanced App
  default held about 26.7 sent FPS at 1920x1080 with clean transport, fast
  Media Foundation H.264, and no WebRTC quality limitation. The visual issue is
  still native pacing because p95/max native gaps remained about 70/171 ms for
  Smooth and 83/208 ms for Balanced.
- The next backend-internal diagnostic layer was added
  instead of changing profiles. Native WGC now emits `Inter Galactic WGC frame
  timing` markers for frame-pool empty/reuse, source capturability, startup
  sleeps, texture resize/recreate, `TryGetNextFrame`, GPU copy, blocking map,
  row copy, monitor scale lookup, and zero-hertz comparison. Stream-test JSON
  and Markdown parse these markers and expose the dominant WGC substage when
  `native_capture_limited` is detected.
- The Complete Stream Diagnostics pass formalized this evidence surface in
  `stream-diagnostic-contract.md`,
  `archive/stream-diagnostic-system-audit.md`, and
  `stream-bottleneck-classification.md`. Stream-test reports now include an
  Executive Summary, Diagnostic Coverage matrix, classifier confidence, exact
  missing fields, evidence against false causes, and a fixed recommended next
  action. New streaming instrumentation should update the current contract and
  parser instead of adding unparsed one-off log lines.
- The local stream-pipeline harness now allows running the synthetic
  D3D11 target and game-capture helper without Matrix login, room join, call
  setup, or LiveKit publishing. Use
  `tools/stream-lab/run_local_capture_benchmark.ps1` when the question is
  local D3D11 Present, host shared-texture consumer, or publication-handoff
  readiness. The first smoke wrote
  `runtime/stream-lab/local-results/local-capture-20260604-160719/` with D3D11
  Present around 57 FPS, hook copy avg/max around 0.006/0.035 ms, host
  consumer evidence available, and publication-handoff output around 20.7 FPS.
  This does not test WGC/window-GDI desktop capture, encoder, LiveKit/network,
  or receiver behavior; those report rows are intentionally `notApplicable` or
  `notTested`.
- The latest debug D3D11 game-hook work moved beyond the old desktop capture
  acquisition limiter for selected game windows. Local WebRTC-source smokes now
  prove GPU-scaled source handoff for synthetic 2K to 720p with
  `gpuScaled=288`, `gpuScaleFailures=0`, `cpuFallback=0`, visible pre-I420 and
  I420 proof, and zero source-frame regressions or shared-slot mismatches. This
  does not change normal WGC/window-GDI sharing; it means the next live BG3
  test should verify visual frame order and source-order counters rather than
  collect another broad preset batch.
- The 20.7 FPS local handoff result has been fixed as a helper pacing bug. The
  helper now samples the latest shared texture on a target-cadence window and
  reports repeated output frames. Synthetic validation now shows the local
  D3D11 hook/host/handoff path is ready for BG3 stress smoke: 720p30,
  1080p30, and 2560x1440-to-1080p30 all reach about 31-32 output FPS with
  roughly 32-34 ms p95 output gaps, and 1080p60 reaches about 57.9 FPS with a
  30 ms p95 output gap. This still does not publish hook frames to LiveKit.
- BG3 stress validation moved the game-capture POC from readback-bound to GPU
  texture handoff-ready. The R10G10B10A2 proof-frame export now has correct
  channel order, so BG3 proof images match the provided reference screenshot
  instead of rendering blue/purple. The helper also supports
  `publicationReadbackMode=proof-only`: it GPU-scales into the target BGRA
  texture each tick and reads back only the requested proof PNGs. Live BG3
  proof runs at 2560x1440 -> 1280x720@30 and 2560x1440 -> 1920x1080@30
  produced full-frame, color-correct output with about 30.5 FPS and 29.9 FPS
  respectively, while total handoff work averaged about 0.04 ms because
  continuous CPU readback was removed from the measured path.
- The debug WebRTC game-capture source has now crossed the first live-call
  handoff boundary. The latest Smooth 720p BG3 stream-test report proves
  visible, color-correct output through pre-I420 and post-I420 proof,
  `gpuScaled=1838`, `gpuScaleFailures=0`, `cpuFallback=0`, hardware
  `MediaFoundationH264`, clean transport, and helper teardown. The remaining
  issue is frame pacing: average capture/encode/send is near 30 FPS, but
  p95/max sender gaps still hit about 55/115 ms. The active implementation
  moved from "make GPU scaling work" to "stabilize async readback pacing."
- The current readback-pacing patch keeps normal stream profiles and LiveKit
  behavior unchanged. It increases the debug WebRTC source's scaled-readback
  ring from four to eight slots and submits one ready pending readback before
  queueing the next scaled frame, reducing the chance that a live three-frame
  readback delay overwrites an almost-ready frame. Synthetic source-local smoke
  now reports `readbackQueued=185`, `readbackReady=184`,
  `readbackNotReady=0`, `readbackOverwritten=0`, `gpuScaled=184`,
  `cpuFallback=0`, and sub-millisecond map/convert timings.
- The follow-up live BG3 Smooth validation now clears the first success target.
  `stream-test-2026-06-05T19-18-37-975209Z` reports source `2560x1440`,
  output/encoded `1280x720`, `34.8` capture FPS, `34.7` encode/send FPS,
  capture/encode/send p50/p95/max around `29/30/33 ms`, hardware
  `MediaFoundationH264`, clean route, `qualityLimitationReason=none`,
  `gpuScaled=2268`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackNotReady=45`, `readbackOverwritten=4`, visible proof `2/2`,
  visible I420 proof `1/1`, and clean helper teardown. The report classifies
  the run as `healthy` with high confidence.
- A later same-session High Quality `1920x1080@60` run remained rough and
  classified as `native_capture_limited`, with stale frame windows and high
  readback pressure despite the GPU path staying active. Treat that as evidence
  that 1080p60 is not the next target; it does not invalidate the Smooth
  720p30 result.
- The post-hotkey-persistence Smooth BG3 live run
  `stream-test-2026-06-05T23-52-31-028657Z` reopened the 720p30 gate. It still
  rendered visible, color-correct BG3 through GPU scale and I420 proof, with
  clean Media Foundation H.264, `qualityLimitationReason=none`, `0.0%` packet
  loss, about `3 ms` RTT, and no NACK pressure. However, the report classified
  `frame_pacing_unstable` because the game-hook readback path dropped `133`
  too-stale pending readbacks, averaged about `2.0` frames / `79 ms` of
  readback latency, and hit a max readback latency of `3` frames while
  encoded/sent p95/max gaps reached about `41/57 ms`. This is not a bandwidth,
  encoder, or source-frame-regression failure; it is residual WebRTC-source
  staging/readback latency pressure.
- OBS's Windows game-capture reference supports that conclusion. OBS gates
  capture inside the hook with a frame interval, copies/resolves the D3D11
  backbuffer into a shared GPU texture for the normal path, and lets its render
  pipeline consume that texture directly. Inter Galactic's debug WebRTC source
  still converts the GPU-scaled frame through an output-sized staging readback
  and CPU I420 conversion before WebRTC `OnFrame`. The next engineering
  direction should be a GPU/NV12/encoder handoff or latest-frame GPU consumer
  boundary, not more bitrate/profile tuning and not broad LiveKit changes.
- The synthetic-target caveat has been repaired. Hook-side PNG proof export is
  now non-blocking and publishes shared-frame state before optional target-side
  proof work, so proof requests no longer wedge the helper. Synthetic NV12
  smokes now complete with metadata, host-consumer, and publication-handoff
  reports: `local-capture-20260604-200324` produced about 32.0 handoff FPS,
  155 NV12 output frames, zero conversion failures, and about 0.028 ms average
  NV12 conversion; `local-capture-20260604-200640` also produced one visible
  publication proof frame and one visible NV12 luma proof. The synthetic
  harness is again the first-step no-call baseline before BG3 stress tests.
- The next synthetic no-call boundary is now cleared. Phase 4C local encoder
  proof feeds the scaled NV12 output into a Media Foundation H.264 sink writer
  with hardware transforms requested. Synthetic 720p30, 1080p30, and 1080p60
  runs completed with zero encoder write failures:
  `local-capture-20260604-204405` submitted 144 frames at 720p30 with about
  0.063 ms average submit time, `local-capture-20260604-204425` submitted 145
  frames at 1080p30 with about 0.065 ms average submit time, and
  `local-capture-20260604-204446` submitted 277 frames at 1080p60 with about
  0.051 ms average submit time. A separate non-encoder visible proof
  (`local-capture-20260604-204830`) still wrote a valid NV12 publication proof
  frame. The next evidence boundary is live BG3 local encoder proof, not
  LiveKit, bitrate, fallback, or another synthetic report-plumbing run.
- The live BG3 local encoder boundary is now cleared for the current target.
  `local-capture-20260604-210942` produced 3 / 3 visible full-frame,
  color-correct NV12 proof frames from the actual 2560x1440 BG3 source.
  `local-capture-20260604-210855` then fed the same source into a 1280x720@30
  local H.264 proof, submitting 281 frames with zero write failures, about
  29.9 output FPS, about 39.5/45.1 ms p95/max output gaps, about 0.028 ms
  average NV12 conversion, and about 0.069 ms average encoder submit time.
  `local-capture-20260604-211322` repeated the encoder proof at 1920x1080@30,
  again submitting 281 frames with zero write failures, about 30.1 output FPS,
  about 39.4/42.9 ms p95/max output gaps, about 0.022 ms average NV12
  conversion, and about 0.068 ms average encoder submit time. The next
  engineering target is a debug-only WebRTC/LiveKit video-source handoff that
  consumes this proven path; more local BG3 encoder proof is not the current
  blocker.
- Phase 4D implements that first debug-only WebRTC source handoff. The app can
  now request `game-d3d11-hook-experimental` for a Windows window source with a
  resolved PID. The patched Flutter WebRTC bridge creates a normal WebRTC
  local video track from `RTCVideoDevice::CreateGameCapture(...)`, while the
  custom libwebrtc capturer launches the D3D11 helper in external-consumer
  mode, opens the shared texture ring, contain-fits to the requested max
  bounds, converts to I420, and emits frames to WebRTC. This is intentionally
  debug-only and does not change normal WGC/window-GDI sharing, bitrate,
  profile, fallback, LiveKit defaults, or receiver policy. Validation completed
  for focused analyzer, native WebRTC rebuild, helper/hook Debug rebuild, zip
  packaging, patched Flutter WebRTC installer, and Windows Debug app build.
  Native libwebrtc source commit: `e09a684`. The new patched
  `libwebrtc.zip` SHA-256 is
  `002779B670C95050387B17D11FEC5864EA31F9C28B0808780651B68176CA4563`;
  the rebuilt `libwebrtc.dll` SHA-256 is
  `5D6B8FDF500F7427FA43B79063B985A582B28134117408615BB4E0A5482CA1F3`.
  The next evidence boundary is live call validation of the experimental game
  backend: visible BG3 output, sender/receiver FPS, p95/max gaps, hook cleanup
  on stop, and native `game_capture_webrtc_source` markers.
