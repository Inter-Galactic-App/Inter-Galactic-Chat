import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/ui/organisms/room_pinned_messages/room_pinned_messages_loader.dart';

void main() {
  group('loadPinnedTimelineEvents', () {
    test('keeps the readable pins when one pin fails to load', () async {
      final first = _FakeTimelineEvent(r'$one');
      final third = _FakeTimelineEvent(r'$three');
      final room = _FakeRoom({
        r'$one': () async => first,
        r'$two': () async => throw StateError('event read exploded'),
        r'$three': () async => third,
      });
      final errors = <String>[];

      final events = await loadPinnedTimelineEvents(room, const [
        r'$one',
        r'$two',
        r'$three',
      ], onError: (eventId, error) => errors.add(eventId));

      expect(events.map((e) => e.eventId), [r'$one', r'$three']);
      expect(errors, [r'$two']);
    });

    test('drops pins the room cannot resolve at all', () async {
      final kept = _FakeTimelineEvent(r'$kept');
      final room = _FakeRoom({
        r'$kept': () async => kept,
        r'$gone': () async => null,
      });

      final events = await loadPinnedTimelineEvents(room, const [
        r'$kept',
        r'$gone',
      ]);

      expect(events.map((e) => e.eventId), [r'$kept']);
    });

    test('keeps every pin when all of them load', () async {
      final room = _FakeRoom({
        r'$one': () async => _FakeTimelineEvent(r'$one'),
        r'$two': () async => _FakeTimelineEvent(r'$two'),
      });

      final events = await loadPinnedTimelineEvents(room, const [
        r'$one',
        r'$two',
      ]);

      expect(events.map((e) => e.eventId), [r'$one', r'$two']);
      expect(room.plainGetEventCalls, 0);
    });
  });
}

class _FakeRoom implements Room {
  _FakeRoom(this.responses);

  final Map<String, Future<TimelineEvent?> Function()> responses;

  int plainGetEventCalls = 0;

  /// The pinned list must read through the decrypting accessor. Reading the
  /// plain [getEvent] is what leaves an encrypted pin unreadable, so this fake
  /// records it rather than serving it.
  @override
  Future<TimelineEvent?> getEvent(String eventId) {
    plainGetEventCalls++;
    return Future.value(null);
  }

  @override
  Future<TimelineEvent?> getDecryptedEvent(String eventId) {
    final response = responses[eventId];
    if (response == null) {
      return Future.value(null);
    }
    return response();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimelineEvent implements TimelineEvent<Client> {
  _FakeTimelineEvent(this.eventId);

  @override
  final String eventId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
