import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_session.dart';

void main() {
  group('direct Matrix session subscription cancellation', () {
    test('recovers stale subscription cancellation failures', () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelDirectCallSessionSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    });
  });

  group('direct Matrix stream disposal', () {
    test('runs healthy stream disposal', () async {
      var disposed = false;

      await debugDisposeDirectCallStreamForTesting(() async {
        disposed = true;
      });

      expect(disposed, isTrue);
    });

    test('recovers stale stream disposal failures', () async {
      var attempts = 0;

      await expectLater(
        debugDisposeDirectCallStreamForTesting(() async {
          attempts++;
          throw StateError('renderer already disposed');
        }),
        completes,
      );

      expect(attempts, 1);
    });
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  var cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('session subscription disposed'));
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future<E>.value(futureValue);

  @override
  bool get isPaused => false;

  @override
  void onData(void Function(void data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}
}
