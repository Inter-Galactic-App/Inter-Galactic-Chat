# Manual Regression Checklist

## Purpose

Use this checklist for release candidates and focused bug-fix validation. Keep
manual checks small, evidence-backed, and tied to the system that changed.
Pull-request review can help catch code issues, but it does not replace focused
tests or runtime smoke checks.

## Smoke Checklist

Run this on each shipped platform before release sign-off:

- Launch the packaged artifact, not only a debug build.
- Log in with an existing account and send/receive a text message.
- Restart the app and confirm session restore.
- Open an encrypted room and confirm new and recent messages decrypt.
- Upload one image or file and download one attachment.
- Open Settings, Help, and account switching/sign-out surfaces.
- Confirm no new fatal diagnostic logs, crash dialogs, or blank screens appear.

## Release Regression Checklist

Add these checks when the release touched the matching area:

- Calls/streaming: direct call if direct Matrix code changed, LiveKit group call
  if LiveKit code changed, screen share start/stop, camera/mic toggles, and
  visible sender FPS/resolution diagnostics when streaming changed.
- Notifications: encrypted and unencrypted notification receipt, tap routing,
  inline reply or bubble flow when in scope, pusher registration, and stale
  pusher cleanup after upgrade.
- Matrix sync/E2EE: fresh login, restart restore, cross-device verification or
  recovery when touched, room classification, and background wake behavior.
- Onboarding: fresh install tutorial, completion persistence after restart,
  Help -> Tutorial replay, and version-bump behavior if the tutorial version
  changed.
- Activity/presence: local visibility toggles, source disconnect/no-active
  states, Matrix presence publish/clear, and desktop runtime checks for Steam
  or Spotify when those sources changed.
- Updates: update banner, same-version no-update behavior, manifest URL trust,
  rollback manifest, artifact checksum, install-over-previous-build, and
  Windows desktop auto-update signing-mode behavior when the release touches
  updater runtime or manifests.
- Windows desktop auto-update: validate startup update, runtime update
  notification flow, no-update, bad checksum rejection, installer failure handling,
  rollback manifest, restart-after-update, and the signing path in use. A
  trusted signed installer should proceed after Authenticode `Valid` plus
  checksum verification. An unsigned or untrusted installer must require
  `allow_unsigned_auto_update: true`, pass HTTPS/checksum validation, show the
  unverified-publisher approval dialog, cancel cleanly when declined, and only
  reach installer/UAC after user approval.

## Hot Reload Vs Rebuild

Use hot reload only to validate development-loop resilience, layout assertions,
and recent `run_dev.bat` regressions. Hot reload is not a release substitute.

Use a restart or rebuild when any of these changed:

- app startup, routing, dependency injection, or global error handling
- generated localization, assets, service worker, or plugin registration
- native runner files, method channels, permissions, entitlements, or Gradle/Xcode
  configuration
- build flags, `--dart-define` values, release scripts, or package versions

Use a packaged artifact for final release validation, especially for installer,
update, file logging, native plugin, and notification behavior.

## Native Rebuild Requirements

- Windows WebRTC/RNNoise/screen capture: rebuild the Windows app and verify the
  packaged runtime, because patched DLLs and native capture bridges are not
  proven by Dart tests alone.
- Android push, voice recording, biometrics, file save sheets, or manifest
  changes: rebuild and install the APK on device.
- iOS ReplayKit, notifications, voice recording, entitlements, or extension
  changes: archive/export through the approved Xcode/macOS path and validate on
  device.
- Web service worker, IndexedDB/session restore, push, or bootstrap changes:
  rebuild web, deploy over HTTPS, and test in a fresh browser profile plus one
  upgrade/refresh path.

## Evidence To Record

- Artifact identity: platform, version, build number, and install source.
- Windows update mode: trusted signed installer or approved unsigned consent
  path, including manifest flags and checksum/signature result.
- Test account type and room type, avoiding secrets or private message content.
- Pass/fail result with exact failure text, screenshot, or diagnostic log path
  when something fails.
- Whether the check was debug, hot reload, rebuilt debug, or packaged release.

## Public Release Evidence Rules

For public submission readiness, use the manual evidence matrix in
`docs/release/test-matrix.md` against the unchecked
`Manual Test Pass Before Submission` items in
`docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md`.

- Use the submitted artifact or a rebuilt release-candidate artifact, not hot
  reload.
- Record one concise evidence note per tracker row: platform, build number,
  account/room type, result, and screenshot or redacted diagnostic path when
  useful.
- Leave tracker boxes unchecked until the evidence exists and the failure path,
  if any, is routed to the owning lane.
- Do not store raw Matrix content, access tokens, push endpoints, private user
  identifiers, local app-data paths, full logs, or screenshots containing
  private messages in coordination docs.
