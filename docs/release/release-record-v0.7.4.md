# Release Record: Inter Galactic v0.7.4

Status: live release published on 2026-06-16

Release cycle: `v0.7.4`
Current desktop/Android live build: `0.7.4+985`
Current iOS/TestFlight candidate build: `0.7.4+986`
Current pubspec identity: `intergalactic/pubspec.yaml` reports `version: 0.7.4+986`

## Scope

This is the semantic-version release-cycle record for `v0.7.4`. Build-specific
artifact attempts stay inside this record as ledger rows. Exact artifacts,
manifests, checksums, source archives, installer trust state, APK/IPA uploads,
and update smoke must still cite the exact `X.Y.Z+build`.

## Build Ledger

| Build | Status | Evidence scope | Notes |
| --- | --- | --- | --- |
| `0.7.4+986` | App Store Connect IPA exported; waiting for upload evidence | iOS/TestFlight refreshed IPA only | IOS refreshed the iOS export-compliance metadata after the user reported Apple confirmed the build can specify no non-exempt encryption / documentation exemption through `Info.plist`. The refreshed IPA was exported on 2026-06-16 with SHA-256 `be84215a6ba5d7c331a97791ea30934abba6a106ebf86a9c5a242b102482f19e`; Runner reports bundle id `chat.intergalactic.app`, version `0.7.4`, build `986`, production APNs entitlement, privacy manifest, Broadcast Extension, `app-store-connect` export method, and `ITSAppUsesNonExemptEncryption=false`. No App Store Connect CLI upload was run because credentials were not configured locally. Desktop/Android public release artifacts remain `0.7.4+985`; if `0.7.4+986` is submitted beyond TestFlight, refresh exact source-offer evidence for this build. |
| `0.7.4+985` | Live release published; Windows/Android update smoke passed | Final desktop/Android website release set | Release Pipeline ran the authorized non-dry-run `release.bat --include-android` flow on 2026-06-16 from clean app repo HEAD `5ea73c0`. Artifacts were regenerated into the live website mirror, and `updates/latest.json` was copied last. Public verification confirms `latest.json` reports `v0.7.4+985`, the installer/APK/source/checksum/changelog URLs return HTTP 200, and the public checksum file matches the final artifact hashes. User confirmed on 2026-06-16 that the app auto-detected the update and updated successfully through both the Windows desktop path and Android APK path. |
| `0.7.4+985` | Final package dry-run passed after REVIEW freeze; ready for rollout authorization | Current candidate | Release Pipeline reran the dry-run packaging pass on 2026-06-16 after REVIEW froze Android evidence and public changelog state. Local `dist` installer, source archive, checksums, non-placeholder changelog, and `latest.json` were regenerated for `v0.7.4+985`; artifact hygiene passed. No live release occurred and no update files were copied into the live website mirror. REVIEW release-closeout on 2026-06-16 accepted the current untrusted-root/unsigned-consent Windows path, recorded S&C/notice defers, and left explicit live-release authorization plus post-publish verification as the remaining Release Pipeline boundary. |

## 2026-06-16 Live Publish

Release Pipeline completed the user-authorized full release for
`v0.7.4+985`.

Publish command:

- `release.bat --include-android` with `IG_RELEASE_NO_PAUSE=1` and
  `IG_INNO_SETUP_COMPILER` set to the installed Inno Setup 6 compiler.
- Release log: `release-logs\release-20260616-153405.log`.
- App repo source HEAD used for packaging:
  `5ea73c0` (`[AGENT:REVIEW] record export compliance closeout`).

Published artifact URLs:

- Installer:
  `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.4+985.exe`
- Android APK:
  `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.4+985.apk`
- Source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- Checksums:
  `https://app.ourgalaxy.space/downloads/checksums-0.7.4+985.txt`
- Update manifest:
  `https://app.ourgalaxy.space/updates/latest.json`
- Changelog:
  `https://app.ourgalaxy.space/updates/changelog/v0.7.4.md`

Final checksum file contents:

```text
SHA256  InterGalactic-Setup-0.7.4+985.exe  CD7AD3F8CB4D477792D5F549E1FDE04C9C55F0CCBA41473A54E180E09BB6DE13
SHA256  InterGalactic-0.7.4+985.apk  ABBA70D04DE69FD5021B5BDA1FE63029DBB05AD9D340034F1E91213CE565799C
SHA256  intergalactic-0.7.4+985-source.zip  342280CB6ED1A8684B96EDCD78F36CB98A9F5AC828C57041322378701AB70255
```

Local mirror verification:

- The live website mirror's `updates/latest.json` reports
  `v0.7.4+985`, `version_name` `0.7.4`, and build number `985`.
- Manifest URLs point to the final installer, Android APK, source archive, and
  checksum file above.
- Windows `auto_update` is `true` and
  `allow_unsigned_auto_update` is `true`.
- Android `auto_update` is `false`, matching the website-download APK route.
- Local artifact hashes match the final checksum file.
- Artifact hygiene passed:
  `.github/scripts/security-review.py --repo-root . --artifact-root dist`.

Public endpoint verification:

- Public `latest.json` returned HTTP 200, has no UTF-8 BOM, strict-parses as
  JSON with UTF-8 decoding, and reports `v0.7.4+985`.
- Public installer URL returned HTTP 200 with content length `171783496`.
- Public Android APK URL returned HTTP 200 with content length `237410714`.
- Public source archive URL returned HTTP 200 with content length `165545020`.
- Public checksum and changelog URLs returned HTTP 200; checksum entries match
  the final hashes above, both text files have no UTF-8 BOM, and the changelog
  starts with `# Inter Galactic v0.7.4 Beta`.

Metadata encoding hotfix:

- Post-publish verification found the initially published `latest.json`,
  checksum file, and changelog were UTF-8 with BOM because `release.bat` used
  Windows PowerShell `Set-Content -Encoding UTF8`.
- Release Pipeline patched `release.bat` to write generated release text files
  with BOM-less UTF-8 and repaired the already-published `v0.7.4+985`
  metadata files in place. The installer, Android APK, and source archive were
  not rebuilt or modified, so the final artifact hashes above remain valid.

Windows trust status:

- Authenticode status for the published installer remains `UnknownError`
  because the signing chain terminates in an untrusted root. This matches the
  approved unsigned/untrusted desktop consent path documented for this rollout.
  The update manifest keeps `allow_unsigned_auto_update=true`.

Post-release validations:

- Passed on 2026-06-16 by user confirmation: an installed Windows desktop app
  auto-detected the live update and updated successfully.
- Passed on 2026-06-16 by user confirmation: the Android APK path
  auto-detected the update and updated successfully.
- iPhone: IPA is complete and waiting for upload. IOS owns the remaining
  TestFlight/App Store upload evidence and released-TestFlight notification
  provider-payload/local-rendering proof.
- iPhone refreshed candidate: IOS exported `0.7.4+986` after the user-reported
  Apple export-compliance guidance changed the required plist route to
  `ITSAppUsesNonExemptEncryption=false`. Upload evidence remains
  pending.

## Carry-Forward Rule

When a release finding requires another `0.7.4+build` candidate, keep this file
as the active release-cycle record. Add a new build-ledger row and rerun only
the gates invalidated by the source, asset, dependency, signing, manifest,
artifact, store, or publication-surface change.

Carry-forward evidence must state why it remains valid for the new build.
Evidence that proves exact artifacts, installer signing, checksums, `latest.json`,
source archive, APK/IPA upload, desktop updater smoke, or public download URLs
does not carry forward automatically.

## Current Gate Disposition

Use `docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md` and
`docs/agent-control/integration-queue.md` as the live gate sources. At the time
this cycle record was opened, the remaining release gates were owner-scoped and
included encryption export evidence, runtime/report redaction resampling where
needed, encrypted-room push payload privacy proof, final third-party
notice/asset provenance surface exposure, rollback proof, public GitHub/source
rebaseline, and rebuilt Windows FFmpeg story-export smoke or explicit release
owner acceptance.

As of the 2026-06-16 REVIEW closeout after S&C completed its prerelease pass,
there are no remaining S&C or third-party notice blockers for the current
website/TestFlight rollout. Remaining items are either Release Pipeline publish
execution, accepted defers, future public-store/public-GitHub route gates, or
post-publish verification.

## 2026-06-16 Release Pipeline Prep Snapshot

Release Pipeline prepared the `v0.7.4` cycle for release review without
publishing. The user explicitly directed that the update not be released yet
and that update files not be placed into the live website mirror, because
those mirrored paths are equivalent to live release staging.

Observed candidate state:

- Current app identity: `intergalactic/pubspec.yaml` reports
  `version: 0.7.4+985`.
- Current app repository HEAD observed before this docs pass: `65c1f59`.
- The `0.7.4+985` Windows candidate artifact set included a `windows-release`
  output plus
  `inter-galactic-windows-v0.7.4+985.zip`.
- The Windows release output includes the bundled desktop story-video FFmpeg
  pair at `windows-release\tools\ffmpeg\ffmpeg.exe` and
  `windows-release\tools\ffmpeg\ffprobe.exe`. This confirms packaging inputs
  are present, but it does not close the rebuilt story-export smoke gate.
- The `0.7.4+985` Android APK candidate was observed with size
  `236607898` bytes.
- App `dist\updates\latest.json` still describes the previous published
  `v0.7.3+984` package set. No `0.7.4+985` manifest was produced in this pass.

Dry-run attempt:

- Command: `release.bat --dry-run --include-android` with
  `WINDOWS_SIGNING_ENABLED=0` and `IG_RELEASE_NO_PAUSE=1`.
- Log: `release-logs\release-20260616-112624.log`.
- Result: failed before installer packaging with
  `Inno Setup compiler (ISCC.exe) not found`.
- Release identity verification passed for `v0.7.4+985` before the failure.
- The dry-run stopped before the local server mirror sync step, so no
  live website mirror update/download/source files were copied.

Open gates before release:

- REVIEW prepared the public `v0.7.4` changelog source with build identity
  `v0.7.4+985` and regenerated the local
  `dist\updates\changelog\v0.7.4.md` output. Final packaging must still rerun
  after source freeze so the release artifact set is generated from the final
  tracked source and release-note state.
- Resolve the Windows installer trust path. SignTool completed for the app
  executable and installer, but Windows Authenticode verification reports
  `UnknownError` because the certificate chain terminates in an untrusted
  root. Keep the manifest's explicit unsigned/untrusted consent path unless a
  trusted `Valid` installer is produced and revalidated.
- REVIEW reconciled the user-refreshed Android release evidence after the
  dry-run. The dry-run source archive was generated from tracked app repo HEAD
  `f05de5b`, before the subsequent release-pipeline evidence commit and this
  REVIEW reconciliation, so final packaging must rerun after source freeze.
- Keep the public tracker open for encryption export evidence, rollback
  artifact/process validation, remaining crash/report redaction resampling if
  evidence becomes available, encrypted-room push payload privacy proof,
  complete notice/About access-surface closure, rebuilt FFmpeg story-export
  smoke, iOS/store metadata, and counsel/export review.
- Do not publish `latest.json` or copy release files into the live website mirror
  until the release owner explicitly starts the live publish step.

## 2026-06-16 Release Pipeline Dry-Run Refresh

After the user refreshed the builds, Release Pipeline reran the package
validation without publishing.

Observed refreshed candidate state:

- Current app identity remains `version: 0.7.4+985`.
- Current tracked app repository HEAD is `f05de5b`
  (`[AGENT:RELEASE PIPELINE] record v0.7.4 release prep`).
- The refreshed Android APK for `0.7.4+985` was regenerated with observed size
  `237410714` bytes.
- Existing app repo dirty files at dry-run time were limited to
  user-refreshed Android release evidence under
  `docs/release/evidence/android-*`; Release Pipeline did not stage, edit, or
  commit those evidence files.

Dry-run attempts:

- `release.bat --dry-run --include-android` with the inherited release
  environment still failed to resolve `ISCC.exe`.
  Log: `release-logs\release-20260616-121246.log`.
- Rerunning the same dry-run with `IG_INNO_SETUP_COMPILER` pointed at the
  installed user-local Inno Setup compiler succeeded.
  Log: `release-logs\release-20260616-121336.log`.
- Inno Setup compiler version reported by the run: `6.7.1`.
- Release identity verification passed for `v0.7.4+985` before packaging and
  again after manifest/artifact generation.

Generated dry-run artifacts:

- Installer: `dist\installer\InterGalactic-Setup-0.7.4+985.exe`
- Source archive: `dist\source\intergalactic-0.7.4+985-source.zip`
- Checksums: `dist\checksums\checksums-0.7.4+985.txt`
- Manifest: `dist\updates\latest.json`
- Changelog output: `dist\updates\changelog\v0.7.4.md`

Checksum file contents:

```text
SHA256  InterGalactic-Setup-0.7.4+985.exe  E0E9F46C0CF9F243A898C4B32622E6FBB0C59144575E4C1F8D27EF6C86E71BDD
SHA256  InterGalactic-0.7.4+985.apk  ABBA70D04DE69FD5021B5BDA1FE63029DBB05AD9D340034F1E91213CE565799C
SHA256  intergalactic-0.7.4+985-source.zip  5826D1BAF20D501BB7D2E60AA08573C04D16A71EDC3DF6337948FF2CE981B33B
```

Manifest checks:

- `version`: `v0.7.4+985`
- `version_name`: `0.7.4`
- `build_number`: `985`
- Windows URL: `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.4+985.exe`
- Android URL: `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.4+985.apk`
- Checksums URL:
  `https://app.ourgalaxy.space/downloads/checksums-0.7.4+985.txt`
- Source URL:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- `platforms.windows.auto_update`: `true`
- `platforms.windows.allow_unsigned_auto_update`: `true`

Validation:

- `.github/scripts/security-review.py --repo-root . --artifact-root dist`
  passed from the app repo.
- Authenticode verification on the generated installer and packaged app
  executable returned `UnknownError` with an untrusted-root certificate-chain
  message. Treat this as the documented unsigned/untrusted consent path unless
  a trusted `Valid` installer is produced and rechecked.
- The local website mirror remained untouched: expected `0.7.4+985` installer,
  APK, checksum, source archive, and changelog files are absent, and the mirror
  `updates/latest.json` still reports `v0.7.3+984`.
- The generated changelog output was a placeholder at dry-run time:
  `# Inter Galactic v0.7.4+985` followed by
  `Release notes not yet available.` REVIEW replaced the local output after
  preparing the public changelog source; final packaging must rerun before any
  live release.

## 2026-06-16 Public Changelog Preparation

REVIEW prepared the public-safe `v0.7.4` release notes for build
`v0.7.4+985`.

Evidence placement:

- Workspace release source:
  `docs/PUBLIC_CHANGELOG.md`
- App-repo public mirror for source archives/public repository readers:
  `PUBLIC_CHANGELOG.md`
- Local generated dry-run output:
  `dist\updates\changelog\v0.7.4.md`

Verification:

- The release-batch extraction rule found the `# Inter Galactic v0.7.4 Beta`
  section and wrote 100 lines to the local generated changelog output.
- The generated output starts with `# Inter Galactic v0.7.4 Beta` and no longer
  contains `Release notes not yet available.`
- The new public changelog entry contains no local workspace path markers.

This closes the placeholder public changelog subgate. Final package generation
still must rerun after release docs, evidence, and changelog are frozen because
the existing dry-run source archive and manifest were created before this
public changelog preparation.

## 2026-06-16 Android Evidence Reconciliation

REVIEW reconciled the refreshed Android release evidence produced for
`0.7.4+985` after the user-run Android release build.

Evidence placement:

- Android Gradle runtime evidence:
  `docs/release/evidence/android-gradle/0.7.4+985/`
- Android FCM license evidence:
  `docs/release/evidence/android-fcm/0.7.4+985/`
- Google OSS Licenses baseline evidence:
  `docs/release/evidence/android-oss-licenses/0.7.4+985/`

Verification:

- Refreshed APK has SHA256
  `ABBA70D04DE69FD5021B5BDA1FE63029DBB05AD9D340034F1E91213CE565799C`,
  matching `dist\checksums\checksums-0.7.4+985.txt`.
- Android Gradle evidence status is `complete`: 171 runtime modules, 106
  POM-derived records, 65 source/policy overrides, and 0 missing records.
- Android FCM evidence records 7 Firebase/FlutterFire packages with 0 missing
  license files.
- Google OSS Licenses baseline status is `complete`: 3 generated files, 228
  parsed notice names, and 229 dependency modules.
- The generated Google OSS file hashes in the baseline JSON match the current
  generated files.
- Android evidence JSON parses, collector scripts parse, evidence text files
  are UTF-8 without BOM, and the Android evidence directories have no retained
  local path or `file:///` references.

Collector hardening:

- Android Gradle, FCM, and Google OSS evidence collectors now write UTF-8
  without BOM using LF line endings.
- The Google OSS baseline collector normalizes local Gradle report file URLs to
  public redacted file references.

This closes the dirty refreshed Android evidence review subgate. Final package
generation still must rerun after release docs, changelog, and evidence are
frozen because the existing dry-run source archive predates this reconciliation.

## 2026-06-16 Final Package Dry-Run After REVIEW Freeze

Release Pipeline reran the final package dry run after REVIEW completed the
public changelog and Android evidence freeze. The first in-sandbox attempt
failed because the installed Inno Setup compiler path was not visible to the
sandbox. The rerun outside the sandbox succeeded with the same dry-run release
scope and did not publish.

Observed candidate state:

- Current app identity remains `version: 0.7.4+985`.
- Current tracked app repository HEAD is `32f3ae4`
  (`[AGENT:REVIEW] prepare v0.7.4 public changelog`).
- Command scope: `release.bat --dry-run --include-android`.
- Failed sandbox log: `release-logs\release-20260616-134803.log`.
- Successful dry-run log: `release-logs\release-20260616-134828.log`.

Generated dry-run artifacts:

- Installer: `dist\installer\InterGalactic-Setup-0.7.4+985.exe`
- Android APK for `0.7.4+985`
- Source archive: `dist\source\intergalactic-0.7.4+985-source.zip`
- Checksums: `dist\checksums\checksums-0.7.4+985.txt`
- Manifest: `dist\updates\latest.json`
- Changelog output: `dist\updates\changelog\v0.7.4.md`

Checksum file contents:

```text
SHA256  InterGalactic-Setup-0.7.4+985.exe  3CFFAC716543C884799CF1FD803067CDB680E244448965DE60D92F75395065FA
SHA256  InterGalactic-0.7.4+985.apk  ABBA70D04DE69FD5021B5BDA1FE63029DBB05AD9D340034F1E91213CE565799C
SHA256  intergalactic-0.7.4+985-source.zip  C84CDB43D0B3B95EEFE632106087FEB68C5B29B793D67B9E21259BDDC5A52E07
```

Manifest checks:

- `version`: `v0.7.4+985`
- `version_name`: `0.7.4`
- `build_number`: `985`
- Windows URL:
  `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.4+985.exe`
- Android URL:
  `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.4+985.apk`
- Checksums URL:
  `https://app.ourgalaxy.space/downloads/checksums-0.7.4+985.txt`
- Source URL:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- `platforms.windows.auto_update`: `true`
- `platforms.windows.allow_unsigned_auto_update`: `true`

Validation:

- Release identity verification passed before and after packaging.
- Changelog extraction passed for `v0.7.4+985`; the generated changelog starts
  with `# Inter Galactic v0.7.4 Beta`, has 84 lines, and no longer contains the
  placeholder `Release notes not yet available.` text.
- `.github/scripts/security-review.py --repo-root . --artifact-root dist`
  passed from the app repo after the final dry-run artifacts were generated.
- Authenticode verification on both the generated installer and packaged app
  executable returned `UnknownError` with an untrusted-root certificate-chain
  message. Treat this as the documented unsigned/untrusted consent path unless
  a trusted `Valid` installer is produced and rechecked.
- The local website mirror remained untouched: expected `0.7.4+985` installer,
  APK, checksum, source archive, and changelog files are absent, and the mirror
  `updates/latest.json` still reports `v0.7.3+984`.

This dry-run closes the package/source-archive rerun subgate after REVIEW's
evidence and public changelog freeze. It does not approve live publication.
Before the live release step, the release owner must still resolve or accept
the remaining public tracker gates and explicitly authorize copying the dry-run
artifact set into the live mirror.

## 2026-06-16 Rollback Proof Archive

Release Pipeline completed the rollback proof for the current `v0.7.4`
release cycle by archiving the previous live mirror state for `v0.7.3+984`.
The live website mirror was used as a read-only source; no publication files
were changed.

Archived rollback set:

- Archive folder:
  `release-rollback/v0.7.4/previous-v0.7.3+984-20260616-143137/`
- Archive zip:
  `release-rollback/v0.7.4/previous-v0.7.3+984-20260616-143137.zip`
- Zip SHA-256:
  `7FBFF5A92C712C314894DF918A30DA4171024F21522FFCA31ED6DA8F57717918`
- Zip entries: 7

Archived files:

- `updates/latest.json`
- `updates/changelog/v0.7.3.md`
- `downloads/checksums-0.7.3+984.txt`
- `downloads/InterGalactic-Setup-0.7.3+984.exe`
- `downloads/InterGalactic-0.7.3+984.apk`
- `source/intergalactic-0.7.3+984-source.zip`
- `rollback-proof.json`

Proof results:

- Archived manifest reports `version: v0.7.3+984`, `version_name: 0.7.3`,
  `build_number: 984`, and `pub_date: 2026-06-11T23:03:40Z`.
- Archived manifest keeps Windows `auto_update: true` and
  `allow_unsigned_auto_update: true`; Android remains direct-download with
  `auto_update: false`.
- Archived checksum file entries matched the archived artifacts:
  - Windows installer:
    `99E2AC77E40690B06D489D49FA42281422FBAE61E54FBF5E3F3D0C35DE882842`
  - Android APK:
    `E6BBA0C6AD690BDE2FFE34EF6F25D797A9E83F47C8171FA470C3C48DDF48F5ED`
  - Source archive:
    `7AEB2033B2DCD27EF7998F439663F07C9FDC970B66FB89ED840804DE1E299684`
- Archived Windows installer Authenticode status is `NotSigned`, matching the
  previously approved checksum-plus-unsigned-consent path for `v0.7.3+984`.
- `rollback-proof.json` records the manifest fields, copied artifact hashes,
  checksum verification, installer signature status, and restore order.

Restore order if `v0.7.4` must be rolled back before or after publication:

1. Restore or confirm the archived `downloads/`, `source/`, and
   `updates/changelog/` assets exist in the live mirror.
2. Copy the archived `updates/latest.json` to the live mirror first during a
   rollback from a bad newer manifest, or last during a forward release.
3. Recheck manifest JSON, artifact presence, SHA-256 matches, and public URLs
   before announcing rollback completion.

Public HEAD verification was attempted from this Windows host with both
PowerShell and `curl.exe`, but SChannel TLS failed before HTTP status results
were returned; WSL was unavailable. Treat public URL reachability as already
covered by the earlier `v0.7.3+984` release smoke unless another machine can
rerun the public HEAD check before live publication.

## 2026-06-16 Release-Owner Gate Dispositions

The current release remains a TestFlight/release-candidate scope rather than a
public App Store launch. Release-owner evidence and acceptance on 2026-06-16:

- Encryption export compliance: user confirmed IOS handled the App Store
  Connect encryption export compliance work for the current TestFlight build.
  Retain the IOS/App Store Connect evidence with release records. This records
  engineering release-gate evidence, not legal advice.
- Third-party notices and asset provenance: user confirmed the
  About/Settings/public notice access surface is verified. Generated notices,
  license evidence, asset provenance, and retained Commet-inherited
  sound/ringtone/confetti asset provenance stay accepted as-is for this release
  scope unless asset bytes change.
- FFmpeg story-export smoke: the rebuilt Windows story-video path currently
  fails with `video could not be recorded.` Release owner accepts deferring
  that runtime story-export validation to the next release rather than
  reopening the completed license/provenance evidence.
- Runtime redaction: BUG-224 Matrix API URI redaction is implemented, covered
  by focused redactor tests and targeted analyzer validation, and supported by
  rebuilt-app non-crash/support-artifact redaction evidence. No safe
  user-accessible crash reproduction path is currently available. Release owner
  accepts the remaining crash/report exception-path resample as post-release or
  controlled-harness validation if a natural crash report occurs or DEBUG/REVIEW
  adds a dev-only crash harness.
- Push privacy remains open for verification from a released iOS/TestFlight
  build so provider payload privacy can be checked without regressing readable
  local notifications or tap-to-room routing.
- Public store metadata remains a future public App Store route gate. For the
  current TestFlight-only scope, keep only the TestFlight/App Store Connect
  fields required for beta distribution current with the release notes, privacy,
  export, support, and reviewer-flow evidence.
- Windows trust path: Release Pipeline dry-run `latest.json` enables the
  documented unsigned/untrusted consent path with checksums. REVIEW accepts
  this path for the current rollout unless a trusted `Valid` installer is
  produced and revalidated before live publication.
- Advisory-alert coverage: GitHub `security-review.yml` passed, while
  Dependabot/code-scanning alert surfaces were disabled or inaccessible and the
  Dependency Review job was skipped. REVIEW records advisory-alert coverage as
  explicitly deferred for this rollout; enable those surfaces or run an
  approved advisory scanner before a future full public sign-off.
- Release automation: the release.bat rollback-proof archive automation is
  deferred until after this release because Release Pipeline already archived
  the previous live `0.7.3+984` rollback set for the current `0.7.4` rollout.
- Counsel/legal review remains an external future gate. This release record is
  engineering evidence and not legal advice.

## 2026-06-16 REVIEW Release-Closeout Handoff

REVIEW reconciled S&C's completed prerelease work, the third-party notice
surface, and Release Pipeline's dry-run/rollback evidence at 2026-06-16
15:15 -04:00.

Current rollout posture:

- Release Pipeline may proceed to the non-dry-run live publish flow after
  explicit live-release authorization.
- Keep the live website mirror untouched until that authorization is given.
- Publish artifacts before `latest.json`; copy or publish `latest.json` last.
- After live publication, run public URL, manifest, checksum, updater, Android
  APK, and TestFlight/App Store verification from the release checklist.
- Keep post-release queue items open for provider push-payload proof and
  future public-store/public-GitHub/counsel/advisory work.

## Artifact Policy

Do not publish or announce a build from this record until the exact build row
has matching artifacts, manifest, checksums, source archive, and platform smoke
evidence for the shipped scope. Downloadable artifacts and `latest.json` remain
`X.Y.Z+build` scoped.
