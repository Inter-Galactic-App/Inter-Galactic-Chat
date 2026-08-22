# Android FCM License Evidence

Generated: 2026-07-30T19:59:01Z

This evidence captures Firebase/FlutterFire Dart package notices from the temporary Google Services dependency state. It does not require or read `google-services.json`.

Source lockfile: `pubspec.lock`

## Packages

| Package | Version | License | Evidence |
| --- | --- | --- | --- |
| `firebase_messaging` | `14.7.10` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_messaging-14.7.10/LICENSE` |
| `firebase_messaging_platform_interface` | `4.5.37` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_messaging_platform_interface-4.5.37/LICENSE` |
| `firebase_messaging_web` | `3.5.18` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_messaging_web-3.5.18/LICENSE` |
| `firebase_core_web` | `2.24.0` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_core_web-2.24.0/LICENSE` |
| `_flutterfire_internals` | `1.3.35` | BSD-3-Clause | `pub-cache:hosted/pub.dev/_flutterfire_internals-1.3.35/LICENSE` |
| `firebase_core` | `2.32.0` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_core-2.32.0/LICENSE` |
| `firebase_core_platform_interface` | `5.4.2` | BSD-3-Clause | `pub-cache:hosted/pub.dev/firebase_core_platform_interface-5.4.2/LICENSE` |

## Release Use

- Include this evidence when the Android release artifact is built with FCM / Google Services enabled.
- Keep the normal shared checkout restored to the non-Google dependency state after collection.
- Android Gradle/Maven runtime notices still need separate Gradle dependency evidence for the shipped APK.
