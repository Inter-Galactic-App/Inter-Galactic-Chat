# Archived: LiveKit Streaming Performance Improvement Plan

Status: Archived historical planning note
Archived on: 2026-06-25
Superseded by:
- `../livekit-gameplay-streaming.md`
- `../streaming-guidance-status.md`
- `../stream-optimization-report.md`

Why archived:
- This was the original baseline performance-improvement plan before later architecture and evidence docs hardened the direction.
- Current gameplay defaults, active guidance, and dated evidence are now split into stronger contributor-facing docs.

Still useful for:
- original performance-plan framing
- early default-profile rationale
- comparing the initial plan against later implementation evidence

---

# LiveKit Streaming Performance Improvement Plan

Status: Historical planning note.

Current streaming source-of-truth docs:

- `streaming-pipeline.md`
- `livekit-gameplay-streaming.md`
- `streaming-guidance-status.md`
- `stream-optimization-report.md`

## Goal

Improve Inter Galactic LiveKit screen-share smoothness so streams feel closer to Discord: stable frame pacing, sane quality defaults, adaptive quality, and clear diagnostics.

Primary target: **smoothness over maximum sharpness**.

LiveKit supports screen sharing as video tracks, and advanced media configuration includes capture settings plus publish settings such as bitrate, framerate, simulcast layers, dynacast, and adaptive stream behavior.
Sources: LiveKit screen share/media docs, advanced video configuration, adaptive stream, and dynacast docs.

## Current Problem

Friends report choppy streams.

Likely causes:
- fixed high-resolution stream
- no simulcast or poor layer configuration
- bitrate too high for receiver/network
- framerate too high or unstable
- CPU-bound encoding
- capture/encode pipeline blocking
- subscribers receiving unnecessarily high-quality layers
- no useful diagnostics exposed

## Product Principle

Prefer:

```text
720p @ stable 30fps

over:

1080p/60fps with stutter
```

Discord-like streaming usually feels good because it prioritizes consistency and adapts quality aggressively.

Phase 1: Repo Discovery

Inspect the current codebase and document:

Where LiveKit rooms are created.
Where RoomOptions are configured.
Where screen share is started.
Where screen share tracks are published.
Current capture resolution/framerate settings.
Current publish encoding settings.
Whether simulcast is enabled.
Whether dynacast is enabled.
Whether adaptive stream is enabled for subscribers.
Whether any stats/diagnostics are already collected.
Whether Windows desktop capture is using Flutter WebRTC defaults or custom native capture.

Output findings before implementing.

Phase 2: Safe Baseline Profile

Create a conservative default screen-share profile.

Target baseline:

Resolution: 1280x720
Framerate: 30fps
Max bitrate: 1.5–2.5 Mbps
Codec: use current stable default unless repo already supports codec selection

Do not default to 1080p or 60fps yet.

Add a named profile enum:

enum ScreenShareQualityProfile {
  smooth,      // 720p 30fps, default
  balanced,    // 1080p 30fps if stable
  highQuality, // later, user opt-in
}

Initial priority:

implement smooth
scaffold balanced
do not over-optimize highQuality yet
Phase 3: Enable LiveKit Adaptation Features

Check and enable where supported:

Dynacast

LiveKit Flutter RoomOptions.dynacast exists and dynamically pauses video layers that are not consumed by subscribers, reducing publishing CPU and bandwidth.

Target:

RoomOptions(
  dynacast: true,
)
Adaptive Stream

Enable adaptive stream for subscribers if supported in the current SDK version.

Reason:
Adaptive stream allows LiveKit to coordinate the selected received quality based on the attached video element size/visibility instead of always sending the largest layer.

Simulcast

Enable simulcast for screen share if the SDK and platform path support it.

Goal layers:

Low:    360p 15fps, 300–700 kbps
Medium: 720p 30fps, 1–2 Mbps
High:   1080p 30fps, 2.5–4 Mbps, opt-in only

For MVP, do:

Low:    360p 15fps
Medium: 720p 30fps

Add high layer later only if metrics show it is stable.

Phase 4: Publish Settings Audit

Find the exact LiveKit API used in this repo to publish screen-share tracks.

Then set explicit publish options for screen share:

max framerate
max bitrate
simulcast enabled if available
screen-share-specific encoding profile

Do not reuse camera defaults for screen sharing.

Screen share needs different tuning:

text readability matters
frame pacing matters
rapid motion is less common than games/video, except game streaming
bitrate spikes can cause visible stutter
Phase 5: Subscriber-Side Rendering Rules

On the receiving side:

Do not render all remote screen shares at full quality if minimized or small.
If a screen-share tile is small, request/allow lower layer.
If a screen-share tile is focused/fullscreen, allow higher layer.
Pause or lower quality when hidden.

Confirm whether the Flutter SDK exposes adaptive stream behavior automatically or requires track attachment/rendering patterns.

Phase 6: Diagnostics Overlay

Add a developer-only diagnostics panel for active streams.

Show:

Publisher-side
capture resolution
capture FPS
encoded FPS if available
selected bitrate
target bitrate
actual sent bitrate
packets sent
packet loss if available
encode CPU warning if detectable
current quality profile
simulcast enabled/disabled
dynacast enabled/disabled
Subscriber-side
received resolution
received FPS
bitrate
packet loss
jitter
freeze count if available
active quality/layer if available

This is critical. Do not keep guessing.

Add a simple UI toggle:

Settings -> Developer -> Show call/stream stats
Phase 7: Adaptive Fallback Logic

Add local heuristics once stats exist.

Publisher-side fallback:

If any of these persist for several seconds:

FPS below target
high encode time
repeated dropped frames
outgoing packet loss
bitrate cannot reach target

Then degrade:

1080p -> 720p
30fps -> 24fps or 20fps
720p -> 540p if needed

Do not immediately bounce quality up and down. Use hysteresis:

degrade after 5–10 seconds of bad stats
upgrade only after 30–60 seconds of stable stats
Phase 8: Windows Capture Pipeline Review

If Windows screen capture is custom or becomes custom later, ensure the architecture is non-blocking:

Bad:

capture -> convert -> encode -> send

Better:

capture thread
  -> bounded frame queue
  -> encode/publish thread
  -> network

Rules:

never let capture block the UI thread
drop old frames instead of building an infinite queue
preserve recent frames over stale frames
log when frames are dropped
cap FPS before encoding
Phase 9: User-Facing Quality Settings

Add simple choices, not technical settings.

Suggested UI:

Screen Share Quality
[ Smooth ]  Recommended
[ Balanced ]
[ High Quality ]  Experimental

Descriptions:

Smooth: best for stability, 720p 30fps
Balanced: sharper, may use more bandwidth
High Quality: best detail, may be unstable on weaker connections

Default all users to Smooth.

Phase 10: Testing Matrix

Test with at least three accounts/devices if possible.

Network conditions
same LAN
normal remote internet
weak Wi-Fi
VPN off
VPN on if relevant
Content types
static desktop
browser scrolling
YouTube/video playback
game footage
Foundry VTT map movement
code editor/text readability
Quality profiles
smooth
balanced
high quality if implemented
Metrics to record
sender CPU
receiver CPU
sender bitrate
receiver bitrate
FPS
resolution
packet loss
visible freezes
subjective smoothness
Acceptance Criteria

MVP is successful when:

Default screen share is stable at 720p/30fps for most users.
Choppiness is reduced versus the current build.
Developer stats show actual bitrate/FPS/resolution.
Simulcast/dynacast/adaptive stream status is known, not guessed.
The app can fall back gracefully instead of trying to force high quality.
High-quality modes are opt-in, not default.
Non-Goals For This Pass

Do not implement yet:

alternate call transport
RNNoise changes
WASAPI loopback
shared screen audio
custom native Windows capture rewrite unless required
major call UI redesign
game/activity presence

This pass is about making existing LiveKit streaming smoother first.

Implementation Output Required

When finished, report:

Current LiveKit configuration found.
Exact changes made.
Whether simulcast is enabled.
Whether dynacast is enabled.
Whether adaptive stream is enabled.
New default screen-share profile.
How to test locally.
Any remaining bottlenecks.
Recommended next performance pass.
Suggested Delivery Order
Step 1

Repo discovery and current LiveKit config summary.

Step 2

Add conservative 720p/30fps default profile.

Step 3

Enable dynacast/adaptive stream where supported.

Step 4

Enable or configure simulcast if supported.

Step 5

Add developer stats overlay.

Step 6

Add simple user quality setting.

Step 7

Only then add fallback logic.

Do not skip diagnostics. Without stats, performance work becomes guessing.


Realistic delivery: **3–7 days** for the baseline profile + LiveKit option audit, **1–2 weeks** with diagnostics, and **2–3 weeks** for adaptive fallback/polish.
