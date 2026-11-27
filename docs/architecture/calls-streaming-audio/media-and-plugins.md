# Media and Plugins

Status: Stable media/plugin architecture map
Last reviewed: 2026-06-27

## Purpose

This document covers the parts of the app that handle:

- attachments and media upload
- GIF search and send
- link previews
- custom emoji and stickers
- plugin-backed native capabilities
- current noise suppression plugin behavior

Use it as the first review map when changing media or plugin-backed features.

## Architecture Summary

Media behavior is shared-domain first, with platform specifics isolated behind either:

- conditional imports
- platform runner code
- explicit plugin packages

Relevant current code areas:

- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/components/gif/matrix_gif_component.dart`
- `intergalactic/lib/client/matrix/components/emoticon/...`
- `intergalactic/lib/client/matrix/components/url_preview/...`
- `intergalactic/lib/ui/molecules/gif_picker.dart`
- `intergalactic/lib/ui/molecules/message_background_settings.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`
- `intergalactic/lib/utils/message_background/`
- `plugins/intergalactic_noise_suppression/`
- `plugins/intergalactic_windows_share/`
- `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_service.dart`
- `intergalactic/lib/client/components/voip/share_session/`
- `docs/architecture/calls-streaming-audio/rnnoise-native-resampler-plan.md`

## Media Categories

### Attachments

Current ownership starts in:

- `intergalactic/lib/client/room.dart`
- `intergalactic/lib/client/matrix/matrix_room.dart`
- `intergalactic/lib/client/matrix/matrix_attachment.dart`
- timeline event attachment parsing under `intergalactic/lib/client/matrix/timeline_events/...`

When changing attachments, inspect:

- upload preparation
- MIME handling
- thumbnail handling
- render-time attachment parsing
- fallback behavior for unsupported or malformed files

Composer picker rules:

- on Android and iOS, the message composer `Gallery` action should use the
  platform photo library picker for both photos and videos
- keep a separate `File` action for documents, arbitrary files, and non-gallery
  media such as loose audio files
- do not add a second generic `Media` action beside `Gallery`; it creates
  duplicate mobile paths and unclear platform behavior

### Spoilers

Text spoilers use Matrix markdown `||spoiler||` / `data-mx-spoiler` formatted
HTML. The plain `body` fallback should not expose hidden spoiler content; use a
neutral `[spoiler]` or `[spoiler: reason]` fallback when building Matrix
message events.

Attachment spoilers are an Inter Galactic/de-facto media behavior, not a
stable core Matrix media field. Image sends may carry `chat.intergalactic.spoiler`
and `fi.mau.spoiler` metadata so Inter Galactic and compatible clients can hide
the media preview until reveal. Keep parsing older/local spoiler markers for
compatibility, but do not rely on a Matrix-wide standard media spoiler key.

Bubble-mode timeline rendering should keep media, URL previews, and reaction
chips outside the text bubble. Bubbles frame text; images and previews are their
own message surfaces.

### Emoji Rendering

Native Unicode emoji should render through `TextUtils.nativeEmojiTextSpans`
anywhere rich text is split into inline spans. The helper intentionally combines
the generated emoji regex with a newer-codepoint heuristic so Android-sent emoji
that are newer than the bundled regex still move onto platform emoji fonts on
iOS, Android, desktop, and Linux. Because this helper runs in shared app code,
platform font selection must import Flutter foundation explicitly rather than
relying on transitive Material exports. Do not bypass this helper for mixed
message-body text, linkified text, composer preview text, forum labels, or
other inline chat surfaces unless that surface is rendering a custom Matrix
emoticon or a code/preformatted block.

### Photo Stacks

Photo stacks are currently a render-time grouping feature, not a custom Matrix
send format.

Current ownership starts in:

- `intergalactic/lib/ui/molecules/timeline_events/events/timeline_event_view_message.dart`
- `intergalactic/lib/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart`

Rules:

- group only adjacent image-only messages from the same sender
- keep Matrix wire compatibility by leaving each image as its own `m.image`
  event
- do not group replies or thread heads, because hiding those child messages
  would hide important interaction surfaces
- reacted images may stay in the stack; render compact reaction indicators
  below the stack instead of splitting a reacted photo back out
- preserve each stacked photo's source `TimelineEvent` and `ImageAttachment`
  so lightbox actions, reactions, deletion, and downloads target the visible
  photo's original Matrix event
- the swipeable gallery is local UI state and should not affect send/retry,
  redaction, edit, or Matrix relation behavior
- honor the caller's `previewMedia` flag; when previews are disabled, do not
  render inline thumbnails and use a non-preview placeholder until the user
  explicitly opens media

### Message Backgrounds

Message backgrounds are local appearance media, not Matrix event content.

Current ownership starts in:

- `intergalactic/lib/config/preferences.dart`
- `intergalactic/lib/utils/message_background/`
- `intergalactic/lib/ui/molecules/message_background_settings.dart`
- `intergalactic/lib/ui/organisms/chat/chat_view.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/appearance_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/room/appearance/room_appearance_settings_page.dart`

Rules:

- render message backgrounds on mobile and desktop local-image builds; web and
  other unsupported targets should keep returning no image through the
  conditional `MessageBackgroundManager` stub
- store selected images in app support storage, not Matrix account data, room
  state, or message events
- use `preferences.messageBackgroundImagePath` for the device default
- use the `room_message_backgrounds` preference map keyed by `Room.localId` for
  room overrides
- treat persisted background paths as recoverable local references: older
  builds stored absolute app-support paths, but mobile OS updates can move the
  app container while preserving the support data, so render/delete paths must
  also look for the same managed background filename under the current
  `message_backgrounds` support directory
- room overrides win over the default; clearing the room value returns to the
  default
- use local preferences for background opacity and sent/received bubble colors;
  do not write these styling choices to Matrix account data, room state, or
  message events
- default background opacity is dynamic until explicitly set: bubbled timelines
  default to a fully visible image, while non-bubbled timelines default to a
  dimmer image for readability
- room-specific opacity and sent/received bubble colors are local overrides keyed by
  `Room.localId` and must fall back to the local default when cleared
- keep the legacy single bubble-color key as a fallback for users who set a
  bubble color before sent/received colors were split
- keep message bubble preset labels generic and product-neutral; colors may be
  inspired by common messaging palettes, but the UI should not use third-party
  product names for presets
- evict the local image cache when replacing or deleting a stored background so
  changes appear immediately

### Message Effects

Message effects are Matrix message events exposed through composer affordances.
They remain user-triggered send actions, not local-only display preferences.

Current ownership starts in:

- `intergalactic/lib/client/matrix/components/message_effects/matrix_message_effects_component.dart`
- `intergalactic/lib/client/matrix/components/command_component/matrix_command_component.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`

Rules:

- keep slash commands working for users who know them
- expose common fun effects through the composer effects menu so users do not
  need to discover slash commands first
- desktop shows an effects icon beside the emoji picker; mobile opens the same
  menu from long-press on the mic/send button
- message effects such as confetti, rainbow, snowfall, and space invaders
  send through their existing command paths when text is present
- hidden and loud are composer text transforms: hidden wraps the draft in
  `||spoiler||`, and loud prefixes the draft with `### `
- cute emoji effects use `msgtype: im.fluffychat.cute_event` with `cute_type`
  values such as `cuddle`, `googly_eyes`, and `hug`
- do not add new persistent preferences for the menu; this is a send surface
  over existing Matrix event behavior

### Link Previews

Current ownership starts in:

- `intergalactic/lib/client/matrix/components/url_preview/...`

When changing previews, inspect:

- fetch policy
- unsafe HTML/content handling
- CORS/platform-specific fallbacks
- cache and retry assumptions
- rendering surfaces in UI

### GIFs

Current ownership starts in:

- `intergalactic/lib/client/matrix/components/gif/matrix_gif_component.dart`
- `intergalactic/lib/ui/molecules/gif_picker.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`
- `intergalactic/lib/ui/organisms/chat/chat.dart`

Current visible design:

- search is relay-first when `GIF_API_BASE_URL` is configured for the build or
  a user saves a relay URL locally
- public builds default `GIF_API_BASE_URL` to the managed Klipy relay configured
  for the release; direct Klipy provider credentials stay server-side in the
  relay
- the last non-empty bundled relay URL is remembered locally as a previous-build
  fallback so an app update that omits `GIF_API_BASE_URL` does not silently
  drop GIF search for users who were already on that managed relay path
- direct KLIPY search is available only when the user saves a local KLIPY API
  key; public builds should not embed a shared provider key by default
- local GIF setup is stored in local preferences through `GifApiKeyStore`
  (`gif_search.relay_base_url` and `gif_search.klipy_api_key`), not Matrix
  account data
- send uploads the selected image payload into Matrix
- MIME and payload validation matter
- picker UI is expected to surface recoverable send failures

When changing GIFs, inspect:

- `intergalactic/lib/config/gif_api_key_store.dart`
- provider response parsing
- relay URL normalization and fallback from relay to local direct key
- payload validation
- upload/send path
- forum/thread rendering if the change affects sticker-like media roots

### Custom Emoji and Stickers

Current ownership starts in:

- `intergalactic/lib/client/matrix/components/emoticon/...`
- `intergalactic/lib/client/components/emoticon/...`
- `intergalactic/lib/client/matrix/matrix_room.dart`

Relevant concerns:

- room/account/space scope
- image pack usage mapping
- sticker compatibility mode
- send payload correctness
- picker/render fallback behavior

### Voice Messages

Current ownership starts in:

- `intergalactic/lib/client/components/voice/voice_recorder_bridge.dart`
- `intergalactic/lib/ui/molecules/message_input.dart`
- `intergalactic/android/app/src/main/kotlin/chat/intergalactic/app/MainActivity.kt`
- `intergalactic/ios/Runner/AppDelegate.swift`

Rules:

- keep the Dart bridge contract platform-neutral; native recorders should
  return `path`, `name`, `mime_type`, optional `size`, and optional
  `duration_ms`
- record mobile voice messages as AAC `.m4a` / `audio/mp4` attachments so the
  existing Matrix upload/send path can stay shared
- preserve the recorder-provided MIME type during `PendingFileAttachment`
  resolution; Android `.m4a` files can otherwise be detected as `video/mp4`
  and sent or rendered through the video attachment path
- render playable audio attachments through the compact in-message voice bubble
  in `intergalactic/lib/ui/molecules/audio_player/audio_player.dart`, keeping
  video/file fallback surfaces for non-audio attachments
- parse legacy or malformed Matrix events with an audio file extension such as
  `.m4a` as audio even if the stored MIME type is `video/mp4`, so older Android
  voice messages can recover into the voice bubble UI when their filename
  identifies them as audio
- keep permission prompts and recorder lifecycle in the platform runner, not in
  Matrix room logic
- cancellation must clean up active native recorders and pending permission or
  startup work so composer teardown does not leave a microphone capture running
- unsupported platforms should keep the recorder UI hidden and fail safely from
  the bridge

### Soundboard

Current ownership starts in:

- `intergalactic/lib/client/components/soundboard/...`
- `intergalactic/lib/client/matrix/components/soundboard/...`
- `intergalactic/lib/ui/pages/settings/categories/space/space_soundboard_settings_page.dart`
- `intergalactic/lib/ui/organisms/soundboard/call_soundboard_panel.dart`

Rules:

- sound definitions are Matrix room state on the containing space
- per-sound volume is shared metadata on the sound state event and should be
  applied before local per-device soundboard volume, so uploaded clips can be
  normalized for the whole server without removing each user's local control
- sound play requests are Matrix room events scoped back to the owning space
  and must be validated before playback
- do not discard a whole timeline batch only because Matrix marked it
  `limited`; use timestamp and nonce guards to prevent backfill/replay while
  still allowing fresh live play events through reconnect or join syncs
- if a live play event arrives before the local VoIP session is registered, the
  receiver may retry briefly before giving up
- the local temp-file cache is bounded to 14 days, 64 files, and 64 MiB.
  Cleanup runs after the persistent soundboard player has stopped the previous
  sound and protects the file about to be opened, so retention cleanup should
  not remove an active playback backing file.
- per-user join-sound preferences for the current user are private per-room
  account data, not member-writable room state
- do not set `SoundboardEventTypes.userState` to member-writable room state;
  that would let regular users spoof other users' soundboard settings
- failed sound playback should log and surface a recoverable UI failure instead
  of dropping an unhandled async error

## Plugin Boundaries

Plugins live under `plugins/` so native/runtime-risk code is isolated from the main app package.

Use a plugin boundary when a feature needs:

- FFI
- native OS APIs
- custom native lifecycle management
- bundled third-party native source or binaries

Do not bury plugin-specific assumptions directly in generic room/message/UI code if the behavior needs separate init, shutdown, or unsupported-platform behavior.

## Current Noise Suppression Plugin Guidance

Current plugin:

- `plugins/intergalactic_noise_suppression/`

Current shared app entry points:

- `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_service.dart`
- `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart`
- `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/voip_settings/voip_settings_page.dart`
- `RNNOISE_TUNING_BASELINE.md`
- `docs/architecture/calls-streaming-audio/rnnoise-native-resampler-plan.md`

What matters for future work:

- Windows now uses Enhanced DeepFilterNet as the app-facing microphone
  suppression baseline after the 2026-07-03 group-call smoke. It runs in the
  native callback while WebRTC echo cancellation and WebRTC noise suppression
  stay enabled. The runtime uses a 60 dB DeepFilterNet attenuation cap and a
  loud-speech protection guard that blends limited dry microphone audio back
  into loud, speech-shaped frames when the model over-attenuates them.
  Diagnostics expose `dfProtect`, `dfWet`, and `dfAtten` for rebuilt call
  validation. On Windows, normal Voice & Video settings offer an opt-in
  `Loud-speech guard stability` switch alongside Hush. Off preserves the
  original per-frame guard; on adds hysteresis and a five-frame hold when the
  model heavily attenuates a loud input. It defaults off and remains available
  without Developer Mode. `dfProtectStable` in Call Diagnostics and
  `guard-on/off` in WAV capture folder names record the active native mode
  for A/B reports. This is a test control, not a claim that loud-speech
  flutter is resolved in calls.
- Android now has a platform-specific Enhanced DeepFilterNet backend packaged
  in `plugins/intergalactic_noise_suppression/android/`. The plugin bundles
  `libdf.so`, `libintergalactic_noise_suppression.so`, and the
  DeepFilterNet3 ONNX model for `arm64-v8a`, `armeabi-v7a`, and `x86_64`, then
  attaches to the `flutter_webrtc` capture post-processing callback when the
  Enhanced pipeline is selected. Android call diagnostics report the platform,
  requested WebRTC AEC/NS state, hardware AEC/NS availability, and native
  backend status so rebuilt device smoke can prove the real capture path.
- The currently bundled Android `libdf.so` can abort during `df_create` instead
  of returning an error, so the
  plugin writes an on-disk attempt guard before calling it and refuses the call
  outright if that guard cannot be persisted. Both the guard and the extracted
  model archive are stamped with the app build (`versionName+versionCode`):
  a guard is honoured only for the build that wrote it, and a model whose stamp
  does not match the running build is re-extracted from the APK asset before
  `df_create` runs. That pairing is what makes the guard recoverable - a build
  change grants one retry *and* refreshes the model that retry runs against, so
  a fix shipped in either the code or the model takes effect. Do not make the
  guard unconditional again, and do not reuse the extracted archive across
  builds without the stamp check.
  **Testing caveat:** "build" here means the fingerprint `versionName+versionCode`,
  which comes from `pubspec.yaml`. A rebuilt APK with an *unchanged* version
  produces an identical fingerprint, so neither the guard nor the model is
  refreshed. A tester who rebuilds a fix locally without bumping the version
  will therefore see the old broken behaviour and report the fix as ineffective
  when it is working as designed. Validate on device by bumping the version
  between installs, or by clearing app data. On a correct refresh the plugin
  logs `Re-extracting the DeepFilterNet model: on disk from build X, running Y`.
- The vendored libDF source now catches model-load errors and Rust panics at
  `df_create` and returns null. The bundled Windows `df.dll` and Android
  `libdf.so` predate that source change; the fail-closed behavior needs a
  provenance-approved rebuild and native runtime proof before it can be claimed
  for an installed app. Windows Hush recovery source also bounds the start of
  its per-sample gain ramp by the current frame's peak-safe gain.
- the Windows DeepFilterNet path also has opt-in post-model support layers for
  smoke testing. `Transient click guard` targets short keyboard/mouse spikes and
  reports `dfClickOn`, `dfClick`, `dfClickSamples`, and `dfClickGain`. `Hush
  voice isolation` targets background voices/speaker bleed and reports
  `dfHushOn`, `dfHush`, `dfHushBypass`, `dfHushReason`, `dfHushSnr`,
  `dfHushRecover`, `dfHushGain`, `dfHushIn`, and `dfHushOut`. A bounded
  post-Hush gain recovery stage runs after successful Hush frames and before the
  final safety limiter so the support layer can be smoke-tested without
  globally quieting speech. Recovery is capped and only restores toward the
  pre-Hush frame level; it is not a general AGC.
  Both are off by default so testers can compare Enhanced DeepFilterNet alone,
  each support layer independently, and both together.
- RNNoise remains the rollback/control path on Windows and Android, and the
  native microphone suppression path on macOS until a platform-specific
  Enhanced backend is implemented there.
- macOS has a narrow build escape path in
  `plugins/intergalactic_noise_suppression/macos/Classes/rnnoise_capture_processor_bridge.cpp`:
  the macOS bridge provides fail-open `DeepFilterNetRuntime` symbols so the
  shared `RnnoiseCaptureProcessor` can compile and link while Enhanced
  DeepFilterNet remains Windows-only. The escape path always reports the
  runtime as unavailable/not initialized and leaves RNNoise as the macOS native
  suppression path. Do not move this stub into the shared Windows CMake path or
  treat it as a macOS Enhanced backend.
- the app must fail open when the plugin is unavailable
- enabling the preference turns on the native capture hook while keeping
  WebRTC's built-in echo cancellation and noise suppression active for the
  current baseline and rollback presets. Native suppression is additive, not
  the sole cleanup layer.
- the affected-user RNNoise compatibility mode is the explicit exception to
  the default hybrid capture profile. It keeps RNNoise active, keeps WebRTC
  echo cancellation on, keeps AGC off, keeps the 48 kHz RNNoise reference
  request on, disables WebRTC's built-in noise suppression for new mic
  captures, and forces the native processor onto a clean/no-fast-close RNNoise
  path instead of `tuned_gate`. This mode exists for microphones that pop in the
  normal hybrid path; it must remain opt-in until rebuilt affected-user smoke
  proves speech quality and transient suppression.
- Windows and macOS share the same native `RnnoiseCaptureProcessor`, FFI API,
  pipeline modes, status JSON shape, and hook-stage WAV diagnostics. Windows
  enters through the patched Flutter WebRTC custom post-processor; macOS enters
  through `flutter_webrtc`'s
  `AudioManager.capturePostProcessingAdapter`.
- user tuning remains preset-driven in preferences. During the 2026-05-26
  popping fix, enabled Windows RNNoise temporarily mapped all presets to the
  native `clean_rnnoise` pipeline. After the 2026-05-30 WebRTC hook scale fix
  was user-validated clean in loopback, normal `balanced`, `strong`, and
  developer `custom` presets again use the native `tuned_gate` pipeline.
  `gentle` intentionally stays on `clean_rnnoise` as the quick local rollback
  path if the tuned gate bothers a user's microphone.
- current measured presets keep `gentle` at the documented baseline. `balanced`
  is the default moderate gate (`vad=0.91`, `grace=14`, `closedGain=0.01`,
  `transient=0.72`); `strong` is the keyboard/tap-heavy profile (`vad=0.95`,
  `grace=10`, `closedGain=0.001`, `transient=1.0`). Future tuning should update
  the Dart preset model, replay script, tests, and this doc together.
- offline replay reporting treats `off` and `identity` as controls only, not
  production suppression candidates. Run summaries from
  `plugins/intergalactic_noise_suppression/tools/rnnoise_replay/run_rnnoise_replay.ps1`
  now split controls, production presets, and experimental candidates; candidate
  scoring gates speech/artifact safety while still rewarding real noise
  reduction. The 2026-06-11 `Sample.m4a` replay review kept `balanced` as the
  practical tuned preset, `strong` as aggressive, and `gentle` as rollback
  pending human listening and LiveKit loopback validation. Do not promote scalar
  custom candidates or disable RNNoise from offline controls alone.
- the call dock owns the in-call voice quick menu on Windows and macOS. The
  mic button continues to mute/unmute the current call, while a separate full
  circular voice button beside the camera opens cascading input-device,
  input-profile, and output-device menus, input/output volume sliders, an
  input-level meter, Push to Talk and Deafen toggles, and a Voice Settings
  shortcut. Device and volume rows write the same Voice and Video preferences
  used by the settings page and call manager. The input-level meter refreshes
  from session stats on visualizer ticks, and LiveKit visualizer samples are
  clamped as 0.0-1.0 values so normal speech below the old threshold can still
  animate the meter. Push-to-Talk mute/unmute requests are guarded as recovered
  call-state operations so tearing-down or stale sessions do not surface as
  unhandled app-zone crash reports.
  Input Profile choices are backed by the existing noise-suppression
  preference/service path: `Standard` disables native suppression, the Windows
  default/migrated baseline can select Enhanced DeepFilterNet, `gentle`,
  `balanced`, and `strong` remain RNNoise rollback presets, and developer mode
  or an already-selected custom profile can expose `custom`.
  Compatibility/capture-profile changes remain in Voice Settings because they
  affect how new microphone captures are created.
- custom tuning must flow through the scalar native `configure(...)` API: VAD
  threshold, speech grace frames, closed gain, transient sensitivity, and
  fast-close enabled. Do not replace this with ad hoc JSON settings.
- the native Windows processor reads RNNoise's returned VAD probability. The
  residual/transient gate runs only when the selected preset maps to the
  internal `tuned_gate` pipeline. Fast-close no longer applies the closed gain
  to an entire callback instantly; it ramps down over a short native window so
  keyboard/click suppression can start quickly without a hard frame-edge click.
- residual/transient gating should use a low non-zero closed gain; hard
  frame-level muting can create audible clicks when suppression opens or
  closes. Presets that enable fast-close may drop gain quickly when closing,
  but opening should stay smoothed so speech does not click or clip.
- impulse-like inputs such as snaps or key taps can receive high RNNoise VAD,
  so transient gating should consider input peak, sample-to-sample delta, and
  crest factor in addition to low VAD confidence. The transient sensitivity
  preference parameterizes this behavior, and likely typing/tap bursts may hold
  the gate closed briefly across adjacent frames. Measured sent-in chair squeak
  samples showed that non-speech mechanical sounds can be high-VAD too, so the
  tuned gate may override speech protection only for narrow high-peak,
  high-delta, high-crest harsh transients. Do not hardcode a single
  microphone's keyboard threshold without exposing diagnostics and a rollback
  path.
- speech protection is intentionally separate from the close threshold. A
  current speech-like frame can protect speech grace even when the selected
  preset has a higher VAD close threshold, and high-RMS or high-confidence
  speech transients should override the typing/tap gate so deep voices and
  plosives are not treated as keyboard bursts.
- suspicious-output bypass is for invalid output or speech-like frames that
  collapse to near-silence; a low output ratio by itself can be successful
  RNNoise attenuation and should not force fail-open
- the shared native processor also has a transient-amplification watchdog for
  affected microphones where RNNoise starts clean and later produces popping.
  The watchdog compares each normalized hook input frame to the RNNoise output
  frame. If RNNoise turns moderate input into a much larger peak/delta/RMS
  transient, that callback returns the dry hook frame. Repeated guarded frames
  reset RNNoise state and raise the existing suspicious-output/state-reset
  counters so diagnostics can prove whether the guard fired.
- clean RNNoise final output has a small post-model safety limiter/de-click
  guard. A low-VAD burst guard softly saturates only non-speech frames that
  already have a high processed peak or sharp processed delta, then clamps the
  guarded frame to a small sample-to-sample ramp anchored to the last emitted
  sample. This is separate from the residual/tuned VAD gate and does not
  restore frame muting. The generic limiter still caps model overshoot and
  extreme sample-to-sample jumps before writing back to WebRTC, including dry
  fallback frames. That limiter is input-delta aware: it should not introduce a
  sharper final-output jump than the incoming hook frame unless the input
  itself is already a large transient. Raw clipping by itself should not force
  dry fallback while the raw app/WebRTC capture frontend is under
  investigation; fallback is for RNNoise/resampler failure, materially
  amplified RNNoise output, or low-VAD output bursts. Diagnostics keep separate
  input clip, output clip, and limiter-adjusted sample counts so future WAV
  captures can distinguish raw microphone/front-end transients from RNNoise
  output artifacts.
- when WebRTC delivers 16 kHz capture despite the 48 kHz request, the clean
  path now low-pass smooths RNNoise's 48 kHz output before downsampling back to
  the capture rate. This anti-alias step is deliberately separate from the VAD
  gate; diagnostics expose `antiAlias` uses on the resampler line so future
  logs prove whether the 16 kHz bridge was active.
- the native processor must preserve WebRTC's incoming sample scale. The
  Flutter WebRTC custom post-processor receives `AudioBuffer::channels()`
  samples in WebRTC FloatS16 scale on Windows, and the macOS adapter feeds the
  same shared processor contract. The native hook must treat hook input as
  PCM16-scale float unconditionally, normalize only for RNNoise/diagnostic
  math, and write back in FloatS16 scale. Do not use peak-based scale
  inference; quiet PCM frames can look like normalized floats and become
  full-scale artifacts.
- WebRTC's built-in echo cancellation and noise suppression stay enabled while
  RNNoise runs unless the affected-user compatibility mode is enabled. Current
  Windows RNNoise tuning is hybrid/additive because field logs showed valid
  native processing could still let transient clicks, taps, and keyboard noise
  through if WebRTC cleanup was fully disabled. Compatibility mode is narrower:
  it is for microphones where the RNNoise+WebRTC-NS stack itself appears to
  introduce popping, and it still keeps RNNoise, AEC, AGC-off, typing
  detection, and the 48 kHz request while moving native processing to the clean
  no-fast-close path.
- Dart verification must also fail open when RNNoise reports speech-like input
  but near-silent output, even before the native suspicious-output state has
  recovered or tripped
- LiveKit microphone tracks are created with capture constraints fixed at that
  moment. If a future RNNoise mode changes whether WebRTC built-in suppression
  should stay on, active LiveKit sessions must refresh/recreate the microphone
  track when that profile changes
- Direct Matrix calls still capture the microphone once when the call is
  answered. Until that path grows the same recapture hook as LiveKit calls,
  changing RNNoise/WebRTC capture controls during a direct call requires
  restarting the direct call to guarantee the new capture constraints are used.
- VoIP settings include a local mic check labeled as local processed capture.
  It must use `NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints()`
  through the same helper path as call microphone capture so WebRTC echo
  cancellation, WebRTC noise suppression, AGC-off behavior, and any RNNoise
  reference-format request are tested together. Local microphone volume is a
  capture constraint input to this same helper path, so changing it affects new
  or restarted capture and restarts the local mic check when active. It is not
  a replacement for the in-call server audio loopback, which remains the
  end-to-end SFU path.
- the VoIP settings and in-call diagnostics readouts should expose the native
  reason, active preset/tuning values, processed/bypass/gated frame counters,
  resampler use, input scale, input/output peaks, callback timing, budget
  misses, sample deltas, split input/output clipping, final-output limiter
  adjustments, non-finite counts, resampler underruns/overruns, pipeline mode,
  diagnostic WAV-capture counters, and guard flags before deeper native tuning
  work
- the VoIP Developer diagnostics surface also exposes an `Enhanced
  DeepFilterNet` selector/status path. On Windows,
  the same native `deepfilternet` processor is the promoted baseline and the
  status reports runtime/frame counters, model presence, fallback labels, and
  whether call-room processing is proven. If the runtime is unavailable, the
  call path falls open to Standard behavior. RNNoise compatibility mode remains
  a separate rollback/affected-user diagnostic path.
- VoIP Developer diagnostics include `Transient click guard` and `Hush voice
  isolation` toggles for DeepFilterNet smoke. Leave both off for baseline
  comparison, then enable click guard, Hush, and both together to test whether
  keyboard/mouse spike suppression and background-voice isolation improve
  without speech damage.
- developer WAV capture records `webrtc_hook_input.wav`,
  `rnnoise_input_48k.wav`, `rnnoise_output_48k.wav`, and
  `final_to_webrtc.wav` atomically for each processed callback. The hook-input
  file is not raw device capture; it is the buffer handed to the native
  WebRTC/RNNoise hook. The reported capture count is callback count, not four
  per-stage writes, and capture stops accepting samples when each stage reaches
  the configured duration at its own sample rate so 16 kHz hook/final WAVs do
  not outlive the 48 kHz RNNoise stage. The `final_to_webrtc.wav` file is the
  native hook output returned into the WebRTC audio pipeline, not a guaranteed
  recording of what a remote listener hears after WebRTC's built-in suppression,
  encoding, transport, and playback.
- developer tap-order diagnostics add an `identity` hook mode beside `off`,
  `clean_rnnoise`, and `tuned_gate`. Identity installs the same native hook path
  but copies input to output unchanged and records stats/stages without RNNoise,
  resampling, limiter, gain, gates, or filters. If identity is noisy, investigate
  capture constraints, WebRTC frontend processing, hook format, or WAV writing
  before tuning RNNoise.
- when tap-order WAV capture is started from VoIP settings or Call Diagnostics,
  the Windows plugin can also record a sidecar `device_raw_wasapi.wav` from the
  selected microphone or the default communications microphone. This capture is
  outside the WebRTC hook and is used only for developer comparison against
  `webrtc_hook_input.wav`. macOS has no WASAPI sidecar; its native status must
  report that path as unsupported while still writing hook-stage WAVs. Sidecar
  worker failures should be reported through native status instead of
  terminating the app process. Native conversions of Windows endpoint/source
  identifiers to UTF-8 must use explicit input lengths that exclude the null
  terminator; allocating `length - 1` and then asking `WideCharToMultiByte` to
  write the null-terminated `length` can fail fast with `0xc0000409` during
  capture startup.
- the same developer WAV capture can be started from VoIP settings or the
  in-call Call Diagnostics panel. It remains local-only: stopping capture writes
  `capture-manifest.json` and per-stage metadata in the diagnostics folder, but
  the app no longer opens an Audio WAV tests report flow or submits WAV/audio
  artifacts through bug reports. The hook-only crash isolation path proved
  stable after folder labels were capped, so both surfaces now request the full
  stage mask again and start the WASAPI sidecar with the selected/default
  microphone. The folder label cap must stay in place because failing field
  folders had reached Windows long-path risk before the WAV filename was
  appended.
- the in-call Call Diagnostics panel also includes a developer-only RNNoise WAV
  batch runner. It cycles the frozen comparison matrix in order, captures each
  scenario into a labeled folder, shows progress/cancel state in the call, and
  restores the original RNNoise enablement, hook mode, and tap-order scenario
  when finished. This is only diagnostic orchestration; it must not tune
  suppression or alter normal call defaults.
- diagnostic capture folders append a self-describing label after the UTC
  timestamp: capture source, hook mode, tap-order scenario, RNNoise on/off
  preset, debug-override state, and WebRTC capture frontend toggles for echo
  cancellation, WebRTC noise suppression, AGC, high-pass, typing-noise
  detection, 48 kHz request, and volume constraint. The folder label is capped
  to keep native WAV file paths out of Windows long-path risk; each folder also
  writes `capture-metadata.txt` with the exact tuning values, requested stage
  mask, stage meanings, and frontend state so ambient-noise bundles can be
  correlated without relying only on saved call logs.
- Enhanced DeepFilterNet developer captures are reported as audio pipeline WAV
  sets, not RNNoise-only diagnostics. Labels include the selected pipeline plus
  the optional click-guard and Hush toggles. Windows Enhanced captures can write
  `deepfilternet_output.wav`, `speech_protect_output.wav`,
  `transient_guard_output.wav`, `hush_input_16k.wav`, `hush_output_16k.wav`,
  `hush_output.wav`, and `final_to_webrtc.wav` in addition to the raw WASAPI,
  WebRTC hook, and legacy RNNoise reference stages. `capture-metadata.txt`
  records those stage meanings: `hush_output.wav` is before post-Hush gain
  recovery, while `final_to_webrtc.wav` includes post-Hush recovery and final
  safety limiting. Bug-report bundles use the
  `audio_pipeline_diagnostic_wav_set` type while remaining local-only; WAV bug
  report upload is still disabled until transport/privacy limits are reopened.
- when RNNoise processing is disabled but a developer WAV capture is active,
  the native hook records a dry diagnostic comparison instead of creating an
  empty folder: hook input, dry 48 kHz reference input/output, and final dry
  output. This lets affected users capture RNNoise-off evidence without turning
  RNNoise processing back on. Dry/off WAVs can still contain front-end
  interference that is not audible in the LiveKit loopback when WebRTC's own
  noise suppression removes it later in the call pipeline.
- for non-48 kHz RNNoise-off/identity dry diagnostics, the hook records only
  the truthful WebRTC hook input and final dry output. It does not synthesize
  fake 48 kHz RNNoise reference stages from a dry callback. Clean RNNoise still
  uses the real stateful 48 kHz bridge when enabled, so `rnnoise_input_48k.wav`
  and `rnnoise_output_48k.wav` remain meaningful for enabled RNNoise captures.
- developer capture scenarios freeze the WebRTC audio constraint matrix for
  comparisons: RNNoise off/default, identity with the same normal constraints,
  RNNoise with the same normal constraints, RNNoise without the volume
  constraint, RNNoise without the 48 kHz request, RNNoise with WebRTC AGC
  explicitly on, RNNoise with WebRTC AGC, WebRTC noise suppression, or AEC
  individually disabled, plus identity and RNNoise with a minimal WebRTC
  frontend. The active preset still decides whether those RNNoise scenarios use
  `clean_rnnoise` (`gentle`) or `tuned_gate` (`balanced`, `strong`, `custom`),
  and metadata/status records the actual pipeline mode. The "same constraints"
  scenarios track the app's normal AGC-off capture defaults. The
  RNNoise-off/default diagnostic uses the identity hook so it can still record
  what WebRTC hands to the hook while leaving RNNoise processing disabled.
  These are diagnostics only; normal call defaults remain hybrid/fail-open.
- Audio Lab has a debug-only app audio-file source planner at
  `intergalactic/lib/client/components/voip/audio/noise_suppression/noise_suppression_audio_file_source.dart`
  with a CLI probe at `intergalactic/tool/audio_lab_file_source_probe.dart`.
  `tools/audio-lab/audio-lab.ps1 run-app-source --input <clip.wav>` invokes
  that app Dart code to parse WAV, downmix to mono, resample, chunk
  deterministic 10 ms frames, and write source frame indexes/timestamps. This
  does not change production microphone capture and is not yet a LiveKit
  publisher or receiver recorder.
- the Windows Flutter WebRTC bridge is patched during
  `intergalactic/scripts/install_patched_libwebrtc.ps1` so microphone capture
  constraints are not only parsed but also copied into `RTCAudioOptions` before
  `CreateAudioSource(...)`. This makes the app's AEC, WebRTC noise
  suppression, auto-gain, and high-pass choices match the actual WebRTC
  processing path. Direct WebRTC captures also duplicate those choices into
  legacy optional constraints because the Windows bridge only parses
  `mandatory` / `optional` audio maps.
- the iOS Flutter WebRTC bridge is patched during CocoaPods `post_install` in
  `intergalactic/ios/Podfile`. The patch is intentionally applied through
  Podfile hooks, not by hand-editing `.pub-cache`, so it survives pod
  regeneration. The current iOS patch makes WebRTC event-sink dispatch
  nil-safe during startup/shutdown races and makes ReplayKit broadcast socket
  teardown idempotent when streams or sockets are already gone. Do not remove
  this guard without a rebuilt iPhone startup smoke plus call/screen-share
  regression smoke.
- RNNoise's native model still operates on 48 kHz / 480-frame audio. If the
  WebRTC capture hook delivers a valid 10 ms frame at another sample rate, the
  desktop processor may resample into RNNoise's reference shape and then
  resample back to the capture shape. Diagnostics must show the resampler mode,
  source/target rates, and frame counts so field logs distinguish real 48 kHz
  capture from bridged 16 kHz capture.
- Flutter WebRTC may report WebRTC's internal `num_bands` value for the
  current sample rate, such as `3 band(s)` at 48 kHz, while the buffer pointer
  still refers to full-band channel data. The native guard should not treat
  positive band counts as a split-band format failure.
- The old native resampler bridge was a frame-local windowed-sinc safety step.
  The current popping-fix path uses a persistent stateful resampler and
  fail-open FIFO bridge for valid 10 ms non-48 kHz callbacks so RNNoise sees
  48 kHz / 480-frame blocks without clamping each callback edge independently.
  The tuned gate has been restored for normal non-gentle presets after the
  hook-scale fix passed loopback and offline replay validation; future native
  fixture hardening should still expand real speech/keyboard/click coverage.
  See
  `docs/architecture/calls-streaming-audio/rnnoise-native-resampler-plan.md`.

Review:

- plugin registration
- initialization and shutdown
- buffer and frame assumptions
- native pass-through guards for invalid, unexpected, or suspicious output
- CPU cost under sustained call load
- unsupported-platform behavior

## Windows ShareSession Guidance

Current plugin:

- `plugins/intergalactic_windows_share/`

Current shared app entry points:

- `intergalactic/lib/client/components/voip/share_session/`
- `intergalactic/lib/client/components/voip/webrtc_screencapture_source.dart`
- `intergalactic/lib/client/matrix/components/voip/matrix_voip_session.dart`
- `intergalactic/lib/client/matrix/components/voip_room/matrix_livekit_voip_session.dart`

What matters for future work:

- shared-content audio is not microphone audio
- RNNoise must stay on the mic path only
- shared audio failure should leave the screen share running video-only
- window/app audio needs validated window-to-process mapping before
  process-tree loopback is used
- the remaining publication work is a PCM-to-WebRTC/LiveKit adapter, not a
  mic-track mix
- `ShareSession` diagnostics should identify the source type, short source-id
  hash, resolved process id, requested audio mode, shared-audio state, and
  reason. Window/source titles are private and should only appear when
  developer stream diagnostics are enabled, and even then they should be
  truncated.

See `docs/architecture/calls-streaming-audio/windows-share-session.md` for the stable ownership
rules.

## Windows Call Audio Ducking Guidance

Windows attenuates ("ducks") other applications' audio while a communications
audio stream is active. Inter Galactic call audio runs through the Windows ADM
inside the packaged `libwebrtc.dll`, which selects `AudioDeviceWindowsCore`,
opens its endpoints with the `eCommunications` device role, and sets
`AudioCategory_Communications`. That combination is what makes a call turn down
whatever the user was already listening to.

Users read that as a bug, so the app opts out by default.

Current entry points:

- setting: Settings > Voice & Video > "Lower other app's volumes during calls",
  backed by `preferences.voipLowerOtherAppVolumes` (default **off**)
- Dart bridge:
  `intergalactic/lib/client/components/voip/audio/windows_call_audio_ducking.dart`
  (+ `_io` / `_stub` halves)
- applied from `CallManager.applyLowerOtherAppVolumesPreference()`, on toggle
  and again at call start
- native export: `IntergalacticSetCallAudioDuckingEnabled` in
  `libwebrtc/src/rtc_intergalactic_audio_ducking.cc`
- native implementation:
  `modules/audio_device/win/audio_device_core_win.cc`, which obtains
  `IAudioClientDuckingControl` from the render `IAudioClient` in
  `InitPlayout()` and calls `SetDuckingOptionsForCurrentStream()`

What matters for future work:

- **The description wording is deliberate.** "Allows Windows to reduce other
  application audio while Inter Galactic is using call audio." The app can only
  decline to trigger ducking; it cannot enable ducking the user has switched
  off in `mmsys.cpl > Communications`, and it writes no system setting. Do not
  reword this into a promise the app cannot keep.
- `IAudioClientDuckingControl` is obtained through
  `IAudioClient::GetService()`, not `IMMDevice::Activate()`.
- It is documented for the **render** stream and only affects the one
  `IAudioClient` it came from, so the ADM re-applies the option every time it
  initializes a render client and keeps a process-global desired-state flag
  that survives ADM teardown.
- `IAudioSessionControl2::SetDuckingPreference` is not the right API here. That
  is for a media app opting out of *being* ducked, not a comms app opting out
  of *causing* ducking.
- Minimum supported client is Windows 10 build 20348; older builds return
  `E_NOINTERFACE` and the native layer logs that once. Building it needs an SDK
  whose `audioclient.h` defines
  `__IAudioClientDuckingControl_INTERFACE_DEFINED__`.
- The toggle is inert until a `libwebrtc.zip` artifact built from the patched
  sources is installed. The Dart side resolves the export lazily and no-ops
  with one warning when it is missing, and the settings page shows a notice.
- `plugins/intergalactic_noise_suppression/windows/wasapi_sidecar_capture.cpp`
  also opens an `eCommunications` capture client, but it is a 10s diagnostic
  WAV recorder, not the call path. Do not apply the fix there. Making
  diagnostics runs stop ducking is a separate follow-up.
- Whether opting out on the render stream alone is enough is not yet proven on
  hardware; the ADM also opens an `eCommunications` capture stream, and
  whether that capture stream also needs an explicit opt-out has not been
  separately tested. Do not assume this is closed.

## Lifecycle Rules

When changing media/plugin code, inspect lifecycle from:

1. setup/init
2. normal use
3. error/fallback
4. cleanup/disposal
5. restart/background/foreground where applicable

### Media lifecycle checklist

- validate external input before use
- avoid trusting provider MIME type or metadata blindly
- surface user-visible failure when send/render cannot proceed
- keep room/event semantics Matrix-compatible

### Plugin lifecycle checklist

- init happens exactly once where required
- repeated enable/disable does not leak resources
- shutdown or dispose path exists
- unsupported targets return safe defaults or stubs

## Permissions and Native Bridges

If a media feature uses camera, microphone, filesystem, or native DSP:

- inspect the shared Dart API
- inspect plugin or platform bridge code
- inspect platform manifests/entitlements if capability prompts are involved

Do not treat permissions as a UI-only concern. They affect lifecycle and fallback behavior.

## CPU / Memory / Cleanup Guidance

### CPU / memory

Pay attention to:

- large media downloads
- repeated thumbnail or image decode work
- preview fetching loops
- audio processing cost in active calls

### Cleanup

Verify:

- temporary media objects do not linger past use
- plugin handles are released
- background subscriptions/listeners are removed
- failed sends do not leave partial state that later code treats as success

## Fallback Behavior

Every media/plugin path needs an intentional fallback:

- unsupported media should fail closed or render a safe generic state
- unavailable plugin capability should keep the rest of the app usable
- web/native differences should be explicit, not accidental

## Change Checklist

If changing media:

- inspect provider parsing
- inspect send/upload path
- inspect timeline/forum rendering path
- inspect fallback UI

If changing plugins:

- inspect plugin package code
- inspect app-side registration/use sites
- inspect unsupported-platform stubs
- inspect release/runtime packaging expectations

## Follow-Ups To Verify In Repo

Status: open checks; do not treat these as implementation instructions.

- Verify whether any additional native media helpers live outside `plugins/` before documenting more plugin ownership beyond the current noise suppression path.
- Verify the exact desktop packaging step for bundling plugin DLLs/shared libraries before documenting platform-specific packaging instructions here.
