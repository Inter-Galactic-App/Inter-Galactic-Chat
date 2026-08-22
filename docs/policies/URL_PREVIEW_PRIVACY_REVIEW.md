# URL Preview Privacy Review

Publication status: S&C-reviewed current policy. New installs keep encrypted
room URL previews off until the user makes a first-use choice; existing
installs preserve their prior encrypted-room preview setting when that state is
already distinguishable.

URL previews can disclose a URL from a private or encrypted conversation to a homeserver preview endpoint, a configured preview service, or a direct fetcher. This is a privacy-sensitive feature.

## Public Release Policy

- Disclose URL preview behavior in the privacy policy.
- Give users a clear setting for URL previews.
- Use extra caution in encrypted rooms.
- Add first-use consent, or default encrypted-room previews off, before
  treating encrypted-room URL previews as fully release-complete while the
  feature remains enabled by default.
- Avoid direct fetching of private-network, localhost, metadata-service, or non-public URLs.
- Redact sensitive URL query parameters from logs.

## Matrix-Specific Caveat

If a selected homeserver generates the preview, that homeserver may see the URL even when the Matrix room is end-to-end encrypted. If a remote preview service or direct fallback is used, that service may see the URL and request metadata.

## Current Implementation Notes

- The direct client fallback now rejects unsafe schemes, localhost,
  `.localhost`/`.local` hosts, metadata-service hostnames, private/link-local
  literal IPs, reserved literal IPs, and redirects to blocked targets before
  document, JSON, HTML, or thumbnail fetches are attempted.
- Durable preview cache writes are keyed by normalized URL hash and only store
  sanitized preview metadata; token-like URL/query/fragment shapes are not
  persisted.
- Volatile social CDN thumbnail URLs may be cached separately for a short
  12-hour window so previews survive room reentry without treating signed
  provider thumbnails as five-day durable metadata. These transient thumbnail
  writes use the same safe-URI and sensitive-query rejection rules.
- Encrypted-room preview fetches are gated through the consent-aware runtime
  helper. New installs do not fetch encrypted-room previews until consent is
  recorded; existing installs with a prior setting keep that setting.
- The optional Inter Galactic preview-service endpoint is a build-time setting
  and remains disabled by default. When configured, the app only calls it for
  the build's allowed homeserver/member domains so a public build does not send
  other homeserver users' URLs to an operator-managed preview cache.
- Runtime diagnostics for the optional Inter Galactic preview-service path are
  intentionally non-secret: they report whether the service is configured,
  homeserver-scoped, blocked, invalid, or cooling down, but they do not print
  the configured endpoint, allowlist, preview URL, or Matrix user ID.
- Preview-service failure diagnostics may include HTTP status or error class
  so operators can distinguish rate limits/server errors from transient
  connection drops without logging the full URL or host.

## Current S&C Classification

S&C reviewed the current implementation posture against the encrypted-room
consent/default-off decision, the direct fallback guards, the durable cache
contract, and the public policy disclosures.

- Encrypted-room default: new installs are default-off until first-use consent;
  existing installs preserve a prior encrypted-room preview setting when one is
  already present.
- User control: Settings exposes an encrypted-room URL-preview toggle, and the
  first-use setup choice records whether encrypted-room previews stay off or are
  allowed.
- Fetch path: Matrix homeserver preview API first. The optional Inter Galactic
  preview service remains build-time configured, scoped, and disabled by
  default.
- Direct fallback: limited to TikTok, Instagram, and Reddit provider adapters,
  with scheme, host, DNS, private/link-local/reserved IP, and redirect safety
  checks before fetches.
- Cache and diagnostics: durable cache keys are normalized URL hashes and store
  sanitized preview metadata; diagnostics use status/error class rather than
  full URLs or hosts.

S&C decision: the current policy posture is release-ready when the release
record and public tracker confirm the consent/default-off implementation is in
the candidate build and no validation exposes raw URL logging, unsafe fallback
fetching, or preview-service scope drift.

## Remaining Release-Readiness Follow-Up

- Release Pipeline: confirm the release candidate includes the consent-aware
  encrypted-room preview gating before closing the public tracker row.
- QA/user: if device proof is requested, capture setting/default and preview
  behavior without logging raw URLs or Matrix content.

Keep this follow-up synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.
