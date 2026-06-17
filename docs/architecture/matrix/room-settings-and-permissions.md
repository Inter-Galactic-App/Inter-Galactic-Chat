# Room Settings And Permissions

Date: 2026-04-25

## Ownership

Room settings live under
`intergalactic/lib/ui/pages/settings/categories/room/`. Matrix room settings
should prefer the shared `Room` contract first, then use `MatrixRoom` only when
the feature needs Matrix-specific state or permission behavior.

## Current Contextual IA

Room Settings now use contextual tabs for Notifications, Appearance, Security,
Emoticons, Members, Admin Settings, Permissions, Calendar when available, and
Developer when enabled. Space Settings use the matching space-focused set:
Notifications, Emoticons, Soundboard, Members, Admin Settings, Permissions,
and Developer.

Notifications owns push-rule mode, read receipts, typing indicators, and local
custom sound/volume overrides for the current room or space. Room Security owns
access controls: encryption, room visibility, and Matrix room-history
visibility. Admin Settings owns identity/profile controls, Matrix addresses,
and room events where that context supports them. Appearance is now local
message-background and bubble styling; Matrix room profile editing moved out of
the Appearance page into Admin Settings.

The Permissions tab owns power-level requirements such as who may change
`m.room.history_visibility`; it does not own the current room-history value.
The visible value control is in Room Settings -> Security -> Room History.

Matrix-backed Space settings may reuse the room-backed widgets because Matrix
spaces are backed by Matrix rooms. Use `SpaceMatrixRoomBuilder` when a page
needs a `MatrixRoom`: it reuses an existing client room wrapper when one is
already registered, creates a temporary wrapper only when needed, and closes
only the wrapper it owns during widget update/dispose.

## Members Tab

The room Members tab is a Matrix room settings surface for changing member
power levels. It uses the same role thresholds shown in the Permissions tab:

- Admin: `100`
- Moderator: `50`
- Calendar Moderator: `25`, when the room exposes the calendar role
- Member: `0`

Members are the draggable entries. Role rows are fixed buckets. Dragging is
enabled only when `room.permissions.canChangeRoles` is true.

Saving role changes should go through `Room.setMemberRole(...)` so Matrix
adapter behavior, sync waiting, and future room implementations stay behind the
shared room API. The Matrix adapter owns the raw `m.room.power_levels` write
needed for Matrix room-version compatibility. In room version 12 and newer,
room creators must not appear in `content.users`, so `MatrixRoom.setMemberRole`
strips immutable creator entries before writing updated power levels.

## Permissions Tab

The Permissions tab remains the owner for changing power-level requirements for
room actions and state events. It moves permission entries between the same
role thresholds, but it does not own member assignment.

## Local Room Appearance Overrides

Room appearance settings may include local-only personal overrides when the
setting should affect just the current device. Message backgrounds use this
model: the app-wide default lives in app Appearance settings, and a room can
override it by storing a local path keyed by `Room.localId`.

These local overrides must not write Matrix room state, Matrix account data, or
custom message events. Clearing a room override should return the room to the
app-wide default instead of removing the default itself.

## Change Guidance

When changing room roles or permissions:

- keep member privilege editing separate from permission-requirement editing
- gate role changes through `room.permissions.canChangeRoles`
- preserve Matrix server-side validation instead of trying to fully predict it
  in the UI
- keep room version 12 creator power-level handling inside `MatrixRoom` rather
  than duplicating raw power-level writes in UI widgets
- keep calendar-specific `25` handling aligned between Members and Permissions
  views
