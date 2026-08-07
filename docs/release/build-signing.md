# Build And Signing Guide

## Purpose

This guide documents the current build and signing flows for Inter Galactic
release artifacts. It is scoped to release management and does not change app
runtime behavior.

Maintainer note: this guide is public app-repo documentation. It should explain
release concepts and required artifact properties without depending on one
maintainer's private helper scripts, local artifact folders, or synced mirror
layout.

## Local Automation Boundary

Maintainers may use private wrapper scripts for interactive builds, staged
desktop auto-update tests, signing, and deployment. Those wrapper names and
machine-local folders are not part of the public source contract.

Public docs should describe:

- source version identity
- platform build requirements
- artifact naming and signing expectations
- update manifest structure
- security and rollback gates

Private docs can describe the exact local wrapper commands, output folders,
synced mirrors, and signing-machine setup.

## Windows Build Flow

Responsibilities:

- Uses a supported Flutter/Dart SDK for the repo.
- Preserves the selected `intergalactic/pubspec.yaml` `X.Y.Z+build` identity.
- Disables Android-only Google Services toggles before Windows package
  resolution.
- Runs package resolution with online then offline fallback.
- Installs or verifies the patched Windows libwebrtc artifact unless the
  release intentionally opts out.
- Runs code generation unless `--skip-codegen` is supplied.
- Runs `intergalactic/scripts/verify_release_identity.ps1` against the current
  pubspec `vX.Y.Z+build` and syncs iOS Broadcast Extension project fields.
- Calls `intergalactic/scripts/build_release.dart --platform windows`.
- Embeds `UPDATE_MANIFEST_URL=https://app.ourgalaxy.space/updates/latest.json`.
- Writes version-stamped Windows release output and, when needed, a release zip.

Important options:

- `--bump build|patch|minor|major`
- `--no-bump`
- `--skip-codegen`
- `--no-detached-call-windows`
- `--libwebrtc-zip <path>`
- `--require-patched-libwebrtc`
- `--no-patched-libwebrtc`
- `--spotify-client-id <id>`
- `--spotify-redirect-uri <uri>`
- `--steam-activity-api-base-url <url>`

## Windows Packaging And Signing Flow

Responsibilities:

- Loads private release environment values outside source control.
- Reads `X.Y.Z+build` from `intergalactic/pubspec.yaml`.
- Selects the intended release scope: Desktop, Android/mobile, or Both.
- Requires an existing Windows Flutter release output only when Desktop is
  selected.
- Detects and requires the version-matched Android APK when Android/mobile is
  selected.
- Locates Inno Setup `ISCC.exe`.
- Signs `InterGalactic.exe` when Windows signing is enabled, builds the
  installer with `windows_installer.iss`, renames the installer to include
  `X.Y.Z+build`, and signs the installer when Desktop is selected and signing
  credentials are configured.
- Creates a source archive from tracked source, such as with `git archive HEAD`.
- Fails packaging if the source archive cannot be created.
- Generates SHA-256 checksums after signing.
- Extracts public changelog content.
- Stages optional per-release Markdown feature notes from
  `IG_FEATURE_NOTES_FILE`, `IG_FEATURE_NOTES_SOURCE`, or
  `docs\release\feature-notes\vX.Y.Z+build.md` /
  `docs\release\feature-notes\vX.Y.Z.md`, then publishes that file as
  `updates\features\vX.Y.Z+build.md` and emits `feature_notes_url` in
  `latest.json`.
- Generates scope-aware `dist\updates\latest.json`: Desktop-only releases
  include Windows platform entries, Android-only releases include Android
  platform entries, and Both includes both.
- Desktop release manifests enable Windows auto-update by default. Set
  `IG_WINDOWS_AUTO_UPDATE=0` only when intentionally publishing a
  manual-download desktop update.
- Verifies release identity before packaging and again after manifest,
  installer, APK, source archive, and checksum outputs exist.
- Copies selected platform assets, checksums, source, changelog assets, and
  optional feature notes to the configured publication target.
- Copies `latest.json` last so update checks see the new version only after
  the selected artifacts are present locally.

Signing environment:

- `WINDOWS_SIGNING_ENABLED=1` by default.
- `WINDOWS_SIGNING_PFX` points at the maintainer's private local certificate
  path when signing is enabled.
- `WINDOWS_SIGNING_PASSWORD` may be supplied by the private environment.
- `WINDOWS_SIGNING_TIMESTAMP_URL` defaults to
  `http://timestamp.digicert.com`.
- `WINDOWS_SIGNTOOL` may point to `signtool.exe` or to the SDK folder that
  contains it.

Unsigned/open-source auto-update policy:

- A trusted Windows code-signing certificate is still the cleanest user-trust
  path, and installers with Authenticode `Valid` status proceed after checksum
  verification.
- A commercial certificate is not required for the current open-source desktop
  auto-update path. If Windows reports the installer as unsigned,
  self-signed, untrusted-root, or `UnknownError`, the manifest must explicitly
  set `platforms.windows.allow_unsigned_auto_update: true` before the updater
  will continue.
- The unsigned path still requires trusted HTTPS URLs and matching SHA-256
  metadata. After checksum verification, the updater shows an `Unverified
  Update` approval dialog; if the user declines, Inter Galactic relaunches
  without installing the update.
- Normal desktop release manifests should emit
  `platforms.windows.auto_update: true` and should set
  `allow_unsigned_auto_update` according to the selected trust path. Set the
  unsigned consent flag to false only when a release must require
  Authenticode-valid installers.

Operational guardrails:

- Keep signing before checksum generation.
- Keep `latest.json` local mirror copy last.
- Do not put signing commands inside parenthesized batch branches that can
  break on Windows SDK paths containing parentheses.
- Keep local packaging logs outside committed source and use them to diagnose
  packaging failures.
- Keep signing certificates, passwords, and keystores out of git.

## Android Build And Signing Flow

Default release behavior:

- Builds release APK.
- Uses FCM / Google Services by default.
- Uses a Pub cache/source layout that keeps Android plugin dependency sources
  reachable by Gradle/Kotlin without cross-drive cache metadata problems.
- Clears generated Kotlin incremental caches under `intergalactic\build\*\kotlin`
  before the APK build to avoid stale cross-drive cache metadata.
- Uses resource-safe Gradle defaults in `intergalactic\android\gradle.properties`:
  `org.gradle.workers.max=2`, `org.gradle.parallel=false`, a 3 GB Gradle JVM
  heap, and a 1.5 GB Kotlin daemon heap. These trade build speed for desktop
  responsiveness during release builds.
- Sets `CARGO_BUILD_JOBS=2` by default for Android builds so the Rust/Cargo
  portion of `flutter_vodozemac` does not use every logical CPU. Set
  `CARGO_BUILD_JOBS` before running the script when intentionally overriding
  the job count.
- Requires `intergalactic\android\key.jks`.
- Requires `intergalactic\android\key.properties`.
- Uses owner-local Android `google-services.json` files for client Firebase
  configuration. They must exist for FCM builds but must not be committed.
- Runs `intergalactic/scripts/verify_release_identity.ps1` against the current
  pubspec `vX.Y.Z+build`.
- Calls `intergalactic/scripts/build_release.dart --platform android`.
- Passes the pubspec build metadata as the Android build number.
- Writes a version-stamped APK such as `InterGalactic-X.Y.Z+build.apk`.
- Restores the shared non-Google dependency state after FCM release builds.

Signing setup example:

```bat
keytool -genkey -v -keystore key.jks -alias key -keyalg RSA -keysize 2048 -validity 10000
copy key.jks intergalactic\android\key.jks
```

Guardrails:

- Do not commit `key.jks` or `key.properties`.
- Confirm FCM vs embedded-ntfy mode before release.
- Confirm Google Services toggles are restored after build.
- Confirm the APK can upgrade the previous public APK.

## iOS Build And Signing Flow

Current repo-local helper:

```bash
dart run scripts/build_release.dart --platform ios --version_tag vX.Y.Z+build --git_hash <sha>
```

Requirements:

- macOS host.
- Xcode.
- Apple signing certificate and provisioning profiles.
- App Store Connect access for TestFlight/App Store upload.

Current project facts:

- Runner bundle id: `chat.intergalactic.app`.
- Broadcast Extension bundle id: `chat.intergalactic.app.broadcast`.
- Runner build number maps through `FLUTTER_BUILD_NUMBER`.
- `build_release.dart` requires full `vX.Y.Z+build`, passes build metadata as
  the Flutter/iOS build number, and syncs Broadcast Extension version fields.
- `build_release.dart` defaults `--ios_export_method` to `app-store`.
- Non-macOS hosts fail early for iOS IPA export.

Pre-upload checks:

- Confirm Runner and Broadcast Extension signing team/profile.
- Confirm entitlements and app groups.
- Confirm Broadcast Extension build number and marketing version are aligned
  with the intended submission.
- Confirm export method: `app-store` for TestFlight/App Store, `ad-hoc` for
  internal device install.
- Confirm App Store Connect processing before declaring TestFlight ready.

Known gap:

- No current fastlane upload lane was found in this inspection. Store upload
  may be manual or machine-local outside the repo.

## Web Build Flow

Responsibilities:

- Loads any required build environment outside source control.
- Requires WSL for `scripts/prepare-web.sh`.
- Regenerates web/PWA icons from the reference app icon.
- Resolves packages and runs code generation unless skipped.
- Runs `intergalactic/scripts/verify_release_identity.ps1` against the current
  pubspec `vX.Y.Z+build`.
- Builds `flutter build web --release --no-pub --no-wasm-dry-run`.
- Embeds `VERSION_TAG=vX.Y.Z+build` and `UPDATE_MANIFEST_URL`.
- Produces `intergalactic\build\web\` for deployment through the selected web
  hosting flow.

## GitHub Workflows

Current workflows:

- `.github/workflows/static-analysis.yml`: PR and merge queue static analysis
  for changed Dart files.
- `.github/workflows/build.yml`: manual Windows, Android debug, and web builds.
- `.github/workflows/integration-test.yml`: manual Linux/Synapse integration
  tests.

Current limitation:

- These workflows are validation/build aids, not the signed release pipeline.
- They do not publish signed Windows installers.
- They do not generate/deploy the production `latest.json`.
- They do not upload to TestFlight/App Store or Play Store.

## Build Release Dart Helper

`intergalactic/scripts/build_release.dart` centralizes Flutter release command
arguments:

- maps `windows` to `flutter build windows`
- maps `android` to `flutter build apk`
- maps `ios` to `flutter build ipa`
- forwards `VERSION_TAG`, `GIT_HASH`, `PLATFORM`, `BUILD_MODE`,
  `UPDATE_MANIFEST_URL`, feature config, and platform flags through
  `--dart-define`
- requires full `vX.Y.Z+build` release tags and passes Android/iOS build
  numbers from that identity
- syncs iOS Broadcast Extension version fields during iOS builds
- validates Android Google Services source toggles when requested
- fails early for iOS builds on non-macOS hosts
- avoids embedding direct KLIPY keys unless explicitly allowed

## Release Signing Sign-Off

Record for each release:

- Windows app executable signed or unsigned path accepted:
- Windows installer Authenticode status:
- Windows timestamp verified, if signed:
- Unsigned auto-update manifest opt-in reviewed:
- Android APK signed:
- Android upgrade signature verified:
- iOS archive signed:
- iOS/TestFlight processing verified:
- Checksums generated after final signing:
- Signing secrets remained out of git:
