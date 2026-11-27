# SQLite Android native payload receipt

Prepared by S&C on 2026-08-19 for the `0.8.1+1003` Android release candidate.
This record covers the conveyed SQLite core library, not the separately licensed
Dart `sqlite3` wrapper package.

## Candidate payload relationship

| Released coordinate | APK entry | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `eu.simonbinder:sqlite3-native-library:3.52.0` | `lib/arm64-v8a/libsqlite3.so` | 1,096,256 | `39d7e39ce70936ff0efcfe919cebb98b6750903a67e81e66f7d92e974b1f51aa` |
| `eu.simonbinder:sqlite3-native-library:3.52.0` | `lib/armeabi-v7a/libsqlite3.so` | 816,828 | `8c98b90c63fcb2fe0fdc42f15761e6cbb80671cd7f76ad8c9a626e7ba3c57a29` |

The durable Android Gradle notice receipt records this exact Maven coordinate
on the release runtime classpath and reports its POM licence as Public Domain:
`docs/release/evidence/android-gradle/0.8.1+996/THIRD_PARTY_NOTICES.android-gradle.md`.
The candidate-wide APK identity is recorded in
`workspace:docs/release/evidence/android-native-payloads/0.8.1+1003-rc.md`.

## Licence and notice decision

SQLite core code is dedicated to the public domain. The official SQLite
copyright statement says that no licence is required for the deliverable core
code: <https://www.sqlite.org/copyright.html>.

Public-domain SQLite carries no copyright licence-text or corresponding-source
publication condition. The app nevertheless exposes a component-specific
public-domain statement through `NativeLicenses._androidEntries`, so users can
identify the shipped native database library without confusing it with the MIT
licence of the Dart wrapper.

## Boundary

This receipt does not claim that the `sqlite3-native-library` packaging itself
is public domain, nor that the native payload is reproducible from an upstream
checkout. It records the package's release-runtime identity, the APK payload
hashes, and the SQLite-core licence posture. A changed package version or
payload hash requires a new review.
