import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/room_open_decrypt_retry.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';

void main() {
  group('RoomOpenDecryptRetryCoordinator', () {
    test('retries once for loaded encrypted events in an E2EE room', () async {
      final room = _FakeRoom(identifier: '!room:example.org', isE2EE: true);
      final timeline = _FakeTimeline(
        room: room,
        events: [_FakeEncryptedEvent(eventId: r'$event1')],
      );
      final coordinator = RoomOpenDecryptRetryCoordinator(
        now: () => DateTime.utc(2026, 6, 2, 17),
      );

      final retried = await coordinator.maybeRetryForLoadedTimeline(timeline);

      expect(retried, isTrue);
      expect(room.retryDecryptCount, 1);
    });

    test('skips non-E2EE rooms', () async {
      final room = _FakeRoom(identifier: '!room:example.org', isE2EE: false);
      final timeline = _FakeTimeline(
        room: room,
        events: [_FakeEncryptedEvent(eventId: r'$event1')],
      );
      final coordinator = RoomOpenDecryptRetryCoordinator();

      final retried = await coordinator.maybeRetryForLoadedTimeline(timeline);

      expect(retried, isFalse);
      expect(room.retryDecryptCount, 0);
    });

    test('skips E2EE timelines without encrypted placeholders', () async {
      final room = _FakeRoom(identifier: '!room:example.org', isE2EE: true);
      final timeline = _FakeTimeline(room: room);
      final coordinator = RoomOpenDecryptRetryCoordinator();

      final retried = await coordinator.maybeRetryForLoadedTimeline(timeline);

      expect(retried, isFalse);
      expect(room.retryDecryptCount, 0);
    });

    test('applies a per-room cooldown window', () async {
      var now = DateTime.utc(2026, 6, 2, 17);
      final room = _FakeRoom(identifier: '!room:example.org', isE2EE: true);
      final timeline = _FakeTimeline(
        room: room,
        events: [_FakeEncryptedEvent(eventId: r'$event1')],
      );
      final coordinator = RoomOpenDecryptRetryCoordinator(now: () => now);

      expect(await coordinator.maybeRetryForLoadedTimeline(timeline), isTrue);
      expect(await coordinator.maybeRetryForLoadedTimeline(timeline), isFalse);
      expect(room.retryDecryptCount, 1);

      now = now.add(defaultRoomOpenDecryptRetryCooldown);
      expect(await coordinator.maybeRetryForLoadedTimeline(timeline), isTrue);
      expect(room.retryDecryptCount, 2);
    });
  });
}

class _FakeClient implements Client {
  @override
  String get identifier => 'fake-client';

  @override
  bool get supportsE2EE => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom({
    required this.identifier,
    required this.isE2EE,
  });

  @override
  final String identifier;

  @override
  final bool isE2EE;

  @override
  final Client client = _FakeClient();

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  Timeline? get timeline => null;

  int retryDecryptCount = 0;

  @override
  Future<void> retryDecryptAll() async {
    retryDecryptCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({
    required Room room,
    List<TimelineEvent> events = const [],
  }) {
    this.room = room;
    client = room.client;
    this.events = List<TimelineEvent>.from(events);
  }

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  Future<void> close() async {}

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeEncryptedEvent implements TimelineEventEncrypted {
  _FakeEncryptedEvent({required this.eventId});

  @override
  final String eventId;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => '';

  @override
  String get senderId => '@sender:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 6, 2, 17);

  @override
  String get source => '';

  @override
  bool get editable => false;

  @override
  Future<TimelineEvent?> attemptDecrypt(Room room) async => null;
}
