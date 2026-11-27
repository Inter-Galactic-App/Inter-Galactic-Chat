# Guided Tutorial Backdrop

Status: production tutorial backdrop plus developer preview modes
Last updated: 2026-05-19

## Purpose

The production tutorial renders the onboarding card flow over a controlled
offline Inter Galactic demo app. This gives first-run and replay users a stable,
real-feeling app shell without requiring a Matrix account, network sync, server
writes, or the user's current room state.

`TutorialMode.realAccount` is the real tutorial mode: it uses the guided offline
demo backdrop and writes the local onboarding completion state on Skip or Finish.
`TutorialMode.demoPreview` keeps the same guided backdrop for developer/review
testing without writing completion. `TutorialMode.legacyPlaceholder` keeps the
old card-only placeholder tutorial behind developer access for future copy or
layout experiments.

## Key Files

- `intergalactic/lib/ui/onboarding/tutorial_mode.dart` defines the production
  guided tutorial, no-completion demo preview, and developer-only legacy
  placeholder modes.
- `intergalactic/lib/ui/onboarding/demo_tutorial_content.dart` contains the
  expanded tutorial steps used by the demo tutorial flow.
- `intergalactic/lib/ui/onboarding/tutorial_scene.dart` maps each demo tutorial
  step to a selected demo room, optional settings surface, optional real-widget
  overlay, tutorial card placement, side-panel state, and focus target.
  Scenes must preserve the app shell's natural scale; they switch context
  instead of shrinking the whole app.
- `intergalactic/lib/ui/onboarding/tutorial_anchor.dart` provides the measured
  widget-anchor registry used by the tutorial focus layer. Real app regions
  register their global bounds while the fallback rectangles remain only as a
  backup for unavailable anchors. Anchors invalidate stale rectangles and
  remeasure after dependency changes, widget updates, child-size changes,
  animated-surface transitions, viewport constraint changes, and window metric
  changes so maximize/restore or picker swaps do not leave stale highlight
  rectangles behind.
- `intergalactic/lib/ui/onboarding/tutorial_focus_overlay.dart` provides the
  dimmed backdrop, outline-color target cutout, glow, and directional arrow
  used by demo-preview scenes.
- `intergalactic/lib/ui/onboarding/tutorial_demo_backdrop.dart` creates an
  isolated local `ClientManager`/`DemoClient` backdrop and renders real inert
  app settings, composer menu, account popup, activity, security, companion,
  encrypted-room, embedded call, and soundboard widgets over that demo app
  where safe. Remaining tutorial-only overlays are reserved for OS/native
  animations
  and scenes that do not yet have a safe reusable inert widget.
- `intergalactic/lib/client/demo/demo_client.dart` seeds the offline demo
  account, rooms, components, and sample data used by the backdrop.
- `intergalactic/lib/ui/pages/settings/categories/help/help_tutorial_page.dart`
  exposes replay for the production guided tutorial and, when developer mode is
  enabled, access to the old card-only placeholder.

## Demo Data Scope

The offline `DemoClient` now includes tutorial-oriented sample coverage for:

- chat, forum, calendar, voice, direct-message, photo-album, and encrypted-room
  examples
- photo album individual photos, stacks, and local thread/comment examples
- room emoticon packs and demo reactions
- account-level demo emoticon packs, recent reactions, and joined
  room/space packs for the real Emoticons settings surface
- a space soundboard with sample sounds and a join sound
- encrypted-message/decryption warning copy
- unread/mention counts and notification override examples where existing UI can
  consume local room state

The backdrop itself renders the real app shell through `MainPage` with the
offline `DemoClient`, so the side rail, room list, room content, composer, and
lower-left account panel stay at normal app scale. App/account/help settings
surfaces use the real `AppSettingsPage` with the isolated demo manager. Room and
space settings use the real contextual settings pages against demo rooms/spaces,
so seeded emoji packs and soundboard sounds are demo data while the settings UI
itself remains the production UI. Composer attachment/effects popups, the
account popup, local activity card, and call soundboard menu also reuse their
real widgets.

The demo preview now opens the real room side panel for photo-thread and member
scenes, including the photo-album thread header/comment surface and the members
panel with its Nicknames action. Broad FAQ scenes show the real Help FAQ page
without an extra modal/highlight. Composer media scenes cycle between the real
attachment menu and the real combined GIF/sticker/emoji picker surface, keeping
the desktop tabs/search/create controls in the same structure as the live
composer. Message-effect scenes use the real particle player contained to the
chat timeline.

The app-emoticon scene now uses the real `EmoticonsSettingsPage` backed by demo
account, recent-reaction, room, and space pack data. The Security scene uses a
demo-specific Security tab built from the same Settings section/control/session
patterns as the Matrix security panel instead of the old non-Matrix placeholder.
The local activity card is injected into the real lower-left activity/account
area, and encrypted-room scenes expose the real `RoomQuickAccessMenu` Retry
Decrypt action above Room Members so the padlock target is measured from the UI
that visually owns it.

The demo preview may still use tutorial-only visual overlays for UI that should
not run in an inert offline client, such as call-member right-click controls and
call/native overlay options. Desktop companion previews reuse extracted
companion-avatar and active-notification visual widgets on an inert detached
card; they must not start OS companion windows, push registration, or network
requests.

The latest demo-correction pass keeps those inert boundaries but makes the
remaining placeholders app-shaped: demo emoji entries render actual emoji glyphs
inside the real combined picker, the app-emoticon tutorial scene shows a
settings-style Available Packs layout, the room-emoticon tutorial targets the
real favorite-heart toggle in the pack row, the call tutorial now starts the
offline demo voice room and uses the embedded real `VoipRoomView`/`CallWidget`
path with real controls forced visible, page 20 leaves the call surface
undimmed when it is demonstrating the full call area, page 21 targets the real
popout-control button, the soundboard popup is placed above the lower-left
account panel, desktop companion scenes use the packaged companion artwork
centered on screen, the activity preview uses the same demo/developer music
activity card attached to the lower-left account area with demo-local activity
visibility enabled, Security demo controls sit over the Security panel content
area, the encrypted room lock target sits on the side-panel rail above Room
Members, and replay tutorial highlighting measures the real Help > Tutorial
button instead of rendering a duplicate button. Composer media-menu anchor
changes retain the last measured real rectangle while the menu swaps between
attachment and picker surfaces, avoiding hard-coded fallback flicker during
resize frames; the attachment menu itself measures the real composer plus
button and stays anchored to the same side as the production popup.

The final review pass tightened the remaining resolution-sensitive anchors.
The composer emoji and effects buttons now publish measured tutorial anchors,
so the GIF/sticker/emoji picker and effects menu can position from the same
controls that visually own those popups. Guided call scenes also force the real
lower-left call/soundboard panel visible and register the offline demo call
session with the isolated tutorial `CallManager`, allowing the soundboard menu
to anchor above the real call-panel soundboard button instead of a fixed screen
offset. The room quick-access menu now cancels its settings subscription on
dispose so measured padlock/quick-action scenes do not retain stale listeners.

## Non-Persistence Rules

- Demo preview must not call Matrix sync, register pushers, or mutate a real
  Matrix account.
- Production guided tutorial Skip and Finish write `onboarding.completed`,
  `onboarding.version`, and `onboarding.completedAt`.
- Demo preview and legacy placeholder Skip/Finish must not write those
  onboarding completion preferences.
- Demo uploads/soundboard/emoticon edits are local in-memory demo state only.
  In demo preview, pointer input is ignored, so the real widgets are displayed
  as proof-of-concept UI context rather than mutating their underlying data.
- Real onboarding completion remains local preferences only and is not Matrix
  account data in this pass.

## Scene Model

Each demo step has a stable `id` and optional `targetAnchorId`. The current
scene layer uses `TutorialSceneSpec` to control the demo backdrop:

- selected demo room
- optional app, room, space, account, or help settings surface
- optional tutorial-only overlay/menu/highlight
- tutorial card placement
- optional side-panel mode and thread root id
- optional focus target rectangle, outline, and arrow
- optional auto-advance timing for animation/menu demonstration steps
- mobile panel reveal state and top/bottom sheet placement
- keyboard navigation with right/Enter for Next/Finish, left for Back, and
  Escape for Skip

The scene model intentionally does not globally scale or zoom out the demo app.
If a future step needs another feature visible, the scene should select the
relevant room, settings surface, side panel, or popup while the app remains at a
normal readable size.

The current focus layer prefers measured anchors for the side rail, room list,
timeline, composer, composer popups, room side panel, settings surface, account
popup, activity card, companion preview, soundboard popup, and FAQ answer card.
Scene-defined fallback rectangles remain for mobile fallback, startup frames
before a widget has reported its bounds, and native/OS-only preview surfaces
that do not yet have reusable inert widgets.

Broad settings-page scenes intentionally omit `focus`. They show the real
settings surface without the darkened backdrop overlay unless the tutorial step
targets a specific setting, button, popup, or callout.

## Limitations

- Focus highlighting now uses measured widget anchors where the real UI exposes
  one. Scenes still need visual smoke across desktop sizes and mobile to tune
  card placement and any intentional fallback rectangles that remain for
  startup frames or native-only preview surfaces.
- Native/OS-level behavior such as detached call windows and desktop companion
  animation is represented by inert tutorial visuals in the preview. The call
  tutorial highlights the real popout control but does not open an OS detached
  window.
- Mobile and desktop share the scene model but use their own scene tables.
  Mobile scenes declare the visible panel and place the tutorial sheet above
  lower-screen targets; visual smoke still tunes fallback geometry on devices.

## Next Step

Keep the mobile and desktop scene tables aligned when a shared tutorial step is
added. New mobile targets need a measured anchor in the widget that owns the
visible control and a device smoke check for sheet placement.
