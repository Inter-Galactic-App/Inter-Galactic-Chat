import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/encryption_readiness_waiter.dart';

void main() {
  group('EncryptionReadinessWaiter', () {
    test('fires onReady synchronously when already ready', () {
      var ready = 0;
      var timedOut = 0;

      EncryptionReadinessWaiter(
        isReady: () => true,
        onReady: () => ready++,
        onTimeout: () => timedOut++,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 40),
      ).start();

      expect(ready, 1);
      expect(timedOut, 0);
    });

    test('fires onReady once it becomes ready before the timeout', () async {
      var ready = 0;
      var timedOut = 0;
      var checks = 0;

      EncryptionReadinessWaiter(
        isReady: () => ++checks >= 3,
        onReady: () => ready++,
        onTimeout: () => timedOut++,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(seconds: 5),
      ).start();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(ready, 1);
      expect(timedOut, 0);
    });

    test('fires onTimeout when it never becomes ready', () async {
      var ready = 0;
      var timedOut = 0;

      EncryptionReadinessWaiter(
        isReady: () => false,
        onReady: () => ready++,
        onTimeout: () => timedOut++,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 30),
      ).start();

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(ready, 0);
      expect(timedOut, 1);
    });

    test('cancel prevents any callback from firing', () async {
      var ready = 0;
      var timedOut = 0;

      final waiter = EncryptionReadinessWaiter(
        isReady: () => false,
        onReady: () => ready++,
        onTimeout: () => timedOut++,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 30),
      )..start();

      waiter.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(ready, 0);
      expect(timedOut, 0);
      expect(waiter.isFinished, isTrue);
    });

    test('reports its outcome exactly once', () async {
      var total = 0;
      var checks = 0;

      EncryptionReadinessWaiter(
        // false on the initial synchronous check, true from the first tick on.
        isReady: () => checks++ > 0,
        onReady: () => total++,
        onTimeout: () => total++,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 50),
      ).start();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(total, 1);
    });
  });
}
