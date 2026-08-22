# 2026-05-02 To 2026-05-06 Hardware Encoder Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## Likely Bottlenecks

- Desktop screen capture constraints are advisory in the current Flutter WebRTC
  path. Smooth asks for 720p, but the sender stats show 1080p and 1440p layers.
- VP8 is running through software encoding in the captured logs. `libvpx
  limited:cpu` with 16-22 FPS means the sender is overloaded before the network
  becomes the main suspect.
- Diagnostics were under-reporting useful signals: first/stale bitrate samples
  displayed as `0kbps`, and cumulative `jitterBufferDelay` appeared as a current
  jitter-buffer value.
- Adaptive stream, dynacast, simulcast, hidden-tile unsubscribe, and receive
  quality policy are already present and should be preserved.

## Evidence

- Smooth log sample:
  `send share 1920x1080 fps:16 ... vp8 ... libvpx limited:cpu`.
- Smooth log sample:
  `send share 2560x1440 fps:22 ... vp8 ... SimulcastEncoderAdapter (libvpx, libvpx)`.
- Receiver log sample:
  `recv share HIGH 1920x1080 fps:44 ... jbuf:11213ms`, which matches cumulative
  `jitterBufferDelay`, not current per-frame buffering.
- Advanced override sample:
  `recv share HIGH 3840x2160 fps:10 ... av1 ... jbuf:368533ms`, confirming that
  heavy codecs/resolutions can create misleading diagnostics and real decode
  pressure.
- Follow-up sample from `docs/logs/StreamLogs_5-1-2008.txt`:
  `OpenH264 hw:no limited:cpu` over `prflx/udp -> host/udp` with 0% loss and
  1-2 ms RTT. Smooth had already fallen back to a 640x360 request, but the
  high simulcast sender still reported actual 1920x1080, so software encoder
  CPU remained the bottleneck.

## Quick Fixes Applied

- Keep Smooth as the normal default profile: 1280x720, 30 FPS target with a
  36 FPS VP8 sender cap, 1.8 Mbps.
  Windows requests H.264 first for hardware acceleration; non-Windows presets
  remain VP8 unless changed through developer advanced override.
- Apply LiveKit/WebRTC sender RTP limits immediately after screen-share publish,
  not only after adaptive fallback changes.
- Add sender `scaleResolutionDownBy` based on observed sender stats so ignored
  1920x1080 and 2560x1440 capture sizes are clamped back toward Smooth.
- Enable adaptive fallback automatically for active Smooth screen shares.
- Add a Smooth CPU-rescue floor: after Smooth reaches its lowest normal
  fallback and still sees sustained CPU limitation, the client disables the
  non-low simulcast sender layer and publishes only the low layer
  (426x240, 20 FPS, 300 kbps) until the stream stabilizes.
- Treat first/stale bitrate calculations as unknown instead of `0kbps`.
- Hide jitter-buffer delay unless raw WebRTC stats include
  `jitterBufferEmittedCount`, allowing a per-frame average to be calculated.
- Add selected ICE route diagnostics to the developer stats overlay and logs.

## Hardware-Encode-First Update

- Windows screen/game sharing now resolves normal quality presets to H.264
  hardware-encode first while preserving the selected resolution, bitrate, and
  single-layer publish shape. Smooth/Balanced use a 30 FPS target with a 36 FPS
  sender cap and explicit H.264 bitrate floors; High Quality remains a 60 FPS
  target/cap.
- The hardware-first bitrate floors are Smooth 2.5 Mbps, Balanced 4 Mbps, and
  High Quality 6 Mbps. The ceilings are Smooth 3 Mbps, Balanced 8 Mbps,
  and High Quality 18 Mbps. Diagnostics include the floor in profile details,
  for example `_min2.5Mbps`.
- Developer advanced override remains explicit: if a developer selects VP8,
  VP9, AV1, H265, or another codec, that codec is still requested instead of
  the Windows hardware-first default.
- The actual encoder is still selected by libwebrtc and the installed GPU
  stack. The developer diagnostics `codec` and `encoderImplementation` fields
  must be used to verify whether a session is using a hardware H.264 encoder or
  falling back to software.

### 2026-05-20 2K BG3 Live-Apply Sweep

- The user validated the real release scenario by returning BG3 to 2560x1440
  while streaming a higher-animation area. This is intentionally harder than
  the earlier 1920x1080 game-resolution pass.
- Observe-only High Quality on the already-running stream averaged 46.4 FPS at
  1920x1080, with 0% loss, low RTT, no NACKs, no WebRTC quality limitation,
  and Media Foundation H.264 active. The user's local preview looked much lower
  than this, so the preview/render surface should not be treated as sender FPS
  proof in debug builds.
- Live-applied exact 30 FPS caps under-drove the Windows capture loop:
  Balanced 1080p/10 Mbps averaged 26.2 FPS, Smooth 720p/5 Mbps averaged
  27.7 FPS, Smooth 720p/3 Mbps averaged 27.7 FPS, and 900p/6 Mbps averaged
  27.3 FPS. Network and send-queue stats stayed clean.
- Sender headroom solved the release target: Balanced 1080p at 36 FPS cap and
  6-8 Mbps averaged 32.6 FPS, while Smooth 720p at 36 FPS cap and 5 Mbps
  averaged 31.8 FPS. The 40/45 FPS cap probes also cleared 30 but add more
  capture/encode pressure than needed.
- Resulting release-candidate tuning: Smooth/Balanced keep a 30 FPS target for
  diagnostics, scoring, and fallback, use a 36 FPS sender cap for Windows
  hardware-first H.264, and keep bitrate floors active. Balanced's
  hardware-first ceiling is 8 Mbps for a little visual headroom without the
  heavier 10 Mbps cap.
- After implementation, the updated Balanced app-default live config was
  applied to the still-running debug stream and averaged 32.7 FPS at 1920x1080
  with 0% loss, about 3.3 ms RTT, no NACKs, no WebRTC quality limitation, and
  a score of 90. A fresh app restart/build should be used for final validation
  because the already-running debug app could not load the newly patched Dart
  code until restart.
- Fresh-debug-build live gameplay validation on a heavier 2K BG3 scene showed
  that 1080p was still encode/pacing-limited despite clean network stats:
  app-started Smooth was active at first, forced Balanced 1080p/8 Mbps averaged
  about 26.1 FPS, Smooth 720p/5 Mbps averaged about 28.2 FPS, Balanced
  1080p/4 Mbps averaged about 27.4 FPS, and 900p/6 Mbps averaged about
  29.0 FPS. Smooth 720p/3 Mbps averaged about 33.8 FPS on the same source and
  clean route. The release-candidate follow-up is therefore a Smooth
  hardware-first ceiling reduction to 3 Mbps while leaving Balanced/High
  Quality as higher-quality opt-in paths.

## 2026-05-02 Hardware Encoder Follow-Up

- Latest logs in `docs/logs/Inter Galactic Call Diagnostics 5-2-2053.txt`
  confirm the Windows hardware-first profile is reaching LiveKit:
  `Balanced: 1920x1080, 30FPS, h264, 4000000bps, simulcast=false,
  hardwareFirst=true`.
- Runtime sender stats still report `engine=OpenH264 hw=false` with low loss,
  low RTT, and direct UDP ICE. That means the Dart/LiveKit profile is requesting
  the intended codec, but the native WebRTC encoder factory is selecting the
  software H.264 implementation.
- This does not look like a Flutter SDK version issue. The app is on Flutter
  `3.41.1`, but the relevant boundary is `flutter_webrtc 1.2.1`, which links a
  downloaded `libwebrtc.dll` from the Flutter WebRTC release package.
- The cached `flutter_webrtc` Windows plugin links only the packaged
  `third_party/libwebrtc/lib/win64/libwebrtc.dll`; the exposed wrapper header
  has no app-level switch for Windows Media Foundation, NVENC, AMF, or QSV
  encoder factories.
- WebRTC/Chromium has a Windows Media Foundation hardware H.264 encoder path,
  and Windows exposes a Media Foundation H.264 encoder, but the current Flutter
  WebRTC desktop wrapper is not proving that path is wired into the
  peer-connection factory used by Inter Galactic.
- Next implementation step is not another bitrate/profile change. It is a
  native dependency investigation/fork: verify the `webrtc-sdk/libwebrtc`
  factory implementation, add or expose a Windows hardware encoder factory if
  available, or vendor a patched Windows `libwebrtc.dll` that registers the
  Media Foundation hardware encoder before OpenH264 fallback.

## 2026-05-02 Libwebrtc Fork Step

- A local `webrtc-sdk/libwebrtc` fork now exists at
  `forks/libwebrtc` on branch
  `intergalactic/windows-hardware-h264`.
- Commit `01a72ac Enable Windows hardware H264 encoder factory by default`
  enables the wrapper's existing Intel Media SDK / oneVPL-backed Windows
  encoder factory by default for Windows builds and adds native logs for
  factory selection/fallback.
- This is the first hardware proof path. It should prove or reject Intel Quick
  Sync style H.264 without changing Dart stream profiles again.
- The fork still has to be built into a replacement Flutter WebRTC
  `libwebrtc.zip` before Inter Galactic can use it. The build must preserve the
  package layout expected by `flutter_webrtc 1.2.1`.
- NVIDIA/AMD-only hardware likely needs the next native patch: a generic
  Windows Media Foundation H.264 encoder factory that prefers hardware MFTs and
  falls back to OpenH264 only after logging the failure reason.

## 2026-05-03 Build Wiring Follow-Up

- The Windows release build path now runs a patched-libwebrtc preparation step after
  `flutter pub get` and before code generation/build.
- Normal builds use `auto` mode: if a validated patched `libwebrtc.zip` is
  found, it is installed into Flutter WebRTC's package cache; if not, the build
  warns and continues with the stock dependency.
- Strict hardware validation builds should use
  a strict patched-libwebrtc release build or pass a specific artifact with
  `--libwebrtc-zip <path> --require-patched-libwebrtc`.
- The helper validates the Flutter WebRTC zip layout and writes an install
  marker at `third_party/libwebrtc/intergalactic-patched-libwebrtc.json` after
  extraction.
- Until a patched `libwebrtc.zip` exists, a successful auto build is ready for
  RNNoise testing but should still be expected to report `OpenH264 hw:false`
  during stream tests.

## 2026-05-03 Media Foundation Hardware Encoder Patch

- The Intel-only artifact was installed correctly but still reported
  `OpenH264 hw:false` on the local NVIDIA RTX 2070 / DisplayLink host. That is
  expected because no Intel Quick Sync device is exposed on this machine.
- The patched Windows `libwebrtc` wrapper now enables a Media Foundation
  hardware H.264 factory before the Intel Media SDK / oneVPL factory and
  OpenH264 fallback.
- The Media Foundation path enumerates hardware H.264 MFTs with `MFTEnumEx`,
  configures H.264 output before NV12 input, requests low-latency settings,
  handles keyframe requests through `CODECAPI_AVEncVideoForceKeyFrame`, and
  reports `MediaFoundationH264` with `is_hardware_accelerated=true` when active.
- The path is single-layer and intentionally wrapped in WebRTC software
  fallback. That matches current Windows hardware-first presets, which already
  avoid software H.264 simulcast until GPU encoding is proven.
- New artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  SHA-256
  `F31484CB27D8847728682D0869FDEF23D7C689CD4A5777AE613D866ADC5FBEAD`.
- Native verification passed with:
  `ninja -C out-release\Windows-x64 libwebrtc`.
- App/runtime validation still needs a strict patched-libwebrtc release build
  and a gameplay stream log showing either `engine=MediaFoundationH264
  hw:true` or the exact Media Foundation activation/processing fallback.

## 2026-05-02 RNNoise Follow-Up

- Earlier diagnostics showed RNNoise intentionally fail-open with
  `reason=rnnoise_rate_unsupported` because WebRTC delivered `16000 Hz`,
  `160 samples`, and `160/160` frames while the reference-gate path requires
  `48000 Hz` / `480-frame` full-band buffers.
- The Windows processor now accepts valid 10 ms non-reference callbacks by
  resampling the downmixed mono frame into RNNoise's 48 kHz / 480-frame shape,
  running the reference gate, then resampling back to the capture frame count.
- The new bridge uses a Hann-windowed sinc filter rather than the old linear
  resampler and emits diagnostics for mode, input/output frames, source/target
  rates, and use count.
- This is still a bridge, not the final voice-quality resampler. The durable
  plan is in
  `docs/architecture/calls-streaming-audio/rnnoise-native-resampler-plan.md`:
  future work should add a stateful native resampler with continuous phase,
  bounded latency, no real-time heap churn, and native tests for impulse, sine
  sweep, speech fixtures, sample-scale preservation, and fail-open cases.

## Deeper Fixes To Consider

- Build and package the patched Flutter WebRTC / `webrtc-sdk/libwebrtc`
  Windows dependency before changing bitrate settings again.
- Add a generic Windows Media Foundation encoder factory if the Intel
  Media SDK / oneVPL proof path does not cover the target gaming machines.
- Revisit Windows Graphics Capture only after the current WebRTC sender clamp
  and diagnostics prove where capture/encode time is spent.
- Replace the stateless RNNoise windowed-sinc bridge with a stateful native
  resampler after native audio-quality tests are in place.
- Add server-side LiveKit metrics only if ICE route and SFU logs point at relay,
  packet forwarding, or SFU CPU pressure.
- Consider per-game capture presets later, but avoid exe-specific logic as the
  first performance fix.

## 2026-05-04 Limiter Retune From Smooth / High Quality / Advanced Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-04T13-34-10.062090Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-04T13-35-54.071514Z.txt`,
  and
  `docs/logs/inter-galactic-call-diagnostics-2026-05-04T13-40-33.054037Z.txt`
  show the patched Windows path working: normal presets report
  `MediaFoundationH264 hw=true` on a direct host/prflx UDP route with 0% loss
  and 1-3 ms RTT.
- The weak point is no longer "is hardware encoding active." Smooth and High
  Quality degraded because fallback treated 13-17 FPS and under-target bitrate
  as enough to downshift even when lowering requested resolution did not improve
  capture or send FPS.
- Advanced override looked better because it allowed a much larger bitrate
  budget. It still reported `OpenH264 hw=false`, so the better visual result
  is evidence that the normal preset limiter/bitrate ceilings were too tight,
  not proof that software encoding is preferred.
- Applied tuning: Windows hardware-first presets keep their resolution/FPS
  goals but use gameplay-oriented H.264 bitrate ceilings: Smooth 720p30 at
  5 Mbps, Balanced 1080p30 at 8 Mbps, and High Quality 1080p60 at 12 Mbps.
- Applied tuning: adaptive fallback no longer downshifts solely because actual
  bitrate is below target without corroborated bandwidth evidence, and the
  low-FPS fallback threshold now waits for a severe sender collapse below
  12 FPS. CPU limitation, software encoder fallback, packet loss, and
  corroborated bandwidth pressure still trigger fallback.

## 2026-05-04 Evening Follow-Up From v0.6.6+929 Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-04T21-50-46.529889Z.txt`
  and
  `docs/logs/inter-galactic-call-diagnostics-2026-05-04T21-53-50.849482Z.txt`
  show `MediaFoundationH264 hw=true`, direct host/prflx UDP, 0% loss, and
  1-10 ms RTT while the share still falls back to 426x240/20.
- The best-looking pass came from higher bitrate headroom. Normal High Quality
  in those logs still requested the older 6 Mbps ceiling, while Advanced
  Override used 17 Mbps and looked better even when it briefly selected
  OpenH264. That points back to preset limiter policy rather than server
  bandwidth.
- `capture_fps`, `encode_fps`, and `send_fps` often move together around
  10-17 FPS. Lowering requested resolution/bitrate did not reliably recover
  30 FPS, so fallback should stop collapsing a clean hardware route just
  because WebRTC's estimator says `bandwidth` or because FPS is below 12.
- Applied tuning: Windows hardware-first opt-in presets now have more bitrate
  headroom: Balanced 10 Mbps and High Quality 18 Mbps. Smooth remains the
  720p/30 default at 5 Mbps.
- Applied tuning: adaptive fallback no longer treats low available-outgoing
  bitrate by itself as bandwidth corroboration. It now needs loss, lost
  packets, high RTT, or repeated NACKs before `webrtc_limit:bandwidth` can
  downshift a stream.
- Applied tuning: hardware-encoded streams wait for a severe FPS collapse
  below 8 FPS before FPS alone can trigger fallback. Software encoder fallback,
  explicit CPU limitation, packet loss, and corroborated bandwidth pressure
  still degrade normally.

## 2026-05-05 Follow-Up From v0.6.6+932 Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T00-30-46.473860Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T00-34-15.119658Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T00-37-25.009828Z.txt`,
  and
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T00-38-09.079512Z.txt`
  show the app build contains the 18 Mbps High Quality hardware-first profile.
- The app fallback controller was not the main actor in the menu-screen
  failure: diagnostics often showed `fallback=none` while WebRTC reported
  `webrtc_limit=bandwidth`, `avail_out` around `300-650 kbps`, and actual
  output falling to `320x180` on a direct UDP route with 0% loss and 1-2 ms RTT.
- The older Advanced Override path performed better because simulcast/OpenH264
  eventually pushed the high layer to roughly 15-19 Mbps at 1080p/1440p. It was
  still not truly better encoder-wise; it simply avoided the single-layer
  hardware path's aggressive resolution adaptation.
- Applied tuning: Windows hardware-first H.264 publishes now use
  maintain-resolution degradation. If WebRTC's bandwidth estimator starts low,
  it should reduce frame cadence/quantization before turning a 1080p gameplay
  stream into a 320x180 thumbnail.
- Applied tuning: sender-limit reapplication now remembers the largest observed
  screen-share sender size instead of chasing the currently degraded output
  size, and it no longer reapplies identical limits every time WebRTC reports a
  new downscaled resolution.

## 2026-05-05 CPU-Limiter Follow-Up From v0.6.6+933 Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T01-43-05.785384Z.txt`
  and
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T01-49-18.604792Z.txt`
  show the patched hardware encoder is active:
  `MediaFoundationH264 hw=true`.
- The route still does not look like the first bottleneck: direct/prflx UDP,
  0% packet loss, 1-4 ms RTT, and only one PLI in the bad samples.
- The new failure boundary is capture/scale before encode. Smooth requests
  1280x720/30, then applies sender limits with `scaleResolutionDownBy`, but
  outbound stats still report actual `2560x1440` frames. When encode time rises
  to roughly 140-180 ms, WebRTC reports `webrtc_limit=cpu` and fallback lowers
  requested bitrate/resolution without reducing the actual captured frame size.
- Root cause narrowed to the Windows Flutter WebRTC bridge: LiveKit passes
  `width`, `height`, and `frameRate` into `getDisplayMedia`, but
  `flutter_screen_capture.cc` only used `deviceId` and `frameRate` before
  starting the desktop capturer. The attempted build-workflow fix routed those
  requested dimensions into `Start(fps, x, y, w, h)`.
- Follow-up validation superseded that attempted fix: the native overload is a
  capture-region path, not a safe full-source scaler. It can produce
  1280x720-class sender stats while the remote view only shows a cropped
  portion of the original 2560x1440 game window.

## 2026-05-05 Crop Regression Follow-Up From v0.6.6+933 Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T03-31-52.019791Z.txt`
  show the target was
  `Baldur's Gate 3 (2560x1440) - (DX11) - (6 + 6 WT)` and Smooth requested
  1280x720 while `MediaFoundationH264 hw=true` stayed active on a clean direct
  route.
- The sender stats moving to 1280x720 did not mean the whole window was scaled.
  User validation showed only part of the window was visible, matching the
  `Start(fps, x, y, w, h)` capture-region semantics in the Flutter WebRTC
  dependency.
- Applied corrective build-workflow fix: the patched-libwebrtc installer now
  repairs package-cache sources that contain the short-lived crop patch,
  restores full-frame `Start(fps)` capture, and leaves only a safety marker on
  clean caches so future builds do not treat crop dimensions as scaling.
- Expected validation is visual first: the receiver should see the entire game
  window again. Actual sender stats may return to the larger source resolution
  until a separate native full-source scaling path is implemented and proven.

## 2026-05-06 FPS Pipeline Follow-Up From v0.7.0+936 Logs

- Fresh logs in
  `docs/logs/inter-galactic-call-diagnostics-2026-05-05T22-26-12.873330Z.txt`
  show the later build is no longer encoding the native 2560x1440 window for
  Smooth. The session starts with `Smooth: 1280x720, 30FPS, h264, 5000000bps`
  and sender stats report `actual=1280x720` with
  `MediaFoundationH264 hw=true`.
- That confirms the Smooth resolution cap is reaching the encoded sender
  frame for this build. The remaining problem is FPS: on a clean direct
  prflx/host UDP route with 0 lost packets, 0 NACKs, and 1-2 ms RTT, the
  sender sits around 7-12 FPS. `capture_fps`, `encode_fps`, and `send_fps`
  move together, while encode time remains roughly 80-128 ms once the stream
  is warm and briefly spikes much higher at startup.
- The current logs still do not prove whether native desktop capture/scaling is
  only emitting about 12 FPS, or whether encoder backpressure is making the
  WebRTC source counter fall to the encoder cadence. The next build therefore
  needs explicit stage labels rather than another fallback tweak.
- Diagnostics-only changes now label sender `actual` as `encoded_size`, add
  WebRTC source/pre-encode dimensions when the stats surface exposes them, and
  duplicate the sender source cadence as `pre_encode_fps` so the log reads as
  native capture -> pre-encode/source -> encoded -> sent -> received -> rendered.
- The native desktop capturer source now emits an `Inter Galactic desktop
  capture pipeline` line with native source size, requested maximum, pre-encode
  output size, target FPS, emitted native FPS, scale state, and crop-region
  state. The Dart WebRTC native log filter now forwards these capture lines
  instead of only forwarding encoder-keyword lines.
- Rebuilt and installed the patched Windows libwebrtc artifact with those
  native diagnostics. Artifact zip SHA-256:
  `8DFB9FAA12C44FF1A51D5BC20C8A45E4E8DC16B370C4743D4008D3B5C12398C7`.
  DLL SHA-256:
  `42D13112BD52B3AE7E0F148CE0654FA4CB903B01D040DDA8B3C6DAD4E12CA785`.
- Validation rule for the next bad stream: if `native_fps` is already near
  8-12 FPS, investigate desktop capture/window capture and the contain-fit
  scaler. If `native_fps` is near 30 but `pre_encode_fps` or `encode_fps` is
  low, investigate WebRTC source backpressure or Media Foundation encode
  timing. If send FPS diverges from encode FPS, inspect packet send delay,
  BWE, and transport queue pressure. If receive/render FPS diverges later,
  inspect subscriber quality, decode, and Flutter renderer cost.
