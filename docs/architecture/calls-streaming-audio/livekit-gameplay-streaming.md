# LiveKit Gameplay Streaming

Status: Active architecture reference
Owner: EXPERIMENTAL for streaming behavior; DOCUMENTATION for structure
Last reviewed: 2026-07-03 by EXPERIMENTAL for call connection health

This note records the client-side streaming defaults for Inter Galactic's
gameplay-heavy LiveKit rooms.

## Related Docs

- `README.md` explains why each calls/streaming/audio doc is separate and which
  doc should be treated as current for a given question.
- `streaming-guidance-status.md` maps the current streaming state against the
  May 20 frame-cadence guidance and lists the next implementation steps.
- `stream-optimization-report.md` records the running stream-quality evidence
  and tuning history.
- `stream-diagnostic-contract.md`, `stream-receiver-diagnostic-contract.md`,
  and `stream-bottleneck-classification.md` define the current stream-test
  schema and interpretation rules.
- `archive/stream-diagnostics-gaps.md` and
  `archive/livekit-streaming-performance-plan.md` preserve the earlier
  diagnostics-gap and baseline-plan history.

## Ownership

- LiveKit-backed group calls are implemented under
  `intergalactic/lib/client/matrix/components/voip_room/`.
- Direct Matrix 1:1 calls remain under
  `intergalactic/lib/client/matrix/components/voip/` and should not be
  converted to LiveKit as part of gameplay streaming work.
- Shared VoIP abstractions live under
  `intergalactic/lib/client/components/voip/`.

## Call Connection Health

The call panel reads passive connection health from
`VoipCallDiagnosticsSnapshot.callHealth`. This snapshot is intentionally
sanitized and user-facing: participant rows use `local` and `remote_N` ids,
collapsed labels are phrased as call status (`Call good`,
`Call slightly unstable`, `Someone's connection is poor`, `Reconnecting...`,
`Audio issue detected`, `Call disconnected`, or `Call status unknown`), and
developer-only details expose issue codes without raw Matrix room ids, Matrix
user ids, tokens, source titles, or local paths.

LiveKit-backed sessions update the health snapshot from room
reconnect/disconnect lifecycle events, participant connection-quality updates,
current participant connection quality, remote microphone
publication/subscription/sink state, local playback volume overrides, and the
same remote-audio reconciliation policy used for active remote microphone
repair. Direct Matrix 1:1 sessions map only their session lifecycle into the
same model; they do not synthesize LiveKit participant quality. This layer must
not change LiveKit connection behavior, stream subscription policy, audio
routing, mute persistence, volume persistence, or AUDIO-owned microphone
suppression behavior.

UI consumers should subscribe to `VoipSession.onDiagnosticsChanged` rather than
adding a second call-state stream. Rebuilt two-client smoke should verify the
indicator across stable, degraded, reconnecting, disconnected, and remote-audio
issue states before closing the integration queue follow-up.

## Current D3D11 Gameplay Status

The current 2026-06-19 BG3 receiver baseline keeps the DX11 game-hook Smooth
720p path on Windows hardware H.264 and uses CBR as the experimental Media
Foundation rate-control default. CBR was promoted after an external receiver
A/B raised average delivered bitrate from about `0.7 Mbps` to `2.6 Mbps`
without failing the true receiver freshness gate:
`source-live-call-freshness-20260619-162443` passed at `29.183` unique FPS
with `rate_control_mode=cbr`, high single-layer H.264 subscription, clean
network evidence, and an attached/visible `1280x720` renderer. The open
runtime work is still native NV12 readiness tail and sender queue/drop
reduction, not receiver auth, server routing, codec replacement, or another
profile sweep.

Historical 2026-06-15 Live Testing Override evidence closed after the DX11
game-hook Smooth
720p branch reached the average product gate twice in BG3. The current
source-adapter baseline is the narrow WebRTC source-adapter branch:
already-sized Inter
Galactic D3D11 native NV12 helper frames may bypass only capturer-level
framerate adapter drops when an active sink exists and no resolution
adaptation is required. Normal I420/window capture, dummy NV12 controls,
receiver policy, SDR/HDR settings, and custom encoded-frame handoff
remain outside that branch.

Validation baseline:
`stream-test-2026-06-16T02-32-02-321672Z` reached about
`31.6 / 29.9 / 30.3` capture/encode/send FPS, and confirmation
`stream-test-2026-06-16T02-33-32-152165Z` reached about
`31.0 / 29.4 / 30.2` at visible/color-correct 1280x720 with native NV12
failures `0`, CPU-I420 fallback `0`, clean network, effectively zero MF fence
wait, sub-millisecond `OnFrame`, and `source_adapter_drops=0`.

Productization remains review-gated by classifier/report cleanup and native
tail-spike attribution. Do not broaden into DX12, Vulkan, 1080p/60 FPS,
receiver/server changes, or public game-capture UI work from this evidence.

## Camera Publish Lifecycle

Participant cameras use the LiveKit room path, but Inter Galactic publishes
camera tracks manually instead of calling `setCameraEnabled(true)`. The manual
path keeps camera capture lightweight at 640x360/15 FPS, VP8, backup codec
disabled, maintain-framerate degradation, and a single sender layer. Gameplay
screen sharing owns the high-resolution and hardware-first media path.

Camera stop must explicitly unpublish every local `TrackSource.camera`
publication and stop the corresponding local track. Do not use
`setCameraEnabled(false)` for the manual camera path: in the current LiveKit
Flutter SDK that mutes and stops capture but leaves the publication in the
local participant publication map. After a stop/re-enable cycle, diagnostics
can then show stale camera senders with zero captured, encoded, or sent frames.
Camera enable should first clear stale camera publications, then create and
publish a fresh camera track. Start/stop requests are serialized so rapid UI
toggles cannot overlap local track teardown and publish negotiation.

## Direct Matrix Camera Lifecycle

Direct Matrix 1:1 calls still use `MatrixVoipSession` and the Matrix SDK call
session, not LiveKit. The direct-call camera-off path must do more than send
muted metadata: `setLocalVideoMuted(true)` updates SDP stream metadata and
disables tracks, but it does not release an already inserted camera capture
track. Inter Galactic therefore mutes the Matrix metadata first, then removes
and stops local video tracks from the usermedia `MediaStream` while preserving
the microphone audio track. Re-enabling camera can then insert a fresh video
track into the existing direct-call usermedia stream. Direct-call camera
enable/disable requests are serialized for the same reason as the LiveKit path:
async track teardown must not be allowed to remove a camera track after a newer
re-enable request has already observed the old track and unmuted metadata.

## Screen-Share Profiles

`ScreenShareQualityProfile` is the source of truth for normal user-facing
screen-share quality.

- `smooth` is the default: 1280x720, 30 FPS, VP8, 1.8 Mbps,
  maintain-framerate degradation, backup codec disabled, with a 240p/30 FPS/
  350 kbps lower simulcast layer. Smooth should avoid fallback unless sender,
  encoder, or transport evidence shows fallback can actually help because
  recent gameplay logs showed lower requested resolutions did not improve a
  capture-limited 13-17 FPS stream.
- `balanced` is opt-in: 1920x1080, 30 FPS, 4 Mbps.
- `highQuality` is experimental opt-in: 1920x1080, 60 FPS, 6 Mbps.
- On Windows, normal presets prefer the hardware-first H.264 path by default
  again after the 2026-05-20 window-geometry fix. The black-window failure was
  not H.264-only: VP8 with the hardware preference off still failed for
  non-borderless window sources while display capture worked. The hardware
  path uses gameplay-tuned bitrate ceilings: Smooth 3 Mbps, Balanced 8 Mbps,
  and High Quality 18 Mbps. Smooth/Balanced hardware-first H.264 keep a 30 FPS
  target and bitrate floors so high-motion scenes do not collapse into
  sub-megabit send rates. Window/game captures keep the 36 FPS sender cap that
  helped prior 2K BG3 window validation, but Windows display captures use the
  30 FPS target as the sender/capture cap after later display tests showed the
  36 FPS loop overdriving desktop capture acquisition and causing visible
  pacing gaps. Smooth was reduced from 5 Mbps to 3 Mbps after fresh 2K BG3
  gameplay validation showed 3 Mbps held 30 FPS where 5 Mbps did not. Floors
  are Smooth 2.5 Mbps, Balanced
  4 Mbps, and High Quality 6 Mbps. Users/developers can still disable the
  preference for explicit VP8/software fallback tests. Media Foundation H.264
  now uses CBR by default for this Windows path; developers can temporarily set
  `INTERGALACTIC_MF_H264_RATE_CONTROL_MODE=unconstrained_vbr` or another
  supported mode for explicit A/B diagnostics.
- Windows window sources apply two source-specific protections before publish:
  profiles that would use simulcast publish single-layer for
  `SourceType.Window`, and the native capturer emits a stable preset-sized
  encoder canvas with contain-fit content centered inside it. This lets a
  normal window client area such as `1920x1048` publish as `1920x1080` without
  crop or stretch, while display capture keeps the dynamic contain-fit path.
- Windows non-developer window/app defaults and obvious browser/non-game
  windows resolve to the DirectX/window-GDI compatibility path. Developer-mode
  game-like app-default window shares may resolve to the D3D11 hook when a
  process id is available; that path has safe DirectX/window-GDI fallback for
  automatic selection, while explicit D3D11 diagnostics still fail loudly.
  WGC-only comparison paths still request Force full-frame dirty regions.
  Display shares, DirectX/window-GDI diagnostics, and hidden crop diagnostics
  keep Auto dirty-region behavior.
- On non-Windows platforms, normal presets remain VP8 by default.
- Legacy raw bitrate, FPS, codec, resolution, and simulcast preferences only
  take effect when the developer advanced stream override is enabled. Preset
  VP8 profiles keep simulcast enabled so stale hidden developer preferences
  cannot silently turn Smooth into single-layer publishing.
- Developer advanced stream override also has a Windows hardware-encoder
  toggle. When enabled, the override keeps the developer bitrate, FPS, and
  resolution controls but forces single-layer H.264 first so the same
  MediaFoundation hardware path can be tested without leaving advanced mode.
  When disabled, the explicit advanced codec and simulcast toggle apply.

VP8 and explicitly chosen H264 advanced profiles can use two-layer simulcast.
Windows hardware-first H264, VP9, and AV1 are single-layer/SVC-style choices.

## Subscriber Quality Policy

The call view applies receive priority through `VoipStream.setReceivePriority`.

- Hidden remote video is disabled/unsubscribed at the LiveKit publication
  level, not merely hidden in the widget tree.
- Screenshare hide/reveal state is keyed by a stable tile identity rather than
  the LiveKit publication SID, so fallback/profile republish does not hide a
  stream the user already revealed. The local call-control state is retained
  for the active session object so navigating away from and back to the call
  view does not reset revealed streams, hidden tiles, local mutes, or local
  participant volume. It is still local runtime state, not Matrix state or a
  persisted preference after the session ends. Local preview auto-hide is
  cancelled once the publisher manually shows or hides their own screenshare,
  and is also suppressed while the debug stream-test runner is active so the
  tester can visually confirm the live output. A manually revealed auto-paused
  local preview remains visible until the publisher hides it again; the tile
  may show a compact performance warning while that preview renderer is active.
- Focused, fullscreen, and popped-out streams request high quality.
- While an in-app fullscreen stream route is open, the call view tracks that
  tile as an active visible receiver surface. Later grid rebuilds or
  hidden-tile policy must not disable or downgrade the fullscreen stream's
  subscription or paired screenshare-audio visibility mute state; closing
  fullscreen releases the hold back to normal call-view priority policy.
- Visible non-focused screen shares request medium quality, or low quality when
  several screen shares are visible, while keeping a 30 FPS receive target and
  letting the SFU/layer choice reduce resolution instead of motion.
- Hidden screenshare tiles also locally mute their paired screenshare/shared
  content audio stream and unmute it when the tile is revealed again. Hiding a
  participant camera tile must not mute that participant's microphone audio.
  Incoming screen-share audio should start muted until the matching video tile
  is visible; this covers the race where the separate `screenShareAudio`
  publication arrives before the screen-share video tile is built. Disposing a
  `CallView` while the call remains active must not unmute audio that was muted
  only because its tile is hidden. Restoring a saved screen-share audio volume
  must preserve any visibility mute, and hidden shared-content audio should
  reassert visibility mute if another local mute/unmute path clears the backing
  local mute while the tile remains hidden. A new default-muted shared-audio
  publication must be unmuted when its matching tile is already visible. Audio
  publications remain subscribed/high priority so reveal can restore playback
  immediately.
- Screen-share/shared-content audio has local-only volume persistence separate
  from microphone participant volume. The preference key is room-local id plus
  remote stream user id plus `screenshareAudio`, values are clamped to
  `0.0..2.0`, and `0.0` means locally muted. Do not persist normal microphone
  participant volume through this path.
- Remote microphone participant volume/mute overrides are local call-view
  state keyed by Matrix user id, not LiveKit publication SID. They are reapplied
  whenever the backing local playback stream drifts away from the remembered
  value, including after LiveKit replaces an audio stream object during
  participant joins, microphone republishes, stream refreshes, or global
  speaker-volume baseline reapplication. That baseline must not overwrite a
  user mute/volume override, so a locally muted person does not become audible
  simply because another call track changed. These overrides are retained for
  the active session object across call-view rebuilds and participant
  leave/rejoin churn, but are intentionally not persisted after the session
  ends. If a stale replacement stream rejects a restore during teardown or
  churn, the failure is logged as recovered and the override is kept for the
  next healthy stream object. Direct Matrix DM call streams use the same
  `LocalPlaybackVolumeStream` contract for tile-level local playback volume,
  backed by Flutter WebRTC `Helper.setVolume` with an enable/disable fallback
  when direct track volume is unavailable.
- Remote microphone audio uses the same reconciliation policy in diagnostics
  and in the active LiveKit room session. On initial room snapshot, remote
  track publish/subscribe/unsubscribe, participant connect, and room reconnect,
  the session classifies incoming microphone audio as audible, unsubscribed,
  missing a stream/sink, locally user-muted, remotely muted, or local playback
  mute drift. While the session is active it can subscribe/enable missing
  remote mic audio, refresh or create the matching stream wrapper, restore local
  playback drift, and log recovered repair failures. Rebuilt two-client LiveKit
  smoke is still required before treating this path as fully validated.
- Receive priority application maps `disabled`, `low`, `medium`, and `high`
  through a pure helper before touching LiveKit publications. Developer stream
  diagnostics should log each video transition with the requested priority,
  applied LiveKit quality label, publication id/name/source, and whether the
  publication was subscribed/enabled or disabled/unsubscribed.

## Local Call Audio Controls

Voice and Video settings expose local microphone volume, speaker volume, and
Push to Talk controls that sit above both direct Matrix and LiveKit sessions.
Microphone volume is applied as a best-effort capture constraint when direct
WebRTC or LiveKit microphone capture is created or restarted. Speaker volume is
local playback only: LiveKit incoming audio uses local track volume, while
direct Matrix incoming audio uses the shared local playback volume interface
over Flutter WebRTC track volume and falls back to enabling/disabling the track
at zero volume. Speaker volume is a default playback baseline, not a user
override: active tile-level participant mutes or volume overrides take
precedence until the user returns that participant to the current baseline.
The speaker slider can boost above normal track gain up to `200%`, and the
default is `125%` so fresh installs are not quiet at default settings.
Direct Matrix incoming accept and outgoing invite paths must prepare the iOS
call-audio session before capture/signaling and then select the call output
route. When no saved output device is present, Android and iOS calls prefer the
speakerphone route while allowing Bluetooth to remain preferred when connected.
Tile-level participant volume in calls is also local playback state; it does
not signal Matrix, LiveKit, or remote participants.

Push to Talk is local state in `CallManager`. When enabled, sessions are muted
unless the `push_to_talk` system shortcut is currently held. The default PTT
keybind is Numpad Decimal. The shortcut uses separate key-down and key-up
callbacks, and disabling the preference releases any PTT-applied mute on active
sessions. PTT must not be implemented as Matrix room state or LiveKit server
state because it is a local input policy.
On Windows, app shortcuts must not use the normal `RegisterHotKey` path by
default because that OS registration reserves the key combo globally and can
swallow keys for other apps. Inter Galactic stores configured keybinds for
settings/display, but polls pass-through shortcut state instead. The app-owned
shortcut display and Windows virtual-key fallback table must be used instead of
debug-only key labels, because release/full builds can report some package
labels as unknown. PTT uses the call-scoped poller only while calls are active
so release can remute the call; other app shortcuts use the shared Windows
polling path without exclusive OS registration. If a Windows keybind cannot be
polled, it should be logged and ignored rather than treated as a usable PTT
trigger.
If PTT is enabled without a configured keybind, `CallManager` falls back to the
Numpad Decimal default. On Windows, PTT-enabled LiveKit joins must start muted
by skipping initial microphone publish. Holding the PTT key then runs the
guarded runtime microphone-enable path, and release/stale rollback must
detach the RTP sender with `RTCRtpSender.replaceTrack(null)` and reattach it
on the next press instead of calling LiveKit `publication.mute()`,
`setMicrophoneEnabled(false)`, or unpublishing/removing the local microphone
publication. That avoids the native `mediaStreamTrack.enabled = false` and
track remove/dispose paths that have terminated desktop builds while still
signaling normal LiveKit mute metadata to remote participants.
PTT mute application is desired-state driven in `CallManager`: session-state
notifications from LiveKit, participants, tracks, or the mute completion itself
must not reapply the same mute state. Keep one PTT mute operation in flight per
session and coalesce rapid press/release changes to the latest desired state.
Non-Windows PTT can continue through the normal session mute/unmute path unless
platform smoke shows the same native failure shape.

## Diagnostics And Fallback

Developer call/stream stats expose a `VoipCallDiagnosticsSnapshot` every two
seconds from the LiveKit session itself when enabled. LiveKit sender and
receiver diagnostics include resolution, FPS, bitrate, packet loss, jitter,
jitter-buffer delay, RTT, codec, encoder/decoder implementation, dropped or
decoded frames, quality limitation reason, simulcast/dynacast/adaptive status,
selected receive quality, selected ICE route summary, and the active profile.
Bitrate is reported as unknown for the first sample or stale counters instead
of showing fake `0kbps` values. Jitter-buffer delay is only shown when raw
WebRTC stats include emitted-count deltas, so the overlay displays a per-frame
average rather than the cumulative `jitterBufferDelay` counter.
Native LiveKit/flutter_webrtc sender stats can report timestamp deltas in
microseconds rather than the millisecond `RTCStats` shape used on web. The
diagnostics layer must normalize those deltas before calculating bitrate;
otherwise healthy hundreds-of-kbps sends can display as near-zero bitrate and
trip false adaptive fallback.

LiveKit call rooms and direct Matrix calls write a scoped pending native-action
crash marker before microphone enable, PTT runtime microphone enable or local
microphone sender detach/reattach, and screen-share start/stop. The marker is cleared after
successful or
handled-failure completion, so normal call-room movement and recovered
call-action errors should not produce a next-launch crash prompt. This
diagnostic guard does not change screen-share profiles, adaptive fallback,
bitrate limits, or call pipeline rate limiters.
Direct Matrix screen-share replacement keeps the outer screen-share-start
marker active while it stops the previous share, because the pending crash
store has a single marker file and a nested stop marker would overwrite the
replacement-start source before the new stream is published.
Desktop LiveKit call joins also write the native join marker before entering the
room setup path. The initial LiveKit microphone publish writes its own
native-action marker and logs start, completion, timeout, late failure, and
stale-rollback breadcrumbs. On Windows, an initial microphone-enable timeout
lets the call UI continue while the native publish future is still observed;
late completion is checked against the current call/microphone intent and is
force-disabled when the user muted or left before it resolved. The primary
LiveKit room session logs reconnect, reconnect-attempt, reconnected, and
unexpected final disconnect events, then runs the existing call cleanup if
LiveKit reports a final disconnect while the session is not already ending.
PTT should not add a LiveKit-backend mute step to the join sequence. On Windows,
PTT-enabled joins log `windows_push_to_talk_join_muted`, then PTT key-down
publishes the microphone through the guarded runtime enable path and key-up
detaches the microphone RTP sender while keeping the local track alive. Crash
reports from this path should identify runtime microphone enable or PTT
microphone sender detach/reattach, not the generic LiveKit publication mute or
local-track unpublish path.

Developer mode also exposes an automated stream test runner from the call
diagnostics menu. The runner is measurement-only: it uses the current connected
LiveKit call as the local test scenario, prompts for one existing
screen/window/game source, cycles the selected existing presets for a configured
duration, waits through a configurable warmup window before sampling, forces a
diagnostics sample every second, and writes paired JSON plus Markdown reports
under the app log directory's `stream-tests` folder. The warmup defaults to 5
seconds in the in-app runner so LiveKit/WebRTC startup ramp, first-keyframe
work, and encoder/BWE settling do not skew steady-state FPS scoring. The JSON
schema is `intergalactic.streamTestRun.v1` and records preset config,
warmup duration, per-second samples, score components, selected-source
metadata, capture/encode/send FPS summaries, pre-encode-dimension sample
availability, encode timing, send-queue delay, available outgoing bitrate,
sampled frame-pacing summaries, and errors.
Before each publish, the Windows desktop source cache is refreshed and the
selected source is rebound by id, then by normalized source title when needed.
This keeps long stream-test batches from relying on stale
`DesktopCapturerSource` ids after stop/start cycles.
The call diagnostics dialog can collapse into a compact top-right status panel
with an undimmed backdrop so the tester can watch the live stream while the
runner continues. It auto-collapses after a stream-test source is selected, and
the developer stats overlay visibility preference is remembered between calls.
While a run is active, the dialog reports the current preset/backend index, such
as `2/5 Balanced - WGC only`, so visual failures can be tied to the active test
without waiting for the exported report.
Windows desktop/window screen-share publishes enable the native latest-frame
pacer by default. The patched native capturer stores the newest scaled frame
and submits on the target cadence using
`intergalacticCaptureFramePacing=latest`. This avoids letting slow capture
callbacks push frames directly into WebRTC and build encode/send backlog. The
debug stream-test runner can still explicitly force the pacer off or on for
paired comparisons; exported reports record pacer submitted FPS, unique FPS,
p95/max submit gaps, frame age, `OnFrame` time, duplicate submissions,
overwritten frames, and skipped ticks.
Runner-triggered diagnostics sampling is observe-only by default: it records the
current adaptive fallback reason but does not apply adaptive fallback or
republish the active screen-share track while a preset/backend sample is being
measured. Normal in-call diagnostics still apply fallback through the regular
session stats update path when adaptive fallback is enabled.
Frame-pacing report fields are derived from cumulative WebRTC counters at the
runner sample cadence for capture, pre-encode proxy, encoded, sent, received,
decoded, and rendered stages; native capture uses desktop-capture cadence
markers when present. The runner's native-diagnostic window begins before the
preset publish call and spans warmup plus measured samples, so startup markers
emitted during warmup still attach to the preset while scored sample timestamps
begin after warmup. The runner snapshots native markers after each preset so
long multi-backend batches do not lose early native backend/acquire-wait
evidence when the final log tail only contains later presets. Stream-test
scoring treats `stable_fps` as average FPS capped by sender/native frame pacing
evidence, so long p95 frame intervals, large max gaps, or stale frame-counter
windows cannot be hidden by an otherwise decent average. The Markdown summary
labels the likely primary limiter as
`healthy`, `capture_limited`, `encode_limited`, `send_limited`,
`frame_pacing_unstable`, `network_limited`, `downgraded_layer`,
`no_sender_stats`, `runner_error`, or `unknown` based only on the collected
stats. This first harness does not auto-login, join rooms, retune profiles,
change saved stream preferences, or change fallback behavior.
Native Windows frame-timing markers also expose the shape of the backend dirty
region when available: updated-region rect count, max rect count, average and
max dirty-area ratio, full-frame update count, and tiny-update count. Stream
test reports render this as `Dirty Shape` so capture-limited runs can separate
full-frame source churn, fragmented dirty regions, tiny/no-op updates, and
unexplained backend wait before any new profile or bitrate tuning.
For WGC-backed Windows capture, native diagnostics also emit
`Inter Galactic WGC frame timing` markers. These split the WGC session below
the wrapper-level capture call into frame-pool empty/reuse counts,
source-capturable misses, startup sleeps, texture resize/recreate counts, and
timings for `TryGetNextFrame`, GPU copy, blocking map, row copy, monitor scale
lookup, and zero-hertz comparison. Stream-test reports parse this as
`WGC Substage`; when `native_capture_limited` is detected, use that field to
decide whether the next fix belongs in WGC frame availability, GPU readback,
dirty-region comparison, or outer callback dispatch.

The diagnostics intentionally separate failure layers. Sender stats should show
requested versus actual media settings, capture/encode/send FPS when WebRTC
emits the source counters, encode time, frame drop stage, target/actual/
available/retransmit bitrate, NACK/PLI/FIR counts, codec, encoder
implementation, and quality limitation reason. Receiver stats should show
decode/render FPS when exposed, received/decoded/rendered frames, dropped
frames, decode time, jitter-buffer average, freeze/pause counters, codec, and
decoder implementation. ICE diagnostics should show candidate type, protocol,
and address class so relay/TCP sessions are visible before server tuning is
blamed.

For sender video, the diagnostic line treats `actual` as the encoded sender
frame size and also labels it as `encoded_size` for capture-pipeline triage.
When raw WebRTC source stats expose dimensions, the same line adds
`pre_encode=<width>x<height>` and `pre_encode_fps` so Smooth/720p validation
can distinguish source/scaler cadence from encoder cadence. Receiver lines
label their current frame size as `received_size` and keep decode/render FPS
separate when exposed by WebRTC.

MatrixRTC call membership state also carries a namespaced
`chat.intergalactic.client_info` payload sourced from `BuildConfig`. The
developer overlay reads that state per participant so call debugging shows which
Inter Galactic app/version/platform each participant is running. Older or
non-Inter-Galactic clients are allowed and should render as an unknown client
rather than blocking diagnostics.

## Join And Rejoin Hardening

LiveKit room joins are serialized by the room component. If the user clicks
into a call while an existing join is still running, the second request reuses
the in-flight join instead of creating another LiveKit room connection and
MatrixRTC membership update. If the room already has an active non-ended
session, `joinCall()` returns that session.

The MatrixRTC room component listens to a session's connection-state stream for
ended-session cleanup. It should not use the broad session-state stream for
this cleanup path because that stream also fires for participant, track, and
media updates while the connection state remains `connected`.

For encrypted MatrixRTC rooms, the LiveKit backend performs a local E2EE trust
preflight before preparing audio, requesting the SFU token, writing local
MatrixRTC membership, or connecting LiveKit. If the current session is blocked,
unknown, or unverified while cross-signing is enabled, the join is blocked with
a verification-required message and redacted diagnostics instead of entering a
partial call state. This is a local safety gate; it does not alter MatrixRTC
membership format or LiveKit server grants.

The LiveKit Flutter SDK can throw a `ConnectException` labelled
`no internet connection` when its platform connectivity check observes a short
network or DNS wobble before the signal websocket opens. Inter Galactic treats
only transient connect failures as retryable and makes one short retry before
clearing local MatrixRTC membership. Authorization-style failures such as
not-allowed, unauthorized, forbidden, 401, or 403 remain terminal.

Failed joins clear local call state, notify listeners, and mark the local
membership key as locally cleared so the UI is not left in a stuck joining
state. The VoIP room view must guard async callbacks with `mounted` and must
not call `setState` from `build`, because call exit/reenter can dispose the
view while LiveKit token or focus lookups are still resolving.

The MatrixRTC auth service may reject the optional
`chat.intergalactic.client_info` token request metadata with HTTP 400 on older
server deployments. After the first rejection, the client caches that fallback
and requests tokens without client metadata until a later recovery probe
succeeds. MatrixRTC membership state still includes client info for diagnostics.

The MatrixRTC auth service also accepts the same
`chat.intergalactic.client_info` metadata in LiveKit token requests. When the
server-side Inter Galactic streaming restriction is enabled, clients missing
that metadata, publishing non-Inter-Galactic metadata, or reporting a version
below the configured minimum still receive join/subscribe and mic/camera publish
grants, but do not receive `screen_share` or `screen_share_audio` publish
sources. This keeps legacy Commet builds from bypassing Inter Galactic's
streaming caps while preserving basic call participation.

Developer mode also exposes a server audio loopback button during active
LiveKit calls. It creates a second subscriber-only LiveKit room connection using
a diagnostic device id, subscribes only to the current participant's microphone
publication, and plays back the received remote audio. This is intentionally not
a local monitor: the microphone must leave the app, pass through RNNoise/capture
processing, publish to the SFU, and return over the subscriber path before the
developer hears it. The loopback connection must not write MatrixRTC membership
state and must stop with normal call teardown.

Developer mode also exposes a call diagnostics menu from the active call
controls. This menu should not replace the stream overlay, full developer log
page, RNNoise settings readout, or share-session status controls. It is a
copyable aggregator for the evidence people need while in a call: call state,
RNNoise health, ShareSession/shared-audio status, the same stream-stat lines
used by the overlay, and recent related call/media log entries. Saved
diagnostics should keep route/SFU state such as adaptive stream, dynacast,
participants, server loopback, and ICE route separate from capture/encode/
render stats. Share-session diagnostics in the saved log should include source
type, short source-id hash, process id when resolved, requested audio mode,
shared-audio state, and reason; window/source titles remain redacted unless
developer stream diagnostics are enabled.

The local screen-share source picker thumbnails are the pre-publish source
previews, not remote stream previews. They depend on the Flutter WebRTC desktop
capturer returning thumbnails or later emitting `desktopSourceThumbnailChanged`.
The picker should keep showing a loading state for delayed native thumbnails,
log how many window/screen sources have thumbnail bytes, and request a source
refresh before falling back to placeholder icons. Do not remove these picker
previews when declining separate remote stream preview work.
The picker filters only known desktop widget or overlay window entries when
the Flutter WebRTC metadata exposes a reliable exact title match or a
conservative Rainmeter skin path fragment; screen sources and normal app
windows remain shareable.

Adaptive fallback is active by default for normal preset screen shares: Smooth,
Balanced, and High Quality. Advanced override remains explicitly manual unless
developer settings force fallback on. Fallback can lower active screen-share
sender limits after corroborated packet loss, encoder overload, a severe
sender-FPS collapse, or confirmed bitrate below target. WebRTC's raw
`bandwidth` label only becomes a network fallback when
supported by other transport evidence such as packet loss, lost packets, high
RTT, or repeated NACKs. Low available-outgoing bitrate by itself is not enough
to downshift a clean direct UDP hardware stream because recent logs showed the
estimator staying low even when the server and sender had headroom. WebRTC's
raw `cpu` label is also contextual: explicit healthy encode/drop/send-delay
counters suppress fallback, but missing-counter CPU labels can still trigger
after hysteresis, and severe FPS collapse remains an escape path. Do not
downshift only because hardware H.264 is sending 10-17 FPS on an otherwise
healthy direct route: recent gameplay logs showed that lowering requested
resolution/bitrate did not raise FPS, while raising the bitrate improved visual
quality. Smooth fallback reduces resolution before cutting frame rate so
gameplay motion stays as stable as possible. It waits for a longer stable
window before restoring the requested profile to avoid quality bouncing.

May 6 gameplay logs added a second guardrail: if adaptive fallback has already
requested a lower resolution but sender diagnostics still show a materially
larger encoded frame, the controller should log `resolution_mismatch` and hold
the current fallback profile instead of stacking more downshifts. This prevents
bitrate from being cut to 360p/240p values while WebRTC is still encoding the
larger 720p or 1080p frame. The next useful fix in that state is at the sender
limit/capture-scaling boundary, not another fallback threshold change.

May 19 evening gameplay logs added a third guardrail for native capture cadence:
when capture, encode, and send FPS all track below target on a clean network,
the fallback controller classifies the problem as `capture FPS below target`
before encoder-overload labels. That reason can downshift High Quality or
Balanced to Smooth and refresh the Windows native capture bounds, but it stops
at Smooth 1280x720 unless there is separate proof of packet loss/RTT/NACK
pressure, severe FPS collapse, or explicit encode/drop/send-queue pressure.
Lower 960/640/CPU-rescue modes remain available for those corroborated cases,
but clean capture-cadence stalls should not collapse a usable 720p stream into
540p or 360p.

If Smooth reaches its lowest normal fallback and the sender still reports CPU
limitation, the client enters CPU rescue. CPU rescue keeps the share alive but
uses the low simulcast target as the active sender layer (426x240, 20 FPS,
300 kbps) and disables non-low WebRTC sender encodings through
`RTCRtpEncoding.active`. This is a defensive software-encoder escape hatch for
logs where H.264 falls back to OpenH264 and the high layer keeps reporting
1080p despite lower Smooth requests. When the fallback controller restores the
requested profile, the session reactivates layers it disabled for CPU rescue.
Sender-limit application also treats any fallback profile whose main layer has
already collapsed to the configured low layer as low-layer-only, even if the
diagnostics label has not flipped to explicit CPU rescue yet. That prevents a
stale high simulcast RID from continuing to encode a full-resolution desktop
capture while the requested target is already 426x240.

Hardware-first streams that still report software encoders such as OpenH264 or
libvpx with `hardwareEncodeActive=false` are diagnostic evidence, not an
adaptive fallback reason by themselves. They become actionable only with
corroborating symptoms such as WebRTC CPU limitation, encode/drop/send-queue
pressure, severe FPS collapse, capture cadence collapse, or transport loss.
Some H.264 sender parameter sets omit RID labels, so sender-limit code infers
low/high layers by encoding index for logging and CPU-rescue activation. Logs
should show inferred labels like `q*`/`h*` in that case rather than repeated
unlabeled `main` encodings.

WebRTC's raw quality-limitation reason is displayed as `webrtc_limit` in
developer diagnostics. Treat `webrtc_limit:bandwidth` as estimator evidence,
not a confirmed root cause, unless it is corroborated by packet loss, lost
packets, high RTT, or repeated NACKs. Treat `webrtc_limit:cpu` as encoder or
capture-pipeline evidence, not proof of high whole-system CPU. It is actionable
when stats show encode overload, encoder/pre-encode drops, send-queue delay, a
severe send/encode FPS collapse, or when the stats surface omits those counters
and the CPU label is sustained through fallback hysteresis. If the same
snapshot shows direct UDP, near-zero loss, tiny RTT, no WebRTC limitation, and
software OpenH264/libvpx, the encoder implementation should be logged for
diagnosis without downshifting quality. When developer stream stats are enabled
on Windows, the LiveKit session also enables filtered native WebRTC log
forwarding for stream-related lines so future call logs may capture hardware
encoder init failures when libwebrtc exposes them. The filter intentionally
includes Inter Galactic native
desktop-capturer lines: `desktop capture frame size` logs the native source,
requested cap, and pre-encode output whenever dimensions change, while
`desktop capture pipeline` logs native source size, requested cap, pre-encode
output, target FPS, native emitted FPS, scaling state, and crop-region state
when the patched libwebrtc artifact includes that native diagnostic.
The debug stream-test runner can now run the Windows backend comparison matrix
for a selected source, cycling App default, Native default, WGC-only,
and DirectX-only runs for each selected preset. The old window-crop diagnostic
backend is not exposed by the stream-test runner because BG3 validation showed
it could shred the stream, reveal the wrong monitor, and crash at batch
cleanup. The native mode may remain as a hidden low-level diagnostic, but
stream-test configs sanitize it back to App default instead of running it.
Reports include the requested backend, the native backend marker when
available, submitted native FPS, p95/max native frame interval, capture
wait/permanent errors, and crop-region state. This is for measurement only.
Normal non-developer window/app defaults stay on the DirectX/window-GDI
compatibility path; developer-mode game-like app-default shares may resolve to
the D3D11 hook when eligible; display sharing continues to use the patched
native default unless the debug runner explicitly sets an override.
Reports include native pacer markers when the active Windows publish uses the
latest-frame pacer, which is now the normal Windows desktop/window default.
Interpret them carefully: `submitted_fps` can be high because the pacer repeats
the newest frame, while `unique_fps` shows how often capture delivered a fresh
frame. High duplicate counts with low unique FPS point at capture acquisition
or scaling starvation; high unique FPS with bad sent/rendered pacing points
downstream of native capture.
Native capture cadence markers also split the outer Windows
`CaptureFrame()` call. `Capture Call` is the total synchronous capture call,
`Source Capture` is WebRTC's own `DesktopFrame.capture_time_ms()` value when
the backend provides it, `Callback Entry` is the delay from starting the outer
call until the result callback is first entered, `Acquire Wait` is the inferred
time outside result-callback work, `Post Callback` is time spent after the
callback finishes before `CaptureFrame()` returns, and `Unaccounted Wait` is
the residual after source capture and post-callback wait are removed. `Frame
Work` comes from the callback timing marker (`convert`, `scale`, and
`OnFrame`). The timing marker also reports updated-region dirty/empty counts.
Current stream-test reports also carry the actual native `DesktopFrame`
capturer id/label and the active dirty-region mode, so App default runs can be
checked against the concrete backend selected by WebRTC instead of only the
requested diagnostic backend. The developer stream-test dialog can force
full-frame dirty regions for comparison or leave Auto selected; normal Windows
window/game shares already use Force full-frame on App default/native-default/
WGC paths. Dirty-region mode changes do not crop, stretch, retune profiles, or
change encoder policy.
If source capture or callback-entry delay dominates, investigate the selected
Windows backend's acquisition, frame lifetime, and callback-dispatch boundary.
If post-callback or unaccounted wait dominates, investigate backend cleanup or
add deeper instrumentation in the concrete App default, WGC, or DirectX
capturer instead of tuning bitrate, scaler, encoder, or LiveKit settings.
Per-preset native marker attribution uses the publish/measurement window and
ends before the runner stops or replaces the share, so cleanup/startup markers
from the next preset should not overwrite the previous preset's native
resolution/backend summary.

When the live stream-lab harness or adaptive fallback refreshes Windows desktop
capture, it stops the existing screen-share video publication before creating
the replacement track. Live testing showed that starting the replacement
capturer first can publish a LiveKit sender with zero captured, encoded, and
sent frames even though native backend option logs appear. The stream-lab
Markdown summary treats that state as `no_sent_frames` with the full downgrade
penalty rather than `healthy`; stale native sidecar markers must not override
the WebRTC sender counters.

DirectX/window-GDI is now the normal Windows window/game App default, but
switching away from an active DirectX/window-GDI backend is still treated as a
restart boundary. Fresh 2026-05-20 live tests showed that switching away from
an active DirectX backend can leave the next sender frame-starved until the
user stops and restarts the share. The live stream-lab harness therefore marks
those samples as a restart boundary and skips in-place switches away from
DirectX/window-GDI. To compare WGC or Native default after a DirectX/window-GDI
sample, stop the screen share in the app, start it again, then run the next
config.

For release-candidate measurement, prefer the stream-lab runner's
`-ObserveOnly` mode: the user starts the stream/preset in the app, and the
runner collects the active capture/encode/send metrics without republishing the
Windows screen-share video track. A May 20 BG3 window-share run showed that
live republish can publish a zero-frame sender even for native-default/WGC, so
the runner now aborts remaining configs and disables live tuning on
`no_sent_frames` or `no_stats`.

Desktop WebRTC capture dimensions are patched during the Windows build because
the Flutter WebRTC `1.2.1` desktop bridge did not originally forward requested
screen-share width/height into the native capturer. The patched build helper
keeps using LiveKit `ScreenShareCaptureOptions`, then modifies the resolved
Flutter WebRTC `flutter_screen_capture.cc` so requested width/height are passed
as maximum pre-encode bounds to `StartWithMaxFrameSize(...)`. The native
capturer must capture the full source frame and contain-fit scale it down; it
must not use `Start(fps, x, y, w, h)` as a scaler because that overload crops a
source region. Keep the post-publish RTP sender clamp in place as a second
guardrail: it reapplies bitrate, frame-rate, and `scaleResolutionDownBy` limits
immediately after publish and remembers the largest observed sender size so
WebRTC adaptation cannot create parameter churn. Future logs should treat
`req:1280x720 -> actual:2560x1440` as evidence that the capture bridge patch
was not present in the build. Manual validation must also inspect the visible
remote frame, because the prior crop regression produced plausible sender
stats while cutting off part of the shared window.

The Windows hardware-first path is intentionally a codec/publish preference in
the existing LiveKit/WebRTC pipeline, not a separate native transport bridge.
It is enabled by default on Windows through the hardware-first screen-share
preference's platform default, and developer controls can still disable it for
explicit VP8/software comparison runs. If developer stats show software H.264
or a zero-frame `SignalEncoderTimedOut` sender after the publish preference is
applied, the next investigation belongs in the Flutter WebRTC Windows native
encoder factory or build configuration rather than in the profile bitrate
model. See
`docs/architecture/calls-streaming-audio/windows-libwebrtc-hardware-encoding.md` for the native
fork/build path.

Android screen sharing must create/publish the screen-share track with explicit
`ScreenShareCaptureOptions` and profile-derived `VideoPublishOptions`; room
creation must also set `defaultScreenShareCaptureOptions` as a safety net. This
prevents LiveKit convenience APIs from falling back to the SDK's 1080p/15 FPS
capture default or stale room publish defaults, both of which are known
choppy-motion failure modes for gameplay.

Receive-quality policy should use LiveKit layer quality for VP8/H264 simulcast
paths. Do not use `setVideoFPS` for the default VP8/H264 presets because that
LiveKit API is only effective for SVC-capable codecs.

Desktop call popouts have an optional transparent-chrome mode. For native
detached Windows call windows, opaque mode uses a custom Flutter title bar on
top of a frameless/resizable HWND. Its draggable area is limited to the label
region, and the transparent, pin, dock, minimize, maximize/restore, and close
buttons are nondraggable zones that target the detached window controller rather
than the main app window. Transparent mode hides that title bar, removes the
Win32 frame/titlebar, and keeps a very faint hit-test backdrop so hover can
restore the compact controls. Do not reintroduce color-key transparency until it
has a runtime-safe implementation that cannot make the whole window disappear.
Hover only reveals popout controls and must not resize or shift the call
layout. Transparent hover chrome should use a dark translucent window-level
pill, not a light theme surface, so it does not appear as a white box over
game/video content. Detached popout roots must paint explicit dark or
transparent surfaces, with local `Material`/`Overlay` boundaries, so Flutter's
default white background cannot appear under camera or screenshare tiles.
Transparent full-call windows must keep normal rounded call-panel tile geometry
and the ordinary tile vignette/scrim. Do not reuse the transparent per-stream
popout edge-to-edge treatment for the full call grid, because that changes the
participant panel shape and was not the white-edge root cause. The shared
transparent-window requirement is only that menus, tooltips, and other overlay
surfaces stay inside the detached window's local overlay instead of using the
app root overlay.
On Windows, detached popouts must also own their native chrome profile instead
of inheriting Flutter `RegularWindow` defaults. Flutter's Windows host extends
the DWM frame through the full client area when a secondary regular window is
created; Inter Galactic detached call windows reset that DWM frame margin,
strip native edge styles, and apply no-border/no-rounded-corner DWM attributes
after retrieving the top-level HWND. If a white edge reappears, classify the
layer first: inspect the detached chrome profile, Win32 style/exstyle, client
and window rects, DWM visible-frame border thickness, DWM border color, and
edge pixel samples. Enable
`INTERGALACTIC_DETACHED_WINDOW_EDGE_DIAGNOSTICS=1` to write those captures under
`runtime/window-diagnostics/transparent-call-border-*` before trying any
Flutter overlay or surface workaround.
Transparent full-call hover controls must not be wrapped in an
opacity/saveLayer fade because Windows transparent-window compositing can
surface that layer as a pale wash over the entire call; use direct
visible/hidden controls in transparent mode instead.
The individual bottom-row call buttons in transparent mode should also avoid
Material/Ink hover and splash layers. Paint them directly as dark translucent
circular controls so hovering the button row cannot create another white
composited surface over the call. Tooltip/help text shown from those controls
must use a dark translucent decoration in transparent mode rather than the
default light Material surface.
Keep those controls centered so they do not compete with top-right video-tile
controls. The mode is intended for always-on-top overlays while playing games.
Keep the toggle on the actual popout/video pane controls rather than in app
settings so transparency cannot be enabled before a popout exists. Transparency
is intentionally in-memory per open popout/window: every new session popout and
per-stream popout starts opaque, even if the previous popout was toggled
transparent, and the user can opt into transparency only after the new popout
has rendered normally.

Mobile call backgrounding is coordinated by `CallManager` through
`MobileCallBackgroundController`. Android keeps any connected, connecting, or
outgoing call alive with `CallForegroundService`, using a media-playback
foreground service and adding microphone/camera foreground-service types only
when an active session currently uses those tracks. The service is only for
call media retention; Android gameplay screen sharing still uses the separate
media-projection foreground service. The full-session popout button maps to
Android picture-in-picture when a desktop detached window is unavailable. iOS
uses the same Dart background-call controller and method channel to notify the
native runner when connected, connecting, or outgoing calls are active. The
iOS runner keeps the background audio path aligned with `UIBackgroundModes`
audio by activating `AVAudioSession` as `.playAndRecord` in voice/video chat
mode while a call is active, then deactivating that retention after the call
set becomes empty. iOS full-session popout uses the same mobile method channel
to create an `AVPictureInPictureController` with the iOS active-video-call
content source API. The iOS runner prepares the selected existing native
WebRTC `RTCVideoTrack`, feeds it into an `AVSampleBufferDisplayLayer`, and
starts PiP only after the sample-buffer renderer reports a first frame. The
runner must discard the prepared session/default track target when PiP entry is
rejected before a real start attempt or when an already-active PiP start is
reused; attempted starts still clear prepared targets through normal content
cleanup on failure, timeout, stop, or teardown.
The source view must be attached to a real visible UIKit hierarchy before
`startPictureInPicture`; an orphan source can render frames and report
`isPictureInPicturePossible == true` but AVKit will still fail activation. The
source-rect hint from Dart is used to size that temporary source view so AVKit
has a valid transition/source lifecycle. `RTCMTLVideoView` was tested inside
`AVPictureInPictureVideoCallViewController` and native frame callbacks kept
arriving, but the device PiP visual froze, so the release path remains
sample-buffer rendering. The iOS PiP window is system-owned; do not paint fake
UIKit or Flutter controls into the mirrored content view because iOS treats
taps on the PiP as PiP restore/system gestures, not as normal app button
touches. When the system asks the app to restore the PiP user interface, the
native delegate forwards a `returnToCall` action over the mobile call popout
method channel so Dart can route through the current call session and normal
room navigation path.

Android PiP, Android resizeable popout, and iOS AVKit PiP state are reported
through the existing mobile call method channel. Android PiP/resizeable popout
uses a call-only app root while that platform state is active and a call is in
progress, so the floating window does not show the room header or an app
corner. iOS AVKit PiP must not switch the Flutter app root to the call-only
surface: AVKit owns the separate PiP window, while the app should remain on the
normal call/chat surface. iOS native PiP also keeps a tiny noninteractive
root-level `CallWidget` mounted while PiP is active; this preserves the
Flutter/LiveKit renderer path needed for adaptive video to keep producing
frames when the user changes rooms/pages or backgrounds the app. Do not mark
the iOS room session as popped out just to show the placeholder unless a future
native bridge owns LiveKit subscription/rendering independently. PiP entry
passes a source-rect hint from the mounted call surface and the iOS
sample-buffer host uses that crop rect while PiP is starting so AVKit can
animate from the active call surface rather than a detached/orphan source
layer. Android 12+
seamless resize is disabled for this Flutter activity surface because live
resizing can otherwise glitch the renderer. Android true PiP suppresses in-app
Flutter call controls so the media surface stays readable, while resizeable/
freeform popout keeps the mobile control dock available. This presentation
routing does not change call media, foreground service behavior, LiveKit
publication/subscription, or MatrixRTC state.

On mobile, call presentation uses a separate compact layout from desktop. When
the user focuses a camera or stream tile, that tile becomes the main panel and
the remaining participants move into a compact strip below it. When no tile is
focused, participants render in a compact grid rather than a desktop-style
stage/rail split. The same `VoipStreamView` tiles are reused so speaking,
mute, visibility, fullscreen, and local volume affordances stay consistent.
The bottom call controls render as a compact scrollable dock on mobile so
larger developer/stream states do not crowd or clip the primary call surface.
This is presentation-only; it must not change PiP lifecycle, foreground
service behavior, LiveKit publication/subscription, or MatrixRTC state.

On desktop, a focused camera or stream tile owns the main stage and the
remaining tiles move into a bounded thumbnail rail above it. The rail may wrap
to a second visible row, but each secondary tile keeps thumbnail dimensions even
when it is the only remaining tile; it must not consume the rail width and
collapse the focused stage. Normal, equal-grid, focused, and rail tiles all
reuse the same `VoipStreamView` behavior. For a local outgoing screen share,
that includes the lower-right ellipsis menu for stop streaming, quality presets,
and share-stream-audio toggling.

Per-stream popouts use native detached desktop windows when
`DetachedCallWindowHost` is supported and mounted; otherwise they keep the
in-app floating overlay fallback. The fallback frame must not use flex children
inside the floating overlay's shrink-wrapped layout; keep the video tile as a
normal sized child and overlay transparent/hover chrome above it. Otherwise
Flutter can collapse the renderer area and leave a blank popout. Native panel
windows render through the same stream-resolution and `VoipStreamView` content
path as the fallback overlay so participant volume, screenshare volume, fit,
fullscreen, and high receive priority stay consistent.
On Windows, opaque native panel windows share the detached-call custom title
bar contract: the title bar is part of the secondary Flutter view, reserves its
own height above the tile, and hides when transparent chrome is enabled so the
video/screen-share surface can run edge-to-edge. Transparent native panel roots
must stay fully transparent rather than low-alpha dark so Windows cannot blend a
white backing surface into the view edge.
Per-stream popouts must receive the same local playback volume target as the
call grid: participant mic/video tiles control the participant's local playback
stream, while screenshare tiles control paired `screenShareAudio` through the
separate saved screenshare-audio volume preference. Transparent per-stream
popouts should remove the normal tile vignette/scrim but keep the explicit
hover controls.
Per-stream popout state is keyed with the same stable tile identity used by the
call grid (`callStreamPopoutIdForStream`), not raw stream ids, so participant
tiles and screenshare tiles can dock back into the app even when the underlying
track id changes. A full-session call popout owns the whole call surface:
opening one clears per-stream popouts for that session, blocks new per-stream
popouts until the call is docked, and hides per-stream popout controls inside
the detached/full-call view. Every new per-stream popout starts opaque; the
transparent-chrome toggle is per open native panel or fallback frame and is not
persisted across later popouts or through the removed legacy
`call_popout_transparent_chrome` preference.
Native per-stream panel close restores the stream after the OS window-destroy
callback returns so Flutter does not rebuild the call grid on the native close
stack. The one exception is a local screenshare panel whose sender diagnostics
show the matching stream at zero capture FPS, which usually means the captured
source window closed before the user stopped sharing. In that case the close
path stops the dead screenshare asynchronously instead of docking a black tile.
This is a UI/window teardown guard; it does not change LiveKit publication
policy, stream-quality tuning, codec choice, or native capture behavior.

The stream fullscreen control should enter true fullscreen: desktop routes
request OS/window fullscreen and restore the prior fullscreen state when
closed, while mobile routes enter immersive system UI and restore edge-to-edge
mode on exit. Do not route stream fullscreen through the generic media
lightbox, because its image/video padding and aspect-ratio frame prevent a call
tile from becoming a true fullscreen stream surface. The fullscreen stream tile
must render the media feed without the normal bottom vignette, name pill,
status badges, or tile action chrome; only the fullscreen route controls such
as close and annotation may overlay the stream.

There is no app-level playout-delay control in the current LiveKit Flutter /
flutter_webrtc renderer path. WebRTC already maintains its own jitter buffer;
adding an artificial UI delay would require access to decoded frames that the
renderer does not expose, and delaying video without delaying call audio would
desync voice, soundboard, and shared-content audio. Treat choppy gameplay
streams as a sender/receiver/network/SFU diagnostics problem before considering
a custom delayed-viewer architecture.

## Guardrails

- Do not move RNNoise or shared-content audio into the screen-share quality
  profile model. Audio capture/publishing remains separate from video quality.
- Keep server audio loopback developer-only and subscriber-only. It is a test
  harness for microphone/RNNoise verification, not a user-facing sidetone
  feature.
- Keep streaming client gating in the MatrixRTC auth service / LiveKit JWT
  grants. UI-only checks are not enough to protect SFU capacity from older
  clients.
- Do not treat server tuning as the first fix. Use the client diagnostics to
  prove sender, receiver, network, or SFU bottlenecks before changing LiveKit
  server config.
- Keep new call diagnostics developer-only unless there is a product decision
  to expose user-facing stream health.
