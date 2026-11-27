import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_room_event.dart';

void main() {
  group('encodeActivityRoomStateContent', () {
    test('round-trips a rich music activity through decode', () {
      const activity = UserActivity(
        id: 'spotify:track',
        kind: ActivityKind.music,
        provider: 'spotify',
        title: 'Starman',
        subtitle: 'David Bowie',
        artworkUrl: 'https://cdn.example/art.jpg',
        visibility: ActivityVisibility.friendsOrSharedRooms,
      );

      final content = encodeActivityRoomStateContent(activity);
      expect(content['v'], activityRoomStateSchemaVersion);

      final decoded = decodeActivityRoomStateContent(content);
      expect(decoded, isNotNull);
      expect(decoded!.id, 'spotify:track');
      expect(decoded.kind, ActivityKind.music);
      expect(decoded.provider, 'spotify');
      expect(decoded.title, 'Starman');
      expect(decoded.subtitle, 'David Bowie');
      expect(decoded.artworkUrl, 'https://cdn.example/art.jpg');
      expect(decoded.visibility, ActivityVisibility.friendsOrSharedRooms);
    });

    test('returns empty content for a null activity (clears the event)', () {
      expect(encodeActivityRoomStateContent(null), isEmpty);
    });

    test('returns empty content for a hidden activity', () {
      const hidden = UserActivity(
        id: 'g',
        kind: ActivityKind.game,
        title: 'Halo',
        visibility: ActivityVisibility.off,
      );
      expect(encodeActivityRoomStateContent(hidden), isEmpty);
    });
  });

  group('decodeActivityRoomStateContent', () {
    test('treats null and empty content as no activity', () {
      expect(decodeActivityRoomStateContent(null), isNull);
      expect(decodeActivityRoomStateContent(const {}), isNull);
    });

    test('rejects content missing the schema version', () {
      expect(
        decodeActivityRoomStateContent({
          'activity': {'id': 'g', 'kind': 'game', 'title': 'Halo'},
        }),
        isNull,
      );
    });

    test('rejects content from an unknown schema version', () {
      expect(
        decodeActivityRoomStateContent({
          'v': activityRoomStateSchemaVersion + 999,
          'activity': {'id': 'g', 'kind': 'game', 'title': 'Halo'},
        }),
        isNull,
      );
    });

    test('rejects content whose activity is not a map', () {
      expect(
        decodeActivityRoomStateContent({
          'v': activityRoomStateSchemaVersion,
          'activity': 'not-a-map',
        }),
        isNull,
      );
    });

    test('rejects a decoded activity that is hidden', () {
      expect(
        decodeActivityRoomStateContent({
          'v': activityRoomStateSchemaVersion,
          'activity': {
            'id': 'g',
            'kind': 'game',
            'title': 'Halo',
            'visibility': 'off',
          },
        }),
        isNull,
      );
    });

    test('rejects an empty activity with no id and no title', () {
      expect(
        decodeActivityRoomStateContent({
          'v': activityRoomStateSchemaVersion,
          'activity': {'id': '', 'title': '', 'kind': 'game'},
        }),
        isNull,
      );
    });
  });
}
