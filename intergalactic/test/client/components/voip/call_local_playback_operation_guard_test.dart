import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_local_playback_operation_guard.dart';

void main() {
  test('runs healthy async local playback operations', () async {
    var operationCount = 0;

    await CallLocalPlaybackOperationGuard.runAsync(
      operation: () async {
        operationCount++;
      },
      content: 'test async playback operation',
      source: 'call-local-playback-test',
    );

    expect(operationCount, 1);
  });

  test('recovers async local playback operation failures', () async {
    var operationCount = 0;

    await expectLater(
      CallLocalPlaybackOperationGuard.runAsync(
        operation: () async {
          operationCount++;
          throw StateError('stream disposed');
        },
        content: 'test async playback failure',
        source: 'call-local-playback-test',
      ),
      completes,
    );

    expect(operationCount, 1);
  });

  test('recovers sync local playback operation failures', () {
    var operationCount = 0;

    expect(
      () => CallLocalPlaybackOperationGuard.runSync(
        operation: () {
          operationCount++;
          throw StateError('override disposed');
        },
        content: 'test sync playback failure',
        source: 'call-local-playback-test',
      ),
      returnsNormally,
    );

    expect(operationCount, 1);
  });
}
