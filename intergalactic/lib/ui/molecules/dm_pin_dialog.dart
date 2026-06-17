import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/utils/device_security/biometric_auth_manager.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum DmPinDialogMode {
  verify,
  setPin,
  changePin,
}

class DmPinDialogResult {
  const DmPinDialogResult({
    this.currentPin,
    this.newPin,
    this.usedBiometrics = false,
  });

  final String? currentPin;
  final String? newPin;
  final bool usedBiometrics;
}

class DmPinDialog extends StatefulWidget {
  const DmPinDialog({
    required this.mode,
    this.description,
    this.submitLabel = "Continue",
    this.allowBiometricFallback = false,
    this.biometricReason,
    super.key,
  });

  final DmPinDialogMode mode;
  final String? description;
  final String submitLabel;
  final bool allowBiometricFallback;
  final String? biometricReason;

  @override
  State<DmPinDialog> createState() => _DmPinDialogState();
}

class _DmPinDialogState extends State<DmPinDialog> {
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  BiometricAvailability _biometricAvailability = const BiometricAvailability(
    available: false,
    biometryType: "none",
  );
  bool _isAuthenticatingBiometrics = false;

  bool get _isVerifyMode => widget.mode == DmPinDialogMode.verify;
  bool get _isChangeMode => widget.mode == DmPinDialogMode.changePin;
  bool get _requiresCurrentPin => _isVerifyMode || _isChangeMode;
  bool get _requiresNewPin => !_isVerifyMode;
  bool get _pinsMatch => _newPinController.text == _confirmPinController.text;
  bool get _newPinLongEnough => _newPinController.text.length >= 4;

  bool get _canSubmit {
    if (_requiresCurrentPin && _currentPinController.text.length < 4) {
      return false;
    }

    if (!_requiresNewPin) {
      return true;
    }

    return _pinsMatch && _newPinLongEnough;
  }

  bool get _showBiometricOption =>
      widget.allowBiometricFallback &&
      _isVerifyMode &&
      _biometricAvailability.available;

  @override
  void initState() {
    super.initState();
    if (widget.allowBiometricFallback) {
      _loadBiometricAvailability();
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Layout.desktop ? 420 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.description?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: tiamat.Text.labelLow(widget.description!),
            ),
          if (_requiresCurrentPin)
            _buildPinField(
              controller: _currentPinController,
              label: _isVerifyMode ? "PIN" : "Current PIN",
            ),
          if (_requiresCurrentPin && _requiresNewPin) const SizedBox(height: 8),
          if (_requiresNewPin)
            _buildPinField(
              controller: _newPinController,
              label: "New PIN",
            ),
          if (_requiresNewPin) const SizedBox(height: 8),
          if (_requiresNewPin)
            _buildPinField(
              controller: _confirmPinController,
              label: "Confirm PIN",
              errorText: _confirmPinController.text.isNotEmpty && !_pinsMatch
                  ? "PINs do not match"
                  : !_newPinLongEnough && _newPinController.text.isNotEmpty
                      ? "PIN must be at least 4 digits"
                      : null,
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_showBiometricOption)
                tiamat.Button.secondary(
                  text: _isAuthenticatingBiometrics
                      ? "Authenticating..."
                      : _biometricAvailability.promptLabel,
                  onTap: _isAuthenticatingBiometrics
                      ? null
                      : _authenticateWithBiometrics,
                ),
              tiamat.Button.secondary(
                text: "Cancel",
                onTap: () => Navigator.of(context).pop(),
              ),
              tiamat.Button(
                text: widget.submitLabel,
                onTap: _canSubmit
                    ? () {
                        Navigator.of(context).pop(
                          DmPinDialogResult(
                            currentPin: _requiresCurrentPin
                                ? _currentPinController.text
                                : null,
                            newPin: _requiresNewPin
                                ? _newPinController.text
                                : _currentPinController.text,
                            usedBiometrics: false,
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      autofocus: label == "PIN",
      keyboardType: TextInputType.number,
      maxLength: 12,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        counterText: "",
        errorText: errorText,
      ),
    );
  }

  Future<void> _loadBiometricAvailability() async {
    final availability = await BiometricAuthManager.getAvailability();
    if (!mounted) {
      return;
    }

    setState(() {
      _biometricAvailability = availability;
    });
  }

  Future<void> _authenticateWithBiometrics() async {
    setState(() {
      _isAuthenticatingBiometrics = true;
    });

    final success = await BiometricAuthManager.authenticate(
      reason: widget.biometricReason ??
          "Authenticate to unlock locally protected direct messages.",
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isAuthenticatingBiometrics = false;
    });

    if (!success) {
      return;
    }

    Navigator.of(context).pop(
      const DmPinDialogResult(
        usedBiometrics: true,
      ),
    );
  }
}
