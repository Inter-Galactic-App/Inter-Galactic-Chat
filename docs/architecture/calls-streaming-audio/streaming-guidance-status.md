# Streaming Guidance Status

Status: Current implementation-decision summary for DX11 gameplay streaming
Owner: EXPERIMENTAL for runtime decisions; DOCUMENTATION for structure
Last reviewed: 2026-06-16 by DOCUMENTATION

This is the volatile current-state companion for the streaming guidance plan.
Use `README.md` for folder routing, `streaming-pipeline.md` for stable
architecture, and `stream-optimization-report.md` for dated evidence.

Source plan: `docs/plans/StreamingGuidance.md`

This document maps the current Inter Galactic streaming state against the
guidance plan. It records the active EXPERIMENTAL implementation boundary for
gameplay streaming without changing LiveKit publish options, TURN behavior,
fallback policy, bitrate, codec, simulcast, or profile resolution defaults.

## Current Conclusion

The first entry below is the current decision baseline. Later entries are
chronological history and may describe earlier failing states.

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
spikes, and keep REVIEW commit hygiene on the native streaming diff.

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

June 14 update: the rebuilt BG3 Debug stream test still proves the true
native-NV12 GPU handoff path under gameplay, but Smooth 720p30 remains
native-NV12 readiness limited. The active path is still:

```text
D3D11 texture -> GPU scale -> GPU NV12 -> native-NV12 Media Foundation/WebRTC handoff
```

This is not yet a stable 720p30 result. The current boundary is not bitrate,
LiveKit/SFU, TURN, receiver policy, or CPU-I420 fallback. The latest evidence
points at native NV12 readiness churn, delivery pacer resyncs, and
VideoProcessorBlt-to-ready spikes while the host is under load.

Latest validation / build state:

- Native explicit-fence handoff build
  `runtime/stream-lab/debug-builds/20260614-234001/stream-debug-build-20260614-234001.md`
  completed after the five-cycle loop. Native/debug-runner `libwebrtc.dll`
  SHA-256 is
  `8663F97A4777BD58C4E75B1E51F760827D838C24ED198110A6C0D5A21ADCA71B`. The
  capturer now defaults native NV12 readiness to an explicit D3D11 fence,
  queues the native buffer with that fence/value, and the Media Foundation H.264
  native sample path waits on the fence before DXGI surface sample submission.
  No post-change live BG3/call stream test has been run yet.

- Rebuilt actual-gameplay report `stream-test-2026-06-14T19-13-57-621504Z`
  completed without an app crash and sustained `input_path=native_nv12`,
  `native_input=yes`, `native_sample_failed=no`, `nativeNv12Submitted=1648`,
  `nativeNv12Failures=0`, and essentially readback-proof-only fallback
  counters.
- The same run still missed Smooth 720p30 with about `23.6` capture FPS,
  `15.0` encode FPS, and `16.2` send FPS. Network counters were clean
  (`0` loss, `0` NACK, RTT max about `4 ms`), so this remains upstream of
  LiveKit and the receiver.
- Native evidence showed `deliveryPacerResyncs=180`, `repeated=244`,
  `deliveryOverwritten=245`, source-to-submit max about `201 ms`,
  native-NV12 not-ready polls around `3491`, and native-NV12 ready drops around
  `115`. Native Media Foundation encoder timing also had a slow tail, with
  roughly `34 ms` average and `118 ms` max over sampled markers.
- Full Debug rebuild manifest
  `runtime/stream-lab/debug-builds/20260614-200136/stream-debug-build-20260614-200136.md`
  completed with native/runner `libwebrtc.dll` SHA-256
  `0F9044EF2F57080A80C1BFEDC25D2050DBF2D0D42D416D7F1E66C542C61094F4`, patched
  `libwebrtc.zip` SHA-256
  `337C1B0B00E923F7BB2693F6CC0E6ED111A615C663A65FB432BB4CD955AD7493`, and
  helper/hook artifacts present in the Debug runner.
- Post-rebuild BG3 harness report
  `stream-test-2026-06-14T20-07-56-765633Z` completed with the D3D11 game-hook
  backend, `game-d3d11-hook` capturer, 1280x720 encoded output, about `22.1`
  capture FPS / `21.8` encode FPS / `22.3` send FPS, `0%` loss, max RTT
  `5.31 ms`, and MediaFoundationH264 hardware encode active.
- The skip-on-miss debug policy changed the failure signature: repeated frames
  dropped to `0` with `deliveryRepeatPolicy=skip-on-miss`,
  `deliverySkipNoQueued=180`, and `deliveryRepeatNoQueued=0`. The report still
  classified `native_nv12_ready_limited` with high confidence because
  `nativeNv12ReadyDropped=90` fresh frames, `nativeNv12NotReadyPolls=4381`,
  `deliveryPacerResyncs=133`, source-to-submit max `281.1 ms`, native-NV12
  convert max `202.1 ms`, and Blt-to-ready max `170.9 ms`.
- Follow-up Debug rebuild
  `runtime/stream-lab/debug-builds/20260614-204556/stream-debug-build-20260614-204556.md`
  completed after the timestamp/delivery handoff diagnostics pass. Native and
  Debug runner `libwebrtc.dll` SHA-256 is
  `CE13CBB79AB250A5A81962265E8FFE10FEE318E4F13DB503083D6F6A36E95E9A`, patched
  `libwebrtc.zip` SHA-256 is
  `5C06666B991F95D790528F4A9AB6798FCA41CD93C121D5904C1BB9ECF38F847C`, and the
  Debug runner still contains matching game-capture helper/hook artifacts.
- Post-call-helper BG3 harness report
  `stream-test-2026-06-14T21-18-46-589271Z` completed with the D3D11 game-hook
  backend, native NV12 active, `cpuFallback=0`, `repeated=0`, source-QPC
  timestamps active with zero fallback/regressions, clean network counters, and
  `22.3/21.6/21.5` capture/encode/send FPS. The report still classified
  `native_nv12_ready_limited`: `nativeNv12ReadyDropped=91` fresh,
  `nativeNv12NotReadyPolls=4645`, `deliveryPacerResyncs=98`,
  `deliveryQueueWait` avg/max `16/97 ms`, `sourceToSubmit` avg/max
  `54/203 ms`, and Blt-to-ready avg/max `25.1/118.0 ms`.
- Live override cycle 1 added source-driven fresh-immediate delivery wake for
  skip-on-miss mode and `deliveryFreshImmediate` reporting. Harness report
  `stream-test-2026-06-14T21-51-07-985241Z` remained below target at
  `24.8/23.1/22.6` capture/encode/send FPS, but improved the delivery boundary:
  `deliveryFreshImmediate=1357`, `deliveryQueueWait` avg/max `5.5/52.5 ms`,
  `deliveryPacerResyncs=7`, and `nativeNv12ReadyDropped=29` fresh. Remaining
  pressure stayed at native NV12 readiness and WebRTC/encoder handoff:
  Blt-to-ready avg/max `24.7/147.0 ms`, `deliveryOnFrameCall` avg/max
  `32.7/124.8 ms`, and `sourceToSubmit` avg/max `49.6/233.4 ms`.
- Live override cycle 2 tested an explicit D3D11 `Flush` immediately after the
  native NV12 VideoProcessorBlt ready-query `End`. Harness report
  `stream-test-2026-06-14T21-57-45-012635Z` still missed target at
  `23.9/22.7/22.7` capture/encode/send FPS and the flush did not improve the
  readiness boundary: Blt-to-ready avg/max was `24.9/190.8 ms`,
  `nativeNv12ReadyDropped=57`, `nativeNv12NotReadyPolls=4929`, and
  `sourceToSubmit` max `285.1 ms`. EXPERIMENTAL backed out the flush test patch
  after this run.
- Restored keeper-state Debug package
  `runtime/stream-lab/debug-builds/20260614-220116/stream-debug-build-20260614-220116.md`
  completed after backing out the rejected flush branch. Native and Debug
  runner `libwebrtc.dll` SHA-256 is
  `E9FF842682ABC2FBFADE5A3B0E3A4EF37DDB40E5B0CA54436830D88979140CE0`, and
  patched `libwebrtc.zip` SHA-256 is
  `10BBD7DDF94B4AFE022A35ABB94BD820562F62025FB040509E6CEF8DE831F06F`.

Implementation status:

- Native `game_capture_webrtc_source` now uses a one-frame newest-only
  delivery queue, resyncs the pacer from the current tick after missed
  deadlines, and supports an explicit debug repeat policy through
  `INTERGALACTIC_GAME_CAPTURE_REPEAT_POLICY=skip-on-miss` while keeping
  `repeat-last-frame` as the default.
- The delivery loop now wakes immediately when a fresh frame arrives after a
  skipped tick, and native timestamps prefer source QPC cadence for fresh
  frames with paced fallback counters for repeated, missing, or regressing
  source-QPC evidence.
- In skip-on-miss debug mode, the delivery loop can now submit a fresh queued
  frame immediately when it arrives before the next scheduled tick. This keeps
  the cycle 1 delivery-queue improvement while preserving `repeat-last-frame`
  as the default behavior.
- The native path drops stale native-NV12 ready frames before queueing and
  splits native NV12 timing into BGRA scale draw, VideoProcessorBlt submit,
  Blt-to-ready, native buffer creation, and frame-ready-to-queue fields.
- Delivery submission timing is split into submit prep, the actual WebRTC
  `OnFrame` call, post-`OnFrame` cleanup, and native buffer release so the next
  report can decide whether WebRTC/encoder handoff is the limiting stage.
- The stream-test runner now parses those fields, suppresses stale WGC/GDI
  summary labels when D3D11 game-hook evidence is active, and can classify
  `native_nv12_ready_limited`, `delivery_queue_limited`, and
  `media_foundation_encoder_limited`, `timestamp_policy_mismatch`, and
  `webrtc_onframe_limited` separately from generic `frame_pacing_unstable`.
- Validation after this implementation passed Dart format, the focused
  `stream_test_runner_test.dart` suite, multiple full Debug rebuilds, and two
  live override Smooth BG3 harness cycles. Those cycles moved the delivery queue
  boundary but did not solve native NV12 readiness or OnFrame/encoder handoff.

Current interpretation:

- Native-NV12 crash/timeout/fallback safety remains closed for the current
  branch; actual BG3 gameplay holds the GPU/NV12 handoff without CPU-I420
  fallback.
- Smooth 720p30 is still experimental until one rebuilt actual-gameplay
  native-NV12 report meets the frame budget with low ready-drop, delivery
  resync, and Blt-to-ready/source-to-submit tails.
- Broad preset matrices should wait until Smooth 720p30 changes state.
- GPU encoder/WebRTC handoff continuity is proven for this branch; stable
  pacing is not.
- The next EXPERIMENTAL decision should be reviewed before another live cycle:
  compare R10G10B10A2 versus 8-bit/SDR source-format behavior, prototype a
  WebRTC native encoder `OnFrame` handoff change, or accept a guarded
  ready-frame buffering tradeoff. The explicit D3D11 `Flush` branch should not
  be restored based on the current evidence.
- This is not a non-developer production default. Explicit consent, unsupported
  target messaging, security review, and broader API support are still required
  before making game capture a normal user-facing mode.

June 8 Phase 4 update: the debug D3D11 game-hook path has a source-local
native NV12/WebRTC proof. The native WebRTC source can now submit a
GPU-scaled NV12-backed native frame instead of mapping the scaled frame back to
CPU I420 before `OnFrame`, and the Media Foundation H.264 encoder declares
native-handle support with a native-NV12 input path. Local validation produced:

- `runtime/stream-lab/local-results/local-capture-20260608-153326/` with
  `NV12 frames/failures/convert avg = 299 / 0 / 0.022 ms`, local
  `h264-mf` encoder proof `299 / 0` submitted frames/write failures, and
  `0` proof readback frames in encoder mode.
- `runtime/stream-lab/local-results/webrtc-source-smoke-20260608-153730/`
  with `submitted=292`, `gpuScaled=292`, `gpuScaleFailures=0`,
  `cpuFallback=0`, `nativeNv12Submitted=292`, `nativeNv12Failures=0`,
  `readbackQueued=0`, `readbackMapAttempts=0`, and source-to-submit avg about
  `0.315 ms`.

This local proof was superseded by the June 10 actual-gameplay reports above.
The current branch now proves live `input_path=native_nv12`,
`native_input=yes`, and `native_sample_failed=no` continuity under BG3
gameplay. It should still not be documented as 720p30 solved until source and
delivery pacing meet the Smooth budget.
After FEATURES cleared the unrelated story composer compile blocker in local
app commit `a6b78eb`, the Windows Debug rebuild passed. Debug
`InterGalactic.exe` SHA-256 is
`3E5D9CE706C0F6AC6C8B78F69F906EEE92A0DA615CF110E079B27FD4100EDFE1`; runner
`libwebrtc.dll` SHA-256 is
`22EFB36308964B1BFE1D9DAAF189E69635C1C37BE76963606CD30F34D7BFA451`; the
staged game-capture helper/hook binaries are present in the Debug runner
folder.

Historical crash-guard follow-up: the first in-app native-NV12 BG3 Smooth run crashed in
Flutter's local video texture rendering, not in the helper, hook, encoder, or
transport path. The renderer boundary now converts native frames to I420 before
handing them to Flutter texture renderers and guards failed native-frame
conversion. The crash-guard Debug build SHA-256 is
`3500EC3BB2B5CF6FFBF8DD1CC8DE4070431DEF27E5C3022AF129687DAFABD907`; runner
`libwebrtc.dll` SHA-256 is
`7EB71CAE5C416FB537FF42D659745AACD04BF678E3E19192727255889158ECD2`; patched
`libwebrtc.zip` SHA-256 is
`6AECF1BD8A63B58F5AD49B0405087DE0DA2767F3FD308D2AB7E1A6615D04C09A`. Later
tests moved the retained branch back to CPU I420 sender input as a stability
guard; that no longer describes the June 10 retained native-NV12 branch.

June 8 Phase 2 update: source/readback stage proof is implemented for the
debug D3D11 game-hook WebRTC source. Native `game_capture_webrtc_source` stats
now split `sourceToSubmitMs` into source-to-readback-ready,
readback-queue-to-map, map-to-I420, source-to-I420-ready, and source-to-queue
timings. The stream-test runner parses those fields into JSON, native summary
labels, diagnostic coverage, bottleneck evidence, and early/middle/late/tail
time-window summaries. The patched libwebrtc artifact is refreshed with SHA-256
`1A9532A02750BFC1E24FC4CD4B672DF51C1468539CB05C60E898A2803BD53FC3`.
Validation passed with native `libwebrtc` rebuild, focused stream-runner tests,
and targeted analyzer. This did not tune bitrate, LiveKit, fallback, profile
defaults, receiver policy, or normal WGC/window-GDI publishing.

Synthetic validation has now cleared the Phase 2 source-local gate. The local
stream-lab run against the deterministic `InterGalacticCaptureTarget` completed
at `runtime/stream-lab/local-results/local-capture-20260608-115445/` with
D3D11 Present FPS `57.091`, output FPS `31.825`, NV12 conversion failures `0`,
proof-visible frames `3 / 3`, and total handoff frame avg `0.177 ms`. A direct
call into `InterGalacticGameCaptureWebrtcSourceSmoke` completed at
`runtime/stream-lab/local-results/webrtc-source-smoke-20260608-115723/` and
proved the patched WebRTC source emits the new split fields with
`gpuScaled=291`, `gpuScaleFailures=0`, `cpuFallback=0`, `submitted=291`,
`repeated=0`, visible BGRA/I420 proof frames, and no helper/target process left
behind.

Important boundary: GPU encoder/WebRTC handoff continuity is not the same as
stable 720p30 pacing. The retained Debug candidate is now
`D3D11 texture -> GPU scale -> GPU NV12 -> hardware encoder /
WebRTC-compatible handoff`, and the latest live reports prove native-NV12
continuity under BG3 gameplay. The next validation is therefore not another
synthetic smoke or broad preset batch; it is a pacing-focused source-local or
single Smooth `1280x720@30` run that bounds `native_frame_ready`, delivery
queue wait, `OnFrame`, and Media Foundation input stalls.

June 7 night update: maintainer-approved live testing moved from user-collected
reports to Debug harness loops against BG3 via `Ctrl+Alt+PgDown`. The final
restored Debug build is the best measured native variant but is not clean.
All normal gameplay presets are truthfully capped/scored as `1280x720@30` for
the experimental D3D11 game-hook backend while it remains CPU-readback based.
The retained native change wakes the delivery thread when a ready frame is
queued and submits the newest queued frame, removing the artificial delivery
queue delay (`queueWait` max under 1 ms). Final confirmation
`stream-test-2026-06-08T00-13-36-295380Z.json` still classified Smooth,
Balanced, and High Quality as `frame_pacing_unstable`: GPU scaling succeeded,
`gpuScaleFailures=0`, `cpuFallback=0`, hardware H.264 and network were clean,
but native delivery/source-to-submit still showed roughly 107-125 ms delivery
gaps and 111-156 ms source-to-submit spikes. Tested helper-feed/source-pacer
variants at 60/45/36 fps were rejected because they either flooded async
readback, introduced stale/latency drops and regressions, or queued only
~23-24 fresh frames and repeated the rest. Next work should stop guessing at
cadence constants and either add missing p95/native-stage proof or move toward
GPU texture/NV12 handoff so the game-hook path does not require BGRA readback
and CPU I420 conversion for every WebRTC frame.

June 7 late update: the rebuilt Debug run showed why the next step is harness
completion before another streaming behavior change. Smooth was visually strong
at the start but developed jitter toward the end, and Balanced remained poor.
The newest reports already classified `frame_pacing_unstable` with GPU scaling
active and `cpuFallback=0`, but the old report shape still collapsed the run
into one aggregate summary. The stream-test runner now exports early,
middle, late, and tail windows for each preset, including sampled sender/receiver
FPS and p95/max sent gaps plus D3D11 game-hook counter deltas for submitted
frames, GPU scale, CPU fallback, readback ready/not-ready, stale drops, latency
drops, and source-order counters. A run that starts clean and degrades late is
therefore classified and reported as frame pacing evidence instead of relying
on manual visual notes or raw marker reading. No bitrate, LiveKit, profile, or
native capture behavior changed in this diagnostic pass.

June 7 latest update: the user re-ran the current Debug build and confirmed the
visual stream still stuttered/froze. Fresh Smooth and Balanced reports from
15:22/15:23/15:30 UTC showed the harness was not truly clean:
`frame_pacing_unstable`, frequent `source_frame_regression_drop`, substantial
`readbackLatencyDropped`, and p95/max frame gaps that match the visual issue.
The evidence still rules out the broad false causes for this pass: GPU scaling
was active, `gpuScaleFailures=0`, `cpuFallback=0`, native Media Foundation
encoder markers were fast, packet loss/RTT/NACK evidence was clean, and the
issue remained upstream of LiveKit/receiver behavior.

The current implementation patch is therefore still native/source-cadence
focused, not sender bitrate or LiveKit tuning. Native libwebrtc now prunes
pending scaled readbacks older than the last submitted source frame before
mapping/selection, and chooses the newest source frame when several readbacks
are ready. The D3D11 game-hook publish path also clamps Smooth/Balanced
`36 FPS` headroom to the actual `30 FPS` target so async readback is no longer
overdriven when the desired output is 30 FPS. The rebuilt Debug app carries
patched `libwebrtc.zip` SHA-256
`D9A785289796396D7FF168C1A6970BA03F8170E526CCE36C8C66BF751AC4A465` and runner
`libwebrtc.dll` SHA-256
`BD2C1579F7E5878A39D05641F0D10527D31C00CB02D6A3F7A5EBA2E0756245A1`.

Next validation starts with one BG3 Smooth `1280x720@30` D3D11 game-hook stream
test using the new stage split. Expected proof: capture request/logs show
`fps=30`, near-zero `sourceFrameRegressions`, low `readbackLatencyDropped`,
`gpuScaled > 0`, `cpuFallback=0`, populated `sourceToReadbackReadyMs`,
`readbackQueueToMapMs`, `mapToI420Ms`, `sourceToI420ReadyMs`, and
`sourceToQueueMs`, plus clean p95/max gaps. Only after Smooth is visually and
diagnostically clean should Balanced `1920x1080@30` be tested. If Smooth still
looks bad while the report claims healthy, treat diagnostic/report coverage as
suspect and inspect the full source -> WebRTC source -> sender path before
changing bitrate, LiveKit, fallback thresholds, or normal WGC/window-GDI
sharing.

Earlier June 7 duplicate-skip validation still matters: the WebRTC source now
skips duplicate source ticks instead of resubmitting stale frames, and High
Quality still requests `1920x1080@60` when BG3 only presents about `30` unique
frames in the tested scene, so the stream runner reports that as
source-present limited instead of a capture-backend failure.

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
- EXPERIMENTAL therefore added the next backend-internal diagnostic layer
  instead of changing profiles. Native WGC now emits `Inter Galactic WGC frame
  timing` markers for frame-pool empty/reuse, source capturability, startup
  sleeps, texture resize/recreate, `TryGetNextFrame`, GPU copy, blocking map,
  row copy, monitor scale lookup, and zero-hertz comparison. Stream-test JSON
  and Markdown parse these markers and expose the dominant WGC substage when
  `native_capture_limited` is detected.
- The Complete Stream Diagnostics pass formalized this evidence surface in
  `stream-diagnostic-contract.md`, `stream-diagnostic-system-audit.md`, and
  `stream-bottleneck-classification.md`. Stream-test reports now include an
  Executive Summary, Diagnostic Coverage matrix, classifier confidence, exact
  missing fields, evidence against false causes, and a fixed recommended next
  action. New streaming instrumentation should update that contract and parser
  instead of adding unparsed one-off log lines.
- The local stream-pipeline harness now lets EXPERIMENTAL run the synthetic
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
- The first live Phase 4D attempt published black output even though native
  source stats showed BG3 frames flowing at roughly 35 FPS and scaling from
  2560x1440 to 1280x720. To avoid another speculative patch, the next debug
  build adds a pre-I420 proof boundary: native libwebrtc writes BMP proof
  frames plus luma/visibility markers from the exact frame about to be
  converted for WebRTC, and stream-test parsing now treats
  `game_capture_webrtc_source` markers as the authoritative capturer evidence.
  The refreshed patched `libwebrtc.zip` SHA-256 is
  `B8FC5B578CEE5CBAEDEB60A2372A9A6874DB2C67DA429A0538A211235ED84C40`;
  the Debug runner `libwebrtc.dll` SHA-256 is
  `98A632FD2D115705F34E7B9C34F3E02C2E1E77BF01DF24FD4D80AAA4396232DF`.
  A pre-I420 proof BMP from session `wrtcdffa991c767a3efe` was inspected and
  is visible, full-frame BG3, and color-correct at 1280x720. Next validation
  should run Smooth only and compare local/remote stream output against this
  proven pre-I420 source boundary before running Balanced or High.
- The follow-up Smooth live run still produced black output while sender stats
  showed frames being captured, encoded, and sent on a clean route. The latest
  implementation adds a post-I420 proof boundary and routes
  `game_capture_webrtc_source` native lines through WebRTC logging so reports
  can distinguish BGRA/R10-to-I420 conversion failure from a later
  WebRTC/encoder/receiver failure. Native libwebrtc rebuild passed and the
  patched artifact was refreshed to SHA-256
  `AF225F5CEDFA33CEFD97074E0C79E9BA04BDF1F8A41C5FF70153FB1B52DFA7B0`
  with staged DLL SHA-256
  `91667E088D2C24E70B59F99C321BF55BBDA1C2BC49688A9EFA9955B72E782E67`.
  Follow-up validation installed the artifact into Flutter WebRTC, confirmed
  the Debug runner DLL hash matches the staged DLL, ran Dart format and the
  focused stream-test runner tests, and rebuilt the Windows Debug app. The
  next evidence boundary is a single Smooth live BG3 game-hook validation that
  compares pre-I420 and `i420_proof` visibility.
- The June 5 follow-up Smooth live run narrowed the black-output failure
  again. Native proof files from the same session showed the first sampled
  frame was truly black, while a later pre-I420 proof was visible and
  color-correct BG3. The stream-test report also failed to preserve
  `game_capture_webrtc_source` markers and fell back to stale window-GDI
  evidence. The next debug build suppresses bounded startup black frames until
  the first visible game-hook frame, records `initialBlackSkipped` and
  `visibleSourceSeen`, writes a visible I420 proof when available, and treats
  game-hook native markers as priority diagnostics. Refreshed patched
  `libwebrtc.zip` SHA-256:
  `E30F5230290CF7891B425782A6AAD76C9CC5A6E3FAC919196F9BCBAD7E651A06`;
  Debug runner `libwebrtc.dll` SHA-256:
  `450DFABB6AB772DC3BA03F2F7EAE1743E2A1FF1494B63BE1A23B9BAB61AFF6B9`.
  The next validation is still one Smooth BG3 window test with the
  `game-d3d11-hook-experimental` backend, not a preset sweep.
- The next June 5 validation still rendered black on the receiver, but moved
  the boundary past native acquisition, scale, I420 conversion, and local H.264
  encoding. Fresh proof BMPs from the same run are visible/color-correct after
  I420 reconstruction, sender stats show H.264 output bytes on a clean route,
  and the remaining surprising evidence was lifecycle contamination: stopped
  presets left one-hour `intergalactic_game_capture_helper` sessions alive.
  The current Debug build fixes that boundary by explicitly removing/stopping
  manually published Windows screen-share video tracks in `stopScreenshare()`,
  treating those manual `screenShareVideo` publications as active local screen
  shares for stream-test/UI stop decisions, stopping them before LiveKit
  `setScreenShareEnabled(false)` can unpublish the publication, and by
  logging/hardening native helper shutdown, including helper termination after
  graceful-stop timeout.
  Refreshed patched `libwebrtc.zip` SHA-256:
  `1DAAE258A6D987783141910C4188173E383E18F1F478B5B0BEAC8A173EEBCB5C`;
  Debug runner `libwebrtc.dll` SHA-256:
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`.
- The follow-up Smooth validation still left the helper alive, but proved the
  app now finds and unpublishes the manual `screenshare` publication. The
  missing evidence was native `stop_capture`, so the newest Debug build stops
  the `LocalVideoTrack` before `removePublishedTrack(...)` for local
  screen-share video publications. This is an app-only rebuild with Debug Dart
  payload SHA-256
  `4228A5B91DE08068C64792F2C788011F165926FF39F6E4FF8FCCBCBEED77393C`;
  `libwebrtc.dll` remains
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`.
  Next validation should again start with one Smooth BG3 window test, then
  stop the share and confirm no `intergalactic_game_capture_helper` process
  survives before considering WebRTC frame submission or receiver rendering.
- The next 60-second Smooth BG3 validation cleared the black-output/lifecycle
  boundary enough to expose the current performance wall. The stream was
  visible and helper teardown was clean, but capture/encode/send all sat around
  15.6 FPS. `game_capture_webrtc_source` markers showed source 2560x1440,
  output 1280x720, copied=3474, submitted=965, `mapMs` about 41-49 ms, and
  `convertMs` about 17-19 ms, while the native Media Foundation encoder timing
  stayed low and transport stayed clean. The current debug build therefore
  GPU-scales the game-hook WebRTC source into the requested output-sized BGRA
  texture before staging readback, maps only the scaled frame, preserves the
  old full-source CPU path as counted fallback, and exposes `gpuScaled`,
  `gpuScaleFailures`, `cpuFallback`, and `gpuScaleMs` in the stream-test
  report. The first implementation used a D3D11 video-processor input view and
  failed on BG3 with `input_view_create_failed hr=0x80070057`; the fixed path
  now matches the proven helper approach by sampling the shared source through
  an SRV into a scaled BGRA render target. Local WebRTC-source smoke passed on
  the rebuilt Debug runner DLL against the synthetic D3D11 target with
  `gpuScaled=103`, `gpuScaleFailures=0`,
  `cpuFallback=0`, source `1920x1080`, output `1280x720`, visible proof
  `2/2`, visible I420 proof `1/1`, `mapMs=1.192 ms`, and
  `convertMs=1.005 ms`.
  Final patched `libwebrtc.zip` SHA-256:
  `CAD4ADF1A4CBBD49D058B08DF928BF9AD1C60557317FC7396EF275E02C4CB8C6`;
  final Debug runner `libwebrtc.dll` SHA-256:
  `0EC17B36B313B9C38FBE3AC6229B10D5ACB3A1300805378168AAEAF8D8C0B6EE`.
  Next validation is one Smooth 720p BG3 live test.
- The June 3 BG3 window tests changed the active comparison target again for
  this specific source. App default, Native default, and WGC-only all observed
  the `wgc` capturer and stayed around 12-14 FPS with native p95/max gaps near
  132-144 ms / 201-246 ms. The debug "DirectX" selection observed
  `window-gdi`, not a DirectX window capturer, and reached roughly 20 FPS with
  native p95/max gaps near 61-64 ms / 126-158 ms. Network, bitrate, encoder
  timing, resolution, and crop state stayed clean. Treat this as evidence that
  the current WGC window path is map/readback-acquisition limited for BG3,
  while the legacy WebRTC window-GDI path is the best current debug comparison.
  It is still not enough to change the product default without resolving source
  rebind/startup risk and display-path behavior.
- The same June 3 reports exposed a report-classification bug: rare WGC
  frame-pool empty/reuse/null counts could label the dominant WGC substage as
  `frame_pool_empty` even when those counts were tiny and the measured blocking
  `map_texture` timing dominated the frame budget. The runner now only reports
  frame-pool/startup wait as dominant when the miss/sleep ratio is substantial
  or no timing evidence exists, and the top summary includes the observed
  native capturer so `window-gdi` versus `wgc` is visible immediately.
- A follow-up June 3 run with the corrected reports made the product change
  concrete. Smooth App default/WGC still observed `wgc`: App default sent about
  15.2 FPS with p95/max native gaps around 125/206 ms and WGC `map_texture`
  averaging about 52 ms; WGC-only sent about 13.6 FPS with p95/max around
  131/229 ms and `map_texture` around 61 ms. The DirectX/window-GDI run
  observed `window-gdi`, sent about 18.6 FPS, cut p95/max native gaps to about
  65/154 ms, kept native encoder timing around 2 ms average, and still had
  clean 0% loss / roughly 3 ms RTT. Normal Windows window/game App default now
  uses that DirectX/window-GDI path. Explicit Native default and WGC-only
  remain test options for WGC work; display sharing remains on native default.
- Post-promotion validation confirms the default split but not the final FPS
  goal. The 16:19 BG3 window App default report observed effective
  `directx-only` / `window-gdi` and correct 1280x720 / 1920x1080 output, but
  Smooth and Balanced still sent only about 16.8-18.0 FPS with native p95/max
  frame gaps around 67-72 ms / 160-167 ms. Native encoder timing stayed low
  at about 2-4 ms and transport remained clean, so the remaining window-source
  limiter is window-GDI capture acquisition/cadence. The 16:22 display control
  correctly stayed WGC and remained `map_texture` limited at about 14 FPS.
  EXPERIMENTAL therefore added parsed window-GDI backend substages instead of
  retuning bitrate, codec, LiveKit, or fallback.
- The window-GDI substage pass adds native `Inter Galactic window GDI frame
  timing` markers and stream-test parsing for window-rect/visibility checks,
  DC acquisition, frame allocation, `PrintWindow(PW_RENDERFULLCONTENT)`,
  fallback `PrintWindow`, `BitBlt`, crop, cleanup, and owned-window work. JSON
  and Markdown now expose `GDI Substage`, a `window-GDI substage markers`
  coverage row, and a `fix window-GDI substage` recommended action when
  `native_capture_limited` has this evidence.
- The refreshed debug build contains the rebuilt native DLL for this pass:
  patched `libwebrtc.zip` SHA-256
  `117ADD0864A6D2038BBF570673B383BF158041D45C42AB49396CF0F267620372`,
  rebuilt/debug `libwebrtc.dll` SHA-256
  `6E564D425EEE78E6B4D436B1D8711038560EF2D95C239EBB89037827422BEB0E`.
- The latest diagnostics-only follow-up adds Capture Cause Attribution to
  stream-test reports and a native timer for dirty-region analysis. The next
  BG3 window logs should now say whether the remaining 55-60 ms native capture
  call is dominated by full source acquisition size, blocking acquire/callback
  wait, CPU readback/copy, dirty-region processing, frame lifetime/lock
  synchronization, or full-frame copy before downscale. Refreshed patched
  `libwebrtc.zip` SHA-256:
  `73A81A9A1CAF482C392E29F39B50C93F7BA469A133DEC4D5F9E6E3EA71F5D396`;
  rebuilt/debug `libwebrtc.dll` SHA-256:
  `5A62E1B1DD53538341C23C2B2B681644EA0742DEE0404F3B6E49B3CBCACE547D`.
- The next pass is still diagnostics-only and targets the same native
  acquisition boundary. Debug stream tests can now cycle window-GDI capture
  methods for window sources: current `PW_RENDERFULLCONTENT` first, plain
  `PrintWindow` first, `BitBlt` first, and `BitBlt` only. Native markers,
  stream-test JSON, and Markdown record the requested/applied mode, final
  producer method counts, and black/low-variance frame counts. This should
  prove whether the slow `PrintWindow(PW_RENDERFULLCONTENT)` call is avoidable,
  whether `BitBlt` is fast but invalid for game windows, or whether the
  remaining limiter is outside the method order. The refreshed test build has
  patched `libwebrtc.zip` SHA-256
  `7BAD628EC7EE79B90E16DEA97C0FEE7F63458FC4DF8F0836CF3B8ABA29B46EDD` and
  debug `libwebrtc.dll` SHA-256
  `80A8B74975FB78747026D143FB6A0FE7A421E9AD8A920F6984994C79D088D2AB`.
- The first method-comparison run proved that the non-default methods are not
  viable for the tested BG3 2560x1440 window. Plain `PrintWindow` first and
  both `BitBlt` modes improved nominal FPS but produced pointer-only/black
  output; native counters showed black/low-variance frames dominating those
  rows. The report classifier now marks those rows as
  `invalid_capture_output` so future score comparisons do not promote them.
  The only currently valid window-GDI method for this source remains
  full-content `PrintWindow`, and its 44-45 ms native substage cost is the
  concrete limiter to fix or avoid.
- The June 4 Phase 3A follow-up changed the optional D3D11 game-capture probe
  from a blocking pre-preset step into a concurrent initial-preset measurement.
  Probe-only runs still avoid LiveKit publishing, but normal stream-test runs
  now compare local Present cadence against the active WGC/window-GDI sender
  cadence in the same time slice. This does not publish hook frames or change
  stream profiles, capture defaults, codec, fallback, LiveKit, or native
  capture behavior.
- The June 4 Phase 3B follow-up adds a host shared-texture consumer to the same
  debug-only probe. The hook publishes shared D3D11 texture ring handles and
  latest-frame metadata through a shared-state mapping/event; the helper opens
  those textures from the host side and reports consumed frames, missed frames,
  host frame age, consumer gaps, open failures, and optional proof readback.
  This proves or disproves the shared-texture handoff before any LiveKit
  publication work. It still does not alter normal WGC/window-GDI publishing or
  stream profiles.
- The June 4 Phase 4A follow-up adds a local publication-handoff probe, still
  debug-only and still outside LiveKit. The helper reads the latest opened
  shared D3D11 texture, contain-fit scales it into a preset-sized BGRA buffer,
  paces output to the first tested preset target, and reports readback, scale,
  total handoff timing, output FPS/gaps, visible buffer counts, paced drops,
  and requested/source/output dimensions. This proves whether the hook path can
  produce publication-shaped local frames before implementing the real Phase 4B
  WebRTC/LiveKit source.
- The first Phase 4A runtime report sharpened the split. The normal BG3
  window sender still measured about 16 FPS with clean network, fast native
  encoder timing, correct scaling, and window-GDI `print_full` as the concrete
  limiter. The D3D11 probe attached to the same source, observed about 50
  Present FPS, opened all host shared-texture slots, consumed 899 frames, and
  had no hook-copy/drop problem. `publication-handoff.json` was missing because
  the helper failed before finishing the handoff result writer/teardown path;
  the follow-up patch fixes the handoff p95 percentile bug, hardens percentile
  normalization, extends the runner watchdog, and logs helper shutdown phases.
- The next Phase 4A runtime report proved the writer/teardown repair and made
  the handoff bottleneck concrete. The helper produced visible 1280x720 output
  from the 2560x1440 BG3 backbuffer, but only at about 10.7 FPS because it
  read back the full source texture and then CPU-scaled into the target buffer.
  The helper now measures a GPU-side contain-fit scale into the preset-sized
  BGRA output before staging readback, and stream-test reports call a visible
  below-target handoff `slow` rather than `healthy`.
- The post-GPU-scale Phase 4A.5 BG3 report improved handoff cadence but did
  not clear the target. Present cadence stayed healthy, GPU scale timing was
  effectively free, and output remained visible, but the scaled-output staging
  readback still held output to about 16 FPS with p95/max readback spikes
  around 30/67 ms. The remaining game-capture handoff question is therefore
  scaled staging/readback and buffer cadence, not BG3 Present, hook copy,
  texture sharing, GPU scale math, encoder, network, LiveKit, or receiver.
- The deterministic D3D11 capture-target follow-up is implemented and
  documented in `docs/architecture/calls-streaming-audio/game-capture-test-target.md`. Use it for repeatable
  log-output, source-selection, report-parser, and pipeline verification before
  asking for another BG3 run. BG3 should remain the stress/compatibility case
  for 10-bit backbuffers, real game window behavior, and real gameplay load.

Treat average FPS as useful but incomplete. The next performance boundary is
frame pacing: native capture cadence, frame interval p95/max, and whether the
capture/scale/convert path delivers frames evenly enough for 30 FPS gameplay.

## Done From StreamingGuidance.md

### Network, SFU, Receiver, And Encoder Triage

Status: done for the current evidence set.

- Diagnostics and stream-lab reports now separate capture, encode, send,
  receive, decode/render, ICE route, and quality-limitation evidence.
- Recent receiver logs show the receiver is requesting HIGH and rendering what
  it receives. No current evidence points to receiver decode/render as the main
  FPS limiter.
- Recent sender logs show clean packet loss/RTT/NACK behavior for the tested
  scenarios, so bitrate and internet capacity are not the primary active
  tuning target.
- Hardware H.264 through Media Foundation is active in the current Windows
  gameplay path when the hardware-first preference is enabled.

### Resolution Cap And Crop/Stretch Repair

Status: done for Windows window/display release-candidate paths, with manual
visual validation still required after native changes.

- The patched Flutter WebRTC bridge passes requested screen-share dimensions
  as max pre-encode bounds to the native `StartWithMaxFrameSize(...)` path.
- Native capture no longer uses `Start(fps, x, y, w, h)` as a scaler, because
  that overload is a capture-region crop.
- Window sources now use the actual captured `DesktopFrame` buffer size and
  publish a stable preset-sized encoder canvas with contain-fit content.
- Display sources keep dynamic contain-fit dimensions.
- Normal validation must still inspect the visible remote frame, because prior
  sender stats looked plausible even while the image was cropped.

### Basic Frame-Cadence Measurement

Status: done for sampled report evidence.

- Native desktop-capture diagnostics now emit submitted FPS plus p95/max frame
  interval evidence.
- The debug stream-test runner can compare App default, Native default,
  WGC-only, DirectX-only, and window-crop diagnostic backends.
- Reports include native submitted FPS, p95/max interval, capture wait/permanent
  errors, crop-region state, observed native capturer label, dirty-region mode,
  dominant native capture delay phase, and a subjective-notes placeholder.
- Stream-test JSON and Markdown now include a Frame Pacing section. It derives
  sampled p50/p95/max intervals from cumulative WebRTC frame counters for
  capture, pre-encode proxy, encoded, sent, received, decoded, and rendered
  stages, counts zero-delta sampled counter windows as stale gaps so freezes
  are visible in p95/max and average FPS, and carries duplicate/stale native
  marker counts where available.
- The sampled stages are not true per-frame timestamps. They are interval
  estimates across the runner's one-second sample windows, enough to identify
  where 100 ms-class gaps begin before designing a native pacer.

### Avoid More LiveKit/Bitrate Guesswork

Status: done as current project posture.

- Smooth remains the default stability profile.
- Windows hardware-first Smooth now uses a release-candidate 3 Mbps ceiling with a
  2.5 Mbps floor, 30 FPS target, and 36 FPS sender cap.
- Balanced and High Quality remain opt-in higher-quality paths.
- LiveKit adaptive stream, dynacast, receive priority, and focused HIGH policy
  remain in place, but the current bottleneck is below LiveKit.
- DirectX/window-GDI is now the normal Windows window/game App default. Live
  switching away from that backend still remains a restart-boundary operation
  because prior tests showed in-place switches can poison the next sender until
  a full share restart.
- The app refreshes and rebinds the desktop source before each publish so
  stream-test batches can reuse the selected source without relying on stale
  `DesktopCapturerSource` ids.

### Do Not Add Artificial Playback Delay

Status: documented as current architecture.

- The current LiveKit/flutter_webrtc renderer path does not expose decoded
  frames for an app-level playout-delay buffer.
- Artificial UI delay would not create missing sender frames and could desync
  stream video from call audio or shared-content audio.
- Choppy gameplay should continue to be handled as a sender cadence,
  capture-path, receiver, network, or SFU diagnostics problem before any
  delay-buffer design is considered.

## Still Needed

### 1. Full Per-Stage Frame Pacing Evidence

Implemented for sampled WebRTC counter evidence.

Current report fields:

- native capture p95/max interval plus submitted FPS, duplicate/stale reuse,
  wait timeouts, and permanent errors when native markers are present
- sampled capture p50/p95/max interval from `framesCaptured`
- sampled pre-encode p50/p95/max interval from `framesCaptured` only when
  pre-encode dimensions are present, labeled as a proxy rather than a separate
  native counter
- sampled encoded p50/p95/max interval from `framesEncoded`
- sampled RTP send p50/p95/max interval from `framesSent`
- sampled receiver receive/decode/render p50/p95/max intervals from
  `framesReceived`, `framesDecoded`, and `framesRendered` when exposed

Current native capture-call split:

- The patched Windows capturer now appends result-callback and inferred
  acquisition-wait fields to `Inter Galactic desktop capture cadence`.
  Stream-test JSON and Markdown parse those fields as
  `averageCaptureResultCallbackMs`, `averageCaptureAcquireWaitMs`, and the
  Native Diagnostic Markers `Acquire Wait` column.
- The existing `desktop capture frame timing` marker remains the copy/convert,
  scale, and `OnFrame` breakdown. Together, `Capture Call - result callback`
  gives the acquisition/wait side of the call, while frame timing shows whether
  local frame work is expensive.
- The May 31 backend pass added one more native split: WebRTC
  `DesktopFrame.capture_time_ms()` is exported as `Source Capture`, and frame
  timing now includes updated-region dirty/empty counts. Reports also classify
  native p95 gaps over 1.5 frame budgets and max gaps over 3 frame budgets as
  visible frame-pacing instability, so a strong average FPS cannot hide
  100 ms-class native gaps.
- The next May 31 backend pass made the capture-call split complete enough for
  another log cycle: native cadence markers now include callback-entry delay,
  result-callback work, post-callback wait, and residual unaccounted wait
  alongside source capture and whole-call acquire wait. Stream-test JSON and
  Markdown reports parse those fields.
- The June 2 diagnostics build adds dirty-region shape to the frame-timing
  marker and stream-test reports: total and max updated-region rect count,
  average and max dirty-area ratio, full-frame update count, and tiny-update
  count. The Markdown Native Diagnostic Markers table shows these as
  `Dirty Shape`, and `native_capture_limited` bottleneck notes include the
  dirty-region label.
- The follow-up June 2 diagnostics patch adds actual native capturer
  attribution, a stream-test Force full-frame dirty regions comparison mode,
  and a report-level dominant capture phase (`source_capture`,
  `callback_entry`, `capture_callback`, `post_callback`, or
  `unaccounted_wait`). The same pass promoted Force full-frame dirty regions
  for normal Windows window/game shares when the effective backend is App
  default/native-default/WGC. This does not crop, stretch, retune profiles, or
  change DirectX/display behavior.
- The next June 2 backend-internal pass instruments the WGC session under that
  wrapper boundary. Reports now parse a `WGC Substage` summary covering
  frame-pool empty/reuse, source capturability, startup waits, texture
  resize/recreate, `TryGetNextFrame`, surface/texture lookup, content-size
  query, `CopySubresourceRegion`, blocking `Map`, row copy, monitor scale
  lookup, and zero-hertz comparison. When wrapper-level `source_capture` is
  still the limiter, bottleneck evidence can now say which WGC substage was
  dominant instead of stopping at the outer callback/acquire bucket.
- The June 3 window-GDI pass applies the same contracted approach to the
  observed `window-gdi` path. Reports now parse a `GDI Substage` summary for
  `PrintWindow(PW_RENDERFULLCONTENT)`, fallback `PrintWindow`, `BitBlt`, crop,
  DC/frame setup, and owned-window capture/composite work.
- The next June 3 capture-cause pass turns those parsed markers into one
  explicit attribution matrix: full source acquisition, blocking acquire wait,
  CPU readback/copy, dirty-region processing, frame lifetime/lock/sync, and
  full-frame copy before downscale. It also adds
  `avg_updated_region_ms`/`max_updated_region_ms` to native frame-timing
  markers so dirty-region shape can be separated from dirty-region processing
  cost.

Remaining precision gap:

- native capture markers do not yet emit p50 interval
- native dirty-region force mode is now normal for explicit Native default and
  WGC-only Windows window/game comparison paths, while App default
  DirectX/window-GDI and display shares stay on Auto
- native queue depth/latest-frame reuse markers still come from the
  latest-frame pacer counters, so pacer-off comparison runs have less native
  queue detail
- true per-frame pre-encode timing still requires a deeper native timestamp
  marker outside the current one-second sampled runner cadence
- if the WGC substage marker shows `map_texture`, `copy_rows`, or
  `zero_hertz_compare` dominating, the next implementation should optimize that
  concrete stage rather than touching bitrate or LiveKit
- if it shows repeated `frame_pool_empty`, startup sleeps, or
  `source_not_capturable`, the next implementation should target WGC frame
  availability/source-state behavior
- if WGC substage timing is small while wrapper-level callback-entry or
  unaccounted wait remains high, the next split should move to frame lifetime,
  callback dispatch, or outer capturer locking rather than deeper WGC copy work
- if the new GDI substage marker shows `print_full`, `print_fallback`,
  `bitblt`, `crop`, or `owned_capture` dominating, the next implementation
  should target that concrete window-GDI stage instead of changing stream
  profiles

The first success target remains Smooth 720p gameplay with sampled/native p95
near the 30 FPS frame budget and no repeated 100 ms-class gaps. Do not make
1080p30 the main target until 720p30 pacing is visibly stable.

### 2. Native Latest-Frame Pacer Design

Implemented and promoted to normal Windows desktop/window publish behavior.

The current pacer separates frame acquisition from submit cadence inside the
patched Windows desktop capturer:

- capture callback stores the latest frame and returns quickly
- pacer wakes on the target cadence
- pacer submits the newest available frame
- stale frames are dropped instead of queued
- queue size stays bounded at one frame

Normal Windows desktop/window screen-share publishes now pass the
`intergalacticCaptureFramePacing=latest` constraint by default. The debug
stream-test runner still exposes an `Enable latest-frame pacer` checkbox so
explicit off/on A/B runs remain possible; reports export submitted FPS, unique
FPS, p95/max submit gaps, frame age, `OnFrame` time, duplicate submissions,
overwritten frames, and skipped ticks.

The promotion was based on the 2026-05-28 BG3 paired evidence. In the clearest
Balanced DirectX-only pair, pacer off captured around 15.9 FPS but encoded and
sent only around 6 FPS with roughly 447 ms encode time and 560 ms packet send
delay. Pacer on kept capture, encode, and send aligned around 18.2 FPS with
roughly 56 ms encode time and 10 ms send delay. Network loss, RTT, and
quality-limitation evidence stayed clean. The remaining performance target is
therefore native capture acquisition/cadence, not WebRTC send queue collapse.

### 3. Capture Backend Policy By Source Type

Partly implemented as diagnostics, not as product policy.

Current state:

- App default/native default is still the normal path.
- WGC-only and DirectX-only are available as debug comparison modes.
- Fresh May 31 windowed BG3 one-at-a-time evidence favors App default and
  Native default. DirectX-only is currently capture-acquisition-limited on the
  user's test machine and should not become a default without newer proof.
- Display Smooth/Balanced shares now use the 30 FPS target as the
  sender/capture cap; window/game captures keep the 36 FPS cap headroom.

Remaining work:

- Re-run windowed BG3 Smooth/Balanced App default and Native default with the
  source-rebind patch, then run one display smoke to validate the display cap.
- If one path consistently wins for gameplay cadence, design an opt-in Game
  Streaming Mode rather than changing the global default.
- Keep privacy implications visible if any display-crop mode is considered.

### 4. GPU-First Scale/Convert Investigation

Partly implemented as a debug-only shared-texture consumer proof; not yet a
publishing path.

The current normal publish path still relies on the existing CPU-oriented
desktop/window capture boundary. The game-capture POC now has enough host-side
shared-texture diagnostics to inspect whether Windows gameplay capture can
preserve GPU surfaces longer:

- acquire/copy Direct3D frames quickly
- open shared D3D11 textures from the Inter Galactic-controlled host side
- measure host frame age, missed frames, and consumer gaps
- keep the proof-only GPU contain-fit texture handoff as the visual-validation
  boundary
- feed the debug-proven NV12/GPU output into an encoder-controlled path; the
  synthetic local Media Foundation proof is complete, and the next proof
  target is now WebRTC/LiveKit source integration from the live BG3-proven
  path
- avoid synchronous heavy work in the capture callback

This remains a post-release quality step for publication. The local helper has
now proven D3D11 attach, shared-texture consumption, proof-only GPU scale,
encoder-compatible NV12 conversion, synthetic-target proof output, local
synthetic H.264 encoder proof, color-correct BG3 proof output, and live BG3
local H.264 encoder proof at 720p30 and 1080p30. A real WebRTC/LiveKit
publication path is still being validated before remote users can rely on the
new backend. The current debug LiveKit path now reaches visible output and
cleans up helper sessions. The latest live Smooth run proved GPU scaling is
active (`gpuScaled=994`, `gpuScaleFailures=0`, `cpuFallback=0`) but still
settled around 24-26 FPS because synchronous scaled staging `mapMs` rose to
about 34.5 ms. The current Debug rebuild replaces that immediate blocking map
with a four-slot async scaled-readback ring and parsed readback counters.
Exact local WebRTC-source smoke against the rebuilt Debug runner cleared the
native source boundary with `gpuScaled=145`, `cpuFallback=0`,
`readbackReady=145`, `readbackNotReady=0`, `readbackOverwritten=0`,
`mapMs=0.00091 ms`, `convertMs=0.18044 ms`, and clean helper teardown.

### 5. Game Streaming Mode

Partially implemented for developer-mode Windows app-default window/game shares.
There is still no polished production-facing game-capture mode. The current
developer path auto-selects the D3D11 hook only for app-default window sources
when developer mode is enabled and falls back to DirectX/window-GDI if the hook
cannot start.

The project has debug backend comparisons and a window-crop diagnostic path,
but no product-facing Game Mode. A future Game Mode should remain opt-in until
logs prove the best source policy. Candidate choices:

- Auto
- Window capture
- Display capture
- Display crop
- WGC diagnostic
- DirectX diagnostic

Do not expose display-crop as a silent default because it can capture overlays
or other visible desktop content.

### 6. Profile Selection Proof

Still needed as a small UX/diagnostic follow-up.

Recent testing exposed one confusing state where the user thought Balanced was
running but diagnostics showed Smooth. Add or verify an unmistakable in-call
active-profile readout before future tuning, so measurements cannot be
misattributed to the wrong profile or a stale saved preference.

## Next Step Plan

### Release-Candidate Validation

Status: true native-NV12 GPU continuity is proven in actual BG3 gameplay;
Smooth 720p30 pacing is still not complete as a non-developer production D3D11
game-hook default.

The earlier `stream-test-2026-06-05T19-18-37-975209Z` result remains useful
historical proof that BG3 can publish visible, color-correct 720p output through
the debug game-hook path. The June 10 actual-gameplay reports supersede the
older CPU-I420 fallback state as the current readiness state: native-NV12
continuity held, but the retained build was still not clean.

Current retained-build evidence:

- Retained native behavior is `1280x720@30` with a ring-slot native-NV12 frame
  handoff to Media Foundation/WebRTC.
- Rejected branches include 60/45/36 FPS helper feeds and WebRTC-side
  source/wall pacing; those either worsened jitter, hid source cadence, or did
  not solve the frame gaps.
- GPU scaling and native-NV12 handoff stayed active with `gpuScaleFailures=0`,
  `nativeNv12Failures=0`, and `cpuFallback=0`.
- Hardware H.264, LiveKit-facing sender stats, route, packet loss, RTT, and
  quality limitation evidence stayed clean.
- Final reports still classified as `frame_pacing_unstable`; repeated frames,
  delivery overwrites, source-to-submit tails, and occasional encoder input
  stalls remained below stable 720p30.

Therefore Smooth 720p30 is cleared only for developer-mode app-default
experimentation, not as a non-developer release-candidate gate for the D3D11
game hook. Normal release streaming should stay on the established
WGC/window-GDI paths while D3D11 remains experimental.

### Next Engineering Pass

1. Do not request another broad live BG3 preset batch until the native-NV12
   Smooth pacing boundary changes.
2. Use one source-local or Smooth 720p D3D11 game-hook run to bound
   `native_frame_ready`, delivery queue wait, `OnFrame`, and Media Foundation
   input stalls at the same timestamp grain as the report.
3. Treat the current best path as ring-slot native NV12 with bounded GPU
   readiness waits. Do not restore the rejected helper-feed, CPU-I420 fallback,
   or WebRTC-source pacer branches without paired evidence.
4. If `nativeNv12Failures`, `cpuFallback`, or `gameCaptureGpuHandoffUnproven`
   returns, fix the GPU resource path before investigating pacing.
5. Keep normal WGC/window-GDI publishing stable while the game-capture backend
   remains debug-only.
6. Continue classifying normal stream-test evidence by p95/max native gaps and
   capture-cause attribution. Do not tune bitrate, codec, or fallback unless a
   fresh report proves those are the limiter.

## Do Not Do Next

- Do not tune bitrate again without new frame-pacing evidence.
- Do not disable the Windows latest-frame pacer in normal publishing unless a
  paired regression proves it harms visibility, latency, or sender cadence.
- Do not switch the default back to VP8 solely because a hardware path had an
  older black-window symptom; that symptom was later narrowed to window
  geometry/source shape.
- Do not make DirectX-only the default while it remains a restart-boundary
  diagnostic backend.
- Do not add an app-level playout delay as a substitute for missing sender
  frames.
- Do not chase 1080p60 as the next goal; return to Smooth 720p30 stability
  before using 1080p30 as the controlled quality step.

## Architecture Docs Status

- `livekit-gameplay-streaming.md` remains the durable behavior reference for
  current presets, receiver policy, diagnostics, and native capture caveats.
- `stream-optimization-report.md` remains the evidence log and historical
  tuning report.
- `streaming-pipeline.md` remains the concise cross-system map owned by the
  DOCUMENTATION area; this pass does not modify it.
- This document is the compact status/checklist for implementing
  `StreamingGuidance.md` without re-reading the full log history.
