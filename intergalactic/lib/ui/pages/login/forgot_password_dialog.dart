import 'package:flutter/material.dart' hide Text;
import 'package:intergalactic/client/account_recovery/account_recovery_api_client.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:url_launcher/url_launcher.dart';

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({
    required this.homeserverInput,
    this.apiClient,
    super.key,
  });

  final String homeserverInput;
  final AccountRecoveryApiClient? apiClient;

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  late final AccountRecoveryApiClient _apiClient =
      widget.apiClient ?? AccountRecoveryApiClient();
  late final bool _ownsApiClient = widget.apiClient == null;
  late _ForgotPasswordStep _step =
      AccountRecoveryEligibility.isAllowedHomeserverInput(
              widget.homeserverInput)
          ? _ForgotPasswordStep.account
          : _ForgotPasswordStep.external;

  final _usernameController = TextEditingController();
  final _recoveryCodeController = TextEditingController();
  final _totpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _resetUsername;
  String? _resetSessionToken;

  @override
  void dispose() {
    _usernameController.dispose();
    _recoveryCodeController.dispose();
    _totpController.dispose();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    if (_ownsApiClient) {
      _apiClient.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStep(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            tiamat.Text.error(_error!),
          ],
        ],
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      _ForgotPasswordStep.external => _externalRecovery(),
      _ForgotPasswordStep.account => _accountStep(),
      _ForgotPasswordStep.factor => _factorStep(),
      _ForgotPasswordStep.code => _codeStep(),
      _ForgotPasswordStep.totp => _totpStep(),
      _ForgotPasswordStep.password => _passwordStep(),
      _ForgotPasswordStep.complete => _completeStep(),
    };
  }

  Widget _externalRecovery() {
    final homeserver = AccountRecoveryEligibility.recoveryDisplayName(
      widget.homeserverInput,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Password recovery for $homeserver is controlled by that Matrix homeserver. Use that homeserver\'s recovery process for password help.',
          softwrap: true,
        ),
        const SizedBox(height: 16),
        tiamat.Button.secondary(
          text: 'Open homeserver site',
          onTap: _openHomeserverSite,
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _accountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Enter your account username to start password recovery. The server gives the same response whether or not an account can be recovered.',
          softwrap: true,
        ),
        const SizedBox(height: 12),
        tiamat.TextInput(
          controller: _usernameController,
          placeholder: 'Username or Matrix user ID',
          onSubmitted: (_) => _startReset(),
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: _busy ? 'Starting...' : CommonStrings.promptContinue,
          isLoading: _busy,
          onTap: _busy ? null : _startReset,
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: CommonStrings.promptCancel,
          onTap: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Enter one recovery code for this exact account. Codes are one-time use.',
          softwrap: true,
        ),
        const SizedBox(height: 12),
        tiamat.TextInput(
          controller: _recoveryCodeController,
          placeholder: 'IG-XXXX-XXXX-XXXX',
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: _busy ? 'Verifying...' : 'Verify code',
          isLoading: _busy,
          onTap: _busy ? null : _verifyCode,
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: CommonStrings.promptBack,
          onTap: _busy
              ? null
              : () => setState(() {
                    _step = _ForgotPasswordStep.factor;
                    _error = null;
                  }),
        ),
      ],
    );
  }

  Widget _factorStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Choose a recovery method for this account. The server will reject unavailable or invalid factors without revealing account details.',
          softwrap: true,
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: 'Use recovery code',
          onTap: _busy
              ? null
              : () => setState(() {
                    _resetSessionToken = null;
                    _step = _ForgotPasswordStep.code;
                    _error = null;
                  }),
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: 'Use authenticator app',
          onTap: _busy
              ? null
              : () => setState(() {
                    _step = _ForgotPasswordStep.totp;
                    _error = null;
                  }),
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: CommonStrings.promptBack,
          onTap: _busy
              ? null
              : () => setState(() {
                    _resetUsername = null;
                    _resetSessionToken = null;
                    _step = _ForgotPasswordStep.account;
                    _error = null;
                  }),
        ),
      ],
    );
  }

  Widget _totpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Enter the current code from the authenticator app you set up for this account.',
          softwrap: true,
        ),
        const SizedBox(height: 12),
        tiamat.TextInput(
          controller: _totpController,
          maxLength: 6,
          placeholder: '6-digit code',
          onSubmitted: (_) => _verifyTotp(),
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: _busy ? 'Verifying...' : 'Verify authenticator',
          isLoading: _busy,
          onTap: _busy ? null : _verifyTotp,
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: CommonStrings.promptBack,
          onTap: _busy
              ? null
              : () => setState(() {
                    _step = _ForgotPasswordStep.factor;
                    _error = null;
                  }),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Choose a new Matrix account password. Existing sessions may be logged out. Encrypted history may still need your Matrix recovery key after you sign in.',
          softwrap: true,
        ),
        const SizedBox(height: 12),
        tiamat.TextInput(
          controller: _newPasswordController,
          obscureText: true,
          placeholder: 'New password',
        ),
        const SizedBox(height: 10),
        tiamat.TextInput(
          controller: _confirmPasswordController,
          obscureText: true,
          placeholder: 'Confirm new password',
          onSubmitted: (_) => _completeReset(),
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: _busy ? 'Resetting...' : 'Reset password',
          isLoading: _busy,
          onTap: _busy ? null : _completeReset,
        ),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: CommonStrings.promptBack,
          onTap: _busy
              ? null
              : () => setState(() {
                    _step = _ForgotPasswordStep.factor;
                    _error = null;
                  }),
        ),
      ],
    );
  }

  Widget _completeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.label(
          'Password reset complete. Sign in with the new password. If encrypted messages are unreadable, use Matrix encrypted history recovery after login.',
          softwrap: true,
        ),
        const SizedBox(height: 16),
        tiamat.Button(
          text: CommonStrings.promptDone,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  Future<void> _startReset() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _error = 'Enter your username.';
      });
      return;
    }

    await _run(() async {
      await _apiClient.startReset(username: username);
      if (mounted) {
        setState(() {
          _resetUsername = username;
          _resetSessionToken = null;
          _usernameController.text = username;
          _step = _ForgotPasswordStep.factor;
          _error = null;
        });
      }
    });
  }

  Future<void> _verifyCode() async {
    final username = (_resetUsername ?? _usernameController.text).trim();
    final code = _recoveryCodeController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _error = 'Enter your username again.';
        _step = _ForgotPasswordStep.account;
      });
      return;
    }
    if (code.isEmpty) {
      setState(() {
        _error = 'Enter a recovery code.';
      });
      return;
    }

    await _run(() async {
      final result = await _apiClient.verifyReset(
        username: username,
        recoveryCode: code,
      );
      if (!result.verified || result.resetSessionToken.isEmpty) {
        throw const AccountRecoveryApiException(
          statusCode: 400,
          code: 'invalid_recovery_factor',
          message: 'Recovery verification failed.',
        );
      }
      if (mounted) {
        setState(() {
          _resetSessionToken = result.resetSessionToken;
          _recoveryCodeController.clear();
          _step = _ForgotPasswordStep.password;
          _error = null;
        });
      }
    });
  }

  Future<void> _verifyTotp() async {
    final username = (_resetUsername ?? _usernameController.text).trim();
    final otp = _totpController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _error = 'Enter your username again.';
        _step = _ForgotPasswordStep.account;
      });
      return;
    }
    if (otp.isEmpty) {
      setState(() {
        _error = 'Enter the authenticator code.';
      });
      return;
    }

    await _run(() async {
      final result = await _apiClient.verifyResetWithTotp(
        username: username,
        otp: otp,
      );
      if (!result.verified || result.resetSessionToken.isEmpty) {
        throw const AccountRecoveryApiException(
          statusCode: 400,
          code: 'invalid_recovery_factor',
          message: 'Recovery verification failed.',
        );
      }
      if (mounted) {
        setState(() {
          _resetSessionToken = result.resetSessionToken;
          _totpController.clear();
          _step = _ForgotPasswordStep.password;
          _error = null;
        });
      }
    });
  }

  Future<void> _completeReset() async {
    final token = _resetSessionToken;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Recovery session expired. Verify a recovery code again.';
        _step = _ForgotPasswordStep.code;
      });
      return;
    }
    if (newPassword.isEmpty) {
      setState(() {
        _error = 'Enter a new password.';
      });
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() {
        _error = 'The new passwords do not match.';
      });
      return;
    }

    await _run(() async {
      final result = await _apiClient.completeReset(
        resetSessionToken: token,
        newPassword: newPassword,
      );
      if (!result.ok) {
        throw const AccountRecoveryApiException(
          statusCode: 500,
          code: 'password_reset_failed',
          message: 'Password reset failed.',
        );
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        setState(() {
          _resetUsername = null;
          _resetSessionToken = null;
          _recoveryCodeController.clear();
          _totpController.clear();
          _step = _ForgotPasswordStep.complete;
          _error = null;
        });
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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

  Future<void> _openHomeserverSite() async {
    final homeserver = AccountRecoveryEligibility.recoveryDisplayName(
      widget.homeserverInput,
    );
    if (homeserver.trim().isEmpty) {
      return;
    }
    await launchUrl(
      Uri.https(homeserver),
      mode: LaunchMode.externalApplication,
    );
  }
}

enum _ForgotPasswordStep {
  external,
  account,
  factor,
  code,
  totp,
  password,
  complete,
}

String _failureMessage(Object error) {
  if (error is AccountRecoveryApiException) {
    return error.message;
  }
  return 'Account recovery is unavailable right now.';
}
