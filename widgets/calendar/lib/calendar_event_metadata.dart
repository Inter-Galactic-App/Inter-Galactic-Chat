class CalendarReminderOption {
  final int minutesBefore;
  final String label;

  const CalendarReminderOption(this.minutesBefore, this.label);
}

const List<CalendarReminderOption> calendarReminderOptions = [
  CalendarReminderOption(0, "At time of event"),
  CalendarReminderOption(5, "5 minutes before"),
  CalendarReminderOption(10, "10 minutes before"),
  CalendarReminderOption(15, "15 minutes before"),
  CalendarReminderOption(30, "30 minutes before"),
  CalendarReminderOption(60, "1 hour before"),
  CalendarReminderOption(120, "2 hours before"),
  CalendarReminderOption(1440, "1 day before"),
  CalendarReminderOption(2880, "2 days before"),
  CalendarReminderOption(10080, "1 week before"),
];

List<int> normalizeReminderOffsets(Iterable<int> offsets) {
  final result = offsets.toSet().toList()..sort();
  return result;
}

String describeReminderOffset(int minutesBefore) {
  for (final option in calendarReminderOptions) {
    if (option.minutesBefore == minutesBefore) {
      return option.label;
    }
  }

  if (minutesBefore == 0) {
    return "At time of event";
  }

  if (minutesBefore % 10080 == 0) {
    final weeks = minutesBefore ~/ 10080;
    return weeks == 1 ? "1 week before" : "$weeks weeks before";
  }

  if (minutesBefore % 1440 == 0) {
    final days = minutesBefore ~/ 1440;
    return days == 1 ? "1 day before" : "$days days before";
  }

  if (minutesBefore % 60 == 0) {
    final hours = minutesBefore ~/ 60;
    return hours == 1 ? "1 hour before" : "$hours hours before";
  }

  return minutesBefore == 1
      ? "1 minute before"
      : "$minutesBefore minutes before";
}

String summarizeReminderOffsets(List<int> offsets) {
  final normalized = normalizeReminderOffsets(offsets);
  if (normalized.isEmpty) {
    return "No reminders";
  }

  return normalized.map(describeReminderOffset).join(", ");
}

class CalendarAttendanceState {
  final String userId;
  final bool attending;
  final bool useDefaultReminders;
  final List<int> reminderOffsetsMinutes;
  final DateTime? updated;

  const CalendarAttendanceState({
    required this.userId,
    required this.attending,
    required this.useDefaultReminders,
    required this.reminderOffsetsMinutes,
    this.updated,
  });

  CalendarAttendanceState copyWith({
    String? userId,
    bool? attending,
    bool? useDefaultReminders,
    List<int>? reminderOffsetsMinutes,
    DateTime? updated,
  }) {
    return CalendarAttendanceState(
      userId: userId ?? this.userId,
      attending: attending ?? this.attending,
      useDefaultReminders: useDefaultReminders ?? this.useDefaultReminders,
      reminderOffsetsMinutes:
          reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
      updated: updated ?? this.updated,
    );
  }
}

class CalendarReminderSchedule {
  final String eventUid;
  final String title;
  final String userId;
  final DateTime eventStart;
  final DateTime remindAt;
  final int minutesBefore;

  const CalendarReminderSchedule({
    required this.eventUid,
    required this.title,
    required this.userId,
    required this.eventStart,
    required this.remindAt,
    required this.minutesBefore,
  });
}
