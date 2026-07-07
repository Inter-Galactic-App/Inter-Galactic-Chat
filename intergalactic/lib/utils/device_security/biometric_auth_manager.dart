import 'package:flutter/services.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

class BiometricAvailability {
  const BiometricAvailability({
    required this.available,
    required this.biometryType,
  });

  final bool available;
  final String biometryType;

  String get promptLabel {
    return switch (biometryType) {
      "face_id" => "Use Face ID",
      "touch_id" => "Use Touch ID",
      "face_unlock" => "Use Face Unlock",
      "fingerprint" => "Use Fingerprint",
      "iris" => "Use Iris Scan",
      _ => "Use Biometrics",
    };
  }
}

class BiometricAuthManager {
  BiometricAuthManager._();

  static const MethodChannel _channel =
      MethodChannel("chat.intergalactic.app/biometrics");

  static Future<BiometricAvailability> getAvailability() async {
    if (!(PlatformUtils.isIOS || PlatformUtils.isAndroid)) {
      return const BiometricAvailability(
        available: false,
        biometryType: "none",
      );
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        "getBiometricAvailability",
      );

      return BiometricAvailability(
        available: response?["available"] == true,
        biometryType: (response?["biometryType"] as String?) ?? "none",
      );
    } on MissingPluginException {
      return const BiometricAvailability(
        available: false,
        biometryType: "none",
      );
    } on PlatformException {
      return const BiometricAvailability(
        available: false,
        biometryType: "none",
      );
    }
  }

  static Future<bool> authenticate({required String reason}) async {
    if (!(PlatformUtils.isIOS || PlatformUtils.isAndroid)) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        "authenticate",
        <String, dynamic>{
          "reason": reason,
        },
      );
      return result == true;
    } on MissingPluginException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Biometric authentication plugin is unavailable",
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Biometric authentication failed",
      );
      return false;
    }
  }
}
