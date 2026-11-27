# Streaming Guidance Status Archive

Status: historical evidence archive

This folder holds the dated closeout/evidence history that used to make up
most of `../streaming-guidance-status.md`. The top-level file now keeps only
the current decision baseline and the still-open work; read these slices when
you need the reasoning or evidence behind how that current state was reached.

## Files

Newest first:

- `2026-06-15-to-21-phase-closeouts-and-live-testing.md` - Phase 4/3/2
  receiver-presentation and sender-mailbox closeouts, CBR bitrate/smear and
  true-receiver-harness closeouts, the stream-test runner refactor, and the
  Live Testing Override / source-adapter closeouts.
- `2026-06-14-native-nv12-readiness-closeout.md` - native-NV12 GPU handoff
  validation cycle and the readiness-churn/delivery-pacer diagnosis.
- `2026-06-07-to-08-window-capture-and-native-nv12-proof.md` - native-NV12
  /WebRTC source proof closeouts and the Debug harness cycles that preceded
  them.
- `2026-06-04-to-06-black-output-debugging-and-gpu-handoff.md` - Phase
  4C/4D local encoder and WebRTC-source-handoff proof, the black-output
  debugging chain, and the Phase 3A/3B/4A/4A.5 shared-texture and
  publication-handoff probes.
- `2026-05-28-to-06-04-window-capture-backend-evolution.md` - latest-frame
  pacer promotion, the Roaming window/display backend comparison, dirty-region
  diagnostics, the window-GDI promotion, and early GPU-scaled source-handoff
  proof.
- `2026-05-31-to-06-03-native-capture-call-diagnostics.md` - native
  capture-call split, dirty-region shape, WGC substage, and GDI substage
  diagnostic additions (extracted from the "Still Needed" section, not the
  main closeout log).

## Maintenance Rules

- Add new current status to `../streaming-guidance-status.md`'s "Current
  Status" section; move it here once it stops being the newest decision
  baseline, as a new dated slice or an addition to the newest existing one.
- Keep `../streaming-guidance-status.md` as the current implementation-decision
  summary - do not let it regrow into a full chronological log.
