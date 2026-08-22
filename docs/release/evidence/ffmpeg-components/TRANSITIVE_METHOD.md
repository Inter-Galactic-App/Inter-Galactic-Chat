# How the transitive component pass works, and where it stops seeing

S&C / REVIEW, 2026-08-09. Engineering licence and provenance evidence.
**Not legal advice. Makes no claim about legal sufficiency, and a clean run
closes no compliance gate.**

Companion data: `TRANSITIVE_COMPONENTS.json`.
Re-run it: `workspace:tools/release/Get-FfmpegTransitiveComponents.ps1`.

## Why a second method was needed

The inventory in this directory enumerates the 58 components FFmpeg's
`configuration:` line names, and cross-checks the licence classes against
FFmpeg `configure`'s own `EXTERNAL_LIBRARY_GPL_LIST`. That is a rigorous check
and it is **blind by construction**, for a reason worth stating precisely:

> A library that arrives as a dependency of an enabled component has no
> `--enable-` flag of its own. There is nothing on the configure line to parse,
> and nothing in `configure`'s GPL list to match, because the list is keyed on
> FFmpeg's own flag names.

That blindness is not hypothetical. **FFTW is GPL-2.0-or-later and is
statically compiled into the `ffmpeg.exe` users already hold.** It arrives
because FFmpeg enables chromaprint (LGPL-2.1) and BtbN builds chromaprint with
`-DFFT_LIB=fftw3`. Chromaprint is not the GPL part; its FFT backend is, and
`configure`'s GPL list has no chromaprint entry because chromaprint itself is
not GPL. **`libudfread` (LGPL-2.1-or-later, via libbluray)** surfaced the same
way days later.

Two instances is a class, not an incident. Hence a method, not two patches.

## The two routes

They are run together because **they find different things**, and the clearest
proof of that is in the results: route 1 found `mbedtls`, which leaves almost no
trace in the artefact; route 2 found `graphengine`, which no pin file names.

### Route 1 — the builder dependency graph

BtbN's build is a graph of shell stages under `scripts.d/`. Each stage declares
`ffbuild_depends` (what it needs) and `ffbuild_enabled` (whether it applies to
this target, variant and FFmpeg version). `generate.sh` walks that graph from
`scripts.d/zz-final.sh` and builds every enabled stage it reaches.

The distinction that matters:

| A stage that emits… | Becomes |
| --- | --- |
| an `ffbuild_configure` flag | a component on the FFmpeg configure line — visible to the existing inventory |
| **no** configure flag | a library built into the same prefix and linked through its dependents — **invisible to the configure line** |

The pass reproduces that walk for `TARGET=win64 VARIANT=lgpl ADDIN=8.1`
(`ffver` 801) at builder commit `a9410e4be2b3`, and reports the second row.

Two details a reader will otherwise trip over:

- **Directory stages carry the grouping, not per-library dependencies.** In
  `scripts.d/50-librist/`, both `40-mbedtls.sh` and `50-librist.sh` declare only
  `base`. The fact that mbedtls is librist's dependency is expressed by them
  living in the same directory. Any analysis that reads `ffbuild_depends` alone
  — which is what the recovered pins recorded — sees a flat list and misses
  every grouped dependency. That is precisely why the recovered pins captured
  nine transitive components and not twenty.
- **"Transitive" is a property of the build, not of the project.**
  `scripts.d/25-openssl.sh` opens its `ffbuild_configure` with
  `[[ $TARGET == win* ]] && return 0`. On Windows OpenSSL is built, linked, and
  absent from the configure line. On Linux the same component is
  configure-named. Nothing about OpenSSL changed; the target did.

**The scripts are parsed, never sourced or executed.** The script throws on any
`ffbuild_enabled` shape it does not recognise, so a future builder change
surfaces as an error rather than a silently wrong answer.

### Route 2 — the artefact string probe

Search the shipped binary for markers only that component's own code emits:
vendor banners, assert source-file names, diagnostic format strings, mangled C++
symbol names. This is the route that caught FFTW, through its wisdom-export
format string `(fftw-3.3.11 fftw_wisdom `.

Every marker used is recorded per component in `TRANSITIVE_COMPONENTS.json`
under `detection_markers.byte_strings`, so the probe is repeatable and **a
release gate can test exactly the strings this analysis tested** rather than
re-inventing them.

## Where the two routes disagreed

Recorded rather than resolved, in every case.

| Component | Route 1 | Route 2 | Reading |
| --- | --- | --- | --- |
| `serd`, `sord`, `sratom`, `zix` | built as lilv dependencies | no marker | lilv itself is confirmed linked (26 `lilv_`, 48 `lv2plug.in` URIs) and cannot function without them. Small stripped C libraries with no diagnostics. Probably present, unprovable by probe. |
| `mbedtls` | built; librist links it for its CSPRNG | only librist's own error message *naming* the API | evidences the caller, not the callee. Left as route-1-only. |
| `libsamplerate` | built | no marker | its only path in is SDL2, and SDL2 is independently recorded as **not linked** (zero `SDL_*`; SDL2 serves `ffplay.exe`, which this project does not ship). Here route 2 is probably right and route 1 over-reports. |
| `spirv-cross` | built in the vulkan stage | no marker | libplacebo was configured against shaderc. Most likely built and not linked. |
| `graphengine` | invisible — route 1 could only see that zimg fetches submodules | **18 mangled C++ symbols** | route 2 alone found it; the pin was then recovered from zimg's `.gitmodules` at the build revision. |
| `ggml` | invisible for the same reason | 494 matches | already acknowledged in the inventory's prose; measured here. |

## What neither route can do

Stated as limits because a named gap is worth more than a confident guess.

1. **Route 1 reports what the scripts declared, at an inferred commit.**
   `a9410e4be2b3` is the last builder commit before the build with zero commits
   in between — tight inference, not proof. The artefact that would prove it,
   the release tag, was pruned by BtbN.
2. **Route 1 cannot know what the linker kept.** Under `--gc-sections`, LTO and
   stripping, an archive can be built into the prefix and contribute nothing.
3. **Route 2 cannot prove absence.** A stripped C library with no diagnostics
   leaves no marker even when fully linked. Header-only code leaves none by
   definition. *Absence of a symbol is not evidence of absence.*
4. **Route 2 cannot prove presence unaided.** `ffmpeg.exe` embeds its whole
   configure line and FFmpeg's help text, so `libdrm`, `openssl` and `vorbis`
   all occur as **text about** components rather than as code from them. Worse,
   Brotli's built-in text dictionary contains the English word *highway*, which
   is the single "highway" hit in the binary — a false positive that a naive
   substring gate would have accepted. Every `present` verdict recorded here
   rests on a marker FFmpeg's own text does not contain, with the raw counts
   kept beside it so the distinction stays auditable.
5. **Level 3 is only partly mapped.** Five enabled scripts fetch git submodules
   recursively; that vendored code is pinned by git, not by BtbN, and appears in
   no project record. Three were identified (`graphengine`, `ggml`, `highway`);
   libplacebo's, mbedtls's and openssl's submodule sets are named as unresolved
   with the reason, in `level_3_vendored_dependencies.unresolved`.
6. **Level 4 and below were not attempted at all.** A vendored submodule may
   itself vendor. The depth here is bounded by effort, not by evidence, and
   pretending otherwise would be the actual defect.

## What the pass found

Twenty transitive components, against nine previously recorded.

- **Twelve new**, all attribution-only: `libpng`, `brotli`, `lcms2`, `mbedtls`,
  `lv2`, `serd`, `sord`, `sratom`, `zix`, `vulkan-headers`, `spirv-cross`,
  `spirv-headers`. Licences were read from the upstream licence file **at the
  pinned revision** for eleven of the twelve — a higher bar than the surrounding
  evidence, most of which is `classification_confidence: low`.
- **One recorded component is not in this build.** `xorg-macros` is guarded by
  `[[ $TARGET != linux* ]] && return -1`. The base stage declares it, which is
  presumably how it was captured, but a declared dependency on a disabled stage
  builds nothing.
- **`mbedtls` is the entry most likely to be misread.** It is offered under
  `Apache-2.0 OR GPL-2.0-or-later` — the recipient elects, and electing
  Apache-2.0 leaves attribution only. It is **not** a second FFTW. It is named
  anyway because an automated scan will surface a GPL-family grant inside an
  LGPL binary and someone will have to answer for it, because `mbedtls` sits on
  FFmpeg configure's `EXTERNAL_LIBRARY_VERSION3_LIST` and a reader checking that
  list will wrongly conclude it cannot be here, and because the election should
  be recorded deliberately rather than left implicit. **A copyleft gate must not
  fail on `mbedtls` alone.**
- **A provenance correction to the inventory.** The `vulkan` entry names
  "Khronos Vulkan-Headers / Vulkan-Loader, Apache-2.0". The loader actually
  linked is BtbN's own `Vulkan-Shim-Loader`, **MIT, Copyright 2025 Timo
  Rothenpieler**. No obligation changes; the attribution text is wrong.

## Effect on the headline

**The headline does not change, and that is a result rather than a null one.**

58 components / 42 attribution-only / 16 with a source obligation / 0 GPL-only
all still hold **for the scope that headline describes** — the configure line.
All twelve newly found components are attribution-only, so nothing moves.

What changes is the completeness claim beneath it. The transitive layer is
twenty components rather than nine; one of the nine is not in this build; and
the only two transitive components carrying a source-availability obligation
(`fftw3`, `libudfread`) were **already known before this pass**.

Said plainly: the method was blind, the blindness was real and is now measured,
and on this particular build it happened to be hiding nothing new that carries
an obligation. The next build is a different question — 41 of 57 shared
components moved between two BtbN releases two months apart, which is why this
is a script and not a one-time analysis.
