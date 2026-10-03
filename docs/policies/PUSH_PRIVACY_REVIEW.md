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
- A Notification Service Extension (`ios/InterGalactic Notification Extension`)
  fetches and decrypts the referenced event on the device when the gateway
  marks a push `mutable-content`. It renders event-derived content only after
  reading the user's local notification policy from the App Group and fails
  closed to the gateway's generic payload otherwise, so "let users disable
  notifications" holds for this second producer as well as for the app.
- The cost of that model, stated so it is not mistaken for a defect: the
  extension can only decrypt messages in sessions the app has already stored.
  A message in a session whose room key has not yet reached the app is shown
  as the generic notification, and the app replaces it with the decrypted one
  once it has the key. The extension never processes key material itself.
- To keep that window short, the app answers the gateway's silent wake by
  re-establishing its database, draining one short sync per account so
  pending room keys are stored, and releasing the database again before it
  reports the wake complete.

Current release-readiness prerequisite: verify the production push gateway
host, payload content, APNs environment, and privacy-label answers for push
tokens. Keep that prerequisite synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
