# Stream Optimization Report

Last updated: 2026-06-16
Status: current index for historical streaming evidence
Runtime owner: EXPERIMENTAL
Structure owner: DOCUMENTATION

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

## Current Streaming Boundary

The latest Live Testing Override evidence on 2026-06-16 landed the narrow
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

Residual risk: the report classifier still labels these runs
`native_nv12_ready_limited` because isolated NV12 BLT-to-ready/source-to-submit
max spikes remain visible even when average capture/encode/send are now at or
above target. The second confirmation run also showed a late-window
capture/encode wobble while send stayed near target. Keep the custom
encoded-frame path out of scope, and make the next review branch a small
report/classifier and native tail-spike follow-up rather than more SDR,
bitrate, receiver, LiveKit, queue-depth, or fallback tuning.

Live Testing Override is now closed for this branch by user direction. Treat
the two source-adapter BG3 runs as the current validation baseline, not an
active request for more live-loop iteration. Additional BG3 Smooth 720p
validation should wait until classifier/report nuance and native tail-spike
attribution are reviewed or changed.

Detailed per-run evidence for direct-BLT, fence wake, source-QPC, dummy NV12
live sender, local native-MF, WebRTC OnFrame, and failed live sender-handoff
steps is archived in
`stream-optimization-report/2026-06-15-to-16-sender-handoff.md`.

Do not use this report for RNNoise/noise-suppression tuning. AUDIO owns
RNNoise behavior and related diagnostics; EXPERIMENTAL retains gameplay
streaming, D3D11 capture, WebRTC/LiveKit video pipeline work, stream
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
