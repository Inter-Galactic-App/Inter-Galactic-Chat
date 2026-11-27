# Dart JNI Android native payload receipt

Prepared by S&C on 2026-08-19 for the `0.8.1+1003` Android release candidate.
This record covers `libdartjni.so`, not merely the Dart package declaration.

## Candidate payload relationship

| Locked package | APK entry | SHA-256 |
| --- | --- | --- |
| `jni` 1.0.0 | `lib/arm64-v8a/libdartjni.so` | `4ff839cb68e90232ff615a1e10d2787bfadba0d764148b027d1cc19bed842b84` |
| `jni` 1.0.0 | `lib/armeabi-v7a/libdartjni.so` | `551b1b6fa352acd57a6e71e6e0d7e5b10c53d5fb7751d4347b6650e5971b8a51` |

The exact package version is locked in the app-root `pubspec.lock`. Its native
`src/CMakeLists.txt` declares `add_library(jni SHARED ...)`, sets
`OUTPUT_NAME "dartjni"`, and enables that target on Android. This is the
direct source-to-filename route; it is not inferred from the library name.
The APK identity and hash verification are also recorded in
`workspace:docs/release/evidence/android-native-payloads/0.8.1+1003-rc.md`.

## Licence and notice route

The `jni` 1.0.0 package `LICENSE` is BSD-3-Clause, copyright 2022 the Dart
project authors. Its bytes are promoted into the app as
`intergalactic/assets/licenses/dart-jni-BSD-3-Clause.txt`, SHA-256
`08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6`.

The JNI package also carries Android NDK `jni.h` under Apache-2.0. The app
already ships the canonical Apache-2.0 text and attaches both texts to the
component-specific Android JNI label. Source package route:
<https://pub.dev/packages/jni/versions/1.0.0>.

These are permissive components. No corresponding-source publication is
asserted or added here.

## Boundary

This receipt identifies the native target emitted by the locked package and
the notice texts attached to it. It does not claim reproducibility of the APK
payload or turn the Dart wrapper record into a substitute for this native one.
