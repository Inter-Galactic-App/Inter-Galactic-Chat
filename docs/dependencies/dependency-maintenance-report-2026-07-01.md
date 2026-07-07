# Dependency Maintenance Report - 2026-07-01

Owner: REVIEW
Goal: safe dependency maintenance pass from `docs/plans/goals/dependency-review.md`

## Summary

REVIEW completed a bounded dependency pass across the app Dart workspace,
project-owned Node tooling, Python/uv audio tooling, GitHub Actions, and open
Dependabot PRs.

Applied changes were intentionally narrow:

- Updated the app Dart workspace lockfile with `flutter pub upgrade`, then
  aligned the source SDK floors with the accepted resolved dependency graph.
- Updated the Klipy proxy `package-lock.json` inside existing constraints for
  `wrangler` and `@types/node`.
- Did not change app behavior, production defaults, audio/streaming behavior,
  model runtimes, Gradle/Kotlin/AGP toolchains, source code, credentials, or
  private assets.

## Current State

- App repo branch: `main`, ahead of `origin/main` by local commits before this
  pass.
- Current app version: `0.8.0+990`.
- Dirty tree already contained unrelated DEBUG/AUDIO/DESIGN/source-doc work.
  REVIEW touched only dependency lockfiles, source SDK floor metadata, and
  coordination/reporting docs.
- 2026-07-02 addendum: the user accepted the Dart dependency bump as safe. The
  repo and app `pubspec.yaml` SDK floors now match the resolved lockfile floor:
  Dart `>=3.11.0 <4.0.0` and Flutter `>=3.38.4`.
- Dependabot alerts API is not available: GitHub reports Dependabot alerts are
  disabled for the repository and the current token lacks the requested admin
  scope.

## Ecosystems Inspected

- Flutter/Dart workspace: `intergalactic-app/inter-galactic/pubspec.yaml`,
  `pubspec.lock`, and workspace packages.
- Android/Gradle: `intergalactic/android`, `tiamat/android`, and open
  Dependabot Gradle PRs.
- CocoaPods lockfiles: iOS/macOS lockfiles inspected as present; no update was
  attempted from Windows.
- Node/npm project tooling:
  - `intergalactic-app/intergalactic-klipy-proxy`
  - `tools/audio-lab/livekit-loopback`
- Python/uv tooling:
  - `tools/livekit-noise-canceller`
- GitHub Actions and Dependabot config:
  - `.github/workflows/*.yml`
  - `.github/dependabot.yml`

Server-side `Linux_Matrix_Build/` and `references/` package manifests were
identified but left out of scope because those areas are SERVER/reference-owned
and not part of the app dependency update.

## Dependabot Triage

Open Dependabot PRs as of 2026-07-01:

| PR | Dependency | Classification | Status | Recommendation |
| --- | --- | --- | --- | --- |
| #48 | Gradle wrapper 8.13 -> 9.6.1 | routine_major, toolchain | Checks green, mergeable | Defer. Evaluate with AGP/Kotlin as one Android toolchain branch. |
| #36 | Kotlin Android plugin 2.1.10 -> 2.4.0 | routine_minor, toolchain | Security/dependency-review checks failed | Defer. Needs coordinated Android validation and check repair. |
| #24 | `intl_translation` 0.20.1 -> 0.21.0 | routine_minor, blocked | Static analysis failed | Do not merge as-is. Current branch pulls analyzer/dart_style compile failures. |
| #22 | Android Gradle Plugin 8.11.1 -> 9.2.1 | routine_major, toolchain | Checks green, mergeable | Defer. Requires Android release/build validation with wrapper/Kotlin. |

Dependabot security alerts:

- Not verified from GitHub alerts because the repository reports alerts are
  disabled via API.
- Post-update `flutter pub outdated --json` reports
  `CurrentAffectedByAdvisory: 0`.
- npm audit was run for project-owned Node tooling and is summarized below.

## Flutter/Dart Updates Applied

Command:

```powershell
flutter pub upgrade
```

Scope:

- Root Dart workspace lockfile:
  `intergalactic-app/inter-galactic/pubspec.lock`.
- 2026-07-02 follow-up: root and app `pubspec.yaml` environment floors were
  updated to match the accepted lockfile `sdks` floor so future agents and CI do
  not treat the dependency pass as unresolved toolchain drift.

Notable lockfile updates:

- `built_value` 8.12.5 -> 8.12.6
- `coverage` 1.15.0 -> 1.15.1
- `cross_file` 0.3.5+2 -> 0.3.5+3
- `dart_jsonwebtoken` 3.4.0 -> 3.4.1
- `flutter_plugin_android_lifecycle` 2.0.34 -> 2.0.35
- `flutter_svg` 2.2.4 -> 2.3.0
- `flutter_timezone` 5.0.2 -> 5.1.0
- `image_picker` 1.2.1 -> 1.2.3
- `image_picker_android` 0.8.13+16 -> 0.8.13+17
- `objective_c` 9.3.0 -> 9.4.1
- `path_provider` 2.1.5 -> 2.1.6
- `permission_handler_apple` 9.4.7 -> 9.4.10
- `safe_local_storage` 2.0.3 -> 2.0.4
- `screen_retriever*` 0.2.0 -> 0.2.1
- `sqflite` 2.4.2 -> 2.4.2+1
- `sqflite_common` 2.5.6 -> 2.5.8
- `url_launcher_android` 6.3.29 -> 6.3.30
- `url_launcher_web` 2.4.2 -> 2.4.3
- `vector_graphics` 1.1.21 -> 1.2.2
- `vector_graphics_compiler` 1.2.0 -> 1.2.6
- `vm_service` 15.0.2 -> 15.2.0
- `wakelock_plus` 1.5.1 -> 1.5.2
- `widgetbook` 3.22.0 -> 3.23.0
- `window_to_front` 0.0.3 -> 0.0.4

The resolver also made compatible transitive dev/tooling moves under existing
constraints, including `code_assets` 1.0.0 -> 1.2.1, `hooks` 1.0.2 -> 2.0.2,
`inspector` 3.1.0 -> 4.0.0, `msix` 3.16.13 -> 3.18.0, and removal of
`native_toolchain_c`.

Post-update outdated summary:

- Total packages reported: 99
- Current affected by advisory: 0
- Current discontinued packages: 4
- Direct packages in output: 36
- Dev packages in output: 6
- Transitive packages in output: 57
- Packages with newer resolvable versions: 43
- Packages with newer latest versions: 90

Remaining Flutter/Dart gaps are mostly constraint or migration work, not
lockfile-only fixes. Examples include `archive`, `build`, `build_runner`,
`device_info_plus`, `drift`, `file_picker`, `flutter_markdown`,
`flutter_secure_storage`, `flutter_webrtc`, `intl_translation`, `livekit_client`,
`permission_handler`, `unifiedpush`, and `widgetbook_generator`.

## Node/npm Updates Applied

### Klipy proxy

Folder: `intergalactic-app/intergalactic-klipy-proxy`

Applied:

- `package-lock.json` updated inside existing constraints.
- `wrangler` 4.103.0 -> 4.106.0
- `@types/node` 26.0.0 -> 26.1.0
- Associated `workerd`/Miniflare transitive packages moved with Wrangler.

Validation:

- `npm test` passed: 1 file, 4 tests.
- Test output included a Cloudflare runtime warning that installed Workerd
  supports compatibility date `2026-03-10` while the project requests
  `2026-06-21`; tests still passed.

Remaining audit:

- `npm audit` still reports 6 dev-tool findings: 1 low, 5 high.
- Remaining findings are routed through `@cloudflare/vitest-pool-workers`,
  Miniflare, Undici, ws, esbuild, and a nested Wrangler dependency.
- `npm audit fix --dry-run --json` made 0 changes.
- Attempting `@cloudflare/vitest-pool-workers@0.17.0` failed with `ERESOLVE`
  because it requires `vitest ^4.1.0` while the proxy currently uses
  Vitest 3.2.6.

Disposition:

- Defer the remaining Klipy audit fix to a coordinated CI/tooling migration:
  `@cloudflare/vitest-pool-workers` 0.17.x plus Vitest 4.x, without
  `--force` or `--legacy-peer-deps`.
- Tracked in integration queue item
  `Klipy Proxy Test Stack Security Update - 2026-07-01`.

### Audio Lab LiveKit loopback

Folder: `tools/audio-lab/livekit-loopback`

Results:

- `npm audit` reported 0 vulnerabilities.
- `npm outdated` reports:
  - `@livekit/rtc-node` 0.13.29 current/wanted, 0.13.30 latest.
  - `livekit-server-sdk` 2.15.5 current/wanted, 2.16.0 latest.

Disposition:

- No update applied. LiveKit/media SDK updates affect loopback/audio behavior
  and should be handled by AUDIO/REVIEW with a focused Audio Lab smoke.

## Python/uv Updates

Folder: `tools/livekit-noise-canceller`

Results:

- `uv --version` failed because the PATH shim points at
  `C:\Users\drumm\AppData\Local\Microsoft\WinGet\Links\uv.exe`, which Windows
  cannot launch in this environment.
- `uv lock --check` failed for the same host-tooling reason.
- Lockfile inspection shows the current audio/model stack includes:
  - `livekit` 1.1.2
  - `livekit-agents` 1.4.3
  - `livekit-plugins-ai-coustics` 0.2.12
  - `livekit-plugins-noise-cancellation` 0.2.5
  - `python-dotenv` 1.1.1
  - `rich` 14.0.0
  - `soundfile` 0.13.1

Disposition:

- No Python dependency update applied. This stack touches audio/model behavior
  and `uv` is currently unavailable.
- Next move is to repair `uv` tooling first, then run `uv lock --check` and a
  small Audio Lab smoke before any update.

## GitHub Actions / Dependabot Config

Inspected:

- `actions/checkout` pinned to SHA for v7.0.0 across workflows.
- `subosito/flutter-action` pinned to SHA for v2.23.0.
- `actions/setup-java@v5`
- `actions/upload-artifact@v7`
- `actions/dependency-review-action@v5`
- `.github/dependabot.yml` schedules weekly checks for GitHub Actions, pub
  workspace packages, and Gradle under `/intergalactic/android`.

No GitHub Actions or Dependabot config changes were made in this pass.

## Native / Platform Toolchains

Inspected but not updated:

- Android Gradle Plugin
- Gradle wrapper
- Kotlin Android plugin
- CocoaPods lockfiles
- Native/WebRTC/media toolchain areas

Reason:

- Open Android PRs are coupled toolchain migrations and require coordinated
  Android build/release validation.
- No security evidence required an immediate platform toolchain update.

## Validation Performed

Flutter/Dart:

```powershell
flutter --version
dart --version
flutter pub upgrade
flutter pub get
flutter pub outdated --json
flutter test --no-pub intergalactic/test/config/preferences_theme_test.dart
flutter build windows --debug --no-pub
```

Results:

- Flutter 3.41.1 / Dart 3.11.0.
- `flutter pub get` passed and reported no advisories.
- Focused Flutter test passed: 4 tests.
- Windows debug build passed from `intergalactic/`:
  `build\windows\x64\runner\Debug\InterGalactic.exe`.
- Full `flutter analyze` was attempted earlier in the pass but stalled/timed
  out without diagnostics. A later `flutter analyze --no-pub` run exited with
  only `Analyzing intergalactic...` after several minutes. This remains a
  validation gap.

Node:

```powershell
npm audit --json
npm outdated --json
npm update wrangler @types/node
npm test
npm audit fix --dry-run --json
npm install --save-dev @cloudflare/vitest-pool-workers@0.17.0
```

Results:

- Audio Lab LiveKit loopback audit clean.
- Klipy proxy `npm test` passed after safe lockfile update.
- Klipy proxy remaining audit fix requires Vitest 4 and was deferred.

Python:

```powershell
uv --version
uv lock --check
```

Results:

- Both blocked by broken `uv.exe` PATH shim.

Process cleanup:

- No Dart/Flutter/flutter_tester processes remained after validation.
- Multiple Node processes existed on the host. Command-line inspection via WMI
  was access denied, so REVIEW did not kill any Node process that could not be
  safely attributed to this task.

## Security Status

Resolved or reduced:

- No Flutter current package is reported as affected by an advisory after the
  lockfile update.
- Klipy proxy direct `wrangler` lock moved to the current wanted version inside
  existing constraints.

Remaining:

- Dependabot alerts API is unavailable because alerts are disabled for the repo.
- Klipy proxy dev-tool audit still reports 6 findings until the Vitest 4 /
  Cloudflare test-harness migration is completed.
- Android Gradle/Kotlin/AGP PRs remain deferred pending coordinated validation.

## Deferred Updates

- Android toolchain PRs #22, #36, #48: deferred as coupled platform toolchain
  work.
- `intl_translation` PR #24: blocked by static-analysis/analyzer compile
  failure on the Dependabot branch.
- Klipy `@cloudflare/vitest-pool-workers` 0.17.x: deferred because it requires
  Vitest 4.x migration.
- Audio Lab LiveKit loopback packages: deferred because they touch media/audio
  loopback behavior.
- Python/uv noise-canceller packages: deferred because `uv` is unavailable and
  the stack affects audio/model behavior.
- Broad Flutter/Dart constraint updates: deferred because they require
  package-by-package migration and full analyze/test/build validation.

## Risk Assessment

Risk is low for the applied changes:

- App dependency changes passed pub get, focused test, and Windows debug build
  before the source SDK floors were aligned to the accepted lockfile floor.
- Klipy proxy change is lockfile-only for dev tooling and passed its test
  suite.
- No app runtime defaults, production service behavior, streaming/audio
  settings, model runtimes, or credentials changed.

Residual risk:

- Full analyze did not complete in this environment.
- Current workspace has unrelated dirty source changes from other agents, so
  this dependency pass should be staged selectively.
- Klipy proxy dev audit is improved but not clean until the Vitest 4 migration.

## Rollback Plan

To revert only this dependency pass:

- Restore `intergalactic-app/inter-galactic/pubspec.lock`.
- Restore the root and app `pubspec.yaml` environment floors if the accepted
  Dart/Flutter floor is rolled back.
- Restore `intergalactic-app/intergalactic-klipy-proxy/package-lock.json`.
- Remove this report if the pass is abandoned.
- Revert the matching `docs/CHANGE_LOG.md` and integration queue updates.

Do not revert unrelated dirty files from DEBUG, AUDIO, DESIGN, or other agents.

## Next Dependency Pass

Recommended order:

1. Repair host `uv` tooling and rerun `uv lock --check`.
2. Complete the Klipy proxy Vitest 4 / Cloudflare test-harness migration on a
   focused branch.
3. Coordinate Android Gradle/Kotlin/AGP as one branch with Android build
   evidence.
4. Investigate why full `flutter analyze` stalls before using it as a release
   gate for broad Dart dependency work.
5. Revisit selected Flutter direct dependency migrations package by package,
   starting with dev-only/build tooling after analyze is reliable.
