# WebRTC Fork Rebuild Kit

How to reconstruct the patched `libwebrtc.dll` that Inter Galactic's Windows
desktop build links against.

## Why this exists

The Windows build requires a **patched** libwebrtc (hardware H264 encoding,
Media Foundation encoder path, game capture, WGC/GDI desktop capture, audio
pipeline changes). Stock `flutter_webrtc` will not do.

Those patches live in two forked git trees under `webrtc-build/`, which is a
~23 GB `gclient` checkout in a workspace that **is not a git repository**. The
tree itself is disposable and reproducible — but the patches are not. Both
patch sets are therefore backed up off-drive, and everything needed to rebuild
is pinned here.

Do not treat the workspace copy as the source of truth.

## Source of truth

Each forked tree lives in two places. **Use the public mirror** — it is the
canonical, reachable source. An internal mirror also exists for operational
backup; its access details are in the internal workspace docs, not here.

| Tree | Public mirror (use this) | Branch |
| --- | --- | --- |
| `webrtc-build/src` (WebRTC core) | https://github.com/Inter-Galactic-App/webrtc-core | `intergalactic/windows-streaming-m137` |
| `webrtc-build/src/libwebrtc` (C++ wrapper) | https://github.com/Inter-Galactic-App/libwebrtc | `intergalactic/windows-hardware-h264` |

What each carries:

- **WebRTC core** — desktop capture (WGC/GDI), video encoder/broadcaster/cadence/
  decoder, audio state and voice engine, PeerConnection factory, `BUILD.gn`.
- **libwebrtc wrapper** — hardware H264 encoder factory, Media Foundation encoder
  path, desktop capture scaler API, native stream diagnostics.

The internal mirror remains the primary push target and the operational backup.
It carries the same commit SHAs as the public mirrors, so the pinned-commit table
below is valid against either — a commit SHA is the same object wherever it is
hosted, which is why nothing here depends on knowing where the internal copy
lives.

The reproducibility anchor for the base is the **commit SHA**
`a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd` — a SHA is content-addressed and
immutable, so it identifies exactly one tree no matter where it is hosted.
`m137_release` is a moving branch and cannot serve that purpose.

The core mirror also carries the tag **`upstream-base-m137-a4bd28d9`** pointing at
that SHA. The tag is a convenience name, not the guarantee — its real job is to
keep the object *reachable in our mirrors*, so that if upstream ever force-pushes
or garbage-collects `m137_release`, the base commit is still fetchable from us
instead of only from upstream.

### Pinned commits — selected 0.8.2+1008 native component

**This block is release-scoped and moves; the rest of this document does not.**
Branch names are mutable. These are the exact patch tips the candidate build
uses and that its matching distributed build must use — check these out, not
the branch names, when you want a reproducible tree:

| Tree | Commit |
| --- | --- |
| WebRTC core | `c6bf02fe64a993fa9d34d44957db71615ec98ddd` |
| libwebrtc wrapper | `c8619a6d98d49939b6affe642a037d9f5a6ed9d5` |
| upstream WebRTC base | `a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd` |
| host `depot_tools` | `0948b46c2396eb38ff61722815af0c218a159f04` |

This pair identifies the selected 20,738,560-byte DLL with SHA-256
`2899E370BC49BA746FB61E3E610CC473B945738EF87C67BBC311552F5810C209`.
The historical public Windows 0.8.1+1004 used the same core but wrapper
`cdd3c9a98e93f911a67489ecaa3968b730baf8a4`, host depot_tools
`ff41874736c800b2f79aa8cf9596c7919066eb02` and DLL
`ED53C3D4ADA4F442658465F487CCC091A858C0A541812D489CC3839992D0BE42`.
Its versioned release record remains unchanged. Earlier public 0.8.0
records retain their own patch pairs. The selected native component is not
a claim that a new application release has been published.

The two patch commits above are also named by the in-app notice
(`native_licenses.dart`), `SOURCE_OFFER.md` and `THIRD_PARTY_LICENSES.json`.
`intergalactic/test/config/webrtc_notice_provenance_test.dart` compares them and
is red at any commit where they disagree, so a partial update cannot survive as
a green state.

**That is an agreement check, not an atomicity check.** It does not read the
queue row, and it cannot tell four surfaces updated in one commit from four
updated across four. *"All four in the same change, or none"* is a separate
release-process rule and is held by the *"first public 0.8.1 release"* row in
the maintainer release tracker, not by an automated gate.

The upstream base in the same table is checked against
`pinned-dependency-revisions.json` beside this file, which is what actually pins
the tree — the base and the patch tips have to describe one coherent checkout,
or step 3 and step 4 below contradict each other.

**The sidecar manifest is not a confirmation of this table.** A built zip's
`libwebrtc.zip.manifest.json` records the inputs of *that zip*, so it ties one
particular `libwebrtc.dll` back to its own sources. A workspace that has already
built ahead of the distributed line carries the newer pair there, by design. This
table records the selected 0.8.2+1008 native component; historical release records
cover the earlier public releases. The manifest tracks what is on the disk in
front of you. Reading either as evidence for the other is how a source pointer
ends up describing a binary nobody has.

## Pinned inputs

- `gclient` — the gclient solution. Upstream is
  `https://github.com/webrtc-sdk/webrtc.git@m137_release`.
- `pinned-dependency-revisions.json` — the exact revision of `src` and all 42
  dependencies at the last good sync. **`m137_release` is a moving branch**, so
  these revisions, not the branch name, are what actually pin the tree. The
  authoritative upstream `src` revision is
  `a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd`.
- `args.gn` — the release build args.

`DEPS` is deliberately not vendored: it is unmodified from upstream and is
recovered by syncing to the pinned `src` revision.

## Rebuild procedure

   Every step below is safe to re-run.

1. Ensure `depot_tools` is on `PATH` (workspace has it at `depot_tools/`).
   `depot_tools` auto-updates itself, so to reconstruct the recorded inputs pin it
   to the revision this build used and stop it from rolling forward:

       cd depot_tools
       git checkout 0948b46c2396eb38ff61722815af0c218a159f04
       set DEPOT_TOOLS_UPDATE=0
       set DEPOT_TOOLS_WIN_TOOLCHAIN=0

   The selected build used local Visual Studio 2022 BuildTools 14.44.35207,
   GN 2233 (85cc21e94af5), Ninja 1.13.2 and Chromium clang-cl/LLD 21.0.0git
   at LLVM `09006611151c7f85862a9da8da34872c456c2c37`. Matching inputs is
   not a demonstrated byte-identical rebuild; measure the resulting DLL.

2. Create the checkout root and gclient config:

       mkdir webrtc-build && cd webrtc-build
       copy <this dir>/gclient .gclient

3. Sync to the pinned revision (not just the branch):

       gclient sync --revision src@a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd

   If a dependency drifts, force the exact set from
   `pinned-dependency-revisions.json`.

4. Restore the WebRTC core patches. Check out the pinned **commit**, not the
   branch — the branch tip moves as work continues:

       cd src
       git remote set-url core https://github.com/Inter-Galactic-App/webrtc-core.git 2>nul || git remote add core https://github.com/Inter-Galactic-App/webrtc-core.git
       git fetch core intergalactic/windows-streaming-m137 --tags
       git checkout c6bf02fe64a993fa9d34d44957db71615ec98ddd

   That commit already sits on the pinned upstream base, so if step 3 drifted you
   do not need to trust `m137_release` at all — the tag
   `upstream-base-m137-a4bd28d9` fetched above is the authoritative base.

   To continue development rather than reproduce, check out the branch instead.

5. Restore the libwebrtc wrapper patches, same rule:

       cd src/libwebrtc
       git remote set-url wrapper https://github.com/Inter-Galactic-App/libwebrtc.git 2>nul || git remote add wrapper https://github.com/Inter-Galactic-App/libwebrtc.git
       git fetch wrapper intergalactic/windows-hardware-h264
       git checkout c8619a6d98d49939b6affe642a037d9f5a6ed9d5

6. Build:

       cd webrtc-build/src
       copy <this dir>/args.gn out-release/Windows-x64/args.gn
       gn gen out-release/Windows-x64
       ninja -C out-release/Windows-x64 libwebrtc

   Outputs `out-release/Windows-x64/libwebrtc.dll` and `libwebrtc.dll.lib`.

7. Package as `libwebrtc.zip` with this layout. `Test-LibwebrtcZip` in
   `install_patched_libwebrtc.ps1` rejects the archive if any of these are
   missing, so build the package from exactly this list:

       libwebrtc/include/libwebrtc.h
       libwebrtc/include/rtc_desktop_capturer.h
       libwebrtc/include/rtc_video_device.h
       libwebrtc/include/rtc_video_frame.h
       libwebrtc/lib/win64/libwebrtc.dll
       libwebrtc/lib/win64/libwebrtc.dll.lib

   The guard also greps the headers for the Inter Galactic API markers
   (`StartWithMaxFrameSize`, `SetWindowsCaptureBackendMode`, `CreateGameCapture`,
   the receiver frame-id accessor, and so on), so a stock upstream build packaged
   into this layout will still be rejected - by design.

8. Stage the new ZIP and matching sidecar in a versioned candidate location.
   Preserve the historical canonical ZIP. The canonical default remains
   `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`. `build.bat` finds it there
   by default; `--libwebrtc-zip` or `INTERGALACTIC_LIBWEBRTC_ZIP` override.

## Artifact provenance

Each built ZIP carries a matching sidecar named `<zip-path>.manifest.json`,
recording its SHA-256 plus the wrapper commit, the WebRTC core commit, the
upstream synced revision, and the `args.gn` used.

### Regenerating it

Whenever a candidate ZIP is rebuilt, refresh its matching sidecar in the
versioned candidate location from step 8. Do not overwrite the historical
canonical ZIP or its sidecar. A stale hash is reported as a mismatch and fails
the build:

```powershell
$zip = '<versioned-candidate-directory>\libwebrtc.zip'
$m   = Get-Content -Raw "$zip.manifest.json" | ConvertFrom-Json
$m.artifact.sha256 = (Get-FileHash -Algorithm SHA256 $zip).Hash
$m.artifact.bytes  = (Get-Item $zip).Length
$m.artifact.builtUtc = (Get-Item $zip).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$m.provenance.webrtcCore.commit       = git -C <webrtc-core-root> rev-parse HEAD
$m.provenance.libwebrtcWrapper.commit = git -C <webrtc-wrapper-root> rev-parse HEAD
$m | ConvertTo-Json -Depth 10 | Set-Content "$zip.manifest.json"
```

Then confirm the installer accepts that explicit candidate before building.
This installs it into the selected build checkout; use the same candidate path
for `--libwebrtc-zip` or `INTERGALACTIC_LIBWEBRTC_ZIP` when starting the build:

```powershell
powershell -File intergalactic\scripts\install_patched_libwebrtc.ps1 `
  -WorkspaceRoot <repo-root> -AppDir <build-checkout>\intergalactic `
  -Mode require -ZipPath $zip
```

It prints the provenance banner on success and throws on a hash mismatch, a
manifest with no `artifact.sha256`, or a structurally invalid zip.

### What this does and does not prove

The manifest is an **integrity check on a local build input, not a supply-chain
signature.** It detects *drift*: a zip rebuilt without regenerating the manifest,
a stale hash, a truncated or corrupted archive, or the wrong artifact dropped
into the artifacts directory.

**Matching records does not prove source-to-binary correspondence.** The
release pipeline separately opens the packaged DLL and compares its bytes
with the selected native ZIP and inventory digest. The measured package
receipt for app commit `2973eae254d090214d7c6254dd6eb8ae7054d65a` is recorded
in `docs/release/evidence/license-sources/libwebrtc-windows/0.8.2+1008.md`.
That receipt cannot establish package contents for a later application commit.
Rebuild inputs, package byte identity and recipient source availability are
separate checks; none is a byte-reproducibility or publication guarantee.

**Scope: this zip is a build input and is not conveyed.**
`install_patched_libwebrtc.ps1` consumes it at build time; there is no
publication step for it, and nothing here describes a distributed build. The
`libwebrtc.dll` inside it *is* conveyed, inside the Windows application payload
— controls over that payload belong to the release pipeline, not to this
rebuild kit, and are not documented here.

Within that scope, it cannot *authenticate* the artifact. The manifest sits next to the zip, so
anyone able to replace the zip can replace the manifest with it. Treating this as
tamper-proof would be a mistake. If this zip were ever published, or built somewhere
untrusted, the manifest would not be enough on its own — but that is a
different procedure from the one documented here and would need writing before
it applied. The checked-in table under "Pinned commits" is the durable half of
provenance today, because it lives in a git history that the artifacts directory
does not.
