# Push Privacy Review

Publication status: draft release-readiness review until the production push
gateway path, APNs environment, and privacy-label answers are confirmed in
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

Inter Galactic uses platform push services to wake the app or notify users about Matrix activity. On iOS this involves APNs and the app's Matrix pusher registration.

## Data Involved

- APNs push token;
- Matrix pusher app ID and pushkey;
- homeserver and push gateway routing metadata;
- room/event identifiers where required by the Matrix push flow;
- notification content if the homeserver or app settings include it.

## Privacy Requirements

- Prefer privacy-enhanced notifications for encrypted rooms.
- Do not send decrypted encrypted-message content through push services.
- Let users disable notifications.
- Explain that homeservers and push gateways may process routing metadata.
- Avoid logging push tokens or full push payloads in public support logs.

## iOS Evidence

- `Info.plist` includes remote notification background mode.
- `Runner.entitlements` includes APNs and app group.
- AppDelegate captures APNs tokens and notification responses.

Current release-readiness prerequisite: verify the production push gateway
host, payload content, APNs environment, and privacy-label answers for push
tokens. Keep that prerequisite synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
