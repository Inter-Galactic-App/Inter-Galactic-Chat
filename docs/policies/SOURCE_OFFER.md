# Source Offer

Draft status: public-release source-offer draft. Counsel review required.

Inter Galactic is a modified fork of Commet and is distributed under the GNU Affero General Public License v3.0.

Version scope:

- Current submitted/public binary source offer: `0.7.4+985` for the live
  Windows desktop and Android website release.
- Current iOS/TestFlight candidate: `0.7.4+986`; the exact corresponding-source
  offer for that candidate is deferred until submission/publication closeout.

## Source For Current Submitted Binary

For each public binary, publish the corresponding source code for the exact submitted build, including build scripts and license notices needed to exercise AGPL rights.

Current public submission:

- Build: `0.7.4+985`
- Source commit used for packaging: `5ea73c0`
- Exact-source tag: deferred until REVIEW confirms the public release tag.
- Public source page: `https://app.ourgalaxy.space/source/`
- Corresponding source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- Source archive SHA-256:
  `342280CB6ED1A8684B96EDCD78F36CB98A9F5AC828C57041322378701AB70255`

Release evidence is recorded in
`docs/release/release-record-v0.7.4.md`. That record states the public
`0.7.4+985` Windows installer, Android APK, source archive, checksums, update
manifest, and changelog are live.

Do not reuse the `0.7.4+985` archive for a future `0.7.4+986` submitted binary
unless REVIEW/RELEASE PIPELINE confirms the source inputs did not change or
publishes exact `0.7.4+986` corresponding source.

Deferred until final submission/legal pass:

- counsel review of source-offer wording;
- exact public release tag confirmation;
- exact iOS/TestFlight `0.7.4+986` source-offer closeout if that candidate is
  submitted or published;
- final App Store metadata placement proof;
- rebuilt-app smoke proving the submitted in-app About/license surfaces open the
  public source page.

## Attribution

Inter Galactic preserves Commet attribution:

- Original app: Commet
- Original creators: commetchat / commet.chat
- Original source: `https://github.com/commetchat/commet`

Inter Galactic should not imply endorsement by Matrix.org, Commet, Discord, Messenger, Spotify, Apple, LiveKit, or GIF providers.
