# DeepFilterNet Native Runtime Evidence

Status: EVIDENCE COLLECTED; PACKAGE GATED

Reviewed by AUDIO on 2026-07-01 for the Windows developer-only Enhanced
DeepFilterNet noise-suppression plugin path. S&C/REVIEW release acceptance is
still required before production shipping.

This file records engineering license/provenance evidence for the current
native Windows DeepFilterNet package used by the app dev build. It is not legal
advice and does not close the final release package, notice-surface, source
archive, or privacy gates.

## Component

- Component: DeepFilterNet native C API runtime and DeepFilterNet3 ONNX model
  archive.
- Current app source folder:
  `plugins/intergalactic_noise_suppression/third_party/deepfilternet/`.
- Runtime files currently bundled by the Windows plugin CMake path:
  `df.dll` and `DeepFilterNet3_onnx.tar.gz`.
- Build/link-only input: `df.dll.lib`.
- Intended use: local Windows plugin noise suppression for the developer-only
  Enhanced DeepFilterNet live callback path.
- Upstream project: `https://github.com/Rikorose/DeepFilterNet`.

The earlier DeepFilterNet OpenVINO evidence packet is separate and does not
cover this native C API runtime package.

## License Evidence

The current checked-in native package carries these license files:

- `plugins/intergalactic_noise_suppression/third_party/deepfilternet/LICENSE-MIT`
- `plugins/intergalactic_noise_suppression/third_party/deepfilternet/LICENSE-APACHE`

Treat those files as the release evidence for this package until S&C/REVIEW
accepts a final source archive and notice bundle.

## Runtime Inventory

| File | Package role | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `plugins/intergalactic_noise_suppression/third_party/deepfilternet/windows/x64/df.dll` | Runtime binary bundled by current Windows plugin CMake path | 16570880 | `48D2DAE7451626CAF98E9D1B90B7AAF2E24DF1319D4820F33449655D4678C0C6` |
| `plugins/intergalactic_noise_suppression/third_party/deepfilternet/models/DeepFilterNet3_onnx.tar.gz` | Runtime model archive loaded by the native DeepFilterNet path | 7983136 | `C94D91F70911001C946E0FABB4AA9ADC37045F45A03B56008CB0C8244CB63616` |
| `plugins/intergalactic_noise_suppression/third_party/deepfilternet/windows/x64/df.dll.lib` | Build/link input, not a runtime package file under current CMake bundling | 3268 | `098DC8DD9D18F52EBE2BD4E0976BFC4A8CD47E30CD11A2FCC89346C873D83D75` |
| `plugins/intergalactic_noise_suppression/third_party/deepfilternet/LICENSE-MIT` | License evidence | 1102 | `D38482491663EE5C55BB9FD4A7A193F1652157BA85A4BE5D4E8A50649B2CBC3D` |
| `plugins/intergalactic_noise_suppression/third_party/deepfilternet/LICENSE-APACHE` | License evidence | 11038 | `2D71D2472AE6446E986CC9AD3EC6182B91868C639734F838AA1D03888838EF56` |

## Package Guidance

- Package only the required runtime files plus notice/license text unless a
  later release design changes the runtime.
- Under the current Windows plugin CMake path, runtime package proof should
  account for `df.dll` and `DeepFilterNet3_onnx.tar.gz`; `df.dll.lib` is a
  link input and should not be counted as a runtime package file.
- Do not rely on the Intel DeepFilterNet OpenVINO evidence packet for this
  native runtime package.
- Re-open S&C if the source, model archive, runtime binary, packaging path,
  production release scope, model downloads, audio upload paths, Hush/Weya
  binaries, or notice surface changes.

## Privacy Boundary

The current implementation evidence points to local Windows plugin processing
with a bundled runtime/model archive. No model download or audio upload path is
accepted by this evidence packet. Any runtime download or remote audio
processing path needs separate privacy and release review.
