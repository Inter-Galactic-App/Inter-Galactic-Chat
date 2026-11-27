# CameraX image-processing JNI and libyuv — Camera Core 1.6.0

**Status:** published dependency licence and notice route recorded. This is an
engineering record, not a source-to-binary reproducibility or legal-sufficiency
conclusion. The retained `0.8.1+1003` APK is reference-only and must be
remeasured against the final release candidate.

## Conveyance and source chain

Inter Galactic declares Flutter `camera` 0.12.0+1. Its Android implementation
`camera_android_camerax` 0.7.2 declares `androidx.camera:camera-core:1.6.0`
alongside the other CameraX 1.6.0 modules. The published Camera Core AAR SHA-256
is `D7F571C1564DB1F9A942EF64F525AC93AE108821DA1EA905DF585C7B644062AA`.
The following AAR entries are byte-identical to the retained APK:

| ABI | APK path and SHA-256 |
| --- | --- |
| arm64-v8a | `lib/arm64-v8a/libimage_processing_util_jni.so` `0292B063FAFCCF734472CBB59588E756C2DBCA907C72021BA6FBF126385508A2` |
| armeabi-v7a | `lib/armeabi-v7a/libimage_processing_util_jni.so` `05973C0CF8E8DD281C8EC505C41814B78B740461056925BB41120594D7C35DCD` |

The origin-to-payload receipt is
`AAR-ORIGINS-0.8.1+1003.md`. CameraX's published 1.6.0 release commit is
`18899702605001b396c92fe1f50666948ce85048`. Its Camera Core CMake file creates
`image_processing_util_jni` and links it to `libyuv::yuv`; its corresponding JNI
source imports libyuv conversion, rotation and planar-function headers.

## Licence and notice route

The exact `camera-core-1.6.0.pom` (SHA-256
`383AA8B63F95C4DA4C2BFFF8DAABEB508024F5D715A8CA31099A06F9A6D96D55`) declares
both Apache-2.0 for Camera Core and BSD-3-Clause for its bundled libyuv limb.
The Camera Core AAR itself carries its Apache `LICENSE.txt`, but not a separate
libyuv text.

The complete libyuv BSD-3-Clause notice was captured from the upstream
`libyuv/libyuv` `LICENSE` at commit
`d694f0a82b4da9d8ea37e6c453b7a34947eb5790`. The captured text is reproduced
verbatim as `intergalactic/assets/licenses/libyuv-BSD-3-Clause.txt`, SHA-256
`2B2CC1180C7E6988328AD2033B04B80117419DB9C4C584918BBB3CFEC7E9364F`, with
`Copyright 2011 The LibYuv Project Authors. All rights reserved.` The app
attaches that exact text to the CameraX image-processing payload label.

The upstream libyuv commit is a durable licence-text anchor, not a claim that
Camera Core 1.6.0's unpublished build input used that exact source revision.
The CameraX release's own public dependency metadata gives the component and
BSD-3-Clause classification but does not publish a separate libyuv revision.

## Surface map

| Surface | State | Evidence or reason |
| --- | --- | --- |
| Structured inventory | required | Native component, CameraX source chain, both ABI digests and notice attachment. |
| Upstream licence and notice capture | required | Camera Core POM declaration plus upstream libyuv LICENSE text/hash. |
| Shipped artifact enumeration | required | Byte-identical Camera Core AAR and retained APK entries; final candidate remeasurement pending. |
| Notice attachment | required | Component-specific Android `LicenseRegistry` entry and packaged BSD asset. |
| Package inclusion | required | `assets/licenses/` is declared by `intergalactic/pubspec.yaml`; candidate package check remains pending. |
| Release/policy notice | required | Third-party notice documents identify CameraX/libyuv and the final-candidate boundary. |
| Corresponding source / public offer | not applicable | BSD-3-Clause permissive notice route; no reciprocal source-offer claim is made. |
| Asset/provenance | required | Tracked asset byte hash and this source record. |
| Tests and negative controls | required | Test checks the holder, clause 3, digest and component attachment. |
| Release record | required | The native-binary gate remains open; final candidate validation is a separate release trigger. |

## Limits

- This resolves the CameraX image-processing mapping and its notice route from
  published dependency information; it does not rebuild or reverse-engineer the
  AAR.
- It does not make an independent CameraX/libyuv source-to-binary,
  corresponding-source, legal-sufficiency or final-release claim.
- The two retained APK digests are reference evidence only because the
  original candidate was overwritten.
