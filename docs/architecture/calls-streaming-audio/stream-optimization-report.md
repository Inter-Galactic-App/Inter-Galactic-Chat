# Stream Optimization Report

Last updated: 2026-06-22
Status: current index for historical streaming evidence

## Current Use

Use this file to route into the streaming evidence archive. Start with
`streaming-guidance-status.md` for current decisions, then open only the dated
archive slice needed for a specific investigation.

This report is not the primary implementation guide. Stable architecture and
runtime guidance live in:

- `streaming-pipeline.md` - stable MatrixRTC, LiveKit, WebRTC, shared audio,
  and diagnostics map.
- `livekit-gameplay-streaming.md` - current gameplay streaming defaults and
  diagnostic guidance.
- `streaming-guidance-status.md` - current guidance summary and next
  implementation decisions.
- `stream-diagnostic-contract.md` and `stream-bottleneck-classification.md` -
  stream-test reporting and classifier contract.

2026-06-19 refactor note: the stream-test runner internals were split
into same-library `stream_test_runner_*.dart` parts while keeping
`stream_test_runner.dart` as the stable import/orchestration surface. This was
an organization-only change; it did not alter LiveKit, sender/receiver runtime,
native capture, bitrate, codec, fallback, server, RNNoise, JSON schema,
Markdown output, or diagnostic labels.

2026-06-21 Phase 4 receiver-presentation note: the fourth phase of the
historical stream-optimization plan was implemented by adding
receiver presentation stage lineage for `remote_renderer_callback`,
`remote_texture_ready`, and `remote_ui_paint`. The external receiver runtime
now displays the same diagnostic `RTCVideoRenderer` that produces native frame
hashes, and in-process/external probes emit texture/UI stage timing, texture
id, native frame sequence, and callback-to-stage timing. Focused stream-test
tests, targeted analyze, Windows Debug rebuild, and synthetic external-render
validation passed. Synthetic run
`synthetic-live-call-freshness-20260621-144047` reported
`remote_renderer_callback=27`, `remote_texture_ready=29`,
`remote_ui_paint=29`, `remote_screen_present=0`, latest target stage
`remote_ui_paint`, receiver render unique FPS about 30.35, decoded FPS p50
about 30.01, and presentation p95 p50 48 ms. This is synthetic receiver
surface proof, not BG3/product visual proof. Clean BG3 run
`source-live-call-freshness-20260621-145710` then failed receiver quality
counters despite high/single H264 1280x720 receive/decode/render, about
2.91 Mbps inbound, QP about 20.3, no PLI/FIR/NACK, and receiver decoded/render
unique FPS about 29.68. Receiver presentation p95 remained red at p50 54 ms,
average 63.8 ms, and max gap 117 ms. `remote_screen_present` remains missing,
and the app-generated report still needs an external receiver summary merge so
external `remote_ui_paint` lineage is visible in the main report.

2026-06-22 non-DX11 app-default routing note: the shared Windows app-default
backend selector was tightened so window titles marked DX12,
D3D12, Vulkan, or OpenGL stay on the DirectX/window-GDI compatibility path
instead of the experimental D3D11 game hook unless a developer explicitly
selects the D3D11 override. The existing browser/non-game title guard and the
current BG3 D3D11 testing route remain intact. Validation was local/focused:
Dart format, `stream_test_runner_test.dart`, targeted Flutter analyze, and
scoped `git diff --check` passed. No live/BG3 smoke was run for this note.

2026-06-21 Phase 3 GPU-timestamp note: the third
phase of the historical stream-optimization plan was implemented by adding D3D11
GPU timestamp/disjoint query diagnostics around native NV12
`VideoProcessorBlt`. The stream-test contract now reports BLT CPU submit,
submit-to-fence, measured GPU execution, estimated GPU queue delay, and
timestamp fail/not-ready/disjoint counters. Focused Dart/Flutter validation,
native `libwebrtc` rebuild, and stream Debug packaging passed. Clean BG3 run
`source-live-call-freshness-20260621-135628` produced 146 BLT timestamp samples
with zero timestamp failures; BLT GPU execution averaged 0.29 ms and peaked at
14.51 ms, submit-to-fence averaged 1.87 ms and peaked at 41.15 ms, and
estimated queue delay averaged 1.58 ms and peaked at 26.72 ms. Receiver
presentation still failed at p95 p50 60 ms, so the next branch should focus on
GPU scheduling/contention/admission and sender-to-receiver presentation
correlation, not shader-converter, bitrate, hook-target, receiver-widget,
server, LiveKit, or RNNoise work.

2026-06-21 Phase 2 sender-mailbox note: the second
phase of the historical stream-optimization plan was implemented by adding a
latest-frame mailbox inside native WebRTC `FrameCadenceAdapter` for Inter
Galactic native D3D11 gameplay frames and dummy NV12 live-sender frames. The
mailbox keeps one active frame and one newest pending frame, replaces pending
frames while processing is active, drops stale pending frames after the
deadline, and reports replacement/stale/age/VSE timing counters through native
markers, stream-test labels, and JSON under
`webrtcRawSenderBoundary.frameCadenceQueue`. Normal window capture, I420,
camera, non-game sources, LiveKit, bitrate, profile, codec, fallback, server,
and RNNoise behavior were not changed. Local validation passed with Dart
format, focused stream-test tests, targeted analyze, native libwebrtc rebuild,
and stream Debug packaging. Later BG3/live validation showed the mailbox path
active but not green: receiver presentation remained red, leading to the Phase
3 GPU-timestamp diagnostic branch above.

2026-06-21 mailbox discard safety addendum: a review found that the new mailbox
and coalesce drop sites bypassed the existing adapter discard path that also
posts ZeroHz discarded-frame bookkeeping. The finding was verified and native
`FrameCadenceAdapter` was updated so mailbox replacement drops, mailbox
stale drops, mailbox internal coalesce drops, pre/post coalesce drops, and
queued coalesce drops all route through the shared discard notifier. The
mailbox eligibility gate remains limited to `helper-d3d11` and
`dummy-nv12-live-sender`. `clang-format`, focused native
`ninja ... libwebrtc`, and native `git diff --check` passed; patched artifact
and app-build refresh remain follow-up validation before the next BG3/browser
smoke.

2026-06-21 Phase 1 receiver-vocabulary note: the
first phase of the historical stream-optimization plan was implemented without a
streaming runtime behavior change. The current candidate baseline remains
D3D11 native NV12, explicit fence readiness, inactive native sink bypass, H.264
Media Foundation hardware encode, CBR, a single high-quality 1280x720 external
receiver, and no receiver-window recorder during performance tests. The
diagnostic-only settings remain forced 12/8 Mbps, low-delay VBR,
queue-after-BLT, ZeroHz overload bypass, larger delivery queues, direct native
preview, and helper target experiments. Stream-test reports now treat the
legacy receiver `remote_render` lane as `remote_renderer_callback`, keep
backward-compatible counters/statuses, and add receiver presentation-stage
coverage for `remote_decode`, `remote_renderer_callback`,
`remote_texture_ready`, `remote_ui_paint`, and `remote_screen_present`. Current
hash-tap evidence therefore proves renderer callback freshness only; texture,
UI paint, and screen-present proof remain the next diagnostic gap before
receiver-visible green claims.

2026-06-19 native cleanup note: the first safe
extraction from `docs/refactor/LIBWEBRTC_WIN_CUSTOM_REFACTOR_AUDIT.md` was implemented by
moving shared Windows libwebrtc diagnostic-file appending and `INTERGALACTIC_*`
environment parsing into `intergalactic_native_diagnostics.*` and
`intergalactic_native_config.*`. The D3D11 game-capture capturer and Media
Foundation H.264 encoder still keep their existing policy decisions, defaults,
diagnostic line shape, and runtime behavior. A focused Windows `libwebrtc`
Ninja build passed with `DEPOT_TOOLS_WIN_TOOLCHAIN=0`; no synthetic, live, or
BG3 validation was run for this behavior-preserving cleanup.

2026-06-19 native proof-writer cleanup note: the
second safe extraction from
`docs/refactor/LIBWEBRTC_WIN_CUSTOM_REFACTOR_AUDIT.md` was implemented by moving BGRA BMP
proof writing, proof directory creation, and BGRA visibility sampling into
`intergalactic_proof_frame_writer.*`. The D3D11 game-capture capturer still
owns the same proof call sites, two-frame pre-I420 cap, first/first-visible
I420 proof gate, counters, marker labels, artifact path, and stream behavior.
A focused Windows `libwebrtc` Ninja build passed with
`DEPOT_TOOLS_WIN_TOOLCHAIN=0`; no synthetic, live, or BG3 validation was run
for this behavior-preserving cleanup.

2026-06-19 native NV12 interop note: the audit's
native buffer type-boundary characterization was implemented by adding a narrow
`NativeHandleBufferKind` discriminator, marking the Inter Galactic D3D11 NV12
buffer as the custom kind, and rejecting generic native buffers before reading
Inter Galactic handle metadata. The exported
`InterGalacticD3D11Nv12BufferInteropSmoke()` now covers null, I420, generic
native, forged generic-native, valid Inter Galactic native, and invalid-create
cases. A focused Windows `libwebrtc` Ninja build passed, the native smoke wrote
`intergalactic.d3d11Nv12BufferInteropSmoke.v1`, and synthetic WebRTC OnFrame
isolation passed at 1280x720@30 with native NV12 submissions, zero native NV12
failures, and zero CPU fallback frames. This did not change LiveKit,
sender/receiver app runtime, server, bitrate/profile/codec/fallback policy,
RNNoise, BG3 automation, game-capture cadence, or Media Foundation recovery
policy.

2026-06-19 native sender-handoff evidence note: fresh local native
capture-to-Media Foundation isolation and WebRTC OnFrame isolation still pass,
but a compare report against the sender-only BG3 run
`source-live-call-freshness-20260619-104708` classifies the live path as
`failed_live_sender_handoff`. Local source/MF/WebRTC prerequisites were
healthy, while live capture/encode/send averaged `6.984 / 15.000 / 8.750` FPS
with bottleneck `native_nv12_ready_limited`, live `OnFrame` around
`24.535414 ms`, native NV12 readiness around `35.153987 ms`, native NV12
failures `0`, and CPU fallback `0`. `intergalactic_game_capture_config.*` was split
out of the D3D11 game-capture capturer
so source-mode, delivery, and native NV12 readiness config are separated
before the deeper sender-handoff branch. Focused native `libwebrtc` build
passed, native capture-to-MF isolation passed at handoff output FPS `32.079`,
and WebRTC OnFrame isolation passed at gate delivery FPS `29.936` with
native NV12 submitted/failures `222 / 0` and CPU fallback `0`.

2026-06-19 adaptive native NV12 backpressure note: a
live `OnFrame` backpressure guard was implemented for the native NV12 handoff. By default,
`INTERGALACTIC_GAME_CAPTURE_NV12_ONFRAME_BACKPRESSURE_SUSPEND=1` suspends the
native NV12 path after three consecutive native NV12 `OnFrame` calls slower
than `20 ms`, then falls through to the existing GPU-scaled readback/I420 path.
The guard emits `native_nv12_encoder_handoff_suspended
reason=live_onframe_backpressure` and exposes the threshold, frame limit,
current streak, total backpressure frames, max `OnFrame` time, and suspended
state in native stats, stream-test JSON, Markdown summaries, and the
sender-handoff diagnostics JSON. Focused `libwebrtc` Ninja build, Dart format,
focused stream-test Flutter test, targeted Flutter analyze, local native
capture-to-MF isolation, WebRTC OnFrame isolation, and pinned
sender-handoff-prerequisite analysis passed. A forced synthetic guard smoke
with threshold `0 ms` and frame limit `1` proved the suspension path:
`nativeNv12SuspendedAfterOnFrameBackpressure=true`, one native NV12 submission,
`readbackQueued=139`, and `gateDeliveryFps=30.009`.

2026-06-19 BG3 receiver-proof validation note: a rebuilt Smooth 720p30 BG3
external-render run
`runtime/stream-lab/local-results/source-live-call-freshness-20260619-150735`
passed the authoritative receiver lane with
legacy `freshnessEvidenceSource=receiver_remote_render`, now interpreted as
`remote_renderer_callback`, with renderer attached/visible,
decode/callback `frame_hash_tap`, and receiver callback/decode unique FPS
`28.177635702036078`. Sender cadence recovered to capture/encode/send
`30.714 / 27.000 / 26.467` FPS with D3D11 helper source mode, native NV12
failures `0`, CPU fallback `0`, and the rebuilt
`libwebrtc.dll` hash
`B4A094E554016030948C60FEC8C8CA276AB1AAEABE592B88C135FB542E7840D3`. The
legacy self-view/tight crop still failed at `11.413` unique FPS, but remains
diagnostic-only. The live BG3 report did not include the expected
`nativeNv12OnFrameBackpressure*` fields, so the next narrow
follow-up is telemetry/reporting cleanup rather than receiver/server tuning.

2026-06-19 BG3 strict receiver FPS note: a single native
behavior change was kept for the latest branch: the D3D11 immediate context is flushed
immediately after a successful native NV12 ready-fence `Signal()` in
`intergalactic_game_capture_video_capturer.cc`. The final candidate
`libwebrtc.dll` hash is
`0421C714505B8E13A1967DB3B28A011936A9836187D484EC6101418B1632E52C`.
The strict external-render run
`runtime/stream-lab/local-results/source-live-call-freshness-20260619-155307`
passed `MinUniqueFps=29` with true receiver decode/render `frame_hash_tap`
freshness at `29.051088903167596` FPS and sender capture/encode/send
`31.857 / 30.571 / 29.533` FPS. The receiver was attached and visible at
`1280x720`, and BG3 focus/rotation cleanup completed. Residual risk remains:
the sender report still classified `native_nv12_ready_limited`, native NV12
BLT-to-ready peaked at about `162 ms`, queue/overload drops remained `9`, and
average bitrate was only about `720 kbps` despite high subscription and
`qualityLimitationReason=none`. Treat FPS as green but thin-margin, and treat
receiver smear as a quality follow-up candidate rather than a resolution-only
setup artifact.

2026-06-19 CBR bitrate/smear note: Media Foundation H.264 rate-control
diagnostics and a guarded `INTERGALACTIC_MF_H264_RATE_CONTROL_MODE` selector
were added, then CBR was promoted to the experimental default after BG3
external-render A/B evidence. The
unconstrained/default baseline
`source-live-call-freshness-20260619-161652` passed receiver render at
`29.848636685466921` FPS but averaged about `698 kbps` and emitted
`rate_control_mode=unconstrained_vbr`. The env-gated CBR run
`source-live-call-freshness-20260619-162024` passed at
`30.356844709560885` FPS and averaged `2.6 Mbps`. The no-env default-CBR
confirmation `source-live-call-freshness-20260619-162443` loaded
`libwebrtc.dll` digest `1D013DE6E8C0`, emitted `rate_control_mode=cbr`,
averaged `2.6 Mbps`, and passed the true receiver render gate at
`29.183055844537915` FPS. This treats the user-observed smear/graininess as
bitrate-control evidence now addressed by CBR, while the remaining FPS margin
risk stays on native NV12 readiness tails and sender queue/overload drops.

2026-06-19 true receiver debug/Release boundary note: the final live evidence
separates automated receiver proof from consumer Release behavior. The
Release-backed harness attempt
`source-live-call-freshness-20260619-194746` joined the call but timed out
because Release builds do not consume stream-test automation requests; the
external receiver therefore blocked on protected IPC. Treat that as the
expected Release boundary, not a stream failure. The rebuilt Debug run
`runtime/stream-lab/local-results/source-live-call-freshness-20260619-195714`
then passed `passed_source_live_call_receiver_render_freshness` with true
receiver decode/render `frame_hash_tap` unique FPS `25.042`, HIGH subscribed
quality, renderer attached/visible, a `1280x720` receiver window moved to
monitor 2, sender capture/encode/send `29.333 / 28.333 / 29.138` FPS, H.264
Media Foundation hardware encode active, packet loss `0.0%`, RTT max
`7.584 ms`, and loaded `libwebrtc.dll` short hash `33D3E9EAEC08`.
The receiver-window screen recording for that run stayed diagnostic-only at
`5.509` unique FPS, but the saved receiver-probe window frame was a nonblack
real `1280x720` BG3 view. Use the debug/developer harness as automated true
receiver proof. Use borrowed-PC or separate-device Release tests only as
product-level human smoke unless a future explicitly developer-enabled Release
test gate is approved.

## Current Streaming Boundary

The current 2026-06-19 boundary is: CBR is the experimental Windows Media
Foundation H.264 rate-control default for the game-hook path because it raised
BG3 receiver-delivered bitrate from about `0.7 Mbps` to `2.6 Mbps` without
failing the true receiver freshness gate. Do not attribute this to the server or
receiver auth unless future evidence shows healthy sender FPS with receiver,
LiveKit, SFU, or network regression. The next runtime branch should stay on
native NV12 readiness tails, sender queue/overload drops, and receiver FPS
margin under the same monitor-isolated external-render BG3 shape. The
receiver probe remains a debug/developer lab harness, not consumer Release
behavior.

Historical Live Testing Override evidence on 2026-06-16 landed the narrow
WebRTC source-adapter branch. `src/internal/video_capturer.cc` lets
already-sized Inter Galactic D3D11 native NV12 helper frames bypass only the
capturer-level framerate adapter drop when an active sink exists and no
resolution adaptation is required. This keeps normal I420/window capture and
dummy NV12 live-sender controls on the existing WebRTC adapter path.

Two BG3 Smooth 1280x720@30 live runs crossed the average product gate with
visible output, clean network basics, native NV12 failures `0`, CPU-I420
fallback `0`, sub-millisecond live `OnFrame`, effectively zero MF fence wait,
and raw sender diagnostics showing `source_adapter_drops=0`. Treat
source-adapter drop pressure as addressed for this branch.

The immediate classifier/report nuance is now implemented locally: when
D3D11 game-hook capture/encode/send averages meet the requested FPS and native
NV12, fence, source-adapter, network, live `OnFrame`, and MF fence-wait
counters are clean, isolated NV12 BLT-to-ready/source-to-submit max tails are
reported as `native_tail_spike_review` evidence under `healthy` instead of
high-confidence `native_nv12_ready_limited`. Keep the remaining review branch
focused on parser validation, native-diff acceptance review, and one narrow
BG3 Smooth 720p confirmation rather than more SDR, bitrate, receiver,
LiveKit, queue-depth, fallback, or custom encoded-frame tuning.

Live Testing Override is now closed for this branch by user direction. Treat
the two source-adapter BG3 runs as the current validation baseline, not an
active request for more live-loop iteration. Additional BG3 Smooth 720p
validation should wait until the classifier/report change passes focused
parser validation and the native diff/residual tail-spike risk is accepted in review.

2026-06-17 follow-up: a rebuilt confirmation looked like one captured frame
followed by black. Diffing against
`runtime/archives/streaming-code-rollback-20260616-081241.zip` showed the
archived native capturer/encoder/wrapper files matched the sensitive current
paths, while the upstream WebRTC broadcaster branch had started bypassing
inactive native sinks whenever an active sender sink existed. The current fix
keeps active sender delivery first, then gives inactive preview/test sinks a
bounded shared-I420 refresh cadence. The next BG3 Smooth 720p confirmation must
therefore check both sender health and visible preview/receiver continuity,
with `inactive_native_refresh` counters present in sender diagnostics.

2026-06-17 visual-cadence follow-up: phone recordings of direct gameplay and
the received stream showed that stream-test FPS counters can be misleading.
The gameplay recording changed visually at roughly display cadence, while the
stream tile looked closer to a low-single-digit unique-frame slideshow with
long stale runs. Treat submitted/encoded/sent FPS as insufficient for final
smoothness claims unless the report also includes visual freshness cadence
evidence. The report contract now parses future `game_capture_visual_freshness`
markers, adds a `visual freshness cadence` coverage row, and shows a dedicated
Markdown section. Keep output copies bounded: sender-side proof frames are fine,
but continuous audit recordings should be receiver/tool-side unless a separate
server-side/LiveKit recording branch is explicitly opened.

The receiver/tool-side proof source now exists as
`tools/stream-lab/measure_visual_freshness.ps1`. It analyzes a video file or a
local MF proof video from `local-capture-benchmark.json`, emits
`intergalactic.visualFreshnessMeasurement.v1` JSON/Markdown, and writes a
parser-compatible `game_capture_output_freshness` marker. Synthetic validation
ran first: `local-capture-20260617-121038` passed native capture-to-MF at
720p30, and `visual-freshness-20260617-121051` measured the proof video at
`143 / 145` unique sampled frames, `29.586` unique FPS, longest stale run
`33.333 ms`, and `2` low-change frames. Do not request BG3 until this
synthetic marker path is preserved for the current build/report workflow.

2026-06-17 live-call synthetic follow-up:
`codex-synthetic-live-freshness-20260617-122246` streamed the synthetic D3D11
target in a live Smooth 1280x720 call before requesting BG3. The target
presented at `56.935` FPS, stream-test counters reported capture/encode/send
around `31.1 / 22.7 / 23.5` FPS, native NV12/fence failures were clean,
source `OnFrame`, MF input, and encoded callback timing were tiny, and the
visible stream tile still measured only `75 / 720` unique sampled frames,
`3.125` unique FPS, and a `333.333 ms` longest stale run. Treat this as a
synthetic live sender/output-freshness failure, not a BG3/R10 conversion
failure. Do not request another BG3 run until synthetic live output freshness
clears.

2026-06-17 post-hardening synthetic rerun:
`synthetic-live-call-freshness-20260617-153548` verified the hotkey-selected
Inter Galactic call window (`Test Voice | Admin | Inter Galactic`), captured a
nonblank preflight frame (`31.71 / 194 / 26.263` mean/contrast/stdDev), and
completed stream-test automation. The gate still failed visual freshness:
`220 / 899` unique sampled frames, `7.341` unique FPS, and a `1666.667 ms`
longest stale run. Stream-test counters averaged `21.3 / 21.2 / 25.0`
capture/encode/send FPS with source mode `helper-d3d11`, bottleneck
`delivery_queue_limited`, and inactive native refresh/bypass `1707 / 0`.
Treat recorder foreground/preflight safety as validated for this rerun, but keep
BG3 gated pending further investigation of sender/output delivery cadence.

2026-06-17 true receiver BG3 follow-up: self-view/local-preview evidence is no
longer enough to classify remote smoothness. An isolated
receiver client/profile was launched, the user joined the call with a second account, and
receiver-side recordings showed that hidden remote stream tiles are invalid
freshness proof because the stream renderer is not instantiated until the tile
is revealed. Valid revealed-tile BG3 receiver runs still failed the 25 unique
FPS gate: `source-live-call-freshness-20260617-201438` measured `17.067`
unique FPS with a `200 ms` longest stale run, and the tighter crop
`source-live-call-freshness-20260617-201817` measured `17.133` unique FPS with
a `166.667 ms` longest stale run. Sender counters during the tighter run were
about `29.091 / 24.909 / 25.075` capture/encode/send FPS. The user confirmed
BG3/source stayed smooth while the receiver-visible stream stuttered. A
highQuality/60 branch froze the receiver stream and then dropped to green
placeholders, so it is not a pass candidate. The next branch should investigate
receiver-visible WebRTC decode/render cadence or delivery-to-receiver frame
availability from revealed-tile evidence, not hidden tiles or self-view alone.

Detailed per-run evidence for direct-BLT, fence wake, source-QPC, dummy NV12
live sender, local native-MF, WebRTC OnFrame, and failed live sender-handoff
steps is archived in
`stream-optimization-report/2026-06-15-to-16-sender-handoff.md`.

Do not use this report for RNNoise/noise-suppression tuning; RNNoise behavior
and related diagnostics are covered elsewhere. This report is scoped to
gameplay streaming, D3D11 capture, WebRTC/LiveKit video pipeline work, stream
diagnostics, stream presets, and native stream helpers.

## Evidence Archives

| Evidence window | File | Primary use |
| --- | --- | --- |
| 2026-06-15 to 2026-06-16 | `stream-optimization-report/2026-06-15-to-16-sender-handoff.md` | Sender handoff, dummy NV12 live sender, source-adapter, direct-BLT, fence-wake, and native-tail evidence. |
| 2026-06-14 | `stream-optimization-report/2026-06-14-native-nv12-freshness.md` | Latest native NV12 freshness, readiness-policy, bounded-pending, and latest-frame queue evidence. |
| 2026-06-13 | `stream-optimization-report/2026-06-13-game-capture-contract.md` | Game-capture contract, host-load, and backpressure diagnostics. |
| 2026-06-08 to 2026-06-11 | `stream-optimization-report/2026-06-08-to-11-native-nv12-handoff.md` | Native NV12 acceptance, first-frame, and source/readback proof evidence. |
| 2026-06-07 | `stream-optimization-report/2026-06-07-phase-4-source-delivery.md` | Phase 4 source delivery, wake-on-ready, stale-readback, and D3D11 cap evidence. |
| 2026-06-04 to 2026-06-05 | `stream-optimization-report/2026-06-04-to-05-source-handoff.md` | Local source handoff, helper lifecycle, GPU-scale, and publication-handoff evidence. |
| 2026-06-02 to 2026-06-03 | `stream-optimization-report/2026-06-02-to-03-window-gdi-wgc.md` | Window GDI, WGC, dirty-region, and capture-attribution evidence. |
| 2026-05-20 to 2026-05-31 | `stream-optimization-report/2026-05-20-to-31-capture-validation.md` | Capture-call split readiness, windowed BG3, and pacer validation evidence. |
| 2026-05-02 to 2026-05-06 | `stream-optimization-report/2026-05-02-to-06-hardware-encoder.md` | Early hardware encoder, libwebrtc, RNNoise, limiter, and FPS-pipeline evidence. |
| 2026-05-11 to 2026-05-20 | `stream-optimization-report/2026-05-11-to-20-stream-lab-cadence.md` | Stream-lab, backend switch, cadence, native capture override, and geometry evidence. |

Archive folder index: `stream-optimization-report/README.md`.

## Maintenance Notes

- Keep this top-level file short. Add or move detailed evidence into dated
  archive files.
- Preserve diagnostic evidence verbatim when splitting or moving historical sections.
- Keep private workspace paths, hostnames, secrets, and internal operational
  details out of app-repo architecture docs.
- Do not edit license/legal evidence files as part of streaming documentation cleanup.
