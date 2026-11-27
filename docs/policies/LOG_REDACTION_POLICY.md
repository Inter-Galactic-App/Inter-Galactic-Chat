# Log Redaction Policy

Publication status: draft operational policy for public support workflows until
runtime redaction coverage is verified against exported logs and the public
support path in `PUBLIC_RELEASE_READINESS_TRACKER.md`.

## Never Include In Logs

- Matrix access tokens, refresh tokens, login tokens, UIA sessions, or bearer tokens;
- E2EE private keys, recovery keys, backup keys, Megolm/Olm secrets, cross-signing private material;
- push tokens, VAPID/auth keys, pusher URLs, Firebase credentials, APNs secrets;
- OAuth codes, Spotify access tokens, refresh tokens, client secrets;
- signing keys, keystore passwords, certificate passwords;
- full URLs with sensitive query parameters.

## Minimize In Logs

- Matrix user IDs;
- room IDs and event IDs;
- homeserver URLs;
- IP addresses;
- file paths;
- message snippets;
- call participant identifiers;
- device IDs.

Use stable redaction markers that preserve debugging shape without exposing the value, such as `[matrix-access-token]`, `[push-token]`, `[room-id]`, or `[url-with-query]`.

## Support Log Submission

Users should be shown what logs contain before they submit them. Logs should be retained only as long as needed for the support, abuse, security, or legal purpose.

Current release blocker: expand runtime redaction and verify exported logs
against this policy before public support intake opens. Keep that blocker state
synchronized with `PUBLIC_RELEASE_READINESS_TRACKER.md`.
