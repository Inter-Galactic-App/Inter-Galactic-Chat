# Report Abuse

Publication status: public beta abuse-reporting guidance. The in-app
Matrix-native report/block path and shared routing inbox are tracked in
`PUBLIC_RELEASE_READINESS_TRACKER.md`; keep future operator-policy changes
synchronized there.

## How To Report

For the public iOS release, Inter Galactic should provide in-app report actions for Matrix messages, rooms, and users. Those actions should default to Matrix-native reporting so the report goes to the selected homeserver, because the homeserver controls the Matrix account, room membership, media repository, server-side logs, and moderation systems.

Matrix-native paths to implement and verify:

- report a message or event: `POST /_matrix/client/v3/rooms/{roomId}/report/{eventId}`;
- report a room: `POST /_matrix/client/v3/rooms/{roomId}/report`;
- report a user: `POST /_matrix/client/v3/users/{userId}/report`;
- block or ignore a user: update the user's Matrix ignored-user account data, commonly `m.ignored_user_list`.

If the in-app Matrix report flow is not available, use the selected homeserver's abuse process or contact Inter Galactic at `intergalactic@ourgalaxy.space` for app-level issues and routing help. The shared inbox monitoring status is recorded in `PUBLIC_RELEASE_READINESS_TRACKER.md`.

Include:

- the Matrix user ID being reported;
- your Matrix user ID if you are comfortable sharing it;
- the homeserver involved;
- the room ID or room alias;
- the event link or event ID for the message;
- screenshots or logs only if they are safe and legal to share;
- a short description of what happened.

Current release status: in-app Matrix-native message, room, and user reporting
plus block/unblock were verified against a real homeserver on 2026-06-12, with
OPERATIONS confirming the report path landed where expected. Keep release
evidence synchronized with `PUBLIC_RELEASE_READINESS_TRACKER.md`.

## What Information May Be Included

An abuse report may include Matrix IDs, room IDs, event IDs, message snippets, media references, timestamps, homeserver names, moderation history, device/app version, and diagnostic logs you choose to attach.

Do not send illegal sexual content involving minors to Inter Galactic. Report it to the appropriate emergency or legal authority.

## Who Receives Reports

Matrix-native reports are sent to the selected homeserver. The homeserver decides whether to notify server administrators, room moderators, safety tooling, or another review process. Inter Galactic does not automatically receive those reports unless the homeserver routes them to Inter Galactic or you separately contact Inter Galactic.

Reports sent directly to Inter Galactic are reviewed by Inter Galactic operators or designated moderators. If the issue involves a homeserver or room Inter Galactic does not operate, Inter Galactic may route you to that homeserver's administrators or room moderators and may forward only the information reasonably needed to handle the issue.

## Expected Process

1. You use the in-app report action where available.
2. Inter Galactic submits the report through the selected homeserver's Matrix reporting API.
3. You may also block or ignore the user locally through Matrix ignored-user controls.
4. The homeserver, room moderators, or Inter Galactic review the report only where they actually receive it and have authority to act.
5. Outcomes may be limited by Matrix federation, encryption, remote homeserver control, missing evidence, or legal constraints.

## Emergency And Legal Limits

Inter Galactic is not an emergency service. If there is immediate danger, contact local emergency services. Inter Galactic cannot guarantee deletion of content from remote homeservers, recipient devices, backups, or legal archives.
