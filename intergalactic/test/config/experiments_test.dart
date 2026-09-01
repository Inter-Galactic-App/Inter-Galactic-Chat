import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/experiments.dart';

void main() {
  group('Experiments', () {
    test('does not gate biometric recovery-key storage', () {
      final experimentIds = Experiments.available.map(
        (experiment) => experiment.id,
      );

      expect(experimentIds, isNot(contains('biometric_recovery_key_unlock')));
    });
  });
}
