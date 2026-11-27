import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:iso_duration/iso_duration.dart';
part 'rfc8984.g.dart';

const List<int> monthlyOrdinalOptions = [1, 2, 3, 4, 5, -2, -1];
const String recurrenceExcludedDatesKey = "excludedDates";

Map<String, dynamic> _deepJsonMap(Map<String, dynamic> data) {
  return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
}

String recurrenceOrdinalLabel(int ordinal) {
  return switch (ordinal) {
    1 => "First",
    2 => "Second",
    3 => "Third",
    4 => "Fourth",
    5 => "Fifth",
    -2 => "Next to Last",
    -1 => "Last",
    _ => ordinal.toString(),
  };
}

String recurrenceWeekdayLabel(String day) {
  return switch (day) {
    "mo" => "Mon",
    "tu" => "Tue",
    "we" => "Wed",
    "th" => "Thu",
    "fr" => "Fri",
    "sa" => "Sat",
    "su" => "Sun",
    _ => day,
  };
}

String recurrenceDateKey(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return DateFormat("yyyy-MM-dd").format(normalized);
}

Set<String> recurrenceExcludedDateKeys(RFC8984CalendarEvent event) {
  final overrides = event.recurrenceOverrides;
  final raw = overrides?[recurrenceExcludedDatesKey];
  if (raw is Iterable) {
    return raw.whereType<String>().toSet();
  }

  return <String>{};
}

List<DateTime> recurrenceExcludedDates(RFC8984CalendarEvent event) {
  return recurrenceExcludedDateKeys(event)
      .map((value) => DateTime.tryParse(value))
      .nonNulls
      .map((value) => DateTime(value.year, value.month, value.day))
      .toList();
}

bool isRecurrenceDateExcluded(RFC8984CalendarEvent event, DateTime date) {
  return recurrenceExcludedDateKeys(event).contains(recurrenceDateKey(date));
}

class IsoDurationConverter extends JsonConverter<Duration, String> {
  const IsoDurationConverter();

  @override
  Duration fromJson(String json) {
    return tryParseIso8601Duration(json)!;
  }

  @override
  String toJson(Duration object) {
    return object.toIso8601String();
  }
}

class IsoDateTimeConverter extends JsonConverter<DateTime, String> {
  const IsoDateTimeConverter();

  @override
  DateTime fromJson(String json) {
    return DateTime.parse(json);
  }

  @override
  String toJson(DateTime object) {
    if (object.isUtc) {
      DateFormat formatter = DateFormat("yyyy-MM-ddTHH:mm:ss");
      var result = formatter.format(object) + "Z";
      return result;
    } else {
      DateFormat formatter = DateFormat("yyyy-MM-ddTHH:mm:ss");
      return formatter.format(object);
    }
  }
}

@JsonSerializable(includeIfNull: false)
class RFC8984CalendarEvent {
  static const String type = "Event";
  String uid;

  @IsoDateTimeConverter()
  DateTime updated;
  String title;

  String? description;

  @IsoDateTimeConverter()
  DateTime start;
  String? timeZone;

  @IsoDurationConverter()
  Duration duration;

  String? locale;

  List<int>? attendeeReminderOffsetsMinutes;

  List<RFC8984RecurrenceRule>? recurrenceRules;
  Map<String, dynamic>? recurrenceOverrides;

  Map<String, RFC8984Location>? locations;
  Map<String, RFC8984VirtualLocation>? virtualLocations;

  Map<String, Map<String, String>>? localizations;

  RFC8984CalendarEvent({
    required this.uid,
    required this.updated,
    required this.title,
    this.description,
    required this.start,
    required this.duration,
    this.timeZone,
    this.attendeeReminderOffsetsMinutes,
    this.recurrenceRules,
    this.locations,
    this.virtualLocations,
    this.localizations,
    this.recurrenceOverrides,
  });

  factory RFC8984CalendarEvent.fromJson(Map<String, dynamic> json) =>
      _$RFC8984CalendarEventFromJson(json);

  RFC8984CalendarEvent copyWith({
    String? uid,
    DateTime? updated,
    String? title,
    String? description,
    DateTime? start,
    String? timeZone,
    Duration? duration,
    String? locale,
    List<int>? attendeeReminderOffsetsMinutes,
    List<RFC8984RecurrenceRule>? recurrenceRules,
    Map<String, dynamic>? recurrenceOverrides,
    Map<String, RFC8984Location>? locations,
    Map<String, RFC8984VirtualLocation>? virtualLocations,
    Map<String, Map<String, String>>? localizations,
  }) {
    return RFC8984CalendarEvent(
      uid: uid ?? this.uid,
      updated: updated ?? this.updated,
      title: title ?? this.title,
      description: description ?? this.description,
      start: start ?? this.start,
      duration: duration ?? this.duration,
      timeZone: timeZone ?? this.timeZone,
      attendeeReminderOffsetsMinutes:
          attendeeReminderOffsetsMinutes ?? this.attendeeReminderOffsetsMinutes,
      recurrenceRules: recurrenceRules ?? this.recurrenceRules,
      recurrenceOverrides: recurrenceOverrides ?? this.recurrenceOverrides,
      locations: locations ?? this.locations,
      virtualLocations: virtualLocations ?? this.virtualLocations,
      localizations: localizations ?? this.localizations,
    )..locale = locale ?? this.locale;
  }

  RFC8984CalendarEvent withExcludedRecurrenceDate(DateTime date) {
    final nextOverrides = Map<String, dynamic>.from(recurrenceOverrides ?? {});
    final excluded = recurrenceExcludedDateKeys(this);
    excluded.add(recurrenceDateKey(date));
    nextOverrides[recurrenceExcludedDatesKey] = excluded.toList()..sort();

    return copyWith(
      updated: DateTime.now().toUtc(),
      recurrenceOverrides: nextOverrides,
    );
  }

  Map<String, dynamic> toJson() {
    var data = _$RFC8984CalendarEventToJson(this);
    data["@type"] = type;
    return _deepJsonMap(data);
  }
}

@JsonSerializable(includeIfNull: false)
class RFC8984Location {
  static const String type = "Location";

  String? rel;
  String? name;
  String? title;
  String? timeZone;
  String? description;
  String? coordinates;

  RFC8984Location({
    this.rel,
    this.name,
    this.title,
    this.timeZone,
    this.description,
    this.coordinates,
  });

  factory RFC8984Location.fromJson(Map<String, dynamic> json) =>
      _$RFC8984LocationFromJson(json);

  Map<String, dynamic> toJson() {
    var data = _$RFC8984LocationToJson(this);
    data["@type"] = type;
    return _deepJsonMap(data);
  }
}

@JsonSerializable(includeIfNull: false)
class RFC8984VirtualLocation {
  static const String type = "VirtualLocation";

  String? rel;
  String? name;
  String? timeZone;
  String? uri;

  RFC8984VirtualLocation({this.rel, this.name, this.timeZone});

  factory RFC8984VirtualLocation.fromJson(Map<String, dynamic> json) =>
      _$RFC8984VirtualLocationFromJson(json);

  Map<String, dynamic> toJson() {
    var data = _$RFC8984VirtualLocationToJson(this);
    data["@type"] = type;
    return _deepJsonMap(data);
  }
}

@JsonSerializable(includeIfNull: false)
class Rfc8984NDay {
  static const String type = "NDay";
  String day;
  int? nthOfPeriod;

  Rfc8984NDay(this.day, {this.nthOfPeriod});

  factory Rfc8984NDay.fromJson(Map<String, dynamic> json) =>
      _$Rfc8984NDayFromJson(json);

  Map<String, dynamic> toJson() {
    var data = _$Rfc8984NDayToJson(this);
    data["@type"] = type;
    return _deepJsonMap(data);
  }
}

@JsonSerializable(
  includeIfNull: false,
)
class RFC8984RecurrenceRule {
  static const String type = "RecurrenceRule";

  String frequency;

  int? interval;

  String? rscale;

  String? skip;

  String? firstDayOfWeek;

  List<Rfc8984NDay>? byDay;
  List<int>? byMonthDay;
  List<String>? byMonth;
  List<int>? byYearDay;
  List<int>? byWeekNo;
  List<int>? byHour;
  List<int>? byMinute;
  List<int>? bySecond;
  List<int>? bySetPos;

  int? count;

  @IsoDateTimeConverter()
  DateTime? until;

  RFC8984RecurrenceRule({
    required this.frequency,
    this.until,
    this.interval,
    this.rscale,
    this.skip,
    this.firstDayOfWeek,
    this.byDay,
    this.byMonthDay,
    this.byMonth,
    this.byYearDay,
    this.byWeekNo,
    this.byHour,
    this.byMinute,
    this.bySecond,
    this.bySetPos,
    this.count,
  });

  factory RFC8984RecurrenceRule.fromJson(Map<String, dynamic> json) =>
      _$RFC8984RecurrenceRuleFromJson(json);

  Map<String, dynamic> toJson() {
    var data = _$RFC8984RecurrenceRuleToJson(this);
    data["@type"] = type;
    return _deepJsonMap(data);
  }

  @override
  String toString() {
    if (frequency == "monthly") {
      final repeatLabel =
          interval == 2 ? "Repeats Every Other Month" : "Repeats Monthly";
      if (byDay != null && byDay!.isNotEmpty) {
        final groupedDays = <int?, List<String>>{};
        for (final day in byDay!) {
          groupedDays.putIfAbsent(day.nthOfPeriod, () => <String>[]);
          if (!groupedDays[day.nthOfPeriod]!.contains(day.day)) {
            groupedDays[day.nthOfPeriod]!.add(day.day);
          }
        }

        final descriptions = <String>[];
        for (final ordinal in [
          ...monthlyOrdinalOptions.where(groupedDays.containsKey),
          ...groupedDays.keys
              .where((key) => !monthlyOrdinalOptions.contains(key))
        ]) {
          final weekdays = groupedDays[ordinal];
          if (weekdays == null || weekdays.isEmpty) {
            continue;
          }

          final labels = weekdays.map(recurrenceWeekdayLabel).join(", ");
          descriptions.add(
            ordinal == null
                ? labels
                : "${recurrenceOrdinalLabel(ordinal)} $labels",
          );
        }

        if (descriptions.isNotEmpty) {
          return "$repeatLabel on ${descriptions.join(', ')}";
        }
      }

      final monthDays = byMonthDay;
      if (monthDays != null && monthDays.isNotEmpty) {
        final label = monthDays.length == 1 ? "day" : "days";
        return "$repeatLabel on $label ${monthDays.join(', ')}";
      }

      if (interval == 2) {
        return "Repeats Every Other Month";
      }
      return "Repeats Monthly";
    }

    if (frequency == "daily") {
      if (interval == 2) {
        return "Repeats Every Other Day";
      }
      return "Repeats Daily";
    }

    if (frequency == "weekly") {
      final repeatLabel =
          interval == 2 ? "Repeats Every Other Week" : "Repeats Weekly";
      if (byDay == null) {
        return repeatLabel;
      }
      var days = [
        if (byDay!.any((i) => i.day == "mo") == true) "Mon",
        if (byDay!.any((i) => i.day == "tu") == true) "Tue",
        if (byDay!.any((i) => i.day == "we") == true) "Wed",
        if (byDay!.any((i) => i.day == "th") == true) "Thu",
        if (byDay!.any((i) => i.day == "fr") == true) "Fri",
        if (byDay!.any((i) => i.day == "sa") == true) "Sat",
        if (byDay!.any((i) => i.day == "su") == true) "Sun",
      ];
      var weekdays = days.join(", ");

      return "$repeatLabel on ${weekdays}";
    }

    if (frequency == "yearly") {
      return "Repeats Yearly";
    }

    return "Unknown Repeat Rule";
  }
}
