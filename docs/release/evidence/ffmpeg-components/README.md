# FFmpeg Bundled Component Licence Inventory

Prepared by S&C, 2026-08-07. Promoted from scratch into tracked release evidence on
2026-08-08 by S&C at REVIEW's placement direction. This is engineering licence/provenance
evidence, not legal advice, and it does not by itself close any source-offer gate.

Nothing here has been published to the live site. Publication of the per-component
corresponding source remains open — see "What this does not close".

## What this covers

`docs/release/evidence/ffmpeg/` treats the bundled Windows tool pair as one artifact
(`LGPL-3.0-or-later`). It does not enumerate what is compiled **inside** those binaries.
FFmpeg's own License Compliance Checklist requires the checklist items to be walked again for
every LGPL external library compiled in — which makes the inside of the binary in scope, not
just the binary. This directory is that enumeration.

## Files

| File | Purpose |
| --- | --- |
| `THIRD_PARTY_LICENSES.ffmpeg-components.json` | Structured inventory. Matches the shape used by `docs/release/evidence/android-gradle/<version>/THIRD_PARTY_LICENSES.android-gradle.json`. |
| `THIRD_PARTY_NOTICES.ffmpeg-components.md` | User-facing notice text. Matches the shape of `THIRD_PARTY_NOTICES.android-gradle.md`. Not yet folded into the deployed `third-party-notices/` surface. |
| `ffmpeg-configure-license-lists.md` | FFmpeg `configure`'s own GPL / non-free / version3 / GPLv3 buckets, extracted from the shipped revision. This is the authority behind the "no GPL-only component is enabled" finding. |
| `TRANSITIVE_COMPONENTS.json` | The layer **beneath** the inventory: the 20 components inside the binary that the configure line cannot name. Carries per-component detection markers a release gate can test. |
| `TRANSITIVE_METHOD.md` | How that layer is enumerated, where the two routes disagreed, and what neither route can see. Read it before trusting either file's completeness. |

FFmpeg's own `LICENSE.md` at the shipped revision is filed with the component it belongs to,
under the established `LICENSE*` convention:
`docs/release/evidence/license-sources/ffmpeg/LICENSE-FFmpeg.md`. It is reusable verbatim for
the FFmpeg portion and carries the IJG credit obligation.

## How the component list was derived

Parsed the `configuration:` line captured from the exact shipped binary
(`docs/release/evidence/ffmpeg/ffmpeg-version.txt`). 62 `--enable-` flags, minus four
non-component switches (`version3`, `pthreads`, `cuda-llvm`, `schannel`), gives **58**
third-party components. The generator asserts this reconciliation and fails if the configure
line and the classification table ever disagree, so the count cannot silently drift.

Both staged binaries were re-hashed against `manifest.json` before use (SHA-256 match on
`ffmpeg.exe` and `ffprobe.exe`) and probed for per-component symbols, so linkage claims are
measured rather than inferred from the configure line alone.

## This derivation is exact for its scope and blind one level down

Read this before quoting the headline below.

A library that arrives as a **dependency of an enabled component** has no
`--enable-` flag of its own. There is nothing on the configure line to parse and
nothing in `configure`'s GPL list to match, because that list is keyed on FFmpeg's
own flag names. So the method above cannot see it — not through oversight, but by
construction.

That is how **FFTW (GPL-2.0-or-later)** turned out to be statically compiled into
this binary: FFmpeg enables chromaprint (LGPL-2.1) and BtbN builds chromaprint with
`-DFFT_LIB=fftw3`. Chromaprint is not the GPL part; its FFT backend is.
**`libudfread` (LGPL-2.1-or-later, via libbluray)** surfaced the same way.

Two instances made it a class, so the layer is now enumerated deliberately, by two
independent methods, in `TRANSITIVE_COMPONENTS.json` and `TRANSITIVE_METHOD.md`.
**Twenty** transitive components, twelve of which had never been recorded anywhere.
Re-run the pass with `workspace:tools/release/Get-FfmpegTransitiveComponents.ps1`;
41 of 57 shared components moved between two BtbN releases two months apart, so this
is not a one-time answer.

## Headline

The four numbers below are **correct for the configure line and silent about the
layer beneath it.** The transitive pass did not move any of them — all twelve newly
found components are attribution-only, and the only two transitive components
carrying a source obligation (`fftw3`, `libudfread`) were already known. What the
pass changes is the completeness claim, not the counts.

- **0** GPL-only or non-free components **among the 58 the configure line names**.
  Not "no GPL code in the binary": FFTW is GPL-2.0-or-later and is in there, one
  level down. Never quote this bullet without that clause.
- **16 of 58** carry a source-availability obligation (14 LGPL-family + 2 MPL-2.0).
  Two more sit in the transitive layer: `fftw3` and `libudfread`.
- `--enable-version3` is load-bearing, not decorative: four enabled components require it.
- Two credit obligations must appear in documentation: the Independent JPEG Group, and FreeType.

## Scope note — `ffprobe.exe` is named here on purpose

The inventory's `applies_to.binaries` names both `ffmpeg.exe` and `ffprobe.exe`.
`ffprobe.exe` was removed from the desktop payload by app PR #101, but every public release
through `0.8.0+993` shipped it, and the source-availability obligation runs to the recipients
of those builds. **Do not "tidy" `ffprobe.exe` out of this evidence.** The two executables are
byte-identical in provenance and configure line, so the component list is the same for both.

## What this does not close

Four gaps are recorded in `open_gaps` in the JSON and repeated in the notice. Summarised:

1. Upstream component **versions** are not recorded anywhere the project holds. BtbN pins them
   in its own build scripts; two classifications (`libkvazaar`, `libzmq`) are version-dependent.
2. **No corresponding source is mirrored for any of the 16 components** carrying a source
   obligation. Only the FFmpeg source tarball itself is held and published.
3. Static linkage engages the LGPL-2.1 §6 / LGPL-3 §4 **relink** provisions per LGPL-family
   component, not merely source availability.
4. Linkage could not be confirmed by symbol probe for **`chromaprint`, `libharfbuzz`,
   `libsnappy` and `libuavs3d`**. Only `chromaprint` materially matters (it is LGPL-family) and
   it is counted as present, which is the conservative direction.

Item 4 is the set of four entries that earlier notes referred to loosely as "needs-review".
They are named here and carry `linkage_confirmed: false` in the JSON so they can be found
rather than inferred.

`sdl2` is enabled on the configure line but is **not linked** into the shipped binaries
(zero `SDL_*` symbols in either executable; SDL2 serves `ffplay.exe`, which this project does
not ship). It is retained in the inventory with that evidence and should be excluded from the
user-facing notice.
