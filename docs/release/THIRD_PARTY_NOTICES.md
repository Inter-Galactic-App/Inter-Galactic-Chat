# Third-Party Notices

This notice index identifies the records and in-app assets that apply to the
application. Exact component/version data is maintained in
`THIRD_PARTY_LICENSES.json`; verbatim licence text remains in the referenced
assets and upstream evidence packets.

The licence-text directory holds **eighteen** files. Its exact file, byte, and
SHA-256 provenance is recorded in
`evidence/license-sources/PACKAGED-LICENCE-TEXT-PROVENANCE.md`.

## Notice access

Use **Settings → About → Open Source Licenses** in the application. The public
notice-access policy is [docs/policies/THIRD_PARTY_NOTICES.md](../policies/THIRD_PARTY_NOTICES.md).

## Component notice routes

| Component family | Platforms or delivery scope | Licence and notice route |
| --- | --- | --- |
| Dart and Flutter packages | All platforms built from the resolved package set | Structured inventory plus Flutter/package licence text. |
| Inter Galactic fork of Commet | All distributed application packages | AGPL-3.0 text, fork attribution, and the corresponding-source route. |
| FFmpeg and libmpv | Earlier Windows releases and current platform-specific media payloads where conveyed | Component-specific notices and [source routes](../policies/SOURCE_OFFER.md). |
| Android CameraX/libyuv | Android image-processing JNI payload | Apache-2.0 CameraX record and BSD-3-Clause libyuv asset attached in-app. |
| Android WebRTC-SDK | Android `libjingle_peerconnection_so.so` payload | Version-specific WebRTC-SDK notice packet attached in-app. |
| Android LiveKit Noise/KISS FFT | Android `libnoise.so` payload | Apache-2.0 LiveKit Noise record and BSD-3-Clause KISS FFT asset attached in-app. |
| vodozemac Rust crate tree | All supported platforms | Versioned Rust crate-tree notice and applicable licence texts registered in-app. |
| DeepFilterNet native runtime | Selected Windows package input | MIT and Apache-2.0 evidence; final package verification pending. |
| Fonts, emoji, sound, and data assets | Where the listed asset is bundled | Asset-specific licences and provenance in `ASSET_PROVENANCE.md`. |

## Candidate boundary

The last distributed public release is `0.8.0+993`. Candidate artefacts must
be checked against the structured inventory and their attached notice assets
before distribution. A record of a component or source input is not by itself
proof that a candidate conveys that material.

## Related records

- [Structured third-party inventory](THIRD_PARTY_LICENSES.json)
- [Asset provenance](ASSET_PROVENANCE.md)
- [Notice-access policy](../policies/THIRD_PARTY_NOTICES.md)
- [Corresponding-source routes](../policies/SOURCE_OFFER.md)

This index provides identification and access information only; it does not
make a legal-sufficiency or publication assertion.
