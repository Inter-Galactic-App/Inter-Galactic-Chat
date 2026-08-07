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

## Upgrading

Re-vendor the new upstream version and re-apply both patches (or drop them if
upstream fixes multi-window delegate scoping and the version check).
