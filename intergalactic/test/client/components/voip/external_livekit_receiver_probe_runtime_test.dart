import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/external_livekit_receiver_probe_runtime_io.dart';

void main() {
  test(
    'external receiver probe widget cancel failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelExternalReceiverProbeWidgetSubscriptionForTesting(
          subscription,
        ),
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
    return Future<void>.error(
      StateError('external receiver probe widget cancel failed'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
