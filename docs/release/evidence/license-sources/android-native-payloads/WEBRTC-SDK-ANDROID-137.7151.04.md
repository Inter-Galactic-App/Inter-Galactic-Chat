# Android WebRTC-SDK native runtime — `137.7151.04`

**Status:** version-specific origin, notice, and in-app attachment evidence
recorded. This is not a source-to-binary reproducibility claim and does not
create a corresponding-source offer.

## Conveyed binary chain

The retained `0.8.1+1003` APK reference contains these matching entries:

| APK entry | SHA-256 |
| --- | --- |
| `lib/arm64-v8a/libjingle_peerconnection_so.so` | `6E06EE9C172230EBA99236B4FDA36744CF2C597313E94B46A5946F442197D637` |
| `lib/armeabi-v7a/libjingle_peerconnection_so.so` | `80E795A32744BACF81656B8C8CD99111CD05AD41DE60FD2859446CEB4605A86D` |

Each is byte-identical to the corresponding `jni/<abi>/libjingle_peerconnection_so.so`
entry in the locally resolved Maven artifact
`io.github.webrtc-sdk:android:137.7151.04`:

```text
android-137.7151.04.aar
SHA-256 D69227B176CEB4169C6D17E8DE3D25441B73D16A873BC8EB4D524A455430E76A
size 47,464,622 bytes
```

The publicly published release asset
`https://github.com/webrtc-sdk/android/releases/download/v137.7151.04/libwebrtc.aar`
has the same size and SHA-256. The Maven AAR and the tag's release AAR are
therefore byte-identical, not merely version-equal.

The wrapper tag is `v137.7151.04` at
`f126941a2667f8f1bd3ac60b1a6a4783a3310e1f`. Its `gradle.properties` declares
the matching `VERSION_NAME=137.7151.04` and its `RELEASING.md` directs the
publisher to attach `libwebrtc.aar` to the versioned GitHub release before
running the publish workflow. `downloadAar.sh` derives that same release-asset
URL from `VERSION_NAME`.

## Exact notice packet and user-facing attachment

The exact tag contains `Licenses/WEBRTC.md`, preserved beside this receipt as
[`webrtc-sdk-android-137.7151.04-WEBRTC.md`](webrtc-sdk-android-137.7151.04-WEBRTC.md):

```text
size 788,358 bytes
SHA-256 D1F9382C6878AC024155FD6D44A5977329108BB8B0A01CEA40E4A2F1D7DE252E
```

It is a component notice packet, not a single SPDX declaration. Its headings
cover `webrtc`, `abseil-cpp`, `android_ndk`, `android_sdk`, `base64`,
`boringssl`, `crc32c`, `fft`, `fiat`, `g711`, `g722`, `ijar`, `libaom`,
`libc++`, `libc++abi`, `libevent`, `libjpeg_turbo`, `libsrtp`, `libvpx`,
`libyuv`, `nasm`, `ooura`, `opus`, `pffft`, `protobuf`, `rnnoise`, `sigslot`,
`spl_sqrt_floor`, `usrsctp`, and `zlib`.

The Maven POM's `BSD-3-Clause` declaration is retained as package metadata but
is not treated as a substitute for this packet. The Android license registry
now attaches the byte-identical copy at
`intergalactic/assets/licenses/webrtc-sdk-android-137.7151.04-NOTICES.txt`
under the component-specific label
`WebRTC-SDK (Android libjingle_peerconnection_so.so)`. The focused test locks
the asset digest, package attachment, representative component headings, and a
size floor.

## Boundaries retained

- The wrapper repository's root `LICENSE` is MIT. It is not represented as the
  runtime binary's license set.
- This records a published-binary and notice relationship. It does **not**
  demonstrate that the released AAR can be rebuilt from a particular WebRTC
  source revision or that it corresponds to the Windows `libwebrtc.dll`.
- No source-offer entry is added by this record. A later source-offer decision
  must use evidence for the actual distributed binary and is not satisfied by
  the Maven POM, this notice packet, or the wrapper tag alone.
- `0.8.1+1003` is retained as an APK reference only. Its original candidate
  was overwritten; a final release build must remeasure
  payload digests before distribution.
