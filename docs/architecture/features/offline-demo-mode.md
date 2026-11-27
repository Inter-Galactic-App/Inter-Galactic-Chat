# Offline Demo Mode

## Purpose

Offline demo mode exists for app review and quick UI walkthroughs where a real
Matrix account should not be required.

The demo is not a second backend and it is not a protocol compatibility path.
It is a local implementation of the app's shared client abstractions with
seeded sample data.

## Scope

The demo client lives under:

- `intergalactic/lib/client/demo/`

It currently seeds:

- one top-level space
- one normal chat room
- one forum room
- one voice/call room
- one calendar room

The login screen can expose the entry point through "Continue in Offline Demo",
but it is hidden by default. Enable it from the login-page App Settings when a
reviewer or developer needs the local sample account. That action creates a
`DemoClient` and adds it directly to `ClientManager`.

## Guardrails

- Do not connect demo mode to a homeserver.
- Do not register Matrix pushers, APNs, FCM, UnifiedPush, or ntfy paths from
  demo mode.
- Do not persist demo mode as a Matrix session.
- Do not run Matrix E2EE recovery, verification, or post-login setup flows for
  demo-only sessions.
- Keep demo data platform-neutral so desktop, iOS, Android, and web can use the
  same sample client when available.

## Intended Review Behavior

Reviewers and developers can use the offline demo to inspect navigation, chat
rendering, forum posts, voice-room presentation, and calendar UI without a real
account. Backend guarantees such as encrypted sync, federation, push delivery,
and real media calls still require normal Matrix accounts and server-side
validation.
