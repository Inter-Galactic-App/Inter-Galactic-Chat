# Codebase Map

## Purpose

This file is the quickest repo-orientation guide for Inter Galactic.

Use it when you need to answer:

- where the main app lives
- which package owns a change
- which folders are product code vs release/config infrastructure
- where to start by change type without grepping the whole repo first

## Repository Shape

Inter Galactic is a forked and renamed Matrix client monorepo.

- `intergalactic/` is the main Flutter app package and replaces the upstream `commet/` app folder.
- `tiamat/` is a separate shared UI package.
- `widgets/` holds smaller shared widget packages.
- `plugins/` contains native/plugin extensions that are intentionally isolated from the main app.
- repo-root folders such as `fastlane/`, `docs/`, and `.github/` support release, automation, and documentation.

## Root Tree

```text
inter-galactic/
├── .github/                 CI and workflow definitions
├── archive/                 Archived workflows and legacy repo material
├── dist/                    Built release artifacts and generated website/update output
├── docs/                    App architecture, release, testing, design, product, ADR, and policy notes
├── fastlane/                Store/release metadata and lane support files
├── intergalactic/           Main Flutter app package (renamed from upstream commet/)
├── plugins/                 Native/plugin packages used by the app
├── tiamat/                  Shared UI/theming package
├── widgets/                 Shared widget packages
├── CHANGE_LOG.md            Internal repo changelog
├── CONTRIBUTING.md          Contributor guidance
├── pubspec.yaml             Repo workspace/package configuration
└── windows_installer.iss    Windows installer definition
```

## Top-Level Folder Roles

### `intergalactic/`

The main app package.

This is where most product changes land:

- Flutter entrypoint and app bootstrap
- Matrix/domain logic
- UI pages, components, and feature flows
- platform runners for Android, iOS, web, Windows, Linux, and macOS
- app-specific scripts such as release/build helpers

High-value subfolders:

- `intergalactic/lib/`
- `intergalactic/scripts/`
- `intergalactic/android/`
- `intergalactic/ios/`
- `intergalactic/web/`
- `intergalactic/windows/`
- `intergalactic/linux/`
- `intergalactic/macos/`

### `tiamat/`

Shared UI package used by the app for reusable design primitives and presentation helpers.

Start here when:

- a styling change is global rather than feature-local
- multiple pages use the same tile/button/panel pattern
- a visual behavior feels package-level instead of app-feature-level

Verify current path inside the package before making assumptions about component ownership.

### `widgets/`

Small shared widget packages. Current visible packages include:

- `widgets/calendar/`
- `widgets/matrix_widget_api/`

Start here when:

- a reusable widget package has its own lifecycle or web/native behavior
- the change affects embedded widgets rather than the main app shell
- a package under `widgets/` is imported by multiple app areas

### `fastlane/`

Release automation and metadata support.

Current visible content is `fastlane/metadata/`. Treat this folder as release/distribution infrastructure, not runtime app logic.

Start here when:

- release notes, screenshots, or store metadata need updates
- a release lane assumption looks wrong
- packaging automation refers to fastlane-managed metadata

### `docs/`

Public contributor and maintainer documentation.

Use this folder to capture:

- architecture overviews
- active design-system guidance under `docs/design/`
- release runbooks and test matrices under `docs/release/`
- focused/manual QA guidance under `docs/testing/`
- beta feedback and product planning templates under `docs/product/`
- ADRs
- contributor guidance that should outlive a single fix

Private infrastructure operations and security runbooks may exist in maintainer
workspaces outside this repository. Public app-repo docs should not require
those private paths for ordinary setup.

For UI, settings, theme, spacing, mobile surface, and component-standardization
work, start with `docs/design/INTERGALACTIC_DESIGN_SYSTEM.md` and the companion
files in `docs/design/`, then verify the current implementation anchors before
editing app or Tiamat code.

### Platform folders

Inside `intergalactic/`, each platform folder is the runner/integration layer for that target:

- `intergalactic/android/`
- `intergalactic/ios/`
- `intergalactic/web/`
- `intergalactic/windows/`
- `intergalactic/linux/`
- `intergalactic/macos/`

These folders usually own:

- native manifests and entitlements
- plugin registration
- OS-specific startup and capability wiring
- packaging/build configuration

They should not be the first place you edit for cross-platform domain behavior unless the bug is platform-specific.

### `plugins/`

Native/plugin packages that extend the app through explicit boundaries.

Current visible plugins:

- `plugins/intergalactic_noise_suppression/`
- `plugins/intergalactic_windows_share/`

This is the right place for:

- native audio processing
- FFI/plugin lifecycle
- bundled third-party native code
- unsupported-platform stubs and fallback behavior

### `scripts`

Inside `intergalactic/scripts/`.

Current visible scripts include:

- `build_release.dart`
- `generate_update_manifest.dart`
- `prepare-web.sh`
- `setup_android_release.dart`
- `codegen.dart`

Start here when:

- build output or update manifests are wrong
- release packaging assumptions changed
- generated artifacts need to stay in sync with runtime expectations
- web build preparation or platform defines changed

## Main App Package Layout

The main app package has this practical split:

```text
intergalactic/
├── android/                 Android runner and native config
├── ios/                     iOS runner and native config
├── lib/                     Main Dart application code
├── linux/                   Linux runner
├── macos/                   macOS runner
├── scripts/                 App build/release helper scripts
├── web/                     Browser bootstrap assets and service worker scope
└── windows/                 Windows runner and packaging integration
```

### `intergalactic/lib/`

This is the main source tree for product behavior.

Useful mental split:

- `lib/client/` = Matrix/domain/application logic
- `lib/client/demo/` = local-only offline demo client and seeded sample data
- `lib/ui/` = pages, widgets, and user interaction flow
- `lib/config/` = build flags, preferences, and configuration defaults
- `lib/service/` = app/background services
- `lib/utils/` = shared helpers
- `lib/generated/` = generated localization and codegen output; verify before editing by hand

### `lib/client/`

Owns high-sensitivity product behavior:

- client lifecycle and account/session management
- Matrix wrappers and domain components
- notifications, media, and feature components
- room/message/event behavior
- VoIP/media processing integration

Examples visible in the repo:

- `lib/client/client_manager.dart`
- `lib/client/demo/demo_client.dart`
- `lib/client/matrix/matrix_client.dart`
- `lib/client/matrix/matrix_room.dart`
- `lib/client/components/push_notification/...`
- `lib/client/components/voip/...`

### `lib/ui/`

Owns presentation and user-driven interaction:

- pages and settings screens
- pickers, cards, dialogs, and message input
- routing outcomes after shared logic decides what should happen

Examples visible in the repo:

- `lib/ui/molecules/message_input.dart`
- `lib/ui/molecules/gif_picker.dart`
- `lib/ui/pages/settings/...`

### `lib/config/`

Owns build-time and user-configured behavior:

- `lib/config/build_config.dart`
- `lib/config/preferences.dart`

If a change depends on environment variables, push gateway defaults, release hosts, or persisted toggles, check this folder first.

### `lib/service/`

Use this when the change involves background or long-running work such as Android notification/background service orchestration.

### `lib/generated/`

Generated output such as localization files. Do not hand-edit unless the repo explicitly treats a file as manually maintained.

## Where To Start By Change Type

### Login, session restore, account switching

Start with:

- `intergalactic/lib/client/client_manager.dart`
- `intergalactic/lib/client/matrix/matrix_client.dart`
- `intergalactic/lib/client/matrix/auth/...`
- `intergalactic/lib/ui/pages/login/...`

Also inspect:

- `intergalactic/lib/config/preferences.dart`
- web-only restore/bootstrap code under `intergalactic/lib/client/matrix/web/`

Main shell account focus is stored in
`preferences.filterClient` (`filter_client_id`) and restored by
`MainPageState`. Account-switching changes must preserve both restore timings:
the saved client may already be in `ClientManager.clients` at `MainPage`
startup, or it may be added shortly afterward during session restore. The side
navigation rail receives the restored filter as a widget prop so spaces,
invitations, and room lists do not fall back to the merged-account view.
The shared `Client.onSelfUpdated` stream is the shell-level signal that an
account's own profile/avatar changed after cached or remote profile refresh;
`ClientManager.onClientUpdated` forwards it to account rails and Home/status
surfaces that cache self profile data. Fresh login/add-account flows can finish
client initialization before the shell calls `ClientManager.addClient`, so
`addClient` also publishes the current self-profile snapshot after subscribing
to future `onSelfUpdated` events. This keeps first-sign-in avatars from waiting
for a restart or a later profile refresh event.

### Matrix E2EE, verification, trust continuity

Start with:

- `intergalactic/lib/client/matrix/matrix_client.dart`
- `intergalactic/lib/client/matrix/components/key_verification_component/...`
- `intergalactic/lib/ui/pages/settings/categories/account/security/matrix/...`
- `intergalactic/lib/ui/pages/matrix/verification/...`

### Direct messages, room classification, spaces

Start with:

- `intergalactic/lib/client/matrix/components/direct_messages/`
- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/matrix_space.dart`
- `intergalactic/lib/client/client_manager.dart`

Matrix `m.direct` is the preferred DM signal. Inter Galactic also stores a
private app-owned direct-room marker for rooms it creates through the DM flow,
so a true one-to-one chat can stay a DM if `m.direct` account data is late or
missing. The joined-member fallback is deliberately narrower: it can rescue a
complete non-space room with exactly the local user and one other joined
member, but it must not classify rooms with known `m.space.parent` state or
rooms already present under a known space as DMs. If changing space sync,
`m.direct`, room creation, or Home/sidebar room grouping, validate both a real
DM with missing/stale `m.direct` and a two-member room inside a space.

### Notifications

Start with:

- `intergalactic/lib/client/components/push_notification/...`
- `intergalactic/lib/client/matrix/components/push_notifications/matrix_push_notification_component.dart`
- `intergalactic/lib/service/background_service.dart`
- `intergalactic/lib/service/background_service_notifications/...`
- `intergalactic/lib/ui/pages/settings/categories/app/notification_settings/...`

Inspect all platform implementations before shipping notification changes.

### Message send, room behavior, mentions, replies, reactions

Start with:

- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/room.dart`
- `intergalactic/lib/ui/organisms/chat/...`
- `intergalactic/lib/ui/molecules/message_input.dart`
- timeline event classes under `intergalactic/lib/client/matrix/timeline_events/...`

### UI, settings, and design-system work

Start with:

- `docs/design/INTERGALACTIC_DESIGN_SYSTEM.md`
- `docs/design/UI_GUIDELINES.md`
- `docs/design/COMPONENT_PATTERNS.md`
- `docs/design/LAYOUT_AND_SPACING.md`
- `docs/design/THEME_GUIDELINES.md` for theme/token/custom-theme work
- `intergalactic/lib/ui/pages/settings/...` for settings surfaces
- `intergalactic/lib/ui/mobile/...` for mobile visual primitives
- `tiamat/lib/atoms/...` for shared UI primitives

Also inspect `docs/architecture/core/change-guide.md` for UI/design-specific
review checks before editing.

### Media upload, GIFs, stickers, emoji/custom packs

Start with:

- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/components/gif/matrix_gif_component.dart`
- `intergalactic/lib/client/matrix/components/emoticon/...`
- `intergalactic/lib/ui/molecules/gif_picker.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`

### Link previews and remote content fetches

Start with:

- `intergalactic/lib/client/matrix/components/url_preview/...`
- rendering surfaces in `intergalactic/lib/ui/...`

### Web/browser behavior

Start with:

- `intergalactic/lib/client/matrix/web/...`
- `intergalactic/lib/client/components/push_notification/web/...`
- `intergalactic/lib/client/matrix/auth/web/...`
- `intergalactic/web/`

Also inspect conditional imports before changing shared files.

### Native/plugin-backed media or VoIP behavior

Start with:

- `plugins/intergalactic_noise_suppression/`
- `intergalactic/lib/client/components/voip/...`
- `intergalactic/lib/client/matrix/components/voip/...`
- `docs/architecture/calls-streaming-audio/media-and-plugins.md`
- `docs/architecture/calls-streaming-audio/rnnoise-native-resampler-plan.md`

### Release/update/build output

Start with:

- `intergalactic/scripts/build_release.dart`
- `intergalactic/scripts/generate_update_manifest.dart`
- `intergalactic/scripts/prepare-web.sh`
- repo-root `windows_installer.iss`
- repo-root `fastlane/`
- runtime update entry points:
  `intergalactic/lib/main.dart` and
  `intergalactic/lib/utils/update_checker_io.dart`

If the issue mentions `latest.json`, packaging, IPA/APK output, or desktop updater behavior, do not limit the review to app Dart code.

## Practical Ownership Rules

- Put Matrix/domain rules in `intergalactic/lib/client/`.
- Put presentation changes in `intergalactic/lib/ui/`.
- Put global design-system changes in `tiamat/` when appropriate.
- Put platform runner changes in `intergalactic/<platform>/`.
- Put plugin/native extensions in `plugins/`.
- Put release automation in `intergalactic/scripts/`, `fastlane/`, or repo-root packaging files.

## Review Notes

- `dist/` is build output, not source of truth.
- `archive/` is reference material, not active implementation.
- `docs/` should explain current architecture, not become a second implementation.
- If a path seems inherited from upstream Commet naming, prefer the Inter Galactic path that replaced it.
- If ownership is unclear, verify current imports before moving code between packages.
