# VoIP Soundboard

Date: 2026-04-26

## Scope

The call soundboard is a Matrix-space feature. A space acts as the current
server boundary, and sounds uploaded there become available to call rooms under
that space.

This feature intentionally uses local playback during active calls. Soundboard
audio is not mixed into the microphone capture path and is not published as a
WebRTC or LiveKit media track in this phase.

## Matrix Events

- `chat.intergalactic.soundboard.sound` state events store one sound per
  state key. The state key is the sound ID. Numeric metadata stored in this
  state must stay canonical-JSON friendly; shared `volume` is written as a
  rounded integer percentage rather than a floating-point value.
- `chat.intergalactic.soundboard.user` state events store per-user settings,
  currently the selected join sound. The state key is the Matrix user ID.
- `chat.intergalactic.soundboard.play` room events are sent in the active call
  room when a user plays a sound.

Play events are hidden from normal timeline rendering by the existing unknown
event handling path. A room sync listener handles them and asks
`SoundboardPlaybackService` to play the referenced MXC sound only if the local
client is currently in that call room.

## Upload Permissions

Matrix state events normally require elevated power. Inter Galactic exposes the
soundboard sound state event through the existing room/space Permissions page,
not through a separate Soundboard-only repair button. New spaces should set
`chat.intergalactic.soundboard.sound` to power level `0` by default; existing
spaces can be changed from the Permissions tab when admins want member uploads.

Join sounds are stored in per-room account data for the current user when
possible. The `chat.intergalactic.soundboard.user` state event remains for
admin-managed per-user join sounds and should not be required for normal member
uploads.

The UI only exposes deletion to the original uploader or a server admin. This
is a client-side product rule; Matrix power levels still define the protocol
enforcement boundary.

The Soundboard settings UI should display the sound upload required power
level, the default member power level, and the current user's power level, but
it should direct permission changes back to the Permissions architecture.
Upload failures must be logged with this context so exported call diagnostics
can distinguish permission failures from MXC upload, encrypted event, resolver,
or playback failures.

## Audio Boundaries

Soundboard playback uses `media_kit` local playback from MXC files, the shared
per-sound volume, and the user's local soundboard volume. It does not affect
microphone mute state, RNNoise processing, shared-content audio, or call
publication.

Playback uses a persistent local player and resolves MXC content into
soundboard-scoped temp files with MIME-derived audio extensions before opening
the media. Avoid short-lived players and extensionless generic cache paths for
this path; on desktop they can produce silent previews even when the Matrix
state and upload are valid.

The soundboard temp cache is bounded by age, count, and total bytes: local
files older than 14 days, beyond 64 cached files, or beyond 64 MiB are pruned
from the soundboard temp directory. Playback stops the single persistent
soundboard player before pruning and protects the file about to be opened, so
cleanup does not remove the active backing file. Cache hits refresh the local
file timestamp so recently reused sounds are retained ahead of stale clips.

Soundboard playback should log each boundary: Matrix play-event send, encrypted
play-event resolution, active-call matching, MXC local URI resolution, deafen
skip, and media player start/open failure. The in-call developer diagnostics
log filter includes soundboard, MXC, media_kit, permission, and forbidden
keywords.

If a Matrix play event references a sound ID that is not present in the local
state cache yet, receivers should refresh soundboard state and retry briefly
before dropping the event. Desktop sync ordering can deliver a live play event
before the new sound state event is visible locally.

Desktop resolver behavior must include common audio MIME aliases such as
`audio/x-wav`, `audio/vnd.wave`, `audio/mp3`, `audio/x-mp3`, `audio/x-mpeg`,
and `audio/x-flac`. When the MIME is uncommon but the uploaded name has a known
audio extension, preserve that extension in the temp cache path so `media_kit`
can choose the expected decoder. Playback-open failures should log the sound
ID, MIME type, and local URI.

Local deafen is handled by `CallManager` and suppresses incoming call audio plus
soundboard playback for the local user. It does not signal remote participants
or change the user's microphone mute state.

## UI Ownership

- In-call controls live in
  `lib/ui/organisms/soundboard/call_soundboard_panel.dart`.
- Desktop call controls use a compact anchored soundboard popover rather than
  a full dialog; mobile keeps the dialog/sheet-style picker.
- Upload/manage/join-sound settings live in
  `lib/ui/pages/settings/categories/space/space_soundboard_settings_page.dart`.
- Soundboard emoji rendering uses the app emoji packs for the owning space so
  custom server emojis can be selected and shown when available.
- Matrix storage lives under
  `lib/client/matrix/components/soundboard/`.
- Shared models and playback coordination live under
  `lib/client/components/soundboard/`.
