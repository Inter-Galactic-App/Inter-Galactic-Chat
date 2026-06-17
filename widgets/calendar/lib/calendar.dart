import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:calendar_view/calendar_view.dart';
import 'package:commet_calendar_widget/calendar_event_metadata.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:commet_calendar_widget/utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix_widget_api/capabilities.dart';
import 'package:matrix_widget_api/matrix_widget_api.dart';
import 'package:matrix_widget_api/types.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:uuid/uuid.dart';

import 'package:timezone/standalone.dart' as tz;

class MatrixCalendarEventState {
  RFC8984CalendarEvent data;
  bool loaded = false;
  String? senderId;
  String? eventId;
  String? remoteSourceId;
  String? type;

  bool get isUnavailability => type == "unavailability";

  MatrixCalendarEventState({this.senderId, required this.data, this.type});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! MatrixCalendarEventState) {
      return false;
    }

    var js = data.toJson();
    var otherJs = other.data.toJson();

    js.remove("updated");
    js.remove("uid");
    otherJs.remove("updated");
    otherJs.remove("uid");

    return other.type == type &&
        other.remoteSourceId == remoteSourceId &&
        jsonEncode(js) == jsonEncode(otherJs);
  }
}

String _calendarDebugKeys(Map<dynamic, dynamic> data) {
  final keys = data.keys.map((key) => key.toString()).toList()..sort();
  return keys.join(',');
}

const int _maxRedactedEventTombstones = 512;

typedef CalendarEventTapCallback = FutureOr<void> Function(
  MatrixCalendarEventState event,
  DateTime occurrenceDate,
);

class MatrixCalendarConfig {
  Color getColorFromUser(String userId) {
    return Utils.hashColor(userId);
  }

  Color processEventColor(Color color, BuildContext context) {
    return tiamat.Text.adjustColor(context, color, saturationMultiplier: 0.5);
  }

  Color processEventTextColor(Color color, BuildContext context) {
    var hsl = HSLColor.fromColor(color);
    double lightness = hsl.lightness;
    double saturation = hsl.saturation;
    if (Theme.of(context).brightness == Brightness.dark) {
      saturation = clampDouble(hsl.saturation * 2, 0, 1);
      lightness = clampDouble(hsl.lightness, 0, 0.1);
    } else {
      lightness = clampDouble(hsl.lightness, 0.99, 1.0);
      saturation = saturation * 0.1;
    }

    return HSLColor.fromAHSL(
      hsl.alpha,
      hsl.hue,
      saturation,
      lightness,
    ).toColor();
  }

  Future<T?> dialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) {
        return AlertDialog(content: builder(context));
      },
    );
  }

  DateTime convertToLocalTime(DateTime time, String? timezone) {
    var localTimezone = DateTime.now().timeZoneName;

    if (time.isUtc) {
      return time.toLocal();
    }

    if (timezone == null || timezone == localTimezone) {
      return time;
    }

    var tztime = tz.TZDateTime(
      tz.getLocation(timezone),
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
      time.millisecond,
      time.microsecond,
    );
    var utc = tztime.toUtc();

    var local = utc.native.toLocal();
    return local;
  }

  ImageProvider? getUserAvatar(String userId) {
    return null;
  }

  String? getUserDisplayname(String userId) {
    return userId.split("@")[1].split(":").first;
  }

  const MatrixCalendarConfig();
}

class _StoredAttendanceEvent {
  final CalendarAttendanceState state;
  final DateTime? originServerTs;

  const _StoredAttendanceEvent({
    required this.state,
    this.originServerTs,
  });
}

class MatrixCalendar {
  static const String attendanceEventType =
      "chat.intergalactic.calendar_attendance";

  final MatrixWidgetApi widgetApi;

  late EventController<MatrixCalendarEventState> controller;

  StreamController onNeedsMigration = StreamController.broadcast();

  Map<String, Map<String, dynamic>> roomState = {};

  final Map<String, Map<String, _StoredAttendanceEvent>> _attendanceState = {};
  final Set<String> _redactedEventIds = {};

  MatrixCalendarConfig config;

  bool needsStateMigration = false;

  MatrixCalendar(this.widgetApi, {this.config = const MatrixCalendarConfig()}) {
    controller = EventController(eventFilter: filterEventsOnDay);

    widgetApi.onReady.listen(onWidgetReady);

    widgetApi.onAction(
        ToWidgetAction.updateState,
        preventDefaultHandler: true,
        onStateUpdated);

    widgetApi.onAction(
        ToWidgetAction.sendEvent, preventDefaultHandler: true, onEventReceived);
  }

  Map<String, dynamic>? onStateUpdated(Map<String, dynamic> update) {
    var states = Map<String, dynamic>.from(update);
    var data = states['data'];
    var stateEvents = data['state'];

    for (var stateEvent in stateEvents) {
      var event = Map<String, dynamic>.from(stateEvent);

      var type = event['type'];

      print("CalendarWidget: received ${type} state event");

      var stateKey = event['state_key'] ?? "";

      if (type == "chat.commet.calendar_event" &&
          stateKey == widgetApi.userId) {
        if ((event["content"] as Map<String, dynamic>).isNotEmpty) {
          needsStateMigration = true;
          onNeedsMigration.add(null);
        }
      }

      if (!roomState.containsKey(type)) {
        roomState[type] = {};
      }

      roomState[type]![stateKey] = event;

      if (type == "chat.commet.calendars") {
        readExistingEvents();
      }
    }

    return null;
  }

  bool canEditEvent(MatrixCalendarEventState event) {
    if (event.remoteSourceId != null) {
      return false;
    }

    if (event.senderId != widgetApi.userId) {
      return false;
    }

    return true;
  }

  bool canDeleteEvent(MatrixCalendarEventState event) {
    if (event.senderId != widgetApi.userId) {
      return false;
    }

    return true;
  }

  void onWidgetReady(void event) async {
    await widgetApi.requestCapabilities([
      MatrixCapability.getRoomState("chat.commet.calendar_event"),
      MatrixCapability.setRoomState(
        "chat.commet.calendar_event",
        stateKey: widgetApi.userId,
      ),
      MatrixCapability.getRoomState("chat.commet.calendars"),
      MatrixCapability.setRoomState("chat.commet.calendars"),
      MatrixCapability.sendEvent("chat.commet.calendar_events"),
      MatrixCapability.receiveEvent("chat.commet.calendar_events"),
      MatrixCapability.sendEvent(attendanceEventType),
      MatrixCapability.receiveEvent(attendanceEventType),
      MatrixCapability.sendEvent("m.room.redaction"),
      MatrixCapability.receiveEvent("m.room.redaction"),
      MatrixCapability.sendEvent("chat.commet.calendar_create"),
    ]);

    await readExistingEvents();
  }

  Future<void> readExistingEvents({String? nextChunk}) async {
    await readRelatedEventsOfType("chat.commet.calendar_events",
        nextChunk: nextChunk);
    await readRelatedEventsOfType(attendanceEventType, nextChunk: nextChunk);
  }

  Future<void> readRelatedEventsOfType(String eventType,
      {String? nextChunk}) async {
    var calendarId = await getCalendarId();
    if (calendarId == null) return;

    var response = await widgetApi.sendAction(FromWidgetAction.readRelations, {
      "event_id": calendarId,
      "event_type": eventType,
      "limit": 100,
      if (nextChunk != null) "from": nextChunk,
      "rel_type": "m.reference",
    });

    var events = response["chunk"] as List<dynamic>;

    for (var event in events) {
      switch (eventType) {
        case "chat.commet.calendar_events":
          handleCalendarEventReceived(event);
          break;
        case attendanceEventType:
          handleAttendanceEventReceived(event);
          break;
      }
    }

    if (response["next_batch"] is String) {
      await readRelatedEventsOfType(eventType,
          nextChunk: response["next_batch"] as String);
    }
  }

  List<MatrixCalendarEventState> getEventsOnDay(DateTime date) {
    return controller
        .getEventsOnDay(date)
        .map((e) => e.event)
        .nonNulls
        .map((e) => e)
        .toList();
  }

  List<MatrixCalendarEventState> getAllEvents() {
    return controller.allEvents.map((i) => i.event!).toList();
  }

  void _removeCalendarEntriesForEventId(String eventId) {
    controller.removeWhere((entry) => entry.event?.eventId == eventId);
  }

  void _rememberRedactedEventId(String eventId) {
    _redactedEventIds.add(eventId);
    while (_redactedEventIds.length > _maxRedactedEventTombstones) {
      _redactedEventIds.remove(_redactedEventIds.first);
    }
  }

  void _markEventRedacted(String eventId) {
    _rememberRedactedEventId(eventId);
    _removeCalendarEntriesForEventId(eventId);
  }

  List<CalendarEventData<MatrixCalendarEventState>> filterEventsOnDay(
    DateTime date,
    List<CalendarEventData<MatrixCalendarEventState>> events,
  ) {
    final results = <CalendarEventData<MatrixCalendarEventState>>[];
    final targetDate = date.withoutTime;

    for (final event in events) {
      final state = event.event;
      if (state == null) {
        continue;
      }

      final rule = state.data.recurrenceRules?.firstOrNull;
      if (rule != null &&
          doesRecurringEventOccurOnDate(
            event: state.data,
            displayEvent: event,
            targetDate: targetDate,
          )) {
        results.add(event);
        continue;
      }

      if (event.occursOnDate(targetDate)) {
        results.add(event);
      }
    }

    results.sort((a, b) =>
        (a.startTime?.getTotalMinutes ?? 0) -
        (b.startTime?.getTotalMinutes ?? 0));
    return results;
  }

  bool doesRecurringEventOccurOnDate({
    required RFC8984CalendarEvent event,
    required CalendarEventData<MatrixCalendarEventState> displayEvent,
    required DateTime targetDate,
  }) {
    final rule = event.recurrenceRules?.firstOrNull;
    if (rule == null) {
      return displayEvent.occursOnDate(targetDate);
    }

    if (isRecurrenceDateExcluded(event, targetDate)) {
      return false;
    }

    final startDate = displayEvent.date.withoutTime;
    if (targetDate.isBefore(startDate)) {
      return false;
    }

    final endDate = displayEvent.recurrenceSettings?.endDate?.withoutTime ??
        rule.until?.withoutTime;
    if (endDate != null && targetDate.isAfter(endDate)) {
      return false;
    }

    final interval = rule.interval ?? 1;

    switch (rule.frequency) {
      case "daily":
        return targetDate.difference(startDate).inDays % interval == 0;
      case "weekly":
        final allowedDays = getAllowedWeekdays(rule, startDate);
        if (!allowedDays.contains(targetDate.weekday - 1)) {
          return false;
        }

        final startOfWeek =
            startDate.firstDayOfWeek(start: getWeekStart(rule.firstDayOfWeek));
        final targetWeek =
            targetDate.firstDayOfWeek(start: getWeekStart(rule.firstDayOfWeek));
        final weeksApart = targetWeek.difference(startOfWeek).inDays ~/ 7;
        return weeksApart % interval == 0;
      case "monthly":
        final monthsApart = (targetDate.year - startDate.year) * 12 +
            targetDate.month -
            startDate.month;
        if (monthsApart < 0 || monthsApart % interval != 0) {
          return false;
        }

        final byDays = rule.byDay;
        if (byDays != null && byDays.isNotEmpty) {
          return byDays
              .any((day) => doesMonthlyWeekdayOccurOnDate(day, targetDate));
        }

        final byMonthDays = rule.byMonthDay;
        if (byMonthDays != null && byMonthDays.isNotEmpty) {
          return byMonthDays.contains(targetDate.day);
        }

        return targetDate.day == startDate.day;
      case "yearly":
        final yearsApart = targetDate.year - startDate.year;
        if (yearsApart < 0 || yearsApart % interval != 0) {
          return false;
        }

        return targetDate.month == startDate.month &&
            targetDate.day == startDate.day;
      default:
        return displayEvent.occursOnDate(targetDate);
    }
  }

  WeekDays getWeekStart(String? value) {
    return value == "su" ? WeekDays.sunday : WeekDays.monday;
  }

  List<int> getAllowedWeekdays(RFC8984RecurrenceRule rule, DateTime startDate) {
    if (rule.byDay == null || rule.byDay!.isEmpty) {
      return [startDate.weekday - 1];
    }

    return rule.byDay!.map((day) {
      return switch (day.day) {
        "mo" => 0,
        "tu" => 1,
        "we" => 2,
        "th" => 3,
        "fr" => 4,
        "sa" => 5,
        "su" => 6,
        _ => startDate.weekday - 1,
      };
    }).toList();
  }

  bool doesMonthlyWeekdayOccurOnDate(Rfc8984NDay day, DateTime targetDate) {
    if (weekdayFromCode(day.day) != targetDate.weekday) {
      return false;
    }

    final nth = day.nthOfPeriod;
    if (nth == null) {
      return true;
    }

    final occurrenceFromStart = ((targetDate.day - 1) ~/ 7) + 1;
    if (nth > 0) {
      return occurrenceFromStart == nth;
    }

    final lastDayOfMonth = DateTime(targetDate.year, targetDate.month + 1, 0);
    final lastOccurrenceDay = lastDayOfMonth.day -
        ((lastDayOfMonth.weekday - targetDate.weekday + 7) % 7);
    final totalOccurrences = ((lastOccurrenceDay - 1) ~/ 7) + 1;
    final occurrenceFromEnd = occurrenceFromStart - totalOccurrences - 1;
    return occurrenceFromEnd == nth;
  }

  int weekdayFromCode(String day) {
    return switch (day) {
      "mo" => DateTime.monday,
      "tu" => DateTime.tuesday,
      "we" => DateTime.wednesday,
      "th" => DateTime.thursday,
      "fr" => DateTime.friday,
      "sa" => DateTime.saturday,
      "su" => DateTime.sunday,
      _ => DateTime.monday,
    };
  }

  List<MatrixCalendarEventState> getUniqueRootEvents() {
    final seen = <String>{};
    final results = <MatrixCalendarEventState>[];

    for (final item in controller.allEvents) {
      final state = item.event;
      if (state == null) {
        continue;
      }

      final key = "${state.eventId}:${state.data.uid}:${state.senderId}";
      if (seen.add(key)) {
        results.add(state);
      }
    }

    return results;
  }

  CalendarAttendanceState? getAttendanceStateForUser(
      String eventUid, String userId) {
    return _attendanceState[eventUid]?[userId]?.state;
  }

  List<CalendarAttendanceState> getAttendanceStates(String eventUid) {
    return (_attendanceState[eventUid]?.values ??
            const <_StoredAttendanceEvent>[])
        .map((entry) => entry.state)
        .where((entry) => entry.attending)
        .toList();
  }

  int getAttendanceCount(String eventUid) {
    return getAttendanceStates(eventUid).length;
  }

  List<int> getDefaultReminderOffsets(RFC8984CalendarEvent event) {
    return normalizeReminderOffsets(
        event.attendeeReminderOffsetsMinutes ?? const <int>[]);
  }

  List<int> getEffectiveReminderOffsets({
    required RFC8984CalendarEvent event,
    String? userId,
  }) {
    final resolvedUserId = userId ?? widgetApi.userId;
    final attendance = getAttendanceStateForUser(event.uid, resolvedUserId);
    if (attendance == null) {
      return getDefaultReminderOffsets(event);
    }

    if (attendance.useDefaultReminders) {
      return getDefaultReminderOffsets(event);
    }

    return normalizeReminderOffsets(attendance.reminderOffsetsMinutes);
  }

  bool sameReminderOffsets(List<int> a, List<int> b) {
    final left = normalizeReminderOffsets(a);
    final right = normalizeReminderOffsets(b);
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }

    return true;
  }

  Future<void> saveAttendanceState({
    required RFC8984CalendarEvent event,
    required bool attending,
    required List<int> reminderOffsets,
  }) async {
    final calendarId = await getCalendarId(createIfNotFound: true);
    if (calendarId == null) {
      return;
    }

    final normalizedDefaults = getDefaultReminderOffsets(event);
    final normalizedOffsets = normalizeReminderOffsets(reminderOffsets);
    final useDefaultReminders =
        attending && sameReminderOffsets(normalizedDefaults, normalizedOffsets);

    await widgetApi.sendAction(FromWidgetAction.sendEvent, {
      "type": attendanceEventType,
      "content": {
        "m.relates_to": {"event_id": calendarId, "rel_type": "m.reference"},
        "calendar_event_uid": event.uid,
        "attending": attending,
        "use_default_reminders": useDefaultReminders,
        if (!useDefaultReminders) "reminder_offsets_minutes": normalizedOffsets,
      }
    });
  }

  Iterable<CalendarReminderSchedule> getReminderSchedulesForUser(
    String userId, {
    DateTime? from,
    Duration horizon = const Duration(days: 30),
  }) sync* {
    final now = from ?? DateTime.now();
    final horizonEnd = now.add(horizon);

    for (final state in getUniqueRootEvents()) {
      final attendance = getAttendanceStateForUser(state.data.uid, userId);
      if (attendance?.attending != true) {
        continue;
      }

      final reminderOffsets = getEffectiveReminderOffsets(
        event: state.data,
        userId: userId,
      );

      if (reminderOffsets.isEmpty) {
        continue;
      }

      final occurrences = getOccurrencesBetween(
        state.data,
        from: now.subtract(const Duration(days: 8)),
        to: horizonEnd,
      );

      for (final occurrence in occurrences) {
        for (final minutesBefore in reminderOffsets) {
          final remindAt =
              occurrence.subtract(Duration(minutes: minutesBefore));
          if (remindAt.isBefore(now) || remindAt.isAfter(horizonEnd)) {
            continue;
          }

          yield CalendarReminderSchedule(
            eventUid: state.data.uid,
            title: state.data.title,
            userId: userId,
            eventStart: occurrence,
            remindAt: remindAt,
            minutesBefore: minutesBefore,
          );
        }
      }
    }
  }

  List<DateTime> getOccurrencesBetween(
    RFC8984CalendarEvent event, {
    required DateTime from,
    required DateTime to,
  }) {
    final localStart = config.convertToLocalTime(event.start, event.timeZone);
    final startDate = localStart.withoutTime;
    final rule = event.recurrenceRules?.firstOrNull;

    if (rule == null) {
      return localStart.isAfter(from) && localStart.isBefore(to)
          ? [localStart]
          : (localStart.isAtSameMomentAs(from) ||
                  localStart.isAtSameMomentAs(to))
              ? [localStart]
              : [];
    }

    final results = <DateTime>[];
    final scanStart =
        from.withoutTime.isBefore(startDate) ? startDate : from.withoutTime;
    for (var date = scanStart;
        !date.isAfter(to.withoutTime);
        date = date.add(const Duration(days: 1))) {
      final displayEvent = CalendarEventData<MatrixCalendarEventState>(
        title: event.title,
        date: startDate,
        startTime: localStart,
        endTime: localStart.add(event.duration),
        event: MatrixCalendarEventState(data: event),
        recurrenceSettings: toRecurrenceSettings(event),
      );

      if (!doesRecurringEventOccurOnDate(
        event: event,
        displayEvent: displayEvent,
        targetDate: date,
      )) {
        continue;
      }

      results.add(DateTime(
        date.year,
        date.month,
        date.day,
        localStart.hour,
        localStart.minute,
        localStart.second,
        localStart.millisecond,
        localStart.microsecond,
      ));
    }

    return results;
  }

  // Converts an RFC8984 Calendar events to a events which can be displayed by the calendar widget
  // If an event spans multiple days, it gets split in to one event per day
  List<CalendarEventData<MatrixCalendarEventState>> fromRfcEvent(
      RFC8984CalendarEvent event,
      {String? eventType}) {
    var eventTimezone = event.timeZone;
    var localTime = config.convertToLocalTime(event.start, eventTimezone);

    bool oneOffAllDayEvent = (event.duration.inMinutes == 24 * 60 &&
        localTime.hour == 0 &&
        localTime.minute == 0);

    var endTime = localTime.add(event.duration);

    var clippedEndTime = clipToValidEndTime(localTime, endTime);

    List<CalendarEventData<MatrixCalendarEventState>> events = List.empty(
      growable: true,
    );

    var finalEvent = CalendarEventData(
      title: event.title,
      date: localTime,
      startTime: localTime,
      endTime: clippedEndTime,
      recurrenceSettings: toRecurrenceSettings(event),
      event: MatrixCalendarEventState(data: event, type: eventType),
    );

    events.add(finalEvent);

    if (oneOffAllDayEvent) {
      return events;
    }

    if (clippedEndTime != endTime) {
      while (endTime.isAfter(clippedEndTime)) {
        var startTime = clippedEndTime;

        var newClippedEndTime = clipToValidEndTime(startTime, endTime);

        events.add(
          CalendarEventData(
            title: event.title + " ${event.uid} ",
            date: startTime,
            startTime: startTime,
            endTime: newClippedEndTime.subtract(
              Duration(minutes: 1),
            ), // to prevent the calendar view from considering this as 'all day event'
            event: MatrixCalendarEventState(data: event, type: eventType),
          ),
        );

        if (clippedEndTime == newClippedEndTime) {
          break;
        }

        clippedEndTime = newClippedEndTime;
      }
    }

    return events;
  }

  DateTime clipToValidEndTime(DateTime startTime, DateTime endTime) {
    if (endTime.withoutTime != startTime.withoutTime) {
      return startTime.copyWith(hour: 23, minute: 59).add(Duration(minutes: 1));
    }

    return endTime;
  }

  String _generateId() {
    var uuid = const Uuid();
    var label = uuid.v4();

    return label;
  }

  Future<void> syncEvents(
    Map<String, List<RFC8984CalendarEvent>> events, {
    String? eventType,
  }) async {
    var calenarId = await getCalendarId(createIfNotFound: true);

    for (var entry in events.entries) {
      var remoteSourceId = entry.key;

      await removeAllEventsFromRemoteCalendar(remoteSourceId);

      var migratedContent = {
        "type": "chat.commet.calendar_events",
        "content": {
          "m.relates_to": {"event_id": calenarId, "rel_type": "m.reference"},
          "format": "chat.commet.calendar.event.rfc8984",
          "remote_source_id": remoteSourceId,
          "events": entry.value
              .map((i) => {
                    if (eventType != null) "type": eventType,
                    "event": i.toJson(),
                  })
              .toList(),
        }
      };

      await widgetApi.sendAction(FromWidgetAction.sendEvent, migratedContent);
    }
  }

  Future<void> removeAllEventsFromRemoteCalendar(String id) async {
    var existing =
        controller.allEvents.where((i) => i.event?.remoteSourceId == id);

    Set<String> removeEvents = Set();
    for (var e in existing) {
      if (e.event?.eventId != null) removeEvents.add(e.event!.eventId!);
    }

    print("CalendarWidget: removing ${removeEvents.length} stale events");

    for (var i in removeEvents) {
      await redactEvent(i);
    }
  }

  Future<void> deleteEvent(RFC8984CalendarEvent event) async {
    print("Deleting event");
    final eventIds = <String>{};
    for (var e in controller.allEvents.toList()) {
      if (e.event?.data.uid == event.uid) {
        var eventId = e.event?.eventId;
        print("CalendarWidget: event id available=${eventId != null}");
        if (eventId != null) {
          eventIds.add(eventId);
        }
      }
    }

    controller.removeWhere(
        (e) => e.event?.data.uid == event.uid && e.event?.eventId == null);

    for (final eventId in eventIds) {
      await redactEvent(eventId);
    }
  }

  Future<void> deleteEventOccurrence(
    RFC8984CalendarEvent event,
    DateTime occurrenceDate, {
    String? eventType,
  }) async {
    if (event.recurrenceRules?.isNotEmpty != true) {
      await deleteEvent(event);
      return;
    }

    await createEvent(
      event.withExcludedRecurrenceDate(occurrenceDate),
      eventType: eventType,
    );
  }

  Future<void> redactEvent(String eventId) async {
    await widgetApi.sendAction(FromWidgetAction.sendEvent, {
      "type": "m.room.redaction",
      "chat.commet.calendar.redaction": "edit",
      "content": {"redacts": eventId}
    });
    _markEventRedacted(eventId);
  }

  Future<bool> createEvent(RFC8984CalendarEvent event,
      {String? eventType}) async {
    if (event.uid == "") {
      event.uid = _generateId();
    }

    var existing = controller.allEvents
        .where((i) =>
            i.event?.data.uid == event.uid &&
            i.event?.senderId == widgetApi.userId)
        .firstOrNull;

    var existingEventId = existing?.event?.eventId;

    print("CalendarWidget: existing event found=${existing != null}");

    final pendingEvents = <CalendarEventData<MatrixCalendarEventState>>[];
    controller.removeWhere((e) =>
        e.event?.data.uid == event.uid &&
        e.event?.senderId == widgetApi.userId);

    print("Replaced existing events with pending local event");
    var calendarEvents = fromRfcEvent(event, eventType: eventType);
    for (var calendarEvent in calendarEvents) {
      var color = config.getColorFromUser(widgetApi.userId);

      calendarEvent = calendarEvent.copyWith(color: color);
      calendarEvent.event!.senderId = widgetApi.userId;
      calendarEvent.event!.type = eventType;
      calendarEvent.event!.loaded = false;

      controller.add(calendarEvent);
      pendingEvents.add(calendarEvent);
    }

    print("Added event");

    var calendarId = await getCalendarId(createIfNotFound: true);
    print("CalendarWidget: calendar id available=${calendarId != null}");
    if (calendarId == null) {
      for (final pendingEvent in pendingEvents) {
        controller.remove(pendingEvent);
      }
      return false;
    }

    var result = await widgetApi.sendAction(FromWidgetAction.sendEvent, {
      "type": "chat.commet.calendar_events",
      "content": {
        "m.relates_to": {"event_id": calendarId, "rel_type": "m.reference"},
        "format": "chat.commet.calendar.event.rfc8984",
        "events": [
          {
            if (eventType != null) "type": eventType,
            "event": event.toJson(),
          }
        ],
      }
    });

    print("Sent event!");
    print(
        "CalendarWidget: send event result keys=${_calendarDebugKeys(result)}");

    if (existingEventId != null) {
      await widgetApi.sendAction(FromWidgetAction.sendEvent, {
        "type": "m.room.redaction",
        "content": {"redacts": existingEventId}
      });
    }

    return true;
  }

  Future<String?> getCalendarId({bool createIfNotFound = false}) async {
    var calendar = roomState["chat.commet.calendars"];
    print("Getting calendar id, create: $createIfNotFound");

    String? calendarId;

    print("CalendarWidget: calendar state available=${calendar != null}");

    if (calendar != null) {
      final defaultCalendarState = calendar[""];
      final content = defaultCalendarState is Map<String, dynamic>
          ? defaultCalendarState["content"]
          : null;
      final calendars =
          content is Map<String, dynamic> ? content["calendars"] : null;

      if (calendars is List && calendars.isNotEmpty) {
        final firstCalendarId = calendars.first;
        if (firstCalendarId is String) {
          calendarId = firstCalendarId;
        }
      }
    }

    if (calendarId == null && createIfNotFound) {
      var result = await widgetApi.sendAction(FromWidgetAction.sendEvent,
          {"type": "chat.commet.calendar_create", "content": {}});

      print("Sent action");
      print(
          "CalendarWidget: send action result keys=${_calendarDebugKeys(result)}");

      if (result.containsKey("event_id")) {
        calendarId = result["event_id"] as String;

        await widgetApi.sendAction(FromWidgetAction.sendEvent, {
          "type": "chat.commet.calendars",
          "state_key": "",
          "content": {
            "calendars": [
              result["event_id"],
            ]
          }
        });

        print("Added calendar to room state");
      }
    }

    return calendarId;
  }

  RecurrenceSettings? toRecurrenceSettings(RFC8984CalendarEvent event) {
    if (event.recurrenceRules == null) return null;

    var rule = event.recurrenceRules?.firstOrNull;
    if (rule == null) return null;

    var frequency = switch (rule.frequency) {
      "daily" => RepeatFrequency.daily,
      "weekly" => RepeatFrequency.weekly,
      "monthly" => RepeatFrequency.monthly,
      "yearly" => RepeatFrequency.yearly,
      _ => RepeatFrequency.doNotRepeat,
    };

    final localStart = config.convertToLocalTime(event.start, event.timeZone);

    List<int>? weekdays;

    if (rule.byDay != null) {
      weekdays = List.empty(growable: true);
      for (var day in rule.byDay!) {
        var dayNum = switch (day.day) {
          "mo" => 0,
          "tu" => 1,
          "we" => 2,
          "th" => 3,
          "fr" => 4,
          "sa" => 5,
          "su" => 6,
          _ => throw UnimplementedError()
        };

        weekdays.add(dayNum);
      }
    }

    if (frequency == RepeatFrequency.weekly &&
        (weekdays == null || weekdays.isEmpty)) {
      weekdays = [localStart.weekday - 1];
    }

    if (rule.count != null) {
      return RecurrenceSettings.withCalculatedEndDate(
        startDate: localStart,
        occurrences: rule.count,
        frequency: frequency,
        weekdays: weekdays,
        excludeDates: recurrenceExcludedDates(event),
      );
    }

    return RecurrenceSettings(
      startDate: localStart,
      endDate: rule.until != null
          ? config.convertToLocalTime(rule.until!, event.timeZone)
          : null,
      occurrences: rule.count,
      frequency: frequency,
      recurrenceEndOn:
          rule.until != null ? RecurrenceEnd.onDate : RecurrenceEnd.never,
      weekdays: weekdays,
      excludeDates: recurrenceExcludedDates(event),
    );
  }

  Map<String, dynamic>? onEventReceived(Map<String, dynamic> apiData) {
    var eventType = apiData["data"]["type"];

    if (eventType == "chat.commet.calendar_events") {
      handleCalendarEventReceived(apiData["data"]);
    }

    if (eventType == attendanceEventType) {
      handleAttendanceEventReceived(apiData["data"]);
    }

    if (eventType == "m.room.redaction") {
      handleCalendarEventDeleted(apiData["data"]);
    }

    return null;
  }

  void handleAttendanceEventReceived(Map<String, dynamic> eventData) {
    final sender = eventData["sender"] as String?;
    final content = eventData["content"] as Map<String, dynamic>?;
    final eventUid = content?["calendar_event_uid"] as String?;
    if (sender == null || content == null || eventUid == null) {
      return;
    }

    final originServerTs = eventData["origin_server_ts"] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            eventData["origin_server_ts"] as int,
            isUtc: true,
          ).toLocal()
        : null;

    final reminderOffsets = normalizeReminderOffsets(
      (content["reminder_offsets_minutes"] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toInt()),
    );

    final nextState = CalendarAttendanceState(
      userId: sender,
      attending: content["attending"] == true,
      useDefaultReminders: content["use_default_reminders"] == true,
      reminderOffsetsMinutes: reminderOffsets,
      updated: originServerTs,
    );

    final existing = _attendanceState[eventUid]?[sender];
    if (existing?.originServerTs != null &&
        originServerTs != null &&
        existing!.originServerTs!.isAfter(originServerTs)) {
      return;
    }

    _attendanceState.putIfAbsent(eventUid, () => {});
    _attendanceState[eventUid]![sender] = _StoredAttendanceEvent(
      state: nextState,
      originServerTs: originServerTs,
    );
    controller.updateFilter(newFilter: (date, events) {
      return filterEventsOnDay(date, events);
    });
  }

  void handleCalendarEventReceived(Map<String, dynamic> eventData) {
    var sender = eventData["sender"];
    var content = eventData["content"] as Map<String, dynamic>;

    if (!content.containsKey("events")) {
      return;
    }
    var events = content["events"] as List<dynamic>;
    var remoteSource = content["remote_source_id"];

    var eventId = eventData["event_id"];
    if (eventId is String) {
      if (_redactedEventIds.contains(eventId)) {
        return;
      }
      _removeCalendarEntriesForEventId(eventId);
    }

    for (var event in events) {
      var mxCalendarEvent = RFC8984CalendarEvent.fromJson(event["event"]);
      var eventType = event["type"];

      var color = config.getColorFromUser(sender);
      var calendarEvents = fromRfcEvent(mxCalendarEvent, eventType: eventType);
      controller.removeWhere((i) =>
          i.event?.data.uid == mxCalendarEvent.uid && i.event?.eventId == null);

      for (var calendarEvent in calendarEvents) {
        calendarEvent = calendarEvent.copyWith(color: color);
        calendarEvent.event!.senderId = sender;
        calendarEvent.event!.loaded = true;
        calendarEvent.event!.remoteSourceId = remoteSource;
        calendarEvent.event!.type = eventType;
        calendarEvent.event!.eventId = eventId;

        controller.add(calendarEvent);
      }
    }
  }

  void handleCalendarEventDeleted(eventData) {
    if (eventData is! Map) {
      return;
    }
    final content = eventData["content"];
    final contentRedacts = content is Map ? content["redacts"] : null;
    final eventId =
        contentRedacts is String ? contentRedacts : eventData["redacts"];

    if (eventId is String) {
      _markEventRedacted(eventId);
    }
  }

  Future<void> migrateRoomStateEvents(
      Function(int progress, int total) onProgress) async {
    var stateEvent = roomState["chat.commet.calendar_event"]![widgetApi.userId];

    var events = Map<String, dynamic>.from(
        stateEvent["content"]['events'] as Map<String, dynamic>);

    var calendarId = await getCalendarId(createIfNotFound: true);
    print("CalendarWidget: calendar id available=${calendarId != null}");
    if (calendarId == null) return;

    int total = events.length;

    while (events.isNotEmpty) {
      var key = events.keys.first;
      var e = events[key];

      var remoteSource = e["remote_source_id"];

      var keys = [
        key,
        if (remoteSource != null)
          ...events.keys
              .where((e) => events[e]["remote_source_id"] == remoteSource)
      ];

      var eventsGroup =
          keys.map((i) => Map<String, dynamic>.from(events[i])).toList();

      for (var event in keys) {
        print("CalendarWidget: removing migrated event key");
        events.remove(event);
      }

      for (var e in eventsGroup) {
        e.remove("remote_source_id");
      }

      int eventsLeft = events.length;

      onProgress(eventsLeft, total);

      var migratedContent = {
        "type": "chat.commet.calendar_events",
        "content": {
          "m.relates_to": {"event_id": calendarId, "rel_type": "m.reference"},
          "format": "chat.commet.calendar.event.rfc8984",
          if (remoteSource != null) "remote_source_id": remoteSource,
          "events": eventsGroup,
        }
      };

      await widgetApi.sendAction(FromWidgetAction.sendEvent, migratedContent);

      await Future.delayed(Duration(seconds: 2));

      print(
        "CalendarWidget: migrated remote source "
        "eventCount=${eventsGroup.length}",
      );
    }

    await widgetApi.sendAction(FromWidgetAction.sendEvent, {
      "type": "chat.commet.calendar_event",
      "state_key": widgetApi.userId,
      "content": {}
    });

    needsStateMigration = false;
    print("Finished migrating");
  }
}
