# RNNoise Tuning Baseline

Status: Microphone noise-suppression rollback baseline
Date: 2026-07-03
Last reviewed: 2026-07-03

This file records the desktop RNNoise behavior so the app has a clear rollback
target while Enhanced DeepFilterNet is the app-facing Windows baseline.
RNNoise remains relevant for Windows rollback/control comparisons and for the
macOS native microphone path until a platform-specific Enhanced backend is
implemented.

Enhanced DeepFilterNet support layers are intentionally outside this RNNoise
rollback baseline. The Windows baseline can be smoke-tested with optional
post-DeepFilterNet `Transient click guard` and `Hush voice isolation` toggles,
but those layers must be evaluated against Enhanced DeepFilterNet controls, not
as scalar RNNoise tuning.

## Rollback Hybrid Behavior

- RNNoise is desktop-native and fail-open on Windows and macOS. If the native
  plugin is unavailable, not initialized, released, or the capture callback
  format is unsafe, mic audio continues through the normal WebRTC capture path.
- WebRTC echo cancellation and noise suppression stay enabled. RNNoise is an
  additive native post-capture gate, not a replacement for WebRTC cleanup.
- The app requests 48 kHz mono capture when RNNoise is enabled, but the native
  processor can resample valid 10 ms callbacks into RNNoise's 48 kHz / 480
  sample reference frame and then resample back.
- Multichannel capture is downmixed to mono for RNNoise and copied back across
  channels after processing.
- Windows and macOS share the same `RnnoiseCaptureProcessor` and Dart FFI
  status contract. Windows installs through the patched Flutter WebRTC custom
  audio processor hook; macOS installs through `flutter_webrtc`
  `AudioManager.capturePostProcessingAdapter`.
- Device-raw WASAPI sidecar capture is Windows-only. macOS diagnostics record
  the hook-stage WAVs and report the WASAPI sidecar as unsupported.

## Baseline Native Constants

- Reference VAD speech threshold: `0.90`
- Speech grace: `20` frames, roughly `200 ms`
- Closed gate gain: `0.03`
- Impulse VAD ceiling: `0.96`
- Impulse input RMS floor: `0.006`
- Impulse peak floor: `0.012`
- Impulse crest factor floor: `5.0`
- Gate transition: smoothed linear ramp across the current capture frame

## Baseline Diagnostics

- `frames` counts processed RNNoise frames.
- `bypassed` counts frames intentionally left unmodified because the plugin was
  disabled, unavailable, unsafe, or produced suspicious output.
- `gated` counts frames attenuated by the VAD or impulse gate.
- `resampled` counts native resampler uses.
- `gate` reports the last gate reason, applied gain, VAD threshold, grace
  frames, recent VAD average, and low/mid/high VAD buckets.
- `signal` reports latest VAD, input/output RMS and peak, output ratio, and
  detected WebRTC sample scale.
- `guards` reports format mismatch, suspicious output, speech collapse, and the
  app-side native health heuristic.

## Rollback

- User-level rollback: set the RNNoise preset to `gentle`, which must preserve
  the constants and smoothed close behavior listed above.
- Code-level rollback: restore the native constants and remove the configurable
  tuning bridge while leaving the existing fail-open WebRTC hybrid path intact.
