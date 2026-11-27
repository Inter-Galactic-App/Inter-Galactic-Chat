import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';

/// BUG-202. Pins what `currentDeviceHealthy` actually decides, because it is the
/// whole of the call-join E2EE gate and nothing tested it.
///
/// ONE OF THESE CASES DOCUMENTS A DEFECT ON PURPOSE and says so in its name. It
/// is a characterization test, not an endorsement: it exists so the fail-open is
/// visible in the suite rather than only in a comment, and so that FIXING it
/// turns this file red and forces whoever fixes it to state the new intent here.
/// Do not "repair" that case to match a changed implementation without reading
/// BUG-202 first.
MatrixE2eeTrustStatus _status({
  bool encryptionAvailable = true,
  bool crossSigningEnabled = true,
  bool currentDeviceKnown = true,
  bool? currentDeviceVerified = true,
  bool? currentDeviceBlocked = false,
}) {
  return MatrixE2eeTrustStatus(
    clientIdHash: 'c',
    userIdHash: 'u',
    deviceId: 'D',
    encryptionAvailable: encryptionAvailable,
    crossSigningEnabled: crossSigningEnabled,
    keyBackupEnabled: false,
    cryptoIdentityInitialized: true,
    cryptoIdentityConnected: true,
    keyBackupCached: false,
    crossSigningCached: false,
    keySharingPolicy: 'all',
    masterKeyAvailable: true,
    masterKeyVerified: true,
    currentDeviceKnown: currentDeviceKnown,
    currentDeviceVerified: currentDeviceVerified,
    currentDeviceCrossVerified: currentDeviceVerified,
    currentDeviceDirectVerified: currentDeviceVerified,
    currentDeviceBlocked: currentDeviceBlocked,
    ownDeviceCount: 1,
    verifiedOwnDeviceCount: 1,
    blockedOwnDeviceCount: 0,
    encryptableOwnDeviceCount: 1,
  );
}

void main() {
  group('currentDeviceHealthy, the call-join gate', () {
    test('a verified device on a cross-signed account is healthy', () {
      expect(_status().currentDeviceHealthy, isTrue);
    });

    test('an UNVERIFIED device on a cross-signed account is NOT healthy', () {
      // The case the gate exists for.
      expect(
        _status(
          crossSigningEnabled: true,
          currentDeviceVerified: false,
        ).currentDeviceHealthy,
        isFalse,
      );
    });

    test('an unknown device is not healthy, so an unloaded key map FAILS '
        'CLOSED', () {
      // Checked while hunting a fail-open and worth keeping as the answer:
      // `currentDeviceKnown` is `currentDeviceKeys != null`, so a device-key map
      // that has not loaded refuses rather than permits. A hypothesis worth
      // killing once.
      expect(_status(currentDeviceKnown: false).currentDeviceHealthy, isFalse);
    });

    test('a blocked device is not healthy even when verified', () {
      expect(_status(currentDeviceBlocked: true).currentDeviceHealthy, isFalse);
    });

    test('encryption being unavailable is not healthy', () {
      expect(_status(encryptionAvailable: false).currentDeviceHealthy, isFalse);
    });

    test('DEFECT BUG-202: an unverified device is judged HEALTHY when '
        'crossSigningEnabled reads false', () {
      // THIS ASSERTS THE CURRENT, WRONG BEHAVIOUR. `currentDeviceHealthy` ends
      // in `(currentDeviceVerified == true || !crossSigningEnabled)`, so an
      // unverified device passes whenever that flag is false.
      //
      // Why that is reachable on an account that HAS cross-signing:
      // `crossSigningEnabled` comes from the SDK's `CrossSigning.enabled`
      // (cross_signing.dart:55, matrix 6.1.1 at 58e0bd24), which is three SSSS
      // ACCOUNT-DATA reads and does NOT await `client.accountDataLoading` -
      // while `isCached()` five lines below it does. Before account data lands,
      // "we have not loaded the data that would tell us cross-signing is on"
      // is silently equivalent to "cross-signing is off", on a gate whose only
      // job is refusing unverified sessions.
      //
      // `refreshE2eeTrustStatus()` does not close it either: it refreshes
      // DEVICE KEYS and never awaits account data, so a refresh that SUCCEEDS
      // can still leave this flag false.
      //
      // WHEN BUG-202 IS FIXED THIS TEST GOES RED. That is intended. Replace it
      // with the assertion for whatever the gate then does - most likely that
      // unknown cross-signing state is treated as NOT healthy - rather than
      // deleting it, so the fail-open stays documented as having existed.
      expect(
        _status(
          crossSigningEnabled: false,
          currentDeviceVerified: false,
        ).currentDeviceHealthy,
        isTrue,
        reason:
            'documents the BUG-202 fail-open; see the comment above before '
            'changing this',
      );
    });
  });
}
