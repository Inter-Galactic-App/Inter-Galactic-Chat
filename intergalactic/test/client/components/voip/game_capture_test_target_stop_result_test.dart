import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/game_capture_test_target_runner_io.dart';

void main() {
  group('gameCaptureTestTargetStopResult', () {
    test('reports an unconfirmed stop when the helper does not exit', () {
      final result = gameCaptureTestTargetStopResult(
        exitCode: -1,
        stopRequested: true,
      );

      expect(result.status, 'stop_unconfirmed');
      expect(result.reason, contains('may still be running'));
    });

    test('reports a confirmed stop after a successful stop request', () {
      final result = gameCaptureTestTargetStopResult(
        exitCode: 0,
        stopRequested: true,
      );

      expect(result.status, 'stopped');
      expect(result.reason, isNull);
    });

    test('reports normal completion without a stop request', () {
      final result = gameCaptureTestTargetStopResult(
        exitCode: 0,
        stopRequested: false,
      );

      expect(result.status, 'completed');
      expect(result.reason, isNull);
    });
  });
}
