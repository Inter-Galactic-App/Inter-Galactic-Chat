# Notification Companion Overlay

The notification companion overlay is a desktop MVP for showing an opt-in
ambient message surface for approved message notifications.

## Policy Boundary

`NotificationManager` is still the notification policy boundary. The companion
controller receives `MessageNotificationContent` only after notifications are
enabled and every notification modifier has returned non-null content. This
keeps active-room suppression, mute-derived suppression, Matrix push-rule
decisions, and platform-specific notification behavior authoritative.

The companion does not replace pushers or remote push registration. When a
desktop companion host is available and the companion is enabled, desktop
notifiers suppress native message notifications so the same message is not
visually delivered in both the companion and a system notification. The
existing local notification sound path still plays before the native
notification is suppressed. Call and calendar reminder notifications continue
to use their native platform notification paths.

## Controller Surface

`NotificationCompanionController` converts approved message notification content into `NotificationCompanionMessage` values. It stores display-only fields, applies companion-specific preview redaction, and exposes a broadcast state stream consumed by the desktop overlay host.

The controller keeps pending companion notifications until the app clears notifications for the matching room/client through `NotificationManager.clearNotifications(room)`. This lets the overlay show a pending count and then return to the avatar state when the app has cleared the room notification state.

`NotificationManager` also reconciles companion pending state after foreground
client sync. If the room/client for a pending companion message no longer has a
displayed unread notification count, such as after the same account marks the
room read from another device, the companion removes that pending message
and, on desktop builds, asks the active notifier to clear native notifications
for the same client/room route. This keeps Windows toasts shown before the
overlay was available, or while the companion was disabled, from outliving the
cleared Matrix unread state without changing pushers, Matrix push rules, or room
read state.

Disabling the companion clears the pending companion display state. While the
preference is off, state emissions from room notification cleanup must not
create or keep a companion window.

Click handling uses `EventBus.openRoomFromNotification((roomId, clientId))` so companion clicks follow the same navigation path as notification responses.

The controller also records whether the desktop overlay host is available and
whether its secondary window is open. That lets desktop notifiers suppress
message notifications during the first approved notification even if the
companion window is being created from that same event.

## Desktop Host

`NotificationCompanionHost` is currently supported only on Windows when the
native detached-window build define and Flutter windowing are available.
The macOS host remains disabled: its runner cannot enable Flutter multi-view
after the implicit view attaches. In that state `overlayHostAvailable` stays
false and macOS message notifications use the normal Darwin local notification
path rather than being suppressed for a companion window that cannot exist.

Windows creates a fixed-size secondary `RegularWindow` through `ViewAnchor`
and applies HWND styling for overlay behavior:

- topmost window placement
- frameless chrome
- tool-window extended style so it does not appear in the taskbar
- pointer drag movement through `SetWindowPos`
- persisted x/y window position in local preferences

Because the companion window is mostly transparent, the Windows host also
strips residual system menu/minimize/maximize and extended edge styles,
disables DWM rounded corners, and asks DWM not to draw a frame border. This
prevents system-drawn corner artifacts from appearing inside the transparent
canvas while keeping the main app custom title bar and notification policy
separate.

Non-IO builds use the stub host; unsupported desktop platforms do not create
an overlay.

Drag movement is anchored to the Windows cursor screen position. On drag start,
the host records the current HWND origin and `GetCursorPos`; on each drag
update, it moves the window to the original origin plus the absolute cursor
delta. This avoids feedback jitter from accumulating Flutter-local pan deltas
while the native window itself is moving.

Placement uses the monitor containing the companion window, not the full
virtual desktop. The host asks Windows for the nearest monitor with
`MonitorFromRect`, reads its rectangle with `GetMonitorInfoW`, and passes those
bounds to the Flutter overlay so multi-monitor edge behavior responds at each
screen's edge.

The companion stores the last dragged window origin in local preferences and
restores it on the next app launch. Restored positions are clamped against the
nearest monitor bounds so an old multi-monitor coordinate does not strand the
overlay off-screen.

## Visual Surface

The companion window uses PNG assets under `intergalactic/assets/images/notification_companion/`. The user can choose `app_icon_light_avatar` or `app_icon_dark_avatar` in App Settings > Desktop Companion on supported desktop platforms. When no companion notifications are pending, the chosen `_avatar.png` image is shown by itself.

When one or more notifications are pending, the companion switches to the matching `_blank.png` image and overlays the pending notification count over the avatar artwork. Clicking the avatar/count opens the latest pending room through the normal notification click route and brings the main app window forward. The newest notification shows a system-theme-colored speech bubble for 10 seconds with room name, sender, and message text. The caret button next to the avatar expands the pending notification list; selecting a list item opens that room through the same route.

The overlay intentionally stays compact so the transparent window frame does
not dominate the desktop. The default message bubble is pinned by its lower
right corner close to the avatar, so it grows left and upward as text wraps.
When the companion is near another screen edge, the same nearest-icon-corner
rule flips: upper-left placement pins the bubble below the icon and grows right
and downward, upper-right grows left and downward, and lower-left grows right
and upward. Idle animation pauses while the user drags the companion so
repositioning stays stable. The bubble and caret menu resolve their placement
from the companion window's current screen position: near the top edge they
open below the avatar, near the bottom edge they open above it, near the left
edge they align inward from the left, and the normal/default layout stays
right-aligned near the avatar.

The caret menu grows away from the companion avatar. In the default above-avatar
layout, the menu keeps its lower edge above the avatar/caret and grows upward
as more notifications are present, then scrolls within the available space. In
the top-edge below-avatar layout, it keeps its upper edge below the avatar and
grows downward within the transparent overlay window. The menu renders every
pending companion message in newest-first order and uses the bounded scroll
area for overflow.

The drag affordance uses the Windows hand cursor mapping because Flutter's
grab/grabbing cursor did not show a visible native cursor change in this
Windows overlay path.

## Privacy

Preview text is redacted to `New message` when companion previews are disabled. If the local client is currently screen sharing and screen-sharing privacy is enabled, the same redaction applies for newly approved companion messages.

The companion defaults to disabled and must be explicitly enabled in the Desktop Companion settings tab. Notification Settings may link to or summarize companion state, but the companion tab is the user-facing home for companion behavior and avatar preferences.
