# True Receiver Probe

## Purpose

The true receiver probe proves what a real LiveKit subscriber receives,
decodes, and renders during a gameplay stream. It is a diagnostic tool, not a
sender capture benchmark: it must not be used to tune bitrate, fallback, TURN,
LiveKit server configuration, receiver quality policy, or stream profiles. See
`stream-receiver-diagnostic-contract.md` for the receiver-side evidence
contract and lane/stage definitions this probe emits into.

## Scope

The probe connects as a separate, subscribe-only LiveKit participant. It
subscribes only to the selected gameplay screenshare and emits receiver-lane
diagnostics defined by the diagnostic contract. It never publishes audio,
video, data tracks, or chat events.

## Modes

| Mode | Purpose | Required proof |
| --- | --- | --- |
| `decode-only` | Validate true subscriber delivery and decoder freshness without visible UI. | `remote_decode` events and `decoded-freshness.json`. |
| `render` | Validate visible remote presentation. | `remote_decode`, `remote_render`, `rendered-freshness.json`, and `renderer_visible=true`. |

An in-process subscribe-only probe can run before the standalone probe; its
reports are labeled `in_process=true` because it adds load to the sender host.

## In-Process Probe

`MatrixLivekitVoipSession` exposes developer-mode in-process receiver and
local-preview probe control paths. The receiver probe requests a short-lived
`/probe/get_token` credential in memory, connects to LiveKit as the returned
distinct probe identity with `autoSubscribe=false`, publishes nothing,
explicitly subscribes to the local publisher's screenshare at high quality,
and emits redacted `remote_decode` events. Render mode emits paired
`remote_decode` and `remote_render` events and validates render freshness
only when the developer-visible receiver render surface is mounted with
`renderer_attached=true` and `renderer_visible=true`. Local-preview mode
attaches a debug renderer to the local screenshare publication after active
share and remains diagnostic only.

All three lanes use the native renderer frame callback to hash sampled Y
64x36 plus U/V 32x18 content in memory and emit only aggregate
`freshness_source=frame_hash_tap` cadence fields — no raw video content
leaves the process.

## External Probe

`InterGalacticReceiverProbe.ps1` launches the packaged Windows app as
`InterGalactic.exe --receiver-probe`, relays the upstream credential envelope
into an app-owned child pipe, and keeps tokens off command-line arguments,
logs, and output files. The external runtime starts before normal app
single-instance/user startup, initializes the same
`MatrixLivekitReceiverProbeController`, joins LiveKit as a subscribe-only
participant, publishes nothing, subscribes to the selected screenshare, and
writes `receiver-summary.json`, `receiver-summary.md`, `events.jsonl`,
`decoded-freshness.json`, and `rendered-freshness.json`. Runs are labeled
`in_process=false` and `protected_ipc=true`. Render mode mounts a small
inactive receiver window and still requires visible renderer evidence.

## Token Handling

Token issuance for the probe is a separate, server-side concern from probe
execution. Probe launch rules:

- Never pass tokens in command-line arguments.
- Never write tokens to logs, Markdown, JSON reports, shell history, or crash
  dumps.
- Prefer a protected local IPC channel or equivalent OS-protected handoff.
- Tokens must be short-lived and subscribe-only.

## Layout

```text
tools/stream-receiver-probe/
  README.md
  InterGalacticReceiverProbe.ps1
  intergalactic app runtime:
    InterGalactic.exe --receiver-probe
    external_livekit_receiver_probe_runtime_io.dart
    matrix_livekit_receiver_probe.dart
```

The runtime uses the existing Flutter/LiveKit/WebRTC dependency surface
instead of a second receiver stack. The PowerShell entry point is the
token-safe wrapper and app resolver; the app owns LiveKit join/decode/render
and receiver report writing.

## Output

The runner writes to `runtime/stream-lab/receiver-results/<run-id>/`:

- `receiver-summary.json`
- `receiver-summary.md`
- `events.jsonl`
- `decoded-freshness.json`
- `rendered-freshness.json` when running render mode
- `true-receiver-test.json`
- `true-receiver-test.md`

All identifiers are hashed or redacted. Raw video is disallowed except an
optional short bounded proof clip from synthetic content.

## Runner Contract

`tools/stream-lab/run_true_receiver_test.ps1` is the entry point:

- `-Mode Plan` or `-PlanOnly` writes the receiver-lab expected output shape.
- `-Mode DecodeOnly` requires a probe executable and protected control pipe.
- `-Mode Render` requires a probe executable, protected control pipe, and
  valid visible renderer evidence.
- `-Mode InProcessDecodeOnly` and `-Mode InProcessRender` read an
  `-InProcessEventsPath` containing already-redacted app probe events and
  write the normal receiver-lab output files without accepting tokens.
- `-Mode InProcessLocalPreview` reads already-redacted local preview events
  and writes the normal receiver-lab output files while keeping the result
  diagnostic-only.
- External `DecodeOnly` and `Render` modes require the separate probe process
  to write receiver-lane `freshness_source=frame_hash_tap` and
  `unique_fps >= MinUniqueFps` before the runner reports
  `completed_external_receiver_probe_events`.
- External `DecodeOnly` and `Render` modes can pass `-ProbeAppExe` through to
  the PowerShell probe, which resolves the app executable and launches
  `--receiver-probe`.
- The wrapper records blocked and inconclusive states instead of silently
  treating missing probe support as a pass.
- PowerShell probe scripts are launched without token-bearing command-line
  arguments; the runner passes only a control-pipe name and run metadata, and
  uses the run output directory as the child process working directory.

Hidden receiver tiles are never valid freshness proof, regardless of mode.

## Cleanup

Every probe run must terminate its own process tree before returning.
Timeouts must kill only the process the wrapper started, and must record the
timeout in `true-receiver-test.json`.
