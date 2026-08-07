import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';

void main() {
  test('LiveKit session cleanup failures are recovered', () async {
    var attempts = 0;

    final recovered = await debugRunMatrixLivekitVoipSessionCleanupForTesting(
      operation: 'test-cleanup',
      cleanup: () {
        attempts++;
        throw StateError('LiveKit session cleanup failed');
      },
    );

    expect(recovered, isFalse);
    expect(attempts, 1);
  });

  test('LiveKit session cleanup continues after recovered failure', () async {
    final attempts = <String>[];

    final firstRecovered =
        await debugRunMatrixLivekitVoipSessionCleanupForTesting(
          operation: 'listener-dispose',
          cleanup: () {
            attempts.add('listener');
            throw StateError('listener dispose failed');
          },
        );
    final secondRecovered =
        await debugRunMatrixLivekitVoipSessionCleanupForTesting(
          operation: 'room-dispose',
          cleanup: () {
            attempts.add('room');
          },
        );

    expect(firstRecovered, isFalse);
    expect(secondRecovered, isTrue);
    expect(attempts, ['listener', 'room']);
  });

  test('LiveKit session cleanup ignores absent cleanup target', () async {
    final recovered = await debugRunMatrixLivekitVoipSessionCleanupForTesting(
      operation: 'missing-cleanup',
      cleanup: null,
    );

    expect(recovered, isTrue);
  });

  test(
    'LiveKit session publication operation failures are recovered',
    () async {
      var attempts = 0;

      final recovered =
          await debugRunMatrixLivekitVoipSessionPublicationOperationForTesting(
            operation: 'test-publication',
            publicationOperation: () {
              attempts++;
              throw StateError('LiveKit publication failed');
            },
          );

      expect(recovered, isFalse);
      expect(attempts, 1);
    },
  );

  test('LiveKit session publication operation ignores absent target', () async {
    final recovered =
        await debugRunMatrixLivekitVoipSessionPublicationOperationForTesting(
          operation: 'missing-publication',
          publicationOperation: null,
        );

    expect(recovered, isTrue);
  });

  group('bounded hang-up teardown step', () {
    test('returns after the timeout when a step wedges', () {
      fakeAsync((async) {
        var completed = false;
        // A step that never completes, standing in for a homeserver
        // membership-clear or LiveKit disconnect against a dead network.
        final wedged = Completer<void>().future;

        debugRunBoundedHangUpStepForTesting(
          stepName: 'clear_call_state',
          step: wedged,
          timeout: const Duration(seconds: 5),
        ).then((_) => completed = true);

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(
          completed,
          isTrue,
          reason: 'a wedged teardown step must not block hang-up past timeout',
        );
      });
    });

    test('swallows a failing step so hang-up can continue', () async {
      await expectLater(
        debugRunBoundedHangUpStepForTesting(
          stepName: 'disconnect_livekit_room',
          step: Future<void>.error(StateError('disconnect failed')),
          timeout: const Duration(seconds: 5),
        ),
        completes,
      );
    });

    test('completes normally when the step succeeds in time', () {
      fakeAsync((async) {
        var completed = false;

        debugRunBoundedHangUpStepForTesting(
          stepName: 'stop_heartbeat',
          step: Future<void>.delayed(const Duration(seconds: 1)),
          timeout: const Duration(seconds: 5),
        ).then((_) => completed = true);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(completed, isTrue);
      });
    });
  });
}
