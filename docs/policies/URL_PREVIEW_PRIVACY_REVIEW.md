# URL Preview Privacy Review

Publication status: current policy. New installs keep encrypted
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
- For homeserver and configured-service previews, display only thumbnails
  served from the homeserver as `mxc://` media. When the user separately
  enables direct fallback for the room type, TikTok, Instagram, and Reddit
  provider adapters may fetch thumbnail bytes directly from a provider or its
  image host. An otherwise complete card with no image may also fetch a
  provider site icon. Disclose both requests at the opt-in control.
- Redact sensitive URL query parameters from logs.

## Matrix-Specific Caveat

If a selected homeserver generates the preview, that homeserver may see the URL even when the Matrix room is end-to-end encrypted. If a remote preview service or direct fallback is used, that service may see the URL and request metadata.

A homeserver or configured-service response can carry a thumbnail URL rather
than image bytes. Displaying a third-party URL directly would be a second,
separate disclosure: the client would contact the image host and expose the
device's network address and request metadata for a link the user may only
have read inside an encrypted room. The homeserver's `preview_url` endpoint
avoids this by downloading the image into its own media repository and returning an
`mxc://` URI, which the client fetches from the homeserver like any other
Matrix media. With the separate direct-fallback opt-in, a supported provider
adapter may instead fetch the image from the provider or its CDN. An imageless
card may also request a provider site icon even if its metadata is complete.
That image host can see the device's network address and request metadata even
when the preview URL was first sent to a homeserver or configured service.

## Current Implementation Notes

- The direct client fallback now rejects unsafe schemes, localhost,
  `.localhost`/`.local` hosts, metadata-service hostnames, private/link-local
  literal IPs, reserved literal IPs, and redirects to blocked targets before
  document, JSON, HTML, or thumbnail fetches are attempted.
- Durable preview cache writes are keyed by normalized URL hash and only store
  sanitized preview metadata; token-like URL/query/fragment shapes are not
  persisted.
- A preview built from a homeserver or preview-service response only displays
  its image when the response gives it as an `mxc://` URI, which is fetched
  from the homeserver's media/thumbnail endpoint. An `http`/`https` image URL
  in that response is dropped rather than displayed, because rendering it
  would make the client contact the origin CDN. Where a response carries both
  an `mxc://` value and a scraped `https` one, the `mxc://` value is used.
  There is no Matrix endpoint that proxies an arbitrary third-party URL, so a
  preview whose image cannot be expressed as `mxc://` does not use that remote
  thumbnail. Under the separate direct-fallback opt-in, it may still acquire a
  provider thumbnail or site icon.
- The card can still recover an image on the hosts that are already
  allowlisted for a direct fetch: dropping the image marks the preview so the
  missing-image refresh path may ask the existing provider adapters, which
  contact those hosts anyway. No host becomes reachable that was not already.
- After the preferred service/homeserver response, a separate site-icon
  fallback may contact an allowlisted provider for an imageless card even when
  the card has enough metadata to skip direct metadata fetching. It requires
  the same room-type direct-fallback opt-in and does not run on Web.
- Volatile social CDN thumbnail URLs may be cached separately for a short
  12-hour window so previews survive room reentry without treating signed
  provider thumbnails as five-day durable metadata. These transient thumbnail
  writes use the same safe-URI and sensitive-query rejection rules, and they
  now only ever hold a thumbnail that came from an allowlisted direct fetch.
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
- Direct fallback is limited to the TikTok, Instagram, and Reddit provider
  adapters. It is not a general-purpose fetcher for arbitrary hosts.

Keep this page synchronized with `PUBLIC_RELEASE_READINESS_TRACKER.md`, which
carries the release-readiness state for the behaviour described above.
