# Hush Runtime Model Evidence

Status: EVIDENCE COLLECTED; PACKAGE GATED

Reviewed by AUDIO with S&C read-only support on 2026-07-03 for the optional
post-DeepFilterNet Hush support layer in the Windows noise-suppression plugin.
This file records engineering license/provenance evidence. It is not legal
advice and does not close the final release package, source archive, notice
surface, privacy, runtime download, or audio upload gates.

## Component

- Component: Hush speech enhancement ONNX model archive.
- Current app source folder:
  `plugins/intergalactic_noise_suppression/third_party/hush/`.
- Runtime file eligible for the Windows plugin package when present:
  `onnx/advanced_dfnet16k_model_best_onnx.tar.gz`.
- Intended use: optional local support layer after Enhanced DeepFilterNet for
  background voice/speaker-bleed experiments.
- Source URL: `https://huggingface.co/weya-ai/hush`.
- Source commit: `a55d932cbf6344d284ac985f21e7f6e5bc4d38a5`.
- Upstream project URL: `https://github.com/pulp-vision/Hush`.

## License Evidence

The mirrored model card/config identify Hush as Apache-2.0, and the local
source checkout includes Apache-2.0 license text.

- `docs/release/evidence/license-sources/hush/MODEL_CARD.md`
- `docs/release/evidence/license-sources/hush/LICENSE-APACHE-2.0.txt`
- `docs/release/evidence/license-sources/hush/config.json`

## Runtime Inventory

| File | Package role | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `plugins/intergalactic_noise_suppression/third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz` | Optional runtime model archive loaded by the Hush support layer | 8558968 | `45632CCAA82B71BB743D6CAA7C78E983FE2F2790A3AF7F6EC48E6ED7BA085DF6` |

The reviewed local source folder also contains a checkpoint and demo WAV files,
but those are not required for the app runtime and should not ship by default.
The app integration does not add Weya NC binaries.

## Package Guidance

- Package only the ONNX runtime archive above plus required notice/license text
  unless a later release design changes the runtime.
- Exclude nested `.git`, LFS/cache files, demo WAV samples, and Weya NC
  binaries by default.
- Final package/source proof must identify whether the Hush ONNX tarball or
  extracted runtime graph files ship.
- Re-open S&C if public distribution, store review, legal review, Weya binaries,
  runtime model downloads, audio uploads, or stricter trained-weight review
  apply.

## Privacy Boundary

The accepted implementation posture is local plugin processing with no runtime
model download and no audio upload path. Any runtime download or remote audio
processing path needs separate privacy and release review.
