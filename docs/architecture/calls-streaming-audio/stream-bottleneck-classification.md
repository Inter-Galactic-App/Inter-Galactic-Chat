# Stream Bottleneck Classification

Status: Active architecture contract
Owner: EXPERIMENTAL
Last updated: 2026-06-16

Every stream-test bottleneck label must be evidence-based. If the required
fields are missing, reports must emit `insufficient_evidence` and list the exact
missing fields.

Recommended next action must be one of:

- `fix source selection`
- `fix geometry/scaling`
- `fix capture backend`
- `fix WGC substage`
- `fix window-GDI substage`
- `fix game-capture handoff`
- `fix dirty-region behavior`
- `fix frame pacing`
- `fix encoder path`
- `fix receiver subscription/rendering`
- `inspect server/network`
- `collect one specific missing field`
- `no stream change recommended`

## Label Rules

| Label | Positive Evidence | Rules Out | False Positives | Required Fields | Confidence | Next Action |
| --- | --- | --- | --- | --- | --- | --- |
| `source_selection_failed` | Share start fails before sender stats or selected source metadata is invalid | Valid source metadata and sender stats | User canceled source picker | Source type/hash, start error | High with explicit error | `fix source selection` |
| `source_rebind_failed` | Existing share cannot restart/rebind after source/window changes | Fresh share succeeds with same source | Window minimized/closed by user | Source id, rebind error, sender stats before/after | Medium to high | `fix source selection` |
| `no_sent_frames` | No sender screenshare stats or sent frames are collected | Sender stats with frames sent | Receiver hidden while sender is healthy | Sender track stats, frames sent | Medium unless runner error explains it | `fix source selection` |
| `livekit_publish_pre_event_limited` | Stream-test start fails with `publishVideoTrack` timeout before `LocalTrackPublishedEvent` / local publication and before sender stats or native WebRTC source startup markers are available | Source selection, D3D11 hook attach, helper ring readiness, track creation, post-publish sender limits, receiver/SFU policy, and encoder `not_accepting` as the first boundary | Slow first negotiation can complete if bounded; require the explicit pre-event publish timeout and no active share before classifying | Stream-test error text containing `publishVideoTrack` and `stage=publishVideoTrack_pre_event`; local publication event absent; sender stats absent | High with explicit timeout | `fix game-capture handoff` |
| `resolution_limit_not_applied` | Encoded size exceeds requested cap beyond tolerance | Encoded size fits requested cap | Letterboxed canvas may be larger than content | Requested and encoded size, pre-encode size | High | `fix geometry/scaling` |
| `geometry_or_canvas_invalid` | Content/canvas/source sizes contradict expected contain-fit rules | Content fits canvas and crop=false | Letterbox/pillarbox with exact content size | Source, content, canvas, pre-encode, crop flag | Medium to high | `fix geometry/scaling` |
| `crop_or_stretch_detected` | Crop flag true, mismatched aspect ratio, or visible content clipped | Contain-fit dimensions with crop=false | Window border/titlebar changing capture rect | Source/content/pre-encode/canvas sizes, aspect ratio | High with visual validation | `fix geometry/scaling` |
| `invalid_capture_output` | Native capture reports successful frames, but frame-validity counters show mostly black and low-variance output, matching pointer-only or blank visual smoke | Validity counters remain clean for the same source/method | Legitimately black/static content can look low-variance; require black and low-variance dominance plus visual or bitrate corroboration before production decisions | Final producer counts, black/low-variance counts, source type, GDI capture mode, visual observation when available | High when counters dominate and visual report matches | `fix window-GDI substage` |
| `native_capture_limited` | Native p95/max frame gaps, slow capture call/source capture, stale reuse, or low native FPS while encoder/network look clean | Clean native cadence or slow encoder/network evidence | Aggregate WebRTC encode time inflated by upstream stalls | Native cadence, capture call/source time, capture cause attribution, sender FPS, network, encoder timing | High with native markers | `fix capture backend`, `fix WGC substage`, or `fix window-GDI substage` |
| `wgc_frame_pool_limited` | WGC frame-pool empty/reuse dominates substage summary by ratio, or timing is absent and frame-pool misses exist | WGC not active, frame pool stable, or miss counts are rare beside slower timing stages | Static content with legitimate no-new-frame intervals | WGC frame timing fields, capture calls, frame-pool miss counts | High | `fix WGC substage` |
| `wgc_map_texture_limited` | Blocking map timing dominates WGC substage | Copy/row/source capture dominates | GPU contention outside app; rare frame-pool misses that are not proportional to capture calls | WGC map timing, source capture timing, frame-pool miss ratio | High | `fix WGC substage` |
| `wgc_copy_rows_limited` | Row copy timing dominates WGC substage | Map/try-get/source capture dominates | Very large source with expected copy cost | WGC copy-row timing and content size | Medium to high | `fix WGC substage` |
| `window_gdi_print_limited` | Window-GDI `PrintWindow(PW_RENDERFULLCONTENT)` or fallback `PrintWindow` dominates source capture while encoder/network look clean | BitBlt/crop/owned-window timing dominates or source capture is fast | Game/app render thread stalls inside Windows off-screen render request | Window-GDI capture mode, final producer counts, black/low-variance counts, frame timing fields, capture call/source time, sender FPS, encoder/network | High | `fix window-GDI substage` |
| `window_gdi_bitblt_limited` | Window-GDI `BitBlt` dominates source capture while encoder/network look clean and final frames are not mostly black/low variance | PrintWindow/crop/owned-window timing dominates, source capture is fast, or BitBlt mostly returns black/low-variance frames | Static desktop/window content with low animation | Window-GDI capture mode, final producer counts, black/low-variance counts, frame timing fields, capture call/source time, sender FPS, encoder/network | High only when validity counters show real frames | `fix window-GDI substage` |
| `window_gdi_owned_window_limited` | Owned-window enum/capture/composite timing dominates source capture or owned-window counts spike | Owned-window timing is small or no owned windows are captured | Menus/overlays/tooltips temporarily visible | Window-GDI owned-window counts/timing, source capture timing | Medium to high | `fix window-GDI substage` |
| `dirty_region_limited` | Tiny/partial dirty regions or dirty-region shape conflicts with visual output | Force full-frame dirty regions restore cadence/visuals | Static desktop content | Dirty-region shape, native frame timing, visual check | Medium | `fix dirty-region behavior` |
| `frame_pacing_unstable` | p95/max frame gaps, stale frame-counter windows, late-window degradation, or generic source/sender cadence tails that are not better explained by a more specific D3D11 game-hook sublabel | p95/max gaps are within budget, early/mid/late/tail windows stay stable, and source/native/encoder split timings are under budget | Low animation content; intentional bounded stale-readback or native-ready drops can be protective when latency remains low and must not classify high-confidence by themselves | Frame pacing for sender/native stages; early/middle/late/tail windows; plus game-hook split timing and freshness fields when available | High only with corroboration | `fix frame pacing` |
| `native_nv12_ready_limited` | Native NV12 queue/ready divergence, repeated `nativeNv12NotReadyPolls`, meaningful `nativeNv12ReadyDropped` or `nativeNv12StaleBeforeQueue`, or split native NV12 readiness timing over the frame budget while GPU handoff remains active | CPU-I420 fallback, LiveKit/SFU, receiver policy, generic network limits, and live sender-handoff backpressure when native NV12 fences are available/signaled with zero failures and zero not-ready polls | Protective stale drops can be expected under source stalls; require readiness timing, drop ratio, or send-FPS impact before high confidence | `nativeNv12Queued`, `nativeNv12Ready`, `nativeNv12NotReadyPolls`, `nativeNv12ReadyDropped`, `nativeNv12StaleBeforeQueue`, `nativeNv12BgraScaleDrawMs`, `nativeNv12VideoProcessorBltSubmitMs`, `nativeNv12VideoProcessorBltToReadyMs`, `nativeNv12BufferCreateMs`, `nativeNv12FrameReadyToQueueMs`, encoder input path | High with split timings and send-FPS impact | `fix game-capture handoff` |
| `delivery_queue_limited` | Delivery pacer resyncs, no-fresh-queued repeats, delivery overwrites, queue-wait/source-to-submit tails, or source-age/repeat-age spikes while source frames and native NV12 frames are otherwise being produced | Bitrate, LiveKit/SFU, TURN, receiver render, and CPU-I420 fallback when network is clean and native handoff is active | Low-motion scenes can repeat legitimately; require queue/freshness timing or sender-FPS impact | `deliveryPacerResyncs`, `deliveryRepeatNoQueue`, `deliveryRepeatSourceAgeMs`, `deliveryOverwritten`, `deliveryFreshWakeAfterSkip`, `deliveryFreshImmediate`, `deliveryQueueWaitMs`, `deliveryOnFrameMs`, `readyToSubmitMs`, `sourceToSubmitMs`, queue depth/policy marker | High with queue timing and FPS impact | `fix frame pacing` |
| `timestamp_policy_mismatch` | Skip-on-miss or sparse fresh-frame delivery uses paced timestamps that remain near one frame interval while delivery wall-clock or source-QPC gaps are much larger | Source-QPC timestamps are active for fresh frames, repeated frames explain cadence, or wall/source/timestamp deltas track each other | Low-motion scenes with intentionally repeated frames; require repeated=0 or clearly separated repeated evidence | `timestampMode`, `timestampDeltaMs`, `timestampSourceQpcFrames`, `timestampPacedFallbackFrames`, `timestampRepeatedFrames`, `deliveryWallDeltaMs`, `sourceQpcDeltaMs`, repeat policy/counters | High when paced timestamps mask fresh-frame gaps | `fix frame pacing` |
| `webrtc_onframe_limited` | Split delivery timing shows the actual WebRTC `OnFrame` call averaging over budget or spiking while submit prep, post-`OnFrame` cleanup, native buffer release, and delivery queue wait are not the stronger limiter | Native NV12 readiness and delivery queue wait are low, and encoder timing/no-output evidence does not provide a more specific encoder label | Aggregate `deliveryOnFrameMs` may include prep or release work; require split `deliveryOnFrameCallMs` before using this label | `deliverySubmitPrepMs`, `deliveryOnFrameCallMs`, `deliveryPostOnFrameMs`, `nativeBufferReleaseMs`, `deliveryQueueWaitMs`, `sourceToSubmitMs`, encoder input/output markers | High with split OnFrame timing and FPS impact | `fix encoder path` |
| `gpu_handoff_unproven` | D3D11 game hook GPU-scales frames, native NV12 submissions remain zero or only startup submissions occur before `native_nv12_encoder_handoff_disabled reason=...`, CPU-I420 encoder input is observed, and the scaled readback path is still active | LiveKit/SFU, bitrate/profile limits, source visibility, GPU-scale setup, source ordering, and Media Foundation startup as the first boundary when network stats are clean | CPU I420 fallback can produce a stable visible stream; it must not be treated as proof that the full GPU/NV12 encoder path is solved. For BG3 R10, distinguish the old pre-gate from a post-attempt fallback by checking for `native_nv12_encoder_handoff_enabled source_format=r10g10b10a2`, async `nativeNv12Queued/nativeNv12Ready` counters, and the first `gpu_nv12_failed reason` before `reason=r10g10b10a2_native_nv12_attempt_failed`; if the fallback then shows readback pressure, `frame_pacing_unstable` may be the final report label while the repair still belongs to GPU handoff. | `gpuScaled`, `nativeNv12Submitted`, `nativeNv12Queued`, `nativeNv12Ready`, `nativeNv12Failures`, `readbackQueued/readbackReady/readbackNotReady`, encoder `input_path`, native NV12 enabled marker, `gpu_nv12_failed reason/hr`, and `native_nv12_encoder_handoff_disabled reason` when present | High with explicit disabled reason, medium without reason | `fix game-capture handoff` |
| `capture_or_preencode_limited` | Capture/pre-encode FPS below target and encode/send track same cadence | Native markers identify acquisition or encoder timing is slow | Missing native markers | Capture/encode/send FPS, pre-encode dimensions, native markers | Medium, low without native | `fix capture backend` or `collect one specific missing field` |
| `encoder_pipeline_limited` | Encode time, encoder drops, or send queue delay exceeds frame budget and stage FPS tracks | Native capture slow before encoder | WebRTC CPU label without encode/drop corroboration | Encode time, drops, capture/encode/send FPS, send delay | High with encode/drops | `fix encoder path` |
| `media_foundation_encoder_limited` | Native Media Foundation encoder timing exceeds the frame budget, has a high slow-sample ratio, or shows max input/encode stalls while native source readiness and delivery queue evidence are not stronger | Native encoder timing is fast and slow samples are rare | WebRTC aggregate encode time includes capture wait; native source readiness or delivery queue may be the stronger upstream label | Native encoder timing/substages, slow-sample count/ratio, input path, native sample status, queue/retained sample counters | High with native encoder markers | `fix encoder path` |
| `encoder_handoff_limited` | Media Foundation accepts native NV12 input with `input_path=native_nv12`, `native_input=yes`, and `native_sample_failed=no`, but encoded output remains absent or blocked, queued/retained native samples accumulate, repeated `stage=not_accepting` / `stage=not_accepting_recovered` appears, `native_suspended=yes` appears, the stream-test exits through the native-handoff timeout path, or live-call sender handoff shows slow `deliveryOnFrameCallMs`/MF timing while local source-OnFrame and local native-MF isolation pass | Source selection, hook attach, GPU scale/NV12 source creation, native-ready fence availability, CPU-I420 fallback, bitrate, LiveKit/SFU, receiver policy, and native sample creation failure | Short startup priming can show zero output or a transient `not_accepting` briefly; require repeated no-output/not-accepting evidence, an explicit recovery/suspension marker, a timed-out publish/report boundary, or `live_sender_handoff_backpressure` with healthy native NV12 readiness counters | Media Foundation `stage`, `input_path`, `native_input`, `native_sample_failed`, `outputs`, `output_bytes`, `queue`, `retained_samples`, `encoded_outputs`, `native_suspended`, `native_ready_fence_wait_ms`, `process_input_ms`, `process_output_ms`, live `deliveryOnFrameCallMs`, sender FPS, and stream-test completion/error state | High with native no-output, repeated not-accepting, suspension evidence, or healthy local gates plus slow live handoff | `fix encoder path` |
| `sender_adaptation_limited` | Sender active layer/quality limitation shows downgrade with clean network and encoder evidence | No downgraded layer or real network/encoder cause | Adaptive stream intentionally serving low receiver | Active layer, quality limitation durations, receiver request | Medium | `fix receiver subscription/rendering` |
| `fallback_policy_error` | App fallback downgrades without verified loss/RTT/encode overload/send queue pressure | Verified overload triggered fallback | WebRTC internal CPU limiter without app action | Fallback reason, loss/RTT/NACK, encode/drop/send-delay evidence | High | `fix frame pacing` or `fix encoder path` |
| `receiver_subscription_limited` | Focused receiver gets low/subscribed layer despite sender high quality | Focused receiver subscribed high | Hidden/default collapsed receiver | Receiver priority, subscribed layer, visibility/focus | High with receiver logs | `fix receiver subscription/rendering` |
| `receiver_decode_limited` | Receive FPS good but decode FPS low/dropped frames/freezes high | Sender and decode counters track | Hidden receiver throttling | Receive/decode/render counters, decoder implementation | Medium to high | `fix receiver subscription/rendering` |
| `receiver_render_limited` | Decode FPS good but render FPS low/freezes high | Render FPS tracks decode FPS | Debug UI/overlay throttling | Decode/render counters, visibility/focus | Medium to high | `fix receiver subscription/rendering` |
| `network_limited` | Packet loss > 1%, RTT > 150ms, or NACK > 8 with bitrate/available outgoing pressure | Clean loss/RTT/NACK and route; D3D11 native-NV12 sender handoff evidence that already explains sub-target capture/encode/send cadence | Initial ramp-up transient; RTT-only spikes on a report whose sender hot path is already below budget with clean loss/NACK | Loss, RTT, NACK, available outgoing bitrate, route | High | `inspect server/network` |
| `turn_or_tcp_limited` | Relay/TCP route plus loss/RTT/throughput pressure | Host/srflx UDP route with clean stats | TURN route that is healthy | ICE candidate type/protocol, loss, RTT, bitrate | Medium to high | `inspect server/network` |
| `livekit_sfu_limited` | SFU warnings or subscriber layer constraints with clean local sender/network route | Local sender bottleneck | Adaptive stream intentionally lowering hidden receiver | LiveKit warnings, subscribed layer, receiver visibility | Medium | `inspect server/network` |
| `healthy` | Send FPS near target, resolution fits request, clean network, no encoder/native limiter | Any clear bottleneck evidence | Low-motion content hiding stutter | Sender FPS, resolution, network, pacing | High | `no stream change recommended` |
| `insufficient_evidence` | FPS or quality is bad but required fields for all confident labels are missing | Any label has positive evidence | Treating missing receiver or native fields as proof | Exact missing fields from coverage/classifier | Insufficient | `collect one specific missing field` |

## Failed-Run Report Behavior

If a stream-test run throws before any preset result can be finalized, the
report must still be written as `intergalactic.streamTestRun.v1` with a
top-level `error`, `Run status: failed`, empty `presetResults`, and the
redacted app/native diagnostic marker tail. Automation `.complete.json` must
use `status=failed` when this run-level error is present even if a report path
exists. Such reports should classify as `insufficient_evidence` until a
specific preset error, native marker, or sender diagnostic supports a more
specific label.

## Missing-Field Behavior

The report must name exact missing fields. Examples:

- Missing receiver-side proof: `receiver render FPS`, `receiver decode FPS`,
  `subscribed layer`.
- Missing sender-stage proof: `capture FPS`, `encode FPS`, `send FPS`,
  `pre-encode dimensions`.
- Missing native proof: `native capture markers`, `WGC substage markers`,
  `window-GDI substage markers`, `dirty-region shape`,
  `updated-region analysis timing`, or one of the capture-cause attribution
  buckets.
- Missing network proof: `packet loss`, `RTT`, `NACK`, `available outgoing
  bitrate`.

Reports must not use a generic `unknown` bottleneck when these fields are
missing. Use `insufficient_evidence`.

## D3D11 Game-Hook Stage Timing Rules

When `game-d3d11-hook-experimental` reports `sourceToSubmitMs` above the frame
budget, classification must include the Phase 2 split when present:

- `sourceToReadbackReadyMs` high: the delay starts before or at scaled
  readback readiness; investigate source-present cadence, GPU scale/copy
  queueing, or readback readiness.
- `readbackQueueToMapMs` high with low `mapToI420Ms`: the delay is mostly
  waiting for a scaled readback to become mappable; investigate async readback
  ring depth, GPU fence/readback readiness, and stale-readback pruning.
- `mapToI420Ms` high: the CPU conversion boundary is the bottleneck; investigate
  output dimensions, I420 conversion cost, or a GPU/NV12/encoder handoff.
- `sourceToI420ReadyMs` high while `sourceToQueueMs` is similar: WebRTC source
  delivery is waiting for readback/conversion, not the downstream delivery
  queue.
- `sourceToQueueMs` high while `sourceToI420ReadyMs` is low: delivery queue or
  source-thread handoff is the likely boundary.

If these fields are missing from a D3D11 game-hook run, use
`insufficient_evidence` or add `game-capture stage timing` to missing evidence
instead of making another bitrate/profile/LiveKit change.

## D3D11 Native NV12 Timing Rules

When `game-d3d11-hook-experimental` reports active native NV12 encoder input,
reports must prefer the most specific sublabel before falling back to generic
`frame_pacing_unstable`:

- If native NV12 reaches Media Foundation with `input_path=native_nv12` but the
  parsed encoder timing has no `native_ready_fence_wait_ms`, classify as
  `insufficient_evidence` and list `delivery_queue_limited`,
  `webrtc_onframe_limited`, `native_nv12_ready_limited`, or
  `media_foundation_encoder_limited` as candidates from the available split
  timings. Do not treat low average `VideoProcessorBltToReady` timing as proof
  that the sender pipeline is healthy until encoder fence wait and
  `ProcessInput`/`ProcessOutput` timing are present.
- `nativeNv12ConversionStartAgeMs` high or
  `nativeNv12StaleBeforeQueue` increasing: classify as
  `native_nv12_ready_limited` when stale work is being admitted before GPU
  conversion, unless delivery queue timing is clearly larger.
- `nativeNv12VideoProcessorBltToReadyMs` high or repeated not-ready polls:
  classify as `native_nv12_ready_limited` and investigate GPU readiness/fence
  behavior before changing bitrate, LiveKit, or receiver policy.
- When `nativeNv12ReadyPolicy=fence`, `nativeNv12FenceSignaled` is nonzero,
  `nativeNv12NotReadyPolls=0`, `nativeNv12ReadyDropped=0`, native failures and
  CPU fallback are zero, and local native-MF/source-OnFrame isolation is
  healthy, do not classify a slow live run as pure
  `native_nv12_ready_limited` only because max BGRA/Blt timings have tails.
  If live `deliveryOnFrameCallMs`, Media Foundation timing, or sender FPS is
  over budget, classify as `encoder_handoff_limited` with reason
  `live_sender_handoff_backpressure`.
- When D3D11 game-hook capture/encode/send averages meet the requested FPS,
  native NV12 failures, CPU fallback, not-ready polls, ready drops, packet
  loss, and sender adapter drops are clean, and live `OnFrame` plus MF fence
  wait are under budget, do not emit high-confidence
  `native_nv12_ready_limited` solely from isolated max BLT/source-to-submit
  spikes. Prefer `healthy` with residual `frame_pacing_unstable` or
  `native_tail_spike_review` commentary until those tails show sustained send
  FPS impact.
- `nativeNv12FrameReadyToQueueMs` high, stale-before-queue counts, or frequent
  ready drops: classify as `native_nv12_ready_limited` unless delivery queue
  timing is the clearly larger downstream delay.
- `deliveryQueueWaitMs`, `readyToSubmitMs`, `sourceToSubmitMs`, delivery
  overwrite counts, or pacer resync counts dominate: classify as
  `delivery_queue_limited`.
- `timestampMode=paced` with skip-on-miss, repeated frames near zero, and
  timestamp deltas near the target frame interval while delivery wall-clock or
  source-QPC deltas are much larger: classify as `timestamp_policy_mismatch`.
- Split `deliveryOnFrameCallMs` over budget with low submit prep,
  post-`OnFrame` cleanup, native buffer release, and queue wait: classify as
  `webrtc_onframe_limited` before falling back to generic delivery queue or
  frame pacing labels.
- Native encoder average over budget or high slow-sample ratio with no stronger
  upstream readiness/queue evidence: classify as
  `media_foundation_encoder_limited`.

When D3D11 game-hook evidence is active, WGC and window-GDI summary labels are
not applicable to the current run even if stale marker tails remain in logs.
Reports may keep the raw markers for forensics, but the user-facing summary
must label those substages as not applicable instead of treating them as active
bottleneck evidence.

## Window-GDI Method Comparison Rules

When a stream test cycles window-GDI methods, a faster method is not actionable
unless the report also proves the method produced usable frames. Required proof:

- `capture_mode` requested/applied by the native window-GDI capturer.
- Final producer counts: `final_print_full`, `final_print_fallback`,
  `final_bitblt`, and `final_none`.
- Frame validity counters: `black_frame_count` and
  `low_variance_frame_count`.

If BitBlt or plain `PrintWindow` is fast but black/low-variance counts
dominate, classify the row as `invalid_capture_output` and keep the next action
as `fix window-GDI substage`. The method should be discarded or gated for the
affected source rather than promoted, even if its FPS score would otherwise look
better.
If BitBlt is fast and validity counters remain clean, it becomes a candidate
for a targeted product-path change after source-rebind and display-path checks.

## Capture Cause Attribution Rules

When `native_capture_limited` is the primary label, the report must expose the
six diagnostic buckets below before changing stream behavior:

| Bucket | Evidence | Rules Out / Redirects |
| --- | --- | --- |
| Full source acquisition | Source/window/content/pre-encode dimensions, megapixels, source-to-content ratio, source-capture time | If source is already at output size, do not blame full 2560x1440 acquisition. |
| Blocking acquire wait | Acquire wait, callback-entry delay, source capture, post-callback, unaccounted wait, dominant phase | If acquire wait is small, look at backend substage, frame work, or downstream pacing. |
| CPU readback/copy | WGC map/copy-row/copy-texture timing; window-GDI PrintWindow/BitBlt/crop timing; wrapper convert/scale timing | If readback/copy timing is small, avoid CPU-copy optimizations as the first fix. |
| Dirty-region processing | Dirty-region shape plus updated-region analysis timing | If dirty shape is full-frame but analysis timing is tiny, the problem is acquisition/copy, not dirty-region bookkeeping. |
| Frame lifetime/lock/sync | Callback-entry, post-callback, unaccounted wait, and pacer frame age | If these waits are small, do not chase outer locks/lifetime before backend substages. |
| Full-frame copy before downscale | Source/content pixel ratio plus wrapper convert/scale/callback timing | If convert/scale timing is small, do not prioritize pre-encode copy removal over the actual dominant backend stage. |
