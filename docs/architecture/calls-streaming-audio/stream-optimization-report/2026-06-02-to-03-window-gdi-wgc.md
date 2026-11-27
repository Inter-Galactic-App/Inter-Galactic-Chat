# 2026-06-02 To 2026-06-03 Window GDI And WGC Evidence

Status: historical evidence archive
Extracted from `../stream-optimization-report.md` during the 2026-06-14 oversized-document split. The evidence body below is preserved from the working report at split time.

## 2026-06-03 Window-GDI Method Comparison Diagnostics

- The first BG3 2560x1440 window comparison run validated the diagnostic
  strategy and ruled out the tempting faster paths for this source. The current
  full-content `PrintWindow(PW_RENDERFULLCONTENT)` path was the only mode that
  produced visible game content. Plain `PrintWindow` first, `BitBlt` first, and
  `BitBlt` only produced pointer-only/black output in visual smoke.
- The parsed counters match the visual report. Plain `PrintWindow` produced
  `black_frames=1404/1404` in Smooth and `1367/1388`-class black/low-variance
  output in Balanced. `BitBlt` paths produced all or nearly all black/low-
  variance frames despite higher nominal FPS. Full-content `PrintWindow`
  remained valid with low/zero black-frame counts but averaged about
  44-45 ms in the native GDI substage, keeping the stream capture-limited.
- Stream-test scoring now treats rows with dominant black plus low-variance
  GDI output as `invalid_capture_output`. Those rows lose usable FPS/resolution
  credit and receive a max downgrade penalty so reports do not rank
  pointer-only output above the slower valid path.
- The latest evidence still points at native window-GDI acquisition/cadence:
  frame gaps and 55-60 ms capture calls persist while scaling, bitrate,
  Media Foundation H.264 encode timing, transport, and receiver policy remain
  clean.
- This pass adds a debug-only window-GDI capture-method selector for stream
  tests. Window-source tests on the DirectX/window-GDI path can now cycle the
  current full-content `PrintWindow` order, plain `PrintWindow` first,
  `BitBlt` first, and `BitBlt` only.
- Native diagnostics now log the requested/applied `capture_mode`, final frame
  producer counts (`final_print_full`, `final_print_fallback`, `final_bitblt`,
  `final_none`), and black/low-variance frame counts. This is the minimum
  evidence needed to distinguish a real faster path from a fast path that
  returns black, stale, or low-information frames.
- Stream-test JSON and Markdown include the requested GDI mode, parsed final
  method mix, validity counters, and top-level `GDI Mode` summary column. The
  classifier/docs were updated so `BitBlt` cannot be promoted solely because
  it is faster; it must also produce usable frames.
- No stream tuning changed in this pass. Bitrate, profiles, codec,
  fallback/adaptation thresholds, LiveKit options, default display behavior,
  and normal non-test publish settings are unchanged.
- Validation passed: Dart format, focused `stream_test_runner_test.dart`,
  focused Flutter analyze for touched streaming files, native
  `ninja -C out-release\Windows-x64 libwebrtc`, patched-libwebrtc install,
  and `flutter build windows --debug --no-pub`.
- Refreshed artifact hashes: patched `libwebrtc.zip` SHA-256
  `7BAD628EC7EE79B90E16DEA97C0FEE7F63458FC4DF8F0836CF3B8ABA29B46EDD`;
  rebuilt/debug `libwebrtc.dll` SHA-256
  `80A8B74975FB78747026D143FB6A0FE7A421E9AD8A920F6984994C79D088D2AB`;
  debug `flutter_webrtc_plugin.dll` SHA-256
  `95DC70B4CFF691C9E3599ED4E7DBED14D61E6E9A078852C8F9B267D52EBAD0B2`.

## 2026-06-03 Capture Cause Attribution Diagnostics

- The stream-test runner now includes a `Capture Cause Attribution` section in
  Markdown and `captureCauseAttribution` JSON under native diagnostics. The
  matrix answers whether the 55-60 ms capture call is coming from full source
  acquisition size, blocking acquire/callback wait, CPU readback/copy,
  dirty-region processing, frame lifetime/lock synchronization, or
  full-frame copy before downscale.
- The native wrapper now times updated-region analysis as
  `avg_updated_region_ms` and `max_updated_region_ms` in the existing
  `Inter Galactic desktop capture frame timing` marker. This separates
  dirty-region bookkeeping cost from dirty-region shape.
- The attribution report is additive and diagnostics-only. No stream profiles,
  bitrate, codec, LiveKit settings, backend defaults, dirty-region mode,
  fallback thresholds, scaler behavior, or capture scheduling changed.
- Validation passed: focused `stream_test_runner_test.dart`, focused Flutter
  analyze, bundled native `ninja ... libwebrtc`, patched-libwebrtc install,
  and `flutter build windows --debug --no-pub`.
- Refreshed artifact hashes: patched `libwebrtc.zip` SHA-256
  `73A81A9A1CAF482C392E29F39B50C93F7BA469A133DEC4D5F9E6E3EA71F5D396`;
  rebuilt/debug `libwebrtc.dll` SHA-256
  `5A62E1B1DD53538341C23C2B2B681644EA0742DEE0404F3B6E49B3CBCACE547D`.
- Next logs should inspect the new attribution matrix before any tuning. If
  dirty-region analysis is tiny while `print_full`, `bitblt`, WGC `map`, or
  source-capture wait dominates, optimize that concrete stage first.

## 2026-06-03 Window-GDI Substage Diagnostics

- The post-promotion BG3 window tests proved App default now reaches the
  intended `window-gdi` path, but Smooth and Balanced still miss 30 FPS because
  capture/source acquisition averages about 50-60 ms while native encoder,
  transport, resolution, and crop state remain clean.
- The next diagnostic layer is now implemented as an additive native marker:
  `Inter Galactic window GDI frame timing`. It splits top-level window-GDI
  capture into window-rect/visibility checks, DC acquisition, frame allocation,
  `PrintWindow(PW_RENDERFULLCONTENT)`, fallback `PrintWindow`, `BitBlt`, crop,
  cleanup, and owned-window enum/capture/composite timings.
- Stream-test JSON and Markdown parse the new marker into `nativeDiagnostics`,
  add a `GDI Substage` column, add a `window-GDI substage markers` coverage row,
  and let `native_capture_limited` recommend `fix window-GDI substage` when
  that evidence is present.
- This pass does not tune bitrate, profiles, codec, LiveKit, fallback,
  backend defaults, dirty-region policy, or native capture behavior. The next
  BG3 window logs should show whether the active limiter is `print_full`,
  fallback `PrintWindow`, `bitblt`, crop, owned-window work, or a failure path.
- Validation for this pass: focused `stream_test_runner_test.dart`, focused
  Flutter analyze, bundled `third_party\ninja\ninja.exe -C
  out-release\Windows-x64 libwebrtc`, patched-libwebrtc install, and
  `flutter build windows --debug --no-pub` passed outside sandbox. The
  refreshed patched `libwebrtc.zip` SHA-256 is
  `117ADD0864A6D2038BBF570673B383BF158041D45C42AB49396CF0F267620372`, and the
  rebuilt/debug `libwebrtc.dll` SHA-256 is
  `6E564D425EEE78E6B4D436B1D8711038560EF2D95C239EBB89037827422BEB0E`.

## 2026-06-03 Window-GDI Default Promotion

- The corrected June 3 reports repeated the BG3 2560x1440 window Smooth test
  one at a time. App default and WGC-only both observed `wgc`;
  DirectX/window-GDI observed `window-gdi`.
- WGC remained the active limiter: App default sent about 15.2 FPS with
  p95/max native gaps around 125/206 ms and WGC `map_texture` around 52 ms
  average; WGC-only sent about 13.6 FPS with p95/max around 131/229 ms and
  `map_texture` around 61 ms average.
- DirectX/window-GDI was visually and metrically better for this window source:
  about 18.6 sent FPS, p95/max native gaps around 65/154 ms, native encoder
  timing around 2 ms average, correct scaled output, 0% packet loss, and roughly
  3 ms RTT.
- Normal Windows window/game App default now resolves to the DirectX/window-GDI
  backend. Display shares stay on the patched native default, and explicit
  Native default/WGC-only stream-test modes remain available for WGC diagnosis.
  This is a capture-backend policy change only; bitrate, profile FPS, codec,
  LiveKit publish options, adaptive fallback, and native libwebrtc behavior are
  unchanged.

### Post-Promotion Validation

- The follow-up Roaming reports
  `stream-test-2026-06-03T16-19-26-719449Z.{json,md}` and
  `stream-test-2026-06-03T16-22-19-806080Z.{json,md}` validated the intended
  policy split. A BG3 window App default share now reports effective backend
  `directx-only` with observed capturer `window-gdi`; a display App default
  control remains on native default/WGC.
- The policy is correct, but the window-GDI path is still native-capture
  limited. Smooth encoded 1280x720 and sent about 16.8 FPS; Balanced encoded
  1920x1080 and sent about 18.0 FPS. Capture, encode, and send FPS moved
  together, while native p95/max gaps stayed around 72/160 ms for Smooth and
  67/167 ms for Balanced.
- Native Media Foundation H.264 timing was not the limiter: native encoder
  timing averaged about 2.3 ms for Smooth and 3.7 ms for Balanced. WebRTC's
  aggregate encode-time values around 56-60 ms therefore reflect upstream
  capture/frame-delivery cadence, not hardware encoder overload.
- Window-GDI auto dirty-region shape was effectively full-scene motion:
  Smooth reported about 23,840 dirty rects with 97.2% average area and
  Balanced reported about 26,902 dirty rects with 97.5% average area. That
  makes dirty-region fragmentation or window-GDI acquisition internals the next
  evidence boundary.
- The display control is still a separate WGC problem: Smooth display App
  default observed `wgc`, sent about 14 FPS, had native p95/max gaps around
  130/223 ms, and reported dominant WGC `map_texture` timing around 57 ms
  average. Do not interpret display-WGC results as evidence against the new
  window-GDI window policy.
- Parsed window-GDI backend substage diagnostics are now implemented as the
  next evidence layer before tuning profiles again. The current evidence rules
  out bitrate, packet loss, RTT, LiveKit fallback, resolution scaling,
  crop/stretch, and actual native encoder work for these runs.

## 2026-06-03 WGC Versus Window-GDI Evidence

- Fresh BG3 window stream-test reports compared App default, Native default,
  WGC-only, and the debug DirectX selection with Force full-frame dirty regions.
  App default, Native default, and WGC-only all observed the native `wgc`
  capturer and stayed around 12-14 FPS, with native p95/max frame gaps near
  132-144 ms / 201-246 ms.
- The debug DirectX selection observed `window-gdi`, not a DirectX window
  capturer, and performed visibly better: roughly 20 FPS with native p95/max
  gaps near 61-64 ms / 126-158 ms. Transport, bitrate, Media Foundation encoder
  timing, resolution, and crop state stayed clean, so this remains a capture
  acquisition/cadence problem.
- The WGC substage parser was corrected after these reports showed tiny
  frame-pool empty/reuse/null counts masking the real timing culprit. Rare
  frame-pool misses no longer dominate the report when blocking `map_texture`
  timing consumes the frame budget. The top stream-test summary now includes
  the observed native capturer so `wgc` versus `window-gdi` is visible without
  digging into the native marker table.
- No streaming behavior changed in this pass. The next backend investigation
  should compare WGC map/readback behavior with the legacy window-GDI path and
  resolve whether a safer window-capture default or targeted WGC mitigation is
  viable.

## 2026-06-02 WGC Backend Substage Diagnostics

- Latest BG3 window runs from the app Roaming stream-test output confirmed the
  current limiter after the Force full-frame dirty-region default: Smooth App
  default with Force full-frame dirty regions held about 27.5 sent FPS at
  1280x720, while Balanced App default held about 26.7 sent FPS at 1920x1080.
  Transport stayed clean (0% packet loss, roughly 3 ms RTT), Media Foundation
  H.264 stayed fast (about 2.3 ms Smooth and 4.6 ms Balanced), and there was no
  WebRTC quality limitation.
- The same reports still showed visible-stutter-class native frame gaps:
  Smooth p95/max native intervals were about 70/171 ms, and Balanced p95/max
  intervals were about 83/208 ms. Native capture calls averaged roughly
  28-31 ms with wrapper-level `callback_entry` currently the dominant phase.
  Because the wrapper can only infer that bucket, the next evidence boundary is
  inside the concrete WGC backend rather than another bitrate/profile change.
- This pass instruments the native Windows Graphics Capture session itself.
  New `Inter Galactic WGC frame timing` markers split WGC `GetFrame`,
  `EnsureFrame`, and `ProcessFrame` into frame-pool empty/reuse counts,
  capturability misses, startup sleeps, texture resize/recreate counts, and
  timings for `TryGetNextFrame`, surface/texture lookup, content-size query,
  `CopySubresourceRegion`, blocking `Map`, row copy, monitor scale lookup, and
  zero-hertz comparison.
- The stream-test runner now parses those markers into JSON and Markdown. The
  Native Diagnostic Markers table includes a `WGC Substage` column, and
  `native_capture_limited` bottleneck evidence now reports the dominant WGC
  substage such as `map_texture`, `copy_rows`, `frame_pool_empty`, or
  `zero_hertz_compare`.
- Validation for this implementation pass: focused
  `stream_test_runner_test.dart` passed outside sandbox, and bundled
  `third_party\ninja\ninja.exe -C out-release\Windows-x64 libwebrtc` rebuilt
  the native DLL/import library successfully. The patched libwebrtc artifact
  was refreshed from the rebuilt output; previous ZIP SHA-256
  `79637D1D3A00442A7D586562D9B845ABB57CA5F39CDA2F67859BF31391DF1EC9`, new ZIP
  SHA-256 `531F8FAF9ADD54E31B88C8E9EEC45D75D494B3F840E673CA43CD720A2EC811A2`.
- The Windows debug build was refreshed after the active plugin cache was
  aligned with that artifact. Debug output path:
  `intergalactic/build/windows/x64/runner/Debug/InterGalactic.exe`; debug
  `libwebrtc.dll` SHA-256
  `FBE3E01DFA4BF217FF8E77199D88B9E8AA74523A954D58AECB815C531908E6EB`.

## 2026-06-02 Observed Capturer And Dirty-Region Mode Follow-Up

- The latest App default and Native default Roaming tests both kept clean
  transport, correct 720p/1080p encoded resolution, low native frame work, and
  low encoder timing, but still landed around 18-21 FPS with native source
  capture/acquire wait dominating. Dirty-region shape was mostly empty or tiny.
  Follow-up Auto versus Force full-frame tests showed Force full-frame improves
  the WGC window dirty-region path but does not remove all native p95/max
  capture gaps.
- The patched Windows desktop capturer now logs the actual
  `DesktopFrame.capturer_id` label (`wgc`, `directx`, `window-gdi`,
  `screen-gdi`, etc.) plus the active dirty-region mode in frame-size,
  pipeline, and timing markers. This prevents App default from being treated as
  a black box when WebRTC chooses a concrete backend internally.
- The stream-test runner now accepts a Windows-only Force full-frame dirty
  regions toggle. It disables updated-region detection for the capture options
  and reports full-frame dirty shape without changing source geometry, scaling,
  bitrate, codec, or LiveKit publish behavior. Normal Windows window/game
  shares on explicit Native default and WGC paths request Force full-frame
  dirty regions; display, App default after the window-GDI promotion,
  DirectX/window-GDI, and crop-diagnostic paths keep Auto.
- The stream-test report now exports a dominant native capture phase from the
  existing wrapper-level buckets (`source_capture`, `callback_entry`,
  `capture_callback`, `post_callback`, or `unaccounted_wait`). This is the
  deepest available split in the vendored libwebrtc wrapper checkout; true WGC
  backend-internal wait/copy timing still requires instrumenting the concrete
  upstream backend source when it is available.
- App default remains native capture-backend policy, not encoder policy. The
  screen-share profile/publish path still chooses the encoder, and Windows
  normal presets continue to prefer hardware-first H.264. This earlier
  conclusion was superseded by the corrected June 3 BG3 reports: App default
  now resolves Windows window/game sources to DirectX/window-GDI, while display
  shares remain on native default.
- Initial debug-build validation exposed a stale artifact boundary: the
  rebuilt `libwebrtc.zip` DLL contained the current native implementation, but
  the packaged `rtc_desktop_capturer.h` header still lacked
  `SetWindowsCaptureDirtyRegionMode`, while the generated Flutter WebRTC bridge
  already called it. The artifact stage has been refreshed from the current
  native include tree and rebuilt output, and the installer now validates that
  dirty-region API before installing the zip.
- Validation now includes native `ninja ... libwebrtc`, patched-libwebrtc
  installation into the Flutter WebRTC cache, and
  `flutter build windows --debug --no-pub`. Follow-up app changes passed
  focused `stream_test_runner_test.dart` and focused Flutter analyze for the
  touched streaming files outside sandbox.

## 2026-06-02 Dirty-Region Shape Diagnostics

- The latest Smooth BG3 window run confirmed the active limiter is still native
  capture acquisition/cadence: transport, resolution, encode path, and sender
  scaling looked clean, but native p95/max frame gaps matched the poor visual
  motion. Average FPS alone remains too optimistic for this path.
- The patched Windows desktop capturer now augments the existing frame-timing
  marker with dirty-region shape fields: updated-region rect count, max rect
  count, average and max dirty-area ratio, full-frame update count, and tiny
  update count. This should tell the next run whether source acquisition is
  repeatedly copying full frames, seeing tiny/no-op updates, or dealing with
  fragmented dirty regions before our scale/encode boundary.
- The debug stream-test runner parses those fields into JSON and the Markdown
  Native Diagnostic Markers table as `Dirty Shape`. Bottleneck notes for
  `native_capture_limited` now include the dirty-region shape label, and the
  scoring path gives p95/max frame gaps enough weight to distinguish two bad
  capture backends instead of flattening both to the same low score.
- Validation passed: Dart format, focused
  `test/client/components/voip/stream_test_runner_test.dart`, focused Flutter
  analyze for the stream-test runner/test files, native
  `{DEPOT_TOOLS}\ninja.bat -C out-release\Windows-x64 libwebrtc`,
  patched-libwebrtc installer, and
  `flutter build windows --debug --no-pub`.
- Rebuilt artifact:
  `artifacts/libwebrtc/windows-hardware-h264/libwebrtc.zip`
  with ZIP SHA-256
  `79637D1D3A00442A7D586562D9B845ABB57CA5F39CDA2F67859BF31391DF1EC9`; the
  debug build's `libwebrtc.dll` SHA-256 is
  `95D1C6CF115B11FCB80961816A18D98D479FD1CA1D51E1936892270875941A77`.
