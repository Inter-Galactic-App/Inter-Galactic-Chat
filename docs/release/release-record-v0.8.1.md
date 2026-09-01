# Inter Galactic v0.8.1 Release Record

Status: RELEASED 2026-08-22. Windows and Android are publicly distributed as
`0.8.1+1004`; iOS went to TestFlight. Installer, update, publication, rollback
archive, and served-bytes validation are complete.
Release owner: RELEASE PIPELINE
Release scope: Windows desktop primary; Android direct APK and iPhone/TestFlight
remain separate platform lanes. macOS and Linux are not public release targets.

**Candidate identity.** The sections below marked `+1003` were measured on
`0.8.1+1003`, built from app `main` `b40b2da2781a515248a82ddb7914021f32fdb73c`.
**They remain historical and did not carry forward.** The release that shipped
is `0.8.1+1004`, measured on its own artefacts and recorded in the ledger
below. Superseded 2026-08-22: this paragraph previously stated that no
candidate had been built or measured at `+1004`, which stopped being true
before publication and is retained here only so the change is visible.

## Candidate Build Ledger

| Build | Source | State | Exact-artifact evidence |
| --- | --- | --- | --- |
| `0.8.1+1003` | app `main` `b40b2da2781a515248a82ddb7914021f32fdb73c` | Non-public Windows candidate built | `build.bat --no-bump --noninteractive` completed with a succeeded result record. Provenance, 43-file native inventory, packaged-notice, package-clean, and 11-entry ZIP-parity gates passed. Installer, source archive, checksums, `latest.json`, rollback proof, and fresh candidate UI/update smoke remain pending. |
| `0.8.1+1004` (Windows) | app `main` `18e425e9932e676e54f6d69e491f37cc7e6b973a` (clean recut) | **RELEASED 2026-08-22** | Served installer `InterGalactic-Setup-0.8.1+1004.exe`, 78,546,112 B, sha256 `3CFBAA29B5E7EFE93CF01E4C66D0CB311D889964EE05FF12D35EB9430110D72A`. Shipped `libwebrtc.dll` sha256 `ED53C3D4ADA4F442658465F487CCC091A858C0A541812D489CC3839992D0BE42`. Public source tag `v0.8.1+1004` peels to `e4da440b`; source archive `intergalactic-0.8.1+1004-desktop-source.zip`, 98,375,817 B, sha256 `EEC57391977B27046ACB360E2A662A31CBEC9BF4EF997013063CA0E16609A810`. |
| `0.8.1+1004` (Android) | app `3b1ca7065d3077c0b82415d5f0472bcd435e075b` | **RELEASED 2026-08-22** | Served APK `InterGalactic-0.8.1+1004.apk`, 193,436,090 B, sha256 `F93ABB58CA9AC264EEF53EBC1E2113F6986187711B6EC66687FDA58ED67BCC49`. APK Signature Scheme v2 verified; signer cert matches the retained `v0.8.0+993` package, so in-place upgrade is compatible. All 30 native payload paths map and hash-match. Owner-operated external-device update and smoke passed. |

The `+1003` row records no public artifact, `latest.json` change, source
archive, or release tag; it was never published. The two `+1004` rows are the
released builds.

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

Full provenance, URLs, and verification history remain in the
[`SOURCE_OFFER.md` component routes](../policies/SOURCE_OFFER.md#component-routes).
This is a source-availability boundary, not a claim that the historical Windows
build can be reproduced end to end: its exact build definition remains
unrecovered and its transitive dependencies remain unenumerated. Do not use the
older assembled-bundle manifest as current source-availability evidence.
