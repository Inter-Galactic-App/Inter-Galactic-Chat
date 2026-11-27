import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/room_event_settings.dart';

void main() {
  group('RoomEventSettings', () {
    test('defaults to showing membership events and hiding profile updates',
        () {
      const settings = RoomEventSettings();

      expect(settings.showJoinEvents, isTrue);
      expect(settings.showLeaveEvents, isTrue);
      expect(settings.showInviteEvents, isTrue);
      expect(settings.showProfileAccountUpdates, isFalse);
    });

    test('serializes separate membership event toggles', () {
      const settings = RoomEventSettings(
        showJoinEvents: false,
        showLeaveEvents: false,
        showInviteEvents: false,
        showProfileAccountUpdates: true,
      );

      expect(settings.toStateContent(), {
        'show_join_events': false,
        'show_leave_events': false,
        'show_invite_events': false,
        'show_profile_account_updates': true,
      });
    });

    test('preserves legacy join setting for missing invite toggle', () {
      final settings = RoomEventSettings.fromStateContent({
        'show_join_events': false,
      });

      expect(settings.showJoinEvents, isFalse);
      expect(settings.showInviteEvents, isFalse);
      expect(settings.showLeaveEvents, isTrue);
    });

    test('uses explicit invite toggle over legacy join setting', () {
      final settings = RoomEventSettings.fromStateContent({
        'show_join_events': false,
        'show_invite_events': true,
      });

      expect(settings.showJoinEvents, isFalse);
      expect(settings.showInviteEvents, isTrue);
    });
  });
}
