# AGPL App Store Review

Status: iOS distribution continues under AGPL-3.0. App Store terms and the
AGPL/GPL family are in tension on usage restrictions (device limits, DRM),
which is why this compliance checklist exists; the tension is not unique to
this project. Nothing here is legal advice, and nothing here states the
arrangement is or is not compliant — it documents what this project does to
meet the obligations that are mechanical, listed under "Required Release
Actions" below.

Inter Galactic is a modified fork of Commet and remains under AGPL-3.0. App Store distribution must preserve user rights under the AGPL while also satisfying App Store terms.

Version scope: the current public source route is the public source repo at
`https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`, with source tag
`v0.8.1+1004`. The last public release is `0.8.1+1004`, whose Windows and Android
builds were produced from different commits and therefore have two
build-matched archives; those archives and their SHA-256 values are recorded in
`SOURCE_OFFER.md`.

## Required Release Actions

- Preserve the AGPL license text in the repo and app notices.
- Preserve Commet attribution.
- Publish corresponding source for the exact submitted binary.
- Include source-offer language in App Store metadata or support/about links.
- Make public repository, tag, and any build-matched source archive URLs
  durable and versioned.
- Include third-party notices and asset provenance.

## Review Questions

*Re-read these before any change of distribution route.*

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
