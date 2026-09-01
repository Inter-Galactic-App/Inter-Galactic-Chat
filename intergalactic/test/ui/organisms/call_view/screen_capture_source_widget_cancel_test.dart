import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/screen_capture_source_widget.dart';

void main() {
  test('thumbnail subscription cancellation failures are recovered', () async {
    final subscription = _FailingCancelSubscription();

    await expectLater(
      debugCancelScreenCaptureSourceSubscriptionForTesting(subscription),
      completes,
    );

    expect(subscription.cancelAttempts, 1);
  });

  test('thumbnail refresh failures are recovered', () async {
    var refreshAttempts = 0;

    await expectLater(
      debugRunScreenCaptureSourceRefreshForTesting(() async {
        refreshAttempts++;
        throw StateError('thumbnail refresh failed');
      }),
      completes,
    );

    expect(refreshAttempts, 1);
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('thumbnail cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
