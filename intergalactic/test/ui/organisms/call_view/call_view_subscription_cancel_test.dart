import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  test('call view subscription cancellation failures are recovered', () async {
    final subscription = _FailingCancelSubscription();

    await expectLater(
      debugCancelCallViewSubscriptionForTesting(subscription),
      completes,
    );

    expect(subscription.cancelAttempts, 1);
  });

  test(
    'call view receiver probe subscription cancellation failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelCallViewReceiverProbeSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    },
  );
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('call view cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
