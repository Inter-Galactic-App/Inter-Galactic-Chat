# June 14 Native NV12 Readiness Closeout

Date range: 2026-06-14

Dated closeout history extracted from `../streaming-guidance-status.md`. Covers the June 14 native-NV12 GPU handoff validation cycle: build hashes, live BG3 stream-test evidence, and the readiness-churn/delivery-pacer diagnosis that carried into the June 15 source-adapter work.

---

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
  `sourceToSubmit` max `285.1 ms`. The flush test patch was backed out
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
- The next implementation decision should be reviewed before another live cycle:
  compare R10G10B10A2 versus 8-bit/SDR source-format behavior, prototype a
  WebRTC native encoder `OnFrame` handoff change, or accept a guarded
  ready-frame buffering tradeoff. The explicit D3D11 `Flush` branch should not
  be restored based on the current evidence.
- This is not a non-developer production default. Explicit consent, unsupported
  target messaging, security review, and broader API support are still required
  before making game capture a normal user-facing mode.

