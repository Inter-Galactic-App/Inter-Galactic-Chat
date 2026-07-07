import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/service/background_service_notifications/background_matrix_wake_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackgroundMatrixWakeLimiter', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BackgroundMatrixWakeLimiter.resetForTests();
    });

    test('allows one wake sync per interval for a client', () async {
      const clientId = '@power-user:example.org';
      const interval = Duration(seconds: 12);
      final startedAt = DateTime(2026, 5, 7, 9, 40);

      expect(
        await BackgroundMatrixWakeLimiter.claim(
          clientId,
          minInterval: interval,
          now: startedAt,
        ),
        isTrue,
      );
      expect(
        await BackgroundMatrixWakeLimiter.claim(
          clientId,
          minInterval: interval,
          now: startedAt.add(const Duration(seconds: 6)),
        ),
        isFalse,
      );
      expect(
        await BackgroundMatrixWakeLimiter.claim(
          clientId,
          minInterval: interval,
          now: startedAt.add(const Duration(seconds: 13)),
        ),
        isTrue,
      );
    });

    test('uses the persisted timestamp after a fresh isolate starts', () async {
      const clientId = '@restored:example.org';
      const interval = Duration(seconds: 12);
      final startedAt = DateTime(2026, 5, 7, 9, 41);
      SharedPreferences.setMockInitialValues({
        BackgroundMatrixWakeLimiter.keyForClient(clientId):
            startedAt.millisecondsSinceEpoch,
      });
      BackgroundMatrixWakeLimiter.resetForTests();

      expect(
        await BackgroundMatrixWakeLimiter.claim(
          clientId,
          minInterval: interval,
          now: startedAt.add(const Duration(seconds: 8)),
        ),
        isFalse,
      );
      expect(
        await BackgroundMatrixWakeLimiter.claim(
          clientId,
          minInterval: interval,
          now: startedAt.add(const Duration(seconds: 13)),
        ),
        isTrue,
      );
    });
  });
}
