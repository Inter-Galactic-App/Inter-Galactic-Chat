# AGPL App Store Review

Status: **owner decision, taken 2026-08-09 — the risk is accepted and iOS
distribution continues.** This is a risk judgement recorded by the project
owner, not a legal opinion, and nothing here states that the arrangement is or
is not compliant.

**The tension is real and is not being denied.** App Store terms impose usage
restrictions — device limits, DRM — that the FSF reads as "further restrictions"
the GPL family forbids, and VLC was pulled from the store in 2011 after an
upstream author objected on exactly that basis. This app is an AGPL-3.0 fork of
Commet, so the copyright holders who could raise it are the upstream Commet
authors as well as the project owner.

**Why the owner accepts it:**

- **iOS distribution has never gone past TestFlight.** There is no public App
  Store listing, so the exposure is small and the decision stays reversible.
- **Commet is a small project** and the owner does not foresee an objection from
  upstream. Enforcement here requires a copyright holder to choose to act; it is
  not automatic and no complaint exists.
- The obligations that *are* mechanical — AGPL text preserved, Commet
  attribution preserved, build-matched corresponding source published for every
  release — are met, and are listed under "Required Release Actions" below.

**One thing this decision does NOT rest on, recorded so the reasoning is not
misread later: dropping FFTW and `libzvbi` from future FFmpeg builds is
irrelevant to this question.** Those are third-party GPL components inside a
bundled binary. This question is about **the application's own AGPL-3.0 licence**
against Apple's terms, and the app stays AGPL-3.0 whatever FFmpeg is built with.
The trim closes a different problem; it does not touch this one.

**Revisit this if any of the three reasons above changes** — in particular
before a public App Store listing, which is the step that turns a small,
reversible exposure into a durable one.

The questions below are kept in full. They are what the decision was taken
against, and deleting them would leave it unsupported.

Inter Galactic is a modified fork of Commet and remains under AGPL-3.0. App Store distribution must preserve user rights under the AGPL while also satisfying App Store terms.

Version scope: the current public source route is the public source repo at
`https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`, with source tag
`v0.8.0+993`. The last public release is `0.8.0+993`, whose Windows and Android
builds were produced from different commits and therefore have two
build-matched archives; those archives and their SHA-256 values are recorded in
`SOURCE_OFFER.md`.

The tag previously named here, `v0.7.4+986`, was deleted from the public
repository and no longer resolves. Do not reinstate it in any reviewer-facing
note.

## Required Release Actions

- Preserve the AGPL license text in the repo and app notices.
- Preserve Commet attribution.
- Publish corresponding source for the exact submitted binary.
- Include source-offer language in App Store metadata or support/about links.
- Make public repository, tag, and any build-matched source archive URLs
  durable and versioned.
- Include third-party notices and asset provenance.

## Review Questions

*These are the questions the decision above was taken against. They remain worth
re-reading before any change of distribution route.*

- Does the App Store distribution path impose terms that conflict with AGPL rights?
- Is the source offer sufficiently prominent for binary users?
- Does the archive include all scripts needed to build the submitted binary?
- Are App Store screenshots/metadata accurate about fork status and no affiliation?
- Are third-party SDK and asset licenses compatible with App Store distribution?

## Suggested Review Note

"Inter Galactic is distributed under AGPL-3.0. Public source is available at https://github.com/Inter-Galactic-App/Inter-Galactic-Chat and the current public source tag is v0.8.1+1004. Build-matched source archives for every published release, with their SHA-256 values and the binary each corresponds to, are listed at https://app.ourgalaxy.space/source/. Inter Galactic is a modified fork of Commet and preserves upstream attribution."

Updated 2026-08-22 for the `0.8.1+1004` release. Before submitting an
iOS/App Store build newer than `0.8.1+1004`, update this note to the exact
submitted build and matching public source tag/archive evidence.
