# True Receiver Probe Plan

Owner: EXPERIMENTAL with SERVER dependency for token issuance
Status: Plan, runner scaffold, app-side in-process subscribe-only receiver
control path, in-process `remote_decode`, visible `remote_render`, diagnostic
`local_preview` frame-hash freshness taps, external process runner gating, and
dedicated external LiveKit/WebRTC receiver runtime implemented. Stream-lab
automation can ingest redacted in-process probe events or launch
`InterGalactic.exe --receiver-probe` through protected IPC into receiver-lab
artifacts. Real external synthetic/live freshness validation remains pending.

## Purpose

The true receiver probe proves what a real subscriber receives, decodes, and
renders. It is not a sender capture benchmark and it must not be used to tune
bitrate, fallback, TURN, LiveKit server configuration, receiver quality policy,
or stream profiles.

## Scope

Maintain the minimal `tools/stream-receiver-probe/` entry point and app-backed
external runtime now that the diagnostic contract is in place. The probe must
connect as a separate subscribe-only LiveKit participant, subscribe only to the
selected gameplay screenshare, and emit receiver-lane diagnostics defined in
`docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md`.

## Modes

| Mode | Purpose | Required proof |
| --- | --- | --- |
| `decode-only` | Validate true subscriber delivery and decoder freshness without visible UI. | `remote_decode` events and `decoded-freshness.json`. |
| `render` | Validate visible remote presentation. | `remote_decode`, `remote_render`, `rendered-freshness.json`, and `renderer_visible=true`. |

An in-process subscribe-only probe may be added before the standalone probe, but
its reports must be labeled `in_process=true` because it adds load to the sender
host.

Current app-side status: `MatrixLivekitVoipSession` now exposes developer-mode
in-process receiver and local-preview probe control paths. The receiver probe
requests the SERVER-owned short-lived `/probe/get_token` credential in memory,
connects to LiveKit as the returned distinct probe identity with
`autoSubscribe=false`, publishes nothing, explicitly subscribes to the local
publisher's screenshare at high quality, and emits redacted `remote_decode`
events. Render mode emits paired `remote_decode` and `remote_render` events and
validates render freshness only when the developer-visible receiver render
surface is mounted with `renderer_attached=true` and
`renderer_visible=true`. Local-preview mode attaches a debug renderer to the
local screenshare publication after active share and remains diagnostic only.
All three lanes use the native renderer frame callback to hash sampled Y 64x36
plus U/V 32x18 content in memory and emit only aggregate
`freshness_source=frame_hash_tap` cadence fields. Stream-test automation can
request these probes, preserve the redacted per-preset event stream, and pass it
to `run_true_receiver_test.ps1 -Mode InProcessDecodeOnly`,
`-Mode InProcessRender`, or `-Mode InProcessLocalPreview` for receiver-lab
artifact generation.

Current external status: `InterGalacticReceiverProbe.ps1` now launches the
rebuilt Windows app as `InterGalactic.exe --receiver-probe`, relays the
protected upstream credential envelope into an app-owned child pipe, and keeps
tokens off command-line arguments, logs, and output files. The external runtime
starts before normal app single-instance/user startup, initializes the same
`MatrixLivekitReceiverProbeController`, joins LiveKit as a subscribe-only
participant, publishes nothing, subscribes to the selected screenshare, writes
`receiver-summary.json`, `receiver-summary.md`, `events.jsonl`,
`decoded-freshness.json`, and `rendered-freshness.json`, and labels the run
with `in_process=false` and `protected_ipc=true`. Render mode mounts a small
inactive receiver window and still requires visible renderer evidence.

## Authentication Boundary

EXPERIMENTAL does not issue LiveKit tokens. SERVER owns the token flow described
by the workspace plan `docs/plans/receiver-lab-server.md`.

Probe launch rules:

- Never pass tokens in command-line arguments.
- Never write tokens to logs, Markdown, JSON reports, shell history, or crash
  dumps.
- Prefer a protected local IPC channel or equivalent OS-protected handoff.
- Tokens must be short-lived and subscribe-only.
- The probe must not publish audio, video, data tracks, or chat events.

## Proposed Probe Layout

```text
tools/stream-receiver-probe/
  README.md
  InterGalacticReceiverProbe.ps1
  intergalactic app runtime:
    InterGalactic.exe --receiver-probe
    external_livekit_receiver_probe_runtime_io.dart
    matrix_livekit_receiver_probe.dart
```

The runtime uses the existing Flutter/LiveKit/WebRTC dependency surface instead
of adding a second receiver stack. The PowerShell entry point remains the
token-safe wrapper and app resolver; the app owns LiveKit join/decode/render
and receiver report writing.

## Output

The runner writes to:

```text
runtime/stream-lab/receiver-results/<run-id>/
```

Required outputs:

- `receiver-summary.json`
- `receiver-summary.md`
- `events.jsonl`
- `decoded-freshness.json`
- `rendered-freshness.json` when running render mode
- `true-receiver-test.json`
- `true-receiver-test.md`

All identifiers must be hashed or redacted. Raw video is disallowed except an
optional short bounded proof clip from synthetic content.

## Validation Order

1. Synthetic live source, local preview lane only.
2. Synthetic live source, in-process decode-only receiver.
3. Synthetic live source, in-process rendered receiver with visible renderer
   after the renderer boundary is implemented.
4. Dedicated external receiver probe, decode-only, with fake credentials for
   process/IPC/artifact smoke.
5. Dedicated external receiver probe, rendered and visible, with fake
   credentials for process/IPC/artifact smoke.
6. Dedicated external receiver probe, decode-only and render, with real
   synthetic live-call credentials.
7. Only after the external synthetic receiver path is trustworthy, repeat with
   BG3.

Hidden receiver tiles are invalid proof at every step.

## Runner Contract

`tools/stream-lab/run_true_receiver_test.ps1` is the entry point for the plan:

- `-Mode Plan` or `-PlanOnly` writes the receiver-lab expected output shape.
- `-Mode DecodeOnly` requires a probe executable and protected control pipe.
- `-Mode Render` requires a probe executable, protected control pipe, and valid
  visible renderer evidence.
- `-Mode InProcessDecodeOnly` and `-Mode InProcessRender` read an
  `-InProcessEventsPath` containing already-redacted app probe events and write
  the normal receiver-lab output files without accepting tokens.
- `-Mode InProcessLocalPreview` reads already-redacted local preview events and
  writes the normal receiver-lab output files while keeping the result
  diagnostic-only.
- External `DecodeOnly` and `Render` modes now require the separate probe
  process to write receiver-lane `freshness_source=frame_hash_tap` and
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
- Synthetic validation now covers the ingest gate: a fixture with
  `remote_decode freshness_source=frame_hash_tap unique_fps=29.3` passes the
  25 unique-FPS threshold, while an otherwise high-`unique_fps` fixture labeled
  `receiver_stats_frame_counter` exits as
  `inconclusive_frame_hash_tap_pending`.
- External fake-credential smoke validation now covers process launch,
  protected child IPC, runner propagation, and artifact creation:
  `external-runtime-smoke-20260618-224920` and
  `true-runner-external-smoke-20260618-225004` both preserved
  `in_process=false` and `protected_ipc=true` while correctly blocking on the
  fake LiveKit endpoint instead of claiming freshness.

## Cleanup

Every probe run must terminate its task-owned process tree before returning.
Timeouts must kill only the process started by the wrapper and must record the
timeout in `true-receiver-test.json`.
