import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';

void main() {
  group('MatrixE2eeBackupProbeScope', () {
    test('bounds probes to two candidates and aggregates outcomes', () async {
      final scope = MatrixE2eeBackupProbeScope(
        enabled: true,
        budget: const Duration(seconds: 5),
      );
      var probeCount = 0;

      await scope.record((_) async {
        probeCount++;
        return MatrixE2eeBackupProbeOutcome.inBackup;
      });
      await scope.record((_) async {
        probeCount++;
        return MatrixE2eeBackupProbeOutcome.notInBackup;
      });
      await scope.record((_) async {
        probeCount++;
        return MatrixE2eeBackupProbeOutcome.inBackup;
      });

      final summary = await scope.finish();
      expect(probeCount, 2);
      expect(summary.candidates, 3);
      expect(summary.inBackup, 1);
      expect(summary.notInBackup, 1);
      expect(summary.versionUnusable, 0);
      expect(summary.skippedBudget, 1);
    });

    test(
      'skips a candidate when less than one probe timeout remains',
      () async {
        var now = DateTime.utc(2026, 9, 12, 13);
        final scope = MatrixE2eeBackupProbeScope(
          enabled: true,
          budget: const Duration(milliseconds: 749),
          now: () => now,
        );

        var probeCount = 0;
        await scope.record((_) async {
          probeCount++;
          return MatrixE2eeBackupProbeOutcome.inBackup;
        });

        now = now.add(const Duration(milliseconds: 749));
        final summary = await scope.finish();
        expect(probeCount, 0);
        expect(summary.candidates, 1);
        expect(summary.skippedBudget, 1);
      },
    );

    test('does nothing outside developer mode', () async {
      final scope = MatrixE2eeBackupProbeScope(
        enabled: false,
        budget: const Duration(seconds: 5),
      );
      var probeCount = 0;

      await scope.record((_) async {
        probeCount++;
        return MatrixE2eeBackupProbeOutcome.inBackup;
      });

      final summary = await scope.finish();
      expect(probeCount, 0);
      expect(summary.candidates, 0);
      expect(summary.inBackup, 0);
      expect(summary.skippedBudget, 0);
    });

    test(
      'rejects an unrelated client decrypt failure from a route-matched wake aggregate',
      () async {
        final scope = MatrixE2eeBackupProbeScope(
          enabled: true,
          budget: const Duration(seconds: 5),
          routeClientId: 'routed-client',
          routeRoomId: '!routed:example.org',
          routeEventId: r'$routed',
        );
        var probeCount = 0;

        await scope.recordForRoute(
          clientId: 'unrelated-client',
          roomId: '!routed:example.org',
          eventId: r'$routed',
          probe: (_) async {
            probeCount++;
            return MatrixE2eeBackupProbeOutcome.inBackup;
          },
        );

        var summary = await scope.finish();
        expect(probeCount, 0);
        expect(summary.candidates, 0);
        expect(summary.inBackup, 0);

        // The exact routed event still records normally; the isolation above
        // is not a blanket probe disablement.
        final matchedScope = MatrixE2eeBackupProbeScope(
          enabled: true,
          budget: const Duration(seconds: 5),
          routeClientId: 'routed-client',
          routeRoomId: '!routed:example.org',
          routeEventId: r'$routed',
        );
        await matchedScope.recordForRoute(
          clientId: 'routed-client',
          roomId: '!routed:example.org',
          eventId: r'$routed',
          probe: (_) async {
            probeCount++;
            return MatrixE2eeBackupProbeOutcome.inBackup;
          },
        );
        summary = await matchedScope.finish();
        expect(probeCount, 1);
        expect(summary.candidates, 1);
        expect(summary.inBackup, 1);
      },
    );
  });

  group('MatrixPersistentRequestableSessionRepairDispatcher', () {
    test(
      'queues one follow-up when dispatch overlaps an active retry',
      () async {
        final callbackStarted = Completer<void>();
        final releaseCallback = Completer<void>();
        var callbackCount = 0;
        final dispatcher = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
          callback: () async {
            callbackCount++;
            if (!callbackStarted.isCompleted) {
              callbackStarted.complete();
            }
            await releaseCallback.future;
          },
        );

        final first = dispatcher.dispatch(suppressAutomaticRepair: false);
        await callbackStarted.future;
        final second = dispatcher.dispatch(suppressAutomaticRepair: false);

        expect(identical(first, second), isTrue);
        expect(callbackCount, 1);

        releaseCallback.complete();
        await first;
        await Future<void>.delayed(Duration.zero);
        expect(callbackCount, 2);
      },
    );

    test(
      'a suppressed dispatch overlapping an active retry queues no follow-up',
      () async {
        // The trailing rerun always dispatches unsuppressed. That is only
        // safe while a suppressed call returns before it can request one.
        final callbackStarted = Completer<void>();
        final releaseCallback = Completer<void>();
        var callbackCount = 0;
        final dispatcher = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
          callback: () async {
            callbackCount++;
            if (!callbackStarted.isCompleted) {
              callbackStarted.complete();
            }
            await releaseCallback.future;
          },
        );

        final first = dispatcher.dispatch(suppressAutomaticRepair: false);
        await callbackStarted.future;
        final suppressed = dispatcher.dispatch(suppressAutomaticRepair: true);

        releaseCallback.complete();
        await Future.wait(<Future<void>>[first, suppressed]);
        await Future<void>.delayed(Duration.zero);
        expect(callbackCount, 1);
      },
    );

    test(
      'does not dispatch when suppressed, disposed, or callback-free',
      () async {
        var callbackCount = 0;
        final suppressed = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
          callback: () async => callbackCount++,
        );
        await suppressed.dispatch(suppressAutomaticRepair: true);

        final disposed = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => true,
          callback: () async => callbackCount++,
        );
        await disposed.dispatch(suppressAutomaticRepair: false);

        final absent = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
        );
        await absent.dispatch(suppressAutomaticRepair: false);

        expect(callbackCount, 0);
      },
    );

    test('contains a callback failure and permits a later retry', () async {
      var callbackCount = 0;
      var failureCount = 0;
      final dispatcher = MatrixPersistentRequestableSessionRepairDispatcher(
        isDisposed: () => false,
        callback: () async {
          callbackCount++;
          if (callbackCount == 1) {
            throw StateError('expected test failure');
          }
        },
        onFailure: (_, _) => failureCount++,
      );

      await dispatcher.dispatch(suppressAutomaticRepair: false);
      await dispatcher.dispatch(suppressAutomaticRepair: false);

      expect(callbackCount, 2);
      expect(failureCount, 1);
    });

    test(
      'developer dispatch requires developer mode and keeps normal bounds',
      () async {
        var callbackCount = 0;
        final dispatcher = MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
          callback: () async => callbackCount++,
        );

        expect(
          await dispatcher.dispatchForDeveloper(
            developerModeEnabled: false,
            suppressAutomaticRepair: false,
          ),
          isFalse,
        );
        expect(
          await dispatcher.dispatchForDeveloper(
            developerModeEnabled: true,
            suppressAutomaticRepair: true,
          ),
          isFalse,
        );
        expect(
          await dispatcher.dispatchForDeveloper(
            developerModeEnabled: true,
            suppressAutomaticRepair: false,
          ),
          isTrue,
        );
        expect(callbackCount, 1);
      },
    );
  });

  test(
    'verified session still recommends recovery when backup key is locked',
    () {
      final status = _status(
        keyBackupEnabled: true,
        cryptoIdentityInitialized: true,
        cryptoIdentityConnected: false,
        keyBackupCached: false,
        currentDeviceVerified: true,
      );

      expect(status.needsRecoveryKeyForHistory, isTrue);
      expect(
        status.currentDeviceSummary,
        'This session is verified, but old messages may still need your recovery key.',
      );
    },
  );

  test('verified session is healthy when backup key is cached', () {
    final status = _status(
      keyBackupEnabled: true,
      cryptoIdentityInitialized: true,
      cryptoIdentityConnected: true,
      keyBackupCached: true,
      currentDeviceVerified: true,
    );

    expect(status.needsRecoveryKeyForHistory, isFalse);
    expect(status.currentDeviceSummary, 'This session is verified.');
  });

  test(
    'stale missing room sessions summarize after repeated unresolved misses',
    () {
      var now = DateTime.utc(2026, 7, 6, 12);
      final tracker = MatrixMissingRoomSessionStalenessTracker(
        now: () => now,
        hash: (value) => value?.toString() ?? 'none',
        staleAfter: const Duration(minutes: 5),
        relogAfter: const Duration(minutes: 30),
        minObservations: 3,
      );

      expect(
        tracker.recordMissing(
          source: 'timeline',
          roomId: '!room:example',
          senderId: '@alice:example',
          sessionId: 'SESSION',
          senderKey: 'SENDER_KEY',
        ),
        isNull,
      );
      now = now.add(const Duration(minutes: 4));
      expect(
        tracker.recordMissing(
          source: 'timeline',
          roomId: '!room:example',
          senderId: '@alice:example',
          sessionId: 'SESSION',
          senderKey: 'SENDER_KEY',
        ),
        isNull,
      );

      now = now.add(const Duration(minutes: 2));
      final summary = tracker.recordMissing(
        source: 'history',
        roomId: '!room:example',
        senderId: '@alice:example',
        sessionId: 'SESSION',
        senderKey: 'SENDER_KEY',
      );

      expect(summary, isNotNull);
      expect(summary!.roomHash, '!room:example');
      expect(summary.senderHash, '@alice:example');
      expect(summary.sessionHash, 'SESSION');
      expect(summary.senderKeyHash, 'SENDER_KEY');
      expect(summary.sourcesLabel, 'timeline,history');
      expect(summary.observations, 3);
      expect(summary.ageSeconds, 360);

      expect(
        tracker.recordMissing(
          source: 'history',
          roomId: '!room:example',
          senderId: '@alice:example',
          sessionId: 'SESSION',
          senderKey: 'SENDER_KEY',
        ),
        isNull,
      );
    },
  );

  test('stale missing room sessions resolve when the room key arrives', () {
    var now = DateTime.utc(2026, 7, 6, 12);
    final tracker = MatrixMissingRoomSessionStalenessTracker(
      now: () => now,
      hash: (value) => value?.toString() ?? 'none',
      staleAfter: const Duration(minutes: 5),
      relogAfter: const Duration(minutes: 30),
      minObservations: 3,
    );

    for (var index = 0; index < 3; index++) {
      tracker.recordMissing(
        source: 'timeline',
        roomId: '!room:example',
        senderId: '@alice:example',
        sessionId: 'SESSION',
        senderKey: 'SENDER_KEY',
      );
      now = now.add(const Duration(minutes: 3));
    }

    final resolved = tracker.recordRoomKeyReceived(
      roomId: '!room:example',
      sessionId: 'SESSION',
    );

    expect(resolved, isNotNull);
    expect(resolved!.roomHash, '!room:example');
    expect(resolved.sessionHash, 'SESSION');
    expect(resolved.sendersLabel, '@alice:example');
    expect(resolved.observations, 3);

    expect(
      tracker.recordRoomKeyReceived(
        roomId: '!room:example',
        sessionId: 'SESSION',
      ),
      isNull,
    );
  });

  test(
    'late matching room keys resolve and dispatch retry before stale',
    () async {
      final tracker = MatrixMissingRoomSessionStalenessTracker(
        hash: (value) => value?.toString() ?? 'none',
      );

      tracker.recordMissing(
        source: 'timeline',
        roomId: '!room:example',
        senderId: '@alice:example',
        sessionId: 'SESSION',
        senderKey: 'SENDER_KEY',
      );

      var retryCount = 0;
      final coordinator = MatrixLateRoomKeyRetryCoordinator(
        tracker: tracker,
        dispatcher: MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => false,
          callback: () async => retryCount++,
        ),
        suppressAutomaticRepair: false,
      );

      final resolved = coordinator.recordRoomKeyReceived(
        roomId: '!room:example',
        sessionId: 'SESSION',
      );

      expect(resolved, isNotNull);
      expect(resolved!.observations, 1);
      await Future<void>.delayed(Duration.zero);
      expect(retryCount, 1);
    },
  );

  test('missing sessions without a room and session never become stale', () {
    final tracker = MatrixMissingRoomSessionStalenessTracker(
      staleAfter: Duration.zero,
      minObservations: 1,
    );

    expect(
      tracker.recordMissing(
        source: 'timeline',
        roomId: '!room:example',
        senderId: '@alice:example',
        sessionId: null,
        senderKey: 'SENDER_KEY',
      ),
      isNull,
    );
    expect(
      tracker.recordMissing(
        source: 'timeline',
        roomId: null,
        senderId: '@alice:example',
        sessionId: 'SESSION',
        senderKey: 'SENDER_KEY',
      ),
      isNull,
    );
  });

  test('unresolved missing session observations stay bounded', () {
    var now = DateTime.utc(2026, 7, 6, 12);
    final tracker = MatrixMissingRoomSessionStalenessTracker(
      now: () => now,
      hash: (value) => value?.toString() ?? 'none',
      staleAfter: Duration.zero,
      minObservations: 1,
      maxTrackedObservations: 4,
    );

    // Log every observation as stale so resolution summaries reveal which
    // entries the tracker still remembers.
    for (var index = 0; index < 10; index++) {
      final summary = tracker.recordMissing(
        source: 'timeline',
        roomId: '!room$index:example',
        senderId: '@alice:example',
        sessionId: 'SESSION$index',
        senderKey: 'SENDER_KEY',
      );
      expect(summary, isNotNull);
      now = now.add(const Duration(seconds: 1));
    }

    // The oldest entries were evicted to honor the cap.
    expect(
      tracker.recordRoomKeyReceived(
        roomId: '!room0:example',
        sessionId: 'SESSION0',
      ),
      isNull,
    );

    // The most recent entries within the cap are still tracked.
    for (var index = 6; index < 10; index++) {
      expect(
        tracker.recordRoomKeyReceived(
          roomId: '!room$index:example',
          sessionId: 'SESSION$index',
        ),
        isNotNull,
        reason: 'recent session $index should still be tracked',
      );
    }
  });
}

MatrixE2eeTrustStatus _status({
  required bool keyBackupEnabled,
  required bool? cryptoIdentityInitialized,
  required bool? cryptoIdentityConnected,
  required bool? keyBackupCached,
  required bool? currentDeviceVerified,
}) {
  return MatrixE2eeTrustStatus(
    clientIdHash: 'client',
    userIdHash: 'user',
    deviceId: 'DEVICE',
    encryptionAvailable: true,
    crossSigningEnabled: true,
    keyBackupEnabled: keyBackupEnabled,
    cryptoIdentityInitialized: cryptoIdentityInitialized,
    cryptoIdentityConnected: cryptoIdentityConnected,
    keyBackupCached: keyBackupCached,
    crossSigningCached: cryptoIdentityConnected,
    keySharingPolicy: MatrixE2eeDiagnostics.policyCrossVerifiedIfEnabled,
    masterKeyAvailable: true,
    masterKeyVerified: true,
    currentDeviceKnown: true,
    currentDeviceVerified: currentDeviceVerified,
    currentDeviceCrossVerified: currentDeviceVerified,
    currentDeviceDirectVerified: false,
    currentDeviceBlocked: false,
    ownDeviceCount: 1,
    verifiedOwnDeviceCount: currentDeviceVerified == true ? 1 : 0,
    blockedOwnDeviceCount: 0,
    encryptableOwnDeviceCount: 1,
  );
}
