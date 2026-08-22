# Asset Provenance

This recipient-facing summary identifies bundled assets, their source, and
their disclosure route. Per-asset collection evidence (source routes, licence
texts, and hashes) is tracked in this repository under
`docs/release/evidence/license-sources/`; the rows below name the path holding
it wherever that evidence has been collected.

## Current scope

The last distributed app release is `0.8.0+993`. A later package remains a
candidate until its contents, hashes, and notice surface are measured.
The native DeepFilterNet Windows runtime is selected for the Windows package;
the optional Hush archive is included only when its CMake condition is met.
OpenVINO model files are not counted as bundled until their pinned model card
and licence texts are captured and a candidate confirms inclusion.

## Asset inventory

| Asset family | Conveyed path or scope | Source and disclosure route | Current state |
| --- | --- | --- | --- |
| Inter Galactic icon and notification icons | `intergalactic/assets/images/app_icon/**`; `notification_companion/**` | Project-created artwork; no font file is bundled. | Included. Reassess if artwork or embedded-font scope changes. |
| Roboto, Jellee, JetBrains Mono, Nunito Sans, and emoji fonts | `intergalactic/assets/font/**`; applicable Tiamat assets | Local Apache-2.0 or OFL text; app evidence under `docs/release/evidence/license-sources/`. | Included with the applicable notice route. |
| CameraX libyuv notice | `intergalactic/assets/licenses/libyuv-BSD-3-Clause.txt` | Camera Core 1.6.0 image-processing JNI limb; evidence at `docs/release/evidence/license-sources/android-native-payloads/CAMERAX-IMAGE-PROCESSING-LIBYUV-1.6.0.md`. | Attached in-app; final Android candidate verification pending. |
| Sound and ringtone assets | `intergalactic/assets/sound/**`; Android raw copies | Original Inter Galactic sound pack by Renzo Mayo / Renzo!; evidence at `docs/release/evidence/license-sources/renzo-sounds/SOURCE.md`. | Included with creator credit where credits are displayed. |
| DeepFilterNet native runtime and model | `df.dll`; `DeepFilterNet3_onnx.tar.gz` | DeepFilterNet; MIT and Apache-2.0 texts and hashes at `docs/release/evidence/license-sources/deepfilternet-native/SOURCE.md`. | Selected for Windows; final package, notice, source-archive, and local-only verification pending. |
| Hush model archive | `advanced_dfnet16k_model_best_onnx.tar.gz` when present | Hush Apache-2.0 evidence at `docs/release/evidence/license-sources/hush/`. | Optional Windows support layer; final candidate verification pending. |
| DeepFilterNet OpenVINO models | Not counted as bundled. | Upstream location only, with no revision pinned: `https://huggingface.co/Intel/deepfilternet-openvino`. | Model card and licence texts must be captured, and an immutable upstream revision plus file hashes recorded, before any package includes these files. |
| Placeholder avatars and photos | `intergalactic/assets/images/placeholders/**` | Commet-derived avatars and Pexels photos; Pexels restrictions continue to apply. | Included; exact source URLs remain a provenance improvement. |
| Fluent emoji particles and confetti | `intergalactic/assets/images/effects/particles/**` | Animated Fluent Emojis MIT evidence; Commet AGPL provenance for `confetti.webp`. | Included with the corresponding notice and source route. |
| Emoji metadata and URL rules | `assets/emoji_data/**`; `assets/data/**` | Emojibase MIT and ClearURLs LGPL evidence under `docs/release/evidence/license-sources/`. | Included with the applicable notice and source route. |
| JS, vodozemac, and store-image placeholders | Listed asset directories | No distributable third-party asset is present in the empty directories; copied store images were removed. | Not bundled. |

## Recipient-facing limitations

- A final candidate must be remeasured whenever bundled asset bytes, runtime
  selection, notice routing, or release SDK inputs change.
- Do not include nested Git data, caches, sample WAV files, or unselected model
  files in a release package.
- Inherited material is not sufficient provenance by itself. Retained Commet
  material follows the AGPL notice and source route recorded for that material.
- This document records provenance and disclosure routes; it does not make a
  legal-sufficiency or publication assertion.
