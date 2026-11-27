# Safe Matrix Room Migration

## Purpose

A Matrix room-version upgrade is a migration, not an in-place update. Inter
Galactic treats it as such: it creates the server-managed successor, then
invites source-room members, and gives an administrator a retryable recovery
path when the post-upgrade work is incomplete.

## Availability

This flow is currently developer-only while real-homeserver migration and
recovery validation remains open. With Developer Mode off, Room Admin shows
only the read-only current room version; it does not expose migration,
recovery, or predecessor-history controls. `/roomupgrade` is likewise omitted
from command discovery and rejected if invoked while Developer Mode is off.

## Flow

1. Room Admin loads stable versions from the homeserver capabilities endpoint
   only while Developer Mode is enabled. Turning it off discards an in-flight
   result; turning it back on starts a fresh load.
2. Before calling the destructive Matrix upgrade endpoint, the client obtains
   the source room's complete joined-member list.
3. Matrix creates the successor and tombstones the source. Existing timeline
   history remains only in the source room.
4. The client waits for the successor to reach sync, then invites only source
   members who are neither joined nor already invited there.
5. Individual invite failures are reported as incomplete, not as a failed room
   upgrade. The source room's `m.room.tombstone.replacement_room` supplies the
   successor ID for a later recovery run.

## Recovery

The Room Admin page detects a tombstone even when the upgrade originated in an
older client. It exposes:

- **Open successor** to continue in the replacement room.
- **Recover missing members** for an administrator with invite permission.

Recovery re-fetches the source joined members and successor joined/invited
members every time. It invites only the difference, so retrying cannot create
another successor or repeat a successful invitation.

Recovery does not blindly rewrite an existing successor `m.room.power_levels`
event. It retries a failed first write only while that client's observed
successor power-level content is unchanged, or if the successor has no
power-level state. An administrator's later edit changes that content and is
preserved. After a
restart there is no in-memory failed-write evidence, so an existing but
incorrect successor state needs explicit administrator review rather than an
automatic overwrite.

The successor's `m.room.create.predecessor.room_id` is also rendered as an
**Open history** link. This preserves bidirectional room-version navigation:
users can move from old to new and from new to the old timeline. It does not
merge two Matrix room event graphs into one scrollable timeline.

## Deliberate limits

- Matrix room IDs and history cannot be preserved by an upgrade.
- The migration does not claim to copy history, memberships, aliases, or other
  state that the protocol does not transfer.
- Real-homeserver smoke is required for upgrade, sync timing, permissions, and
  membership outcomes. The focused unit coverage protects the idempotent
  missing-member calculation only.

## Implementation anchors

- `intergalactic/lib/client/matrix/matrix_room_migration.dart`
- `intergalactic/lib/ui/pages/settings/categories/room/admin/room_admin_room_classification_settings.dart`
- `intergalactic/test/client/matrix/matrix_room_migration_test.dart`
