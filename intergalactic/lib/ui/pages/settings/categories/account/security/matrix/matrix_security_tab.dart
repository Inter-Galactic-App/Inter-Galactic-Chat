import 'dart:async';

import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/molecules/matrix_password_change_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:tiamat/tiamat.dart' hide Text;
import 'package:tiamat/tiamat.dart' as tiamat;

import 'biometric_recovery_key_panel.dart';
import 'cross_signing/cross_signing_page.dart';

class MatrixSecurityTab extends StatefulWidget {
  const MatrixSecurityTab(
    this.client, {
    this.accountRecoveryControls,
    super.key,
  });
  final MatrixClient client;
  final Widget? accountRecoveryControls;
  @override
  State<MatrixSecurityTab> createState() => _MatrixSecurityTabState();
}

class _MatrixSecurityTabState extends State<MatrixSecurityTab> {
  bool crossSigningEnabled = false;
  bool? messageBackupEnabled;
  bool _decryptSweepRunning = false;
  bool _repairRunning = false;
  bool _refreshingTrustStatus = false;
  MatrixE2eeTrustStatus? _trustStatus;
  List<Device>? devices;

  String get labelMatrixCrossSigning => Intl.message(
    "Cross signing",
    desc: "Title label for matrix cross signing",
    name: "labelMatrixCrossSigning",
  );

  String get labelMatrixCrossSigningAndBackup => Intl.message(
    "Cross Signing & Backup",
    desc: "Header label for matrix cross signing and message backup section",
    name: "labelMatrixCrossSigningAndBackup",
  );

  String get labelMatrixAccountSessions => Intl.message(
    "Sessions",
    desc: "Title label for account sessions",
    name: "labelMatrixAccountSessions",
  );

  String get labelMatrixAccountSecurity => Intl.message(
    "Account security",
    desc: "Title label for Matrix account security settings",
    name: "labelMatrixAccountSecurity",
  );

  String get labelMatrixEncryptionHealth => Intl.message(
    "Encryption health",
    desc: "Header label for matrix encryption health status",
    name: "labelMatrixEncryptionHealth",
  );

  String get labelMatrixPassword => Intl.message(
    "Password",
    desc: "Title label for Matrix account password settings",
    name: "labelMatrixPassword",
  );

  String get labelMatrixPasswordExplanation => Intl.message(
    "Change the password for this Matrix account. Other sessions stay signed in.",
    desc: "Explains the Matrix account password change setting",
    name: "labelMatrixPasswordExplanation",
  );

  String get labelMatrixPasswordUnverifiedExplanation => Intl.message(
    "Verify this session before changing your password.",
    desc:
        "Explains why Matrix account password change is disabled for an unverified session",
    name: "labelMatrixPasswordUnverifiedExplanation",
  );

  String get promptMatrixChangePassword => Intl.message(
    "Change",
    desc: "Button text to change the Matrix account password",
    name: "promptMatrixChangePassword",
  );

  String get labelMatrixChangePasswordTitle => Intl.message(
    "Change password",
    desc: "Dialog title for changing the Matrix account password",
    name: "labelMatrixChangePasswordTitle",
  );

  String get labelMatrixPasswordChanged => Intl.message(
    "Password changed",
    desc: "Snackbar text after Matrix account password changed",
    name: "labelMatrixPasswordChanged",
  );

  String get labelMatrixCrossSigningExplanation => Intl.message(
    "Setup to verify and keep track of all your sessions",
    desc: "Explains what matrix cross signing does",
    name: "labelMatrixCrossSigningExplanation",
  );

  String get labelMatrixResetCrossSigningTitle => Intl.message(
    "Reset cross signing",
    desc: "Title for the popup dialog when resetting cross signing",
    name: "labelMatrixResetCrossSigningTitle",
  );

  String get labelMatrixMessageBackup => Intl.message(
    "Message backup",
    desc: "TItle label for matrix message backup settings",
    name: "labelMatrixMessageBackup",
  );

  String get labelMatrixMessageBackupExplanation => Intl.message(
    "Maintains a backup of your message history, in case you lose all your sessions. Your messages will be encrypted before uploading",
    desc: "Explains what matrix message backup does",
    name: "labelMatrixMessageBackupExplanation",
  );

  String get promptSetupMatrixMessageBackup => Intl.message(
    "Setup backup",
    desc: "Text on the button to begin the setup process for message backup",
    name: "promptSetupMatrixMessageBackup",
  );

  String get labelRestoreMatrixBackupTitle => Intl.message(
    "Restore backup",
    desc: "Title of the popup dialog for restoring message backup",
    name: "labelRestoreMatrixBackupTitle",
  );

  String get labelMatrixRunDecryption => Intl.message(
    "Retry message decryption",
    desc: "Title label for manually retrying message decryption",
    name: "labelMatrixRunDecryption",
  );

  String get labelMatrixRunDecryptionExplanation => Intl.message(
    "Try unreadable encrypted messages again with keys this session already has. Use this after verifying, entering a recovery key, or receiving shared room keys.",
    desc: "Explains what manually retrying message decryption does",
    name: "labelMatrixRunDecryptionExplanation",
  );

  String get promptMatrixRunDecryption => Intl.message(
    "Retry decryption",
    desc: "Button text to manually retry message decryption",
    name: "promptMatrixRunDecryption",
  );

  String get promptMatrixDecryptionRunning => Intl.message(
    "Running...",
    desc: "Button text shown while manual message decryption retry is running",
    name: "promptMatrixDecryptionRunning",
  );

  String get labelMatrixDecryptionComplete => Intl.message(
    "Decryption retry complete",
    desc: "Snackbar text after manual message decryption retry completes",
    name: "labelMatrixDecryptionComplete",
  );

  String get labelMatrixRepairEncryption => Intl.message(
    "Repair key delivery",
    desc: "Title label for Matrix encryption repair action",
    name: "labelMatrixRepairEncryption",
  );

  String get labelMatrixRepairEncryptionExplanation => Intl.message(
    "Refresh this session's key state, run a bounded sync, and ask loaded encrypted rooms for missing keys. Use this when unreadable messages seem stuck before keys arrive.",
    desc: "Explains Matrix encryption repair action",
    name: "labelMatrixRepairEncryptionExplanation",
  );

  String get promptMatrixRepairEncryption => Intl.message(
    "Repair delivery",
    desc: "Button text to repair Matrix encryption sessions",
    name: "promptMatrixRepairEncryption",
  );

  String get promptMatrixRepairingEncryption => Intl.message(
    "Repairing...",
    desc: "Button text shown while Matrix encryption repair is running",
    name: "promptMatrixRepairingEncryption",
  );

  String get labelMatrixRepairComplete => Intl.message(
    "Encryption repair complete",
    desc: "Snackbar text after Matrix encryption repair completes",
    name: "labelMatrixRepairComplete",
  );

  String get labelMatrixRepairCompleteRecoveryNeeded => Intl.message(
    "Repair complete. If older messages are still unreadable, enter your recovery key to unlock backed-up message keys.",
    desc:
        "Snackbar text after Matrix encryption repair completes but recovery key is still needed",
    name: "labelMatrixRepairCompleteRecoveryNeeded",
  );

  String get labelMatrixEncryptedMessageTools => Intl.message(
    "Encrypted message tools",
    desc: "Title label for combined encrypted message repair tools",
    name: "labelMatrixEncryptedMessageTools",
  );

  String get labelMatrixEncryptedMessageToolsExplanation => Intl.message(
    "Choose whether to repair missing key delivery or retry unreadable messages with keys already on this session.",
    desc: "Explains the combined encrypted message tools setting",
    name: "labelMatrixEncryptedMessageToolsExplanation",
  );

  String get labelMatrixEncryptedMessageToolsTitle => Intl.message(
    "Choose encrypted message tool",
    desc: "Dialog title for choosing an encrypted message tool",
    name: "labelMatrixEncryptedMessageToolsTitle",
  );

  String get promptMatrixChooseEncryptedMessageTool => Intl.message(
    "Choose",
    desc: "Button text to choose an encrypted message tool",
    name: "promptMatrixChooseEncryptedMessageTool",
  );

  String get promptMatrixEnterRecoveryKey => Intl.message(
    "Enter key",
    desc: "Button text to open the recovery key restore flow",
    name: "promptMatrixEnterRecoveryKey",
  );

  String get labelMatrixRecoveryKeyNeededExplanation => Intl.message(
    "Emoji verification trusts this session for future key sharing, but older encrypted history may still need your recovery key.",
    desc:
        "Explains why a verified Matrix session may still need recovery key entry",
    name: "labelMatrixRecoveryKeyNeededExplanation",
  );

  String get labelMatrixKeySharingPolicy => Intl.message(
    "Compatibility key sharing",
    desc: "Title label for Matrix outbound key-sharing compatibility toggle",
    name: "labelMatrixKeySharingPolicy",
  );

  String get labelMatrixKeySharingPolicyExplanation => Intl.message(
    "Send new encrypted-room keys to non-blocked sessions even if they are not verified yet. Leave this off unless trusted contacts cannot decrypt your new messages.",
    desc: "Explains Matrix outbound key-sharing compatibility toggle",
    name: "labelMatrixKeySharingPolicyExplanation",
  );

  String get promptRefreshMatrixTrustStatus => Intl.message(
    "Refresh",
    desc: "Button text to refresh Matrix encryption trust status",
    name: "promptRefreshMatrixTrustStatus",
  );

  String get promptRefreshingMatrixTrustStatus => Intl.message(
    "Refreshing...",
    desc: "Button text while refreshing Matrix encryption trust status",
    name: "promptRefreshingMatrixTrustStatus",
  );

  @override
  void initState() {
    super.initState();
    checkState();
    getDevices();
    refreshTrustStatus();
  }

  void checkState() {
    setState(() {
      var encryption = widget.client.getMatrixClient().encryption;
      crossSigningEnabled = encryption?.crossSigning.enabled ?? false;
      messageBackupEnabled = encryption?.keyManager.enabled ?? false;
      _trustStatus = widget.client.e2eeTrustStatus;
    });
  }

  void getDevices() async {
    var gotDevices = await widget.client.runWithSessionRepairOnUnknownToken(
      'loading Matrix device list',
      () => widget.client.getMatrixClient().getDevices(),
    );

    gotDevices?.sort(
      (a, b) => (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0),
    );

    if (mounted)
      setState(() {
        devices = gotDevices;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        SettingsSection(
          title: labelMatrixAccountSecurity,
          children: [
            passwordChangePanel(),
            if (widget.accountRecoveryControls != null) ...[
              const _SecurityDivider(),
              widget.accountRecoveryControls!,
            ],
          ],
        ),
        SettingsSection(
          title: labelMatrixEncryptionHealth,
          children: [encryptionHealthPanel()],
        ),
        SettingsSection(
          title: labelMatrixCrossSigningAndBackup,
          children: [crossSigningPanel()],
        ),
        SettingsSection(
          title: labelMatrixAccountSessions,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: sessionsPanel(),
            ),
          ],
        ),
      ],
    );
  }

  Widget passwordChangePanel() {
    final status = _trustStatus ?? widget.client.e2eeTrustStatus;
    final sessionVerified = status.currentDeviceVerified == true;

    return SettingsControlRow(
      title: labelMatrixPassword,
      description: sessionVerified
          ? labelMatrixPasswordExplanation
          : labelMatrixPasswordUnverifiedExplanation,
      trailing: tiamat.Button.secondary(
        text: promptMatrixChangePassword,
        onTap: sessionVerified ? _showPasswordChangeDialog : null,
      ),
    );
  }

  Widget sessionsPanel() {
    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: devices == null
          ? const CircularProgressIndicator()
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: MatrixSession(
                    devices![index],
                    widget.client.getMatrixClient(),
                    appClient: widget.client,
                    onUpdated: () {
                      setState(() {
                        getDevices();
                      });
                    },
                  ),
                );
              },
              itemCount: devices!.length,
            ),
    );
  }

  Widget crossSigningPanel() {
    return Column(
      children: [
        compatibilityKeySharingToggle(),
        const _SecurityDivider(),
        crossSigning(),
        const _SecurityDivider(),
        messageBackup(),
        if (!Layout.desktop) ...[
          const _SecurityDivider(),
          BiometricRecoveryKeySettingsRow(
            client: widget.client,
            onRecoveryKeyUnlocked: (recoveryKey) =>
                _showRestoreBackupDialog(initialRecoveryKey: recoveryKey),
            onStorageChanged: refreshTrustStatus,
          ),
        ],
        const _SecurityDivider(),
        encryptedMessageTools(),
      ],
    );
  }

  Widget encryptionHealthPanel() {
    final status = _trustStatus ?? widget.client.e2eeTrustStatus;
    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: SettingsControlRow(
        title: status.currentDeviceSummary,
        description: status.deviceId == null
            ? "Device ID unavailable"
            : "Device ${status.deviceId} - ${status.ownDeviceCount} session(s), ${status.verifiedOwnDeviceCount} verified, ${status.blockedOwnDeviceCount} blocked.",
        trailing: tiamat.Button.secondary(
          text: _refreshingTrustStatus
              ? promptRefreshingMatrixTrustStatus
              : promptRefreshMatrixTrustStatus,
          onTap: _refreshingTrustStatus ? null : refreshTrustStatus,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: _statusChips(status)),
            if (status.needsRecoveryKeyForHistory) ...[
              const SizedBox(height: 12),
              tiamat.Text.labelLow(labelMatrixRecoveryKeyNeededExplanation),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: tiamat.Button.secondary(
                  text: promptMatrixEnterRecoveryKey,
                  onTap: _showRestoreBackupDialog,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _statusChips(MatrixE2eeTrustStatus status) {
    if (Layout.mobile) {
      return [
        _statusChip(
          label: status.encryptionAvailable
              ? "Encryption ready"
              : "Encryption unavailable",
          compactLabel: status.encryptionAvailable ? "E2EE ready" : "E2EE off",
          tone: status.encryptionAvailable
              ? SettingsStatusTone.accent
              : SettingsStatusTone.danger,
        ),
        _statusChip(
          label: status.keyBackupEnabled ? "Backup on" : "Backup off",
          tone: status.keyBackupEnabled
              ? SettingsStatusTone.accent
              : SettingsStatusTone.warning,
        ),
        _statusChip(
          label: _recoveryStatusLabel(status),
          compactLabel: _mobileRecoveryStatusLabel(status),
          tone: _recoveryStatusTone(status),
        ),
        _statusChip(
          label: status.currentDeviceVerified == true
              ? "This session verified"
              : "This session unverified",
          compactLabel: status.currentDeviceVerified == true
              ? "Verified"
              : "Unverified",
          tone: status.currentDeviceVerified == true
              ? SettingsStatusTone.accent
              : SettingsStatusTone.warning,
        ),
      ];
    }

    return [
      _statusChip(
        label: status.encryptionAvailable
            ? "Encryption ready"
            : "Encryption unavailable",
        compactLabel: status.encryptionAvailable ? "E2EE ready" : "E2EE off",
        tone: status.encryptionAvailable
            ? SettingsStatusTone.accent
            : SettingsStatusTone.danger,
      ),
      _statusChip(
        label: status.crossSigningEnabled
            ? "Cross signing on"
            : "Cross signing off",
        compactLabel: status.crossSigningEnabled ? "Signing on" : "Signing off",
        tone: status.crossSigningEnabled
            ? SettingsStatusTone.accent
            : SettingsStatusTone.warning,
      ),
      _statusChip(
        label: status.keyBackupEnabled ? "Backup on" : "Backup off",
        tone: status.keyBackupEnabled
            ? SettingsStatusTone.accent
            : SettingsStatusTone.warning,
      ),
      _statusChip(
        label: _backupKeyStatusLabel(status),
        compactLabel: _compactBackupKeyStatusLabel(status),
        tone: _backupKeyStatusTone(status),
      ),
      _statusChip(
        label: _recoveryStatusLabel(status),
        compactLabel: _mobileRecoveryStatusLabel(status),
        tone: _recoveryStatusTone(status),
      ),
      _statusChip(
        label: status.currentDeviceVerified == true
            ? "This session verified"
            : "This session unverified",
        compactLabel: status.currentDeviceVerified == true
            ? "Verified"
            : "Unverified",
        tone: status.currentDeviceVerified == true
            ? SettingsStatusTone.accent
            : SettingsStatusTone.warning,
      ),
      _statusChip(
        label: "${status.encryptableOwnDeviceCount} receiving key(s)",
        compactLabel: "${status.encryptableOwnDeviceCount} key(s)",
        tone: status.encryptableOwnDeviceCount > 0
            ? SettingsStatusTone.accent
            : SettingsStatusTone.danger,
      ),
    ];
  }

  SettingsStatusChip _statusChip({
    required String label,
    required SettingsStatusTone tone,
    String? compactLabel,
    String? semanticLabel,
  }) {
    return SettingsStatusChip(
      icon: _statusChipIcon(tone),
      label: label,
      compactLabel: compactLabel,
      semanticLabel: semanticLabel ?? label,
      tone: tone,
    );
  }

  IconData _statusChipIcon(SettingsStatusTone tone) {
    return switch (tone) {
      SettingsStatusTone.accent => Icons.check_circle_outline,
      SettingsStatusTone.warning => Icons.warning_amber_rounded,
      SettingsStatusTone.danger => Icons.error_outline,
      SettingsStatusTone.neutral => Icons.info_outline,
    };
  }

  String _backupKeyStatusLabel(MatrixE2eeTrustStatus status) {
    if (!status.keyBackupEnabled) {
      return "Backup key unavailable";
    }
    if (status.keyBackupCached == true) {
      return "Backup key unlocked";
    }
    if (status.keyBackupCached == false) {
      return "Backup key locked";
    }
    return "Backup key unknown";
  }

  String _compactBackupKeyStatusLabel(MatrixE2eeTrustStatus status) {
    if (!status.keyBackupEnabled) {
      return "No key";
    }
    if (status.keyBackupCached == true) {
      return "Key unlocked";
    }
    if (status.keyBackupCached == false) {
      return "Key locked";
    }
    return "Key unknown";
  }

  SettingsStatusTone _backupKeyStatusTone(MatrixE2eeTrustStatus status) {
    if (!status.keyBackupEnabled) {
      return SettingsStatusTone.warning;
    }
    if (status.keyBackupCached == true) {
      return SettingsStatusTone.accent;
    }
    return SettingsStatusTone.warning;
  }

  String _recoveryStatusLabel(MatrixE2eeTrustStatus status) {
    if (status.cryptoIdentityInitialized == false) {
      return "Recovery not set up";
    }
    if (status.cryptoIdentityConnected == true) {
      return "Recovery connected";
    }
    if (status.cryptoIdentityConnected == false) {
      return "Recovery key needed";
    }
    return "Recovery unknown";
  }

  String _mobileRecoveryStatusLabel(MatrixE2eeTrustStatus status) {
    if (status.cryptoIdentityInitialized == false) {
      return "No recovery";
    }
    if (status.cryptoIdentityConnected == true) {
      return "Recovery OK";
    }
    if (status.cryptoIdentityConnected == false) {
      return "Key needed";
    }
    return "Recovery ?";
  }

  SettingsStatusTone _recoveryStatusTone(MatrixE2eeTrustStatus status) {
    if (status.cryptoIdentityConnected == true) {
      return SettingsStatusTone.accent;
    }
    if (status.cryptoIdentityInitialized == false) {
      return SettingsStatusTone.warning;
    }
    return SettingsStatusTone.warning;
  }

  Widget compatibilityKeySharingToggle() {
    final compatibilityEnabled =
        preferences.matrixKeySharingPolicy.value ==
        MatrixE2eeDiagnostics.policyAllNonBlocked;
    return SettingsControlRow(
      title: labelMatrixKeySharingPolicy,
      description: labelMatrixKeySharingPolicyExplanation,
      semanticValue: settingsToggleStateLabel(compatibilityEnabled),
      toggled: compatibilityEnabled,
      semanticOnTapHint: compatibilityEnabled ? "Turn off" : "Turn on",
      onActivate: () => _setCompatibilityKeySharing(!compatibilityEnabled),
      excludeChildSemantics: true,
      trailing: SettingsSwitchStateLabel(
        value: compatibilityEnabled,
        child: ExcludeFocus(
          child: tiamat.Switch(
            state: compatibilityEnabled,
            onChanged: _setCompatibilityKeySharing,
          ),
        ),
      ),
    );
  }

  Future<void> _setCompatibilityKeySharing(bool enabled) async {
    await preferences.matrixKeySharingPolicy.set(
      enabled
          ? MatrixE2eeDiagnostics.policyAllNonBlocked
          : MatrixE2eeDiagnostics.policyCrossVerifiedIfEnabled,
    );
    widget.client.applyConfiguredKeySharingPolicy();
    if (mounted) {
      setState(() {
        _trustStatus = widget.client.e2eeTrustStatus;
      });
    }
  }

  Widget crossSigning() {
    return SettingsControlRow(
      title: labelMatrixCrossSigning,
      description: labelMatrixCrossSigningExplanation,
      trailing: crossSigningEnabled
          ? tiamat.Button.danger(
              text: CommonStrings.promptReset,
              onTap: () => AdaptiveDialog.show(
                context,
                builder: (_) => MatrixCrossSigningPage(
                  client: widget.client,
                  mode: MatrixCrossSigningMode.resetCrossSigning,
                  onComplete: checkState,
                ),
                dismissible: true,
                title: labelMatrixResetCrossSigningTitle,
              ),
            )
          : tiamat.Button.secondary(
              text: CommonStrings.promptEnable,
              onTap: () => AdaptiveDialog.show(
                context,
                builder: (_) => MatrixCrossSigningPage(
                  client: widget.client,
                  onComplete: checkState,
                ),
                dismissible: true,
                title: labelMatrixCrossSigning,
              ),
            ),
    );
  }

  Widget messageBackup() {
    return SettingsControlRow(
      title: labelMatrixMessageBackup,
      description: labelMatrixMessageBackupExplanation,
      trailing: messageBackupEnabled == true
          ? tiamat.Button.secondary(
              text: CommonStrings.promptRestore,
              onTap: _showRestoreBackupDialog,
            )
          : messageBackupEnabled == false
          ? tiamat.Button.secondary(
              text: CommonStrings.promptEnable,
              onTap: () => AdaptiveDialog.show(
                context,
                builder: (_) => MatrixCrossSigningPage(
                  client: widget.client,
                  onComplete: checkState,
                  mode: MatrixCrossSigningMode.enableBackup,
                ),
                dismissible: true,
                title: promptSetupMatrixMessageBackup,
              ),
            )
          : const CircularProgressIndicator(),
    );
  }

  Future<void> _showRestoreBackupDialog({String? initialRecoveryKey}) async {
    await AdaptiveDialog.show(
      context,
      builder: (_) => MatrixCrossSigningPage(
        client: widget.client,
        onComplete: checkState,
        mode: MatrixCrossSigningMode.restoreBackup,
        initialRecoveryKey: initialRecoveryKey,
      ),
      dismissible: true,
      title: labelRestoreMatrixBackupTitle,
    );
    if (mounted) {
      await refreshTrustStatus();
    }
  }

  Future<void> _showPasswordChangeDialog() async {
    final result = await AdaptiveDialog.show<MatrixPasswordChangeResult>(
      context,
      builder: (_) => MatrixPasswordChangeDialog(client: widget.client),
      dismissible: true,
      scrollable: true,
      title: labelMatrixChangePasswordTitle,
    );

    if (result == MatrixPasswordChangeResult.changed && mounted) {
      await _showMatrixSecurityFeedback(
        title: labelMatrixChangePasswordTitle,
        message: labelMatrixPasswordChanged,
      );
    }
  }

  Widget encryptedMessageTools() {
    final encryptionEnabled = widget.client.getMatrixClient().encryptionEnabled;
    return SettingsControlRow(
      title: labelMatrixEncryptedMessageTools,
      description: labelMatrixEncryptedMessageToolsExplanation,
      trailing: tiamat.Button.secondary(
        text: _encryptedMessageToolsButtonText(),
        onTap: encryptionEnabled && !_repairRunning && !_decryptSweepRunning
            ? _showEncryptedMessageToolsDialog
            : null,
      ),
    );
  }

  String _encryptedMessageToolsButtonText() {
    if (_repairRunning) {
      return promptMatrixRepairingEncryption;
    }
    if (_decryptSweepRunning) {
      return promptMatrixDecryptionRunning;
    }
    return promptMatrixChooseEncryptedMessageTool;
  }

  Future<void> _showEncryptedMessageToolsDialog() async {
    if (_repairRunning || _decryptSweepRunning) {
      return;
    }
    await AdaptiveDialog.show<void>(
      context,
      title: labelMatrixEncryptedMessageToolsTitle,
      scrollable: true,
      builder: (dialogContext) => SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.label(
              'These tools fix different encrypted-message problems. Start with repair when keys are missing; retry decryption when keys should already be available.',
              softwrap: true,
            ),
            const SizedBox(height: 16),
            SettingsActionChoiceCard(
              icon: Icons.key_outlined,
              title: labelMatrixRepairEncryption,
              description: labelMatrixRepairEncryptionExplanation,
              detail:
                  'This can refresh key delivery and request missing room keys. It cannot unlock backed-up history without your recovery key.',
              tone: SettingsStatusTone.warning,
              action: tiamat.Button.secondary(
                text: promptMatrixRepairEncryption,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_runEncryptionRepair());
                },
              ),
            ),
            const SizedBox(height: 12),
            SettingsActionChoiceCard(
              icon: Icons.refresh_rounded,
              title: labelMatrixRunDecryption,
              description: labelMatrixRunDecryptionExplanation,
              detail:
                  'This does not fetch more keys. It retries unreadable messages using the keys already stored on this session.',
              tone: SettingsStatusTone.accent,
              action: tiamat.Button.secondary(
                text: promptMatrixRunDecryption,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_runManualDecryptSweep());
                },
              ),
            ),
            const SizedBox(height: 16),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMatrixSecurityFeedback({
    required String title,
    required String message,
    String? actionLabel,
    FutureOr<void> Function()? onAction,
  }) async {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final scaffold = Scaffold.maybeOf(context);
    final action = onAction;
    final label = actionLabel;
    if (messenger != null && scaffold != null) {
      final snackBarAction = label != null && action != null
          ? SnackBarAction(
              label: label,
              onPressed: () {
                if (mounted) {
                  unawaited(_runMatrixSecurityFeedbackAction(action));
                }
              },
            )
          : null;
      messenger.showSnackBar(
        SnackBar(content: Text(message), action: snackBarAction),
      );
      return;
    }

    final runAction = await AdaptiveDialog.show<bool>(
      context,
      title: title,
      scrollable: true,
      builder: (dialogContext) => SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Text.label(message, softwrap: true),
            const SizedBox(height: 16),
            if (label != null && action != null) ...[
              tiamat.Button.secondary(
                text: label,
                onTap: () => Navigator.of(dialogContext).pop(true),
              ),
              const SizedBox(height: 8),
            ],
            tiamat.Button.secondary(
              text: CommonStrings.promptDone,
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
          ],
        ),
      ),
    );

    if (runAction == true && mounted && action != null) {
      await action();
    }
  }

  Future<void> _runMatrixSecurityFeedbackAction(
    FutureOr<void> Function() action,
  ) async {
    try {
      await Future<void>.sync(action);
    } catch (error, trace) {
      if (mounted) {
        AdaptiveDialog.showError(context, error, trace);
      }
    }
  }

  Future<void> refreshTrustStatus() async {
    if (_refreshingTrustStatus) {
      return;
    }

    setState(() {
      _refreshingTrustStatus = true;
    });

    try {
      await widget.client.refreshE2eeTrustStatus();
      if (!mounted) {
        return;
      }
      checkState();
    } finally {
      if (mounted) {
        setState(() {
          _refreshingTrustStatus = false;
        });
      }
    }
  }

  Future<void> _runEncryptionRepair() async {
    if (_repairRunning) {
      return;
    }

    setState(() {
      _repairRunning = true;
    });

    try {
      await widget.client.repairEncryptionSessionsAndRetry();
      if (!mounted) {
        return;
      }
      await refreshTrustStatus();
      if (!mounted) {
        return;
      }
      final status = _trustStatus ?? widget.client.e2eeTrustStatus;
      await _showMatrixSecurityFeedback(
        title: labelMatrixRepairEncryption,
        message: status.needsRecoveryKeyForHistory
            ? labelMatrixRepairCompleteRecoveryNeeded
            : labelMatrixRepairComplete,
        actionLabel: status.needsRecoveryKeyForHistory
            ? promptMatrixEnterRecoveryKey
            : null,
        onAction: status.needsRecoveryKeyForHistory
            ? _showRestoreBackupDialog
            : null,
      );
    } catch (error, trace) {
      if (mounted) {
        AdaptiveDialog.showError(context, error, trace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _repairRunning = false;
        });
      }
    }
  }

  Future<void> _runManualDecryptSweep() async {
    if (_decryptSweepRunning) {
      return;
    }

    setState(() {
      _decryptSweepRunning = true;
    });

    try {
      await widget.client.retryDecryptAllRooms();
      if (!mounted) {
        return;
      }
      await _showMatrixSecurityFeedback(
        title: labelMatrixRunDecryption,
        message: labelMatrixDecryptionComplete,
      );
    } catch (error, trace) {
      if (mounted) {
        AdaptiveDialog.showError(context, error, trace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _decryptSweepRunning = false;
        });
      }
    }
  }
}

class _SecurityDivider extends StatelessWidget {
  const _SecurityDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.72),
      height: 1,
      thickness: 1,
    );
  }
}
