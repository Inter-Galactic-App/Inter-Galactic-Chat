# Corresponding-source archive definition — libmpv-2.dll

Prepared by S&C, 2026-08-07. **Draft. Not published.** REVIEW owns publication.

> The task asked for this bundle "to satisfy GPL §1". The shipped DLL is **not** GPL — see
> `LICENCE-DETERMINATION.md`. The obligation is LGPL, so this document is written to
> **LGPLv2.1 §4/§6 and LGPLv3 §4**, which is a narrower but genuinely live obligation. The
> practical archive contents barely differ; the offer text and the relinking requirement do.

## What the LGPL actually requires here

Because mpv, FFmpeg and their dependencies are **statically linked into a DLL that the
application dynamically loads**, the relevant obligation is the LGPL's, not the GPL's, and it
splits in two:

1. **Source for the LGPL library itself.** Complete corresponding source for `libmpv-2.dll` —
   mpv, FFmpeg, and every non-system component statically compiled in — plus the build scripts
   and configuration needed to reproduce it.
2. **The ability to relink.** LGPLv2.1 §6 / LGPLv3 §4 require that a user can replace the
   library with a modified version and still use the application. This is already satisfied by
   construction: `libmpv-2.dll` is a separate DLL loaded at run time, and a user can drop in
   their own build. **No application source is required**, and nothing about the LGPL forces
   the app's own licence.

Point 2 is why this is much less onerous than the GPL framing implied. The app does not become
encumbered.

## Bill of materials

### Tier 1 — the two primaries

| Item | Identity | Retrieval | Status |
| --- | --- | --- | --- |
| **mpv** | `v0.36.0-403-g652a1dd907` | `git clone https://github.com/mpv-player/mpv && git checkout 652a1dd907` | Obtainable. Specific identifiable commit. |
| **FFmpeg** | `n6.0` = commit `ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2` | `git clone https://github.com/FFmpeg/FFmpeg && git checkout ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2` | **PUBLISHED 2026-08-08** at `/source/ffmpeg-n6.0-source.tar.gz`. Cell updated 2026-08-09; it read "prepared and staged, not published". See `ffmpeg-n6.0-SOURCE.md`. |

Both are upstream, public, and nothing is pruned — unlike the BtbN/FFmpeg case where the
build inputs had been garbage-collected.

### Tier 2 — the build definition

| Item | Identity | Status |
| --- | --- | --- |
| Build scripts | `media-kit/libmpv-win32-video-build` | **BLOCKED — see below** |
| Parent project | `zhongfly/mpv-winbuild`, itself from `lachs0r/mingw-w64-cmake` | MIT, redistributable |

**This is the one genuine gap.** The recorded commit `0837d6b2eb` does **not** describe the
shipped artefact: its `packages/mpv.cmake` declares `-Dlua=enabled -Dopenal=enabled
-Dvulkan=enabled -Dlibplacebo=enabled` and carries no `-Dgpl` flag, while the binary's own
meson line says `-Dlua=disabled -Dopenal=disabled -Dvulkan=disabled -Dlibplacebo=disabled
-Dgpl=false`. Publishing that commit as the build definition would be publishing something
demonstrably not corresponding to the binary, which is worse than publishing nothing.

The upstream repository was **archived on 2024-10-09**. It is still readable, but it will not
change and cannot be corrected upstream.

**Required before publication:** identify the commit or CI run that produced release
`2023-09-24`. The most direct routes are the GitHub Actions run attached to that release, or a
reproduction build compared against the recovered configure lines. Once identified, mirror the
scripts into project-controlled storage rather than relying on an archived third-party repo.

Redistribution of the scripts themselves is permitted: the repository has no LICENSE file, but
it is a fork of `zhongfly/mpv-winbuild`, which is MIT.

### Tier 3 — statically compiled non-system components

Enumerated with per-component confidence and evidence in
`THIRD_PARTY_LICENSES.libmpv.json`. Summary:

- **15** FFmpeg external components (libdav1d, libfreetype, libfribidi, libsoxr, libspeex,
  libxml2, libzimg, libwebp, libvpl, libshaderc, mbedtls, libjxl, libmysofa, libbs2b, zlib)
- **2** header-only vendor API sets (nv-codec-headers, AMF headers)
- **11** mpv components (libass, harfbuzz, libunibreak, lcms2, uchardet, libarchive, mujs,
  libjpeg-turbo, libpng, spirv-cross, mingw-w64 runtime)

Exact upstream revisions for Tier 3 are **not yet pinned**. Four components carry version
numbers recoverable from the binary — fribidi 1.0.13, zlib 1.2.13, libjpeg-turbo 3.0.1,
libpng 1.6.41 — and the rest must come from the build definition, which is the same blocker as
Tier 2. This is the second reason resolving Tier 2 is the critical path.

### Tier 4 — excluded, and why

Excluding these correctly is as load-bearing as including the rest, and is the point the
owner's research doc makes. Do **not** ship source for:

- Anything present only in the build repo's `packages/` catalogue. That directory holds 100+
  definitions, including GPL-only ones (`libdvdnav`, `libdvdread`, `x264`, `x265`,
  `avisynth-headers`) and many plainly unused (`aom`, `libvpx`, `lame`, `opus`, `flac`,
  `curl`, `luajit`, `megasdk`). Catalogue membership is not evidence of presence.
- Components disabled by a later flag on the same line: **libmfx** (`--enable-libmfx` then
  `--disable-libmfx`; last wins), **libuavs3d**, **bzip2**.
- Components disabled in mpv's meson line: **lua/luajit**, **openal-soft**, **vulkan**,
  **libplacebo**.
- Components excluded by `-Dgpl=false`: **libdvdnav**, **libdvdread**, **vo_direct3d**.
- Windows system APIs: **dxva2**, **d3d11va**, Direct3D, EGL.
- The NVIDIA and AMD runtimes themselves — only their MIT headers are compiled in; no vendor
  binary is redistributed.
- **ANGLE**, which arrives as a separate archive and separate DLLs
  (`libEGL.dll`, `libGLESv2.dll`, `vk_swiftshader.dll`) from
  `alexmercerind/flutter-windows-ANGLE-OpenGL-ES v1.0.1`. It is a different covered artefact
  under BSD-3-Clause, and it is not part of this bundle. It is also not currently covered by
  any notice — worth its own item.

## Proposed archive

One archive per native artefact, reusable across app releases. This DLL is byte-identical in
all 19 sampled Windows builds, so one archive covers every Windows release to date; it does
not need regenerating per version.

```text
libmpv-2.dll-corresponding-source/
├── README.md                     how to rebuild; what this covers
├── SOURCE_MANIFEST.json          the mapping below
├── LICENSES/                     LGPL-2.1, LGPL-3.0, GPL-3.0 (referenced by LGPLv3),
│                                 plus each component's own licence text
├── build/
│   ├── build-instructions.md
│   ├── mpv-meson-configure-line.txt      (recovered from the binary)
│   ├── ffmpeg-configure-line.txt         (recovered from the binary)
│   └── toolchain-information.txt         mingw-w64 cross toolchain
├── build-scripts/                libmpv-win32-video-build at the CORRECT commit  [BLOCKED]
├── mpv/                          652a1dd907
├── ffmpeg/                       n6.0
└── third-party/                  Tier 3, at pinned revisions                     [BLOCKED]
```

`SOURCE_MANIFEST.json` maps: app release → native artefact → artefact SHA-256 →
corresponding-source archive → archive SHA-256 → component versions and licences. Per the
owner's research, checksums are **provenance metadata, not an LGPL requirement**; they belong
in the manifest and should not become per-component public download links.

## Hosting and offer

- **One** page, e.g. `/legal/open-source`, grouped by native artefact — not by dependency.
- **One** link to it from each real download surface and from the app's About/Legal screen.
  Not under every button, not beside every mention of "download".
- Group `libmpv-2.dll` and the `ffmpeg.exe`/`ffprobe.exe` pair as **two separate artefacts**
  with two separate archives. They share a licence conclusion and nothing else.
- Avoid floating `main`/`master`/`latest` references. Every row pins a commit or tag.

## Readiness

| Element | State |
| --- | --- |
| Artefact identity and hashes | **Done** — verified locally, provenance chain closed |
| Licence determination | **Done** — LGPL, four independent checks |
| mpv source | **Published** — live at `/source/`, digest re-verified against the served file 2026-08-08 |
| FFmpeg `n6.0` source | **Published 2026-08-08** — digest re-verified against the served file after copying; `ffmpeg-n6.0-SOURCE.md`. Row updated 2026-08-09; it read "Staged, awaiting publication" |
| Obligated components (`libfribidi` 1.0.13, `libsoxr` 0.1.3, `uchardet`) | **Published 2026-08-09** — at their own pins, which are *not* the FFmpeg tool pair's. `uchardet`'s arm was elected LGPL-2.1-or-later by the owner on 2026-08-09 and its commit is best evidence, not a recovered pin |
| Notice text | **Drafted** — `THIRD_PARTY_NOTICES.libmpv.md` |
| Component list | **Drafted** — confidence-marked, 4 items unresolved |
| Build definition | **Blocked** — recorded commit contradicts the binary |
| Tier 3 revisions | **Partly closed 2026-08-09** — the three obligated ones are pinned and published; the attribution-only remainder still depends on the build definition |
| Per-component licence texts | **Not started** for the attribution-only remainder |
| Transitive dependencies of this DLL | **Not enumerable** — the same blind spot that hid FFTW inside `ffmpeg.exe`, so the obligated set of three is not proven complete |

The notice surface can be published ahead of the archive; the source offer cannot be finalised
until the build definition is identified.
