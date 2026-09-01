# Stream Optimization Report Archive

Status: historical evidence archive
Last reviewed: 2026-06-16

This folder contains dated slices extracted from
`../stream-optimization-report.md` so agents can read only the evidence window
they need. The top-level report remains the current index and routing document.

## Files

- `2026-06-15-to-16-sender-handoff.md` - sender handoff, dummy NV12 live
  sender, source-adapter, direct-BLT, fence-wake, and native-tail evidence.
- `2026-06-14-native-nv12-freshness.md` - latest native NV12 freshness,
  readiness-policy, bounded-pending, and latest-frame queue evidence.
- `2026-06-13-game-capture-contract.md` - game-capture contract, host-load,
  and backpressure diagnostics.
- `2026-06-08-to-11-native-nv12-handoff.md` - native NV12 acceptance,
  first-frame, and source/readback proof evidence.
- `2026-06-07-phase-4-source-delivery.md` - Phase 4 source delivery and
  stale-readback validation evidence.
- `2026-06-04-to-05-source-handoff.md` - local source handoff, helper
  lifecycle, and GPU-scale evidence.
- `2026-06-02-to-03-window-gdi-wgc.md` - Window GDI, WGC, and
  capture-attribution evidence.
- `2026-05-20-to-31-capture-validation.md` - capture-call split, windowed BG3,
  and pacer validation evidence.
- `2026-05-02-to-06-hardware-encoder.md` - early hardware encoder, libwebrtc,
  RNNoise, and limiter tuning evidence.
- `2026-05-11-to-20-stream-lab-cadence.md` - stream-lab, backend switch,
  cadence, and window geometry evidence.

## Maintenance Rules

- Add new current evidence to the newest dated archive or create a new dated
  slice instead of growing the top-level index.
- Keep `../streaming-guidance-status.md` as the current implementation-decision summary.
- Keep RNNoise/noise-suppression tuning in AUDIO-owned docs such as
  `../media-and-plugins.md`, `../RNNOISE_TUNING_BASELINE.md`, and
  `../rnnoise-native-resampler-plan.md`.
