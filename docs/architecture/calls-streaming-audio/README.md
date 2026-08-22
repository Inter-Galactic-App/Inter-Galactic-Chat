# Calls, Streaming, And Audio Architecture Docs

Status: Folder index and source-of-truth map
Owner: DOCUMENTATION for structure; runtime owners are listed per doc family
Last reviewed: 2026-08-06

Use this folder for durable app architecture around calls, LiveKit/WebRTC
streaming, Windows capture, stream diagnostics, shared-content audio, call
soundboard behavior, and microphone noise suppression.

## Source Of Truth Rules

Use this folder for current contributor-safe streaming guidance.

- Stable architecture belongs in `streaming-pipeline.md`,
  `livekit-gameplay-streaming.md`, and
  `game-capture-backend-architecture.md`.
- Current branch/runtime status belongs in `streaming-guidance-status.md`.
- Stream-test schema/classifier rules belong in
  `stream-diagnostic-contract.md`,
  `stream-receiver-diagnostic-contract.md`, and
  `stream-bottleneck-classification.md`.
- Dated evidence belongs in `stream-optimization-report.md` and its archive
  slices, not in the stable architecture docs.
- Historical milestone and gap docs are preserved under `archive/`, but should
  not be treated as the active implementation source once a stronger current
  doc exists.

## Current Streaming Baseline

Current branch/runtime status lives only in `streaming-guidance-status.md`.
This README intentionally stays a routing index so contributors do not have to
reconcile multiple baseline summaries.

## Doc Map

| Doc | Runtime owner | Why it is separate |
| --- | --- | --- |
| `streaming-pipeline.md` | Shared / DOCUMENTATION structure | Stable end-to-end map for MatrixRTC, LiveKit, direct Matrix calls, shared audio, RNNoise boundaries, and diagnostics. Keep this concise. |
| `livekit-gameplay-streaming.md` | EXPERIMENTAL for streaming behavior | Current LiveKit gameplay streaming defaults, call lifecycle rules, call connection health, screen-share profiles, subscriber policy, and stream-test behavior. |
| `streaming-guidance-status.md` | EXPERIMENTAL | Current implementation-decision summary from the active streaming guidance plan. It is intentionally more volatile than stable architecture docs. |
| `game-capture-backend-architecture.md` | EXPERIMENTAL | D3D11 game-hook backend architecture, developer-mode promotion boundary, backend-neutral contract, and GPU/native capture limitations. |
| `local-stream-pipeline-harness.md` | EXPERIMENTAL | No-LiveKit local harness and isolation gates for DX11 capture, GPU NV12/P010 conversion, and local Media Foundation proof. |
| `game-capture-test-target.md` | EXPERIMENTAL | Synthetic game-capture target details for reproducible local capture validation. |
| `windows-libwebrtc-hardware-encoding.md` | EXPERIMENTAL | Patched Windows libwebrtc, Media Foundation H.264, native diagnostics, and artifact/build expectations. |
| `stream-diagnostic-contract.md` | EXPERIMENTAL | Canonical stream-test field contract for native logs, Dart parsing, JSON, Markdown, and diagnostic coverage. |
| `stream-bottleneck-classification.md` | EXPERIMENTAL | Evidence rules for stream-test bottleneck labels and recommended next actions. Kept separate so classifier behavior can change without rewriting the schema contract. |
| `stream-optimization-report.md` | EXPERIMENTAL runtime / DOCUMENTATION structure | Short current index into the evidence archive. Do not grow it with new long run narratives. |
| `stream-optimization-report/` | EXPERIMENTAL runtime / DOCUMENTATION structure | Dated evidence slices. Separate archive files keep current docs readable while preserving run history. |
| `archive/README.md` | DOCUMENTATION structure | Index for archived milestone, gap, and planning docs that were moved out of the live app architecture surface. |
| `archive/stream-diagnostic-system-audit.md` | EXPERIMENTAL | Snapshot of diagnostic-system architecture gaps from the diagnostics audit. Use the contract/classifier docs for current rules. |
| `archive/stream-diagnostic-completion-report.md` | EXPERIMENTAL | Implementation completion report for the stream diagnostics pass. Kept as a milestone record, not as current routing. |
| `archive/stream-diagnostics-gaps.md` | EXPERIMENTAL | Historical May 2026 gap snapshot. Use current contract/classifier docs before implementing diagnostics. |
| `archive/livekit-streaming-performance-plan.md` | EXPERIMENTAL | Historical performance plan preserved for rationale and comparison with later evidence. |
| `windows-share-session.md` | EXPERIMENTAL for shared-content audio/video boundary | Windows ShareSession architecture for keeping screen/window video, shared-content audio, and microphone audio separate. |
| `voip-soundboard.md` | FEATURES / calls integration | Soundboard Matrix events and local in-call playback. Separate because it is call-adjacent audio playback, not media capture or stream transport. |
| `media-and-plugins.md` | DOCUMENTATION structure; owners by section | Broad media/plugin map. Use only its plugin/RNNoise/shared-audio sections for call/stream work. |
| `RNNOISE_TUNING_BASELINE.md` | AUDIO | Microphone noise-suppression tuning rollback baseline. Separate because it is audio DSP behavior, not gameplay streaming. |
| `rnnoise-native-resampler-plan.md` | AUDIO | Native RNNoise resampler and microphone capture-format plan. Separate from streaming because it only affects mic audio. |

## Maintenance Rules

- Keep current streaming decisions in `streaming-guidance-status.md`.
- Keep stable architecture in `streaming-pipeline.md` and
  `livekit-gameplay-streaming.md`.
- When a workspace/internal document overlaps these app docs, treat the app
  docs as canonical and keep the workspace doc limited to research, code
  anchors, archive routing, or internal rationale.
- Keep schema/parser obligations in `stream-diagnostic-contract.md`.
- Keep bottleneck-label rules in `stream-bottleneck-classification.md`.
- Add new run narratives to the newest dated file under
  `stream-optimization-report/`, or create a new dated slice.
- Route microphone suppression changes to AUDIO-owned RNNoise docs.
- Do not paste raw stream logs, private paths, source titles, PIDs, tokens, or
  Matrix identifiers into app-repo docs.
