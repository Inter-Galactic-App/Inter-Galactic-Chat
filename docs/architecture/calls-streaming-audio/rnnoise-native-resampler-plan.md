# RNNoise Native Resampler Plan

Status: AUDIO-owned microphone capture-format plan
Owner: AUDIO for RNNoise behavior; DOCUMENTATION for structure
Last reviewed: 2026-06-16 by DOCUMENTATION

This note tracks the Windows microphone-format work needed to make RNNoise
reliable when WebRTC does not deliver RNNoise's preferred native frame shape.

## Goal

RNNoise expects 48 kHz mono audio in 480-sample, 10 ms frames. Inter Galactic
requests that capture shape when Windows RNNoise is enabled, but field logs
show WebRTC can still deliver 16 kHz / 160-frame callbacks. The app must either
receive true 48 kHz capture or bridge valid 10 ms callbacks into RNNoise's
shape without damaging speech quality.

## Current Bridge

The Windows processor accepts valid 10 ms mono/downmixed callbacks even when
they are not already 48 kHz / 480 frames. The 2026-05-26 popping fix replaced
the frame-local conversion path with persistent resampler state and a
fail-open FIFO bridge. The capture callback now converts the current source
format into normalized mono, feeds a stateful source-to-48 kHz resampler,
processes exact 480-frame RNNoise blocks when enough samples are available,
then feeds a stateful 48 kHz-to-source resampler before writing the final
output back in the original sample scale.

Current bridge properties:

- stateful interpolation with persistent phase across callbacks
- bounded initial dry/fail-open behavior while the FIFO gathers enough samples
- clean `RNNoise only` processing by default while popping is validated
- original capture sample scale is preserved
- invalid/native-mismatch buffers still fail open
- diagnostics expose mode, source/target rates, frame counts, use counters,
  resampler underruns/overruns, callback timing, sample deltas, split
  input/output clipping, final-output limiter adjustments, non-finite counters,
  RNNoise state resets, and active pipeline mode
- clean RNNoise output now passes through a small final-output safety limiter
  before returning audio to WebRTC. This is not the residual/tuned gate. A
  low-VAD non-speech burst guard softly saturates high-peak or high-delta
  frames and clamps the guarded samples to a small ramp from the previous
  emitted sample before the generic output limiter, so raw non-speech
  transients cannot become clipped or rail-jump output pops while the base
  RNNoise path is being validated.
- the clean path also has a narrow post-speech residual guard. It arms only
  after hot/clipped speech input, and then only adjusts quiet-input frames when
  RNNoise output remains unusually loud relative to the quiet mic input. The
  adjustment ramps from the last emitted sample toward a small soft ceiling so
  delayed speech-tail artifacts are reduced without restoring the old
  residual gate or broadly attenuating typing/silence.
- the clean path also fails open to the dry mic frame when the current input is
  clipped/discontinuous, when RNNoise output becomes materially louder than the
  input, or when a low-VAD output burst is detected. This preserves the
  existing hybrid safety model: WebRTC built-in suppression can still clean the
  dry path, and RNNoise does not get to reshape distorted microphone-front-end
  bursts into harder-to-suppress artifacts.
- the 48 kHz-to-capture-rate leg applies a small stateful anti-alias smoother
  when the capture callback is below 48 kHz. Field WAVs from 2026-05-29 showed
  the 48 kHz RNNoise output was cleaner than the final 16 kHz writeback, so the
  downsample path now filters before the stateful linear resampler and the
  final de-click guard uses a tighter delta ceiling.
- developer-only explicit WAV capture can write raw input, RNNoise 48 kHz
  input, RNNoise 48 kHz output, and final output for short local diagnostics
- WAV stage capture is aligned per processed callback. The recorder writes the
  selected stages under one lock, reports callback count rather than per-stage
  writes, and stops accepting samples when each stage reaches the requested
  duration at its own sample rate.
- The in-call Call Diagnostics panel exposes the same developer-only WAV
  capture action used by VoIP settings. The in-call action auto-stops and
  flushes the 10-second native capture so affected users can gather WAVs
  without leaving the call panel. The capture remains local-only and is not
  bundled into bug reports automatically.
- RNNoise-off captures are diagnostic-only dry captures. When capture is
  active but RNNoise processing is disabled, the hook now records raw input,
  dry 48 kHz reference input/output, and final dry output instead of returning
  before the recorder sees any samples. These dry WAVs are native-stage
  evidence, not post-WebRTC/remote-heard audio; WebRTC's built-in suppression
  can still remove dry-path interference later in the call pipeline.
- A developer-only capture-front-end override is available in VoIP developer
  settings. It can toggle WebRTC echo cancellation, WebRTC noise suppression,
  auto gain, high-pass filtering, typing-noise detection, the 48 kHz mono
  request, and whether the microphone volume constraint is sent. The normal
  user path keeps WebRTC echo cancellation/noise suppression on, auto gain off,
  and RNNoise additive/fail-open. Active calls refresh microphone capture when
  this full capture-profile signature changes, and the app logs sanitized
  constraint summaries for default device capture, LiveKit call join, and
  mid-call microphone refresh.
- Microphone capture volume is normalized to `0.0..1.0` before it reaches
  WebRTC constraints. At `100%` or above, the media `volume` constraint is
  omitted instead of sending a no-op or boost value, because field WAVs showed
  raw app-capture clipping before RNNoise and the old app preference allowed
  values above unity.
- An offline replay harness now lives at
  `plugins/intergalactic_noise_suppression/tools/rnnoise_replay/`. The harness
  builds a tiny native console target around the same Windows
  `RnnoiseCaptureProcessor`, decodes a supplied audio sample with `ffmpeg`,
  replays it as 10 ms callbacks at 16 kHz and 48 kHz, writes processed output
  plus the four diagnostic stage WAVs, and exports JSON/Markdown summaries.
  `run_rnnoise_replay.ps1` accepts an explicit audio sample path plus
  `speech=0-7.14,keyboard=7.14-14.27,clicks=14.27-21.41` style segment
  ranges, scores speech preservation/noise reduction/artifact safety, and can
  compare `off`, `clean`, and named tuned candidates before another live-call
  iteration.

This bridge is intentionally conservative. It lets real calls test whether
stateful RNNoise processing removes popping without turning the residual gate
back on. It should not be treated as the final tuned noise gate until live WAV
captures and fixture tests show the base path is clean.

## Remaining Production Requirements

The current path covers the main stateful-resampler requirement, but future
production hardening still needs:

- fixture-backed native tests for 8 kHz, 16 kHz, 32 kHz, 44.1 kHz, and 48 kHz
  inputs
- comparison against a higher-quality polyphase/windowed-sinc or vetted
  permissively licensed resampler if linear interpolation is audibly weak
- measured callback allocation and lock behavior under sustained LiveKit call
  load
- a deliberate restore of `tuned_gate` presets only after clean RNNoise is
  pop-free

Future implementation options if quality still falls short:

- vendor a small permissively licensed native resampler such as SpeexDSP after
  license review
- implement a small polyphase windowed-sinc resampler with persistent state
- use platform APIs only if they can run predictably on WebRTC's real-time
  audio path and avoid hidden allocations

## Test Plan

Native tests should be added before treating the resampler as final:

- impulse response preserves timing and does not ring excessively
- sine sweeps avoid obvious aliasing across supported input rates
- speech fixtures remain intelligible and do not pump/click across frame
  boundaries
- 16 kHz / 160-frame callbacks produce exactly 48 kHz / 480-frame RNNoise input
  and return exactly 16 kHz / 160-frame output
- sample-scale preservation keeps normalized and PCM16-scale float paths stable
- invalid buffers fail open without muting microphone audio

Manual validation should compare RNNoise off, clean hybrid RNNoise with WebRTC
suppression, and later `tuned_gate` developer experiments using a real LiveKit
call plus server loopback. Passing logs should show increasing processed
frames, no speech-collapse guard, no callback budget misses under normal use,
no clipping/non-finite spikes, and either true 48 kHz capture or
`stateful_linear` diagnostics without sustained resampler underruns/overruns.
If a pop remains, compare the renamed hook stages and the split clip/limiter
counters: a `webrtc_hook_input.wav` spike points at microphone/WebRTC-front-end
capture, an `rnnoise_output_48k.wav` spike that is absent from
`final_to_webrtc.wav` points at the safety limiter doing its job, and a
`final_to_webrtc.wav` spike points at the remaining hot callback/writeback path.
`webrtc_hook_input.wav` is not device raw; use `device_raw_wasapi.wav` from the
tap-order sidecar to decide whether the issue exists before WebRTC. Dry
RNNoise-off WAVs can still show native-stage noise that the LiveKit loopback
does not contain after WebRTC suppression. For 16 kHz captures, final-output
deltas should now be lower than the earlier 0.60 and 0.35 safety-limit
ceilings. Low-speech burst captures should show no new clipping, no exact 0.35
rail-jump steps, final-output max delta near or below the soft-guard ramp, and
the resampler diagnostics should show anti-alias use. Speech-tail captures
should compare hook input to RNNoise output/final output: if hook speech is hot
or clipped and the input becomes quiet while output stays elevated, the
post-speech residual guard or dry fallback should prevent the delayed residual
from reaching final output without changing clean typing or silence captures.
If final output matches the dry hook path, compare loopback or remote-heard
audio before treating the dry WAV noise as a regression, because WebRTC
suppression may still remove that dry-path interference after the native stage.

If `webrtc_hook_input.wav` remains the first bad stage, use the developer
tap-order scenario picker and identity hook mode to isolate WebRTC capture
constraints before tuning RNNoise further. The current matrix compares RNNoise
off/default capture, identity with the same constraints, clean RNNoise with the
same constraints, no volume constraint, no 48 kHz request, WebRTC noise
suppression off, echo cancellation off, and AGC off. Each capture should record
whether the native callback is still 16 kHz / 160 frames, whether hook input is
clipped, whether `device_raw_wasapi.wav` is clean, whether loopback/remote audio
is audibly clean, and the logged constraint summary. Keep any private sample
logs or root-cause notes in maintainer-only storage unless they are scrubbed for
publication.

Before the next live-call tuning pass, run the offline harness against the
latest supplied sample:

```powershell
& 'plugins\intergalactic_noise_suppression\tools\rnnoise_replay\run_rnnoise_replay.ps1' `
  -InputPath '<path-to-scrubbed-sample.m4a>' `
  -Modes off,identity,clean `
  -TunedProfiles baseline,balanced,strong `
  -OutputRoot '<local-output-folder>'
```

The 2026-05-29 `Sample.m4a` replay is a clean test fixture with speech first,
keyboard second, and clicks last. In clean mode, 48 kHz replay had no resampler
use or underruns, no clipping, and max output delta around `0.23`, but keyboard
and click sections were only lightly reduced. `tuned_gate` suppressed clicks
far more strongly in offline replay, but that path remains withheld from
normal presets until popping and speech-tail behavior are proven safe.

The 2026-05-29 candidate sweep showed all 48 kHz tuned candidates artifact-safe
on the supplied fixture with no limiter samples or resampler issues.
`tuned-strong` scored highest
(`79.5` overall, `87.4` speech, `61.4` noise, `100.0` safety), while
`tuned-balanced` was close (`79.0` overall). This is evidence for the next
candidate set, not approval to restore tuned gate as the normal live default;
affected-user WAV validation is still required.
