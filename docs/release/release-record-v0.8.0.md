# Inter Galactic v0.8.0 Release Record

Status: v0.8.0+993 PUBLISHED and live. Corrected 2026-08-14 - this header
previously read "v0.8.0+993 desktop hotfix identity staged with exact-artifact
evidence pending", which stopped being true on 2026-07-09 and was never updated.
See "Observed on 2026-08-14" below.
Owner: RELEASE PIPELINE
Opened: 2026-07-03

## Scope

Current intended route:

- Desktop: primary release target with desktop auto-update.
- Android: website APK download route.
- iPhone: TestFlight/App Store Connect handoff to IOS.
- macOS/Linux: architecture exists, but not public release scope unless the
  user explicitly promotes either platform.

The live desktop plus Android website-mirror publish completed for
`0.8.0+992` on 2026-07-07. The release copied installer, Android APK,
checksums, source archive, changelog, feature notes, and `latest.json` to the
local website mirror, with rollback proof created first and `latest.json`
copied last. No build-output archive/delete cleanup was performed. iPhone
upload and TestFlight/App Store Connect processing remain the IOS/user lane.

## Current Identity Snapshot

Observed on 2026-07-03:

- Current pubspec identity: `0.8.0+991`.
- Current version tag: `v0.8.0+991`.
- Existing feature-note draft:
  `docs/release/feature-notes/v0.8.0+991.md`.
- Source freeze had not been declared, so the source tree was not treated as a
  release candidate.

Exception recorded by release owner:

- More bug fixes and a couple UI changes still need to land.
- Those changes are expected to bump the build number after testing completes.
- Therefore `0.8.0+991` is preliminary cycle evidence only, not the final
  release candidate identity.
- The final exact build is TBD and must be higher than `+991` if tester-facing
  or public.

Observed on 2026-07-05:

- Current pubspec identity: `0.8.0+992`.
- Current version tag: `v0.8.0+992`.
- Existing feature-note draft:
  `docs/release/feature-notes/v0.8.0+992.md`.
- `0.8.0+992` remains part of the same v0.8.0 release cycle. It invalidates
  final exact-artifact evidence, but it does not require restarting source-cycle
  evidence that a build-input delta report shows was untouched.
- Source freeze had still not been declared, so this remained preliminary
  cycle evidence only.

Observed on 2026-07-08:

- Current pubspec identity: `0.8.0+993`.
- Current version tag: `v0.8.0+993`.
- The accidental `0.8.1+994` development bump was not built. REVIEW reset the
  app pubspec, MSIX metadata, and release-verifier iOS project fields to the
  same v0.8.0 release cycle for a desktop hotfix.
- No `0.8.0+993` build, package, checksum, source archive, manifest, mirror
  copy, GitHub release, or public publish was produced by the reset pass.
- The desktop hotfix must rerun exact-artifact evidence before publication.

> The four lines above are accurate as of **2026-07-08** and are deliberately
> not rewritten. The hotfix was built and published the following day. See the
> next section.

Observed on 2026-08-14:

- **`v0.8.0+993` shipped on 2026-07-09 and is the live release.** The manifest
  has carried `"version": "v0.8.0+993"` since `pub_date`
  `2026-07-10T02:59:28Z`, and the installer, APK, checksum file and both source
  archives are all present on the mirror.
- **It was published in three passes on one day, and Windows and Android came
  from different commits.** The Windows installer was packaged at 11:38 from
  `29ed8795`, before `5cde7aea` ("Fix android overspill", 19:07) existed; the
  APK was built at 22:40, after it. That commit changes three shared Dart UI
  files - `favorite_rooms_list.dart`, `attachment_processor.dart` and
  `room_side_panel.dart` - which compile into the Windows binary but are not in
  it.
- **This build therefore has two build-matched source archives, and that is
  correct, not a duplicate.** `intergalactic-0.8.0+993-desktop-source.zip`
  corresponds to the Windows installer;
  `intergalactic-0.8.0+993-source.zip` corresponds to the APK. The desktop
  archive was originally published, later overwritten by the Android-matching
  one, and subsequently restored. **Do not "tidy" these into one archive.**
- The pairing was verified rather than asserted: `data/app.so` was extracted
  from the shipped installer (`sha256 d0bbb6c8…750a`) and confirmed
  byte-identical to the archived build output, and all three Dart files in the
  desktop archive match the `29ed8795` tree rather than `5cde7aea`. The full
  statement is `SOURCE-CORRESPONDENCE-0.8.0+993.md`, published at `/source/`
  beside the archives.
- **Why this record was wrong for five weeks:** nothing updated it after the
  release ran. The 2026-07-08 observations above were true when written, and
  with no later section they read as the current state - so the record asserted
  that a shipped, live release did not exist. `release.bat` has since been
  changed so a source archive is staged from the commit each binary was
  actually built from, which is the durable half of this defect; this section is
  the record half.

## Build Ledger

| Build | State | Notes | Exact-artifact evidence status |
| --- | --- | --- | --- |
| `0.8.0+991` | Preliminary | Current pubspec/build-note baseline. Feature-note draft exists. More bug/UI work is expected before release freeze. | Not final. Exact artifact validation, checksums, manifest, source archive, signing, desktop updater, Android APK, and iOS/TestFlight evidence must be regenerated for the final build. |
| `0.8.0+992` | Local mirror published | Final desktop plus Android website-mirror publish completed 2026-07-07 from clean `main`/`origin/main` at `57a956908acef70a7447b636acf6d8268748c6ff`. | Final local artifact validation, checksums, manifest, source archive, signing/unsigned-consent proof, rollback proof, package hygiene, and source/security review passed. Public endpoint verification is still pending from a working non-SChannel client after Syncthing/public sync. iOS upload/processing remains IOS/user handoff. |
| `0.8.0+993` | **PUBLISHED 2026-07-09/10** | Desktop hotfix plus Android, published in three passes on 2026-07-09; `latest.json` `pub_date` `2026-07-10T02:59:28Z`. **Windows and Android were built from DIFFERENT commits** - installer from `29ed8795` (archive taken at `d244a882`), APK from `5cde7aea` ("Fix android overspill") - so this build has TWO build-matched source archives and one cannot cover both. Row corrected 2026-08-14; it previously read "Pending desktop hotfix / No exact-artifact evidence yet", which was true only until 2026-07-09. | Installer `D02E03ED…B16C6`; APK `A06A185C…D3916`; Android-matching source `A46A8D32…1AAC2`; Windows-matching desktop source `7090332A…F35C3`. All four are entries in `checksums-0.8.0+993.txt`. Pairing and method recorded in `SOURCE-CORRESPONDENCE-0.8.0+993.md`, published at `/source/`: the Windows pairing was verified by extracting `data/app.so` from the shipped installer (`sha256 d0bbb6c8…750a`) and confirming byte-identity with the archived build output. |
| `0.8.0+TBD` | Pending | Expected after remaining bug fixes, UI changes, and testing complete. | This becomes the release-candidate candidate only after REVIEW/source freeze and release owner confirmation. |

## Same-Version Build-Bump Delta Workflow

The v0.8.0 release process is semantic-version scoped, not restarted from
scratch for every build-number bump.

When moving from one `0.8.0+build` candidate to another:

1. Record the previous candidate ref/build and the new candidate ref/build.
2. Produce a build-input delta report between those refs, including the working
   tree only when intentionally assessing internal release-readiness state.
3. Mark every triggered source-cycle, platform, and risk-smoke gate as needing
   fresh evidence for the new candidate.
4. Carry forward only gates that the delta report shows were untouched, and
   write the carry-forward reason in this release record.
5. Always regenerate final exact-artifact evidence for the new build number:
   package identity, installer/APK/IPA outputs, source archive, checksums,
   `latest.json`, signing or unsigned-consent trust path, updater smoke,
   rollback-proof, and artifact hygiene.

For the current `0.8.0+991` to `0.8.0+992` preliminary progression, no
carry-forward decision is final yet because release freeze has not been
declared.

## 2026-07-05 Windows Runtime Diagnostics Exclusion Proof

Release Pipeline performed a read-only package-hygiene proof for the current
preliminary `0.8.0+992` Windows desktop output after REVIEW hardened the root
`build.bat` archive gate.

Validation:

- The release package-cleanliness check passed against both the Windows payload
  and zip.
- Explicit payload and zip-entry searches found no `runtime/`,
  `game-capture-poc`, or `helper.log` entries.
- No build, publish, archive, delete, or website-mirror copy command was
  run during this evidence pass.

Disposition:

- The dedicated `Windows Release Runtime Diagnostics Exclusion Gate -
  2026-07-04` queue item can close for the REVIEW hardening proof.
- This is still preliminary `0.8.0+992` evidence. The final exact release
  candidate must rerun Windows package creation and artifact hygiene after
  release freeze/build identity is confirmed.

## 2026-07-04 DeepFilterNet/Hush Package Evidence Pass

Release Pipeline performed a read-only package inspection for the current
preliminary `0.8.0+991` Windows build output and zip.

Preliminary findings:

- `df.dll`, `DeepFilterNet3_onnx.tar.gz`, and
  `advanced_dfnet16k_model_best_onnx.tar.gz` are present in the current Windows
  release payload and release zip.
- Observed SHA-256 hashes match the DeepFilterNet native and Hush release
  evidence records.
- `df.dll.lib` is not present in the release zip, matching the intended
  link-only/import-library boundary.
- Focused scan of the noise-suppression plugin/app code found no runtime model
  download or audio upload implementation; diagnostic strings still state that
  WAV bug-report upload is disabled.

Disposition:

- This satisfies the current Release Pipeline package-identification wait for
  preliminary `0.8.0+991` only.
- Final release closeout still requires the final exact build package, source
  archive, notice surface, checksum, manifest, artifact hygiene, and local-only
  source scan proof.
- The current `0.8.0+991` release zip still includes
  `runtime/game-capture-poc/results/...` logs and handoff JSON/Markdown files,
  so it is not production-clean.
- Source-archive proof remains open for the final exact candidate.

## 2026-07-05 Emoticon Creator S&C Disposition

S&C reviewed the Emoticon Creator mobile native background-removal shape for
the preliminary `0.8.0+992` release cycle.

Disposition:

- S&C accepts the implemented mobile/native shape for continued release
  integration. Details are recorded in
  `docs/security/findings/EMOTICON_CREATOR_SECURITY_PRIVACY_REVIEW.md`.
- iOS uses Apple's local Vision framework on supported iOS versions.
- Android uses Google Play services ML Kit Subject Segmentation
  `com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1`,
  an API 24+ boundary, and unbundled `subject_segment` model metadata.
- No app-bundled subject-segmentation model file, desktop ONNX backend, cloud
  background-removal API, or background-removal API key was accepted in this
  pass.

Remaining release gates:

- Rebuilt Android real-photo smoke with network available.
- Rebuilt Android fresh-install/offline first-use smoke.
- Rebuilt iPhone iOS 17+ real-photo smoke.
- Final exact package/source archive proof after release freeze, including
  dependency/notice evidence and absence of unintended model artifacts.
- Final Google Play Data safety and App Store metadata reconciliation for the
  submitted build route.
- Separate S&C review before any desktop ONNX/model artifact is enabled.

## 2026-07-06 Release Queue Preparation Triage

Release Pipeline triaged the open release-pipeline integration queue items for
v0.8.0 release preparation.

Current release state:

- Current observed app identity remains `0.8.0+992`.
- REVIEW's PR #69 / CodeRabbit closeout is complete, but this is still not a
  release candidate until final source freeze, final build identity, final
  exact-artifact validation, and rebuilt platform smoke are complete.
- Current release scope remains desktop primary, Android website APK, and
  iPhone/TestFlight handoff. macOS/Linux remain future-demand targets unless
  explicitly promoted.
- No build, package, publish, upload, archive, delete, or
  website-mirror copy command was run during this triage.

Closed/non-blocking queue disposition:

- Closed the v0.8.0 sound-pack notice freshness row after verifying the
  current Renzo sound/ringtone hashes match
  `docs/release/evidence/license-sources/renzo-sounds/SOURCE.md` and the
  release notice/provenance docs reference the Renzo Mayo / Renzo! evidence.
- Closed the macOS extended testing row as non-blocking for the current release
  route because macOS is not part of this public release scope.
- Closed the historical artifact cleanup handoff as non-blocking maintenance.
  Archive-first cleanup still requires separate explicit user authorization
  before modifying local build outputs.

Remaining release-pipeline queue gates:

- Main v0.8.0 gate: final source freeze, final build identity, exact artifacts,
  rollback proof, updater checks, Android APK checks, and rebuilt platform
  smoke.
- Emoticon Creator: rebuilt Android/iPhone smoke plus final
  package/source/dependency/notice/store-disclosure proof.
- Optional Hush: final package must either prove Hush absence or complete Hush
  package/source/notice/local-only proof if included.
- Hugging Face model redistribution: final exact DeepFilterNet/Hush package,
  source archive, notice surface, local-only source scan, and artifact-hygiene
  proof.
- RNNoise/Enhanced audio: AUDIO owns behavior/tuning proof; Release Pipeline
  owns final package/source/notice proof for the selected
  DeepFilterNet/Hush artifact set.

## 2026-07-06 Pre-Release Workflow Gate

Release Pipeline started the pre-release workflow after the code-complete
signal. This is still a gated checkpoint, not a live release.

Public release state:

- Current candidate identity remains `v0.8.0+992`.
- Intended release scope is desktop plus Android APK; iPhone remains IOS
  TestFlight/App Store Connect handoff evidence.
- The candidate is not approved for live publication until source freeze,
  exact-artifact validation, rollback proof, and rebuilt platform smoke are
  complete.

Validation summary:

- Preliminary desktop and Android artifacts were generated through the local
  release workflow and passed package-hygiene checks for generated-runtime
  diagnostics.
- Public changelog extraction still needs release-owner attention before live
  publication.
- Feature notes exist for the candidate release.
- Owner-local environment inputs remained covered by repository ignore rules.

Pre-release disposition:

- `v0.8.0+992` is a strong preliminary candidate identity, but it is not yet an
  approved exact release candidate.
- Before final dry run, REVIEW must confirm source freeze or provide a clean
  release source, and the security gate must pass from that release source
  without owner-local private files entering the source/archive/artifact scan.
- Final exact-artifact evidence must still be regenerated for the chosen build:
  installer, APK, source archive, checksums, update manifest, feature-notes
  publish copy, Windows unsigned-consent/signing proof, rollback proof,
  package hygiene, desktop updater smoke, Android APK smoke, and iOS handoff
  confirmation.

## Preliminary Gates

These are open before any dry-run package or live release:

- Remaining bug fixes and UI changes land in the correct owner lanes.
- REVIEW completes source synchronization / CodeRabbit / PR closeout for the
  release source.
- Build number is bumped after testing if the result is tester-facing or
  public.
- `docs/release/feature-notes/` is updated or copied forward to the final
  exact build identity.
- S&C/RELEASE/REVIEW verify final DeepFilterNet/Hush package, source archive,
  notice surface, dataset-provenance, local-only runtime proof, and release-zip
  artifact hygiene against the final exact build.
- S&C/RELEASE/REVIEW verify final Emoticon Creator Android/iOS package,
  source archive, dependency/notice evidence, app privacy/store disclosure
  alignment, and rebuilt-device smoke against the final exact build.
- RELEASE PIPELINE/S&C/REVIEW complete the v0.8.0 sound-pack notice freshness
  recheck.
- QA/user rebuilt smoke is recorded for the changed release-risk surfaces,
  including call-room behavior, optional Hush support layer, BG3 DX11 release
  sidecar packaging, native per-panel popouts, accessibility settings/media
  surfaces, and any bug/UI changes that land after this checkpoint.

## Final Candidate Validation Plan

After the final build number is known:

1. Confirm clean or intentionally reviewed app repo source state.
2. Confirm `intergalactic/pubspec.yaml` reports the final `0.8.0+build`.
3. Run release identity verification for the final build.
4. Build/package desktop and Android release artifacts through the configured
   local release path.
5. Preserve iOS/TestFlight upload proof in IOS handoff records.
6. Generate and validate checksums, source archive, changelog extract,
   feature notes, and update manifest.
7. Confirm desktop unsigned-consent or signing path:
   `auto_update=true` and `allow_unsigned_auto_update=true` when using the
   open-source unsigned updater path.
8. Confirm rollback-proof archive for the previous live version exists before
   any live publish.
9. Run artifact hygiene/security review on the final artifact set.
10. Run desktop auto-update smoke, Android APK install/update smoke, and
    iOS/TestFlight smoke appropriate to the final release route.

## Publication Boundary

Do not publish the website/server artifact set, publish `latest.json`, upload
to TestFlight/App Store Connect, or move/archive build artifacts as part of
this preliminary pass.

## 2026-07-06 REVIEW Rebuild Gate Closeout

REVIEW completed the post-branch-sync rebuild gates requested before handing
the release back to Release Pipeline.

Public validation summary:

- The candidate identity remained `v0.8.0+992`.
- Desktop and Android were rebuilt through the configured local build paths
  without bumping the build number.
- The desktop package-hygiene check passed for generated-runtime diagnostics.
- The Steam activity proxy was confirmed to use the local environment URL
  configuration rather than a bundled Steam API key.
- Android Gradle/Maven, FCM, and OSS license evidence was refreshed under:
  - `docs/release/evidence/android-gradle/0.8.0+992`
  - `docs/release/evidence/android-fcm/0.8.0+992`
  - `docs/release/evidence/android-oss-licenses/0.8.0+992`
- The source/security review gate passed from the app repo, and owner-local
  Android signing, Google Services, Firebase options, and stream-test env
  inputs remained ignored by repository rules.
- No live publish, upload, `release.bat` dry run, archive/delete, or
  website-mirror copy occurred during this REVIEW pass.

Remaining Release Pipeline gates:

- Confirm the accepted frozen source state for the exact release candidate.
- Re-run exact-candidate `release.bat` packaging after source/archive alignment
  is confirmed if any source or artifact inputs change.
- Replace the generated placeholder public changelog before live publish.
- Confirm rollback proof, unsigned updater/signing stance, desktop updater
  smoke, Android APK smoke, and iOS/TestFlight handoff evidence.

## 2026-07-07 Release Dry-Run Packaging Gate

Release Pipeline ran the next release stage as a dry run only. This generated
local release artifacts and metadata, but skipped the public website copy and
did not publish the update manifest.

Validation passed:

- Release identity verification passed for `v0.8.0+992`.
- The local update manifest strict-parsed as UTF-8 JSON with no BOM.
- The checksum manifest strict-decoded as UTF-8 text with no BOM and parsed the
  expected SHA-256 entries.
- Local checksum entries matched the installer, Android APK, and source
  archive.
- Read-only public metadata verification passed against the local dry-run
  manifest.
- Source archive and Windows desktop release zip opened successfully, with no
  forbidden secret/key filename matches in the inspected zip entries.
- Filename/manifest-level package hygiene passed against the Windows release
  payload and desktop zip. This gate covered UTF-8/BOM parsing, checksum
  matching, and zip-entry name scans only; it did not include content-level
  secret scanning of the packaged files.
- The source/security review gate passed from the app repo.

Signing and updater status:

- The accepted desktop updater trust path remains HTTPS plus SHA-256
  verification plus explicit unsigned or untrusted Windows consent.
- Release Pipeline must confirm the exact signing route again during the final
  package pass.

Live-release blockers:

- Source/archive alignment is not final. The generated source archive must not
  be treated as matching the binaries until REVIEW provides a clean/frozen
  release ref or commits the intended delta.
- The generated public changelog is not release-ready and must be replaced
  before live publish.
- Rollback proof was only previewed; the dry-run did not create a rollback
  archive.
- Final desktop updater smoke, Android APK smoke, and IOS/TestFlight handoff
  confirmation still need exact-candidate evidence before live publish.

## 2026-07-07 Live Desktop And Android Publish

Release Pipeline completed the authorized live desktop plus Android publish for
`v0.8.0+992`.

Source and command:

- User confirmed GitHub was synced, packages were refreshed, the dry run had
  completed, and local `main` matched `origin/main`.
- App repo source identity before publish:
  `57a956908acef70a7447b636acf6d8268748c6ff`.
- App identity: `0.8.0+992`.
- Command: `release.bat --include-android`.
- Successful log: `release-logs/release-20260707-131914.log`.

Artifacts published to the local website mirror:

- Windows installer:
  `<website-mirror>/intergalactic/downloads/InterGalactic-Setup-0.8.0+992.exe`
  SHA-256
  `22C333635FA89A575D392CF141998EBF0060A50774952AEB9137989D94F5EFA9`.
- Android APK:
  `<website-mirror>/intergalactic/downloads/InterGalactic-0.8.0+992.apk`
  SHA-256
  `B52171C728E3BBD11877AC42A6C72B688769B0E08D1C19E33097317937BD2C0A`.
- Source archive:
  `<website-mirror>/intergalactic/source/intergalactic-0.8.0+992-source.zip`
  SHA-256
  `20A03923981519218CF67E8B68788AE5363ADD70A1871C31DBD733FF61F201FF`.
- Checksums:
  `<website-mirror>/intergalactic/downloads/checksums-0.8.0+992.txt`.
- Changelog:
  `<website-mirror>/intergalactic/updates/changelog/v0.8.0.md`.
- Feature notes:
  `<website-mirror>/intergalactic/updates/features/v0.8.0+992.md`.
- Update manifest:
  `<website-mirror>/intergalactic/updates/latest.json`.

Rollback proof:

- Previous live mirror version archived: `v0.7.4+985`.
- Archive directory:
  `<release-archive>/release-rollback/v0.8.0/previous-v0.7.4+985-20260707-132305`.
- Archive zip:
  `<release-archive>/release-rollback/v0.8.0/previous-v0.7.4+985-20260707-132305.zip`.
- Archive zip SHA-256:
  `1F7FC0773D28A6974158C4BB7FBD618363BE1B1E4AB3D4A7E834343E9DEE7D62`.
- `rollback-proof.json` validates the archived previous `latest.json`,
  checksum file, Windows installer, Android APK, source archive, and changelog
  hashes.

Validation completed:

- Local and mirror `latest.json` strict-parse as UTF-8 JSON with no BOM.
- Local and mirror manifest identity is `v0.8.0+992`, `version_name` `0.8.0`,
  and build number `992`.
- Mirror checksum file strict-decodes as UTF-8 with no BOM, parses three
  SHA-256 entries, and matches installer, APK, and source archive.
- Changelog extraction now publishes the public `v0.8.0` release notes instead
  of the placeholder fallback.
- `tools/quality/Assert-ReleasePackageClean.ps1` passed against the Windows
  release payload and desktop zip.
- `.github/scripts/security-review.py --repo-root . --artifact-root dist`
  passed from the app repo.
- Authenticode status for the app executable and installer remains
  `UnknownError` because the local signing chain terminates at an untrusted
  root. This is the accepted HTTPS plus SHA-256 plus explicit
  unsigned/untrusted consent path; `latest.json` keeps
  `allow_unsigned_auto_update: true`.
- Final package/model evidence for DeepFilterNet/Hush closed the release-side
  queue gates: `df.dll`,
  `DeepFilterNet3_onnx.tar.gz`, and
  `advanced_dfnet16k_model_best_onnx.tar.gz` match recorded hashes, and the
  package/zip scans found no Hush demo WAVs, Weya binaries, LFS metadata, or
  nested model repo metadata beyond app asset `.gitkeep` placeholders.

Remaining external verification:

- Public endpoint verification from this Windows host failed before HTTP status
  because both the helper's .NET HTTP client and `curl.exe` hit local SChannel
  credential errors. Verify the public `app.ourgalaxy.space` URLs from another
  approved environment after Syncthing/public sync.
- IOS/user still owns App Store Connect/TestFlight upload and processing proof.

## 2026-07-14 Supplemental Desktop Native Source Proof

S&C approved the corrected supplemental desktop-native notice and component
receipt. REVIEW then compared the released source archive to public tag
`v0.8.0+992` at commit
`3b8ac7ad0414701da4fc53f5656d34b937caf764`.

- Source archive SHA-256:
  `20A03923981519218CF67E8B68788AE5363ADD70A1871C31DBD733FF61F201FF`.
- All 2,142 public-tag files are present: 290 match byte-for-byte and 1,852
  match after deterministic CRLF normalization. No source-content mismatch or
  missing public-tag file remains.
- The archive has seven inventoried historical public release artifacts under
  `dist/`, making it a complete source-content superset rather than a
  byte-identical tag export.
- The public app, WebRTC Core commit
  `6084687728c2adc049908e353a679f7d91c0d3d5`, and libwebrtc wrapper commit
  `1f70ae1d5b063c51a531fe94eef6ae20d09c6c3e` were reachable with their license
  files. The public LF license contents reproduce the receipt hashes after the
  same deterministic Windows CRLF normalization.
- Machine-readable proof is retained in the Matrix_Dev release evidence at
  `docs/release/evidence/desktop-native-notices/0.8.0+992/source-archive-equivalence.json`.

Remaining gates are user-accessible publication of the supplemental notice and
receipt, plus inclusion and post-package verification of the accepted notice
in the next Windows package. No released installer, source archive,
`latest.json`, or app behavior changed during this proof.
