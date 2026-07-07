import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';

void main() {
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
