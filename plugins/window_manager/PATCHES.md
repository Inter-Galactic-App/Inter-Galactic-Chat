# Inter Galactic Patches

Vendored from pub.dev `window_manager 0.5.1` (MIT, LICENSE unchanged) and
consumed through a `dependency_overrides` path entry in
`intergalactic/pubspec.yaml`. `example/` and `test/` are omitted; all other
files are unmodified upstream except the patches below.

## 1. Scope the WindowProc delegate to the plugin's own window

`windows/window_manager_plugin.cpp` (`HandleWindowProc`) and
`windows/window_manager.cpp` (`native_window` initialization).

Flutter's `RegisterTopLevelWindowProcDelegate` delivers messages for every
top-level Flutter window, including multi-window `RegularWindow` popouts
(`engine .../windows/host_window.cc` routes host-window messages through the
same delegate manager). Upstream applied hidden-title-bar `WM_NCCALCSIZE`
insets (8px left/right/bottom), `WM_NCHITTEST`/min-max/prevent-close
overrides, and window events to all of them. On detached call/stream popouts
that stolen non-client band rendered as a white border, most visibly in
transparent mode. The delegate now returns early for any window that is not
`window_manager`'s own main window.

## 2. Correct the inverted `IsWindows11OrGreater` build check

Upstream returned `dwBuild < 22000`, which is true on Windows 10 and false on
Windows 11 — inverted relative to its name and usage. Real Windows 11 machines
therefore took the "Windows 10 white line" workaround (`rgrc[0].top += 1`) and
showed a 1px light strip above the custom title bar, while Windows 10 machines
skipped the workaround they needed. The check now returns `dwBuild >= 22000`.

## 3. Make the macOS `mainWindow` getter nil-safe (SIGILL guard)

`macos/window_manager/Sources/window_manager/WindowManager.swift`
(`mainWindow` getter and `isFocused()`).

Upstream's `mainWindow` computed property force-unwraps `_mainWindow!`. An
`isFocused` (or other) method-channel call can arrive before the window
registers or during teardown, while `_mainWindow` is still nil — the
force-unwrap then crashes the app with `EXC_BAD_INSTRUCTION` (SIGILL). The
getter now falls back to `NSApplication.shared.mainWindow` / `keyWindow` /
`windows.first`, and finally a throwaway `NSWindow()`, instead of unwrapping.
`isFocused()` additionally guards on `_mainWindow` and returns `false` when no
real window is registered (a throwaway fallback window is never key).

Discovered during the WebRTC 1.5.2 macOS spike
(`docs/agent-control/ios/webrtc-1.5.2-phase0a-ios-handoff-2026-07-11.md`);
pre-existing and unrelated to that migration.

## Upgrading

Re-vendor the new upstream version and re-apply all three patches (or drop them
if upstream fixes multi-window delegate scoping, the version check, and the
macOS nil-unwrap).
