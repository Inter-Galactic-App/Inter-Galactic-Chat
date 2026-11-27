# Is libzvbi's GPL-2.0-only code actually in the shipped `ffmpeg.exe`?

Measured by REVIEW, 2026-08-09. **This records a measurement of the binary. It
draws no licence conclusion** — that is S&C's, and the two questions are
deliberately kept apart.

## Why the question exists

`libzvbi` is LGPL-2.0-or-later as a project, but its tree is per-file mixed.
`COPYING.md` at the pinned commit `41477c97c8edf7a01f1594b2a95b94f0117eed21`
states verbatim:

> The files src/packet-830.\* and src/pdc.\* have the following copyright and
> license: License: GPL-2

Four files, and their headers say *"the GNU General Public License version 2"*
with **no "or later"** — so no v3 election and no GPL-3 §8 cure for them.

**That the files are GPL-2-only is settled.** What was never measured is whether
their compiled code is in the binary we distribute. The obligation follows
distribution of the code, not use of the feature, so this is the question that
decides the exposure.

## What was already established, and by what

| Object | Status before this measurement | How |
| --- | --- | --- |
| `packet-830.o` | Believed linked | Source-level link chain: FFmpeg's `libzvbi-teletextdec.c:679` → `vbi.c:472` → `packet.c:2686` → `packet.c:2146/2165`, which call functions defined in `packet-830.c`. The guards on that path are runtime `event_mask` tests, not link-time. |
| `pdc.o` | **Unknown** | No cross-translation-unit reference to any `pdc.c` symbol was found. Settling it was said to need a map file or an unstripped build. |

A prior string probe was **retracted as evidence in either direction**: both
literals it searched for (`Europe/London`, `Indefinite time window`) occur only
inside C comments, which the preprocessor strips, so it could never have
returned a hit.

## This measurement

The retraction above applies to *comments*. It does not apply to string literals
in code, which do survive compilation. `pdc.c` has three distinctive format
strings, and each was checked to sit **outside any `#if`/`#ifdef`** — so they
compile unconditionally whenever `pdc.c` is compiled:

```
 luf=%u mi=%u prf=%u
%05x (%02u-%02u %02u:%02u)
pcs=%s pty=%02x tape_delayed=%u
```

Searching the shipped `ffmpeg.exe`
(`C5C6E92D80884470A4D09C80A801989757DB1E80837E5018B636AF76DD826FEC`):

| | Result |
| --- | --- |
| `pdc.c` unconditional code literals found | **0 of 3** |
| Control — `libzvbi` string in the same binary | **12 occurrences** |

The control matters: it shows the search works and that libzvbi is genuinely
present in the binary. The absence is therefore about `pdc.o` specifically, not
about the probe failing.

**Reading: `pdc.o` appears NOT to be linked.**

## Limits — this is evidence, not proof

- **`--gc-sections` and LTO can strip unreferenced functions along with their
  string constants.** If `pdc.o` were linked but nothing referenced it, these
  literals could be removed. Absence of a symbol is not evidence of absence
  under this toolchain — a trap already recorded in this project's libmpv work,
  and it applies here too.
- **`packet-830.c` cannot be measured this way at all.** It contains essentially
  no string literals that survive compilation, so a negative result would carry
  no information. Its linkage still rests on the source-level call chain above,
  which is reasoning about source rather than measurement of the artefact.
- A map file or an unstripped build would settle both definitively. Neither
  exists for this binary.

## What this changes

The exposure is **narrower than the record implied**, but not eliminated:

- `pdc.o` — positive evidence of absence, from unconditional literals with a
  working control.
- `packet-830.o` — still inferred present, and still the reason libzvbi is
  carried as a GPL-family component.

Nothing here reduces what has already been published. Corresponding source for
`libzvbi` is live at `/source/` regardless, which is the correct posture: the
component ships, so the source ships, and whether one object file inside it was
garbage-collected does not change that.

**The forward fix does not depend on resolving this.** Nothing in this
application uses teletext decoding — the only `zvbi` reference anywhere in
`lib/` is the licence notice itself — so `--disable-libzvbi` in a narrower build
removes the component, the question, and the obligation together.

## Reproducing

Extract `pdc.c` from the published archive
`https://app.ourgalaxy.space/source/libzvbi-g41477c97c8ed-source.tar.gz`, strip
comments, take string literals of 10+ characters, confirm each is outside any
preprocessor conditional, and search the staged `ffmpeg.exe` for them as bytes.
Use the `libzvbi` string itself as a positive control — a run that cannot find
the control proves nothing about the rest.
