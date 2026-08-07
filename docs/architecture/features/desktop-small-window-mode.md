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
- `intergalactic/lib/utils/window_management_io.dart` initializes desktop
  window management for Linux and Windows, including main-window bounds
  persistence.
- `intergalactic/lib/utils/desktop_window_bounds_persistence.dart` saves and
  restores the main desktop window's last normal bounds and maximized state.
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
- Primary timeline message text and desktop composer text keep the normal app
  text scale. Text readability is controlled through the app text size setting
  instead of the compact shell preference, while URL previews, media cards,
  reactions, timestamps, and other message chrome keep their normal sizing so
  embedded cards do not crowd the narrow layout.
- Soundboard/activity panels are not rendered in compact rail mode, regardless
  of window height, so the small-window shell does not show persistent lower-left
  auxiliary panels. Clicking the current user avatar opens an anchored activity
  popover so local activity and music playback controls remain reachable without
  occupying the rail by default.
- The user bar shows a quick toggle next to the settings button for entering
  or exiting small-window mode.
- Preference toggles listen for changes from the user-bar quick toggle so the
  settings switch reflects the real persisted value instead of stale state.
- The main desktop window stores its last normal position and size locally and
  restores those bounds on the next launch. Maximized state is restored after
  the saved normal bounds are applied, so unmaximizing returns to the user's
  previous size instead of the startup default.
- Restore validation is monitor-aware: negative coordinates are valid for
  secondary monitors, and saved bounds are accepted when enough of the window
  intersects a currently visible display. If the saved monitor is missing, the
  app keeps the platform default startup placement instead of reopening
  off-screen.

## Guardrails

Do not implement this by changing `Layout.desktop` / `Layout.mobile`
resolution. Desktop small-window mode must remain a desktop layout so keyboard,
context-menu, room-header, and desktop composer behavior remain intact.

Keep LiveKit, MatrixRTC, and call-media session code out of this feature unless
a later call-window change explicitly needs to coordinate with compact shell
chrome.

## Detached Call Windows

Full-call popouts use `DetachedCallWindowHost` on desktop platforms where
Flutter windowing is available. The host creates a secondary `RegularWindow`
through `ViewAnchor` and mounts only the call-room surface with `CallWidget`;
the main app shell stays in the primary window. Windows and macOS should take
this native detached-window path when
`ENABLE_NATIVE_DETACHED_CALL_WINDOWS=true`.

Per-stream call popouts now use the same native detached-window host when that
host is mounted. The existing tile popout button still records a stable
`callStreamPopoutIdForStream` entry in `CallPopoutController`, but supported
desktop builds route those entries to separate OS windows keyed by session plus
stream popout id. Unsupported platforms, disabled native detached windows, and
builds where the host is not mounted keep the previous in-app `FloatingTile`
overlay fallback.

Native per-stream panel close is intentionally deferred out of the OS
window-destroy callback before it restores controller state. If the closed panel
belongs to the local user's screenshare and the latest sender diagnostics show
the matching stream at zero capture FPS, the close path stops that dead
screenshare instead of docking a black tile back into the main call grid.
Ordinary active camera and screenshare panel closes still dock the stream.

Windows-only native chrome controls, such as HWND always-on-top and frameless
style changes, must stay behind `Platform.isWindows` guards. macOS detached
call windows still use the normal native window frame and should not call the
Windows FFI styling path.

On Windows, opaque detached full-call and per-stream popouts use a custom
Flutter title bar instead of relying on the OS-drawn caption. The native HWND is
kept frameless/resizable, while the in-window title bar owns the draggable label
area plus nondraggable transparent, pin, dock, minimize, maximize/restore, and
close controls. Those controls must target the detached `RegularWindow`
controller/window handle, never the main app window. Transparent chrome hides
the custom title bar, removes the native frame, and keeps the compact hover
pill controls so users can restore opacity, pin, or dock the popout. It must
also strip Windows extended edge styles such as client/window/static edge in
both opaque and transparent custom-chrome modes, then apply the DWM
no-border/no-rounded-native-corner attributes. Otherwise Windows can still
paint a white non-client rim around the Flutter-drawn title bar or outside the
transparent Flutter surface.
The compact hover pill must reserve enough width for its primary 40px opacity
button even during collapsed-to-expanded animation frames, and secondary hover
controls should not enter the row until the animated width can contain them.
Detached-window roots must provide their own transparent `Material`,
`Overlay.wrap(...)`, and explicit background boundary so Flutter's default
white surface cannot appear beneath camera or screenshare tiles. Transparent
chrome must use a true `Colors.transparent` root, not a low-alpha dark fallback,
because even a tiny alpha can blend against a white native backing surface at
the edge of the secondary view. The transparent `Material` and background
boundary must wrap the local `Overlay.wrap(...)`; putting `Material` only
inside the first overlay entry still leaves tooltip/menu overlay entries
without the popout-safe surface. Transparent chrome is per open popout and must
not use the old persisted `call_popout_transparent_chrome` preference.

The shared release helper runs `flutter config --enable-windowing` by default
for desktop release builds before invoking `flutter build`, so toolchains that
expose Flutter windowing through the supported config path take that route. On
stable toolchains where `flutter config --list` reports
`enable-windowing: true (Unavailable)`, the native detached-call host applies a
desktop-only runtime guard for the internal `isWindowingEnabled` flag before it
mounts `ViewAnchor`/`RegularWindow`. Manual macOS/Windows/Linux build paths
that bypass `intergalactic/scripts/build_release.dart` must still enable the
Flutter config before validating native detached call or companion windows.
The workspace debug runners mirror that requirement: `build_menu.bat` option 2
configures `--enable-windowing` before `flutter build windows --debug`, and
`run_dev.bat` configures windowing plus
`ENABLE_NATIVE_DETACHED_CALL_WINDOWS=true` before attached `flutter run` so
DEBUG can reproduce popout and overlay errors with live logs.

Flutter widget tests are different from release/native-window validation. On
Windows, a user profile with `enable-windowing: true` can make `flutter test`
initialize Flutter's experimental windowing owner before the test body loads,
then fail with `InternalFlutterWindows_WindowManager_Initialize` when no
matching native test asset is available. Windows widget-test runs should use a
workspace-local appdata/temp profile or another isolated Flutter tool profile
that does not inherit release/native-window Flutter config from the developer's
normal user profile.

Detached call diagnostics are intentionally route-focused and export-safe. App
startup logs one `detached_call_window event=support_check` line with the build
define, platform gate, Flutter windowing gate, `forced_windowing`, final support
result, and reason. Full-call popout requests log
`call_popout event=pop_out_session` with either `route=native-session` or
`route=desktop-fallback-session`; individual stream popouts now log
`route=native-stream` when the native stream host is configured and
`route=stream-overlay` for fallback overlays. A macOS or Windows smoke should
therefore be able to prove whether a failed popout was blocked by Flutter
windowing, used the runtime guard, fell back to the in-app desktop panel, or
reached `RegularWindow` creation. If native stream-window construction or
activation fails after routing to `native-stream`, the host must log a recovered
`detached-call-window` diagnostic, mark native stream windows unavailable on the
controller, and preserve the popped stream state so the existing `FloatingTile`
fallback can render the panel in-app.
