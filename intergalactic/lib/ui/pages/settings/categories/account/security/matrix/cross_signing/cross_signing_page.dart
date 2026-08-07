import 'dart:async';

import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_view.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/encryption.dart';

enum MatrixCrossSigningMode {
  standard,
  enableBackup,
  restoreBackup,
  resetCrossSigning,
  crossSigningOnly
}

class MatrixCrossSigningPage extends StatefulWidget {
  const MatrixCrossSigningPage(
      {required this.client,
      this.mode = MatrixCrossSigningMode.standard,
      super.key,
      this.initialRecoveryKey,
      this.onComplete});
  final MatrixClient client;
  final MatrixCrossSigningMode mode;
  final String? initialRecoveryKey;
  final Function()? onComplete;

  @override
  State<MatrixCrossSigningPage> createState() => MatrixCrossSigningPageState();
}

class MatrixCrossSigningPageState extends State<MatrixCrossSigningPage> {
  BootstrapState state = BootstrapState.loading;
  Bootstrap? bootstrapper;
  String? unavailableMessage;
  bool _didStartDecryptSweep = false;

  @override
  void initState() {
    super.initState();

    final mx = widget.client.getMatrixClient();
    final encryption = mx.encryption;
    if (encryption == null || !mx.encryptionEnabled) {
      unavailableMessage =
          'End to end encryption is not available for this session yet. Wait for chat sync to finish, then reopen Security. If it stays unavailable, sign out and sign back in again.';
      Log.w('Matrix cross-signing opened without encryption being available.');
      return;
    }

    bootstrapper = encryption.bootstrap(onUpdate: onBootstrapperUdate);
    onBootstrapperUdate(bootstrapper!);
  }

  @override
  Widget build(BuildContext context) {
    if (unavailableMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(unavailableMessage!),
        ),
      );
    }

    return MatrixCrossSigningView(
      state,
      recoveryKey: bootstrapper?.newSsssKey?.recoveryKey,
      initialRecoveryKey: widget.initialRecoveryKey,
      onSetNewSsss: (passphrase) {
        bootstrapper?.newSsss(passphrase);
      },
      onAskSetupCrossSigning: () async {
        await bootstrapper?.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
      },
      onAskSetupOnlineBackup: (enable) {
        bootstrapper?.askSetupOnlineKeyBackup(enable);
      },
      useExistingKeys: (use) {
        bootstrapper?.useExistingSsss(use);
      },
      wipeSsss: (wipe) {
        bootstrapper?.wipeSsss(wipe);
        // When wipe == false, wipeSsss(false) tells the bootstrap to keep
        // existing keys. The state machine transitions to the appropriate
        // next state (askUseExistingSsss or openExistingSsss) on its own.
        // Do NOT call useExistingSsss/openExistingSsss here -- that would
        // bypass the recovery key input step.
      },
      wipeExistingBackup: (wipe) {
        bootstrapper?.wipeOnlineKeyBackup(wipe);
      },
      openExistingSsss: (key) async {
        final currentBootstrapper = bootstrapper;
        if (currentBootstrapper == null) {
          throw Exception('Bootstrap is not initialized.');
        }

        var recoveryKey = currentBootstrapper.newSsssKey;
        if (recoveryKey == null) {
          // The SSSS key handle may not be loaded yet. Re-trigger
          // useExistingSsss to populate it, then retry.
          currentBootstrapper.useExistingSsss(true);
          recoveryKey = currentBootstrapper.newSsssKey;
        }

        if (recoveryKey == null) {
          throw Exception(
            'Unable to open secret storage. The default key may be missing. '
            'Try closing this dialog and reopening Security settings.',
          );
        }

        await recoveryKey.unlock(keyOrPassphrase: key);
        await currentBootstrapper.openExistingSsss();

        final encryption = currentBootstrapper.client.encryption;
        if (currentBootstrapper.encryption.crossSigning.enabled &&
            encryption != null) {
          await encryption.crossSigning.selfSign(keyOrPassphrase: key);
        }
      },
      unlockOldSsss: unlockOldSsss,
      ignoreBadSecrets: (ignore) {
        bootstrapper?.ignoreBadSecrets(ignore);
      },
      wipeCrossSigning: (wipe) {
        bootstrapper?.wipeCrossSigning(wipe);
      },
    );
  }

  Future<void> unlockOldSsss(String keyOrPassphrase) async {
    final bootstrapper = this.bootstrapper;
    if (bootstrapper == null) {
      return;
    }

    final oldKeys = bootstrapper.oldSsssKeys?.values.toList() ?? const [];
    var unlockedAny = false;

    for (final oldKey in oldKeys) {
      try {
        await oldKey.unlock(keyOrPassphrase: keyOrPassphrase);
        if (oldKey.isUnlocked) {
          unlockedAny = true;
        }
      } catch (_) {
        // Keep recovery-key failures generic so secret material can never be
        // reflected back through SDK error strings.
      }
    }

    if (!unlockedAny) {
      throw Exception(
        'Unable to unlock the existing recovery key.',
      );
    }

    bootstrapper.unlockedSsss();
  }

  void _startDecryptSweepOnce() {
    if (_didStartDecryptSweep) {
      return;
    }

    _didStartDecryptSweep = true;
    unawaited(widget.client.retryDecryptAllRooms());
  }

  void onBootstrapperUdate(Bootstrap bootstrapper) async {
    if (bootstrapper.state == BootstrapState.done) {
      _startDecryptSweepOnce();
      widget.onComplete?.call();
      if (!mounted) {
        return;
      }
    }

    if (widget.mode == MatrixCrossSigningMode.enableBackup ||
        widget.mode == MatrixCrossSigningMode.restoreBackup) {
      switch (bootstrapper.state) {
        case BootstrapState.askUseExistingSsss:
          bootstrapper.useExistingSsss(true);
          break;
        case BootstrapState.askWipeSsss:
          bootstrapper.wipeSsss(false);
          break;
        case BootstrapState.askWipeCrossSigning:
          bootstrapper.wipeCrossSigning(false);
          break;
        case BootstrapState.askWipeOnlineKeyBackup:
          bootstrapper.wipeOnlineKeyBackup(false);
          break;
        default:
          break;
      }
    }

    setState(() {
      state = bootstrapper.state;
    });
  }
}
