# macOS platform integration

## Scope

This page maps the macOS runner, window bootstrap, and permission boundary that
connects the native desktop host to the shared Flutter application. It is not a
signing, notarization, release, or plugin implementation guide.

## Host runner and lifecycle

`intergalactic/macos/Runner/AppDelegate.swift` is the native application
delegate. Its current responsibilities are intentionally narrow:

- It terminates the application when the last window closes.
- It opts into secure restorable state.

It does not define a macOS-specific method channel or a custom native lifecycle
bridge. Shared Dart and Flutter code continue to own feature behavior after the
Flutter engine starts. Do not add parallel client, navigation, or Matrix-session
lifecycle logic to the runner; use the shared lifecycle boundaries documented in
[`client-lifecycle.md`](client-lifecycle.md).

## Flutter window bootstrap

`intergalactic/macos/Runner/MainFlutterWindow.swift` creates the
`FlutterViewController`, preserves the Interface Builder window frame while
installing it as the content view controller, and registers generated plugins.

The native window owns macOS frame and application-window setup. Flutter owns
the view tree and feature UI after this handoff. Window behavior implemented in
Dart should follow the shared desktop UI architecture; this runner is not a
second routing shell.

## Permissions and sandbox boundary

The Runner target is sandboxed in both debug and release configurations. Its
declared capabilities cover:

- camera and microphone input;
- user-selected read/write file access;
- network client and server access.

`DebugProfile.entitlements` additionally allows JIT for debug execution; that
debug-only entitlement is not part of the release capability set.

`Info.plist` provides the user-facing purpose strings for camera, microphone,
and screen capture. A purpose string explains a prompted capability; it is not
authorization to access the resource. Keep an entitlement, its purpose string,
and the calling feature consistent when adding or removing native access.

## Configuration boundary

`Runner/Configs/AppInfo.xcconfig` supplies the product name, bundle identifier,
and copyright used by the Runner target. `Info.plist` consumes those build
settings and defines the minimum macOS version through the Flutter build
