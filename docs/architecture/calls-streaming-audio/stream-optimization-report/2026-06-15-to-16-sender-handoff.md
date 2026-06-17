# 2026-06-15 to 2026-06-16 Sender Handoff Evidence

Status: historical evidence archive; current DX11 validation baseline
Owner: EXPERIMENTAL for runtime evidence; DOCUMENTATION for structure
Last reviewed: 2026-06-16 by DOCUMENTATION

This archive slice preserves the detailed run narrative that previously lived
in the top-level `stream-optimization-report.md`. Use the top-level report for
current routing and this file when investigating the 2026-06-15/16 sender
handoff, dummy NV12, source-adapter, and native-tail evidence.

## Source-Adapter Validation

Latest Live Testing Override evidence on 2026-06-16 landed the narrow WebRTC
source-adapter branch. `src/internal/video_capturer.cc` lets already-sized
Inter Galactic D3D11 native NV12 helper frames bypass only the capturer-level
framerate adapter drop when an active sink exists and no resolution adaptation
is required. Normal I420/window capture and dummy NV12 live-sender controls
stay on the existing WebRTC adapter path.

Local validation after the branch passed:
`native-sender-handoff-isolation-20260615-222842` reported native capture to MF
handoff around `30.2 FPS`, WebRTC source gate delivery around `30.7 FPS`,
native NV12 failures `0`, CPU fallback `0`, `OnFrame` call about `0.044 ms`
average, and debug runner libwebrtc digest `DAE05805B55E`.

Two BG3 Smooth 1280x720@30 live runs then crossed the average product gate:
`stream-test-2026-06-16T02-32-02-321672Z` reached about
`31.6 / 29.9 / 30.3` capture/encode/send FPS, and confirmation
`stream-test-2026-06-16T02-33-32-152165Z` reached about
`31.0 / 29.4 / 30.2`. Both runs used `game-d3d11-hook`, visible/color-correct
1280x720 output, native NV12 failures `0`, CPU-I420 fallback `0`, clean packet
loss/RTT, sub-millisecond live `OnFrame`, effectively zero MF fence wait, and
raw sender diagnostics with `source_adapter_drops=0`.

Residual risk: the report classifier still labels these runs
`native_nv12_ready_limited` because isolated NV12 BLT-to-ready/source-to-submit
max spikes remain visible even when average capture/encode/send are at or
above target. The second confirmation run also showed a late-window
capture/encode wobble while send stayed near target.

## Direct-BLT, Fence Wake, And Source-QPC Evidence

Earlier 2026-06-16 Live Testing Override evidence moved the BG3 Smooth
1280x720@30 limiter again. EXPERIMENTAL replaced the scratch-to-owned native
NV12 copy with a direct `VideoProcessorBlt` into a per-frame encoder-owned
NV12 texture and queued that texture with an explicit post-BLT fence. Local BG3
source isolation after the change,
`native-sender-handoff-isolation-20260615-211136`, reported WebRTC source gate
delivery about `30.2 FPS`, native NV12 failures `0`, CPU fallback `0`,
source-to-submit about `8.7 ms`, and BLT-to-ready about `0.5 ms`.

The matching live BG3 calls did not reach the 720p30 product gate. The best
direct-BLT immediate-fence result, `stream-test-2026-06-16T01-13-00-451772Z`,
kept visible 1280x720 output, `owned_texture_direct_blt`, native NV12 failures
`0`, CPU-I420 fallback `0`, packet loss `0.0%`, source-to-submit about
`13.6 ms`, and BLT-to-ready about `1.2 ms`, but still landed around
`28.2 / 28.3 / 28.0` capture/encode/send FPS. A post-BLT flush experiment,
`stream-test-2026-06-16T01-17-57-747408Z`, worsened MF fence wait and was
rolled back.

The next accepted branch moved readiness waiting out of Media Foundation by
registering a D3D fence-completion wake for direct-BLT native NV12 slots, then
admitting fresh frames from source QPC when the source interval is due. The
fence-event live run, `stream-test-2026-06-16T01-58-09-753944Z`, drove Media
Foundation native-ready fence wait down to about `0.001 ms` average with `0`
native NV12 failures and `0` CPU fallback, but still reached only about
`28.3 / 28.0 / 28.0` capture/encode/send FPS. The best source-QPC admission
run, `stream-test-2026-06-16T02-04-53-264032Z`, loaded libwebrtc digest
`9F138B436DAF`, kept `OnFrame` about `0.12 ms` average, MF fence wait about
`0.001 ms`, and native capture around `31.7 FPS`, but the published stream was
still only about `28.7 / 28.1 / 28.2` capture/encode/send FPS.

Rejected local branches: hard source-QPC capping starved source-local WebRTC
delivery, and timestamp minimum-delta pacing also failed the local gate. Both
were rolled back. The final local verification
`native-sender-handoff-isolation-20260615-221503` passed with native MF
handoff about `30.6 FPS`, WebRTC source gate about `31.1 FPS`, native NV12
failures `0`, and CPU fallback `0`.

## Dummy NV12 Live Sender Gate

The 2026-06-15 dummy NV12 live-sender run separated the live sender from the
BG3-specific native frame path. `dummy-nv12-live-sender-20260615-174359` fed
generated 1280x720 native NV12 through the normal WebRTC/Media
Foundation/LiveKit sender path and passed at about `30.3 / 30.0 / 30.0`
capture/encode/send FPS. It reported source mode `dummy-nv12-live-sender`,
native NV12 submitted/failures/CPU fallback `1057 / 0 / 0`,
`deliveryOnFrameCall` about `3.07 ms` average, and Media Foundation
`ProcessInput` about `0.38 ms` average.

The result proved the current raw sender can sustain Smooth 720p30 from
already-ready native NV12. It did not prove BG3 native frame ownership,
R10-to-NV12 readiness, source frame age, or sample lifetime under live sender
coupling.

## Sender/Input Boundary And Queue Constants

Earlier 2026-06-15 evidence moved the branch from broad local capture tuning
to the sender/input boundary. Full stream debug build
`runtime/stream-lab/debug-builds/20260615-194341/stream-debug-build-20260615-194341.md`
completed after a narrow native cleanup that makes invalid numeric diagnostic
environment values fall back to defaults. Short source smoke
`runtime/stream-lab/local-results/webrtc-onframe-isolation-20260615-154627/`
confirmed the fallback path: invalid values reported `deliveryQueueDepth=1`,
`nativeNv12ReadyDrainDepth=1`, `nativeNv12PendingPollMs=8`, and
`nativeNv12MaxPendingSlots=2`.

The prerequisite BG3 local aggregate
`native-sender-handoff-isolation-20260615-153151` passed again with camera
motion: native capture-to-MF reached `30.309` handoff FPS with native NV12
failures `0`, CPU fallback `0`, and the local WebRTC source-OnFrame gate
reached `29.535` FPS with sub-millisecond `OnFrame` calls. The following live
BG3 Smooth 1280x720@30 calls still missed target. Default newest-only `1/1`
`stream-test-2026-06-15T19-37-12-620527Z` landed around
`25.0 / 24.8 / 24.7` capture/encode/send FPS, while guarded diagnostic `2/2`
`stream-test-2026-06-15T19-39-21-107011Z` landed around
`26.5 / 25.5 / 24.7` FPS. Both runs classified as `encoder_handoff_limited`;
native NV12 fences stayed healthy, failures and CPU fallback stayed at `0`,
not-ready/ready-drop counters stayed at `0`, and packet loss was clean.

This evidence kept `2/2` as a diagnostic comparison only. It did not justify
default queue-constant tuning or requiring users to switch BG3 HDR/SDR modes.

## Local Native-MF And WebRTC OnFrame Gates

The local native capture-to-Media Foundation isolation gate proved the local
D3D11 hook, R10-to-NV12 conversion, and Media Foundation H.264 proof boundary
could sustain the 720p30 starter gate outside WebRTC/LiveKit.

Synthetic R10/HDR-like validation
`runtime/stream-lab/local-results/local-capture-20260615-100322/` passed at
`1280x720@30`: source format `r10g10b10a2`, Present `58.218 FPS`, handoff
output `32.118 FPS`, NV12 frames/failures/convert avg `142 / 0 / 0.035 ms`,
and local `h264-mf` proof frames/failures/submit p95
`142 / 0 / 0.108 ms`.

Live BG3 DX11 validation
`runtime/stream-lab/local-results/local-capture-20260615-101334/` passed the
same wrapper gate with camera rotation active: source format `r10g10b10a2`,
Present `77.223 FPS`, handoff output `30.188 FPS`, output `1280x720` NV12,
NV12 frames/failures/convert avg `279 / 0 / 0.023 ms`, local `h264-mf` proof
frames/failures/submit p95/output bytes `279 / 0 / 0.108 ms / 8477308`, and no
missing evidence or failing gates.

The WebRTC source/OnFrame local boundary also turned green. The wrapper
`tools/stream-lab/run_webrtc_onframe_isolation.ps1` calls the patched
`InterGalacticGameCaptureWebrtcSourceSmoke` export, writes
`intergalactic.webrtcOnFrameIsolation.v1` reports, and links the native
capture-to-MF proof without claiming Matrix, LiveKit sender, network, or
receiver coverage. After tightening source-driven scheduling and helper
startup diagnostics,
`runtime/stream-lab/local-results/webrtc-onframe-isolation-20260615-104143/`
classified the live BG3 source smoke as `passed_webrtc_onframe_isolation`:
output `1280x720`, measured delivery FPS `29.64`, fixed-window FPS `28.2`,
native NV12 submitted/failures `279 / 0`, CPU fallback `0`, delivery queue wait
avg/max `0.027 / 0.494 ms`, `OnFrame` call avg/max `0.0027 / 0.035 ms`, and
visible proof frames present.

## Failed Live Sender Handoff Evidence

The linked live call evidence,
`stream-test-2026-06-15T15-50-03-152124Z`, confirmed the rebuilt D3D11 path
with visible/color-correct 1280x720 output, `game-d3d11-hook`, native NV12
fence policy, native NV12 failures `0`, and CPU-I420 fallback `0`, but still
landed around `11-12 FPS` with live `deliveryOnFrameCallMs` near `48 ms`
average / `276 ms` max. Because the local native-MF and source-OnFrame gates
were green, the stream-test classifier treated this shape as
`encoder_handoff_limited` with reason `live_sender_handoff_backpressure`.

The aggregate wrapper
`tools/stream-lab/run_native_sender_handoff_isolation.ps1` linked the local
native-MF report, local WebRTC source-OnFrame report, and optional live
stream-test JSON. Its 2026-06-15 analyze-only run against the latest live JSON
and the two passing local BG3 reports produced `failed_live_sender_handoff`,
which justified the dummy NV12 live-sender gate.

## Retest Gate Shift

Fresh 2026-06-15 14:26 retesting changed the immediate live-test gate. A full
stream debug build completed at
`runtime/stream-lab/debug-builds/20260615-181737/`, followed by NativeQuick
`runtime/stream-lab/debug-builds/20260615-182241/`. Focused stream-test parser
coverage for native NV12 and encoder handoff markers passed. The local
aggregate gate then failed before a new live call started:

- `native-sender-handoff-isolation-20260615-142113` failed because native
  capture-to-MF dropped to `27.515` handoff FPS / `25.4` encoder-estimated FPS,
  while local WebRTC source-OnFrame still passed at `30.108` gate FPS.
- With BG3 camera rotation active, default newest-only `1/1`
  `native-sender-handoff-isolation-20260615-142456` failed at `15.222`
  native-MF handoff FPS / `14.25` encoder-estimated FPS and `27.039` WebRTC
  source gate FPS, with native NV12 failures `0` and CPU fallback `0`.
- The guarded diagnostic `2/2` comparison
  `webrtc-onframe-isolation-20260615-142604` did not help; it fell to
  `24.482` gate FPS and showed BLT-to-ready avg/max around `44 / 602 ms`.

This evidence blocked another full BG3 call test until the BG3 native frame
readiness/ownership branch became healthy again.
