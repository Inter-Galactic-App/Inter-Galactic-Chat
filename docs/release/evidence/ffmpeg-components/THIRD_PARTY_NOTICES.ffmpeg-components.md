# FFmpeg Bundled Component License Evidence (Windows desktop)

Generated: 2026-08-07T14:12:12Z
Prepared by: S&C
Status: Tracked release evidence. Promoted from scratch 2026-08-08 at REVIEW's placement
direction. **Not yet folded into the deployed `third-party-notices/` surface.** The
per-component corresponding source **was published 2026-08-09** at
`https://app.ourgalaxy.space/source/` — see "Open Gaps". *(Until 2026-08-09 this line
read "is not published", which stopped being true the day the archives went live.)*

This evidence enumerates the third-party components compiled **into** the bundled Windows
FFmpeg tool pair. It is a companion to `docs/release/evidence/ffmpeg/`, which covers the
FFmpeg tool pair as a single artifact. FFmpeg's own compliance checklist requires the items
to be walked again for every LGPL external library compiled in, which is what this document
provides. The structured form of the same data is
`THIRD_PARTY_LICENSES.ffmpeg-components.json` beside this file; FFmpeg's own licence text at
the shipped revision is `docs/release/evidence/license-sources/ffmpeg/LICENSE-FFmpeg.md`.

## Scope

- `intergalactic/windows/third_party/ffmpeg/bin/ffmpeg.exe`
- `intergalactic/windows/third_party/ffmpeg/bin/ffprobe.exe`

`ffprobe.exe` was removed from the desktop payload by app PR #101, but every public release
through `0.8.0+993` shipped it and the source-availability obligation runs to the recipients
of those builds. It is named here deliberately and **must not be tidied out**. Both
executables share one provider, revision and configure line, so the component list below is
identical for each.

- FFmpeg version: `n8.1.1-13-g83e8541aa6-20260613` (revision `83e8541aa601935a610b1b8958d56e8d0331318b`)
- Provider: BtbN FFmpeg Builds, autobuild-2026-06-13-13-31, ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip
- Linkage: static; the two executables are self-contained
- App integration: the app runs the tools as subprocesses and does not link FFmpeg libraries

## Derivation

Component list derived by parsing the `configuration:` line captured from the exact shipped
binary (`repo:docs/release/evidence/ffmpeg/ffmpeg-version.txt`).

- `--enable-` flags on the configure line: **62**
- Non-component switches excluded: `version3`, `pthreads`, `cuda-llvm`, `schannel`
- Third-party components: **58**

--enable-version3 is a licence-election switch; --enable-pthreads selects a threading model; --enable-cuda-llvm selects how CUDA kernels are compiled; --enable-schannel uses the Windows TLS API rather than a redistributed library. None is a third-party component shipped inside the binaries.

## Coverage Summary

- Third-party components: 58
- Attribution only: 42
- LGPL-family (attribution **and** source availability): 13
- GPL-family (attribution **and** source availability): 1 — `libzvbi`, which is
  partly GPL-2.0-only; see the correction in "Component Notes"
- Weak copyleft, file-level (attribution **and** source availability): 2
- Total carrying a source obligation: **16**
- GPL-only *code* present: **yes** — see the correction below. The count of
  configure-line components FFmpeg itself classifies as GPL-only remains 0
- Non-free components enabled: 0
- Entries flagged needs-review: **2** — `libkvazaar`, `libzmq`

> **Correction, 2026-08-09 (S&C).** This summary read "GPL-only components enabled: 0" from
> 2026-08-07. That number was accurate about the axis it measured — FFmpeg configure's own
> `EXTERNAL_LIBRARY_GPL_LIST` — and inaccurate as a statement about the binary, in the same
> way and for the same reason as the FFTW miss. Two paths put GPL code inside `ffmpeg.exe`
> without any configure-line component being GPL-only: **FFTW** (GPL-2.0-or-later), a
> transitive dependency of `chromaprint`, already disclosed separately; and **part of
> `libzvbi`** (GPL-2.0-only in `src/packet-830.*` and `src/pdc.*`), which is invisible to a
> per-component SPDX id because the component is per-file mixed. A whole-component licence id
> cannot express a mixed tree, and a configure-line check cannot see inside one. `libzvbi`
> also leaves the needs-review list here — not because the doubt was cleared in its favour,
> but because reading the source resolved it against the earlier classification.
- Entries whose linkage could not be confirmed by probe: **4** — `chromaprint`,
  `libharfbuzz`, `libsnappy`, `libuavs3d`

> This document and the JSON beside it both read "Entries flagged needs-review: 4" from
> 2026-08-07 until 2026-08-08. Only three entries carry a NEEDS-REVIEW marker and no fourth
> could be reconciled to any entry, so the count is corrected to 3 and the members are named.
> The likely source of the confusion is the separate set of **four** linkage-unconfirmed
> components, which is a different axis and is now counted on its own line. Do not restore 4
> without naming the fourth.

## GPL and Non-Free Check

Result: **CLEAN AS TO THE CONFIGURE LINE — and that is not the same as clean as to the
binary. Read the scope note below before quoting this result.**

> **Scope correction, 2026-08-09 (S&C).** This check was previously reported as "CLEAN"
> without qualification, and that phrasing has now been the proximate cause of two wrong
> public statements — the FFTW miss, and the in-app notice claiming "no GPL-only component is
> present". The check is correct and correctly run. It is authoritative for **direct
> configure-line components as FFmpeg itself classifies them**, and blind by construction to
> two things: **transitive dependencies** (FFTW arrives beneath `chromaprint`, which is not
> itself GPL) and **per-file mixed licensing inside a component** (`libzvbi` carries
> GPL-2.0-only files under a component id that is not GPL). Both blind spots have now
> produced a real GPL component in the shipped binary. A "CLEAN" from this check must never
> be restated as "no GPL code is present"; it means "no enabled component is on FFmpeg's
> GPL-only list", and nothing more.

Cross-checked every enabled flag against FFmpeg configure's own EXTERNAL_LIBRARY_GPL_LIST, EXTERNAL_LIBRARY_NONFREE_LIST and EXTERNAL_LIBRARY_GPLV3_LIST, extracted from the matching source revision.

- GPL-only libraries enabled: none *(on FFmpeg's own list — see the scope correction above)*
- Non-free libraries enabled: none
- GPL-only libraries explicitly disabled in this build: `avisynth`, `frei0r`, `libdavs2`, `libdvdnav`, `libdvdread`, `librubberband`, `libvidstab`, `libx264`, `libx265`, `libxavs2`, `libxvid`
- Non-free libraries explicitly disabled in this build: `libfdk-aac`

The extracted buckets themselves are recorded in `ffmpeg-configure-license-lists.md` beside
this file, so the check can be re-run against its own authority.

### Why `--enable-version3` is required

These enabled components force the v3 licence election:

- gmp (LGPL-3.0-or-later)
- libaribb24 (LGPL-3.0-or-later)
- libopencore-amrnb (Apache-2.0)
- libopencore-amrwb (Apache-2.0)

--enable-version3 is not optional decoration: four enabled components require it. Removing it would make the build non-distributable, so LGPL-3.0-or-later is the correct and necessary licence for the tool pair.

## Required Credits

### Independent JPEG Group

FFmpeg LICENSE.md: libavcodec/jfdctfst.c, libavcodec/jfdctint_template.c and libavcodec/jrevdct.c are taken from libjpeg. Because we distribute executables only, we must credit the Independent JPEG Group in the accompanying documentation, and must indicate any changes (additions and deletions) to those three files.

> This software is based in part on the work of the Independent JPEG Group.

No Inter Galactic modifications were made; the binaries are unmodified upstream BtbN builds.

### FreeType

The FreeType Licence (FTL) requires a specific credit line in the documentation when the FTL is elected over the GPL-2.0 alternative.

> Portions of this software are copyright (c) The FreeType Project (www.freetype.org).
> All rights reserved.

## Components Carrying A Source-Availability Obligation

For each of these, providing attribution is not sufficient. The corresponding source must be
made available, and because the tool pair is **statically** linked, the LGPL relink provisions
(LGPL-2.1 section 6 / LGPL-3 section 4) are engaged as well.

| Component | Upstream | License | Class |
| --- | --- | --- | --- |
| `iconv` | [GNU libiconv](https://www.gnu.org/software/libiconv/) | LGPL-2.1-or-later | LGPL-family - source |
| `libfribidi` | [GNU FriBidi](https://github.com/fribidi/fribidi) | LGPL-2.1-or-later | LGPL-family - source |
| `gmp` | [GNU MP (GMP)](https://gmplib.org/) | LGPL-3.0-or-later | LGPL-family - source |
| `libaribb24` | [aribb24](https://code.videolan.org/videolan/aribb24) | LGPL-3.0-or-later | LGPL-family - source |
| `chromaprint` | [AcoustID Chromaprint](https://github.com/acoustid/chromaprint) | LGPL-2.1-or-later | LGPL-family - source |
| `libgme` | [Game_Music_Emu](https://github.com/libgme/game-music-emu) | LGPL-2.1-or-later | LGPL-family - source |
| `libbluray` | [VideoLAN libbluray](https://code.videolan.org/videolan/libbluray) | LGPL-2.1-only | LGPL-family - source |
| `libmp3lame` | [LAME](https://lame.sourceforge.io/) | LGPL-2.0-or-later | LGPL-family - source |
| `libplacebo` | [libplacebo](https://code.videolan.org/videolan/libplacebo) | LGPL-2.1-or-later | LGPL-family - source |
| `libssh` | [libssh (libssh.org)](https://www.libssh.org/) | LGPL-2.1-or-later | LGPL-family - source |
| `libzmq` | [ZeroMQ libzmq](https://github.com/zeromq/libzmq) | MPL-2.0 | weak copyleft - source |
| `openal` | [OpenAL Soft](https://github.com/kcat/openal-soft) | LGPL-2.0-or-later | LGPL-family - source |
| `libsoxr` | [SoX Resampler library](https://sourceforge.net/projects/soxr/) | LGPL-2.1-or-later | LGPL-family - source |
| `libsrt` | [Haivision SRT](https://github.com/Haivision/srt) | MPL-2.0 | weak copyleft - source |
| `libtwolame` | [TwoLAME](https://github.com/njh/twolame) | LGPL-2.1-or-later | LGPL-family - source |
| `libzvbi` | [ZVBI (Zapping VBI library)](https://github.com/zapping-vbi/zvbi) | LGPL-2.0-or-later | LGPL-family - source |

## Attribution-Only Components

| Component | Upstream | License |
| --- | --- | --- |
| `zlib` | [zlib](https://zlib.net/) | Zlib |
| `libxml2` | [GNOME libxml2](https://gitlab.gnome.org/GNOME/libxml2) | MIT |
| `libvmaf` | [Netflix VMAF](https://github.com/Netflix/vmaf) | BSD-2-Clause-Patent |
| `fontconfig` | [fontconfig](https://gitlab.freedesktop.org/fontconfig/fontconfig) | MIT |
| `libharfbuzz` | [HarfBuzz](https://github.com/harfbuzz/harfbuzz) | MIT |
| `libfreetype` | [FreeType](https://freetype.org/) | FTL OR GPL-2.0-or-later |
| `vulkan` | [Khronos Vulkan-Headers / Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Headers) | Apache-2.0 |
| `libshaderc` | [Google shaderc](https://github.com/google/shaderc) | Apache-2.0 |
| `libvorbis` | [Xiph.Org libvorbis](https://xiph.org/vorbis/) | BSD-3-Clause |
| `opencl` | [Khronos OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers) | Apache-2.0 |
| `lzma` | [XZ Utils liblzma](https://tukaani.org/xz/) | 0BSD |
| `liblcevc-dec` | [V-Nova LCEVCdec](https://github.com/v-novaltd/LCEVCdec) | BSD-3-Clause-Clear |
| `amf` | [AMD Advanced Media Framework headers](https://github.com/GPUOpen-LibrariesAndSDKs/AMF) | MIT |
| `libaom` | [AOMedia libaom](https://aomedia.googlesource.com/aom/) | BSD-2-Clause AND AOM-Patent-License-1.0 |
| `libdav1d` | [VideoLAN dav1d](https://code.videolan.org/videolan/dav1d) | BSD-2-Clause |
| `ffnvcodec` | [nv-codec-headers](https://github.com/FFmpeg/nv-codec-headers) | MIT |
| `libkvazaar` | [Kvazaar (Ultra Video Group, Tampere Univ.)](https://github.com/ultravideo/kvazaar) | BSD-3-Clause |
| `libaribcaption` | [libaribcaption](https://github.com/xqq/libaribcaption) | MIT |
| `libass` | [libass](https://github.com/libass/libass) | ISC |
| `libjxl` | [libjxl (JPEG XL)](https://github.com/libjxl/libjxl) | BSD-3-Clause |
| `libopus` | [Opus / libopus (Xiph.Org, Mozilla, Broadcom, et al.)](https://opus-codec.org/) | BSD-3-Clause |
| `librist` | [librist (RIST Forum / VideoLAN)](https://code.videolan.org/rist/librist) | BSD-2-Clause |
| `libtheora` | [Xiph.Org libtheora](https://theora.org/) | BSD-3-Clause |
| `libvpx` | [WebM libvpx](https://github.com/webmproject/libvpx) | BSD-3-Clause AND additional IP rights grant |
| `libwebp` | [Google libwebp](https://chromium.googlesource.com/webm/libwebp) | BSD-3-Clause |
| `lv2` | [LV2 (with lilv / serd / sord / sratom)](https://lv2plug.in/) | ISC |
| `libvpl` | [Intel Video Processing Library (oneVPL dispatcher)](https://github.com/intel/libvpl) | MIT |
| `liboapv` | [OpenAPV (Advanced Professional Video)](https://github.com/AcademySoftwareFoundation/openapv) | BSD-3-Clause |
| `libopencore-amrnb` | [OpenCORE AMR-NB](https://sourceforge.net/projects/opencore-amr/) | Apache-2.0 |
| `libopencore-amrwb` | [OpenCORE AMR-WB](https://sourceforge.net/projects/opencore-amr/) | Apache-2.0 |
| `libopenh264` | [Cisco OpenH264](https://github.com/cisco/openh264) | BSD-2-Clause |
| `libopenjpeg` | [OpenJPEG](https://github.com/uclouvain/openjpeg) | BSD-2-Clause |
| `libopenmpt` | [libopenmpt (OpenMPT)](https://lib.openmpt.org/libopenmpt/) | BSD-3-Clause |
| `librav1e` | [rav1e](https://github.com/xiph/rav1e) | BSD-2-Clause |
| `sdl2` | [Simple DirectMedia Layer 2](https://www.libsdl.org/) | Zlib |
| `libsnappy` | [Google Snappy](https://github.com/google/snappy) | BSD-3-Clause |
| `libsvtav1` | [SVT-AV1 (Alliance for Open Media)](https://gitlab.com/AOMediaCodec/SVT-AV1) | BSD-3-Clause-Clear AND AOM-Patent-License-1.0 |
| `libuavs3d` | [uavs3d (Peking Univ. Shenzhen / Peng Cheng Lab / Bohua UHD)](https://github.com/uavs3/uavs3d) | BSD-3-Clause |
| `vaapi` | [libva (Intel VA-API)](https://github.com/intel/libva) | MIT |
| `libvvenc` | [Fraunhofer HHI VVenC](https://github.com/fraunhoferhhi/vvenc) | BSD-3-Clause-Clear |
| `whisper` | [whisper.cpp (with ggml)](https://github.com/ggml-org/whisper.cpp) | MIT |
| `libzimg` | [zimg](https://github.com/sekrit-twc/zimg) | WTFPL |

## Toolchain Components Not Named On The Configure Line

These are linked into the shipped binaries but are invisible to a configure-line-only
inventory. They are listed so the notice describes what actually ships.

| Component | Upstream | License |
| --- | --- | --- |
| `libgomp` | [GCC OpenMP runtime](https://gcc.gnu.org/) | GPL-3.0-or-later WITH GCC-exception-3.1 |
| `libgcc / libstdc++` | [GCC runtime libraries](https://gcc.gnu.org/) | GPL-3.0-or-later WITH GCC-exception-3.1 |
| `winpthreads` | [mingw-w64 winpthreads](https://www.mingw-w64.org/) | MIT AND Zope-2.1-style |
| `mingw-w64 CRT` | [mingw-w64 runtime / import libraries](https://www.mingw-w64.org/) | permissive (per-file; ZPL-2.1 / MIT / public domain) |

## Notes And Flags

- **`iconv`** - Well-established GNU project licence; not independently re-fetched this session. Linkage confirmed ('libiconv_t' in binary).
- **`libxml2`** - 109 distinct xml* symbols present in shipped binary.
- **`libvmaf`** - DISCREPANCY: FFmpeg LICENSE.md still states VMAF is Apache-2.0 and therefore requires --enable-version3. Upstream LICENSE is BSD-2-Clause-Patent (verified). The version3 requirement is independently satisfied by gmp/libaribb24/libopencore-amr, so the build is unaffected.
- **`fontconfig`** - fontconfig's own licence text is an MIT/BSD-style permissive licence.
- **`libharfbuzz`** - Linkage not confirmable by symbol probe (no hb_* symbols found); presence assumed because libass requires it.
- **`libfreetype`** - OBLIGATION: electing the FreeType Licence (FTL) requires the credit line 'Portions of this software are copyright (c) <year> The FreeType Project (www.freetype.org). All rights reserved.' in the documentation. The dual-licence election must be recorded explicitly.
- **`opencl`** - Headers only; the OpenCL ICD is loaded from the host system at runtime and is not redistributed.
- **`gmp`** - Dual GPL-2.0-or-later / LGPL-3.0-or-later. FFmpeg LICENSE.md lists gmp under 'libraries under LGPL version 3'. This is one of the components that forces --enable-version3.
- **`lzma`** - liblzma core is public domain / 0BSD; no attribution strictly required but listing is good practice.
- **`liblcevc-dec`** - Verified from upstream LICENSE.md ('The Clear BSD License'). Note the Clear BSD grants no patent rights.
- **`amf`** - Headers only; amfrt64.dll is an AMD driver component on the host, not redistributed.
- **`libaribb24`** - FFmpeg LICENSE.md lists libaribb24 under 'libraries under LGPL version 3'. Forces --enable-version3.
- **`chromaprint`** - Upstream LICENSE.md: Chromaprint's own code is MIT but it embeds LGPL-2.1 FFmpeg code, so 'as a whole, Chromaprint should be therefore considered to be licensed under the LGPL 2.1 license'. GitHub API reports NOASSERTION. Linkage not confirmable by symbol probe; treated as present (conservative). This is the only linkage-unconfirmed entry that is LGPL-family, so it is the only one where the uncertainty could change an obligation.
- **`ffnvcodec`** - Headers only; NVIDIA driver DLLs are host components, not redistributed.
- **`libgme`** - Linkage confirmed by internal strings 'Blip_Buffer', 'Nintendo NES', 'Game Music Emu'.
- **`libkvazaar`** - NEEDS-REVIEW (version-dependent): Kvazaar was LGPL-2.1 through the 1.x series and relicensed to BSD-3-Clause at 2.0. BtbN pins the version in its build scripts; the FFmpeg configure line does not record it. If BtbN pinned a 1.x build this moves into the LGPL-family bucket.
- **`libbluray`** - **CORRECTED 2026-08-09 (S&C): LGPL-2.1-or-later, not LGPL-2.1-only.** This entry previously read "VideoLAN states LGPL v2.1 only (not 'or later')", taken from VideoLAN's project description. The component's own source at the pinned commit contradicts it, and the source governs. Verified in the held archive `libbluray-g4dfb9b0123b0-source.tar.gz` at `4dfb9b0123b006ce5d66592dc8058f61e5c0cdc8`: `src/libbluray/bluray.c` reads *"either version 2.1 of the License, or (at your option) any later version"*, 845 files in the tree carry that same or-later grant, and **zero** files state 2.1 without it. The tree is not mixed in any way that matters: the only non-LGPL files are `jni/*.h` (MPL-1.1/GPL-2.0+/LGPL-2.1+ tri-licensed, so LGPL-2.1-or-later is electable) and `src/devtools/bdj_test.c` (GPL-2.0-or-later, a devtool that is not in the library build). **Consequence: libbluray can elect v3 and does have access to GPL-3 §8 cure.** Any statement that it is the one component with no cure route is wrong and is retracted.
- **`libmp3lame`** - Dual GPL-2.0 / LGPL-2.0 upstream; FFmpeg links it as LGPL. This is the exact component FFmpeg's own compliance checklist names as the worked example.
- **`libplacebo`** - 63 distinct pl_* symbols present in shipped binary.
- **`libssh`** - This is libssh.org's libssh, NOT libssh2 (which is BSD-3-Clause). FFmpeg's libavformat/libssh.c uses libssh. Linkage confirmed ('ssh_new', 'sftp_new', 'ssh_connect').
- **`libzmq`** - NEEDS-REVIEW (version-dependent): current upstream is MPL-2.0 (verified). Releases up to 4.3.4 were LGPL-3.0-or-later with a static-linking exception. Either way this carries a source-availability obligation for the library's own files; under MPL-2.0 it is file-level, not whole-work. BtbN pins the version; the configure line does not record it.
- **`lv2`** - 26 distinct lilv_* symbols present in shipped binary.
- **`openal`** - Upstream COPYING is the GNU Library General Public License Version 2 (verified). Linkage confirmed ('alcOpenDevice', 'alcCaptureOpenDevice').
- **`libopencore-amrnb`** - Apache-2.0 is incompatible with LGPL-2.1; FFmpeg lists OpenCORE among the libraries that force --enable-version3.
- **`libopencore-amrwb`** - Same version3 driver as AMR-NB.
- **`libopenh264`** - PATENT CAVEAT (not a licence defect): Cisco's royalty-free AVC/H.264 patent offer covers Cisco's own precompiled openh264 binary module only. BtbN compiles openh264 from source into ffmpeg.exe, so that offer does not attach. Owner decision, route separately.
- **`libopenmpt`** - 91 distinct openmpt_* symbols present in shipped binary.
- **`sdl2`** - NOT LINKED into the shipped binaries. Verified: zero SDL_* symbols in ffmpeg.exe or ffprobe.exe; the only 'SDL' hits are the embedded configure string. SDL2 is used by ffplay.exe, which this project does not ship. Recommend excluding from the shipped-binary notice with this evidence recorded.
- **`libsnappy`** - Linkage not confirmable by symbol probe (C++ symbols); presence assumed from configure line.
- **`libsoxr`** - Verified from upstream LICENCE. Linkage confirmed ('soxr_create').
- **`libsrt`** - MPL-2.0 is file-level weak copyleft: source for the SRT files themselves must be made available. Linkage confirmed ('srt_socket', 'srt_connect').
- **`libtwolame`** - Linkage confirmed ('twolame_init'). Note --extra-cflags=-DLIBTWOLAME_STATIC confirms static linkage explicitly.
- **`libuavs3d`** - Upstream COPYING is a BSD-style three-clause text but carries no SPDX tag (GitHub reports NOASSERTION). Linkage not confirmable by symbol probe.
- **`vaapi`** - 63 distinct va* symbols present in shipped binary.
- **`whisper`** - 37 distinct whisper_* symbols present. Models are not bundled; they are supplied at runtime.
- **`libzimg`** - WTFPL imposes no attribution requirement; listed for completeness.
- **`libzvbi`** - **CORRECTED 2026-08-09 (S&C): the single id `LGPL-2.0-or-later` is incomplete. The tree is mixed and part of it is GPL-2.0-only.** This entry previously rested on distribution metadata and was flagged needs-review; reading the source settles it. Verified in the held archive `libzvbi-g41477c97c8ed-source.tar.gz` at `41477c97c8edf7a01f1594b2a95b94f0117eed21`. `COPYING.md` is per-directory and states verbatim: *"The files src/packet-830.\* and src/pdc.\* have the following copyright and license: License: GPL-2"*. The files agree — `src/pdc.c` and `src/packet-830.c` both read *"under the terms of the GNU General Public License version 2 as published by the Free Software Foundation"* with **no "or later"**. That is **four** files, not two: the `.h` files carry the same header. Remaining scope: `src/*` default LGPL-2.0-or-later, `src/dvb/{dmx,frontend}.h` and `src/strptime.*` LGPL-2.1-or-later, `src/ure.*` MIT, `src/videodev2k.h` GPL-2.0-or-later or BSD-3-Clause, project root and `po/*` GPL-2.0-or-later, `examples/*` BSD-2-Clause.
  - **Established — `packet-830` reaches the executable.** `src/Makefile.am` places `packet-830.c packet-830.h` and `pdc.c pdc.h` in `libzvbi_la_SOURCES`, and there is an unconditional link-time chain from FFmpeg: `libavcodec/libzvbi-teletextdec.c:679` calls `vbi_decode` → `src/vbi.c:472` `vbi_decode_teletext` → `src/packet.c:2686` `parse_8_30` → `src/packet.c:2146` and `:2165`, which call `vbi_decode_teletext_8301_local_time` and `vbi_decode_teletext_8302_pdc`, both defined in `packet-830.c`. The `event_mask` tests at those call sites are **runtime** guards, not link-time ones, so a static link must resolve the references and pull `packet-830.o`.
  - **Not established — `pdc.o`.** No cross-translation-unit reference to any `pdc.c`-defined symbol exists in the tree, so on a standard static link it would not be pulled. That is an inference about linker behaviour, **not a fact about this binary**. Settling it needs the build's map file or an unstripped build, neither of which this project holds. Stated as unknown rather than resolved either way.
  - **Retracted — the string probe.** An earlier probe searched the shipped `ffmpeg.exe` for the literals `Europe/London` and `Indefinite time window` and found neither, which was read as evidence those objects were not linked. **That probe was incapable of returning a positive result and is retracted as evidence in either direction.** Both literals occur *only inside C comments* in `pdc.c` (lines 804, 994, 1382 and 1237, 1452). The preprocessor strips comments before compilation, so they could never appear in any binary whether or not the file was linked.
  - **Corrected 2026-08-09, after the binary was measured (REVIEW, app PR #139).** The "Established" and "Not established" statuses above have both moved, in opposite directions. `pdc.o` now has **positive evidence of absence**: three format strings in `pdc.c` that compile unconditionally — each verified to sit outside any preprocessor conditional, so this does not repeat the comment-string mistake retracted above — are all missing from the shipped `ffmpeg.exe`, while `libzvbi` appears 12 times in the same binary as a working control. Still evidence rather than proof: `--gc-sections` and LTO can strip an unreferenced function together with its constants. `packet-830.o` is **undeterminable by measurement** rather than established: nothing of it survives compilation to search for (no string literals; symbol names do not survive the strip either — even `vbi_decode`, certainly used, appears zero times), and no map file or unstripped build exists. It is treated as present on the strength of the source-level chain above, the conservative reading. **The measurement narrows the exposure and withdraws nothing** — the component ships, so its source stays published, and the Consequence bullet below stands. Method, controls and reproduction: `docs/release/evidence/ffmpeg/libzvbi-gpl2-linkage-measurement.md`.
  - **Consequence:** the GPL-2.0-only files carry no "or later", so **no v3 election and no GPL-3 §8 cure is available for them**. This component moves from the LGPL-family bucket to the GPL-family bucket.
- **`libgomp`** - Pulled in by --extra-libs=-lgomp, not by any --enable- flag, so it is invisible to a configure-line-only inventory. VERIFIED LINKED: 'GOMP_target_enter_exit_data' plus 36 distinct omp_* symbols in ffmpeg.exe. This is GPL-3 code inside an LGPL-3 binary; the GCC Runtime Library Exception is what makes that lawful, and it holds here because the build used GCC 15.2.0 (an Eligible Compilation Process). Worth stating explicitly so a later audit does not read it as GPL contamination.
- **`libgcc / libstdc++`** - Statically linked by the mingw-w64 toolchain. Same Runtime Library Exception reasoning as libgomp.
- **`winpthreads`** - Pulled in by --enable-pthreads on a mingw32 target. mingw-w64 runtime carries a mix of permissive licences by directory.
- **`mingw-w64 CRT`** - Standard mingw-w64 redistribution; attribution only.

## Open Gaps

- Upstream component VERSIONS are not recorded anywhere we hold. The FFmpeg configure line names components but not versions, and BtbN pins them in its own build scripts. Two classifications (libkvazaar, libzmq) are version-dependent, and a defensible SBOM needs the pinned versions regardless.
- ~~No corresponding source is currently mirrored for any of the 16 components carrying a source obligation. Only the FFmpeg source tarball itself is held.~~ **CLOSED 2026-08-09** — corresponding source for every obligated component (the 16 here plus the transitive `fftw3` and `libudfread`) is published at `https://app.ourgalaxy.space/source/`, each cut at its exact pinned commit. Commits and digests: `docs/release/evidence/corresponding-source-holding/HOLDING.json`.
- Static linkage means LGPL-2.1 sec.6 / LGPL-3 sec.4 relink provisions are engaged for each LGPL-family component, not merely source availability.
- Linkage could not be confirmed by symbol probe for chromaprint, libharfbuzz, libsnappy and libuavs3d. Only chromaprint materially matters (it is LGPL-family) and it is counted as present, which is the conservative direction. These four carry `linkage_confirmed: false` in the JSON beside this file so they can be found from the data rather than from this sentence.
- This notice is not yet folded into the deployed `third-party-notices/` surface — still true as of 2026-08-09: the live page names only the disclosure components (FFTW, chromaprint, libzvbi, libbluray), not this full enumeration. *(Updated 2026-08-09: this line also read "nothing here has been published to the live site", which the publication made false — the component archives and the FFTW/chromaprint/libudfread disclosure are live.)*
