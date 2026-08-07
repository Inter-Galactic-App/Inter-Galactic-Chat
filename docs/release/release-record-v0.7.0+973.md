# Release Record: Inter Galactic v0.7.0+973

Historical record: this file preserves one release run as evidence. Local
workspace paths and mirror details have been removed from the public copy; keep
full maintainer-local evidence outside the public app repo.

Status: dry-run validation complete - release not approved yet
Review date: 2026-05-20
Reviewer: Maintainer review
Release scope: desktop update only
Dry-run log: local workspace log retained outside this repository.
Artifact checklist: `docs/release/release-artifact-checklist.md`

## Release Notes Candidate

Inter Galactic v0.7.0 is a beta desktop release focused on clearer onboarding,
more organized settings, richer link and media previews, safer support
diagnostics, and call/streaming reliability work.

### Windows Beta Caveats

- Windows desktop installers may show expected trust warnings because this dry
  run used a local/self-signed certificate chain. The approval section tracks the
  trusted code-signing decision that must be made before broad publication.
- This was a beta desktop build with possible instability and manual download
  required.
- Automatic Windows updates were disabled for this dry run
  (`windows.auto_update: false`).
- Android APK distribution is a manual-install beta path when included, and
  iPhone beta access is through TestFlight when that channel is open.

Highlights:
- New first-run onboarding introduces the main app areas after sign-in and can
  be replayed later from Help settings.
- Settings now include desktop and mobile search, clearer App/Account/Room/Space
  sections, focused desktop overlays, safer profile drafts, and clearer theme
  reset prompts.
- GIF search can use a configured relay for existing homeserver users, while
  fresh installs without a relay guide users to set up their own relay URL or
  provider key.
- URL previews now warm and reuse recent link previews when switching chats, and
  mobile chat reports picker clearance so emoji, GIF, sticker, and longer
  composer panels are less likely to cover recent messages.
- Windows noise suppression presets, screen-share diagnostics, CPU/resolution
  fallback handling, and source-picker thumbnail loading have been improved.
- Camera toggles in calls have better cleanup when cameras are turned off and
  re-enabled quickly.
- Windows users can opt into the notification companion for approved message
  notifications with preview privacy controls and less duplicate toast noise.
- Android encrypted FCM notifications, mobile/web attachment downloads, offline
  demo mode, and current-version release-note handling received beta fixes, but
  Android was intentionally out of scope for this desktop-only dry run.

Public changelog artifact validated in dry run:
- `dist\updates\changelog\v0.7.0.md`

## Artifact Validation

| Gate | Result | Evidence |
| --- | --- | --- |
| Release identity | Pass | `pubspec.yaml` version is `0.7.0+973`; local release tooling reported `Release identity OK: v0.7.0+973`. |
| Release scope | Pass | Dry run was `desktop update only`; Android upload was skipped even though `InterGalactic-0.7.0+973.apk` exists locally. |
| Installer artifact | Pass with signing caveat | `dist\installer\InterGalactic-Setup-0.7.0+973.exe` exists and matches the checksum file. It is signed/timestamped as `CN=Inter Galactic`, but Windows reports an untrusted root for the local/self-signed certificate chain. |
| Installer input app executable | Pass with signing caveat | `intergalactic\build\windows\x64\runner\Release\InterGalactic.exe` is signed/timestamped with the same certificate chain caveat. |
| Local convenience executable | Warn | The unpacked local executable was unsigned and should be treated as a convenience build, not a published release artifact. |
| Source archive | Pass | `dist\source\intergalactic-0.7.0+973-source.zip` exists, matches the checksum file, and the security gate did not find high-risk secret filenames. |
| Checksums | Pass | `checksums-0.7.0+973.txt` matches computed SHA-256 hashes for the installer and source archive. |
| Update manifest | Pass | `dist\updates\latest.json` advertises `v0.7.0+973`, desktop download URLs, checksum/source/changelog URLs, and `windows.auto_update: false`. No Android platform entry is present for this desktop-only scope. |
| Local web mirror | Pass | The local web mirror manifest matched the generated dist manifest exactly. |
| Firebase desktop spillover | Pass | Windows generated plugin registrant and active `pubspec.yaml` dependencies are clean; Google Services config remains Android-scoped. |
| Local security gate | Pass | `python .github/scripts/security-review.py --repo-root . --artifact-root dist` passed locally. |
| Live v0.7.0 URLs | Pending | Dry run did not upload artifacts; final live URL and checksum verification must run after the real release. |
| GitHub security/dependency checks | Pending | This pass ran the local security gate only. GitHub-side security-review / Dependency Review still need first-release observation when a branch or PR is used. |
| Source freeze | Blocker | The app repo has a dirty worktree with active feature/debug/streaming changes. Rerun build/release validation after the intended release source is frozen. |

## Checksum Record

`dist\checksums\checksums-0.7.0+973.txt`:

```text
SHA256  InterGalactic-Setup-0.7.0+973.exe  946A0D0F2FFF0E84F85BC148854A5E4D739885124EF354228FD6D82D6A363DCB
SHA256  intergalactic-0.7.0+973-source.zip  D036148ACECFF94C47060BBCA8F6DBFA0258BF739288ADBED432EB701243C4FC
```

## Security Gate Notes

Local command:

```powershell
python .github/scripts/security-review.py --repo-root . --artifact-root dist
```

Result: passed.

The gate noted expected Android Google Services client config files and
dependency inventory paths. In current public-source practice, those Firebase
client files are owner-local release inputs and should not be committed.

## Rollback Record

Previous live version: `v0.6.6+929`

Live manifest source:
- `https://app.ourgalaxy.space/updates/latest.json`

Previous live artifact URLs verified with HTTP 200:
- `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.6.6+929.exe`
- `https://app.ourgalaxy.space/downloads/InterGalactic-0.6.6+929.apk`
- `https://app.ourgalaxy.space/source/intergalactic-0.6.6+929-source.zip`
- `https://app.ourgalaxy.space/updates/changelog/v0.6.6.md`

Previous live checksums:

```text
SHA256  InterGalactic-Setup-0.6.6+929.exe  79AF9F6A14D1EB1262E3E60D7668781A36D7E75C5CDC646AD08AAAEF295458D9
SHA256  InterGalactic-0.6.6+929.apk  8596FE5485043309FCB016089AF4065F98327969685680D096BB923A45FBD088
SHA256  intergalactic-0.6.6+929-source.zip  A64643EDC1A0A75034A6DCB7D98283895A9BCBD79228338AA0ED39B369FF6EEB
```

Rollback action:
1. Restore the previous `latest.json` manifest so clients see `v0.6.6+929`
   again.
2. Confirm the previous installer, APK, source archive, changelog, and checksum
   URLs still return HTTP 200.
3. Confirm the published checksum file still matches the previous artifact
   hashes above.
4. Announce the rollback reason and note whether the desktop-only `v0.7.0+973`
   package should be removed from public download pages or left as a manual beta
   artifact.

## Personal Approval Needed

Before approving the real release, the user should decide or complete:
1. Confirm `v0.7.0+973` is intended to be a desktop-only release and Android
   should remain out of the published update manifest for this run.
2. Decide whether the current self-signed `CN=Inter Galactic` code-signing
   chain is acceptable for this beta/public desktop release, or whether release
   should wait for a trusted code-signing certificate.
3. Freeze the intended source set, then rerun the build/release dry run because
   the current app repo is dirty and includes active feature/debug/streaming
   changes.
4. Run the packaged installer smoke test on the build machine: install/launch,
   login/session restore, encrypted-room send/receive, update-check display,
   and any release-critical call/stream/report-a-bug/biometric flows included
   in the frozen source set.
5. After the real upload, verify the live `v0.7.0+973` installer, changelog,
   checksum, source, and latest-manifest URLs return HTTP 200 and match local
   SHA-256 values.
6. Observe GitHub security-review / Dependency Review on the release branch or
   PR if one is used for the final release cut.
