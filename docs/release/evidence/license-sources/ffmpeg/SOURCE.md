# FFmpeg Corresponding Source Evidence

Status: SOURCE RECOVERED, VERIFIED AND **PUBLISHED**

*Status line updated 2026-08-09. It read "PUBLICATION PENDING". FFmpeg's own
source was published 2026-08-07; all 18 obligated components and the build
definition followed on 2026-08-09, under GPL-3 §6(d) — equivalent access from the
same place as the binary, which for a downloaded binary is the only available
route.*

Recorded by REVIEW on 2026-08-06 at the maintainer's direction, after the
upstream provenance recorded in `docs/release/evidence/ffmpeg/manifest.json` was
found to be **dead**. This file is engineering licence/provenance evidence, not
legal advice, and it does not by itself close the source-offer gate — see
"What is still outstanding".

## Why this file exists

`docs/release/evidence/ffmpeg/manifest.json` records the bundled Windows
`ffmpeg.exe`/`ffprobe.exe` as coming from a BtbN autobuild release. **That
release no longer exists.** Verified 2026-08-06:

| Check | Result |
|---|---|
| `GET /repos/BtbN/FFmpeg-Builds/releases/tags/autobuild-2026-06-13-13-31` | **404** |
| `GET` the exact `asset_url` recorded in the manifest | **HTTP 404** |
| `GET /repos/BtbN/FFmpeg-Builds` | 200, repository alive and pushing daily |

BtbN prunes its autobuild releases. The repository is healthy; that particular
release is simply not retained. A 2026-08-06 S&C review listed "if BtbN deletes
the release, the obligation survives and the artefact does not" as a *risk* —
it had already happened.

The consequence is the point: the binary shipping in every Windows desktop
release could no longer be re-obtained or independently verified from its own
recorded provenance, while the LGPL source-availability obligation continued to
apply. This file closes the recoverable half of that.

## The shipped binaries are recovered and byte-verified

Recovered from local copies and hashed against the values recorded in
`manifest.json`. **All six comparisons matched**, so what is held is provably the
artefact that shipped, not a lookalike rebuild:

| File | SHA-256 (recorded, and confirmed) | Size |
|---|---|---|
| `ffmpeg.exe` | `C5C6E92D80884470A4D09C80A801989757DB1E80837E5018B636AF76DD826FEC` | 173,416,960 |
| `ffprobe.exe` | `134B9BC17D0FE3B1F81ECA108615356F4C304C58C7750CE85592E8CFDBB3F523` | 173,210,624 |

Copies were verified in the staged
`intergalactic/windows/third_party/ffmpeg/bin/`, the `sb` build checkout, and the
desktop payloads of both public releases that contain the tools —
`Desktop_Builds/Inter-Galactic/0.8.0+993/` and `.../0.8.0+992/`.

**The binaries are NOT published as a separate download, and are not meant to
be.** An earlier draft of this line said they were staged for publication under
a `dist/` path. That staging area is gitignored and swept, and the directory was
never served - verified 2026-08-19, it returns 404. The binaries are conveyed
inside the application payload, which is precisely what `ffmpeg.org/legal.html`
asks the source to be hosted alongside. What durably identifies them is the
SHA-256 pair in the table above, confirmed against both public release payloads.

**The binary is byte-identical across every build that contains it**, public and
local: `0.8.0+992`, the `0.8.0+993` hotfix, and the unreleased local `0.8.1`
builds all carry the same two hashes. So the source recovered below is the
Corresponding Source for the binary that was actually distributed to the public,
not merely for a local build. `0.8.0+993` is the last public release; no `0.8.1`
build has been released, and earlier drafts of this file wrongly cited the local
`0.8.1+1001` payload as shipped.

## The Corresponding Source is recovered and verified

Upstream FFmpeg is unaffected by BtbN's pruning — the commit is still available.

- Revision: `83e8541aa601935a610b1b8958d56e8d0331318b`
- Committed: 2026-06-12T13:07:35Z ("forgejo/workflows: update test workflow for
  8.1 release")
- Version string recorded for the binary: `n8.1.1-13-g83e8541aa6-20260613`
- Upstream repository: `https://git.ffmpeg.org/ffmpeg.git`
- GitHub mirror commit:
  `https://github.com/FFmpeg/FFmpeg/commit/83e8541aa601935a610b1b8958d56e8d0331318b`

Archive obtained 2026-08-06 from
`https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/83e8541aa601935a610b1b8958d56e8d0331318b`:

- Filename: `ffmpeg-n8.1.1-13-g83e8541aa6-source.tar.gz`
- Size: 16,878,631 bytes
- **SHA-256: `E1F42BA0646F50C7C6F8761ADCC05933F71D70FF131DA0F80CFC0E449199B4F5`**

Verified rather than assumed: valid gzip magic, 10,252 entries, root
`FFmpeg-83e8541aa601935a610b1b8958d56e8d0331318b/`, and the tree contains
`configure`, `COPYING.LGPLv2.1`, `COPYING.LGPLv3` and `libavcodec/version.h`. The
archive's own `RELEASE` file reads `8.1.1`, matching the recorded version string.

**Published** at
`https://app.ourgalaxy.space/source/ffmpeg-n8.1.1-13-g83e8541aa6-source.tar.gz`.
Re-verified live 2026-08-19: HTTP 200 with `Content-Length: 16,878,631`, which
matches the recorded size above byte for byte, so the copy being served is the
archive whose SHA-256 is recorded here. This line previously cited the `dist/`
staging path, which is gitignored and swept; the durable location is the
published URL, and the digest above is what proves the two are the same file.

## What is still outstanding

1. **Publication — DONE 2026-08-07.** The Corresponding Source is live and
   verified on the host, alongside the binaries it corresponds to, which is what
   `ffmpeg.org/legal.html` asks for ("Host the FFmpeg source code on the same
   webserver as the binary you are distributing"):

   | File | Live | Type |
   |---|---|---|
   | `/source/ffmpeg-n8.1.1-13-g83e8541aa6-source.tar.gz` | 16,878,631 bytes | `application/gzip` |
   | `/source/ffmpeg-BUILD-CONFIGURATION.txt` | | `text/plain` |
   | `/source/ffmpeg-LICENSE-LGPL-3.0.txt` | | `text/plain` |

   Hash re-verified after the copy: `E1F42BA0…99B4F5`, unchanged.

   **The archive was deliberately not repacked.** Upstream's checklist suggests
   putting the configure line in a text file *inside* the source root, which
   would mean rebuilding the tarball and destroying the one property that makes
   it independently checkable: it is byte-for-byte upstream's own export, so
   anyone can re-download from FFmpeg and compare hashes without trusting this
   server. The build configuration is published as a sibling file instead, which
   serves the same purpose — explaining how it was compiled — without giving up
   verifiability. It also records the binaries' hashes, the revision, the
   licence reasoning, and the builder's commit, so it stands alone.

2. **`SOURCE_OFFER.md` does not mention FFmpeg at all.** It covers the app's own
   AGPL source. The LGPL offer for the bundled FFmpeg tools needs its own entry
   pointing at the published source and the hash above.

3. **The notices are missing from every user-facing surface** — measured
   2026-08-07: zero FFmpeg mentions on `/download/`, on `/source/`, in the app's
   about box, or in the published terms. See the checklist mapping below.

   > **Re-measured 2026-08-15 by S&C — three of those four have changed, one has
   > not, and "every" is no longer accurate.** Live, browser UA, against a
   > negative control (a bogus component name returns 0) and a positive control
   > on `/terms/` (`licen` × 8, so the fetch is real):
   >
   > | Surface | 2026-08-07 | 2026-08-15 |
   > | --- | --- | --- |
   > | `/source/` | zero | **116** `ffmpeg` (51 `FFmpeg`, 8 `n8.1.1`) |
   > | `/download/` | zero | **5** `ffmpeg` (3 `FFmpeg`) |
   > | App about box | absent | **present** — `NativeLicenses.register()` runs immediately before `showLicensePage` (`settings_category_about.dart:108-109`) |
   > | Published terms | zero | **still zero** |
   >
   > **This refreshes the evidence and does not by itself close anything.** A
   > mention is not a notice: counting the string "FFmpeg" cannot establish that
   > the wording present is the wording required, and that judgement needs
   > someone to read the pages. The about-box row in the checklist below *is*
   > marked Met, because that one was verified at the call site rather than by
   > string count. The bullet is left standing above because it is accurate about
   > 2026-08-07; only its currency has expired.

### Route drift found while correcting this file, 2026-08-06

Recorded here because it was measured during this work and it determines where
the FFmpeg offer must point. It is an AGPL/app-source issue, not an FFmpeg one,
and it is tracked separately in the integration queue.

The source route has moved to version tags on the public GitHub mirror, but
neither the tags nor the website have followed the shipped builds:

| Check | Result |
|---|---|
| Public release actually shipped | `0.8.0+993` (desktop hotfix of `+992`) |
| Tags on the public mirror | **`v0.8.0+992` only** — no `+993` tag |
| Tags on `forgejo` | **none** for 0.8.x |
| `docs/policies/SOURCE_OFFER.md` says current | `0.7.4+985` / tag `v0.7.4+986` |
| `https://app.ourgalaxy.space/source/` | **HTTP 200, live**, still presenting itself as the source page |
| The archive that page serves | **HTTP 200, a real 165,545,020-byte zip** of `0.7.4+985` |
| `docs/release/release-record-v0.8.0.md` on `+993` | "Pending desktop hotfix… no source archive, GitHub release, or public publish was produced" |

So the shipped `0.8.0+993` has no source tag on any remote, the release record
still describes it as unreleased, and the website continues to serve a
`0.7.4+985` archive described as build-matched. The website page is not a
leftover 404 — it is live and serving a real archive two minor versions behind,
which is worse than serving nothing, because it reads as current.

### The build recipe, revisited 2026-08-07 — largely recovered after all

An earlier version of this file recorded the build recipe as unrecoverable,
reasoning that the build definition could not be identified once the release tag
was deleted. That was too pessimistic. The tag is only one way to reach it, and
the commit history is another.

GPLv3 §1 counts "the scripts used to control compilation and installation" as
Corresponding Source, so this matters. Re-checked against the live GitHub API:

| Check | Result |
|---|---|
| `BtbN/FFmpeg-Builds` tag ref `autobuild-2026-06-13-13-31` | **404** — still pruned |
| `BtbN/FFmpeg-Builds` commit history | alive and complete |
| Last commit before the 2026-06-13T13:31Z build | **`a9410e4be2b3`**, 2026-06-10T17:39:42Z |
| Commits between `a9410e4b` and the build | **none** |

Because nothing landed in that window, `a9410e4b` is the repository state the
build ran from. That is the build definition, reachable by an immutable commit
hash that no release pruning can remove.

**This is a tight inference, not proof.** The artefact that would prove it — the
release tag pointing at a commit — is exactly what was deleted. The date bracket
is narrow and the repository is public, so it is good evidence; it is recorded
as evidence rather than as certainty.

### The original upstream release archive is also held

Recovered 2026-08-06 from a working directory and moved by the maintainer to
`references/ffmpeg-n8.1-lgpl-20260613/` on 2026-08-07:

- `ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip`
- 198,755,840 bytes, **SHA-256
  `6C1C443C762A8D8AD9C9303AF26E2144DC711B0E7277E1B03FD72CDF2DEAA9DB`**
- valid zip, 48 entries, verified before and after the move
- contains upstream's own `LICENSE.txt` (the LGPL-3 text), the `doc/` tree,
  `presets/`, and all three executables including `ffplay.exe`, which the project
  does not ship

This is the actual artefact the dead `asset_url` pointed at — stronger
provenance than the extracted binaries alone, because it is what upstream
published rather than what was unpacked from it.

`references/` is **gitignored** (`.gitignore:52`, zero tracked files), so this is
one machine's disk and not version control. It is a real improvement on the
swept agent-cache temporary directory it came from, but the durable artefacts
remain the published archive and the hashes recorded here.

### So the source was never actually at risk; the binary was

Worth separating, because it changes what is worth mirroring. The FFmpeg source
commit `83e8541aa6…` returns 200 from both the GitHub API and codeload today —
it is immutable and has never been unavailable. What disappeared was BtbN's
*built artefact* and its release tag.

A fork of FFmpeg was considered and rejected on that basis: it would re-host the
component that never went missing, would not contain the build scripts (those
are BtbN's repository, a different project), and would move the single point of
failure from a long-lived upstream onto this project's own account. Recording
the two commit hashes — `83e8541aa6…` for the source and `a9410e4b` for the
build definition — achieves more than a fork would, at the cost of one edit. A
pinned repository becomes the right shape only if this project starts building
FFmpeg itself, at which point the build definition genuinely is its own.

## Upstream's own compliance checklist, mapped to our state

Source: <https://ffmpeg.org/legal.html>, "License Compliance Checklist", read
2026-08-07. Upstream calls it "not the only way to comply, but we think it is
the easiest", and prefixes the page with "this is not legal advice". Neither is
this file. It is recorded because it converts a vague obligation into a list
that can actually be checked.

Two items on that page settle questions this project had been reasoning about
from first principles:

- **"Distribute the source code of FFmpeg, no matter if you modified it or
  not."** Modification is explicitly irrelevant. Distribution is the trigger.
- **"Go through all the items again for any LGPL external library you compiled
  into FFmpeg (for example LAME)."** The external libraries are not only an
  attribution problem — the LGPL ones carry the same source-availability
  obligation FFmpeg itself does. That is materially larger than a notices file.

| Upstream item | State | Note |
|---|---|---|
| No `--enable-gpl` / `--enable-nonfree` | **Met, at the configure line** | Verified from the recorded configure line; `configure` hard-fails if a GPL-only *external* is enabled without the flag. **It does not follow that no GPL code is in the binary** — corrected 2026-08-09, see the FFTW row below |
| Dynamic linking | **Exceeded** | Shipped as separate executables invoked as subprocesses — not linked into the app at all |
| Distribute source, modified or not | **Met** | Corrected 2026-08-08: this row read "Held, not published", contradicting the "Publication — DONE 2026-08-07" section earlier in this same file. The archive is live; `HEAD https://app.ourgalaxy.space/source/ffmpeg-n8.1.1-13-g83e8541aa6-source.tar.gz` returns 200, re-checked 2026-08-08 |
| Source corresponds exactly to the binaries | **Met and proven** | Commit `83e8541aa6…`, byte-verified |
| `git diff > changes.diff` | **N/A — unmodified** | Worth stating positively rather than omitting: there are no modifications, so there is no diff |
| Explain the configure line in a text file in the source root | **Not done** | `manifest.json` records it, but not in the archive. This is upstream's own suggested way to satisfy the build-recipe question, and it is cheaper than reconstructing the builder's scripts |
| Tarball or zip for the source | **Met** | `.tar.gz` |
| Host the source on the same webserver as the binary | **Met** | Corrected 2026-08-08, same reason as the row above: the source is served from `app.ourgalaxy.space/source/`, the same host as the binaries |
| Notice on every page with a download link | **Not done — but the evidence under it was stale** | **Measurement refreshed 2026-08-15 by S&C, and the status deliberately NOT flipped.** This cell cited *"Measured 2026-08-07: zero FFmpeg mentions on `/download/` and zero on `/source/`"*. Both are now false: `/source/` returns **116** case-insensitive `ffmpeg` matches (51 `FFmpeg`, 8 `n8.1.1`) and `/download/` returns **5** (3 `FFmpeg`), fetched live with a browser UA against a negative control (a bogus component name returns 0, so the method discriminates). **The status stays "Not done" because a mention is not a notice** — the requirement is that a notice accompany the download link, and counting the string "FFmpeg" cannot establish that the wording present is the required one. Whoever closes this row must read what those pages actually say. Refreshing the measurement without flipping the status is the point: the old evidence would have been re-cited as current |
| Mention in the program's about box | **Met** | **Corrected 2026-08-15 by S&C** (routed from REVIEW; licence evidence, so corrected by the owning lane rather than in passing). This cell read **"Not done"** with the reason *"the in-app screen is Flutter `showLicensePage`, which enumerates `LicenseRegistry` — Dart packages only"*. That was true when written and is false now. `settings_category_about.dart:108-109` calls `NativeLicenses.register()` **immediately before** `showLicensePage(context: context)`, so the native notices are injected into `LicenseRegistry` before the page renders. On Windows that includes the `ffmpeg.exe`/`ffprobe.exe` notice this document covers. Verified by reading the call site, not inferred from the changelog |
| Mention in the EULA | **Not done** | Zero FFmpeg mentions in the published terms |
| EULA must not claim ownership of FFmpeg | **No conflict found** | |
| Remove any prohibition of reverse engineering | **Met** | Measured: zero reverse-engineering, decompilation or disassembly prohibitions in the published terms. This is the item that would actively conflict with the licence, and it is clean |
| Do not misspell FFmpeg | **Watch** | Correct in this evidence; worth a sweep when the notices are written |
| Do not rename the binaries | **Met** | Shipped as `ffmpeg.exe` / `ffprobe.exe`, unrenamed |
| Repeat for every LGPL external compiled in | **Enumerated; source availability not done** | The inventory exists as of 2026-08-08: `docs/release/evidence/ffmpeg-components/`. **58** components on the configure line, of which **42 are attribution-only** and **16 carry a source-availability obligation** (14 LGPL-family + 2 MPL-2.0); 0 GPL-only and 0 non-free *among those 58*. **Plus 2 transitive components with a source obligation** (FFTW, `libudfread`) that the configure line cannot name — so the obligation is **18**, not 16, and not 58. **Corrected 2026-08-09:** this cell ended "No corresponding source is mirrored for any of them yet". **All 18 are now published** at `https://app.ourgalaxy.space/source/`, each keyed to the exact upstream revision compiled (git commits, except `libmp3lame` at Subversion `r6531`), together with the build definition. Also corrected in the same pass: "0 GPL-only … among those 58" is right about the configure line and wrong about the binary — part of `libzvbi` is GPL-2.0-**only**, which makes two GPL components here, not one |
| No GPL libraries such as libx264 | **Not met — corrected 2026-08-09** | This row read "**Met** — No `--enable-gpl`, so none are present". `libx264` specifically *is* absent. But **FFTW (GPL-2.0-or-later) is statically in the binary**, reaching it through `chromaprint`, which BtbN builds with `-DFFT_LIB=fftw3`. Chromaprint is LGPL-2.1 and has no entry in `EXTERNAL_LIBRARY_GPL_LIST`, so `configure` never demanded the flag. Absence of `--enable-gpl` is authoritative for direct externals and blind beneath them by construction. Disclosed in `docs/policies/SOURCE_OFFER.md` and `docs/policies/THIRD_PARTY_NOTICES.md`; owner decision in workspace `docs/DECISIONS.md`, 2026-08-09 |
| FFTW, transitively (added 2026-08-09) | **Disclosed; source published** | **GPL-2.0-or-later**, version `fftw-3.3.11` from the artefact's own wisdom-export string, pinned at `5d0f4db2fc157867b7dc972b40418f171d77a6bc`. In the `ffmpeg.exe` shipped from **`0.7.4+985` onward** — three public releases, measured by hashing the executable inside each retained payload. *Two cells corrected 2026-08-09: status read "source not published", and the scope read "`0.8.0+992` and `0.8.0+993`".* Do not remove this row to make the table read clean |
| `libudfread`, transitively (added 2026-08-09) | **Disclosed; source published** | LGPL-2.1-or-later, via `libbluray`, pinned at `139a2194525f2745b98a98e4d8fa627d07440176` |
| `libzvbi`, partly GPL-2.0-**only** (added 2026-08-09) | **Disclosed; source published** | A **second** GPL component, found after FFTW. Its own `COPYING.md` at pinned commit `41477c97c8ed` licenses `src/packet-830.*` and `src/pdc.*` under GPL-2 with **no "or later"** — so no v3 election and no GPL-3 §8 cure for those files. `packet-830` is established as link-reachable through an unconditional chain from `libavcodec/libzvbi-teletextdec.c`; `pdc.o` is **not** establishable from source alone and is recorded as unknown. *Corrected 2026-08-09 (REVIEW, app PR #139), superseding the two linkage claims in the previous sentence: the shipped binary was measured. `pdc.o` now has **positive evidence of absence** — three unconditional `pdc.c` format strings all missing from the executable, with `libzvbi` ×12 in the same binary as the working control; evidence rather than proof under `--gc-sections`/LTO. `packet-830.o` is **undeterminable by measurement** (no surviving literals or symbol names; no map file) and is treated as present on the source-level chain, the conservative reading. Narrows the exposure, withdraws nothing — the source stays published. Method: `../../ffmpeg/libzvbi-gpl2-linkage-measurement.md`* |
| `libbluray` classification | **Corrected 2026-08-09** | Recorded `LGPL-2.1-only` from VideoLAN's project description. Its own headers at pinned commit `4dfb9b0123b0` say "or (at your option) any later version" — 845 files carry that grant and none state 2.1 alone. It **can** elect v3 and **does** have GPL-3 §8 cure |

### Licence version

`ffmpeg.org/legal.html` describes FFmpeg as LGPL **v2.1 or later**. This build
was configured with `--enable-version3`, which elevates it to **LGPL-3.0**, so
notice wording should say v3 (or "v2.1 or later") rather than flatly copying
upstream's suggested v2.1 phrasing.

### The builder's own licence

`BtbN/FFmpeg-Builds` is **MIT** (confirmed via the GitHub API, repository not
archived). That is worth recording because it makes the build-definition
question cheap: the scripts at `a9410e4b` are permissively licensed and freely
redistributable, so if the configure-line file above is ever judged
insufficient, mirroring the build definition carries no copyleft consequences of
its own.

## Why the notices were missing — the MIT badge

Recorded because it is the most likely reason nothing on the site, in the terms
or in the about box ever mentioned FFmpeg, and because it is a trap that recurs
with any "builds of X" repository.

`github.com/BtbN/FFmpeg-Builds` displays an **MIT** badge. MIT means "keep the
notice, no further obligations", and that is the first and most visible signal
anyone evaluating the dependency sees. Concluding "MIT, nothing further to do"
is a reasonable inference from the repository page alone.

It is wrong, for a reason not visible from that page. The MIT licence there
reads "Copyright 2020-2021 BtbN" and covers **what BtbN wrote** — the build
scripts. It does not reach what those scripts produce. The output is FFmpeg,
and `ffmpeg.org/legal.html` states plainly: *"FFmpeg is not available under any
other licensing terms, especially not proprietary/commercial ones, not even in
exchange for payment."* No downstream builder can relicense it.

BtbN is consistent with this in two visible places, both confirmed 2026-08-07:

- their release archive ships `LICENSE.txt` containing the **LGPL-3 text**, held
  at `references/ffmpeg-n8.1-lgpl-20260613/`;
- their README names the build variants `gpl`, `lgpl` and `nonfree` — labelling
  each build by the licence its *output* carries. This project uses the variant
  literally named `lgpl`.

BtbN being listed on `ffmpeg.org/download.html` ("Windows builds by BtbN") also
does not change terms. It means the build is trusted, not relicensed — if
anything it is evidence BtbN complies, since FFmpeg would not list a builder who
relicensed their work.

**The general rule:** for any third-party build of someone else's software, the
repository's licence covers the packaging. The payload keeps its own licence,
and only the packaging gets a badge. Check what is inside the artefact, not what
the repository page advertises.

## Preventing a repeat

The failure was not that BtbN pruned a release; it is that the project recorded
a URL and treated it as durable. For every future third-party binary:

- capture the artefact **and** its Corresponding Source at staging time,
- record the builder's own commit SHA alongside the release tag,
- and publish the source before the binary ships, not after someone notices the
  link is dead.

The 2026-08-07 re-check adds one more, learned from getting it wrong here: when
a provenance route dies, check whether a *different* route to the same
information survives before recording it as lost. A deleted tag does not delete
the commit history behind it, and a date bracket over that history was enough to
identify the build definition. "Unrecoverable" is a claim that should itself be
tested.

## Related

- `docs/release/evidence/ffmpeg/manifest.json` — original provenance record,
  annotated 2026-08-06 with the 404 finding.
- `docs/DECISIONS.md` 2026-06-13 — the decision to bundle LGPL-only FFmpeg tools,
  which already required recording the source revision, link, build configuration
  and any patch diff before a production desktop build closed the gate.
- `docs/DECISIONS.md` 2026-08-06 — the decision to narrow the build, and the
  finding that BtbN's `-shared` LGPL variant roughly halves the payload with no
  change of provenance class.
