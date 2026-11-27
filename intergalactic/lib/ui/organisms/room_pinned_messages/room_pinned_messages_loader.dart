import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

/// Loads the timeline events for a room's pinned message ids.
///
/// Reads are independent: a pinned id that fails to load - the event was
/// redacted away, the server refuses it, the read throws - is dropped from the
/// result instead of failing the whole batch, so one bad pin cannot empty the
/// pinned messages list.
///
/// Events that could not be decrypted are *not* dropped:
/// [Room.getDecryptedEvent] returns the still-encrypted event, so the pin
/// keeps rendering its placeholder instead of vanishing from the list.
Future<List<TimelineEvent>> loadPinnedTimelineEvents(
  Room room,
  Iterable<String> eventIds, {
  void Function(String eventId, Object error)? onError,
}) async {
  final results = await Future.wait(
    eventIds.map((id) async {
      try {
        return await room.getDecryptedEvent(id);
      } catch (error) {
        onError?.call(id, error);
        return null;
      }
    }),
  );

  return results.whereType<TimelineEvent>().toList(growable: false);
}
