import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/widget/privelidged_matrix_widget_runner.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_widget_api/capabilities.dart';
import 'package:matrix_widget_api/types.dart';

void main() {
  test('grants only the approved calendar capability set', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('m.room.power_levels'),
      MatrixCapability.sendEvent('chat.commet.calendar_create'),
    ]);

    expect(fixture.runner.grantedCapabilities, [
      MatrixCapability.sendEvent('chat.commet.calendar_create'),
    ]);
  });

  test(
    'rejects an ungranted non-calendar state write before its Matrix sink',
    () async {
      final fixture = _Fixture();
      final result = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {'type': 'm.room.power_levels', 'state_key': '', 'content': const {}},
      );

      expect(result, contains('error'));
      expect(fixture.client.stateWrites, isZero);
    },
  );

  test('permits the current user calendar state write', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.setRoomState(
        'chat.commet.calendar_event',
        stateKey: '@me:example.org',
      ),
    ]);

    final result = await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
      'type': 'chat.commet.calendar_event',
      'state_key': '@me:example.org',
      'content': const {'events': {}},
    });

    expect(result['event_id'], r'$state');
    expect(fixture.client.stateWrites, 1);
  });

  test('permits only the registry-shaped calendar list state', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.setRoomState('chat.commet.calendars'),
    ]);

    final allowed = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'chat.commet.calendars',
        'state_key': '',
        'content': const {
          'calendars': [r'$calendar'],
        },
      },
    );
    final rejected = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'chat.commet.calendars',
        'state_key': '',
        'content': const {'calendars': 'not-a-list'},
      },
    );

    expect(allowed['event_id'], r'$state');
    expect(rejected, contains('error'));
    expect(fixture.client.stateWrites, 1);
  });

  test('permits the first event immediately after a registry write', () async {
    final fixture = _Fixture();
    fixture.room.registryCalendarIds = const {};
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('chat.commet.calendar_create'),
      MatrixCapability.setRoomState('chat.commet.calendars'),
      MatrixCapability.sendEvent('chat.commet.calendar_events'),
    ]);

    final rootCreate = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {'type': 'chat.commet.calendar_create', 'content': const {}},
    );
    final registryWrite = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'chat.commet.calendars',
        'state_key': '',
        'content': const {
          'calendars': [r'$new-calendar'],
        },
      },
    );
    final firstEvent = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'chat.commet.calendar_events',
        'content': const {
          'm.relates_to': {
            'event_id': r'$new-calendar',
            'rel_type': 'm.reference',
          },
        },
      },
    );

    expect(rootCreate['event_id'], r'$new-calendar');
    expect(registryWrite['event_id'], r'$state');
    expect(firstEvent['event_id'], r'$timeline');
    expect(fixture.client.stateWrites, 1);
    expect(fixture.room.timelineSends, 2);
  });

  test('rejects a registry entry that is not a calendar root', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('chat.commet.calendar_create'),
      MatrixCapability.setRoomState('chat.commet.calendars'),
    ]);
    await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
      'type': 'chat.commet.calendar_create',
      'content': const {},
    });

    final result = await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
      'type': 'chat.commet.calendars',
      'state_key': '',
      'content': const {
        'calendars': [r'$non-calendar-event'],
      },
    });

    expect(result, contains('error'));
    expect(fixture.client.stateWrites, isZero);
  });

  test('a poisoned synced registry cannot authorize sends or reads', () async {
    final fixture = _Fixture();
    fixture.room.registryCalendarIds = {r'$non-calendar-event'};
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('chat.commet.calendar_events'),
      MatrixCapability.receiveEvent('chat.commet.calendar_events'),
    ]);

    final sent = await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
      'type': 'chat.commet.calendar_events',
      'content': const {
        'm.relates_to': {
          'event_id': r'$non-calendar-event',
          'rel_type': 'm.reference',
        },
      },
    });
    final read = await fixture.runner
        .sendAction(FromWidgetAction.readRelations, {
          'event_id': r'$non-calendar-event',
          'event_type': 'chat.commet.calendar_events',
          'rel_type': 'm.reference',
          'limit': 100,
        });

    expect(sent, contains('error'));
    expect(read, contains('error'));
    expect(fixture.room.timelineSends, isZero);
    expect(fixture.client.relationReads, isZero);
  });

  test('does not permit a new root before its registry write', () async {
    final fixture = _Fixture();
    fixture.room.registryCalendarIds = const {};
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('chat.commet.calendar_events'),
    ]);

    final firstEvent = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'chat.commet.calendar_events',
        'content': const {
          'm.relates_to': {
            'event_id': r'$new-calendar',
            'rel_type': 'm.reference',
          },
        },
      },
    );

    expect(firstEvent, contains('error'));
    expect(fixture.room.timelineSends, isZero);
  });

  test(
    'a registry replacement immediately removes stale authorization',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.setRoomState('chat.commet.calendars'),
        MatrixCapability.sendEvent('chat.commet.calendar_events'),
      ]);

      await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
        'type': 'chat.commet.calendars',
        'state_key': '',
        'content': const {
          'calendars': [r'$new-calendar'],
        },
      });
      final staleRootEvent = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {
          'type': 'chat.commet.calendar_events',
          'content': const {
            'm.relates_to': {
              'event_id': r'$calendar',
              'rel_type': 'm.reference',
            },
          },
        },
      );

      expect(staleRootEvent, contains('error'));
      expect(fixture.room.timelineSends, isZero);
    },
  );

  test(
    'a state-only sync registry replacement revokes every removed-root action',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.setRoomState('chat.commet.calendars'),
        MatrixCapability.sendEvent('chat.commet.calendar_events'),
        MatrixCapability.sendEvent('chat.intergalactic.calendar_attendance'),
        MatrixCapability.receiveEvent('chat.commet.calendar_events'),
      ]);
      await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
        'type': 'chat.commet.calendars',
        'state_key': '',
        'content': const {
          'calendars': [r'$calendar'],
        },
      });

      fixture.runner.onSync(_syncWithRegistryState(const {'calendars': []}));
      await _settle();

      for (final type in [
        'chat.commet.calendar_events',
        'chat.intergalactic.calendar_attendance',
      ]) {
        expect(
          await fixture.runner.sendAction(FromWidgetAction.sendEvent, {
            'type': type,
            'content': const {
              'm.relates_to': {
                'event_id': r'$calendar',
                'rel_type': 'm.reference',
              },
            },
          }),
          contains('error'),
        );
      }
      expect(
        await fixture.runner.sendAction(FromWidgetAction.readRelations, {
          'event_id': r'$calendar',
          'event_type': 'chat.commet.calendar_events',
          'rel_type': 'm.reference',
          'limit': 100,
        }),
        contains('error'),
      );

      expect(fixture.room.timelineSends, isZero);
      expect(fixture.client.relationReads, isZero);
    },
  );

  test(
    'rejects a calendar state write for another user before its Matrix sink',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.setRoomState(
          'chat.commet.calendar_event',
          stateKey: '@me:example.org',
        ),
      ]);

      final result = await fixture.runner
          .sendAction(FromWidgetAction.sendEvent, {
            'type': 'chat.commet.calendar_event',
            'state_key': '@other:example.org',
            'content': const {},
          });

      expect(result, contains('error'));
      expect(fixture.client.stateWrites, isZero);
    },
  );

  test(
    'permits calendar creation but rejects non-empty creation content',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.sendEvent('chat.commet.calendar_create'),
      ]);

      final allowed = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {'type': 'chat.commet.calendar_create', 'content': const {}},
      );
      final rejected = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {
          'type': 'chat.commet.calendar_create',
          'content': const {'unexpected': true},
        },
      );

      expect(allowed['event_id'], r'$new-calendar');
      expect(rejected, contains('error'));
      expect(fixture.room.timelineSends, 1);
    },
  );

  test(
    'rejects an unrequested calendar operation before its Matrix sink',
    () async {
      final fixture = _Fixture();
      final result = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {'type': 'chat.commet.calendar_create', 'content': const {}},
      );

      expect(result, contains('error'));
      expect(fixture.room.timelineSends, isZero);
    },
  );

  test('rejects malformed relation reads before their Matrix sink', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.receiveEvent('chat.commet.calendar_events'),
    ]);

    final result = await fixture.runner
        .sendAction(FromWidgetAction.readRelations, {
          'event_id': r'$calendar',
          'event_type': 'chat.commet.calendar_events',
          'rel_type': 'm.annotation',
          'limit': 101,
        });

    expect(result, contains('error'));
    expect(fixture.client.relationReads, isZero);
  });

  test('permits registered calendar and attendance timeline events', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('chat.commet.calendar_events'),
      MatrixCapability.sendEvent('chat.intergalactic.calendar_attendance'),
    ]);

    for (final type in [
      'chat.commet.calendar_events',
      'chat.intergalactic.calendar_attendance',
    ]) {
      final result = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {
          'type': type,
          'content': const {
            'm.relates_to': {
              'event_id': r'$calendar',
              'rel_type': 'm.reference',
            },
          },
        },
      );
      expect(result['event_id'], r'$timeline');
    }

    expect(fixture.room.timelineSends, 2);
  });

  test(
    'permits a bounded relation read for a registered calendar root',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.receiveEvent('chat.commet.calendar_events'),
      ]);

      final result = await fixture.runner
          .sendAction(FromWidgetAction.readRelations, {
            'event_id': r'$calendar',
            'event_type': 'chat.commet.calendar_events',
            'rel_type': 'm.reference',
            'limit': 100,
          });

      expect(result['chunk'], isEmpty);
      expect(fixture.client.relationReads, 1);
    },
  );

  test('redacts only the current user\'s calendar timeline event', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.sendEvent('m.room.redaction'),
    ]);

    final allowed = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'm.room.redaction',
        'content': const {'redacts': r'$calendar-event'},
      },
    );
    final rejected = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'm.room.redaction',
        'content': const {'redacts': r'$foreign-event'},
      },
    );
    final nonCalendar = await fixture.runner.sendAction(
      FromWidgetAction.sendEvent,
      {
        'type': 'm.room.redaction',
        'content': const {'redacts': r'$non-calendar-event'},
      },
    );

    expect(allowed['event_id'], r'$redaction');
    expect(rejected, contains('error'));
    expect(nonCalendar, contains('error'));
    expect(fixture.room.redactions, 1);
  });

  test(
    'lookup failure rejects outgoing and skips incoming redactions',
    () async {
      final fixture = _Fixture();
      fixture.room.throwOnLookupIds.add(r'$lookup-error');
      await fixture.runner.requestCapabilities([
        MatrixCapability.sendEvent('m.room.redaction'),
        MatrixCapability.receiveEvent('m.room.redaction'),
      ]);
      final received = <String>[];
      fixture.runner.onAction(ToWidgetAction.sendEvent, (data) {
        received.add(data['data']['event_id'] as String);
        return null;
      });

      final outgoing = await fixture.runner.sendAction(
        FromWidgetAction.sendEvent,
        {
          'type': 'm.room.redaction',
          'content': const {'redacts': r'$lookup-error'},
        },
      );
      fixture.runner.onSync(
        _syncWithRedaction(
          eventId: r'$sync-lookup-error',
          redacts: r'$lookup-error',
        ),
      );
      fixture.runner.onEvent(
        _redactionEvent(
          eventId: r'$timeline-lookup-error',
          redacts: r'$lookup-error',
          room: fixture.room,
        ),
      );
      await _settle();

      expect(outgoing, contains('error'));
      expect(fixture.room.redactions, isZero);
      expect(received, isEmpty);
    },
  );

  test(
    'rejects every out-of-contract relation query before its Matrix sink',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.receiveEvent('chat.commet.calendar_events'),
      ]);
      const baseQuery = {
        'event_id': r'$calendar',
        'event_type': 'chat.commet.calendar_events',
        'rel_type': 'm.reference',
        'limit': 100,
      };

      for (final query in [
        {...baseQuery, 'event_type': 'm.room.message'},
        {...baseQuery, 'rel_type': 'm.annotation'},
        {...baseQuery, 'event_id': r'$unregistered'},
        {...baseQuery, 'limit': 101},
      ]) {
        expect(
          await fixture.runner.sendAction(
            FromWidgetAction.readRelations,
            query,
          ),
          contains('error'),
        );
      }
      expect(fixture.client.relationReads, isZero);
    },
  );

  test('relation pagination cannot change the approved query', () async {
    final fixture = _Fixture();
    await fixture.runner.requestCapabilities([
      MatrixCapability.receiveEvent('chat.commet.calendar_events'),
      MatrixCapability.receiveEvent('chat.intergalactic.calendar_attendance'),
    ]);
    const baseQuery = {
      'event_id': r'$calendar',
      'event_type': 'chat.commet.calendar_events',
      'rel_type': 'm.reference',
      'limit': 100,
    };

    final first = await fixture.runner.sendAction(
      FromWidgetAction.readRelations,
      baseQuery,
    );
    final next = await fixture.runner.sendAction(
      FromWidgetAction.readRelations,
      {...baseQuery, 'from': first['next_batch']},
    );
    final changedType = await fixture.runner
        .sendAction(FromWidgetAction.readRelations, {
          ...baseQuery,
          'event_type': 'chat.intergalactic.calendar_attendance',
          'from': first['next_batch'],
        });

    expect(next['chunk'], isEmpty);
    expect(changedType, contains('error'));
    expect(fixture.client.relationReads, 2);
  });

  test(
    'forwards only calendar-scoped redactions from sync and timeline',
    () async {
      final fixture = _Fixture();
      await fixture.runner.requestCapabilities([
        MatrixCapability.receiveEvent('m.room.redaction'),
      ]);
      final received = <String>[];
      fixture.runner.onAction(ToWidgetAction.sendEvent, (data) {
        received.add(data['data']['event_id'] as String);
        return null;
      });

      fixture.runner.onSync(
        _syncWithRedaction(
          eventId: r'$sync-non-calendar',
          redacts: r'$non-calendar-event',
        ),
      );
      fixture.runner.onEvent(
        _redactionEvent(
          eventId: r'$timeline-non-calendar',
          redacts: r'$non-calendar-event',
          room: fixture.room,
        ),
      );
      await _settle();

      expect(received, isEmpty);

      fixture.runner.onSync(
        _syncWithRedaction(
          eventId: r'$sync-calendar',
          redacts: r'$calendar-event',
        ),
      );
      fixture.runner.onEvent(
        _redactionEvent(
          eventId: r'$timeline-calendar',
          redacts: r'$calendar-event',
          room: fixture.room,
        ),
      );
      await _settle();

      expect(received, [r'$sync-calendar', r'$timeline-calendar']);
    },
  );

  test(
    'filters encrypted relation plaintext after decrypting its envelopes',
    () async {
      final fixture = _Fixture();
      final decryptedIds = <String>[];
      final events = [
        matrix.MatrixEvent(
          type: 'm.room.encrypted',
          content: const {},
          senderId: '@other:example.org',
          eventId: r'$encrypted-calendar',
          originServerTs: DateTime.utc(2026, 9, 23),
        ),
        matrix.MatrixEvent(
          type: 'm.room.encrypted',
          content: const {},
          senderId: '@other:example.org',
          eventId: r'$encrypted-message',
          originServerTs: DateTime.utc(2026, 9, 23),
        ),
      ];

      final result = await decryptAndFilterWidgetRelationEvents(
        events,
        'chat.commet.calendar_events',
        (event) async {
          decryptedIds.add(event.eventId);
          return matrix.Event(
            content: const {},
            type: event.eventId == r'$encrypted-calendar'
                ? 'chat.commet.calendar_events'
                : 'm.room.message',
            eventId: event.eventId,
            senderId: '@other:example.org',
            originServerTs: DateTime.utc(2026, 9, 23),
            room: fixture.room,
          );
        },
      );

      expect(decryptedIds, [r'$encrypted-calendar', r'$encrypted-message']);
      expect(result.map((event) => event.eventId), [r'$encrypted-calendar']);
    },
  );
}

matrix.SyncUpdate _syncWithRedaction({
  required String eventId,
  required String redacts,
}) => matrix.SyncUpdate.fromJson({
  'next_batch': 'batch',
  'rooms': {
    'join': {
      '!room:example.org': {
        'timeline': {
          'events': [
            {
              'type': 'm.room.redaction',
              'content': <String, Object?>{},
              'sender': '@other:example.org',
              'event_id': eventId,
              'origin_server_ts': 0,
              'redacts': redacts,
            },
          ],
        },
      },
    },
  },
});

matrix.SyncUpdate _syncWithRegistryState(Map<String, Object?> content) =>
    matrix.SyncUpdate.fromJson({
      'next_batch': 'batch',
      'rooms': {
        'join': {
          '!room:example.org': {
            'state': {
              'events': [
                {
                  'type': 'chat.commet.calendars',
                  'state_key': '',
                  'content': content,
                  'sender': '@other:example.org',
                  'event_id': r'$registry-replacement',
                  'origin_server_ts': 0,
                },
              ],
            },
          },
        },
      },
    });

matrix.Event _redactionEvent({
  required String eventId,
  required String redacts,
  required matrix.Room room,
}) => matrix.Event(
  content: const {},
  type: 'm.room.redaction',
  eventId: eventId,
  senderId: '@other:example.org',
  originServerTs: DateTime.utc(2026, 9, 23),
  redacts: redacts,
  room: room,
);

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _Fixture {
  _Fixture() {
    client = _RecordingClient();
    room = _RecordingRoom(client);
    runner = PrivelidgedMatrixWidgetRunner(client, room);
  }

  late final _RecordingClient client;
  late final _RecordingRoom room;
  late final PrivelidgedMatrixWidgetRunner runner;
}

class _RecordingClient extends matrix.Client {
  _RecordingClient() : super('widget-runner-test', database: _FakeDatabase());

  int stateWrites = 0;
  int relationReads = 0;

  @override
  String? get userID => '@me:example.org';

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    stateWrites++;
    return r'$state';
  }

  @override
  Future<matrix.GetRelatingEventsWithRelTypeAndEventTypeResponse>
  getRelatingEventsWithRelTypeAndEventType(
    String roomId,
    String eventId,
    String relType,
    String eventType, {
    String? from,
    String? to,
    int? limit,
    matrix.Direction? dir,
    bool? recurse,
  }) async {
    relationReads++;
    return matrix.GetRelatingEventsWithRelTypeAndEventTypeResponse(
      chunk: const [],
      nextBatch: r'$page',
    );
  }
}

class _RecordingRoom extends matrix.Room {
  _RecordingRoom(matrix.Client client)
    : super(id: '!room:example.org', client: client);

  int timelineSends = 0;
  int redactions = 0;
  Set<String> registryCalendarIds = {r'$calendar'};
  final Set<String> throwOnLookupIds = {};

  @override
  matrix.StrippedStateEvent? getState(String typeKey, [String stateKey = '']) {
    if (typeKey != 'chat.commet.calendars' || stateKey.isNotEmpty) return null;
    return matrix.StrippedStateEvent(
      type: typeKey,
      stateKey: '',
      content: {'calendars': registryCalendarIds.toList()},
      senderId: '@me:example.org',
    );
  }

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = matrix.EventTypes.Message,
    String? txid,
    matrix.Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    timelineSends++;
    return type == 'chat.commet.calendar_create'
        ? r'$new-calendar'
        : r'$timeline';
  }

  @override
  Future<matrix.Event?> getEventById(String eventId) async {
    if (throwOnLookupIds.contains(eventId)) {
      throw StateError('Test lookup failure');
    }
    return matrix.Event(
      content: const {},
      type: switch (eventId) {
        r'$calendar' || r'$new-calendar' => 'chat.commet.calendar_create',
        r'$non-calendar-event' => 'm.room.message',
        _ => 'chat.commet.calendar_events',
      },
      eventId: eventId,
      senderId: eventId == r'$foreign-event'
          ? '@other:example.org'
          : '@me:example.org',
      originServerTs: DateTime.utc(2026, 9, 23),
      room: this,
    );
  }

  @override
  Future<String?> redactEvent(
    String eventId, {
    String? reason,
    String? txid,
  }) async {
    redactions++;
    return r'$redaction';
  }
}

class _FakeDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
