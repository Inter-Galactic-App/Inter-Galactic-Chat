# App Store Review Notes

Draft status: review-note source with current public URLs filled in. App Store
privacy-label evidence was recorded from owner-provided App Store Connect
screenshots on 2026-06-14. Encryption export answers and reviewer account flow
remain deferred until their evidence exists. *(Corrected 2026-08-09: an
outstanding review was listed alongside them. The encryption-export answer is a
submission-time self-declaration, not a deferral.)*

Inter Galactic is a Matrix client for existing Matrix accounts. The iOS build does not expose account registration. Users sign in with a Matrix account from the homeserver they choose, such as `matrix.org`, a self-hosted homeserver, or a community homeserver if custom homeserver entry is enabled.

Matrix account deletion is handled by the selected homeserver. Deleting the app does not delete a Matrix account. The app includes an Account Management account-deletion handoff for each signed-in account. That handoff identifies the Matrix account, opens the selected homeserver, and explains that the homeserver controls deletion, deactivation, identity checks, retention, and whether delivered messages or media can be removed.

The app contains user-generated content because Matrix rooms can contain messages, media, reactions, files, calls, and room metadata. The public release must include in-app report and block/ignore controls plus public community guidelines and abuse contact information. The intended report pathway is Matrix-native: message, room, and user reports are submitted to the selected homeserver through Matrix Client-Server reporting APIs, and block/ignore updates Matrix ignored-user account data. Inter Galactic does not host or moderate every Matrix homeserver.

The app supports Matrix end-to-end encryption. E2EE protects message content in supported rooms but does not hide all metadata and cannot remove content already delivered to other users, devices, homeservers, or backups.

Optional integrations may include push notifications, URL previews, GIF search through a relay/provider, Spotify activity, and LiveKit calls. Each optional feature is disclosed in the privacy policy and privacy label inventory.

## Current Public URLs

These URLs describe the current live public website surfaces and the public
source-offer route. The current public source repo is tagged `v0.8.0+993`. The
last public release is `0.8.0+993`, whose Windows and Android builds came from
different commits and so have two build-matched archives; every published
release keeps its archive for exact package evidence, and the source page lists
all of them with checksums.

The tag this section previously named, `v0.7.4+986`, was deleted from the public
repository and returns 404. Every URL below was verified to resolve on
2026-08-06.

Re-verified 2026-08-08 (S&C): the public repository carries exactly two tags,
`v0.8.0+993` and `v0.8.0+992`. `v0.7.4+986` and `v0.7.4+985` both return HTTP
404 as tag routes — for `0.7.4` the retained source **archive** is the offer,
not a tag. Any reference to a `0.7.4` tag anywhere in this document or in the
linked release records is historical and must not be given to a reviewer.

- Website: `https://app.ourgalaxy.space/`
- Privacy Policy: `https://app.ourgalaxy.space/privacy/`
- Terms/EULA: `https://app.ourgalaxy.space/terms/`
- Support: `https://app.ourgalaxy.space/support/`
- Report Abuse: `https://app.ourgalaxy.space/report-abuse/`
- Account Deletion: `https://app.ourgalaxy.space/account-deletion/`
- Community Guidelines: `https://app.ourgalaxy.space/community-guidelines/`
- Source Offer: `https://app.ourgalaxy.space/source/`
- Public source repository:
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`
- Current public source tag:
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat/tree/v0.8.0%2B993`
- Build-matched `0.8.0+993` Android source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.0+993-source.zip`
- Build-matched `0.8.0+993` Windows source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.0+993-desktop-source.zip`
- Build-matched `0.8.0+992` source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.0+992-source.zip`
- Build-matched `0.7.4+985` source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- Support, abuse, privacy, and security routing inbox:
  `intergalactic@ourgalaxy.space`

## Submitted-Build Evidence Already Recorded

- Account Management account-deletion handoff was verified in
  `PUBLIC_RELEASE_READINESS_TRACKER.md`.
- Matrix-native message, room, and user reporting plus block/unblock were
  verified against a real homeserver and recorded in
  `PUBLIC_RELEASE_READINESS_TRACKER.md`.
- The `0.7.4+985` release and its source archive are recorded in
  `docs/release/release-record-v0.7.4.md`. That record also names a
  `v0.7.4+986` public source tag: **that tag no longer exists** (see above), so
  treat every `v0.7.4+986` reference in the release record as historical
  candidate evidence, not as a route a reviewer can follow. The live route for
  that release is the retained archive
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`.
- iOS archive privacy-manifest validation is recorded in
  `PUBLIC_RELEASE_READINESS_TRACKER.md` and
  `docs/release/release-record-v0.7.4.md`. The `0.7.4+986` build referenced
  there was a submission *candidate*; it is not the current public source tag.
- App Store privacy labels were recorded from user-provided App Store Connect
  screenshots on 2026-06-14 and reconciled with
  `APP_PRIVACY_LABEL_INVENTORY.md`.

## Still Deferred Before App Store Submission Closeout

- provide demo/test account credentials or a reviewer homeserver flow;
- attach encryption export evidence;
- refresh the public source tag/archive evidence in this document if the
  submission candidate changes before submission or publication. The current
  tag is `v0.8.0+993`; do not reinstate `v0.7.4+986`, which was deleted and
  returns 404;
- record the export self-declaration with the release record.
  *(Corrected 2026-08-09: this previously described the item as an outstanding
  review. It is the `ITSAppUsesNonExemptEncryption` key plus App Store Connect's
  export-compliance questions, answered at submission against Apple's own
  published guidance.)*
