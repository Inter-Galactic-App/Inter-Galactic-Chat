# Component-set diff: shared candidate vs the shipped build

Captured by RELEASE PIPELINE, 2026-08-09. Engineering provenance, **not legal advice**.
Licence classification is S&C's, in `docs/release/evidence/ffmpeg-components/`, which this
capture read and did not modify.

## What is being compared

| | Shipped (staged today) | Shared candidate |
| --- | --- | --- |
| BtbN release | `autobuild-2026-06-13-13-31` (**pruned upstream**) | `autobuild-2026-08-09-13-03` |
| Variant | `win64-lgpl` (static) | `win64-lgpl-shared` |
| FFmpeg revision | `83e8541aa601935a610b1b8958d56e8d0331318b` | `9b6c8969e05b4f0b29f0f85cd501be6b3e582e6b` |
| Version string | `n8.1.1-13-g83e8541aa6-20260613` | `n8.1.2-34-g9b6c8969e0-20260809` |
| Builder commit | `a9410e4be2b3` (inferred from timestamps) | `2437e7b868da3c11872367b15f3c613b87c24819` (**from the tag object**) |
| Components enabled | 58 | 57 |

Both configure lines were compared flag-by-flag. The shipped line is
`docs/release/evidence/ffmpeg/BUILD-CONFIGURATION.txt`; the candidate's is
`BUILD-CONFIGURATION.txt` beside this file.

## The diff, in full

**Components added: none.**

**Components removed: one.**

| Component | Change |
| --- | --- |
| `whisper` | `--enable-whisper` → `--disable-whisper` |

**Non-component flag changes (the variant switch itself):**

| Flag | Change |
| --- | --- |
| `--enable-shared` | added |
| `--disable-static` | added |

Nothing else moved. Every other one of the 57 components is enabled in both builds with the
same flag.

### What the `whisper` removal means for the inventory

`docs/release/evidence/ffmpeg-components/` enumerates **58** components and asserts that count
against the shipped configure line, failing if the two disagree. A shared swap would make that
assertion fail — correctly — because the candidate has 57. `whisper` (whisper.cpp) drops out of
the set that carries a source obligation.

This is a mechanical consequence of the diff, not a proposal. **S&C owns that inventory**; the
regeneration is theirs to run against whatever build is finally staged, not something to
pre-apply from here.

## Finding: FFTW reaches the shipped binary and the configure line does not say so

This is the substantive result of recovering the build definition, and it is **not** a
consequence of the shared variant — it is equally true of the binary already published.

Measured, in this order:

1. `scripts.d/50-chromaprint.sh` at builder commit `2437e7b8` builds chromaprint with
   `-DFFT_LIB=fftw3` and declares `ffbuild_depends() { echo base; echo fftw3; }`.
2. `scripts.d/25-fftw3.sh` pins `https://github.com/FFTW/fftw3.git` at
   `93ed4c786934aec9946f8dda4b4e3eb08f8be41c`, configured `--disable-shared --enable-static`.
3. Byte-scanning the candidate archive's DLLs for `fftw_` / `fftwf_` symbol names:
   **`avformat-62.dll` — 1015 matches.** No other library in the archive carries any.
4. Byte-scanning the **currently staged, already-published** static
   `intergalactic/windows/third_party/ffmpeg/bin/ffmpeg.exe`: **1015 matches**, the same count.

So FFTW is statically present in the binary that shipped, and would be statically present in the
shared one, reaching it through chromaprint rather than through any FFmpeg configure flag.

Why it was not visible before: FFmpeg's own `EXTERNAL_LIBRARY_GPL_LIST` does not contain
`chromaprint` (chromaprint itself is LGPL-2.1+ and can be built against a non-GPL FFT), so
`configure` had no reason to demand `--enable-gpl`, and the "0 GPL-only components" headline in
the current inventory follows correctly from the evidence that inventory had. The FFT backend is
a **builder** decision, invisible in the configure line and only recoverable from the build
scripts — which is precisely the artefact that was lost for the shipped build and is now held.

FFTW is distributed by its authors under GPL-2.0-or-later. **What that implies for a binary
distributed under an LGPL claim is a judgement this lane does not make.** Routed to S&C and
REVIEW on integration-queue row *"Desktop Native Third-Party Notices And AGPL Source Chain"*.

Two things worth stating plainly so nobody over- or under-reacts:

- It is **not a regression introduced by the shared variant**. Switching variants neither creates
  nor removes it.
- It is **not evidence that the previous analysis was careless**. It was unreachable without the
  build scripts, and getting the build scripts back is what this task was for.

## Carried forward from the existing inventory, re-measured here

- `sdl2` is enabled on the configure line but serves `ffplay.exe` only. Re-probed on the
  candidate: **474 `SDL_*` matches in `ffplay.exe`, zero in every other binary.** The existing
  inventory's finding holds on the shared build too, and this project ships neither `ffplay.exe`
  nor `ffprobe.exe`.
- Of the four components the existing inventory could not confirm by symbol probe
  (`chromaprint`, `libharfbuzz`, `libsnappy`, `libuavs3d`), `chromaprint` is now confirmed
  present in `avformat-62.dll` by its FFTW dependency chain. The other three remain unconfirmed
  by this method; absence of a symbol name is not absence of the library, and no attempt was made
  here to settle them.

## Gaps this capture does **not** close

- **Component *licences* for the shared candidate were not re-derived.** Only versions and repos.
  The 57 pins are in `component-pins.json`; mapping them to licences is S&C's inventory work.
- **No corresponding source is mirrored for any of the 57 components.** The pins make that
  possible for the first time; they do not do it.
- **Component pins were not verified against the built artefact.** They are what the builder
  scripts declare at the recorded commit. Nothing here proves the container that produced the
  release used exactly those commits — that is BtbN's build environment, not observable from the
  archive.
