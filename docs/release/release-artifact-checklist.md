# Release Artifact Checklist

Maintainer note: this checklist describes public artifact expectations. Keep
personal artifact folders, synced mirrors, and helper-script paths outside this
repository.

## Purpose

Use this checklist to verify that release artifacts, checksums, signing, public
URLs, and `latest.json` all describe the same build.

## Required Identity

For every release, record the full identity from `intergalactic/pubspec.yaml`:

- Semantic version: `X.Y.Z`
- Build number: `build`
- Full version: `X.Y.Z+build`
- Version tag: `vX.Y.Z+build`
- Git SHA:
- Build date/time:
- Release scope:

## Expected Artifact Names

New release artifacts should use the full `X.Y.Z+build` identity unless a
specific store requires separate metadata.

| Artifact | Expected name |
| --- | --- |
| Windows installer | `InterGalactic-Setup-X.Y.Z+build.exe` |
| Android APK | `InterGalactic-X.Y.Z+build.apk` |
| Source archive | `intergalactic-X.Y.Z+build-source.zip` |
| Checksums | `checksums-X.Y.Z+build.txt` |
| Public changelog | `updates/changelog/vX.Y.Z.md` |
| Update manifest | `updates/latest.json` |

Windows installer metadata may use semantic `X.Y.Z` because Inno Setup receives
`MyAppVersion=X.Y.Z`; the hosted filename must still include `+build`.

## Local Artifact Locations

| Artifact | Local path |
| --- | --- |
| Windows build output | Configured Windows release output folder for `X.Y.Z+build` |
| Windows installer | `dist\installer\InterGalactic-Setup-X.Y.Z+build.exe` |
| Android APK | Configured Android release output folder for `InterGalactic-X.Y.Z+build.apk` |
| Checksums | `dist\checksums\checksums-X.Y.Z+build.txt` |
| Source archive | `dist\source\intergalactic-X.Y.Z+build-source.zip` |
| Changelog extract | `dist\updates\changelog\vX.Y.Z.md` |
| Manifest | `dist\updates\latest.json` |
| Local web mirror manifest | Configured website/update mirror `updates\latest.json` |

## Signing Checks

Windows:

- `InterGalactic.exe` exists in the Windows release output before packaging.
- When Windows signing is enabled and credentials are configured, the release
  flow signs `InterGalactic.exe` before Inno Setup packaging and signs
  `InterGalactic-Setup-X.Y.Z+build.exe` after packaging.
- Installer Authenticode status is recorded as `Valid`, `NotSigned`,
  `UnknownError`, untrusted-root, or the exact Windows-reported status.
- Trusted signed path: installer Authenticode status is `Valid`, and signature
  subject, timestamp, and hash algorithm are acceptable.
- Open-source unsigned consent path: HTTPS URLs, SHA-256 metadata,
  `platforms.windows.auto_update: true`,
  `platforms.windows.allow_unsigned_auto_update: true`, and the updater
  unverified-publisher approval dialog are verified before installer
  execution.
- Manual-download opt-out: `platforms.windows.auto_update` is false only when
  `IG_WINDOWS_AUTO_UPDATE=0` was intentionally set and the release record
  explains why.
- SHA-256 checksums were generated after the final signing/packaging decision.

Android:

- Release APK uses the intended keystore at
  `intergalactic\android\key.jks`.
- `intergalactic\android\key.properties` exists only on the release machine or
  local secure workspace.
- FCM/Google Services source toggles are enabled only for the Android build and
  restored afterward.
- Embedded-ntfy fallback APK is clearly labeled in release notes when used.

iOS:

- Main app bundle id is `chat.intergalactic.app`.
- Broadcast Extension bundle id is `chat.intergalactic.app.broadcast`.
- Main app and extension use compatible teams, capabilities, provisioning
  profiles, and build numbers.
- Archive/export was performed on macOS with the intended export method.

## `latest.json` Validation

Validate these fields before upload:

- `version` equals `vX.Y.Z+build`.
- `version_name` equals `X.Y.Z`.
- `build_number` equals numeric `build`.
- `build_date_ms` is present and is newer than the previous public build.
- `pub_date` is present for website/display use.
- `release_url` points at the public download page when both app-managed
  updater platforms are in scope. Single-platform releases rely on that
  platform entry's `release_url` so other platforms do not see a false update.
- `notes` summarizes this release and does not mention internal-only details.
- `notes_url` points at `/updates/changelog/vX.Y.Z.md`.
- `checksums_url` points at `checksums-X.Y.Z+build.txt`.
- `source_url` points at `intergalactic-X.Y.Z+build-source.zip`.
- `platforms.windows` and `platforms.windows-x86_64` exist only when Desktop
  was explicitly selected for this release.
- `platforms.windows.download_url` and `platforms.windows.url` point at the
  version-matched Windows installer when Desktop is in scope.
- `platforms.windows.checksum_url` points at the matching checksum file when
  Desktop is in scope.
- `platforms.windows.auto_update` is true for the normal desktop release path.
  If false, the manual-download reason is recorded and the release notes do not
  imply automatic Windows installation.
- `platforms.windows.allow_unsigned_auto_update` is intentionally true or false
  when Desktop is in scope. If true, the release record says the open-source
  unsigned consent fallback is permitted when Windows does not report the
  installer as Authenticode `Valid`; if false or absent, the release requires a
  `Valid` installer signature for auto-update.
- `platforms.windows-x86_64.url` points at the same Windows installer when
  Desktop is in scope.
- `platforms.android` exists only when Android/mobile was explicitly selected
  for this release and the matching APK exists.
- No manifest URL points at a local path, private IP, unsigned draft outside
  the reviewed consent path, or stale version.

## Public URL Verification

Before uploading `latest.json`, verify these URLs are live or will be live
before manifest upload:

- `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-X.Y.Z+build.exe`
- `https://app.ourgalaxy.space/downloads/InterGalactic-X.Y.Z+build.apk` when
  Android is in scope.
- `https://app.ourgalaxy.space/downloads/checksums-X.Y.Z+build.txt`
- `https://app.ourgalaxy.space/source/intergalactic-X.Y.Z+build-source.zip`
- `https://app.ourgalaxy.space/updates/changelog/vX.Y.Z.md`
- `https://app.ourgalaxy.space/updates/latest.json`

## Checksum File Contents

The checksum file should include each shipped downloadable artifact:

- Windows installer, always.
- Android APK, when Android/mobile was explicitly selected.
- Source archive, when generated.

Do not publish checksums generated before the final signing/packaging decision.

## Store Metadata Checks

Android:

- Fastlane text metadata is present under `fastlane/metadata/android/`; copied
  Commet store images were removed on 2026-06-13.
- Changelog file for the target version code exists if using Play Store upload.
- Screenshots/icon/feature graphic must be current Inter Galactic-owned/listing
  material before store submission.

iOS:

- App Store / TestFlight release notes are prepared from the release template.
- App privacy, UGC, abuse reporting, and encryption notes are current.
- Broadcast Extension screenshots/metadata are not required unless App Store
  Connect asks for them, but extension capability review must be complete.

## Security Artifact Checks

Run these checks after a release dry run and before publishing `latest.json`:

- Run the app-repo security gate from the repository root:
  `python .github/scripts/security-review.py --repo-root . --artifact-root dist`.
- Confirm the latest GitHub `security-review` workflow passed for the release
  branch when the release branch exists on GitHub.
- Confirm no release artifact, installer input, source archive, checksum
  bundle, manifest, or web bundle contains `.env`, `.env.*`,
  service-account JSON, APNs `.p8`, VAPID private key, LiveKit API secret,
  LiveKit JWT, Matrix access/refresh/OpenID token, bot storage, signing key,
  signing password, `key.jks`, `key.properties`, or local
  `firebase_options.dart`.
- Confirm the private release environment file remains operator-owned local
  state and is not copied into source archives, web assets, installers,
  checksums, or support bundles.
- Confirm owner-local Android `google-services.json` files are the intended
  Firebase client configuration for the target app. Do not treat them as
  service-account JSON, but do verify they are not committed and are not
  pointing at a stale project.
- Confirm Developer Logs exports remain redacted for Matrix tokens,
  Authorization headers, provider tokens, and local-only paths.
- Confirm LiveKit/WebRTC diagnostic exports, if captured for the release, do
  not include LiveKit JWTs, Matrix OpenID token request bodies, full Matrix
  room/user/device identifiers, ICE candidate IPs beyond what is needed for
  private debugging, or unredacted screen-share source/window titles.

## Final Artifact Approval

Do not approve the release unless all intended artifacts are:

- version-stamped
- signed where required or explicitly released through the documented unsigned
  consent path
- checksum-covered
- URL-addressable
- represented correctly in `latest.json`
- backed by rollback notes for the previous live version
