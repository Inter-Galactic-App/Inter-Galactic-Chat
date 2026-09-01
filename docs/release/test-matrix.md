# Release Test Matrix

Maintainer note: this matrix references operator-only release automation and
private device/build evidence. Keep those details outside the public app repo.
See `docs/release/README.md` for the release-documentation boundary.

## Purpose

This matrix defines the minimum verification expected before a desktop/mobile
release is offered to users. Expand it when the release touches high-risk
systems such as auth, encryption, notifications, calls, media, updates, or
platform runners.

## Test Levels

- Smoke: fast check that the released artifact starts and core flows are alive.
- Regression: targeted checks for changed features and recent bugs.
- Upgrade: install over the previous public build and verify persisted state.
- Store: platform-specific distribution requirements.

## Core Smoke Matrix

| Area | Windows | Android | iOS | Web |
| --- | --- | --- | --- | --- |
| Launch packaged artifact | Required | Required | Required | Required |
| Login with existing account | Required | Required | Required | Required |
| New login on fresh install | Required | Required | Required | Required |
| Restart/session restore | Required | Required | Required | Required |
| Encrypted room decrypt | Required | Required | Required | Required |
| Send text message | Required | Required | Required | Required |
| Receive text message | Required | Required | Required | Required |
| Download attachment | Required | Required | Required | Browser-specific |
| Upload image/file | Required | Required | Required | Required |
| Open settings | Required | Required | Required | Required |
| Sign out/add account | Required | Required | Required | Required |

## Platform Device Matrix

Use real devices for mobile release sign-off whenever the release touches
notifications, media capture, storage, or native plugins. Emulators/simulators
are useful for smoke coverage, but they do not replace device checks for push,
camera, microphone, file save sheets, ReplayKit, or notification permissions.

| Platform | Minimum release target | Preferred extra target | Notes |
| --- | --- | --- | --- |
| Windows | Current release machine or clean Windows 11 VM | Upgrade over previous public build | Required for installer, updater, WebRTC desktop capture, RNNoise, and companion logging checks. |
| Android | One physical Google Services/FCM device | One clean emulator or secondary OEM device | Required for encrypted push, notification tap/reply, voice recording, downloads, and keyboard behavior. |
| iOS | One physical iPhone via TestFlight/ad-hoc | One simulator for layout-only smoke | Required for push, file share sheets, voice recording, and ReplayKit. |
| Web | Current Chrome over HTTPS | One non-Chrome browser | Required when auth/session storage, service worker, web push, URL previews, or GIF setup changed. |

## High-Risk Regression Triggers

Run the matching focused regression checklist whenever a release includes these
change types:

| Change type | Required checks |
| --- | --- |
| WebRTC, LiveKit, RNNoise, screen share, or call diagnostics | Streaming/call focused tests, Windows packaged screen-share smoke, direct-call smoke if direct call code changed, LiveKit group-call smoke if LiveKit code changed. |
| Android/iOS/web notifications, pushers, background service, or notification settings | Platform notification receipt, tap routing, encrypted-room preview/decrypt, pusher registration, and stale-pusher cleanup where applicable. |
| Matrix sync, login, E2EE, account switching, room classification, or background sync | Fresh login, restart/session restore, encrypted-room decrypt, cross-device verification/recovery if touched, multi-account restore if account ownership changed. |
| Onboarding, first-run, app review demo, or tutorial settings | Fresh install onboarding, completed onboarding persistence after restart, tutorial replay from Help, no onboarding for logged-out/demo-only state unless intended. |
| Activity, presence, profile status, or rich presence integrations | Local visibility gates, Matrix presence publish/clear, source disconnect/no-active-state clear, desktop runtime check for Steam/Spotify/local-media source in scope. |
| Release/update scripts, `latest.json`, build metadata, desktop auto-update, or installer/APK naming | Update manifest tests, upgrade over previous build, same-version no-update check, rollback manifest check, artifact naming/signing/checksum verification, and the Windows signing mode checks below. |

## Windows Auto-Update Signing Modes

Windows desktop releases can follow either of these approved validation paths:

- Trusted signed path: the installer Authenticode status is `Valid`; checksum
  verification still passes; the updater does not show the unsigned-installer
  consent dialog.
- Open-source unsigned consent path: `platforms.windows.auto_update` is true,
  `platforms.windows.allow_unsigned_auto_update` is true, HTTPS and SHA-256
  verification pass, the updater shows the unverified-publisher approval
  dialog, declining relaunches Inter Galactic without installing, and accepting
  reaches the normal Windows installer/UAC flow.

Do not treat an unsigned or untrusted installer as release-ready if the
manifest lacks the explicit unsigned-consent flag, if checksum verification is
missing or fails, or if the user is not shown the updater approval dialog
before installer execution.

## Windows Desktop

Build/artifact:

- The configured Windows release build completed with intended version
  handling.
- The release dry run produced the intended Windows installer and manifest
  signing mode.
- Installer runs on a clean Windows profile or VM.
- Installed app launches from Start Menu/Desktop shortcut.
- `InterGalactic.exe` and installer signatures validate, or the release is
  explicitly using the open-source unsigned consent path documented above.
- Existing install upgrades without losing local settings.
- Previous version detects `latest.json` update.
- Update banner opens the expected download/release URL.

Core app:

- Login and restore.
- Encrypted room decrypt after restart.
- Notifications display or are intentionally suppressed by companion settings.
- Voice/video settings open.
- Direct call smoke, if calls changed.
- LiveKit group call smoke, if calls/streaming changed.
- Screen share start/stop, if media/desktop runner changed.
- Download/save file path.

Recent regression focus:

- `run_dev.bat` hot-reload issues are not a release blocker for packaged
  users unless the same crash reproduces in installed release mode.
- Account popup, composer menus, settings overlays, and desktop notifications
  should receive a quick visual smoke when UI changed.

## Android

Build/artifact:

- The configured Android release build completed in intended mode.
- APK filename includes `X.Y.Z+build`.
- Release APK installs over the previous public APK.
- FCM build includes Google Services configuration when FCM is intended.
- Embedded-ntfy fallback build is used only when explicitly selected.
- APK signature lineage allows upgrade.

Core app:

- Fresh login.
- Restart/session restore.
- Encrypted room decrypt.
- Push pusher registration.
- Notification receipt for encrypted and unencrypted rooms when in scope.
- Notification tap opens the intended room.
- Inline reply/bubble behavior when notification changes are in scope.
- Voice message record/send/render.
- Attachment download/save sheet.
- Keyboard/composer behavior in a busy room.

## iOS / TestFlight / App Store

Build/artifact:

- Build performed on macOS with Xcode.
- `intergalactic/scripts/build_release.dart --platform ios --version_tag
  vX.Y.Z+build` or the approved Xcode/archive lane completed. The version tag
  is required; the script exits without it.
- Export method matches release channel: app-store for TestFlight/App Store,
  ad-hoc for internal device install.
- Main app and Broadcast Extension are signed with compatible profiles.
- Runner build number and extension build number are checked before upload.
- App Store Connect processing succeeds.

Core app:

- Fresh login on device.
- Restart/session restore.
- Encrypted room decrypt.
- Push notification permission and delivery when in scope.
- Voice message record/send when in scope.
- ReplayKit screen share path when calls/LiveKit changed.
- File download/share sheet.
- App Store demo/account review path when public submission is in scope.

Store review:

- Release notes, known issues, privacy text, abuse reporting, and moderation
  contact are current.
- No private test server, private IP, or local-only URL is exposed in the build.
- Encryption/export compliance answers are prepared.

## Web

Build/artifact:

- The configured web release build or dry run completed when web is in scope.
- `intergalactic/scripts/prepare-web.sh` completed through WSL.
- Generated web icons/service worker assets are present.
- Deployed bundle loads over HTTPS.

Core app:

- Fresh login.
- Refresh/reopen session behavior.
- Encrypted-room usability.
- URL previews and GIF setup when media changed.
- Web push/service worker behavior when notification changed.
- Browser-specific smoke in Chrome and one non-Chrome browser when auth or web
  storage changed.

## Update Manifest Tests

- Manifest is valid JSON.
- `version` is parsed as newer by an older installed build.
- Same-version manifest does not show an update banner.
- `build_date_ms` fallback behaves correctly if a version tag is unparseable.
- Windows platform entry points at the release installer.
- Windows desktop auto-update releases include
  `platforms.windows.auto_update: true` unless this release intentionally opts
  out and records the manual-download reason.
- Unsigned or untrusted Windows auto-update releases include
  `platforms.windows.allow_unsigned_auto_update: true` and pass the consent
  checks above.
- Android platform entry exists only when Android APK is shipped.
- Notes appear in the update/release-notes alert and stay below practical UI
  length.
- Untrusted manifest or download URLs are rejected by the client.

## Rollback Tests

- Previous manifest can be restored locally.
- Restored manifest points at reachable prior artifacts.
- Previous Windows installer checksum validates.
- Previous Android APK installs or can be offered as direct download when
  Android rollback is in scope.
- Bad build can see a higher hotfix build if users have already installed it.

## Public Release Manual Evidence Matrix

Use this matrix for the unchecked `Manual Test Pass Before Submission` section
in `docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md`. Leave tracker boxes
unchecked until the submitted or rebuilt release-candidate app has direct
evidence. Do not paste raw logs, Matrix message content, tokens, private user
IDs, or full device diagnostics into release docs.

| Tracker check | Minimum coverage | Evidence to record | Failure route |
| --- | --- | --- | --- |
| Existing Matrix account login works on `matrix.org` | Windows plus one mobile target | App version/build, platform, account type, pass/fail note or screenshot | FEATURES/DEBUG for login failure; S&C if token/privacy evidence is exposed |
| Custom homeserver login works if allowed | Windows or web, plus mobile if custom homeserver is enabled there | Homeserver type without secrets, login result, restore-after-restart result | FEATURES/DEBUG for login/session failure |
| Native mobile login hides Create Account | Android and iOS submitted build | Login screen screenshot or note proving registration entry is hidden | FEATURES for app UI behavior |
| E2EE restore, device verification, and recovery prompts work | Two Matrix devices/accounts, at least one encrypted room | Verification/recovery path used, decrypt result after restart, redacted failure text if any | DEBUG/FEATURES for Matrix client behavior; S&C for storage/privacy findings |
| Help & Safety can report a message | Real test homeserver room | Redacted target type, report submission result, failure-path note | FEATURES for UI/routing; SERVER/OPERATIONS if backend receipt fails |
| Help & Safety can report a room | Real test homeserver room | Redacted room type, report submission result, failure-path note | FEATURES for UI/routing; SERVER/OPERATIONS if backend receipt fails |
| Help & Safety can report a user | Real test homeserver room | Redacted user target type, report submission result, failure-path note | FEATURES for UI/routing; SERVER/OPERATIONS if backend receipt fails |
| Help & Safety can block and unblock a user | Real test account pair | Ignored-user state changes observed, unblock restores visibility as expected | FEATURES/DEBUG for Matrix account-data behavior |
| Account deletion/deactivation handoff is visible and understandable | iOS submitted build, plus Windows if Account settings changed | Screenshot or note showing route/copy and whether it opens the intended public page or handoff | FEATURES for UI/copy; S&C for policy wording |
| Support, privacy, abuse, security, and source links open public pages | All submitted platforms with Settings/About access | Public URL opened, platform, build, and any broken link | DOCUMENTATION/COMMUNITY for public pages; FEATURES for app links |
| URL preview settings are understandable in encrypted rooms | Encrypted test room on one desktop and one mobile target | Setting state, consent/default copy, preview behavior result | FEATURES for UI/behavior; S&C for privacy claim gap |
| GIF search uses approved relay or user setup path | One desktop and one mobile target | Relay/user-setup path used, no embedded private key evidence, search result/failure | FEATURES for app behavior; S&C for secret/privacy issue |
| Push notification registration and privacy-enhanced mode work | Android physical device and iOS device/TestFlight when in release scope | Pusher registration, notification receipt/tap, privacy mode result, APNs/FCM environment | DEBUG/FEATURES for client behavior; OPERATIONS/SERVER for provider/gateway failure |
| iOS permission strings make sense | iOS submitted build/device | Prompt text or screenshots for voice, camera, microphone, photos/files, notifications, and screen share | IOS for native project strings; S&C for privacy wording |
| Public artifacts install/launch and match submitted build number | Every submitted platform | Artifact name, version/build, install source, launch result | RELEASE PIPELINE for artifact/build identity |

## Sign-Off

Record sign-off per platform:

| Platform | Build | Smoke | Regression | Upgrade | Store/update | Owner | Date |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Windows |  |  |  |  |  |  |  |
| Android |  |  |  |  |  |  |  |
| iOS |  |  |  |  |  |  |  |
| Web |  |  |  |  |  |  |  |

Record focused high-risk sign-off when a trigger above applies:

| System | Automated focused tests | Manual/device regression | Owner | Date |
| --- | --- | --- | --- | --- |
| WebRTC / streaming |  |  |  |  |
| Notifications / push |  |  |  |  |
| Matrix sync / E2EE |  |  |  |  |
| Onboarding |  |  |  |  |
| Activity / presence |  |  |  |  |
| Updates / release metadata |  |  |  |  |
