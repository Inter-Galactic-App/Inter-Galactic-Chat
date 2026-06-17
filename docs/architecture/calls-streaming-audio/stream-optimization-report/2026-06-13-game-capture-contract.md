# 2026-06-13 Game Capture Contract And Host-Load Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-13 23:51 BG3 Native-NV12 Pacing Report

- Fresh BG3 Smooth 720p30 report inspected:
  `stream-test-2026-06-13T23-51-43-712859Z`. The debug app loaded the expected
  `libwebrtc.dll` digest `A249AE5C08C9`, observed `game-d3d11-hook`, captured
  D3D11/R10/event/ready with `failureReason=none`, and completed without an app
  crash.
- True GPU/native-NV12 stayed active: native NV12 submitted 1766 frames with
  0 failures, CPU I420 fallback stayed at 0, proof frames were visible, and
  packet loss was 0%. This rules out source attach, visibility, fallback,
  native sample creation, and packet loss as the primary current boundary.
- The run still missed Smooth 720p30 at the sender: capture/encode/send averaged
  about `27.2/22.3/23.4` FPS, with the first measured window around
  `27.0/13.8/16.2` before recovering to about `27.9` send FPS in the tail.
  Host load was high, with system CPU avg/max about `90%/97%` and BG3 target
  CPU about `39%` average.
- Native evidence now points at delivery/source-to-submit pacing under host
  load rather than readback: source-to-submit max `280.8 ms`, delivery queue
  wait max `194.2 ms`, delivery wall max `175.1 ms`, delivery overwrites `65`,
  pacer resyncs `110`, native NV12 ready drops `93`, not-ready polls `3782`,
  and native NV12 readiness avg/max about `22.6/182.5 ms`. Media Foundation
  timing improved versus the earlier 20:10/20:12 runs at about `16.9 ms`
  average, with 10/58 sampled slow frames.
- Report classifier follow-up: native-NV12 delivery backpressure now runs before
  repeated-frame readback evidence, and proof-only readback timings are no
  longer used as primary evidence for true native-NV12 runs. The older readback
  and repeated-frame classifier cases remain covered separately.
- Local validation for this reporting fix passed outside the sandbox: Dart
  format, focused Flutter tests for native-NV12 proof-readback ordering,
  delivery-backpressure ordering, repeated-frame pacing, and readback delivery
  pressure, plus targeted Flutter analyze of the edited runner/test files.

## 2026-06-13 Delivery Backpressure Classifier And Native Drain Tuning

- Reports `stream-test-2026-06-13T20-10-47-409363Z` and
  `stream-test-2026-06-13T20-12-07-147015Z` kept the true D3D11/native-NV12
  path alive but did not meet Smooth 720p30. App-default correctly resolved to
  `game-d3d11-hook`; both reports showed native NV12 submitted frames, no CPU
  fallback, no native NV12 failures, no packet loss, and no app crash.
- The failed boundary is local frame delivery / encoder backpressure under
  heavy host load, not source selection, visibility, fallback, or network loss.
  Host CPU averaged about 82-84% and peaked about 92-94%; BG3 target CPU
  averaged about 46-47%; GPU utilization counters were still 0%, which is a
  sampler blind spot rather than proof the GPU was idle.
- Evidence for the boundary: the reports landed around capture/encode/send
  `20.7/20.4/18.9` and `22.2/21.5/18.6` FPS while native markers showed
  source-to-submit max 218-300 ms, delivery queue wait max 133-161 ms,
  delivery wall max 179-196 ms, delivery overwrites 208/354, and delivery
  pacer resyncs 204/360. Native NV12 readiness averaged about 32-34 ms with
  high tails, and Media Foundation encoder timing averaged about 60-66 ms with
  slow samples.
- The stream-test classifier now reports this evidence as
  `frame_pacing_unstable` before the generic `encoder_pipeline_limited` path.
  The report keeps WebRTC/Media Foundation encode timing as positive evidence
  for this boundary instead of listing it as a false-cause exclusion, while
  preserving the existing source-to-submit evidence path.
- Native delivery now registers the capture and delivery threads with MMCSS
  `Capture` when `avrt.dll` is available, while retaining the existing thread
  priority boost. The native-NV12 ready-slot drain also queues only the newest
  ready slot per pass instead of letting a burst fill the two-frame delivery
  queue; older ready slots are counted through the existing
  `nativeNv12ReadyDropped` metric.
- Local validation passed outside the sandbox: Dart format, focused classifier
  tests for the new delivery-backpressure boundary and the older
  source-to-submit visual pacing boundary, targeted Flutter analyze from the
  earlier classifier pass, native Ninja build of `libwebrtc.dll`, generated
  helper/hook Debug build, Flutter Windows Debug rebuild, and a stream debug
  package refresh at `runtime/stream-lab/debug-builds/20260613-205103/`.
  Native and Debug runner `libwebrtc.dll` SHA-256 matched at
  `A249AE5C08C9E37539A17056717B4014512412D53A278787A408386A1F0C7C5D`; patched
  `libwebrtc.zip` SHA-256 was
  `F9DC095F1C1D06704598A3125771B926FF123C563AD0A13D8FAB4ACF600EB1FC`; Debug
  runner exe SHA-256 was
  `A654AE8C1A1F6EAF92B241B97F0613D68392ADF4514808B5741D38E8BF2E5BFB`.
- No-call BG3 helper/handoff validation passed at
  `runtime/stream-lab/local-results/local-capture-20260613-165606/`. BG3 PID
  `bg3_dx11` was attached by process id, D3D11/R10/event/ready contract fields
  were present with `failureReason=none`, Present FPS was 29.767, hook copy
  avg/max was 0.002 / 0.013 ms, host consumed 282 frames, NV12 handoff output
  FPS was 28.968, NV12 conversion produced 282 frames with 0 failures and
  0.028 ms average conversion, and 3 / 3 proof frames were visible.
- The local harness did not exercise Matrix, LiveKit, WebRTC sender stats,
  receiver decode, network, or the patched libwebrtc delivery thread in an
  active call. The in-call BG3 stream test remains pending because the Windows
  desktop automation helper failed during bootstrap, so this pass did not
  automate debug-app launch, call-hotkey join, BG3 focus, or W-key input.

## 2026-06-13 Host Load Sampler Hardened And Synthetic Local Rerun

- The first rebuilt synthetic D3D11 report after adding the `hostLoad` report
  surface proved the Markdown/JSON/report plumbing but failed the sampler
  boundary: `stream-test-2026-06-13T18-44-50-103913Z` completed with
  `hostLoad.available=false`, `sampleCount=0`, and unavailable reason
  `host load sampler emitted no samples`.
- Direct local probing showed the sampler was too all-or-nothing for short
  stream tests. `Win32_Processor` / `Win32_OperatingSystem` CIM reads were
  denied on this host, and the first GPU `Get-Counter` sweep could take long
  enough that cleanup killed the sampler before any stdout JSON sample was
  emitted.
- The sampler now uses .NET `Diagnostics.PerformanceCounter` for CPU/RAM/GPU
  counters and emits an immediate CPU/RAM/process sample before the slower GPU
  sweep. GPU utilization and dedicated-memory counters are cached into the
  next sample, so short tests can still report partial host evidence instead
  of returning zero samples.
- Validation passed with Dart format, focused `stream_test_runner_test.dart`
  host-load tests, targeted Flutter analyze, a direct two-sample embedded
  PowerShell probe, a Dart-only debug rebuild, and a no-BG3 local synthetic
  stream run.
- Latest no-BG3 validation report: `stream-test-2026-06-13T19-02-33-103002Z`.
  The local synthetic target was selected by process id to avoid launching
  BG3. The Diagnostic Coverage Matrix reports `host/system load` as available
  with 3 samples, no missing host metrics, CPU avg/max 96.3%/99.0%, RAM
  avg/max 52.3%/53.0%, app CPU 8.5% average, target CPU 0.5% average, GPU 3D
  and video encode 0.0%, and dedicated GPU memory around 2849 MB.
- The same no-BG3 run exercised the D3D11 game-hook path without crashing:
  Smooth 1280x720, observed `game-d3d11-hook`, score 57, capture/encode/send
  about 30.0/5.0/5.4 FPS, 0% loss, 2 ms RTT, native NV12 active with 295
  submitted frames, 0 native NV12 failures, 0 CPU fallback, and only proof
  readbacks. Classification remained `encode_limited`; this validates
  diagnostics stability, not BG3 performance readiness.
- Workflow caveat: the rebuilt Debug app was launched from the workspace root,
  so the built-in synthetic target resolver did not find the existing
  `tools/game-capture-target/build/Debug/InterGalacticCaptureTarget.exe`.
  The successful local run used a manually launched target PID, which means the
  report's built-in `game-capture test target` section is N/A. Follow-up should
  package/resolve the test target for Debug launches or wire the automation
  executable-path override so future no-BG3 runs keep target diagnostics.

## 2026-06-13 Host Load Diagnostics Added For Bad-Run Correlation

- The bad BG3 run `stream-test-2026-06-13T17-51-46-462822Z` did not include
  host/system CPU, RAM, or GPU load, so it could not separate local machine
  contention from stream delivery / encoder backpressure.
- Stream-test runs now start a parsed Windows host-load sampler for the batch
  and stop it during bounded cleanup. Reports include top-level `hostLoad`
  JSON, a Markdown `## Host/System Load` section, and a `host/system load`
  Diagnostic Coverage Matrix row.
- The report surface summarizes system CPU, memory used/available, GPU engine
  utilization for 3D/copy/video encode/compute, dedicated GPU memory, and
  app/target process CPU when the target PID is available. Raw process names,
  executable paths, source titles, local usernames, and PIDs are not serialized.
- Counter failures or unsupported platforms are reported as unavailable and do
  not fail the stream test. No bitrate, LiveKit/SFU, receiver, fallback,
  source-selection, native game-capture, or encoder behavior changed in this
  pass.
- Next rebuilt BG3 report should compare the new host-load row against
  capture/encode/send FPS, native delivery gaps, and Media Foundation timing
  before labeling a poor run as network-limited or local encoder-limited.

## 2026-06-13 Rebuilt BG3 Contract Proof And Backpressure Regression

- Latest report inspected: `stream-test-2026-06-13T17-51-46-462822Z`.
  Requested settings were Smooth 1280x720, 30 FPS target / 36 FPS sender cap,
  H.264 hardware-first, single layer, and the D3D11 game-hook backend.
- Rebuilt-artifact proof passed. The report loaded `libwebrtc.dll` digest
  `7092806BBA9A`, matching the full debug package manifest
  `runtime/stream-lab/debug-builds/20260613-170649/`, and the Diagnostic
  Coverage Matrix includes `game-capture backend contract` as available.
- Actual backend proof passed. The observed capturer was `game-d3d11-hook`;
  the live backend contract reported version `2`, `sourceApi=d3d11`,
  `sourceFormat=r10g10b10a2`, `syncKind=event`, `readyState=ready`, and
  `failureReason=none`.
- Visibility/color proof passed. The native source was 2560x1440, output was
  1280x720, pre-I420 proof was 2 / 2 visible, I420 proof was 1 / 1 visible,
  and the encoded sender resolution stayed at 1280x720.
- GPU/native handoff stayed alive but did not meet the Smooth 720p30 pacing
  target. The run completed with `nativeNv12Submitted=746`,
  `nativeNv12Failures=0`, `cpuFallback=0`, and only proof readbacks
  (`readbackQueued=3`), but game-capture submitted cadence averaged about
  21.3 FPS.
- Non-regression failed versus the prior clean BG3 Smooth report
  `stream-test-2026-06-11T19-37-35-988891Z`: capture/encode/send moved from
  about 29.8/30.2/30.2 FPS to 23.3/11.8/9.4 FPS, score moved from 90 to 36,
  `deliveryOverwritten` moved from 0 to 149, `deliveryPacerResyncs` moved from
  0 to 145, `sourceFrameGaps` moved from 52 to 1192, max delivery wall gap
  moved from 45 ms to 266 ms, max delivery queue wait moved from 57 ms to
  240 ms, and max source-to-submit moved from 168 ms to 294 ms.
- Network/sender pressure was real but should not be treated as the whole
  boundary. The report classified `network_limited` because max RTT reached
  223 ms and available outgoing bitrate was reported around 302 kbps, while
  loss stayed 0%. However, local delivery and encoder evidence also regressed:
  WebRTC average encode time was 208 ms, native Media Foundation encoder timing
  averaged about 64 ms with 232 ms max, 13 / 23 sampled encoder markers were
  slow/very slow, one `not_accepting` marker appeared, and
  `deliveryOnFrame` reached 266 ms.
- Causes ruled out for this run: wrong native artifact, missing backend
  contract fields, source invisibility/black output, CPU I420 fallback, native
  NV12 conversion failure, profile resolution-limit failure, packet loss, and
  D3D11 hook attach failure.
- Current diagnosis: contract extraction is validated in a live packaged run,
  but D3D11 performance is not validated. The first actionable local boundary
  is the sender delivery / Media Foundation encoder backpressure path under
  transient network pressure, not bitrate tuning, receiver policy, or a return
  to I420 fallback.
- Recommended next local pass: audit and tighten stream-test classification so
  a single high RTT window does not hide simultaneous game-hook delivery and
  encoder-handoff regressions, then inspect the Media Foundation
  `ProcessInput` / WebRTC `OnFrame` backpressure path before asking for another
  BG3 validation run.

Diagnostic coverage matrix for this run:

| Area | Result |
| --- | --- |
| Source/backend | PASS - window source, D3D11 game hook, PID/title available |
| Requested settings | PASS - Smooth 1280x720@30 target / 36 cap |
| Artifact identity | PASS - `libwebrtc.dll` digest `7092806BBA9A` |
| Backend contract | PASS - v2 D3D11/R10/event/ready fields present |
| Visibility/color | PASS - pre-I420 and I420 proof frames visible |
| GPU scale/native NV12 | PASS for continuity - no CPU fallback or NV12 failures |
| Frame pacing | FAIL - submitted/delivery cadence below target with tail gaps |
| Encoder handoff | WARN - native NV12 input used, but slow MF samples and one `not_accepting` |
| Network | WARN - 0% loss, but max RTT 223 ms and low available outgoing estimate |
| Receiver | Missing - decode/render/subscribed-layer evidence unavailable |

## 2026-06-13 Multi-API Game-Capture Contract Slice

- `GAME_CAPTURE_MULTI_API_BACKEND_PLAN.md` Phase 1 has started as a
  backend-contract extraction around the proven D3D11 path only. The active
  boundary is future expansion risk: Vulkan/DX12 must not grow separate
  one-off attach, shared-frame, conversion, encoder handoff, or diagnostic
  report shapes.
- The D3D11 shared state, hook reports, helper host/publication reports,
  libwebrtc `game_capture_webrtc_source` markers, and Dart stream-test parser
  now share a common contract vocabulary: `backendContractVersion`,
  `sourceApi/sourceApiId`, `sourceFormat/sourceFormatId`, `colorSpace`,
  `syncKind`, `readyState`, and `failureReason`.
- Stream-test JSON/Markdown now includes a `game-capture backend contract`
  coverage row when a game-hook source is observed. The row should be treated
  as a rebuilt-artifact proof gate for the next BG3 run: if it is missing,
  the report cannot be used to compare future API backends.
- Local validation for this implementation slice passed: Dart format, focused
  stream-test parser coverage for the new contract marker fields, targeted
  Flutter analyze, direct MSBuild Debug builds for
  `intergalactic_game_capture_helper.exe` and
  `intergalactic_game_capture_hook64.dll`, the patched libwebrtc
  `third_party\ninja\ninja.exe -C out-release\Windows-x64 libwebrtc` target,
  coordination JSON parse, conflict-marker scan, scoped diff whitespace checks,
  and a post-validation process sweep.
- Debug package refresh passed after hardening the command structure. The
  wrapper `tools/stream-lab/stream_debug_build.ps1 -Mode Full` now runs the
  stable native/helper/artifact/Flutter Debug/bundle sequence, and the package
  script auto-detects Visual Studio 2022's bundled `cmake.exe` when CMake is
  not on PATH. Full manifest
  `runtime/stream-lab/debug-builds/20260613-170649/` completed with zero
  warnings and an empty process sweep; native and Debug runner `libwebrtc.dll`
  SHA-256 matched at
  `7092806BBA9A1EC3BAFEE583ED05878D4C0487BAF8D07EBB9580E8C24EEC0DA6`, patched
  `libwebrtc.zip` SHA-256 was
  `49571A85E3E92748862BCF8B0819CBD95542625264B9FF39361EA368E64CE087`, and
  Debug runner helper/hook hashes matched the generated Debug outputs. The
  quick native refresh command `-Mode NativeQuick -NoZip` also passed in
  `runtime/stream-lab/debug-builds/20260613-170838/` without Flutter.
- This pass intentionally leaves bitrate, LiveKit/SFU behavior, receiver
  policy, production defaults, fallback policy, P010/HDR tuning, and
  Vulkan/DX12/OpenGL implementation untouched.
