import 'dart:async';

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
          'event': event.toJson(),
        },
      ],
    },
  };
}

class _FakeMatrixWidgetApi implements MatrixWidgetApi {
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
      sentEvents.add(Map<String, dynamic>.from(data));
      return {
        'room_id': '!debug:ourgalaxy.space',
        'event_id': '\$sent-${sentEvents.length}',
      };
    }

    return {};
  }

  @override
  void start() {}

  @override
  void stop() {}
}
