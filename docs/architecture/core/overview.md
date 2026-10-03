# Overview

For the concise, source-routing architecture map, start with
[`system-overview.md`](system-overview.md). This page provides product framing
and broader context; `codebase-map.md` remains the folder-ownership guide.

## What Inter Galactic Is

Inter Galactic is a Matrix-native client built from the upstream Commet codebase and adapted toward a more community-oriented chat experience.

It is not a new protocol, a server replacement, or a proprietary messaging backend.

Core expectations:

- standard Matrix interoperability
- Synapse compatibility
- end-to-end encryption support
- multi-platform delivery through Flutter plus targeted native/plugin integrations

## Product Framing

Inter Galactic tries to improve usability, media interaction, and community/chat ergonomics without replacing Matrix concepts.

That means the app should still think in terms of:

- accounts
- devices
- rooms and spaces
- Matrix events and relations
- pushers and notification routing
- verification and trust state

## High-Level Architecture

At a high level, the app is split into five layers:

1. app shell
2. Matrix/domain layer
3. UI layer
4. platform/native layer
5. plugin layer

```text
Platform runner
  -> App shell/bootstrap
    -> Matrix/domain layer
      -> UI layer
    -> Platform services
    -> Plugin-backed capabilities
```

## Layer Breakdown

### App Shell

Primary role:

- start the app
- initialize configuration and preferences
- choose the right bootstrap/recovery path
- wire global services
- route into login, recovery, or main application flows

Typical code areas:

- `intergalactic/lib/main.dart`
- app bootstrap and service initialization code
- top-level navigation and startup decision points

### Matrix / Domain Layer

Primary role:

- own Matrix-facing behavior
- manage clients, accounts, sessions, and restore flows
- wrap SDK behavior in app-level components
- keep room/event/media/notification logic Matrix-compatible

Typical code areas:

- `intergalactic/lib/client/`
- especially `client_manager.dart`, `matrix_client.dart`, `matrix_room.dart`
- Matrix components under `intergalactic/lib/client/matrix/components/`

This is the highest-sensitivity layer for protocol correctness and E2EE safety.

### UI Layer

Primary role:

- render data and interaction surfaces
- gather user intent
- call domain actions without reimplementing protocol rules in widgets

Typical code areas:

- `intergalactic/lib/ui/`

Examples:

- settings pages
- room timeline UI
- message input and pickers
- recovery and verification screens

### Platform / Native Layer

Primary role:

- own OS-specific packaging and runtime integration
- bridge notifications, permissions, capabilities, and app startup behavior

Typical code areas:

- `intergalactic/android/`
- `intergalactic/ios/`
- `intergalactic/web/`
- `intergalactic/windows/`
- `intergalactic/linux/`
- `intergalactic/macos/`

This layer should stay thin where possible. Shared product logic should not live here unless the behavior is truly platform-specific.

### Plugin Layer

Primary role:

- isolate native or low-level capabilities behind explicit package boundaries
- expose stable Dart-facing APIs with safe fallback behavior

Typical code areas:

- `plugins/intergalactic_noise_suppression/`
- widget packages under `widgets/` when the feature is package-level rather than app-local

The plugin layer exists so platform-specific or native-risk code does not bleed into general app logic.

## Package Responsibilities

### `intergalactic/`

The main application package. This replaces the upstream `commet/` app folder.

### `tiamat/`

Shared UI/theming package. Use it when the change is design-system-level rather than screen-local.

### `widgets/`

Smaller shared packages such as widget APIs and calendar support.

### `plugins/`

Explicit native/plugin extensions.

### `docs/`

Developer-facing architecture, ADR, and contributor guidance.

## Major Runtime Flows

### Startup

Typical flow:

1. platform runner launches
2. desktop and mobile UI launches render a minimal Flutter startup shell before
   account restore
3. app bootstrap initializes preferences and services
4. stored accounts/session state is inspected
5. Matrix client restore path runs
6. crypto/session health is checked
7. app routes to login, recovery, or main UI

The startup shell lives in `intergalactic/lib/ui/pages/startup/` and is shown
from `main.dart` before `ClientManager.init()`. Desktop uses the phase/detail
layout; mobile uses the centered Inter Galactic icon and compact progress line
so launch does not sit on a blank frame while initialization continues. The
shell reports coarse, user-readable phases while preserving the existing fatal
error page, headless Android startup path, Matrix restore, login, recovery, and
main-shell routing.

### Messaging

Typical flow:

1. UI gathers user action
2. domain layer constructs the Matrix-safe operation
3. room/client layer sends or updates events
4. local state and timeline reconcile
5. UI rerenders from current domain state

### Notifications

Typical flow:

1. platform-specific notifier obtains permission/token/subscription
2. Matrix push component registers the pusher for the correct account
3. platform delivery arrives
4. shared notification routing resolves account and room context
5. UI navigation or background handling runs

### Media

Typical flow:

1. UI selects or references media
2. domain layer validates and prepares the payload
3. upload or fetch happens
4. event/timeline rendering consumes the normalized result
5. unsupported paths fail closed with visible fallback behavior

## Architecture Constraints

### Keep Matrix-native behavior

Do not replace Matrix room/event/session concepts with app-local shortcuts that only work in Inter Galactic.

### Keep E2EE and trust continuity intact

Do not trade away crypto persistence, verification, or device trust for convenience.

### Keep platform code isolated

Use conditional imports, platform guards, and plugin boundaries instead of spreading platform-specific assumptions across shared Dart code.

### Prefer targeted fixes over broad rewrites

This repo inherits real structure from upstream Commet. The default should be to improve existing seams, not rebuild the app around new abstractions unless there is a concrete payoff.

## Non-Goals

Inter Galactic is not trying to:

- become a non-Matrix backend
- replace Synapse behavior with app-local protocol rules
- weaken verification or trust semantics to reduce friction
- hide platform differences by pretending they do not exist
- move all native capability work into shared Dart code
- make `dist/` or generated build output the source of truth

## When To Read Which Doc Next

- Read `codebase-map.md` when you need folder ownership.
- Read `../matrix/matrix-e2ee.md` before changing login, restore, verification, or crypto behavior.
- Read `../notifications/notifications.md` before touching push, badge, routing, or notifier code.
- Read `../calls-streaming-audio/media-and-plugins.md` before touching GIFs, attachments, previews, stickers, emoji, or native media plugins.
- Read `../calls-streaming-audio/livekit-gameplay-streaming.md`,
  `../calls-streaming-audio/streaming-guidance-status.md`, and `../calls-streaming-audio/stream-optimization-report.md`
  before changing LiveKit/WebRTC gameplay streaming behavior.
- Read `../matrix/room-settings-and-permissions.md` before changing room member role editing or permission-requirement UI.
- Read `../features/rich-presence-activity.md` before changing local activity cards, Spotify, Steam, or Matrix status publishing.
- Read `../release/release-targets.md` before changing packaging, manifests, release scripts, or updater assumptions.
- Read `change-guide.md` before starting cross-cutting work.

## Open Architecture Questions

- Confirm current store/distribution usage inside `fastlane/metadata/` before
  documenting lane-specific release policy.
- Confirm whether installed/PWA-style web behavior is still a release target
  before adding stronger web-install guidance beyond browser support.
