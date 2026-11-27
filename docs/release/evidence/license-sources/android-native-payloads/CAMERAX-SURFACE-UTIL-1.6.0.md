# AndroidX Camera Core `libsurface_util_jni.so` — 1.6.0

**Status:** native-origin and Apache-2.0 notice routing recorded. This is a
coverage measurement, not a legal-sufficiency or source-reproducibility
conclusion. The retained `0.8.1+1003` APK is a reference only: its original
candidate was overwritten, so the final release APK must be
remeasured before distribution.

## Conveyance

`androidx.camera:camera-core:1.6.0` is the published AAR origin. Its AAR SHA-256
is `D7F571C1564DB1F9A942EF64F525AC93AE108821DA1EA905DF585C7B644062AA`.
The uncompressed AAR JNI entries are byte-identical to the retained APK paths:

| ABI | APK path and SHA-256 |
| --- | --- |
| arm64-v8a | `lib/arm64-v8a/libsurface_util_jni.so` `A5C9D1928EA92EC7A94DFF8CF666E7739CD734198B9F0AE1D4E28EA3C86516BA` |
| armeabi-v7a | `lib/armeabi-v7a/libsurface_util_jni.so` `78EB0B10E91B819BE97CB7DAA8C97FB757FA6D07CB80CCB7E92C113B45BDA9BE` |

The origin-to-payload comparison is recorded in
`AAR-ORIGINS-0.8.1+1003.md`.

## Exact release source route

AndroidX's Camera 1.6.0 release notes identify the release commit as
`18899702605001b396c92fe1f50666948ce85048` in the public
`platform/frameworks/support` repository. At that commit:

| File | SHA-256 | Finding |
| --- | --- | --- |
| `camera/camera-core/src/main/cpp/CMakeLists.txt` | `6506D3C4353821F4596648008801A81312E2214725297286E067351F8667B286` | creates `surface_util_jni` from `surface_util_jni.cc` and links it only to Android's `native-window` library |
| `camera/camera-core/src/main/cpp/surface_util_jni.cc` | `DD3F02712E359FA0B987BFEF17661686FA130666674FCA2D91405B50AB309779` | Apache-2.0 Camera Core JNI source |
| `camera/camera-core/src/main/cpp/image_processing_util_jni.cc` | `BB35F0827F1D7AD62A321A8F584B2759D2FEFC1A80F5CABB7A3CFBE5B5300256` | separate target that imports and links `libyuv`; not covered by this record |

This distinction is material. The Camera Core POM declares both Apache-2.0 and
BSD-3-Clause because the AAR also contains the libyuv-linked image-processing
target. It must not be read as putting libyuv inside this surface-only payload.

## Notice route

The Camera Core 1.6.0 AAR contains
`META-INF/androidx/camera/camera-core/LICENSE.txt`: Apache-2.0, 10,175 bytes,
SHA-256 `809FA1ED21450F59827D1E9AEC720BBC4B687434FA22283C6CB5DD82A47AB9C0`.
The app renders the complete Apache-2.0 terms under the component-specific
label `AndroidX Camera Core Surface Utility (Android libsurface_util_jni.so)`.
It reuses the tracked canonical Apache asset
`intergalactic/assets/licenses/mbedtls-Apache-2.0.txt`; that filename records
where the terms were first captured and does not attribute CameraX to Mbed TLS.

## Boundaries

- `libimage_processing_util_jni.so` is a distinct libyuv-linked target with
  its own dependency, notice and payload record at
  `CAMERAX-IMAGE-PROCESSING-LIBYUV-1.6.0.md`.
- It does not prove the published AAR can be rebuilt from the recorded source
  commit, nor establish a corresponding-source offer.
- It does not decide legal sufficiency. It records the component boundary,
  receipt, source route, and in-app notice surface.
