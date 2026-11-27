# AndroidX Graphics Path and DataStore native payload receipt

Prepared by S&C on 2026-08-19 for the `0.8.1+1003` Android release candidate.
This is a component-identity, licence-text, and notice-attachment record. It
does **not** make a reproducible-build claim and it does not cover the other
native libraries in the APK.

## Candidate payload relationship

The candidate APK contains the following files. Their hashes were taken from
the ZIP entries themselves, and are also enforced by the workspace native
payload gate mapping. The candidate-wide receipt is
`workspace:docs/release/evidence/android-native-payloads/0.8.1+1003-rc.md`.

| Component | Released coordinate | APK paths and SHA-256 |
| --- | --- | --- |
| AndroidX Graphics Path | `androidx.graphics:graphics-path:1.0.1` | `lib/arm64-v8a/libandroidx.graphics.path.so` — `41e9a793c43a0f4fddb19e33f346bace464f30f888ba7b9eaf96294ea115bfb6`; `lib/armeabi-v7a/libandroidx.graphics.path.so` — `41399eba6fc2a60f6f14642375c1824f3cf25eb8fec7397d753730a3ceda3e2b` |
| AndroidX DataStore | `androidx.datastore:datastore-android:1.1.7` (with the `datastore-*` 1.1.7 release family) | `lib/arm64-v8a/libdatastore_shared_counter.so` — `d3e48717c9aa147e0ab21063ba0e8e0211cabf8bf40b222640829519edbf58e1`; `lib/armeabi-v7a/libdatastore_shared_counter.so` — `716c5d8d2cac8ca0edf65da8f139c7886b726ac79d542a14edeb94994ba6d3dc` |

The Gradle release-dependency enumeration for the candidate names both exact
coordinates. That build output is not cited as durable evidence; the durable
candidate receipt above records the resulting shipped paths and hashes.

## Licence and source routes

Both components are Apache-2.0. The full unmodified Apache-2.0 text shipped
in the app is `intergalactic/assets/licenses/mbedtls-Apache-2.0.txt`, SHA-256
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.
It is attached to the two component-specific package labels in
`NativeLicenses._androidEntries`; the focused test verifies that attachment.

* Graphics Path release record: <https://developer.android.com/jetpack/androidx/releases/graphics#1.0.1>.
  The AndroidX source build definition identifies `graphics-path` native source
  under `src/main/cpp` and carries the Apache-2.0 header:
  <https://android.googlesource.com/platform/frameworks/support/+/32a846624ba79ea93528bd09f1cb51fb5c5c4329/graphics/graphics-path/build.gradle>.
* DataStore 1.1.7 release record:
  <https://developer.android.com/jetpack/androidx/releases/datastore#1.1.7>.
  The AndroidX source tree is licensed under Apache-2.0:
  <https://github.com/androidx/androidx/blob/androidx-main/LICENSE.txt>.

These are permissively licensed, unmodified Maven-distributed runtime
components. No corresponding-source publication is asserted or added here.

## Boundaries

This receipt does not prove the compiled bytes can be reproduced from the
linked source trees. It proves only the release-candidate payload identity,
the released component coordinates, the declared licence family, and the
in-app text/attachment route. A changed APK hash or coordinate requires a new
receipt and a review of the notice mapping before release.
