# CI and validation boundaries

This page documents repository-owned CI entry points, evidence boundaries, and what is intentionally left out.

## Scope

- tracked workflow and script configuration
- what those checks prove
- what they do not prove
- transcript capture boundaries

## CI entry points

- `.forgejo/workflows/forgejo-ci.yml`: runs on `push` to `main` and `pull_request`; jobs `dart-gates` and `repo-checks`; non-blocking transcript per run/job.
- `.github/workflows/build.yml`: runs on `workflow_dispatch` and selected PR paths; compiles Windows app in profile mode only.
- `.github/workflows/build-web.yml`: runs on `workflow_dispatch` and allow-listed PR paths; runs `flutter build web --release`.
- `.github/workflows/minipc-ci.yml`: runs on `workflow_dispatch` and `push` to `release/**`; runs miniPC release-branch repository checks.
- `.github/workflows/minipc-nightly.yml`: runs on `workflow_dispatch` and daily schedule; runs miniPC repo checks on default branch.

## What gates are evidence

### Forgejo Dart gate (`forgejo-ci.yml`)

- **Pin checks**: workflow Flutter pins match `.flutter-version`.
- **Dependency and analysis**: `flutter pub get`, formatting, analyzer on changed reviewable Dart.
- **Focused tests only**, from `.github/scripts/resolve-focused-tests.sh` with command `flutter test <selected_tests>`.

### Forgejo repo checks (`forgejo-ci.yml`)

- `scripts/ci/check-json.sh`
- `scripts/ci/check-agent-docs.sh`
- `scripts/ci/check-release-docs.sh`
- `scripts/ci/check-security-docs.sh`

### GitHub workflow gates

- `build.yml` (`build-windows`): Windows C++ + intergalactic AOT profile compilation.
- `build-web.yml` (`build-web`): hosted web compilation.
- `minipc-ci.yml` / `minipc-nightly.yml`: miniPC repository checks.

## Focused-test selection

`forgejo-ci.yml` computes changed tests:
1. resolves base ref (`GITHUB_BASE_REF` when present, else `HEAD^1`)
2. writes `changed_files` from `git diff`
3. filters reviewable `.dart` files, excluding `*.g.dart` and `*.freezed.dart`
4. resolves candidates via `.github/scripts/resolve-focused-tests.sh`
5. runs selected tests only when any are returned

A PR with no reviewable Dart changes skips format/analyze/test gates.

## What this CI does not cover (non-evidence)

- integration tests
- product runtime behavior and release behavior
- QA/manual evidence
- security policy ownership or external risk posture
- Windows C++ or other platform-native code paths outside these workflows

## Flutter pin controls

- pin source: `.flutter-version`
- `scripts/ci/check-flutter-pin.sh` validates all `.flutter-version` / `FLUTTER_PIN` in `.github/workflows` and `.forgejo/workflows`
- `forgejo-ci.yml` also exports `FLUTTER_PIN` (miniPC local runner mode) and validates it via `flutter --version --machine`
- gate fails on any mismatch or missing pin

## Transcript boundary

- command output is captured by `scripts/ci/forgejo-transcript.sh`
- transcript reference: `docs/ci/forgejo-ci-transcripts.md`
- captures only `ci_capture` / `ci_capture_script` commands
- excludes checkout/action internals and runner/system output
- best-effort publishing; never gates job status

## Ownership exclusions

- `static-analysis.yml`: separate workflow family not included in this document’s evidence claims
- `check-security-docs.sh`: documentation check, not runtime/product security assurance
- QA/manual validation and product-behavior proof remain outside CI evidence boundary

## Related files

- `.github/workflows/build.yml`
- `.github/workflows/build-web.yml`
- `.github/workflows/minipc-ci.yml`
- `.github/workflows/minipc-nightly.yml`
- `.forgejo/workflows/forgejo-ci.yml`
- `.github/scripts/resolve-focused-tests.sh`
- `.flutter-version`
- `scripts/ci/check-flutter-pin.sh`
- `scripts/ci/forgejo-transcript.sh`
- `docs/ci/forgejo-ci-transcripts.md`
