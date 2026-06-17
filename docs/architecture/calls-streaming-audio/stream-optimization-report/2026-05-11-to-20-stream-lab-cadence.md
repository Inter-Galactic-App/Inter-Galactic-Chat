# 2026-05-11 To 2026-05-20 Stream Lab And Cadence Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## Diagnostics To Run During A Bad Stream

- In Inter Galactic developer stats, capture screenshots or copy lines at start,
  after 30 seconds, with one focused stream, and with several visible streams.
- Watch Windows Task Manager for CPU plus GPU Video Encode/Decode while sharing
  a game.
- On the server during the bad session:
  `docker logs --since=10m matrix-livekit`
- Also capture:
  `docker stats matrix-livekit matrix-rtc-auth`
- Note whether the app reports an ICE route using `relay` or `tcp`; if so, TURN
  and firewall routing should be inspected before tuning video settings again.

## Files Involved

- `docs/logs/StreamLogs.txt`
- `docs/architecture/calls-streaming-audio/livekit-streaming-performance-plan.md`
- `intergalactic/lib/client/components/voip/screen_share_quality_profile.dart`
- `intergalactic/lib/client/components/voip/screen_share_adaptive_fallback.dart`
- `intergalactic/lib/client/components/voip/voip_call_diagnostics.dart`
- `intergalactic/lib/client/matrix/components/voip_room/matrix_livekit_voip_session.dart`
- `intergalactic/lib/ui/organisms/call_view/call_view.dart`
- `intergalactic/test/client/components/voip/screen_share_quality_profile_test.dart`
- `intergalactic/test/client/components/voip/screen_share_adaptive_fallback_test.dart`
- `intergalactic/test/client/components/voip/voip_call_diagnostics_test.dart`
- `intergalactic/scripts/install_patched_libwebrtc.ps1`
- `webrtc-build/src/libwebrtc/src/win/mediafoundationh264encoderfactory.cc`
- `webrtc-build/src/libwebrtc/src/rtc_peerconnection_factory_impl.cc`
- `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`

## 2026-05-11 Drakus/Nick FPS Follow-Up From v0.7.0+949/+954 Logs

- Fresh paired sender/watcher logs from `docs/logs/inter-galactic-call-diagnostics-2026-05-11T00-27-42.752359Z`,
  `00-32-05.180069Z.txt`, `00-41-58.584978Z.txt`,
  `00-43-17.930978Z.txt`, `00-52-34.827017Z.txt`,
  `01-11-49.871759Z.txt`, `01-24-11.912727Z.txt`,
  `01-25-12.580825Z.txt`, `01-36-49.697766Z.txt`, and
  `02-04-39.601166Z.txt` show the sender as
  `<publisher-user-id>` on Inter Galactic for Windows `v0.7.0+949` and
  the watcher as `<watcher-user-id>` on `v0.7.0+954`; both report commit
  `69546a6`.
- The low-FPS boundary is before or at sender encode. Sender
  `capture_fps`, `pre_encode_fps`, `encode_fps`, and `send_fps` move together,
  while receiver `decode_fps` and `render_fps` match the incoming sender FPS.
  Watcher logs decode 1080p H.264 at roughly 6-8 ms with focused HIGH quality,
  so receiver decode/render is not the primary limiter in this batch.
- Smooth is not truly encoding 1280x720 in the main sender samples. Smooth
  requests `1280x720/30fps/5.0Mbps`, but the published track and sender stats
  repeatedly report `encoded_size=1920x1080` with
  `resolution_mismatch=req_1280x720_encoded_1920x1080`.
- Advanced/fallback samples also commonly request `960x540/30fps/1.2Mbps` but
  continue encoding `1920x1080`. One Smooth fallback sample did encode
  `1280x720`, but FPS still stayed near 12 FPS, so after scaler proof there may
  be a second Media Foundation/capture backpressure problem.
- Hardware encode is active: sender stats consistently show H.264 with
  `MediaFoundationH264 hw=true`. The limiting signal is encode cadence/timing,
  not software OpenH264 fallback.
- Bitrate is not the first suspect for these logs. The cleanest sender samples
  show 0% summary packet loss, low NACK/PLI/FIR counts, RTT around 59-63 ms,
  and `availableOutgoingBitrate` generally around 15-30 Mbps while actual send
  bitrate ranges roughly 1-7 Mbps.
- Encode time tracks the observed FPS ceiling. Smooth 1080p samples sit around
  78-100 ms encode time and 10-15 FPS. Advanced/fallback 1080p samples often
  sit around 51-67 ms and 15-20 FPS. The only near-30 FPS receiver window
  aligns with sender encode time dropping closer to the 30 FPS budget.
- No May 11 saved diagnostics contain the native
  `Inter Galactic desktop capture pipeline native_source=... requested_max=... pre_encode=...`
  lines that were added to prove actual native capture and pre-encode scaler
  output. Either those native lines are not being captured into saved call
  diagnostics, or the streamer build did not invoke the new scaler bridge.
- The "static desktop/no-game" sample was not identifiable in this saved batch:
  active share-source summaries still point at the Baldur's Gate 3 window. A
  future no-game comparison should be captured with an explicit source title
  and a short note of which file corresponds to it.

### May 11 Assessment

- Do not tune bitrate or fallback thresholds from this batch. The network path
  and receiver path are good enough to carry 30 FPS when the sender emits it.
- The next blocker is proving the capture-scaler bridge in the actual streamer
  build. Smooth must show native source size, requested max `1280x720`, and
  pre-encode output `1280x720` before the remaining FPS problem can be cleanly
  separated from encoder backpressure.
- If the next logs show `native_fps` already below 30, investigate the Windows
  desktop/window capturer and selected source type. If `native_fps` is near 30
  but `pre_encode_fps` or `encode_fps` collapses, investigate WebRTC source
  backpressure and Media Foundation encode timing. If 720p still encodes at
  80 ms, compare Media Foundation H.264 against the next best Windows-safe
  codec/encoder path before changing adaptive fallback again.

### May 11 Next Steps

- Add or verify a saved diagnostic line from the Flutter WebRTC bridge showing
  the requested width/height values and whether `StartWithMaxFrameSize` was
  called for the selected desktop/window source.
- Add or verify saved diagnostics for the loaded patched `libwebrtc.dll` SHA
  and bridge patch marker so streamer logs can prove the intended native
  artifact is actually running.
- Keep the current app publish path passing `ScreenShareCaptureOptions.params`
  and `maxFrameRate`, but verify that `createScreenShareTracksWithAudio`
  produces the scalar `video["width"]` and `video["height"]` values consumed by
  the Windows Flutter WebRTC bridge.
- Re-test Smooth with a source note and require these fields in the saved
  diagnostics: native source size, requested max, pre-encode output size,
  native FPS, pre-encode/source FPS, encode FPS, send FPS, receive FPS, render
  FPS, encode time, and active encoder implementation.

## 2026-05-17 Windows Display-Share And FPS Follow-Up From v0.7.0+968 Logs

- Fresh logs assessed:
  `docs/logs/inter-galactic-logs-2026-05-17T19-25-02.672666Z.txt`,
  `docs/logs/inter-galactic-logs-2026-05-17T19-29-58.560706Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-17T19-32-26.205013Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-17T19-36-45.729625Z.txt`,
  `docs/logs/inter-galactic-call-diagnostics-2026-05-17T19-40-05.640409Z.txt`,
  and
  `docs/logs/inter-galactic-call-diagnostics-2026-05-17T19-45-06.069541Z.txt`.
- The screen-source picker is still enumerating displays. The app logs show
  `windows=4/5 thumbnails=0 screens=2 thumbnails=0`, followed by selected
  display sources for Screen 1 and Screen 2. Those display publishes fail
  immediately in `MediaDeviceNative.getDisplayMedia` before any local tracks
  are created.
- Window sources in the same session do create `LocalVideoTrack` tracks and
  publish. That makes the current "screen share is not working; window share
  works" report a display-source publish failure, not a picker filter issue.
- Source picker previews are also regressed in this build: every enumerated
  window and display reports `thumb=0B`. That is separate from stream-preview
  work and should be fixed as source-picker preview restoration.
- Successful gameplay/window streams still run through H.264 hardware encode:
  diagnostics report `MediaFoundationH264 hw=true` with simulcast disabled.
- Bitrate and network are not the first limit in this batch. Stable samples use
  direct UDP routes with 0 lost packets, 0 NACK/PLI/FIR, roughly 59-68 ms RTT,
  and available outgoing bitrate above the actual sent bitrate.
- The FPS ceiling is before or at sender encode. `capture_fps`,
  `pre_encode_fps`, `encode_fps`, and `send_fps` move together around
  14-21 FPS. The 1080p samples report roughly 50 ms encode time and sit near
  20 FPS; 720p/fallback samples report roughly 67-70 ms encode time and sit
  near 14-16 FPS.
- Smooth is not reliably encoding its requested 1280x720 output. Some Smooth
  samples do encode 1280x720, but the longer game samples in the High Quality
  / Advanced log request Smooth `1280x720/30fps/5.0Mbps` and keep encoding
  `1920x1080` with
  `resolution_mismatch=req_1280x720_encoded_1920x1080`.
- Fallback requests such as `960x540/30fps/1.2Mbps` also keep encoding
  `1280x720`, so fallback can lower the app profile without proving the native
  pre-encode scaler obeyed the new bound.
- The native scaler proof is still missing from saved diagnostics. None of
  these files contain the expected
  `Inter Galactic desktop capture pipeline native_source=... requested_max=... pre_encode=...`
  line. That means the next build must prove the loaded patched `libwebrtc.dll`
  identity and Flutter WebRTC bridge invocation before further bitrate or
  fallback retuning.

### May 17 Assessment

- Fix the display-source start failure first. Add a guarded failure path around
  `LocalVideoTrack.createScreenShareTracksWithAudio`, log source type,
  source-id hash, profile, capture constraints, and native/platform exception
  details, then inspect the Windows `SourceType.Screen` source-id path through
  LiveKit and `flutter_webrtc`.
- Restore source-picker thumbnails/previews. The user-visible missing screen
  preview is the existing source-picker preview surface, not a separate stream
  preview feature.
- Prove the active native capture artifact. Saved diagnostics need the loaded
  `libwebrtc.dll` path/hash/build marker plus a bridge marker showing the
  selected source type and requested max width/height passed into
  `StartWithMaxFrameSize`.
- Re-test Smooth, Balanced, and Advanced only after that proof. Smooth must
  show requested max `1280x720` and encoded/pre-encode output `1280x720` for a
  gameplay window before the remaining 20 FPS ceiling can be attributed to
  capture cadence, WebRTC source backpressure, or Media Foundation encode
  timing.
- Do not retune bitrate, fallback thresholds, or LiveKit adaptation from this
  batch. The clean route and under-target actual bitrate are effects of the
  sender only producing 14-21 FPS, not evidence of a bandwidth ceiling.

### May 17 Implementation Notes

- The source picker and publish path now refresh the native desktop-capture
  cache with both `Window` and `Screen` source families. This avoids the
  `flutter_webrtc` Windows bridge cache being narrowed to windows by thumbnail
  refreshes before a display source is published.
- The picker waits briefly for asynchronous native thumbnail events, then
  triggers one full source refresh if all thumbnails are still empty. This
  restores the existing source-picker preview surface without adding stream
  previews.
- Windows screen share track creation now uses LiveKit's video-only
  `createScreenShareTrack` path. Shared-content audio remains owned by the
  separate Windows `ShareSession` pipeline, so LiveKit no longer forces
  `captureScreenAudio=true` on Windows.
- The LiveKit publish path logs source type, source-id hash, requested max
  dimensions, FPS, and capture-audio intent before track creation. Track-create
  failures are now logged with the same source/cap context instead of escaping
  only as an unhandled app-zone stack.
- The patched `flutter_webrtc` installer now upgrades an already-scaled bridge
  with an `Inter Galactic desktop capture bridge start` native log line. New
  stream logs should include both the bridge marker and the existing native
  capture pipeline line before any further FPS retuning.
- 2026-05-17 build follow-up: the bridge marker must use the plugin-side
  logging style (`std::cout`), not `rtc_base/logging.h`, because
  `flutter_screen_capture.cc` is compiled by the Flutter plugin project rather
  than inside libwebrtc's private include tree. The installer now repairs stale
  package-cache sources that still contain the missing header or `RTC_LOG`
  bridge call.
- 2026-05-17 build follow-up: the patched Windows libwebrtc artifact does not
  export flutter_webrtc's optional media `FrameCryptorFactory` sender/receiver
  constructors. Inter Galactic uses Matrix room E2EE rather than that optional
  media FrameCryptor path, so the installer stubs only the Windows
  `FrameCryptorFactoryCreateFrameCryptor` plugin method to fail open at
  runtime and keep the plugin link step compatible with the patched artifact.
- 2026-05-17 dependency-prep follow-up: the FrameCryptor patch is now
  idempotent for both the normal Pub cache and the local user cache directory
  used by maintainer builds. It detects the
  `FrameCryptorFactoryCreateFrameCryptorUnavailable` stub, or a source that no
  longer contains the missing sender/receiver factory exports, before patching;
  fresh stock sources are replaced by method boundaries instead of a brittle
  exact line-format regex.
- The in-call Call Diagnostics panel now has a report action that writes the
  current route/capture/encode/render diagnostic snapshot into recent redacted
  logs, then opens the existing Help -> Report a Bug email/upload flow with
  logs and device diagnostics enabled.

## 2026-05-18 BG3 1920x1080 Capture-Cadence Follow-Up

- New stream-test logs compared a BG3 DX11 window changed to 1920x1080 against
  earlier 2560x1440 window and static-desktop captures. Lowering the game
  window to 1920x1080 did not materially improve gameplay-window FPS: Smooth
  and Balanced still sat around 12 FPS, and High Quality reached only the
  mid-teens.
- The strongest new discriminator is the Advanced Override VP8 run. It encoded
  1280x720 with `libvpx`, `hw=false`, and roughly 8 ms encode time, but
  capture/pre-encode/encoded/sent FPS still stayed around 11-13 FPS. That
  makes the primary bottleneck upstream of H.264 hardware encoding for this
  game-window path.
- The H.264 Advanced Override log that was expected to be "hardware off" still
  selected `MediaFoundationH264 hw:yes`. The profile toggle only controls
  whether Inter Galactic forces hardware-first H.264; it does not forbid
  WebRTC from choosing a hardware encoder when the requested codec is H.264.
  Future logs must show both the requested hardware preference and the actual
  selected encoder implementation.
- Task Manager GPU Video Encode usage of roughly 1-3% is consistent with the
  logs: the GPU encode engine is not saturated. H.264 `encode_ms` around 80 ms
  may include upstream frame delivery, copy, or synchronization wait rather
  than pure hardware encode work.

## 2026-05-20 Black-Stream Recovery Note

- After live stream-lab republish experiments, app-started BG3 shares selected
  valid sources and the native capturer continued submitting scaled frames, but
  every H.264 sender encoded zero frames and logged `SignalEncoderTimedOut`.
  LiveKit still published the local track, so receivers saw a black stream.
- The release-candidate recovery is to stop forcing Windows normal presets through
  the hardware-first H.264 profile. Smooth, Balanced, and High Quality now use
  their normal VP8 preset path unless the developer hardware encoder toggle is
  explicitly enabled.
- Hardware H.264 remains available for targeted diagnostics and advanced
  override tests, but normal app-started sharing should prioritize visible
  video over the still-unresolved Media Foundation timeout path.

### May 18 Implementation Notes

- Saved call diagnostics and stream-test reports now include applied profile
  details: advanced override state, requested resolution/FPS/bitrate, requested
  codec, hardware preference, simulcast, low layer, and degradation preference.
  Sender lines still report the actual selected codec, encoder implementation,
  and hardware-active inference.
- The stream-test runner now labels low-cadence game/window runs as
  `capture_or_preencode_limited` when capture/pre-encode, encode, and send FPS
  move together below target. This label takes priority over high encode-time
  and send-delay symptoms so H.264 synchronization wait does not masquerade as
  a saturated encoder.
- The next useful investigation target is Windows desktop/window capture
  cadence for active DX game windows. Compare BG3 display capture, BG3
  alternate graphics/window modes, and a non-game high-motion window before
  changing bitrate, fallback, or LiveKit adaptation policy.

## 2026-05-18 Native Capture Cadence Patch

- The final pre-change log pass was strong enough to make one real streaming
  change: the low-FPS BG3 window path is upstream of network and often
  upstream of pure encoder cost. Smooth/Balanced/High Quality had clean loss,
  low RTT, and enough outgoing bitrate, while capture/pre-encode/encode/send
  FPS moved together below target.
- The native Windows desktop capturer now enables faster Windows capture
  backends where the patched libwebrtc build supports them: DirectX remains
  enabled, Windows Graphics Capture screen/window capture is enabled when
  `RTC_ENABLE_WIN_WGC` is present, WGC fallback is enabled, and the cropping
  window capturer is allowed as a lower-level fallback for frame cadence.
- The native capture loop no longer waits a full frame interval after capture
  work completes. It measures each `CaptureFrame()` call and schedules the
  next capture after `target_interval - capture_work`, or immediately when the
  work already exceeded the target interval. This is intended to remove the
  observed "capture work time plus 33 ms" cadence penalty.
- New native diagnostics log the selected backend option flags and a
  `desktop capture cadence` summary with target delay, average/max capture
  call time, scheduled delay, and call count. Existing pipeline diagnostics
  still log native source size, requested max, pre-encode size, target FPS,
  emitted native FPS, scale state, and crop-region state.
- The Flutter WebRTC installer now rejects patched libwebrtc zips that do not
  expose the Inter Galactic `StartWithMaxFrameSize` desktop-capture scaler API.
  This prevents accidentally testing a stock/stale artifact after rebuilding
  app code.
- Native rebuild completed with
  `ninja -C out-release\Windows-x64 libwebrtc`; the only compiler output was
  existing Media SDK deprecation warnings. The patched Windows artifact was
  repackaged at
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with SHA-256
  `4FA8997CBFC4207BC201C28F8AAFE1004885A266D0FD308738D30208307855C2`.
  The previous zip was preserved as a timestamped `.bak-*` file in the same
  artifact folder.
- The app dependency-prep installer accepted and installed the rebuilt artifact
  into the active Flutter WebRTC package cache, and
  `flutter build windows --debug --no-pub` passed with the local
  AppData workaround.

### Validation Required

- Live-stream a BG3 window and a BG3 display capture with Smooth, Balanced,
  High Quality, and VP8 720p30 advanced override.
- Confirm logs include `desktop capture options`, `desktop capture cadence`,
  `desktop capture bridge start`, and `desktop capture pipeline` lines.
- Compare capture FPS, pre-encode FPS, encoded FPS, sent FPS, encode time,
  available outgoing bitrate, loss, RTT, and receiver rendered FPS before
  making any bitrate, fallback, or LiveKit adaptation changes.

## 2026-05-19 BG3 Encoder-Pipeline Diagnostics Patch

- The next BG3 1920x1080 stream-test logs showed resolution capping working:
  Smooth encoded 1280x720 and Balanced/High Quality encoded 1920x1080. Loss,
  NACK, RTT, layer selection, and quality-limitation reasons stayed clean, but
  H.264 encode time sat around 75-78 ms while capture, encode, and send FPS
  moved together around 13 FPS.
- The stream-test runner now distinguishes this pattern from a pure capture
  limiter. When low capture/encode/send FPS track together and average encode
  time exceeds the frame budget, reports label the bottleneck
  `encoder_pipeline_limited` and include encode-time, send-delay, and missing
  pre-encode evidence. Lower-cadence runs without slow encode remain
  `capture_or_preencode_limited`.
- Stream-test JSON/Markdown now includes a native diagnostic marker tail by
  clearing and reading the bounded Windows sidecar
  `%TEMP%\intergalactic-native-webrtc-diagnostics.log`. This captures matching
  native lines such as desktop capture options/cadence/frame-size/pipeline, the
  bridge-start marker, Media Foundation encoder setting acceptance/rejection,
  and Media Foundation H.264 encoder timing without requiring manual log
  copying.
- The Media Foundation H.264 native encoder now emits throttled per-frame
  timing breadcrumbs for `ToI420`, I420-to-NV12 conversion, input buffer copy,
  `ProcessInput`, pre/retry/post drain, `ProcessOutput`, output-copy time,
  output frame count/bytes, queue depth, async state, and whether the frame
  exceeded the target frame budget. CodecAPI setup now logs accepted settings
  as well as rejected settings.
- No stream profile, bitrate, fallback, scaler, simulcast, LiveKit adaptation,
  or receiver policy was retuned in this patch.
- Native rebuild completed with
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`.
  The patched Windows artifact was repackaged at
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `502DCB3C2CB2057510DE09E1531DEDE8351CF95CA0B117EEFCC141B6F59152C5`
  and DLL SHA-256
  `4FF5442E68BAE23BE45F46CC4C288EFA3B6D6034DF4E61CE03E0220D03692FC5`.
  The installer accepted the rebuilt artifact and
  `flutter build windows --debug --no-pub` passed with local
  AppData.

### Next Validation Target

- Run one BG3 stream-test pass from the new build. The key output is whether
  the native marker section contains Media Foundation encoder timing lines,
  whether capture cadence/pipe lines are present, whether `process_output_ms`
  or `input_copy_ms` dominates the 75-80 ms frame cost, and whether the sender
  still reports `encoder_pipeline_limited` after the native cadence patch.

## 2026-05-19 Native Capture Backend Override Patch

- The stream-test runner now parses native desktop-capture markers instead of
  only preserving them as a tail. Reports extract selected backend mode,
  requested max resolution, native source size, pre-encode size, native emitted
  FPS, capture-call timing, and Media Foundation encoder timing.
- Bottleneck classification now has a separate `native_capture_limited` label.
  It is used when capture/encode/send FPS track below target, native capture
  call time or native emitted FPS proves the native capturer is slow, and the
  native Media Foundation encoder timing is below the frame budget. This keeps
  slow capture backends from being lumped into pure encoder pipeline cost.
- Developer stream-test configuration on Windows now exposes a debug-only
  capture backend selector: Default, WGC only, DirectX only, and Window crop
  fallback. Normal calls and normal stream publishing do not set this override.
- The Flutter WebRTC bridge patch now forwards
  `intergalacticCaptureBackend` to the native desktop capturer before
  `StartWithMaxFrameSize`, and logs the selected backend in the bridge-start
  marker.
- The native desktop capturer exposes
  `SetWindowsCaptureBackendMode(...)` and rebuilds its desktop-capture options
  before capture starts. It logs the selected native flags for DirectX, crop
  window, WGC screen, WGC window, and WGC fallback.
- Native rebuild completed with
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`.
  The patched Windows artifact was repackaged at
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `CC50381BFB869BF3DA5435C11091EFE09366034BC8A2AB519BEB648DD93B6C56`
  and DLL SHA-256
  `11B613C22AFB7E3CC98A01C525B652F503060FCE231F05726767DB1A2EF560D4`.
  The previous zip was preserved as
  `libwebrtc.zip.bak-20260519-110821-502DCB3C2CB2057510DE09E1531DEDE8351CF95CA0B117EEFCC141B6F59152C5`.
- The app dependency-prep installer accepted the rebuilt artifact and
  `flutter build windows --debug --no-pub` passed.

### Next Validation Target

- Run BG3 stream tests with the same preset set and, if time allows, one pass
  each for WGC only and DirectX only. The key comparison is whether low FPS
  follows a specific native backend, whether the new report labels the run
  `native_capture_limited` or `encoder_pipeline_limited`, and whether exact
  pre-encode dimensions still match the requested profile cap without crop.

## 2026-05-19 Backend Override Tests And Capture Timing Split

- The default/WGC-only/DirectX-only BG3 logs showed that WGC/default window
  capture stayed around 11-14 FPS while DirectX-only improved to roughly
  21 FPS under the same resolution cap and clean network conditions. A later
  App-default run showed the danger of treating that as permanent backend law:
  once normal publishing was forced to DirectX-only, the same class of BG3
  window stream could still stall around 15-20 FPS at 1080p. Normal publishing
  therefore returns to the patched native default, and backend choice remains a
  debug stream-test override rather than a user-wide default.
- Debug stream-test runs can explicitly select Native default, WGC-only,
  DirectX-only, or window-crop fallback. App default now means the same path a
  real stream uses: no forced backend override unless the test asks for one.
- Stream-test native marker attribution now uses each preset's exact
  `[startedAt, endedAt]` window instead of padding the end by two seconds.
  This prevents the next preset's native frame-size or backend markers from
  being attributed to the previous preset.
- The native desktop capturer now logs `Inter Galactic desktop capture frame
  timing` with average convert, scale, `OnFrame`, full callback, max callback,
  and frame count values. Stream-test JSON/Markdown parses these values beside
  capture-call timing and Media Foundation encoder timing, which should show
  whether the remaining FPS loss is capture acquisition, ARGB-to-I420
  conversion, contain-fit scaling, WebRTC frame delivery, or encoder work.
- Rebuilt artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `430748BABA1222D91B5BB5CC11A9FF9148D015EA9F09633D1A06713E1BC4A4F6` and DLL
  SHA-256
  `491C26DE5E5ADA2885C85F72227FB29225F9E57696537820E0E8341BF7904CEF`.
  The previous zip was preserved as a timestamped `.bak-*` in the same
  artifact folder.
- Validation passed: Dart format, focused Flutter test
  `test/client/components/voip/stream_test_runner_test.dart`, focused Flutter
  analyze, native
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`,
  patched-libwebrtc installer, and
  `flutter build windows --debug --no-pub`.

### Next Validation Target

- Run one normal BG3 window stream test with Smooth, Balanced, and High
  Quality. The report should show the patched native default backend, Smooth
  pre-encode `1280x720`, Balanced/High pre-encode `1920x1080`, and the new
  frame-timing breakdown.
- Run one display-share smoke test and verify it still publishes the full
  display frame without crop/stretch.

## 2026-05-19 Adaptive Capture Refresh Patch

- The BG3 gameplay window/display logs after the DirectX/default patch showed
  the decisive failure point: adaptive fallback moved the requested profile to
  Smooth (`1280x720@30`), but the active sender continued encoding
  `1920x1080`. Loss, NACK, RTT, and available outgoing bitrate stayed clean,
  while encode time remained high and FPS stayed below target.
- On Windows, sender RTP parameters are not enough to change the native
  desktop-capture scaler bounds after a track has already been created. The
  app now recreates the local screen-share video publication when adaptive
  fallback or recovery changes the native capture layer width, height, or FPS.
  This keeps the same selected source, same ShareSession, and existing
  shared-audio state, but forces the next `StartWithMaxFrameSize` call to use
  the new profile bounds.
- The refresh is limited to Windows desktop/window screen-share sources. Other
  platforms continue to use sender-parameter updates only.
- The stream-test runner's Windows backend selector starts on "App default",
  which measures normal app behavior without forcing a native backend override.
  "Native default", WGC-only, DirectX-only, and window-crop fallback remain
  available as explicit comparison overrides.
- Stream-test bottleneck classification now reports
  `resolution_limit_not_applied` when the requested cap is lower than the
  encoded frame size, so this failure no longer hides behind generic encoder
  or capture labels.
- Automated stream-test sampling now evaluates adaptive fallback on each
  1-second diagnostics snapshot. Before this patch, each forced sample updated
  `_lastUpdatedDiagnostics`, which could starve the normal 2-second
  `updateStats()` path and prevent fallback from firing during the exact runs
  meant to validate it.
- Adaptive fallback now treats sustained capture-stage FPS deficit as
  actionable only when capture, encode, and send FPS move together below 75% of
  target on a clean network route. This lets a 1080p stream downshift and
  recreate native capture bounds when the capture cadence is the limiter,
  without blaming DirectX, WGC, or bandwidth from one ambiguous label.
- Validation passed: Dart format; focused Flutter tests
  `screen_share_adaptive_fallback_test.dart` and
  `stream_test_runner_test.dart`; focused Flutter analyze for the touched
  streaming files; and `flutter build windows --debug --no-pub`.

### Next Validation Target

- Run BG3 gameplay window and display tests with App default first, then only
  add explicit WGC-only or DirectX-only overrides if App default still misses
  720p30. Success means sustained low capture/encode/send FPS triggers
  `capture FPS below target`, recreates the Windows screen-share track, and the
  post-fallback sender reports requested/pre-encode/encoded `1280x720` with FPS
  approaching 30 instead of staying at `1920x1080`.
- If 720p30 stabilizes, the next tuning pass can focus on making 1080p30
  viable without changing fallback architecture again.

## 2026-05-19 Evening Capture-Cadence Follow-Up

- Fresh BG3 window and display tests proved the contain-fit scaler is doing the
  right resolution work: native markers showed full-frame 2560x1440 sources
  scaled to the requested 1920x1080, 1280x720, 960x540, and 640x360 outputs
  without crop-region mode.
- Network evidence stayed clean during the poor-FPS runs: loss was 0%, RTT was
  single-digit milliseconds, available outgoing bitrate stayed around the
  expected high headroom, and receiver-side FPS matched what the sender sent.
- Smooth display capture was the first encouraging result at roughly 28 FPS for
  1280x720, while 1080p Balanced/High and BG3 window runs still sat closer to
  16-25 FPS. That points to native capture cadence and source/backend behavior,
  not bitrate, as the next discovery target.
- Adaptive fallback had one harmful behavior left: clean capture-limited runs
  could be labeled as encoder overload because WebRTC exposed high
  encode-time/CPU symptoms even when capture, encode, and send FPS all moved
  together. The controller now lets that evidence downshift High Quality or
  Balanced to Smooth, then stops at Smooth instead of continuing to 960x540,
  640x360, or CPU rescue without corroborated network, software-encoder,
  severe-collapse, or encode/drop/send-queue pressure.
- The stream-test runner now logs its report export result into the same
  call-diagnostics/log-email path: saved Markdown/JSON paths are listed when
  available, and write failures are visible as `export failed: ...` instead of
  requiring manual path hunting after a run.

### Next Validation Target

- Run one App-default BG3 or desktop stream test and confirm Smooth stays at
  1280x720 when the problem reason is `capture FPS below target`.
- If Smooth display remains near 30 FPS, use the next discovery pass to compare
  why BG3 window capture still under-runs: source type, backend choice, native
  capture timing, and game/window compositor behavior are now the useful
  variables.

## 2026-05-19 Stream Capture Cadence Lab Implementation

- Implemented the required measurement-first stream capture cadence plan before
  behavior changes. The pass deliberately does not retune stream profiles,
  bitrates, fallback thresholds, LiveKit defaults, or receiver policy.
- The debug stream-test runner now has a Windows backend comparison mode. For a
  single selected source it can run each selected preset against App default,
  Native default, WGC-only, DirectX-only, and window-crop diagnostic backends,
  producing one JSON/Markdown report instead of requiring separate manual runs.
- Reports now include requested backend, native backend when logged, submitted
  native FPS, p95/max native frame interval, capture wait/permanent errors,
  crop-region state, and a subjective-notes placeholder for the visible remote
  result.
- The native desktop capturer now emits `Inter Galactic desktop capture frame
  cadence` markers with submitted FPS and frame-interval evidence, plus wait
  and permanent error counts. Existing frame-size, pipeline, frame-timing, and
  Media Foundation encoder markers remain intact.
- Rebuilt artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `C48E87D9CF0A0A6511100665913295E899A0C14B7F0168EB051BEE40E551E43D` and DLL
  SHA-256
  `C36E6397AEA5BA6295402BE8ABA3961FFF01DDD5BFFA3F44368F92CE05C1055E`.
  The previous zip was preserved as a timestamped `.bak-*` in the same
  artifact folder.
- Validation passed: Dart format, focused Flutter test
  `test/client/components/voip/stream_test_runner_test.dart`, focused Flutter
  analyze, native
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`,
  patched-libwebrtc installer, and
  `flutter build windows --debug --no-pub`.

### Next Validation Target

- Run one BG3 window stream test with the new "Compare Windows backends" option
  enabled for Smooth first. If duration allows, include Balanced as a second
  preset; otherwise keep it to Smooth so the run stays readable.
- For the report, check whether App default, Native default, WGC-only, or
  DirectX-only produces the best submitted native FPS and smallest p95/max
  frame interval, while keeping `crop_region=false` for normal backends.
- Use the visible receiver frame as a sanity check. The crop diagnostic is
  allowed to crop for evidence, but normal App/WGC/DirectX/default runs must
  still show the whole source frame without crop or stretch.

## 2026-05-20 Stream-Lab Live Backend Switch Follow-Up

- The first live stream-lab run against an already active BG3 window stream
  confirmed the 720p cap and hardware path in app-default mode:
  `1280x720`, H.264 `MediaFoundationH264`, hardware encode active, no WebRTC
  quality limitation, 0% loss, roughly 1-2 ms RTT, and 0 NACK. The stream still
  averaged about 21 FPS, with capture/encode/send FPS moving together.
- Native app-default diagnostics from that healthy sender showed source
  2560x1440, pre-encode 1280x720, `crop_region=false`, average native FPS in
  the mid-20s, and p95 frame interval around 70 ms. That keeps the active
  performance target on capture cadence rather than bitrate.
- WGC-only and DirectX-only live backend overrides exposed a harness/republish
  failure: LiveKit published a sender, but WebRTC stats stayed at zero
  captured, encoded, and sent frames. The native sidecar only logged backend
  option selection after the switch and did not emit fresh frame cadence or
  encoder timing markers.
- The fix is to stop the existing Windows screen-share video publication
  before creating the replacement capturer during live stream-lab or adaptive
  fallback refresh. This accepts a short stream gap but avoids overlapping
  desktop capturers that can leave the replacement sender frame-starved.
- The PowerShell live runner now classifies a published sender with zero
  captured/encoded/sent frames as `no_sent_frames` and applies the full
  downgrade penalty, so future summaries do not report that state as healthy.
- Added `smooth-720-native-default.json` as an explicit reset/control config
  because omitting `captureBackend` means "leave the current backend as-is",
  while `captureBackend: "default"` actively clears a WGC/DirectX override.

### Next Validation Target

- Restart into the rebuilt debug executable, start a fresh BG3 window share
  with the desired preset/advanced override, then run the stream-lab runner in
  `-ObserveOnly` mode. This preserves the active app-started capture path and
  still collects structured sender/native diagnostics without forcing a live
  republish.
- Run `smooth-720-directx` only as the last sample in a sequence or after a
  fresh share start. Fresh 2026-05-20 validation showed DirectX can publish a
  valid 720p sender first, but switching away from active DirectX without a
  full stop/start can leave the next sender with zero captured, encoded, and
  sent frames. The live harness now logs this as a restart boundary and skips
  in-place switches away from DirectX to keep later reports from being
  contaminated.
- A later May 20 run showed the live-republish path can also create a
  zero-frame sender for native-default/WGC when applied to an already active
  BG3 share. The PowerShell runner now aborts remaining configs on
  `no_sent_frames` or `no_stats`, disables live tuning, and provides
  `-ObserveOnly` for release-candidate measurement.
- Success means native-default/WGC runs report nonzero captured/encoded/sent
  frames, fresh native frame-cadence markers after the switch time, and no
  visible crop/stretch.

## 2026-05-20 Window Geometry Capture Fix

- Follow-up manual validation showed the black-window boundary was window
  geometry, not hardware: borderless windows producing a full 1920x1080 frame
  could share, but normal windowed mode and other non-borderless windows failed.
  VP8 with hardware preference off reproduced the failure, while display share
  worked in the same build.
- The native desktop capturer previously used the HWND `GetWindowRect()` size as
  the source dimensions for `libyuv::ConvertToI420`. That works for borderless
  windows where the outer rectangle and captured buffer match, but normal
  windows can capture a client-area frame shorter than the outer window. The
  native path now converts from the actual `DesktopFrame` buffer size and logs
  the outer rectangle separately as `window_rect`.
- Windows window sources using `StartWithMaxFrameSize` now emit a stable
  preset-sized encoder canvas and center the contain-fit content inside it.
  Example: a captured `1920x1048` window under a `1920x1080` cap publishes
  `pre_encode=1920x1080` with letterbox padding instead of crop/stretch or a
  fragile non-16:9 sender size. Display capture keeps exact dynamic contain-fit
  dimensions.
- The app-side `SourceType.Window` single-layer publish guard remains in place
  as release-candidate protection, but the native canvas fix is the primary
  geometry repair. Windows hardware-first H.264 is restored as the preferred
  default; developer controls can still disable it for explicit VP8/software
  comparison.
- Rebuilt artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `95F9A32CC25273A08348FFA3E04A3083B5955D7B5B2FDD8F9C3BCBCFFD490B88` and DLL
  SHA-256
  `5CCA98473FCE9566B8A31C0823DFAA58118C8B661AEDDE9A7F22FE3F4E43B989`.
- Validation passed: Dart format for `preferences.dart`, focused Flutter test
  `test/client/components/voip/screen_share_quality_profile_test.dart`,
  focused Flutter analyze for touched streaming/preferences files, native
  `{DEPOT_TOOLS}\ninja.bat -C
  {WEBRTC_BUILD_ROOT}\out-release\Windows-x64 libwebrtc`,
  patched-libwebrtc installer, and
  `flutter build windows --debug --no-pub`.
- Review validation passed for the post-geometry parser/failure-state fixes:
  Dart format, focused Flutter test
  `test/client/components/voip/stream_test_runner_test.dart`, targeted Flutter
  analyze for the stream session/runner/test files, and `git diff --check`.

### Next Validation Target

- Start a fresh app window share from a normal windowed game and from one
  non-game desktop window. The receiver should see the full source, and native
  diagnostics should show actual captured `source=...`, separate
  `window_rect=...`, `content=...`, and `pre_encode=1280x720` or `1920x1080`.
- Recheck one display share to confirm it still uses dynamic contain-fit output
  and remains visible.
