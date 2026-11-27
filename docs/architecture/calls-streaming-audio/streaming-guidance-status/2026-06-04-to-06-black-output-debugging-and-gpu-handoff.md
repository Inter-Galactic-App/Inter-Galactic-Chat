# June 4-6 Black-Output Debugging And GPU Handoff Proof

Date range: 2026-06-04 to 2026-06-06

Dated evidence history extracted from `../streaming-guidance-status.md`. Covers the Phase 4C/4D local encoder and WebRTC-source-handoff proof work, the black-output debugging chain (pre-I420/post-I420 proof boundaries, helper lifecycle fixes), the June 3 window-GDI/WGC backend comparison detail, and the June 4 Phase 3A/3B/4A/4A.5 shared-texture and publication-handoff probes.

---

- The first live Phase 4D attempt published black output even though native
  source stats showed BG3 frames flowing at roughly 35 FPS and scaling from
  2560x1440 to 1280x720. To avoid another speculative patch, the next debug
  build adds a pre-I420 proof boundary: native libwebrtc writes BMP proof
  frames plus luma/visibility markers from the exact frame about to be
  converted for WebRTC, and stream-test parsing now treats
  `game_capture_webrtc_source` markers as the authoritative capturer evidence.
  The refreshed patched `libwebrtc.zip` SHA-256 is
  `B8FC5B578CEE5CBAEDEB60A2372A9A6874DB2C67DA429A0538A211235ED84C40`;
  the Debug runner `libwebrtc.dll` SHA-256 is
  `98A632FD2D115705F34E7B9C34F3E02C2E1E77BF01DF24FD4D80AAA4396232DF`.
  A pre-I420 proof BMP from session `wrtcdffa991c767a3efe` was inspected and
  is visible, full-frame BG3, and color-correct at 1280x720. Next validation
  should run Smooth only and compare local/remote stream output against this
  proven pre-I420 source boundary before running Balanced or High.
- The follow-up Smooth live run still produced black output while sender stats
  showed frames being captured, encoded, and sent on a clean route. The latest
  implementation adds a post-I420 proof boundary and routes
  `game_capture_webrtc_source` native lines through WebRTC logging so reports
  can distinguish BGRA/R10-to-I420 conversion failure from a later
  WebRTC/encoder/receiver failure. Native libwebrtc rebuild passed and the
  patched artifact was refreshed to SHA-256
  `AF225F5CEDFA33CEFD97074E0C79E9BA04BDF1F8A41C5FF70153FB1B52DFA7B0`
  with staged DLL SHA-256
  `91667E088D2C24E70B59F99C321BF55BBDA1C2BC49688A9EFA9955B72E782E67`.
  Follow-up validation installed the artifact into Flutter WebRTC, confirmed
  the Debug runner DLL hash matches the staged DLL, ran Dart format and the
  focused stream-test runner tests, and rebuilt the Windows Debug app. The
  next evidence boundary is a single Smooth live BG3 game-hook validation that
  compares pre-I420 and `i420_proof` visibility.
- The June 5 follow-up Smooth live run narrowed the black-output failure
  again. Native proof files from the same session showed the first sampled
  frame was truly black, while a later pre-I420 proof was visible and
  color-correct BG3. The stream-test report also failed to preserve
  `game_capture_webrtc_source` markers and fell back to stale window-GDI
  evidence. The next debug build suppresses bounded startup black frames until
  the first visible game-hook frame, records `initialBlackSkipped` and
  `visibleSourceSeen`, writes a visible I420 proof when available, and treats
  game-hook native markers as priority diagnostics. Refreshed patched
  `libwebrtc.zip` SHA-256:
  `E30F5230290CF7891B425782A6AAD76C9CC5A6E3FAC919196F9BCBAD7E651A06`;
  Debug runner `libwebrtc.dll` SHA-256:
  `450DFABB6AB772DC3BA03F2F7EAE1743E2A1FF1494B63BE1A23B9BAB61AFF6B9`.
  The next validation is still one Smooth BG3 window test with the
  `game-d3d11-hook-experimental` backend, not a preset sweep.
- The next June 5 validation still rendered black on the receiver, but moved
  the boundary past native acquisition, scale, I420 conversion, and local H.264
  encoding. Fresh proof BMPs from the same run are visible/color-correct after
  I420 reconstruction, sender stats show H.264 output bytes on a clean route,
  and the remaining surprising evidence was lifecycle contamination: stopped
  presets left one-hour `intergalactic_game_capture_helper` sessions alive.
  The current Debug build fixes that boundary by explicitly removing/stopping
  manually published Windows screen-share video tracks in `stopScreenshare()`,
  treating those manual `screenShareVideo` publications as active local screen
  shares for stream-test/UI stop decisions, stopping them before LiveKit
  `setScreenShareEnabled(false)` can unpublish the publication, and by
  logging/hardening native helper shutdown, including helper termination after
  graceful-stop timeout.
  Refreshed patched `libwebrtc.zip` SHA-256:
  `1DAAE258A6D987783141910C4188173E383E18F1F478B5B0BEAC8A173EEBCB5C`;
  Debug runner `libwebrtc.dll` SHA-256:
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`.
- The follow-up Smooth validation still left the helper alive, but proved the
  app now finds and unpublishes the manual `screenshare` publication. The
  missing evidence was native `stop_capture`, so the newest Debug build stops
  the `LocalVideoTrack` before `removePublishedTrack(...)` for local
  screen-share video publications. This is an app-only rebuild with Debug Dart
  payload SHA-256
  `4228A5B91DE08068C64792F2C788011F165926FF39F6E4FF8FCCBCBEED77393C`;
  `libwebrtc.dll` remains
  `46702FC0DBDAF92ACD099EE013F91B00FE99A70C676F8F58670948D5DE584EAD`.
  Next validation should again start with one Smooth BG3 window test, then
  stop the share and confirm no `intergalactic_game_capture_helper` process
  survives before considering WebRTC frame submission or receiver rendering.
- The next 60-second Smooth BG3 validation cleared the black-output/lifecycle
  boundary enough to expose the current performance wall. The stream was
  visible and helper teardown was clean, but capture/encode/send all sat around
  15.6 FPS. `game_capture_webrtc_source` markers showed source 2560x1440,
  output 1280x720, copied=3474, submitted=965, `mapMs` about 41-49 ms, and
  `convertMs` about 17-19 ms, while the native Media Foundation encoder timing
  stayed low and transport stayed clean. The current debug build therefore
  GPU-scales the game-hook WebRTC source into the requested output-sized BGRA
  texture before staging readback, maps only the scaled frame, preserves the
  old full-source CPU path as counted fallback, and exposes `gpuScaled`,
  `gpuScaleFailures`, `cpuFallback`, and `gpuScaleMs` in the stream-test
  report. The first implementation used a D3D11 video-processor input view and
  failed on BG3 with `input_view_create_failed hr=0x80070057`; the fixed path
  now matches the proven helper approach by sampling the shared source through
  an SRV into a scaled BGRA render target. Local WebRTC-source smoke passed on
  the rebuilt Debug runner DLL against the synthetic D3D11 target with
  `gpuScaled=103`, `gpuScaleFailures=0`,
  `cpuFallback=0`, source `1920x1080`, output `1280x720`, visible proof
  `2/2`, visible I420 proof `1/1`, `mapMs=1.192 ms`, and
  `convertMs=1.005 ms`.
  Final patched `libwebrtc.zip` SHA-256:
  `CAD4ADF1A4CBBD49D058B08DF928BF9AD1C60557317FC7396EF275E02C4CB8C6`;
  final Debug runner `libwebrtc.dll` SHA-256:
  `0EC17B36B313B9C38FBE3AC6229B10D5ACB3A1300805378168AAEAF8D8C0B6EE`.
  Next validation is one Smooth 720p BG3 live test.
- The June 3 BG3 window tests changed the active comparison target again for
  this specific source. App default, Native default, and WGC-only all observed
  the `wgc` capturer and stayed around 12-14 FPS with native p95/max gaps near
  132-144 ms / 201-246 ms. The debug "DirectX" selection observed
  `window-gdi`, not a DirectX window capturer, and reached roughly 20 FPS with
  native p95/max gaps near 61-64 ms / 126-158 ms. Network, bitrate, encoder
  timing, resolution, and crop state stayed clean. Treat this as evidence that
  the current WGC window path is map/readback-acquisition limited for BG3,
  while the legacy WebRTC window-GDI path is the best current debug comparison.
  It is still not enough to change the product default without resolving source
  rebind/startup risk and display-path behavior.
- The same June 3 reports exposed a report-classification bug: rare WGC
  frame-pool empty/reuse/null counts could label the dominant WGC substage as
  `frame_pool_empty` even when those counts were tiny and the measured blocking
  `map_texture` timing dominated the frame budget. The runner now only reports
  frame-pool/startup wait as dominant when the miss/sleep ratio is substantial
  or no timing evidence exists, and the top summary includes the observed
  native capturer so `window-gdi` versus `wgc` is visible immediately.
- A follow-up June 3 run with the corrected reports made the product change
  concrete. Smooth App default/WGC still observed `wgc`: App default sent about
  15.2 FPS with p95/max native gaps around 125/206 ms and WGC `map_texture`
  averaging about 52 ms; WGC-only sent about 13.6 FPS with p95/max around
  131/229 ms and `map_texture` around 61 ms. The DirectX/window-GDI run
  observed `window-gdi`, sent about 18.6 FPS, cut p95/max native gaps to about
  65/154 ms, kept native encoder timing around 2 ms average, and still had
  clean 0% loss / roughly 3 ms RTT. Normal Windows window/game App default now
  uses that DirectX/window-GDI path. Explicit Native default and WGC-only
  remain test options for WGC work; display sharing remains on native default.
- Post-promotion validation confirms the default split but not the final FPS
  goal. The 16:19 BG3 window App default report observed effective
  `directx-only` / `window-gdi` and correct 1280x720 / 1920x1080 output, but
  Smooth and Balanced still sent only about 16.8-18.0 FPS with native p95/max
  frame gaps around 67-72 ms / 160-167 ms. Native encoder timing stayed low
  at about 2-4 ms and transport remained clean, so the remaining window-source
  limiter is window-GDI capture acquisition/cadence. The 16:22 display control
  correctly stayed WGC and remained `map_texture` limited at about 14 FPS.
  Parsed window-GDI backend substages were added instead of
  retuning bitrate, codec, LiveKit, or fallback.
- The window-GDI substage pass adds native `Inter Galactic window GDI frame
  timing` markers and stream-test parsing for window-rect/visibility checks,
  DC acquisition, frame allocation, `PrintWindow(PW_RENDERFULLCONTENT)`,
  fallback `PrintWindow`, `BitBlt`, crop, cleanup, and owned-window work. JSON
  and Markdown now expose `GDI Substage`, a `window-GDI substage markers`
  coverage row, and a `fix window-GDI substage` recommended action when
  `native_capture_limited` has this evidence.
- The refreshed debug build contains the rebuilt native DLL for this pass:
  patched `libwebrtc.zip` SHA-256
  `117ADD0864A6D2038BBF570673B383BF158041D45C42AB49396CF0F267620372`,
  rebuilt/debug `libwebrtc.dll` SHA-256
  `6E564D425EEE78E6B4D436B1D8711038560EF2D95C239EBB89037827422BEB0E`.
- The latest diagnostics-only follow-up adds Capture Cause Attribution to
  stream-test reports and a native timer for dirty-region analysis. The next
  BG3 window logs should now say whether the remaining 55-60 ms native capture
  call is dominated by full source acquisition size, blocking acquire/callback
  wait, CPU readback/copy, dirty-region processing, frame lifetime/lock
  synchronization, or full-frame copy before downscale. Refreshed patched
  `libwebrtc.zip` SHA-256:
  `73A81A9A1CAF482C392E29F39B50C93F7BA469A133DEC4D5F9E6E3EA71F5D396`;
  rebuilt/debug `libwebrtc.dll` SHA-256:
  `5A62E1B1DD53538341C23C2B2B681644EA0742DEE0404F3B6E49B3CBCACE547D`.
- The next pass is still diagnostics-only and targets the same native
  acquisition boundary. Debug stream tests can now cycle window-GDI capture
  methods for window sources: current `PW_RENDERFULLCONTENT` first, plain
  `PrintWindow` first, `BitBlt` first, and `BitBlt` only. Native markers,
  stream-test JSON, and Markdown record the requested/applied mode, final
  producer method counts, and black/low-variance frame counts. This should
  prove whether the slow `PrintWindow(PW_RENDERFULLCONTENT)` call is avoidable,
  whether `BitBlt` is fast but invalid for game windows, or whether the
  remaining limiter is outside the method order. The refreshed test build has
  patched `libwebrtc.zip` SHA-256
  `7BAD628EC7EE79B90E16DEA97C0FEE7F63458FC4DF8F0836CF3B8ABA29B46EDD` and
  debug `libwebrtc.dll` SHA-256
  `80A8B74975FB78747026D143FB6A0FE7A421E9AD8A920F6984994C79D088D2AB`.
- The first method-comparison run proved that the non-default methods are not
  viable for the tested BG3 2560x1440 window. Plain `PrintWindow` first and
  both `BitBlt` modes improved nominal FPS but produced pointer-only/black
  output; native counters showed black/low-variance frames dominating those
  rows. The report classifier now marks those rows as
  `invalid_capture_output` so future score comparisons do not promote them.
  The only currently valid window-GDI method for this source remains
  full-content `PrintWindow`, and its 44-45 ms native substage cost is the
  concrete limiter to fix or avoid.
- The June 4 Phase 3A follow-up changed the optional D3D11 game-capture probe
  from a blocking pre-preset step into a concurrent initial-preset measurement.
  Probe-only runs still avoid LiveKit publishing, but normal stream-test runs
  now compare local Present cadence against the active WGC/window-GDI sender
  cadence in the same time slice. This does not publish hook frames or change
  stream profiles, capture defaults, codec, fallback, LiveKit, or native
  capture behavior.
- The June 4 Phase 3B follow-up adds a host shared-texture consumer to the same
  debug-only probe. The hook publishes shared D3D11 texture ring handles and
  latest-frame metadata through a shared-state mapping/event; the helper opens
  those textures from the host side and reports consumed frames, missed frames,
  host frame age, consumer gaps, open failures, and optional proof readback.
  This proves or disproves the shared-texture handoff before any LiveKit
  publication work. It still does not alter normal WGC/window-GDI publishing or
  stream profiles.
- The June 4 Phase 4A follow-up adds a local publication-handoff probe, still
  debug-only and still outside LiveKit. The helper reads the latest opened
  shared D3D11 texture, contain-fit scales it into a preset-sized BGRA buffer,
  paces output to the first tested preset target, and reports readback, scale,
  total handoff timing, output FPS/gaps, visible buffer counts, paced drops,
  and requested/source/output dimensions. This proves whether the hook path can
  produce publication-shaped local frames before implementing the real Phase 4B
  WebRTC/LiveKit source.
- The first Phase 4A runtime report sharpened the split. The normal BG3
  window sender still measured about 16 FPS with clean network, fast native
  encoder timing, correct scaling, and window-GDI `print_full` as the concrete
  limiter. The D3D11 probe attached to the same source, observed about 50
  Present FPS, opened all host shared-texture slots, consumed 899 frames, and
  had no hook-copy/drop problem. `publication-handoff.json` was missing because
  the helper failed before finishing the handoff result writer/teardown path;
  the follow-up patch fixes the handoff p95 percentile bug, hardens percentile
  normalization, extends the runner watchdog, and logs helper shutdown phases.
- The next Phase 4A runtime report proved the writer/teardown repair and made
  the handoff bottleneck concrete. The helper produced visible 1280x720 output
  from the 2560x1440 BG3 backbuffer, but only at about 10.7 FPS because it
  read back the full source texture and then CPU-scaled into the target buffer.
  The helper now measures a GPU-side contain-fit scale into the preset-sized
  BGRA output before staging readback, and stream-test reports call a visible
  below-target handoff `slow` rather than `healthy`.
- The post-GPU-scale Phase 4A.5 BG3 report improved handoff cadence but did
  not clear the target. Present cadence stayed healthy, GPU scale timing was
  effectively free, and output remained visible, but the scaled-output staging
  readback still held output to about 16 FPS with p95/max readback spikes
  around 30/67 ms. The remaining game-capture handoff question is therefore
  scaled staging/readback and buffer cadence, not BG3 Present, hook copy,
  texture sharing, GPU scale math, encoder, network, LiveKit, or receiver.
- The deterministic D3D11 capture-target follow-up is implemented and
  documented in `docs/architecture/calls-streaming-audio/game-capture-test-target.md`. Use it for repeatable
  log-output, source-selection, report-parser, and pipeline verification before
  asking for another BG3 run. BG3 should remain the stress/compatibility case
  for 10-bit backbuffers, real game window behavior, and real gameplay load.

