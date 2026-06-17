import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intergalactic/client/components/voip/audio/webrtc_initialization_state.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class IosCallAudioSession {
  IosCallAudioSession._();

  static const MethodChannel _channel =
      MethodChannel('chat.intergalactic.app/call_audio');

  static final webrtc.AppleAudioConfiguration _callAudioConfiguration =
      webrtc.AppleAudioConfiguration(
    appleAudioCategory: webrtc.AppleAudioCategory.playAndRecord,
    appleAudioCategoryOptions: {
      webrtc.AppleAudioCategoryOption.allowBluetooth,
      webrtc.AppleAudioCategoryOption.allowBluetoothA2DP,
      webrtc.AppleAudioCategoryOption.allowAirPlay,
      webrtc.AppleAudioCategoryOption.defaultToSpeaker,
    },
    appleAudioMode: webrtc.AppleAudioMode.default_,
  );

  static bool _loggedAlreadyInitialized = false;

  static Future<bool> prepareForCall({required String source}) async {
    if (!PlatformUtils.isIOS) {
      return true;
    }

    try {
      final snapshot = await _channel.invokeMapMethod<String, dynamic>(
        'prepareForCall',
        <String, dynamic>{'source': source},
      );
      final permission = snapshot?['microphonePermission'];
      if (permission != 'granted') {
        Log.w(
          'iOS call audio preflight did not get microphone permission: '
          '$permission',
          category: LogCategory.livekit,
          source: source,
        );
        return false;
      }

      await _configureWebRtcVoiceProcessingBypass(source);
      await webrtc.AppleNativeAudioManagement.setAppleAudioConfiguration(
        _callAudioConfiguration,
      );
      Log.i(
        'Prepared iOS call audio session '
        'category=${snapshot?['category']} mode=${snapshot?['mode']} '
        'sampleRate=${snapshot?['sampleRate']}',
        category: LogCategory.livekit,
        source: source,
      );
      return true;
    } on MissingPluginException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'iOS call audio preflight channel unavailable; continuing with '
            'WebRTC default audio setup',
        category: LogCategory.livekit,
        source: source,
      );
      return true;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'iOS call audio preflight failed; blocking call audio startup to '
            'avoid native WebRTC audio-session crash',
        category: LogCategory.livekit,
        source: source,
      );
      return false;
    }
  }

  static Future<void> _configureWebRtcVoiceProcessingBypass(
    String source,
  ) async {
    final wasInitialized = wasWebRtcInitialized();
    await livekit.LiveKitClient.initialize(bypassVoiceProcessing: true);
    if (wasInitialized && !_loggedAlreadyInitialized) {
      Log.w(
        'Flutter WebRTC was already initialized before iOS call-audio '
        'preflight; applying runtime voice-processing bypass',
        category: LogCategory.livekit,
        source: source,
      );
      _loggedAlreadyInitialized = true;
    }

    await webrtc.NativeAudioManagement.setIsVoiceProcessingBypassed(true);

    final bypassed =
        await webrtc.NativeAudioManagement.isVoiceProcessingBypassed();
    final enabled =
        await webrtc.NativeAudioManagement.isVoiceProcessingEnabled();
    Log.i(
      'Configured iOS WebRTC voice-processing bypass '
      'factoryPreinitialized=$wasInitialized bypassed=$bypassed '
      'voiceProcessingEnabled=$enabled',
      category: LogCategory.livekit,
      source: source,
    );
  }
}
