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

## Building An FCM (Firebase Push) Variant

The source tree ships with Google Firebase Cloud Messaging (FCM) **off by
default**, and no Firebase configuration is committed. The default open-source
Android build delivers push without Google, through UnifiedPush/ntfy via a
Matrix push gateway. The maintainer's official APK additionally enables FCM at
build time using maintainer-local Firebase config that is never checked in.

If you want to build your own FCM-enabled Android variant, use **your own**
Firebase project — you cannot use the maintainer's, and the config files below
are gitignored on purpose.

1. Create a Firebase project and register an Android app (your own application
   id). Download its `google-services.json` to
   `intergalactic/android/app/google-services.json` (gitignored, per-operator).
2. Generate `intergalactic/lib/firebase_options.dart` for your project — for
   example with `flutterfire configure`. It is gitignored and provides
   `DefaultFirebaseOptions`.
3. In `intergalactic/pubspec.yaml`, uncomment the `firebase_core` and
   `firebase_messaging` dependencies, then run `flutter pub get`.
4. Uncomment the Google Services Gradle plugin in both
   `intergalactic/android/settings.gradle` and
   `intergalactic/android/app/build.gradle`.
5. In
   `intergalactic/lib/client/components/push_notification/android/firebase_push_notifier.dart`,
   uncomment the `firebase_core` / `firebase_messaging` imports (and import your
   generated `firebase_options.dart`), then remove the `dynamic Firebase;`,
   `dynamic FirebaseMessaging;`, and `dynamic DefaultFirebaseOptions;` stubs that
   stand in while Firebase is off.
6. Server side: FCM delivery still needs a Matrix push gateway that holds **your**
   Firebase service-account key. That key is server-side only — never commit it,
   the `google-services.json`, or `firebase_options.dart`, and never place them in
   logs or diagnostics.
7. Build and validate the Android release:

   ```bash
   cd intergalactic
   flutter build apk --release --dart-define PLATFORM=android
   ```

   Use `flutter build appbundle --release --dart-define PLATFORM=android`
   instead if you are publishing to Play. The `--dart-define` is required, not
   optional: platform-conditional code reads it, and omitting it produces a
   build that compiles and then misbehaves at runtime.

   Release builds are signed, so `intergalactic/android/key.properties` must
   point at your own keystore before the `release` build type will configure.
   Without it the build fails with `SigningConfig "release" is missing required
   property "storeFile"`. `intergalactic/scripts/setup_android_release.dart`
   encodes and decodes a keystore for CI use. Signing material is yours; none
   is distributed with this repository.

   Validate the FCM variant on a real device: confirm a push actually arrives.
   CI cannot check this, because the CI job builds a DEBUG APK with no Firebase
   configuration (`.github/workflows/build-android.yml`). A green CI run is not
   evidence that your FCM build works.

The maintainer's official build automates steps 3–5 with a private workspace
script and restores the non-Google state afterward; the steps above are the
manual equivalent so a fork can reproduce the FCM build with its own project.

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
