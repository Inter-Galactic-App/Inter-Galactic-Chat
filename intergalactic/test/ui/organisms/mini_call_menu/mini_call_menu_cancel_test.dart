import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/mini_call_menu/mini_call_menu.dart';

void main() {
  test(
    'mini call menu subscription cancellation failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelMiniCallMenuSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    },
  );

  test('a synchronously throwing cancel is recovered too', () async {
    // The failing fake above returns a rejected future, which only ever
    // reaches the `await`'s catch. A `cancel()` that throws BEFORE returning
    // enters the try/catch at the call itself - a different site, and the one
    // an `onCancel` handler that throws immediately produces. Removing either
    // half of the guard should fail something.
    final subscription = _SyncThrowingCancelSubscription();

    await expectLater(
      debugCancelMiniCallMenuSubscriptionForTesting(subscription),
      completes,
    );

    expect(subscription.cancelAttempts, 1);
  });

  test('a null mini call menu subscription is a no-op', () async {
    await expectLater(
      debugCancelMiniCallMenuSubscriptionForTesting(null),
      completes,
    );
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('mini call menu cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Throws from `cancel()` itself rather than returning a rejected future, so
/// the failure arrives at the synchronous call site instead of the await.
class _SyncThrowingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    throw StateError('mini call menu cancel threw synchronously');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
