# Inter Galactic v0.8.1 Release Record

Status: Windows release candidate built and verified locally; final installer,
update, and publication validation remain pending.
Release owner: RELEASE PIPELINE
Release scope: Windows desktop primary; Android direct APK and iPhone/TestFlight
remain separate platform lanes. macOS and Linux are not public release targets.

**Candidate identity.** Every measurement in this record was taken on
`0.8.1+1003`, built from app `main` `b40b2da2781a515248a82ddb7914021f32fdb73c`.
The source tree has since moved to `0.8.1+1004` (`intergalactic/pubspec.yaml`,
bumped at `3b1ca706`), and no candidate has been built or measured at that
build number. Everything below is therefore historical evidence for `+1003`:
it does not carry forward, and none of it closes a gate for the final
candidate, which must be measured on its own artefact.

## Candidate Build Ledger

| Build | Source | State | Exact-artifact evidence |
| --- | --- | --- | --- |
| `0.8.1+1003` | app `main` `b40b2da2781a515248a82ddb7914021f32fdb73c` | Non-public Windows candidate built | `build.bat --no-bump --noninteractive` completed with a succeeded result record. Provenance, 43-file native inventory, packaged-notice, package-clean, and 11-entry ZIP-parity gates passed. Installer, source archive, checksums, `latest.json`, rollback proof, and fresh candidate UI/update smoke remain pending. |

No public artifact, `latest.json` change, source archive, or release tag is
recorded by this entry.

## Windows Candidate Evidence (`0.8.1+1003`, historical)

The non-public package is
`inter-galactic-windows-v0.8.1+1003.zip` (140,660,294 bytes, SHA-256
`5AC7067E0138629555BEC5DD24EC62C22BF56BB5F0B686AFDFF3F00D9A407D71`).
The build provenance stamp resolves the runner's `data/app.so` to
`b40b2da2781a515248a82ddb7914021f32fdb73c`. The 43-file Windows native
inventory, packaged licence notice, and package-clean gates passed against the
fresh runner; the ZIP matched that runner for the executable, `app.so`,
`NOTICES.Z`, Direct3D, WebView2, libwebrtc, libmpv, and the four required
licence assets.

The previous manual About -> Open Source Licenses check covered the Direct3D
and WebView2 entries on a `6954e05` candidate. Those two Windows notice entries
and the WebView2 text asset are unchanged at `b40b2da`, and `NOTICES.Z` has the
same SHA-256, so it remains useful risk-equivalence evidence. It is not a fresh
launch of this candidate; the final Windows package still needs that smoke and
the updater path must be checked against the final installer.

**Gates NOT satisfied by the local candidate, named here so a build cannot pass
its own checklist without them:**

- **Artifact signing.** The local ZIP result is unsigned. The final Inno Setup
  installer must record its Authenticode outcome after the configured release
  signing step: either `Valid`, or the approved HTTPS/SHA-256/explicit-consent
  unsigned-update path.
- **Published checksums.** The libmpv boundary below records a SHA-256 for the
  DLL, but no checksum is recorded for the distributed installer/package
  itself, which is what a recipient can actually verify.
- **Rollback path.** No rollback-proof archive or tested manifest restore has
  been created for this candidate.

- **0.8.1 libwebrtc source pointers.** The checked-in public notice surfaces
  intentionally still describe the distributed 0.8.0 libwebrtc. On the first
  public 0.8.1 release, the source-pair pins must move together in all four
  governed notice, offer, inventory, and rebuild-recipe surfaces. Do not change
  only one surface or publish this pre-trigger candidate as though those
  pointers already matched its DLL.

These are release gates, not accepted defers.

## Windows Release Build Evidence

Recorded here rather than in `.github/workflows/build.yml`, whose comment block
previously carried it: that comment cited a maintainer workstation checkout,
and a machine-local path cannot support a reproducible CI claim.

- **2026-08-15, maintainer workstation**, app `main` `659402d1`, with the
  FFmpeg staging directory present-but-empty - the same state that makes the
  CMake guard inert on CI. `flutter build windows --release` exited 0,
  produced `build\windows\x64\runner\Release\InterGalactic.exe`, and
  `INSTALL.vcxproj` - the target that produced MSB3073 on PR #90 - completed.
  No staged ffmpeg directory appeared in the output.
- **Wall time is a lower bound only.** That was a warm-cache workstation build.
  PR #90's own 506s of Release compilation is the runner figure.

## Windows libmpv Source Boundary

The Windows `libmpv-2.dll` is byte-identical across the retained Windows
payloads measured to date: 29,764,622 bytes, SHA-256
`D5F0694B08C124E785D858D00082F3E3B158DD9138BFC48C0382BF1EB443A5FC`.
The published corresponding-source set for that DLL names these five artifacts:

- `mpv-v0.36.0-403-g652a1dd907-source.tar.gz`
- `ffmpeg-n6.0-source.tar.gz`
- `libfribidi-1.0.13-gb54871c339da-source.tar.gz`
- `libsoxr-0.1.3-source.tar.xz`
- `uchardet-gab1d2f112029-source.tar.gz` under the elected LGPL-2.1-or-later arm

Full provenance, URLs, and verification history remain in
[`SOURCE_OFFER.md`](../policies/SOURCE_OFFER.md#bundled-libmpv--a-third-offer-under-a-third-licence).
This is a source-availability boundary, not a claim that the historical Windows
build can be reproduced end to end: its exact build definition remains
unrecovered and its transitive dependencies remain unenumerated. Do not use the
older assembled-bundle manifest as current source-availability evidence.
