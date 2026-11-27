import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/sidebar_call_icon/sidebar_calls_list.dart';

void main() {
  test(
    'sidebar calls list subscription cancellation failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelSidebarCallsListSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    },
  );

  test('a null sidebar calls list subscription is a no-op', () async {
    await expectLater(
      debugCancelSidebarCallsListSubscriptionForTesting(null),
      completes,
    );
  });

  test('a synchronously throwing cancel is recovered too', () async {
    // The failing fake below returns a rejected future, which reaches the
    // `await`'s catch only. A `cancel()` that throws BEFORE returning enters
    // the try/catch at the call itself - a different site, and the one an
    // `onCancel` handler that throws immediately produces. Removing either half
    // of the guard should fail something.
    final subscription = _SyncThrowingCancelSubscription();

    await expectLater(
      debugCancelSidebarCallsListSubscriptionForTesting(subscription),
      completes,
    );

    expect(subscription.cancelAttempts, 1);
  });
}

/// Throws from `cancel()` itself rather than returning a rejected future, so
/// the failure arrives at the synchronous call site instead of the await.
class _SyncThrowingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    throw StateError('sidebar calls list cancel threw synchronously');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('sidebar calls list cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
