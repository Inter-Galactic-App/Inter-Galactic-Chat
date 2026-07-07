# Release Record: Inter Galactic v0.7.1+978

Historical record: this file preserves one release run as evidence. Local
workspace paths and mirror details have been removed from the public copy; keep
full maintainer-local evidence outside the public app repo.

Status: pre-release checklist pass complete - release packaging not yet approved
Review date: 2026-05-28
Reviewer: Maintainer review
Release scope: not selected yet; local release tooling will ask for desktop,
Android, or both
Artifact checklist: `docs/release/release-artifact-checklist.md`
Public notes source: workspace public changelog.

## Release Notes Candidate

Inter Galactic v0.7.1 is a beta update focused on release-delivery safety,
recent call/screen-share fixes, Android beta readiness, URL preview/cache
validation, and small sign-in usability polish.

### Beta Caveats

- Windows desktop installers may show expected trust warnings because this beta
  used a certificate chain that terminated in an untrusted root. Approval for
  that signing state was a release-owner decision for this hotfix build.
- Android beta builds may require manual APK install rather than Play Store
  distribution.
- iPhone beta access is through TestFlight when that channel is open.
- This remains beta software; manual download/install steps and platform-specific
  instability are possible.

Top manifest notes are now sourced from the new `v0.7.1` section in
`docs/PUBLIC_CHANGELOG.md`. The release script matches
`# Inter Galactic v0.7.1*`, so the same public section will be used for
`v0.7.1+978` and any same-semantic hotfix build.

## Current Identity

| Gate | Result | Evidence |
| --- | --- | --- |
| App version | Pass | `intergalactic/pubspec.yaml` currently reports `version: 0.7.1+978`. |
| Public changelog source | Pass | `docs/PUBLIC_CHANGELOG.md` now has a top `# Inter Galactic v0.7.1 Beta` section. A local extraction simulation captured that section successfully. |
| Current local desktop build | Partial | A local desktop zip for `0.7.1+978` existed. Release installer packaging was still pending. |
| Current local Android build | Blocked for combined release | No version-matched Android APK was found. Choose desktop-only or build Android `0.7.1+978` before selecting Android/both. |
| App-repo dist manifest | Needs release run | `dist\updates\latest.json` was absent. Release packaging should regenerate it before publication. |
| Current local web mirror | Existing previous build | The local web mirror still advertised the previous build with Windows and Android platform entries. |
| Dirty source check | Blocker until freeze | The app repo has dirty files across iOS notifications, biometric recovery, RNNoise/streaming, login UI, and docs. Freeze/commit the intended release source before final packaging. |

## Existing v0.7.1+975 Mirror Evidence

The local web mirror currently contains:

- `downloads\InterGalactic-Setup-0.7.1+975.exe`
- `downloads\InterGalactic-0.7.1+975.apk`
- `downloads\checksums-0.7.1+975.txt`
- `source\intergalactic-0.7.1+975-source.zip`
- `updates\changelog\v0.7.1.md`
- `updates\latest.json`

Checksum verification against the local mirror passed:

```text
SHA256  InterGalactic-Setup-0.7.1+975.exe  6BE2A6729876B422D689F88C8DB41B6F92C1D38AAB6C7BA2F54F7E53C6B72A40
SHA256  InterGalactic-0.7.1+975.apk  6DF9239AE70D18201A9902D85663417B4EEEBC641107966E5DAAC9A48D985F11
SHA256  intergalactic-0.7.1+975-source.zip  DFFDECE5DA6B07D88AF5E060E0D31270E72ACD72E0377D741892E8D53F7F6BB4
```

The Windows installer Authenticode check returned `UnknownError` because the
certificate chain terminates in an untrusted root. This matches the previous
beta signing caveat and should remain an explicit release-owner decision.

## Security Gate

Local command:

```powershell
python .github/scripts/security-review.py --repo-root . --artifact-root dist
```

Result: passed.

Notes:

- The gate reported expected Android `google-services.json` client files and
  dependency inventory paths. In current public-source practice, those Firebase
  client files are owner-local release inputs and should not be committed.
- A direct attempt to scan the external local mirror as `--artifact-root`
  crashed because the script formats artifact paths relative to the app repo.
  Manual mirror filename checks and source/APK zip member checks found no
  `.env`, `key.jks`, `key.properties`, `firebase_options.dart`,
  `bot-storage.json`, `.p8`, `.p12`, or `.pfx` entries.
- LiveKit/WebRTC diagnostic export spot-check remains a release-time manual
  privacy gate if new diagnostics are captured for this release.

## Release Checklist Results

| Checklist area | Status | Notes |
| --- | --- | --- |
| Release scope | Pending | Choose desktop-only, Android-only, or both when packaging the release. |
| Public notes | Ready | `PUBLIC_CHANGELOG.md` has `v0.7.1` notes and no local absolute paths in the new section. |
| Artifact naming | Pending | Release packaging must create `InterGalactic-Setup-0.7.1+978.exe`, `checksums-0.7.1+978.txt`, `intergalactic-0.7.1+978-source.zip`, and optionally `InterGalactic-0.7.1+978.apk`. |
| Manifest scope | Pending | Verify `platforms` only includes the selected release targets. |
| Checksums | Pending | Recompute after signing/package creation. |
| Source archive | Pending | Must be generated from the frozen release commit. |
| Local mirror sync | Pending | Release packaging should copy artifacts to the configured publication mirror and copy `latest.json` last. |
| GitHub security/dependency checks | Pending | Local gate passed; GitHub workflow/Dependency Review still depends on the release branch/PR state. |
| Runtime smoke | Pending | User-side release-candidate smoke is still needed after packaging. |
| Live URL verification | Pending | Verify public URLs after deployment propagation. |

## Rollback Record

Rollback point before publishing `v0.7.1+978`:

- Local mirror manifest currently advertises `v0.7.1+975`.
- Local mirror artifacts and checksums for `v0.7.1+975` matched during this
  pass.
- If `v0.7.1+978` is published and must be rolled back, restore the previous
  `latest.json` so clients see `v0.7.1+975`, then confirm the `v0.7.1+975`
  installer, APK, checksum, source, and changelog URLs still return HTTP 200.

## Personal Approval Needed

Before approving the real release, the user should decide or complete:

1. Choose release scope: desktop-only, Android-only, or both.
2. If Android is in scope, build `0.7.1+978` Android first so the APK matches
   the current pubspec identity.
3. Decide whether the current self-signed/untrusted-root Windows certificate is
   acceptable for this beta/public release.
4. Freeze or intentionally accept the current dirty source set before running
   final release packaging.
5. Run release packaging and confirm the generated `latest.json` has only the
   selected platform entries.
6. Smoke the packaged build: launch, sign in with show/hide password, restore a
   session, open encrypted rooms, confirm update notes, and cover any platform
   flows included in the selected release.
7. After deployment propagation, verify public download, changelog,
   checksum, source, and `latest.json` URLs.
