# ADR 0003: Plugin Strategy

## Status

Accepted

## Context

Inter Galactic increasingly needs targeted native capabilities such as:

- audio processing
- lower-level media handling
- platform-specific runtime integrations

Those features often need:

- native code
- FFI
- platform-specific packaging
- lifecycle and cleanup rules that do not belong in general chat/domain logic

The repo already reflects this with an explicit plugin boundary such as:

- `plugins/intergalactic_noise_suppression/`

## Decision

Native/plugin functionality stays behind explicit plugin boundaries instead of being spread across general app code.

That means:

- native code belongs in `plugins/` or platform runner code, not arbitrary shared Dart files
- the main app talks to plugins through stable Dart-facing APIs
- unsupported platforms must have safe fallback behavior
- plugin lifecycle must be reviewable separately from general product logic

## Consequences

### Positive

- native risk is easier to isolate
- plugin packaging and lifecycle are easier to review
- shared app code stays more portable
- unsupported-platform behavior can be stubbed explicitly

### Negative

- plugin changes often require coordination across package boundaries
- packaging/release review gets slightly more complex
- contributors need to inspect both app-side usage and plugin-side lifecycle

## Practical Guidance

- If a feature needs native code, first ask whether it belongs in a plugin boundary.
- Do not hard-code plugin assumptions directly into unrelated chat/session/UI code.
- Always document fallback behavior when a plugin is unavailable.
- Verify registration, initialization, and shutdown paths together.

## Review Trigger

Re-read this ADR when:

- adding a new plugin
- moving native logic out of app code into a plugin
- changing plugin packaging or runtime assumptions
