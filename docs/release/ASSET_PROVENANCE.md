# Asset Provenance

Status: PROVISIONAL FOR CURRENT RELEASE SCOPE; NATIVE DEEPFILTERNET AND OPTIONAL HUSH SUPPORT LAYER SELECTED FOR 0.8.0 WINDOWS PACKAGE, WITH FINAL PACKAGE PROOF PENDING

Inventory date: 2026-06-13
Updated: 2026-06-27 for the original Inter Galactic sound-pack replacement.
Updated: 2026-06-30 for pending DeepFilterNet OpenVINO and Hush model evidence.
Updated: 2026-07-01 for native DeepFilterNet runtime/model evidence.
Updated: 2026-07-02 for owner confirmation that native DeepFilterNet is
selected for the current Windows package.
Updated: 2026-07-03 for the optional Windows Hush support-layer package path.

This file records bundled or release-adjacent asset provenance for the current
Inter Galactic `0.8.0+991` release-evidence inventory. It is evidence for
S&C/release review, not legal sign-off. Final release acceptance remains pending
until the package/source archive and notice/access proof are captured for this
release scope. Re-open the gate if asset bytes, source, bundled dependencies,
notice routing, or release SDK state change.

Native DeepFilterNet runtime/model artifacts and the optional Hush support-layer
ONNX archive are selected for the current `0.8.0+991` Windows package, while
DeepFilterNet OpenVINO remains package-gated unless separately selected. None
of these model/runtime artifacts were shipped in the previous `0.7.4+985`
package.
Final `0.8.0+991` package/source archive and notice-surface proof remains
required before release closeout.

## Summary

| Asset family | Paths | Source or creator | License evidence | Release status | Notes |
| --- | --- | --- | --- | --- | --- |
| Inter Galactic app icon/logo | `intergalactic/assets/images/app_icon/**`; generated platform icon variants | Project owner | The Inter Galactic icon artwork was created for this project. It utilizes Lucida Bright Demibold Italic, a Windows supplied font available on the creation machine; Microsoft Learn lists Lucida Bright Demibold Italic in the Lucida Bright family and the Microsoft Windows font FAQ covers rendered logos/graphic files separately from font-file redistribution. No Lucida font file is bundled. | OK | Keep this note with any future public asset provenance export. Re-open if icon/logo source bytes change or a Lucida font file is embedded, redistributed, converted, or bundled. |
| Notification companion icons | `intergalactic/assets/images/notification_companion/**` | Derived from Inter Galactic icon family | Covered by owner-created app icon evidence if generated from the same source | OK | Reconfirm if future variants use external artwork. |
| Roboto fonts | `intergalactic/assets/font/roboto/**`; Tiamat RobotoCustom files | Google/Roboto | Local Apache-2.0 text exists under app and Tiamat font folders | OK | Include notice text in generated bundle. |
| Jellee font | `intergalactic/assets/font/jellee/**` | Jellee font project | Local OFL text exists as `Jellee-OFL.txt` | OK | Include OFL notice. |
| JetBrains Mono | `intergalactic/assets/font/code/**` | JetBrains Mono project | Local OFL text exists as `OFL.txt` | OK | Include OFL notice. |
| Nunito Sans | `intergalactic/assets/font/nunito/**` | Nunito Sans font family | Mirrored app-repo evidence exists in `docs/release/evidence/license-sources/nunito/`, including `SOURCE.md` | OK WITH NOTICE SURFACE | Release-ready evidence normalized by REVIEW on 2026-06-14. Include OFL/source evidence in the generated notice surface. |
| App emoji font | `intergalactic/assets/font/emoji-font/**` | TwemojiCOLR source noted in README | Mirrored Twemoji-derived license/source evidence exists in `docs/release/evidence/license-sources/twemoji-colr/`, including `SOURCE.md` | OK WITH NOTICE SURFACE | REVIEW accepted attribution/source evidence on 2026-06-14. Include TwemojiCOLR/Twemoji attribution, applicable license links, change indication where applicable, and Noto Color Emoji OFL notice in the final app/release notice surface. |
| Tiamat emoji font | `tiamat/assets/font/emoji-font/**` | Noto Color Emoji | Local OFL text exists | OK | Include notice if Tiamat ships this font. |
| Sound and ringtone assets | `intergalactic/assets/sound/**`; Android raw sound copies | Original Inter Galactic sound pack by Renzo Mayo aka Renzo! | `docs/release/evidence/license-sources/renzo-sounds/SOURCE.md` records creator credit, source masters, shipped mappings, hashes, and Android WAV regeneration evidence | OK WITH NOTICE SURFACE | Replaced on 2026-06-27. Include Renzo Mayo / Renzo! credit and creator link where public credits are surfaced. |
| DeepFilterNet OpenVINO model artifacts | `tools/hugging-face-models/deepfilternet-openvino/**`; final app package path pending AUDIO/REVIEW packaging | Intel/Hugging Face model card for OpenVINO IRs converted from DeepFilterNet2/3 ONNX packages | `docs/release/evidence/license-sources/deepfilternet-openvino/SOURCE.md`; `LICENSE-MIT.txt`; `LICENSE-APACHE-2.0.txt`; `MODEL_CARD.md` | EVIDENCE COLLECTED; PACKAGE GATED | Implementation may continue through plugin noise suppression. Final release package must include only required runtime files and notices; OpenVINO runtime binaries/plugins need separate review if bundled. |
| DeepFilterNet native runtime/model artifacts | `plugins/intergalactic_noise_suppression/third_party/deepfilternet/windows/x64/df.dll`; `plugins/intergalactic_noise_suppression/third_party/deepfilternet/models/DeepFilterNet3_onnx.tar.gz`; final app package proof pending AUDIO/REVIEW packaging | DeepFilterNet native C API runtime and DeepFilterNet3 ONNX archive from the DeepFilterNet project | `docs/release/evidence/license-sources/deepfilternet-native/SOURCE.md`; checked-in `LICENSE-MIT`; checked-in `LICENSE-APACHE`; SHA-256 hashes for `df.dll`, `DeepFilterNet3_onnx.tar.gz`, and link-only `df.dll.lib` are recorded in `docs/release/LICENSE_AUDIT_REPORT.md` | OWNER SELECTED; PACKAGE PROOF PENDING | Owner selected native DeepFilterNet for the current Windows package on 2026-07-02. Current Windows CMake bundling of `df.dll` plus `DeepFilterNet3_onnx.tar.gz` is intentional; `df.dll.lib` is link-only under current packaging. S&C/REVIEW must verify final package/source archive, notices, and local-only privacy posture before production shipping. |
| Hush model artifacts | `plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz`; source evidence under `tools/hugging-face-models/hush/**` | Hush model card/config/license from local Hugging Face checkout; built on DeepFilterNet3 | `docs/release/evidence/license-sources/hush/SOURCE.md`; `LICENSE-APACHE-2.0.txt`; `MODEL_CARD.md`; `DATASETS.md`; `config.json` | SELECTED OPTIONAL SUPPORT LAYER; PACKAGE PROOF PENDING | Owner accepted continuing implementation on 2026-06-30 with dataset-provenance note retained. On 2026-07-03, AUDIO added the off-by-default Windows Hush support layer and current CMake conditionally bundles the ONNX tarball when present. Final release package/source archive proof must exclude demo WAVs, nested `.git`, LFS/cache files, and Weya NC binaries; re-open if downloads, uploads, extracted graph files, or stricter review apply. |
| Placeholder avatars | `intergalactic/assets/images/placeholders/avatar*.jpg` | Commet-created per user confirmation on 2026-06-13 | User confirmation | OK WITH OWNER CONFIRMATION | Keep this note with any future public asset provenance export. |
| Placeholder photos | `intergalactic/assets/images/placeholders/photos/pexels-*.jpg` | Pexels-named files | Pexels license page reviewed on 2026-06-13: free use, attribution not required, modifications allowed; restrictions still apply | OK WITH PEXELS LICENSE EVIDENCE | Keep the Pexels license URL with release evidence; exact download URLs remain nice-to-have, not a release blocker for this pass. |
| Tiamat generic placeholders | `tiamat/assets/images/placeholder/generic/**` | Kenney Prototype Textures | Local CC0 license file exists | OK | Keep local license file with source. |
| Fluent emoji particles | `intergalactic/assets/images/effects/particles/fluent-emoji-*` | Animated Fluent Emojis repository | Local source note says MIT as of 2025-02-16; particle files match `references/commet-main` by SHA-256 | OK WITH NOTICE SURFACE | REVIEW accepted MIT attribution evidence on 2026-06-13. Include Animated Fluent Emojis source attribution and MIT notice in the final app/release notice surface. |
| Confetti particle image | `intergalactic/assets/images/effects/particles/confetti.webp` | Commet repository asset; Element Web supports the same `nic.custom.confetti` effect type through canvas-generated particles | `docs/release/evidence/license-sources/commet/commetassets.md` records first-observed Commet commit `3d39f25`, AGPL repository-asset inheritance, unknown upstream original creator, and 2026-06-14 user/owner acceptance | OK WITH NOTICE SURFACE | Release-ready evidence for this release pass. Element confirms interoperability only; Commet evidence covers release provenance. Include Commet AGPL/fork/source notices. |
| Theme/config/l10n JSON | `intergalactic/assets/themes/**`; `intergalactic/assets/config/**`; `intergalactic/assets/l10n/**` | Project/app data and localization data | No third-party media license issue identified in static pass | OK WITH REVIEW | Recheck if imported translations or theme imagery are added. |
| Emoji metadata and shortcodes | `intergalactic/assets/emoji_data/**` | `emojibase-data@17.0.0` | `intergalactic/assets/emoji_data/SOURCE.md`; `docs/release/evidence/license-sources/emojibase/SOURCE.md`; MIT license evidence in `docs/release/evidence/license-sources/emojibase/LICENSE.txt` | OK WITH NOTICE SURFACE | REVIEW regenerated `data.json` from `package/en/data.json` and `shortcodes/en.json` from `package/en/shortcodes/emojibase.json` on 2026-06-13, removed the stale Commet-era readme, and recorded package tarball, gitHead, integrity, generation command, project links, and shipped file hashes. Include Emojibase MIT attribution/source details in the final notice surface. |
| URL/data rules | `intergalactic/assets/data/clearurls.json`; `sources.txt`; `url_handlers.json` | ClearURLs Rules source pin for `clearurls.json` | Source pin and mirrored LGPL/source evidence exist in `docs/release/evidence/license-sources/clearurls/`, including `SOURCE.md` | OK WITH SOURCE OFFER | REVIEW accepted current `ClearURLs/Rules @ 9317c06` handling on 2026-06-14. Include LGPL-3.0 notice and source-offer/source-link details in the final app/release notice surface. |
| JS package directory | `intergalactic/assets/js/package/**` | Empty placeholder directory in static pass | Only `.gitkeep` found | OK | Re-audit if JS/WASM files are added. |
| Vodozemac asset directory | `intergalactic/assets/vodozemac/**` | Empty placeholder directory in static pass | Only `.gitkeep` found | OK | Re-audit if crypto/WASM assets are added. |
| App shaders | `intergalactic/assets/shader/**`; Tiamat shader assets | Inter Galactic-authored active login shader; Tiamat local shader assets | Active pubspec-listed login shader is `constellation.frag` | OK WITH REVIEW | Re-audit if imported shader material is added later. |
| Fastlane/store images | `intergalactic/fastlane/metadata/**` and store screenshots/images if present | Copied Commet store-page images | Removed from the repo on 2026-06-13 by user direction | REMOVED | Future store images should be current Inter Galactic-owned/listing material before store submission. |

## Remaining File/Use Inventory

### Sounds

On 2026-06-27, REVIEW replaced the shipped sound/ringtone assets with an
original Inter Galactic sound pack designed specifically for the app by Renzo
Mayo aka Renzo!. Evidence is recorded in
`docs/release/evidence/license-sources/renzo-sounds/SOURCE.md`, including source
masters under `references/inter-galactic-sounds/`, shipped OGG mappings,
SHA-256 hashes, and Android raw WAV regeneration evidence. The prior Commet
sound/ringtone evidence remains in
`docs/release/evidence/license-sources/commet/commetassets.md` only as
superseded historical release evidence.

| File | Use |
| --- | --- |
| `intergalactic/assets/sound/message.ogg` | Default app and room notification sound via `CustomSoundManager`; used by desktop notification playback paths. |
| `intergalactic/assets/sound/ringtone_in.ogg` | Default incoming-call ringtone via `CustomSoundManager`. |
| `intergalactic/assets/sound/ringtone_out.ogg` | Default outgoing-call ringtone via `CustomSoundManager`. |
| `intergalactic/assets/sound/joined_call.ogg` | Played by `CallManager` when joining a call. |
| `intergalactic/assets/sound/left_call.ogg` | Played by `CallManager` when leaving or ending a call. |
| `intergalactic/assets/sound/muted.ogg` | Played by `CallManager` for mute and push-to-talk end feedback. |
| `intergalactic/assets/sound/unmuted.ogg` | Played by `CallManager` for unmute and push-to-talk start feedback. |
| `intergalactic/android/app/src/main/res/raw/message.wav` | Android raw resource for message/story notification channel sound, regenerated from `IG_Message.ogg`. |
| `intergalactic/android/app/src/main/res/raw/ringtone_in.wav` | Android raw resource for incoming-call notification channel sound, regenerated from `IG_Ringtone_In.ogg`. |

### Placeholder Avatars

User confirmation on 2026-06-13: `avatar1.jpg` and `avatar2.jpg` were created
by Commet.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/placeholders/avatar1.jpg` | Sample avatar in text chat, voice room, and calendar room creation previews. |
| `intergalactic/assets/images/placeholders/avatar2.jpg` | Sample avatar in text chat, voice room, and calendar room creation previews. |

### Placeholder Photos

License evidence reviewed on 2026-06-13: the Pexels license page states Pexels
photos and videos are free to use, attribution is not required, and modification
is allowed. The listed Pexels restrictions still apply.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/placeholders/photos/pexels-stijn-dijkstra-1306815-16747816.jpg` | Photo album creator sample grid; demo single-photo event fallback. |
| `intergalactic/assets/images/placeholders/photos/pexels-james-lee-932763-2017111.jpg` | Photo album creator sample grid; demo photo stack root. |
| `intergalactic/assets/images/placeholders/photos/pexels-kostiantyn-35582290.jpg` | Photo album creator sample grid; second demo photo stack item. |
| `intergalactic/assets/images/placeholders/photos/pexels-rdne-8474967.jpg` | Photo album creator sample grid; third demo photo stack item. |
| `intergalactic/assets/images/placeholders/photos/pexels-fr3nks-287229.jpg` | Photo album creator sample grid; demo photo fallback. |
| `intergalactic/assets/images/placeholders/photos/pexels-nivdex-796206.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-mikhail-nilov-8221589.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-krisof-1252873.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-byrahul-2162909.jpg` | Photo album creator sample grid. |

### Confetti

Commet asset provenance evidence reviewed on 2026-06-13 and accepted for this
release evidence gate on 2026-06-14:
`docs/release/evidence/license-sources/commet/commetassets.md` records
`commet/assets/images/effects/particles/confetti.webp` as first observed in
Commet commit `3d39f25` (`implement message effects (#401)`) and inherited as
an upstream Commet AGPL repository asset, with original creator unknown
upstream.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/effects/particles/confetti.webp` | 59-frame 64x64 sprite sheet loaded by `ParticleSystemConfetti` for the `MessageEffectConfetti` message effect. SHA-256 matches `references/commet-main/commet/assets/images/effects/particles/confetti.webp`; Element Web supports `nic.custom.confetti` using generated canvas particles, not this image file. |

### Store Images

Removed on 2026-06-13 by user direction: copied Commet Android Fastlane store
images under `fastlane/metadata/android/{en-US,jp-JP,zh-CN}/images/**`.
Fastlane text metadata remains, but future store listing images must be current
Inter Galactic-owned/listing material before store submission.

### Noise-Suppression Models

S&C collected license/provenance evidence on 2026-06-30 after the owner decided
to continue implementation of model-backed noise suppression through the plugin
path. On 2026-07-02, the owner selected native DeepFilterNet for the current
Windows package. On 2026-07-03, AUDIO added the off-by-default Hush support
layer and the Windows CMake package path conditionally bundles the Hush ONNX
archive when present. These rows still need Release Pipeline or REVIEW final
package/source archive proof before release closeout.

| Model artifact family | Current evidence | Release package requirements |
| --- | --- | --- |
| DeepFilterNet OpenVINO | `docs/release/evidence/license-sources/deepfilternet-openvino/SOURCE.md` with MIT model-card evidence, upstream DeepFilterNet MIT/Apache license files, source URLs, commits, and hashes. | Include only required OpenVINO IR runtime files and notices. Exclude nested `.git`; separately review OpenVINO runtime binaries/plugins if bundled. |
| DeepFilterNet native C API / DeepFilterNet3 ONNX | `docs/release/evidence/license-sources/deepfilternet-native/SOURCE.md` with hashes for `df.dll`, `DeepFilterNet3_onnx.tar.gz`, `df.dll.lib`, and checked-in MIT/Apache license files. Owner-selected for the current Windows package on 2026-07-02. | Include only `df.dll`, `DeepFilterNet3_onnx.tar.gz`, and required notices unless the runtime design changes. Treat `df.dll.lib` as link-only under current CMake bundling. Verify final package/source archive and local-only privacy posture before production shipping. |
| Hush | `docs/release/evidence/license-sources/hush/SOURCE.md` with Apache-2.0 license/config/model-card evidence, dataset-provenance note, owner implementation acceptance, and hashes. Current Windows optional support-layer path is `plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz`. | Include only the selected runtime ONNX archive or documented extracted graph files plus required notices. Exclude sample WAVs, nested `.git`, LFS/cache files, and Weya NC binaries; separately review Weya NC binaries, runtime downloads, audio upload paths, or extracted graph-file package changes if added. |

## Required Follow-Up Evidence

- Current release: user confirmed on 2026-06-16 that the notice/access surface
  is verified, including accepted attribution text for assets marked
  `OK WITH NOTICE SURFACE`.
- Keep the Renzo Mayo / Renzo! creator credit with current sound/ringtone
  release records and public credits.
- Keep the accepted Commet unknown-creator provenance note with retained
  Commet asset release records such as `confetti.webp`, unless counsel requires
  stricter provenance.
- Remove or replace any future assets whose source/license cannot be verified or
  explicitly accepted.
- Re-run the static inventory after any asset replacement.
- Re-run the notice/access-surface check after any change to bundled assets,
  notice routing, dependency state, or release SDK state.
- For model-backed noise suppression, re-run package manifest/source archive
  checks for the selected native DeepFilterNet runtime/model files and the
  optional Hush support-layer archive before release notices are closed.

## Commet And Inherited Assets

Some assets may have been inherited from Commet. Treat inherited status as a
provenance lead, not final evidence by itself. For retained Commet assets such
as `confetti.webp`, cite
`docs/release/evidence/license-sources/commet/commetassets.md` as the accepted
Commet AGPL repository-asset evidence for this release pass. Current
sound/ringtone assets cite
`docs/release/evidence/license-sources/renzo-sounds/SOURCE.md` instead. Future
inherited assets still need their own source/license evidence, replacement, or
explicit release acceptance before closure.
