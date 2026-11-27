# Third-Party Notices

This page explains where a recipient can read third-party notices. The complete
component inventory and release evidence are in `docs/release/`.

## In-app notice access

Open **Settings → About → Open Source Licenses**.

The page is populated through Flutter's `LicenseRegistry` and
`NativeLicenses.register()`. Flutter package notices are collected from the
application package set. Native notices are registered separately because they
are not discovered by the Flutter package mechanism.

| Platform | Registered native notice scope |
| --- | --- |
| Windows | `libmpv-2.dll` and its LGPL-2.1, LGPL-3.0, and GPL-3.0 documents; DeepFilterNet libDF Rust-crate notice for `df.dll`. |
| iOS | The bundled media framework components and the applicable complete licence texts. |
| Android | Native media components, CameraX including the libyuv image-processing limb, DataStore, SQLite, Dart JNI payloads, KISS FFT, the version-specific WebRTC-SDK notice packet, and the DeepFilterNet libDF Rust-crate notice. |
| macOS | No media-set notice is registered. No macOS artifact has been distributed. |
| All supported platforms | The vodozemac Rust crate-tree notice and its applicable licence texts. |

The in-app page is the notice-access route for mobile packages because files
inside an IPA or APK are not independently accessible to recipients. Windows
also uses this route for the current package.

## Release scope

The last distributed public binaries are `0.8.1+1004`. The release evidence
inventory includes earlier `0.7.4+985` material where a notice or source route
continues to apply to recipients of that release. A later build remains a
candidate until its package contents and notice attachments are verified.

The current Windows package contains `libmpv-2.dll`; it does not contain the
removed `ffmpeg.exe` or `ffprobe.exe` tools. Earlier releases that conveyed
those tools retain their applicable notice and corresponding-source routes.

## Notice records

- [Release notice index](../release/THIRD_PARTY_NOTICES.md)
- [Structured component inventory](../release/THIRD_PARTY_LICENSES.json)
- [Asset provenance](../release/ASSET_PROVENANCE.md)
- [Corresponding-source routes](SOURCE_OFFER.md)

The records identify component versions, licence text routes, platform scope,
and candidate limitations. They do not make a legal-sufficiency conclusion.
