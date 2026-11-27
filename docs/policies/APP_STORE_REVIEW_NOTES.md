# App Store Review Notes

Inter Galactic is a Matrix client for existing Matrix accounts. The iOS build does not expose account registration. Users sign in with a Matrix account from the homeserver they choose, such as `matrix.org`, a self-hosted homeserver, or a community homeserver if custom homeserver entry is enabled.

Matrix account deletion is handled by the selected homeserver. Deleting the app does not delete a Matrix account. The app includes an Account Management account-deletion handoff for each signed-in account. That handoff identifies the Matrix account, opens the selected homeserver, and explains that the homeserver controls deletion, deactivation, identity checks, retention, and whether delivered messages or media can be removed.

The app contains user-generated content because Matrix rooms can contain messages, media, reactions, files, calls, and room metadata. The app provides in-app report and block/ignore controls, public community guidelines, and abuse contact information. Message, room, and user reports are submitted to the selected homeserver through Matrix Client-Server reporting APIs, and block/ignore updates Matrix ignored-user account data. Inter Galactic does not host or moderate every Matrix homeserver.

The app supports Matrix end-to-end encryption. E2EE protects message content in supported rooms but does not hide all metadata and cannot remove content already delivered to other users, devices, homeservers, or backups.

Optional integrations may include push notifications, URL previews, GIF search through a relay/provider, Spotify activity, and LiveKit calls. Each optional feature is disclosed in the privacy policy and privacy label inventory.

## Current Public URLs

These URLs describe the current live public website surfaces and the public
source-offer route. The current public source repo is tagged `v0.8.1+1004`. The
last public release is `0.8.1+1004`; its Windows and Android builds came from
different commits and have separate build-matched archives listed below. The
source page identifies release-specific routes and checksums; this note does
not assert that every historical archive is still served.

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
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat/tree/v0.8.1%2B1004`
- Build-matched `0.8.1+1004` Android source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.1+1004-source.zip`
- Build-matched `0.8.1+1004` Windows source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.1+1004-desktop-source.zip`
- Build-matched `0.8.0+992` source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.8.0+992-source.zip`
- Build-matched `0.7.4+985` source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`
- Support, abuse, privacy, and security routing inbox:
  `intergalactic@ourgalaxy.space`
