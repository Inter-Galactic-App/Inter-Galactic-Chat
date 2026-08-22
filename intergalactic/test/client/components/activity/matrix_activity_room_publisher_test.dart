import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_room_component.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/publishers/matrix_activity_room_publisher.dart';

class _FakeActivityRoomComponent implements ActivityRoomComponent {
  final List<UserActivity?> published = [];

  @override
  Future<void> publishSelfActivity(UserActivity? activity) async {
    published.add(activity);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _game = UserActivity(
  id: 'steam:halo',
  kind: ActivityKind.game,
  title: 'Halo',
  artworkUrl: 'https://cdn.example/halo.jpg',
);

void main() {
  group('MatrixActivityRoomPublisher', () {
    test('publishes the rich activity into each active call room', () async {
      final target = _FakeActivityRoomComponent();
      final publisher = MatrixActivityRoomPublisher(
        targetProvider: () => [target],
      );

      await publisher.publish(
        _game,
        const ActivitySettings(
          publishRichActivity: true,
          showGameActivity: true,
        ),
      );

      expect(target.published, [_game]);
    });

    test('clears the room when rich publishing is disabled', () async {
      final target = _FakeActivityRoomComponent();
      final publisher = MatrixActivityRoomPublisher(
        targetProvider: () => [target],
      );

      await publisher.publish(
        _game,
        const ActivitySettings(
          publishRichActivity: false,
          showGameActivity: true,
        ),
      );

      expect(target.published, [null]);
    });

    test('clears the game activity when the game toggle is off', () async {
      final target = _FakeActivityRoomComponent();
      final publisher = MatrixActivityRoomPublisher(
        targetProvider: () => [target],
      );

      await publisher.publish(
        _game,
        // Rich publishing on, but the game category is muted.
        const ActivitySettings(
          publishRichActivity: true,
          showGameActivity: false,
        ),
      );

      expect(target.published, [null]);
    });

    test(
      'clears a room it previously owned once it is no longer active',
      () async {
        final target = _FakeActivityRoomComponent();
        var targets = <ActivityRoomComponent>[target];
        final publisher = MatrixActivityRoomPublisher(
          targetProvider: () => targets,
        );

        const settings = ActivitySettings(
          publishRichActivity: true,
          showGameActivity: true,
        );

        // First publish: the room becomes owned with the activity.
        await publisher.publish(_game, settings);
        // The call ends: the room drops out of the active set.
        targets = <ActivityRoomComponent>[];
        await publisher.publish(_game, settings);

        expect(target.published, [_game, null]);
      },
    );
  });
}
