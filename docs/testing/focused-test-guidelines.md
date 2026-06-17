# Focused Test Guidelines

## Purpose

Focused tests protect high-risk behavior without turning every change into a
slow integration suite. Add the smallest test that would fail for the bug or
regression being prevented.

## Naming

- File names should describe the system and behavior:
  `screen_share_adaptive_fallback_test.dart`,
  `onboarding_service_test.dart`, or
  `activity_visibility_test.dart`.
- Test names should read like behavior:
  `keeps hardware preset on clean low-FPS sender stats` or
  `completed state survives a new Preferences initialization`.
- Prefer `keeps`, `clears`, `ignores`, `falls back`, `does not`, and
  `preserves` when they describe a regression boundary.

## What To Test

- Pure Dart helpers: profile resolution, parsing, state machines, visibility
  filters, persistence wrappers, and formatting logic.
- Widget tests: compact UI state, navigation buttons, settings/search rows, and
  layout regressions that do not require native services.
- Integration tests: only when behavior requires Synapse, cross-device Matrix
  state, platform permissions, native media capture, push delivery, or a
  packaged artifact.

## What To Avoid

- Do not add broad app boot tests for a single helper bug.
- Do not mock full Matrix clients when a pure helper or small fake source is
  enough.
- Do not depend on external services in unit/widget tests.
- Do not treat pull-request review comments as passing validation; verify findings with
  focused tests or manual evidence.

## Path-Aware PR CI

Pull requests run formatter/analyzer through `.github/workflows/static-analysis.yml`
as before, then resolve focused Flutter tests with
`.github/scripts/resolve-focused-tests.sh`.

Resolver behavior:

- Changed files under `intergalactic/test/**_test.dart` always run that exact
  test file.
- Source changes in mapped high-risk areas run the matching focused suites for
  calls/streaming/RNNoise, notifications, activity, onboarding, URL
  previews/media, settings/themes/UI primitives, Matrix room/client behavior,
  diagnostics, updates/downloads, and shortcuts.
- Dependency or CI routing changes such as `pubspec.yaml`, `pubspec.lock`,
  `analysis_options.yaml`, `.github/workflows/static-analysis.yml`, or the
  resolver script run all configured focused tests.
- Unrelated documentation-only changes should resolve `count=0`, making the
  focused Flutter test step a green no-op.
- The resolver validates that every selected test exists before emitting the
  GitHub outputs `count` and `path`. A stale mapping should fail CI rather than
  silently skipping coverage.

When adding or moving a focused test, update the resolver mapping in the same
change if a related source path should start routing to that test. Keep mapped
suites targeted; do not turn every Dart change into a broad smoke run unless
the changed dependency or CI route can affect all focused tests.

## Local Command Pattern

Run Flutter commands from the main app package unless a package-specific test
requires a different working directory:

```powershell
Set-Location 'intergalactic'
& "$env:FLUTTER_ROOT\bin\flutter.bat" test test\path\to\focused_test.dart
```

If `FLUTTER_ROOT` is not set, use the Flutter SDK path for your machine. Do
not commit personal SDK paths into documentation or CI scripts.

For analysis, keep the file list focused on touched files and imported helpers
where practical. Run `git diff --check` from
the repository root before opening or updating a pull request.

## When Manual Validation Is Required

Manual/device validation is required when the behavior crosses:

- OS permissions or notifications
- native plugin registration, DLLs, Android services, iOS entitlements, or web
  service workers
- real Matrix sync, E2EE keys, verification, or homeserver background wake
- WebRTC capture, hardware encoding, TURN/ICE routing, ReplayKit, or microphone
  capture
- installer/APK/TestFlight/web deployment behavior
