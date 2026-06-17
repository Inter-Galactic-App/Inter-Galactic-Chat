# Rich Presence Activity System

Date: 2026-04-24

## Ownership

Inter Galactic activity/rich presence is owned by a transport-agnostic
`ActivityService` layer under `intergalactic/lib/client/components/activity/`.
It is not a Spotify-only feature and it is not a replacement for Matrix
presence.

The Activity layer is responsible for:

- normalizing music, game, call, screen-share, and custom activities into
  `UserActivity`
- merging multiple `ActivitySource`s into one selected local activity
- applying privacy settings before UI or publishers see the activity
- exposing optional `ActivityControl`s owned by the source that created them
- formatting simple Matrix presence summaries through publisher adapters

## Matrix Boundary

Matrix `m.presence` only supports basic presence state plus `status_msg`. Use it
only for optional simple summaries such as `Listening to Artist - Track` or
`Playing Game`.

Do not treat Matrix account data as remote rich presence. Account data is useful
for local settings/cache or the user's own devices, but other users do not
receive it as a live activity feed.

Rich remote metadata, if added later, needs a separate Matrix-compatible
distribution decision before using the `space.ourgalaxy.activity` namespace.

## Privacy Rules

- Activity is off by default.
- Local rendering is opt-in through `activity_show_locally`.
- Source families are separately gated, starting with Spotify and game toggles.
- `activity_hide_current` suppresses the selected activity without clearing the
  source state.
- Do not publish executable paths, private window titles, process paths, raw
  local metadata, OAuth tokens, or device identifiers.
- Game status detection must use approved display metadata rather than raw
  process/window data.

## Current Implementation

Implemented:

- `ActivityKind`, `ActivityVisibility`, `UserActivity`, and `ActivityControl`
- `ActivitySource`, `GameActivitySource`, `MusicActivitySource`,
  `ActivityPublisher`, and `ActivityRenderer`
- `ActivityService` source merging, local privacy filtering, source priority,
  publisher hooks, and the local `currentActivities` list used by UI surfaces
  that need to show more than the selected primary activity
- settings preferences for local display, source family gates, hide-current,
  and future publish switches
- `Settings > App Settings > Activity`
- a compact local activity card above the lower-left user panel on desktop and
  mobile navigation; desktop small-window compact rail mode also exposes the
  same card and playback controls from the current-user avatar popover
- a desktop account popup anchored to the lower-left user bar. It shows a
  compact profile summary, editable status, account actions, and an activity
  view that can show an alternate local activity when multiple sources are
  active
- local activity rotation through `ActivityService.selectNextLocalActivity()`.
  When more than one source is active, rotating swaps the selected activity
  shown by the existing activity card and the foremost activity shown by the
  desktop account popup
- a developer-only mock music source with disabled control placeholders
- Spotify framework classes for PKCE authorization request generation,
  token-store boundaries, current-playback API polling, playback parsing, and
  degraded local Activity states
- Spotify connect/disconnect settings UI and Authorization Code with PKCE token
  exchange/refresh
- secure Spotify token persistence through `SecureSpotifyTokenStore`
- Spotify playback controls for previous, play/pause, and next through source
  owned Web API calls
- Spotify saved-track state plus a local like/unlike control backed by the
  current track URI
- Spotify degraded/no-song states use `ActivityVisibility.off`, so they can
  clear local/published activity without losing source status information
- iOS local media controls through `LocalMediaActivitySource`, backed by the
  `chat.intergalactic.app/local_media_controls` method channel and the native
  system music player bridge
- opt-in Matrix `status_msg` publishing through `MatrixActivityPresencePublisher`
  for simple summaries only
- Steam game activity through `SteamActivitySource`, gated by
  `activity_show_game`, `activity_steam_id`, and build-time
  `STEAM_ACTIVITY_API_BASE_URL`
- Steam Activity settings are hidden on mobile because the current source is a
  desktop/internal-build Web API configuration path, not native mobile media or
  game detection

Deferred:

- native game/process detection
- remote rich metadata publishing

## Spotify Framework Boundary

Spotify is represented as an `ActivitySource`, not as a standalone widget.
`SpotifyActivitySource` stays inactive until `activity_show_spotify` is enabled.
When enabled without credentials or tokens, it emits a degraded local activity
state instead of attempting unsafe token storage or background polling.

Build-time configuration is read from:

- `SPOTIFY_CLIENT_ID`
- `SPOTIFY_REDIRECT_URI`

These build values are defaults, not the only supported configuration path.
`Settings > App Settings > Activity > Spotify connection` lets users open setup
instructions and save their own Spotify developer app Client ID plus Redirect
URI in preferences (`activity_spotify_client_id` and
`activity_spotify_redirect_uri`). Inter Galactic uses Authorization Code with
PKCE, so users should not enter or store a Spotify Client Secret in the app.
Changing the stored Client ID or Redirect URI clears the saved Spotify token so
the next connection is issued against the matching developer app.
When a build provides Spotify defaults, the app also remembers those non-empty
values as previous-build fallbacks. Explicit user-entered values still win and
current build values are preferred over remembered ones, but a later update
that omits the build defines will not make an existing Spotify token look
disconnected solely because the bundled auth config disappeared.
Emergency revocation is explicit rather than omission-based: a release that
must disable bundled Spotify defaults should ship a config migration that clears
`activity_spotify.last_build_client_id` and
`activity_spotify.last_build_redirect_uri`, then record the revocation in the
release notes. Removing the Dart defines alone is not a revocation path because
existing clients can still use remembered previous-build values.

Windows release builds get those values through maintainer build inputs that
forward them to `scripts/build_release.dart` as Dart defines. If a client id
exists without an explicit redirect, the Windows build defaults the redirect to
`http://127.0.0.1:3001/spotify` to match Spotify's loopback redirect
requirements.

The OAuth helper uses Spotify's Authorization Code with PKCE shape for desktop,
mobile, and web-style clients where a client secret should not be stored in the
app. The current implementation can exchange authorization codes and refresh
expired access tokens when a refresh token is available.

Tokens are stored through `SecureSpotifyTokenStore`, backed by
`flutter_secure_storage`, so the Spotify connection survives app restarts. Do
not replace this with `SharedPreferences`; refresh tokens must remain in an OS
credential/keychain-style store.

Playback polling is implemented against Spotify's playback-state endpoint
behind `SpotifyApiClient`, with an available-devices fallback when Spotify
returns no playback content. It maps playing, paused, available-device/no-track,
no-device, unavailable, unauthorized, token-expired, rate-limited, and error
states into `UserActivity`. Only playable track states are visible activity;
degraded/no-song states are intentionally invisible so the local controller
autohides and Matrix status clears when no song is active. The default poll
interval is short enough for activity UI updates after external skips/song
changes, but this is still polling and should not become a high-frequency
transport.

Playback controls are source-owned and transport-agnostic: the compact activity
card forwards an `ActivityControl` id back to the source that produced it.
Spotify currently handles previous, play/pause, next, save current track, and
remove saved current track. The default OAuth scopes include playback-state
read, playback modification, and library read/write:

- `user-read-currently-playing`
- `user-read-playback-state`
- `user-modify-playback-state`
- `user-library-read`
- `user-library-modify`

Users with tokens from the earlier read-only implementation must reconnect
Spotify before controls or like/unlike can enable. Spotify playback commands
may still fail or remain unavailable when the account, active device, Premium
state, or Spotify Connect target does not allow remote control.

The player API can briefly return no content while Spotify is changing tracks
or while the desktop client is restarting. Do not immediately treat that as an
authorization failure. Querying available Spotify Connect devices lets the UI
show `Spotify ready` when a device exists but no track is active yet, which is
less misleading than `No active Spotify device`.

Mobile note: the current Spotify integration is the Spotify Web API plus PKCE
OAuth path. Android and iOS phone builds use the
`intergalactic-spotify://callback` deep link when the build provides
`SPOTIFY_REDIRECT_URI=intergalactic-spotify://callback`. Native OS media
session controls stay separate from `SpotifyActivitySource`.

## Mobile Local Media Controls Boundary

`LocalMediaActivitySource` is the mobile-native music-control foundation. It is
a separate `MusicActivitySource` so remote API sources such as Spotify can keep
their desktop/web behavior and OAuth assumptions.

The first supported platform is iOS. The Dart bridge lives under
`intergalactic/lib/client/components/activity/sources/local_media/`, and the
native channel is implemented in `ios/Runner/AppDelegate.swift` as
`chat.intergalactic.app/local_media_controls`. Unsupported platforms return an
unsupported snapshot and should stay quiet until their own platform bridge is
designed.

The iOS bridge uses Apple's system music player APIs, so it is best treated as
Apple Music / local system-player control. Public iOS APIs do not provide a
general-purpose controller for arbitrary third-party now-playing apps, so do
not route Spotify, YouTube Music, or other mobile services through this source
unless a source-specific native/API integration is added later.

Controls remain source-owned: the activity card sends `previous`,
`play_pause`, or `next` back to `LocalMediaActivitySource`, which maps those to
the platform channel. The source polls at a modest interval and emits visible
activity only for playing/paused snapshots.

Android currently does not have a native media-session bridge for local device
playback. Keep Android phone activity on the Spotify source until an Android
method channel is designed for media sessions and permission behavior.

## Steam Game Activity Boundary

Steam is the first approved game activity source. It is intentionally Web
API-first and must not be replaced with an exhaustive `.exe` list.

`SteamActivitySource` reads:

- `BuildConfig.STEAM_ACTIVITY_API_BASE_URL`
- `preferences.activitySteamId`
- `preferences.activityShowGame`

It calls the configured server-side Steam activity proxy with the SteamID64 as
the `steamids` query parameter and expects a sanitized response compatible with
`ISteamUser/GetPlayerSummaries`.
The client must not ship a privileged Steam Web API key. The source emits a
`UserActivity` only when the response includes current-game metadata
(`gameid` and `gameextrainfo`). The emitted activity uses provider `steam`,
kind `game`, the game title from Steam, a Steam store URL derived from the app
id, game artwork from a proxy-provided absolute thumbnail/artwork URL when
available, and a deterministic Steam CDN capsule image as fallback. Visibility
stays self-only until the user opts into publishing through the shared Activity
settings.

If the proxy URL, SteamID64, profile visibility, or current-game fields are
missing, the source emits no activity. This is deliberate: do not infer game
status from local process names, raw window titles, executable paths, or
private local metadata. If native detection is added later, keep it behind
`GameActivitySource` and map it through approved display metadata before it can
reach UI or Matrix presence.

When Steam later reports no active game, the source must emit `null` so the
local activity card clears and `MatrixActivityPresencePublisher` can clear any
owned Matrix status summary. Matrix SDK `setPresence(..., statusMsg: null)`
omits the JSON field, so Inter Galactic clears owned activity summaries by
sending an empty status string and treating blank received `status_msg` values
as no custom status locally.

Windows release builds can pass `STEAM_ACTIVITY_API_BASE_URL` to
`scripts/build_release.dart` as a Dart define. Store the actual Steam Web API
key only in the server/proxy environment for public builds. Private/internal
build shortcuts may still support direct-key fallback, but public build docs
and release logs must never expose that key.
The client remembers the last non-empty bundled Steam activity proxy URL as a
previous-build fallback. A saved SteamID64 remains the user-owned connection
setting, while the proxy fallback prevents an update with a missing
`STEAM_ACTIVITY_API_BASE_URL` define from disabling polling for users who were
already configured on the managed proxy path.
Emergency revocation is explicit here too: a release that must disable the
managed Steam proxy fallback should ship a config migration that clears
`activity_steam.last_build_api_base_url` and records that revocation in the
release notes. Omitting `STEAM_ACTIVITY_API_BASE_URL` from a later build does
not clear remembered proxy values.

## Testing

Current automated tests cover:

- default-private behavior
- local rendering when settings allow it
- hide-current suppression
- independent Spotify/game source gating
- simple Matrix presence summary formatting
- publisher hook invocation when publishing is enabled
- compact activity widget rendering and hidden-state behavior
- Spotify PKCE request construction
- Spotify token exchange and refresh response handling
- Spotify current-playback parsing
- Spotify source disabled/not-connected/token-backed polling behavior
- Spotify source expired-token refresh before playback polling
- Spotify player-control command dispatch
- Spotify library save/remove command dispatch and saved-track UI refresh
- Steam current-game parsing, API request construction, disabled/missing config
  behavior, proxy-provided and deterministic artwork URLs, active-game
  emission, and no-active-game clearing

Manual validation should cover the Activity settings page, lower-left panel
layout at desktop/mobile widths, Spotify connect/disconnect, playback controls,
like/unlike, app restart token persistence, autohide when Spotify has no
playable track and no game is active, SteamID64 configuration on desktop,
hidden Steam settings on mobile, Steam game activity with a visible current
game, opt-in Matrix status publishing and clearing, and the developer mock
source before adding native game detection or remote rich metadata publishing.
