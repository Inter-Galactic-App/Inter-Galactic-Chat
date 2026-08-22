import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';

void main() {
  group('LiveKit session subscription cancellation', () {
    test('recovers stale listener cancellation failures', () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelLiveKitSessionSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    });
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('probe listener cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
