# Account Deletion

Publication status: draft for App Store review and support until any
Inter-Galactic-operated deletion path and public contact commitments are
confirmed in `PUBLIC_RELEASE_READINESS_TRACKER.md`.

Deleting Inter Galactic from your device does not delete your Matrix account.

## Who Controls Account Deletion

Your selected Matrix homeserver controls Matrix account deletion or deactivation. Inter Galactic can sign out of the app and remove local data, but it cannot delete an account from a homeserver it does not operate.

If you use `matrix.org`, follow Matrix.org's account deletion process. If you use a self-hosted or community homeserver, contact that homeserver's administrator or use that homeserver's account management page.

Current release blocker: if Inter Galactic ever operates a public homeserver
for app users, publish the exact account deletion URL and expected response
time for that homeserver. Keep that blocker state synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

## What Deletion May Not Remove

Matrix account deletion may not remove:

- messages and media already delivered to other users;
- content copied to federated homeservers;
- content saved by recipients;
- encrypted content for which other devices still have keys;
- moderation, abuse, security, backup, and legal records.

## Local App Data

Signing out or deleting the app can remove local app data from that device. It does not remove data from homeservers or other devices. Before deleting local data, save any recovery key or account information you need.

## App Store Readiness

If the iOS app exposes account creation in the future, it must also expose an account deletion initiation path that leads users to the selected homeserver's deletion process. Current native mobile policy is login-only.
