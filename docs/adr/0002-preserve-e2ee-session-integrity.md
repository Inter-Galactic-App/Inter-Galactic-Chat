# ADR 0002: Preserve E2EE and Session Integrity

## Status

Accepted

## Context

The app’s most fragile and highest-risk areas are:

- login and session restore
- encrypted-room usability
- device verification and cross-signing
- trust continuity across updates, restarts, and account changes

Inter Galactic inherits real Matrix E2EE/session complexity from upstream code and from the Matrix ecosystem itself. Replacing that complexity with convenience shortcuts creates false trust, broken restore behavior, and user-visible crypto failures.

## Decision

E2EE, verification, and session trust cannot be weakened for convenience.

Specifically:

- restore logic must preserve account/device continuity where local state is intact
- verification UI must stay truthful
- crypto state must not be silently discarded just to simplify flow control
- recovery must be explicit when local state is missing or corrupt
- multi-account state must remain isolated

## Consequences

### Positive

- encrypted rooms remain dependable
- device trust state is less likely to fragment
- future contributors have a clear rule when UX convenience conflicts with crypto/session safety

### Negative

- some fixes require heavier review than they would in a non-E2EE app
- restore flows may need explicit recovery UI instead of silent fallback
- platform-specific persistence quirks, especially on web/browser targets, must be handled carefully

## Practical Guidance

- Treat `matrix_client.dart`, `client_manager.dart`, and verification/security surfaces as coordinated review areas.
- If a change touches login or restore, inspect storage, crypto, verification, and notification/account routing together.
- Do not merge “it logs in again so it’s fine” fixes if they damage trust continuity or encrypted usability.

## Review Trigger

Re-read this ADR when changing:

- login, logout, or restore behavior
- crypto persistence
- cross-signing or verification flows
- web/browser storage assumptions
