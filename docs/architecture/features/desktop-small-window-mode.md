# Desktop Small-Window Mode

## Purpose

Desktop small-window mode is a user-enabled compact shell for short or narrow
desktop windows. It keeps the app in the desktop navigation model instead of
switching to the mobile overlapping-panel layout.

Use it when a desktop user wants Inter Galactic to fit beside another app while
still showing room navigation, the active timeline, and the message composer.

## Ownership

The mode is owned by the desktop shell and app settings:

- `intergalactic/lib/config/preferences.dart` stores
  `desktopSmallWindowMode`.
- `intergalactic/lib/ui/pages/settings/categories/app/general_settings_page.dart`
  exposes the setting under App Behaviour on desktop layouts.
- `intergalactic/lib/ui/pages/main/main_page_view_desktop.dart` applies the
  compact shell sizing, hover-reveal panels, and user-bar quick toggle.
- `intergalactic/lib/ui/organisms/side_navigation_bar/` owns compact navigation
  rail sizing.
- `intergalactic/lib/ui/organisms/room_side_panel/` owns compact side-panel
  widths and narrow-window default-panel collapse.

## Behavior

When the preference is enabled:

- The desktop room picker collapses into a left hover-reveal panel so
  horizontal space belongs to the timeline and composer until navigation is
  needed.
- The room members panel collapses into a right hover-reveal panel in compact
  mode. Threads, search, pinned-message, and calendar panels still open from
  their normal events, but the default members list does not permanently occupy
  width.
- The room header, space header, and user bar use shorter desktop sizes. The
  compact room header hides the topic line and uses smaller avatar/title
  treatment.
- Primary timeline message text scales up while the compact preference is
  enabled. URL previews, media cards, reactions, timestamps, and other message
  chrome keep normal sizing so embedded cards do not crowd the narrow layout.
  The desktop composer also gets a small readability bump.
- Soundboard/activity panels are not rendered in compact rail mode, regardless
  of window height, so the small-window shell does not show persistent lower-left
  auxiliary panels. Clicking the current user avatar opens an anchored activity
  popover so local activity and music playback controls remain reachable without
  occupying the rail by default.
- The user bar shows a quick toggle next to the settings button for entering
  or exiting small-window mode.
- Preference toggles listen for changes from the user-bar quick toggle so the
  settings switch reflects the real persisted value instead of stale state.

## Guardrails

Do not implement this by changing `Layout.desktop` / `Layout.mobile`
resolution. Desktop small-window mode must remain a desktop layout so keyboard,
context-menu, room-header, and desktop composer behavior remain intact.

Keep LiveKit, MatrixRTC, and call-media session code out of this feature unless
a later call-window change explicitly needs to coordinate with compact shell
chrome.
