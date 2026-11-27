# Inter Galactic Receiver Probe

Status: real external receiver runtime implemented through
`InterGalactic.exe --receiver-probe`; protected IPC, external runner gating,
artifact writing, and decode/render frame-hash outputs are smoke-validated.
Real LiveKit synthetic freshness still needs a live token/room run.

This tool is the dedicated receiver-probe entry point for Receiver Lab. It is
launched by `tools/stream-lab/run_true_receiver_test.ps1` and writes the
receiver-lab output files required by
`docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md`.

## Current Behavior

- Accepts run metadata from the runner.
- Reads the LiveKit URL and subscribe-only JWT from a local named pipe. The
  PowerShell wrapper receives the upstream protected IPC envelope, starts the
  app receiver process, then relays the same raw envelope into an app-owned
  child pipe.
- Refuses token-like command-line arguments.
- Launches the rebuilt Inter Galactic app in isolated receiver-probe mode with
  `--receiver-probe`, bypassing normal single-instance/user app startup.
- Joins LiveKit as a subscribe-only participant, publishes nothing, subscribes
  to the selected screenshare track, and emits redacted receiver-lane
  diagnostics through the same `MatrixLivekitReceiverProbeController` path used
  by the in-process probe.
- In render mode, mounts a small inactive receiver window with `RTCVideoView`
  and requires visible renderer evidence before the render gate can pass.
- Writes redacted JSON, JSONL, and Markdown outputs, including
  `receiver-summary.json`, `receiver-summary.md`, `events.jsonl`,
  `decoded-freshness.json`, and `rendered-freshness.json`.
- Labels external runtime evidence with `in_process=false` and
  `protected_ipc=true`.

`run_true_receiver_test.ps1 -Mode DecodeOnly` and `-Mode Render` now require a
separate probe process to emit receiver-lane `freshness_source=frame_hash_tap`
and `unique_fps >= MinUniqueFps` before reporting
`completed_external_receiver_probe_events`. Render mode also requires
`renderer_attached=true` and `renderer_visible=true`.

## Token Boundary

Do not pass tokens in command-line arguments, environment variables, logs,
Markdown, JSON reports, crash dumps, or shell history. The only supported token
handoff is a protected local IPC envelope sent over the runner-provided control
pipe.

Expected envelope fields:

```json
{
  "sfu_url": "wss://example.invalid",
  "jwt": "<subscribe-only token>",
  "room_id": "!room:example.invalid",
  "publisher_identity": "publisher-livekit-identity",
  "probe_identity": "receiver-probe-livekit-identity",
  "room_hash": "sha256:...",
  "publisher_identity_hash": "sha256:...",
  "receiver_identity_hash": "sha256:...",
  "track_sid_hash": "sha256:...",
  "track_source": "screenshare",
  "expires_at_utc": "2026-06-18T18:30:00Z"
}
```

Raw room, participant, and track identifiers are accepted only for local testing
through the protected IPC envelope and are hashed before any diagnostic file is
written.

## App Runtime Resolution

`InterGalacticReceiverProbe.ps1` resolves the app runtime from:

- explicit `-AppExe`;
- `INTERGALACTIC_RECEIVER_PROBE_APP_EXE`;
- the default Windows debug/release build outputs.

The true receiver runner exposes this through
`tools/stream-lab/run_true_receiver_test.ps1 -ProbeAppExe`.

## Receiver Window Placement

For visible render validation, the receiver probe window can be placed on a
specific Windows monitor with zero-based monitor indices:

- `InterGalacticReceiverProbe.ps1 -RenderMonitorIndex <index>`
- `tools/stream-lab/run_true_receiver_test.ps1 -ProbeMonitorIndex <index>`
- `tools/stream-lab/run_synthetic_live_call_freshness.ps1
  -ReceiverProbeMonitorIndex <index>`

The probe wrapper writes `receiver-window-placement.json` in the receiver run
directory with the requested monitor index, placement status, and non-secret
window bounds. In external BG3 runs, the synthetic wrapper waits for that
placement artifact before sending the BG3 camera-rotation start hotkey, so a
visible receiver window launch does not silently stop source motion before the
measurement window.

## Validation Snapshot

Local smoke validation with fake credentials proved process launch, protected
IPC, external labels, and artifact writing:

- Direct app receiver smoke
  `direct-app-receiver-smoke-20260618-224610` connected to the child pipe,
  exited cleanly, wrote a summary, and reported
  `blocked_external_receiver_probe_runtime_failed` as expected for the fake
  `ws://127.0.0.1:9` LiveKit URL.
- Wrapper smoke `external-runtime-smoke-20260618-224920` wrote
  `events.jsonl`, `decoded-freshness.json`, and `rendered-freshness.json` with
  `in_process=false` and `protected_ipc=true`.
- True receiver runner smoke
  `true-runner-external-smoke-20260618-225004` returned the expected blocked
  gate from fake credentials while preserving the external receiver status.

These smokes do not prove receiver freshness because they intentionally did
not use a real LiveKit room or token. The next validation step is one external
synthetic live-call receiver run with real `/probe/get_token` credentials.
