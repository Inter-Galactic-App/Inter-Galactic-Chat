import 'dart:async';
import 'dart:convert';

import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_widget_api/matrix_widget_api.dart';
import 'package:matrix_widget_api/types.dart';

void main() {
  test('missing calendar room state is treated as pending state', () async {
    final calendar = MatrixCalendar(_FakeMatrixWidgetApi());

    expect(await calendar.getCalendarId(), isNull);
  });

  test('calendar id is read from the default calendar state event', () async {
    final calendar = MatrixCalendar(_FakeMatrixWidgetApi());
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };

    expect(await calendar.getCalendarId(), '\$calendar-event');
  });

  test('calendar event receipts are idempotent by Matrix event id', () {
    final calendar = MatrixCalendar(_FakeMatrixWidgetApi());
    final event = _calendarEvent(uid: 'event-a');
    final data = _calendarEventsMessage(
      eventId: '\$matrix-event-a',
      event: event,
    );

    calendar.handleCalendarEventReceived(data);
    calendar.handleCalendarEventReceived(data);

    expect(calendar.getAllEvents(), hasLength(1));
    expect(calendar.getAllEvents().single.eventId, '\$matrix-event-a');
  });

  test('delete removes local events and suppresses stale echoes', () async {
    final api = _FakeMatrixWidgetApi();
    final calendar = MatrixCalendar(api);
    final event = _calendarEvent(uid: 'event-b');
    final data = _calendarEventsMessage(
      eventId: '\$matrix-event-b',
      event: event,
    );

    calendar.handleCalendarEventReceived(data);
    await calendar.deleteEvent(event);
    calendar.handleCalendarEventReceived(data);

    expect(calendar.getAllEvents(), isEmpty);
    expect(api.sentEvents, hasLength(1));
    expect(api.sentEvents.single['type'], 'm.room.redaction');
    expect(api.sentEvents.single['content'], {'redacts': '\$matrix-event-b'});
  });

  test('redaction events can use top-level redacts', () {
    final calendar = MatrixCalendar(_FakeMatrixWidgetApi());
    final event = _calendarEvent(uid: 'event-c');
    calendar.handleCalendarEventReceived(
      _calendarEventsMessage(
        eventId: '\$matrix-event-c',
        event: event,
      ),
    );

    calendar.handleCalendarEventDeleted({
      'type': 'm.room.redaction',
      'event_id': '\$redaction-event',
      'redacts': '\$matrix-event-c',
      'content': <String, dynamic>{},
    });

    expect(calendar.getAllEvents(), isEmpty);
  });

  test('weekly recurrence without byDay uses start weekday', () {
    final calendar = MatrixCalendar(_FakeMatrixWidgetApi());
    final event = _calendarEvent(uid: 'event-d')
      ..recurrenceRules = [
        RFC8984RecurrenceRule(frequency: 'weekly'),
      ];

    final recurrence = calendar.toRecurrenceSettings(event);

    expect(recurrence, isNotNull);
    expect(recurrence!.weekdays, [DateTime.sunday - 1]);
  });

  test('createEvent sends a timezone-backed weekly recurrence', () async {
    final api = _FakeMatrixWidgetApi();
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };

    final event = RFC8984CalendarEvent(
      uid: '',
      updated: DateTime.utc(2026, 6, 26, 12),
      title: 'Weekly debug sync',
      start: DateTime(2026, 6, 26, 9),
      timeZone: 'America/New_York',
      duration: const Duration(hours: 1),
      recurrenceRules: [
        RFC8984RecurrenceRule(
          frequency: 'weekly',
          firstDayOfWeek: 'su',
          byDay: [Rfc8984NDay('fr')],
        ),
      ],
    );

    final succeeded = await calendar.createEvent(event, eventType: 'event');

    expect(succeeded, isTrue);

    final sentEvent = api.sentEvents.singleWhere(
      (data) => data['type'] == 'chat.commet.calendar_events',
    );
    final events = sentEvent['content']['events'] as List<dynamic>;
    final content = events.single as Map<String, dynamic>;
    final calendarEvent = content['event'] as Map<String, dynamic>;
    final rules = calendarEvent['recurrenceRules'] as List<dynamic>;
    final rule = rules.single as Map<String, dynamic>;
    final days = rule['byDay'] as List<dynamic>;
    final day = days.single as Map<String, dynamic>;

    expect(calendarEvent['timeZone'], 'America/New_York');
    expect(rule['frequency'], 'weekly');
    expect(rule['firstDayOfWeek'], 'su');
    expect(day['day'], 'fr');
  });

  test('createEvent rolls back optimistic event when send fails', () async {
    final api = _FakeMatrixWidgetApi(omitEventId: true);
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };

    final succeeded = await calendar.createEvent(
      _calendarEvent(uid: ''),
      eventType: 'event',
    );

    expect(succeeded, isFalse);
    expect(calendar.getAllEvents(), isEmpty);
  });

  test('createEvent restores existing local entries when edit send fails',
      () async {
    final api = _FakeMatrixWidgetApi(omitEventId: true);
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };
    final existing = _calendarEvent(uid: 'event-edit');
    calendar.handleCalendarEventReceived(
      _calendarEventsMessage(
        eventId: '\$matrix-event-edit',
        event: existing,
      ),
    );

    final replacement = _calendarEvent(uid: 'event-edit')..title = 'Updated';
    final succeeded = await calendar.createEvent(
      replacement,
      eventType: 'event',
    );

    expect(succeeded, isFalse);
    expect(calendar.getAllEvents(), hasLength(1));
    final restored = calendar.getAllEvents().single;
    expect(restored.eventId, '\$matrix-event-edit');
    expect(restored.data.title, 'Debug event');
  });

  test('createEvent restores existing local entries when edit send throws',
      () async {
    final api = _FakeMatrixWidgetApi(throwOnSendEvent: true);
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };
    final existing = _calendarEvent(uid: 'event-throw');
    calendar.handleCalendarEventReceived(
      _calendarEventsMessage(
        eventId: '\$matrix-event-throw',
        event: existing,
      ),
    );

    final replacement = _calendarEvent(uid: 'event-throw')..title = 'Updated';
    final succeeded = await calendar.createEvent(
      replacement,
      eventType: 'event',
    );

    expect(succeeded, isFalse);
    expect(calendar.getAllEvents(), hasLength(1));
    final restored = calendar.getAllEvents().single;
    expect(restored.eventId, '\$matrix-event-throw');
    expect(restored.data.title, 'Debug event');
  });

  test('createEvent keeps replacement success when edit redaction throws',
      () async {
    final api = _FakeMatrixWidgetApi(throwOnRedaction: true);
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };
    final existing = _calendarEvent(uid: 'event-redaction-throw');
    calendar.handleCalendarEventReceived(
      _calendarEventsMessage(
        eventId: '\$matrix-event-redaction-throw',
        event: existing,
      ),
    );

    final replacement = _calendarEvent(uid: 'event-redaction-throw')
      ..title = 'Updated';
    final succeeded = await calendar.createEvent(
      replacement,
      eventType: 'event',
    );

    expect(succeeded, isTrue);
    expect(
      api.sentEvents
          .where((data) => data['type'] == 'chat.commet.calendar_events'),
      hasLength(1),
    );
  });

  test('delete occurrence replaces series and redacts the source event',
      () async {
    final api = _FakeMatrixWidgetApi();
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };
    final event = _calendarEvent(uid: 'event-e')
      ..recurrenceRules = [
        RFC8984RecurrenceRule(
          frequency: 'weekly',
          firstDayOfWeek: 'su',
          byDay: [Rfc8984NDay('su')],
        ),
      ];
    final data = _calendarEventsMessage(
      eventId: '\$matrix-event-e',
      event: event,
    );
    calendar.handleCalendarEventReceived(data);

    await calendar.deleteEventOccurrence(
      event,
      DateTime.utc(2026, 6, 14),
      eventType: 'event',
    );
    calendar.handleCalendarEventReceived(data);

    final replacement = api.sentEvents.singleWhere(
      (data) => data['type'] == 'chat.commet.calendar_events',
    );
    final replacementEvent = replacement['content']['events'].single['event']
        as Map<String, dynamic>;
    final overrides =
        replacementEvent['recurrenceOverrides'] as Map<String, dynamic>;
    final redaction = api.sentEvents.singleWhere(
      (data) => data['type'] == 'm.room.redaction',
    );

    expect(overrides[recurrenceExcludedDatesKey], ['2026-06-14']);
    expect(redaction['content'], {'redacts': '\$matrix-event-e'});
    expect(
      calendar.getAllEvents().where((event) => event.eventId == null),
      hasLength(1),
    );
  });

  test('delete occurrence redacts every duplicate source event id', () async {
    final api = _FakeMatrixWidgetApi();
    final calendar = MatrixCalendar(api);
    calendar.roomState['chat.commet.calendars'] = {
      '': {
        'content': {
          'calendars': ['\$calendar-event'],
        },
      },
    };
    final event = _calendarEvent(uid: 'event-duplicate-occurrence')
      ..recurrenceRules = [
        RFC8984RecurrenceRule(
          frequency: 'weekly',
          firstDayOfWeek: 'su',
          byDay: [Rfc8984NDay('su')],
        ),
      ];
    final firstSource = _calendarEventsMessage(
      eventId: '\$matrix-event-occurrence-a',
      event: event,
    );
    final secondSource = _calendarEventsMessage(
      eventId: '\$matrix-event-occurrence-b',
      event: event,
    );
    calendar.handleCalendarEventReceived(firstSource);
    calendar.handleCalendarEventReceived(secondSource);

    await calendar.deleteEventOccurrence(
      event,
      DateTime.utc(2026, 6, 14),
      eventType: 'event',
    );
    calendar.handleCalendarEventReceived(firstSource);
    calendar.handleCalendarEventReceived(secondSource);

    final replacement = api.sentEvents.singleWhere(
      (data) => data['type'] == 'chat.commet.calendar_events',
    );
    final replacementEvent = replacement['content']['events'].single['event']
        as Map<String, dynamic>;
    final overrides =
        replacementEvent['recurrenceOverrides'] as Map<String, dynamic>;
    final redactions = api.sentEvents
        .where((data) => data['type'] == 'm.room.redaction')
        .toList();
    final remainingEventIds = calendar
        .getAllEvents()
        .map((event) => event.eventId)
        .whereType<String>()
        .toSet();

    expect(overrides[recurrenceExcludedDatesKey], ['2026-06-14']);
    expect(
      redactions.map((data) => data['content']['redacts']).toSet(),
      {'\$matrix-event-occurrence-a', '\$matrix-event-occurrence-b'},
    );
    expect(remainingEventIds.contains('\$matrix-event-occurrence-a'), isFalse);
    expect(remainingEventIds.contains('\$matrix-event-occurrence-b'), isFalse);
    expect(
      calendar.getAllEvents().where((event) => event.eventId == null),
      hasLength(1),
    );
  });

  test('delete event redacts every duplicate source event id', () async {
    final api = _FakeMatrixWidgetApi();
    final calendar = MatrixCalendar(api);
    final event = _calendarEvent(uid: 'event-delete-duplicates');
    final firstSource = _calendarEventsMessage(
      eventId: '\$matrix-event-delete-a',
      event: event,
    );
    final secondSource = _calendarEventsMessage(
      eventId: '\$matrix-event-delete-b',
      event: event,
    );
    calendar.handleCalendarEventReceived(firstSource);
    calendar.handleCalendarEventReceived(secondSource);

    await calendar.deleteEvent(event);
    calendar.handleCalendarEventReceived(firstSource);
    calendar.handleCalendarEventReceived(secondSource);

    final redactions = api.sentEvents
        .where((data) => data['type'] == 'm.room.redaction')
        .toList();

    expect(
      redactions.map((data) => data['content']['redacts']).toSet(),
      {'\$matrix-event-delete-a', '\$matrix-event-delete-b'},
    );
    expect(
      calendar
          .getAllEvents()
          .where((event) => event.data.uid == 'event-delete-duplicates'),
      isEmpty,
    );
  });
}

RFC8984CalendarEvent _calendarEvent({required String uid}) {
  return RFC8984CalendarEvent(
    uid: uid,
    updated: DateTime.utc(2026, 6, 6, 12),
    title: 'Debug event',
    start: DateTime.utc(2026, 6, 7, 13),
    duration: const Duration(hours: 1),
  );
}

Map<String, dynamic> _calendarEventsMessage({
  required String eventId,
  required RFC8984CalendarEvent event,
  String sender = '@debug:ourgalaxy.space',
}) {
  return {
    'type': 'chat.commet.calendar_events',
    'event_id': eventId,
    'sender': sender,
    'content': {
      'm.relates_to': {
        'event_id': '\$calendar-event',
        'rel_type': 'm.reference',
      },
      'format': 'chat.commet.calendar.event.rfc8984',
      'events': [
        {
          'type': 'event',
          'event': jsonDecode(jsonEncode(event.toJson())),
        },
      ],
    },
  };
}

class _FakeMatrixWidgetApi implements MatrixWidgetApi {
  _FakeMatrixWidgetApi({
    this.omitEventId = false,
    this.throwOnSendEvent = false,
    this.throwOnRedaction = false,
  });

  final bool omitEventId;
  final bool throwOnSendEvent;
  final bool throwOnRedaction;
  final StreamController<void> _readyController = StreamController.broadcast();
  final List<Map<String, dynamic>> sentEvents = [];

  @override
  String get userId => '@debug:ourgalaxy.space';

  @override
  Stream<void> get onReady => _readyController.stream;

  @override
  void onAction(
    String toWidgetAction,
    Map<String, dynamic>? Function(Map<String, dynamic> data) callback, {
    preventDefaultHandler = false,
  }) {}

  @override
  Future<void> requestCapabilities(List<String> capabilities) async {}

  @override
  Future<Map<String, dynamic>> sendAction(
    String fromWidgetAction,
    Map<String, dynamic> data,
  ) async {
    if (fromWidgetAction == FromWidgetAction.sendEvent) {
      if (throwOnSendEvent) {
        throw StateError('send failed');
      }
      if (throwOnRedaction && data['type'] == 'm.room.redaction') {
        throw StateError('redaction failed');
      }
      sentEvents.add(jsonDecode(jsonEncode(data)) as Map<String, dynamic>);
      return {
        'room_id': '!debug:ourgalaxy.space',
        if (!omitEventId) 'event_id': '\$sent-${sentEvents.length}',
      };
    }

    return {};
  }

  @override
  void start() {}

  @override
  void stop() {}
}
