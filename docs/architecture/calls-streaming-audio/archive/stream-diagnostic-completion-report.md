# Archived: Stream Diagnostic Completion Report

Status: Archived historical milestone doc
Archived on: 2026-06-25
Superseded by:
- `../stream-diagnostic-contract.md`
- `../stream-receiver-diagnostic-contract.md`
- `../stream-bottleneck-classification.md`

Why archived:
- This was a milestone completion report for the first formal stream-diagnostics pass.
- The active contract and classifier docs now carry the durable contributor-facing guidance.

Still useful for:
- milestone closeout history
- validation scope from the completion pass
- comparing the original contract rollout against later changes

---

# Stream Diagnostic Completion Report

Status: Implementation report
Owner: EXPERIMENTAL
Last updated: 2026-06-03

## Summary

The stream diagnostic system now has a formal architecture contract, an audit of
existing sources, explicit bottleneck evidence rules, and additive JSON/Markdown
coverage reporting in the stream-test runner. This pass did not change bitrate,
profiles, fallback thresholds, backend defaults, LiveKit settings, or native
capture behavior.

## Sources That Exist

- Stream-test runner samples from `VoipCallDiagnosticsSnapshot`.
- Sender WebRTC stats for requested/encoded size, FPS, bitrate, quality
  limitation, codec, encoder implementation, and hardware encode state.
- Native capture markers for backend, source/content/pre-encode geometry,
  capture cadence, p95/max frame gaps, dirty-region shape, WGC substages,
  window-GDI substages/method validity, and latest-frame pacer evidence.
- Native capture-cause attribution derived from parsed markers, covering source
  acquisition size, blocking acquire wait, CPU readback/copy, dirty-region
  processing, frame lifetime/lock synchronization, and full-frame copy before
  downscale.
- Native Media Foundation H.264 timing markers.
- Receiver frame pacing when receiver stats are present in the same run.
- Network evidence from packet loss, RTT, NACK, and available outgoing bitrate.

## Schema Defined

`stream-diagnostic-contract.md` defines the canonical sections:

- Session metadata
- Requested settings
- Actual sender settings
- Native capture
- WGC backend substages
- Window-GDI backend substages
- Dirty-region shape
- Frame pacing
- Encoder
- Receiver
- Network/SFU

New stream instrumentation must update the contract, parser, JSON, Markdown, and
coverage matrix in the same pass.

## Report Coverage Now Shows

The stream-test JSON now includes `diagnosticCoverage` at run level, preset
result level, and preset summary level. Markdown reports now include:

- Executive summary
- Diagnostic Coverage matrix
- Capture Cause Attribution matrix
- Classification and confidence
- Missing evidence
- Evidence for the bottleneck
- Evidence against common false causes
- Fixed recommended next action

Coverage statuses are `available`, `missing`, `unavailable`, and
`notApplicable`.

## Formalized Labels

The classification contract formalizes source selection, no-sent-frame,
geometry, crop/stretch, native capture, WGC substage, dirty-region, frame
pacing, encoder, sender adaptation, receiver, network/SFU, healthy, and
`insufficient_evidence` labels. The current runner implements the additive
reporting fields for its existing labels and now uses `insufficient_evidence`
instead of generic `unknown` when it cannot prove a cause.

## Fields Still Unavailable

- Loaded `libwebrtc` artifact path/hash in stream-test reports.
- Native p50 frame interval.
- Full Media Foundation encoder substage breakdown and queue depth.
- Receiver subscribed-layer reason in sender-only test runs.
- SFU/server-side evidence unless collected separately.

## New Instrumentation

The original Complete Stream Diagnostics pass did not add native probes or
stream behavior changes. The 2026-06-03 follow-up added one contracted native
probe for observed `window-gdi` captures only: `Inter Galactic window GDI frame
timing`. Reports parse it into JSON/Markdown and coverage rows without changing
bitrate, presets, fallback thresholds, backend defaults, LiveKit settings, or
native capture behavior.

The later 2026-06-03 capture-cause pass added a native wrapper timer around
updated-region analysis and a report-level attribution matrix. This remains a
diagnostics-only change: it does not change stream profiles, backend policy,
capture scheduling, dirty-region mode, fallback thresholds, or LiveKit
behavior.

The next 2026-06-03 window-GDI method-comparison pass extended the existing
window-GDI probe with requested/applied capture mode, final frame producer
counts, and black/low-variance frame counts. Stream tests can cycle current
full-content `PrintWindow`, plain `PrintWindow`, `BitBlt` first, and
`BitBlt` only for window sources. This is still diagnostics-only and exists to
prove whether a faster method also produces valid frames before any default
capture-path change is considered.

## How To Interpret Future Reports

1. Read the Executive Summary first.
2. Check Diagnostic Coverage before trusting a bottleneck label.
3. If the label is `insufficient_evidence`, collect the named field only.
4. If native capture is classified with high confidence and network/encoder
   evidence is clean, focus work on capture backend/WGC/dirty-region/frame
   pacing before touching bitrate or profile values.
5. Use Capture Cause Attribution to choose the next native target: source
   acquisition, acquire wait, readback/copy, dirty-region processing,
   frame-lifetime/sync, or pre-downscale full-frame copy.
6. For window-GDI comparisons, require final producer counts plus
   black/low-variance frame counts before treating a faster method as viable.
7. Do not add one-off logs; update the contract and parser if a required field
   is truly missing.

## Validation

Completed validation:

- `dart format` on `stream_test_runner.dart` and
  `stream_test_runner_test.dart`.
- `flutter test intergalactic/test/client/components/voip/stream_test_runner_test.dart --no-pub`.
- `flutter analyze` on the touched stream runner and focused test files.

Focused tests cover:

- Coverage matrix JSON and Markdown output.
- Coverage statuses for available, missing, unavailable, and not applicable
  categories.
- High-confidence `native_capture_limited` with native cadence plus fast native
  encoder evidence.
- Missing receiver render FPS as exact missing evidence.
- `insufficient_evidence` replacing generic `unknown` when a cause cannot be
  proven.
- Recommended next action constrained to the fixed action set.

Historical local stream-test JSON reports were inspected from developer-local
report directories, including recent 2026-06-02 reports. The runner does not
currently include a reverse
importer that rehydrates old JSON into `StreamTestRunResult`, so historical
validation for this pass is represented by focused synthetic tests based on the
same BG3 window, WGC, DirectX, display, zero-frame, and resolution-mismatch
shapes seen in local reports. A historical importer remains a future optional
tool, not a requirement for the runtime report contract.

## Remaining Gaps

- Add build/libwebrtc hash to reports if it becomes necessary to distinguish
  stale artifacts from runtime behavior.
- Add a historical-report importer only if future work needs to re-render old
  JSON reports with the latest classifier.
- Add receiver-side stream-test coordination when a second participant is
  available; sender-only reports should continue to mark receiver evidence as
  missing.
