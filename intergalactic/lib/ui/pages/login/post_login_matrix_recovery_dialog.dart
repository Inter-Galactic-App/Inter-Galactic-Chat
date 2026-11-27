import 'dart:async';

import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/biometric_recovery_key_panel.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_page.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PostLoginMatrixRecoveryDialog extends StatefulWidget {
  const PostLoginMatrixRecoveryDialog({
    required this.client,
    this.initialRecoveryKey,
    super.key,
  });

  final MatrixClient client;
  final String? initialRecoveryKey;

  @override
  State<PostLoginMatrixRecoveryDialog> createState() =>
      _PostLoginMatrixRecoveryDialogState();
}

class _PostLoginMatrixRecoveryDialogState
    extends State<PostLoginMatrixRecoveryDialog> {
  _PostLoginRecoveryPhase phase = _PostLoginRecoveryPhase.waiting;
  _PostLoginRecoverySnapshot? snapshot;
  bool _isClosed = false;
  bool _autoRecoveryAttempted = false;
  String? _autoRecoveryError;
  String? _biometricRecoveryKey;
  bool _biometricRecoveryKeyFailedRecovery = false;

  String? get _effectiveRecoveryKey {
    final biometricRecoveryKey = _biometricRecoveryKey?.trim();
    if (biometricRecoveryKey != null && biometricRecoveryKey.isNotEmpty) {
      return biometricRecoveryKey;
    }
    final recoveryKey = widget.initialRecoveryKey?.trim();
    if (recoveryKey == null || recoveryKey.isEmpty) {
      return null;
    }
    return recoveryKey;
  }

  String get labelPreparingSecureSession => Intl.message(
        'Preparing secure session',
        name: 'labelPreparingSecureSession',
        desc:
            'Title shown while Inter Galactic waits for Matrix encryption state to load immediately after login',
      );

  String get labelPreparingSecureSessionExplanation => Intl.message(
        'Inter Galactic is checking whether this account already has encrypted session data to restore on this device.',
        name: 'labelPreparingSecureSessionExplanation',
        desc:
            'Explains why the app is waiting after login before deciding whether recovery is needed',
      );

  String get labelRestoreEncryptedHistory => Intl.message(
        'Restore encrypted history',
        name: 'labelRestoreEncryptedHistory',
        desc:
            'Title shown when the user is asked for their Matrix recovery key immediately after login',
      );

  String get labelRestoreEncryptedHistoryExplanation => Intl.message(
        'Sign-in is complete. This account has encrypted keys or message backup configured, so you can enter your recovery key now, unlock a stored key with biometrics, or set up a local biometric-protected copy.',
        name: 'labelRestoreEncryptedHistoryExplanation',
        desc:
            'Explains why the user is being asked for a recovery key after login',
      );

  String get labelDeferredRecoveryExplanation => Intl.message(
        'Encrypted session data is still loading. You can continue into the app for now, but recovery and verification may not be ready until chat sync finishes.',
        name: 'labelDeferredRecoveryExplanation',
        desc:
            'Shown when the app could not determine recovery state quickly enough after login',
      );

  String get labelEncryptionReady => Intl.message(
        'Encryption ready',
        name: 'labelEncryptionReady',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether encryption is loaded',
      );

  String get labelCrossSigningReady => Intl.message(
        'Cross-signing found',
        name: 'labelCrossSigningReady',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether cross-signing exists for the account',
      );

  String get labelCryptoIdentityInitialized => Intl.message(
        'Crypto identity initialized',
        name: 'labelCryptoIdentityInitialized',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether cross-signing and backup already exist for this account',
      );

  String get labelCryptoIdentityConnected => Intl.message(
        'Crypto identity connected',
        name: 'labelCryptoIdentityConnected',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether this device already has the encrypted secrets cached locally',
      );

  String get labelMessageBackupReady => Intl.message(
        'Message backup found',
        name: 'labelMessageBackupReady',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether online key backup exists',
      );

  String get labelCurrentDeviceVerified => Intl.message(
        'Current device verified',
        name: 'labelCurrentDeviceVerified',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether the current device is already trusted',
      );

  String get labelCurrentDeviceKeyLoaded => Intl.message(
        'Current device key loaded',
        name: 'labelCurrentDeviceKeyLoaded',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether the current device key is available locally yet',
      );

  String get labelRecoveryKeyDetected => Intl.message(
        'Recovery key ready',
        name: 'labelRecoveryKeyDetected',
        desc:
            'Diagnostic-style label shown in the post-login recovery dialog for whether a recovery key is ready to try',
      );

  String get labelAutomaticRecoveryNeedsAttention => Intl.message(
        'Automatic recovery could not finish with the recovery key. You can review or correct the key below and try again.',
        name: 'labelAutomaticRecoveryNeedsAttention',
        desc:
            'Shown when a provided or biometric-unlocked recovery key did not fully restore the Matrix crypto identity automatically',
      );

  String get labelStoredRecoveryKeyNeedsAttention => Intl.message(
        'The stored recovery key did not unlock Matrix recovery. Update it with your current recovery key or delete the local copy below.',
        name: 'labelStoredRecoveryKeyNeedsAttention',
        desc:
            'Shown when a biometric-unlocked recovery key appears stale and should be updated or deleted',
      );

  String get promptContinueWithoutRecovery => Intl.message(
        'Continue without recovery',
        name: 'promptContinueWithoutRecovery',
        desc:
            'Button text to skip the immediate recovery-key step after login and continue into the app',
      );

  String get promptKeepWaiting => Intl.message(
        'Keep waiting',
        name: 'promptKeepWaiting',
        desc:
            'Button text to continue waiting for Matrix encryption state to load after login',
      );

  @override
  void initState() {
    super.initState();
    unawaited(_prepareRecoveryFlow());
  }

  @override
  void dispose() {
    _isClosed = true;
    _biometricRecoveryKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: switch (phase) {
        _PostLoginRecoveryPhase.waiting => _buildWaitingState(),
        _PostLoginRecoveryPhase.ready => _buildRecoveryState(),
        _PostLoginRecoveryPhase.deferred => _buildDeferredState(),
      },
    );
  }

  Future<void> _prepareRecoveryFlow() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));

    while (!_isClosed && DateTime.now().isBefore(deadline)) {
      var currentSnapshot = await _captureSnapshot();
      snapshot = currentSnapshot;

      if (await _tryAutomaticRecoveryIfPossible(currentSnapshot)) {
        return;
      }
      currentSnapshot = snapshot ?? currentSnapshot;

      if (_isHealthy(currentSnapshot)) {
        if (mounted && !_isClosed) {
          _startDecryptSweep();
          _isClosed = true;
          Navigator.of(context).pop(true);
        }
        return;
      }

      if (currentSnapshot.encryptionReady &&
          !_needsRecoveryGate(currentSnapshot)) {
        if (mounted && !_isClosed) {
          _isClosed = true;
          Navigator.of(context).pop(true);
        }
        return;
      }

      if (_needsImmediateRecovery(currentSnapshot)) {
        if (mounted && !_isClosed) {
          setState(() {
            phase = _PostLoginRecoveryPhase.ready;
          });
        }
        return;
      }

      await _waitForNextSyncTick();
    }

    var currentSnapshot = await _captureSnapshot();
    snapshot = currentSnapshot;

    if (await _tryAutomaticRecoveryIfPossible(currentSnapshot)) {
      return;
    }
    currentSnapshot = snapshot ?? currentSnapshot;

    if (_isHealthy(currentSnapshot) || !_needsRecoveryGate(currentSnapshot)) {
      if (mounted && !_isClosed) {
        if (_isHealthy(currentSnapshot)) {
          _startDecryptSweep();
        }
        _isClosed = true;
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (mounted && !_isClosed) {
      setState(() {
        phase = _PostLoginRecoveryPhase.deferred;
      });
    }
  }

  Future<_PostLoginRecoverySnapshot> _captureSnapshot() async {
    final matrixClient = widget.client.getMatrixClient();
    final encryption = matrixClient.encryption;
    final userId = matrixClient.userID;
    final deviceId = matrixClient.deviceID;

    final accountDataLoading = matrixClient.accountDataLoading;
    if (accountDataLoading != null) {
      try {
        await accountDataLoading;
      } catch (_) {}
    }

    final userDeviceKeysLoading = matrixClient.userDeviceKeysLoading;
    if (userDeviceKeysLoading != null) {
      try {
        await userDeviceKeysLoading;
      } catch (_) {}
    }

    bool cryptoIdentityInitialized = false;
    bool cryptoIdentityConnected = false;

    if (matrixClient.encryptionEnabled && encryption != null) {
      try {
        final cryptoIdentityState = await matrixClient.getCryptoIdentityState();
        cryptoIdentityInitialized = cryptoIdentityState.initialized;
        cryptoIdentityConnected = cryptoIdentityState.connected;
      } catch (_) {}
    }

    final currentDeviceKeys = userId == null || deviceId == null
        ? null
        : matrixClient.userDeviceKeys[userId]?.deviceKeys[deviceId];

    return _PostLoginRecoverySnapshot(
      encryptionReady: matrixClient.encryptionEnabled &&
          encryption != null &&
          userId != null,
      hasCrossSigning: encryption?.crossSigning.enabled ?? false,
      hasOnlineBackup: encryption?.keyManager.enabled ?? false,
      cryptoIdentityInitialized: cryptoIdentityInitialized,
      cryptoIdentityConnected: cryptoIdentityConnected,
      currentDeviceKnown: currentDeviceKeys != null,
      currentDeviceVerified: currentDeviceKeys?.verified ?? false,
      recoveryKeyProvided: _effectiveRecoveryKey != null,
    );
  }

  bool _isHealthy(_PostLoginRecoverySnapshot snapshot) {
    return snapshot.encryptionReady &&
        (!_needsRecoveryGate(snapshot) || snapshot.cryptoIdentityConnected);
  }

  bool _needsRecoveryGate(_PostLoginRecoverySnapshot snapshot) {
    return snapshot.cryptoIdentityInitialized ||
        snapshot.hasCrossSigning ||
        snapshot.hasOnlineBackup;
  }

  bool _needsImmediateRecovery(_PostLoginRecoverySnapshot snapshot) {
    return snapshot.encryptionReady &&
        _needsRecoveryGate(snapshot) &&
        !snapshot.cryptoIdentityConnected;
  }

  Future<bool> _tryAutomaticRecoveryIfPossible(
    _PostLoginRecoverySnapshot snapshot,
  ) async {
    final recoveryKey = _effectiveRecoveryKey;
    final biometricRecoveryKey = _biometricRecoveryKey?.trim();
    final usingBiometricRecoveryKey = biometricRecoveryKey != null &&
        biometricRecoveryKey.isNotEmpty &&
        recoveryKey == biometricRecoveryKey;
    if (_autoRecoveryAttempted ||
        recoveryKey == null ||
        !snapshot.encryptionReady ||
        !_needsRecoveryGate(snapshot) ||
        snapshot.cryptoIdentityConnected) {
      return false;
    }

    _autoRecoveryAttempted = true;

    try {
      await widget.client.getMatrixClient().restoreCryptoIdentity(recoveryKey);
    } catch (_) {
      _autoRecoveryError = 'Recovery could not unlock this account.';
      if (usingBiometricRecoveryKey) {
        _biometricRecoveryKeyFailedRecovery = true;
      }
    }

    final updatedSnapshot = await _captureSnapshot();
    this.snapshot = updatedSnapshot;

    if (_isHealthy(updatedSnapshot)) {
      _autoRecoveryError = null;
      if (mounted && !_isClosed) {
        _startDecryptSweep();
        _isClosed = true;
        Navigator.of(context).pop(true);
      }
      return true;
    }

    if (_autoRecoveryError == null) {
      _autoRecoveryError =
          'Automatic recovery did not fully reconnect this device yet.';
    }
    if (usingBiometricRecoveryKey) {
      _biometricRecoveryKeyFailedRecovery = true;
    }

    if (mounted && !_isClosed) {
      setState(() {});
    }

    return false;
  }

  Future<void> _waitForNextSyncTick() async {
    try {
      await widget.client.onSync.first.timeout(const Duration(seconds: 1));
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  void _startDecryptSweep() {
    unawaited(widget.client.retryDecryptAllRooms());
  }

  Future<void> _retryWaiting() async {
    if (!mounted || _isClosed) {
      return;
    }

    setState(() {
      phase = _PostLoginRecoveryPhase.waiting;
    });
    await _prepareRecoveryFlow();
  }

  Future<void> _completeRecovery() async {
    if (_isClosed || !mounted) {
      return;
    }

    _isClosed = true;
    _startDecryptSweep();
    Navigator.of(context).pop(true);
  }

  Future<void> _handleBiometricRecoveryKeyUnlocked(String recoveryKey) async {
    if (_isClosed || !mounted) {
      return;
    }

    setState(() {
      _biometricRecoveryKey = recoveryKey;
      _autoRecoveryAttempted = false;
      _autoRecoveryError = null;
      _biometricRecoveryKeyFailedRecovery = false;
    });

    final currentSnapshot = snapshot ?? await _captureSnapshot();
    if (await _tryAutomaticRecoveryIfPossible(currentSnapshot)) {
      return;
    }

    if (mounted && !_isClosed) {
      final updatedSnapshot = this.snapshot ?? currentSnapshot;
      setState(() {
        snapshot = updatedSnapshot;
      });
    }
  }

  Future<void> _handleBiometricStorageChanged() async {
    if (_isClosed || !mounted) {
      return;
    }

    final updatedSnapshot = await _captureSnapshot();
    snapshot = updatedSnapshot;
    _biometricRecoveryKey = null;
    _autoRecoveryAttempted = false;
    _autoRecoveryError = null;
    _biometricRecoveryKeyFailedRecovery = false;
    if (_isHealthy(updatedSnapshot)) {
      await _completeRecovery();
      return;
    }

    if (mounted && !_isClosed) {
      setState(() {});
    }
  }

  void _skipRecovery() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    Navigator.of(context).pop(false);
  }

  Widget _buildWaitingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        tiamat.Text.label(labelPreparingSecureSession),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(labelPreparingSecureSessionExplanation),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          _buildSnapshotDetails(snapshot!),
        ],
        if (_autoRecoveryError != null) ...[
          const SizedBox(height: 12),
          _buildAutomaticRecoveryWarning(),
        ],
        const SizedBox(height: 16),
        tiamat.Button.secondary(
          text: promptContinueWithoutRecovery,
          onTap: _skipRecovery,
        ),
      ],
    );
  }

  Widget _buildRecoveryState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(labelRestoreEncryptedHistory),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(labelRestoreEncryptedHistoryExplanation),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          _buildSnapshotDetails(snapshot!),
        ],
        if (_autoRecoveryError != null) ...[
          const SizedBox(height: 12),
          _buildAutomaticRecoveryWarning(),
        ],
        const SizedBox(height: 12),
        BiometricRecoveryKeySettingsRow(
          client: widget.client,
          onRecoveryKeyUnlocked: _handleBiometricRecoveryKeyUnlocked,
          onStorageChanged: _handleBiometricStorageChanged,
        ),
        const SizedBox(height: 16),
        MatrixCrossSigningPage(
          client: widget.client,
          mode: MatrixCrossSigningMode.restoreBackup,
          initialRecoveryKey: _effectiveRecoveryKey,
          onComplete: _completeRecovery,
        ),
        const SizedBox(height: 12),
        tiamat.Button.secondary(
          text: promptContinueWithoutRecovery,
          onTap: _skipRecovery,
        ),
      ],
    );
  }

  Widget _buildDeferredState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(labelRestoreEncryptedHistory),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(labelDeferredRecoveryExplanation),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          _buildSnapshotDetails(snapshot!),
        ],
        if (_autoRecoveryError != null) ...[
          const SizedBox(height: 12),
          _buildAutomaticRecoveryWarning(),
        ],
        const SizedBox(height: 16),
        tiamat.Button(
          text: promptKeepWaiting,
          onTap: () => unawaited(_retryWaiting()),
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: promptContinueWithoutRecovery,
          onTap: _skipRecovery,
        ),
      ],
    );
  }

  Widget _buildAutomaticRecoveryWarning() {
    final label = _biometricRecoveryKeyFailedRecovery
        ? labelStoredRecoveryKeyNeedsAttention
        : labelAutomaticRecoveryNeedsAttention;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.error),
        color: Theme.of(context).colorScheme.errorContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.label(label),
            const SizedBox(height: 8),
            tiamat.Text.labelLow(_autoRecoveryError!),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotDetails(_PostLoginRecoverySnapshot snapshot) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSnapshotRow(labelEncryptionReady, snapshot.encryptionReady),
            _buildSnapshotRow(labelCrossSigningReady, snapshot.hasCrossSigning),
            _buildSnapshotRow(
              labelMessageBackupReady,
              snapshot.hasOnlineBackup,
            ),
            _buildSnapshotRow(
              labelCryptoIdentityInitialized,
              snapshot.cryptoIdentityInitialized,
            ),
            _buildSnapshotRow(
              labelCryptoIdentityConnected,
              snapshot.cryptoIdentityConnected,
            ),
            _buildSnapshotRow(
              labelCurrentDeviceKeyLoaded,
              snapshot.currentDeviceKnown,
            ),
            _buildSnapshotRow(
              labelCurrentDeviceVerified,
              snapshot.currentDeviceVerified,
            ),
            _buildSnapshotRow(
              labelRecoveryKeyDetected,
              snapshot.recoveryKeyProvided,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: value
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: tiamat.Text.labelLow(
              '$label: ${value ? CommonStrings.labelEnabled : CommonStrings.labelDisabled}',
            ),
          ),
        ],
      ),
    );
  }
}

enum _PostLoginRecoveryPhase {
  waiting,
  ready,
  deferred,
}

class _PostLoginRecoverySnapshot {
  const _PostLoginRecoverySnapshot({
    required this.encryptionReady,
    required this.hasCrossSigning,
    required this.hasOnlineBackup,
    required this.cryptoIdentityInitialized,
    required this.cryptoIdentityConnected,
    required this.currentDeviceKnown,
    required this.currentDeviceVerified,
    required this.recoveryKeyProvided,
  });

  final bool encryptionReady;
  final bool hasCrossSigning;
  final bool hasOnlineBackup;
  final bool cryptoIdentityInitialized;
  final bool cryptoIdentityConnected;
  final bool currentDeviceKnown;
  final bool currentDeviceVerified;
  final bool recoveryKeyProvided;
}
