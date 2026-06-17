import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:intergalactic/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('MatrixThreadsComponent.sendMessage', () {
    test('allows attachment-only thread sends without requiring a text event',
        () async {
      final rootEvent = _event(
        eventId: r'$root',
        content: const {'body': 'root'},
      );
      final timeline = _FakeMatrixTimeline(
        events: [_timelineEvent(rootEvent)],
      );
      final room = _FakeMatrixRoom(
        timeline: timeline,
        sendMessageResult: null,
      );
      final component = MatrixThreadsComponent(_FakeMatrixClient());

      await component.sendMessage(
        threadRootEventId: r'$root',
        room: room,
        processedAttachments: <ProcessedAttachment>[],
      );

      expect(room.sendMessageCallCount, 1);
      expect(timeline.recordedAggregatedEvents, isEmpty);
      expect(timeline.changedIndices, [0]);
    });

    test('still aggregates a thread text event into the room timeline',
        () async {
      final rootEvent = _event(
        eventId: r'$root',
        content: const {'body': 'root'},
      );
      final replyEvent = _event(
        eventId: r'$reply',
        content: const {
          'm.relates_to': {
            'event_id': r'$root',
            'rel_type': matrix.RelationshipTypes.thread,
          },
        },
      );
      final timeline = _FakeMatrixTimeline(
        events: [_timelineEvent(rootEvent)],
      );
      final room = _FakeMatrixRoom(
        timeline: timeline,
        sendMessageResult: _timelineEvent(replyEvent),
      );
      final component = MatrixThreadsComponent(_FakeMatrixClient());

      final result = await component.sendMessage(
        threadRootEventId: r'$root',
        room: room,
        message: 'hello',
      );

      expect(result, isA<MatrixTimelineEvent>());
      expect(room.sendMessageCallCount, 1);
      expect(
        timeline.recordedAggregatedEvents.map((event) => event.eventId),
        [r'$reply'],
      );
      expect(timeline.changedIndices, [0]);
    });
  });

  group('MatrixThreadTimeline', () {
    test('updates a tracked thread event even after redaction removes relation',
        () async {
      final rootEvent = _timelineEvent(_event(
        eventId: r'$root',
        content: const {'body': 'root'},
      ));
      final replyEvent = _timelineEvent(_event(
        eventId: r'$reply',
        content: const {
          'm.relates_to': {
            'event_id': r'$root',
            'rel_type': matrix.RelationshipTypes.thread,
          },
        },
      ));
      final redactedReplyEvent = _timelineEvent(_event(
        eventId: r'$reply',
        content: const {},
        unsigned: {
          'redacted_because': {
            'content': {},
            'event_id': r'$redaction',
            'origin_server_ts': 0,
            'room_id': '!room:example.org',
            'sender': '@user:example.org',
            'type': matrix.EventTypes.Redaction,
          },
        },
      ));
      final mainTimeline = _FakeMatrixTimeline(
        events: [rootEvent, replyEvent],
      );
      final threadTimeline = MatrixThreadTimeline(
        client: _FakeMatrixClient(),
        room: _FakeMatrixRoom(timeline: mainTimeline),
        threadRootId: r'$root',
        mainRoomTimeline: mainTimeline,
        component: MatrixThreadsComponent(_FakeMatrixClient()),
      );
      threadTimeline.events.add(replyEvent);

      final changedIndices = <int>[];
      final sub = threadTimeline.onChange.stream.listen(changedIndices.add);

      mainTimeline.events[1] = redactedReplyEvent;
      threadTimeline.onMainTimelineEventChanged(1);
      await Future<void>.delayed(Duration.zero);

      expect(threadTimeline.events.single.eventId, r'$reply');
      expect(
          (threadTimeline.events.single as MatrixTimelineEvent).event.redacted,
          isTrue);
      expect(changedIndices, [0]);

      await sub.cancel();
      await threadTimeline.close();
    });
  });
}

matrix.Event _event({
  required String eventId,
  required Map<String, dynamic> content,
  Map<String, dynamic>? unsigned,
}) {
  return matrix.Event(
    content: content,
    type: matrix.EventTypes.Message,
    eventId: eventId,
    senderId: '@user:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    room: _FakeSdkRoom(),
    unsigned: unsigned,
  );
}

MatrixTimelineEvent _timelineEvent(matrix.Event event) {
  return MatrixTimelineEventUnknown(
    event,
    client: _FakeMatrixClient(),
  );
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixRoom implements MatrixRoom {
  _FakeMatrixRoom({
    this.timeline,
    this.sendMessageResult,
  });

  @override
  final Timeline? timeline;

  final MatrixTimelineEvent? sendMessageResult;

  int sendMessageCallCount = 0;

  @override
  Future<TimelineEvent?> sendMessage({
    String? message,
    TimelineEvent? inReplyTo,
    TimelineEvent? replaceEvent,
    String? threadRootEventId,
    String? threadLastEventId,
    Map<String, dynamic>? fileExtraContent,
    List<ProcessedAttachment>? processedAttachments,
  }) async {
    sendMessageCallCount += 1;
    return sendMessageResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixTimeline extends Timeline implements MatrixTimeline {
  _FakeMatrixTimeline({
    required List<TimelineEvent> events,
  }) {
    this.events = List<TimelineEvent>.from(events);
    for (final event in events) {
      _eventsById[event.eventId] = event;
    }
  }

  final List<int> changedIndices = <int>[];
  final List<matrix.Event> recordedAggregatedEvents = <matrix.Event>[];
  final Map<String, TimelineEvent> _eventsById = <String, TimelineEvent>{};
  final StreamController<void> _loadingStatusChangedController =
      StreamController<void>.broadcast();

  @override
  Client get client => _FakeMatrixClient();

  @override
  Room get room => _FakeMatrixRoom(timeline: this);

  @override
  bool get isLoadingHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  @override
  matrix.Timeline? get matrixTimeline =>
      _FakeSdkTimeline(recordedAggregatedEvents);

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  Future<void> close() async {
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
    await _loadingStatusChangedController.close();
  }

  @override
  Future<void> deleteEvent(TimelineEvent event) async {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async =>
      _eventsById[eventId];

  @override
  bool isEventRedacted(TimelineEvent event) =>
      (event as MatrixTimelineEvent).event.redacted;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}

  @override
  void notifyChanged(int index) {
    changedIndices.add(index);
    onChange.add(index);
    _eventsById[events[index].eventId] = events[index];
  }

  @override
  TimelineEvent? tryGetEvent(String eventId) => _eventsById[eventId];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkTimeline implements matrix.Timeline {
  _FakeSdkTimeline(this.recordedAggregatedEvents);

  final List<matrix.Event> recordedAggregatedEvents;

  @override
  void addAggregatedEvent(matrix.Event event) {
    recordedAggregatedEvents.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
