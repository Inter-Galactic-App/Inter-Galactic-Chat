# Stream Diagnostic Contract

Status: Active architecture contract
Owner: EXPERIMENTAL
Last updated: 2026-06-15

This contract defines the canonical field surface for Inter Galactic stream
diagnostics. Stream instrumentation must land here before it is added to native
logs, Dart parsers, JSON, or Markdown reports.

Field status legend:

- Required: needed for confident classification.
- Optional: useful context, not required for most classifications.
- Diagnostic-only: developer evidence, not expected in normal user UI.
- Unavailable: not exposed by current APIs or report inputs.
- Planned: designed but not implemented.

## A. Session Metadata

| Field | Status | Current Source |
| --- | --- | --- |
| App version | Planned | Build metadata, not yet copied into stream-test reports |
| Git/build hash | Planned | Build/release ledgers |
| Platform | Planned | Runtime platform |
| Source type | Required | `StreamTestSourceMetadata.sourceType` |
| Source title/hash | Required | `StreamTestSourceMetadata.sourceIdHash`; title optional/developer only |
| Profile name | Required | `ScreenShareProfileConfig.label` |
| Stream-test mode | Required | `StreamTestRunConfig.scenarioLabel` |
| Observe-only/live-tune/normal app-started | Planned | Future runner mode metadata |
| Sender user | Optional | Call diagnostics participants if present |
| Receiver user | Optional | Receiver-side diagnostics when present |
| Timestamp range | Required | `startedAt`, `endedAt`, `diagnosticStartedAt`, `diagnosticEndedAt` |
| Stream start/publish failure boundary | Required on failed stream-test start | `StreamTestPresetResult.error`; D3D11 stream-test publish guard emits `stage=publishVideoTrack_pre_event` when `publishVideoTrack` times out before local publication |
| Run-level stream-test failure | Required when the runner throws before a preset result can be returned | Top-level `StreamTestRunResult.error`; JSON/Markdown reports must still include run status, redacted error text, config, coverage, and redacted native diagnostic marker tails |
| Stream-test automation status | Required for automation runs | `stream-test-request-*.running.json` and `.complete.json`; running/completion envelopes must keep schema/id/status/timestamps/sanitized request shape and avoid raw local paths, source titles, and PIDs |

## B. Requested Settings

| Field | Status | Current Source |
| --- | --- | --- |
| Target width/height/FPS | Required | Profile layer and sender requested stats |
| Sender/capture FPS cap | Required | Profile layer and native target FPS |
| Bitrate min/target/max | Required | Profile layer and sender requested bitrate where exposed |
| Codec requested | Required | `ScreenShareProfileConfig.codec` |
| Hardware preference requested | Required | `ScreenShareProfileConfig.hardwareEncodeFirst` |
| Simulcast/single-layer | Required | `ScreenShareProfileConfig.useSimulcast` |
| Dynacast/adaptive on/off | Optional | `VoipCallDiagnosticsSnapshot` |
| Degradation preference | Planned | Sender parameters if exposed |
| Backend override requested | Required | `StreamTestRunConfig.windowsCaptureBackendMode(s)` |
| Effective backend resolved | Required | Stream-test per-result summary and publish diagnostics; app-default Windows window tests may resolve to `game-d3d11-hook-experimental` in developer mode while preserving the requested backend as `App default` |
| Window-GDI capture method override requested | Diagnostic-only | `StreamTestRunConfig.windowsWindowGdiCaptureMode(s)` |
| Requested game-capture backend | Required when explicit | D3D11 game-capture stream-test/backend override or developer-mode app-default effective backend resolution |
| Dummy NV12 live sender requested | Diagnostic-only | Stream-test automation/config fields `dummyNv12LiveSender=true` and `gameCaptureSourceMode=dummy-nv12-live-sender`; used only for sender isolation and must not be treated as BG3/game-hook proof |
| Game-capture source mode | Required when non-default | Stream-test JSON `config.gameCaptureSourceMode`, native diagnostics `gameCaptureSourceMode`, and native `sourceMode` marker; distinguishes normal helper D3D11 capture from `dummy-nv12-live-sender` generated NV12 isolation |

When a report says `App default`, consumers must read the effective backend as
well as the requested backend. Developer-mode Windows window/game sources can
use the D3D11 game hook without writing an explicit override into the requested
settings, so classification and profile scoring must use the effective backend
for target resolution/FPS and game-capture marker requirements.

## C. Actual Sender Settings

| Field | Status | Current Source |
| --- | --- | --- |
| Encoded width/height | Required | Sender `VoipTrackDiagnostics.width/height` |
| Pre-encode width/height | Required | Sender `preEncodeWidth/preEncodeHeight` and native markers |
| Source width/height | Required | Native source markers |
| Capture/pre-encode/encode/send FPS | Required | Sender FPS stats and frame counters |
| Actual codec | Required | Sender codec stats |
| Encoder implementation | Required | Sender encoder implementation |
| Hardware active | Required | Sender hardware encode state |
| Quality limitation reason/duration | Required | Sender quality limitation stats |
| Target bitrate | Required | Sender target/requested bitrate |
| Actual send bitrate | Required | Sender bitrate |
| Available outgoing bitrate | Required | Sender available outgoing bitrate |
| Retransmit bitrate | Optional | Sender retransmit stats |

## D. Native Capture

| Field | Status | Current Source |
| --- | --- | --- |
| Loaded libwebrtc path/hash/marker | Unavailable | Not exposed in stream-test report |
| Bridge marker | Diagnostic-only | Native log markers |
| Capturer ID | Required | Native capture pipeline marker |
| Backend mode | Required | Native capture options marker |
| Window-GDI capture mode | Required when window-GDI | Native capture options/bridge/window-GDI markers |
| Dirty-region mode | Required | Native capture options/pipeline marker |
| Source/window/content/pre-encode sizes | Required | Native capture pipeline marker |
| Requested max size | Required | Native capture pipeline marker |
| Canvas mode and crop_region | Required | Native capture pipeline marker |
| Loaded libwebrtc artifact identity | Required on stream-test reports | Report field `loadedLibwebrtc` and diagnostic coverage row with filename, source label, size, modified time, and SHA-256 digest; proves the report came from the expected native artifact without exposing raw local paths |
| Game-capture backend contract | Required when `game-d3d11-hook-experimental` | Native hook/helper/libwebrtc markers and reports expose `backendContractVersion`, `sourceApi`, `sourceApiId`, `sourceFormat`, `sourceFormatId`, `colorSpace`, `syncKind`, `readyState`, and `failureReason`. Stream-test JSON/Markdown parse these into `StreamTestNativeDiagnostics`, the frame summary label, and the `game-capture backend contract` Diagnostic Coverage Matrix row. This row is the common comparison surface for future Vulkan/DX12 work and must remain D3D11-populated before new API backends are added. |
| Game-capture WebRTC source/output size | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker; overrides stale desktop-capturer size markers for this backend |
| Game-capture WebRTC source format | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats/proof marker, e.g. DXGI format numeric code |
| Game-capture WebRTC source FPS/submitted frames | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker fields `fps`, `submitted`, `repeated`, and `duplicateSkipped`; used as native source cadence evidence and to distinguish clean source-present FPS limits from stale repeated-frame submission |
| Game-capture WebRTC GPU-scale/cpu-fallback counters | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker fields `gpuScaled`, `gpuScaleFailures`, `cpuFallback`, and `gpuScaleMs`; proves whether the live WebRTC source used GPU scale or fell back to full-source CPU work |
| Game-capture WebRTC native NV12 handoff counters | Required when Phase 4 native handoff is enabled | Native `game_capture_webrtc_source` stats marker fields `nativeNv12Submitted`, `nativeNv12Queued`, `nativeNv12Ready`, `nativeNv12NotReadyPolls`, `nativeNv12ReadyPolicy`, `nativeNv12FenceAvailable`, `nativeNv12PendingPollMs`, `nativeNv12MaxPendingSlots`, `nativeNv12ReadyDrainDepth`, `nativeNv12FrameOwnership`, `nativeNv12OwnedCopies`, `nativeNv12OwnedCopyMs/MaxMs/Samples`, `nativeNv12FenceSignaled`, `nativeNv12FenceReady`, `nativeNv12FenceSignalFailures`, `nativeNv12Overwritten`, `nativeNv12ReadyDropped`, `nativeNv12Failures`, `nativeNv12ConversionStartAgeMs/MaxMs/Samples`, `nativeNv12ConvertMs/MaxMs/Samples`, `nativeNv12BgraScaleDrawMs/MaxMs/Samples`, `nativeNv12VideoProcessorBltSubmitMs/MaxMs/Samples`, `nativeNv12VideoProcessorBltToReadyMs/MaxMs/Samples`, `nativeNv12BufferCreateMs/MaxMs/Samples`, `nativeNv12FrameReadyToQueueMs/MaxMs/Samples`, `consumerAdapterLuid`, `consumerAdapterVendorId`, `consumerAdapterDeviceId`, `sourceAdapterLuid`, and `crossAdapterSuspected`; proves whether the WebRTC source submitted GPU-scaled NV12-backed native frames, whether the handed-off texture is per-frame owned or a reusable ring slot, whether the ownership copy is cheap, whether async GPU readiness is draining without hot-path blocking, whether stale source frames are being admitted before conversion, which bounded ready-drain depth was active for a diagnostic run, whether the consumer adapter is stable, whether a source/consumer cross-adapter copy is suspected, and whether the older scaled-readback/I420 path was bypassed |
| Game-capture WebRTC native NV12 attempt marker | Required when a BG3 R10 source attempts Phase 4 native handoff | Native `native_nv12_encoder_handoff_enabled source_format=r10g10b10a2` marker; proves the live WebRTC source tried the R10 GPU/NV12 path instead of skipping it before submission |
| Game-capture WebRTC native NV12 stage/failure marker | Required when a BG3 R10 source attempts Phase 4 native handoff | Native `gpu_nv12_stage` breadcrumbs and `gpu_nv12_failed reason/hr` marker; identifies the exact conversion/lifetime/readiness boundary when a post-attempt fallback occurs. Current healthy async stages include `native_frame_ready_pending` and `newest_ready_queued`; old blocking failures such as `video_processor_blt_wait_timeout` must be treated as source-conversion/readiness regressions, not bitrate or LiveKit evidence |
| Game-capture WebRTC native NV12 disabled reason | Required when Phase 4 native handoff is enabled and no native NV12 frames are submitted | Native `native_nv12_encoder_handoff_disabled` marker field `reason`; reports must expose the reason in JSON/Markdown and classify a GPU-scaled readback/I420 fallback run as `gpu_handoff_unproven` until native NV12 submission reaches the encoder. The R10 post-attempt fallback reason is `r10g10b10a2_native_nv12_attempt_failed`; inspect the first `gpu_nv12_failed` marker before changing bitrate, LiveKit, or I420 fallback behavior |
| Game-capture WebRTC async readback counters | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker fields `readbackQueued`, `readbackReady`, `readbackNotReady`, `readbackOverwritten`, `readbackLatencyDropped`, `readbackMapAttempts`, `readbackLatencyMs`, `readbackLatencyFramesAvg`, and `readbackLatencyFramesMax`; proves whether scaled GPU readback is being drained without blocking, silently overwriting queued frames, or publishing stale-but-ordered frames during motion |
| Game-capture WebRTC stage timing split | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker fields `sourceToReadbackReadyMs/MaxMs/Samples`, `readbackQueueToMapMs/MaxMs/Samples`, `mapToI420Ms/MaxMs/Samples`, `sourceToI420ReadyMs/MaxMs/Samples`, and `sourceToQueueMs/MaxMs/Samples`; proves whether remaining source-to-submit gaps are before readback readiness, waiting to map, CPU conversion, or delivery queue handoff |
| Game-capture WebRTC source frame ordering | Required when `game-d3d11-hook-experimental` | Native `game_capture_webrtc_source` stats marker fields `sourceFrameIndex`, `lastSubmittedSourceFrameIndex`, `sourceFrameRegressions`, `sourceFrameDuplicates`, `sourceFrameGaps`, and `sharedSlotMismatches`; proves whether the WebRTC source submitted stale or out-of-order shared texture slots after the helper copied newer game frames |
| Game-capture WebRTC pre-I420 proof frame count/visibility | Required when `game-d3d11-hook-experimental` | Native pre-I420 proof marker and BMP output under `%TEMP%\intergalactic-game-capture-webrtc-proof` |
| Game-capture WebRTC post-I420 proof frame count/visibility | Required when `game-d3d11-hook-experimental` | Native `i420_proof` marker and reconstructed BMP output under `%TEMP%\intergalactic-game-capture-webrtc-proof` |
| Game-capture WebRTC proof luma/sample stats/path | Diagnostic-only | Native pre-I420 and post-I420 proof markers; classifies black-output boundary before I420 conversion, after I420 conversion, or after WebRTC frame submission |
| Game-capture WebRTC startup black skip count | Required when `game-d3d11-hook-experimental` | Native `skip_initial_black`, `startup_visible_after_black`, and stats markers. This proves whether startup all-black helper frames were withheld before first visible source submission. |
| Game-capture WebRTC visible-source-seen flag | Required when `game-d3d11-hook-experimental` | Native stats marker. A false value after startup means the selected game source never produced visible content, not an encoder/network limitation. |
| Native submitted FPS | Required | Native cadence marker |
| Native p50/p95/max frame interval | Required | p95/max available; p50 planned |
| Capture call/source/acquire/callback/post/unaccounted time | Required | Native cadence marker |
| Frame work timing | Required | Native frame timing marker |
| Capture cause attribution | Required | Derived from native markers |
| Wait timeouts/permanent errors | Required | Native cadence/frame markers |

## E. WGC Backend Substages

| Field | Status | Current Source |
| --- | --- | --- |
| Frame-pool empty/reuse count | Required when WGC | WGC frame timing marker |
| Capturability misses | Required when WGC | WGC frame timing marker |
| Startup sleeps | Required when WGC | WGC frame timing marker |
| Texture resize/recreate count | Required when WGC | WGC frame timing marker |
| TryGetNextFrame timing | Required when WGC | WGC frame timing marker |
| Surface/texture/content-size timing | Required when WGC | WGC frame timing marker |
| CopySubresourceRegion timing | Required when WGC | WGC frame timing marker |
| Blocking Map timing | Required when WGC | WGC frame timing marker |
| Row copy timing | Required when WGC | WGC frame timing marker |
| Monitor scale lookup timing | Required when WGC | WGC frame timing marker |
| Zero-hertz comparison timing | Required when WGC | WGC frame timing marker |
| Dominant WGC substage | Required when WGC | Derived from WGC timing |

## F. Window-GDI Backend Substages

| Field | Status | Current Source |
| --- | --- | --- |
| Window-GDI call/success/error counts | Required when window-GDI | Window-GDI frame timing marker |
| Hidden/minimized, rect/DC/frame allocation failures | Required when window-GDI | Window-GDI frame timing marker |
| Original/cropped/frame sizes | Required when window-GDI | Window-GDI frame timing marker |
| `PrintWindow(PW_RENDERFULLCONTENT)` calls/successes/timing | Required when window-GDI | Window-GDI frame timing marker |
| Fallback `PrintWindow` calls/successes/timing | Required when window-GDI | Window-GDI frame timing marker |
| `BitBlt` calls/successes/timing | Required when window-GDI | Window-GDI frame timing marker |
| Final producer method counts | Required when comparing window-GDI methods | Window-GDI `final_print_full`, `final_print_fallback`, `final_bitblt`, and `final_none` fields |
| Black/low-variance frame counts | Required when comparing window-GDI methods | Window-GDI frame-content sampler fields |
| Derived output validity | Required when comparing window-GDI methods | Stream-test report derives `valid` or `invalid_black_low_variance` from final producer counts plus black/low-variance ratios |
| Crop timing | Required when window-GDI | Window-GDI frame timing marker |
| Owned-window enum/capture/composite timing | Required when window-GDI | Window-GDI frame timing marker |
| Dominant window-GDI substage | Required when window-GDI | Derived from window-GDI timing |

## G. Dirty-Region Shape

| Field | Status | Current Source |
| --- | --- | --- |
| Updated-region rect count/max rect count | Required | Native frame timing marker |
| Average/max dirty-area ratio | Required | Native frame timing marker |
| Full-frame update count | Required | Native frame timing marker |
| Tiny update count | Required | Native frame timing marker |
| Dirty-region analysis timing | Required | Native frame timing marker |
| Dirty-region shape label | Required | Derived from dirty-region fields |

## H. Frame Pacing

| Field | Status | Current Source |
| --- | --- | --- |
| Native/capture/pre-encode/encoded/sent intervals | Required | Native markers and sender counters |
| Received/decoded/rendered intervals | Required when receiver logs exist | Receiver counters |
| p50/p95/max for available stages | Required | `StreamTestFramePacingStageSummary` |
| Duplicated/stale/skipped/overwritten frame counts | Required | Native cadence and pacer markers |
| Pacer unique/submitted FPS | Required when pacer enabled | Native pacer markers |
| Early/middle/late/tail pacing windows | Required | `StreamTestTemporalAnalysis` in each preset result; windows include sampled capture/encode/send/receive/decode/render FPS and p95/max sent gaps |
| Game-hook per-window counter deltas | Required when `game-d3d11-hook-experimental` | Timestamped `game_capture_webrtc_source` markers parsed into each time window, including submitted/gpuScaled/cpuFallback/native-NV12 submitted/failures/readback ready/not-ready/stale/latency-drop/source-order deltas. Time-window analysis uses the uncapped per-preset marker set before the report export cap is applied, so late/tail evidence is not dropped from long runs. |
| Game-hook per-window stage maxima | Required when `game-d3d11-hook-experimental` | Timestamped `game_capture_webrtc_source` markers parsed into each time window, including max source-to-readback-ready, readback-queue-to-map, map-to-I420, source-to-I420-ready, source-to-queue, and source-to-submit timings |
| Late degradation signals | Required | Derived from time windows when early pacing is acceptable but late or tail FPS/gaps/readback pressure deteriorate |

## I. Encoder

| Field | Status | Current Source |
| --- | --- | --- |
| Media Foundation marker present | Required on Windows H.264 | Native encoder timing marker |
| Encode time average/max/p95 | Required | Average/max available; p95 planned |
| Encoder input path | Required on Phase 4 Windows H.264 | Native encoder timing marker fields `stage`, `input_path`, `native_input`, and `native_sample_failed`; proves whether Media Foundation consumed native NV12 surfaces, fell back to CPU I420, or stalled at `stage=not_accepting` before input was accepted |
| ToI420/NV12/input copy/ProcessInput/drain/output-copy timing | Required on Phase 4 Windows H.264 | Native encoder timing marker fields `to_i420_ms`, `nv12_ms`, `create_sample_ms`, `input_copy_ms`, `native_ready_fence`, `native_ready_fence_timeout`, `native_ready_fence_wait_ms`, `native_source_mode`, `native_source_format`, `native_source_frame`, `native_source_age_ms`, `native_source_age_at_create_ms`, `native_buffer_age_ms`, `native_sample_lifetime_ms`, `native_sample_lifetime_max_ms`, `native_sample_lifetime_samples`, `native_adapter_luid`, `native_adapter_vendor_id`, `native_adapter_device_id`, `process_input_ms`, `pre_drain_ms`, `retry_drain_ms`, `post_drain_ms`, `process_output_ms`, and `output_copy_ms`; reports must expose these fields in JSON/Markdown and mark `native_ready_fence_wait_ms`, native source age, native buffer age, or native sample lifetime missing when native NV12 input is active but the field is absent |
| Output frame/byte count | Required on Phase 4 Windows H.264 | Native encoder timing marker fields `outputs`, `output_bytes`, and `encoded_outputs` |
| Queue depth/async state | Required on Phase 4 Windows H.264 | Native encoder timing marker fields `queue`, `retained_samples`, `native_suspended`, and `async` |
| Sender handoff diagnostic block | Required on Phase 4 D3D11 game-hook stream tests | Stream-test JSON `summary.senderHandoffDiagnostics`, Markdown `## Sender Handoff Diagnostics`, and Diagnostic Coverage Matrix rows `sender handoff diagnostics` plus `WebRTC raw sender boundary`; combines live `deliveryOnFrameCallMs`, native conversion-start frame age, delivery queue/source-to-submit timing, diagnostic `deliveryQueueDepth`, native NV12 fence/readiness counters including `nativeNv12ReadyDrainDepth`, native NV12 frame ownership and owned-copy timing, adapter/source-format ownership, WebRTC source sink dispatch timing, `VideoBroadcaster` `frames`, `sink_count`, `max_sink_count`, `lock_wait_ms`, `lock_wait_max_ms`, `sink_dispatch_ms`, `sink_dispatch_max_ms`, `max_single_sink_ms`, `slow_sink_id`, `slow_sink_ms`, `slow_sink_label`, `slowest_sink_id`, `slowest_sink_ms`, `slowest_sink_avg_ms`, `slowest_sink_frames`, `slowest_sink_label`, `active_sinks`, `inactive_sinks`, `requested_sinks`, `black_frame_sinks`, `rotation_applied_sinks`, `inactive_native_sinks_bypassed`, `inactive_native_sinks_bypassed_last`, `sink_roster`, `black_sinks`, `rotation_discards`, `update_rect_cleared`, and `discarded_frames`, `VideoStreamEncoder` post-to-OnFrame/OnFrame/adaptation/drop/MaybeEncode timing, `VideoEncoder::Encode` timing, Media Foundation native source age, buffer age, fence wait, sample lifetime, ProcessInput/ProcessOutput/queue/retained/output cadence, encoded callback timing, and sender drop counters. Reports must either expose these fields or mark the exact missing handoff fields. |
| Slow encoder samples | Required | Native encoder timing marker |
| Dominant encoder substage | Planned | Future native encoder substage parser |

## J. Receiver

| Field | Status | Current Source |
| --- | --- | --- |
| Subscribed layer | Required | Receiver diagnostics when present |
| Focused/visible state | Required | Receive priority diagnostics |
| Receive/decode/render FPS | Required | Receiver WebRTC stats and counters |
| Decoder implementation | Optional | Receiver stats when exposed |
| Frames received/decoded/rendered | Required | Receiver counters |
| Dropped frames/freezes | Optional | Receiver WebRTC stats |
| Layer switch events | Planned | LiveKit publication/subscription events |

## K. Network/SFU

| Field | Status | Current Source |
| --- | --- | --- |
| ICE candidate type and route | Required | Call diagnostics ICE summary |
| UDP/TCP/TURN usage | Required | ICE candidate diagnostics |
| Packet loss/lost packets | Required | Sender/receiver WebRTC stats |
| RTT/jitter | Required | WebRTC stats |
| NACK/PLI/FIR | Required | WebRTC stats |
| LiveKit warnings | Optional | Call diagnostics/log markers |
| SFU/server evidence | Optional | Server logs when collected |

## L. Host/System Load

Host/system load is a stream-test report surface, not a raw log side channel.
The sampler must continue to fail open: if Windows counters are unavailable,
the stream test still completes and the report marks this section unavailable.
Durable reports must not include raw process names, executable paths, source
titles, local usernames, or PIDs.

| Field | Status | Current Source |
| --- | --- | --- |
| Host load report | Required on stream-test reports | Top-level `hostLoad` JSON plus the Markdown `## Host/System Load` section and `host/system load` Diagnostic Coverage Matrix row |
| System CPU percent average/min/max | Required | Windows host-load sampler using OS processor load counters; report field `hostLoad.systemCpuPercent` |
| System memory used/available | Required | Windows host-load sampler using `Win32_OperatingSystem`; report fields `memoryUsedPercent` and `memoryAvailableMb` |
| GPU utilization by engine | Required on Windows stream tests | Windows `\GPU Engine(*)\Utilization Percentage` counters grouped into 3D/copy/video encode/compute; report fields `gpu3dPercent`, `gpuCopyPercent`, `gpuVideoEncodePercent`, and `gpuComputePercent` |
| GPU dedicated memory usage | Optional | Windows `\GPU Adapter Memory(*)\Dedicated Usage`; report field `gpuDedicatedMemoryMb` |
| App process CPU | Optional | Report field `appCpuPercent`; raw process IDs are used only in-memory for sampling and are not serialized |
| Target process CPU | Optional / Required when target PID is available | Report field `targetCpuPercent`; raw process IDs are used only in-memory for sampling and are not serialized |
| Sampler unavailable reason | Required when unavailable | Report field `hostLoad.unavailableReason`; counter failure must not fail the stream test |

## M. Capture Cause Attribution

These derived fields answer why a native capture call is slow before agents add
another backend or profile change:

| Field | Status | Current Source |
| --- | --- | --- |
| Full source acquisition size/ratio | Required | Native source/content/pre-encode sizes plus source-capture timing |
| Blocking acquire wait | Required | Native cadence acquire/callback/source/post/unaccounted buckets |
| CPU readback/copy work | Required | WGC map/copy-row/copy-texture timing, window-GDI requested capture mode, final producer counts, black/low-variance counts, print/bitblt/crop timing, and wrapper convert/scale timing |
| Dirty-region processing work | Required | Dirty-region shape plus dirty-region analysis timing |
| Frame lifetime/lock/synchronization | Required | Callback-entry, post-callback, unaccounted wait, and pacer frame-age fields |
| Full-frame copy before downscale | Required | Source/content/pre-encode pixel ratio plus wrapper convert/scale timing |

## N. Game-Capture Backend

These fields cover the D3D11 game-capture POC. Phase 2 emits them into
standalone local POC files under
`{LOCAL_GAME_CAPTURE_RESULTS_DIR}\`. Phase 3A also lets the
debug stream-test runner invoke the helper as a local probe for a selected
window PID, parse the resulting `metadata.json`, and include the evidence in
stream-test JSON, Markdown, and the diagnostic coverage matrix.
Phase 3B adds host shared-texture consumer evidence through
`host-consumer.json`, merged into the stream-test `gameCaptureProbe` report.
Phase 4A adds local publication-handoff evidence through
`publication-handoff.json`, also merged into `gameCaptureProbe`.
The Phase 4B debug path uses proof-only GPU texture handoff with an
optional encoder-compatible NV12 output probe. The helper scales into the
target BGRA D3D11 texture on each output tick, can convert that texture to
`DXGI_FORMAT_NV12` through the D3D11 video processor, and reads back only
requested proof PNGs / luma samples. Reports must distinguish this from older
all-frame BGRA readback probes. Hook-side PNG proof export is non-blocking and
may report busy frames; publication proof frames are the preferred visible
validation for the handoff output. Phase 4C adds a local Media Foundation
H.264 encoder proof fed from the scaled NV12 handoff texture. It is still
measurement-only: the helper writes a local MP4 proof and diagnostics, but it
does not create a WebRTC video source or publish to LiveKit.

The deterministic D3D11 capture target is separate from the probe. It is a
local test application launched by the stream-test UI when requested, rendered
through its own swap chain, selected as a normal window source, and reported as
top-level `gameCaptureTestTarget` evidence. It lets maintainers validate log fields,
source selection, capture cadence, and report parsing without launching BG3 for
every non-stress run.

The Phase 3A/3B/4A stream-test probe is still measurement-only. It does not
publish hook frames, alter LiveKit, replace WGC/window-GDI, change stream
profiles, or make D3D11 game capture user-facing.

Phase 4D adds a separate debug-only WebRTC source handoff. Unlike the
measurement-only probe, it can publish a selected BG3/window source through
the normal LiveKit screen-share path when the backend is explicitly
`game-d3d11-hook-experimental`. Its parsed native markers must be labeled
`game_capture_webrtc_source` and must override stale WGC/window-GDI marker
evidence in the same app log. After the first live attempt produced black
output, the contract requires both pre-I420 and post-I420 proof fields:
source/output dimensions, DXGI format, source/output FPS, proof frame count,
visible proof count, min/max luma, nonzero sample count, and proof BMP path.
The pre-I420 proof classifies the native acquisition/scale/color boundary; the
post-I420 proof reconstructs the exact buffer passed to WebRTC. Together these
fields decide whether black output begins before I420 conversion, during I420
conversion, or after WebRTC frame submission/encoding/rendering before any
behavior change is made. The June 5 follow-up also requires
`initialBlackSkipped` and `visibleSourceSeen` markers because live validation
showed the first sampled helper frame could be all-black while later pre-I420
frames were visible. Reports must preserve `game_capture_webrtc_source`
markers ahead of stale desktop-capturer marker tails.

The current Phase 4 native-NV12 extension keeps that backend debug-only but
changes the preferred WebRTC source boundary. The source now tries to submit a
GPU-scaled NV12-backed native handle to WebRTC before falling back to CPU I420.
Native NV12 frames must carry a stable per-frame texture lifetime, or an
equivalent explicit lifetime lease, before they are submitted to WebRTC. A
reusable GPU scratch-ring texture is valid as a video-processor target, but it
must not be the object wrapped by the native frame if the encoder may consume
that frame asynchronously after the source has reused the ring slot.
Reports must parse and display `nativeNv12Submitted`,
`nativeNv12Failures`, `nativeNv12ConvertMs`, `nativeNv12ConvertMaxMs`, and
`nativeNv12ConvertSamples`. A healthy native-NV12 source run should show
nonzero `nativeNv12Submitted`, zero `nativeNv12Failures`, zero or near-zero
legacy `readbackQueued`, and zero `cpuFallback`. For H.264, Media Foundation
markers must also show whether the encoder consumed the native frame through
`input_path=native_nv12`, `native_input=yes`, and
`native_sample_failed=no`; otherwise the source handoff may be fixed while the
encoder input boundary still falls back to CPU I420.

The June 9 encoder-handoff repair adds a separate Media Foundation drain
boundary. Reports must parse `outputs`, `output_bytes`, `queue`,
`retained_samples`, `encoded_outputs`, and `native_suspended` from encoder
timing markers. If native NV12 input is accepted with
`native_sample_failed=no` but produces no encoded output while queued/retained
samples grow, classify the run as `encoder_handoff_limited` instead of
retrying bitrate, LiveKit, fallback, receiver, or source-selection changes.
Repeated `stage=not_accepting` means Media Foundation is refusing additional
input before metadata can be queued, so queue-depth-only recovery may not fire.
`stage=not_accepting_recovered` plus
`action=reinitialize_cpu_i420_not_accepting` means the encoder instance has
hit the bounded not-accepting threshold, deliberately stopped using native NV12,
and reinitialized around the CPU I420 input path so the stream-test can
complete and report the boundary.

`native_suspended=yes` means the encoder instance has deliberately stopped
using native NV12 after either a bounded accepted-no-output stall or a bounded
not-accepting stall and has reinitialized around the CPU I420 input path.

After the black-output and helper-lifecycle boundary cleared, the same backend
exposed a performance limiter inside the WebRTC source: full-source 2560x1440
CPU map/scale/convert work held Smooth output around 15 FPS. The contract now
requires `gpuScaled`, `gpuScaleFailures`, `cpuFallback`, and `gpuScaleMs` for
`game-d3d11-hook-experimental` reports. A healthy GPU-scale run should show
nonzero `gpuScaled`, zero or near-zero `cpuFallback`, zero `gpuScaleFailures`,
and map/convert timings near the scaled output size rather than the native
source size. The follow-up async-readback boundary adds `readbackQueued`,
`readbackReady`, `readbackNotReady`, `readbackOverwritten`,
`readbackLatencyDropped`, `readbackMapAttempts`, `readbackLatencyMs`,
`readbackLatencyFramesAvg`, and `readbackLatencyFramesMax`; a healthy run
should drain queued scaled frames with minimal `readbackNotReady`/overwrite
pressure and one to two frames of latency rather than blocking the capture
thread on immediate `Map` or publishing stale ordered frames. A nonzero
`readbackLatencyDropped` means the WebRTC source intentionally discarded stale
pending readbacks to keep submitted motion current while preserving monotonic
source-frame order.

For debug source-local validation,
`intergalactic.gameCaptureWebrtcSourceSmoke.v1` reports may be used before a
live call. They exercise the same native WebRTC game-capture source without
Matrix/LiveKit and must record source/output size, `gpuScaled`,
`gpuScaleFailures`, `cpuFallback`, proof visibility, async readback queue/ready
state, readback latency, and map/convert timings. These smoke reports prove the
native source boundary only; they do not replace live sender/receiver
validation.

The June 8 Phase 2 source/readback proof extends the live
`game_capture_webrtc_source` marker beyond aggregate `sourceToSubmitMs`.
Reports must now parse and expose the full split:

- source QPC to readback-ready,
- readback queued/copy-complete to `Map` attempt,
- mapped BGRA/R10 data to I420 buffer completion,
- source QPC to I420-ready,
- source QPC to delivery queue insertion.

These fields appear in per-preset JSON, the native summary label, diagnostic
coverage as `game-capture stage timing`, bottleneck evidence, and
early/middle/late/tail window summaries. If they are missing from a D3D11
game-hook stream test, the report should request this exact missing field
instead of asking for another broad stream log.

The June 7 latest-ready readback repair adds an important interpretation rule:
when game-hook reports show many copied source frames, nonzero `gpuScaled`,
zero `cpuFallback`, and high `readbackNotReady` or
`readbackLatencyDropped`, the bottleneck is readback delivery pressure even if
source present cadence is healthy. Reports should not call that
source-present-limited unless copied/source cadence is also genuinely below
target and there is no readback backlog. After readback delivery is healthy,
remaining gaps between native capture FPS and encoded/sent FPS belong to the
sender/WebRTC encode queue classification, especially if native Media
Foundation timing markers are fast.

The local stream-pipeline harness is another measurement-only path. It writes
`intergalactic.localStreamPipelineHarness.v1` wrapper reports under
`{LOCAL_STREAM_LAB_RESULTS_DIR}\` by invoking the synthetic
D3D11 target and game-capture helper directly from
`tools/stream-lab/run_local_capture_benchmark.ps1`. Unlike the in-call
stream-test runner, this harness does not require Matrix login, room join,
call setup, or LiveKit publishing. It currently covers the D3D11 Present hook,
host shared-texture consumer, publication-handoff texture/proof path, and an
optional local Media Foundation H.264 encoder proof. Desktop WGC/window-GDI,
WebRTC sender integration, LiveKit/network, and receiver categories are marked
`notApplicable`, `unavailable`, or `notTested` in those reports.

`tools/stream-lab/run_native_capture_mf_isolation.ps1` is the decision wrapper
for the local native capture-to-Media Foundation boundary. It runs the local
benchmark with `PublicationOutputFormat=nv12`,
`PublicationEncoderProof=h264-mf`, `PublicationProofFrames=0`, and
`PublicationReadbackMode=proof-only`, then writes
`intergalactic.nativeCaptureMfIsolation.v1` reports. These reports classify the
local no-WebRTC gate as `passed_native_capture_mf_720p30`,
`failed_native_capture_mf_720p30`, or `inconclusive_native_capture_mf` and name
the next boundary without implying that Matrix, LiveKit, WebRTC sender,
network, or receiver behavior was tested.

`tools/stream-lab/run_webrtc_onframe_isolation.ps1` is the decision wrapper
for the local WebRTC game-capture source and `VideoCapturer::OnFrame`
boundary. It calls the native
`InterGalacticGameCaptureWebrtcSourceSmoke` export, preserves the source-smoke
JSON, links an optional native capture-to-MF report, and writes
`intergalactic.webrtcOnFrameIsolation.v1` reports. These reports must keep
Matrix, LiveKit, WebRTC sender, native encoded-frame handoff, network, and
receiver coverage false; a pass only proves the local source/OnFrame path and
routes the next boundary to sender or native encoded-frame integration.

`tools/stream-lab/run_native_sender_handoff_isolation.ps1` is the aggregate
decision wrapper for the current BG3/DX11 boundary. It links the native
capture-to-MF gate, the local WebRTC source-OnFrame gate, and an optional live
stream-test JSON. When local gates pass but the supplied live report still has
low sender FPS with slow live `deliveryOnFrameCallMs` or encoder handoff
timing, it writes `failed_live_sender_handoff` and routes the next decision to
dummy NV12 live-sender isolation before any custom encoded-frame design.

`tools/stream-lab/run_dummy_nv12_live_sender_isolation.ps1` is the decision
wrapper for the existing live raw-frame sender path. It writes a stream-test
automation request with `dummyNv12LiveSender=true` and
`gameCaptureSourceMode=dummy-nv12-live-sender`, then analyzes the resulting
stream-test JSON. It must expose `intergalactic.dummyNv12LiveSenderIsolation.v1`
status, copied report paths, source-mode confirmation, capture/encode/send FPS,
native NV12 submitted/failure/CPU-fallback counters, live
`deliveryOnFrameCallMs`, Media Foundation `ProcessInput`, bottleneck label, and
the next boundary. A pass proves the WebRTC/Media Foundation/LiveKit raw sender
can sustain 720p30 from already-ready native NV12; it does not prove BG3 helper,
R10 conversion, or game-frame readiness.

| Field | Status | Current Source |
| --- | --- | --- |
| Local harness wrapper schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/*/local-capture-benchmark.json` |
| Local harness Matrix/LiveKit/network/receiver tested flags | Diagnostic-only | `local-capture-benchmark.json` top-level booleans |
| Local harness coverage map | Diagnostic-only | `local-capture-benchmark.json.coverage` and Markdown coverage table |
| Native capture-to-MF isolation schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/**/native-capture-mf-isolation.json` |
| Native capture-to-MF isolation boundaries | Diagnostic-only | `native-capture-mf-isolation.json.boundaries`; Matrix, LiveKit, WebRTC sender, network, and receiver are false |
| Native capture-to-MF isolation gate result | Diagnostic-only | `native-capture-mf-isolation.json.status`, `failingGates`, `missingEvidence`, `warnings`, `nextBoundary`, and `recommendation` |
| Native capture-to-MF isolation evidence | Diagnostic-only | `native-capture-mf-isolation.json.evidence` with source format, Present FPS/gaps, handoff FPS/gaps, NV12 conversion, and local MF encoder-proof timing/output bytes |
| WebRTC source-smoke schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/**/webrtc-source-smoke.json` |
| WebRTC source-smoke startup diagnostics | Diagnostic-only | `webrtc-source-smoke.json` fields `startupFailureReason`, `helperOutputRoot`, `helperExitedBeforeSharedState`, `helperExitCodeAvailable`, `helperExitCode`, and `openSharedStateWaitMs` |
| WebRTC OnFrame isolation schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/**/webrtc-onframe-isolation.json` |
| WebRTC OnFrame isolation boundaries | Diagnostic-only | `webrtc-onframe-isolation.json.boundaries`; `webRtcSourceOnFrameTested` may be true while Matrix, LiveKit, WebRTC sender, native encoded-frame handoff, network, and receiver remain false |
| WebRTC OnFrame isolation gate result | Diagnostic-only | `webrtc-onframe-isolation.json.status`, `failingGates`, `missingEvidence`, `warnings`, `nextBoundary`, and `recommendation` |
| WebRTC OnFrame isolation FPS evidence | Diagnostic-only | `webrtc-onframe-isolation.json.evidence.fixedWindowDeliveryFps`, `measuredDeliveryFps`, and `gateDeliveryFps`; measured delivery cadence is preferred when native wall-delta samples are present because fixed requested-duration counts include helper/source startup time |
| WebRTC OnFrame isolation timing evidence | Diagnostic-only | `webrtc-onframe-isolation.json.evidence` fields for delivery queue wait, `deliveryOnFrameCallMs/MaxMs`, native buffer release, source-to-submit, native NV12 conversion, Blt-to-ready, visible proof frames, and linked native-MF status |
| Native sender handoff isolation schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/**/native-sender-handoff-isolation.json` |
| Native sender handoff isolation gate result | Diagnostic-only | `native-sender-handoff-isolation.json.status`, `missingEvidence`, `nextBoundary`, and `recommendation`; statuses include `passed_local_sender_prerequisites`, `failed_live_sender_handoff`, `failed_local_sender_handoff_prerequisite`, `passed_live_sender_handoff`, and `inconclusive_native_sender_handoff` |
| Native sender handoff isolation evidence | Diagnostic-only | `native-sender-handoff-isolation.json.evidence.nativeMf`, `.evidence.webrtcOnFrame`, and optional `.evidence.liveStream`; live comparison records bottleneck label, capture/encode/send FPS, live OnFrame timing, native NV12 failures/fence counters, CPU fallback, and whether the stream-test report contained the sender handoff diagnostic block |
| Dummy NV12 live sender isolation schema/status/path | Diagnostic-only | `runtime/stream-lab/local-results/**/dummy-nv12-live-sender-isolation.json` |
| Dummy NV12 live sender isolation gate result | Diagnostic-only | `dummy-nv12-live-sender-isolation.json.status`, `nextBoundary`, and `minSustainedFps`; statuses include `passed_dummy_nv12_live_sender_720p30`, `failed_dummy_nv12_live_sender_720p30`, `failed_dummy_nv12_live_sender_native_nv12_unhealthy`, `failed_dummy_nv12_live_sender_automation`, and `inconclusive_dummy_nv12_live_sender_*` |
| Dummy NV12 live sender isolation evidence | Diagnostic-only | `dummy-nv12-live-sender-isolation.json.evidence` with `dummyConfig`, `sourceMode`, capture/encode/send FPS, native NV12 submitted/failures, CPU fallback frames, `averageDeliveryOnFrameCallMs`, `averageEncoderProcessInputMs`, and bottleneck label |
| Deterministic target requested | Diagnostic-only | Stream-test `config.gameCaptureTestTarget.enabled` |
| Deterministic target process/window metadata | Diagnostic-only | `gameCaptureTestTarget.processIdAvailable`, `config.title`, selected source metadata |
| Deterministic target scene/mode/size/FPS | Diagnostic-only | `gameCaptureTestTarget.config` and target `capture-target.json` |
| Deterministic target Present FPS/gaps | Diagnostic-only | `tools/game-capture-target` `capture-target.json`, merged into stream-test `gameCaptureTestTarget.diagnostics` |
| Deterministic target late/missed frames | Diagnostic-only | `capture-target.json` |
| Deterministic target auto-selection result | Diagnostic-only | Stream-test `gameCaptureTestTarget.selectedAutomatically` |
| Requested game-capture backend | Diagnostic-only | Phase 2/3A POC `metadata.json` and stream-test `gameCaptureProbe` |
| Probe timing | Diagnostic-only | Stream-test `gameCaptureProbe.config.timing`; `standalone` for probe-only runs or `concurrentWithInitialPreset` when run beside the first LiveKit preset |
| Hook attach status | Diagnostic-only | Phase 2/3A helper result `metadata.json` |
| Hook attach error code/category | Diagnostic-only | Phase 2 helper `summary.md` / `helper.log` |
| Target PID hash | Diagnostic-only | Phase 2 helper result metadata; raw PID is not written to normal result files |
| Target process architecture | Diagnostic-only | Phase 2 helper process inspection |
| Target elevation/protection compatibility | Diagnostic-only | Phase 2 helper process access/integrity checks |
| Helper architecture | Diagnostic-only | Phase 2 CMake x64 helper artifact |
| Hook DLL architecture | Diagnostic-only | Phase 2 CMake x64 hook DLL artifact |
| Detected graphics API | Diagnostic-only | Phase 2/3A hook `metadata.json` and `present-events.jsonl` |
| Present FPS | Diagnostic-only | Phase 2/3A hook `metadata.json` / `summary.md` |
| Present p50/p95/max gaps | Diagnostic-only | Phase 2/3A hook `metadata.json` / `summary.md` |
| Present frame count | Diagnostic-only | Phase 2/3A hook `metadata.json` / `present-events.jsonl` |
| Backbuffer width/height/format | Diagnostic-only | Phase 2/3A hook `metadata.json` / `present-events.jsonl` |
| Shared texture width/height/format | Diagnostic-only | Phase 2 hook ring/backbuffer metadata |
| Shared texture ring depth | Diagnostic-only | Phase 2 hook `metadata.json` / `present-events.jsonl` |
| Active ring slot | Diagnostic-only | Phase 2 hook `present-events.jsonl` |
| Copy time | Diagnostic-only | Phase 2 hook `metadata.json` / `present-events.jsonl` |
| Resolve time | Diagnostic-only | Phase 2 hook `metadata.json` / `present-events.jsonl` |
| Dropped frames | Diagnostic-only | Phase 2 hook `metadata.json` / `present-events.jsonl` |
| Overwritten frames | Diagnostic-only | Phase 2 hook `metadata.json` / `present-events.jsonl` |
| CPU readback count | Diagnostic-only | Phase 2 hook local PNG export metadata |
| CPU readback time | Diagnostic-only | Phase 2 hook local frame export timing |
| Resize/device-loss count | Diagnostic-only | Phase 2 hook ring recreation count |
| Fallback reason | Diagnostic-only | Phase 2 helper/hook result metadata |
| Hook stop reason | Diagnostic-only | Phase 2 hook result metadata |
| Local validation output path | Diagnostic-only | Phase 2 helper console output and result folder; Phase 3A stream-test report path |
| Visible-frame validation result | Diagnostic-only | Phase 2/3A hook saved/visible frame counts and preview frames |
| Host shared-texture consumer enabled | Diagnostic-only | Phase 3B helper `host-consumer.json`; stream-test `gameCaptureProbe.hostTextureConsumer.enabled` |
| Host shared-state availability | Diagnostic-only | Phase 3B helper shared mapping result |
| Host D3D11 device creation | Diagnostic-only | Phase 3B helper consumer result |
| Host opened shared texture | Diagnostic-only | Phase 3B helper `OpenSharedResource` result |
| Host opened texture slots | Diagnostic-only | Phase 3B helper consumer result |
| Host shared-texture open failures | Diagnostic-only | Phase 3B helper consumer result |
| Host observed frame signals | Diagnostic-only | Phase 3B frame-ready event count |
| Host consumed frames | Diagnostic-only | Phase 3B unique consumed frame count |
| Host duplicate signals | Diagnostic-only | Phase 3B duplicate frame-ready/event count |
| Host missed frames | Diagnostic-only | Phase 3B inferred missed frame-index gaps |
| Host frame age avg/p95/max | Diagnostic-only | Phase 3B helper QPC age from hook latest-frame timestamp |
| Host consumer gap p50/p95/max | Diagnostic-only | Phase 3B helper gap timing between consumed frame timestamps |
| Host proof readback count | Diagnostic-only | Phase 3B optional low-count CPU readback proof |
| Host visible proof frames | Diagnostic-only | Phase 3B optional sampled-content visibility proof |
| Host proof readback timing | Diagnostic-only | Phase 3B optional proof-only staging map timing |
| Host consumer health | Diagnostic-only | Derived in stream-test report from shared state, D3D device, opened texture, consumed frame, open-failure, and invalid-state evidence |
| Publication handoff enabled | Diagnostic-only | Phase 4A helper `publication-handoff.json`; stream-test `gameCaptureProbe.publicationHandoff.enabled` |
| Publication handoff target width/height/FPS | Diagnostic-only | Phase 4A helper CLI/config and `publication-handoff.json` |
| Publication source texture width/height/format | Diagnostic-only | Phase 4A helper opened shared-texture metadata |
| Publication output width/height | Diagnostic-only | Phase 4A/4A.5/4B contain-fit output metadata |
| Publication output format | Diagnostic-only | Phase 4B helper `outputFormat`, currently `bgra` or `nv12` |
| Publication encoder format | Diagnostic-only | Phase 4B helper `encoderFormat`, currently `DXGI_FORMAT_NV12` for the NV12 probe or `none` for BGRA proof mode |
| Publication scale mode | Diagnostic-only | Phase 4A/4A.5/4B helper output mode, currently `contain_fit_gpu_before_readback` for BGRA proof and `contain_fit_gpu_scale_then_video_processor_nv12` for the NV12 probe |
| Publication readback mode | Diagnostic-only | Phase 4B helper `readbackMode`, currently `proof-only` for GPU texture handoff proof and `all` for legacy all-frame BGRA readback |
| Publication proof output directory | Diagnostic-only | Phase 4B helper `proofOutputDirectory` when proof PNGs are requested |
| Publication requested proof frames | Diagnostic-only | Phase 4B helper `requestedProofFrames`; clamped by the native proof-frame limit |
| Publication input/output/visible frame counts | Diagnostic-only | Phase 4A helper handoff counters |
| Publication paced-drop count | Diagnostic-only | Phase 4A helper target-FPS pacing counter |
| Publication repeated-output count | Diagnostic-only | Phase 4A helper `repeatedOutputFrames` when the target-cadence sampler emits the latest available source frame again |
| Publication output FPS and p50/p95/max gaps | Diagnostic-only | Phase 4A helper output buffer cadence |
| Publication frame age avg/p95/max | Diagnostic-only | Phase 4A helper QPC age from hook latest-frame timestamp |
| Publication readback avg/p95/max | Diagnostic-only | Phase 4A.5 scaled-output staging copy/map timing; in Phase 4B `proof-only` mode this describes proof readbacks only, not continuous per-frame handoff cost; older Phase 4A reports used full-source staging timing |
| Publication scale avg/p95/max | Diagnostic-only | Phase 4A.5 GPU scale submission timing; older Phase 4A reports used CPU contain-fit scale timing |
| Publication total handoff avg/p95/max | Diagnostic-only | Handoff frame timing for scale, optional readback, and buffer/proof bookkeeping; in `proof-only` mode this must not be interpreted as all-frame CPU readback cost |
| Publication readback failure count | Diagnostic-only | Phase 4B helper `readbackFailures` |
| Publication proof output frames | Diagnostic-only | Phase 4B helper `proofOutputFrames` |
| Publication visible proof output frames | Diagnostic-only | Phase 4B helper `visibleProofOutputFrames` |
| Publication proof output write failures | Diagnostic-only | Phase 4B helper `proofOutputWriteFailures` |
| Publication NV12 texture created | Diagnostic-only | Phase 4B helper `nv12TextureCreated` |
| Publication NV12 output frames | Diagnostic-only | Phase 4B helper `nv12OutputFrames` |
| Publication NV12 conversion failures | Diagnostic-only | Phase 4B helper `nv12ConvertFailures` |
| Publication NV12 convert avg/p95/max | Diagnostic-only | Phase 4B D3D11 video-processor conversion timing |
| Publication NV12 proof readback frames | Diagnostic-only | Phase 4B helper `nv12ProofReadbackFrames` |
| Publication NV12 visible proof frames | Diagnostic-only | Phase 4B helper `nv12VisibleProofFrames` luma-sampling validation |
| Publication NV12 proof readback avg/p95/max | Diagnostic-only | Phase 4B optional proof-only NV12 staging readback timing |
| Publication D3D11 video-processor capability probe | Diagnostic-only | Phase 4B helper fields `videoProcessorProbeAvailable`, `videoProcessorBgraInputSupported`, `videoProcessorR10InputSupported`, `videoProcessorNv12OutputSupported`, `videoProcessorP010OutputSupported`, `videoProcessorBgraToNv12Supported`, `videoProcessorR10ToNv12Supported`, and `videoProcessorR10ToP010Supported`; proves whether the local adapter advertises the R10/BGRA to NV12/P010 conversion combinations before interpreting a failed handoff as a code-path failure |
| Hook proof export busy frames | Diagnostic-only | Phase 4B hook `proofExportBusyFrames`; non-blocking hook-side PNG export skipped because the staging texture was still drawing |
| Local encoder proof mode | Diagnostic-only | Phase 4C helper `encoderProofMode`, currently `off` or `h264-mf` |
| Local encoder proof codec/container/path | Diagnostic-only | Phase 4C helper `encoderProofCodec`, `encoderProofContainer`, and `encoderProofOutputPath` |
| Local encoder proof enabled/initialized/finalized | Diagnostic-only | Phase 4C helper lifecycle booleans |
| Local encoder proof hardware transforms requested | Diagnostic-only | Phase 4C Media Foundation sink-writer attribute |
| Local encoder proof submitted frames | Diagnostic-only | Phase 4C helper `encoderProofFramesSubmitted` |
| Local encoder proof write failures | Diagnostic-only | Phase 4C helper `encoderProofWriteFailures` and first/last error fields |
| Local encoder proof GPU-copy frames | Diagnostic-only | Phase 4C helper `encoderProofGpuCopyFrames` |
| Local encoder proof output bytes | Diagnostic-only | Phase 4C helper `encoderProofOutputBytes` after sink-writer finalize |
| Local encoder proof init/submit/GPU-copy/finalize timing | Diagnostic-only | Phase 4C helper timing fields |
| Local encoder proof readback suppression | Diagnostic-only | Phase 4C helper `proofReadbackSuppressedForEncoder`; encoder proof should run with zero publication proof frames |
| Publication handoff health | Diagnostic-only | Derived in stream-test report from shared state, D3D device, opened texture, output frames, visible output, error evidence, and target-cadence threshold |

## O. Stream-Test Failure and Automation Artifacts

Stream-test failures must be reportable even when the runner throws before any
per-preset sample can be finalized. In that case the report uses the normal
`intergalactic.streamTestRun.v1` schema with:

- top-level `error` set,
- an empty `presetResults` list,
- `Run status: failed` and `Run error` in Markdown,
- recent app/native diagnostic markers capped and redacted through the same
  marker path used by successful reports.

Automation completion must mark such runs as `status=failed` while still
linking the JSON/Markdown failure report when it was written. A hard app crash
or exit before completion may leave a `.running.json`; stale-running cleanup
must convert it into a failed `.complete.json` with the safe request summary.
Those files are diagnostic breadcrumbs, not raw logs: record booleans such as
`sourceProcessIdSet`, `sourceTitleSet`, and `runningPathSet` instead of raw
PIDs, titles, or local filesystem paths.

## Instrumentation Gate

New stream instrumentation is allowed only when all are true:

1. This contract lists the field as missing, planned, or unavailable.
2. The missing field blocks a bottleneck classification.
3. No existing source can provide it.
4. The implementation adds the field to the schema, parser, JSON, Markdown, and
   coverage matrix in the same change.

One-off stream logs that are not parsed into the report are not accepted.
