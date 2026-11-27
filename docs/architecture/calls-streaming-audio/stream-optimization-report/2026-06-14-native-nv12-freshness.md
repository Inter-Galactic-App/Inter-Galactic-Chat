# 2026-06-14 Native NV12 Freshness And Latest-Frame Queue Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-14 23:40 Native NV12 Explicit-Fence Handoff Build

- Summary: EXPERIMENTAL implemented the concrete GPU synchronization /
  native encoder handoff pass after the bounded-pending loop. No new live BG3
  or call stream test was run in this pass.
- Build manifest:
  `runtime/stream-lab/debug-builds/20260614-234001/stream-debug-build-20260614-234001.md`.
- Native/debug-runner `libwebrtc.dll` SHA-256:
  `8663F97A4777BD58C4E75B1E51F760827D838C24ED198110A6C0D5A21ADCA71B`.
- Patched `libwebrtc.zip` SHA-256 remained
  `50F4F0222087DFEBBF38D8D7841DB9A20E9B4408FFAD7A519618BC1F00321DFA`.
- Capturer change: `INTERGALACTIC_GAME_CAPTURE_NV12_READY_POLICY` now defaults
  to `fence`. The D3D11 path creates a per-device `ID3D11Fence`, signals it
  immediately after `VideoProcessorBlt`, queues the native NV12 buffer with the
  fence/value token, and falls back to event-query readiness when
  `ID3D11Device5` / `ID3D11DeviceContext4` or signal creation is unavailable.
- Buffer change: `IntergalacticD3D11Nv12Buffer` now carries an optional
  `ID3D11Fence` and fence value with the texture and exposes a bounded wait
  helper so the fence object lifetime stays tied to the native frame buffer.
- Encoder change: the Media Foundation H.264 native sample path waits up to
  50ms on the explicit fence before creating/submitting the DXGI surface
  sample. Encoder timing diagnostics include `native_ready_fence`,
  `native_ready_fence_timeout`, and `native_ready_fence_wait_ms`.
- Validation: native `libwebrtc` compile/link passed. The first full wrapper
  attempt failed only during the separate game-capture helper CMake stamp
  refresh; a rerun with helper build skipped completed and copied the rebuilt
  native DLL into the Debug runner.
- Next evidence needed: one BG3 Smooth 1280x720@30 D3D11 game-hook test when
  live testing resumes, with explicit checks for color correctness,
  `nativeNv12FenceAvailable`, `nativeNv12FenceSignaled`, encoder fence wait
  duration, `deliveryOnFrame`, Blt-to-ready, source-to-submit, and
  capture/encode/send FPS.

## 2026-06-14 23:14 BG3 Native NV12 Readiness Five-Cycle Loop

- Summary: Live Testing Override completed the five allowed BG3 Smooth
  1280x720@30 D3D11 game-hook cycles after rebuilding NativeQuick package
  `runtime/stream-lab/debug-builds/20260614-230459/stream-debug-build-20260614-230459.md`.
  Runner `libwebrtc.dll` SHA-256:
  `3B00718305CED4797C529962B8929EA6D838262135B60111A988DFD3DBE4356C`.
- Current pipeline map under test:
  `BG3 DX11 Present -> D3D11 hook/shared texture -> GPU scale -> native NV12
  surface -> WebRTC source OnFrame -> Media Foundation H.264 -> LiveKit sender`.
- Reports inspected in this loop:
  `stream-test-2026-06-14T22-52-57-515220Z`,
  `stream-test-2026-06-14T22-59-17-743662Z`,
  `stream-test-2026-06-14T23-06-59-003038Z`,
  `stream-test-2026-06-14T23-10-07-941076Z`, and
  `stream-test-2026-06-14T23-13-06-817716Z`.
- Source/backend/settings: BG3 DX11, D3D11 game hook, R10G10B10A2 source,
  Smooth 1280x720@30, H.264 Media Foundation path. The runs preserved
  source-QPC timestamps, zero CPU fallback, zero native NV12 failures, and zero
  repeated submitted frames in the successful non-starved paths.
- Source visibility and color correctness: R10/BG3 proof stayed visible enough
  for stream classification. A separate SDR/8-bit deterministic capture-target
  comparison preserved expected marker/text/band colors, but requiring users to
  change game HDR/SDR settings is not a product fix.
- Queue-after-BLT result: `nativeNv12NotReadyPolls=0` and
  `nativeNv12ReadyDropped=0`, but the wait moved downstream. The run classified
  `webrtc_onframe_limited`, reached about `25.5/26.1/24.6`
  capture/encode/send FPS, and showed delivery OnFrame plus encoder input
  stalls. Do not default this policy.
- Event-query poll1 result: shortening pending readiness polling to `1 ms`
  classified `native_nv12_ready_limited` and reached about `25.3/24.9/24.2`
  FPS. It improved honesty of readiness waiting but produced high poll churn:
  `nativeNv12NotReadyPolls=17629`, `nativeNv12ReadyDropped=37`.
- Bounded pending result: `nativeNv12MaxPending=1` starved the live path and
  regressed to about `3 FPS`. `maxPending=2` recovered to about
  `24.7/22.5/23.1` FPS. `maxPending=3` was the best bounded run at about
  `24.4/24.8/24.8` FPS, still `native_nv12_ready_limited` with
  `nativeNv12Queued/Ready=1751/1709`, `nativeNv12NotReadyPolls=16817`,
  `nativeNv12ReadyDropped=41`, source-to-submit avg/max about `47/188 ms`,
  native NV12 convert avg/max about `22/131 ms`, Blt-to-ready avg/max about
  `22/113 ms`, and encoder total avg/max about `17/111 ms`.
- Likely bottleneck: GPU/NV12 readiness plus native encoder/WebRTC handoff
  under BG3 R10 gameplay load. The evidence no longer supports bitrate,
  LiveKit/SFU/TURN, receiver policy, WGC/GDI fallback, or user SDR settings as
  the next product path.
- Recommended next implementation step: keep the new readiness-policy, poll
  cadence, and max-pending controls guarded as diagnostics only; inspect the
  native NV12 / Media Foundation / WebRTC boundary for explicit GPU
  synchronization or a true GPU-surface encoder handoff; after a concrete
  handoff change, run exactly one BG3 Smooth 1280x720@30 D3D11 game-hook
  validation.
- Rollback notes: no production default should depend on
  `INTERGALACTIC_GAME_CAPTURE_NV12_READY_POLICY=queue-after-blt`,
  `INTERGALACTIC_GAME_CAPTURE_NV12_PENDING_POLL_MS=1`, or
  `INTERGALACTIC_GAME_CAPTURE_NV12_MAX_PENDING`.

Diagnostic coverage matrix for this loop:

| Boundary | Evidence | Status |
| --- | --- | --- |
| Source/backend | BG3 DX11, D3D11 game hook, R10G10B10A2, Smooth 1280x720@30 | covered |
| Hook attach / visibility | Game-hook reports completed with valid output and no hook failure | covered |
| Source Present cadence | Source-QPC timestamps remained active; detailed present-gap proof still indirect | partial |
| GPU scale / native NV12 creation | `cpuFallback=0`, native NV12 failures `0`, 1280x720 output | covered |
| Native NV12 readiness | poll counts, ready drops, Blt-to-ready, and convert timings captured across all policies | covered |
| CPU map / conversion | CPU fallback absent in successful non-starved runs; CPU conversion not the reported hot path | covered enough |
| WebRTC OnFrame | queue-after-BLT moved stalls to OnFrame/encoder, proving early queueing is unsafe | covered |
| Encoder | Media Foundation H.264 stayed active; encoder tail remained above frame budget in several runs | covered |
| Network/server | No evidence from this loop points to network/SFU; not primary suspect | not pursued |
| Product decision | SDR/game-setting requirement rejected; debug knobs remain diagnostics-only | decided |

## 2026-06-14 01:53 BG3 Native-NV12 Freshness Run

- Fresh BG3 Smooth report inspected:
  `stream-test-2026-06-14T01-53-11-871079Z`. The run completed without an app
  crash, loaded `libwebrtc.dll` digest `96963AA2A042`, used
  `game-d3d11-hook` with D3D11/R10/event/ready and `failureReason=none`, and
  stayed on H.264 `MediaFoundationH264` hardware encode at `1280x720`.
- True native NV12 remained active: `nativeNv12Submitted=1461`,
  `nativeNv12Failures=0`, `cpuFallback=0`, `gpuScaled=1469`, and
  `gpuScaleFailures=0`. Network still was not the primary limiter:
  packet loss `0%`, NACK `0`, quality limitation `none`, and the requested
  resolution cap held.
- The run still missed Smooth 720p30: score `70`,
  capture/encode/send about `23.0/22.8/23.8` FPS, native submitted FPS about
  `24.3`, source frame duplicates `253/1469` (`17.2%`), source frame gaps
  `2215`, source QPC avg/max about `50/267 ms`, source-to-submit avg/max about
  `49/245 ms`, delivery queue wait avg/max about `15/95 ms`, delivery wall
  avg/max about `42/227 ms`, delivery overwrites `241`, and pacer resyncs
  `185`. Host CPU was high at about `84.7%/90.0%` avg/max, with BG3 target CPU
  about `40.4%` average.
- The new raw native source-freshness counters are present in the log block but
  not in the parsed JSON/tables from this Debug runner. Final raw stats show
  `deliveryRepeatNoQueued=253` with repeat source age avg/max about
  `87/286 ms`, `deliveryOverwrittenFresh=241` with overwrite age avg/max about
  `85/240 ms`, `nativeNv12ReadyDroppedFresh=157` with ready-drop age avg/max
  about `76/248 ms`, and `nativeNv12OverwrittenFresh=0`.
- Diagnosis for this specific report: the native instrumentation was refreshed,
  but the app-side stream-test parser/classifier was stale. The Debug runner's
  `data/flutter_assets/kernel_blob.bin` timestamp was older than current
  stream/call app sources, so this run can be used for raw native evidence but
  not as validation that the new parser, JSON fields, or classifier wording are
  shipped in the app.
- Workflow fix added: NativeQuick debug-build refresh now checks stream/call
  Flutter source freshness when `-SkipFlutterBuild` is used and refuses stale
  Debug runner assets unless `-AllowStaleFlutterBuild` is explicitly passed for
  a verified native-only refresh. Validation passed for plan mode, and an
  expected stale-guard failure was captured in private stream-lab debug-build
  evidence. The guard run found no task-owned leftover processes.

Next validation should be a Full debug rebuild, not NativeQuick, followed by
one BG3 Smooth 1280x720@30 gameplay run. Only after the rebuilt app parses the
new freshness counters should the next native pass decide whether to change
ready-drop selection, delivery overwrite policy, source cadence handling, or
host-load scheduling behavior.

## 2026-06-14 Source-Freshness Attribution Pass

- Implementation pass completed for the failed 00:48 BG3 boundary where native
  NV12 stayed active but repeated submitted frames worsened under the native
  latest-frame pacer. This pass is diagnostic-first and does not change stream
  presets, bitrate policy, fallback behavior, LiveKit/SFU behavior, call UI, or
  AUDIO/RNNoise.
- Native `game_capture_webrtc_source stats` now distinguishes the main stale
  source paths:
  `deliveryRepeatNoQueued`, repeat source age avg/max/samples,
  delivery-overwrite age plus fresh-overwrite count, duplicate source-skip age,
  native NV12 pending-overwrite age plus fresh-overwrite count, and native NV12
  ready-drop age plus fresh-drop count.
- The stream-test parser, JSON report, compact native diagnostics label,
  time-window counters, and `frame_pacing_unstable` classifier now surface those
  fields. The next bad BG3 run should say whether repeats came from the game
  source not advancing, the delivery pacer having no fresh queued frame, fresh
  frames being overwritten in the delivery queue, or native NV12 ready/pending
  frames being dropped before submission.
- Local validation passed outside the Dart/Flutter sandbox: Dart format on
  `stream_test_runner.dart` and `stream_test_runner_test.dart`, targeted Flutter
  tests for `game hook delivery backpressure` and `native NV12 delivery pacing`,
  focused native `ninja ... libwebrtc`, scoped Dart/libwebrtc `git diff
  --check`, conflict-marker scan, and process sweeps. The libwebrtc diff check
  only reported the existing LF-to-CRLF warning for the native source file.
- Debug runner refresh completed with NativeQuick manifest
  `runtime/stream-lab/debug-builds/20260614-013806/stream-debug-build-20260614-013806.md`.
  Native and Debug runner `libwebrtc.dll` SHA-256:
  `96963AA2A04262327C5D588F9123191A1765302C30F9C5D8287DC166F0F7E7C1`;
  patched `libwebrtc.zip` SHA-256:
  `E8F79D54CD58FD7909C169E96A0A17D6BD2321ECEA0AF8B5FE123842D4334329`.
  Helper/hook rebuild was intentionally skipped because this pass only changed
  libwebrtc; existing helper/hook binaries were copied into the Debug runner.

Next validation should be one rebuilt in-call BG3 DX11 Smooth 1280x720@30 run.
Compare the new repeat/overwrite/drop age and fresh-frame counters against the
00:42/00:48 D33 reports before tuning preset, bitrate, or fallback policy.

## 2026-06-14 00:48 BG3 Native Latest-Frame Pacer A/B

- Fresh BG3 Smooth report inspected:
  `stream-test-2026-06-14T00-48-19-302358Z`. This run used the same intended
  rebuilt native artifact as the 00:42 run: `libwebrtc.dll` SHA-256
  `D33EB59E4945DCAC7FE3D1DB04CCF5F9B7BA4C400F81117D2CFEDEC2C0B7E935`.
  It observed `game-d3d11-hook`, D3D11/R10/event/ready with
  `failureReason=none`, encoded `1280x720` H.264 through
  `MediaFoundationH264`, and completed without app crash.
- Difference under test: this report says `Native latest-frame pacer: enabled`,
  while `stream-test-2026-06-14T00-42-00-803565Z` says the same setting was
  disabled. This makes the pair a direct enough A/B for the separate native
  latest-frame pacer behavior, while keeping the same D33 latest-preferred
  delivery queue build.
- Pacer-on did not fix Smooth 720p30. Compared with the 00:42 pacer-off run,
  score moved `75 -> 70`, average capture/encode/send moved
  `26.2/26.2/27.8 -> 24.8/24.2/26.3`, and minimum capture/encode/send moved
  `21/22/22 -> 16/16/16`. The report still classified
  `frame_pacing_unstable`.
- The pacer-on run improved a few queue-shape counters but worsened source
  freshness. Delivery queue wait max moved `87.0 ms -> 84.9 ms`, pacer resyncs
  `90 -> 65`, and not-ready polls `3522 -> 2236`, but repeated submitted
  frames worsened from `211/1659` (`12.7%`) to `174/940` (`18.5%`), native
  ready drops increased `81 -> 108`, source-to-submit max rose
  `203.5 ms -> 217.0 ms`, and source QPC max rose `195.1 ms -> 220.4 ms`.
- The primary false causes remain ruled out: native NV12 stayed active
  (`nativeNv12Submitted=932`, `nativeNv12Failures=0`, `cpuFallback=0`,
  `gpuScaled=940`, `gpuScaleFailures=0`), encoder input remained
  `native_nv12`, proof frames were visible, packet loss was `0%`, NACK stayed
  clean, and the requested/encoded resolution stayed `1280x720`. Host load was
  still very high and comparable: system CPU avg/max `90.9%/100.0%`, app CPU
  about `11.1%`, target CPU about `37.5%`.
- Updated boundary: enabling the native latest-frame pacer can reduce some
  delivery lag/resync counters, but it does not solve the live BG3 failure and
  appears to trade frame uniqueness/FPS for queue shape under this load. The
  remaining first fix target stays upstream: source cadence / source-frame
  freshness and repeated-frame attribution before delivery, especially
  `sourceQpcDelta`, `sourceToQueue`, native ready-drop policy, and source frame
  gap/repeat causes.

Recommended next implementation step: keep the latest-preferred delivery queue
change, but do not treat the native latest-frame pacer as the current fix. Add
or repair source-cadence attribution around helper publish cadence, source QPC
gaps, source-to-queue latency, repeated submitted frames, ready-drop selection,
and frame lifetime/lock synchronization before another preset or bitrate pass.

## 2026-06-14 00:42 BG3 Latest-Frame Queue Validation

- Fresh BG3 Smooth report inspected:
  `stream-test-2026-06-14T00-42-00-803565Z`. The test used the intended
  rebuilt native artifact: `libwebrtc.dll` SHA-256
  `D33EB59E4945DCAC7FE3D1DB04CCF5F9B7BA4C400F81117D2CFEDEC2C0B7E935`.
  It observed `game-d3d11-hook`, D3D11/R10/event/ready with
  `failureReason=none`, encoded `1280x720` H.264 through
  `MediaFoundationH264`, and completed without app crash.
- The delivery-queue fix helped the intended tail: compared with
  `stream-test-2026-06-13T23-51-43-712859Z`, delivery queue wait max improved
  from `194.2 ms` to `87.0 ms`, source-to-submit max from `280.8 ms` to
  `203.5 ms`, delivery wall max from `175 ms` to `154 ms`, pacer resyncs from
  `110` to `90`, native ready drops from `93` to `81`, and not-ready polls
  from `3782` to `3522`. Encode/send FPS improved from about `22.3/23.4` to
  `26.2/27.8`, and minimum encode/send FPS improved from `6/5` to `22/22`.
- True native-NV12 remained active: `nativeNv12Submitted=1652`,
  `nativeNv12Failures=0`, `cpuFallback=0`, `gpuScaled=1659`,
  `gpuScaleFailures=0`, encoder input path `native_nv12`, and proof frames
  `2/2` visible with I420 proof `1/1`. Network was not the limiter:
  packet loss `0%`, max RTT `3.5 ms`, NACK `0`, and quality limitation
  `none`.
- The run still failed Smooth 720p30 as `frame_pacing_unstable`. Source repeats
  rose to `211/1659` submitted frames (`12.7%`, up from `6.8%`), source frame
  gaps remained high at `1938`, native FPS averaged `27.5`, capture FPS
  averaged `26.2`, source QPC max was `195.1 ms`, and source-to-queue max was
  `195.1 ms`. Host load stayed high and comparable to the previous run:
  system CPU avg/max `90.4%/96.0%`, app CPU about `12.9%`, target CPU about
  `38.5%`.
- Important caveat: this report says `Native latest-frame pacer: disabled`,
  while the prior `23:51` comparison run had `nativeFramePacingEnabled=true`.
  The `D33EB59` native DLL was definitely loaded, and the delivery queue
  latest-frame eviction path was exercised via `deliveryOverwritten=157`, but
  this is not a perfect toggle-for-toggle comparison of the separate native
  latest-frame pacer setting.
- Updated boundary: the latest-frame queue pass reduced stale delivery backlog.
  The remaining first visible boundary is now source cadence / source-frame
  freshness before delivery, not LiveKit/SFU, bitrate, fallback, native NV12
  sample creation, or Media Foundation input. The missing attribution fields
  that would sharpen the next native pass are blocking acquire wait, dirty-area
  ratio, dirty-region processing attribution, frame lifetime/lock
  synchronization attribution, full-frame update count, pre-downscale
  full-frame copy attribution, updated-region analysis timing, and
  updated-region rect count.

Recommended next implementation step: inspect why this rebuilt BG3 run had
`nativeFramePacingEnabled=false` and add/repair source-cadence attribution
around the remaining `sourceQpcDelta`, `sourceToQueue`, repeated-frame, and
source-frame-gap counters before requesting another live BG3 validation.

## 2026-06-14 Native Latest-Frame Delivery Queue Pass

- Failed boundary addressed: the 2026-06-13 BG3 Smooth run proved true
  native-NV12 delivery was alive, but sender pacing still missed 720p30 because
  source-to-submit and delivery queue tails grew under host load. The fix keeps
  the native delivery queue latest-preferred by evicting older queued
  non-repeated source frames before a newer source frame is queued, while
  preserving the existing `deliveryOverwritten` evidence counter.
- Exact path changed: `QueueFrameForDelivery` in
  `webrtc-build/src/libwebrtc/src/win/intergalactic_game_capture_video_capturer.cc`.
  The change is scoped to queued frame selection after native NV12/readback work
  is ready; it does not change LiveKit/SFU behavior, bitrate/profile defaults,
  fallback policy, AUDIO/RNNoise, P010/HDR scope, or call UI.
- Local source-smoke validation passed against the synthetic D3D11 target:
  `runtime/stream-lab/local-results/webrtc-source-smoke-20260613-202819-latest-delivery/webrtc-source-smoke.json`
  completed with requested `1280x720@30`, source `2560x1440`, output
  `1280x720`, `nativeNv12Submitted=222`, `nativeNv12Failures=0`,
  `cpuFallback=0`, `deliveryPacerResyncs=0`, `deliveryQueueWait` max
  `31.4 ms`, `sourceToSubmit` max `150.7 ms`, visible proof frames `2/2`,
  visible I420 proof `1/1`, and `deliveryOverwritten=1`.
- Native and packaging validation passed: Ninja rebuilt `libwebrtc.dll`, then
  `tools/stream-lab/stream_debug_build.ps1 -Mode NativeQuick -NoZip`
  refreshed the Debug runner. Manifest:
  `runtime/stream-lab/debug-builds/20260614-002921/stream-debug-build-20260614-002921.md`.
  Native and Debug runner `libwebrtc.dll` SHA-256:
  `D33EB59E4945DCAC7FE3D1DB04CCF5F9B7BA4C400F81117D2CFEDEC2C0B7E935`;
  patched `libwebrtc.zip` SHA-256:
  `832113216D1F8C8982F200FB36168C4402637C0832437B39D88EEE5696C22EE5`.
- Diagnostic coverage matrix for this pass:

  | Boundary | Evidence | Status |
  | --- | --- | --- |
  | D3D11 source attach / visibility | source-smoke visible proof `2/2`, I420 proof `1/1` | covered locally |
  | native NV12 creation | `nativeNv12Submitted=222`, failures `0`, CPU fallback `0` | covered locally |
  | delivery queue freshness | older queued source frames now evicted; `deliveryOverwritten` preserved and observed as `1` | changed and covered locally |
  | delivery pacing | source-smoke `deliveryPacerResyncs=0`, queue wait max `31.4 ms` | covered locally |
  | live BG3 sender pacing | next in-call BG3 Smooth run must compare source-to-submit, queue wait, pacer resyncs, native ready drops, host load, and FPS | pending user/live validation |

Next validation should be one rebuilt in-call BG3 DX11 Smooth 1280x720@30 run
using Debug runner manifest `20260614-002921`, focused on whether
source-to-submit max, delivery queue wait max, pacer resyncs, and native ready
drops improve versus `stream-test-2026-06-13T23-51-43-712859Z`.
