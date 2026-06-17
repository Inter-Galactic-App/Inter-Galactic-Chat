# 2026-06-07 Phase 4 Source Delivery Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-07 Phase 4K Live Harness Loop And Wake-On-Ready Delivery

The full recovered internal work log for this loop remains in the private
workspace archive. This public section keeps only the durable
architecture/evidence summary.

- Maintainer-approved live-testing automation ran the Debug app, triggered the
  configured call-room hotkey, wrote stream-test requests, focused BG3, rebuilt
  native libwebrtc, and repeated without waiting for manual validation.
- The first loop confirmed the previous aggregate "clean enough" interpretation
  was false. Effective `1280x720@30` sender stats, GPU scaling, hardware H.264,
  network, and LiveKit-facing metrics could all look healthy while native
  source-to-submit latency and frame repeats still produced visible jitter.
- Retained native fix: the D3D11 game-hook WebRTC delivery thread now wakes
  when a ready frame is queued and submits the newest queued frame. This removed
  the artificial delivery FIFO delay: final reports show `queueWait` max under
  1 ms instead of roughly 32-132 ms in earlier runs.
- Rejected variants:
  - `60fps` helper feed with every hook frame submitted to readback flooded the
    async readback path and repeated roughly 95-99% of submitted frames.
  - `45fps` and `36fps` helper feeds reduced repeats but introduced stale
    readback pressure, source regressions, and latency/stale drops.
  - `60fps` helper feed with WebRTC-side source pacing avoided readback flood
    but only queued about 23-24 fresh frames and filled the rest with repeats.
- Final restored confirmation report
  `stream-test-2026-06-08T00-13-36-295380Z.json` was not clean. Smooth,
  Balanced, and High Quality all stayed at `1280x720@30`, `gpuScaled>0`,
  `gpuScaleFailures=0`, `cpuFallback=0`, clean network, and hardware H.264, but
  still classified `frame_pacing_unstable` with native delivery gaps around
  107-125 ms and source-to-submit spikes around 111-156 ms.
- Trial matrix:
  - `depth2-all-presets`: delivery queue depth `4 -> 2`; improved queue wait to
    ~32-66 ms but left ~5.6-8.3% repeats and ~180 ms source-to-submit spikes.
  - `freshhook-all-presets`: helper `60fps` feed plus newest queued delivery;
    flooded readback and repeated ~94.5-98.6%.
  - `newest-ready-all-presets`: newest-ready readback with `60fps` feed; still
    flooded map attempts and repeated ~90-99%.
  - `wake-ready-all-presets`: helper feed restored to `30fps`; delivery wait
    predicate now wakes on queued frames. This was the useful improvement:
    queue wait under 1 ms and repeats around ~1.2-1.9%, but max native gaps
    remained ~104-109 ms.
  - `hook45-all-presets` and `hook36-all-presets`: extra helper-feed headroom
    reduced repeats but created stale readback pressure, source regressions, or
    latency/stale drops.
  - `block-prevmap-all-presets`: blocking map for non-latest readbacks reduced
    stale/latency drops but did not solve max delivery/source-to-submit gaps.
  - `bg3focused-block-prevmap-all-presets`: focusing BG3 did not remove native
    gaps, so the automated harness focus state was not the root cause.
  - `hook60-sourcepacer-*` and `hook60-wallpacer-*`: WebRTC-side source pacing
    with a `60fps` helper feed kept GPU readback bounded but queued only
    ~23-24 fresh frames and repeated ~20-24%.
  - `restored-wake30-confirm-all-presets`: final restored best path; still not
    clean, but better than the rejected branches.
- Conclusion: the next implementation should not tune bitrate, LiveKit,
  fallback, or another cadence constant. The remaining limiter is the native
  game-hook CPU-readback/source-to-submit path. Next useful work is either
  p95/native-stage proof that separates source-present stalls from readback
  readiness, or Phase 4 GPU texture/NV12 handoff to avoid BGRA readback plus
  CPU I420 conversion for every WebRTC frame.

## 2026-06-07 Phase 4J Stream Harness Late-Window Diagnostics

- The follow-up Debug run changed the immediate next step: Smooth was visually
  good at the start but jittered near the end, while Balanced remained poor.
  That means aggregate FPS and one final native counter set are not sufficient
  to treat the harness as equivalent to a manual visual run.
- Latest user reports still showed the issue was not broad network/LiveKit
  capacity or CPU fallback. Smooth averaged about `26 FPS` with p95/max sent
  gaps around `48-49 ms`, while Balanced averaged about `17 FPS` with sent
  p95/max around `214/350 ms`. Both kept `gpuScaled > 0` and `cpuFallback=0`;
  Balanced accumulated hundreds of readback latency/stale drops.
- The stream-test runner now keeps per-preset native markers in the scoring
  path and exports `timeWindows` for each preset: early, middle, late, and
  `tail_10s`. Each window reports sampled capture/encode/send/receiver pacing
  plus D3D11 game-hook counter deltas such as submitted frames, GPU scale, CPU
  fallback, readback ready/not-ready, stale drops, latency drops, source-frame
  regressions, source gaps, and max queued readback latency.
- Markdown reports now include a `Time-Window Degradation` section above raw
  native markers. If the early window is acceptable but the late/tail window
  loses FPS, grows p95/max gaps, or accumulates readback pressure, the run is
  treated as `frame_pacing_unstable` rather than relying on a manual note that
  the stream looked worse later.
- This was a diagnostics/reporting pass only. It did not change stream
  profiles, bitrate, LiveKit publish options, fallback thresholds, or native
  capture behavior.
- Validation passed outside the sandbox with workspace-local AppData:
  focused `stream_test_runner_test.dart` and targeted Flutter analyze for the
  touched runner/test files.

## 2026-06-07 Phase 4I Stale-Readback Prune and D3D11 FPS Cap

- Fresh Debug captures after the Phase 4H build showed the visual stream was
  still not healthy. Smooth and Balanced both classified as
  `frame_pacing_unstable`; representative reports showed capture/encode/send
  around `23-26 FPS` for Smooth and as low as `13 FPS` for a batch Balanced
  run, with p95/max sender gaps reaching about one second in the worst
  Balanced samples.
- The failure was still upstream of network/LiveKit/receiver behavior:
  `gpuScaled` stayed nonzero, `gpuScaleFailures=0`, `cpuFallback=0`, native
  Media Foundation encoder timings stayed fast, loss/RTT/NACK evidence stayed
  clean, and `qualityLimitationReason` did not explain the visible freezes.
  The active bad counters were `source_frame_regression_drop`,
  `sourceFrameRegressions`, `readbackLatencyDropped`, and large p95/max frame
  gaps.
- Interpretation: the readback ring could still map or select a pending scaled
  readback whose source frame had become older than the most recently submitted
  frame. The source-frame regression guard prevented visible backward motion,
  but it did so by dropping frames repeatedly, which matches the user's
  stutter/freeze report.
- Native libwebrtc now discards pending scaled readbacks older than
  `last_submitted_source_frame_index_` before mapping them, and when multiple
  readbacks are ready it selects the newest source frame rather than relying
  only on ring sequence order. The final source-regression guard remains as a
  safety check, but should no longer be a normal path.
- The D3D11 game-hook publish path now also applies a backend-specific cadence
  compatibility rule: Smooth/Balanced keep their resolution, bitrate, codec,
  and single-layer hardware profile, but clamp the old `36 FPS` sender/capture
  headroom to the true `30 FPS` scoring target. This avoids asking the async
  readback source for `@36` when the intended stream is `30 FPS`.
- Validation performed before asking for another live run:
  native `libwebrtc` rebuilt successfully, the patched artifact was
  refreshed/installed with ZIP SHA-256
  `D9A785289796396D7FF168C1A6970BA03F8170E526CCE36C8C66BF751AC4A465`, Windows
  Debug rebuilt successfully with runner `libwebrtc.dll` SHA-256
  `BD2C1579F7E5878A39D05641F0D10527D31C00CB02D6A3F7A5EBA2E0756245A1`, focused
  `screen_share_quality_profile_test.dart` passed, and targeted Flutter
  analyze found no issues.
- Next validation should be one Smooth `720p30` BG3 D3D11 game-hook stream
  test first. Expected proof is `fps=30` in the capture request, near-zero
  `sourceFrameRegressions`, low `readbackLatencyDropped`, and clean p95/max
  gaps. If the stream still looks bad while reports look clean, the next fix is
  diagnostic coverage/report accuracy, not bitrate or LiveKit tuning.

## 2026-06-07 Phase 4H Latest-Ready Readback Delivery Validation

- The user suspected the first of two BG3 tests was the wrong selection and
  asked whether it left processes open before judging the second, almost
  frozen run. Process checks found no lingering
  `InterGalacticGameCaptureHelper` or capture target; only BG3 and the Debug
  app were still running. Both reports also logged helper cleanup, so the
  second run was not contaminated by a stale hook process.
- The second report showed a real native delivery failure shape:
  capture/encoded/sent frame gaps were about `1034/1066/1090 ms`, while the
  native game-hook source still reported `source=2560x1440`,
  `output=1920x1080`, `fps=29.64`, `copied=1793`, `gpuScaled=226`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `readbackQueued=966`,
  `readbackReady=226`, `readbackNotReady=1664`, and
  `readbackLatencyDropped=739`.
- Interpretation: BG3 was presenting, helper copy was active, GPU scale was
  active, and CPU fallback was not the limiter. The WebRTC source was waiting
  behind old staging-readback slots and discarding most pending work before it
  could reach the sender. This is readback delivery pressure, not a source
  present-rate limit, bitrate collapse, LiveKit downgrade, or stale helper
  lifecycle issue.
- Native libwebrtc now scans the readback ring for the newest ready scaled
  frame, drops stale pending slots, and allows a small three-frame latency
  window instead of head-of-line waiting on the oldest staging slot. The stream
  runner now classifies copied-frame surplus plus GPU-scale success plus
  readback delivery pressure as `frame_pacing_unstable` with recommended next
  action `fix frame pacing`, rather than source-present limited.
- Post-patch BG3 Smooth at `1280x720` is the current known-good control:
  capture/encode/send were about `29.9/30.0/30.0 FPS`, encoded size was
  `1280x720`, p50/p95/max gaps were about `33/34/34 ms`,
  `gpuScaled=1055`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackLatencyDropped=0`, `sourceFrameRegressions=0`,
  `sharedSlotMismatches=0`, `0.0%` loss, about `3 ms` RTT, and
  `qualityLimitationReason=none`.
- Post-patch BG3 Balanced at `1920x1080` no longer freezes at the native
  boundary: native capture/readback reported about `29.7 FPS`,
  `gpuScaled=1043`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackLatencyDropped=0`, and clean source-order counters. The remaining
  issue is later in the sender/WebRTC encode path: encoded/sent FPS landed
  around `24.7`, encoded/sent p50/p95/max gaps were roughly `34/93/342 ms`,
  WebRTC average encode time was about `49 ms`, and send queue delay was about
  `85 ms`, while the native Media Foundation encoder marker stayed fast at
  roughly `2.9 ms` average / `7.8 ms` max. The next pass should test 1080p
  sender pacing and bitrate floor/cap pressure before changing broader
  capture behavior.
- Validation artifacts:
  - Frozen report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T14-49-40-653075Z.md`
  - Post-patch Balanced report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T15-05-07-369696Z.md`
  - Post-patch Smooth report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T15-07-45-284639Z.md`
  - Refreshed patched `libwebrtc.zip` SHA-256:
    `CE940A479B9F0942DF1CA9F3E42F31E8C71D1BEF075AC2E207FFA47A12316EFF`

## 2026-06-07 Phase 4G Duplicate Source-Tick Skip Validation

- EXPERIMENTAL rebuilt the patched Windows libwebrtc artifact and Debug app
  after changing the D3D11 game-hook WebRTC source to skip duplicate source
  ticks instead of resubmitting the last frame. Duplicate ticks still drain any
  ready GPU readback so a real frame already in flight is not stranded.
- The prior BG3 Smooth run in the same busy 2K scene showed the failure shape:
  `submitted=1268`, `repeated=212`, `sourceFrameDuplicates=212`,
  `gpuScaled=1268`, `gpuScaleFailures=0`, `cpuFallback=0`, and clean
  transport/encoder stats. That made the visible rubber-band/stutter likely to
  be repeated stale-frame injection rather than network, encoder, scaling, or
  source-frame regression.
- After the duplicate-skip patch, BG3 Smooth at `1280x720` reported
  `repeated=0`, `duplicateSkipped=217`, `sourceFrameDuplicates=0`,
  `sourceFrameRegressions=0`, `sharedSlotMismatches=0`, `gpuScaled=1051`,
  `gpuScaleFailures=0`, `cpuFallback=0`, and p50/p95/max capture, encoded, and
  sent gaps of about `33/35/35 ms`. The report classified healthy with
  capture/encode/send all about `29.8 FPS`, `0.0%` loss, about `2 ms` RTT, no
  quality limitation, and single-layer hardware H.264.
- BG3 Balanced at `1920x1080` also classified healthy: capture/encode/send
  about `29.8 FPS`, p50/p95/max gaps about `34/35/35 ms`,
  `gpuScaled=1046`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `sourceFrameDuplicates=0`, `sourceFrameRegressions=0`, clean network, and no
  WebRTC quality limitation. This meets the current sender-side release target
  of stable `1080p30` for the D3D11 hook path.
- BG3 High Quality requested `1920x1080@60` but the hook only saw about
  `30.1` unique BG3 presents in this scene. The source skipped roughly one
  duplicate tick for every submitted frame (`duplicateSkipped=1056`,
  `repeated=0`, `sourceFrameDuplicates=0`) and kept clean `33/34/34 ms`
  capture/encode/send pacing at about `30 FPS`. The stream runner now parses
  `duplicateSkipped` and classifies this case as source-present limited instead
  of a generic capture-backend failure.
- Validation artifacts:
  - Smooth report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T14-06-18-582247Z.md`
  - Balanced report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T14-08-10-254763Z.md`
  - High Quality report:
    `<local-log-path>\stream-tests\stream-test-2026-06-07T14-10-48-262574Z.md`
  - Refreshed patched `libwebrtc.zip` SHA-256:
    `A9FA5DF0C51C7DABA093C151A99BAE1841C3829CDA01A9FD348E7400F9BB9758`
  - Native `libwebrtc.dll` SHA-256:
    `D3C3ADA7C30ED03DF5904F64C64971BDB77B51D07572CD54A8F65C9ABA414BD3`
- Remaining evidence gap: these are sender-side harness results. A final visual
  receiver smoke is still useful, but user validation should start from
  Balanced `1080p30` using the rebuilt Debug app and the D3D11 game-hook
  backend.

## 2026-06-05 Phase 4F Post-Live Evidence Review

- Maintainer-approved live-testing automation ended after
  `stream-test-2026-06-05T23-52-31-028657Z`. The user's call-room hotkey
  persistence fix was confirmed, but the BG3 Smooth 720p D3D11 hook stream
  still visibly rubber-banded while walking.
- The latest run proves the failure is no longer black output, color, crop,
  GPU-scale fallback, encoder choice, bitrate, packet loss, RTT, or LiveKit
  downgrade. The stream used `game-d3d11-hook`, source `2560x1440`, output and
  encoded `1280x720`, hardware `MediaFoundationH264`, `qualityLimitationReason`
  `none`, about `2.7 Mbps` sent bitrate, `0.0%` loss, about `3 ms` RTT, and
  `0` NACKs. Proof frames and I420 proof frames were visible.
- The active evidence is frame pacing inside the debug WebRTC game-hook source:
  `gpuScaled=2215`, `gpuScaleFailures=0`, `cpuFallback=0`,
  `readbackQueued=2351`, `readbackReady=2215`, `readbackNotReady=561`,
  `readbackLatencyDropped=133`, average readback latency about `79 ms` /
  `2.0` queued frames, max readback latency `3` frames,
  `sourceFrameRegressions=0`, and `sharedSlotMismatches=0`. Capture/encode/send
  averaged roughly `34.0/32.8/32.8 FPS`, but encoded/sent p95 and max gaps were
  about `41/57 ms`, with minimum sampled FPS at `10`.
- Interpretation: the previous fix prevented submitting frames more than two
  queued readbacks stale, but the WebRTC source still lives near that latency
  ceiling during live BG3 motion. Dropping 133 stale readbacks is better than
  showing older ordered frames, but it can still create visible hiccups. The
  current symptom is therefore stale-latency pressure / presentation cadence,
  not source-frame regression; the report shows no explicit backwards index.
- OBS comparison:
  - OBS D3D11 game capture hooks Present and uses a capture interval in the
    hook (`graphics-hook.h::frame_ready`, `game-capture.c::reset_frame_interval`)
    so it does not capture every game Present when the output target is lower.
  - OBS's normal D3D11 shared-texture path copies/resolves the backbuffer into a
    shared GPU texture (`d3d11-capture.cpp::d3d11_copy_texture`,
    `d3d11_shtex_capture`) and opens/uses that shared texture on the OBS render
    side (`game-capture.c::init_shtex_capture`). It does not require a
    continuous staging `Map` + CPU I420 conversion before the compositor sees
    the frame.
  - OBS keeps a shared-memory fallback with two texture buffers and nonblocking
    mutex selection (`copy_shmem_tex` / `try_lock_shmem_tex`), but that is not
    its preferred GPU texture path.
- Current Inter Galactic difference: the debug WebRTC source still performs GPU
  scale to BGRA, copies into an output-sized staging readback slot, maps with
  `D3D11_MAP_FLAG_DO_NOT_WAIT`, converts to I420 on CPU, then calls WebRTC
  `OnFrame`. The per-frame `mapMs` and `convertMs` are small, but the async
  readback queue remains about two frames behind under live pressure. OBS
  suggests the durable fix direction should move toward a GPU-texture/NV12
  handoff to the encoder or WebRTC pipeline, or an OBS-like latest-frame GPU
  consumer boundary, instead of continuing to tune the staging-readback queue.
- Separate user-facing issue discovered during validation: the custom
  call-room hotkey now persists and joins the call after restart, but the call
  room view does not refresh after the auto-join. This looks like an app-side
  room/call membership timing or event refresh issue, not a blocker for stream
  testing, and is tracked separately from the game-hook pacing issue.

## 2026-06-05 Phase 4E Frame-Order And Source Pacing Guard

- The user reported a new visual failure after the prior Smooth 720p report
  classified healthy: camera spins occasionally appeared to rubber-band
  backward. That symptom is not explained by bitrate, encoder timing, packet
  loss, RTT, or LiveKit quality selection. It points at stale or out-of-order
  source frame submission inside the debug D3D11 game-hook handoff.
- Native libwebrtc now carries the hook source frame index and source QPC
  through the async GPU readback slot, validates that
  `latest_slot_index` still contains `latest_frame_index`, drops regressing
  source frames before WebRTC submission, and reports
  `sourceFrameIndex`, `lastSubmittedSourceFrameIndex`,
  `sourceFrameRegressions`, `sourceFrameDuplicates`, `sourceFrameGaps`, and
  `sharedSlotMismatches` in `game_capture_webrtc_source` stats. The hook also
  flushes after copying into the shared texture ring when any external WebRTC
  shared-state consumer is active, not only when the helper host-consumer mode
  is enabled.
- The WebRTC source pacing loop now advances from the scheduled due time
  instead of `now + interval` after late wakes. The previous behavior could
  compound small wake delays into permanent cadence drift. Exact local source
  smoke improved from `submitted=207` to `submitted=288` over a 10-second
  synthetic 30 FPS run while keeping `gpuScaled=288`, `cpuFallback=0`,
  `readbackNotReady=0`, `readbackOverwritten=0`,
  `sourceFrameRegressions=0`, and `sharedSlotMismatches=0`.
- The 2K boundary was also validated locally: a synthetic `2560x1440` source
  capped to `1280x720@30` produced `submitted=288`, `gpuScaled=288`,
  `gpuScaleFailures=0`, `cpuFallback=0`, `readbackReady=288`,
  `readbackNotReady=0`, `readbackOverwritten=0`,
  `sourceFrameRegressions=0`, `sharedSlotMismatches=0`,
  `visibleProofFrames=2`, and `visibleI420ProofFrames=1`. Report:
  `{LOCAL_STREAM_LAB_RESULTS_DIR}\webrtc-source-smoke-20260605-2k-to-720-frame-order-pacing\webrtc-source-smoke.json`.
- Current validation artifacts: patched `libwebrtc.zip` SHA-256
  `A545101DE38EB453ADE331CFDE642C9F00E6CAF0586C0CE897F27D19B214E805`;
  native build, workspace Flutter WebRTC cache, and rebuilt Debug runner
  `libwebrtc.dll` SHA-256
  `1C5C87E4ED617E6E8557BA3534A2DC4C2576A13415E43745DCDAA73C26265556`.
  Next validation should be one Smooth 720p BG3 camera-spin test with the
  `game-d3d11-hook-experimental` backend. Success requires visually no
  backward rubber-band, `sourceFrameRegressions=0`,
  `sharedSlotMismatches=0`, nonzero `gpuScaled`, and `cpuFallback=0`.
