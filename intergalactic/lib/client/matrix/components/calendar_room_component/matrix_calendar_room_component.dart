import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/calendar_room/calendar_sync.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_direct_fetch_resolver.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';
import 'package:intergalactic/client/matrix/widget/privelidged_matrix_widget_runner.dart';
import 'package:intergalactic/config/global_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:intergalactic/utils/timezone_utils.dart';
import 'package:commet_calendar_widget/calendar_event_metadata.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:icalendar_parser/icalendar_parser.dart' as ical;
import 'package:matrix/matrix.dart';
import 'package:commet_calendar_widget/calendar.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class CustomMatrixCalendarConfig extends MatrixCalendarConfig {
  final MatrixRoom room;

  CustomMatrixCalendarConfig(this.room);

  @override
  Future<T?> dialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext context) builder,
  }) {
    return AdaptiveDialog.show(
      context,
      scrollable: false,
      builder: (context) => constrainDialogContent(context, builder(context)),
    );
  }

  @override
  ImageProvider<Object>? getUserAvatar(String userId) {
    return room.getMemberOrFallback(userId).avatar;
  }

  @override
  Color getColorFromUser(String userId) {
    return room.getColorOfUser(userId);
  }
}

class MatrixCalendarRoomComponent
    implements
        CalendarRoom<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener,
        NeedsPostLoginInit,
        DisposableComponent {
  MatrixCalendar? _calendar;
  bool _disposed = false;
  bool _calendarListenerAttached = false;

  static const String syncedCalendarsEventType =
      "chat.commet.calendar.synced_calendar_urls";
  static const Duration _icsFetchTimeout = Duration(seconds: 8);
  static const int _maxIcsBodyBytes = 1024 * 1024 * 2;
  static const int _maxIcsRedirects = 5;

  final StreamController<void> controller = StreamController.broadcast();

  late StoredStreamController<Map<String, SyncedCalendar>> syncedCalendars;
  final Map<String, Timer> _reminderTimers = {};

  @override
  bool get isCalendarRoom {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        "chat.commet.calendar";
  }

  MatrixCalendarRoomComponent(this.client, this.room) {
    var api = PrivelidgedMatrixWidgetRunner(
      client.matrixClient,
      room.matrixRoom,
    );

    if (isCalendarRoom) {
      _calendar = MatrixCalendar(api, config: CustomMatrixCalendarConfig(room));
      _attachCalendarListener(_calendar!);
    }

    syncedCalendars = StoredStreamController(getCalendarsFromAccountData());
  }

  @override
  void postLoginInit() {
    if (!isHeadless) {
      unawaited(_startPostLoginCalendarSync());
    }
  }

  Future<void> _startPostLoginCalendarSync() async {
    try {
      await TimezoneUtils.instance.init();
      if (_disposed) {
        return;
      }

      _calendar?.widgetApi.start();
      await CalendarSync.instance.startSyncing();
      refreshReminderTimers();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to initialize calendar post-login sync',
      );
    }
  }

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  @override
  MatrixCalendar? get calendar {
    if (_disposed) {
      return _calendar;
    }

    if (_calendar != null) {
      return _calendar!;
    } else {
      if (isCalendarRoom || hasCalendarWidget) {
        var api = PrivelidgedMatrixWidgetRunner(
          client.matrixClient,
          room.matrixRoom,
        );
        _calendar = MatrixCalendar(
          api,
          config: CustomMatrixCalendarConfig(room),
        );
        _attachCalendarListener(_calendar!);

        _calendar!.widgetApi.start();
        refreshReminderTimers();
      }
      return _calendar;
    }
  }

  bool get hasCalendarWidget =>
      room.matrixRoom.states.containsKey("chat.commet.calendar_events") ||
      room.matrixRoom.states["im.vector.modular.widgets"]?.values.any(
            (i) =>
                i.content["type"] == "chat.commet.widgets.calendar" ||
                (i.content["url"] as String?)?.startsWith(
                      "https://${GlobalConfig.calendarWidgetHost}",
                    ) ==
                    true,
          ) ==
          true;

  @override
  bool get hasCalendar => isCalendarRoom || hasCalendarWidget;

  @override
  Stream<void> get onEventsChanged => controller.stream;

  @override
  List<MatrixCalendarEventState> getEventsOnDay(DateTime date) {
    return _calendar?.getEventsOnDay(date) ?? [];
  }

  @override
  onSync(JoinedRoomUpdate update) {
    if (_disposed) {
      return;
    }

    if (update.accountData?.any((i) => i.type == syncedCalendarsEventType) ==
        true) {
      syncedCalendars.add(getCalendarsFromAccountData());
    }

    refreshReminderTimers();
  }

  void refreshReminderTimers() {
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();

    if (_disposed) {
      return;
    }

    final currentCalendar = calendar;
    if (currentCalendar == null || isHeadless) {
      return;
    }

    final userId = client.matrixClient.userID;
    if (userId == null) {
      return;
    }

    for (final schedule in currentCalendar.getReminderSchedulesForUser(
      userId,
    )) {
      final key =
          "${schedule.eventUid}:${schedule.eventStart.toIso8601String()}:${schedule.minutesBefore}";
      final delay = schedule.remindAt.difference(DateTime.now());
      if (delay.isNegative) {
        continue;
      }

      _reminderTimers[key] = Timer(delay, () async {
        _reminderTimers.remove(key);
        if (_disposed) {
          return;
        }

        await showReminderNotification(schedule);
        refreshReminderTimers();
      });
    }
  }

  Future<void> showReminderNotification(
    CalendarReminderSchedule schedule,
  ) async {
    final leadText = switch (schedule.minutesBefore) {
      0 => "now",
      final minutes when minutes % 10080 == 0 =>
        "${minutes ~/ 10080} week${minutes ~/ 10080 == 1 ? "" : "s"}",
      final minutes when minutes % 1440 == 0 =>
        "${minutes ~/ 1440} day${minutes ~/ 1440 == 1 ? "" : "s"}",
      final minutes when minutes % 60 == 0 =>
        "${minutes ~/ 60} hour${minutes ~/ 60 == 1 ? "" : "s"}",
      final minutes => "$minutes minute${minutes == 1 ? "" : "s"}",
    };

    final content = CalendarReminderNotificationContent(
      roomId: room.identifier,
      clientId: client.identifier,
      roomName: room.displayName,
      eventUid: schedule.eventUid,
      eventStart: schedule.eventStart,
      minutesBefore: schedule.minutesBefore,
      title: schedule.minutesBefore == 0
          ? schedule.title
          : "Upcoming: ${schedule.title}",
      content: schedule.minutesBefore == 0
          ? "${schedule.title} starts now in ${room.displayName}."
          : "${schedule.title} starts in $leadText in ${room.displayName}.",
      roomImage: await room.getShortcutImage(),
      roomImageId: room.avatarId,
    );

    await NotificationManager.notify(content, forceShow: true);
  }

  Map<String, SyncedCalendar> getCalendarsFromAccountData() {
    var data = room.matrixRoom.roomAccountData[syncedCalendarsEventType];

    if (data != null && room.isE2EE) {
      if (data.content.isNotEmpty) {
        Log.w(
          "Deleting calendar URL source because this room is encrypted, and the source is stored in plaintext - you should generate a new URL",
        );
        Log.w(
          "Plaintext calendar URL source account data removed; "
          "keys=${data.content.keys.join(",")}",
        );

        room.matrixRoom.client.setAccountDataPerRoom(
          client.matrixClient.userID!,
          room.identifier,
          syncedCalendarsEventType,
          {},
        );
      }
    }

    if (room.isE2EE) {
      data = BasicEvent(
        type: syncedCalendarsEventType,
        content: {
          "remote_calendars": preferences.getCalendarSources(room.identifier),
        },
      );
    }

    if (data == null) {
      return {};
    }

    try {
      var content = data.content["remote_calendars"];
      if (content == null) {
        return {};
      }

      var entries = content as Map<String, dynamic>;
      var result = Map<String, SyncedCalendar>();

      for (var entry in entries.entries) {
        var id = entry.key;
        var data = entry.value as Map<String, dynamic>;

        var cal = SyncedCalendar.fromJson(data);
        cal.id = id;
        result[id] = cal;
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> addSyncedCalendar(SyncedCalendar calendar) async {
    var calendars = syncedCalendars.value ?? {};

    var uuid = const Uuid();
    var id = calendar.id ?? uuid.v4();
    calendars[id] = calendar;

    syncedCalendars.add(calendars);

    var c = room.matrixRoom.client;

    var result = Map<String, dynamic>();

    for (var entry in calendars.entries) {
      result[entry.key] = entry.value.toJson();
    }

    Log.i("Setting synced calendars: ${calendars}");
    Log.i("Is room encrypted: ${room.isE2EE}");

    if (room.isE2EE) {
      Log.i("Storing calendar source locally, because this room is encrypted");
      await preferences.setCalendarSources(room.matrixRoom.id, result);
      syncedCalendars.add(getCalendarsFromAccountData());
    } else {
      Log.i("Storing calendar source in account data");
      return room.matrixRoom.client.setAccountDataPerRoom(
        c.userID!,
        room.matrixRoom.id,
        syncedCalendarsEventType,
        {"remote_calendars": result},
      );
    }
  }

  @override
  Future<void> runCalendarSync() async {
    if (calendar == null) return;

    var calendars = syncedCalendars.value;
    if (calendars == null) {
      return;
    }

    if (calendar!.getAllEvents().isEmpty) {
      await Future.delayed(Duration(seconds: 5));
    }

    Map<String, List<RFC8984CalendarEvent>> foundEvents = {};

    for (var entry in calendars.entries) {
      if (entry.value.sourceType == CalendarSource.ical) {
        var url = Uri.tryParse(entry.value.source);
        if (url == null) {
          Log.w("Skipping synced calendar with invalid ICS URL");
          continue;
        }
        var events = await getEventsFromIcsUrl(url);

        var existingEvents = calendar!
            .getAllEvents()
            .where((i) => i.remoteSourceId == entry.key)
            .map((i) => i.data)
            .toList();

        if (entry.value.overrideEventName != null) {
          events = events
              .map(
                (i) => RFC8984CalendarEvent(
                  uid: i.uid,
                  updated: i.updated,
                  title: entry.value.overrideEventName!,
                  start: i.start,
                  timeZone: i.timeZone,
                  duration: i.duration,
                ),
              )
              .toList();
        }

        if (areEventListsIdentical(existingEvents, events)) {
          Log.i(
            "Calendar events are identical, not sending any data for this calendar",
          );
          continue;
        } else {
          Log.i("Calendar events are different, syncing");
        }

        if (events.isNotEmpty) {
          foundEvents[entry.key] = events;
        }
      }
      calendar!.syncEvents(
        foundEvents,
        eventType: switch (entry.value.syncType) {
          CalendarSyncType.events => "event",
          CalendarSyncType.unavailability => "unavailability",
        },
      );
    }
  }

  RFC8984CalendarEvent? fromIcal(String calendarId, Map<String, dynamic> data) {
    if (data["type"] != "VEVENT") {
      return null;
    }

    final startIcs = (data["dtstart"] as ical.IcsDateTime?);
    final endIcs = (data["dtend"] as ical.IcsDateTime?);

    var start = startIcs?.toDateTime();
    var end = endIcs?.toDateTime();
    var rrule = data["rrule"] as String?;
    var startTimezone = startIcs?.tzid;

    RFC8984RecurrenceRule? recur;
    if (rrule != null) {
      recur = parseRecurrenceRule(rrule);
    }

    // if it doesnt recur, we dont need a timezone
    if (recur == null) {
      start = start?.toUtc();
      end = end?.toUtc();
      startTimezone = null;
    }

    if (start == null || end == null) {
      Log.i("Event had no start or end time, skipping");
      return null;
    }

    final title = (data["summary"] as String?) ?? "(No title)";

    var updated =
        (data["lastModified"] as ical.IcsDateTime?)?.toDateTime() ??
        DateTime.now();

    var uid = sha1.convert("$calendarId/${data["uid"]}".codeUnits);

    var duration = end.difference(start);

    return RFC8984CalendarEvent(
      uid: uid.toString(),
      timeZone: startTimezone,
      updated: updated.toUtc(),
      title: title,
      recurrenceRules: recur != null ? [recur] : null,
      start: start,
      duration: duration,
    );
  }

  RFC8984RecurrenceRule? parseRecurrenceRule(String rrule) {
    Log.i("Parsing calendar recurrence rule");
    var rule = Map<String, String>.new();
    var parts = rrule.split(";");
    for (var part in parts) {
      var otherParts = part.split("=");
      var key = otherParts[0];
      var value = otherParts[1];
      rule[key] = value;
    }

    var frequency = rule["FREQ"]?.toLowerCase();
    var firstDayOfWeek = rule["WKST"]?.toLowerCase();
    int? count = rule["COUNT"] != null ? int.parse(rule["COUNT"]!) : null;
    int? interval = rule["INTERVAL"] != null
        ? int.parse(rule["INTERVAL"]!)
        : null;

    if (frequency == null) return null;

    List<Rfc8984NDay>? byDays;
    if (rule["BYDAY"] != null) {
      byDays = parseByDays(rule["BYDAY"]!);
    }

    List<int>? byMonthDay;
    if (rule["BYMONTHDAY"] != null) {
      byMonthDay = rule["BYMONTHDAY"]!
          .split(",")
          .map(int.tryParse)
          .nonNulls
          .toList();
    }

    return RFC8984RecurrenceRule(
      firstDayOfWeek: firstDayOfWeek,
      frequency: frequency,
      interval: interval,
      count: count,
      byMonthDay: byMonthDay,
      byDay: byDays,
    );
  }

  List<Rfc8984NDay> parseByDays(String rule) {
    var days = rule.split(",");
    var result = List<Rfc8984NDay>.empty(growable: true);
    for (var day in days) {
      var lower = day.toLowerCase();
      var dayName = lower.substring(lower.length - 2);
      int? period;
      if (lower.length > 2) {
        var periodStr = lower.substring(0, lower.length - 2);
        period = int.tryParse(periodStr);
      }

      if (["mo", "tu", "we", "th", "fr", "sa", "su"].contains(dayName)) {
        result.add(Rfc8984NDay(dayName, nthOfPeriod: period));
      }
    }

    return result;
  }

  @override
  Future<void> removeSyncedCalendar(String id) async {
    if (syncedCalendars.value == null) {
      return;
    }

    var urls = syncedCalendars.value ?? {};
    urls.remove(id);
    var c = room.matrixRoom.client;

    if (room.isE2EE) {
      Log.i("Storing calendar source locally, because this room is encrypted");
      await preferences.setCalendarSources(room.matrixRoom.id, urls);
      syncedCalendars.add(getCalendarsFromAccountData());
    } else {
      await room.matrixRoom.client.setAccountDataPerRoom(
        c.userID!,
        room.matrixRoom.id,
        syncedCalendarsEventType,
        {"remote_calendars": urls},
      );
    }

    calendar!.removeAllEventsFromRemoteCalendar(id);
  }

  @override
  Future<List<RFC8984CalendarEvent>> getEventsFromIcsUrl(
    Uri uri, {
    String? calendarId,
  }) async {
    try {
      final content = await _fetchIcsBody(uri);
      if (content == null) {
        return List.empty();
      }

      final iCal = ICalendar.fromString(content);

      var id = calendarId ?? "unknown_id";

      var results = iCal.data.map((e) => fromIcal(id, e)).nonNulls.toList();

      Log.i("Found ${results.length} events to sync to calendar");
      return results;
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content:
            "Failed to fetch or parse remote calendar for host=${_calendarHostForLog(uri)}",
      );
      return List.empty();
    }
  }

  Future<String?> _fetchIcsBody(Uri uri) async {
    if (!UrlPreviewFallbackFetcher.isSafeDirectFetchUri(uri)) {
      Log.w(
        "Blocked unsafe remote calendar URL host=${_calendarHostForLog(uri)}",
      );
      return null;
    }

    final client = http.Client();
    try {
      var currentUri = uri;
      for (var redirects = 0; redirects <= _maxIcsRedirects; redirects += 1) {
        if (!UrlPreviewFallbackFetcher.isSafeDirectFetchUri(currentUri) ||
            !await isDirectFetchDnsSafe(currentUri)) {
          Log.w(
            "Blocked unsafe remote calendar URL host=${_calendarHostForLog(currentUri)}",
          );
          return null;
        }

        final request = http.Request("GET", currentUri)
          ..followRedirects = false
          ..headers.addAll({
            "Accept":
                "text/calendar,text/plain,text/x-vcalendar,application/octet-stream,*/*",
            "User-Agent": "Inter Galactic Calendar Sync",
          });
        final response = await client.send(request).timeout(_icsFetchTimeout);

        if (_isRedirectStatus(response.statusCode)) {
          final location = response.headers["location"];
          await _drainIcsResponse(response.stream);
          if (location == null || location.trim().isEmpty) {
            return null;
          }
          currentUri = currentUri.resolve(location);
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await _drainIcsResponse(response.stream);
          Log.w(
            "Remote calendar fetch failed status=${response.statusCode} "
            "host=${_calendarHostForLog(currentUri)}",
          );
          return null;
        }

        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > _maxIcsBodyBytes) {
          await _drainIcsResponse(response.stream);
          Log.w(
            "Remote calendar response too large "
            "host=${_calendarHostForLog(currentUri)}",
          );
          return null;
        }

        if (!_isSupportedIcsContentType(response.headers["content-type"])) {
          await _drainIcsResponse(response.stream);
          Log.w(
            "Remote calendar response had unsupported content type "
            "host=${_calendarHostForLog(currentUri)}",
          );
          return null;
        }

        final bytes = await _readLimitedIcsBody(response.stream);
        return utf8.decode(bytes, allowMalformed: true);
      }

      Log.w("Remote calendar fetch exceeded redirect limit");
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _drainIcsResponse(Stream<List<int>> stream) async {
    await stream.drain<void>().timeout(_icsFetchTimeout);
  }

  Future<List<int>> _readLimitedIcsBody(Stream<List<int>> stream) {
    return _readLimitedIcsBodyWithoutTimeout(stream).timeout(_icsFetchTimeout);
  }

  Future<List<int>> _readLimitedIcsBodyWithoutTimeout(
    Stream<List<int>> stream,
  ) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > _maxIcsBodyBytes) {
        throw StateError("Remote calendar response exceeded size limit");
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  bool _isSupportedIcsContentType(String? contentType) {
    if (contentType == null || contentType.trim().isEmpty) {
      // Some calendar providers omit a content type for valid ICS feeds.
      // Safety still comes from scheme/DNS checks, body timeout, and size caps.
      return true;
    }
    final normalized = contentType.split(";").first.trim().toLowerCase();
    return normalized == "text/calendar" ||
        normalized == "text/plain" ||
        normalized == "text/x-vcalendar" ||
        normalized == "application/octet-stream";
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  String _calendarHostForLog(Uri uri) {
    final host = uri.host.trim();
    if (host.isEmpty) {
      return "unknown";
    }
    return Log.redactSensitiveInfo(host);
  }

  bool shouldUpdateState(
    List<MatrixCalendarEventState> existingEvents,
    List<MatrixCalendarEventState> eventsAfterSync,
  ) {
    if (existingEvents.length != eventsAfterSync.length) return true;

    existingEvents.sort((a, b) => a.data.start.compareTo(b.data.start));
    eventsAfterSync.sort((a, b) => a.data.start.compareTo(b.data.start));

    for (var event in eventsAfterSync) {
      if (!existingEvents.any((i) => i == event)) {
        return true;
      }
    }

    return false;
  }

  bool containsEvent(
    List<RFC8984CalendarEvent> list,
    RFC8984CalendarEvent event,
  ) {
    var b = event.toJson();
    b.remove("uid");
    b.remove("updated");

    var bstr = jsonEncode(b);
    var contained = list.firstWhereOrNull((i) {
      var a = i.toJson();
      a.remove("uid");
      a.remove("updated");
      var ason = jsonEncode(a);
      var identical = ason == bstr;

      return identical;
    });

    return contained != null;
  }

  bool areEventListsIdentical(
    List<RFC8984CalendarEvent> existingEvents,
    List<RFC8984CalendarEvent> events,
  ) {
    if (existingEvents.any((i) => !containsEvent(events, i))) {
      return false;
    }

    if (events.any((i) => !containsEvent(existingEvents, i))) {
      return false;
    }

    return true;
  }

  void _attachCalendarListener(MatrixCalendar calendar) {
    if (_calendarListenerAttached) {
      return;
    }

    calendar.controller.addListener(_onCalendarChanged);
    _calendarListenerAttached = true;
  }

  void _detachCalendarListener() {
    final calendar = _calendar;
    if (calendar == null || !_calendarListenerAttached) {
      return;
    }

    calendar.controller.removeListener(_onCalendarChanged);
    _calendarListenerAttached = false;
  }

  void _onCalendarChanged() {
    if (_disposed) {
      return;
    }

    if (!controller.isClosed) {
      controller.add(null);
    }
    refreshReminderTimers();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();
    _detachCalendarListener();
    await syncedCalendars.close();
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}
