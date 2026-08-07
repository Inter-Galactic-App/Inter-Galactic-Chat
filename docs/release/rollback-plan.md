# Inter Galactic Rollback Plan

Maintainer note: this plan references workspace-level deployment mirrors and
release helpers that are not part of a standard public clone. See
`docs/release/README.md` for the release-documentation boundary.

## Purpose

This plan protects users from broken desktop/mobile releases by keeping the
previous known-good assets, manifest, and notes recoverable. Rollback means
restoring the published update/download metadata to a known-good state; it does
not replace normal bug-fix development.

## Rollback Principles

- Roll back metadata first when users are being directed to a bad build.
- Keep old artifacts immutable. Do not overwrite version-stamped installers,
  APKs, source zips, or checksum files.
- Publish `latest.json` last during forward release and first during rollback.
- Do not delete the bad artifact until the incident is understood; users or
  logs may need the exact file for diagnosis.
- Prefer a new hotfix build when users already installed the bad version and
  need an in-app update path forward.

## Rollback Inventory

Before every release, capture the currently live values:

- Live manifest:
  `https://app.ourgalaxy.space/updates/latest.json`
- Previous `version`, `version_name`, `build_number`, and `build_date_ms`.
- Previous Windows installer URL.
- Previous Android APK URL when Android was shipped.
- Previous checksum URL and contents.
- Previous source archive URL.
- Previous changelog/notes URL.
- Local copy from the maintainer website mirror, if available.
- Local generated copy under `dist\updates\latest.json` if it matches the live
  version.
- For local maintainer releases, the live publish flow must archive the
  currently live mirror manifest and every manifest-referenced rollback file
  before copying new release files. The proof must include a machine-readable
  `rollback-proof.json`, a zip archive, and a SHA-256 sidecar.

## Rollback Triggers

Rollback is warranted when the released build causes:

- startup crash
- login failure
- session restore failure
- encrypted-room decrypt failure after update
- updater loop or manifest parse failure
- unexpected Windows signature failure or an unreviewed unsigned installer
  published without the required updater approval path
- installer/APK URL mismatch
- destructive data migration
- severe Android notification/push regression in a pushed Android release
- App Store/TestFlight build rejection that must stop external testing

## Manifest Rollback

Use this when the bad build has been published but a previous good build should
be restored as the offered download/update.

1. Fetch and archive the bad live manifest for incident records.
2. Restore the previous known-good `latest.json`.
3. Confirm all URLs inside the restored manifest still return HTTP 200.
4. Confirm checksums in the restored checksum file match the restored artifacts.
5. Upload the restored manifest to `/updates/latest.json`.
6. Confirm the public download page now resolves the restored version.
7. Launch a previous client and confirm it no longer offers the bad build.
8. Add a changelog/incident note describing the rollback and user impact.

## Rollback Proof Archive

Before publishing a new manifest, create or confirm a rollback-proof archive
for the previous live version. The archive must contain:

- `updates/latest.json` from the previous live mirror.
- Manifest-referenced installer/APK/source/checksum/changelog/feature-note
  files.
- `rollback-proof.json` with release candidate, previous manifest version,
  file list, hashes, and checksum validation results.
- A zipped copy of the proof folder plus a `.sha256.txt` sidecar.

The publish flow must fail before mirror copy begins if required previous
files are missing or checksum entries do not match the current mirror files.

## Windows Rollback

Windows rollback is mostly manifest-driven because artifacts are versioned.

- Restore `latest.json` to the previous known-good Windows installer URL.
- Keep the bad installer in `downloads/` until the incident review decides
  whether to remove it.
- If a downloaded bad installer has a signing or install-time failure, publish
  an incident note warning users not to install that exact version.
- If users already installed the bad build and the app can still check updates,
  ship a new higher `X.Y.Z+build` hotfix rather than lowering the manifest to an
  older build only.
- If users already installed the bad build and update checks are broken, provide
  direct manual reinstall instructions on the download page.

## Android Rollback

Android public APK rollback is also metadata-driven for direct downloads.

- Restore `latest.json` to omit Android or point Android at the previous
  known-good APK.
- Verify the APK signature lineage is compatible with installed clients before
  recommending downgrade/reinstall.
- If the bad APK changed notification transport mode, confirm whether old
  pushers or tokens need in-app cleanup in the hotfix.
- For Play Store distribution, use Play Console staged rollout controls first:
  pause rollout, halt expansion, or supersede with a fixed build. Play Store
  version codes cannot be decreased for a new production artifact.

## iOS Rollback

iOS rollback depends on distribution channel.

- TestFlight: stop testing for the bad build or expire the build in App Store
  Connect, then promote a previous good build if Apple still allows it for the
  tester group.
- App Store: use phased release controls to pause rollout when available.
  Submit a fixed build with a higher build number for users who already updated.
- Direct/ad-hoc IPA: remove the bad download link and republish the previous
  known-good IPA link if the provisioning profile still permits install.
- Always verify the Broadcast Extension build/version/capabilities alongside
  the main app before re-promoting an iOS build.

## Web Rollback

Web rollback uses the selected web deployment target.

- Restore the previous web bundle on the server or redeploy a previous good
  commit.
- Confirm service worker/cache behavior does not keep serving the bad assets.
- Confirm login/session restore in a fresh browser profile and an existing
  profile.
- Keep the app/download update manifest separate from the web bundle rollback
  unless the manifest itself is the issue.

## Hotfix Forward Plan

Use this when users may have installed the bad release.

1. Fix the blocking issue in a scoped branch.
2. Bump build metadata at minimum so `VERSION_TAG` increases.
3. Build and sign artifacts through the normal checklist.
4. Generate a fresh manifest with the higher version.
5. Validate that the bad build detects the hotfix as newer.
6. Publish assets, then publish `latest.json` last.
7. Leave release notes that identify the fixed regression and upgrade risk.

## Incident Notes Template

```markdown
## Release Rollback: vX.Y.Z+build

- Date/time:
- Released version:
- Rolled back to:
- Trigger:
- Affected platforms:
- User impact:
- Action taken:
- Verification:
- Follow-up fix:
- Remaining risk:
```
