import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_local_playback_operation_queue.dart';

void main() {
  test('runs local playback writes in request order', () async {
    final queue = CallLocalPlaybackOperationQueue();
    final firstStarted = Completer<void>();
    final allowFirstToFinish = Completer<void>();
    final order = <String>[];

    final first = queue.run(() async {
      order.add('first-started');
      firstStarted.complete();
      await allowFirstToFinish.future;
      order.add('first-finished');
    });
    await firstStarted.future;

    final second = queue.run(() async {
      order.add('second');
    });

    expect(order, ['first-started']);
    allowFirstToFinish.complete();
    await Future.wait([first, second]);

    expect(order, ['first-started', 'first-finished', 'second']);
  });

  test('evaluates a default write after a queued override clear', () async {
    final queue = CallLocalPlaybackOperationQueue();
    var hasManualOverride = true;
    var defaultApplied = false;

    final clear = queue.run(() async {
      hasManualOverride = false;
    });
    final defaultWrite = queue.run(() async {
      if (!hasManualOverride) {
        defaultApplied = true;
      }
    });

    await Future.wait([clear, defaultWrite]);

    expect(defaultApplied, isTrue);
  });
  test('continues after a failed local playback write', () async {
    final queue = CallLocalPlaybackOperationQueue();

    await expectLater(
      queue.run<void>(() async => throw StateError('track detached')),
      throwsStateError,
    );

    var completed = false;
    await queue.run(() async {
      completed = true;
    });

    expect(completed, isTrue);
  });
}
