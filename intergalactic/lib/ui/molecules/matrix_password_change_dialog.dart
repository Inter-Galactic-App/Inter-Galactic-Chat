import 'package:flutter/material.dart' as m;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum MatrixPasswordChangeResult { changed, signOut }

class MatrixPasswordChangeDialog extends m.StatefulWidget {
  const MatrixPasswordChangeDialog({
    required this.client,
    this.forced = false,
    this.initialCurrentPassword,
    super.key,
  });

  final MatrixClient client;
  final bool forced;
  final String? initialCurrentPassword;

  @override
  m.State<MatrixPasswordChangeDialog> createState() =>
      _MatrixPasswordChangeDialogState();
}

class _MatrixPasswordChangeDialogState
    extends m.State<MatrixPasswordChangeDialog> {
  final _currentPasswordController = m.TextEditingController();
  final _newPasswordController = m.TextEditingController();
  final _confirmPasswordController = m.TextEditingController();

  bool _submitting = false;
  String? _error;

  String get bodyForcedPasswordReset => Intl.message(
        'This account must choose a new password before Inter Galactic can continue. Enter the temporary password you just used, then choose a new password.',
        name: 'bodyForcedPasswordReset',
        desc:
            'Body text explaining the forced password reset screen after login.',
      );

  String get bodyVoluntaryPasswordChange => Intl.message(
        'Change the Matrix account password for this account. Other signed-in sessions will stay signed in.',
        name: 'bodyVoluntaryPasswordChange',
        desc: 'Body text explaining voluntary Matrix password changes.',
      );

  String get placeholderTemporaryPassword => Intl.message(
        'Temporary password',
        name: 'placeholderTemporaryPassword',
        desc: 'Placeholder for a temporary password field.',
      );

  String get placeholderCurrentPassword => Intl.message(
        'Current password',
        name: 'placeholderCurrentPassword',
        desc: 'Placeholder for a current account password field.',
      );

  String get placeholderNewPassword => Intl.message(
        'New password',
        name: 'placeholderNewPassword',
        desc: 'Placeholder for a new password field.',
      );

  String get placeholderConfirmNewPassword => Intl.message(
        'Confirm new password',
        name: 'placeholderConfirmNewPassword',
        desc: 'Placeholder for confirming a new password field.',
      );

  String get promptChangePassword => Intl.message(
        'Change password',
        name: 'promptChangePassword',
        desc: 'Button text to change an account password.',
      );

  String get promptChangingPassword => Intl.message(
        'Changing...',
        name: 'promptChangingPassword',
        desc: 'Button text while an account password is changing.',
      );

  String get promptSignOut => Intl.message(
        'Sign out',
        name: 'promptSignOut',
        desc: 'Button text to sign out from the password reset dialog.',
      );

  String get errorCurrentPasswordRequired => Intl.message(
        'Enter the current password.',
        name: 'errorCurrentPasswordRequired',
        desc: 'Validation error when the current password field is empty.',
      );

  String get errorNewPasswordRequired => Intl.message(
        'Enter a new password.',
        name: 'errorNewPasswordRequired',
        desc: 'Validation error when the new password field is empty.',
      );

  String get errorNewPasswordMismatch => Intl.message(
        'The new passwords do not match.',
        name: 'errorNewPasswordMismatch',
        desc: 'Validation error when new password confirmation does not match.',
      );

  String get errorResetStillRequired => Intl.message(
        'The server still requires a password reset. Please try a different password.',
        name: 'errorResetStillRequired',
        desc:
            'Error shown after changing password if the forced reset marker remains.',
      );

  @override
  void initState() {
    super.initState();
    _currentPasswordController.text = widget.initialCurrentPassword ?? '';
  }

  @override
  void dispose() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
            widget.forced
                ? bodyForcedPasswordReset
                : bodyVoluntaryPasswordChange,
          ),
          const m.SizedBox(height: 16),
          tiamat.TextInput(
            controller: _currentPasswordController,
            obscureText: true,
            placeholder: widget.forced
                ? placeholderTemporaryPassword
                : placeholderCurrentPassword,
          ),
          const m.SizedBox(height: 10),
          tiamat.TextInput(
            controller: _newPasswordController,
            obscureText: true,
            placeholder: placeholderNewPassword,
          ),
          const m.SizedBox(height: 10),
          tiamat.TextInput(
            controller: _confirmPasswordController,
            obscureText: true,
            placeholder: placeholderConfirmNewPassword,
          ),
          if (_error != null) ...[
            const m.SizedBox(height: 10),
            tiamat.Text.error(_error!),
          ],
          const m.SizedBox(height: 16),
          tiamat.Button(
            text: _submitting ? promptChangingPassword : promptChangePassword,
            isLoading: _submitting,
            onTap: _submitting ? null : _submit,
          ),
          if (widget.forced) ...[
            const m.SizedBox(height: 8),
            tiamat.Button.secondary(
              text: promptSignOut,
              onTap: _submitting
                  ? null
                  : () => m.Navigator.of(context)
                      .pop(MatrixPasswordChangeResult.signOut),
            ),
          ] else ...[
            const m.SizedBox(height: 8),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap:
                  _submitting ? null : () => m.Navigator.of(context).pop(null),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmedPassword = _confirmPasswordController.text;

    setState(() {
      _error = null;
    });

    if (currentPassword.isEmpty) {
      setState(() {
        _error = errorCurrentPasswordRequired;
      });
      return;
    }

    if (newPassword.isEmpty) {
      setState(() {
        _error = errorNewPasswordRequired;
      });
      return;
    }

    if (newPassword != confirmedPassword) {
      setState(() {
        _error = errorNewPasswordMismatch;
      });
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.client.changeAccountPassword(
        oldPassword: currentPassword,
        newPassword: newPassword,
        logoutDevices: false,
      );

      if (widget.forced) {
        final status = await widget.client.getPasswordResetStatus();
        if (!status.supported || status.required) {
          if (mounted) {
            setState(() {
              _error = errorResetStillRequired;
            });
          }
          return;
        }
      }

      if (mounted) {
        m.Navigator.of(context).pop(MatrixPasswordChangeResult.changed);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = MatrixClient.passwordChangeFailureMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
