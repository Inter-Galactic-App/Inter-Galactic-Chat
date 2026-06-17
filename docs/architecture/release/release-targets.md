# Release Targets

## Purpose

This file documents what a release is expected to prove for:

- Android
- iOS
- Web
- Desktop

It is written for contributors and maintainers who are changing code that can
affect packaging, startup, updater behavior, notifications, or encrypted
usability.

Detailed release-management runbooks now live under `docs/release/`:

- `docs/release/release-checklist.md` - release candidate, pre-release,
  publish, and post-release checklist.
- `docs/release/release-artifact-checklist.md` - artifact naming, signing,
  checksums, and `latest.json` validation.
- `docs/release/versioning-policy.md` - `X.Y.Z+build` version policy.
- `docs/release/build-signing.md` - Windows, Android, iOS, web, and GitHub
  build/signing flow.
- `docs/release/test-matrix.md` - desktop/mobile/web smoke and upgrade
  matrix.
- `docs/release/rollback-plan.md` - manifest rollback and hotfix-forward plan.
- `docs/release/release-notes-template.md` - release notes, known issues, and
  upgrade-risk template.

## Shared Expectations

A release is not just a successful build.

Across all targets, verify:

- app starts cleanly
- login works
- session restore works
- encrypted rooms remain usable
- key feature paths affected by the change still work
- packaging/update metadata matches runtime expectations

## Android

### Current responsibilities to inspect

- `intergalactic/android/`
- `intergalactic/scripts/build_release.dart`
- repo-root Android helper scripts if the release path uses them

### Platform expectations

- installable package builds successfully
- manifest and permission changes are intentional
- notification registration still works if the release depends on it
- account restore and encrypted rooms still behave after restart

### Common blockers

- manifest/permission mismatch
- wrong icon/signing/config resource assumptions
- push registration regressions
- plugin startup failures

### Android pre-release checklist

- build succeeds
- install succeeds on device/emulator
- login succeeds
- restart/session restore succeeds
- notifications and media behavior match expectations for the change

## iOS

### Current responsibilities to inspect

- `intergalactic/ios/`
- `intergalactic/scripts/build_release.dart`
- maintainer release helpers if the release is prepared outside the repo

### Platform expectations

- archive/export path is still valid
- entitlements/capabilities match the feature set
- login and encrypted restore remain stable on device
- native/plugin registration still works for the features included in the build

### Common blockers

- signing/capability mismatch
- notification or permission flow regressions
- plugin registration problems
- feature assumptions that only worked in debug or simulator contexts

### iOS pre-release checklist

- archive/export path verified on macOS/Xcode
- app launches on device
- login and restore succeed
- encrypted rooms remain usable
- notification/media/plugin paths affected by the change are smoke-tested

## Web

### Current responsibilities to inspect

- `intergalactic/web/`
- `intergalactic/scripts/prepare-web.sh`
- `intergalactic/scripts/build_release.dart`
- web/browser code under `intergalactic/lib/client/.../web/...`

### Platform expectations

- browser build loads cleanly
- no conditional-import regressions
- session/restore behavior is acceptable for current browser target assumptions
- web push/service-worker behavior still matches the intended deployment

### Common blockers

- web-only import leakage into shared code
- broken service worker or bootstrap assumptions
- update manifest / hosted asset path mismatch
- browser storage assumptions that break login or restore

### Web pre-release checklist

- browser build succeeds
- app loads without import/runtime errors
- login works
- refresh/reopen behavior matches expectations
- notification or media changes are smoke-tested in browser context if applicable

## Desktop

Desktop here means the packaged desktop targets driven by the Flutter runners under:

- `intergalactic/windows/`
- `intergalactic/linux/`
- `intergalactic/macos/`

Verify current active desktop release scope before assuming all three are shipped equally.

### Current responsibilities to inspect

- platform runner folders
- repo-root `windows_installer.iss`
- `intergalactic/scripts/build_release.dart`
- update manifest generation if updater behavior changed

### Platform expectations

- packaged app launches from the release artifact
- updater or release-manifest assumptions still match the actual hosted structure
- local persistence and encrypted restore remain stable after restart
- Windows auto-update runs only from a packaged `InterGalactic.exe`, never from
  a debug/Dart runtime.
- Windows auto-update requires a trusted HTTPS manifest, installer download URL,
  and checksum metadata before installer execution.
- Windows installers with Authenticode `Valid` status can proceed after
  checksum verification. Unsigned, self-signed, or untrusted-root installers
  can proceed only when the manifest sets
  `platforms.windows.allow_unsigned_auto_update: true` and the user approves
  the updater warning before installer launch; cancelling that warning
  relaunches Inter Galactic without installing the update.
- Normal desktop releases publish `platforms.windows.auto_update: true` by
  default. Disable Windows auto-update only for intentional manual-download
  releases.
- Windows updater PowerShell commands must run temp `.ps1` files with `-File`
  and pass the downloaded installer path as a normal argument. Do not use
  `$args[0]` or inline scripts after `-Command` for this path.
- Startup auto-update launches a copied runtime helper before the normal app
  window/session stack starts; runtime auto-update uses the existing update
  alert style, then closes the main app and hands off to the updater window.

### Common blockers

- installer or packaging config drift
- wrong manifest/update URL structure
- plugin DLL/binary bundling mistakes
- platform-specific startup regressions
- missing checksum URL or inline SHA-256 for the Windows installer
- untrusted or invalid Windows installer signature without explicit manifest
  opt-in and user approval
- accidental disabling of `platforms.windows.auto_update` for a normal desktop
  release after the updater path has become the default

### Desktop pre-release checklist

- packaged artifact launches
- login works
- restart/restore works
- updater paths or `latest.json` assumptions still match runtime code
- previous packaged Windows build detects a staged newer `latest.json` on
  startup, shows the updater progress window before the main window, installs,
  and restarts into the new version
- running packaged Windows build detects a newly published update during the
  periodic check, shows the normal update notification, then hands off to the
  updater progress window after user acceptance
- corrupt download, wrong checksum, unsigned/untrusted installer, installer
  approval/cancel, installer failure, no-update, rollback-manifest, and restart
  paths are verified before enabling `windows.auto_update`
- affected plugin/media features are smoke-tested from the packaged build

### Windows build toolchain notes

- The Windows release build path must select the intended Flutter SDK before
  codegen or release build steps.
- Run `flutter pub get` with the selected SDK before Dart codegen, because
  workspace `package_config.json` records SDK package roots such as
  `package:flutter`.
- `intergalactic/scripts/build_release.dart` honors `FLUTTER_EXE` when it
  spawns `flutter build`; keep that environment handoff intact when changing
  release helpers.
- If a Windows build error references an unexpected Flutter SDK path, treat it
  as a toolchain selection/cache issue before changing app code.
- When local automation runs Flutter/Dart/build commands on Windows, use a
  stable local app-data/cache location. Isolated sandbox profiles can produce
  false tool-cache failures.

## Release Blockers

Treat these as likely blockers unless the release scope explicitly says otherwise:

- build failure for the target
- startup crash
- login failure
- session restore failure
- encrypted-room usability failure
- wrong-account notification or routing behavior
- updater/manifest mismatch for a target that uses auto-update or hosted downloads
- plugin initialization crash for a shipped feature

## Pre-Release Checklist

Use this as the shared default checklist:

- confirm target build path
- confirm packaging path
- smoke-test startup
- smoke-test login
- smoke-test restart/session restore
- verify encrypted room access
- verify notifications if the target uses them
- verify media/plugin paths touched by the change
- verify release/update metadata assumptions

## Notes On Release Scripts

Do not treat release scripts as isolated build glue.

If changing release helpers, also inspect:

- hosted manifest assumptions such as `latest.json`
- package/output naming
- platform-specific artifact paths
- any companion website/download page expectations

Current build-number rule:

- New hosted release artifacts use the full pubspec identity
  `{version}+{build}` in filenames and directories, for example
  `InterGalactic-0.6.5+899.apk`.
- Windows installer metadata may remain semantic `X.Y.Z`; the hosted installer
  filename is renamed to include `{version}+{build}` after packaging.
- `latest.json` publishes `version` as `v{version}+{build}` and also exposes
  `version_name` plus `build_number` for website and updater consumers.
- Public changelog files remain semantic-version scoped, for example
  `/updates/changelog/v0.6.5.md`, unless a release intentionally needs
  separate notes for each build.

Current environment and signing rule:

- Maintainer batch helpers load environment values from a private, local
  operator env file. Do not commit env contents or treat repository templates as
  canonical secret storage.
- The maintainer release script signs the Windows app executable before packaging and signs
  the Inno Setup installer before checksum generation when Windows signing is
  enabled and credentials are configured. The signing certificate path is
  environment-configured.
- Keep signing before checksum generation when signing is enabled. For the
  unsigned/open-source path, generate checksums only after the final installer
  artifact has been accepted so published checksums describe the exact
  artifact users download.
- `windows_installer.iss` is the installer recipe in the repo root; the release
  machine must still provide Inno Setup's `ISCC.exe`. Nonstandard installs can
  be pointed at with `IG_INNO_SETUP_COMPILER`, `IG_ISCC`, or
  `INNO_SETUP_COMPILER` in the configured private env file.
- Keep Windows signing commands out of parenthesized batch branches. Windows
  SDK paths often include parentheses, and raw `cmd.exe` parsing can otherwise
  fail with `\Windows was unexpected at this time`.
- `WINDOWS_SIGNTOOL` may point either to `signtool.exe` or to the SDK folder
  that contains it; release tooling should normalize the folder form before
  signing.
- Checksum generation should stay independent of optional PowerShell cmdlets;
  release tooling should not silently produce a bad checksum file when
  `Get-FileHash` is unavailable.
- Keep local packaging logs outside committed source so launcher-window
  failures remain diagnosable.
- The release flow must copy selected artifacts into the publication target
  before copying `latest.json` last.
- Restart or refresh the web service only after the web deployment target has
  the intended bundle.
- iOS/macOS release handoffs should carry the current architecture and release
  notes alongside the app checkout.

GIF provider release rule:

- `build_release.dart` may forward `GIF_API_BASE_URL` into release builds for
  managed relay-backed artifacts.
- `KLIPY_API_KEY` is ignored by default even when present in the environment.
  It is embedded only when `--allow_direct_klipy_api_key` or
  `ALLOW_DIRECT_KLIPY_API_KEY=1` is supplied intentionally.
- Public/user-setup builds should normally ship with no direct KLIPY key and
  either an intentional relay URL or empty GIF provider setup so users can add
  their own relay/API key from General settings.

## TODOs To Verify In Repo

- Verify the current active Linux desktop release policy before documenting it as a first-class shipped target rather than a supported runner.
- Verify the current iOS distribution path outside the repo before documenting exact ad-hoc/internal distribution steps here.
