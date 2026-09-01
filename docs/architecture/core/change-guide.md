# Change Guide

## Purpose

This is the quick contributor checklist for cross-cutting changes.

Use it before starting a fix so you inspect the right code together instead of repairing one file and missing the adjacent system that actually controls behavior.

## If Changing UI Or Design

Start with the active design reference:

- `docs/design/INTERGALACTIC_DESIGN_SYSTEM.md`
- `docs/design/UI_GUIDELINES.md`
- `docs/design/COMPONENT_PATTERNS.md`
- `docs/design/LAYOUT_AND_SPACING.md`
- `docs/design/THEME_GUIDELINES.md` when themes, tokens, custom themes, or
  glass/transparency are involved

Then inspect the current implementation anchors named by those docs before
editing. For settings work, also inspect:

- `intergalactic/lib/ui/pages/settings/`
- `intergalactic/lib/ui/pages/settings/categories/app/setting_row.dart`
- `intergalactic/lib/ui/mobile/mobile_visuals.dart`
- `intergalactic/lib/ui/mobile/mobile_surface.dart`
- `tiamat/lib/atoms/` when changing shared primitives

Checks:

- keep desktop settings on the overlay path and mobile settings on the mobile
  route path unless the task explicitly changes navigation
- reuse existing settings rows, mobile surface tokens, and Tiamat primitives
  before adding one-off UI components
- preserve row-level settings search aliases when moving or renaming settings
- avoid changing Matrix state, preferences, calls, or media runtime behavior
  during visual-only design work unless that behavior change is in scope

## If Changing Login

Inspect all of:

- session restore
- storage
- crypto availability
- verification flows
- account switching/client ownership

Start with:

- `intergalactic/lib/client/client_manager.dart`
- `intergalactic/lib/client/matrix/matrix_client.dart`
- `intergalactic/lib/client/matrix/auth/...`
- `intergalactic/lib/client/demo/demo_client.dart` when login or client
  abstractions can affect app-review demo mode
- `intergalactic/lib/client/matrix/matrix_user_agent_http_client.dart`
- `intergalactic/lib/config/build_config.dart`
- `intergalactic/lib/ui/pages/login/...`
- `intergalactic/lib/client/matrix/web/...` for browser/web-specific restore behavior

Questions to answer before merging:

- does the correct account restore
- does the correct device identity survive
- do Synapse-visible user-agent and Matrix device display labels still include
  Inter Galactic app/version/platform identity
- does encrypted room usability survive restart
- does failure route into recovery instead of silent partial state
- does the offline demo still avoid Matrix session restore, push registration,
  and post-login setup prompts

## If Changing Notifications

Inspect:

- shared notification code
- Matrix pusher registration
- every platform implementation that participates in delivery or click routing

Start with:

- `intergalactic/lib/client/components/push_notification/...`
- `intergalactic/lib/client/matrix/components/push_notifications/matrix_push_notification_component.dart`
- `intergalactic/lib/service/background_service.dart`
- `intergalactic/lib/service/background_service_notifications/...`
- `intergalactic/lib/ui/pages/settings/categories/app/notification_settings/...`

Also inspect platform-specific code under:

- `intergalactic/android/`
- `intergalactic/ios/`
- `intergalactic/web/`

Do not ship notification changes that were only reviewed in one notifier implementation.

Android pusher guardrail:

- FCM builds must remove stale Android URL pushers for Inter Galactic and
  legacy Android app ids before per-device matching.
- Do not make stale URL-pusher cleanup depend only on Matrix device display
  names; older app versions can leave mismatched metadata behind after update.

## If Changing Mobile Keyboard Or Chat Insets

Inspect:

- `intergalactic/android/app/src/main/AndroidManifest.xml`
- `intergalactic/lib/ui/atoms/keyboard_adaptor.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`
- `intergalactic/lib/ui/organisms/chat/chat_view.dart`

Checks:

- Android should stay on `windowSoftInputMode="adjustNothing"` while Flutter
  owns chat composer movement from `MediaQuery.viewInsets.bottom`.
- `KeyboardAdaptor.shouldPushContent` is for custom panels such as emoji,
  GIF, and sticker pickers. It must not disable normal text-keyboard avoidance.
- Avoid stacking multiple independent keyboard paddings around the chat view
  unless a device test proves the single owner cannot see keyboard insets.

## If Changing Web Code

Inspect:

- conditional imports
- browser storage
- IndexedDB/session restore behavior
- service worker/web push code if the change can run in the background

Start with:

- `intergalactic/lib/client/matrix/web/...`
- `intergalactic/lib/client/components/push_notification/web/...`
- `intergalactic/lib/client/matrix/auth/web/...`
- `intergalactic/web/`

Checks:

- no web-only import leaks into shared code
- browser storage failure modes are handled intentionally
- session restore still has a clear healthy/recovery split

## If Changing Plugins

Inspect:

- plugin registration
- plugin lifecycle
- platform support boundaries
- fallback behavior

Start with:

- `plugins/...`
- app-side usage sites under `intergalactic/lib/client/...`
- related settings/UI toggles
- platform runner code if the plugin needs native packaging or registration changes

For the current noise suppression plugin also inspect:

- `plugins/intergalactic_noise_suppression/`
- `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_service.dart`
- `docs/architecture/calls-streaming-audio/media-and-plugins.md`
- `docs/architecture/calls-streaming-audio/livekit-gameplay-streaming.md` when the change affects
  server-routed microphone verification or LiveKit call diagnostics

Checks:

- unsupported platforms fail safely
- init/shutdown do not leak resources
- release packaging still includes needed binaries

## If Changing Release Scripts

Inspect:

- platform packaging
- output naming
- updater and manifest assumptions
- website/download expectations if the release publishes hosted metadata

Start with:

- `intergalactic/scripts/build_release.dart`
- `intergalactic/scripts/generate_update_manifest.dart`
- `intergalactic/scripts/prepare-web.sh`
- repo-root `windows_installer.iss`
- any additional tracked release script that is part of the real release path

Checks:

- artifact path still matches packaging step
- updater/runtime code still matches manifest structure
- hosted file paths still match website or in-app updater expectations
- Android APKs, Windows installers, checksums, source archives, and
  `latest.json` should use the full pubspec build identity
  `{version}+{build}` for new release artifacts. Keep changelog URLs on the
  semantic version unless the public notes truly differ per build.
- The release build path should make version/build metadata changes explicit
  before editing `pubspec.yaml`. Scripted or noninteractive runs should still
  record whether they bumped build metadata, bumped semantic version, or reused
  the current version.

## If Changing Workspace Dependencies

Inspect:

- workspace-root package membership
- app-level dependency overrides
- local package pubspecs under `widgets/`, `plugins/`, and `tiamat/`

Start with:

- repo-root `pubspec.yaml`
- `intergalactic/pubspec.yaml`
- affected package `pubspec.yaml` files

Checks:

- keep each overridden package owned by only one workspace package
- prefer the app/workspace-level override when a local package depends on the
  same forked package
- avoid duplicating dependency overrides inside reusable packages unless they
  must be built completely outside this workspace

## If Running Pull Request Reviews

Use the repository pull-request workflow as the default review path for Inter
Galactic. Keep each review split small, focused, and easy to validate.

Start with:

- repo root: `.`
- PR branch: verify current branch with `git status -sb`

Successful review loop:

- keep each split small and reviewable
- stage explicit file paths only when the worktree is mixed
- commit the split before pushing
- push to the PR branch and let configured GitHub review checks run
- inspect GitHub PR review threads for actionable comments
- verify each finding against current code before editing
- resolve stale comments with evidence instead of forcing an outdated fix
- rerun focused local checks before each follow-up push
- push follow-up commits and re-check GitHub PR comments until there are no
  actionable unresolved review findings

Useful checks:

- `gh pr checks <number> --watch=false`
- `gh pr view --json number,url,headRefName`
- GitHub review threads/comments for inline findings
- focused `dart analyze` and focused tests on touched files
- `git diff --cached --check` before committing

Do not upload private or sensitive diffs to third-party review tooling unless
the repository owner has explicitly approved that review path.

## If Changing Desktop Windowing Or Call Popouts

Inspect:

- Windows startup path
- Flutter windowing feature flags
- call popout controller state
- plugin registration risk for video, WebRTC, and LiveKit rendering

Start with:

- `intergalactic/lib/main.dart`
- `intergalactic/lib/config/build_config.dart`
- `intergalactic/lib/ui/windows/detached_call_window/...`
- `intergalactic/lib/ui/organisms/call_view/desktop_call_popout_host.dart`
- `docs/release/build-signing.md` for the documented desktop release build
  path, when relevant

Checks:

- default Windows builds run with `flutter config --enable-windowing`
- native detached call windows are enabled by default with `ENABLE_NATIVE_DETACHED_CALL_WINDOWS=true`
- emergency overlay fallback builds pass
  `--enable_native_detached_call_windows=false` to the release helper
  (`intergalactic/scripts/build_release.dart`, see
  `docs/release/build-signing.md`), or
  `--dart-define=ENABLE_NATIVE_DETACHED_CALL_WINDOWS=false` for a direct
  `flutter build`. The helper also honours an
  `ENABLE_NATIVE_DETACHED_CALL_WINDOWS` environment variable. There is no
  `--no-detached-call-windows` option.
- `main.dart` keeps the normal `runApp(...)` startup path
- secondary call windows are mounted from the app tree through `ViewAnchor`
- per-stream popouts remain in-app overlays unless a later change explicitly expands the native-window scope
- startup is smoke-tested for a single visible main window before live-call media testing

## If Changing Desktop Shell Or Small-Window Mode

Inspect:

- desktop shell composition
- persisted layout preferences
- user-bar controls
- room side-panel widths/collapse behavior
- navigation rail sizing

Start with:

- `intergalactic/lib/config/preferences.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/general_settings_page.dart`
- `intergalactic/lib/ui/pages/main/main_page_view_desktop.dart`
- `intergalactic/lib/ui/organisms/side_navigation_bar/`
- `intergalactic/lib/ui/organisms/room_side_panel/`
- `docs/architecture/features/desktop-small-window-mode.md`

Checks:

- keep compact desktop windows on the desktop layout path rather than forcing
  `Layout.mobile`
- preserve room navigation, timeline readability, and composer reachability in
  short horizontal windows
- avoid touching LiveKit/call-media session code unless the change is explicitly
  about call-window integration

## If Changing Media, GIFs, Stickers, or Emoji

Inspect:

- provider parsing
- send/upload path
- render path
- fallback UI

Start with:

- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/components/gif/matrix_gif_component.dart`
- `intergalactic/lib/client/matrix/components/emoticon/...`
- `intergalactic/lib/ui/molecules/gif_picker.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`

## If Changing Room/Timeline Messaging Behavior

Inspect:

- domain room logic
- event/timeline conversion
- input/composer
- UI surfaces where the behavior renders

Start with:

- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/timeline_events/...`
- `intergalactic/lib/ui/organisms/chat/...`
- `intergalactic/lib/ui/molecules/...`

## Fast Sanity Checklist

Before declaring a change done, ask:

- did I inspect both shared logic and the platform-specific implementation
- did I inspect the restore/session path if the feature depends on account state
- did I inspect the UI error/fallback path
- did I inspect release/update assumptions if packaging is involved
- did I update the relevant doc if the architecture rule changed

## Repository Contract

- Do not make a workspace-root batch file mandatory contributor flow unless its
  command is added to the tracked release documentation and repository contract.

## Open Architecture Questions

None currently tracked here. Unresolved decisions belong in this section with
a tracking reference; settled rules go under Repository Contract above.
