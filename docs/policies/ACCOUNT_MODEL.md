# Inter Galactic Account Model

Publication status: draft for review notes and support routing until the
submitted-build homeserver/login behavior is confirmed in
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

Inter Galactic is a Matrix client. It is not itself the Matrix account provider. Private homeservers, friend-group domains, `matrix.org`, self-hosted servers, and community servers are separate from the public Inter Galactic app unless a public release explicitly documents a specific relationship.

## Key Points

- Inter Galactic may not create accounts in native mobile builds.
- Users sign in with an account from the selected Matrix homeserver.
- The default homeserver in current repo evidence is `matrix.org`.
- Users may be able to enter another homeserver, including a self-hosted server, depending on build configuration.
- The selected homeserver controls account creation, login, password reset, account deletion, server-side retention, media storage, room membership, and moderation.
- Matrix-native abuse reports are sent to the selected homeserver. Inter Galactic does not automatically receive or control those reports unless the homeserver routes them to Inter Galactic or the user separately contacts Inter Galactic.
- Blocking or ignoring a user is a Matrix account control, commonly stored in `m.ignored_user_list`, and may not remove content already delivered to the device or room.
- Deleting Inter Galactic from a device does not delete the Matrix account.
- Messages and media already delivered to other users, devices, homeservers, backups, or moderation/legal systems may not be fully removable.

## Matrix Data Locations

Local device:

- Matrix session cache;
- local settings;
- push preferences;
- encrypted room caches;
- E2EE device keys and key backup state;
- local logs if enabled or generated.

Selected homeserver:

- account record;
- room membership;
- message and media events;
- device list;
- push rules and pusher registrations;
- server logs and abuse/moderation records.
- Matrix-native message, room, and user reports submitted through the selected homeserver.

Other homeservers:

- data for federated rooms, if the room or selected homeserver federates with other servers.

## Review Language

Use this phrasing in App Store review notes: "Inter Galactic is a Matrix client for existing Matrix accounts. Native iOS builds do not expose account registration. Account deletion and Matrix-native abuse reports are handled through the selected Matrix homeserver; deleting the app does not delete the Matrix account."

Current publication prerequisite: confirm whether the submitted iOS build
permits arbitrary homeserver entry or limits login to specific homeservers.
Keep that final statement synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
