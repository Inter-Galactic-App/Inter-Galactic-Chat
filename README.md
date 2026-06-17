# Inter Galactic

Inter Galactic is a beta Matrix messaging client for community chat, direct messages, voice/video calls, stories, forums, and desktop-first communication workflows.

The project is built from the Commet Matrix client codebase and is being shaped into an Inter Galactic experience for communities that want a Discord/Messenger-style app while keeping Matrix interoperability. Commet remains the upstream project for its own client; Inter Galactic issue reports and support requests should use this repository.

## Current Status

Inter Galactic is in active beta development.

| Platform | Current path | Notes |
| --- | --- | --- |
| Windows desktop | Primary beta target | Desktop releases are the current priority. |
| Android | APK downloads from the project website | Play Store release is not planned before v1. |
| iPhone | TestFlight | App Store release is not planned before v1. |
| Web | Beta/dev validation | Availability may vary by release. |
| macOS/Linux desktop | Development/community validation | Not the primary release path today. |

## Highlights

- Matrix rooms, direct messages, spaces, forums, and thread-style conversation flows.
- End-to-end encryption support with ongoing session recovery and verification improvements.
- Voice/video calling, screen sharing, and LiveKit-backed streaming experiments.
- Story and media-sharing flows for richer community updates.
- Desktop update support, release manifests, and release notes built around public beta releases.
- Notification, presence, and account recovery improvements for the Inter Galactic beta channel.

## Beta Notes

- Desktop updates currently support a checksum-verified unsigned installer path. Users still need to approve the Windows installer prompt.
- Streaming, game capture, and related diagnostics remain beta systems and may change between builds.
- Android users currently install APKs manually from the website.
- iPhone users currently install through TestFlight.
- Third-party Matrix homeserver behavior may vary from the Inter Galactic-managed beta environment.
- Do not include access tokens, recovery codes, private homeserver details, or full diagnostic logs in public issues.

## Support And Reporting

- Public bug reports and feature feedback belong in this repository's GitHub issues.
- Security-sensitive reports should follow [SECURITY.md](SECURITY.md) and stay off public issue threads.
- Support, privacy, and account-model questions are documented in [docs/policies/SUPPORT.md](docs/policies/SUPPORT.md).
- Public policy drafts are available for [privacy](docs/policies/PRIVACY_POLICY.md),
  [terms](docs/policies/TERMS_OF_SERVICE.md),
  [community guidelines](docs/policies/COMMUNITY_GUIDELINES.md), and
  [abuse reporting](docs/policies/REPORT_ABUSE.md).
- Homeserver-specific moderation, abuse, and account actions usually belong to the selected homeserver operator.

## Development Setup

Install Flutter with Windows desktop support, then clone the repository and
work from the app package directory:

```powershell
git clone https://github.com/Inter-Galactic-App/Inter-Galactic.git inter-galactic
cd inter-galactic
cd intergalactic
flutter pub get
dart run scripts/codegen.dart
flutter run -d windows --dart-define PLATFORM=windows
```

For release-oriented work, read:

- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Documentation Index](docs/README.md)
- [Architecture Change Guide](docs/architecture/change-guide.md)
- [Codebase Map](docs/architecture/codebase-map.md)

## Contributing

Inter Galactic welcomes focused beta feedback and scoped contributions. Please open an issue or discussion before large platform, release, encryption, calling, or account-system changes.

Security reports should follow [SECURITY.md](SECURITY.md) and should not be posted as public issues.

## License And Attribution

Inter Galactic is based on Commet. See [LICENSE](LICENSE) and [FORK_NOTICE.md](FORK_NOTICE.md) for license and attribution details.
