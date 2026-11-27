import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline.dart';

void main() {
  test(
    'failed owned timeline initialization closes the partial timeline',
    () async {
      final timeline = _RecordingTimeline();

      await expectLater(
        RoomTimelineLease.initializeOwned(timeline, () async {
          throw StateError('context initialization failed');
        }),
        throwsStateError,
      );

      expect(timeline.closeCount, 1);
    },
  );

  test(
    'successful owned timeline initialization transfers cleanup to caller',
    () async {
      final timeline = _RecordingTimeline();

      final lease = await RoomTimelineLease.initializeOwned(
        timeline,
        () async {},
      );

      expect(lease.timeline, same(timeline));
      expect(timeline.closeCount, 0);
      await lease.close();
      expect(timeline.closeCount, 1);
    },
  );
}

class _RecordingTimeline implements Timeline {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
