# LiveKit Noise Android native runtime — 2.0.0

**Status:** Apache-2.0 component record and in-app notice route recorded. This
does not establish a native source-to-binary rebuild, a corresponding-source
offer, legal sufficiency, or a final-release measurement.

## Conveyance

The retained Android `0.8.1+1003` reference APK carries `libnoise.so` on two
ABIs. Both uncompressed entries are byte-identical to the published
`io.livekit:noise:2.0.0` AAR (`DE84EC504E0D7371BCB2AE3790573B418A3B4F3A4B1AF63B91AB991E81169575`):

| ABI | APK path and SHA-256 |
| --- | --- |
| arm64-v8a | `lib/arm64-v8a/libnoise.so` `51176EBDACB2F58075A66564525DE60B0E870F0C81974A9ECEACB032A584F153` |
| armeabi-v7a | `lib/armeabi-v7a/libnoise.so` `CAB25539F0AA5893D00F811245419021127E69EE130775A4E51568C1C982F0E1` |

The AAR-origin receipt is in `AAR-ORIGINS-0.8.1+1003.md`.

## Publisher package evidence

Maven Central publishes the exact `noise-2.0.0.pom` (1,739 bytes,
SHA-256 `68459114435EFA2968FA1BAEBFA4C4299CD17542090ED73A69413FE7504CAECF`).
It names the component `Noise`, declares Apache License 2.0, identifies
LiveKit as developer, and points its SCM field to `github.com/livekit/noise`.

The matching Maven source JAR is 1,629 bytes with SHA-256
`812F474E9B912305E939C40F8F8781B865A14E9CB428EB33BF01558B2FBB1074`.
It contains exactly `com/paramsen/noise/Noise.kt` and
`NoiseNativeBridge.kt`; the bridge calls `System.loadLibrary("noise")`. This
is a versioned publisher artifact linking the declared component to the native
runtime, but it is not a native source archive.

The AAR has only its manifest, metadata, classes JAR, and JNI binaries; it has
no `LICENSE` or `NOTICE` entry. The full Apache-2.0 terms therefore appear
under the dedicated in-app `LiveKit Noise (Android libnoise.so)` label using the
tracked canonical Apache asset.

## Separate KISS FFT limb

`libnoise.so` also statically includes KISS FFT. It is not absorbed into this
Apache component record: the version-pinned BSD-3-Clause attribution and
in-app notice are maintained separately in `KISSFFT-0.8.1+1003.md`.

## Limits

- `github.com/livekit/noise` has no `2.0.0` tag, and the Maven source JAR does
  not contain native build inputs. Do not infer a source revision or rebuild
  correspondence from the source-JAR version.
- The retained APK was overwritten after the original candidate measurement;
  these hashes are a reference only. Remeasure the final release APK.
