# Inter Galactic Privacy Policy

Effective date: 2026-05-03

Inter Galactic is a Matrix client. It helps you connect to a Matrix homeserver that you choose, such as `matrix.org`, a self-hosted server, or a community server. Inter Galactic should be treated as separate from any private homeserver or friend-group domain unless a public release specifically says otherwise. Your Matrix account, messages, media, rooms, account deletion, and server logs are controlled by the selected homeserver, not by the Inter Galactic app alone.

## Data Inter Galactic Handles

Inter Galactic may handle Matrix account identifiers such as your Matrix user ID, display name, avatar URL, device ID, homeserver URL, room IDs, event IDs, and push routing identifiers.

When you send or receive Matrix content, the app handles messages, media uploads, reactions, room membership events, call membership events, voice/video/screen-share signaling, and files you choose to upload. Matrix homeservers store and deliver this content according to their own policies.

The app stores local device data needed to work, including settings, Matrix session data, encrypted message caches, E2EE keys and key-backup state, notification preferences, local media/cache files, and diagnostic logs if you enable or submit them.

Optional features may involve additional data:

- Push notifications: APNs or another push service receives a push token and routing metadata. Notification content depends on the selected homeserver and app settings.
- URL previews: when enabled, a URL may be sent to the selected homeserver
  preview endpoint, a configured preview service, or a provider-limited direct
  client fallback for supported public providers so a preview can be generated.
- GIF search: search text and request metadata may be sent to a configured GIF provider or relay.
- Emoticon Creator/background removal: source photos you select are processed
  on your device to create transparent images and local drafts. On Android,
  Google Play services ML Kit may prepare an unbundled on-device segmentation
  model and collect SDK diagnostics described by Google. Source photos and
  generated images are uploaded to a Matrix homeserver only if you choose to
  save or share them through Matrix.
- Spotify/activity: if you connect Spotify, OAuth tokens and playback metadata are used to display or control activity features.
- Support, abuse, and security reports: Matrix-native abuse reports may be submitted to your selected homeserver. Direct Inter Galactic reports may include Matrix IDs, event IDs, message snippets, files, screenshots, logs, and supported non-audio developer diagnostic attachments that you choose to send. RNNoise WAV/audio diagnostics remain local-only in the app and are not accepted by the bug-report submission path.

## End-to-End Encryption

Matrix end-to-end encryption can protect message content so homeservers and relays cannot read encrypted message bodies. E2EE does not hide all metadata. Homeservers and network services may still see account identifiers, room identifiers, device identifiers, IP addresses, timestamps, sender/recipient metadata, media repository metadata, push routing metadata, and call/signaling metadata.

E2EE also has practical limits. Content already decrypted on another user's device can be saved or shared by that user. Messages or media already delivered to other devices or homeservers may not be fully removable. If you lose your device keys or recovery key, Inter Galactic may not be able to recover older encrypted messages.

## Homeservers And Federation

The selected homeserver is responsible for your Matrix account and server-side data. If a room is federated, data may be copied to other participating homeservers. Those servers may be operated by different organizations and may have different retention, moderation, and legal processes. Inter Galactic cannot delete or control data held by servers it does not operate.

## How Data Is Used

Data is used to provide Matrix messaging, calling, media sharing, Emoticon Creator/background removal, push notifications, account/session restore, E2EE, optional rich activity, GIF search, URL previews, customer support, abuse handling, security investigation, and legal compliance. Abuse reports sent through Matrix-native pathways are handled by the selected homeserver according to that homeserver's process.

Inter Galactic does not use tracking for advertising in this draft. If advertising, cross-app tracking, or third-party analytics are added later, this policy and App Store privacy labels must be updated before release.

## Retention

Messages and media are retained by the selected homeserver according to that homeserver's policy. Local app data remains on your device until you remove accounts, clear app data, or delete the app. Emoticon Creator drafts and generated local images remain local unless you choose to save, share, export, or delete them. Diagnostic logs and supported non-audio diagnostic attachments remain local unless you choose to send or save them. RNNoise WAV diagnostics stay local unless you manually share files outside the bug-report flow. Support, abuse, and security records are retained only as long as needed for those purposes, unless law requires longer retention.

## Choices And Controls

You can manage notification settings, disconnect Spotify, disable rich activity, manage GIF and URL preview behavior where settings are available, manage local Emoticon Creator drafts where the feature provides draft controls, and choose whether to share diagnostic logs or supported non-audio diagnostic attachments. You can choose a different Matrix homeserver at login when the app build permits custom homeserver entry.

## Account Deletion

Deleting the Inter Galactic app does not delete your Matrix account. Matrix account deletion or deactivation belongs to the selected homeserver. If you use `matrix.org`, follow Matrix.org's account deletion process. If you use a self-hosted or community homeserver, contact that homeserver's administrator.

Deleting a Matrix account may not remove messages or media already delivered to other users, other devices, remote homeservers, backups, moderation archives, or legal records.

## Children

Inter Galactic is not intended for children under 13. Users under the age of majority should use the app only with parent or guardian permission where required.

## Contact

Privacy: `intergalactic@ourgalaxy.space`

Support: `intergalactic@ourgalaxy.space`

Abuse reports: use the in-app Matrix report action or selected homeserver's abuse process first. For app-level issues or routing help, contact `intergalactic@ourgalaxy.space`.

Security: `intergalactic@ourgalaxy.space`
