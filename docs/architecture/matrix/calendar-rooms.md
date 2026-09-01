# Calendar Rooms

Inter Galactic calendar rooms render Matrix-backed calendar events through the
local `widgets/calendar` package. Calendar event batches are sent as
`chat.commet.calendar_events` events related to the room calendar root event.

## Event Reconciliation

- The widget may receive the same Matrix event through relation reads, sync
  timeline events, and local echoes. Incoming calendar batches must be
  idempotent by Matrix `event_id`; a repeated batch replaces existing display
  entries for that same event id instead of appending duplicates.
- Local pending edits use entries with no Matrix `eventId`. When the confirmed
  Matrix event arrives, pending entries with the same calendar UID are removed.
- Deletes are represented by Matrix redactions. The widget removes local
  display entries after successful redaction and remembers a bounded in-memory
  tombstone for redacted event ids so stale live/relation echoes cannot re-add
  deleted events before the next full reload.
- Redaction events can expose the target through either `content.redacts` or
  top-level `redacts`; handlers must support both shapes.

## Recurring Events

Deleting one occurrence of a recurring event edits the original RFC8984 event
by adding an excluded recurrence date, then redacts the superseded Matrix
event. Deleting the series redacts the Matrix event id that carried the series.
