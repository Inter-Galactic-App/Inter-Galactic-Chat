import 'package:collection/collection.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class WebrtcDefaultDevices {
  static Future<webrtc.MediaStream?> getDefaultMicrophone({
    bool bypassVoiceProcessing = false,
  }) async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    final devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput")
        .toList();

    final inputVolume = _normalizedMicrophoneVolume();
    Map<String, dynamic> constraints =
        NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(
          inputVolume: inputVolume,
          bypassVoiceProcessing: bypassVoiceProcessing,
        );

    if (preferences.voipDefaultAudioInput.value != null) {
      final pickedDevice = await _resolveSavedDevice(
        devices,
        preferences.voipDefaultAudioInput.value,
        preferences.voipDefaultAudioInput.set,
      );

      if (pickedDevice != null) {
        print(
          "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})",
        );
        constraints =
            NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(
              deviceId: pickedDevice.deviceId,
              inputVolume: inputVolume,
              bypassVoiceProcessing: bypassVoiceProcessing,
            );

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    } else {
      print("No default device set picking first");
    }

    Log.i(
      "${NoiseSuppressionCaptureProfile.callAudioInstrumentationSummary(callType: 'direct-native', bypassVoiceProcessing: bypassVoiceProcessing)} "
      "constraints=${NoiseSuppressionCaptureProfile.describeConstraints(constraints)}",
      category: LogCategory.livekit,
      source: 'webrtc-default-devices',
    );
    final stream = await webrtc.navigator.mediaDevices.getUserMedia({
      "audio": constraints,
    });
    NoiseSuppressionService.instance.scheduleHealthRefresh();
    return stream;
  }

  static Future<String?> getDefaultMicrophoneId() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    final devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput")
        .toList();

    if (preferences.voipDefaultAudioInput.value == null) return null;

    return (await _resolveSavedDevice(
      devices,
      preferences.voipDefaultAudioInput.value,
      preferences.voipDefaultAudioInput.set,
    ))?.deviceId;
  }

  static Future<webrtc.MediaDeviceInfo?> getDefaultCamera() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    final devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "videoinput")
        .toList();

    if (preferences.voipDefaultVideoInput.value == null) return null;

    return _resolveSavedDevice(
      devices,
      preferences.voipDefaultVideoInput.value,
      preferences.voipDefaultVideoInput.set,
    );
  }

  static Future<void> selectInputDevice() async {
    final devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput")
        .toList();

    if (preferences.voipDefaultAudioInput.value != null) {
      final pickedDevice = await _resolveSavedDevice(
        devices,
        preferences.voipDefaultAudioInput.value,
        preferences.voipDefaultAudioInput.set,
      );

      if (pickedDevice != null) {
        print(
          "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})",
        );

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    }
  }

  static Future<void> selectOutputDevice({
    bool preferSpeakerphoneOnMobile = false,
  }) async {
    final savedOutput = preferences.voipDefaultAudioOutput.value;
    if (savedOutput == null || savedOutput.isEmpty) {
      if (preferSpeakerphoneOnMobile) {
        await _preferSpeakerphoneOnMobile();
      }
      return;
    }

    final devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audiooutput")
        .toList();

    final device = await _resolveSavedDevice(
      devices,
      savedOutput,
      preferences.voipDefaultAudioOutput.set,
    );

    if (device != null) {
      Log.i("Setting webrtc output to: ${device.label}  (${device.deviceId})");
      try {
        await webrtc.Helper.selectAudioOutput(device.deviceId);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              "Failed to select saved call audio output device; "
              "continuing with platform default route",
          category: LogCategory.webrtc,
          source: "webrtc-default-devices",
        );
        if (preferSpeakerphoneOnMobile) {
          await _preferSpeakerphoneOnMobile();
        }
      }
      return;
    }

    if (preferSpeakerphoneOnMobile) {
      await _preferSpeakerphoneOnMobile();
    }
  }

  static Future<void> selectCallOutputDevice({required String source}) async {
    try {
      await selectOutputDevice(preferSpeakerphoneOnMobile: true);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            "Failed to select call output device; continuing with system route",
        category: LogCategory.webrtc,
        source: source,
      );
    }
  }

  static Future<void> _preferSpeakerphoneOnMobile() async {
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) {
      return;
    }

    Log.i(
      "Selecting mobile speakerphone output route",
      category: LogCategory.webrtc,
      source: "webrtc-default-devices",
    );
    await webrtc.Helper.setSpeakerphoneOnButPreferBluetooth();
  }

  static Future<webrtc.MediaDeviceInfo?> _resolveSavedDevice(
    List<webrtc.MediaDeviceInfo> devices,
    String? savedValue,
    Future<void> Function(String? value) updatePreference,
  ) async {
    if (savedValue == null || savedValue.isEmpty) {
      return null;
    }

    final deviceIdMatch = devices.firstWhereOrNull(
      (device) => device.deviceId == savedValue,
    );
    if (deviceIdMatch != null) {
      return deviceIdMatch;
    }

    final legacyLabelMatch = devices.firstWhereOrNull(
      (device) => device.label == savedValue,
    );
    if (legacyLabelMatch != null) {
      await updatePreference(legacyLabelMatch.deviceId);
      return legacyLabelMatch;
    }

    Log.w("Preferred WebRTC device was not found; clearing it.");
    await updatePreference(null);
    return null;
  }

  static double _normalizedMicrophoneVolume() {
    return NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
      preferences.voipMicrophoneVolume.value,
    );
  }
}
