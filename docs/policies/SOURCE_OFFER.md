# Source Offer

This page identifies the corresponding-source routes for distributed material.
It describes source availability and release scope; it is not a statement of
legal sufficiency.

## Current public binaries

The current public Windows and Android release is `0.8.0+993`. Source for the
application and the components listed below is available from:

- Application source: `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`
- Corresponding-source index and archives: `https://app.ourgalaxy.space/source/`

Earlier releases remain covered by the source route associated with the
material they conveyed. A later build is a candidate until it is distributed;
do not use a candidate hash or component record to describe an earlier public
binary.

## Component routes

| Component family | Delivered scope | Source route |
| --- | --- | --- |
| Inter Galactic modified Commet fork | Distributed app packages | Application source repository and fork notices. |
| FFmpeg tool binaries | Earlier Windows releases that included them | Versioned FFmpeg source archive and published build definition under `/source/`. |
| `libmpv-2.dll` | Windows releases that include the DLL | libmpv source route and its separate FFmpeg source route under `/source/`. |
| Apple media frameworks | Distributed iOS packages containing the frameworks | Versioned corresponding-source archives and applicable patches under `/source/`. |
| libwebrtc | Distributed packages containing the recorded libwebrtc payload | The pinned source repositories and revisions named in the release source index. |
| ClearURLs rules | Packages containing `clearurls.json` | Pinned ClearURLs source revision and LGPL route. |
| vodozemac Rust crate tree | Supported packages that contain the compiled tree | The application source route and the recorded crate-source evidence. |

### Recorded libwebrtc source pins

The public Windows libwebrtc record uses these source revisions:

- WebRTC core: `https://github.com/Inter-Galactic-App/webrtc-core`, branch
  `intergalactic/windows-streaming-m137`, commit
  `6084687728c2adc049908e353a679f7d91c0d3d5`.
- libwebrtc wrapper: `https://github.com/Inter-Galactic-App/libwebrtc`, branch
  `intergalactic/windows-hardware-h264`, commit
  `1f70ae1d5b063c51a531fe94eef6ae20d09c6c3e`.

## Package boundaries

- The current Windows package contains `libmpv-2.dll`; it does not contain the
  removed FFmpeg tools.
- Android and Apple payloads must be measured against the final candidate before
  their component hashes or package scope are updated.
- Native DeepFilterNet, Hush, and model artifacts are governed by their own
  inventory and evidence records. This page does not assert their final package
  inclusion.
- System libraries supplied by a platform are not application-bundled source
  obligations.

## Notices and attribution

Use the [third-party notice index](THIRD_PARTY_NOTICES.md) for licence-text
access and the [structured inventory](../release/THIRD_PARTY_LICENSES.json)
for component identity, platform scope, and evidence references.

The listed routes must remain available for the releases to which they apply.
