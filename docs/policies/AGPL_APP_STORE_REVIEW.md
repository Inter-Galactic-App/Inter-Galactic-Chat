# AGPL App Store Review

Draft status: counsel review required.

Inter Galactic is a modified fork of Commet and remains under AGPL-3.0. App Store distribution must preserve user rights under the AGPL while also satisfying App Store terms.

Version scope: the current public source route is the public source repo at
`https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`, with source tag
`v0.7.4+986`. The live Windows desktop and Android website release remains
`0.7.4+985`; its build-matched source archive and SHA-256 remain recorded in
`SOURCE_OFFER.md`.

## Required Release Actions

- Preserve the AGPL license text in the repo and app notices.
- Preserve Commet attribution.
- Publish corresponding source for the exact submitted binary.
- Include source-offer language in App Store metadata or support/about links.
- Make public repository, tag, and any build-matched source archive URLs
  durable and versioned.
- Include third-party notices and asset provenance.

## Counsel Review Questions

- Does the App Store distribution path impose terms that conflict with AGPL rights?
- Is the source offer sufficiently prominent for binary users?
- Does the archive include all scripts needed to build the submitted binary?
- Are App Store screenshots/metadata accurate about fork status and no affiliation?
- Are third-party SDK and asset licenses compatible with App Store distribution?

## Suggested Review Note

"Inter Galactic is distributed under AGPL-3.0. Public source is available at https://github.com/Inter-Galactic-App/Inter-Galactic-Chat and the current public source tag is v0.7.4+986. The build-matched source archive for the live 0.7.4+985 Windows/Android release remains available at https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip. Inter Galactic is a modified fork of Commet and preserves upstream attribution."

Before submitting an iOS/App Store build newer than `0.7.4+986`, update this
note to the exact submitted build and matching public source tag/archive
evidence.
