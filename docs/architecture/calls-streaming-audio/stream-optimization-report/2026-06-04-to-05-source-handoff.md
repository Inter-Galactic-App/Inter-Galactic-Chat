# 2026-06-04 To 2026-06-05 Source Handoff Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-05 Phase 4D WebRTC Source GPU Scale

- Post-scheduler live Smooth 720p BG3 validation at
  `stream-test-2026-06-05T19-18-37-975209Z` passed the target boundary. The
  report classified the run as `healthy` with high confidence: source
  `2560x1440`, output/encoded `1280x720`, capture/encode/send
  `34.8/34.7/34.7 FPS`, frame pacing around `29/30/33 ms` p50/p95/max,
  hardware `MediaFoundationH264`, clean route, `qualityLimitationReason=none`,
  visible proof `2/2`, visible I420 proof `1/1`, `gpuScaled=2268`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `readbackNotReady=45`,
  `readbackOverwritten=4`, and helper teardown through
  `cleanup helper_exited`. This clears the Smooth 720p30 gameplay gate for the
  debug D3D11 game-hook path.
- A later side run at `stream-test-2026-06-05T19-21-00-417649Z` requested High
  Quality `1920x1080@60` and should not be treated as a Smooth regression. It
  proved the GPU path still stayed active (`gpuScaled=721`,
  `gpuFailures=0`, `cpuFallback=0`), but the report classified
  `native_capture_limited` with stale frame windows, high `readbackNotReady`
  and `readbackOverwritten`, and higher encode cost at 1080p60. The next
  quality target should be controlled 1080p30 work, not another 720p Smooth
  data-gathering loop.
- The rebuilt Debug Smooth 720p BG3 live validation at
  `stream-test-2026-06-05T18-56-00-982960Z` proved the async GPU readback path
  landed in the real app: source `2560x1440`, output and encoded
  `1280x720`, visible proof `2/2`, visible I420 proof `1/1`,
  `gpuScaled=1838`, `gpuScaleFailures=0`, `cpuFallback=0`, hardware
  `MediaFoundationH264`, clean route, and helper `cleanup helper_exited`.
  The active limiter is no longer GPU-scale failure or blocking scaled
  `Map`; it is residual pacing jitter. Capture/encode/send averaged about
  `29.8 FPS`, but p95/max frame gaps were about `55/115 ms`.
- The native WebRTC game-capture source now drains one ready async readback
  before queueing the next scaled frame and uses an eight-slot scaled-readback
  ring. The previous four-slot ring lived on the edge of the observed live
  latency: readback latency sat near three frames, with
  `readbackNotReady=292` and `readbackOverwritten=290` over the 60-second BG3
  run. Submitting an already-ready slot before writing a new one avoids
  overwriting an almost-ready frame and should reduce p95/max sender gaps
  without changing bitrate, profiles, LiveKit, or fallback behavior.
- Exact local WebRTC-source smoke against the rebuilt native DLL passed after
  the readback scheduler patch: source `1920x1080`, output `1280x720`,
  `submitted=184`, `gpuScaled=184`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackQueued=185`, `readbackReady=184`, `readbackNotReady=0`,
  `readbackOverwritten=0`, `readbackMapAttempts=184`,
  `gpuScaleMs=0.00243 ms`, `copyMs=0.02124 ms`, `mapMs=0.00042 ms`,
  `convertMs=0.08315 ms`, readback latency `3.548 ms` /
  `0.114` frames average / `1` frame max, visible proof `2/2`, visible I420
  proof `1/1`, and no helper process left behind. Report:
  `{LOCAL_STREAM_LAB_RESULTS_DIR}\webrtc-source-smoke-20260605-1502-readback-pacing\webrtc-source-smoke.json`.
- Current validation artifacts for the scheduler patch: patched
  `libwebrtc.zip` SHA-256
  `09FACF127DAA49D44D46E7F1B1414E97B6A47399588CFFC806A066E7B9108FF1`;
  staged/global/plugin/Debug runner `libwebrtc.dll` SHA-256
  `53B36EBD511FB8130B7B88CFE85DB2A8209DE81A797308F1BD76AFF48DA105EE`;
  Debug `flutter_webrtc_plugin.dll` SHA-256
  `28D1381F7A732A14D3D736E49A8AA8F47094A90A97361C8DAABED3F0C4BF2A1E`.
  The follow-up Smooth 720p BG3 live test confirmed those counters and p95/max
  sender gaps dropped enough to classify the path as healthy.
- Follow-up live Smooth 720p BG3 validation of the shader/SRV GPU-scale path
  proved the previous `input_view_create_failed` fallback was fixed:
  `gpuScaled=994`, `gpuScaleFailures=0`, `cpuFallback=0`, visible proof
  `2/2`, visible I420 proof `1/1`, and helper teardown clean. Network and
  Media Foundation H.264 timing stayed clean. The active limiter moved to the
  synchronous scaled staging readback: `mapMs` climbed from about 13-18 ms to
  `34.504 ms`, while capture/encode/send settled around 24-26 FPS.
- Native libwebrtc now uses a four-slot asynchronous scaled-readback ring for
  the debug game-hook WebRTC source. Each frame queues GPU scale/copy into an
  output-sized staging slot, probes the oldest pending slot with
  `D3D11_MAP_FLAG_DO_NOT_WAIT`, and submits only ready frames. Reports now
  expose `readbackQueued`, `readbackReady`, `readbackNotReady`,
  `readbackOverwritten`, `readbackMapAttempts`, `readbackLatencyMs`,
  `readbackLatencyFramesAvg`, and `readbackLatencyFramesMax`.
- Exact local WebRTC-source smoke against the rebuilt Debug runner DLL passed
  after the async-readback patch: source `1920x1080`, output `1280x720`,
  `submitted=145`, `gpuScaled=145`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackQueued=146`, `readbackReady=145`, `readbackNotReady=0`,
  `readbackOverwritten=0`, `readbackMapAttempts=145`,
  `gpuScaleMs=0.00496 ms`, `copyMs=0.04923 ms`, `mapMs=0.00091 ms`,
  `convertMs=0.18044 ms`, readback latency `10.914 ms` /
  `0.234` frames average / `1` frame max, visible proof frames `2/2`, visible
  I420 proof `1/1`, and no helper process left behind. Report:
  `{LOCAL_STREAM_LAB_RESULTS_DIR}\webrtc-source-smoke-20260605-142427\webrtc-source-smoke.json`.
- The current patched artifact is `libwebrtc.zip` SHA-256
  `27155394E49DB4A0071EFC32019C09B4D9F7B8718DE339337B84BE0CEE625AD3`;
  staged, global Flutter WebRTC cache, plugin symlink, and rebuilt Debug
  runner `libwebrtc.dll` all match SHA-256
  `CDE515401B4769B4FC3BCC1C660D2F349164D0F31B4A0D654C60075934FAA746`.
  The next validation is one Smooth 720p BG3 live test, now specifically to
  prove live sender FPS and readback counters after the local source boundary
  cleared.
- Follow-up after the first GPU-scale build found the actual failure boundary:
  every BG3 frame still fell back to CPU because the WebRTC source attempted to
  create a D3D11 video-processor input view directly on the shared source
  texture and hit `input_view_create_failed hr=0x80070057`. The fix now uses
  the helper-proven shader path instead: create/cache a source
  `ID3D11ShaderResourceView`, draw a full-screen triangle into an output-sized
  BGRA render target, then stage/map only that scaled texture. This avoids
  changing crop semantics and keeps contain-fit scaling before readback.
- Exact local WebRTC-source smoke passed against the synthetic D3D11 target
  using the rebuilt Debug runner DLL: source `1920x1080`, output `1280x720`,
  `gpuScaled=103`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `gpuScaleMs=0.009 ms`,
  `mapMs=1.192 ms`, `convertMs=1.005 ms`, visible proof frames `2/2`, and
  visible I420 proof `1/1`. Report:
  `{LOCAL_STREAM_LAB_DIR}\webrtc-source-smoke-20260605-133705-debug-dll\webrtc-source-smoke.json`.
- The final patched artifact for this pass is `libwebrtc.zip` SHA-256
  `CAD4ADF1A4CBBD49D058B08DF928BF9AD1C60557317FC7396EF275E02C4CB8C6`; the
  rebuilt Debug runner `libwebrtc.dll` SHA-256 is
  `0EC17B36B313B9C38FBE3AC6229B10D5ACB3A1300805378168AAEAF8D8C0B6EE`.
  Next validation may now be one Smooth 720p BG3 live test.
- The latest 60-second Smooth `game-d3d11-hook-experimental` BG3 window run
  changed the active boundary. The stream was visible and helper teardown was
  clean, but capture, encode, and send FPS tracked together around 15.6 FPS on
  a clean route with H.264 and no WebRTC quality limitation. The native
  `game_capture_webrtc_source` markers showed the helper copied thousands of
  shared frames, while the WebRTC source only submitted 965 frames because it
  still mapped the full 2560x1440 shared texture and CPU-scaled/converted it
  before handing I420 to WebRTC. Typical `mapMs` was about 41-49 ms and
  `convertMs` about 17-19 ms; native Media Foundation encoder timing stayed
  low, so this was not a bitrate, LiveKit, network, or hardware-encoder limit.
- Native libwebrtc now moves that debug game-hook WebRTC source boundary onto a
  D3D11 shader/SRV scale path: it samples the full shared source texture into
  the requested output-sized BGRA render target on the GPU, copies only that
  scaled output to staging, maps the smaller frame, then runs the existing I420
  conversion and WebRTC frame submission. The previous full-source CPU path
  remains a fallback and is counted as `cpuFallback`.
- Stream-test JSON/Markdown now parse and surface the new native fields:
  `gpuScaled`, `gpuScaleFailures`, `cpuFallback`, and `gpuScaleMs`. The next
  report should prove whether frames are using GPU scaling or falling back to
  the old CPU readback path.
- Validation passed with native `ninja -C ...\out-release\Windows-x64
  libwebrtc`, native libwebrtc source commit `7395e5e`, refreshed patched
  `libwebrtc.zip` SHA-256
  `82B9650FBB5D89B1E06DD58DAAEC65BCFFB0C9E0F48E9459AEAC43363BB81B98`,
  staged/Debug `libwebrtc.dll` SHA-256
  `005E34A9123AA99415A4F167C625DE71E023FD62526E4656FE024C0A638EA592`,
  patched Flutter WebRTC installation, focused `stream_test_runner_test.dart`
  passing `+56`, focused Flutter analyze on the touched runner files, and a
  Windows Debug rebuild. The Debug runner `flutter_webrtc_plugin.dll` SHA-256
  is `CB793661ED497FC69EC2691128EF349A01B197A30D60711AC796C10006D84D09`; the
  Debug Dart payload SHA-256 is
  `10FEFAA3856459A13C29237E8ADE7B71D9240D20A119B4EB7E67D80014554014`.
- Next validation should run one 60-second Smooth BG3 window stream with
  `game-d3d11-hook-experimental` from the rebuilt Debug app. Pass criteria:
  visible full-frame output, `Observed Capturer: game-d3d11-hook`, nonzero
  `gpu_scaled`, zero or near-zero `cpu_fallback`, no `gpu_failures`,
  `map`/`convert` below the 30 FPS frame budget, sender FPS near 30, clean
  helper teardown after stop, and no `intergalactic_game_capture_helper`
  process left behind.

## 2026-06-05 Phase 4D Helper Lifecycle Cleanup

- Fresh live validation still rendered black remotely after startup
  black-frame suppression, but the newest stream-test/native evidence moved the
  boundary again. The active `game_capture_webrtc_source` wrote visible,
  full-frame, color-correct post-I420 proof BMPs and Media Foundation H.264
  encoder timing logs showed output bytes from 1280x720/1920x1080 frames.
- The same run exposed a separate lifecycle bug: multiple
  `intergalactic_game_capture_helper` processes remained alive after preset
  stop and continued logging stats for earlier 720p/1080p sessions. Their
  helper logs showed one-hour live durations and `hook_wait_begin` with no
  `hook_wait_complete` / `helper_stop`, meaning stopped presets were not
  actually tearing down the hook sessions.
- The app stop path now explicitly calls
  `_stopLocalScreenShareVideoPublications(reason: 'screen-share stop')` before
  LiveKit `setScreenShareEnabled(false)`. This is required for manually created
  Windows screen-share tracks published through `publishVideoTrack`, including
  the debug D3D11 game-hook source.
- Follow-up validation showed why the first cleanup patch did not run during
  the stream-test `finally` block: `isSharingScreen` only returned LiveKit's
  `localParticipant.isScreenShareEnabled()` helper flag, while the Windows
  game-hook path manually publishes a `screenShareVideo` publication. The
  getter now also checks local screen-share video publications, and that
  publication filter matches LiveKit `isScreenShare`, `TrackSource.screenShareVideo`,
  or the `screenshare` track name.
- A second validation showed LiveKit was unpublishing the `screenshare` track
  before the manual cleanup could still see and stop it, leaving the helper
  alive even though the publication disappeared. The stop path now stops local
  screen-share video publications before calling `setScreenShareEnabled(false)`.
- A follow-up Smooth validation still left the helper alive after the stream
  runner completed. App logs showed the manual `screenshare` publication was
  now found and unpublished, but no native `stop_capture` marker appeared.
  The cleanup helper now calls `LocalVideoTrack.stop()` before
  `removePublishedTrack(...)` for local screen-share video publications so the
  Flutter WebRTC capturer remains reachable while native teardown is requested.
- The next validation showed that Dart/LiveKit did request local track stop,
  but native `StopCapture()` still did not fire. The root cause was the patched
  Flutter WebRTC game-capture branch returning before registering
  `base_->local_streams_[uuid] = stream`; `trackDispose` scans that stream map,
  so it could not find the game track and never stopped the capturer/helper.
  The installer now registers game-capture streams before returning and also
  hardens `MediaStreamTrackDispose` to stop any orphan video capturer by track
  id as a defensive cleanup path. This same native stream ownership gap could
  also explain black local rendering despite visible I420 and encoded sender
  evidence.
- The native game-capture WebRTC source now logs `stop_capture` and `cleanup`
  steps, signals the helper stop event during both stop and cleanup, logs
  helper exit, and terminates its owned helper if graceful stop does not finish
  within the bounded cleanup wait.
- Validation passed with native `libwebrtc` rebuild, patched `libwebrtc.zip`
  SHA-256
  `1DAAE258A6D987783141910C4188173E383E18F1F478B5B0BEAC8A173EEBCB5C`,
  patched Flutter WebRTC installation, Windows Debug rebuild, Debug runner
  `libwebrtc.dll` SHA-256
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`,
  and focused Flutter analyze on `matrix_livekit_voip_session.dart`. A second
  app-side Debug rebuild after the `isSharingScreen` correction produced
  `build/windows/x64/runner/Debug/InterGalactic.exe`; the Debug Dart payload
  `data/flutter_assets/kernel_blob.bin` SHA-256 is
  `50249C5E177D3EC927F4F7DD27589C58E03D300A9D23D8818B5BE1476C334300`.
  The app-only rebuild after the `LocalVideoTrack.stop()` ordering correction
  produced Debug Dart payload SHA-256
  `4228A5B91DE08068C64792F2C788011F165926FF39F6E4FF8FCCBCBEED77393C`;
  `libwebrtc.dll` remained
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`. The
  Flutter WebRTC bridge ownership/lifecycle patch installed cleanly and the
  Windows Debug rebuild produced `flutter_webrtc_plugin.dll` SHA-256
  `23B7ADB5B2C988CCFFD1B9D716B47CC5CD78E419FB71BCEC00DCBF06C872DB50`.
- Next validation should start from a clean Debug app and run one Smooth BG3
  window test with `game-d3d11-hook-experimental`. Confirm the report has
  visible pre-I420 and visible `i420_proof` evidence, then stop the stream and
  confirm logs include the Flutter WebRTC media-stream lifecycle cleanup line
  or native `stop_capture worker_joined` plus `cleanup helper_exited`, and that
  no `intergalactic_game_capture_helper` processes remain. If proof frames are
  visible, encoder output bytes are present, cleanup is clean, and output is
  still black, the boundary moves past native stream ownership into WebRTC
  frame submission, LiveKit sender delivery, or receiver rendering.

## 2026-06-05 Phase 4D Startup Black-Frame Suppression

- The follow-up live Smooth `game-d3d11-hook-experimental` run still rendered
  black remotely, but the proof evidence moved the boundary. The first native
  WebRTC proof BMP and its reconstructed I420 proof were black; a later
  pre-I420 proof BMP from the same session was visible, full-frame, and
  color-correct BG3 at 1280x720. This means the helper/source can produce
  valid BG3 frames, but the WebRTC source was allowed to submit startup
  all-black frames before visible source content was established.
- The native game-capture WebRTC source now suppresses startup black frames for
  a bounded window until the first visible source frame is observed, logs
  `skip_initial_black`, `startup_visible_after_black`,
  `initialBlackSkipped`, and `visibleSourceSeen`, and still falls through after
  the bounded window so legitimate black loading scenes do not block forever.
- The post-I420 proof writer now records a visible I420 proof when a visible
  source frame is available, instead of only proving the first submitted black
  frame. Stream-test JSON/Markdown now preserve
  `game_capture_webrtc_source` markers as priority diagnostics, parse the new
  startup-black fields, and prevent stale window-GDI marker tails from
  mislabeling a game-hook run.
- Validation passed with native `libwebrtc` rebuild, refreshed patched
  `libwebrtc.zip` SHA-256
  `E30F5230290CF7891B425782A6AAD76C9CC5A6E3FAC919196F9BCBAD7E651A06`,
  focused `stream_test_runner_test.dart` passing `+56`, patched Flutter
  WebRTC installation, and Windows Debug rebuild. The Debug runner
  `libwebrtc.dll` SHA-256 is
  `450DFABB6AB772DC3BA03F2F7EAE1743E2A1FF1494B63BE1A23B9BAB61AFF6B9`.
- Next validation remains a single Smooth BG3 window test with the experimental
  D3D11 game hook. Expected report evidence: observed capturer
  `game-d3d11-hook`, nonzero `initial_black_skipped` only during startup,
  visible pre-I420 proof, visible `i420_proof`, and no stale window-GDI
  capturer classification.

## 2026-06-04 Phase 4C Local Encoder Proof

- Added a debug-only local Media Foundation H.264 encoder proof to
  `intergalactic_game_capture_helper.exe`. The proof consumes the scaled
  `DXGI_FORMAT_NV12` publication-handoff texture, uses a DXGI device manager
  with Media Foundation hardware transforms requested, writes a local MP4, and
  reports encoder lifecycle, output bytes, first/last errors, frame counts,
  GPU-copy timing, submit timing, initialization timing, and finalize timing.
- The PowerShell local harness exposes this as
  `-PublicationEncoderProof h264-mf`. It requires
  `-PublicationOutputFormat nv12` and rejects proof-frame capture in the same
  run, because visible PNG/luma proof readback must stay separate from encoder
  timing.
- Synthetic encoder-proof validation passed without Matrix, LiveKit, or WebRTC:
  `local-capture-20260604-204405` submitted 144 frames at 720p30 with zero
  write failures and about 0.063 ms average submit time;
  `local-capture-20260604-204425` submitted 145 frames at 1080p30 with zero
  write failures and about 0.065 ms average submit time; and
  `local-capture-20260604-204446` submitted 277 frames at 1080p60 with zero
  write failures and about 0.051 ms average submit time.
- A separate non-encoder visible-proof run
  `local-capture-20260604-204830` still wrote one visible NV12 publication
  proof frame, confirming the pixel-inspection path remains available.
- Live BG3 local validation passed after the synthetic baseline:
  `local-capture-20260604-210942` produced 3 / 3 visible full-frame,
  color-correct NV12 proof frames from the actual 2560x1440 BG3 DX11 source;
  `local-capture-20260604-210855` submitted 281 local H.264 proof frames at
  1280x720@30 with zero write failures, about 29.9 output FPS, and about
  0.069 ms average encoder submit time; and
  `local-capture-20260604-211322` submitted 281 local H.264 proof frames at
  1920x1080@30 with zero write failures, about 30.1 output FPS, and about
  0.068 ms average encoder submit time.
- This is still local measurement only. It does not create a WebRTC video
  source, publish D3D11 hook frames to LiveKit, change stream profiles, alter
  capture defaults, or tune bitrate/fallback. The next exit boundary is a
  debug-only WebRTC/LiveKit source handoff that consumes the live BG3-proven
  GPU/NV12/encoder-shaped path.

## 2026-06-04 Encoder-Compatible NV12 Handoff Probe

- Added a debug-only `--publication-handoff-output-format bgra|nv12` helper
  option and `-PublicationOutputFormat bgra|nv12` local harness option. The
  default remains BGRA proof mode; the new `nv12` option is measurement-only
  and does not publish frames to LiveKit.
- The helper now scales the shared D3D11 frame into the existing BGRA output
  texture, then uses the D3D11 video processor to convert that output into a
  `DXGI_FORMAT_NV12` texture. Reports label this as
  `gpu_scaled_nv12_handoff_probe` with scale mode
  `contain_fit_gpu_scale_then_video_processor_nv12`.
- `publication-handoff.json` now records `outputFormat`, `encoderFormat`,
  `nv12TextureCreated`, `nv12OutputFrames`, `nv12ConvertFailures`,
  NV12 convert avg/p95/max timing, NV12 proof readback timing, and visible
  NV12 luma proof counts. The local harness Markdown surfaces output/encoder
  format, NV12 frame/failure/convert timing, and hook proof-export busy frames.
- Hardened target-side proof export after the synthetic proof run exposed a
  stall. The hook now publishes shared-frame state before optional PNG export
  and uses non-blocking staging maps for hook-side proof frames. Busy proof
  exports increment `proofExportBusyFrames`; publication proof frames remain
  the preferred visible validation output.
- Synthetic no-proof NV12 validation:
  `runtime/stream-lab/local-results/local-capture-20260604-200324/` completed
  at 1280x720 -> 1280x720@30 with about 58.7 Present FPS, about 32.0 handoff
  FPS, 155 NV12 output frames, zero NV12 conversion failures, and about
  0.028 ms average NV12 conversion.
- Synthetic visible-proof NV12 validation:
  `runtime/stream-lab/local-results/local-capture-20260604-200640/` completed
  at 1280x720 -> 1280x720@30 with about 57.5 Present FPS, about 31.9 handoff
  FPS, 154 NV12 output frames, zero conversion failures, one visible
  publication proof frame, one visible NV12 luma proof, and about 0.024 ms
  average NV12 conversion.
- The synthetic-target timeout caveat from the earlier BG3 proof pass is now
  resolved for the local no-call harness. The next implementation target is a
  local encoder proof fed from the scaled GPU/NV12 output, not another CPU
  readback or bitrate/profile tuning pass.

## 2026-06-04 BG3 Color And GPU Texture Handoff Proof

- Fixed the BG3 proof-frame color cast in the debug D3D11 game-capture path.
  The BG3 swap chain reports `R10G10B10A2_UNORM`; the previous proof export
  treated the low 10 bits as red, which made the screenshot look blue/purple.
  The helper/hook proof export now maps the packed channels as B, G, R in
  memory and writes correct RGBA output. The saved BG3 proof frames now match
  the provided reference screenshot's red/brown flesh tones, gold UI, and
  neutral sky instead of the blue cast.
- Added a proof-only GPU publication handoff mode. The helper now scales into
  the target BGRA D3D11 texture every output tick but skips continuous CPU
  `CopyResource` / `Map`; CPU readback is performed only for the small number
  of requested proof PNGs. Reports label this as
  `gpu_scaled_texture_handoff_probe` and include `readbackMode`,
  proof-output directory, requested proof-frame count, readback failures,
  proof output frames, visible proof frames, and proof write failures.
- BG3 720p30 validation:
  `runtime/stream-lab/local-results/local-capture-20260604-180806/` attached
  to the live BG3 DX11 process, used source/output 2560x1440 -> 1280x720,
  produced about 30.5 handoff FPS, 43.8 ms p95 output gaps, GPU scale average
  about 0.018 ms, total handoff work average about 0.038 ms, and 3 / 3
  visible publication proof frames.
- BG3 1080p30 validation:
  `runtime/stream-lab/local-results/local-capture-20260604-181045/` used
  source/output 2560x1440 -> 1920x1080, produced about 29.9 handoff FPS,
  44.9 ms p95 output gaps, GPU scale average about 0.015 ms, total handoff
  work average about 0.042 ms, and 3 / 3 visible publication proof frames.
- A stale-hook cleanup guard now unloads an already-loaded hook DLL from the
  target process before reinjecting. This recovered cleanly after the first WIC
  proof-writer crash left the hook loaded in BG3.
- Earlier synthetic-target smokes (`local-capture-20260604-181336` and
  `local-capture-20260604-181609`) installed the hook and reached `ring_ready`
  but produced no metadata or consumed frames before helper timeout. The later
  NV12 handoff pass fixed that proof-path stall by making hook-side PNG export
  non-blocking and by relying on publication proof frames for visible output.

## 2026-06-04 Local No-Call Stream Pipeline Harness

- Implemented `tools/stream-lab/run_local_capture_benchmark.ps1` so maintainers
  can run local D3D11 hook and publication-handoff diagnostics without Matrix
  login, room join, call setup, or LiveKit publishing.
- The MVP supports `future-game-d3d11-hook`: it can launch
  `InterGalacticCaptureTarget.exe`, attach
  `intergalactic_game_capture_helper.exe`, collect D3D11 Present cadence,
  host shared-texture consumer evidence, and publication-handoff output
  cadence, then write `local-capture-benchmark.json` and Markdown under
  `{LOCAL_STREAM_LAB_RESULTS_DIR}\`.
- WGC/window-GDI/app-default labels are accepted by the script but currently
  write a `not_implemented` local report, because no standalone native
  WGC/GDI desktop-capture CLI exists outside Flutter/WebRTC yet.
- Validation smoke:
  `runtime/stream-lab/local-results/local-capture-20260604-160719/` completed
  at 1280x720 with D3D11 hook attach `attached`, detected `d3d11`, Present
  about 57 FPS, hook copy avg/max about 0.006/0.035 ms, host consumed 279
  frames, and visible publication-handoff output at about 20.7 FPS. The local
  report correctly marks Matrix, LiveKit, network, receiver, and encoder as
  not tested.
- Follow-up local tuning found that the 20.7 FPS handoff was a helper pacing
  bug, not a texture-copy, scale, or readback bottleneck. The helper had been
  gating output from the previous output completion time, so a 60-ish FPS
  source whose second frame arrived around 31 ms could be skipped until the
  third frame around 46 ms. The helper now samples the latest available shared
  texture on a target-cadence window and reports repeated output frames when
  cadence is maintained from the same source frame.
- Post-fix local results prove the debug helper/handoff path is ready for BG3
  stress smoke: 1280x720 -> 1280x720@30 reached about 32.1 FPS with 32.3 ms
  p95 gaps in `local-capture-20260604-165437`; 1920x1080 -> 1920x1080@30
  reached about 31.8 FPS with 32.5 ms p95 gaps in
  `local-capture-20260604-164630`; 1920x1080 -> 1920x1080@60 reached about
  57.9 FPS with 30.0 ms p95 gaps in `local-capture-20260604-164705`; and
  2560x1440 -> 1920x1080@30 reached about 32.0 FPS with 32.5 ms p95 gaps in
  `local-capture-20260604-164741`.
- This is diagnostic harness work only. It does not tune stream profiles,
  change production capture backends, publish hook frames, alter LiveKit, or
  replace the in-call stream-test runner when sender/receiver/network evidence
  is actually needed.

## 2026-06-04 Deterministic D3D11 Capture Target

- Fresh BG3 window evidence from
  `stream-test-2026-06-04T18-00-35-194043Z` showed the GPU-scaled Phase 4A.5
  handoff path improved over the earlier CPU-scale probe but still missed the
  30 FPS target. The D3D11 Present path reported about 50 FPS with p95/max
  gaps around 25/63 ms, while the local handoff produced visible 1280x720
  output at about 16.3 FPS. GPU scale time was negligible, but scaled-output
  readback averaged about 15 ms and spiked to about 67 ms, so the remaining
  game-capture handoff limiter is staging/readback cadence.
- Implemented the debug-only `InterGalacticCaptureTarget.exe` under
  `tools/game-capture-target/`. It is a
  deterministic D3D11 swap-chain test app with windowed/borderless modes,
  1920x1080 / 2560x1440 sizes, 30/60/uncapped pacing, gameplay/high-motion/
  low-motion/UI-heavy scenes, and local `capture-target.json` / Markdown
  diagnostics.
- The stream-test UI can now launch and auto-select this target, run the
  existing stream presets/backends against it, stop it after the batch, and
  merge target Present FPS/gaps into top-level `gameCaptureTestTarget` JSON,
  Markdown, and diagnostic coverage.
- A local 3-second target smoke at 1280x720 wrote visible motion diagnostics
  with about 59.2 Present FPS. This target should be used for repeatable
  log-output and parser/pipeline checks before asking for BG3. BG3 remains the
  required stress case for real gameplay/window quirks.
- This remains diagnostic harness work only. No stream profile, bitrate,
  codec, fallback, LiveKit setting, normal capture backend, or D3D11 LiveKit
  publication path changed.

## 2026-06-04 Phase 4A.5 GPU-Scaled Publication-Handoff Probe

- Fresh BG3 window evidence from
  `stream-test-2026-06-04T17-09-58-491720Z` proved the Phase 4A handoff writer
  repair: `publication-handoff.json` was written, the helper exited cleanly,
  and helper shutdown breadcrumbs reached host-consumer join, handoff report
  write, and remote unload.
- The same evidence showed the local publication handoff was visible but too
  slow: requested 1280x720 at 30 FPS, source/output 2560x1440 -> 1280x720,
  output 10.7 FPS, p95 output gap about 125 ms, readback avg/p95/max about
  23/54/107 ms, CPU scale avg/p95/max about 25/26/29 ms, and total handoff
  avg/p95/max about 48/79/134 ms. This ruled in full-source CPU readback plus
  CPU contain-fit scaling as the next bottleneck.
- The helper handoff path now scales on the GPU into the preset-sized BGRA
  output texture first and readbacks only the scaled output for proof. Reports
  label this as `gpu_scaled_bgra_readback_probe` with
  `contain_fit_gpu_before_readback`.
- Stream-test report semantics now separate visible handoff evidence from
  target-cadence health. A visible 10 FPS handoff is reported as
  `handoff=slow`, not `handoff=healthy`, and the run-level recommended next
  action becomes `fix game-capture handoff` when this diagnostic boundary is
  active.
- This remains debug-only measurement work. No D3D11 hook frames publish to
  LiveKit, and no stream profiles, bitrates, codecs, fallback thresholds,
  LiveKit defaults, or normal WGC/window-GDI capture behavior changed.

## 2026-06-04 Phase 4A Local Publication-Handoff Probe

- Implemented the next debug-only D3D11 game-capture measurement step after
  the healthy host-consumer evidence. The helper can now sample the latest
  opened shared texture, contain-fit scale it into a paced BGRA buffer target,
  and write `publication-handoff.json` / `publication-handoff.md`.
- Stream-test game-capture probe config now enables the publication handoff by
  default and derives the handoff target from the first tested preset: Smooth
  1280x720 at 30 FPS, Balanced 1920x1080 at 30 FPS, and High Quality 1920x1080
  at 60 FPS.
- Reports merge the handoff evidence into `gameCaptureProbe`, including
  requested/source/output dimensions, output FPS/gaps, frame age, readback,
  scale, total handoff timing, visible output count, paced drops, and a derived
  handoff health label.
- This is still not LiveKit publication. Normal streams continue through the
  existing WGC/window-GDI sender path, and no stream profiles, bitrates, codec
  choices, fallback thresholds, or capture defaults changed.
- First runtime evidence from
  `stream-test-2026-06-04T16-27-19-436678Z` showed the normal BG3 window
  stream still capture-limited at about 16 FPS through valid window-GDI
  `PrintWindow(PW_RENDERFULLCONTENT)`, while the D3D11 probe attached,
  observed the 2560x1440 `R10G10B10A2_UNORM` backbuffer at about 50 Present
  FPS, opened all three host shared-texture slots, consumed 899 host frames,
  and had no hook-copy cost, drops, or shared-texture open failures.
- That same run did not prove Phase 4A because `publication-handoff.json` was
  missing. The helper had written `host-consumer.json` and the hook had stopped
  cleanly, but the helper never logged remote-unload shutdown. Follow-up code
  fixed the handoff writer's p95 percentile inputs, hardened percentile
  normalization against 95-versus-0.95 mistakes, extended the Dart runner
  watchdog so normal helper teardown is not killed, and added helper shutdown
  breadcrumbs around host join, report writes, and remote unload.
- Next runtime validation should run BG3 window stream tests with the D3D11
  probe enabled. A healthy report should show `present`, `hostConsumer`, and
  `handoff` as healthy; if that happens while the normal sender remains choppy,
  the next implementation target is the real Phase 4B WebRTC/LiveKit
  game-capture source or GPU encoder handoff.

## 2026-06-04 Phase 3B Shared-Texture Host Consumer

- Implemented the next debug-only D3D11 game-capture step after the concurrent
  probe evidence: the helper now creates a shared-state mapping and frame-ready
  event, the hook publishes the shared texture ring handles/latest frame
  metadata, and the helper opens/observes those shared textures from the host
  side.
- The host consumer writes `host-consumer.json` and `host-consumer.md` beside
  the normal helper output. Stream-test reports merge that evidence into the
  `Game Capture Probe` section and coverage matrix, including opened texture
  slots, consumed frames, missed/duplicate frames, host frame age, consumer
  gaps, and optional proof-readback visibility.
- This is still measurement-only. No D3D11 hook frames are published to
  LiveKit, no stream profiles/bitrates/codecs/fallback thresholds changed, and
  normal WGC/window-GDI publishing remains the active stream path.
- Validation passed: native CMake/MSVC Debug rebuild, no-PID helper
  fail-closed smoke with the new host-consumer CLI flags, focused
  `stream_test_runner_test.dart`, and targeted Flutter analyze for the touched
  Dart stream-test files.
- Next runtime validation should run the BG3 window stream test with the D3D11
  probe enabled. A healthy report should show both `present` cadence and
  `hostConsumer=healthy`; if Present is healthy but host consumption is not,
  fix shared-handle/device/synchronization before designing LiveKit
  publication.

## 2026-06-04 Concurrent D3D11 Probe Stream-Test Integration

- Fresh BG3 window evidence showed the optional D3D11 probe attached and
  reported a healthier local Present path while the actual LiveKit stream was
  still limited by valid window-GDI `PrintWindow(PW_RENDERFULLCONTENT)`
  acquisition. However, the first Phase 3A runner integration awaited the
  probe immediately after source selection, so the UI appeared stuck before the
  first preset and the hook evidence was adjacent to, not concurrent with, the
  streamed capture interval.
- The stream-test runner now starts the optional game-capture probe
  concurrently with the initial preset run when presets are selected. Probe-only
  runs still do not publish to LiveKit. The probe config/result JSON and
  Markdown now report timing as `standalone` or
  `concurrentWithInitialPreset`.
- The concurrent probe duration is extended to cover the first preset warmup
  plus measured sample window. This keeps the D3D11 Present cadence and the
  published WGC/window-GDI capture cadence comparable without adding a new
  LiveKit publishing backend or making long all-preset injection runs block
  cleanup.
- This is measurement-harness work only. Stream profiles, bitrate, codec,
  fallback thresholds, LiveKit publish behavior, capture backend defaults,
  native libwebrtc behavior, and the D3D11 helper/hook implementation are
  unchanged.
