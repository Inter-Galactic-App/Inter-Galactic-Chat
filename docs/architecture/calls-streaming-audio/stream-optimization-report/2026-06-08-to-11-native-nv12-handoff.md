# 2026-06-08 To 2026-06-11 Native NV12 Handoff Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-11 Native-NV12 Pending-Readiness Wait-Cap Tuning

- The latest actual-gameplay report moved the active boundary to native
  readiness and delivery cadence: true GPU/native NV12 stayed alive, but the
  source delivered about 24-25 FPS with `nativeNv12ReadyDropped=109`,
  `delivery_queue_wait` max `71 ms`, and `source_to_submit` max `240 ms`.
- The native source now caps the next capture-loop wait to `8 ms` whenever a
  native NV12 slot is pending. This lets ready GPU frames drain between
  source-present/target-FPS wakes without reintroducing the old blocking
  per-frame GPU wait in the sender path.
- Focused native build passed for the patched Windows `libwebrtc` target using
  the maintained WebRTC build toolchain.
- Local R10 WebRTC source smoke
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260611-110439-native-nv12-waitcap8/`
  completed with `submitted=226`, `repeated=9`, `deliveryQueued=219`,
  `deliverySubmitted=226`, `deliveryOverwritten=1`,
  `nativeNv12Submitted=220`, `nativeNv12Queued=217`,
  `nativeNv12Ready=216`, `nativeNv12NotReadyPolls=1420`,
  `nativeNv12ReadyDropped=0`, `nativeNv12Failures=0`, and `cpuFallback=0`.
  Compared with the earlier drain smoke, repeats dropped `27 -> 9`, delivery
  overwrites dropped `19 -> 1`, and native-ready drops dropped `1 -> 0`.
- The stream debug package harness also gained native-only runner refresh for
  native DLL changes plus explicit NuGet preflight for full Windows Debug
  rebuilds. It auto-detects maintainer-local NuGet installs, prepends the
  selected directory to PATH only for the package process, records NuGet
  resolution in manifests, and accepts `-NuGetExe` / `-NuGetDirectory` for
  deterministic reruns. The
  previous native-only manifest `runtime/stream-lab/debug-builds/20260611-151633/`
  remains valid; the later full Debug build manifest
  `runtime/stream-lab/debug-builds/20260611-161346/` completed with native and
  Debug runner `libwebrtc.dll` SHA-256
  `D1393E684641BC0440E6399D22C54E25228A5AA9777889C44087AC26B4E018A4`; patched
  `libwebrtc.zip` SHA-256
  `1CD246E829D85F53936512BEF0F45D83D65E61B43950858D577E58C49A195D86`; Debug
  runner exe SHA-256
  `95ACDEFE8456C2CFC31072A9CBE8CF38ED567B352CCD3644677CB0C86793EFC6`; and
  successful NuGet preflight from the configured NuGet executable.
- Next validation should be exactly one BG3 Smooth 720p30 actual-gameplay run
  compared against `stream-test-2026-06-11T02-22-27-924579Z`. Success should
  show sustained native NV12, `nativeNv12Failures=0`, `cpuFallback=0`, no app
  crash, fewer ready drops/delivery overwrites, and capture/encode/send closer
  to 30 FPS without retuning bitrate, LiveKit, receiver policy, or fallback.

## 2026-06-11 BG3 Native-NV12 Startup Recovery And New Pacing Boundary

- Native `libwebrtc.dll` was rebuilt, installed into the Windows Debug runner,
  and live-tested with SHA-256
  `99E32CCBB942A94D015A700131CCBD6E9974AE7EC8112CF89B15B4D35BCBFEB3`. The
  refreshed workspace artifact
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip` has SHA-256
  `531FDA1A467C31619B959416568E917178B329668EBBA4B3A6C9645DE09C1F7D`.
- Local preflight passed before BG3: R10/HDR-like synthetic source to
  NV12 + Media Foundation H.264 proof at
  `runtime/stream-lab/local-results/local-capture-20260610-222019/` completed
  with `Nv12Frames=339`, `Nv12Failures=0`, `EncoderFrames=339`, and
  `EncoderFailures=0`.
- BG3 actual gameplay Smooth 720p30
  `stream-test-2026-06-11T02-22-27-924579Z` completed with the game focused
  and constant W-key motion. The stream did not crash, and the report loaded
  the rebuilt `99E32CCB...` DLL.
- The previous startup handoff boundary is now cleared. Repeated startup
  `MF_E_NOTACCEPTING` triggered a bounded native-startup encoder
  reinitialization instead of suspending native input; Media Foundation then
  continued on `input_path=native_nv12`.
- The report proves true GPU/native continuity during gameplay:
  `nativeNv12Submitted=1187`, `nativeNv12Failures=0`, `cpuFallback=0`,
  `encoder_native_input=43`, `encoder_cpu_i420_input=1` warmup frame,
  `encoder_native_sample_failures=0`, `encoder_native_suspended=0`, and
  `encoder_outputs=40` in parsed markers.
- The remaining boundary is frame pacing/source readiness, not conversion
  continuity, app stability, network, bitrate, LiveKit, or CPU fallback. The
  run classified `frame_pacing_unstable` with score `70`: capture `25.1 FPS`,
  encode `24.6 FPS`, send `24.2 FPS`, loss `0.0%`, RTT about `84 ms`, and no
  WebRTC quality limitation.
- Native source tails are the next target: `nativeNv12Queued=1429`,
  `nativeNv12Ready=1319`, `nativeNv12NotReadyPolls=2488`,
  `nativeNv12ReadyDropped=109`, `deliveryOverwritten=260`,
  `delivery_queue_wait` max `71 ms`, `source_to_submit` max `240 ms`,
  `source_to_queue` max `237 ms`, and `delivery_wall_delta` max `121 ms`.
- Next work should stay on the true-GPU path. Do not switch the primary plan
  to P010 or treat I420 fallback as success; P010 remains diagnostic/HDR
  research until there is an encoder/live WebRTC path for it. The next code
  pass should reduce native readiness/drop pressure and source-to-submit tail
  latency before another single BG3 Smooth 720p30 gameplay validation.

## 2026-06-10 Actual Gameplay Native-NV12 Continuity And Pacing Boundary

- After the native GPU NV12 sync guard, the BG3 intro-menu Smooth
  `1280x720@30` run `stream-test-2026-06-10T19-52-20-135422Z` completed without
  app crash, scored `90` / `healthy`, and proved sustained native R10 handoff:
  `nativeNv12Submitted=1049`, `nativeNv12Failures=0`, `cpuFallback=0`,
  readback limited to warmup/proof work, and Media Foundation
  `input_path=native_nv12`.
- The runner/reporting hardening after that smoke records loaded `libwebrtc.dll`
  identity without raw local paths. The following actual-gameplay report
  included digest prefix `EAA5A80D9DB7`, size `20417024` bytes, and source
  label `executable_directory/libwebrtc.dll`, confirming the tested app loaded
  the rebuilt native artifact.
- User-run actual gameplay `stream-test-2026-06-10T20-30-35-779759Z` completed
  without app crash and kept clean network/encoder evidence: H.264 via
  `MediaFoundationH264`, hardware encode true, capture `29.9 FPS`, encode
  `29.7 FPS`, send `29.8 FPS`, loss `0.0%`, RTT about `5 ms`, and `NACK=0`.
- The failed boundary is not LiveKit, bitrate, helper lifecycle, source
  visibility, or persistent `MF_E_NOTACCEPTING`. Native NV12 started
  (`nativeNv12Submitted=33`) and then disabled only the R10 native attempt after
  `gpu_nv12_failed reason=video_processor_blt_wait_timeout hr=0x80070102`.
- The safe fallback kept the stream alive, but the report correctly classified
  `frame_pacing_unstable` with score `75`: `1011` readbacks queued, `5159`
  readback map attempts not ready, `264 / 1042` submitted frames repeated,
  `sourceToSubmitMaxMs=246.755`, and `readbackQueueToMapMaxMs=201.537`.
- Follow-up `stream-test-2026-06-10T21-14-15-739117Z` changed the R10 native
  path to wait after the per-frame NV12 copy and require three consecutive R10
  failures before disabling native handoff. It completed without app crash or
  fallback, loaded `libwebrtc.dll` digest prefix `8FC4DDBA04A7`, and sustained
  `nativeNv12Submitted=783`, `nativeNv12Failures=0`, `cpuFallback=0`, and
  Media Foundation `input_path=native_nv12`. The run still scored `75` /
  `frame_pacing_unstable`, with native cadence around `22.4 FPS`,
  `157 / 789` repeated submitted frames, average native NV12 conversion about
  `22 ms`, and source-to-submit max about `171 ms`.
- Follow-up `stream-test-2026-06-10T21-20-57-701804Z` increased native NV12
  ring depth to `16` and handed the ring-slot texture directly to the native
  buffer instead of allocating/copying a per-frame NV12 texture. It again
  completed without app crash or fallback, loaded digest prefix `2ABE569D74F3`,
  and sustained `nativeNv12Submitted=836`, `nativeNv12Failures=0`,
  `cpuFallback=0`, `gameCaptureGpuHandoffUnproven=false`, and Media Foundation
  `input_path=native_nv12`.
- The ring-slot run improved but did not clear BUG-208: repeated submitted
  frames dropped to `85 / 841`, average native NV12 conversion fell to about
  `16 ms`, and source-to-submit max fell to about `147 ms`, but the run still
  scored `75` / `frame_pacing_unstable` with native cadence around `23.9 FPS`
  and delivery wall max about `120 ms`.
- Next work should stay local on the true-GPU path. The next implementation
  boundary is async/bounded `native_frame_ready` handling and delivery queue
  pacing so capture/source acquisition does not block on every GPU handoff.
  The next live validation should be one actual-gameplay Smooth run proving
  sustained native NV12, `nativeNv12Failures=0`, `cpuFallback=0`, no app crash,
  no helper leak, and sender p95/max pacing within budget.

## 2026-06-10 BG3 R10-Format Gate Smoke

- User-run BG3 intro-menu Smooth `1280x720@30` smoke
  `stream-test-2026-06-10T14-29-26-324333Z` completed and the app did not
  crash. This is the first completed post-gate report after the native-NV12
  BG3 `R10G10B10A2` source hang/device-loss boundary was addressed.
- The intended source-format guard fired:
  `native_nv12_encoder_handoff_disabled reason=r10g10b10a2_source_format
  using_gpu_scale_i420_readback=true`. The retained BG3 path therefore used
  GPU scale plus output-sized I420 readback instead of trying the native NV12
  encoder handoff for the 10-bit source format.
- The pipeline reached a normal sender state: `MediaFoundationH264 hw=true`,
  H.264, encoded size `1280x720`, capture/encode/send each around `30.3 FPS`,
  nonzero encoded/sent frames, loss `0.0%`, RTT about `2 ms`, and no WebRTC
  quality limitation. Native encoder timing was below the frame budget, with
  early CPU-I420 markers reporting `stage=ok` and encoded output beginning on
  frame 2.
- Hook/source correctness was also proven for the tested path:
  `gpuScaled=1055`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `nativeNv12Submitted=0`, visible pre-I420 and I420 proof frames,
  `sourceFrameRegressions=0`, and `sharedSlotMismatches=0`. Helper cleanup
  logged stop signaling and `helper_exited`.
- The remaining boundary is still frame pacing/readback pressure, not crash,
  publication, encoder selection, network, or resolution. The report
  classified `frame_pacing_unstable` with score `75` because the safe
  GPU-scale/I420 path submitted `163 / 1055` repeated source frames, recorded
  `3847` readback-not-ready attempts, dropped `53` stale readbacks, and showed
  `sourceToReadbackReadyMaxMs=239.261` /
  `readbackQueueToMapMaxMs=234.892`.
- Live testing is paused after this completed smoke because the user needs the
  machine. The next pass should be local/code-level work against the R10
  GPU-scale/I420 readback pacing boundary; do not request another broad BG3
  preset run before that boundary changes.

## 2026-06-09 Native NV12 Not-Accepting Recovery

- Added a separate Media Foundation recovery path for repeated
  `MF_E_NOTACCEPTING` on native NV12 input. The previous native no-output
  recovery only ran after `ProcessInput` accepted a frame and queued metadata,
  so it could not fire when the async encoder repeatedly rejected input before
  the queue grew.
- The native encoder now counts consecutive native-NV12 `not_accepting` frames,
  reinitializes the Media Foundation transform after a bounded threshold,
  suspends native NV12 for that encoder instance, and continues through CPU
  I420 on following frames instead of reporting every rejected input as a
  harmless dropped frame.
- Repeated `not_accepting` app-log forwarding is now throttled while native
  sidecar diagnostics still record cadence samples. Recovery writes
  `stage=not_accepting_recovered`, `native_suspended=yes`, and
  `action=reinitialize_cpu_i420_not_accepting` evidence so stream-test reports
  can keep classifying the failed boundary as `encoder_handoff_limited`.
- Validation passed with native `libwebrtc` rebuild, patched artifact refresh,
  patched Flutter WebRTC install, and Windows Debug rebuild outside the
  Dart/Flutter sandbox. Patched `libwebrtc.zip` SHA-256:
  `8DF5815ED2B99B090AA0EEDDCF6D50E134EC20FA0E40D02C2F947061F95FA159`;
  rebuilt native / Debug runner `libwebrtc.dll` SHA-256:
  `231E613EFA620D69EC0A7BC126D48C858B8CA6B8F7CF683F7A34037811042488`;
  Debug `InterGalactic.exe` SHA-256:
  `3CD8517F530BA7248D41FFC988E148D687B7D33F042D78B3ABD11ECE733DA53B`.
- Source-local WebRTC smoke against the rebuilt Debug runner completed at
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260609-notaccepting-recovery/`
  with `submitted=140`, `gpuScaled=140`, `nativeNv12Submitted=138`,
  `nativeNv12Failures=0`, `cpuFallback=0`, delivery wall delta avg/max
  `33.3957 / 47 ms`, source regressions `0`, and shared slot mismatches `0`.
- A short local stream-lab NV12 / Media Foundation proof completed at
  `runtime/stream-lab/local-results/local-capture-20260609-160529/`: Present
  FPS `58.342`, handoff output FPS `31.102`, NV12 frames/failures/convert avg
  `141 / 0 / 0.025 ms`, and local `h264-mf` encoder proof
  `141 / 0 / 363.917 ms / 0.064 ms / 4576958` output bytes.
- Live BG3 intro-menu Smooth `1280x720@30` request
  `codex-bg3-native-nv12-notaccepting-recovery-smooth-20260609-1618`
  proved native NV12 can recover from the startup not-accepting frame and
  produce live H.264 output. The encoder reported one frame-2
  `stage=not_accepting`, then frame 3 reported `stage=ok_native_nv12`,
  `outputs=1`, `output_bytes=275580`, and `encoded_outputs=1`. Later LiveKit
  diagnostics reported `MediaFoundationH264 hw=true`, `capture_fps=30`,
  `pre_encode_fps=30`, `encode_fps=30`, `send_fps=30`, `captured=506`,
  `encoded=435`, and `sent=435`.
- The same live run exposed a new runner/report boundary. Native source stats
  stayed healthy through `submitted=452`, `gpuScaled=452`,
  `nativeNv12Submitted=449`, `nativeNv12Failures=0`, `cpuFallback=0`, source
  regressions `0`, shared slot mismatches `0`, and delivery-wall max `35 ms`,
  but app logging stopped at `2026-06-09T20:18:05Z` after stream-test sample
  `10`. No stream-test report was written and the request remained
  `.running.json`.

### Runner Completion Guard

- This pass proves the live native NV12 path can produce H.264 output after an
  initial `not_accepting`; it did not prove the stream-test automation/report
  path was healthy. The follow-up guard now bounds the runner batch, bounds
  diagnostic-log marker reads, and attempts bounded `stopShare()` cleanup after
  a batch timeout so automation can write either a report or a failed
  `.complete.json` instead of leaving the request `.running.json`.
- Local validation passed with Dart format, focused
  `intergalactic/test/client/components/voip/stream_test_runner_test.dart`, and
  targeted Flutter analyze for the touched runner/test files outside the
  Dart/Flutter sandbox.
- Do not tune bitrate, LiveKit/SFU, receiver policy, BG3 presets, D3D11 capture
  cadence, or product-facing game-capture UI from this pass. The next live
  validation remains one Smooth `720p30` BG3 intro-menu run that must produce
  nonzero encoded/sent frames and either a stream-test report or a bounded
  failed completion.

## 2026-06-09 Native NV12 Encoder-Handoff Retention / Timeout Repair

- Implemented the Media Foundation native-NV12 encoder handoff repair in the
  patched Windows `libwebrtc` tree. Native input samples are now retained in
  encoder frame metadata until the matching output is drained, so DXGI-backed
  NV12 sample lifetime survives asynchronous Media Foundation output timing.
- Added a bounded no-output recovery path for the native NV12 branch. If Media
  Foundation accepts native NV12 input but produces no output while queued
  native samples accumulate, the encoder logs the handoff stall, reinitializes,
  suspends native NV12 for that encoder instance, and continues through CPU
  I420 instead of leaving the stream-test request hung indefinitely.
- Added stream-test timeout and stale-request handling around share start/stop,
  diagnostics collection, and automation polling. The report parser now exposes
  encoder output/byte counts, queue depth, retained sample count, encoded output
  count, native suspension frames, and `encoder_handoff_limited` when native
  input reaches Media Foundation but output never drains.
- Reduced live native encoder log-bridge pressure and added stream-test runner
  breadcrumbs for measurement start/completion, diagnostic sampling, and cleanup.
  This was added after the first BG3 retention smoke proved native output could
  start but automation/log delivery stopped before a report was written.
- Refreshed patched artifact and rebuilt Debug app. Patched `libwebrtc.zip`
  SHA-256:
  `7C53FC44D31B4508C61F9F1661599A953FED8AC99F684D121A9A1D33AB428B7B`;
  rebuilt native `libwebrtc.dll` SHA-256:
  `0A434505CDE091A6D19BE68463FE413A7B998F23D30EC2157E1EA38C8DD67EF3`;
  Debug `InterGalactic.exe` SHA-256:
  `738C232A2B99A533A1FA7B2D339D2FF970BFE80E0EF712939534D7124949A5A4`.
- Validation passed with native Ninja rebuild, Dart format, focused
  `stream_test_runner_test.dart` plus `native_webrtc_diagnostics_test.dart`,
  targeted Flutter analyze, patched-libwebrtc install, and Windows Debug
  rebuild outside the Dart/Flutter sandbox.
- Local deterministic D3D11 target / Media Foundation proof passed at Smooth
  resolution:
  `runtime/stream-lab/local-results/local-capture-20260609-143327/local-capture-benchmark.md`.
  Key fields: status `completed`, Present FPS `58.243`, handoff output FPS
  `32.197`, p95/max handoff gaps `32.155 / 45.944 ms`, NV12
  frames/failures/convert avg `145 / 0 / 0.025 ms`, and local `h264-mf`
  encoder proof `145 / 0 / 366.815 ms / 0.070 ms / 4589279` output bytes.
- Local deterministic D3D11 target / Media Foundation proof also passed at
  Balanced resolution:
  `runtime/stream-lab/local-results/local-capture-20260609-143356/local-capture-benchmark.md`.
  Key fields: status `completed`, Present FPS `57.960`, handoff output FPS
  `32.047`, p95/max handoff gaps `32.133 / 45.470 ms`, NV12
  frames/failures/convert avg `145 / 0 / 0.027 ms`, and local `h264-mf`
  encoder proof `145 / 0 / 369.216 ms / 0.065 ms / 9609682` output bytes.

### Remaining Boundary

- The post-repair live BG3 intro-menu smoke now completes and writes a report,
  so the automation/reporting hang is repaired. Request
  `codex-bg3-native-nv12-logbridge-smooth-20260609-1523` produced
  `<local-log-path>/stream-tests/stream-test-2026-06-09T19-23-46-553999Z.md`
  and completed at `2026-06-09T19:24:24Z`.
- BUG-208 remains open because the completed report classified the run as
  `encoder_handoff_limited` with score `0`: capture stayed near target
  (`30.5 FPS`, `gpuScaled=1054`, `nativeNv12Submitted=1051`,
  `nativeNv12Failures=0`, `cpuFallback=0`, no >2x/>3x delivery-wall gaps), but
  the Media Foundation sender produced no encoded output (`framesEncoded=0`,
  `framesSent=0`, `encoder_outputs=0`, `encoder_output_bytes=0`) after native
  NV12 input reached the encoder.
- The next implementation boundary is the Media Foundation native NV12
  `ProcessInput` / output-drain state after `stage=not_accepting`, plus tighter
  throttling for repeated `not_accepting` app-log forwarding. Do not tune
  bitrate, LiveKit/SFU, receiver policy, BG3 presets, or D3D11 capture cadence
  until this encoder no-output boundary is fixed.

## 2026-06-09 Live BG3 Native NV12 First-Frame Stall

- Repackaged the patched native artifact and rebuilt the Debug Windows app for
  a real BG3 intro-menu pipeline smoke. Patched `libwebrtc.zip` SHA-256:
  `8FAE6DB20298128F94F6D4159C1460EEC722889EE7CBB24905D5480F3EF7D379`;
  Debug runner `libwebrtc.dll` SHA-256:
  `6AD81B73AB2F450ADB61805ED35A88FC3C3EE8807EFFDE15B07BAF7879C3B1DE`;
  Debug `InterGalactic.exe` SHA-256:
  `738C232A2B99A533A1FA7B2D339D2FF970BFE80E0EF712939534D7124949A5A4`.
- Live setup passed the outer pipeline gates: the rebuilt app launched, BG3
  DX11 launched on the intro menu, the `Ctrl+Alt+PgDown` shortcut joined the
  LiveKit call, and stream-test automation started Smooth `1280x720@30` with
  `windowsBackendMode=game-d3d11-hook-experimental`.
- Request id:
  `codex-bg3-native-nv12-frame-owned-smooth-20260609-1329`. The runner selected
  BG3 PID `46312` / title `Baldur's Gate 3 (2560x1440) - (DX11) - (6 + 6 WT)`.
- Positive native proof reached the encoder boundary. Logs showed
  `shared_textures_opened`, `gpu_scale_resources_ready`, and
  `gpu_nv12_resources_ready ... frameOwnership=per_frame_texture_copy`, then
  Media Foundation emitted one encoder timing line with
  `stage=ok_native_nv12`, `input_path=native_nv12`, `native_input=yes`, and
  `native_sample_failed=no`.
- The live publisher then stalled before a completed stream-test report. Only
  one Media Foundation timing line appeared, no `game_capture_webrtc_source`
  stats or `nativeNv12Submitted` summary appeared, `Stream test runner
  completed` never logged, and the request remained as `.running.json` after
  more than three minutes. The first native sample was slow at about
  `112.6 ms` total, with about `99.4 ms` in sample creation/input copy,
  `outputs=0`, `queue=1`, `async=yes`, and `slow=yes`.

### Current Boundary

- The frame-owned native NV12 path is no longer blocked before Media
  Foundation: live BG3 evidence now proves native NV12 input reaches the
  encoder with `native_sample_failed=no`.
- BUG-208 remains open because live publication stalls at the Media Foundation
  native-sample handoff/drain boundary. The next repair should inspect native
  sample creation/copy lifetime and async drain behavior, plus the stream-test
  timeout/stop guard. Do not tune bitrate, LiveKit, fallback, receiver policy,
  or BG3 presets from this run.

## 2026-06-09 Native NV12 Frame-Owned Handoff Repair

- Re-enabled the debug D3D11 game-hook native NV12 source handoff, but changed
  the ownership boundary before it reaches WebRTC. The video processor still
  writes into the small NV12 scratch ring, then the source copies that scratch
  surface into a per-frame-owned NV12 texture before wrapping it in
  `IntergalacticD3D11Nv12Buffer`.
- Rationale: the previous native NV12 branch could hand WebRTC/Media
  Foundation a texture from a reusable ring slot. If the encoder consumed the
  native frame asynchronously after the source reused that slot, the encoder
  could see overwritten content or stall-like behavior. The new per-frame
  texture copy keeps the frame GPU-resident while giving each submitted native
  buffer a stable lifetime.
- Native validation passed for the patched Windows `libwebrtc` target using
  the maintained WebRTC build toolchain.
- Source-local validation passed against the synthetic D3D11 target via the
  exported `InterGalacticGameCaptureWebrtcSourceSmoke` entry point. Report:
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260609-*-frame-owned-nv12/webrtc-source-smoke.json`.
  Key markers: `submitted=140`, `gpuScaled=140`,
  `nativeNv12Submitted=137`, `nativeNv12Failures=0`, `cpuFallback=0`,
  `readbackQueued=5` warmup/proof frames, `visibleSourceSeen=true`,
  `visibleProofFrames=2`, `visibleI420ProofFrames=1`, and no delivery wall
  gaps over 2x/3x.

### Remaining Boundary

- This clears the rebuilt native source-local gate, not live BG3 publication.
  The next rebuilt-app check must prove the same native-NV12 path under the
  in-app LiveKit/WebRTC sender and show Media Foundation encoder markers with
  `input_path=native_nv12`, `native_input=yes`, and
  `native_sample_failed=no`.
- If the in-app report still falls back to `cpu_i420`, keep the next work in
  native Media Foundation/WebRTC input handling. Do not tune bitrate, LiveKit,
  fallback, or receiver policy from this source-local proof alone.

## 2026-06-08 BG3 Smooth 720p30 Helper-Feed Headroom Validation

- Rebuilt the safe debug D3D11 game-hook path so the helper captures/source-feeds
  at a minimum 60 FPS while WebRTC delivery stays at the preset target, currently
  30 FPS for Smooth. This keeps the source side ahead of the delivery pacer
  without returning to the earlier branch that submitted every 60 FPS helper
  frame into readback and flooded the ring.
- Patched native file:
  `webrtc-build/src/libwebrtc/src/win/intergalactic_game_capture_video_capturer.cc`.
  The retained delivery grace is the stricter `10 ms`; the rejected half-frame
  grace branch produced worse wall-gap variance and was not kept.
- Refreshed patched artifact and rebuilt Debug runner fingerprints were
  recorded in private validation evidence. This public report keeps the
  behavioral markers without exact build hashes.
- 30-second BG3 Smooth report:
  `<local-log-path>\stream-tests\stream-test-2026-06-09T00-38-32-652223Z.md`.
  Key markers: `hookTargetFps=60`, `source=2560x1440`,
  `output=1280x720`, `gpuScaled=1055`, `gpuScaleFailures=0`,
  `cpuFallback=0`, `repeated=0/1055`, `deliveryOverwritten=1`,
  readback ready max about `23.6 ms`, source-to-submit max about `50 ms`, and
  delivery wall gaps `29-37 ms`.
- 60-second BG3 Smooth report:
  `<local-log-path>\stream-tests\stream-test-2026-06-09T00-40-23-486928Z.md`.
  Key markers: score `90`, capture/encode/send near `30 FPS`, `gpuScaled=1962`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `repeated=26/1962` (`1.33%`), no
  under-half or over-2x delivery gaps, readback-ready max about `31.7 ms`, and
  native encoder timing around `1.36 ms` average / `5.4 ms` max.
- Interpretation: this materially improves the Smooth 720p30 BG3 path and moves
  it to manual visual confirmation. The remaining report classifications can
  still be too pessimistic when sampled WebRTC p95/send-delay counters disagree
  with clean native D3D11 evidence. That is a report-calibration follow-up, not
  proof that bitrate, LiveKit, or fallback should be retuned.

### Remaining Boundary

- GPU scaling is active, but GPU encoder handoff is not solved in this retained
  build. Reports still show `encoderInput=cpu_i420` and
  `nativeNv12Submitted=0`, so the live hot path remains:

```text
D3D11 texture -> GPU scale -> staging readback/map -> CPU I420 -> WebRTC
```

- The target hot path remains GPU NV12 or another encoder-compatible surface
  feeding hardware encoder / WebRTC-compatible handoff without per-frame CPU
  I420 conversion. That work should be the next architecture phase after one
  Smooth 720p30 visual confirmation.

## 2026-06-08 Phase 4 Native NV12 WebRTC Source Proof

- Implemented the next GPU-first roadmap slice in the patched Windows
  libwebrtc tree. The debug D3D11 game-hook WebRTC source now attempts
  `D3D11 source -> GPU scaled BGRA -> D3D11 video-processor NV12 ring ->
  NativeHandleBuffer -> WebRTC OnFrame` before the older CPU I420 fallback.
  The Media Foundation H.264 encoder advertises native-handle support and
  tries `MFCreateDXGISurfaceBuffer` for NV12 native frames before falling back
  to CPU I420.
- New parsed native fields:
  - `nativeNv12Submitted`
  - `nativeNv12Failures`
  - `nativeNv12ConvertMs`
  - `nativeNv12ConvertMaxMs`
  - `nativeNv12ConvertSamples`
  - Media Foundation `input_path`, `native_input`, and
    `native_sample_failed`.
- Native libwebrtc rebuild passed with bundled Ninja. Refreshed patched
  artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip` SHA-256
  `E113E5D10A891F06B1C6FFB8F17E5A7216B708A42347801C61B3F6F3B8D65710`.
  The rebuilt Debug runner `libwebrtc.dll` SHA-256 is
  `22EFB36308964B1BFE1D9DAAF189E69635C1C37BE76963606CD30F34D7BFA451`.
  After FEATURES cleared the unrelated story composer compile blocker, the
  Windows Debug app rebuild passed; Debug `InterGalactic.exe` SHA-256 is
  `3E5D9CE706C0F6AC6C8B78F69F906EEE92A0DA615CF110E079B27FD4100EDFE1`, and the
  game-capture helper/hook pair is staged in the Debug runner folder.
- Local stream-lab validation against the deterministic D3D11 target completed
  at `runtime/stream-lab/local-results/local-capture-20260608-153326/`.
  The local publication/encoder proof reported `299` NV12 frames,
  `0` NV12 failures, about `0.022 ms` average NV12 conversion, local
  `h264-mf` encoder proof `299 / 0` submitted frames/write failures, and no
  proof readbacks in encoder mode.
- Source-local WebRTC validation completed at
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260608-153730/`.
  The smoke reported `submitted=292`, `gpuScaled=292`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `nativeNv12Submitted=292`,
  `nativeNv12Failures=0`, `readbackQueued=0`, `readbackMapAttempts=0`,
  `nativeNv12ConvertMs=0.015`, `nativeNv12ConvertMaxMs=0.0307`, and
  source-to-submit avg/max `0.315 / 16.547 ms`.
- The first in-app BG3 Smooth run with that native-NV12 build crashed before a
  usable report. Crash dumps showed the failure in Flutter local video texture
  rendering after the D3D11 helper, shared textures, and GPU/NV12 resources had
  opened. The fix keeps the native sender/encoder path intact but converts
  renderer-bound native frames to I420 and guards failed `ToI420` / ARGB
  conversion paths. Refreshed crash-guard artifact SHA-256:
  `6AECF1BD8A63B58F5AD49B0405087DE0DA2767F3FD308D2AB7E1A6615D04C09A`.
  Rebuilt Debug `InterGalactic.exe` SHA-256:
  `3500EC3BB2B5CF6FFBF8DD1CC8DE4070431DEF27E5C3022AF129687DAFABD907`;
  runner `libwebrtc.dll` SHA-256:
  `7EB71CAE5C416FB537FF42D659745AACD04BF678E3E19192727255889158ECD2`.
- Dart-side validation passed outside the sandbox with workspace-local
  AppData: Dart format, focused `stream_test_runner_test.dart`, and targeted
  Flutter analyze on the stream runner/test files.

### Remaining Boundary

- This was a local source/WebRTC no-readback proof, not final live gameplay
  readiness. At the time, the BG3 Smooth 720p D3D11 gate was to show no full app
  crash, visible local/remote output, nonzero `nativeNv12Submitted`, zero
  `nativeNv12Failures`, zero or near-zero legacy `readbackQueued`, zero
  `cpuFallback`, and, for the hardware H.264 path, Media Foundation markers
  with `input_path=native_nv12`, `native_input=yes`, and
  `native_sample_failed=no`. Later live validation moved the retained Debug
  branch back to CPU I420 for stability, so those markers now belong to the next
  GPU handoff phase rather than the current Smooth 720p30 safe-path check.
- If those encoder markers fall back to `cpu_i420`, the full-source readback
  problem is still solved at the WebRTC source boundary, but the GPU encoder
  handoff remains incomplete and the next work should stay inside native
  Media Foundation/WebRTC input handling rather than LiveKit, bitrate,
  fallback, or receiver policy.

## 2026-06-08 Phase 2 Source/Readback Stage Proof

- Implemented the GPU-first roadmap Phase 2 diagnostics for the debug D3D11
  game-hook WebRTC source. This is a measurement/reporting pass only: no
  stream profiles, bitrate, fallback thresholds, LiveKit options, receiver
  policy, or normal WGC/window-GDI defaults changed.
- Native `game_capture_webrtc_source` stats now split aggregate
  `sourceToSubmitMs` into:
  - `sourceToReadbackReadyMs/MaxMs/Samples`
  - `readbackQueueToMapMs/MaxMs/Samples`
  - `mapToI420Ms/MaxMs/Samples`
  - `sourceToI420ReadyMs/MaxMs/Samples`
  - `sourceToQueueMs/MaxMs/Samples`
- The stream-test runner parses these fields into per-preset JSON, the native
  summary label, bottleneck evidence, the diagnostic coverage matrix category
  `game-capture stage timing`, and early/middle/late/tail time-window summaries.
  Future D3D11 reports should therefore identify whether remaining 100 ms-class
  gaps are before readback readiness, while waiting to map a scaled readback,
  inside BGRA/R10-to-I420 conversion, or in the delivery queue handoff.
- Native validation passed with bundled Ninja:
  `third_party\ninja\ninja.exe -C out-release\Windows-x64 libwebrtc`.
  The rebuilt DLL fingerprint was recorded in private validation evidence.
- Refreshed patched artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`. The exact
  artifact fingerprint was recorded in private validation evidence.
  Previous artifact backup:
  `libwebrtc.zip.bak-phase2-stage-timing-20260608-113239-89B313B20A284C2C`.
- Dart-side validation passed outside the sandbox with workspace-local AppData:
  Dart format, focused `stream_test_runner_test.dart`, and targeted Flutter
  analyze for the stream runner and focused test.

### Synthetic Target Validation

- 2026-06-08 local synthetic validation passed before requesting another BG3
  run. `tools/stream-lab/run_local_capture_benchmark.ps1` with the
  deterministic `InterGalacticCaptureTarget` at `1280x720@60` and a
  `1280x720@30` NV12 publication handoff completed successfully:
  `runtime/stream-lab/local-results/local-capture-20260608-115445/`.
- The local handoff path reported D3D11 Present FPS `57.091`, Present p95/max
  gap `31.037 / 62.002 ms`, hook copy avg/max `0.011 / 2.432 ms`, host frame
  age avg/p95/max `0.313 / 0.37 / 14.116 ms`, output FPS `31.825`, output
  p95/max gap `32.15 / 46.217 ms`, NV12 frames/failures/convert avg
  `312 / 0 / 0.025 ms`, proof-visible frames `3 / 3`, and total handoff frame
  avg `0.177 ms`.
- A source-local call into the exported
  `InterGalacticGameCaptureWebrtcSourceSmoke` entry point also completed:
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260608-115723/`.
  This exercised the patched WebRTC source class directly and proved the new
  stage fields are emitted. The synthetic run reported `gpuScaled=291`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `submitted=291`, `repeated=0`,
  `deliverySubmitted=291`, `deliveryOverwritten=0`, visible BGRA/I420 proof
  frames, and `visibleSourceSeen=true`.
- The WebRTC-source split in the synthetic smoke was dominated by the intended
  proof-only readback cadence rather than conversion or delivery queue time:
  `sourceToReadbackReadyMs=29.64`, `readbackQueueToMapMs=28.6013`,
  `mapToI420Ms=0.88308`, `sourceToI420ReadyMs=30.5231`,
  `sourceToQueueMs=30.5604`, and `deliveryQueueWaitMs=0.181555`.
  Synthetic target metrics were stable enough for this gate:
  `presentFps=58.671`, p95/max Present gap `31.121 / 32.728 ms`, and no missed
  frame intervals.
- Important boundary: `gpuScaled > 0`, `gpuScaleFailures=0`, and visible local
  NV12 proof frames do not mean the live WebRTC GPU encoder handoff is solved.
  They prove the D3D11 texture can be GPU-scaled and that the helper can produce
  encoder-shaped proof surfaces. The current debug WebRTC-source path still
  uses `D3D11 texture -> GPU scale -> staging readback/map -> CPU I420 ->
  WebRTC OnFrame`. The better target remains `D3D11 texture -> GPU scale ->
  GPU NV12 or another encoder-compatible surface -> hardware encoder /
  WebRTC-compatible handoff`.
- Cleanup was verified after the source smoke: no
  `InterGalacticCaptureTarget` or `intergalactic_game_capture_helper` process
  remained. This clears the synthetic/source-local validation target for Phase
  2, but it does not close BG3/live-call jitter because BG3 may stress the
  same stage split differently.

### Next Validation Target

- Do not request another broad BG3 preset batch yet. The synthetic/source-local
  gate is cleared, so the next useful run is a single Smooth 720p D3D11
  game-hook stream-test against BG3 that confirms the new
  `game-capture stage timing` fields appear in the in-app stream-test
  JSON/Markdown under real game load.
- If `readbackQueueToMapMs` dominates, work on async readback/fence/ring
  scheduling. If `mapToI420Ms` dominates, prioritize GPU/NV12/encoder handoff.
  If `sourceToQueueMs` is high while `sourceToI420ReadyMs` is low, investigate
  delivery-thread wake/queue behavior.
