import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';

/// CodeRabbit #8. Web session restore awaits vodozemac before any restored
/// client is created, and each attempt is bounded by the caller's own timeout.
/// A Dart timeout does not cancel the work it gave up on, so the retry could
/// start a second WASM download and bridge setup while the first was still
/// running. These pin the latch that stops it, and the readiness state that
/// direct encryption surfaces now read.
void main() {
  group('VodozemacSingleFlight', () {
    test('a retry after a timeout joins the attempt already running', () async {
      final latch = VodozemacSingleFlight();
      var initCalls = 0;
      final firstAttempt = Completer<void>();
      var initialized = false;

      Future<void> initialize() {
        initCalls++;
        return firstAttempt.future;
      }

      // Attempt one, abandoned by its own timeout the way `_checkSystem`
      // abandons it. The work keeps running.
      final abandoned = latch.run(
        isInitialized: () => initialized,
        initialize: initialize,
      );
      unawaited(abandoned.catchError((Object _) {}));
      await expectLater(
        abandoned.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );

      // Attempt two, while the first is still pending.
      final retry = latch.run(
        isInitialized: () => initialized,
        initialize: initialize,
      );

      expect(
        initCalls,
        1,
        reason:
            'a second WASM download and bridge setup against the same runtime '
            'is the race this exists to prevent',
      );

      initialized = true;
      firstAttempt.complete();
      await retry;
      expect(latch.hasAttemptInFlight, isFalse);
    });

    test('an attempt that failed can be retried', () async {
      final latch = VodozemacSingleFlight();
      var initCalls = 0;

      Future<void> failing() {
        initCalls++;
        return Future<void>.error(StateError('wasm load failed'));
      }

      await expectLater(
        latch.run(isInitialized: () => false, initialize: failing),
        throwsA(isA<StateError>()),
      );
      expect(latch.hasAttemptInFlight, isFalse);

      await expectLater(
        latch.run(isInitialized: () => false, initialize: failing),
        throwsA(isA<StateError>()),
      );
      expect(
        initCalls,
        2,
        reason:
            'the retry budget exists for attempts that really failed; a latch '
            'that outlived a failure would spend it on nothing',
      );
    });

    test(
      'an attempt abandoned by its caller cannot raise an unhandled error',
      () async {
        // The first caller times out and stops listening. If the attempt then
        // fails, nothing is awaiting it - the latch has to be the listener, or
        // a slow failing cold start reports an unhandled async error.
        //
        // TWO things make this counter able to fail, and it had neither.
        //
        // An unhandled future error is reported to the zone the FUTURE was
        // created in, so the latch and everything it builds internally has to
        // be created inside the guarded zone. Built outside it, the report
        // goes to the test's own zone and this counter stays at zero no
        // matter what the latch does.
        //
        // And the caller here owns no `catchError`. `timeout` is the only
        // listener a timed-out production caller leaves behind; a
        // caller-owned catchError absorbs exactly the failure the latch is
        // supposed to absorb, so with one attached the assertion holds even
        // after the latch stops handling the error itself.
        late VodozemacSingleFlight latch;
        Object? timedOutWith;
        var unhandled = 0;
        await runZonedGuarded(
          () async {
            latch = VodozemacSingleFlight();
            final attempt = Completer<void>();
            final abandoned = latch.run(
              isInitialized: () => false,
              initialize: () => attempt.future,
            );
            try {
              await abandoned.timeout(const Duration(milliseconds: 10));
            } catch (error) {
              timedOutWith = error;
            }

            attempt.completeError(
              StateError('failed after the caller gave up'),
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
          },
          (Object error, StackTrace stack) {
            unhandled++;
          },
        );

        expect(timedOutWith, isA<TimeoutException>());
        expect(unhandled, 0);
        expect(latch.hasAttemptInFlight, isFalse);
      },
    );

    test('an initialized runtime is not initialized again', () async {
      final latch = VodozemacSingleFlight();
      var initCalls = 0;

      await latch.run(
        isInitialized: () => true,
        initialize: () async => initCalls++,
      );

      expect(initCalls, 0);
      expect(latch.hasAttemptInFlight, isFalse);
    });
  });

  group('Retry Decrypt gating', () {
    // A direct encryption action. While vodozemac is still initializing it
    // cannot work, and after initialization has finally failed it can never
    // work; in both cases it used to be offered, do nothing, and say nothing.
    void expectDisabled(RoomQuickAccessMenuEntry entry) {
      expect(
        entry.action,
        isNull,
        reason: 'a null action is what makes the entry inoperable',
      );
      expect(entry.semanticLabel, isNotNull);
    }

    test('offered normally once encryption is ready', () {
      var retried = 0;
      final entry = retryDecryptMenuEntry(
        availability: EncryptionAvailability.ready,
        onRetry: (_) => retried++,
      );

      expect(entry.name, retryDecryptActionName);
      expect(entry.semanticLabel, isNull);
      expect(entry.disabledReason, isNull);

      // Not merely non-null: the entry has to carry the retry through, or the
      // gate would "pass" while quietly disabling the feature for everyone.
      entry.action!(_FakeBuildContext());
      expect(retried, 1);
    });

    test('inoperable and explained while encryption is pending', () {
      final entry = retryDecryptMenuEntry(
        availability: EncryptionAvailability.pending,
        onRetry: (_) => fail('must not be reachable while pending'),
      );

      expectDisabled(entry);
      expect(
        entry.name,
        retryDecryptActionName,
        reason:
            'name is identity: the side panel selects this entry by exact '
            'name, the widget key derives from it, and the tutorial anchor '
            'compares it. Renaming it to explain the state removes the '
            'button instead of disabling it',
      );
      expect(entry.disabledReason, contains('preparing'));
    });

    test('inoperable and explained once encryption is unavailable', () {
      final entry = retryDecryptMenuEntry(
        availability: EncryptionAvailability.unavailable,
        onRetry: (_) => fail('must not be reachable once unavailable'),
      );

      expectDisabled(entry);
      expect(entry.name, retryDecryptActionName);
      expect(entry.disabledReason, contains('unavailable'));
    });
  });
}

/// The entry's action takes a BuildContext it never touches here.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
