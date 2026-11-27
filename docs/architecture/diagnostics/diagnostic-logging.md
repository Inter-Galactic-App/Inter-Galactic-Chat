# Diagnostic Logging

Status: implemented
Last updated: 2026-06-25

## Purpose

Stable desktop builds need the same useful runtime warnings and errors that are
visible during `flutter run`, without requiring a developer console. The app now
keeps the existing in-memory Developer Logs view and also writes lightweight
diagnostic logs to disk.

## Runtime Capture

`intergalactic/lib/debug/log.dart` is the single app logging API. It now
captures:

- `FlutterError.onError`
- `PlatformDispatcher.instance.onError`
- uncaught zone errors through `runZonedGuarded`
- existing `Log.i`, `Log.w`, `Log.e`, `Log.d`, and zone `print` output

`Log.d` and print-style verbose logging remain lightweight by default. Stable
builds persist warnings and errors by default; info/debug lines are persisted
when Developer Mode or `--ig-debug-logs` is active.

## Categories

Every log entry has a category:

- `app`
- `matrix`
- `livekit`
- `webrtc`
- `notifications`
- `media`

Callers may pass the category explicitly. Legacy callers are categorized from
the current `Log.prefix` and high-signal message keywords so older logging paths
continue to contribute useful diagnostics without broad rewrites.

## Files And Rotation

The file sink lives under the platform application-support directory in
`logs/`. Do not store app runtime logs in release-automation log folders; those
folders are only for packaging/build output.

Log files are named `intergalactic-YYYY-MM-DD.log` with numeric suffixes when a
day rotates by size. Rotation defaults:

- 5 MB per file
- 10 files maximum
- 25 MB total budget
- 14 day retention

Writes are queued asynchronously during normal operation. Fatal startup,
Flutter, platform-dispatcher, and zone errors request a synchronous flush so the
last error has the best chance of reaching disk before termination.

Explicit fatal boundaries also write a synchronous
`pending-crash-report.json` marker in the same `logs/` directory. The marker is
small, redacted, and overwritten by the latest fatal boundary. It is created
only when the logged message identifies the run as unable to continue: fatal
startup errors and unhandled background entrypoint failures. It also trusts the
explicit marker sources that are only written by fatal startup handling or by
the mobile native LiveKit join guard or scoped native call-action guards, so
true markers still survive read-time validation if their summary text is
reduced. Main app `runZonedGuarded`, zone callback, Flutter, and
platform-dispatcher errors stay in the diagnostic logs, but they do not create a
next-launch crash marker by source label alone because recoverable async
callbacks can reach those handlers while the app remains open. The next normal
UI launch reads the marker, offers the user a crash-report prompt, and clears it
after the user chooses whether to open the bug reporter. The marker never
triggers automatic upload.
Newer builds also revalidate an existing marker against this same fatal,
headless, and native-guard allowlist before prompting, so stale nonfatal
markers written by older builds are deleted quietly during update/startup.

Desktop call-room native actions that can enter native WebRTC/LiveKit work use
explicit pre-operation guards for microphone enable, Push to Talk runtime
microphone enable or microphone sender detach/reattach, and screen-share
start/stop.
The guard is cleared once Dart
observes successful or handled-failure completion. Direct Matrix screen-share
replacement keeps the outer start marker active while it stops the old share,
because the pending crash store keeps only one marker file and a nested stop
marker would erase the replacement-start source. General Dart error handlers
cannot recover a marker after a native process termination, and broad
`PlatformDispatcher` or zone markers remain excluded to avoid reporting
recoverable runtime callbacks as crashes.

Recoverable asynchronous UI work must not rely on the app-zone crash reporter
as its error boundary. For example, Matrix MXC image thumbnail/full-resolution
loads report failures through the Flutter image stream and treat `M_NOT_FOUND`
as unavailable media. Those failures may log a redacted `media` warning, but
they should not write a pending crash marker or prompt for a crash report on
the next launch. The same rule applies to nonfatal async callback failures that
reach the main app zone: keep the diagnostic entry, but do not label the next
launch as a crash. URL-preview timeline refreshes also treat missing current
links as a normal no-preview state, because event content can change or lose a
previewable URL between the UI deciding to load a preview and the async preview
component running.

## Redaction

Diagnostic text is redacted before memory storage and before file writes.
Redaction covers access tokens, refresh tokens, passwords, Authorization
headers, Matrix access tokens, query-string tokens, OpenID token fields, and
LiveKit/JWT-shaped tokens. The default in-memory/file path also applies the
bug-report redaction policy for local filesystem paths, email-like identifiers,
and identifying device-info fields such as local computer/user names, product
IDs, device IDs, machine GUIDs, serial numbers, owner fields, and install dates.
Copy/export actions run redaction again before placing text on the clipboard or
in saved log files.

Developer Logs also avoids putting full local filesystem paths in normal UI
confirmation text or copied/saved log headers. Open/save actions still operate
on the selected folder/file, but success messages use generic wording and
exports report only whether the diagnostic log folder is available. This keeps
screenshots and pasted support context from carrying local usernames or
machine-specific paths when the exact path is not needed.

Matrix diagnostic logs also redact raw Matrix user IDs, room IDs, room aliases,
event IDs, MXC URIs, recovery-key-like grouped strings, and common E2EE payload
fields such as `session_id`, `session_key`, `sender_key`,
`sender_claimed_ed25519_key`, `ciphertext`, device keys, and forwarded-key
chains. Security, recovery, repair, and decrypt retry paths must log counts,
coarse states, or short non-reversible hashes instead of raw identifiers or
event objects.
The shared redactor also handles Matrix SDK room-key breadcrumbs such as
`Received room key with session ...`, domainless room IDs that start with
`!-`, and raw `requesting_device=...` assignments while preserving app-owned
12-character diagnostic hashes. App-owned E2EE summaries, E2EE room-key request
breadcrumbs, Server Discovery homeserver fields, and chat timeline lifecycle
entries should keep using short hashes at the logging source.

Matrix SDK decrypt spam is summarized before it reaches persisted diagnostics
when it matches room-decrypt failure forms, including `reason=missing_room_session`
and the SDK's "has not sent us a session key" wording. The SDK log bridge is
installed during process startup so the first sync/timeline burst is covered
before individual Matrix clients finish initializing. A separate stale-session
breadcrumb may log only hashed room/sender/session identifiers after the same
requestable missing Megolm session is observed repeatedly over time, and that
tracker clears when a matching room key arrives. This is diagnostic evidence
only; it does not change decrypt timing, key-sharing policy, room-key requests,
or repair behavior.

Timeline lifecycle diagnostics must not log room display names. New chat
timeline init/dispose entries use short room/thread hashes, and the redactor
still strips legacy `Initializing room timeline for:` /
`Disposing room timeline for:` display-name breadcrumbs from older logs.

Call Diagnostics redacts each visible, copied, saved, and bug-report snapshot
section before export. Participant client lines must not expose raw Matrix user
IDs or free-form local build-detail labels; the UI keeps the diagnostic shape
while replacing those sensitive values with redaction placeholders.

Call Diagnostics and stream-test UI confirmations must not display full local
filesystem paths. Save/finish snackbars, collapsed stream-test report summaries,
and RNNoise capture banners use generic wording or basename-only artifact
labels while preserving the existing local save/report/open behavior.

Call Diagnostics -> Report stream logs writes a redacted
`call-diagnostics-report` snapshot to recent logs before opening the
Call/stream logs bug-report template. That submission still uses the normal
Report a Bug preview/confirm boundary and includes logs/diagnostics through the
same redacted `diagnostic-logs.txt` and `diagnostics.json` attachment paths.

RNNoise WAV capture files stay local. Stopping capture writes
`capture-manifest.json` and local per-stage metadata for developer inspection,
but VoIP settings and Call Diagnostics no longer expose an Audio WAV report
submission path. Bug reports omit RNNoise WAV metadata and reject audio/WAV
attachments so audio content is not collected through the support endpoint.

## Developer UI

Settings -> Developer -> Logs exposes:

- Open Log Folder
- Copy Recent Logs
- Clear Logs
- Save Logs

Clear Logs removes only diagnostic log files and clears the current in-memory
list. It does not delete release logs, build logs, caches, or unrelated files.

## Startup Flags

- `--ig-debug-logs` enables verbose info/debug persistence for the current
  process only.
- `--ig-webrtc-stats` enables periodic LiveKit/WebRTC stats logging for the
  current process only and does not change the persisted Show call/stream stats
  setting.

These flags are runtime diagnostics only. They must not alter Matrix sync,
notification delivery, call behavior, or media behavior.
