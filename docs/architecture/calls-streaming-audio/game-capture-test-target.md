# Game Capture Test Target

Status: Debug-only measurement harness
Owner: EXPERIMENTAL
Last updated: 2026-06-05

Inter Galactic includes a local Windows D3D11 test app named
`InterGalacticCaptureTarget.exe` under `tools/game-capture-target/`. It exists
to make stream-test diagnostics repeatable without launching BG3 for every
pipeline/log validation run.

This target does not tune stream profiles, publish hook frames, replace WGC or
window-GDI capture, or change LiveKit behavior. It is a deterministic source
window that the existing screen-share path can capture and the D3D11 probe can
hook.

## What It Simulates

- A real D3D11 swap-chain based application window.
- Windowed and borderless modes at 1920x1080 or 2560x1440.
- Continuous 30 FPS, 60 FPS, or uncapped rendering.
- Deterministic moving content: animated grid, motion/noise fields,
  gameplay-like perspective motion, UI-heavy surfaces, high-contrast markers,
  and a frame/time HUD drawn inside the swap chain.
- Local target diagnostics: Present FPS, p50/p95/max Present gaps, render FPS,
  late frame count, missed frame intervals, window/client/swap-chain size, and
  scene mode.

## What It Does Not Simulate

- Real game engine frame pacing, shader complexity, CPU simulation, asset
  streaming, or overlay conflicts.
- Protected/elevated targets or anti-cheat behavior.
- BG3-specific window behavior, HDR format quirks, or game menu/gameplay load.
- A LiveKit publication backend. The stream still uses the normal app
  screen/window sharing path unless the separate D3D11 probe is enabled.

## Manual Run

Build from the app repo:

```powershell
cmake -S tools/game-capture-target -B tools/game-capture-target/build -A x64
cmake --build tools/game-capture-target/build --config Debug
```

Run examples:

```powershell
tools\game-capture-target\build\Debug\InterGalacticCaptureTarget.exe --width 1920 --height 1080 --mode windowed --scene gameplay --fps 60 --title "Inter Galactic Capture Target"
tools\game-capture-target\build\Debug\InterGalacticCaptureTarget.exe --width 2560 --height 1440 --mode borderless --scene high-motion --fps 30 --duration 60
```

If `--output-dir` is omitted, the target writes diagnostics under the app data
stream-test logs in a `capture-targets` folder. The key files are
`capture-target.json` and `capture-target.md`.

## Stream-Test Runner Use

In the Call Diagnostics stream-test dialog, enable **Launch D3D11 capture
target**. The runner will:

1. Launch `InterGalacticCaptureTarget.exe`.
2. Auto-select the target window by its stable title prefix when possible.
3. Run the selected stream presets and Windows backend overrides normally.
4. Stop the target after the batch.
5. Merge the target diagnostics into stream-test JSON and Markdown as
   top-level `gameCaptureTestTarget` evidence.

The runner resolves the executable from:

- beside the running app executable,
- `tools/game-capture-target/build/Debug/InterGalacticCaptureTarget.exe`
  found from the current working directory, or
- the local workspace absolute fallback path.

The target section is separate from `gameCaptureProbe`. Use
`gameCaptureTestTarget` to confirm the synthetic source Present cadence, and
use `gameCaptureProbe` to confirm hook/host/handoff behavior for the selected
process.

## Local No-Call Harness

For local capture/handoff diagnostics that do not need Matrix or LiveKit, use
the stream-lab script instead of the in-call command file:

```powershell
tools\stream-lab\run_local_capture_benchmark.ps1 `
  -LaunchSyntheticTarget `
  -Backend future-game-d3d11-hook `
  -Width 1280 `
  -Height 720 `
  -Fps 60 `
  -DurationSeconds 5 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30
```

The script launches this target, runs the D3D11 hook/helper, stops the target,
and writes wrapper reports under the configured local stream-lab results
directory.

Use this path before asking for BG3 logs when the question is local
D3D11 hook, host shared-texture consumer, or publication-handoff readiness.
It does not test WGC/window-GDI desktop capture, WebRTC sender stats, LiveKit,
network, or receiver rendering.

## Command-File Automation

Debug Windows builds also support a developer-only in-call command file. This
is intentionally narrower than full room automation: the user must already have
Inter Galactic open, developer mode enabled, and an active LiveKit call. When a
`CallView` is mounted, it polls:

```text
<app log directory>\stream-tests\stream-test-request.json
```

Example request for the synthetic target baseline:

```json
{
  "schema": "intergalactic.streamTestAutomation.v1",
  "id": "synthetic-baseline",
  "presets": ["smooth", "balanced", "highQuality"],
  "durationSeconds": 30,
  "warmupSeconds": 5,
  "windowsBackendMode": "app-default",
  "nativeFramePacingEnabled": true,
  "launchCaptureTarget": true,
  "captureTarget": {
    "width": 1920,
    "height": 1080,
    "mode": "windowed",
    "scene": "gameplay",
    "fps": "60"
  }
}
```

The app renames the request to a `.running.json` file, launches the target,
auto-selects the target window, runs the requested presets through the existing
stream-test runner, writes the normal JSON/Markdown reports, and then writes:

```text
stream-test-request-<id>.complete.json
```

The completion file contains `status`, the report path when available, and an
error string when the command could not run. If auto-selection fails, the
automation fails closed instead of opening a manual source picker.

For a real running game/window, keep `launchCaptureTarget` false and provide a
specific source selector. `sourceProcessId` is preferred for BG3 because its
visible OS title can be blank even when desktop capture can enumerate the
window. `sourceTitle` remains available for stable named windows:

```json
{
  "schema": "intergalactic.streamTestAutomation.v1",
  "id": "bg3-smooth-live",
  "presets": ["smooth"],
  "durationSeconds": 30,
  "warmupSeconds": 5,
  "windowsBackendMode": "game-d3d11-hook-experimental",
  "nativeFramePacingEnabled": true,
  "launchCaptureTarget": false,
  "sourceProcessId": 12212,
  "sourceTitle": "Baldur",
  "captureTarget": {
    "enabled": false
  }
}
```

## Local Diagnostic Workflow

For local helper/handoff validation, prefer:

1. Build the target/helper if needed.
2. Run `tools\stream-lab\run_local_capture_benchmark.ps1` against the
   synthetic target.
3. Confirm the local report has:
   - D3D11 Present FPS/gaps,
   - host texture consumer evidence,
   - publication-handoff output FPS/gaps,
   - coverage rows marking LiveKit/network/receiver as not tested.
4. Use the in-call command-file path only when the test requires normal
   screen-share publishing and sender/receiver stats.
5. For in-call log-pipeline validation, confirm the report has:
   - source metadata for the auto-selected window,
   - `gameCaptureTestTarget` Present FPS/gaps,
   - native capture markers,
   - sender/encoder/network diagnostics,
   - diagnostic coverage marking the target row as `available`.
6. Only then ask the user for BG3 logs when the test target proves the pipeline
   and report fields are working.

## Comparing Against BG3

The target is a baseline, not a replacement for BG3:

- If the target Present cadence is healthy and the stream is still choppy, the
  problem is in app capture, scaling, encode, transport, or receive/render
  stages.
- If both the target and BG3 show the same capture bottleneck, the issue is
  likely independent of BG3.
- If the target is healthy but BG3 is not, use BG3 as the stress/compatibility
  case and compare window-GDI/WGC/D3D11-probe evidence.
- BG3 remains required before claiming gameplay streaming is fixed because it
  exercises real game frame pacing, 10-bit backbuffers, window mode quirks, and
  content that invalidates faster plain GDI captures.

## Future Backend Support

The target intentionally exposes stable process/window metadata and a normal
D3D11 Present path. It can be used as the first proof target for later
game-capture backend phases:

- D3D11 hook attach/detach validation.
- Shared texture ring cadence validation.
- GPU texture handoff validation.
- Eventually, encoder texture-input experiments before attempting BG3.

Any future phase that publishes target/hook frames to LiveKit must update the
game-capture backend architecture, stream diagnostic contract, integration
queue, and security/review plan before becoming user-facing.
