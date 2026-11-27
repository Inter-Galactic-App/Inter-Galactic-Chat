# May 31 - June 3 Native Capture-Call Diagnostics

Date range: 2026-05-31 to 2026-06-03

Dated evidence history extracted from the "Still Needed" section of `../streaming-guidance-status.md` (item 1, Full Per-Stage Frame Pacing Evidence). Covers the native capture-call split, dirty-region shape, WGC substage, and GDI substage diagnostic additions.

---

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
