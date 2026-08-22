# License Release Checklist

Status: PASS FOR 0.7.4+985 RELEASE SCOPE; REOPENED FOR 0.8.0+991 SOUND/MODEL PACKAGE RECHECK

Audit date: 2026-06-12
Updated: 2026-08-09

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
- [x] iOS CocoaPods acknowledgement/license source files are **promoted into
  tracked evidence** at `docs/release/evidence/ios/podfile-lock-snapshot/`,
  covering the Runner acknowledgement markdown/plist plus direct pod license
  files for DKImagePickerController, DKPhotoGallery, SDWebImage, SwiftyGif, and
  WebRTC-SDK. *(Corrected 2026-08-14: this said the files were "synced locally
  under `intergalactic/ios/Pods/Target Support Files/`". That path is gitignored
  and no `ios/Pods/` path has ever been committed, so the checklist was ticked
  against evidence git did not keep. Do not point it back at the working tree.)*
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
  **HISTORICAL SCOPE, stated 2026-08-19:** that packet belongs to the
  `0.7.4+985` evidence set. It is NOT the packet for the `libwebrtc.dll`
  currently recorded in `THIRD_PARTY_LICENSES.json` (`C96E0575…`, public
  `0.8.0+991`–`0.8.0+993`), and it is not the `0.8.1` one either. Ticked
  because the generation step was done for the release it covers; it does not
  discharge anything for a later artefact. The item below is where the current
  and next artefacts are tracked.
- [ ] **0.8.1+1004 Windows libwebrtc re-pin — recut gate.** The four
  source-pointer surfaces move in one change: `_libwebrtcNotice`, the recorded
  source pins in `SOURCE_OFFER.md`, the patched-libwebrtc inventory record, and
  the rebuild-recipe table. They name WebRTC core
  `c6bf02fe64a993fa9d34d44957db71615ec98ddd` and wrapper
  `cdd3c9a98e93f911a67489ecaa3968b730baf8a4`; the record pins the candidate
  `libwebrtc.dll` digest
  `ED53C3D4ADA4F442658465F487CCC091A858C0A541812D489CC3839992D0BE42`.
  `intergalactic/test/config/webrtc_notice_provenance_test.dart` compares the
  two source roles across all four surfaces, and the native-payload gate must
  hash the recut package against the inventory record before this item is
  checked. The old `0.8.0` pair remains historical release evidence, not the
  source pointer for this package.

- [ ] **UNTICKED 2026-08-15 by S&C — this item was ticked and was not done.** It
  read *"DeepFilterNet OpenVINO model evidence is recorded under
  `docs/release/evidence/license-sources/deepfilternet-openvino/`, including
  source/provenance notes, the MIT-tagged model card, upstream DeepFilterNet
  MIT/Apache license files, and evidence hashes."* **That directory has never
  existed in either repo and has no git history.** Partially held instead: the
  upstream URL, both pinned commits and a per-file SHA-256 manifest, in the
  workspace repo at
  `docs/security/hugging-face-model-redistribution-review-2026-06-30.md`. **Not
  held: the model card and the MIT/Apache licence texts.** This stays unticked
  until those are captured at the pinned commit. It is not release-blocking
  today only because the models are not counted as shipped — which is precisely
  why a ticked box here was dangerous: it would have been read as satisfied at
  the moment inclusion finally made it matter.

  **CONFIRMED NON-BLOCKING FOR 0.8.1, 2026-08-19, from the gate's own list.**
  `tools/release/native-payload-inventory.json` enumerates **43** Windows
  native payload paths and contains **no OpenVINO artefact of any name** — zero
  matches for `openvino` in the entire file. The DeepFilterNet component that
  does ship is `df.dll`, the native C API, whose evidence item immediately below
  is ticked and complete. That inventory is the list the 43-file gate asserts
  against, and it passed on the `0.8.1+1003` candidate, so this is the shipping
  set rather than an intention. This item remains open for whenever OpenVINO is
  actually included; it is not owed by this release.

  **Scope of that result, recorded 2026-08-21:** it was measured on
  `0.8.1+1003`. The tree has since moved to `0.8.1+1004` and the gate has not
  been re-run there, so the statement above is historical evidence for `+1003`
  and not a clearance for the current candidate. Re-run the inventory gate
  against whatever build is actually released before treating this as closed.
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

- [x] ~~Stage the Windows desktop story-video export tool: `ffmpeg.exe`.~~
  **RETIRED 2026-08-15 by S&C — DO NOT PERFORM THIS STEP. Following it now
  breaks the build.** `ffmpeg.exe` and `ffprobe.exe` were deleted from the app
  on 2026-08-15 along with story video trim, and
  `intergalactic/windows/CMakeLists.txt:109-116` raises `FATAL_ERROR` if
  **anything at all** is left in `intergalactic/windows/third_party/ffmpeg/bin`.
  The item is kept ticked and struck through rather than deleted, because it is
  the historical record of what was staged for `0.7.4+985` through
  `0.8.0+993`, and the corresponding-source obligation for those releases
  persists. **The June 2026 evidence below covers the pair as it was staged
  then and remains the historical record for those releases.**

  Two things this item said that were also wrong about the current guard, now
  corrected: the guard is **not** an `ffprobe.exe`-name check and is **not**
  Release-only. It is a directory-wide glob that fires on any build type when
  the directory is non-empty. It was described as narrow, which is exactly what
  made the instruction above look survivable.
- [x] **Do not classify the shipped `ffmpeg.exe` as an LGPL-only build.** It
  statically contains FFTW 3.3.11 under GPL-2.0-or-later, reached through
  `chromaprint`'s FFT backend, disclosed 2026-08-09 in
  `docs/policies/SOURCE_OFFER.md`. An LGPL-only classification here would let
  the release gate skip the GPL notice and the corresponding-source work.
  Closed the same day: corresponding source for all 18 obligated components of
  `ffmpeg.exe` — FFTW among them — plus the build definition is **published and
  live**, via GPL-3 §6(d) equivalent access rather than a written offer, and
  `Assert-ThirdPartySource.ps1 -Mode Verify -Platform windows` passes 28
  entries. The classification itself must stay corrected regardless: the box
  closing records that the obligation was discharged, not that the binary
  became LGPL-only.
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
  Current disposition: the source roster was reconciled against `pubspec.lock`
  on 2026-08-19 after AUDIT found 42 missing, stale, or version-drifted rows.
  This supersedes the 2026-06-16 confirmation: it must not be read as proof
  for a `0.8.1` candidate. The independent lockfile-parity gate and an
  artefact-level comparison remain required before this item can close.
- [ ] For model-backed noise suppression, verify the final package/source
  archive includes only selected runtime model files plus notices.
  Native DeepFilterNet C API / DeepFilterNet3 ONNX and Hush license evidence is
  collected, and the release package must still prove exact included files.
  **DeepFilterNet OpenVINO is NOT in that set** — its evidence is `EVIDENCE NOT
  COLLECTED` per the unticked item above and the 2026-08-15 retraction. This
  clause listed it as collected, which is the item a release operator reads when
  closing this gate, so it presented the gate as satisfied on evidence that does
  not exist. *(Corrected 2026-08-18.)* For the current Windows plugin package, the selected
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
