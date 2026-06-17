# GIF Relay Public Build Policy

Publication status: draft release-readiness policy until the submitted build's
GIF provider path and disclosure copy are confirmed in
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

Public builds must not embed a direct GIF provider API key. GIF search should use a relay or provider configuration that can be rotated and rate-limited without shipping a new client.

## Requirements

- Public release builds must not embed a direct provider API key.
- Managed distributions may set `GIF_API_BASE_URL` for a relay they operate.
- Builds without a managed relay must require users to add their own relay URL
  or provider API key in app settings before GIF search is available.
- Public release builds must fail or warn loudly if a direct provider API key is present.
- GIF search settings must disclose that search terms go to the relay/provider
  the user or build config selected.
- Logs must not include raw API keys, full search URLs with credentials, or user-identifying request metadata unless needed and redacted.
- Provider terms and privacy policy must be listed in third-party notices.

## Current Release-Readiness State

For the current public release path, users may configure either their own KLIPY
API key or their own GIF relay URL. The saved GIF setup persists across app
updates. Inter Galactic does not ship a public provider key by default.

Ongoing release duties:

- If a managed relay is added later, keep it rate-limited, rotatable, and
  disclosed before enabling it in public artifacts.
- Rotate any provider key that may already have been embedded in local or test
  builds.
- Keep the UI wording aligned with the active provider path: KLIPY for direct
  user keys, relay wording for user-managed relays, or generic GIF provider
  wording if the provider changes.

Keep those prerequisites synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
