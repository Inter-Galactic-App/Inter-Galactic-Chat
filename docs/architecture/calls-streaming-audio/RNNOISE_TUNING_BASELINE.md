# RNNoise Tuning Baseline

Status: AUDIO-owned microphone noise-suppression rollback baseline
Date: 2026-05-05
Owner: AUDIO for RNNoise behavior; DOCUMENTATION for structure
Last reviewed: 2026-06-16 by DOCUMENTATION

This file records the pre-tuning Windows RNNoise behavior so the app has a
clear rollback target while short transient and keyboard suppression are tuned.

## Current Hybrid Behavior

- RNNoise is Windows-first and fail-open. If the native plugin is unavailable,
  not initialized, released, or the capture callback format is unsafe, mic audio
  continues through the normal WebRTC capture path.
- WebRTC echo cancellation and noise suppression stay enabled. RNNoise is an
  additive native post-capture gate, not a replacement for WebRTC cleanup.
- The app requests 48 kHz mono capture when RNNoise is enabled, but the native
  processor can resample valid 10 ms callbacks into RNNoise's 48 kHz / 480
  sample reference frame and then resample back.
- Multichannel capture is downmixed to mono for RNNoise and copied back across
  channels after processing.

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
