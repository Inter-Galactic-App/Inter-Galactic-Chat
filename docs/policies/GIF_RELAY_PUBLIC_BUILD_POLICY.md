# GIF Relay Public Build Policy

Publication status: draft release-readiness policy until the submitted build's
GIF provider path and disclosure copy are confirmed in
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

Public builds must not embed a direct GIF provider API key. GIF search should use a relay or provider configuration that can be rotated and rate-limited without shipping a new client.

## Requirements

- Public release builds must not embed a direct provider API key.
- Managed distributions may set `GIF_API_BASE_URL` for a relay they operate.
- Inter Galactic public builds default to the configured managed relay unless
  the build explicitly disables or overrides that relay.
- Builds without a managed relay must require users to add their own relay URL
  or provider API key in app settings before GIF search is available.
- Public release builds must fail or warn loudly if a direct provider API key is present.
- GIF search settings must disclose that search terms go to the relay/provider
  the user or build config selected.
- Logs must not include raw API keys, full search URLs with credentials, or user-identifying request metadata unless needed and redacted.
- Provider terms and privacy policy must be listed in third-party notices.

## Current Release-Readiness State

For the current public release path, fresh installs use the configured managed
Cloudflare Klipy relay. The app does not embed a direct Klipy provider API key;
for this managed-relay default path, the provider credential stays server-side
in the relay.

Users may still configure their own GIF relay URL or KLIPY API key locally. A
saved user relay takes precedence over the bundled managed relay, and the saved
GIF setup persists across app updates. Search terms and user-supplied direct
provider keys are sent to the selected relay/provider.

Ongoing release duties:

- Keep the managed relay rate-limited, rotatable, and disclosed before enabling
  it in public artifacts.
- Rotate any provider key that may already have been embedded in local or test
  builds.
- Keep the UI wording aligned with the active provider path: KLIPY for direct
  user keys, relay wording for user-managed relays, or generic GIF provider
  wording if the provider changes.

Keep those prerequisites synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
