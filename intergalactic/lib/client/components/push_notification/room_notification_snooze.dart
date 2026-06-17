class RoomNotificationSnoozeDurationOption {
  const RoomNotificationSnoozeDurationOption({
    required this.id,
    required this.label,
    required this.compactLabel,
    required this.actionLabel,
    required this.duration,
  });

  final String id;
  final String label;
  final String compactLabel;
  final String actionLabel;
  final Duration duration;

  int get minutes => duration.inMinutes;

  String get notificationActionId => 'room_snooze_$minutes';

  static const thirtyMinutes = RoomNotificationSnoozeDurationOption(
    id: '30m',
    label: '30 minutes',
    compactLabel: '30 min',
    actionLabel: 'Snooze 30m',
    duration: Duration(minutes: 30),
  );

  static const oneHour = RoomNotificationSnoozeDurationOption(
    id: '1h',
    label: '1 hour',
    compactLabel: '1 hr',
    actionLabel: 'Snooze 1h',
    duration: Duration(hours: 1),
  );

  static const eightHours = RoomNotificationSnoozeDurationOption(
    id: '8h',
    label: '8 hours',
    compactLabel: '8 hrs',
    actionLabel: 'Snooze 8h',
    duration: Duration(hours: 8),
  );

  static const twentyFourHours = RoomNotificationSnoozeDurationOption(
    id: '24h',
    label: '24 hours',
    compactLabel: '24 hrs',
    actionLabel: 'Snooze 24h',
    duration: Duration(hours: 24),
  );

  static const values = <RoomNotificationSnoozeDurationOption>[
    thirtyMinutes,
    oneHour,
    eightHours,
    twentyFourHours,
  ];

  static RoomNotificationSnoozeDurationOption? fromMinutes(int minutes) {
    for (final option in values) {
      if (option.minutes == minutes) {
        return option;
      }
    }

    return null;
  }

  static RoomNotificationSnoozeDurationOption? fromNotificationActionId(
    String? actionId,
  ) {
    if (actionId == null || actionId.isEmpty) {
      return null;
    }

    for (final option in values) {
      if (option.notificationActionId == actionId) {
        return option;
      }
    }

    return null;
  }
}

class RoomNotificationSnooze {
  const RoomNotificationSnooze({
    required this.clientId,
    required this.roomId,
    required this.snoozedUntil,
    required this.createdAt,
    required this.source,
  });

  final String clientId;
  final String roomId;
  final DateTime snoozedUntil;
  final DateTime createdAt;
  final String source;

  bool isActive(DateTime now) => snoozedUntil.isAfter(now);

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'room_id': roomId,
        'snoozed_until_ms': snoozedUntil.toUtc().millisecondsSinceEpoch,
        'created_at_ms': createdAt.toUtc().millisecondsSinceEpoch,
        'source': source,
      };

  static RoomNotificationSnooze? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }

    final clientId = value['client_id'];
    final roomId = value['room_id'];
    final snoozedUntilMs = value['snoozed_until_ms'];
    if (clientId is! String ||
        clientId.isEmpty ||
        roomId is! String ||
        roomId.isEmpty ||
        snoozedUntilMs is! num) {
      return null;
    }

    final createdAtMs = value['created_at_ms'];
    return RoomNotificationSnooze(
      clientId: clientId,
      roomId: roomId,
      snoozedUntil: DateTime.fromMillisecondsSinceEpoch(
        snoozedUntilMs.toInt(),
        isUtc: true,
      ).toLocal(),
      createdAt: createdAtMs is num
          ? DateTime.fromMillisecondsSinceEpoch(
              createdAtMs.toInt(),
              isUtc: true,
            ).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(
              snoozedUntilMs.toInt(),
              isUtc: true,
            ).toLocal(),
      source: value['source']?.toString() ?? 'unknown',
    );
  }
}

String roomNotificationSnoozeKey({
  required String clientId,
  required String roomId,
}) {
  return '$clientId::$roomId';
}

String formatRoomNotificationSnoozeRemaining(
  RoomNotificationSnooze snooze, {
  DateTime? now,
}) {
  final remaining = snooze.snoozedUntil.difference(now ?? DateTime.now());
  if (!remaining.isNegative && remaining.inMinutes < 1) {
    return 'less than 1m left';
  }

  if (remaining.isNegative) {
    return 'expired';
  }

  final seconds = remaining.inSeconds;

  if (seconds < 60 * 60) {
    return '${_ceilDurationUnit(seconds, 60)}m left';
  }

  if (seconds < 24 * 60 * 60) {
    return '${_ceilDurationUnit(seconds, 60 * 60)}h left';
  }

  return '${_ceilDurationUnit(seconds, 24 * 60 * 60)}d left';
}

int _ceilDurationUnit(int value, int unit) {
  return (value + unit - 1) ~/ unit;
}
