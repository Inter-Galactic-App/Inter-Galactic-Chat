import 'dart:async';

import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/encryption_readiness_waiter.dart';
import 'package:flutter/material.dart';

import 'package:matrix/encryption.dart';

enum MatrixCrossSigningMode {
  standard,
  enableBackup,
  restoreBackup,
  resetCrossSigning,
  crossSigningOnly,
}

class MatrixCrossSigningPage extends StatefulWidget {
  const MatrixCrossSigningPage({
    required this.client,
    this.mode = MatrixCrossSigningMode.standard,
    super.key,
    this.initialRecoveryKey,
    this.onComplete,
  });
  final MatrixClient client;
  final MatrixCrossSigningMode mode;
  final String? initialRecoveryKey;
  final Function()? onComplete;

  @override
  State<MatrixCrossSigningPage> createState() => MatrixCrossSigningPageState();
}

class MatrixCrossSigningPageState extends State<MatrixCrossSigningPage> {
  static const String _encryptionUnavailableMessage =
      'End to end encryption could not be prepared for this session. On the '
      'web app, reload the page to reinitialize encryption. If this keeps '
      'happening, sign out and sign back in again.';

  BootstrapState state = BootstrapState.loading;
  Bootstrap? bootstrapper;
  String? unavailableMessage;
  bool _waitingForEncryption = false;
  EncryptionReadinessWaiter? _readinessWaiter;
  bool _didStartDecryptSweep = false;

  @override
  void initState() {
    super.initState();

    if (_encryptionAvailable) {
      _startBootstrap();
      return;
    }

    // Encryption is not attached to the client yet. Rather than showing a
    // one-shot "wait for sync" message that never re-checks (which stranded
    // web users trying to run recovery), wait for it to come up and proceed
    // automatically once it does.
    _waitingForEncryption = true;
    _readinessWaiter = EncryptionReadinessWaiter(
      isReady: () => _encryptionAvailable,
      onReady: () {
        if (!mounted) {
          return;
        }
        _waitingForEncryption = false;
        _startBootstrap();
      },
      onTimeout: () {
        if (!mounted) {
          return;
        }
        Log.w(
          'Matrix cross-signing opened but encryption never became available.',
        );
        setState(() {
          _waitingForEncryption = false;
          unavailableMessage = _encryptionUnavailableMessage;
        });
      },
    )..start();
  }

  @override
  void dispose() {
    _readinessWaiter?.cancel();
    super.dispose();
  }

  bool get _encryptionAvailable {
    final mx = widget.client.getMatrixClient();
    return mx.encryptionEnabled && mx.encryption != null;
  }

  void _startBootstrap() {
    final encryption = widget.client.getMatrixClient().encryption;
    if (encryption == null) {
      setState(() {
        unavailableMessage = _encryptionUnavailableMessage;
      });
      return;
    }

    bootstrapper = encryption.bootstrap(onUpdate: onBootstrapperUdate);
    onBootstrapperUdate(bootstrapper!);
  }

  @override
  Widget build(BuildContext context) {
    if (_waitingForEncryption) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Preparing end-to-end encryption…'),
            ],
          ),
        ),
      );
    }

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
      throw Exception('Unable to unlock the existing recovery key.');
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
