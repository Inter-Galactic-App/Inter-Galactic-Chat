# Corresponding Source — the Apple media_kit bundle

Prepared by REVIEW, 2026-08-15, on the Windows host.

**PUBLISHED 2026-08-15 and verified served.** All nine artefacts below are live
under `https://app.ourgalaxy.space/source/`. Each was fetched back over HTTPS and
re-hashed against the table: **9/9 HTTP 200, 9/9 digests match**. See "How it was
published, and how that was verified" below.

> This file first read **"STAGED, NOT PUBLISHED"** with a section titled *"The
> blocker"* asserting that no agent host could upload. Both were true when
> written and stopped being true the same day. Corrected here rather than left to
> age, because this project's recurring defect is a state claim written as a fact
> — see `docs/agent-control/cleanup.md`, *"not published" describes a moment*.

> **SUPERSEDED LATER THE SAME DAY — the offer pages now list the archives.**
> Corrected by S&C 2026-08-15, re-verified live rather than relayed: the
> rendered `/source/` page returns hits for `mpv-0.36.0-source`,
> `fribidi-1.0.13-source`, `uchardet-0.0.8-source`, `libmpv-darwin-build`,
> `ffmpeg-fix-vp9`, `darwin` and `xcframework`, and carries the macOS
> bundled-not-distributed paragraph; `/third-party-notices/` carries the Apple
> component sections including the FreeType *"based in part"* disclaimer. The
> paragraph below is preserved as an accurate record of the state at the time it
> was written. See "What is still open" at the end of this file for the current
> position.

**Published is not the same as offered.** The `/source/` and
`/third-party-notices/` **pages do not yet list these archives** — verified live,
zero hits for `mpv-0.36.0-source`, `fribidi-1.0.13-source`,
`uchardet-0.0.8-source`, `libmpv-darwin-build`, `ffmpeg-fix-vp9`, `darwin` and
`xcframework` on the rendered `/source/` page, against a positive control that
finds `ffmpeg-n6.0-source` four times. The bytes are reachable; the offer page
that names them is a separate, still-open limb. Do not summarise this as "the
Apple offer is discharged".

The archives were also staged at `Corresponding_Source/source/apple-media-kit/`
with a `MANIFEST.json` carrying the same digests. That directory is gitignored,
so **this file remains the durable record**: the digests here are what let anyone
re-obtain the same bytes from upstream without trusting this project's server.

## Why this exists

The Apple binaries are **modified**. `media-kit/libmpv-darwin-build` v0.6.0
applies four FFmpeg patches and one mpv patch unconditionally before configure,
so the published upstream archives do not describe what ships. The shipped
notices already say the patches are part of the corresponding source the offer
covers, and the notices point at `https://app.ourgalaxy.space/source/`.

**That address now delivers what the notices name.** This was an ordering
constraint on the next iOS archive; as of 2026-08-15 it no longer blocks one.
The residual is the offer *page*, which does not yet list these files.

## What was verified, and how

Three of the four source archives match the recipe's **own** `downloads.lock`
entry — the digest `libmpv-darwin-build` itself checks at fetch time. Matching it
means the archive is byte-identical to what the build consumed, which is a
stronger claim than "same version".

> **THE FFmpeg BASE IS THE EXCEPTION, AND IT IS NOT BYTE-IDENTICAL TO THE LOCK
> PIN.** Corrected 2026-08-15 after the `/source/` page stated it correctly and
> this file did not. `downloads.lock` pins
> `https://ffmpeg.org/releases/ffmpeg-6.0.tar.xz` at
> `57be87c22d9b49c112b6d24bc67d42508660e6b718b3db89c44e47e289137082`; what this
> project publishes is `ffmpeg-n6.0-source.tar.gz`, the **git-tag export** at
> `aacce24d5bb6c67fbf1e3343bc15a6977ad700cdb4f43c8551f6544fa54ab7ec`. **Same
> upstream release, two different containers — the code corresponds, the files do
> not hash alike.** Read from `downloads.lock` inside the published build-
> definition archive, not relayed. Which container is offered is a packaging
> choice and both correspond to FFmpeg 6.0, but do not restate the FFmpeg base as
> "byte-identical to what the build consumed", because it is not. The
> byte-identical claim holds for **mpv, FriBidi and uchardet only** — all three
> re-checked against the lock in the same read.

| Artefact | Bytes | SHA-256 | Provenance |
| --- | ---: | --- | --- |
| `mpv-0.36.0-source.tar.gz` | 3,409,178 | `29abc44f8ebee013bb2f9fe14d80b30db19b534c679056e4851ceadf5a5e8bf6` | **matches `downloads.lock` pin** |
| `fribidi-1.0.13-source.tar.xz` | 1,170,100 | `7fa16c80c81bd622f7b198d31356da139cc318a63fc7761217af4130903f54a2` | **matches `downloads.lock` pin** |
| `uchardet-0.0.8-source.tar.xz` | 222,648 | `e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0` | **matches `downloads.lock` pin** |
| `libmpv-darwin-build-g4286f5557bdc-build-definition.tar.gz` | 43,982 | `092a4bc3dcabcd1d9f931e98664616093e6cad969ddf9be03bf259c1c23bd8e0` | exported by commit SHA; fetched twice, identical |
| `ffmpeg-fix-vp9-hwaccel.patch` | 2,335 | `3b6b44f6df5fc4665fd53711765d5324981abde8e66a26a631522bf816d66620` | from the definition archive |
| `ffmpeg-fix-hls-mp4-seek.patch` | 528 | `a8f5445db1e2d0fec936b1b885d98fbd07d3d989b951b8b60c20a29d6f49edfd` | from the definition archive |
| `ffmpeg-fix-ios-hdr-texture.patch` | 1,621 | `76a777fa18890b058ed5375bbc008b7aca2bfc5ed264c19b545c6b3d023928f2` | from the definition archive |
| `ffmpeg-fix-dash-base-url-escape.patch` | 1,135 | `625b8c09f356fcf60850a18856736d9b96055674102177d4faf739f50bd8dd7d` | from the definition archive |
| `mpv-fix-missing-objc.patch` | 728 | `9affd0b9bf9a36ac57ba1ce211e2292ad7cda2050abb560909bafc585c908851` | from the definition archive |

Every row above was **re-fetched from the served copy** on 2026-08-15 and
re-hashed: 9/9 HTTP 200, 9/9 byte counts and digests identical to the table.
Each file is at `https://app.ourgalaxy.space/source/<filename>`.

Upstream URLs, so a recipient can re-obtain and compare without trusting this
project's server:

- mpv — `https://github.com/mpv-player/mpv/archive/refs/tags/v0.36.0.tar.gz`
- FriBidi — `https://github.com/fribidi/fribidi/releases/download/v1.0.13/fribidi-1.0.13.tar.xz`
- uchardet — `https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz`
- build definition — `https://codeload.github.com/media-kit/libmpv-darwin-build/tar.gz/4286f5557bdccc0747030e3c376ce5cd160a96a0`

The build definition is exported **by commit SHA, not by tag**, per
`docs/DECISIONS.md` → *"Record A Third-Party Binary's Builder Commit SHA At
Staging Time"*. `v0.6.0` resolves to commit
`4286f5557bdccc0747030e3c376ce5cd160a96a0`. That rule exists because a BtbN tag
was deleted out from under this project's FFmpeg provenance once already.

## The patch inventory was re-verified here, not relayed

The handoff stated which patches apply. Read from
`scripts/ffmpeg/build.sh` and `scripts/mpv/build.sh` in the staged definition:

```
ffmpeg/build.sh:8-11   vp9-hwaccel, hls-mp4-seek, ios-hdr-texture,
                       dash-base-url-escape        -> all unconditional
mpv/build.sh:8         mpv-fix-missing-objc        -> unconditional
mpv/build.sh:9-11      mpv-remove-libass           -> if VARIANT == "audio"
```

**`mpv-remove-libass.patch` is deliberately NOT published as applied.** It is
guarded by `VARIANT == "audio"` and this project ships
`ios-universal-video-default`. Publishing it as part of the corresponding source
would describe a binary that was never built.

## Scope: why five components and not eleven

The bundle is 11 components, but they ship as **separate dynamically linked
frameworks**, so each is its own artefact under its own licence rather than one
combined static work. Source obligations therefore attach per component:

- **Source obligation** — FFmpeg 6.0 (LGPL-3), mpv 0.36.0 (LGPL-2.1),
  FriBidi 1.0.13 (LGPL-2.1), uchardet 0.0.8 (LGPL-2.1, elected).
- **Attribution only, no source limb** — libass (ISC), dav1d (BSD-2-Clause),
  HarfBuzz (MIT), libpng, Mbed TLS (Apache-2.0), libxml2 (MIT), and FreeType
  (FTL — a credit and disclaimer obligation, discharged in the notice).

**FFmpeg's base source is already published** as `ffmpeg-n6.0-source.tar.gz`
(14,751,707 bytes, `AACCE24D…B7EC`) and covers this bundle's base. Two limits on
that archive, both of which have been misread before:

- It is a **different container from the `downloads.lock` pin** — see the
  correction under "What was verified". Same upstream release, different bytes.
- It does **not** cover the four patches; that is what the patch files above are
  for. Do not cite it as complete Apple corresponding source.

**The four patches are the whole of why the Apple source differs from the
Windows libmpv one.** The Windows notice's *"upstream FFmpeg, unmodified, so
there is no accompanying patch"* is true of the Windows artefact and false of
this one.

*This scoping is an engineering judgement recorded for the owner, not a legal
conclusion. If the owner prefers to publish all eleven regardless, the six
permissive archives are cheap to add and their pins are in the definition
archive's `downloads.lock`.*

## How it was published, and how that was verified

`app.ourgalaxy.space` is served from `/srv/docker/matrix/www/intergalactic/` on
`192.168.4.109`. The nine files were placed into `source/` there through the
**Syncthing mirror at `Linux_Matrix_Build/www/intergalactic/source/`**, and they
appear in that directory dated 2026-08-15.

**That mirror is the publish path for `/source/` archives.** This is the
correction that unblocked the limb, and it is worth stating precisely because the
earlier record got it half right: the mirror is *not* an authoring surface for
rendered **pages** — a page edited there is overwritten by the next site build —
but static archives dropped under `source/` are exactly what it carries. The
existing `tools/release/third-party-source.json` had said so all along; every
`localPath` in it is
`Linux_Matrix_Build/www/intergalactic/source/<archive>`. The blocker note that
this file previously carried generalised "cannot edit rendered output there" into
"cannot publish anything there", and that generalisation was the whole of the
blocker.

Verification, done against the **served** copies rather than the staged ones,
which is the reusable ordering from the `ffmpeg-n6.0` publication record:

- Each of the nine URLs fetched over HTTPS: **9/9 HTTP 200**.
- Each body re-hashed with SHA-256 and length-checked: **9/9 match the table
  above, byte count and digest**.
- Negative control, so a blanket-200 host cannot fake the result: the sibling
  `https://app.ourgalaxy.space/source/ffmpeg-n6.0.tar.gz` (no `-source`) still
  returns **404**, while `ffmpeg-n6.0-source.tar.gz` returns 200 at 14,751,707
  bytes. The check distinguishes published from unpublished.

The earlier blocker finding is preserved as accurate history: on this host
`IG_RELEASE_SSH_KEY` was empty in `B:/matrix/.env` and
`ssh nick@192.168.4.109` returned `Permission denied (publickey,password)`. SSH
was never the only route; it was the only route that had been tried.

## What is still open

**Updated by S&C 2026-08-15, later the same day. The deployed-page limb is
CLOSED; the in-repo one was closed by the same pass.** The original text is kept
beneath, because "not published" describes a moment and the record of that moment
is what makes the sequence legible.

Re-verified live rather than relayed, and the ten artefacts were re-fetched from
the **served** copies and re-hashed as part of the same check — 10/10 HTTP 200,
10/10 digests and byte counts matching this file's table:

- **`/source/` lists the archives.** Hits for `mpv-0.36.0-source`,
  `fribidi-1.0.13-source`, `uchardet-0.0.8-source`, `libmpv-darwin-build`,
  `ffmpeg-fix-vp9` and `xcframework`, plus the full Apple block, the
  11-component licence summary, the modification statement and the macOS
  bundled-not-distributed paragraph.
- **`/third-party-notices/` carries the Apple sections**, including the
  component inventory and the FreeType *"based in part of the work"* disclaimer.
- **The three in-repo policy documents** — `docs/policies/SOURCE_OFFER.md`,
  `docs/policies/THIRD_PARTY_NOTICES.md` and
  `docs/release/THIRD_PARTY_NOTICES.md` — had **zero** Apple coverage while the
  site had all of it. That was the real residual and it is closed in the same
  change as this correction.

What remains owed on this artefact is the **licence-text packaging**, not the
source or the offer: the FTL text is captured at
`docs/release/evidence/license-sources/freetype/FTL.at-920c5502cc3d.txt` but is
not shipped as an app asset, and the ISC / BSD-2-Clause / MIT / Apache-2.0 /
PNG-v2 texts are neither held nor shipped. The three texts that do ship —
`LGPL-2.1.txt`, `LGPL-3.0.txt`, `GPL-3.0.txt` — cover FFmpeg, mpv, FriBidi and
uchardet.

### The original, preserved

The archives are published. **The offer pages are not updated.**

- `/source/` does not list any of the nine — verified live, zero hits for
  `mpv-0.36.0-source`, `fribidi-1.0.13-source`, `uchardet-0.0.8-source`,
  `libmpv-darwin-build`, `ffmpeg-fix-vp9`, `darwin`, `xcframework`, against a
  positive control that finds `ffmpeg-n6.0-source` four times.
- `/third-party-notices/` has no Apple sections.

So the files are served but **unlinked**. Authoring those two sections is the
remaining limb and is in progress in `inter-galactic-website`. The rule that
governed the ordering has now been satisfied in the safe direction: the archives
existed before the page names them, so deploying the sections cannot create a
404 in a compliance document.

macOS remains deferred by owner decision (`docs/DECISIONS.md`, 2026-08-15,
*"The Source Offer Names macOS As Bundled-But-Not-Distributed"*). Nothing here
changes that.
