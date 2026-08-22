# Flutter Android engine payload receipt

Prepared by S&C on 2026-08-19 for the `0.8.1+1003` Android release candidate.
This record is Android-specific; the Windows Flutter-engine record cannot stand
in for it because the shipped engine binary and packaged notice archive differ.

## Candidate payloads

| APK entry | Bytes | SHA-256 |
| --- | ---: | --- |
| `lib/arm64-v8a/libflutter.so` | 11,316,480 | `ac5d13b275d83ba47ec27e1bf14f24cc9e9f6584d9ab498573117be1c94686c2` |
| `lib/armeabi-v7a/libflutter.so` | 8,275,708 | `2a732f8faa3492c9b788f303cba06e7f82649630222d5a0ccee3c67d50303ac7` |
| `assets/flutter_assets/NOTICES.Z` | 201,601 | `351db2e9581ae68169115ad67ba80f900041368b457182ea86c3171ec206fb2b` |

The workspace candidate receipt records the APK identity and the native-payload
gate recomputes the two `.so` hashes from the ZIP entries:
`workspace:docs/release/evidence/android-native-payloads/0.8.1+1003-rc.md`.

## Identity and notice route

The tracked Android Gradle evidence for this dependency family records the
same engine revision for both release ABIs:
`io.flutter:arm64_v8a_release:1.0.0-3452d735bd38224ef2db85ca763d862d6326b17f`
and
`io.flutter:armeabi_v7a_release:1.0.0-3452d735bd38224ef2db85ca763d862d6326b17f`.
See `docs/release/evidence/android-gradle/0.8.1+996/THIRD_PARTY_NOTICES.android-gradle.md`.

The candidate `NOTICES.Z` was decompressed and inspected as part of this
receipt. It includes the Flutter Authors BSD-style notice and ICU entries with
the Unicode/IBM copyright material. Flutter renders `NOTICES.Z` through its
ordinary licence registry, which is the user-visible route used by the app’s
third-party licence page; no duplicate hand-written Flutter notice is added.

* Engine revision source route:
  <https://github.com/flutter/engine/tree/3452d735bd38224ef2db85ca763d862d6326b17f>.
* Flutter distribution licence route:
  <https://github.com/flutter/flutter/blob/3.32.4/LICENSE>.

## Boundary

This receipt establishes the candidate APK identity and its packaged notice
route. It does not claim that the Flutter engine is reproducible from the
linked source tree, and it does not replace a review if the engine revision or
the compressed notice hash changes.
