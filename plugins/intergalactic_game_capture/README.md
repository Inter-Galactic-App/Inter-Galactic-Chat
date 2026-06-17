# Inter Galactic Game Capture POC

Debug-only native Windows proof of concept for D3D11 game capture.

This folder is still debug-only. It validates BG3 DX11 attach,
Present/Present1 capture, shared D3D11 texture ring copies, host consumption,
and local publication-shaped handoff buffers before any LiveKit publication or
production source-picker integration.

Build from the `windows` directory:

```powershell
cmake -S . -B build -A x64
cmake --build build --config Debug
```

Run the helper against a selected 64-bit DX11 target process:

```powershell
.\build\Debug\intergalactic_game_capture_helper.exe --pid <targetPid> --duration-ms 10000
```

By default the hook saves five local proof frames. For cadence-only runs, skip
PNG export so the report measures Present timing without synchronous diagnostic
readback pauses:

```powershell
.\build\Debug\intergalactic_game_capture_helper.exe --pid <targetPid> --duration-ms 10000 --max-saved-frames 0
```

Phase 3B can also run a host shared-texture consumer. This keeps the hook
diagnostic-only, but proves whether the helper/host side can open the shared
D3D11 texture ring and observe fresh frames:

```powershell
.\build\Debug\intergalactic_game_capture_helper.exe --pid <targetPid> --duration-ms 10000 --max-saved-frames 0 --host-consume-frames true --host-proof-frames 0
```

The host consumer writes `host-consumer.json` and `host-consumer.md` beside the
normal `metadata.json`. Optional `--host-proof-frames <n>` performs a small
diagnostic CPU readback sample to prove visible content; keep it at `0` for
cadence-only runs.

Phase 4A can also run a local publication-handoff probe. This reads the latest
shared texture from the host consumer, contain-fit scales the full source into a
preset-sized BGRA buffer, and records the output cadence/timing. It still does
not publish frames to LiveKit:

```powershell
.\build\Debug\intergalactic_game_capture_helper.exe --pid <targetPid> --duration-ms 10000 --max-saved-frames 0 --host-consume-frames true --host-proof-frames 0 --publication-handoff true --publication-handoff-max-width 1280 --publication-handoff-max-height 720 --publication-handoff-target-fps 30
```

The publication handoff writes `publication-handoff.json` and
`publication-handoff.md`. Treat healthy handoff output as evidence that the
hook path can produce local publication-shaped frames; it is not evidence that
remote LiveKit stream quality is fixed until a dedicated game-capture video
source or encoder handoff publishes those frames.

Output is written under:

```text
%INTERGALACTIC_WORKSPACE_ROOT%\runtime\game-capture-poc\results\<timestamp>-<session>\
```

Set `INTERGALACTIC_WORKSPACE_ROOT` to your local workspace root before using
the workspace stream-lab helpers. Do not commit personal absolute output paths in
plugin documentation or test evidence.

The local proof-frame exporter writes PNG previews from BGRA/RGBA 8-bit
backbuffers and BG3's observed `R10G10B10A2_UNORM` backbuffer by converting the
saved diagnostic readback to 8-bit RGBA. This conversion is for local proof
frames only; it does not change the shared texture ring.

The prototype must stay local and developer-triggered. It does not publish to
LiveKit and it must fail closed on unsupported, elevated, protected, or
non-D3D11 targets.
