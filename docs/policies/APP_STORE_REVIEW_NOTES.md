# App Store Review Notes

Draft status: review-note source with current public URLs filled in. App Store
privacy-label evidence was recorded from owner-provided App Store Connect
screenshots on 2026-06-14. Encryption export answers, reviewer account flow,
and counsel review remain explicitly deferred until their evidence exists.

Inter Galactic is a Matrix client for existing Matrix accounts. The iOS build does not expose account registration. Users sign in with a Matrix account from the homeserver they choose, such as `matrix.org`, a self-hosted homeserver, or a community homeserver if custom homeserver entry is enabled.

Matrix account deletion is handled by the selected homeserver. Deleting the app does not delete a Matrix account. The app includes an Account Management account-deletion handoff for each signed-in account. That handoff identifies the Matrix account, opens the selected homeserver, and explains that the homeserver controls deletion, deactivation, identity checks, retention, and whether delivered messages or media can be removed.

The app contains user-generated content because Matrix rooms can contain messages, media, reactions, files, calls, and room metadata. The public release must include in-app report and block/ignore controls plus public community guidelines and abuse contact information. The intended report pathway is Matrix-native: message, room, and user reports are submitted to the selected homeserver through Matrix Client-Server reporting APIs, and block/ignore updates Matrix ignored-user account data. Inter Galactic does not host or moderate every Matrix homeserver.

The app supports Matrix end-to-end encryption. E2EE protects message content in supported rooms but does not hide all metadata and cannot remove content already delivered to other users, devices, homeservers, or backups.

Optional integrations may include push notifications, URL previews, GIF search through a relay/provider, Spotify activity, and LiveKit calls. Each optional feature is disclosed in the privacy policy and privacy label inventory.

## Current Public URLs

These URLs describe the current live public website surfaces and the public
source-offer route. The current public source repo is tagged
`v0.7.4+986`; the live Windows desktop / Android website release remains
`0.7.4+985` and keeps a build-matched source archive for exact package
evidence.

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
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat/tree/v0.7.4%2B986`
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
- The current public `0.7.4+985` release/source archive and `0.7.4+986`
  public source tag are recorded in `docs/release/release-record-v0.7.4.md`.
- iOS archive privacy-manifest validation and current `0.7.4+986` candidate
  status are recorded in `PUBLIC_RELEASE_READINESS_TRACKER.md` and
  `docs/release/release-record-v0.7.4.md`.
- App Store privacy labels were recorded from user-provided App Store Connect
  screenshots on 2026-06-14 and reconciled with
  `APP_PRIVACY_LABEL_INVENTORY.md`.

## Still Deferred Before App Store Submission Closeout

- provide demo/test account credentials or a reviewer homeserver flow;
- attach encryption export evidence;
- refresh the `0.7.4+986` public source tag/archive evidence if the candidate
  changes before submission or publication;
- attach counsel/legal review note.
