# License Release Checklist

Status: PASS FOR 0.7.4+985 RELEASE SCOPE; REOPENED FOR 0.8.0+991 SOUND/MODEL PACKAGE RECHECK

Audit date: 2026-06-12
Updated: 2026-07-03

Use this checklist before closing the public release tracker row for third-party
notices and asset provenance.

2026-06-30/2026-07-01 update: the original Renzo Mayo / Renzo! sound-pack
replacement was added after the `0.7.4+985` release-owner closeout. S&C also
collected DeepFilterNet OpenVINO and Hush model evidence after the owner
decided to continue implementation through plugin noise suppression, and AUDIO
added separate native DeepFilterNet C API / DeepFilterNet3 ONNX evidence for
the current Windows developer package. On 2026-07-02 the owner confirmed native
DeepFilterNet should be included now; the Windows CMake bundling of `df.dll`
plus `DeepFilterNet3_onnx.tar.gz` is intentional. Treat the bundled asset,
model/runtime package, and notice/access freshness checks as reopened for the
`0.8.0+991` release until Release Pipeline or REVIEW verifies the final package
manifest/source archive and notice surface. On 2026-07-03, AUDIO added the
off-by-default Windows Hush support layer; current Windows CMake conditionally
bundles
`plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz`
when present.

## Generated Evidence

- [x] `docs/release/THIRD_PARTY_LICENSES.json` exists.
- [x] `docs/release/THIRD_PARTY_NOTICES.md` exists.
- [x] `docs/release/ASSET_PROVENANCE.md` exists.
- [x] `docs/release/LICENSE_AUDIT_REPORT.md` exists.
- [x] Commet fork attribution is included through `FORK_NOTICE.md`.
- [x] Project AGPL license evidence is included through `LICENSE`.
- [x] Owner-supplied app icon/logo provenance is recorded, including the
  2026-07-03 note that logo text was rendered with Lucida Bright Demibold
  Italic from the Windows/Office supplied font available on the creation
  machine; no Lucida font file is bundled.
- [x] User confirmation records `avatar1.jpg` and `avatar2.jpg` as
  Commet-created.
- [x] Pexels license evidence is recorded for Pexels-named placeholder photos.
- [x] Copied Commet Android Fastlane/store images were removed from the repo;
  future store image submissions need current Inter Galactic-owned/listing
  material.
- [x] Original Inter Galactic sound/ringtone evidence is recorded in
  `docs/release/evidence/license-sources/renzo-sounds/SOURCE.md`, including
  creator credit for Renzo Mayo aka Renzo!, the app inclusion/redistribution
  usage basis, source-master mappings, hashes, and Android raw WAV regeneration
  evidence.
- [x] Commet asset provenance evidence is recorded for retained
  `confetti.webp` in
  `docs/release/evidence/license-sources/commet/commetassets.md`; older
  Commet sound/ringtone rows remain superseded historical evidence only.
- [x] Flutter SDK license evidence is recorded for `flutter`,
  `flutter_driver`, `flutter_localizations`, `flutter_test`,
  `flutter_web_plugins`, `fuchsia_remote_debug_protocol`, `integration_test`,
  and `sky_engine` from the Flutter repository `LICENSE`; local app metadata
  records SDK revision `7048ed95a5ad3e43d697e0c397464193991fc230`.
- [x] Starfield git package evidence is recorded from the local Unlicense text
  already present in the pub cache.
- [x] User-supplied local license evidence was mirrored into
  `docs/release/evidence/license-sources/` for Nunito, Twemoji-derived app
  emoji font material, Emojibase, ClearURLs, and Commet asset evidence so the
  app repo/source archive no longer depends on workspace-only evidence paths.
- [x] REVIEW normalized the provided Nunito, TwemojiCOLR/Twemoji, Emojibase,
  ClearURLs, and Commet asset evidence into release-ready source records on
  2026-06-14.
- [x] iOS CocoaPods acknowledgement/license source files are synced locally
  under `intergalactic/ios/Pods/Target Support Files/` plus direct pod license
  files for DKImagePickerController, DKPhotoGallery, SDWebImage, SwiftyGif, and
  WebRTC-SDK.
- [x] iOS pod inventory rows resolve to the synced acknowledgement markdown/plist,
  Flutter podspec, and direct pod license files.
- [x] Android Gradle Plugin, Kotlin Gradle plugin, AndroidX Biometric, and
  `desugar_jdk_libs` rows have Maven/POM evidence recorded; AndroidX Biometric
  and `desugar_jdk_libs` also point to generated Android Gradle evidence for
  `0.7.4+985`.
- [x] RNNoise vendored source/model attribution is recorded from local
  `UPSTREAM.md` and `COPYING`, and the generated patched WebRTC dependency
  notice includes the `rnnoise` section for the Windows libwebrtc artifact.
- [x] Patched WebRTC/libwebrtc notice evidence is generated under
  `docs/release/evidence/webrtc/` for `//libwebrtc:libwebrtc` and shipped
  `libwebrtc.zip` sha256
  `f9dc095f1c1d06704598a3125771b926ff123c563ad0a13d8fab4acf600eb1fc`.
- [x] DeepFilterNet OpenVINO model evidence is recorded under
  `docs/release/evidence/license-sources/deepfilternet-openvino/`, including
  source/provenance notes, the MIT-tagged model card, upstream DeepFilterNet
  MIT/Apache license files, and evidence hashes.
- [x] Native DeepFilterNet C API / DeepFilterNet3 ONNX evidence is recorded
  under `docs/release/evidence/license-sources/deepfilternet-native/`,
  including the current Windows developer package hashes for `df.dll`,
  `DeepFilterNet3_onnx.tar.gz`, `df.dll.lib`, and checked-in MIT/Apache license
  files. Owner confirmation on 2026-07-02 selects these native runtime/model
  artifacts for the current Windows package.
- [x] Hush model evidence is recorded under
  `docs/release/evidence/license-sources/hush/`, including Apache-2.0 license,
  model card, config metadata, dataset-provenance note, owner implementation
  acceptance, package guidance, evidence hashes, and the 2026-07-03 optional
  Windows support-layer package path.
- [x] REVIEW accepted the TwemojiCOLR-derived app emoji font attribution/source
  evidence on 2026-06-13. Include TwemojiCOLR/Twemoji attribution, license
  links, and applicable change indication in the final notice surface.
- [x] REVIEW regenerated Emojibase metadata on 2026-06-13 from
  `emojibase-data@17.0.0`, removed the stale Commet-era `readme.md`, and
  recorded the package tarball, gitHead, integrity, generation command, MIT
  license evidence, and shipped JSON SHA-256 hashes in
  `intergalactic/assets/emoji_data/SOURCE.md` and
  `docs/release/evidence/license-sources/emojibase/SOURCE.md`.
- [x] REVIEW accepted ClearURLs `clearurls.json` handling on 2026-06-13 for the
  current `ClearURLs/Rules @ 9317c06` pin, provided the final notice surface
  carries LGPL-3.0 text and source-offer/source-link details.
- [x] REVIEW accepted synced iOS CocoaPods acknowledgement/license source files
  for the inventory on 2026-06-13. Final exposure of those notices is tracked
  by the aggregate app/release notice surface item below.
- [x] REVIEW accepted Animated Fluent emoji particle attribution on 2026-06-13
  from the local MIT source note after confirming the particle files match the
  Commet reference by SHA-256. Include the source attribution and MIT notice in
  the final notice surface.

## Full Gate Closure Evidence

- [x] Stage the Windows desktop story-video export tool pair:
  `ffmpeg.exe` and `ffprobe.exe` from the same LGPL-only FFmpeg build.
- [x] Record exact FFmpeg source/revision, configure/build flags, source link,
  and patch diff/source-offer evidence for the bundled desktop export tools.
  REVIEW staged the static BtbN `win64-lgpl` pair from
  `ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip` on 2026-06-13 and recorded
  archive hash, binary hashes, FFmpeg source commit, LGPLv3 license text, and
  local `-version` output under `docs/release/evidence/ffmpeg/`.
- [x] For Android FCM artifacts, attach the generated Firebase/FlutterFire
  package evidence from `docs/release/evidence/android-fcm/<version>/`.
  REVIEW reran `build_android.bat` on 2026-06-14 after fixing the evidence
  collectors. The generated `docs/release/evidence/android-fcm/0.7.4+985/`
  bundle records 7 Firebase/FlutterFire packages with 0 missing local license
  files.
- [x] For Android Gradle/Maven runtime artifacts, regenerate or review the
  retained `docs/release/evidence/android-gradle/<version>/` evidence until no
  missing POM license metadata remains unresolved. REVIEW added source/policy
  overrides and a Google OSS licenses plugin baseline comparison, then reran
  `build_android.bat --skip-codegen` on 2026-06-14. The final FCM-mode
  `0.7.4+985` Gradle bundle records 171 runtime modules with 106 POM-covered,
  65 override-covered, and 0 missing license rows; the Google OSS baseline
  records 3 generated files, 228 parsed notice names, and 229 dependency
  modules.
- [x] Expose the complete native/asset/fork notice bundle in the app About
  surface or release package, including accepted iOS, Nunito, Twemoji,
  Emojibase, ClearURLs, native/vendored, asset, and fork notices.
- [ ] Re-run or confirm license-inventory freshness if the FCM/dependency
  state, release SDK, or bundled assets change after the current `0.7.4+985`
  evidence.
  Current disposition: user confirmed on 2026-06-16 that the notice/access
  surface is verified, and REVIEW confirmed no dependency, release SDK, FCM
  state, bundled asset, or FFmpeg evidence change invalidated the current
  `0.7.4+985` records. For the `0.8.0+991` release, the Renzo sound/ringtone
  replacement is a bundled-asset change and must be rechecked before this item
  is closed again.
- [ ] For model-backed noise suppression, verify the final package/source
  archive includes only selected runtime model files plus notices.
  DeepFilterNet OpenVINO, native DeepFilterNet C API / DeepFilterNet3 ONNX, and
  Hush license evidence is collected, but the release package must still prove
  exact included files. For the current Windows plugin package, the selected
  native DeepFilterNet runtime files are `df.dll` plus
  `DeepFilterNet3_onnx.tar.gz`, and the optional Hush support-layer archive is
  `plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz`
  when present. Keep `df.dll.lib` link-only unless a separate review explicitly
  includes it. Exclude nested `.git`, LFS metadata/cache files, Hush demo WAV
  samples, and Weya NC binaries unless a separate review explicitly includes
  them.
- [ ] Re-run the notice/access-surface check after exact model package contents
  are known, and re-open S&C if OpenVINO runtime binaries/plugins, Weya NC
  binaries, extracted Hush graph-file packaging changes, runtime model
  downloads, or audio upload paths are added.

## S&C Close Criteria

- [x] No asset row remains unresolved without an explicit accepted release
  decision or regeneration/replacement note.
- [x] All required attribution text has a release surface for the current
  release scope.
- [x] The generated notice bundle covers Dart/Flutter packages, iOS pods,
  Android runtime artifacts, native/vendored components, fonts, images, sounds,
  shaders, emoji data, and fork notices.
- [x] Release Pipeline or Review updates
  `docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md` with final evidence.
