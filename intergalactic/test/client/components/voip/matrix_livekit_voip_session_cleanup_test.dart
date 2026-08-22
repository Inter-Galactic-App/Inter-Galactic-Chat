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
        bool? result;
        // A step that never completes, standing in for a homeserver
        // membership-clear or LiveKit disconnect against a dead network.
        final wedged = Completer<void>().future;

        debugRunBoundedHangUpStepForTesting(
          stepName: 'clear_call_state',
          step: wedged,
          timeout: const Duration(seconds: 5),
        ).then((value) => result = value);

        async.elapse(const Duration(seconds: 4));
        expect(result, isNull);

        async.elapse(const Duration(seconds: 2));
        expect(
          result,
          isFalse,
          reason: 'a wedged teardown step must not block hang-up past timeout',
        );
      });
    });

    test(
      'reports a failing step so native teardown can quarantine it',
      () async {
        await expectLater(
          debugRunBoundedHangUpStepForTesting(
            stepName: 'disconnect_livekit_room',
            step: Future<void>.error(StateError('disconnect failed')),
            timeout: const Duration(seconds: 5),
          ),
          completion(isFalse),
        );
      },
    );

    test('completes normally when the step succeeds in time', () {
      fakeAsync((async) {
        bool? result;

        debugRunBoundedHangUpStepForTesting(
          stepName: 'stop_heartbeat',
          step: Future<void>.delayed(const Duration(seconds: 1)),
          timeout: const Duration(seconds: 5),
        ).then((value) => result = value);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(result, isTrue);
      });
    });
  });

  group('releasing a replaced screen share', () {
    test('stops the outgoing session even when its publication '
        'teardown throws', () async {
      var stopped = false;

      await expectLater(
        debugReleaseReplacedScreenShareForTesting(
          releasePublication: () async {
            throw StateError('disposeSharedAudioPublicationStream failed');
          },
          stopSession: () async {
            stopped = true;
          },
        ),
        completes,
      );

      // `ShareSession.stop()` is what performs the native shared-audio stop and
      // disposal, and `_currentShareSession` already points at the incoming
      // share by this point. Skipping it leaves the outgoing Windows capture
      // running with nothing holding a handle to it.
      expect(
        stopped,
        isTrue,
        reason: 'the two releases must not share one try block',
      );
    });

    test('a failing session stop does not take down the caller', () async {
      var released = false;

      await expectLater(
        debugReleaseReplacedScreenShareForTesting(
          releasePublication: () async {
            released = true;
          },
          stopSession: () async {
            throw StateError('ShareSession.stop failed');
          },
        ),
        completes,
      );

      expect(released, isTrue);
    });
  });
}
