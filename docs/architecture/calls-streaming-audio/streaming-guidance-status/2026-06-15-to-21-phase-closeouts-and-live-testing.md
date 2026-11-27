# Phase 2-4 Closeouts And Live Testing Override Cycle

Date range: 2026-06-15 to 2026-06-21

Dated closeout history extracted from `../streaming-guidance-status.md` (the current-status document keeps only the newest decision baseline). Covers the June 21 Phase 4/3/2 receiver-presentation and sender-mailbox closeouts, the June 19 CBR bitrate/smear and true-receiver-harness closeouts, the June 19 stream-test runner refactor, and the five June 15 Live Testing Override / source-adapter closeouts.

---

June 21 Phase 4 receiver-presentation proof local closeout: this closeout
implemented the receiver presentation lineage branch from
the historical stream-optimization plan. The receiver probe event
schema now includes explicit stage metadata for `remote_renderer_callback`,
`remote_texture_ready`, and `remote_ui_paint`, with native frame sequence,
stage timing, texture id, and callback-to-stage timing copied forward from the
renderer callback. The in-process receiver debug surface and the external
receiver runtime both emit texture-ready and UI-paint stage events.

Current decision: Phase 4 is synthetic-green, not BG3/product-green. The
external receiver runtime now displays the same diagnostic `RTCVideoRenderer`
that produces native frame hashes, replacing the prior neighboring
`VideoTrackRenderer` view in the probe window. Synthetic run
`synthetic-live-call-freshness-20260621-144047` reported
`remote_renderer_callback=27`, `remote_texture_ready=29`,
`remote_ui_paint=29`, `remote_screen_present=0`, latest target stage
`remote_ui_paint`, receiver render unique FPS about `30.35`, decoded FPS p50
about `30.01`, and presentation p95 p50 `48ms`. Clean BG3 run
`source-live-call-freshness-20260621-145710` then failed receiver quality
counters: receiver was high/single H264 at 1280x720 received, decoded, and
rendered, inbound bitrate was about `2.91Mbps`, QP was about `20.3`,
PLI/FIR/NACK were `0/0/0`, and receiver decoded/render unique FPS was about
`29.68`, but receiver presentation p95 remained red at p50 `54ms`, average
`63.8ms`, and max gap `117ms`. Treat `remote_ui_paint` as diagnostic surface
proof, not screen-present proof: `remote_screen_present` remains missing until
a low-overhead screen/capture tap exists. The next branch should fix/report
the external receiver summary merge gap and continue receiver presentation
cadence plus sender/VSE tail correlation. Do not return to sender capture
tuning, bitrate/profile policy, hook-target, receiver-widget, LiveKit/server,
or RNNoise changes from this branch.

June 21 Phase 3 GPU-timestamp closeout: this closeout implemented the
GPU timestamp diagnostic branch from
the historical stream-optimization plan. The clean BG3 run
`source-live-call-freshness-20260621-135628` kept sender capture/encode/send
near target at about `28.4/28.7/28.9` FPS and receiver decode/render unique
FPS at `29.60`, but receiver presentation still failed with p95 p50 `60ms`
and max gap `107ms`. Receiver quality/layer stayed high/single `1280x720`.

Current decision: Phase 3 is complete as a diagnostic branch. The final native
marker reported 146 BLT timestamp samples with `0/0/0` fail/not-ready/disjoint
counts. BLT GPU execution averaged `0.29ms` and peaked at `14.51ms`;
submit-to-fence averaged `1.87ms` and peaked at `41.15ms`; estimated GPU queue
delay averaged `1.58ms` and peaked at `26.72ms`. Do not build a shader
converter next. Continue with GPU scheduling/contention/admission and
sender-to-receiver presentation correlation, then Phase 4 receiver
presentation proof. Do not pivot to bitrate, hook-target, receiver-widget,
server, LiveKit, or RNNoise changes from this evidence.

June 21 Phase 2 sender-mailbox local closeout: this closeout implemented the
sender latest-frame mailbox from
the historical stream-optimization plan. The mailbox is default-on
only for Inter Galactic custom native D3D11 NV12 gameplay frames and dummy NV12
live-sender frames. It keeps one active frame and one newest pending frame,
replaces pending frames while processing is active, and drops stale pending
frames after the configured deadline. Stream-test diagnostics now expose
mailbox replacements, stale drops, pending/processing ages, admission deadline
misses, enqueue-to-processing, processing-to-VSE, and VSE-call timing in the
WebRTC raw sender boundary block.

Current decision: Phase 2 is locally implemented and packaged, but not yet BG3
green. Dart format, focused `stream_test_runner_test.dart`, targeted Flutter
analyze, native libwebrtc rebuild, and stream Debug packaging passed. Because
Live Testing Override is inactive, do not treat this branch as a gameplay/live
result yet. The next step is a BG3 receiver-quality run under Live Testing
Override, with camera rotation active, comparing mailbox counters and
`processing_start_to_vse` / `vse_call` tails against receiver presentation p95
spikes. Do not return to hook-target, pending-depth, bitrate-only,
receiver-widget, ZeroHz, or server tuning until that Phase 2 evidence exists.

June 19 CBR bitrate/smear closeout: user-observed BG3 receiver smear/graininess
now has concrete bitrate-control evidence. This closeout added Media Foundation
H.264 `target_bitrate_bps` and `rate_control_mode` diagnostics plus
`INTERGALACTIC_MF_H264_RATE_CONTROL_MODE` for A/B testing, then made CBR the
experimental default for the Windows H.264 path after true receiver evidence.

The baseline/unconstrained rerun
`source-live-call-freshness-20260619-161652` passed the external receiver
render gate at `29.848636685466921` unique FPS but averaged only about
`698 kbps`. The env-gated CBR A/B
`source-live-call-freshness-20260619-162024` passed at
`30.356844709560885` unique FPS and averaged `2.6 Mbps`. The no-env default
confirmation `source-live-call-freshness-20260619-162443` loaded the updated
Debug runner DLL digest `1D013DE6E8C0`, emitted `rate_control_mode=cbr`,
averaged `2.6 Mbps`, and passed at `29.183055844537915` unique FPS with high,
single-layer H.264 receiver subscription and an attached/visible `1280x720`
renderer.

Current decision: keep CBR as the experimental default candidate and use the
env override only for fallback A/Bs. Receiver/server routing is not indicated:
network evidence stayed clean and receiver decode/render was authoritative.
The remaining branch is native NV12 readiness tail and sender queue/drop
reduction under BG3 motion, because the latest default CBR run still classified
`native_nv12_ready_limited`, with native NV12 readiness averaging `9.8 ms` and
peaking near `90.2 ms` while host CPU averaged `93.6%`.

June 19 true receiver harness boundary: automated true receiver proof is a
debug/developer harness concern, not consumer Release behavior. The
Release-backed attempt `source-live-call-freshness-20260619-194746` joined the
call but did not consume the stream-test automation request because Release
builds keep the automation poller gated to developer/debug modes; the external
receiver then stopped at protected IPC. The rebuilt Debug run
`source-live-call-freshness-20260619-195714` passed the external render
freshness gate with receiver decode/render `frame_hash_tap` unique FPS
`25.042`, HIGH subscribed quality, renderer attached/visible, a `1280x720`
receiver window on monitor 2, sender capture/encode/send
`29.333 / 28.333 / 29.138` FPS, Media Foundation H.264 hardware encode, no
packet loss, and low RTT.

Current decision: the debug/developer true receiver probe can replace a
borrowed Windows PC for automated receiver-probe proof. A separate PC or mobile
viewer is still useful for product-level Release UX smoke, but it is not the
primary engineering freshness gate. Do not put the probe into consumer Release
by default; if Release automation is required later, add an explicit
developer-enabled test gate. The next technical work stays on native NV12
readiness tails and sender queue/drop reduction unless fresh evidence shows a
healthy sender with receiver/SFU/network regression.

June 19 refactor closeout: this closeout completed a behavior-preserving
stream-test runner split before resuming sender-handoff or BG3 behavior work.
`stream_test_runner.dart` remains the public import surface and orchestration
home. Receiver probe modeling, result/reporting, bottleneck scoring, native
diagnostics parsing/redaction, frame/temporal summaries, and coverage now live
in same-library `stream_test_runner_*.dart` parts.

This is not new streaming validation evidence and does not change the current
runtime decision boundary. No LiveKit, sender/receiver runtime, D3D11/native
capture, bitrate, codec, fallback, server, or RNNoise behavior changed. Focused
validation passed with Dart format, `stream_test_runner_test.dart`, targeted
analyze for the runner and parts, and scoped diff checks. No synthetic/live/BG3
validation was run for this refactor.

June 15 22:45 closeout: Live Testing Override has ended. The latest
source-adapter branch is the current validated baseline for DX11 gameplay
streaming: local BG3 sender isolation
`native-sender-handoff-isolation-20260615-222842` passed with native MF
handoff about `30.2 FPS`, WebRTC source gate about `30.7 FPS`, native NV12
failures `0`, CPU fallback `0`, and libwebrtc digest `DAE05805B55E`.

Two BG3 Smooth 1280x720@30 live runs crossed the average 720p30 gate:
`stream-test-2026-06-16T02-32-02-321672Z` reached about
`31.6 / 29.9 / 30.3` capture/encode/send FPS, and
`stream-test-2026-06-16T02-33-32-152165Z` confirmed about
`31.0 / 29.4 / 30.2`. Both kept visible/color-correct 1280x720 output, clean
network, native NV12 failures `0`, CPU-I420 fallback `0`, sub-millisecond
live `OnFrame`, effectively zero MF fence wait, and
`source_adapter_drops=0`.

This closes the immediate WebRTC raw sender/source-adapter limiter. Do not
restart SDR/HDR, bitrate, receiver, LiveKit/SFU, fallback, queue-depth, hard
source-QPC cap, timestamp pacing, or custom encoded-frame work from this
evidence. The remaining branch is small and reviewable: fix/report classifier
nuance so average-pass runs are not over-labeled as
`native_nv12_ready_limited`, attribute isolated NV12 BLT/source-to-submit tail
spikes, and keep the native streaming diff clean and easy to review.

June 15 17:44 update: dummy/pre-generated NV12 live sender isolation passed.
`dummy-nv12-live-sender-20260615-174359` fed generated 1280x720 native NV12
through the normal Windows WebRTC/Media Foundation/LiveKit sender path and
passed at about `30.3 / 30.0 / 30.0` capture/encode/send FPS. The run
confirmed source mode `dummy-nv12-live-sender`, native NV12
submitted/failures/CPU fallback `1057 / 0 / 0`, `deliveryOnFrameCall` about
`3.07 ms` average, and Media Foundation `ProcessInput` about `0.38 ms`
average. This proves the existing raw sender path can sustain Smooth 720p30
from already-ready native NV12.

This supersedes the immediate custom native encoded-frame handoff hypothesis.
Do not implement that path yet. The next implementation branch is BG3 native
frame ownership, GPU fence/readiness, R10-to-NV12 readiness, source frame age,
and native sample lifetime under live sender coupling. Another BG3 Smooth
720p live call is useful after that branch lands, not as the immediate next
decision step.

June 15 15:47 update: live validation moved past the local BG3-motion gate
again, but still did not reach Smooth 720p30. Full stream debug build
`runtime/stream-lab/debug-builds/20260615-194341/` completed after tightening
numeric diagnostic env parsing for delivery depth, NV12 ready-drain depth,
NV12 pending poll, and NV12 max-pending values. A short invalid-env source
smoke `webrtc-onframe-isolation-20260615-154627` confirmed bad numeric
diagnostic values fall back to the normal defaults:
`deliveryQueueDepth=1`, `nativeNv12ReadyDrainDepth=1`,
`nativeNv12PendingPollMs=8`, and `nativeNv12MaxPendingSlots=2`.

Before that cleanup, local aggregate validation with BG3 camera motion passed
at `native-sender-handoff-isolation-20260615-153151`: native capture-to-MF
reported `30.309` handoff FPS / `28.2` encoder-estimated FPS, and the local
WebRTC source-OnFrame gate reported `29.535` FPS with `OnFrame` call avg/max
about `0.003 / 0.016 ms`. The rebuilt live BG3 Smooth call then failed the
target at `stream-test-2026-06-15T19-37-12-620527Z`: capture/encode/send
landed around `25.0 / 24.8 / 24.7 FPS`, with visible/color-correct 1280x720,
native NV12 failures `0`, CPU fallback `0`, not-ready polls `0`, ready drops
`0`, clean packet loss, and classification `encoder_handoff_limited`.

The guarded `2/2` delivery queue / ready-drain diagnostic run,
`stream-test-2026-06-15T19-39-21-107011Z`, also failed the target at about
`26.5 / 25.5 / 24.7 FPS`. It lowered some intermediate averages
(`deliveryOnFrameCall` about `28 ms` versus `31 ms`, source-to-submit about
`17 ms` versus `22 ms`) but did not improve send FPS and worsened the
`OnFrame` max tail to about `125 ms`. Keep `2/2` diagnostic-only. This is a
sender/input decision point that required dummy NV12 live-sender isolation, not
evidence to promote queue smoothing or require SDR/game-setting changes. The
later dummy isolation passed and shifted the branch to BG3 native frame
readiness/ownership.

June 15 14:26 update: fresh local validation now blocks another live BG3 call
until the local motion path is stable again. The stream debug full build
`runtime/stream-lab/debug-builds/20260615-181737/` and NativeQuick rebuild
`runtime/stream-lab/debug-builds/20260615-182241/` completed, and focused
stream-test parser coverage passed. The no-rotation aggregate gate
`native-sender-handoff-isolation-20260615-142113` failed because native
capture-to-MF fell to `27.515` handoff FPS / `25.4` encoder-estimated FPS,
even though WebRTC source-OnFrame still passed at `30.108` gate FPS. With BG3
camera rotation active, default newest-only `1/1`
`native-sender-handoff-isolation-20260615-142456` failed at `15.222`
native-MF handoff FPS / `14.25` encoder-estimated FPS and `27.039` WebRTC
source gate FPS, with native NV12 failures `0` and CPU fallback `0`. The
guarded `2/2` diagnostic comparison
`webrtc-onframe-isolation-20260615-142604` was worse at `24.482` gate FPS and
Blt-to-ready avg/max about `44 / 602 ms`.

No new full live call was run after those local failures. Keep `2/2`
diagnostic-only, keep the default at newest-only `1/1`, and fix local
BG3-motion GPU conversion/fence wait plus Media Foundation native-input
behavior before returning to live validation.
Invalid `INTERGALACTIC_GAME_CAPTURE_REPEAT_POLICY` values now fall back to the
same `skip-on-miss` default as the absent/default case; short source-smoke
validation `webrtc-onframe-isolation-20260615-142918` confirmed an invalid
repeat-policy env reported `deliveryRepeatPolicy=skip-on-miss`,
`deliveryQueueDepth=1`, and `nativeNv12ReadyDrainDepth=1`.

June 15 update: local source/encoder isolation changed the active diagnosis.
The latest live stream test,
`stream-test-2026-06-15T15-50-03-152124Z`, still fails BG3 Smooth 720p30 at
about `11-12 FPS` with live `deliveryOnFrameCallMs` around `48 ms` average /
`276 ms` max, but it also confirms the rebuilt D3D11 path is active,
color/visibility remains good, native NV12 fences are available/signaled,
native NV12 failures are `0`, CPU-I420 fallback is `0`, network is clean, and
encoded output is `1280x720`.

This supersedes the immediate June 14 native-readiness interpretation for the
next implementation branch. Local BG3 D3D11 capture -> GPU NV12 -> Media
Foundation proof is green, and the local WebRTC source -> `VideoCapturer`
`OnFrame` gate is also green. The stream-test classifier now treats the live
shape as `encoder_handoff_limited` with reason
`live_sender_handoff_backpressure` when the native fence/ready path is healthy
but live `OnFrame`/MF handoff and sender FPS remain over budget. The aggregate
wrapper `tools/stream-lab/run_native_sender_handoff_isolation.ps1` linked the
two local pass reports with the latest live JSON and produced
`failed_live_sender_handoff`, so the next decision was dummy NV12 live-sender
isolation, not another capture-queue-constant loop. That dummy gate now passes;
the current branch is BG3 native frame readiness/ownership under live sender
coupling.

