# Source Offer

This page identifies the corresponding-source routes for distributed material.
It describes source availability and release scope; it is not a statement of
legal sufficiency.

## Current public binaries

The current public Windows and Android release is `0.8.1+1004`. Source for the
application and the components listed below is available from:

- Application source: `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`
- Corresponding-source index and archives: `https://app.ourgalaxy.space/source/`

Windows and Android were built from different commits for this release, so they
have separate corresponding-source archives. The repository snapshot above is
the Windows source; `SOURCE-CORRESPONDENCE-0.8.1+1004.md` under `/source/`
names each platform's build commit and the archive that matches it.

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
| DeepFilterNet libDF Rust crate tree | Windows `df.dll` and Android `libdf.so` in `0.8.1+1004` | No corresponding-source offer is added solely for this tree: the captured 109-package closure and Rust standard library declare permissive-only terms. The retained native-payload receipts identify the historical binary scope; the 109-package in-app notice was registered later and requires verification in a future package before recipient delivery is claimed. |

### Upstream source reference for Android desugaring 2.1.5

The Android core-library desugaring runtime's upstream
[release-preparation source](https://github.com/google/desugar_jdk_libs/tree/73170c345e6a762fc6a1f0301bb15218850023ef)
declares `desugar_jdk_libs` 2.1.5 and configuration dependency 2.1.5.
Its [BUILD target](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/BUILD)
is selected with `bazel build maven_release_jdk11`; this is an inspected
upstream target, not a tested complete build recipe or independently proven
source for the published Maven JAR. The [versioned component record](../release/evidence/license-sources/desugar-jdk/2.1.5/SOURCE.md)
contains the exact licence text, artifact identity and correspondence limits.
This upstream reference does not identify a newly served corresponding-source
archive or assert that historical app-source ZIPs contain this library.
Complete covered-source/build-material delivery and the applicable recipient
source-access route remain separate from this source reference.

### iOS patched-wrapper source identity

An iOS-only `flutter_vodozemac`/Dart `vodozemac` 0.5.0 variant uses
upstream Famedly commit `1bdded7dd13d26b3f77c4287c9321f7cf924dec9`
plus the exact modification, manifest and build instructions tracked at
`intergalactic/ios/patches/dart-vodozemac/`. Its source record is
`docs/release/evidence/license-sources/dart-vodozemac-ios-patch/SOURCE.md`.
This is the modified AGPL wrapper, not the unpatched hosted package named by
the committed default lock. This source-offer index does not identify a
published iOS archive for this variant; the current public release offer
above is unchanged.

### Selected Windows 0.8.2+1008 libwebrtc source pins

The selected Windows native build uses WebRTC core
`https://github.com/Inter-Galactic-App/webrtc-core`, branch
`intergalactic/windows-streaming-m137`, commit
`c6bf02fe64a993fa9d34d44957db71615ec98ddd`, and libwebrtc wrapper
`https://github.com/Inter-Galactic-App/libwebrtc`, branch
`intergalactic/windows-hardware-h264`, commit
`c8619a6d98d49939b6affe642a037d9f5a6ed9d5`.
The measured DLL has SHA-256
`2899E370BC49BA746FB61E3E610CC473B945738EF87C67BBC311552F5810C209`.
The versioned evidence is
`../release/evidence/license-sources/libwebrtc-windows/0.8.2+1008.md`;
the build instructions are in the WebRTC fork rebuild kit. This identifies
the selected native component, not a newly published app-source archive.
The current public Windows/Android source offer above is unchanged.

### Historical Windows 0.8.1+1004 libwebrtc source pins

The Windows `0.8.1+1004` release record uses these source revisions:

- WebRTC core: `https://github.com/Inter-Galactic-App/webrtc-core`, branch
  `intergalactic/windows-streaming-m137`, commit
  `c6bf02fe64a993fa9d34d44957db71615ec98ddd`.
- libwebrtc wrapper: `https://github.com/Inter-Galactic-App/libwebrtc`, branch
  `intergalactic/windows-hardware-h264`, commit
  `cdd3c9a98e93f911a67489ecaa3968b730baf8a4`.

## Package boundaries

- The current Windows package contains `libmpv-2.dll`; it does not contain the
  removed FFmpeg tools.
- Android and Apple payloads must be measured against the final candidate before
  their component hashes or package scope are updated.
- The libDF Rust runtime has its own delivered-payload record and permissive
  source-offer classification. DeepFilterNet3, Hush, and other model artifacts
  remain separate inventory/evidence records; this page does not infer their
  package inclusion from the libDF runtime.
- System libraries supplied by a platform are not application-bundled source
  obligations.

## Notices and attribution

Use the [third-party notice index](THIRD_PARTY_NOTICES.md) for licence-text
access and the [structured inventory](../release/THIRD_PARTY_LICENSES.json)
for component identity, platform scope, and evidence references.

The listed routes must remain available for the releases to which they apply.
