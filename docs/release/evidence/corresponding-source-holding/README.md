# Corresponding source: resolution, capture and staging record

`HOLDING.json` in this directory is the machine-readable record. This file says
what it is for and what came out of producing it.

Produced by **RELEASE PIPELINE**, 2026-08-09, with
`tools/release/Get-CorrespondingSourceHolding.ps1` in the workspace repo.
Engineering provenance evidence. **Not legal advice, and not a compliance
claim.**

## Scope

The **18 components carrying a source-availability obligation** inside the
distributed Windows `ffmpeg.exe` / `ffprobe.exe`: 16 from
`../ffmpeg-components/THIRD_PARTY_LICENSES.ffmpeg-components.json` (14
LGPL-family, 2 MPL-2.0) plus the two transitive ones from
`../ffmpeg-components/TRANSITIVE_COMPONENTS.json` — `fftw3` (GPL-2.0-or-later,
via chromaprint's FFT backend) and `libudfread` (LGPL-2.1-or-later, via
libbluray).

Pins are read from
`../ffmpeg-shared-candidate/component-pins-SHIPPED-BUILD.json` — the build users
actually hold — and never from `component-pins.json`, which is the August
candidate and moves 41 of 57 components.

## What was done

1. **Every pin resolved and verified against upstream.** 18 of 18. Each pinned
   object was fetched from its own upstream and confirmed to be a reachable
   commit; the full 40-character SHA and the commit date are recorded.
2. **Licence text captured at the pinned commit** — not from the project's
   current default branch. A licence can change between revisions and the one
   that applies is the one that shipped. 27 texts, in
   `../license-sources/<component>/`, each named `<file>.at-<rev>.txt`.
3. **Source archived at the pinned commit** and published.

## Where the source is

**PUBLISHED 2026-08-09.** All 18 archives are live at
`https://app.ourgalaxy.space/source/`, beside the binaries, together with the
build definition recovered from the builder's commit history. Each digest was
verified against `HOLDING.json` after copying, and each URL confirmed live.

*Section updated 2026-08-09. It was headed "Where the source is, and why it is
not published yet" and said "Nothing has been published; publication is an
owner/OPERATIONS action." That was true when written; the owner action followed
the same day.*

The archives were staged at `Corresponding_Source/source/` in the workspace —
flat, and named the way `/source/` already names its archives, so publishing was
a copy rather than a conversion. **18 archives, 20.8 MB total.**

The destination is `/source/`, beside the binaries, rather than a private
holding answered on request. That follows S&C's clause-level verification
(`Matrix_Dev:docs/security/findings/SOURCE_OFFER_MODEL_CLAUSE_VERIFICATION_2026-08-09.md`):
GPL-3 §6(a) and §6(b), the written-offer routes, both open *"Convey the object
code in, or embodied in, a physical product"*. These binaries are downloads, so
those subsections are unavailable rather than merely unmet, and that binds
`ffmpeg.exe` itself as LGPL-3.0-or-later via `--enable-version3`. §6(d) —
*"equivalent access to the Corresponding Source in the same way through the same
place"* — is what remains, and on-request delivery is not equivalent access.
That is the route actually taken.

The staging directory is gitignored for size. That is only acceptable because
`HOLDING.json` is tracked: every archive is refetchable from the upstream URL
and commit SHA recorded there, and the digest says whether what came back is the
same source. Rebuild with `-Mode Fetch`, re-hash with `-Mode Verify`.

## Findings

### 1. The pins are snapshots, not releases — 16 of 17 git components

`fftw3` was already known to be pinned five commits ahead of the `fftw-3.3.11`
tag its binary self-reports. Running that check across the whole set shows it is
**the rule, not the exception**. Only `libsoxr` sits exactly on a release tag
(`0.1.3`). Every other git-pinned component is at a commit upstream never
tagged.

Consequence: for 16 of 18 components **there is no release tarball that is this
source**, and any process that reaches for one publishes something that was not
compiled.

### 2. Seven recorded version numbers do not identify the source

Eight components carry a version recovered from the shipped binary's own strings
and corroborated against the builder pin. That agreement is about the *version*.
It is not evidence that the pinned commit is that release, and for seven of the
eight it is not:

| Component | Recorded version | Distance from that release |
| --- | --- | --- |
| `libssh` | 0.12.0 | **145 commits ahead** — past 0.12.1 and 0.12.2 |
| `libbluray` | 1.4.1 | 20 commits ahead |
| `openal` | 1.25.2 | 5 commits ahead |
| `fftw3` | 3.3.11 | 5 commits ahead |
| `libfribidi` | 1.0.16 | 4 commits ahead |
| `libzvbi` | 0.2.44 | 4 commits ahead |
| `libplacebo` | v7.364.0 | **no such tag exists upstream** — highest is v7.360.1 |
| `libsoxr` | 0.1.3 | 0 — the pin *is* the release commit |

`libplacebo` is the sharpest case: `v7.364.0` is a build identifier the library
computes, not a release anyone can download.

This is now measured mechanically per run (`version_claim_check` in
`HOLDING.json`), so a future component set cannot quietly reintroduce it.

### 3. Licence text at the pinned commit contradicts the inventory — two components

Both are stated as textual observations. Neither is a legal conclusion.

**`libzvbi` — classified `LGPL-2.0-or-later`; the tree is multi-licensed and its
project default is GPL-2+.** `COPYING.md` at `41477c97c8ed`:

- project default: **GPL-2+**
- `src/*`: LGPL-2+  ← what the single-id classification reflects
- `src/dvb/dmx.h`, `src/dvb/frontend.h`: LGPL-2.1+
- **`src/packet-830.*`, `src/pdc.*`: GPL-2** — no "or later", inside `src/`
- `src/ure.*`: MIT; `src/videodev2k.h`: GPL-2+ or BSD-3-Clause;
  `src/strptime.*`: LGPL-2.1+

A GPL-2-**only** file admits no v3 election, so it would also have no access to
GPL-3 §8's cure provision.

**S&C answered this on 2026-08-09, and the answer is the opposite of what this
section originally said.** The paragraph below is retained struck, because the
way it was wrong is the reusable lesson:

> ~~**Whether those objects are in the shipped binary is a separate question and
> the evidence says probably not:** a string probe of `ffmpeg.exe` finds
> `libzvbi` 11 times but none of the distinctive literals in `pdc.c` or
> `packet-830.c` (`"Europe/London"`, `"Indefinite time window"`,
> `"Unallocated"`). Static linking pulls object files in only when referenced,
> and FFmpeg's teletext decoder does not use PDC. **That is evidence, not
> proof** — string probes are weak. Routed to S&C.~~

- **The probe is retracted as evidence in either direction.** Those literals
  occur only inside **C comments** in `pdc.c`, which the preprocessor strips.
  The probe could not have returned a hit whatever the truth was, so its null
  result carried no information. *General rule for linkage probes in this
  project: confirm the string is a string literal in the translation unit before
  the result means anything.*
- **`packet-830` IS established as reaching the executable.** It is in
  `libzvbi_la_SOURCES`, and the chain from
  `libavcodec/libzvbi-teletextdec.c` → `vbi_decode` → `src/vbi.c` →
  `src/packet.c` (`parse_8_30`) into two functions defined in `packet-830.c` is
  unconditional at link time. The `event_mask` tests along it are runtime
  guards, not link-time ones.
- **`pdc.o` is NOT established**, and cannot be from source alone under this
  stripped static link. Recorded as unknown rather than resolved either way.

**Corrected 2026-08-09 (REVIEW), after the shipped binary was measured — app PR
#139, merged as `c78cad2e`.** The two bullets above are retained as written;
both statuses have since moved, in opposite directions:

- **`pdc.o` now has positive evidence of absence**, superseding "Recorded as
  unknown rather than resolved either way." `pdc.c` carries three format
  strings that compile unconditionally — each verified to sit outside any
  preprocessor conditional, so this does not repeat the comment-string mistake
  retracted above — and **none of the three appears in the shipped
  `ffmpeg.exe`**, while `libzvbi` appears 12 times in the same binary as a
  working control. Still evidence rather than proof: `--gc-sections` and LTO
  can strip an unreferenced function together with its string constants.
  Method, controls, limits and reproduction:
  `../ffmpeg/libzvbi-gpl2-linkage-measurement.md`.
- **`packet-830.o` moved the other way — from "established" to undeterminable
  by measurement.** It has essentially no string literals that survive
  compilation, symbol names do not survive this stripped link (even
  `vbi_decode`, certainly used, appears zero times), and no map file or
  unstripped build exists. Its presence rests on the source-level call chain
  above and it is **treated as present**, which is the conservative reading.
- **The measurement narrows the exposure; it withdraws nothing.** The component
  ships, so its source stays published at `/source/`, and `libzvbi` remains the
  second GPL-family component in this record.

So `libzvbi` is a **second GPL component** in `ffmpeg.exe` alongside FFTW, and
unlike FFTW it has no "or later" to elect from. ~~Whether GPL-2.0-only and
GPL-3-family code may sit in one statically linked executable is a
licence-compatibility question deferred to an external review; nothing here
answers it.~~ **Corrected 2026-08-09: it was decided rather than deferred** —
accepted for the three releases that already shipped, removed going forward by
`--disable-libzvbi`. The struck sentence's caution stands: nothing here or
there is a legal conclusion — the question is closed as a decision about what
to do, not answered as law.

**`libbluray` — classified `LGPL-2.1-only`; the source says `LGPL-2.1-or-later`.**
`src/libbluray/bluray.c` at `4dfb9b0123b0`: *"either version 2.1 of the License,
or (at your option) any later version."*

This one has a direct consequence for work already done. The clause verification
singles libbluray out: *"`libbluray` is **LGPL-2.1-only**. It cannot be upgraded
to v3, so it has no access to any v3 mechanism, including the cure provision
discussed in §8."* If the source is 2.1-or-later, that premise does not hold and
the conclusion drawn from it should be revisited. **Routed to S&C.**

**S&C confirmed and closed this on 2026-08-09: `libbluray` is
LGPL-2.1-or-later.** The whole tree was scanned — **845 files carry the or-later
grant and none state 2.1 without it**. The only non-LGPL files are the
tri-licensed `jni/*.h` (LGPL-2.1-or-later electable) and `src/devtools/bdj_test.c`
(GPL-2.0-or-later, a devtool absent from the library build). The prior value came
from VideoLAN's description of its own project, recorded at high confidence; a
project's prose is a weaker authority than its licence headers. `libbluray` can
elect v3 and does have GPL-3 §8 cure, and the clause verification's contrary
conclusion is retracted there.

**Note on `HOLDING.json` itself:** its `licence_id_claimed` still reads
`LGPL-2.1-only` for `libbluray` and a bare `LGPL-2.0-or-later` for `libzvbi`.
That field is **generated** from
`docs/release/evidence/ffmpeg-components/THIRD_PARTY_LICENSES.ffmpeg-components.json`,
which carries both corrections. The JSON was deliberately not hand-edited: it
picks them up on its next regeneration, and hand-patching a generated field is
how the generator and the artefact drift apart. Read this README for the
classifications until then.

**Also worth recording, though not a contradiction:** `chromaprint` is
classified `LGPL-2.1-or-later`, and `LICENSE.md` at the pinned commit says its
own code is **MIT**, with the LGPL classification arising only from bundled
FFmpeg fragments — *"As a whole, Chromaprint should be therefore considered to be
licensed under the LGPL 2.1 license."* The text says "LGPL 2.1"; it does not say
"or later". The classification is defensible as the effective licence of the
whole, but it is `MIT AND LGPL-2.1`, and the "-or-later" is not supported by the
text.

### 4. `gmp`'s source comes from the builder's own mirror

`gmp` is pinned in `https://github.com/BtbN/gmplib.git`, not canonical GMP
(`gmplib.org`, Mercurial). The pinned commit is the right source — it is what was
compiled — but the upstream of record for this component is a build-farm mirror,
and mirrors can disappear the way the BtbN release tag did. The archive is
staged, so the source survives the mirror; the provenance caveat stands.

## Two components needed something other than a commit lookup

- **`libmp3lame`** is pinned to **SVN r6531**, not a git commit. Upstream LAME has
  never left SourceForge SVN; this machine has no `svn` and no `git svn`, and
  SourceForge's snapshot endpoint 404s for this project. The revision was
  exported from the canonical repository over HTTP DAV
  (`tools/release/svn_export_dav.py`), 329 files, with each file's last-changed
  revision recorded in `Corresponding_Source/provenance/`. An SVN revision is
  immutable and monotonic, which is the same guarantee a commit SHA gives — it
  is simply not one, and the record says so rather than substituting a
  third-party git mirror's SHA for source nobody compiled.
- **`gmp`** initially reported "no licence file". It ships `COPYINGv3` and
  `COPYING.LESSERv3`, which matched no enumerated suffix. The matcher was
  widened; gmp has three licence texts. Recorded because "no licence file found"
  on an LGPL-3.0 component is the worst possible way to be wrong.

## Still open

- **13 licence identifiers** for the FFmpeg bundle and **11** for libmpv remain
  uncollected, down from 17 and 12. All belong to **attribution-only**
  components, which are outside this pass's 18-component scope. The
  source-obligated families — where LGPL-2.1 §6 and LGPL-3 §4(b) require the text
  — are now covered by texts captured at each component's own pinned commit.
  libmpv's `uchardet` is the one obligated component still without a text; its
  version is unpinned, so there is no commit to capture from.
- ~~**Publication has not happened.** Owner/OPERATIONS action.~~ **CLOSED
  2026-08-09** — the owner/OPERATIONS action happened the same day; see "Where
  the source is" above. This bullet outlived the section it pointed at.
- The **relink limb** (LGPL-2.1 §6a / LGPL-3 §4(d)(0)) is untouched by this work
  and is not dischargeable by publishing source. See the clause verification, F5.
