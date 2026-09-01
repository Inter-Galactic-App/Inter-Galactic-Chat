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

### Pinned commits — the 0.8.1+1004 candidate

**This block is release-scoped and moves; the rest of this document does not.**
Branch names are mutable. These are the exact patch tips the candidate build
uses and that its matching distributed build must use — check these out, not
the branch names, when you want a reproducible tree:

| Tree | Commit |
| --- | --- |
| WebRTC core | `c6bf02fe64a993fa9d34d44957db71615ec98ddd` |
| libwebrtc wrapper | `cdd3c9a98e93f911a67489ecaa3968b730baf8a4` |
| upstream WebRTC base | `a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd` |
| host `depot_tools` | `ff41874736c800b2f79aa8cf9596c7919066eb02` |

The Windows 0.8.1+1004 candidate uses this different patch pair. Earlier
public 0.8.0 releases used the separately recorded `608468...` / `1f70ae...`
pair. Reproducing 0.8.1 from the older table would produce the wrong DLL, so
this candidate-scoped table moves with the four recorded source-pointer
surfaces and remains a candidate record until its matching release is
published.

The two patch commits above are also named by the in-app notice
(`native_licenses.dart`), `SOURCE_OFFER.md` and `THIRD_PARTY_LICENSES.json`.
`intergalactic/test/config/webrtc_notice_provenance_test.dart` compares them and
is red at any commit where they disagree, so a partial update cannot survive as
a green state.

**That is an agreement check, not an atomicity check.** It does not read the
queue row, and it cannot tell four surfaces updated in one commit from four
updated across four. *"All four in the same change, or none"* is a separate
release-process rule and is held by the *"first public 0.8.1 release"* row in
`docs/agent-control/integration-queue.json`, not by any gate.

The upstream base in the same table is checked against
`pinned-dependency-revisions.json` beside this file, which is what actually pins
the tree — the base and the patch tips have to describe one coherent checkout,
or step 3 and step 4 below contradict each other.

**The sidecar manifest is not a confirmation of this table.** A built zip's
`libwebrtc.zip.manifest.json` records the inputs of *that zip*, so it ties one
particular `libwebrtc.dll` back to its own sources. A workspace that has already
built ahead of the distributed line carries the newer pair there, by design. This
table records the 0.8.1+1004 candidate; the separately recorded 0.8.0 tables
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
   `depot_tools` auto-updates itself, so for a byte-reproducible rebuild pin it
   to the revision this build used and stop it from rolling forward:

       cd depot_tools
       git checkout ff41874736c800b2f79aa8cf9596c7919066eb02
       set DEPOT_TOOLS_UPDATE=0

   A newer `depot_tools` will usually work; pin it only when you are trying to
   reproduce this exact artifact.

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
       git checkout cdd3c9a98e93f911a67489ecaa3968b730baf8a4

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

8. Drop it at
   `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip` and refresh the
   sidecar `libwebrtc.zip.manifest.json` (see below). `build.bat` finds it there
   by default; `--libwebrtc-zip` or `INTERGALACTIC_LIBWEBRTC_ZIP` override.

## Artifact provenance

Each built zip carries a sidecar manifest,
`artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip.manifest.json`,
recording its SHA-256 plus the wrapper commit, the WebRTC core commit, the
upstream synced revision, and the `args.gn` used.

### Regenerating it

Whenever the zip is rebuilt, refresh the manifest — a stale hash is reported as a
mismatch and fails the build:

```powershell
$zip = '<path to libwebrtc.zip>'
$webRtcRoot = '<path to webrtc-build/src>'
$wrapperRoot = '<path to webrtc-build/src/libwebrtc>'
$m   = Get-Content -Raw "$zip.manifest.json" | ConvertFrom-Json
$m.artifact.sha256 = (Get-FileHash -Algorithm SHA256 $zip).Hash
$m.artifact.bytes  = (Get-Item $zip).Length
$m.artifact.builtUtc = (Get-Item $zip).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$m.provenance.webrtcCore.commit       = git -C $webRtcRoot rev-parse HEAD
$m.provenance.libwebrtcWrapper.commit = git -C $wrapperRoot rev-parse HEAD
$m | ConvertTo-Json -Depth 10 | Set-Content "$zip.manifest.json"
```

Then confirm the installer accepts it:

```powershell
powershell -File intergalactic\scripts\install_patched_libwebrtc.ps1 `
  -WorkspaceRoot <repo-root> -AppDir <repo-root>\intergalactic -Mode require
```

It prints the provenance banner on success and throws on a hash mismatch, a
manifest with no `artifact.sha256`, or a structurally invalid zip.

### What this does and does not prove

The manifest is an **integrity check on a local build input, not a supply-chain
signature.** It detects *drift*: a zip rebuilt without regenerating the manifest,
a stale hash, a truncated or corrupted archive, or the wrong artifact dropped
into the artifacts directory.

**Nothing here proves the pinned commits built the DLL that shipped.** The
provenance gate compares records against records. Confirming that the packaged
`libwebrtc.dll` is the recorded digest means opening the final Windows payload,
and **no automated check does that today** — do not read the gate's green as
covering it. That confirmation is a manual publication step owned by RELEASE
PIPELINE and carried in `docs/release/LICENSE_RELEASE_CHECKLIST.md`, where it is
an OPEN item blocking the first public 0.8.1 release: all four surfaces move
together, and the packaged DLL is hashed out of the payload and matched against
the digest recorded in `docs/release/THIRD_PARTY_LICENSES.json`.

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
