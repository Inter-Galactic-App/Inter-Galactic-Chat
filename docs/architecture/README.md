# Architecture Docs

Status: active index
Maintenance: project documentation contributors
Last reviewed: 2026-08-06

Use this index to choose the smallest architecture document that matches a
change. Start with the stable maps, then open feature-specific docs only when
the change touches that feature.

## Folder Map

- `core/` - app-wide maps, repository orientation, and change checklists.
- `matrix/` - Matrix protocol, room, media, E2EE, and permission behavior.
- `features/` - product feature surfaces and settings architecture.
- `notifications/` - push, local notification, and companion-overlay behavior.
- `diagnostics/` - bug-report and diagnostic logging contracts.
- `calls-streaming-audio/` - calls, LiveKit, streaming, game capture, WebRTC,
  RNNoise, and shared-content audio.
- `release/` - release target and distribution behavior.

## Start Here

- `core/overview.md` - high-level app layers, runtime flows, and architecture
  constraints.
- `core/codebase-map.md` - package and folder orientation before app-repo work.
- `core/change-guide.md` - change-type checklist for cross-cutting work.
- `core/system-overview.md` - concise subsystem map for broad architecture review.
- `core/ci-and-validation.md` - CI entry points, gate boundaries, and transcript scope.
- `core/ui-shell-and-responsive-navigation.md` - main shell composition,
  desktop/mobile navigation, accessibility context, and responsive routing.
- `core/theming-accessibility-and-motion.md` - theme catalog and resolution
  order, custom theme storage/import/export, accessibility-derived contrast
  tokens, and the shared motion/duration system.
- `core/client-lifecycle.md` - foreground client ownership, headless
  notification processing, background tasks, and file-cache boundaries.
- `core/ios-platform-integration.md` - iOS runner, notification, extension,
  and shared-Dart handoff boundaries.
- `core/macos-platform-integration.md` - macOS runner, Flutter-window bootstrap,
  entitlement/permission boundary, and lifecycle ownership.

## Core System Maps

- `matrix/matrix-e2ee.md` - login, Matrix restore, verification, and recovery-key
  safety.
- `matrix/media-pipeline.md` - Matrix media send/upload/render flow, URL-preview
  boundaries, and the platform-to-composer inbound-share handoff.
- `matrix/room-interactions.md` - polls, threads, forum posts, room search,
  receipts, typing indicators, invitations, and knock-approval behavior.
- `notifications/notifications.md` and `notifications/push-pipeline.md` -
  pushers, platform notifiers, notification routing, and cleanup rules.
- `features/activity-system.md` and `features/rich-presence-activity.md` -
  local activity, presence publishing, Spotify, Steam, and status cards.
- `features/profile-and-presence.md` - profile fields, profile UI, Matrix
  presence, custom status, cache updates, and the boundary from local activity.
- `features/onboarding-system.md`, `features/offline-demo-mode.md`, and
  `features/tutorial-demo-preview.md` - first-run, demo, and tutorial behavior.

## Calls, Streaming, And Audio

- `calls-streaming-audio/streaming-pipeline.md` - stable map for MatrixRTC,
  LiveKit, WebRTC, shared audio, RNNoise boundaries, and diagnostics.
- `calls-streaming-audio/livekit-gameplay-streaming.md` - current
  LiveKit/gameplay streaming defaults and diagnostics guidance.
- `calls-streaming-audio/streaming-guidance-status.md` - current streaming guidance and next
  implementation decisions.
- `calls-streaming-audio/stream-optimization-report.md` - compact index for the split historical
  streaming evidence archive. Open dated files under
  `calls-streaming-audio/stream-optimization-report/` only when investigation
  detail is needed.
- `calls-streaming-audio/stream-diagnostic-contract.md`,
  `calls-streaming-audio/stream-receiver-diagnostic-contract.md`, and
  `calls-streaming-audio/stream-bottleneck-classification.md` - stream-test
  reporting and classifier contract.
- `calls-streaming-audio/archive/README.md` - historical milestone, gap, and
  planning docs that were moved out of the live streaming architecture surface.
- `calls-streaming-audio/local-stream-pipeline-harness.md`,
  `calls-streaming-audio/game-capture-backend-architecture.md`,
  `calls-streaming-audio/game-capture-test-target.md`, and
  `calls-streaming-audio/windows-libwebrtc-hardware-encoding.md` - Windows game-capture and native
  WebRTC diagnostics.
- `calls-streaming-audio/media-and-plugins.md`,
  `calls-streaming-audio/RNNOISE_TUNING_BASELINE.md`, and
  `calls-streaming-audio/rnnoise-native-resampler-plan.md` - media/plugin map
  and RNNoise follow-up docs. RNNoise behavior belongs to AUDIO.
- `calls-streaming-audio/windows-share-session.md` and
  `calls-streaming-audio/voip-soundboard.md` - shared-content audio and call
  soundboard behavior.

## Product Feature Areas

- `features/dm-stories.md` - direct-message stories, story media, notifications, and
  viewer routing.
- `matrix/space-room-categories.md`, `matrix/room-settings-and-permissions.md`,
  `matrix/thread-timelines.md`, `matrix/room-interactions.md`,
  `features/settings-information-architecture.md`, `features/settings-ui-map.md`, and
  `features/settings_areas.md` - space/room/timeline/settings structure and
  permission-aware settings surfaces.
- `diagnostics/bug-reporting-flow.md` and `diagnostics/diagnostic-logging.md` - bug-report payloads,
  crash prompts, diagnostics, and redaction boundaries.
- `matrix/calendar-rooms.md` - Matrix calendar-room event handling.
- `features/desktop-small-window-mode.md` - compact desktop window behavior.
- `release/release-targets.md` - release target, updater, and distribution behavior.
- `core/repo-tree.md` - stable app-repo tree snapshot.

## Design Docs

Design-system guidance lives in `../design/`. Start with
`../design/INTERGALACTIC_DESIGN_SYSTEM.md` before changing UI, theme, layout,
settings surfaces, or component patterns.

The runtime composition map for the main UI shell is
`core/ui-shell-and-responsive-navigation.md`. It complements the design-system
guidance with source-backed routing and composition anchors; it does not replace
the visual guidance or claim ownership of feature-specific behavior.

The runtime map for theme resolution/storage, accessibility-derived contrast
tokens, and the shared motion system is
`core/theming-accessibility-and-motion.md`. It complements
`../design/THEME_GUIDELINES.md` and `../design/ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md`
the same way - source anchors for how a design decision is actually resolved
and stored, not a restatement of what the decision should be.

## Maintenance Notes

- Keep stable maps concise. Move long investigation evidence into dedicated
  reports or archives.
- Feature and subsystem documents remain maintained by their domain owners;
  this file is only the navigation index.
- Do not put private workspace paths, private hostnames, secrets, or internal
  agent coordination state in app-repo architecture docs.
- License/legal evidence files are out of scope for architecture-doc cleanup.
