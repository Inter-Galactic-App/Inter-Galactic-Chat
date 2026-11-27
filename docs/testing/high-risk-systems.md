# High-Risk Systems

## Purpose

This guide maps the riskiest Inter Galactic systems to the regression checks
expected before release or merge. Prefer focused automated tests for
pure Dart/service logic and manual device checks for native, Matrix, push, and
media runtime behavior.

## WebRTC / Streaming

Risk signals:
- Changes under VoIP, LiveKit, WebRTC diagnostics, RNNoise, native capture, or
  screen-share profile/fallback code.
- Recent open queue item: Streaming FPS Diagnostics Follow-Up.

Manual checks:
- Start and stop screen share from a packaged Windows build.
- Compare requested and encoded resolution/FPS in developer diagnostics.
- Join a LiveKit room with at least two users when LiveKit code changed.
- Check camera/mic toggles when capture code changed.

Focused tests:
- Screen-share quality profile and contain-fit scaling.
- Adaptive fallback reasons, hysteresis, CPU rescue, bandwidth corroboration,
  and hardware/software encoder fallback classification.

Remaining runtime gaps:
- Real GPU encoder selection, native scaler bridge activation, TURN/ICE route
  behavior, and cross-device media quality still require live validation.

## Notifications / Push

Risk signals:
- Changes to pusher registration, background service, notification response
  routing, platform notification handlers, companion overlay, or notification
  settings.

Manual checks:
- Android encrypted and unencrypted push receipt.
- Notification tap opens the expected room/account.
- Inline reply or bubble entry works when touched.
- Desktop companion suppression/notification behavior matches settings.
- Web push/service worker behavior when web notification code changed.

Focused tests:
- Notification response routing helpers, pusher cleanup helpers, background
  wake limiters, and companion controller state.

Remaining runtime gaps:
- FCM/APNs/web-push provider delivery, OS notification permissions, and Android
  OEM background behavior require real devices or deployed services.

## Matrix Sync / E2EE

Risk signals:
- Changes to login, client manager, Matrix client startup, account switching,
  background sync, direct-message classification, E2EE, verification, or room
  event parsing.

Manual checks:
- Fresh login and restart/session restore.
- Encrypted room decrypt after restart.
- Multi-account restore if account ownership changed.
- Cross-device verification/recovery if crypto or web restore changed.
- Room classification for DMs and group rooms when membership logic changed.

Focused tests:
- Pure room classification rules, update/session helpers, event parsing, and
  background wake limiters.

Remaining runtime gaps:
- Homeserver sync timing, to-device key delivery, OTK upload pressure, and real
  cross-device verification require Synapse/device integration checks.

## Onboarding

Risk signals:
- Changes to first-run flow, tutorial routing, Help tutorial replay, login
  completion, demo/app-review behavior, or onboarding preferences.

Manual checks:
- Fresh install shows onboarding after login.
- Completing or skipping onboarding survives restart.
- Help -> Tutorial replays without resetting completion state.
- Logged-out or demo-only flows do not show onboarding unless intentionally
  changed.

Focused tests:
- Onboarding service persistence, version bump behavior, corrupted local
  completion timestamps, and widget navigation controls.

Remaining runtime gaps:
- Fresh-install platform storage and full login-to-first-frame timing require
  packaged app/device smoke checks.

## Activity / Presence

Risk signals:
- Changes to local activity service, Spotify/Steam/local media sources, Matrix
  presence publisher, account popup activity view, or Activity settings.

Manual checks:
- Local activity appears only when enabled.
- Hiding current activity suppresses local rendering and publishing.
- Steam/Spotify no-active states clear local card and Matrix status.
- Source switching does not leave stale preferred cards.

Focused tests:
- Activity visibility filters, provider gates, selected-card fallback, Matrix
  presence summary publish/clear behavior, and source parser edge cases.

Remaining runtime gaps:
- Steam proxy/API availability, Spotify OAuth/token refresh on real accounts,
  native iOS local media bridge behavior, and Matrix presence propagation.

## Updates

Risk signals:
- Changes to `latest.json`, update checker, release scripts, artifact naming,
  installer/APK output, signing, or download URLs.
- Changes to Windows desktop auto-update runtime, manifest defaults,
  Authenticode handling, checksum metadata, unsigned-installer consent, or
  release staging helpers.

Manual checks:
- Older installed build sees a newer manifest.
- Same-version manifest does not show an update.
- Update alert notes and download URL are correct.
- Rollback manifest points to reachable prior artifacts.
- Installer/APK upgrade preserves local settings and session restore.
- Windows desktop auto-update verifies HTTPS plus SHA-256 before installer
  execution.
- Trusted signed Windows installers report Authenticode `Valid` and do not show
  the unsigned-installer consent dialog.
- Open-source unsigned or untrusted Windows installers require
  `platforms.windows.allow_unsigned_auto_update: true`, show the
  unverified-publisher approval dialog, cancel without installing when
  declined, and only run installer/UAC after approval.

Focused tests:
- Update checker parsing, trusted URL validation, version/build comparison, and
  manifest edge cases.
- Pure update-helper tests for checksum parsing, signing-mode classification,
  and cancellation result handling when those helpers change.

Remaining runtime gaps:
- Hosted file availability, certificate/signature validation, user approval
  dialogs, installer/UAC behavior, rollback manifests, and install-over
  behavior require real release artifacts.
