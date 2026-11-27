# Provenance of packaged licence texts

`intergalactic/assets/licenses/` holds nineteen licence documents rendered by
the native in-app licence page. This record identifies each shipped text, its
byte identity, and the component it covers. The listed hashes describe the
tracked files; a final distribution still requires package-level verification.

| Asset | Bytes | SHA-256 | Covers |
| --- | ---: | --- | --- |
| `LGPL-2.1.txt` | 26,419 | `20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95` | mpv, FriBidi, uchardet |
| `LGPL-3.0.txt` | 7,651 | `da7eabb7bafdf7d3ae5e9f223aa5bdc1eece45ac569dc21b3b037520b4464768` | FFmpeg (`--enable-version3`) |
| `GPL-3.0.txt` | 35,150 | `e6037104443f9a7829b2aa7c5370d0789a7bda3ca65a0b904cdc0c2e285d9195` | Required by LGPL-3, which incorporates it by reference |
| `libass-ISC.txt` | 755 | `f7e30699d02798351e7f839e3d3bfeb29ce65e44efa7735c225464c4fd7dfe9c` | libass |
| `dav1d-BSD-2-Clause.txt` | 1,317 | `b327887de263238deaa80c34cdd2ff3e0ba1d35db585ce14a37ce3e74ee389e9` | dav1d |
| `harfbuzz-Old-MIT.txt` | 1,971 | `ba8f810f2455c2f08e2d56bb49b72f37fcf68f1f4fade38977cfd7372050ad64` | HarfBuzz |
| `libpng-PNG-2.0.txt` | 5,345 | `5c0bb4b05b1354ae7c173532b6702ea68b611047ff9b91c4d3af77da39c195d9` | libpng (iOS only) |
| `mbedtls-Apache-2.0.txt` | 11,358 | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` | Mbed TLS; AndroidX Camera Core surface utility; LiveKit Noise |
| `libxml2-MIT.txt` | 1,289 | `c5c63674f8a83c4d2e385d96d1c670a03cb871ba2927755467017317878574bd` | libxml2 |
| `freetype-FTL.txt` | 6,743 | `08c135755dd589039470f1fdbb400daaabaaa50d0b366d19cebff4d22986baa1` | FreeType |
| `zlib-Zlib.txt` | 1,006 | `d63f0feeb74cca59f7369452878bf3d659e32ca00777d3b594699b4c77190831` | zlib (Android only) |
| `media-kit-android-helper-MIT.txt` | 1,112 | `2e3000f38718f050869d57540c288c661a446f64df1ba4ea4764df552b04a331` | media-kit-android-helper (Android only) |
| `Microsoft-WebView2-BSD-3-Clause.txt` | 1,487 | `9995174528dba139ca753d02d8667dbec49f65ab17e65c643a914f2b58cfb4a2` | Microsoft Edge WebView2 Loader, `Webview2Loader.dll` 1.0.992.28 (Windows only) |
| `dart-jni-BSD-3-Clause.txt` | 1,503 | `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` | Dart JNI, `libdartjni.so` from `jni` 1.0.0 (Android only) |
| `kissfft-BSD-3-Clause.txt` | 1,475 | `ddd1400f963747b305bfa39e21206e58805a1c650451e2ee5ce81ed86bc0b1ab` | KISS FFT statically linked into `libnoise.so` from `io.livekit:noise` 2.0.0 (Android only) |
| `rust-crates-NOTICE.txt` | 210,367 | `777f715ed4322654ecbd0a266c245d744e7587f1e030d52f03378547636296c2` | 59 Rust crates and the Rust standard library on supported native platforms |
| `deepfilternet-libdf-rust-crates-NOTICE.txt` | 393,212 | `47d95db86aa1030964635319f4d17e3a1550e4aa7376642c06e8f2342f31bfc3` | 109 DeepFilterNet libDF Rust package/version pairs and Rust standard library on Windows and Android |
| `webrtc-sdk-android-137.7151.04-NOTICES.txt` | 788,358 | `d1f9382c6878ac024155fd6d44a5977329108bb8b0a01cea40e4a2f1d7de252e` | WebRTC-SDK `v137.7151.04` Android `libjingle_peerconnection_so.so` notice packet |
| `libyuv-BSD-3-Clause.txt` | 1,506 | `2b2cc1180c7e6988328ad2033b04b80117419db9c4c584918bbb3cfec7e9364f` | CameraX image-processing JNI payload (Android only) |

## Capture and composition boundaries

The component-specific receipts under this directory record the corresponding
published source or package metadata. Most table entries are verbatim upstream
licence files. `rust-crates-NOTICE.txt` and
`deepfilternet-libdf-rust-crates-NOTICE.txt` are exceptions: they are composed
from their measured crate rosters by their respective generators. The latter
reads only the tracked DeepFilterNet feature-roster capture and the tracked
Rust-standard-library evidence, not a mutable Cargo registry.
The WebRTC-SDK notice packet is a verbatim upstream packet preserved at
`android-native-payloads/webrtc-sdk-android-137.7151.04-WEBRTC.md`.

This evidence records provenance and notice routing, not legal sufficiency,
source-to-binary reproducibility, or a corresponding-source offer.
