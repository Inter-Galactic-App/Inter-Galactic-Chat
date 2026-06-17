import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:intergalactic/client/account_recovery/account_recovery_api_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tiamat/tiamat.dart' hide Text;
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountRecoverySettingsSection extends StatefulWidget {
  const AccountRecoverySettingsSection({
    required this.client,
    this.apiClient,
    this.includeSection = true,
    this.usePanel = true,
    super.key,
  });

  final MatrixClient client;
  final AccountRecoveryApiClient? apiClient;
  final bool includeSection;
  final bool usePanel;

  @override
  State<AccountRecoverySettingsSection> createState() =>
      _AccountRecoverySettingsSectionState();
}

class _AccountRecoverySettingsSectionState
    extends State<AccountRecoverySettingsSection> {
  late final AccountRecoveryApiClient _apiClient =
      widget.apiClient ?? AccountRecoveryApiClient();
  late final bool _ownsApiClient = widget.apiClient == null;
  AccountRecoveryStatus? _status;
  Object? _error;
  bool _loading = false;
  int _statusLoadEpoch = 0;

  @override
  void initState() {
    super.initState();
    if (AccountRecoveryEligibility.isLocalMatrixClient(widget.client)) {
      _loadStatus();
    }
  }

  @override
  void didUpdateWidget(AccountRecoverySettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _statusLoadEpoch++;
      _status = null;
      _error = null;
      _loading = false;
      if (AccountRecoveryEligibility.isLocalMatrixClient(widget.client)) {
        _loadStatus();
      }
    }
  }

  @override
  void dispose() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!AccountRecoveryEligibility.isLocalMatrixClient(widget.client)) {
      content = _wrapContent(
        SettingsControlRow(
          title: 'Homeserver-controlled recovery',
          description:
              'Password recovery for this account is controlled by its Matrix homeserver. Inter Galactic account recovery is only available for ourgalaxy.space accounts.',
        ),
      );
      return _maybeWrapSection(content);
    }

    final description = _descriptionText();

    content = _wrapContent(
      SettingsControlRow(
        title: 'Recovery codes',
        description: description,
        trailing: tiamat.Button.secondary(
          text: _loading && _status == null ? 'Checking...' : 'Manage',
          isLoading: _loading && _status == null,
          onTap: _loading ? null : _showManagementDialog,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.labelLow(
              'Recovery codes reset your account password. Matrix encrypted history still uses a separate recovery key.',
              softwrap: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              tiamat.Text.error(_failureMessage(_error!)),
            ],
          ],
        ),
      ),
    );
    return _maybeWrapSection(content);
  }

  Widget _wrapContent(Widget child) {
    if (!widget.usePanel) {
      return child;
    }
    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: child,
    );
  }

  Widget _maybeWrapSection(Widget content) {
    if (!widget.includeSection) {
      return content;
    }
    return SettingsSection(
      title: 'Account Recovery',
      children: [content],
    );
  }

  String _descriptionText() {
    final status = _status;
    if (_loading && status == null) {
      return 'Checking recovery status...';
    }
    if (_error != null && status == null) {
      return 'Recovery status could not be loaded.';
    }
    if (status == null) {
      return 'Set up display-once recovery codes for this ourgalaxy.space account.';
    }
    if (status.recoveryCodes.enrolled) {
      return '${status.recoveryCodes.activeCount} active recovery code(s) available.';
    }
    return 'No recovery codes are enrolled for this ourgalaxy.space account.';
  }

  Future<void> _loadStatus() async {
    if (_loading || !mounted) {
      return;
    }
    final loadEpoch = ++_statusLoadEpoch;
    final loadClient = widget.client;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await _apiClient.getStatus(client: loadClient);
      if (mounted &&
          loadEpoch == _statusLoadEpoch &&
          identical(loadClient, widget.client)) {
        setState(() {
          _status = status;
        });
      }
    } catch (error) {
      if (mounted &&
          loadEpoch == _statusLoadEpoch &&
          identical(loadClient, widget.client)) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted &&
          loadEpoch == _statusLoadEpoch &&
          identical(loadClient, widget.client)) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showManagementDialog() async {
    final changed = await AccountRecoveryManagementDialog.show(
      context,
      client: widget.client,
      apiClient: _apiClient,
      initialStatus: _status,
    );
    if (changed == true && mounted) {
      await _loadStatus();
    }
  }
}

class AccountRecoveryManagementDialog extends StatefulWidget {
  const AccountRecoveryManagementDialog({
    required this.client,
    required this.apiClient,
    this.initialStatus,
    super.key,
  });

  final MatrixClient client;
  final AccountRecoveryApiClient apiClient;
  final AccountRecoveryStatus? initialStatus;

  static Future<bool?> show(
    BuildContext context, {
    required MatrixClient client,
    required AccountRecoveryApiClient apiClient,
    AccountRecoveryStatus? initialStatus,
  }) {
    return AdaptiveDialog.show<bool>(
      context,
      title: 'Account Recovery',
      scrollable: true,
      builder: (_) => AccountRecoveryManagementDialog(
        client: client,
        apiClient: apiClient,
        initialStatus: initialStatus,
      ),
    );
  }

  @override
  State<AccountRecoveryManagementDialog> createState() =>
      _AccountRecoveryManagementDialogState();
}

class _AccountRecoveryManagementDialogState
    extends State<AccountRecoveryManagementDialog> {
  AccountRecoveryStatus? _status;
  Object? _error;
  bool _loading = false;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'Account recovery helps you regain password access to this ourgalaxy.space account. It does not unlock Matrix encrypted message history.',
            softwrap: true,
          ),
          const SizedBox(height: 16),
          _statusPanel(),
          const SizedBox(height: 16),
          _recoveryCodeActions(),
          const SizedBox(height: 12),
          _totpActions(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            tiamat.Text.error(_failureMessage(_error!)),
          ],
          const SizedBox(height: 16),
          tiamat.Button.secondary(
            text: 'Close',
            onTap: _busy ? null : () => Navigator.of(context).pop(_changed),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    final status = _status;
    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: SettingsControlRow(
        title: status == null
            ? 'Recovery status'
            : status.recoveryCodes.enrolled
                ? 'Recovery enabled'
                : 'Recovery not set up',
        description: status == null
            ? 'Checking recovery status...'
            : status.recoveryCodes.enrolled
                ? '${status.recoveryCodes.activeCount} recovery code(s) remain. Generated codes are shown only once.'
                : 'Generate recovery codes before you need them. Inter Galactic does not store plaintext copies.',
        trailing: tiamat.Button.secondary(
          text: _loading ? 'Refreshing...' : 'Refresh',
          isLoading: _loading,
          onTap: _loading || _busy ? null : _loadStatus,
        ),
      ),
    );
  }

  Widget _recoveryCodeActions() {
    final enrolled = _status?.recoveryCodes.enrolled == true;
    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: SettingsControlRow(
        title: enrolled ? 'Regenerate recovery codes' : 'Set up recovery codes',
        description: enrolled
            ? 'Regenerating invalidates unused old recovery codes and shows a new set once.'
            : 'Generate one-time recovery codes and save them somewhere safe.',
        trailing: tiamat.Button(
          text: _busy
              ? 'Working...'
              : enrolled
                  ? 'Regenerate'
                  : 'Generate',
          isLoading: _busy,
          onTap: _busy
              ? null
              : enrolled
                  ? _confirmRegenerate
                  : _generateCodes,
        ),
      ),
    );
  }

  Widget _totpActions() {
    final status = _status;
    final available = status?.totp.available == true;
    final enabled = status?.totp.enabled == true;
    final hasRecoveryCodes = status?.recoveryCodes.enrolled == true;

    final title = enabled ? 'Authenticator app enabled' : 'Authenticator app';
    final description = !available
        ? 'Authenticator app recovery is planned, but the server does not advertise it yet.'
        : !hasRecoveryCodes
            ? 'Generate and save recovery codes before enabling authenticator app recovery.'
            : enabled
                ? 'A current authenticator code can reset this account password. Keep recovery codes as a backup.'
                : 'Add an authenticator app as an optional password-recovery factor.';

    final Widget trailing;
    if (!available) {
      trailing = tiamat.Button.secondary(text: 'Planned', onTap: null);
    } else if (!hasRecoveryCodes) {
      trailing = tiamat.Button.secondary(text: 'Needs codes', onTap: null);
    } else if (enabled) {
      trailing = tiamat.Button.danger(
        text: _busy ? 'Working...' : 'Disable',
        isLoading: _busy,
        onTap: _busy ? null : _disableTotp,
      );
    } else {
      trailing = tiamat.Button(
        text: _busy ? 'Working...' : 'Set up',
        isLoading: _busy,
        onTap: _busy ? null : _startTotpSetup,
      );
    }

    return Panel(
      header: null,
      mode: TileType.surfaceContainerLow,
      child: SettingsControlRow(
        title: title,
        description: description,
        trailing: trailing,
      ),
    );
  }

  Future<void> _loadStatus() async {
    if (_loading || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.apiClient.getStatus(client: widget.client);
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmRegenerate() async {
    final confirmed = await AdaptiveDialog.show<bool>(
      context,
      title: 'Regenerate recovery codes',
      dismissible: false,
      builder: (_) => SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.label(
              'Unused old recovery codes will stop working. The new codes are shown only once.',
              softwrap: true,
            ),
            const SizedBox(height: 16),
            tiamat.Button(
              text: 'Regenerate',
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _generateCodes(regenerate: true);
    }
  }

  Future<void> _generateCodes({bool regenerate = false}) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = regenerate
          ? await widget.apiClient.regenerateRecoveryCodes(
              client: widget.client,
            )
          : await widget.apiClient.generateRecoveryCodes(client: widget.client);
      if (result.codes.isEmpty) {
        throw const AccountRecoveryApiException(
          statusCode: 0,
          code: 'empty_recovery_codes',
          message: 'The server did not return recovery codes.',
        );
      }
      if (!mounted) {
        return;
      }
      await RecoveryCodesDisplayDialog.show(context, result.codes);
      _changed = true;
      await _loadStatus();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _startTotpSetup() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final setup = await widget.apiClient.startTotp(client: widget.client);
      if (!setup.available) {
        throw const AccountRecoveryApiException(
          statusCode: 501,
          code: 'totp_not_enabled',
          message: 'Authenticator app recovery is not available yet.',
        );
      }
      if (!setup.hasSetupMaterial) {
        throw const AccountRecoveryApiException(
          statusCode: 0,
          code: 'missing_totp_setup',
          message: 'The server did not return authenticator setup details.',
        );
      }
      if (!mounted) {
        return;
      }
      final changed = await TotpSetupDialog.show(
        context,
        client: widget.client,
        apiClient: widget.apiClient,
        setup: setup,
      );
      if (changed == true) {
        _changed = true;
        await _loadStatus();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _disableTotp() async {
    final disabled = await TotpDisableDialog.show(
      context,
      client: widget.client,
      apiClient: widget.apiClient,
    );
    if (disabled == true) {
      _changed = true;
      await _loadStatus();
    }
  }
}

class TotpSetupDialog extends StatefulWidget {
  const TotpSetupDialog({
    required this.client,
    required this.apiClient,
    required this.setup,
    super.key,
  });

  final MatrixClient client;
  final AccountRecoveryApiClient apiClient;
  final AccountRecoveryTotpSetupStartResult setup;

  static Future<bool?> show(
    BuildContext context, {
    required MatrixClient client,
    required AccountRecoveryApiClient apiClient,
    required AccountRecoveryTotpSetupStartResult setup,
  }) {
    return AdaptiveDialog.show<bool>(
      context,
      title: 'Set up authenticator app',
      dismissible: false,
      scrollable: true,
      builder: (_) => TotpSetupDialog(
        client: client,
        apiClient: apiClient,
        setup: setup,
      ),
    );
  }

  @override
  State<TotpSetupDialog> createState() => _TotpSetupDialogState();
}

class _TotpSetupDialogState extends State<TotpSetupDialog> {
  final _otpController = TextEditingController();
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    final periodSeconds = setup.period.inSeconds;
    return SizedBox(
      width: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'Scan this QR code with your authenticator app, or copy the manual secret. Inter Galactic will not store this setup secret locally.',
            softwrap: true,
          ),
          const SizedBox(height: 16),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: setup.otpauthUri,
                  version: QrVersions.auto,
                  size: 192,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          tiamat.Text.labelLow(
            'Manual secret',
            softwrap: true,
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                setup.manualSecret,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          tiamat.Button.secondary(
            text: _copied ? CommonStrings.promptCopyComplete : 'Copy secret',
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: setup.manualSecret),
              );
              if (mounted) {
                setState(() {
                  _copied = true;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          tiamat.Text.labelLow(
            'Enter the ${setup.digits}-digit code from your authenticator app. Codes refresh every $periodSeconds seconds.',
            softwrap: true,
          ),
          const SizedBox(height: 8),
          tiamat.TextInput(
            controller: _otpController,
            maxLength: setup.digits,
            placeholder: '${setup.digits}-digit code',
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            tiamat.Text.error(_error!),
          ],
          const SizedBox(height: 16),
          tiamat.Button(
            text: _busy ? 'Verifying...' : 'Verify and enable',
            isLoading: _busy,
            onTap: _busy ? null : _verify,
          ),
          const SizedBox(height: 8),
          tiamat.Button.secondary(
            text: CommonStrings.promptCancel,
            onTap: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Future<void> _verify() async {
    if (_busy || !mounted) {
      return;
    }
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() {
        _error = 'Enter the authenticator code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.verifyTotp(
        client: widget.client,
        setupSessionToken: widget.setup.setupSessionToken,
        otp: otp,
      );
      if (!result.available || !result.ok || !result.enabled) {
        throw const AccountRecoveryApiException(
          statusCode: 400,
          code: 'invalid_totp_setup',
          message: 'Authenticator app setup could not be verified.',
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _failureMessage(error);
        });
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

class TotpDisableDialog extends StatefulWidget {
  const TotpDisableDialog({
    required this.client,
    required this.apiClient,
    super.key,
  });

  final MatrixClient client;
  final AccountRecoveryApiClient apiClient;

  static Future<bool?> show(
    BuildContext context, {
    required MatrixClient client,
    required AccountRecoveryApiClient apiClient,
  }) {
    return AdaptiveDialog.show<bool>(
      context,
      title: 'Disable authenticator app',
      dismissible: false,
      builder: (_) => TotpDisableDialog(
        client: client,
        apiClient: apiClient,
      ),
    );
  }

  @override
  State<TotpDisableDialog> createState() => _TotpDisableDialogState();
}

class _TotpDisableDialogState extends State<TotpDisableDialog> {
  final _otpController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'Disabling authenticator app recovery removes this recovery factor. Your recovery codes remain available if any unused codes are left.',
            softwrap: true,
          ),
          const SizedBox(height: 12),
          tiamat.TextInput(
            controller: _otpController,
            placeholder: 'Authenticator code',
            onSubmitted: (_) => _disable(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            tiamat.Text.error(_error!),
          ],
          const SizedBox(height: 16),
          tiamat.Button.critical(
            text: _busy ? 'Disabling...' : 'Disable authenticator',
            isLoading: _busy,
            onTap: _busy ? null : _disable,
          ),
          const SizedBox(height: 8),
          tiamat.Button.secondary(
            text: CommonStrings.promptCancel,
            onTap: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Future<void> _disable() async {
    if (_busy || !mounted) {
      return;
    }
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() {
        _error = 'Enter the authenticator code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.disableTotp(
        client: widget.client,
        otp: otp,
      );
      if (!result.available || !result.ok || result.enabled) {
        throw const AccountRecoveryApiException(
          statusCode: 400,
          code: 'totp_disable_failed',
          message: 'Authenticator app recovery could not be disabled.',
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _failureMessage(error);
        });
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

class RecoveryCodesDisplayDialog extends StatefulWidget {
  const RecoveryCodesDisplayDialog({required this.codes, super.key});

  final List<String> codes;

  static Future<void> show(BuildContext context, List<String> codes) {
    return AdaptiveDialog.show<void>(
      context,
      title: 'Save recovery codes',
      dismissible: false,
      scrollable: true,
      builder: (_) => RecoveryCodesDisplayDialog(codes: codes),
    );
  }

  @override
  State<RecoveryCodesDisplayDialog> createState() =>
      _RecoveryCodesDisplayDialogState();
}

class _RecoveryCodesDisplayDialogState
    extends State<RecoveryCodesDisplayDialog> {
  bool _saved = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final codeText = widget.codes.join('\n');
    return SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'These codes can reset your account password. They are shown only once. Save them somewhere private before closing this dialog.',
            softwrap: true,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                codeText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          tiamat.Button.secondary(
            text: _copied ? CommonStrings.promptCopyComplete : 'Copy codes',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: codeText));
              if (mounted) {
                setState(() {
                  _copied = true;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _saved,
                onChanged: (value) => setState(() {
                  _saved = value == true;
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: tiamat.Text.labelLow(
                  'I saved these codes and understand Inter Galactic will not show them again.',
                  softwrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          tiamat.Button(
            text: CommonStrings.promptDone,
            onTap: _saved ? () => Navigator.of(context).pop() : null,
          ),
        ],
      ),
    );
  }
}

String _failureMessage(Object error) {
  if (error is AccountRecoveryApiException) {
    return error.message;
  }
  return 'Account recovery is unavailable right now.';
}
