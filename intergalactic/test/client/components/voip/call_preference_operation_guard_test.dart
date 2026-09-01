import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_preference_operation_guard.dart';

void main() {
  test('runs healthy preference operations', () async {
    var operationCount = 0;

    await CallPreferenceOperationGuard.run(
      operation: () {
        operationCount++;
      },
      content: 'test preference operation',
      source: 'call-preference-test',
    );

    expect(operationCount, 1);
  });

  test('recovers sync preference operation failures', () async {
    var operationCount = 0;

    await expectLater(
      CallPreferenceOperationGuard.run(
        operation: () {
          operationCount++;
          throw StateError('preference write failed');
        },
        content: 'test preference sync failure',
        source: 'call-preference-test',
      ),
      completes,
    );

    expect(operationCount, 1);
  });

  test('recovers async preference operation failures', () async {
    var operationCount = 0;

    await expectLater(
      CallPreferenceOperationGuard.run(
        operation: () async {
          operationCount++;
          throw StateError('preference write failed');
        },
        content: 'test preference async failure',
        source: 'call-preference-test',
      ),
      completes,
    );

    expect(operationCount, 1);
  });
}
