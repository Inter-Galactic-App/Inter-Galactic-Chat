# AGPL App Store Review

Draft status: counsel review required.

Inter Galactic is a modified fork of Commet and remains under AGPL-3.0. App Store distribution must preserve user rights under the AGPL while also satisfying App Store terms.

Version scope: the current live public source-offer record is `0.7.4+985` for
the Windows desktop and Android website release. The current iOS/TestFlight
candidate is `0.7.4+986`; its exact source-offer URL/hash remains deferred
until App Store/TestFlight submission or publication closeout.

## Required Release Actions

- Preserve the AGPL license text in the repo and app notices.
- Preserve Commet attribution.
- Publish corresponding source for the exact submitted binary.
- Include source-offer language in App Store metadata or support/about links.
- Make source archive URLs durable and versioned.
- Include third-party notices and asset provenance.

## Counsel Review Questions

- Does the App Store distribution path impose terms that conflict with AGPL rights?
- Is the source offer sufficiently prominent for binary users?
- Does the archive include all scripts needed to build the submitted binary?
- Are App Store screenshots/metadata accurate about fork status and no affiliation?
- Are third-party SDK and asset licenses compatible with App Store distribution?

## Suggested Review Note

"Inter Galactic is distributed under AGPL-3.0. Corresponding source for the current public build 0.7.4+985 is available at https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip. The public source page is https://app.ourgalaxy.space/source/. Inter Galactic is a modified fork of Commet and preserves upstream attribution."

Before submitting an iOS/App Store build newer than `0.7.4+985`, update this
note to the exact submitted build, source archive URL, and source archive hash.
