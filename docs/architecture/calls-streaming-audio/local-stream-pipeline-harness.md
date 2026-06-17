# Local Stream Pipeline Harness

Status: Debug-only measurement harness
Owner: EXPERIMENTAL
Last updated: 2026-06-15

Inter Galactic has a local stream-pipeline harness for collecting capture-path
evidence without Matrix login, room join, call creation, or LiveKit publishing.
It is intentionally separate from the in-call stream-test runner.

The current implementation is a Windows PowerShell entrypoint:

```text
tools/stream-lab/run_local_capture_benchmark.ps1
```

Default reports are written under:

```text
{LOCAL_RESULTS_DIR}\
```

## Why This Exists

The current gameplay-stream bottleneck evidence points upstream of LiveKit:
native capture and local handoff cadence are the limiting areas, while bitrate,
TURN/ICE, LiveKit upload, and receiver policy have not been the active limiter
in the tested BG3 cases.

The older stream-test automation still needs:

- a logged-in app,
- an active MatrixRTC/LiveKit call,
- a mounted `CallView`,
- a selected screen/window source,
- LiveKit publish and sender stats.

That is too much manual setup when the next question is local pipeline health.
The local harness lets maintainers run the synthetic D3D11 target and helper directly
from the Windows workspace.

## Current Supported Mode

The first supported mode is:

```text
synthetic target or selected D3D11 process
-> D3D11 Present hook helper
-> shared D3D11 texture ring
-> host texture consumer
-> GPU contain-fit BGRA publication-handoff texture
-> optional D3D11 video-processor NV12 or P010 conversion
-> optional local Media Foundation H.264 encoder proof for NV12
-> optional proof-only PNG/luma readback or all-frame BGRA readback
-> local JSON/Markdown report
```

This mode uses:

- `tools/game-capture-target/build/Debug/InterGalacticCaptureTarget.exe`
- `plugins/intergalactic_game_capture/windows/build/Debug/intergalactic_game_capture_helper.exe`
- `plugins/intergalactic_game_capture/windows/build/Debug/intergalactic_game_capture_hook64.dll`

The helper writes its existing files beside the wrapper report:

- `metadata.json`
- `summary.md`
- `host-consumer.json`
- `host-consumer.md`
- `publication-handoff.json`
- `publication-handoff.md`
- `helper.log`

The synthetic target also writes:

- `capture-target.json`
- `capture-target.md`

## What It Tests

- D3D11 swap-chain Present cadence.
- Hook attach/detach and failure classification.
- Backbuffer size/format.
- Hook copy/resolve timing.
- Shared texture ring production.
- Host-side shared texture opening and frame consumption.
- Contain-fit publication-handoff output size.
- Handoff output cadence, p50/p95/max gaps, GPU scale timing, readback mode,
  proof-readback counters, and paced drops.
- Handoff output/encoder format, including the debug-only `nv12` /
  `DXGI_FORMAT_NV12` probe and debug-only `p010` / `DXGI_FORMAT_P010`
  source-conversion proof.
- Debug-only local Media Foundation H.264 proof from the scaled NV12 texture,
  including initialization, submit, GPU-copy, finalize, output-size, and
  write-failure evidence.
- Repeated publication outputs when the sampler keeps target cadence with the
  latest available frame.
- Local visible-output proof when the helper is run with saved/proof frames.
- Hook-side proof export busy frames when target-side PNG export is skipped
  rather than blocking the render hook.

## What It Does Not Test

- Matrix login/session restore.
- MatrixRTC membership.
- LiveKit token, SFU, TURN, ICE, or network behavior.
- WebRTC sender stats.
- Remote receiver decode/render stats.
- In-app source picker behavior.
- Production screen sharing.
- WGC/window-GDI desktop capture outside Flutter.
- WebRTC sender texture/frame integration.

The report marks those areas as `notTested`, `notApplicable`, or
`unavailable` rather than implying they were measured.

## How To Run

### Native Capture To Media Foundation Isolation Gate

Use this first-class wrapper when the question is whether the no-WebRTC DX11
capture -> GPU NV12 -> local Media Foundation H.264 path can sustain the
720p30 gate:

```powershell
.\tools\stream-lab\run_native_capture_mf_isolation.ps1 `
  -SourceTitle "Baldur's Gate 3" `
  -DurationSeconds 10 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30
```

For a no-game synthetic R10/HDR-like smoke of the same local MF proof boundary:

```powershell
.\tools\stream-lab\run_native_capture_mf_isolation.ps1 `
  -LaunchSyntheticTarget `
  -DurationSeconds 5 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30
```

The wrapper invokes `run_local_capture_benchmark.ps1` with:

- `-Backend future-game-d3d11-hook`
- `-PublicationOutputFormat nv12`
- `-PublicationEncoderProof h264-mf`
- `-PublicationProofFrames 0`
- `-PublicationReadbackMode proof-only`

It then writes `native-capture-mf-isolation.json` and
`native-capture-mf-isolation.md` beside the local benchmark report. The status
values are:

- `passed_native_capture_mf_720p30`: local capture, NV12 conversion, and MF
  proof cleared the 720p30 gate; next work should isolate WebRTC `OnFrame` or a
  native encoded-frame handoff.
- `failed_native_capture_mf_720p30`: stop before another live call loop and fix
  local capture, GPU conversion, or MF proof timing first.
- `inconclusive_native_capture_mf`: repair missing local diagnostic coverage
  before using the report as a decision gate.

`-BenchmarkReportJson` can analyze an existing `local-capture-benchmark.json`
without launching a target. Analysis-mode reports are written under a fresh
`runtime/stream-lab/local-results/native-capture-mf-isolation-*` directory so
archived benchmark folders are not modified.

Validation note: `local-capture-20260615-100322` ran the synthetic
R10/HDR-like path at 1280x720@30 and produced
`passed_native_capture_mf_720p30`: source format `r10g10b10a2`, Present
`58.218 FPS`, handoff output `32.118 FPS`, NV12 frames/failures/convert avg
`142 / 0 / 0.035 ms`, and `h264-mf` proof frames/failures/submit p95/output
bytes `142 / 0 / 0.108 ms / 4627843`. It still does not test WebRTC, LiveKit,
network, or receiver behavior.

Live BG3 validation note: `local-capture-20260615-101334` attached to
`bg3_dx11` with camera rotation active and also produced
`passed_native_capture_mf_720p30`: source format `r10g10b10a2`, Present
`77.223 FPS`, handoff output `30.188 FPS`, output `1280x720` NV12, NV12
frames/failures/convert avg `279 / 0 / 0.023 ms`, and `h264-mf` proof
frames/failures/submit p95/output bytes `279 / 0 / 0.108 ms / 8477308`. This
proves the local BG3 DX11 capture -> NV12 -> MF proof boundary, not the
WebRTC/LiveKit call sender boundary.

### WebRTC Source OnFrame Isolation Gate

Use this wrapper after the native capture-to-Media Foundation gate passes and
the next question is whether the libwebrtc game-capture source and local
`VideoCapturer::OnFrame` handoff can sustain 720p30 without Matrix, LiveKit,
network, receiver, or full sender stats:

```powershell
.\tools\stream-lab\run_webrtc_onframe_isolation.ps1 `
  -SourceTitle "Baldur's Gate 3" `
  -DurationSeconds 10 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30
```

The wrapper calls the patched `InterGalacticGameCaptureWebrtcSourceSmoke`
export, writes `intergalactic.gameCaptureWebrtcSourceSmoke.v1`, then writes an
`intergalactic.webrtcOnFrameIsolation.v1` gate report. Source-smoke reports
include helper startup diagnostics (`startupFailureReason`,
`helperOutputRoot`, helper exit-code fields, and `openSharedStateWaitMs`) so a
failed local source run does not look like a sender bottleneck.

Status values are:

- `passed_webrtc_onframe_isolation`: the no-sender WebRTC source/OnFrame path
  and the linked native capture-to-MF report clear the local 720p30 gate; route
  remaining BG3 work to WebRTC sender/native encoded-frame handoff.
- `failed_webrtc_onframe_isolation`: stop before another live call loop and fix
  local source delivery, native NV12 submission, CPU fallback, or OnFrame
  callback cost first.
- `inconclusive_webrtc_onframe_isolation`: repair missing source-smoke
  diagnostics before using the result as a decision gate.

Live BG3 source/OnFrame validation note:
`webrtc-onframe-isolation-20260615-104143` reclassified the latest rebuilt
source-smoke run as `passed_webrtc_onframe_isolation`, linked to the passing
`local-capture-20260615-101334` native MF proof. Pass
`-NativeMfIsolationJson` explicitly when comparing against a specific archived
MF proof; otherwise the wrapper links the latest local MF report it can find.
Evidence: output `1280x720`,
submitted/delivery submitted `282 / 282`, measured delivery FPS `29.64`,
fixed-window FPS `28.2`, native NV12 submitted/failures `279 / 0`, CPU fallback
`0`, delivery queue wait avg/max `0.027 / 0.494 ms`, `OnFrame` call avg/max
`0.0027 / 0.035 ms`, and visible proof frames present. The fixed-window count
is lower because the report requested a 10 second smoke but the measured
delivery window starts after helper/source startup; use measured delivery
cadence for this local gate.

### Dummy NV12 Live Sender Isolation Gate

Use this wrapper after local BG3 capture/MF and no-sender source-OnFrame gates
pass, and the remaining decision is whether the existing live WebRTC raw-frame
sender can sustain 720p30 when frames are already-ready native NV12:

```powershell
.\tools\stream-lab\run_dummy_nv12_live_sender_isolation.ps1 `
  -DurationSeconds 30 `
  -WarmupSeconds 5 `
  -SourceTitle ''
```

This requires a rebuilt Debug app in an active call. The wrapper writes a
stream-test automation request with `dummyNv12LiveSender=true` and
`gameCaptureSourceMode=dummy-nv12-live-sender`. The native source generates a
1280x720 NV12 D3D11 texture, carries it through the normal native NV12 buffer,
explicit fence, WebRTC raw-frame sender, Media Foundation H.264, RTP sender,
and LiveKit publication path, and bypasses BG3, the game hook helper, R10
conversion, WGC/GDI capture, bitrate tuning, receiver tuning, and custom
encoded-frame handoff.

Status values are:

- `passed_dummy_nv12_live_sender_720p30`: the raw WebRTC/MF/LiveKit sender can
  sustain 720p30 from already-ready native NV12; do not implement the custom
  encoded-frame path as the next default branch.
- `failed_dummy_nv12_live_sender_720p30`: classify the WebRTC sender or
  encoder-input handoff as the limiter and design the custom native
  encoded-frame or encoder-input handoff.
- `failed_dummy_nv12_live_sender_native_nv12_unhealthy`: repair dummy native
  NV12 sample/fence/Media Foundation input plumbing before using the result.
- `inconclusive_dummy_nv12_live_sender_*`: repair automation/report/source-mode
  evidence before using the run as a decision gate.

Latest validation note:
`dummy-nv12-live-sender-20260615-174359` produced
`passed_dummy_nv12_live_sender_720p30`. The linked stream-test
`stream-test-2026-06-15T21-44-01-565259Z` reported about
`30.3 / 30.0 / 30.0` capture/encode/send FPS, source mode
`dummy-nv12-live-sender`, native NV12 submitted/failures/CPU fallback
`1057 / 0 / 0`, `deliveryOnFrameCallMs` about `3.07 ms` average, and Media
Foundation `ProcessInput` about `0.38 ms` average. This proves the existing
raw sender path can hit Smooth 720p30 when fed already-ready native NV12 and
routes the next work to BG3 native frame ownership, GPU fence/readiness, or
game NV12 readiness under live sender coupling.

### Native Sender Handoff Isolation Gate

Use this aggregate wrapper after the native capture-to-MF and local WebRTC
source-OnFrame gates exist, and the decision point is whether the remaining
failure belongs to live WebRTC sender/native encoded-frame handoff:

```powershell
.\tools\stream-lab\run_native_sender_handoff_isolation.ps1 `
  -AnalyzeOnly `
  -StreamTestJson "<latest-stream-test.json>"
```

Without `-AnalyzeOnly`, the wrapper can launch the two local prerequisite
wrappers first, using the same BG3 source title/PID and 1280x720@30 target
arguments. It writes `native-sender-handoff-isolation.json` and
`native-sender-handoff-isolation.md` under
`runtime/stream-lab/local-results/native-sender-handoff-isolation-*`.

Status values are:

- `passed_local_sender_prerequisites`: local native MF and source-OnFrame gates
  pass; run exactly one live BG3 DX11 Smooth 720p30 call test next.
- `failed_live_sender_handoff`: local gates pass, but the linked live
  stream-test still has low capture/encode/send FPS and slow live sender
  handoff evidence. Before moving to native encoded-frame/WebRTC sender
  handoff design, run the dummy NV12 live sender isolation gate above. If dummy
  NV12 passes, route work to BG3 native frame ownership, GPU fence/readiness,
  or game NV12 readiness instead of assuming the raw sender is inherently
  capped.
- `failed_local_sender_handoff_prerequisite`: fix native MF, GPU conversion,
  source delivery, CPU fallback, or local OnFrame before another live call.
- `passed_live_sender_handoff`: linked live test clears the local sender gate;
  repeat once only if confirmation is needed.
- `inconclusive_native_sender_handoff`: repair missing local evidence before
  using the wrapper as a decision gate.

Latest validation note: analyzing
`stream-test-2026-06-15T15-50-03-152124Z.json` against
`local-capture-20260615-101334` and
`webrtc-onframe-isolation-20260615-104143` produced
`failed_live_sender_handoff`. Local BG3/DX11 capture -> NV12 -> MF and local
source-OnFrame prerequisites are healthy, while the live report remained near
11-12 FPS with `deliveryOnFrameCallMs` around `48 ms` average and `276 ms`
max.

Dummy sender validation note:
`dummy-nv12-live-sender-20260615-174359` passed the live sender gate at about
30 FPS capture/encode/send from already-ready NV12. Combined with the BG3 live
miss, this means the current next branch is BG3-specific native frame
readiness/ownership under live sender coupling, not custom encoded-frame
handoff yet.

From the app repo:

```powershell
.\tools\stream-lab\run_local_capture_benchmark.ps1 `
  -LaunchSyntheticTarget `
  -Backend future-game-d3d11-hook `
  -Width 1280 `
  -Height 720 `
  -Fps 60 `
  -DurationSeconds 5 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30 `
  -PublicationReadbackMode proof-only `
  -PublicationOutputFormat nv12 `
  -PublicationProofFrames 3
```

To test the scaled NV12 frame path against a local H.264 Media Foundation sink
writer, run encoder proof with no publication proof frames:

```powershell
.\tools\stream-lab\run_local_capture_benchmark.ps1 `
  -LaunchSyntheticTarget `
  -Backend future-game-d3d11-hook `
  -Width 1920 `
  -Height 1080 `
  -Fps 60 `
  -DurationSeconds 5 `
  -TargetWidth 1920 `
  -TargetHeight 1080 `
  -TargetFps 30 `
  -PublicationReadbackMode proof-only `
  -PublicationOutputFormat nv12 `
  -PublicationEncoderProof h264-mf `
  -PublicationProofFrames 0
```

Visible proof and encoder proof are intentionally separate runs. If
`-PublicationEncoderProof h264-mf` is set with proof frames above zero, the
wrapper fails before creating output folders and asks for a separate
non-encoder proof pass. This keeps diagnostic PNG/readback work from
contaminating encoder timing.

To compare R10/HDR-like source conversion into P010 without claiming encoder or
LiveKit coverage, run a non-encoder proof pass:

```powershell
.\tools\stream-lab\run_local_capture_benchmark.ps1 `
  -LaunchSyntheticTarget `
  -Backend future-game-d3d11-hook `
  -SyntheticFormat r10g10b10a2 `
  -SyntheticHdrLike `
  -SyntheticScene high-motion `
  -Width 2560 `
  -Height 1440 `
  -Fps 60 `
  -DurationSeconds 5 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30 `
  -PublicationReadbackMode proof-only `
  -PublicationOutputFormat p010 `
  -PublicationEncoderProof off `
  -PublicationProofFrames 3
```

`p010` is currently a local source-conversion proof. The wrapper rejects
`-PublicationEncoderProof h264-mf` unless `-PublicationOutputFormat nv12`
because the Media Foundation proof path and live WebRTC handoff are still NV12.

To attach to an already running process:

```powershell
.\tools\stream-lab\run_local_capture_benchmark.ps1 `
  -SourcePid 12345 `
  -Backend future-game-d3d11-hook `
  -DurationSeconds 10 `
  -TargetWidth 1280 `
  -TargetHeight 720 `
  -TargetFps 30 `
  -PublicationReadbackMode proof-only `
  -PublicationOutputFormat nv12 `
  -PublicationProofFrames 3
```

To resolve by visible window title:

```powershell
.\tools\stream-lab\run_local_capture_benchmark.ps1 `
  -SourceTitle "Inter Galactic Capture Target" `
  -Backend future-game-d3d11-hook
```

## Debug Stream Package Workflow

> Internal maintainer workflow: this section requires the private stream-lab
> workspace, patched WebRTC/native build inputs, and writable runtime output
> that are not included with the app repository checkout.
> Public contributors should use the normal Flutter/Windows build docs unless
> a maintainer provides this workspace-local harness.

Maintainers with the private stream-lab workspace can use the local stream
package harness when native `libwebrtc.dll`, game-capture helper/hook binaries,
or patched Flutter WebRTC artifacts need to be staged into the Windows Debug
app before a stream test. This helper is not part of an ordinary app repository
checkout.

Use the wrapper command from the workspace root that contains
`tools/stream-lab`; it supplies the stable build flags and leaves tool-path
discovery to the package script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\stream-lab\stream_debug_build.ps1 `
  -Mode Plan
```

For a full rebuilt Debug app package, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\stream-lab\stream_debug_build.ps1 `
  -Mode Full
```

`-Mode Full` builds native `libwebrtc`, builds the game-capture helper/hook,
refreshes `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`, runs
Flutter pub get and the patched-libwebrtc installer, rebuilds the Windows Debug
app, explicitly copies the native DLL plus helper/hook into the Debug runner,
creates a Debug bundle zip, and writes a manifest under
`runtime/stream-lab/debug-builds/<runid>/`.

For quick native stream-bit refreshes after a full Debug runner already exists,
run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\stream-lab\stream_debug_build.ps1 `
  -Mode NativeQuick `
  -NoZip
```

`-Mode NativeQuick` skips Flutter pub get, patched install, and Flutter build,
then refreshes only native `libwebrtc.dll` plus the generated helper/hook inside
the existing Debug runner. Use `-Mode Full` again after Flutter/plugin,
dependency, asset, or runner changes.

The harness performs a NuGet preflight before Windows Flutter builds. It can
auto-detect a machine-local NuGet install and prepends that directory to PATH
for the package process only. If a machine uses a custom install location,
pass one of:

```powershell
-NuGetDirectory <path-to-nuget-directory>
-NuGetExe <path-to-nuget.exe>
```

The helper/hook build also auto-detects CMake from PATH, common CMake install
locations, and Visual Studio 2022's bundled CMake tools. Pass `-CMakeExe` to
the wrapper only when a machine needs a custom CMake path.

A normal full Debug package should verify native and Debug runner
`libwebrtc.dll` hashes match, and that Debug runner helper/hook hashes match the
generated Debug helper/hook outputs.

Each manifest records resolved NuGet state, artifact/native/runner hashes,
validation steps, warnings, and a bounded process sweep. Treat any
workspace-related Dart/Flutter/helper process started after the run as cleanup
risk before beginning BG3 or live call testing.

Current debug refresh evidence:

- `runtime/stream-lab/debug-builds/20260613-170649/` completed `-Mode Full`
  with zero warnings and an empty process sweep. Native and Debug runner
  `libwebrtc.dll` SHA-256 matched at
  `7092806BBA9A1EC3BAFEE583ED05878D4C0487BAF8D07EBB9580E8C24EEC0DA6`; patched
  `libwebrtc.zip` SHA-256 was
  `49571A85E3E92748862BCF8B0819CBD95542625264B9FF39361EA368E64CE087`;
  helper and hook hashes also matched the generated Debug build outputs.
- `runtime/stream-lab/debug-builds/20260613-170838/` completed
  `-Mode NativeQuick -NoZip` with zero warnings and an empty process sweep,
  proving the fast native/helper refresh path can keep the existing Debug
  runner consistent without running Flutter.

## Backend Names

The script accepts these backend labels so future command lines remain stable:

- `future-game-d3d11-hook`
- `app-default`
- `wgc`
- `window-gdi`

Only `future-game-d3d11-hook` is implemented today. The other backends write a
safe `not_implemented` report because there is no standalone native WGC/GDI
desktop-capture CLI yet.

## Local Diagnostic Workflow

For local streaming diagnostics:

1. Run the local harness against the synthetic target first.
2. Check `local-capture-benchmark.md` for Present FPS/gaps, hook copy timing,
   host consumer health, and publication-handoff cadence.
3. Treat LiveKit/network/receiver as untested in this report.
4. Ask for BG3 only after the synthetic target shows the local helper/report
   path is producing complete evidence.
5. Use BG3 as the stress/compatibility test, not the first report-plumbing
   validation target.

## Current Validation

The first 2026-06-04 smoke proved the D3D11 Present and host texture consumer
path was healthy, but it also exposed a helper-side publication pacing bug:
`local-capture-20260604-163601` produced about 58 Present FPS and 578 consumed
host frames, while the publication handoff emitted only about 20.8 FPS with
62 ms p95 output gaps even though per-frame handoff work averaged about
2.7 ms.

The helper now samples the latest available shared texture on a target-cadence
window instead of requiring the next source event to arrive strictly after the
previous output and readback. The report also exposes `repeatedOutputFrames`,
so cadence-padding is visible when a future source cannot present fast enough.

Post-fix synthetic checks:

- `local-capture-20260604-165437`: 1280x720 source to 1280x720@30 produced
  about 32.1 handoff FPS, 32.3 ms p95 output gaps, 153 visible output frames,
  and 1 repeated output frame in a 5-second post-rebuild smoke.
- `local-capture-20260604-164630`: 1920x1080 source to 1920x1080@30 produced
  about 31.8 handoff FPS, 32.5 ms p95 output gaps, 314 visible output frames,
  and 3 repeated output frames.
- `local-capture-20260604-164705`: 1920x1080 source to 1920x1080@60 produced
  about 57.9 handoff FPS and 30.0 ms p95 output gaps, matching the synthetic
  source cadence.
- `local-capture-20260604-164741`: 2560x1440 source to 1920x1080@30 produced
  about 32.0 handoff FPS, 32.5 ms p95 output gaps, 315 visible output frames,
  and 4 repeated output frames.

These reports prove the local D3D11 hook, shared-texture consumer, GPU
contain-fit scale, and BGRA handoff buffer are ready for a BG3 stress smoke.
They still do not prove encoder, LiveKit, network, or receiver behavior.

BG3 proof-only validation after the R10 color fix and GPU texture handoff:

- `local-capture-20260604-180806`: live BG3 DX11 2560x1440 source to
  1280x720@30 produced about 30.5 handoff FPS, 43.8 ms p95 output gaps, GPU
  scale averaging about 0.018 ms, total handoff work averaging about
  0.038 ms, and 3 / 3 visible publication proof frames. The proof PNG was
  full-frame and color-correct against the provided BG3 reference screenshot.
- `local-capture-20260604-181045`: live BG3 DX11 2560x1440 source to
  1920x1080@30 produced about 29.9 handoff FPS, 44.9 ms p95 output gaps, GPU
  scale averaging about 0.015 ms, total handoff work averaging about
  0.042 ms, and 3 / 3 visible publication proof frames. The proof PNG was
  full-frame and color-correct.
- These runs used `publicationReadbackMode=proof-only`, so continuous
  per-frame CPU readback is no longer part of the measured publication path.
  CPU readback happens only for the requested proof frames.
- The helper now cleans up a stale already-loaded hook DLL before injecting a
  new run. This recovered cleanly after an earlier helper crash left the hook
  loaded inside the BG3 process.

Encoder-compatible NV12 probe validation:

- `local-capture-20260604-200324`: synthetic 1280x720 source to
  1280x720@30 with `PublicationOutputFormat=nv12` completed without proof
  readback, produced about 32.0 handoff FPS, 31.97 ms p95 output gaps,
  155 NV12 output frames, zero NV12 conversion failures, and about
  0.028 ms average NV12 conversion time.
- `local-capture-20260604-200640`: the same synthetic target with one host
  proof and one publication proof completed cleanly, produced about
  31.9 handoff FPS, 154 NV12 output frames, zero conversion failures, one
  visible publication proof frame, one visible NV12 luma proof, and about
  0.024 ms average NV12 conversion time.
- Hook-side PNG export is now non-blocking. When the target-side staging map is
  busy, reports increment `proofExportBusyFrames` instead of blocking the
  Present hook. Use publication proof frames for visible output validation.
- This fixes the post-BG3 synthetic-target timeout caveat. The synthetic
  harness is again the first-step no-call baseline before BG3 stress tests.

Local encoder proof validation:

- `local-capture-20260604-204405`: synthetic 1280x720 source to
  1280x720@30 with `PublicationEncoderProof=h264-mf` submitted 144 NV12
  frames to the local H.264 Media Foundation sink writer, recorded zero write
  failures, averaged about 0.063 ms per `WriteSample`, and wrote a 4.6 MB
  MP4 proof file.
- `local-capture-20260604-204425`: synthetic 1920x1080 source to
  1920x1080@30 submitted 145 encoder-proof frames, recorded zero write
  failures, averaged about 0.065 ms per submit, and wrote a 9.6 MB MP4 proof
  file.
- `local-capture-20260604-204446`: synthetic 1920x1080 source to
  1920x1080@60 submitted 277 encoder-proof frames, recorded zero write
  failures, averaged about 0.051 ms per submit, and wrote a 13.9 MB MP4 proof
  file.
- `local-capture-20260604-204830`: separate non-encoder visible proof still
  produced one visible NV12 publication proof frame after the encoder path was
  added.

These reports prove the debug local handoff can feed scaled NV12 textures into
a local hardware-transform-enabled H.264 encoder proof at 720p30, 1080p30, and
1080p60 synthetic cadence. They still do not prove WebRTC/LiveKit publication
or remote receiver behavior.

Live BG3 local encoder validation:

- `local-capture-20260604-210942`: live BG3 DX11 proof-only validation used
  the actual 2560x1440 source, produced 1280x720 NV12 output, wrote 3 / 3
  visible publication proof frames, wrote 3 / 3 visible NV12 luma proof
  frames, and recorded zero NV12 conversion failures. The proof image was
  inspected and remained full-frame and color-correct. Because this was a
  visible proof run, its proof-readback timing should not be used as the
  encoder cadence baseline.
- `local-capture-20260604-210855`: live BG3 DX11 to 1280x720@30 with
  `PublicationEncoderProof=h264-mf` submitted 281 local H.264 proof frames,
  recorded zero write failures, produced about 29.9 handoff FPS, held
  p95/max output gaps to about 39.5/45.1 ms, averaged about 0.028 ms for NV12
  conversion, averaged about 0.069 ms per encoder submit, and wrote an 8.2 MB
  MP4 proof file.
- `local-capture-20260604-211322`: live BG3 DX11 to 1920x1080@30 with
  `PublicationEncoderProof=h264-mf` submitted 281 local H.264 proof frames,
  recorded zero write failures, produced about 30.1 handoff FPS, held
  p95/max output gaps to about 39.4/42.9 ms, averaged about 0.022 ms for NV12
  conversion, averaged about 0.068 ms per encoder submit, and wrote an 18.7 MB
  MP4 proof file.

These live BG3 reports clear the local Phase 4C boundary for 720p30 and
1080p30. The June 10 WebRTC-source follow-up also proved the live BG3
`R10G10B10A2` path can submit native NV12 and feed Media Foundation on the
intro menu. The first motion-heavy report then found a
`gpu_nv12_failed reason=video_processor_blt_wait_timeout` fallback boundary,
but the later ring-slot native-NV12 run sustained actual gameplay with
`nativeNv12Submitted=836`, `nativeNv12Failures=0`, `cpuFallback=0`, and Media
Foundation `input_path=native_nv12`. The remaining boundary is no longer
conversion continuity; it is stable 720p30 pacing while the true GPU path is
active. The next local harness comparison should bound GPU `native_frame_ready`
wait, delivery queue wait, `OnFrame`, and Media Foundation input stalls before
another live validation.

The 2026-06-10 SourceConversion local pass added synthetic `R10G10B10A2` and
HDR-like target modes and cleared the helper-side conversion boundary without
BG3. `local-capture-20260610-180534` converted a 2560x1440 R10/HDR-like
high-motion source to 1280x720@30 NV12 with `242` Media Foundation H.264 proof
frames, `0` NV12 failures, and `0.024 ms` average NV12 conversion.
`local-capture-20260610-180628` repeated the path at 1920x1080@30 with `241`
encoder proof frames, `0` failures, and `0.022 ms` average NV12 conversion.
`local-capture-20260610-180714` ran proof-only NV12 readback and produced
`3 / 3` visible proof frames. The same pass added helper capability fields for
BGRA/R10 input and NV12/P010 output support, and the live WebRTC source now
reports async native-NV12 queue/ready counters for the next BG3 validation.

The same day, the P010 comparison pass proved the local helper can emit and
read back P010 luma from an R10/HDR-like source:
`local-capture-20260610-204335` produced 147 P010 frames, 0 conversion
failures, 3 / 3 visible P010 proof readbacks, and 0.045 ms average P010
conversion. A fresh same-settings NV12 proof
`local-capture-20260610-204414` stayed tied on cadence with 143 NV12 frames, 0
failures, and 0.043 ms average conversion, and
`local-capture-20260610-204503` confirmed the NV12 H.264 encoder proof still
submitted 135 frames with 0 write failures. This keeps P010 in the diagnostic
branch, not the live encoder path.

The same P010/NV12 comparison was then run against an actual BG3 DX11 process
using PID attach. `local-capture-20260610-205743` saw the real BG3 source as
2560x1440 DXGI format `24`, opened 3 shared texture slots, and produced 291
P010 frames with 0 conversion failures, 3 / 3 visible P010 proof readbacks, and
0.022 ms average P010 conversion. The same-PID NV12 comparison
`local-capture-20260610-205834` produced 293 NV12 frames with 0 conversion
failures, 3 / 3 visible NV12 proof readbacks, and 0.023 ms average NV12
conversion. This confirms P010 works against BG3 locally, but does not improve
the local helper cadence boundary relative to NV12.

## Comparing Against BG3

- Healthy synthetic Present cadence plus slow publication handoff means the
  next work is local helper/handoff pacing, not LiveKit.
- Healthy synthetic helper/handoff but poor BG3 in-call streams means the next
  comparison is BG3-specific capture/source behavior.
- Poor synthetic target Present cadence means the test host is overloaded or
  the synthetic target itself is not a valid baseline.
- Missing helper metadata, host-consumer, or publication-handoff files means
  the local harness is incomplete and should be fixed before asking for more
  gameplay logs.

## Future Work

Mode A desktop capture outside Flutter still needs a native CLI that can run:

```text
selected window/display source
-> native WGC/window-GDI capture
-> scaler/canvas
-> diagnostics
```

Mode B now has a local Media Foundation encoder proof for the synthetic
D3D11 path. The next measurement step is the same encoder proof against live
BG3, then a dedicated WebRTC/LiveKit video source only after BG3 clears the
local encoder boundary. Mode C can add local WebRTC loopback later if
sender/receiver stats are needed
without Matrix/LiveKit.

The immediate game-capture publication step is BG3 validation of the local
encoder proof, still without reintroducing continuous CPU readback.

None of those future modes should change production stream behavior without a
separate plan and diagnostics-backed implementation pass.
