# 2026-05-20 To 2026-05-31 Capture Validation Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-05-31 Capture-Call Split Readiness

- After the latest Roaming stream tests showed visibly poor motion despite
  clean transport, correct resolution, and acceptable average FPS, the active
  investigation shifted to native capture p95/max cadence tails.
- Native Windows desktop-capture markers now split each outer `CaptureFrame()`
  call into `Source Capture`, callback-entry delay, result-callback work,
  post-callback wait, and residual unaccounted wait. The stream-test JSON and
  Markdown report parse and display those fields under Native Diagnostic
  Markers.
- Next logs should be interpreted by the first large bucket: source capture
  points at backend platform acquisition/dirty-region behavior; callback entry
  points at frame lifetime/lock or dispatch before our wrapper starts frame
  work; post-callback wait points at cleanup/release after the callback; high
  residual unaccounted wait means the next instrumentation must move into the
  concrete Windows capturer backend.
- Validation passed for this diagnostics-only pass: Dart format, focused
  `stream_test_runner_test.dart`, focused Flutter analyze, native libwebrtc
  build, patched-libwebrtc installer, and `flutter build windows --debug
  --no-pub`. The installed artifact ZIP SHA-256 is
  `A39ABD1DCAC5C9512DD31685EE6198289D92A9F8906E6958FCC2961FE957CE61`; the
  debug build's `libwebrtc.dll` SHA-256 is
  `7B0FA454A16DD38F17A212EADDA2ADDFEF9116E0646C7AE674A9BE8F5C6B63D8`.

## 2026-05-20 Window-Source Black Stream Follow-Up

- A live debug build reproduced black video with a Windows window source while
  VP8 was selected and the hardware preference was off. A display share in the
  same build worked, so the immediate failure is not hardware encoding alone.
- The failing window path captured/submitted frames natively but produced a
  contain-fit output such as `1920x1048` under a `1920x1080` cap. Normal VP8
  presets still attempted a two-layer simulcast publish, which made WebRTC
  derive a low layer from a non-16:9 source frame.
- The release-candidate app-side mitigation is source-specific: Windows
  `SourceType.Window` shares publish single-layer when the selected profile
  would otherwise use simulcast. Display shares keep the existing simulcast path.
- This does not crop, stretch, or change the native scaler. It removes the
  fragile publish shape while preserving the current codec controls for live
  A/B validation.

## 2026-05-20 Windowed Stream Observe-Only Validation

- The first app-started BG3 normal windowed validation after the native
  geometry/canvas fix produced healthy sender stats without live-tuning
  republish. The active call profile was Balanced, not Smooth, because the
  runner used observe-only mode and preserved the user's running profile.
- Stream-lab summary:
  `runtime/stream-lab/results/20260520-160025-smooth-720-native-default.md`.
  The filename preserves the runner-request label from observe-only mode; the
  active call profile recorded inside the report was Balanced 1080p.
  It recorded 60 samples, score 90, average 28.8 FPS, 1920x1080 sent against a
  1920x1080 target, 0% loss, about 2.3 ms RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- The raw native sidecar proved the new window geometry path was active:
  `native_source=1920x1032`, `native_window_rect=1936x1048`,
  `content=1920x1032`, `pre_encode=1920x1080`, `canvas=letterbox`, and
  `crop_region=false`.
- Review follow-up: the stream-lab JSON/native diagnostics parser now parses
  `native_window_rect`, `content`, and `canvas` marker fields and includes them
  in JSON, Markdown, and summary labels for reports generated after the parser
  fix.

### Smooth Windowed Follow-Up

- A second observe-only pass against the user-started BG3 Smooth windowed stream
  confirmed Smooth now stays on its actual 1280x720 sender target. Summary:
  `runtime/stream-lab/results/20260520-161038-smooth-720-native-default.md`.
- The Smooth run recorded 60 samples, score 90, average 27.7 FPS, 1280x720
  sent against a 1280x720 target, 0% loss, about 3.2 ms max RTT, no NACKs,
  single-layer H.264, Media Foundation hardware encode, and no WebRTC quality
  limitation.
- Native evidence showed the repaired window path scaling the full captured
  frame into a stable 720p canvas:
  `native_source=1920x1032`, `native_window_rect=1936x1048`,
  `requested_max=1280x720`, `content=1280x688`, `pre_encode=1280x720`,
  `canvas=letterbox`, and `crop_region=false`.
- The run had a few short startup/transition dips, but the final stretch held
  28-31 FPS. Native capture cadence near the end was roughly 29-30 FPS, and
  native Media Foundation H.264 timing stayed around 1-2 ms per 1280x720 frame,
  so this pass does not point at bitrate, WebRTC adaptation, or encoder
  overload.

### Borderless Balanced Comparison

- The user then switched back to BG3 borderless Balanced and EXPERIMENTAL ran
  an observe-only pass without live tuning. Summary:
  `runtime/stream-lab/results/20260520-162016-balanced-1080-app-default.md`.
- This run recorded 61 samples, score 83, average 25.7 FPS, 1920x1080 sent
  against the 1920x1080 target, 0% loss, low RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- Raw native evidence showed the borderless source path captures a larger
  compositor/game frame than the normal windowed path:
  `native_source=2560x1440`, `native_window_rect=2560x1440`,
  `requested_max=1920x1080`, `content=1920x1080`,
  `pre_encode=1920x1080`, `canvas=fixed`, and `crop_region=false`.
- Compared with the normal-windowed Balanced pass at 28.8 FPS / score 90, this
  borderless pass was lower and more variable. The user noted the test machine
  was also running multiple workload-heavy apps during the borderless pass, so
  this delta is not enough evidence to declare borderless inherently slower
  than normal windowed mode.
- The durable conclusion from this pass is narrower: borderless was visible,
  capped at 1920x1080, uncropped, single-layer, H.264 hardware encoded, and
  clean on the network path. Native encoder timing stayed in the
  low-millisecond range. If future quiet-host runs reproduce the same FPS gap,
  investigate capture/acquisition cadence from the larger 2560x1440 borderless
  source before the 1080p cap.

### Display Share Follow-Up

- The next observe-only pass used the user-started display share with the same
  Balanced profile. Summary:
  `runtime/stream-lab/results/20260520-162855-balanced-1080-app-default.md`.
- This run recorded 60 samples, score 90, average 29.0 FPS, 1920x1080 sent
  against the 1920x1080 target, 0% loss, low RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- Share diagnostics identified `sourceType=display`, `audioMode=systemLoopback`,
  and `audioState=active`. Native diagnostics averaged about 28.1 submitted FPS,
  about 3.2 ms native Media Foundation encode timing, and 2 slow encoder
  samples out of 206.
- The stream-lab parser reports display native source/pre-encode dimensions as
  unknown in this pre-parser-fix report, so sender stats remain the
  authoritative source for the 1920x1080 display publication in this run.
  Reports generated after the Review parser fix can surface the newer native
  geometry fields when the native sidecar emits them. This validates the display
  share path after the window-source geometry repair; remaining validation
  should concentrate on receiver-side visual confirmation.

### Motion Display Share Follow-Up

- The follow-up observe-only pass used a user-started display share while a
  YouTube video was playing. Summary:
  `runtime/stream-lab/results/20260520-163404-balanced-1080-app-default.md`.
- This run recorded 60 samples, score 90, average 27.4 FPS, 1920x1080 sent
  against the 1920x1080 target, 0% loss, low RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- Share diagnostics again identified `sourceType=display`,
  `audioMode=systemLoopback`, and `audioState=active`. Native diagnostics
  averaged about 27.7 submitted FPS, about 2.6 ms native Media Foundation encode
  timing, and 0 slow encoder samples out of 204.
- User caveat: the preceding BG3 game-window tests were loaded-in and idle, not
  active gameplay motion. They are valid release-stability evidence for
  visibility, capping, no crop, and clean network/encoder stats, but they do
  not yet prove high-motion gameplay. The YouTube display-motion pass is a
  stronger motion baseline and still shows current release-level improvement.

### Motion Window Share Follow-Up

- The next observe-only pass used a user-started YouTube video as a window
  share. Summary:
  `runtime/stream-lab/results/20260520-163835-balanced-1080-app-default.md`.
- This run recorded 60 samples, score 90, average 27.7 FPS, 1920x1080 sent
  against the 1920x1080 target, 0% loss, low RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- Share diagnostics identified `sourceType=window`,
  `audioMode=systemLoopback`, and `audioState=active`. Native diagnostics
  averaged about 28.9 submitted FPS, about 2.4 ms native Media Foundation encode
  timing, and 0 slow encoder samples out of 177.
- This non-game motion-window result closely matches the YouTube display-motion
  result and is strong release-candidate evidence that the repaired Windows
  window-source path is visible, capped, stable, and not being degraded by
  WebRTC adaptation. This report predated the Review parser fix for
  `native_window_rect`, `content`, and `canvas` markers, so receiver-side visual
  confirmation remains the final proof for crop/stretch.

### High Quality Window Share Follow-Up

- EXPERIMENTAL added
  `tools/stream-lab/configs/high-quality-1080-app-default.json` so observe-only
  reports for High Quality streams are not mislabeled as Balanced experiments.
- The follow-up observe-only pass used a user-started YouTube video as a High
  Quality window share. Summary:
  `runtime/stream-lab/results/20260520-164450-high-quality-1080-app-default.md`.
- This run recorded 60 samples, score 90, average 56.9 FPS, 1920x1080 sent
  against the 1920x1080 target, 0% loss, low RTT, no NACKs, single-layer H.264,
  Media Foundation hardware encode, and no WebRTC quality limitation.
- The active profile evidence is the key result: the sender reported
  `highQuality`, requested 1920x1080@60, and reached a max of 61 FPS. High
  Quality is therefore not unexpectedly capped at 30 FPS on the repaired window
  path.
- Average send bitrate was about 9.8 Mbps against an 18 Mbps target with about
  55.8 Mbps available outgoing bitrate. This suggests the content/encoder did
  not need the full configured bitrate during this sample; it does not look
  bandwidth-limited. Native diagnostics averaged about 3.0 ms Media Foundation
  encode timing, with 1 slow native encoder sample out of 208. The native marker
  parser can average submitted FPS differently than WebRTC sender stats in this
  mode, so WebRTC sender FPS remains the authoritative cadence signal for the
  preset-cap question.

### 30 FPS Profile Headroom Tuning

- The High Quality YouTube window pass reached 56.9 FPS on the same repaired
  window-source path where Balanced averaged 27.7 FPS. That indicates the lower
  result is profile/cadence limited rather than a hard capture, encoder, or
  network ceiling.
- Smooth and Balanced now distinguish target FPS from sender cap. Their success
  target remains 30 FPS for fallback, scoring, diagnostics, and release
  validation. The normal VP8 preset definitions keep a 36 FPS sender cap for
  cadence headroom, and Windows hardware-first H.264 now uses the same 36 FPS
  cap after live-apply testing showed exact 30 FPS caps under-drive the Windows
  capture loop on a 2K BG3 source.
- Stream diagnostics now show this explicitly, for example
  `requested=1280x720@30fps_target/36fps_cap/...`. Per-track `requestedFps`
  remains 30 so adaptive fallback does not treat an acceptable 30 FPS stream as
  a cap miss.
- Stream-lab JSON and Markdown scoring use the target FPS, and profile JSON now
  includes `targetFramerate`, `maxFramerate`, and `minBitrateBps`. Advanced
  override keeps its explicit FPS as both the target and cap.
- This is intentionally a small profile/pacing change. It does not alter the
  native scaler, codec preference, single-layer window-source guard, or LiveKit
  room defaults.
- 2026-05-31 Roaming stream-test evidence now narrows the headroom rule by
  source type. Smooth/Balanced display captures of a 2560x1440 desktop produced
  correct 720p/1080p output, 0% loss, low RTT, and no bitrate ceiling pressure,
  but the 36 FPS cap drove a native 27 ms capture loop while acquisition waits
  averaged roughly 24-41 ms and native p95/max gaps reached about 70-220 ms.
  Windows display captures with a 30 FPS target therefore use 30 FPS as the
  sender/capture cap; Windows window/game captures keep the 36 FPS headroom
  that prior BG3 window validation showed was useful.

### Sampled Frame-Pacing Report Upgrade

- EXPERIMENTAL added a diagnostics-only stream-test report upgrade before any
  native pacer or profile retuning work. JSON and Markdown now include a
  Frame Pacing section for native capture, capture, pre-encode proxy, encoded,
  sent, received, decoded, and rendered stages.
- Sender stages derive p50/p95/max intervals from cumulative WebRTC
  `framesCaptured`, `framesEncoded`, and `framesSent` deltas across the
  runner's sample windows. Receiver stages use `framesReceived`,
  `framesDecoded`, and `framesRendered` when available.
- Pre-encode is explicitly labeled as a proxy: it uses the capture counter only
  when pre-encode dimensions are present, because WebRTC does not expose a
  separate pre-encode frame counter in the current diagnostics surface.
- Native capture still uses the native cadence markers for submitted FPS,
  p95/max interval, duplicated frames, stale reuse, wait timeouts, and
  permanent errors. Native p50 interval and queue-depth markers remain future
  native-side evidence gaps.

## 2026-05-28 Pacer-Default Validation And Native Capture Limiter

- Normal app-started publish logs now confirm the product path is using the
  latest-frame pacer by default: `LiveKit screen-share capture request` records
  `nativeFramePacing=true` for Windows window and display shares without the
  debug stream-test checkbox being selected.
- A manual Balanced display share on the normal app path reached the intended
  release cadence: 1920x1080 H.264 Media Foundation hardware encode, capture /
  pre-encode / encode / send around 34-36 FPS, 0% packet loss, 0 NACKs, 1-2 ms
  RTT, and no WebRTC quality limitation. This keeps display capture, hardware
  encode, bitrate, transport, and LiveKit sender policy out of the main suspect
  list for the latest low-FPS window runs.
- The latest DirectX-only BG3 window stream tests show the remaining limiter
  clearly. Smooth 720p with the pacer enabled sent about 17.9 FPS and Balanced
  1080p sent about 17.0 FPS. Both had 0% loss, no WebRTC quality limitation,
  correct native contain-fit output, and `pacer submitted FPS == pacer unique
  FPS` with no duplicate submits, skipped ticks, or overwritten frames.
- The expensive part is not the scaler, WebRTC `OnFrame`, or native encoder:
  Smooth logged about 55 ms average / 457 ms max capture calls, 4 ms average
  frame work, and 2 ms average native encoder time. Balanced logged about
  59 ms average / 421 ms max capture calls, 4 ms average frame work, and 4 ms
  average native encoder time. Dropping from 1080p to 720p only improved the
  DirectX window run by roughly 1 FPS, so resolution/bitrate tuning alone is
  not the next useful lever.
- Conclusion: the current bad path is native window capture acquisition/cadence
  for the tested DirectX-only source, not WebRTC send queue collapse. The pacer
  is still useful because it prevents downstream encode/send backlog, but it
  cannot create unique frames when the native capture call itself is averaging
  50-60 ms.
- 2026-05-28 follow-up instrumentation split the native capture call into
  total call time, result-callback/frame-work time, and inferred acquisition
  wait. The existing frame timing marker already reports convert/copy, scale,
  and `OnFrame` cost; the new cadence fields make the platform acquisition
  wait visible in JSON/Markdown as `averageCaptureAcquireWaitMs` and the
  Markdown `Acquire Wait` column.
- The rebuilt validation artifact is installed at
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `9590EAAB0DADA95D38591F8DFA31E31D45BE02874C8596C8806496162433AF9B` and DLL
  SHA-256
  `28683B4171BF886665BC902A8C99703DF23C427F2931EA0715B605E69F4D5218`.
- Validation passed: Dart format for the touched stream-test files, focused
  `stream_test_runner_test.dart`, focused Flutter analyze for the stream-test
  runner/test files, native
  `{DEPOT_TOOLS}\ninja.bat -C
  {WEBRTC_BUILD_ROOT}\out-release\Windows-x64 libwebrtc`, and the
  patched-libwebrtc installer. After refreshing stale Flutter plugin symlinks
  with `flutter pub get`, `flutter build windows --debug --no-pub` also passed.

### Next Validation Target

- Re-run the BG3 window/display stream tests with the new artifact. In the
  Native Diagnostic Markers table, compare `Capture Call`, `Acquire Wait`, and
  `Frame Work`.
- If `Acquire Wait` accounts for most of the 50-60 ms call, the next native
  pass belongs inside the selected Windows backend / updated-region / frame
  lifetime boundary rather than the scaler, encoder, or bitrate profile.
- If `Acquire Wait` is low but `Frame Work` rises, revisit CPU conversion,
  contain-fit scaling, or `OnFrame` delivery.
- Superseded by the June 3 window-GDI promotion: DirectX/window-GDI is now the
  normal Windows window/game App default after same-scene reports proved WGC
  `map_texture` timing remained the limiter. Keep Native default and WGC-only
  as diagnostic comparison backends.

## 2026-05-31 Roaming P95/Max Cadence Evidence

- Latest Roaming stream-test reports matched the user's visual read: average
  FPS alone still made bad-looking streams look better than they were. The
  common limiter is native frame acquisition/cadence tails, not transport,
  bitrate, scaler cost, or hardware encode.
- Smooth/App default BG3 window share encoded 1280x720 at about 30.4 FPS with
  0% loss, about 4 ms RTT, no WebRTC quality limitation, and roughly 2.6 Mbps
  send bitrate. Native capture still showed 54 ms p95 / 122 ms max frame gaps,
  with capture-call/acquire-wait spikes around 214/206 ms.
- Balanced/App default BG3 window share encoded 1920x1080 at about 27.6 FPS
  with 0% loss, about 8 ms RTT, and no quality limitation. Native p95/max gaps
  rose to about 69/147 ms, with acquire-wait spikes around 275 ms.
- Smooth/Native default window share regressed harder on the same source:
  capture/encode/send averaged about 22.4 FPS, native p95/max gaps were about
  93/177 ms, and acquisition wait averaged about 38 ms with a 230 ms max.
  Balanced/Native default recovered to about 27.6 FPS but still had 71/150 ms
  native p95/max gaps.
- Smooth/App default display share, after the display cap narrowing, still
  averaged only about 24.8 FPS at 1280x720 with clean network stats. Native
  p95/max gaps were about 65/139 ms, and acquisition wait averaged about
  25 ms with a 166 ms max.
- The stream-test scorer now caps `stable_fps` on native/sender max gaps above
  three frame budgets and classifies p95 gaps above 1.5 frame budgets as
  `frame_pacing_unstable`. This is intentionally stricter so reports match
  visual stutter instead of rewarding a good average that hides long tails.
- Native diagnostics now add WebRTC's own `DesktopFrame.capture_time_ms()` as
  `Source Capture` plus updated-region dirty/empty counts. The next backend
  investigation should compare `Capture Call`, `Source Capture`,
  `Acquire Wait`, `Frame Work`, and updated-region counts before changing
  stream profiles again.

## 2026-05-31 Windowed BG3 One-At-A-Time Evidence

- The user stayed in BG3 windowed mode and ran the Windows backend tests one at
  a time from the Roaming stream-test harness. This avoided the stale-source
  poisoning seen in earlier batch runs and gives a clearer source/backend split.
- Smooth/App default window share:
  1280x720 encoded, score 75, capture 29.6 FPS, encode 29.5 FPS, send 29.5 FPS,
  about 34 ms average encode time, 2.5 Mbps sent bitrate, 0% loss, about 5 ms
  RTT, and no WebRTC quality limitation. Native diagnostics reported roughly
  29.9 submitted FPS with average capture call about 26 ms and inferred acquire
  wait about 22 ms.
- Smooth/Native default window share:
  1280x720 encoded, score 75, capture 32.2 FPS, encode 32.2 FPS, send 32.1 FPS,
  about 31 ms average encode time, 2.7 Mbps sent bitrate, 0% loss, about 3 ms
  RTT, and no WebRTC quality limitation. Native diagnostics reported roughly
  31.6 submitted FPS with average capture call about 23 ms and acquire wait
  about 19 ms.
- Smooth/WGC-only window share:
  1280x720 encoded, score 59, capture/encode/send about 26 FPS, about 40 ms
  average encode time, 0% loss, about 4 ms RTT, and the report bottleneck was
  `frame_pacing_unstable`. Native acquisition wait rose into the high-20 ms
  average range with larger p95/max gaps.
- Smooth/DirectX-only window share:
  1280x720 encoded, score 49, capture/encode/send about 11 FPS, about 91 ms
  average encode time, 0% loss, about 3 ms RTT, and the report bottleneck was
  `native_capture_limited`. Native diagnostics showed capture call/acquire wait
  dominating the frame budget while native encoder timing stayed around 2 ms.
- Interpretation: for this windowed BG3 scene, the normal app/default path and
  native/default diagnostic path are now the useful release-candidate baseline.
  WGC-only remains lower and jitterier, and DirectX-only is currently a capture
  acquisition failure mode rather than a hardware-encode, bitrate, or network
  failure. Do not make DirectX-only the product default from older evidence.
- The remaining batch-run issue is stale desktop source reuse. When the runner
  repeatedly stops and restarts the selected window source, later backend
  iterations can fail with `source not found` or publish a zero/bad stream. The
  app now refreshes the desktop source cache immediately before every publish,
  rebinds the selected source by id and then by normalized title when possible,
  and logs both the requested and resolved source hashes.
- Stream-test usability was also tightened for future validation: the runner
  config dialog scrolls, the call diagnostics window auto-collapses after a
  stream-test source is selected so the user can see the stream, and the
  developer stats overlay visibility persists between calls.

### Next Validation Target

- Build a fresh debug artifact and run windowed BG3 Smooth and Balanced first
  with App default and Native default. These are the candidates to optimize.
- In the stream-test report, confirm the selected source logs a cache-refresh
  `match=id` or `match=name` before each publish and that backend comparisons
  no longer fail with `source not found`.
- Re-run one display Smooth/Balanced smoke after the source-rebind patch to
  validate the 30 FPS display cap did not regress visibility, scaling, or audio.
- Keep WGC-only and DirectX-only as explicit diagnostic overrides. Treat them
  as evidence-gathering modes, not release defaults, unless fresh same-scene
  logs show they beat App/Native default on stable FPS and p95/max gaps.
- Implementation validation passed for this patch: Dart format, focused Flutter
  analyze for the touched stream/session/preferences files, focused
  `screen_share_quality_profile_test.dart` and `stream_test_runner_test.dart`,
  and `flutter build windows --debug --no-pub`. The debug executable was built
  at `intergalactic/build/windows/x64/runner/Debug/InterGalactic.exe`.
