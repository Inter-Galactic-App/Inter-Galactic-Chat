import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/main/stream_lab_call_join_retry.dart';

void main() {
  test('retries only while own device keys remain unknown', () {
    expect(
      shouldRetryStreamLabTrustPreflight(
        encryptionAvailable: true,
        currentDeviceKnown: false,
        currentDeviceBlocked: null,
      ),
      isTrue,
    );
    for (final state in [
      (encryptionAvailable: true, known: true, blocked: false),
      (encryptionAvailable: true, known: false, blocked: true),
      (encryptionAvailable: false, known: false, blocked: null),
    ]) {
      expect(
        shouldRetryStreamLabTrustPreflight(
          encryptionAvailable: state.encryptionAvailable,
          currentDeviceKnown: state.known,
          currentDeviceBlocked: state.blocked,
        ),
        isFalse,
      );
    }
  });
}
