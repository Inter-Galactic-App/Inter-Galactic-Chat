# Versioning Policy

Maintainer note: this policy is public app-repo documentation. Keep personal
helper-script names, local artifact folders, and private deployment mirrors in
workspace-private release notes outside this repository.

## Source Of Truth

The release version source of truth is:

```yaml
intergalactic/pubspec.yaml
version: X.Y.Z+build
```

`X.Y.Z` is the semantic version. `build` is the monotonically increasing build
metadata used by update checks, artifact names, and mobile/store version codes.

Windows MSIX metadata mirrors the same release identity in the MSIX-required
dotted form:

```yaml
msix_version: X.Y.Z.build
```

## Version Forms

| Form | Example | Use |
| --- | --- | --- |
| Semantic version | `0.7.0` | Store notes, public changelog grouping |
| Build number | `967` | Mobile/store build identity and updater comparison |
| Full version | `0.7.0+967` | Artifact names and release directories |
| Version tag | `v0.7.0+967` | `VERSION_TAG`, `latest.json.version`, app update comparison |
| MSIX version | `0.7.0.967` | Windows MSIX package identity only |

## Bump Rules

- Bump build metadata for every public or tester-facing rebuild.
- Bump patch for bug-fix releases that users should recognize as a new patch.
- Bump minor for feature batches or meaningful release trains.
- Bump major only for a compatibility or product milestone that justifies it.
- Do not reuse a previously published `X.Y.Z+build`.
- Do not lower a build number for Android/iOS store channels.

## Release Cycle Records

Release pipeline coordination is semantic-version scoped. Treat `X.Y.Z` as the
release cycle and `+build` as an exact artifact attempt inside that cycle.

Use one active release-cycle record per semantic version:

- `docs/release/release-record-vX.Y.Z.md`

That record should contain a build ledger with rows for each candidate or
published build, for example `0.7.4+985`, `0.7.4+986`, and so on. When release
pipeline work finds an issue and the fix requires a new build number, continue
the same `vX.Y.Z` release-cycle record instead of restarting the whole release
packet in a new build-specific document.

Build-specific records such as `release-record-vX.Y.Z+build.md` may remain as
legacy exact-build evidence or be used for exceptional postmortems, but they
should not be the default release-pipeline coordination surface for new release
cycles.

Evidence can carry forward across builds only when the underlying input did not
change. Record the evidence scope explicitly:

- **Cycle evidence**: valid for the semantic release cycle until the related
  source, dependency, policy, signing, or publication surface changes.
- **Build evidence**: valid only for one `X.Y.Z+build` artifact set, such as
  checksums, installer signing state, `latest.json`, source archive, TestFlight
  upload, Android APK install, and desktop auto-update smoke.
- **Invalidated evidence**: must be rerun when the new build changes the code,
  assets, dependency graph, signing path, manifest, installer, APK/IPA, or any
  release blocker that the evidence was proving.

The practical rule is: bumping `+build` restarts exact-artifact validation, not
the entire release cycle. Re-run only the gates invalidated by the changes and
record why any prior evidence is still valid.

## Automation Source Of Truth

The release identity source of truth is the app pubspec plus the generated
release manifest and version-stamped artifacts. Local maintainer automation may
drive the build, signing, packaging, and publication steps, but public docs
should not require one maintainer's private script layout.

GitHub Actions are validation-only in this release phase. They may build,
analyze, test, or review artifacts, but they should not be treated as the
canonical signed-production release path.

Release identity consistency is enforced locally by
`intergalactic/scripts/verify_release_identity.ps1`, which compares the
pubspec identity with local build inputs, artifact names, update-manifest
fields, app build diagnostics, and iOS project version fields.

## Platform Build Identity

Windows:

- Build the current pubspec identity unless the release intentionally bumps
  `X.Y.Z+build`.
- Run the release identity verifier before building.
- Sync iOS Broadcast Extension project fields when the release process updates
  pubspec identity.

Android:

- Android builds read the current pubspec version and should not invent a
  separate build number.
- Release managers must bump pubspec before building Android if the APK will
  be tester-facing or public.
- Pass pubspec build metadata as the Flutter/Android build number.

iOS:

- `intergalactic/scripts/build_release.dart --platform ios --version_tag
  vX.Y.Z+build` requires that full version tag - it has no default and the
  script exits without it. It maps `X.Y.Z` to Flutter build name, maps `build`
  to Flutter/Xcode `FLUTTER_BUILD_NUMBER`, and syncs the Broadcast Extension
  project version fields before export.
- App Store/TestFlight builds must use a build number higher than any build
  already uploaded for the same app version.
- Full archive/export validation still requires macOS/Xcode and signing assets.

Web:

- Web builds read `X.Y.Z+build`, set `VERSION_TAG` to `vX.Y.Z+build`, and run
  release identity verification before deployment.

## Release Identity Verification

Run the local verifier before approving release artifacts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "intergalactic\scripts\verify_release_identity.ps1" `
  -ProjectRoot "." `
  -AppDir "intergalactic" `
  -ExpectedVersionTag "vX.Y.Z+build"
```

The release packaging flow should select Desktop, Android/mobile, or Both
explicitly. Desktop manifests enable Windows auto-update by default unless the
release is intentionally manual-download only. The unsigned-installer consent
fallback must be explicit in the manifest and should be disabled only for
strict Authenticode-valid releases. Run the verifier once before packaging and
again after `latest.json`, selected installer/APK filenames, source archive,
and checksums are present. The release must fail if the source archive cannot
be created from tracked source.
Selected release artifacts are copied into the configured publication target,
with `latest.json` copied last.
If per-release education copy is needed, set `IG_FEATURE_NOTES_FILE` or
`IG_FEATURE_NOTES_SOURCE`, or add
`docs\release\feature-notes\vX.Y.Z+build.md` before packaging the release.
The file is published as `updates/features/vX.Y.Z+build.md` and referenced by
`latest.json.feature_notes_url`.

## Artifact Naming Rule

Use full version names for downloadable artifacts:

- `InterGalactic-Setup-X.Y.Z+build.exe`
- `InterGalactic-X.Y.Z+build.apk`
- `intergalactic-X.Y.Z+build-source.zip`
- `checksums-X.Y.Z+build.txt`

Use semantic version names for public changelog grouping unless there is a
reason to publish separate notes for multiple builds under one semantic
version:

- `updates/changelog/vX.Y.Z.md`

## `latest.json` Version Rule

`latest.json` must publish:

- `version`: `vX.Y.Z+build`
- `version_name`: `X.Y.Z`
- `build_number`: numeric `build`
- `build_date_ms`: current release build timestamp in epoch milliseconds
- `platforms.windows`: only when Desktop is selected
- `platforms.android`: only when Android/mobile is selected
- `platforms.windows.auto_update`: `true` by default for Desktop releases
- `platforms.windows.allow_unsigned_auto_update`: `true` by default for the
  current open-source Windows consent path
- optional `feature_notes_url`: build-stamped user-facing Markdown for the
  post-update "What's New" dialog

The app compares `latest.json.version` with the baked
`BuildConfig.VERSION_TAG`, including build metadata. If the version parser
cannot compare tags, it falls back to `build_date_ms`.

## Store Channel Rules

Android:

- The APK build number must be monotonically increasing.
- Play Store version code cannot be reused or decreased.
- Direct APK users still need version-stamped filenames and manifest entries.

iOS:

- App Store Connect build numbers are per-version and cannot be reused after
  upload.
- TestFlight and App Store releases need a higher build number than the last
  processed build for that version.
- If the semantic version stays the same for a hotfix, increment build number.

## Release Notes Version Rule

Release notes should state:

- public version: `vX.Y.Z`
- build identity: `vX.Y.Z+build`
- platform scope: Windows, Android, iOS, web, or subset
- release-cycle record: `docs/release/release-record-vX.Y.Z.md`

Known issues and upgrade risks should be attached to the full build identity
when a risk only applies to one build under the same semantic version.

## Known Gaps

- Android and iOS release flows do not own version bumping directly.
- GitHub Actions are validation-only and are not the signed production release
  path while signed release automation remains maintainer-controlled.
- Store upload lanes for TestFlight/App Store and Play Store are not automated
  in-repo.
- The first real release-candidate packaging run should still be observed end
  to end on the release machine.
