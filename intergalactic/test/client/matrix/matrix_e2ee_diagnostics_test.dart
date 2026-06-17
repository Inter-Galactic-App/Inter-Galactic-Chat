import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';

void main() {
  test('verified session still recommends recovery when backup key is locked',
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
  });

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
