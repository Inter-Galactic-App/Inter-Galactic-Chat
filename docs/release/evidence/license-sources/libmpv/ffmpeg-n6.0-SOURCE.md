# Corresponding Source — FFmpeg `n6.0`, statically linked into `libmpv-2.dll`

Prepared by S&C, 2026-08-08. **PUBLISHED 2026-08-08** at
`https://app.ourgalaxy.space/source/ffmpeg-n6.0-source.tar.gz`.

*Status updated 2026-08-09. This line read "Staged, not published. Publication
is an owner/OPERATIONS action; nothing here has been uploaded." That was true
when written and was overtaken the same day; the four publication steps at the
bottom of this file were all carried out, and the digest was re-computed from
the served file after copying, not before.*

## Why this file exists

`libmpv-2.dll` statically carries FFmpeg `n6.0`. That is a **different FFmpeg**
from the `n8.1.1-13-g83e8541aa6` build used by the standalone `ffmpeg.exe`
tooling, whose source is already published at
`https://app.ourgalaxy.space/source/ffmpeg-n8.1.1-13-g83e8541aa6-source.tar.gz`.

Until now `n6.0` was **named but not offered**: it appears in prose on the
public source page and in `docs/release/THIRD_PARTY_NOTICES.md`, and a page-wide
scan for `n6` returns one hit and zero download links. For a statically linked
LGPL component, corresponding source normally has to include the statically
linked LGPL components — so a named-but-unoffered component is the substantive
gap, not a wording gap.

Raised as finding 1, item 1 in
`Matrix_Dev/docs/audit/license-compliance-findings-2026-08-08.md`.

## Identity

| Field | Value |
| --- | --- |
| Project | FFmpeg |
| Version | `n6.0` (`RELEASE` file in the tree reads `6.0`) |
| Tag object | `3949db4d261748a9f34358a388ee255ad1a7f0c0` (annotated, PGP-signed) |
| Tagged by | Michael Niedermayer, 2023-02-27T20:32:19Z, message `FFmpeg 6.0 release` |
| **Commit** | **`ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2`** |
| Upstream | `https://git.ffmpeg.org/ffmpeg.git`, mirrored at `https://github.com/FFmpeg/FFmpeg` |
| Modifications | None. Inter Galactic does not build or patch this FFmpeg; it arrives already compiled inside `libmpv-2.dll`. |

The commit SHA is the identity to rely on. The tag is a mutable pointer — the
standing rule in `Matrix_Dev/docs/DECISIONS.md` → *"Record A Third-Party
Binary's Builder Commit SHA At Staging Time" (2026-08-07)* exists because
exactly that kind of pointer was deleted out from under the BtbN FFmpeg
provenance.

## The archive

| Field | Value |
| --- | --- |
| Filename | `ffmpeg-n6.0-source.tar.gz` |
| Size | 14,751,707 bytes |
| SHA-256 | `AACCE24D5BB6C67FBF1E3343BC15A6977AD700CDB4F43C8551F6544FA54AB7EC` |
| Obtained from | `https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2` |
| Durable publication record | The temporary staging copy was superseded by the public URL below; it is not retained as evidence. |
| Published | **YES — 2026-08-08.** Row flipped 2026-08-09; it read "**NO** — pending owner/OPERATIONS action" |
| URL | `https://app.ourgalaxy.space/source/ffmpeg-n6.0-source.tar.gz` |

This deliberately reuses the retrieval method already used for the `n8.1.1`
archive — upstream's own export by **commit SHA**, published byte-for-byte and
not repacked — so a recipient can re-obtain it from FFmpeg and compare
hash-for-hash without trusting this project's server. Repacking to embed extra
files in the source root would destroy exactly that property.

## Verification performed 2026-08-08

- Annotated tag `n6.0` resolved through its tag object to commit
  `ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2`.
- Archive downloaded **twice**; both fetches produced the identical SHA-256
  above, so the export is reproducible rather than a one-off byte stream.
- Contents confirmed to be the intended tree: `RELEASE` reads `6.0`, and
  `LICENSE.md` is FFmpeg's own, stating LGPL v2.1+ by default with GPL parts
  reachable only via `--enable-gpl`.
- Confirmed the gap is real and not already covered: HTTP `HEAD` against
  `https://app.ourgalaxy.space/source/ffmpeg-n6.0-source.tar.gz` and
  `.../ffmpeg-n6.0.tar.gz` both returned **404**, while the `n8.1.1` archive,
  the mpv archive and both build-configuration files returned **200**.
- The mpv archive already published was re-downloaded and re-hashed; it matches
  its recorded digest
  `926DCE4DFB918CBBAC603AD5D453D453D0036D1E00E77BAAF5D76CA99CE7A419`.

## Licence position of this component

`--enable-version3` with `--disable-gpl --disable-nonfree`, and the library
self-reports `libavcodec license: LGPL version 3 or later`, so **LGPL-3.0-or-later**
for this copy. The full configure line the binary records of itself is already
published in `mpv-BUILD-CONFIGURATION.txt` and does not need restating here.

No claim is made about legal sufficiency. This file records identity,
retrieval, digests and what was checked.

## What publication requires

**All four were completed on 2026-08-08 and are retained as the record of what
was required.** Do not re-run them; the file is live and re-uploading would
serve no purpose. Kept in place because the ordering constraint in step 2 — hash
the served copy, not the staged one — is the reusable part.

The completed publication sequence was:

1. Publish the verified source archive at the `/source/` deploy root and
   confirm it serves `200` with `application/gzip` at the intended URL.
2. Re-hash the **served** file and confirm it matches the digest above — the
   public page's own claim is that "the SHA-256 shown for each is verified
   against the served file", so the digest must be verified post-copy, not
   pre-copy.
3. Add it to the `libmpv` block on `/source/`, beside the mpv archive, labelled
   as the FFmpeg **statically compiled into `libmpv-2.dll`** and explicitly not
   the `ffmpeg.exe` one.
4. Flip `Published` in the table above, and remove the "not yet published"
   wording from the libmpv section of `docs/policies/SOURCE_OFFER.md`.

## What this does *not* close

The other two libmpv gaps are untouched by this. Their status as of 2026-08-09:

- the **build definition** for `libmpv-2.dll` is still unrecovered (see
  `corresponding-source-bundle.md`, Tier 2). Note that the *FFmpeg tool pair's*
  build definition was recovered from commit history on 2026-08-09 and
  published; that is a different builder and does not transfer, but the
  commit-history route should be exhausted here before the word "unrecoverable"
  is used again;
- **Tier 3 component revisions** were unpinned when this was written. The three
  that carry a **source obligation** — `libfribidi` 1.0.13, `libsoxr` 0.1.3 and
  `uchardet` — were pinned and published on 2026-08-09. The remainder are
  attribution-only and their per-component licence texts are still not started.
  This DLL's **transitive** dependencies remain not enumerable, so the set of
  three is not proven complete.

Publishing the `n6.0` archive closed the largest of the three, not the set.
