# ADR 0001: Stay Matrix-Native

## Status

Accepted

## Context

Inter Galactic is trying to improve the user experience of a Matrix client without replacing Matrix semantics.

The repo still clearly centers the app around:

- Matrix clients and rooms
- Matrix event flows
- Matrix pushers
- Matrix E2EE and verification
- Matrix-compatible media and sticker behavior

Because the product direction is more consumer-friendly than many traditional Matrix clients, there is constant pressure to shortcut rough Matrix edges with app-local behavior.

## Decision

Inter Galactic remains Matrix-native.

That means:

- rooms remain Matrix rooms
- spaces remain Matrix spaces
- account/device semantics remain Matrix account/device semantics
- media, stickers, mentions, replies, and reactions stay aligned with Matrix event behavior
- push registration continues to use Matrix pusher concepts

UX may improve, but protocol truth does not move into app-local substitutes.

## Consequences

### Positive

- interoperability remains possible
- Synapse compatibility stays central
- E2EE/session behavior remains reviewable against Matrix expectations
- feature work can still reference Matrix-native upstream/client behavior when needed

### Negative

- some rough Matrix concepts cannot be hidden completely
- product features sometimes need to work around protocol constraints rather than replacing them
- fixes may require more coordination across restore, verification, and event layers than a proprietary app would

## Practical Guidance

- Prefer Matrix-compatible payloads over app-local shortcuts.
- If a UX change seems to conflict with Matrix semantics, preserve Matrix semantics.
- If a proposed feature needs non-Matrix behavior, isolate it clearly and do not make it look like core Matrix behavior.

## Review Trigger

Re-read this ADR when changing:

- room/event semantics
- account/device identity rules
- notification/account routing
- media or sticker send behavior
