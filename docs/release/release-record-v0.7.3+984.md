# Release Record: Inter Galactic v0.7.3+984

Status: release published; QA/user desktop, Android, and iOS install
validation passed; PR #38 merged; exact-source tag `v0.7.3+984` pushed
Release date: 2026-06-11
Release owner: Release Pipeline
Source commit: `91c4adf072dee05092f24943ee686c4eec91bd7e`
Release scope: Windows desktop, Android direct APK download, and iPhone/TestFlight; macOS/Linux remain future-demand architecture targets
Artifact checklist: `docs/release/release-artifact-checklist.md`
Readiness tracker: `docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md`

## Release Summary

Release Pipeline built and published the Windows desktop and Android APK
artifacts for `v0.7.3+984` from the reviewed source commit. Windows desktop is
published through the checksum-verified unsigned consent update path. Android
remains a direct APK download from the website.

iPhone/TestFlight was not built or uploaded from the Windows release run. IOS
produced the matching App Store/TestFlight IPA on macOS and opened it in
Apple's Transporter app for manual delivery through any signed-in GUI account.
On 2026-06-12, the user confirmed the IPA was uploaded and the `0.7.3+984`
update installed on their iPhone. This clears the iOS upload/install evidence
gate; broader iPhone functional smoke remains QA-owned if required.

On 2026-06-12, the user also confirmed the Windows updater/install path and
Android APK install/smoke path passed for the published `v0.7.3+984` artifacts.
Those confirmations clear the release-blocking manual desktop and Android
validation gates. Exact-build S&C readiness tracker boxes remain evidence-gated
to their owning artifacts and should not be closed from these release-smoke
confirmations alone.

The GitHub source closeout completed on 2026-06-12. PR #38 merged into
`main` at merge commit `0bb2381cf4e354719f1f85c19a70da03182f1b90` after
automated review success and successful `security-review`, `docs-secret-scan`,
and `static-analysis` checks on head
`b76d40d6552123671e510b7a7fc856ab812bbd47`. The annotated release tag
`v0.7.3+984` was pushed to GitHub and peels to the exact release source commit
`91c4adf072dee05092f24943ee686c4eec91bd7e`.

## Candidate Identity

| Gate | Result | Evidence |
| --- | --- | --- |
| Pubspec identity | Passed | `intergalactic/pubspec.yaml` reports `version: 0.7.3+984`. |
| Source commit | Passed | Built from `91c4adf072dee05092f24943ee686c4eec91bd7e`. |
| Working tree | Passed | App repo was clean before packaging and after build scripts completed. |
| Desktop build | Passed | `build.bat --no-bump` completed for `v0.7.3+984`; release folder and ZIP were produced. |
| Android build | Passed | `build_android.bat` completed a release APK with FCM / Google Services enabled. |
| Release dry run | Passed | `release.bat --dry-run --include-android` completed identity validation, installer packaging, checksums, source archive, changelog extraction, and manifest generation without mirror copy. |
| Release publish | Passed | `release.bat --include-android` copied installer, APK, checksums, source archive, changelog, and `latest.json` to the website publication target, with manifest copied last. |
| Artifact hygiene | Passed for desktop/Android artifacts | `security-review.py --repo-root . --artifact-root dist` passed. |
| Public endpoint | Passed for desktop/Android/source | Public `latest.json`, checksums, installer, APK, source archive, and changelog endpoints were reachable after sync. |
| iPhone/TestFlight | Passed for upload/install | IOS produced the matching App Store/TestFlight IPA for `0.7.3` build `984`; user confirmed on 2026-06-12 that the IPA was uploaded and the update installed on their iPhone. |
| Manual release smoke | Passed by user confirmation | User confirmed on 2026-06-12 that Windows updater/install, Android public APK install/smoke, and iPhone TestFlight update/install passed for `v0.7.3+984`. |
| PR #38 merge | Passed | Merged into `main` on 2026-06-12 at `0bb2381cf4e354719f1f85c19a70da03182f1b90` after automated review and CI success on head `b76d40d6552123671e510b7a7fc856ab812bbd47`. |
| Release tag | Passed | Remote annotated tag `v0.7.3+984` exists and peels to `91c4adf072dee05092f24943ee686c4eec91bd7e`. |

## GitHub Source Closeout

PR #38 was merged and the `v0.7.3+984` tag was pushed to the private-primary
repository. Neither private-primary URL is a public source link. The tag
historically pointed at source commit
`91c4adf072dee05092f24943ee686c4eec91bd7e`, because Windows desktop and
Android artifacts were built and published from that commit before later
documentation and review closeout commits landed.

On 2026-09-27, the public `Inter-Galactic-Chat` mirror did not advertise this
tag, and the former website source-archive route returned 404. No equivalent
public tag or archive was verified. The artifact and endpoint references below
record release-time publication, not current availability. A formal GitHub
Release page was deferred. Do not substitute a public-mirror tag URL or
retarget the historical tag without exact-source verification and release
review.

## Published Artifacts

| Artifact | Public URL | SHA-256 | Size |
| --- | --- | --- | --- |
| Windows installer | `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.3+984.exe` | `99E2AC77E40690B06D489D49FA42281422FBAE61E54FBF5E3F3D0C35DE882842` | 87,627,549 bytes |
| Android APK | `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.3+984.apk` | `E6BBA0C6AD690BDE2FFE34EF6F25D797A9E83F47C8171FA470C3C48DDF48F5ED` | 236,103,602 bytes |
| Source archive | `https://app.ourgalaxy.space/source/intergalactic-0.7.3+984-source.zip` | `7AEB2033B2DCD27EF7998F439663F07C9FDC970B66FB89ED840804DE1E299684` | 166,087,940 bytes |
| Desktop ZIP retention artifact | Local retained build artifact | `79EBBAF2FE2A92EE37A33BFCFC3CA218F015580C5E436C5DFDBCD5C3628DD6E5` | 120,993,972 bytes |
| iOS IPA | Local App Store/TestFlight artifact | `79c3bec7c04a6305ad0f1bd3e2df98305163b280e8fc0e638b6299fa721cc3eb` | about 77.8 MB by Flutter output / 74 MB on disk |

Checksum file:

`https://app.ourgalaxy.space/downloads/checksums-0.7.3+984.txt`

Public changelog:

`https://app.ourgalaxy.space/updates/changelog/v0.7.3.md`

Update manifest:

`https://app.ourgalaxy.space/updates/latest.json`

## Public Policy And Support URLs

Current public policy/support pages for this release packet:

- Website: `https://app.ourgalaxy.space/`
- Privacy Policy: `https://app.ourgalaxy.space/privacy/`
- Terms/EULA: `https://app.ourgalaxy.space/terms/`
- Support: `https://app.ourgalaxy.space/support/`
- Report Abuse: `https://app.ourgalaxy.space/report-abuse/`
- Account Deletion: `https://app.ourgalaxy.space/account-deletion/`
- Community Guidelines: `https://app.ourgalaxy.space/community-guidelines/`
- Source Offer: `https://app.ourgalaxy.space/source/`
- Exact submitted-build source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.3+984-source.zip`
- Support, abuse, privacy, and security routing inbox:
  `intergalactic@ourgalaxy.space`

DOCUMENTATION rechecked the listed policy/support/source URLs with Python HTTPS
HEAD requests on 2026-06-12. All returned HTTP 200; the source archive reported
the expected 166,087,940-byte length.

## Update Manifest Verification

The published `latest.json` was verified after sync with these release-relevant
fields:

- `version`: `v0.7.3+984`
- `version_name`: `0.7.3`
- `build_number`: `984`
- `platforms.windows.auto_update`: `true`
- `platforms.windows.allow_unsigned_auto_update`: `true`
- `platforms.android.auto_update`: `false`
- `platforms.windows.download_url`: `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.3+984.exe`
- `platforms.android.download_url`: `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.3+984.apk`

No per-release feature notes file was found for this build, so
`feature_notes_url` was not emitted.

## Windows Signing Mode

Authenticode signing was disabled for this release run because the project is
using the open-source checksum verification path rather than a paid Windows
code-signing certificate.

Release packaging used:

- `WINDOWS_SIGNING_ENABLED=0`
- `IG_WINDOWS_AUTO_UPDATE=1`
- `IG_ALLOW_UNSIGNED_AUTO_UPDATE=1`

This means Windows auto-update is intentionally allowed only through the
checksum-verified unsigned consent path. Users should still see the Windows
installer/UAC unsigned publisher warning and choose whether to proceed.

## Validation Run

| Check | Result |
| --- | --- |
| `build.bat --no-bump` | Passed |
| `build_android.bat` | Passed |
| `release.bat --dry-run --include-android` | Passed; log `release-20260611-185946.log` |
| `security-review.py --repo-root . --artifact-root dist` | Passed |
| `release.bat --include-android` | Passed; log `release-20260611-190213.log` |
| Local mirror hash comparison | Passed for installer, APK, and source archive |
| Public `latest.json` parse | Passed; reports `v0.7.3+984` |
| Public installer HEAD | Passed; HTTP 200, 87,627,549 bytes |
| Public APK HEAD | Passed; HTTP 200, 236,103,602 bytes |
| Public source archive HEAD | Passed; HTTP 200, 166,087,940 bytes |
| Public changelog fetch | Passed; first heading `# Inter Galactic v0.7.3 Beta`; release notes were refreshed from draft `v0.7.3+982` to published `v0.7.3+984` wording |
| PR #38 review status | Passed; automated review status success on `b76d40d6552123671e510b7a7fc856ab812bbd47` |
| PR #38 GitHub Actions | Passed; `security-review` run 101, `docs-secret-scan` run 27, and `static-analysis` run 190 completed successfully |
| PR #38 review threads | Passed; all inline review threads were resolved before merge |
| PR #38 merge | Passed; merged into `main` on 2026-06-12 at `0bb2381cf4e354719f1f85c19a70da03182f1b90` |
| Release tag push | Passed; pushed annotated tag `v0.7.3+984`, and remote peeled target is `91c4adf072dee05092f24943ee686c4eec91bd7e` |
| iOS IPA build | Passed; `dart run scripts/build_release.dart --platform ios --version_tag v0.7.3+984 --ios_export_method app-store` completed |
| iOS IPA identity | Passed; main app `chat.intergalactic.app` and Broadcast Extension `chat.intergalactic.app.broadcast` both report version `0.7.3`, build `984` |
| iOS export/signing | Passed; `ExportOptions.plist` reports `method=app-store-connect`, automatic signing, team `8RSRT93XU9`, and `testFlightInternalTestingOnly=false` |
| iOS production APNs | Passed; DistributionSummary, exported code signature, and embedded provisioning profile report main-app `aps-environment=production`; app group `group.chat.intergalactic.app` and `get-task-allow=false` are intact |
| iOS local code-sign verify | Passed; `codesign --verify --deep --strict --verbose=4` reports the unpacked exported app is valid on disk and satisfies its designated requirement |
| iOS CLI upload auth preflight | Blocked; `xcrun altool --validate-app` reports that JWT API-key auth or Apple ID app-specific-password/provider auth is required |
| iOS App Store/TestFlight delivery | Completed by user; the signed `InterGalactic.ipa` was delivered through Apple's Transporter app, and the user later confirmed the IPA was uploaded and installed on their iPhone |
| iOS TestFlight upload/install | Passed by user confirmation on 2026-06-12; uploaded IPA installed on the user's iPhone as the `v0.7.3+984` update |

## Rollback Reference

The previous live manifest observed before this publish was `v0.7.2+980`.
Rollback should follow `docs/release/rollback-plan.md`:

1. Restore or regenerate the previous `latest.json` for `v0.7.2+980`.
2. Copy the rollback manifest to `updates/latest.json` last.
3. Verify `https://app.ourgalaxy.space/updates/latest.json` reports
   `v0.7.2+980`.
4. Leave the `v0.7.3+984` artifacts in downloads/source unless there is a
   specific takedown reason; rollback should change update metadata first.

Known previous public artifact names:

- `InterGalactic-Setup-0.7.2+980.exe`
- `InterGalactic-0.7.2+980.apk`
- `checksums-0.7.2+980.txt`
- `intergalactic-0.7.2+980-source.zip`

## Remaining Follow-Up

- S&C/Review: reconcile public-release-readiness tracker items only from
  exact-build evidence; do not close App Store, privacy/export, or manual-test
  boxes from release-smoke confirmation alone.
- GitHub Release page: optional manual/tooling backfill remains if the project
  wants a formal GitHub Releases UI entry. REVIEW pushed the exact-source tag;
  do not retarget it away from
  `91c4adf072dee05092f24943ee686c4eec91bd7e`.
