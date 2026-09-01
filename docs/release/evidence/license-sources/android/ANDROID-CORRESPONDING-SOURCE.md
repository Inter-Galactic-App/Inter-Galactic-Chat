# Corresponding Source — the Android media_kit bundle

Prepared by REVIEW, 2026-08-15, on the Windows host.

**PUBLISHED AND VERIFIED.** All three artefacts are live at
`https://app.ourgalaxy.space/source/`, each fetched back over HTTPS and
re-hashed against the staged digest after propagation. The served copy was
hashed, not the staged one.

## Why Android needs its own archives at all

## Which ABIs the obligation actually covers — measured from the APKs

**Every public Android release conveyed an `x86_64` `libmpv.so`, not just the
two ABIs shipping today.** Opened the retained release APKs directly:

| Release | ABIs carrying `libmpv.so` |
| --- | --- |
| `0.7.4+985` — public | arm64-v8a, armeabi-v7a, **x86_64** |
| `0.8.0+992` — public | arm64-v8a, armeabi-v7a, **x86_64** |
| `0.8.0+993` — public | arm64-v8a, armeabi-v7a, **x86_64** |
| `0.8.1+1000` | arm64-v8a, armeabi-v7a, **x86_64** |
| `0.8.1+1001` onward | arm64-v8a, armeabi-v7a |

`android/app/build.gradle`'s release block now sets
`abiFilters 'arm64-v8a', 'armeabi-v7a'`; the cutover falls between `+1000` and
`+1001`. **`x86` has never shipped in any release APK.**

The source published here covers x86_64 as well — it is the same upstream mpv
revision and the same recipe for every ABI, so one archive serves all three.
Recording the span anyway, because a source offer is scoped to what was
*conveyed*, and dropping an ABI does not retract the copies already
distributed.

### The round number was wrong in both directions, which is why it survived

Until 2026-08-15 the in-app notice and `THIRD_PARTY_LICENSES.json` both said
`libmpv.so` ships for **four** ABIs including `x86`. That figure came from
`merged_native_libs`, a **pre-filter build intermediate**, rather than from the
APK.

It named an ABI that has never shipped *and*, by being visibly generous, made
the real three-ABI history invisible — nobody re-derives a number that already
looks conservative. An overstatement is harder to catch than an omission.
Found by opening 48 APKs; the S&C lane surfaced it and REVIEW confirmed the
public-release span independently.

---

Android ships `libmpv.so` per ABI, statically carrying FFmpeg n6.0 — the same
shape as the Windows `libmpv-2.dll` and the Apple frameworks. But it is a
**third distinct build from a third distinct source revision**, and nothing
already published serves it.

| Platform | mpv revision | Already published? |
| --- | --- | --- |
| Windows `libmpv-2.dll` | `652a1dd907…` (v0.36.0-403) | yes |
| Apple frameworks | upstream `0.36.0` tag | yes |
| **Android `libmpv.so`** | **`78d43740f5…` (v0.36.0-549)** | **this record** |

Three artefacts, three revisions. Treating any one as covering another would
offer source that does not correspond to the binary.

## What is published

| Artefact | Bytes | SHA-256 |
| --- | ---: | --- |
| `mpv-g78d43740f5-source.tar.gz` | 3,399,318 | `678889728708141e97d283b2a7ef9953aa3102127a4c2aacefaf1adcb211915d` |
| `mpv-lavc-set-java-vm.patch` | 1,488 | `7184d1b1d52c2877b623fad23ad5cacf0e528311c15f64376fcf68de44602259` |
| `libmpv-android-video-build-gfe8c3ac1a91c-build-definition.tar.gz` | 74,108 | `c278bc8789ebaad45a23afd9588bb77e051714892f7f0367356e1cc6ebfe4c62` |
| `fribidi-1.0.12-g6428d8469e53-source.tar.gz` | 2,110,394 | `7920b7d33f1e3945134745a8c665ca5bc748b9d907b3a03b1a6d481a77c0ae7f` |

Upstream, so a recipient can re-obtain and compare without trusting this
project's server:

- mpv — `https://codeload.github.com/mpv-player/mpv/tar.gz/78d43740f52db817d98bcf24fb30a76ab6fa13ff`
- build definition — `https://codeload.github.com/media-kit/libmpv-android-video-build/tar.gz/fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768`
- the patch — `buildscripts/patches/mpv/mpv_lavc_set_java_vm.patch` inside that
  archive. Republished under a hyphenated name for consistency with its
  neighbours under `/source/`; the content is byte-identical and the digest
  above is what identifies it.

Both archives were **exported by commit SHA, not by tag**, and **fetched twice**
with identical digests. `v1.1.7` resolves to commit
`fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768`. That rule exists because a BtbN tag
was deleted out from under this project's FFmpeg provenance once already —
`docs/DECISIONS.md`, *"Record A Third-Party Binary's Builder Commit SHA At
Staging Time"*.

## Verification performed

- Archive root is `mpv-78d43740f52db817d98bcf24fb30a76ab6fa13ff/`, so the export
  is of the pinned commit rather than a tag that could later move.
- The tree's own `Copyright` confirms the licence posture this project relies
  on: mpv is *"GPL version 2 or later … by default, or the GNU Lesser General
  Public License … if built with the `-Dgpl=false` configure switch."* The
  shipped `libmpv.so` reports `-Dgpl=false`, so LGPL-2.1 applies.
- All three fetched from `/source/` after propagation: **3/3 HTTP 200, 3/3
  digests match.**
- **Negative control**: the same mpv filename with one character changed in the
  revision (`…740f5` → `…740f6`) returns **404**, so the host is not
  prefix-matching and the three 200s mean something.

## FFmpeg needs nothing further, and that is measured

The Android recipe fetches upstream FFmpeg `n6.0` — the archive already
published as `ffmpeg-n6.0-source.tar.gz`. It applies exactly two patches in the
`default` flavour, and **both are byte-identical to patches already published
for iOS**, compared by digest rather than matched by filename:

| Android recipe path | Digest matches published |
| --- | --- |
| `buildscripts/patches/ffmpeg/dash_base_url_escape.patch` | `ffmpeg-fix-dash-base-url-escape.patch` |
| `buildscripts/patches/ffmpeg/hls_mp4_seek.patch` | `ffmpeg-fix-hls-mp4-seek.patch` |

## The patch set is flavour-scoped — read this before adding any

The recipe carries **two** patch directories, and only one applies here:

- `buildscripts/patches/` — the **`default`** flavour. FFmpeg gets the two
  above; mpv gets `mpv_lavc_set_java_vm.patch`. **This is what ships**: the
  downloaded jars are literally named `default-<abi>.jar`.
- `buildscripts/patches-encoders-gpl/` — the **`encoders-gpl`** flavour, which
  additionally patches `libx264` (`fix_x86_asm.patch`) and mpv
  (`depend_on_fftools_ffi.patch`). **Not shipped.** Publishing those as applied
  would describe a binary that was never built, and would also imply a GPL
  encoder this project does not convey.

Same trap as `mpv-remove-libass.patch` on Apple, which is guarded to the audio
variant and is likewise not published as applied.

## Scope: why mpv and not the whole component set

The Android bundle is 10 components. Source obligations attach only to the
copyleft ones:

- **Source limb** — FFmpeg n6.0 (LGPL-3, already published), mpv 0.36.0-549 and
  FriBidi 1.0.12, both LGPL-2.1 and both published here.
- **Attribution only** — libass (ISC), dav1d (BSD-2-Clause), HarfBuzz (MIT),
  Mbed TLS (Apache-2.0), libxml2 (MIT), FreeType (FTL), zlib (Zlib). Their
  texts ship as app assets and carry each component's own copyright line.

### FriBidi 1.0.12 — found while writing this file, and closed rather than filed

Android pins FriBidi **1.0.12**. The archives already published are `1.0.13`
(Apple's release tarball) and a Windows git export at a different revision.
Neither corresponds to this binary, so a 1.0.12 archive was owed.

Confirmed it actually ships before publishing anything: **16 `fribidi_` symbol
hits** in the shipped `arm64-v8a/libmpv.so`, against a working control
(`avcodec` 160). No version string is recoverable from the binary, so the
`1.0.12` figure rests on the recipe pin rather than on the artefact — stated
rather than glossed.

The recipe **git-clones** `https://github.com/fribidi/fribidi.git` at tag
`v1.0.12`, so the published archive is a commit export rather than a release
tarball; the annotated tag dereferences to commit
`6428d8469e536bcbb6e12c7b79ba6659371c435a`, and the archive root confirms it.
Fetched twice, identical.

**Not rounded to the 1.0.13 archive.** A source offer has to correspond to the
binary, and an off-by-one-patch-version archive does not.

*This is an engineering record, not a legal conclusion. It states identity,
retrieval, digests and what was checked.*

## How it was published

Written into the live Syncthing mirror at
`Linux_Matrix_Build/www/intergalactic/source/`, which propagates to
`/srv/docker/matrix/www/intergalactic/source/` on the host. That tree is
SERVER-owned; the overlap is logged in `conflict-log.json`. Directory went
44 → 47 files, nothing overwritten — each file was existence-checked first.
