# libmpv and its bundled FFmpeg — third-party notice evidence (Windows desktop)

Generated: 2026-08-07
Prepared by: S&C
Status: DRAFT - NOT PUBLISHED. REVIEW owns placement and publication.

This document supplies the notice content for `libmpv-2.dll`, the Windows media playback
library, and for the FFmpeg statically compiled inside it. Neither
`docs/release/THIRD_PARTY_NOTICES.md` nor `docs/policies/THIRD_PARTY_NOTICES.md` currently
contains any occurrence of `mpv` or `libmpv`, and `THIRD_PARTY_LICENSES.json` covers only the
Dart `media_kit` packages and the separate `ffmpeg.exe`/`ffprobe.exe` pair. This is the missing
surface.

> **Read this first.** The shipped `libmpv-2.dll` is an **LGPL** build, not a GPL build. The
> determination and its evidence are in `LICENCE-DETERMINATION.md`. Notice text below is
> written for the LGPL position and must not be published alongside a GPL claim.

## Scope

- Artefact: `libmpv-2.dll` (Windows desktop, all builds)
- SHA-256: `D5F0694B08C124E785D858D00082F3E3B158DD9138BFC48C0382BF1EB443A5FC`
- Size: 29,764,622 bytes
- Linkage: the app **dynamically loads** this DLL; mpv, FFmpeg and their dependencies are
  **statically compiled into** it
- Applies to: every Windows desktop release sampled, `0.7.2+980` through `0.8.1+1001`, which
  all ship a byte-identical DLL

## Two different FFmpegs — do not conflate

The project ships FFmpeg twice, as two separate covered artefacts with different versions,
different configure lines and different licences. A reader must be able to tell them apart.

| | **Inside `libmpv-2.dll`** (this document) | **Bundled tool pair** (`docs/release/evidence/ffmpeg-components/`) |
| --- | --- | --- |
| Artefact | `libmpv-2.dll` | `ffmpeg.exe`, `ffprobe.exe` |
| FFmpeg version | **n6.0** | **n8.1.1-13-g83e8541aa6** |
| Provider | media-kit libmpv-win32-video-build, release `2023-09-24` | BtbN FFmpeg Builds, `autobuild-2026-06-13-13-31` |
| Licence | LGPLv3-or-later | LGPLv3-or-later |
| External components | 15 (see below) | 58 |
| How the app uses it | linked into a DLL the app loads | run as a subprocess |
| Notice surface | this document | `docs/release/evidence/ffmpeg-components/THIRD_PARTY_NOTICES.ffmpeg-components.md` |

They share a licence conclusion and nothing else. The component lists are not
interchangeable, and neither corresponding-source archive satisfies the other's obligation.

---

## Notice content — mpv / libmpv

Version: `mpv v0.36.0-403-g652a1dd907`
Upstream: https://github.com/mpv-player/mpv
Licence: **GNU Lesser General Public License, version 2.1 or later (LGPLv2.1+)**

mpv is GPLv2-or-later by default. This build was produced with `-Dgpl=false`, which mpv's own
`Copyright` file describes as placing the result under "the GNU Lesser General Public License
LGPL version 2 or later (LGPLv2.1+ in this document)". The GPL-gated components — the
`direct3d` video output, `cdda`, `dvbin`, `dvdnav`, `jack`, `oss-audio`, `caca` and `x11` — are
excluded from this build by that flag.

Suggested user-facing text:

```text
mpv / libmpv

This application includes libmpv, from the mpv media player project
(https://mpv.io), version v0.36.0-403-g652a1dd907.

libmpv is used under the GNU Lesser General Public License, version 2.1 or
later. This build of libmpv is licensed under the LGPL; it does not include
the GPL-licensed components of mpv.

A copy of the LGPL version 2.1, the complete corresponding source code for
this build of libmpv, and the build instructions needed to reproduce it are
available from the Inter Galactic open-source information page.
```

Required alongside the notice:

- the full text of **LGPL version 2.1** (and, because of the FFmpeg inside, **LGPL version 3**
  and **GPL version 3**, which LGPLv3 incorporates by reference)
- an offer for, or direct link to, the corresponding source — see
  `corresponding-source-bundle.md`
- mpv's own copyright statement, taken from the `Copyright` file at the shipped revision

---

## Notice content — FFmpeg n6.0 inside libmpv

Version: `FFmpeg version n6.0`
Upstream: https://github.com/FFmpeg/FFmpeg
Licence: **GNU Lesser General Public License, version 3 or later (LGPLv3+)**

Confirmed two ways from the shipped binary. The configure line carries `--disable-gpl
--disable-nonfree --enable-version3`; and each library reports its own licence:

```text
libavcodec    license: LGPL version 3 or later
libavformat   license: LGPL version 3 or later
libavfilter   license: LGPL version 3 or later
libavutil     license: LGPL version 3 or later
libswscale    license: LGPL version 3 or later
libswresample license: LGPL version 3 or later
```

`--enable-version3` is load-bearing rather than decorative: `mbedtls` is Apache-2.0, which is
incompatible with GPLv2 but compatible with the v3 family, so the election to LGPLv3 is what
makes this component set coherent.

No GPL-only component is enabled. `--disable-gpl` is present, and none of FFmpeg's
GPL-list libraries (`libx264`, `libx265`, `libxvid`, `libdavs2`, `librubberband`, `libvidstab`,
`libcdio`, `libdvdnav`, `libdvdread`, `frei0r`, `avisynth`, `libxavs`, `libxavs2`) appears on
the configure line. No non-free component is enabled: `--disable-nonfree` is present and
`libfdk_aac`, `decklink` and `libmpeghdec` are absent.

Suggested user-facing text:

```text
FFmpeg (inside libmpv)

This application includes FFmpeg version n6.0 (https://ffmpeg.org), compiled
into the libmpv media playback library.

This build of FFmpeg is used under the GNU Lesser General Public License,
version 3 or later. It is built with --disable-gpl and --disable-nonfree and
contains no GPL-licensed or non-free FFmpeg components.

This is a different build from the FFmpeg command-line tools also distributed
with this application, which are covered by their own notice.

The complete corresponding source code and build instructions are available
from the Inter Galactic open-source information page.
```

### Credit obligations carried by this FFmpeg

- **FreeType** (`--enable-libfreetype`): the FreeType Licence requires, under its
  LEGAL TERMS, that redistribution in binary form provide a disclaimer in the
  distribution documentation. That mandatory disclaimer is:
  *"This software is based in part of the work of the FreeType Team."*
  (The phrase "based in part **of** the work" is upstream's own wording, quoted
  verbatim from `FTL.TXT`; it is not a typo here and should not be "corrected".)
  The licence separately **encourages**, in its introduction, a preferred credit
  form, which is reproduced here:
  *"Portions of this software are copyright © The FreeType Project
  (www.freetype.org). All rights reserved."*
  The credit form is encouraged rather than required — the two are distinct, and
  this entry previously presented the encouraged text as the required one.
  **The year is permanently absent, and this is now settled rather than
  pending.** The FTL directs replacing `<year>` with the version actually used.
  S&C recorded that this bundle's FreeType version appears nowhere and expected
  a direct probe of the DLL to confirm it; REVIEW ran that probe on Windows,
  2026-08-15, against the shipped `libmpv-2.dll`, sha256
  `D5F0694B08C124E785D858D00082F3E3B158DD9138BFC48C0382BF1EB443A5FC` — the
  digest this document already records — and it comes back **empty**:

  - **Positive controls all hit**, so the technique works on this binary:
    `libjpeg-turbo version 3.0.1 (build 20230924)`, `1.2.13` for zlib, and
    `libpng version 1.6.41.git`.
  - **FreeType is genuinely linked**, so the miss is not absence of the library:
    172 distinct `FT_*` symbols are present.
  - **The only FreeType strings are `FreeType` and the runtime format template
    `FreeType %d.%d.%d`.** No literal `2.11.x` / `2.12.x` / `2.13.x` appears
    anywhere in the 382,865 printable runs.

  FreeType's version lives in this DLL as numeric constants substituted at
  runtime, so no string probe can reach it. The remaining routes — reading the
  `FREETYPE_MAJOR/MINOR/PATCH` constants, or calling `FT_Library_Version` — are
  disproportionate to one credit-line year and are not being pursued.

  Do **not** infer the year from the DLL's build date: 2.13.x, 2.12.x and 2.11.x
  give 2023, 2022 and 2021 respectively, and a date bound only answers where
  every candidate agrees. Tracked in
  `docs/agent-control/security-and-compliance-handoff.md` (Matrix_Dev).

  The credit form is encouraged rather than required, so an absent year does not
  leave a mandatory limb unmet; the mandatory disclaimer above is present. Note
  that iOS **is** year-filled (2023) because its FreeType is version-pinned at
  `VER-2-13-2` — the platforms differ because the evidence differs, not because
  one was done less carefully.
- **libjpeg-turbo**, present in the DLL and reporting `libjpeg-turbo version 3.0.1 (build
  20230924)` with `Copyright (C) 1991-2023 The libjpeg-turbo Project and many others`. Where
  the IJG-derived code is used, the Independent JPEG Group credit obligation applies, as it
  does for the separate tool pair.
- **libpng**, reporting `libpng version 1.6.41.git`, carries its own copyright roster
  (Cosmin Truta; Glenn Randers-Pehrson; Andreas Dilger; Guy Eric Schalnat / Group 42).
- **zlib**, reporting `inflate 1.2.13 Copyright 1995-2022 Mark Adler` and
  `deflate 1.2.13 Copyright 1995-2022 Jean-loup Gailly and Mark Adler`.

These four copyright lines are present verbatim in the shipped binary and should be reproduced
as-is rather than paraphrased.

---

## Component list — see the structured inventory

The enumerated component list, with per-component confidence and the evidence behind each
entry, is in `THIRD_PARTY_LICENSES.libmpv.json`. The derivation method and its limits are
stated there and in `LICENCE-DETERMINATION.md`; in short, the list comes from the two
configure lines recovered from the shipped binary, **not** from the build repository's
`packages/` catalogue, which lists 100+ packages including GPL ones that are not in this
artefact.
