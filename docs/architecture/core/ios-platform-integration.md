# iOS platform integration

## Scope

This page maps the iOS runner and extension boundaries that connect native iOS
behavior to the shared Flutter application. It is not a signing, export, privacy,
or distribution guide.

## Host runner

`intergalactic/ios/Runner/AppDelegate.swift` is the native host boundary. It
initializes Flutter integration and owns native method-channel entry points.
Shared Dart code owns cross-platform feature behavior after a channel handoff.

The runner also owns native lifecycle entry points: application launch,
foreground return, accepted app URLs, and platform permission requests. Keep
platform callbacks narrow; do not add iOS-only routing that bypasses the shared
Dart flow.

## Notifications

The runner receives native notification responses, retains pending responses
until Flutter can consume them, and delivers them through the notification
bridge. Shared Dart routing decides the resulting app navigation and acknowledges
completed consumption back to the native side.

For notifier, pusher, and route behavior, use
[`notifications/notifications.md`](../notifications/notifications.md) and
[`notifications/push-pipeline.md`](../notifications/push-pipeline.md).

## Inbound sharing

The Share Extension classifies and stages shareable content in the shared app
container. It does not compose or send messages. The host app reads staged
sessions through the inbound-share bridge and explicitly reserves, accepts, or
rejects them; that host decision is the consumption boundary.

The broader Matrix media and composer path is documented in
[`matrix/media-pipeline.md`](../matrix/media-pipeline.md).

## Broadcast extension

The Broadcast Extension has its own capture and upload lifecycle. It exchanges
only the required handoff state with the host app; the runner and Flutter UI do
not directly own extension capture callbacks.

## Release boundary

Entitlements, capabilities, and platform packaging must remain consistent with
this topology. Release validation and distribution responsibilities are covered
by [`release/release-targets.md`](../release/release-targets.md).
