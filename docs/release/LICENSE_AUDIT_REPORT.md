# License Audit Report

Status: PASS FOR CURRENT RELEASE SCOPE; NATIVE DEEPFILTERNET AND OPTIONAL HUSH SUPPORT LAYER SELECTED FOR 0.8.0 WINDOWS PACKAGE WITH FINAL PACKAGE PROOF PENDING

Audit date: 2026-06-12

Build scope reviewed: Inter Galactic `0.7.4+985`

Model-evidence update: on 2026-06-30 S&C collected DeepFilterNet OpenVINO and
Hush license/provenance evidence for the owner-approved plugin
noise-suppression implementation path. On 2026-07-01 AUDIO added separate
native DeepFilterNet C API / DeepFilterNet3 ONNX evidence for the current
Windows developer plugin package. On 2026-07-02 the owner selected the native
DeepFilterNet runtime/model artifacts for the current Windows package; current
Windows CMake bundling is intentional. On 2026-07-03 AUDIO added the optional
Windows Hush support layer and the current Windows CMake path conditionally
bundles the Hush ONNX tarball when present. These records are not proof that
the models or runtime files shipped in `0.7.4+985`, and final `0.8.0+991`
package proof remains required.

This report follows `docs/plans/thirdparty.md` and records the release
compliance evidence gathered by S&C. It avoids speculative legal conclusions and
records future recheck triggers separately from accepted notice decisions.

## Inputs Reviewed

- `LICENSE`, `FORK_NOTICE.md`, and source-offer/policy docs.
- `pubspec.yaml`, `pubspec.lock`, workspace package pubspec files, and local
  Pub package license evidence.
- `intergalactic/ios/Podfile.lock` and platform package names/versions.
- Android Gradle/build metadata for runtime and build dependencies.
- Android FCM / Google Services dependency toggles in
  `intergalactic/scripts/set_google_services.ps1` and the restored shared
  checkout dependency state.
- Native/vendored dependency folders, including RNNoise and patched WebRTC
  release surfaces.
- Bundled app assets under `intergalactic/assets/**`.
- Tiamat assets under `tiamat/assets/**`.
- User-supplied license/provenance evidence mirrored into app-repo release
  evidence under `docs/release/evidence/license-sources/**`.
- DeepFilterNet OpenVINO and Hush local Hugging Face model checkouts plus the
  native DeepFilterNet Windows developer package, with mirrored app-repo
  evidence under
  `docs/release/evidence/license-sources/deepfilternet-openvino/`,
  `docs/release/evidence/license-sources/deepfilternet-native/`, and
  `docs/release/evidence/license-sources/hush/`.
- Flutter repository license evidence for SDK package rows.
- Existing public policy placeholders for third-party notices and asset
  provenance.

## Generated Evidence

- `docs/release/THIRD_PARTY_LICENSES.json`
- `docs/release/THIRD_PARTY_NOTICES.md`
- `docs/release/ASSET_PROVENANCE.md`
- `docs/release/LICENSE_RELEASE_CHECKLIST.md`

The generated JSON inventory currently records:

| Area | Count |
| --- | ---: |
| Dart/Flutter packages | 317 |
| Dart/Flutter packages with local license text | 309 |
| iOS pods | 31 |
| Native/vendored component groups | 7 |
| Asset families | 19 |
| Unknown-license or owner-decision entries | 0 |
| Pending model/runtime artifact evidence records | 3 |

## Findings

### Accounted For

- The Commet fork relationship is documented in `FORK_NOTICE.md`.
- The project license file is present and records AGPL-3.0 text.
- The README points to `LICENSE` and `FORK_NOTICE.md`.
- Most Dart/Flutter package licenses were found from local package cache
  evidence.
- Flutter SDK package rows including `flutter`, `flutter_driver`,
  `flutter_localizations`, `flutter_test`, `flutter_web_plugins`,
  `fuchsia_remote_debug_protocol`, `integration_test`, and `sky_engine` are
  covered for this inventory pass by Flutter repository `LICENSE` evidence
  reviewed on 2026-06-13 plus local app metadata revision
  `7048ed95a5ad3e43d697e0c397464193991fc230`. Regenerate or pin exact SDK
  revision evidence if the release SDK changes.
- The Starfield git package now records the Unlicense evidence already present
  in local pub cache evidence.
- RNNoise has local upstream pinning and a local `COPYING` file, and its
  attribution is now carried in the release notice surface and generated
  patched WebRTC dependency bundle.
- Patched WebRTC/libwebrtc has generated release evidence under
  `docs/release/evidence/webrtc/`, including `LICENSE.md`, `NOTICE`, and
  `manifest.json` for `//libwebrtc:libwebrtc` tied to shipped `libwebrtc.zip`
  sha256
  `f9dc095f1c1d06704598a3125771b926ff123c563ad0a13d8fab4acf600eb1fc`.
- Roboto, Jellee, JetBrains Mono, Tiamat Noto Color Emoji, and Tiamat Kenney
  placeholders have local license evidence.
- Nunito license/source evidence now exists under
  `docs/release/evidence/license-sources/nunito/`, including release-ready
  `SOURCE.md`.
- Twemoji-derived app emoji font license/source evidence now exists under
  `docs/release/evidence/license-sources/twemoji-colr/`; REVIEW accepted the
  current attribution/source evidence on 2026-06-14 for final notice-surface
  inclusion.
- Emojibase metadata was regenerated by REVIEW on 2026-06-13 from
  `emojibase-data@17.0.0`. The stale Commet-era `readme.md` was removed, and
  exact package/source evidence now exists in
  `intergalactic/assets/emoji_data/SOURCE.md` plus
  `docs/release/evidence/license-sources/emojibase/SOURCE.md`.
- ClearURLs LGPL/source evidence now exists under
  `docs/release/evidence/license-sources/clearurls/`; REVIEW accepted current
  shipping on 2026-06-14 with LGPL notice and source-offer/source-link handling
  for `ClearURLs/Rules @ 9317c06`.
- Original Inter Galactic sound-pack evidence now exists under
  `docs/release/evidence/license-sources/renzo-sounds/SOURCE.md` for current
  bundled sound/ringtone assets and Android raw WAV copies, with creator credit
  for Renzo Mayo aka Renzo!, source-master mappings, hashes, and 2026-06-27
  REVIEW regeneration notes recorded.
- DeepFilterNet OpenVINO model evidence now exists under
  `docs/release/evidence/license-sources/deepfilternet-openvino/`, including
  the MIT-tagged model card, upstream DeepFilterNet MIT/Apache license files,
  source URLs/commits, package guidance, and evidence hashes.
- Native DeepFilterNet runtime/model evidence now exists under
  `docs/release/evidence/license-sources/deepfilternet-native/`, including
  hashes for `df.dll`, `DeepFilterNet3_onnx.tar.gz`, `df.dll.lib`, and the
  checked-in MIT/Apache license files. This evidence is distinct from the
  OpenVINO packet and covers the current owner-selected Windows plugin package.
- Hush model evidence now exists under
  `docs/release/evidence/license-sources/hush/`, including Apache-2.0
  license/config/model-card evidence, the upstream dataset-provenance note,
  owner implementation acceptance recorded on 2026-06-30, package guidance, and
  evidence hashes. On 2026-07-03, AUDIO added an off-by-default Windows Hush
  support layer that conditionally bundles
  `plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz`
  when present.
- Commet asset provenance evidence remains under
  `docs/release/evidence/license-sources/commet/commetassets.md` for retained
  `confetti.webp`. Earlier sound/ringtone rows remain superseded historical
  evidence only after the 2026-06-27 replacement.
- iOS CocoaPods acknowledgement and direct license source files are present in
  the Windows workspace, and all 31 iOS pod inventory rows now resolve to those
  files or the synced Flutter podspec.
- Android Gradle Plugin, Kotlin Gradle plugin, AndroidX Biometric, and
  `desugar_jdk_libs` now have Maven/POM evidence attached in the JSON inventory;
  AndroidX Biometric and `desugar_jdk_libs` also point to generated Android
  Gradle evidence for `0.7.4+985`. REVIEW removed Gradle warning pseudo-modules
  and maintainer-local warning/report URI lines from the retained Android
  evidence snapshot on 2026-06-13. REVIEW then added source/policy overrides
  and a Google OSS licenses plugin baseline comparison on 2026-06-14; the final
  FCM-mode Gradle bundle records 171 runtime modules with 0 missing license
  rows.
- The Inter Galactic app icon/logo family is covered by owner-supplied
  provenance from the project owner on 2026-06-12. On 2026-07-03 the owner
  recorded that the logo text was rendered with Lucida Bright Demibold Italic
  from the Windows/Office supplied font available on the creation machine; no
  Lucida font file is bundled. Microsoft Learn Lucida Bright and Windows font
  FAQ links are tracked in `ASSET_PROVENANCE.md` and
  `THIRD_PARTY_LICENSES.json`.
- Placeholder avatars `avatar1.jpg` and `avatar2.jpg` are covered by user
  confirmation on 2026-06-13 that they were Commet-created.
- Pexels-named placeholder photos are covered for this pass by the Pexels
  license page reviewed on 2026-06-13; attribution is not required per that
  page, but its listed restrictions still apply.
- Copied Commet Android Fastlane/store images were removed from the repo on
  2026-06-13 by user direction.
- Empty JS/vodozemac asset placeholder directories did not contain bundled
  third-party JS/WASM files in this pass.

### Notice Surface

- Current release disposition: user confirmed on 2026-06-16 that the
  notice/access surface is verified for the current `0.7.4+985` rollout.
- Nunito Sans, accepted Twemoji-derived app emoji font material, accepted
  Emojibase, accepted ClearURLs, current Renzo sound/ringtone provenance,
  retained Commet confetti provenance, accepted Animated Fluent emoji
  particles, iOS acknowledgements, native/vendored notices, and fork notices
  are included in the accepted current release notice surface.

### Release Evidence Required

- Windows FFmpeg story-video export binaries are staged locally under
  `intergalactic/windows/third_party/ffmpeg/bin/` from the static BtbN
  `win64-lgpl` archive
  `ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip`, and exact
  source/revision, LGPL-only build flags, source URL/source-offer, archive
  hash, binary hashes, and license evidence are attached under
  `docs/release/evidence/ffmpeg/`.
- Android FCM / Firebase package licenses now have generated FCM evidence from
  `docs/release/evidence/android-fcm/0.7.4+985/` attached for the FCM release
  artifact. REVIEW reran `build_android.bat` on 2026-06-14 after fixing the
  evidence collectors; the FCM bundle records 7 Firebase/FlutterFire packages
  with 0 missing local license files. The normal restored checkout will not
  list `firebase_core` or `firebase_messaging` in the static lockfile inventory.
- The prior imported-shader blocker is closed for current source: the active
  login shader is project-authored `constellation.frag`.
- Store/fastlane image provenance is no longer a blocker for the current repo
  state because copied Commet store-page images were removed.
- The current app/public notice access surface is accepted for this release
  scope. Recheck if notice routing changes.

## Highest-Risk Future Recheck Areas

1. Mobile platform notice-surface gaps: iOS acknowledgements and Android
   Gradle/Maven/FCM evidence are now identified in the JSON inventory and
   release evidence. The Android Gradle bundle for `0.7.4+985` is complete with
   0 missing license rows, the Android FCM FlutterFire package evidence is
   attached for `0.7.4+985`, and the Google OSS baseline is generated. Recheck
   if the release SDK, Gradle graph, FCM state, or iOS pod state changes.
2. Rebuilt Windows story-video runtime smoke currently fails with
   `video could not be recorded.` Release owner deferred that runtime story
   export validation to the next release; current FFmpeg license/provenance
   evidence remains accepted.
3. Recheck the app/release notice UI if hosted notice URLs, About/Settings
   routes, bundled assets, or notice text change.
4. Native DeepFilterNet C API / DeepFilterNet3 ONNX and the optional Hush
   support-layer ONNX archive are selected for the current Windows package, and
   DeepFilterNet OpenVINO remains cleared for continued implementation with
   evidence collected. Final release packaging must prove exact files included,
   exclude nested `.git`, LFS/cache files, Hush demo WAV files, and Weya NC
   binaries, include notices, keep `df.dll.lib` link-only unless separately
   packaged, and re-open review if OpenVINO runtime binaries/plugins, extracted
   Hush graph-file packaging changes, Weya NC binaries, runtime model downloads,
   or audio upload paths are added.

## Release Decision

Recommended S&C state: PASS FOR CURRENT RELEASE SCOPE.

This means the inventory and review artifacts exist, unknown/owner-decision
rows are resolved, and the 2026-06-16 release-owner closeout accepted the
current notice/access surface for `0.7.4+985`. Release Pipeline should re-open
the third-party notice/provenance gate only if dependencies, bundled assets,
FFmpeg binaries, notice routing, or release SDK state change.

For model-backed noise-suppression work, recommended S&C state is: native
DeepFilterNet and the optional Hush support-layer ONNX archive may ship in the
current Windows package after Release Pipeline/REVIEW verifies the final
package/source archive, notice surface, and local-only privacy proof; other
model/runtime additions remain package-gated.
