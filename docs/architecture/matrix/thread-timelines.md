# Matrix Thread Timelines

Status: current
Last updated: 2026-06-25

## Purpose

Inter Galactic renders Matrix `m.thread` replies through a derived
`MatrixThreadTimeline` rather than showing thread replies directly in the parent
room timeline. The thread timeline listens to the parent `MatrixTimeline` so
pending sends, edits, redactions, and synced relation updates appear while the
thread panel stays open.

## Ordering Contract

Thread timelines keep the same newest-first event list contract as room
timelines:

- index `0` is the newest/latest side and renders at the bottom of the chat
  panel
- older history is stored at larger indices and renders toward the top
- the thread root/original message must be kept at the far history end so it
  stays pinned at the top of the thread view

When the root event arrives from a parent timeline add/change signal, the
thread timeline must resolve its insertion position to the history end instead
of using parent index `0`. If a previously tracked root is found in the wrong
position, the thread timeline removes and re-adds it at the history end so the
UI key list receives normal remove/add notifications.

## Important Files

- `intergalactic/lib/client/matrix/components/threads/matrix_thread_timeline.dart`
  owns thread membership, history fetches, live parent-timeline updates, and the
  root-placement invariant.
- `intergalactic/lib/client/matrix/components/threads/matrix_threads_component.dart`
  creates Matrix thread timelines and updates the parent root after thread
  sends.
- `intergalactic/lib/ui/molecules/timeline_events/timeline_view_entry.dart`
  renders the "Original message" pinned root treatment for thread timelines.
- `intergalactic/test/client/matrix/matrix_threads_component_test.dart`
  covers attachment-only thread sends, redaction refresh, and root placement.

## Validation

Focused validation should include:

- `dart format` on touched thread timeline/UI/test files
- `flutter test --no-pub intergalactic/test/client/matrix/matrix_threads_component_test.dart`
- targeted `flutter analyze --no-pub` on touched thread timeline/UI/test files
- rebuilt-app smoke opening a thread with existing replies and confirming the
  original message remains pinned at the top after new replies, edits, or
  timeline refreshes
