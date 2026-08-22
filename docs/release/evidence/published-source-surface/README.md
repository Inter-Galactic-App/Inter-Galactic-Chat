# Published `/source/` surface — the documents, under version control

Lane: REVIEW · Established 2026-08-16

Every non-archive document served at `https://app.ourgalaxy.space/source/`,
byte-identical to what is published. **This directory exists so the deploy root
is reproducible.** Before it, eleven files of the published source offer existed
in exactly one place: the deploy root itself.

## Why this was worth doing

`SOURCE-CORRESPONDENCE-0.8.0+993.md` carried a wrong SHA-256 and byte count for
`intergalactic-0.8.0+993-desktop-source.zip` from 6 August to 16 August. Nothing
caught it, because there was nothing to catch it *against* — no repo copy, no
diff, no gate. Every other licence surface has a counterpart that can disagree
with it. These eleven had none.

Two hazards, both real and both previously recorded against a different path:

1. **A full rsync deploy would delete all of them.** `DEPLOY.md` already forbids
   mirroring for this reason. That prohibition is a rule someone has to
   remember; this directory is the backup that makes the rule survivable.
2. **Drift is invisible without a second copy.** That is not hypothetical here —
   it already happened, for ten days, on a compliance surface.

## What is here, and what is deliberately not

**Here — 11 files, ~69 KB:** the AGPL `LICENSE`, the release-correspondence
record, both build-configuration transcripts, the FFmpeg LGPL-3 text, and the
seven upstream patches (four FFmpeg, two mpv, plus the dash escape fix).

**Not here, on purpose:**

- **The 36 source archives** (`.zip`, `.tar.gz`, `.tar.xz`, `.7z`) — hundreds of
  megabytes of release payload. Their digests are recorded in
  `docs/policies/SOURCE_OFFER.md` and in `downloads/checksums-*.txt`, which is
  the right way to pin a large binary. Do **not** commit them here.
- **`index.html`** — it is *generated*, not hand-published. The website build
  emits it from `website/Inter Galactic Website.dc.html`, and the built
  `site/source/index.html` is byte-identical to the served copy (verified
  2026-08-16, sha256 `c692393d5b3e8473…`, 162,232 bytes). Copying it here would
  create a second source of truth for a file that already has one. If the source
  page needs a copy change, change the authored `.dc.html` and rebuild.

## Keeping this honest

These are copies of a published surface, so the only failure mode that matters
is **silent divergence** — this directory saying one thing while the deploy root
says another, which is precisely the defect it was created to prevent.

- If you change a served document, change it in **both** places in the same
  change, and say so in the commit.
- Verify with a hash comparison, not by eye. All eleven were confirmed
  byte-identical at the time of import.
- These files are records of what was *published*. When one is corrected, the
  correction belongs **inside** the document as a dated note — as
  `SOURCE-CORRESPONDENCE-0.8.0+993.md` now carries — rather than as a silent
  overwrite. A published compliance document that quietly changes its own
  digests is worse than one that shows its history.
