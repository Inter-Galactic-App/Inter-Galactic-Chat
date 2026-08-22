import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('room notification snooze preferences', () {
    late Preferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = Preferences();
      await preferences.init();
    });

    test('stores active snoozes by client and room', () async {
      final now = DateTime(2026, 6, 3, 10);

      await preferences.setRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        duration: const Duration(hours: 1),
        now: now,
      );

      final active = preferences.getRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        now: now.add(const Duration(minutes: 59)),
      );

      expect(active, isNotNull);
      expect(active!.snoozedUntil, now.add(const Duration(hours: 1)));
      expect(
        preferences.isRoomNotificationSnoozed(
          clientId: '@alice:example.org',
          roomId: '!room:example.org',
          now: now.add(const Duration(minutes: 59)),
        ),
        isTrue,
      );
    });

    test('keeps snoozes isolated across rooms and clients', () async {
      final now = DateTime(2026, 6, 3, 10);

      await preferences.setRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room-a:example.org',
        duration: const Duration(hours: 1),
        now: now,
      );

      expect(
        preferences.getRoomNotificationSnooze(
          clientId: '@alice:example.org',
          roomId: '!room-b:example.org',
          now: now,
        ),
        isNull,
      );
      expect(
        preferences.getRoomNotificationSnooze(
          clientId: '@bob:example.org',
          roomId: '!room-a:example.org',
          now: now,
        ),
        isNull,
      );
    });

    test('hides and prunes expired snoozes', () async {
      final now = DateTime(2026, 6, 3, 10);

      await preferences.setRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        duration: const Duration(minutes: 30),
        now: now,
      );

      final afterExpiry = now.add(const Duration(minutes: 31));

      expect(
        preferences.getRoomNotificationSnooze(
          clientId: '@alice:example.org',
          roomId: '!room:example.org',
          now: afterExpiry,
        ),
        isNull,
      );

      expect(
        preferences.getRoomNotificationSnoozes(
          now: afterExpiry,
          includeExpired: true,
        ),
        hasLength(1),
      );

      await preferences.pruneExpiredRoomNotificationSnoozes(now: afterExpiry);

      expect(
        preferences.getRoomNotificationSnoozes(
          now: afterExpiry,
          includeExpired: true,
        ),
        isEmpty,
      );
    });

    test('maps notification action ids to duration options', () {
      expect(
        RoomNotificationSnoozeDurationOption.fromNotificationActionId(
          'room_snooze_60',
        ),
        RoomNotificationSnoozeDurationOption.oneHour,
      );
      expect(
        RoomNotificationSnoozeDurationOption.fromNotificationActionId(
          'room_snooze_unknown',
        ),
        isNull,
      );
    });

    test('formats exact remaining durations without over-rounding', () {
      final now = DateTime(2026, 6, 3, 10);
      final snooze = RoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        snoozedUntil: now.add(const Duration(hours: 1)),
        createdAt: now,
        source: 'test',
      );

      expect(
        formatRoomNotificationSnoozeRemaining(snooze, now: now),
        '1h left',
      );
    });

    test(
      'round trips account-scoped snooze data without local identifiers',
      () {
        final now = DateTime.utc(2026, 8, 21, 18);
        final original = RoomNotificationSnooze(
          clientId: '@alice:example.org',
          roomId: '!room:example.org',
          snoozedUntil: now.add(const Duration(hours: 8)),
          createdAt: now,
          source: 'notification_action',
        );

        final synced = original.toSyncedJson();

        // The round trip alone cannot catch a leak: fromSyncedJson is HANDED
        // clientId and roomId, so it would restore them even if toSyncedJson
        // had written them into the payload. This record is per-room account
        // data on the user's own account, so the identifiers are implied by
        // where it is stored and must not be duplicated into the body.
        expect(synced.keys, isNot(contains('client_id')));
        expect(synced.keys, isNot(contains('room_id')));
        expect(
          synced.values.whereType<String>(),
          isNot(contains(anyOf('@alice:example.org', '!room:example.org'))),
        );

        final restored = RoomNotificationSnooze.fromSyncedJson(
          synced,
          clientId: '@alice:example.org',
          roomId: '!room:example.org',
        );

        expect(restored, isNotNull);
        expect(restored!.clientId, original.clientId);
        expect(restored.roomId, original.roomId);
        expect(restored.snoozedUntil.toUtc(), original.snoozedUntil.toUtc());
        expect(restored.source, original.source);
      },
    );
  });
}
