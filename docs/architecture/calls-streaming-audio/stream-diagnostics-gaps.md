# Stream Diagnostics Gaps

Status: Historical diagnostic gap snapshot
Owner: EXPERIMENTAL
Date: 2026-05-01

Use this file as May 2026 history. Current stream-test schema and classifier
requirements live in `stream-diagnostic-contract.md` and
`stream-bottleneck-classification.md`.

## Summary

Inter Galactic stream diagnostics now separate the main failure classes for
gameplay streaming:

- capture/source problems
- encoder CPU/GPU problems
- network loss/congestion problems
- TURN/direct transport problems
- receiver decode/render problems

The diagnostics are still developer-only and are collected from the existing
LiveKit / flutter_webrtc WebRTC stats path. No broad stream transport refactor
was added.

## Added Or Verified

### Capture And Requested Profile

- Requested screen-share profile is shown separately from actual sender stats:
  requested resolution, FPS, and bitrate come from the active
  `ScreenShareProfileConfig`.
- Raw WebRTC `media-source` / `track` reports are parsed when exposed:
  `capture_fps`, `framesCaptured`, and pre-encode dropped frames.
- Actual sender resolution/FPS/bitrate still comes from outbound RTP stats.

### Encoder / CPU / GPU

- Sender diagnostics now include encode FPS, encoded frame count, encoder-drop
  count when exposed, average encode time derived from
  `totalEncodeTime / framesEncoded` deltas, codec, encoder implementation, and
  quality limitation reason.
- Hardware encode status is a heuristic derived from `encoderImplementation`.
  Known software strings such as `libvpx` and `OpenH264` are reported as
  software. Hardware-like strings such as Media Foundation, D3D11/DXVA, NVENC,
  QSV, AMF, VideoToolbox, VAAPI, and V4L2 are reported as likely hardware.
- The runtime encoder string remains the source of truth. A requested H.264
  hardware-first profile can still fall back to software if libwebrtc or the
  installed GPU stack does not expose a hardware encoder.

### Bitrate And Network

- Sender diagnostics now show target bitrate, actual bitrate, available
  outgoing bitrate from the selected ICE candidate pair when exposed, and
  retransmit bitrate derived from `retransmittedBytesSent` deltas.
- Packet counters now include packets sent/received/lost plus NACK, PLI, and
  FIR counts.
- RTT, jitter, packet loss, retransmitted packets, and quality limitation reason
  remain visible.

### TURN / Direct Transport

- Selected ICE route diagnostics include local and remote candidate type
  (`host`, `srflx`, `relay` when exposed), protocol (`udp` or `tcp` when
  exposed), and address class (`private`, `public`, `mdns`, `loopback`, or
  `unknown`).
- Available incoming/outgoing bitrate from the selected candidate pair is
  included when WebRTC emits it.

### Receiver Decode And Render

- Receiver diagnostics now include decode FPS, render FPS when exposed,
  frames received/decoded/rendered, dropped decode frames, average decode time
  derived from `totalDecodeTime / framesDecoded` deltas, decoder implementation,
  freeze count, pause count, and total freeze/pause duration when exposed.
- Jitter-buffer delay remains a per-frame average derived from cumulative
  `jitterBufferDelay` and `jitterBufferEmittedCount` deltas. The overlay does
  not display the cumulative counter as a current delay value.

### Logging

- Developer stream stats now emit a compact `LiveKit stream diagnostics` log
  every ten seconds while enabled, in addition to the copyable in-call overlay.
- The log includes profile, adaptive stream, dynacast, simulcast, fallback
  state, ICE route, requested versus actual media settings, FPS breakdown,
  bitrate breakdown, packet counters, frame counters, timing, codec, encoder or
  decoder string, hardware heuristic, and quality limitation reason.

## Not Exposed Reliably

- `capture_fps` and `framesCaptured` depend on WebRTC emitting `media-source`
  or `track` reports on the current platform. If those reports are absent, the
  field stays blank rather than being inferred from send FPS.
- `framesDroppedBeforeEncode` and `framesDroppedByEncoder` are optional WebRTC
  counters. Some Windows builds may omit one or both.
- `availableOutgoingBitrate` and `availableIncomingBitrate` are candidate-pair
  stats. They are transport-level estimates, not per-track bandwidth limits.
- Active simulcast layer from the SFU is not directly exposed as a single
  authoritative value in the current LiveKit Flutter API. Sender layer is shown
  by RTP `rid`; receiver selection is shown by the app's requested receive
  priority.
- Hardware encode detection is not a formal WebRTC boolean in this stack. It is
  a readable heuristic over `encoderImplementation`.
- Renderer-only frame presentation can be partially visible through
  `framesRendered` or track stats when WebRTC emits them, but Flutter's video
  widget does not expose a separate renderer frame-timing API.

## How To Interpret Logs

### Capture Problem

Likely capture/source issue when:

- `capture_fps` is lower than the requested FPS while encode/send FPS are not
  independently limited.
- `framesCaptured` stops increasing.
- pre-encode dropped frames increase.

### Encoder / CPU / GPU Problem

Likely sender encode issue when:

- `capture_fps` is healthy but `encode_fps` or `send_fps` is low.
- average `encode_ms` is high for the target FPS.
- `limited:cpu` or `limited:other` appears.
- encoder drops increase.
- `engine=libvpx` or another software encoder appears for a Windows gameplay
  share that should be H.264 hardware-first.

### Network Problem

Likely network/congestion issue when:

- actual bitrate stays far below target.
- available outgoing bitrate is low.
- retransmit bitrate, packet loss, NACK, PLI, or FIR counts climb.
- `limited:bandwidth` appears.
- RTT and jitter rise with packet loss.

### TURN / Direct Transport Problem

Likely relay/transport issue when:

- ICE route shows `relay` instead of `host` or `srflx`.
- protocol is `tcp` instead of `udp`.
- available outgoing bitrate is low despite healthy local capture and encode
  timing.

### Receiver Decode / Render Problem

Likely receiver issue when:

- sender stats look healthy but receiver decode FPS or render FPS is low.
- `framesReceived` rises while `framesDecoded` or `framesRendered` lags.
- dropped decode frames, decode time, freezes, or jitter-buffer average climb.
- decoder implementation suggests software decode on a weak device.
