import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/desktop_call_popout_host.dart';

void main() {
  test(
    'popout host subscription cancellation failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelDesktopCallPopoutSubscriptionForTesting(subscription),
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
    return Future<void>.error(StateError('popout host cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
