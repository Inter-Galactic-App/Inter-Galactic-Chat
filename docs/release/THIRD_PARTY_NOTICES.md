# Third-Party Notices

Status: PASS FOR CURRENT RELEASE SCOPE

Inventory date: 2026-06-12

Build scope reviewed: Inter Galactic `0.7.4+985`

Follow-up reviewed: 2026-06-13 upstream Commet provenance, Flutter SDK license
evidence, iOS CocoaPods acknowledgements, Android Maven/POM evidence, and
primary-source license metadata where available; 2026-06-14 provided license
evidence normalization and owner acceptance for retained Commet-inherited asset
evidence.

This is an engineering notice inventory for release readiness. It does not
replace legal review. The 2026-06-16 release-owner closeout accepted the
current evidence and verified notice/access surface for the `0.7.4+985`
website/TestFlight rollout. Re-open this gate if dependency state, release SDK,
bundled assets, notice routing, or FFmpeg binaries change.

## Source Files

- Machine-readable inventory: `docs/release/THIRD_PARTY_LICENSES.json`
- Asset provenance review: `docs/release/ASSET_PROVENANCE.md`
- Audit summary: `docs/release/LICENSE_AUDIT_REPORT.md`
- Release checklist: `docs/release/LICENSE_RELEASE_CHECKLIST.md`
- Project license: `LICENSE`
- Fork attribution: `FORK_NOTICE.md`

The JSON inventory was generated from checked-in lockfiles, local package
license files, native/vendored dependency metadata, and manual asset evidence.
No Flutter or Dart command was run for this pass.

Android release APK builds refresh shipped Gradle/Maven dependency evidence
with `intergalactic/scripts/collect_android_gradle_license_evidence.ps1`.
Workspace `build_android.bat` runs that helper after the release APK is built,
while the classpath still matches the shipped artifact, and writes evidence
under `docs/release/evidence/android-gradle/<version>/`.

Android FCM / Google Services builds have one additional dependency-state
boundary: the shared checkout normally restores Firebase dependencies to the
commented-out non-Google state after Android builds. Workspace
`build_android.bat` now also runs
`intergalactic/scripts/collect_android_fcm_license_evidence.ps1` for FCM release
APKs and writes Firebase/FlutterFire package notice evidence under
`docs/release/evidence/android-fcm/<version>/`. These collectors do not read or
embed `google-services.json`.

REVIEW reran `build_android.bat` on 2026-06-14 after fixing the evidence
collectors. The refreshed Gradle bundle exists at
`docs/release/evidence/android-gradle/0.7.4+985/` with `build_mode: fcm` and
includes Firebase/FCM Maven modules. The separate Firebase/FlutterFire package
notice bundle under `docs/release/evidence/android-fcm/0.7.4+985/` records 7
packages with 0 missing local license files.

## Project And Fork Notices

Inter Galactic is a modified fork of Commet. The fork notice and project license
are release-required notices:

- Upstream project: Commet
- Upstream source: `https://github.com/commetchat/commet`
- Fork notice: `FORK_NOTICE.md`
- Project license text: `LICENSE`
- Project license family recorded by this inventory: AGPL-3.0

The app should continue to ship or link the source offer, `LICENSE`, and
`FORK_NOTICE.md` anywhere source-license notices are surfaced.

## Dependency Inventory Summary

| Area | Count | Status |
| --- | ---: | --- |
| Dart/Flutter packages from `pubspec.lock` | 317 | 309 had local license text available in the static pass. Flutter SDK pseudo-package rows now use Flutter repository license evidence, and the Starfield git package now records the Unlicense evidence already present locally. No Dart/Flutter row remains `UNKNOWN` or `NEEDS OWNER DECISION`. |
| iOS pods from `intergalactic/ios/Podfile.lock` | 31 | All 31 pod rows now resolve to the locally synced CocoaPods acknowledgement markdown/plist, Flutter podspec, or direct pod license files. REVIEW accepted those source files for the release-notice inventory on 2026-06-13; final app/release notice exposure is tracked by the aggregate notice-surface gate. |
| Native and vendored components | 7 | RNNoise has local upstream/license evidence and release-notice attribution. Android Gradle Plugin, Kotlin Gradle plugin, AndroidX Biometric, `desugar_jdk_libs`, and Android release runtime artifacts now have Maven/POM, source/policy override, generated Android Gradle, Android FCM, and Google OSS baseline evidence for `0.7.4+985`. Patched WebRTC has a generated native notice bundle under `docs/release/evidence/webrtc/`. FFmpeg/FFprobe Windows story-export tools have static LGPL evidence under `docs/release/evidence/ffmpeg/`. |
| Asset families | 19 | Owner-created app icon and several font/image families have evidence. REVIEW accepted the TwemojiCOLR attribution/source evidence, regenerated Emojibase from `emojibase-data@17.0.0`, accepted ClearURLs LGPL source-offer handling, and accepted Animated Fluent emoji MIT attribution on 2026-06-13. On 2026-06-14, REVIEW normalized the provided license evidence into release-ready source records and recorded user/owner acceptance for retained Commet-inherited sound/ringtone/confetti evidence. User confirmed the notice/access surface on 2026-06-16; stricter optional exact-file provenance follow-up is future work only. |
| Unknown-license or owner-decision entries | 0 | The generated JSON has no remaining `UNKNOWN` / `NEEDS OWNER DECISION` rows. Rebuilt Windows FFmpeg story-export smoke is deferred to the next release and does not reopen current license/provenance evidence. |

## Notices Already Accounted For

The generated inventory includes local license text or local evidence for the
following material areas:

- AGPL-3.0 project license and Commet fork attribution.
- Most Dart and Flutter packages resolved from `pubspec.lock`.
- Flutter SDK package rows including `flutter`, `flutter_driver`,
  `flutter_localizations`, `flutter_test`, `flutter_web_plugins`,
  `fuchsia_remote_debug_protocol`, `integration_test`, and `sky_engine`, using
  Flutter repository `LICENSE` evidence reviewed on 2026-06-13 and local app
  metadata revision `7048ed95a5ad3e43d697e0c397464193991fc230`.
- Starfield git package `6e3dee6dd4f56c3d8afb180832c27418d101c86f`, using the
  local Unlicense text already present in the pub cache evidence.
- iOS CocoaPods rows, using the synced Runner acknowledgement markdown/plist,
  Flutter podspec, and direct pod license files for DKImagePickerController,
  DKPhotoGallery, SDWebImage, SwiftyGif, and WebRTC-SDK.
- Android Gradle/Maven root rows, using generated Android evidence for
  `0.7.4+985` plus primary Maven POM metadata for Android Gradle Plugin,
  Kotlin Gradle plugin, AndroidX Biometric, and `desugar_jdk_libs`; source and
  policy overrides for runtime artifacts whose local POM metadata is absent;
  and Google OSS licenses plugin baseline evidence for the FCM release build.
- RNNoise vendored source, upstream pin, and local `COPYING` file, with
  attribution carried in this release notice surface and the patched WebRTC
  dependency bundle.
- Patched WebRTC/libwebrtc Windows artifact notices generated under
  `docs/release/evidence/webrtc/` for `//libwebrtc:libwebrtc`, including
  `LICENSE.md`, `NOTICE`, and `manifest.json` tied to shipped
  `libwebrtc.zip` sha256
  `f9dc095f1c1d06704598a3125771b926ff123c563ad0a13d8fab4acf600eb1fc`.
- Roboto font family, Apache-2.0 evidence in `intergalactic/assets/font/roboto/`.
- Jellee font family, OFL evidence in `intergalactic/assets/font/jellee/`.
- JetBrains Mono font family, OFL evidence in `intergalactic/assets/font/code/`.
- Noto Color Emoji as used by Tiamat, OFL evidence in `tiamat/assets/font/emoji-font/`.
- Kenney prototype texture placeholders used by Tiamat, CC0 evidence in
  `tiamat/assets/images/placeholder/generic/License.txt`.
- Animated Fluent emoji particle source note, MIT noted in
  `intergalactic/assets/images/effects/particles/fluent-emoji-source.txt`.
- Nunito license/source evidence mirrored under
  `docs/release/evidence/license-sources/nunito/`, including `SOURCE.md`.
- Twemoji-derived app emoji font license evidence under
  `docs/release/evidence/license-sources/twemoji-colr/`, including
  `SOURCE.md`.
- Emojibase license/source evidence under
  `docs/release/evidence/license-sources/emojibase/` and
  `intergalactic/assets/emoji_data/SOURCE.md`.
- ClearURLs rule source pin in `intergalactic/assets/data/sources.txt`, plus
  mirrored release-ready license/source evidence under
  `docs/release/evidence/license-sources/clearurls/`.
- Commet asset provenance evidence under
  `docs/release/evidence/license-sources/commet/commetassets.md`, covering
  bundled sound / ringtone assets and `confetti.webp` as upstream Commet AGPL
  repository assets with first-observed commits and 2026-06-14 user/owner
  acceptance recorded.
- Inter Galactic app icon family, with creator/provenance confirmed by the
  project owner on 2026-06-12.
- Placeholder avatars `avatar1.jpg` and `avatar2.jpg`, confirmed by the user on
  2026-06-13 as Commet-created.
- Pexels-named placeholder photos under
  `intergalactic/assets/images/placeholders/photos/`; Pexels license evidence
  reviewed on 2026-06-13.

## 2026-06-14 Local License Evidence Mirror

S&C reviewed the user-supplied workspace-only license evidence folder. REVIEW
mirrored the release-relevant files into app-repo evidence under
`docs/release/evidence/license-sources/` on 2026-06-13 so the public source
archive and app docs do not depend on a private workspace path. On 2026-06-14,
REVIEW normalized the loose sidecars into release-ready `SOURCE.md` records and
recorded user/owner acceptance for the retained Commet-inherited sound,
ringtone, and confetti asset evidence. The 2026-06-16 release-owner closeout
accepted this evidence for the current release scope and verified the
notice/access surface.

| Evidence folder | Current use in release review | Remaining action |
| --- | --- | --- |
| `docs/release/evidence/license-sources/nunito/` | Supports the bundled Nunito font license/source row with local OFL-1.1 text and `SOURCE.md`. | Release-ready evidence; notice/access surface verified for the current release. |
| `docs/release/evidence/license-sources/twemoji-colr/` | Supports the Twemoji-derived app emoji font license row with local license evidence and `SOURCE.md`. | Release-ready evidence; notice/access surface verified for the current release. |
| `docs/release/evidence/license-sources/emojibase/` | Supports the bundled emoji metadata license row with MIT text and package/source/hash evidence in `SOURCE.md`. | Release-ready evidence from `emojibase-data@17.0.0`; notice/access surface verified for the current release. |
| `docs/release/evidence/license-sources/clearurls/` | Supports ClearURLs rule license/source evidence with local LGPL-3.0 text and `SOURCE.md`. | Release-ready evidence for current pinned rules with LGPL notice and source-offer/source-link handling; notice/access surface verified for the current release. |
| `docs/release/evidence/license-sources/commet/` | Supports Commet-inherited sound/ringtone assets and `confetti.webp` as AGPL repository assets with first-observed upstream commits and user/owner acceptance recorded. | Release-ready evidence for this release pass; Commet AGPL/fork/source and retained asset provenance notes are accepted for the current notice surface. |

## 2026-06-13 Upstream Commet Follow-Up

AUDIT compared the remaining release-evidence rows against `references/commet-main`
and primary upstream metadata where it was available. This follow-up identifies
usable evidence and remaining blockers; it does not replace counsel or owner
review.

### Upstream Evidence Found

| Item | Evidence found | Release interpretation |
| --- | --- | --- |
| Commet fork license | `references/commet-main/LICENSE` contains the upstream AGPL-3.0 license text. | Keep AGPL license text, fork attribution, source offer, and modification notice in the release package. |
| Inherited asset bytes | Current Inter Galactic files for TwemojiCOLR OTF, Nunito Sans TTFs, and Fluent emoji particle images match files under `references/commet-main/commet/assets/**` by SHA-256 comparison. | Inheritance is provenance evidence only. For rows with independent source/license evidence or explicit owner acceptance recorded here, use that release decision; otherwise replace or re-audit before treating inherited status alone as license closure. |
| Commet sound/ringtone assets | `docs/release/evidence/license-sources/commet/commetassets.md` records `ringtone_in.ogg`, `ringtone_out.ogg`, `joined_call.ogg`, `left_call.ogg`, `message.ogg`, `muted.ogg`, and `unmuted.ogg` as upstream Commet repository assets with first-observed commits, AGPL repository-asset inheritance, unknown original creators, and 2026-06-14 user/owner acceptance. | Treat the sound/ringtone rows as release-ready evidence for this release pass under the Commet AGPL/fork/source path; include the retained unknown-creator provenance note in the final notice surface. |
| Commet confetti asset | `docs/release/evidence/license-sources/commet/commetassets.md` records `commet/assets/images/effects/particles/confetti.webp` as first observed in Commet commit `3d39f25` and inherited as an upstream Commet AGPL repository asset, with unknown original creator and 2026-06-14 user/owner acceptance. | Treat `confetti.webp` as release-ready evidence for this release pass under the Commet AGPL/fork/source path; keep Element evidence only as interoperability context. |
| Placeholder avatars | User confirmed on 2026-06-13 that `avatar1.jpg` and `avatar2.jpg` are Commet-created. | Treat these placeholder avatars as owner-confirmed provenance for this release pass. |
| Pexels placeholder photos | Files under `intergalactic/assets/images/placeholders/photos/` are Pexels-named, and the Pexels license page reviewed on 2026-06-13 says Pexels photos/videos are free to use, attribution is not required, and modification is allowed. | Treat as Pexels-license evidence for this release pass; retain the Pexels license URL and remember the listed restrictions. Exact download URLs remain nice-to-have provenance. |
| Fastlane store images | User identified the Android Fastlane images as copied from Commet's store page and directed removal on 2026-06-13. | Removed from the repo; future store image submissions need current Inter Galactic-owned/listing assets. |
| Element confetti compatibility | `references/element-web/apps/web/src/effects/index.ts` uses the same `nic.custom.confetti` message effect type, and `references/element-web/apps/web/src/effects/confetti/index.ts` renders confetti with canvas-generated particles. No matching `confetti.webp` file was found in Element Web. | Element proves Matrix/Element interoperability for the effect type, but not provenance or license evidence for Inter Galactic's bundled WebP sprite sheet. |
| Roboto, Jellee, JetBrains Mono, Tiamat Noto Color Emoji, Kenney placeholders | Local license files exist in Inter Galactic and/or `references/commet-main`. | Already accounted; include these notices in the generated bundle. |
| Fluent emoji particles | Commet and Inter Galactic both carry a source note for `Tarikul-Islam-Anik/Animated-Fluent-Emojis`; Inter Galactic records MIT as of 2025-02-16, and the current particle files match Commet by SHA-256. | Accepted for this release-notice pass; include the Animated Fluent Emojis source attribution and MIT notice in the generated notices. |
| ClearURLs rules | Commet and Inter Galactic carry `assets/data/sources.txt` pinning `ClearURLs/Rules @ 9317c06`; mirrored release-ready evidence now exists under `docs/release/evidence/license-sources/clearurls/`. | Current pinned rules are accepted for this release-notice pass if the final notice surface includes LGPL-3.0 text, the source pin, and source-offer/source-link details. |
| Nunito Sans | Inter Galactic and Commet ship identical TTF files; mirrored release-ready evidence now exists under `docs/release/evidence/license-sources/nunito/`. | Include the local OFL/source evidence in the generated notices before closing. |
| Emojibase data | REVIEW removed the stale Commet-era `readme.md` and regenerated the current files from `emojibase-data@17.0.0`: `package/en/data.json` and `package/en/shortcodes/emojibase.json`. Exact package tarball, gitHead, integrity, generation command, and shipped-file hashes are recorded in `intergalactic/assets/emoji_data/SOURCE.md` and `docs/release/evidence/license-sources/emojibase/SOURCE.md`. | Accepted for this release-notice pass with the MIT notice, source-project link, package evidence, and shipped-file hashes. |
| TwemojiCOLR | Local README points to `12Me21/twemoji-COLR`; mirrored Twemoji-derived license/source evidence now exists under `docs/release/evidence/license-sources/twemoji-colr/`. | Accepted for this release-notice pass; include TwemojiCOLR/Twemoji attribution, applicable license links, change indication where applicable, and Noto Color Emoji OFL notice in the generated notices. |
| Login shader | The active pubspec-listed login shader is project-authored `constellation.frag`, wrapped by `ConstellationBackground`. | Current shader material is not a third-party blocker. Re-audit if imported shader material is added later. |

### Native And Platform Notice Evidence

- iOS: `intergalactic/ios/Podfile.lock` lists 31 pods. Runner and Broadcast
  Extension CocoaPods acknowledgement markdown/plist files are now synced under
  `intergalactic/ios/Pods/Target Support Files/`, direct pod license files
  exist for DKImagePickerController, DKPhotoGallery, SDWebImage, SwiftyGif, and
  WebRTC-SDK, and the JSON pod rows now point at those sources. REVIEW accepted
  these iOS notice sources for the inventory on 2026-06-13. Final exposure of
  the iOS text remains part of the aggregate app About/release package notice
  surface gate.
- Android: `intergalactic/android/app/build.gradle` ships AndroidX Biometric
  `1.1.0` and `desugar_jdk_libs` `2.1.5`, and Flutter plugins may add more
  Android artifacts to the final release runtime classpath. The Android release
  build path captures Gradle dependency reports plus Maven POM license metadata
  under `docs/release/evidence/android-gradle/<version>/` for the shipped APK.
  The current JSON references the generated `0.7.4+985` evidence for AndroidX
  Biometric and `desugar_jdk_libs`.
- Android FCM / Firebase: FCM builds temporarily enable `firebase_core`,
  `firebase_messaging`, and the Google Services Gradle plugin, then restore the
  shared checkout to the non-Google dependency state. The release build path
  captures Firebase/FlutterFire package notice evidence under
  `docs/release/evidence/android-fcm/<version>/` for FCM release artifacts.
- Patched WebRTC: generated notice evidence now exists under
  `docs/release/evidence/webrtc/` for target `//libwebrtc:libwebrtc` and
  shipped `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip` sha256
  `f9dc095f1c1d06704598a3125771b926ff123c563ad0a13d8fab4acf600eb1fc`.
  `LICENSE.md` includes WebRTC and mapped third-party dependency sections,
  including `rnnoise`; `NOTICE` preserves the source checkout notice text; and
  `manifest.json` records the build graph, generator source, hashes, and the
  local GN/toolchain fallback used to avoid mutating the WebRTC checkout.
- FFmpeg: the static BtbN `win64-lgpl` `ffmpeg.exe` / `ffprobe.exe` pair is
  staged locally under `intergalactic/windows/third_party/ffmpeg/bin/`, ignored
  by git, and documented under `docs/release/evidence/ffmpeg/`. The manifest
  records the retained archive URL, FFmpeg source commit, LGPLv3 license text,
  archive hash, binary hashes, and `-version` configure output. Release CMake
  packaging now copies the pair to `tools/ffmpeg/`; rebuilt story-export smoke
  currently fails with `video could not be recorded.` and is deferred to the
  next release rather than reopening current license/provenance evidence.
- RNNoise: local `UPSTREAM.md` and `COPYING` identify the vendored source/model
  and BSD-style notice, and the generated WebRTC bundle includes the `rnnoise`
  dependency notice for the patched Windows artifact. Current aggregate notice
  exposure is accepted for this release scope.

Primary-source URLs checked for this follow-up:

- `https://raw.githubusercontent.com/google/fonts/main/ofl/nunitosans/OFL.txt`
- `https://github.com/googlefonts/nunito`
- `https://github.com/milesj/emojibase`
- `https://raw.githubusercontent.com/milesj/emojibase/master/LICENSE`
- `https://github.com/ClearURLs/Rules`
- `https://raw.githubusercontent.com/ClearURLs/Rules/master/LICENSE`
- `https://github.com/flutter/flutter/blob/master/LICENSE`
- `https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/8.11.1/gradle-8.11.1.pom`
- `https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.1.10/kotlin-gradle-plugin-2.1.10.pom`
- `https://dl.google.com/dl/android/maven2/androidx/biometric/biometric/1.1.0/biometric-1.1.0.pom`
- `https://dl.google.com/dl/android/maven2/com/android/tools/desugar_jdk_libs/2.1.5/desugar_jdk_libs-2.1.5.pom`
- `https://raw.githubusercontent.com/google/desugar_jdk_libs/master/LICENSE`
- `https://raw.githubusercontent.com/JetBrains/kotlin/v2.1.10/license/LICENSE.txt`
- `https://github.com/12Me21/twemoji-COLR`
- `https://github.com/commetchat/commet`
- `https://ffmpeg.org/download.html`
- `https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-06-13-13-31`
- `https://github.com/FFmpeg/FFmpeg/commit/83e8541aa601935a610b1b8958d56e8d0331318b`

## FFmpeg Desktop Story Video Exporter

Windows desktop story-video trim export bundles a separate FFmpeg tool
pair:

- `ffmpeg.exe`
- `ffprobe.exe`

Release decision: use an LGPL-only FFmpeg build, invoke the tools through
subprocess execution, and avoid GPL/nonfree configure options or GPL-only
encoders such as `libx264`. REVIEW staged the tools under
`intergalactic/windows/third_party/ffmpeg/bin/` on 2026-06-13 from BtbN's
static `win64-lgpl` archive
`ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip`. The Windows Release CMake
install step copies them into `tools/ffmpeg/` beside `InterGalactic.exe`.

Source link: `https://ffmpeg.org/download.html`

Evidence: `docs/release/evidence/ffmpeg/manifest.json`,
`ffmpeg-version.txt`, `ffprobe-version.txt`, and `LICENSE-LGPL-3.0.txt`.
The accepted tool version is `n8.1.1-13-g83e8541aa6-20260613`; source revision
`83e8541aa601935a610b1b8958d56e8d0331318b`; archive SHA-256
`6C1C443C762A8D8AD9C9303AF26E2144DC711B0E7277E1B03FD72CDF2DEAA9DB`;
`ffmpeg.exe` SHA-256
`C5C6E92D80884470A4D09C80A801989757DB1E80837E5018B636AF76DD826FEC`; and
`ffprobe.exe` SHA-256
`134B9BC17D0FE3B1F81ECA108615356F4C304C58C7750CE85592E8CFDBB3F523`.
The captured configuration has no `--enable-gpl` or `--enable-nonfree`, has
`--enable-version3`, and explicitly disables `libx264`, `libx265`, `libxavs2`,
and `libxvid`. No Inter Galactic local FFmpeg patches were applied.

## Release Evidence Follow-Up

The following areas are not pre-publish blockers for the current
`0.7.4+985` rollout, but should remain visible for future release work:

- Re-run story recording/trim export from the bundled `tools/ffmpeg/` path
  before the next release that depends on desktop story recording/export. The
  current rebuilt smoke failed with `video could not be recorded.` and the
  release owner accepted deferring that runtime validation.
- Re-run or review the inventory if dependency state, release SDK, FCM package
  state, bundled assets, FFmpeg binaries, or notice-routing surfaces change.

## Release Gate Interpretation

The generated notice inventory, app/release evidence mirror, hosted/public
notice path, and in-app About/Settings access path are accepted for the current
release scope. This does not replace counsel/legal review and should be
reopened if any shipped dependency, asset, or notice surface changes.
