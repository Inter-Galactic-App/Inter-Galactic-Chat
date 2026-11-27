# June 7-8 Window Capture And Native NV12 Proof

Date range: 2026-06-07 to 2026-06-08

Dated closeout history extracted from `../streaming-guidance-status.md`. Covers the June 8 Phase 4/Phase 2 native-NV12/WebRTC source proof closeouts and the June 7 night/late/latest Debug harness cycles that preceded them.

---

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
After the unrelated story composer compile blocker was cleared in local
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

