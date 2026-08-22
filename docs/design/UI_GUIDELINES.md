# UI Guidelines

Status: active design reference
Owner: DESIGN
Last updated: 2026-06-23

## Scope

Use these guidelines when adding or changing Inter Galactic UI. They are meant
to keep product code, settings, chat surfaces, mobile panels, and developer
tools visually consistent.

## General Rules

- Use existing Inter Galactic and Tiamat primitives before creating new
  components.
- Respect the current route and state boundaries. UI polish should not move
  Matrix state, preferences, or call/media behavior unless the task explicitly
  includes that work.
- Keep layout responsive. Do not hard-code wide desktop assumptions into shared
  mobile code.
- Prefer semantic theme tokens over literal colors.
- Keep dangerous settings visually distinct and textually clear.
- Do not use visible instructional text to explain obvious controls. Use labels,
  tooltips, clear states, and confirmations.
- Do not make UI surfaces one-note by using only one color family or a single
  repeated accent.

## Settings

Settings are the strongest current expression of the app design language.

Use:

- `SettingsTypography` for settings surfaces.
- `SettingsSection` for grouped sections.
- `SettingsControlRow` for common row controls.
- `surfaceContainer` for the main desktop content pane.
- `surfaceContainerLow` for sidebar and panel cards.
- Dividers with enough outline alpha to remain visible across themes.
- Row-level search metadata and aliases when settings move or rename.

Avoid:

- Bold section titles unless there is a clear exception.
- Full-window desktop settings pages.
- Hidden nested scrollbars inside two-pane layouts.
- Debug-only controls in user-facing settings groups.

Risk tiers should follow `settings-information-architecture.md`:

- Local-only preferences can be direct and compact.
- Device/platform preferences need device-specific copy when relevant.
- Matrix account/server-affecting settings need explanation.
- Room/space state settings need permission and power-level awareness.
- Developer/debug settings stay behind Developer surfaces.

## Chat And Composer

The chat view is content-first. Message input should support rich actions
without stealing vertical space.

Guidance:

- Keep the latest message visible above the composer in the neutral position.
- Let messages pass behind clear composer surroundings when scrolling.
- Apply glass blur to the intended input pill or floating surface only.
- Slash commands and attachment actions should appear in anchored popup tiles
  when they are available.
- Desktop composer, plus/slash/effects menus, picker tabs, and account popups
  should derive edge highlights and active frames from `ColorScheme.outline`
  rather than accent colors, `onSurface`, or hard-coded black.
- Keyboard dismissal should be gesture/placement based when possible, not
  fragile speed-only behavior.
- Sending a message should return to neutral position without collapsing and
  reopening the keyboard.

## Rooms, Spaces, And Lists

Room and space settings should look similar to app settings when they expose the
same concept. Copy should be context-specific:

- Use "space" labels on space pages.
- Use "room" labels on room pages.
- Explain Matrix room-backed implementation only when it matters.

Lists should reserve stable row height, icon space, and collapsed-state space so
hover controls, badges, and expansion do not cause distracting jumps.

## Media Surfaces

Media views should be polished but not heavy:

- Use clean media tiles with predictable hover actions.
- Use count badges and visible stack affordances for grouped media.
- Keep comments/reactions attached to the root media event when using threads.
- Use explicit controls for alternate actions such as full-size viewing.

## Calls And Voice/Video

Calls are high-risk shared UI. Preserve existing runtime behavior unless a task
explicitly includes call logic.

User-facing voice/video settings should prioritize:

- Default input and output devices.
- Volume controls.
- Mic check.
- Camera selection and camera test.
- Screen-share quality.
- Push-to-talk enablement, with keybind configuration in Shortcuts.

Diagnostics belong in Developer and should be collapsible.

## Floating And Detached Surfaces

Popouts, detached call/video windows, hover chrome, and other floating media
surfaces must be able to fail without exposing Flutter's default white debug
error chrome.

Required guardrails:

- Start every new media popout opaque. Transparent chrome is an in-memory state
  for the current open popout/window only, and users may opt into it after the
  new surface has rendered normally.
- Provide a local `Material` ancestor before custom `InkWell`, tooltip, popup,
  or ink/splash widgets on custom room, favorites, media, and popout surfaces.
  A transparent `Material` is enough when the visual treatment should not
  change.
- Provide a local `Overlay` inside secondary Flutter views such as
  `ViewAnchor`/detached window hosts before rendering tooltips, menus, or other
  overlay-seeking controls.
- Keep video/media content explicitly sized in floating or shrink-wrapped
  frames; do not rely on flex children that can collapse and leave a blank
  popout.
- In transparent popouts, paint hover controls directly with dark translucent
  theme-token surfaces. Avoid default light Material hover/splash layers and
  opacity/saveLayer fades that can composite as white boxes over video.

## Empty, Loading, And Error States

Every new surface should include:

- Empty state that says what is missing and what action is available.
- Loading state that preserves layout size when possible.
- Error state with recovery when user action can help.

Do not let failed async content collapse a card into a white or unthemed error
screen.

Use `STATE_AND_RECOVERY_PATTERNS.md` for the shared copy and layout matrix.
Prefer inline retry, refresh, clear-search, account-switch, and setup actions
over modal errors when the surrounding surface can remain usable. State copy
should describe the user-visible problem and next step without exposing private
deployment names or raw implementation errors.

## Accessibility

- Keep hit targets large enough for desktop and touch.
- Keep labels available for icon-only actions via tooltip, semantics, or nearby
  text.
- Use contrast-safe foreground/background pairs from the theme.
- Do not rely on color alone for selected, disabled, or dangerous states.
- Respect reduced motion when animation affects reading position or vestibular
  comfort.
- Do not make hover the only way to retry, cancel, delete, close, or recover.
  Provide a keyboard and mobile path for required actions.
- Pair compact visible labels with full semantics labels when text is shortened
  for dense layouts.

Use `ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md` as the selected-surface smoke
checklist for settings, Discover, room creation, categories, snooze controls,
and timeline/media hover parity.

## Developer UI

Developer tools should be useful but visually quieter than everyday settings.

- Use collapsible groups.
- Put diagnostics and raw JSON below user-facing controls.
- Explain what utilities do in plain language.
- Keep destructive/debug actions behind clear labels and confirmations.
