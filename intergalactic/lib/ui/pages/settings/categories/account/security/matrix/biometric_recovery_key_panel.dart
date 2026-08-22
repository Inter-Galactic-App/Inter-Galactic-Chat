import 'dart:async';

import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart';
import 'package:intergalactic/client/matrix/biometric_recovery_key_store.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class BiometricRecoveryKeySettingsRow extends m.StatefulWidget {
  const BiometricRecoveryKeySettingsRow({
    required this.client,
    this.store,
    this.onRecoveryKeyUnlocked,
    this.onStorageChanged,
    super.key,
  });

  final MatrixClient client;
  final BiometricRecoveryKeyStore? store;
  final Future<void> Function(String recoveryKey)? onRecoveryKeyUnlocked;
  final Future<void> Function()? onStorageChanged;

  @override
  m.State<BiometricRecoveryKeySettingsRow> createState() =>
      _BiometricRecoveryKeySettingsRowState();
}

class _BiometricRecoveryKeySettingsRowState
    extends m.State<BiometricRecoveryKeySettingsRow> {
  BiometricRecoveryKeyStatus? _status;
  bool _loading = true;
  bool _busy = false;

  BiometricRecoveryKeyStore get _store =>
      widget.store ?? BiometricRecoveryKeyStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStatus());
  }

  @override
  void didUpdateWidget(covariant BiometricRecoveryKeySettingsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client)) {
      unawaited(_refreshStatus());
    }
  }

  @override
  m.Widget build(m.BuildContext context) {
    final status = _status;
    return SettingsControlRow(
      title: 'Biometric recovery key',
      description: _descriptionFor(status),
      trailing: _trailingFor(status),
      child: _detailFor(status),
    );
  }

  String _descriptionFor(BiometricRecoveryKeyStatus? status) {
    if (_loading || status == null) {
      return 'Checking local biometric recovery-key storage on this device.';
    }
    if (!status.supported) {
      return 'Biometric recovery-key storage is available on supported iOS and Android devices.';
    }
    if (status.stored &&
        status.unavailableReason == 'biometry_changed_or_unavailable') {
      return 'The stored recovery key can no longer be unlocked with this device biometric set. Delete it and store the key again when you are ready.';
    }
    if (!status.biometricAvailable) {
      if (status.stored) {
        return 'A local recovery-key copy exists, but biometric unlock is not available on this device right now. You can delete the local copy.';
      }
      return 'Biometric unlock is not available on this device, so no local recovery-key copy can be stored.';
    }
    if (status.stored) {
      return 'A recovery key copy is stored on this device only and can be unlocked with ${status.promptLabel}. Keep a separate backup copy somewhere safe.';
    }
    return 'Optionally store an existing Matrix recovery key on this device only, protected by ${status.promptLabel}. Inter Galactic cannot recover it for you.';
  }

  m.Widget? _detailFor(BiometricRecoveryKeyStatus? status) {
    if (status == null || !status.supported) {
      return null;
    }

    final details = <m.Widget>[];
    final lastUpdated = status.lastUpdatedAt?.toLocal();
    if (status.stored) {
      details.add(
        tiamat.Text.labelLow(
          lastUpdated == null
              ? 'Stored locally. The key is not shown, logged, uploaded, or saved in preferences.'
              : 'Stored locally. Last updated ${lastUpdated.toString().split(".").first}. The key is not shown, logged, uploaded, or saved in preferences.',
        ),
      );
      details.add(const m.SizedBox(height: 8));
    }

    details.add(
      tiamat.Text.labelLow(
        'Emergency cleanup removes every Inter Galactic biometric recovery-key copy on this device, including historical copies from older sign-ins.',
      ),
    );
    details.add(const m.SizedBox(height: 8));
    details.add(
      m.Align(
        alignment: m.Alignment.centerLeft,
        child: tiamat.Button.danger(
          text: _busy ? 'Working...' : 'Delete all local keys',
          onTap: _busy ? null : _deleteAllStoredKeys,
        ),
      ),
    );

    return m.Column(
      crossAxisAlignment: m.CrossAxisAlignment.stretch,
      children: details,
    );
  }

  m.Widget _trailingFor(BiometricRecoveryKeyStatus? status) {
    if (_loading || status == null) {
      return const m.SizedBox(
        width: 24,
        height: 24,
        child: m.CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (!status.canStore) {
      if (status.stored) {
        return m.Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: m.WrapAlignment.end,
          children: [
            tiamat.Button.secondary(text: 'Unavailable', onTap: null),
            tiamat.Button.danger(
              text: CommonStrings.promptDelete,
              onTap: _busy ? null : _deleteStoredKey,
            ),
          ],
        );
      }
      return tiamat.Button.secondary(text: 'Unavailable', onTap: null);
    }

    if (status.stored) {
      return m.Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: m.WrapAlignment.end,
        children: [
          if (status.canRead)
            tiamat.Button.secondary(
              text: _busy ? 'Unlocking...' : 'Unlock',
              onTap: _busy ? null : _unlockStoredKey,
            ),
          tiamat.Button.secondary(
            text: _busy ? 'Working...' : 'Update',
            onTap: _busy ? null : () => _showSetupDialog(isUpdate: true),
          ),
          tiamat.Button.danger(
            text: CommonStrings.promptDelete,
            onTap: _busy ? null : _deleteStoredKey,
          ),
        ],
      );
    }

    return tiamat.Button.secondary(
      text: 'Set up',
      onTap: _busy ? null : () => _showSetupDialog(isUpdate: false),
    );
  }

  Future<void> _refreshStatus() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final status = await _store.status(widget.client);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _showSetupDialog({required bool isUpdate}) async {
    final saved = await AdaptiveDialog.show<bool>(
      context,
      title: isUpdate ? 'Update stored recovery key' : 'Store recovery key',
      dismissible: !_busy,
      builder: (context) => _BiometricRecoveryKeySetupDialog(
        client: widget.client,
        store: _store,
        isUpdate: isUpdate,
      ),
    );
    if (saved == true) {
      await widget.onStorageChanged?.call();
      await _refreshStatus();
      if (mounted) {
        m.ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const m.SnackBar(
            content: m.Text('Recovery key stored locally on this device.'),
          ),
        );
      }
    }
  }

  Future<void> _unlockStoredKey() async {
    setState(() {
      _busy = true;
    });
    String? recoveryKey;
    try {
      recoveryKey = await _store.read(
        widget.client,
        reason: 'Unlock your stored Matrix recovery key.',
      );
      if (recoveryKey == null) {
        if (mounted) {
          m.ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const m.SnackBar(
              content: m.Text('Stored recovery key was not unlocked.'),
            ),
          );
        }
        return;
      }
      await widget.onRecoveryKeyUnlocked?.call(recoveryKey);
    } finally {
      recoveryKey = null;
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteStoredKey() async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete local recovery key?',
      prompt:
          'This removes only the local biometric-protected copy from this device. Keep your separate recovery-key backup somewhere safe.',
      confirmationText: CommonStrings.promptDelete,
      dangerous: true,
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await _store.delete(widget.client);
      await widget.onStorageChanged?.call();
      await _refreshStatus();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteAllStoredKeys() async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete every local recovery key?',
      prompt:
          'This removes every Inter Galactic biometric recovery-key copy from this device, including historical copies from older app versions. Matrix recovery on the server is unchanged.',
      confirmationText: 'Delete all local keys',
      dangerous: true,
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await _store.deleteAllLocalRecoveryKeys();
      await widget.onStorageChanged?.call();
      await _refreshStatus();
      if (mounted) {
        m.ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const m.SnackBar(
            content: m.Text(
              'All local recovery-key copies were deleted from this device.',
            ),
          ),
        );
      }
    } catch (error) {
      Log.w(
        'Biometric recovery-key delete-all failed (${error.runtimeType}).',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      if (mounted) {
        m.ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const m.SnackBar(
            content: m.Text(
              'Local recovery-key copies could not be deleted from this device.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}

class BiometricRecoveryKeyUnlockButton extends m.StatefulWidget {
  const BiometricRecoveryKeyUnlockButton({
    required this.client,
    required this.onRecoveryKeyUnlocked,
    this.store,
    this.text = 'Unlock stored recovery key',
    super.key,
  });

  final MatrixClient client;
  final BiometricRecoveryKeyStore? store;
  final String text;
  final Future<void> Function(String recoveryKey) onRecoveryKeyUnlocked;

  @override
  m.State<BiometricRecoveryKeyUnlockButton> createState() =>
      _BiometricRecoveryKeyUnlockButtonState();
}

class _BiometricRecoveryKeyUnlockButtonState
    extends m.State<BiometricRecoveryKeyUnlockButton> {
  BiometricRecoveryKeyStatus? _status;
  bool _busy = false;

  BiometricRecoveryKeyStore get _store =>
      widget.store ?? BiometricRecoveryKeyStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStatus());
  }

  @override
  m.Widget build(m.BuildContext context) {
    if (_status?.canRead != true) {
      return const m.SizedBox.shrink();
    }
    return tiamat.Button.secondary(
      text: _busy ? 'Unlocking...' : widget.text,
      onTap: _busy ? null : _unlock,
    );
  }

  Future<void> _refreshStatus() async {
    final status = await _store.status(widget.client);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
    });
    String? recoveryKey;
    try {
      recoveryKey = await _store.read(
        widget.client,
        reason: 'Unlock your stored Matrix recovery key.',
      );
      if (recoveryKey != null) {
        await widget.onRecoveryKeyUnlocked(recoveryKey);
      }
    } finally {
      recoveryKey = null;
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}

class _BiometricRecoveryKeySetupDialog extends m.StatefulWidget {
  const _BiometricRecoveryKeySetupDialog({
    required this.client,
    required this.store,
    required this.isUpdate,
  });

  final MatrixClient client;
  final BiometricRecoveryKeyStore store;
  final bool isUpdate;

  @override
  m.State<_BiometricRecoveryKeySetupDialog> createState() =>
      _BiometricRecoveryKeySetupDialogState();
}

class _BiometricRecoveryKeySetupDialogState
    extends m.State<_BiometricRecoveryKeySetupDialog> {
  final m.TextEditingController _controller = m.TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.SizedBox(
      width: 500,
      child: m.Column(
        mainAxisSize: m.MainAxisSize.min,
        crossAxisAlignment: m.CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'This keeps a copy of your existing Matrix recovery key on this device only.',
          ),
          const m.SizedBox(height: 8),
          tiamat.Text.labelLow(
            'Biometrics unlock the stored key. Inter Galactic cannot recover it for you, and deleting the app or losing this device may remove this local copy. Keep a separate backup somewhere safe.',
          ),
          const m.SizedBox(height: 16),
          tiamat.TextInput(
            controller: _controller,
            obscureText: true,
            placeholder: 'Existing recovery key',
          ),
          if (_error != null) ...[
            const m.SizedBox(height: 8),
            tiamat.Text.error(_error!),
          ],
          const m.SizedBox(height: 16),
          tiamat.Button(
            text: _saving
                ? 'Validating...'
                : widget.isUpdate
                    ? 'Update'
                    : 'Store locally',
            isLoading: _saving,
            onTap: _saving ? null : _save,
          ),
          const m.SizedBox(height: 8),
          tiamat.Button.secondary(
            text: CommonStrings.promptCancel,
            onTap: _saving ? null : () => m.Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.store.validateAndSave(
        widget.client,
        _controller.text,
        validator: _validateRecoverySecretBeforeStorage,
      );
      _controller.clear();
      if (mounted) {
        m.Navigator.of(context).pop(true);
      }
    } catch (error) {
      Log.w(
        'Biometric recovery-key setup failed before local storage completed '
        '(${error.runtimeType}).',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _safeSetupError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _validateRecoverySecretBeforeStorage(String recoveryKey) async {
    final matrixClient = widget.client.getMatrixClient();
    final validationPath =
        await BiometricRecoveryKeyValidation.validateForCurrentIdentity(
      recoverySecret: recoveryKey,
      cryptoIdentityState: matrixClient.getCryptoIdentityState,
      validateConnectedSecretStorage: (recoverySecret) =>
          _validateRecoverySecretAgainstConnectedSsss(
        matrixClient,
        recoverySecret,
      ),
      restoreCryptoIdentity: matrixClient.restoreCryptoIdentity,
    );
    _logValidationPath(validationPath);

    await widget.client.refreshE2eeTrustStatus();
    unawaited(widget.client.retryDecryptAllRooms());
  }

  void _logValidationPath(BiometricRecoveryKeyValidationPath path) {
    switch (path) {
      case BiometricRecoveryKeyValidationPath.connectedSecretStorage:
        Log.i(
          'Biometric recovery-key setup validated against connected Matrix '
          'secret storage.',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
        return;
      case BiometricRecoveryKeyValidationPath.restoreCryptoIdentity:
        Log.i(
          'Biometric recovery-key setup restored Matrix crypto identity before '
          'local storage.',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
    }
  }

  Future<void> _validateRecoverySecretAgainstConnectedSsss(
    matrix.Client matrixClient,
    String recoveryKey,
  ) async {
    final encryption = matrixClient.encryption;
    if (encryption == null) {
      throw Exception('End to end encryption not available!');
    }

    final defaultKeyId = encryption.ssss.defaultKeyId;
    if (defaultKeyId == null || !encryption.ssss.isKeyValid(defaultKeyId)) {
      throw Exception('Matrix secure secret storage is not available.');
    }

    final openSsss = encryption.ssss.open(defaultKeyId);
    try {
      await openSsss.unlock(
        keyOrPassphrase: recoveryKey,
        postUnlock: false,
      );
    } finally {
      openSsss.privateKey = null;
    }
  }

  String _safeSetupError(Object error) {
    if (error is BiometricRecoveryKeyStoreException) {
      return error.message;
    }
    if (error is PlatformException) {
      return switch (error.code) {
        'auth_cancelled' =>
          'Biometric unlock was cancelled. The recovery key was not stored.',
        'auth_failed' =>
          'Biometric unlock did not complete. The recovery key was not stored.',
        'biometrics_unavailable' =>
          'Biometric unlock is not available. The recovery key was not stored.',
        _ => 'The recovery key could not be stored on this device.',
      };
    }
    return 'The recovery key could not unlock this Matrix account, so it was not stored.';
  }
}
