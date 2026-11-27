# Android native payload AAR-origin receipt — retained `0.8.1+1003` APK reference

**Status:** partial provenance receipt. This records byte equality between the
retained APK reference entries and the locally resolved Maven AAR entries. It
is not a final licence record, a final notice decision, or corresponding-source
proof. Each unresolved licence/source boundary is stated below.

## Candidate and method

The retained APK reference is
`Android_Builds/Inter-Galactic/0.8.1+1003/InterGalactic-0.8.1+1003.apk`.
The APK and each AAR were opened without extraction, then the uncompressed JNI
entry bytes were SHA-256 hashed. Each listed AAR entry is byte-identical to the
candidate entry with the same ABI.

| Candidate paths | Maven component and AAR identity | Proven result |
| --- | --- | --- |
| `lib/arm64-v8a/libimage_processing_util_jni.so` `0292B063FAFCCF734472CBB59588E756C2DBCA907C72021BA6FBF126385508A2`; `lib/armeabi-v7a/libimage_processing_util_jni.so` `05973C0CF8E8DD281C8EC505C41814B78B740461056925BB41120594D7C35DCD` | `androidx.camera:camera-core:1.6.0`; `camera-core-1.6.0.aar` SHA-256 `D7F571C1564DB1F9A942EF64F525AC93AE108821DA1EA905DF585C7B644062AA` | exact AAR-entry match |
| `lib/arm64-v8a/libsurface_util_jni.so` `A5C9D1928EA92EC7A94DFF8CF666E7739CD734198B9F0AE1D4E28EA3C86516BA`; `lib/armeabi-v7a/libsurface_util_jni.so` `78EB0B10E91B819BE97CB7DAA8C97FB757FA6D07CB80CCB7E92C113B45BDA9BE` | same `androidx.camera:camera-core:1.6.0` AAR | exact AAR-entry match |
| `lib/arm64-v8a/libjingle_peerconnection_so.so` `6E06EE9C172230EBA99236B4FDA36744CF2C597313E94B46A5946F442197D637`; `lib/armeabi-v7a/libjingle_peerconnection_so.so` `80E795A32744BACF81656B8C8CD99111CD05AD41DE60FD2859446CEB4605A86D` | `io.github.webrtc-sdk:android:137.7151.04`; `android-137.7151.04.aar` SHA-256 `D69227B176CEB4169C6D17E8DE3D25441B73D16A873BC8EB4D524A455430E76A` | exact AAR-entry match |
| `lib/arm64-v8a/libnoise.so` `51176EBDACB2F58075A66564525DE60B0E870F0C81974A9ECEACB032A584F153`; `lib/armeabi-v7a/libnoise.so` `CAB25539F0AA5893D00F811245419021127E69EE130775A4E51568C1C982F0E1` | `io.livekit:noise:2.0.0`; `noise-2.0.0.aar` SHA-256 `DE84EC504E0D7371BCB2AE3790573B418A3B4F3A4B1AF63B91AB991E81169575` | exact AAR-entry match |

## Component surface map

| Component / surface | State | Evidence or limit |
| --- | --- | --- |
| CameraX image-processing utility: structured inventory | recorded / final release remeasurement pending | `libimage_processing_util_jni.so` originates from `camera-core:1.6.0`. Flutter's `camera_android_camerax` 0.7.2 declares that CameraX version, release CMake links this target to `libyuv::yuv`, the exact POM declares BSD-3-Clause, and the full libyuv notice is attached in-app. See `CAMERAX-IMAGE-PROCESSING-LIBYUV-1.6.0.md`. |
| CameraX surface utility: structured inventory | recorded / final release remeasurement pending | `libsurface_util_jni.so` originates from `camera-core:1.6.0` and maps to its own Apache-2.0 native-runtime record. The exact release CMake target links only Android system APIs, not libyuv. |
| CameraX upstream licence and notice capture | recorded / split by native target | `camera-core-1.6.0.pom` SHA-256 `383AA8B63F95C4DA4C2BFFF8DAABEB508024F5D715A8CA31099A06F9A6D96D55` declares Apache-2.0 and BSD-3-Clause because Camera Core includes libyuv. The AAR contains `META-INF/androidx/camera/camera-core/LICENSE.txt`, Apache-2.0, 10,175 bytes, SHA-256 `809FA1ED21450F59827D1E9AEC720BBC4B687434FA22283C6CB5DD82A47AB9C0`; the libyuv BSD text and attribution are captured separately in `CAMERAX-IMAGE-PROCESSING-LIBYUV-1.6.0.md`. |
| Android WebRTC-SDK: structured inventory | recorded / final release remeasurement pending | Payload pair originates from `io.github.webrtc-sdk:android:137.7151.04` and maps to its own Android runtime record, never the Windows `libwebrtc` record. |
| Android WebRTC-SDK: upstream licence and source boundary | partial / notice recorded | The exact tag release AAR is byte-identical to the Maven AAR and its `Licenses/WEBRTC.md` packet is captured and attached in-app; see `WEBRTC-SDK-ANDROID-137.7151.04.md`. The wrapper's MIT file is not substituted, and source-to-binary rebuild correspondence is not claimed. |
| LiveKit Noise: structured inventory | recorded / final release remeasurement pending | Candidate payload pair originates from `io.livekit:noise:2.0.0` and maps to its own Apache-2.0 native-runtime record. KISS FFT remains a separately recorded static BSD-3-Clause limb; neither record substitutes for the other. |
| LiveKit Noise: upstream licence and source boundary | partial / notice recorded | Maven Central's exact 2.0.0 POM SHA-256 `68459114435EFA2968FA1BAEBFA4C4299CD17542090ED73A69413FE7504CAECF` declares Apache-2.0, and the matching 1,629-byte source JAR SHA-256 `812F474E9B912305E939C40F8F8781B865A14E9CB428EB33BF01558B2FBB1074` carries the `com.paramsen.noise` JNI wrapper. The AAR has no licence or notice file, and the upstream repository has no 2.0.0 tag; no source-to-binary or source-offer claim is made. |
| Notice / package inclusion | WebRTC-SDK recorded; other groups pending | The WebRTC-SDK complete release notice packet is attached under its own Android licence-page label. Existing Gradle/OSS package metadata remains supplementary; KISS FFT retains its separate attachment. |
| Corresponding source / public offer | blocked | Source revision/build correspondence is not established for the WebRTC-SDK or Noise AARs. Permissive-module POM declarations do not constitute a corresponding-source offer record. |
| Release record | required | The existing native-binary gate remains open; this receipt narrows the origin question only. |

## Required next evidence

1. If a source-offer obligation is proposed for Android WebRTC-SDK, establish
   it from the actual distributed binary; the recorded release AAR/notice
   packet does not prove reproducibility.
2. Re-run the Android inventory gate against a final release candidate; this
   retained reference is not a final-release assertion.
