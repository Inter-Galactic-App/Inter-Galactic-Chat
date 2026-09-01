# Stream Receiver Diagnostic Contract

Owner: EXPERIMENTAL
Status: Phase 4 receiver presentation lineage diagnostics are implemented for
the in-process and external receiver probes. The contract, runner scaffold,
app-side in-process subscribe-only receiver control path, in-process
`remote_decode` frame-hash freshness tap, developer-visible in-process legacy
`remote_render` renderer-callback proof, diagnostic-only `local_preview`
frame-hash tap, external process runner gating, and the dedicated external
LiveKit/WebRTC receiver runtime are implemented. Stream-lab
automation can ingest redacted in-process probe events or launch the external
`InterGalactic.exe --receiver-probe` runtime through protected IPC and write
receiver-lab artifacts. Debug-backed live BG3 external receiver validation now
has a real LiveKit token/room pass; consumer Release builds intentionally do
not consume stream-test automation by default, so Release-package validation is
manual product smoke unless an explicit developer-enabled Release test gate is
added later.

This app-repo contract defines the receiver-side evidence required before a
gameplay streaming run can claim visual freshness. It is intentionally separate
from sender capture tuning, bitrate tuning, LiveKit server policy, TURN policy,
receiver quality policy, stream profiles, and Vulkan/DX12 work.

## Lanes

Receiver diagnostics must tag every sample with one of these lanes:

| Lane | Meaning | Validity rule |
| --- | --- | --- |
| `local_preview` | Sender track through the local preview sink and local renderer. | Diagnostic only. Smooth local preview does not prove a remote viewer is fresh. |
| `remote_decode` | True subscriber inbound RTP through remote decode or decoded-frame sink. | Valid when a separate subscriber track is attached and frame identity can be sampled without raw video content. |
| `remote_render` | Legacy event lane for decoded remote frames reaching render-side diagnostic stages. | Report callback events as `remote_renderer_callback`. Phase 4 may also emit explicit `remote_texture_ready` and `remote_ui_paint` stage events on this lane. These still do not prove Windows compositor screen presentation. |

Use marker name `intergalactic_stream_view_probe` for lane events.

## Receiver Presentation Stages

Stream-test reports must name the receiver presentation lineage with these
stage labels, even when later stages are still missing:

| Stage | Current source | Status |
| --- | --- | --- |
| `remote_decode` | `remote_decode` lane events. | Implemented. |
| `remote_renderer_callback` | Legacy `remote_render` lane events from the native renderer frame callback. | Implemented as callback proof only. |
| `remote_texture_ready` | Diagnostic `RTCVideoRenderer` texture availability observed after a renderer callback frame. | Implemented for in-process and external probes. |
| `remote_ui_paint` | Flutter paint/post-frame observer for the diagnostic renderer surface. | Implemented for in-process and external probes. |
| `remote_screen_present` | External receiver-window Flutter frame-timing callback after the diagnostic renderer surface is mounted. | Implemented as low-overhead receiver-window presentation cadence evidence. It does not prove source-linked visual-content freshness without frame lineage or receiver-window pixel analysis. |

The current hash tap plus Phase 4 surface observers can prove
`remote_renderer_callback`, `remote_texture_ready`, `remote_ui_paint`, and the
external probe-window `remote_screen_present` frame-timing stage. The
`remote_screen_present` stage proves the diagnostic receiver window is being
scheduled through Flutter presentation callbacks; it is not source-linked
visual-content freshness by itself. Receiver-window pixel analysis or
user-visible evidence may still disagree with earlier stages; that disagreement
is a presentation-lineage gap, not a reason to retune sender bitrate or hook
targets by itself.

Do not conflate receiver `frame_presentation_*` fields with
`remote_screen_present`. The frame-presentation fields are native
renderer/frame-tap interval summaries for received video frames. The
`remote_screen_present` stage and
`receiver_window_flutter_frame_gap_*` fields are external receiver-window
Flutter frame-timing observer evidence. If frame-tap presentation is red while
Flutter frame-timing p95 is healthy, classify the run as a renderer/content
cadence or measurement-path split until source-linked receiver frame IDs or a
receiver-window visual marker prove what content actually reached screen.

## Required Fields

All run output must avoid raw Matrix ids, room ids, LiveKit tokens, E2EE keys,
display names, and video content. Stable identifiers must be hashed or redacted.

| Field | Required for | Notes |
| --- | --- | --- |
| `run_id` | all lanes | Stable per test run. |
| `lane` | all lanes | One of `local_preview`, `remote_decode`, `remote_render`; `remote_render` is a legacy event lane normalized to report stage `remote_renderer_callback`. |
| `stage` | all lanes | Normalized receiver stage. Expected values are `remote_decode`, `remote_renderer_callback`, `remote_texture_ready`, `remote_ui_paint`, or `remote_screen_present`. |
| `receiverPresentationStages` | stream-test report | Report-only list of `remote_decode`, `remote_renderer_callback`, `remote_texture_ready`, `remote_ui_paint`, and `remote_screen_present` with `reported` or `missing` status. |
| `remoteRendererCallbackLaneEventCount` | stream-test report | Count of callback-lane events. Legacy `remote_render` input events are normalized into this callback metric for ingestion only. |
| `remoteRendererCallbackEventCount` | stream-test report | Count of normalized `remote_renderer_callback` presentation-stage events. This is callback proof, not screen presentation proof. |
| `latestTargetStage` | stream-test report | Normalized latest stage used for the active probe mode, for example `remote_ui_paint` when Phase 4 render-mode paint evidence is the latest event. |
| `room_hash` | all lanes | Hash only. |
| `publisher_identity_hash` | all lanes | Hash only. |
| `receiver_identity_hash` | remote lanes | Hash only; self-probe identities still count as receiver identities. |
| `track_sid_hash` | remote lanes | Hash only. |
| `track_source` | all lanes | Expected source is screenshare for gameplay streams. |
| `subscription_state` | remote lanes | Include subscribed, unsubscribed, muted, or ended. |
| `subscribed_quality` | remote lanes | Include high/medium/low/unknown. |
| `simulcast_layer` | remote lanes | Include layer id/name when available. |
| `codec` | remote lanes | Include codec name/profile when available. |
| `decoder_implementation` | remote lanes | Include hardware/software/unknown. |
| `hardware_decode` | remote lanes | Boolean or unknown. |
| `renderer_attached` | render lanes | Boolean. |
| `renderer_visible` | render lanes | Boolean. |
| `renderer_width` | render lanes | Pixel dimensions are acceptable. |
| `renderer_height` | render lanes | Pixel dimensions are acceptable. |
| `inbound_bitrate_bps` | remote lanes | Receiver-side bitrate from inbound byte deltas; `bitrate_bps` remains as the legacy alias. |
| `received_width` / `received_height` | remote lanes | Receiver stats frame dimensions from LiveKit/WebRTC when exposed. |
| `decoded_width` / `decoded_height` | remote lanes | Raw inbound-RTP decoded frame dimensions when exposed; may match received dimensions. |
| `rendered_width` / `rendered_height` | render lanes | Renderer/track frame dimensions used to detect lower-layer upscaling. |
| `receiver_fps` | remote lanes | Receiver-side WebRTC frames-per-second stat when exposed. |
| `frames_received` | remote lanes | RTP or SDK receiver counter. |
| `frames_decoded` | remote lanes | Decoder counter. |
| `frames_rendered` | render lanes | Renderer/presentation counter. |
| `received_fps` / `decoded_fps` / `rendered_fps` | remote/render lanes | Windowed FPS derived from cumulative receiver counters and wall-clock sample deltas. Prefer these over instantaneous `receiver_fps` when gating receiver quality. |
| `receiver_stats_sample_window_ms` | remote/render lanes | Wall-clock interval used to derive windowed counter FPS. Missing on the first sample is expected. |
| `*_fps_min` / `*_fps_p50` / `*_fps_average` / `*_fps_max` | receiver summary | Aggregate summary fields for event-window FPS counters. Use p50 or average to classify true low-rate receiver delivery; keep latest event FPS for tail-spike diagnosis. |
| `freshness_source` | all lanes | Must be `frame_hash_tap` before `unique_fps` can pass the receiver freshness gate. |
| `frame_hash_algorithm` | all lanes | Hash source/algorithm label, for example `sha256-png-captureframe`. |
| `frame_hash_sample_count` | all lanes | Number of frame-hash samples in the active window. |
| `frame_hash_error_count` | all lanes | Bounded count of frame-hash sampling failures; do not persist exception text. |
| `last_frame_captured_at_utc` | all lanes | Last frame-hash sample timestamp. |
| `unique_frames` | all lanes | Count from frame-hash cadence. |
| `duplicate_frames` | all lanes | Count of repeated frame hashes. |
| `unique_fps` | all lanes | Unique-frame cadence over the active sample window; gate-passing values require `freshness_source=frame_hash_tap`. |
| `p50_gap_ms` | all lanes | Unique-frame gap percentile. |
| `p95_gap_ms` | all lanes | Unique-frame gap percentile. |
| `max_gap_ms` | all lanes | Maximum unique-frame gap. |
| `frame_presentation_p50_gap_ms` | all lanes | Percentile for all native frame-tap presentation intervals, not only unique-content intervals. |
| `frame_presentation_p95_gap_ms` | all lanes | P95 for all native frame-tap presentation intervals. |
| `frame_presentation_max_gap_ms` | all lanes | Maximum all-frame presentation interval. |
| `frame_presentation_latest_gap_ms` | all lanes | Latest adjacent native frame-tap presentation interval. |
| `frame_presentation_p95_gap_ms_min` / `frame_presentation_p95_gap_ms_p50` / `frame_presentation_p95_gap_ms_average` / `frame_presentation_p95_gap_ms_max` | receiver summary | Aggregate summary of event-window presentation p95 values, used to separate healthy decoded frame rate from uneven presentation cadence. |
| `receiver_window_flutter_frame_count` / `receiver_window_flutter_frame_gap_p50_ms` / `receiver_window_flutter_frame_gap_p95_ms` / `receiver_window_flutter_frame_gap_max_ms` / `receiver_window_flutter_frame_gaps_over_50ms` / `receiver_window_flutter_frame_gaps_over_100ms` / `receiver_window_flutter_frame_gaps_over_200ms` | external receiver summary | Flutter frame-timing observer evidence for the external receiver probe window after `remote_screen_present` is wired. These fields prove receiver-window scheduling cadence, not source-linked video-content freshness. |
| `longest_stale_run_ms` | all lanes | Longest time without hash change. |
| `perceptual_difference_score` | all lanes | Hash-derived change score over adjacent sampled frames. It is a bounded perceptual proxy, not a raw image dump. |
| `native_frame_sequence` | all lanes | Latest native renderer diagnostic sequence when exposed by the patched renderer. |
| `native_frame_sequence_gaps` | all lanes | Count of missing native diagnostic sequence numbers within the active sample window. |
| `native_frame_event_delay_ms` | all lanes | Average native frame event-to-Dart receipt delay within the active sample window. |
| `native_frame_event_delay_max_ms` | all lanes | Maximum native frame event-to-Dart receipt delay within the active sample window. |
| `dropped_or_replaced_texture_updates` | all lanes | Count derived from native frame sequence gaps; `0` is meaningful evidence. |
| `stage_source` | presentation stages | Diagnostic source label for the derived stage event, for example external probe `RTCVideoView`, custom paint observer, or Flutter frame-timing callback. |
| `stage_observed_at_utc` | presentation stages | Timestamp when the texture-ready or UI-paint observer ran. |
| `stage_observed_gap_ms` | presentation stages | Gap between adjacent observations for the same stage and receiver frame lineage. |
| `stage_frame_age_ms` | presentation stages | Age of the renderer-callback frame when the derived stage was observed. |
| `stage_native_frame_sequence` | presentation stages | Native frame sequence copied from the renderer-callback event used as the frame lineage id. |
| `stage_frame_captured_at_utc` | presentation stages | Renderer-callback frame timestamp copied into the derived stage event. |
| `renderer_texture_id` | presentation stages | Diagnostic texture id for the `RTCVideoRenderer` surface; do not treat it as a stable user identifier. |
| `renderer_callback_to_stage_ms` | presentation stages | Milliseconds from the renderer callback frame timestamp to the derived texture/UI stage observation. |
| `receiver_window_flutter_frame_count` | external render summary | Flutter frame-callback count while the external receiver window is mounted. Summary-only because it describes the probe window/compositor, not a decoded video lane. |
| `receiver_window_flutter_frame_gap_p50_ms` / `receiver_window_flutter_frame_gap_p95_ms` / `receiver_window_flutter_frame_gap_max_ms` / `receiver_window_flutter_frame_gap_latest_ms` | external render summary | Flutter frame-callback cadence for the receiver probe window. Used to separate UI/compositor scheduling jank from decode/render frame-tap cadence. |
| `receiver_window_flutter_frame_gaps_over_50ms` / `receiver_window_flutter_frame_gaps_over_100ms` / `receiver_window_flutter_frame_gaps_over_200ms` | external render summary | Count of receiver-window Flutter frame gaps above visible-stutter thresholds. These are aggregate counters only and do not persist frame content. |
| `jitter_buffer_delay_ms` | remote lanes | WebRTC/SDK stat when available. |
| `jitter_buffer_emitted_count` | remote lanes | WebRTC/SDK stat when available. |
| `total_decode_time_ms` | remote lanes | WebRTC/SDK stat when available. |
| `average_qp` / `qp_sum` | remote lanes | QP is emitted only when raw inbound-RTP stats expose `qpSum`; missing QP is a coverage gap, not proof of healthy quality. |
| `key_frames_decoded` | remote lanes | Raw inbound-RTP keyframe counter when exposed. |
| `key_frames_decoded_delta` | remote lanes | Delta from the prior receiver sample. |
| `keyframe_interval_frames` | remote lanes | Approximate decoded-frame interval per keyframe when counters advance. |
| `keyframe_interval_ms` | remote lanes | Approximate wall-time interval per keyframe when counters advance. |
| `packets_received` / `packets_lost` | remote lanes | Receiver-side RTP packet counters when exposed. |
| `receiver_jitter_ms` | remote lanes | Receiver jitter converted to milliseconds when exposed. |
| `pli_count` / `fir_count` / `nack_count` | remote lanes | Receiver-side control counters. |
| `pli_delta` / `fir_delta` / `nack_delta` | remote lanes | Delta from the prior receiver sample. |
| `frames_dropped` | remote lanes | Receiver/decoder/renderer dropped frames when available. |
| `freeze_count` | remote lanes | WebRTC freeze count when available. |
| `total_freeze_duration_ms` | remote lanes | WebRTC freeze duration when available. |
| `receive_to_decode_ms` | remote lanes | Derived from inbound sample and decoded-frame timestamp when available. |
| `decode_to_render_ms` | render lanes | Derived from decoded-frame and presentation timestamp when available. |
| `upscaling_lower_layer_suspected` | render lanes | Derived flag for rendered dimensions larger than decoded dimensions. |
| `adaptive_stream_low_layer_suspected` | remote lanes | Derived flag for non-high subscription quality or non-high/non-single layer labels. |
| `sender_frame_id` | all lanes | Optional hashed or synthetic marker id only. |
| `sender_to_render_ms` | render lanes | Optional end-to-end latency when a safe marker exists. |

## Frame Hash Tap

Debug-only frame taps must avoid persisting raw video. App reports must not
persist raw frame images or raw per-frame hashes; they should emit only bounded
aggregate freshness fields unless a future dedicated synthetic proof artifact
explicitly needs per-frame debug events.

The current diagnostic `local_preview`, in-process `remote_decode`,
legacy `remote_render` / normalized `remote_renderer_callback`, and external
receiver runtime taps use an opt-in native renderer frame callback. The
callback hashes sampled Y 64x36 plus U/V 32x18 content in memory and emits only
aggregate cadence fields. Phase 4 derives `remote_texture_ready` and
`remote_ui_paint` events from the same diagnostic renderer lineage so the
external receiver window and the hash tap describe the same surface. The
receiver gate treats `unique_fps` as valid callback freshness proof only when
`freshness_source=frame_hash_tap`; a `local_preview` pass remains diagnostic and
does not prove true receiver freshness. Callback freshness plus texture/UI
observer evidence still does not prove `remote_screen_present`.

Minimum aggregate event shape:

```json
{
  "marker": "intergalactic_stream_view_probe",
  "run_id": "20260618T123000Z",
  "lane": "remote_decode",
  "sample_time_utc": "2026-06-18T12:30:00.000Z",
  "freshness_source": "frame_hash_tap",
  "frame_hash_algorithm": "sha256-png-captureframe",
  "frame_hash_sample_count": 90,
  "unique_frames": 88,
  "duplicate_frames": 2,
  "unique_fps": 29.3,
  "p50_gap_ms": 33.3,
  "p95_gap_ms": 40.0,
  "max_gap_ms": 50.0,
  "frame_presentation_p95_gap_ms": 40.0,
  "perceptual_difference_score": 0.98,
  "longest_stale_run_ms": 66.7
}
```

## Output Layout

Receiver-lab automation writes bounded output under:

```text
runtime/stream-lab/receiver-results/<run-id>/
```

Required files:

- `receiver-summary.json`
- `receiver-summary.md`
- `events.jsonl`
- `local-preview-freshness.json`
- `decoded-freshness.json`
- `rendered-freshness.json`

Optional files:

- `bounded-proof.mp4`, limited to short non-sensitive synthetic proof only.
- `true-receiver-test.json`, written by the runner wrapper.
- `true-receiver-test.md`, written by the runner wrapper.

## Classification

Use these classifications when reporting receiver-lab results:

| Observation | Classification |
| --- | --- |
| `local_preview` stale while source is healthy | Local preview sink or renderer path issue. |
| `local_preview` fresh and `remote_decode` stale | Delivery, subscription, inbound RTP, jitter buffer, or decoder issue. |
| `remote_decode` fresh and `remote_renderer_callback` stale | Renderer callback, texture handoff, or callback scheduling issue. |
| `remote_renderer_callback` fresh but `remote_texture_ready` or `remote_ui_paint` missing/stale | Inspect diagnostic renderer texture binding or Flutter paint scheduling before retuning sender bitrate or hook targets. |
| `remote_ui_paint` fresh but visible receiver output is stale | Missing or unhealthy `remote_screen_present` proof; inspect compositor/screen capture/user-visible presentation before retuning sender bitrate or hook targets. |
| `frame_presentation_*` red while `remote_screen_present` exists and `receiver_window_flutter_frame_gap_p95_ms` is healthy | Renderer/content cadence or measurement-path split. Do not call this broad Flutter/window presentation failure without source-linked frame IDs or receiver-window visual evidence. |
| Legacy `remote_render` has `renderer_visible=false` or `renderer_attached=false` | Invalid callback proof; do not pass the visual freshness gate. |
| No separate subscriber identity or subscribe-only probe | Inconclusive for true receiver freshness. |

## Implementation Status

Done in this phase:

- Contract fields and lane definitions are documented.
- The probe plan is captured in
  `docs/streaming/archive/contracts/stream-receiver-diagnostic-contract-workspace-phase1.md`.
- `tools/stream-lab/run_true_receiver_test.ps1` provides a safe runner scaffold.
- `tools/stream-receiver-probe/InterGalacticReceiverProbe.ps1` accepts a
  protected local control pipe, refuses token-like command-line arguments, and
  writes redacted receiver-lab outputs.
- `InterGalacticReceiverProbe.ps1` can now launch the rebuilt Inter Galactic
  Windows app as `InterGalactic.exe --receiver-probe`, resolve the app path
  from `-AppExe`, `INTERGALACTIC_RECEIVER_PROBE_APP_EXE`, or default build
  outputs, and relay the upstream protected IPC envelope into an app-owned
  child pipe without exposing the token through process arguments.
- The external receiver runtime starts before normal app single-instance/user
  startup, initializes the same LiveKit/WebRTC receiver probe controller,
  joins as a subscribe-only participant, publishes nothing, subscribes to the
  selected screenshare, and writes external `remote_decode` plus legacy
  `remote_render` / normalized `remote_renderer_callback` artifacts labeled
  `in_process=false` and `protected_ipc=true`.
- External render mode mounts a small inactive `RTCVideoView` receiver window
  and still requires `renderer_attached=true` plus `renderer_visible=true`
  before the renderer-callback freshness gate can pass.
- `MatrixLivekitReceiverProbeController` can be started from a developer-mode
  LiveKit call session to request the SERVER-owned short-lived probe token in
  memory, join the same LiveKit room as a distinct subscribe-only participant,
  publish nothing, subscribe to the selected screenshare at high quality, and
  emit redacted `intergalactic_stream_view_probe` events labeled
  `in_process=true`.
- In-process render-mode events are valid only when the developer-only receiver
  render surface is mounted and reports `renderer_attached=true` plus
  `renderer_visible=true`; hidden or unattached renderer events remain invalid.
- In-process decode-only and render-mode events now include a debug frame-hash
  freshness tap sourced from the native renderer frame callback. The app hashes
  sampled frame content in memory, emits `freshness_source=frame_hash_tap` plus
  aggregate cadence fields, and does not persist raw frames or raw hashes.
- Diagnostic local-preview mode attaches a debug renderer to the local
  screenshare publication after active share starts and emits `local_preview`
  frame-hash cadence events. This lane is diagnostic only and cannot satisfy
  true receiver freshness claims.
- Stream-test automation accepts an in-process receiver-probe request and stores
  the redacted event stream in each preset result. `run_true_receiver_test.ps1`
  supports `InProcessLocalPreview`, `InProcessDecodeOnly`, and
  `InProcessRender` event-ingest modes that write `receiver-summary.json`,
  `receiver-summary.md`, `events.jsonl`, `local-preview-freshness.json`,
  `decoded-freshness.json`, and `rendered-freshness.json`. Synthetic validation
  proved that a fixture with
  `remote_decode freshness_source=frame_hash_tap unique_fps=29.3` passes the
  25 unique-FPS gate, while an otherwise high-`unique_fps` fixture labeled
  `receiver_stats_frame_counter` is rejected as
  `inconclusive_frame_hash_tap_pending`.
- Phase 1 of the 2026-06-21 optimization plan keeps legacy `remote_render`
  event/status compatibility but reports the lane as
  `remote_renderer_callback` in stream-test Markdown and JSON. Reports now also
  include `receiverPresentationStages` and a Diagnostic Coverage Matrix row
  that names `remote_decode`, `remote_renderer_callback`,
  `remote_texture_ready`, `remote_ui_paint`, and `remote_screen_present`.
- Phase 4 of the 2026-06-21 optimization plan adds debug-only
  `remote_texture_ready` and `remote_ui_paint` events for the diagnostic
  receiver surface. The external receiver runtime now displays the same
  `RTCVideoRenderer` that produces native frame hashes, so its visible debug
  window, texture id, native frame sequence, and paint observer describe one
  receiver surface.
- The follow-up receiver presentation branch adds `remote_screen_present`
  events from the external receiver window's Flutter frame-timing callback.
  This is low-overhead presentation cadence evidence for the diagnostic
  receiver window, not source-linked visual-content freshness by itself.
- Synthetic local-preview validation passed in
  `synthetic-live-call-freshness-20260618-211306` with
  `freshnessEvidenceSource=local_preview_diagnostic`,
  `localPreviewFreshnessSource=frame_hash_tap`, and `30.659` unique FPS. The
  visible self-view crop in that run remained red, so `local_preview` is useful
  for diagnostics but still cannot satisfy true receiver proof.
- `run_synthetic_live_call_freshness.ps1` keeps the legacy self-view crop
  recording as a diagnostic artifact only. It no longer sets
  `freshnessEvidenceSource=local_visual_crop` and no longer passes or fails the
  run from the crop cadence.
- `run_true_receiver_test.ps1` external `DecodeOnly` and `Render` modes now
  treat the probe process as a real freshness gate. A separate probe process
  must write receiver-lane `freshness_source=frame_hash_tap` and
  `unique_fps >= MinUniqueFps` before the runner reports
  `completed_external_receiver_probe_events`; render mode also requires
  `renderer_attached=true` and `renderer_visible=true`. Timeouts terminate the
  task-owned probe process tree.
- Local external-runtime smoke validation on 2026-06-18 proved app process
  launch, protected child IPC, redacted artifact writing, external labels, and
  runner propagation with fake credentials. `external-runtime-smoke-20260618-224920`
  wrote `events.jsonl`, `decoded-freshness.json`, and
  `rendered-freshness.json` with `in_process=false` and
  `protected_ipc=true`; `true-runner-external-smoke-20260618-225004` returned
  the expected blocked gate from the fake LiveKit URL while preserving the
  external receiver status.
- Live BG3 receiver validation on 2026-06-19 proved the external render gate
  in the debug/developer harness. The Release-backed attempt
  `source-live-call-freshness-20260619-194746` joined the call but did not
  consume stream-test automation, so protected IPC stayed blocked as expected.
  The rebuilt Debug run `source-live-call-freshness-20260619-195714` passed
  `passed_source_live_call_receiver_render_freshness` with receiver
  decode/callback `freshness_source=frame_hash_tap`, unique FPS `25.042`, HIGH
  subscribed quality, `renderer_attached=true`, `renderer_visible=true`, and a
  `1280x720` receiver window placed on monitor 2. Under the 2026-06-21 stage
  vocabulary, this is renderer-callback proof, not screen-present proof.
- Receiver probe events now include quality/presentation diagnostics for the
  "30 FPS but visually grainy/stuttered" case: subscribed quality/layer,
  inbound bitrate, received/decoded/rendered dimensions, receiver FPS,
  windowed received/decoded/rendered FPS derived from cumulative counters,
  packets/loss/jitter, PLI/FIR/NACK counters and deltas, optional QP and
  keyframe intervals when raw WebRTC stats expose them, all-frame presentation
  intervals, hash-derived perceptual change score, longest stale run, native
  frame sequence gaps, dropped/replaced texture update count, and derived
  lower-layer/upscaling flags. `receive_to_decode_ms` and
  `decode_to_render_ms` remain explicit null/coverage-gap fields until safe
  frame lineage timestamps are available.
- Phase 4 synthetic external-render validation passed in
  `synthetic-live-call-freshness-20260621-144047`. The receiver summary
  reported `remote_renderer_callback=27`, `remote_texture_ready=29`,
  `remote_ui_paint=29`, and `remote_screen_present=0`, with
  `latest_target_stage=remote_ui_paint`, receiver render unique FPS about
  `30.35`, decoded FPS p50 about `30.01`, and receiver presentation p95 p50
  `48ms`.

Pending:

- Optional explicit developer-enabled Release automation if maintainers need
  automated receiver-probe proof against a Release package. Do not make the
  probe a consumer Release default.
- Product-level Release receiver smoke on a separate PC/device when release UX
  confidence is needed. This is manual product validation, not the canonical
  automated frame-hash proof gate.
- Any future call E2EE media key handoff through the same protected IPC
  boundary.

The current green receiver-callback evidence includes the debug/developer
external BG3 run above. The receiver-window screen recording from that run
remains diagnostic-only because it can undercount visual uniqueness; Phase 4
surface-stage decisions should come from receiver-lane `frame_hash_tap`
evidence with attached and visible legacy `remote_render`, normalized to
`remote_renderer_callback`, plus explicit `remote_texture_ready` and
`remote_ui_paint` stage events when present.
