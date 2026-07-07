# Archived: Stream Diagnostic System Audit

Status: Archived historical milestone doc
Archived on: 2026-06-25
Superseded by:
- `../stream-diagnostic-contract.md`
- `../stream-receiver-diagnostic-contract.md`
- `../stream-bottleneck-classification.md`

Why archived:
- This was a point-in-time audit of the diagnostic system during the initial completion pass.
- The active schema, receiver contract, and classifier rules now live in stronger current docs.

Still useful for:
- diagnostic-source inventory history
- understanding what the completion pass covered
- comparing later contract changes against the original audit snapshot

---

# Stream Diagnostic System Audit

Status: Active architecture reference
Owner: EXPERIMENTAL
Last updated: 2026-06-03

This audit inventories the stream diagnostic system as of the Complete Stream
Diagnostics pass. It is intentionally limited to reporting and evidence quality;
it does not prescribe stream tuning.

## Existing Sources

| Source | Collection Path | Parser/Model | JSON Surface | Markdown Surface | Notes |
| --- | --- | --- | --- | --- | --- |
| Stream test runner samples | `StreamTestRunner.run()` samples `VoipCallDiagnosticsSnapshot` once per configured interval | `StreamTestSample`, `StreamTestSummary` | `presetResults[].samples`, `presetResults[].summary` | Summary table, per-preset details | Canonical automated sender-side stream lab. |
| Source metadata | Share target metadata passed into `StreamTestRunConfig.sourceMetadata` | `StreamTestSourceMetadata` | `config.source` | Run header, coverage matrix | Developer title is only present when supplied by selection path. |
| Requested profile/settings | `ScreenShareProfileConfig` and sender diagnostics requested fields | `_profileToJson()`, `StreamTestSummary` | `config.presets`, `summary.requested*` | Run header, summary, per-preset pipeline | Duplicated between static profile and actual sender stats; actual sender stats are preferred for evidence. |
| Sender WebRTC stats | `VoipCallDiagnosticsSnapshot.tracks` sender screenshare track | `_bestSenderTrack()`, `StreamTestSummary.fromSamples()` | `summary.*`, `samples[].tracks[]` | Summary and per-preset details | Primary source for encoded size, FPS, bitrate, quality limitation, encoder implementation. |
| Receiver WebRTC stats | Receiver screenshare tracks in `VoipCallDiagnosticsSnapshot` when present | `_bestReceiverTrack()`, `StreamTestFramePacingSummary` | `summary.framePacing.received/decoded/rendered` | Frame pacing table, coverage matrix | Often absent in sender-run reports; coverage now names the missing fields. |
| Native capture markers | Recent diagnostic log tail filtered by stream test runner | `StreamTestNativeDiagnostics.fromMarkers()` | `nativeDiagnostics`, `summary.nativeDiagnostics` | Native Diagnostic Markers table and per-preset native summary | Required for capture acquisition conclusions. |
| WGC substage markers | Native log marker `wgc frame timing` | `StreamTestNativeDiagnostics.fromMarkers()` | WGC fields inside `nativeDiagnostics` | WGC substage column and coverage matrix | Used to split WGC frame-pool, map, copy, and zero-hertz causes. |
| Window-GDI substage markers | Native log marker `window gdi frame timing` | `StreamTestNativeDiagnostics.fromMarkers()` | GDI fields inside `nativeDiagnostics` | GDI substage column and coverage matrix | Used to split Win32 window capture into PrintWindow, BitBlt, crop, and owned-window causes. |
| Dirty-region shape markers | Native frame timing marker updated-region fields | `updatedRegion*` fields in `StreamTestNativeDiagnostics` | Dirty-region fields inside `nativeDiagnostics` | Dirty Shape column and per-preset native summary | Useful for proving full-frame vs tiny/partial dirty updates. |
| Native frame pacing | Native frame cadence and latest-frame pacer markers | `StreamTestFramePacingSummary.fromNative()` | `summary.framePacing.nativeCapture` | Frame Pacing table | Important because averages previously hid visible stutter. |
| Media Foundation encoder timing | Native encoder timing markers | `StreamTestNativeDiagnostics.averageEncoderTotalMs` | Encoder timing fields inside `nativeDiagnostics` | Native Encoder column and per-preset native summary | Confirms native encoder timing separately from WebRTC aggregate encode time. |
| Network evidence | Sender WebRTC packet loss, RTT, NACK, available outgoing bitrate | `StreamTestSummary.fromSamples()` | `summary.maxPacketLossPercent`, `summary.maxRoundTripTimeMs`, `summary.maxNackCount`, bitrate fields | Summary, per-preset details, coverage matrix | Clean network evidence rules out server/network causes for many sender-side failures. |
| Bottleneck classifier | `StreamTestScore._classifyBottleneck()` | `StreamTestBottleneck` | `score.bottleneck` | Summary label, executive summary, per-preset classification | Now includes confidence, missing fields, false-cause evidence, and fixed next action. |

## Duplicated Signals

- Requested resolution and FPS exist in both profile configuration and sender
  stats. For classification, sender stats win because they prove parameters were
  applied to the actual RTP sender.
- FPS exists as instantaneous sender values and frame-counter pacing. Frame
  pacing is preferred for stability conclusions because averages can hide p95
  and max frame gaps.
- Native encoder timing and WebRTC average encode time both describe encoder
  work. Native timing is preferred when present because it isolates the Media
  Foundation path from capture acquisition.

## Unreliable Signals

- Average FPS alone is not reliable for visual smoothness; p95/max frame gaps
  and stale/duplicated frame counters must be checked.
- `qualityLimitationReason=cpu` is not sufficient by itself. It needs encode
  time, drop, send-delay, or frame-counter corroboration.
- Receiver evidence is frequently absent in sender-run logs. Reports must say
  exactly which receiver fields are missing rather than implying the sender
  report proves receiver rendering.

## Missing Or Unavailable Signals

- Loaded `libwebrtc` path/hash is not exposed in stream-test JSON today. The
  coverage matrix marks this as `unavailable`.
- Receiver subscribed layer and adaptive-stream reason are not always available
  in stream-test runs. Coverage marks receiver fields as missing when absent.
- Native p50 frame intervals are not currently parsed; p95/max are available and
  remain the primary stutter evidence.
- Full Media Foundation substage details such as queue depth and async state are
  only partially available; aggregate native encoder timing exists.

## Current Completion State

The runner now emits a diagnostic coverage matrix in JSON and Markdown, and each
bottleneck result includes confidence, missing evidence, evidence against common
false causes, and one fixed recommended next action. New one-off stream logs
should not be added unless the diagnostic contract identifies a blocking missing
field and the parser/report surfaces are updated in the same pass.
