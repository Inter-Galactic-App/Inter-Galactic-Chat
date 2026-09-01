# Calls And Stories Motion Audit

Status: docs-only DESIGN audit
Owner: DESIGN
Date: 2026-06-24
Backlog item: `docs/design/UX_UI_POLISH_BACKLOG.md` P20
Related audit: `docs/design/MOTION_AND_MICROINTERACTION_AUDIT.md`

## Purpose

Calls and stories are high-motion surfaces with media, platform permission,
upload, playback, and live-session state. This audit records the safe design
boundary before any later implementation pass changes their motion or layout.

No app behavior changed in this pass.

## Surfaces Reviewed

| Surface | Primary files | Existing motion/state |
| --- | --- | --- |
| Story viewer | `intergalactic/lib/ui/organisms/home_screen/home_story_viewer.dart` | Full-screen dialog, top progress bars, tap left/right navigation, delayed video progress until media is ready. |
| Story composer | `intergalactic/lib/ui/organisms/home_screen/home_story_composer.dart` | Fade route, camera/recording timers, capture controls, draft strip, busy/locked controls. |
| Story editors | `home_story_editor.dart`, `home_story_video_editor.dart`, `home_story_video_tools.dart` | Fade routes, crop/trim/edit controls, local draft preview and export states. |
| Call view | `intergalactic/lib/ui/organisms/call_view/call_view.dart` | Control visibility fade, local screenshare auto-hide timers, fullscreen/popout/PiP actions, diagnostics panels. |
| Stream tiles | `intergalactic/lib/ui/organisms/call_view/voip_stream_view.dart` | Audio-level animation, hover chrome, hidden-video reveal panel, fullscreen/context actions. |
| Fullscreen stream | `intergalactic/lib/ui/organisms/call_view/voip_fullscreen_stream_view.dart` | Fade route around a live stream renderer. |

## Current Risks

- Story viewer progress is functional timing, not decoration. It should remain
  tied to actual media readiness, especially for encrypted video downloads.
- Story composer recording state and camera lifecycle are platform-sensitive.
  Avoid motion that delays stop/cancel/release feedback.
- Call video and screen-share tiles contain live render surfaces. Do not animate
  decoded video, renderer textures, capture surfaces, or LiveKit media frames.
- Call PiP, detached windows, fullscreen, and platform permission flows cross
  app, OS, and plugin boundaries; they need owner-lane smoke before visual
  changes.
- Audio-level animation is functional speaking feedback. If reduced motion is
  added later, preserve the same information with a static or stepped meter.

## Safe Future Candidates

| ID | Candidate | Scope | Reduced-motion behavior | Ownership gate |
| --- | --- | --- | --- | --- |
| CS01 | Story viewer route consistency | Keep the full-screen viewer entrance short and non-spatial, aligned with shared modal motion tokens. | Fade-only or instant. | DESIGN plus FEATURES review. |
| CS02 | Story composer busy feedback | Standardize capture/upload/export busy labels and stable action widths without changing camera/upload behavior. | Static labels and disabled states. | FEATURES review. |
| CS03 | Story draft strip state | Use shared preparing/uploading/failed/sent language for drafts after the media-send QA caveats close. | Instant icon/label swap. | FEATURES and QA. |
| CS04 | Call controls visibility | Normalize fade duration and focus behavior for call controls only, leaving render surfaces untouched. | Controls appear/disappear instantly. | EXPERIMENTAL/DEBUG review. |
| CS05 | Hidden stream reveal affordance | Clarify hidden-video state with static icon/text and accessible action labels. | Static only. | EXPERIMENTAL/DEBUG review. |
| CS06 | Fullscreen media route | Align fullscreen stream/story route duration with shared modal tokens. | Fade-only or instant. | EXPERIMENTAL/FEATURES review. |

## Deferred Or Excluded

- Do not add decorative story capture flashes until platform camera capture has
  fresh mobile smoke.
- Do not animate LiveKit/RTC renderer size, decoded frames, receiver probe
  views, screen-share previews, or gameplay-stream surfaces.
- Do not change story event contracts, upload sequencing, media readiness
  timers, call connect behavior, PiP behavior, or detached-window behavior in a
  DESIGN-only pass.
- Do not add global reduced-motion behavior to calls/stories before the shared
  app motion helper exists.

## Validation Needed Before Implementation

- Story viewer smoke: photo, encrypted video, slow video load, tap left/right,
  close, delete own story, reaction failure.
- Story composer smoke: camera start, camera flip, capture photo, hold to
  record, cancel while recording starts/stops, album import, video trim/export,
  post failure.
- Call smoke: incoming call, active group call, fullscreen stream, hidden video,
  screen-share reveal/hide, PiP/popout where supported, Escape/back dismissal.
- Accessibility smoke: keyboard focus order, visible focus, labels for
  icon-only controls, progress state announcements where status changes are
  user-relevant.

## Recommendation

Treat P20 as complete for design audit purposes and keep implementation
deferred until a narrow owner-cleared task selects one candidate above.

## EXPERIMENTAL Implementation Update - 2026-06-24

EXPERIMENTAL addressed the calls-owned subset of this audit without changing
LiveKit media, renderer texture, stream subscription, PiP, popout, or detached
window behavior.

- CS04: call controls now use shared `InterGalacticMotion` fade timing and are
  removed from focus/semantics while hidden. Reduced-motion contexts show or
  hide controls instantly. Detached transparent call controls keep their
  existing instant visibility path to avoid transparent-window opacity
  compositing wash.
- CS05: hidden video/screen-share tiles now use static state/action labels and
  explicit semantics while keeping the existing reveal/hide callbacks and
  renderer-pausing behavior.
- CS06: fullscreen stream routes now use shared modal fade timing and honor
  reduced-motion contexts with an instant transition.

Story-side CS01/CS02/CS03 and the story half of CS06 remain deferred to
DESIGN/FEATURES ownership.

## FEATURES Implementation Update - 2026-06-24

FEATURES addressed the story-side subset of this audit without changing story
Matrix events, upload sequencing, media readiness timers, camera capture,
trim/export, desktop recording, or notification behavior.

- CS01: story viewer, composer, photo editor, and video editor full-screen
  routes now use shared `InterGalacticMotion` short fade timing and honor
  reduced-motion contexts with instant transitions.
- CS02: composer draft preparation and sharing now use explicit status labels
  and a stable-width share action while preserving existing camera, render,
  upload, and retry behavior.
- CS03: story draft queue state is typed as preparing, sharing, sent, or
  failed; background upload success now reports a sent outcome, while existing
  retryable failure snackbars remain the failure path.
- CS06: the story full-screen media/editor routes now match the same shared
  modal fade/reduced-motion contract used by the call-side follow-up.

Remaining validation is rebuilt-app smoke for story viewer open/close, photo
capture to edit, draft prepare/share status, successful share snackbar,
retryable failure snackbar, video editor trim/export, and OS reduced-motion
behavior on desktop and mobile.
