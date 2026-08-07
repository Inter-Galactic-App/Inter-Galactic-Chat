# Contributing To Inter Galactic

Thanks for helping improve Inter Galactic. The app is in active beta, so focused bug reports, release-readiness feedback, and small scoped pull requests are the most useful contributions right now.

## Before You Start

- Check the current beta status in [README.md](README.md).
- Read the [Security Policy](SECURITY.md) before reporting anything involving auth, encryption, account recovery, private data, or update integrity.
- Open an issue or discussion before large changes to release tooling, platform behavior, encryption/session handling, calling/streaming, account systems, or app architecture.
- Keep reports public-safe. Do not include access tokens, recovery codes, passwords, private keys, private room identifiers, private homeserver internals, or full diagnostic logs.

## Local Setup

Windows desktop is the default contributor path today. After cloning the
repository, work from the Flutter app directory:

```powershell
git clone https://github.com/Inter-Galactic-App/Inter-Galactic.git inter-galactic
cd inter-galactic
cd intergalactic
flutter pub get
dart run scripts/codegen.dart
flutter run -d windows --dart-define PLATFORM=windows
```

Useful references:

- [Documentation Index](docs/README.md)
- [Architecture Change Guide](docs/architecture/core/change-guide.md)
- [Codebase Map](docs/architecture/core/codebase-map.md)
- [Security Policy](SECURITY.md)
- [Support](docs/policies/SUPPORT.md)

## Pull Request Expectations

Pull requests should:

- Describe the user-facing change or release-readiness improvement.
- List tested platforms and any tests, static checks, or manual validation performed.
- Call out upgrade, rollback, signing, update-manifest, privacy, or encryption risks when relevant.
- Keep unrelated behavior changes out of the PR.
- Avoid committing generated artifacts unless the repository already tracks them for that workflow.
- Keep public docs free of private workspace paths, internal tracker IDs, raw
  diagnostic logs, and maintainer-only coordination notes.

## AI And Generated Code

Do not use automated coding agents or AI-generated code for security-sensitive changes unless a maintainer explicitly approves the scope and review path.

Security-sensitive areas include:

- Authentication and account recovery.
- End-to-end encryption and session verification.
- Release signing, update manifests, and artifact integrity.
- Private data handling, diagnostics, and telemetry.

All generated code must be reviewed by a human before it is merged.
