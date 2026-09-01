import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intergalactic/client/components/voip/audio/webrtc_initialization_state.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class IosCallAudioSession {
  IosCallAudioSession._();

  static const MethodChannel _channel = MethodChannel(
    'chat.intergalactic.app/call_audio',
  );

  /// Whether iOS calls should use Apple's native voice-processing audio unit
  /// (AEC/NS/AGC) instead of the historical full bypass. Gated behind an
  /// opt-in preference because enabling voice processing was the source of the
  /// BUG-168 `setVoiceProcessingEnabled` call-entry crash.
  static bool get nativeVoiceProcessingEnabled =>
      PlatformUtils.isIOS && preferences.voipIosNativeVoiceProcessing.value;

  /// The bypass decision used at every call-audio capture site so group and DM
  /// calls stay consistent: bypass on iOS unless native voice processing is
  /// explicitly enabled.
  static bool get shouldBypassVoiceProcessing =>
      PlatformUtils.isIOS && !nativeVoiceProcessingEnabled;

  static webrtc.AppleAudioConfiguration _callAudioConfiguration({
    required bool nativeEnabled,
  }) => webrtc.AppleAudioConfiguration(
    appleAudioCategory: webrtc.AppleAudioCategory.playAndRecord,
    appleAudioCategoryOptions: {
      webrtc.AppleAudioCategoryOption.allowBluetooth,
      webrtc.AppleAudioCategoryOption.allowBluetoothA2DP,
      webrtc.AppleAudioCategoryOption.allowAirPlay,
      webrtc.AppleAudioCategoryOption.defaultToSpeaker,
    },
    // `.voiceChat` engages the AVAudioSession voice-processing path when we
    // enable native suppression; `.default_` preserves the crash-safe bypass
    // baseline. (BUG-168 crashed under `.videoChat`.)
    appleAudioMode: nativeEnabled
        ? webrtc.AppleAudioMode.voiceChat
        : webrtc.AppleAudioMode.default_,
  );

  static bool _loggedAlreadyInitialized = false;

  static Future<void> configureStartupVoiceProcessing() async {
    if (!PlatformUtils.isIOS) {
      return;
    }

    try {
      await ensureVoiceProcessingConfigured(source: 'startup');
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'iOS startup WebRTC voice-processing configuration failed; call '
            'preflight will retry before joining',
        category: LogCategory.livekit,
        source: 'startup',
      );
    }
  }

  /// [forceBypassVoiceProcessing] keeps the crash-safe bypass regardless of the
  /// [nativeVoiceProcessingEnabled] flag. Direct (1:1) calls set this because
  /// the native flutter_webrtc peer-connection audio path still aborts in
  /// `AVAudioIONode setVoiceProcessingEnabled` (BUG-168) even when the ADM
  /// bypass is requested; only the LiveKit/group path is safe with native
  /// voice processing enabled.
  static Future<bool> prepareForCall({
    required String source,
    bool forceBypassVoiceProcessing = false,
  }) async {
    if (!PlatformUtils.isIOS) {
      return true;
    }

    try {
      await ensureVoiceProcessingConfigured(
        source: source,
        forceBypassVoiceProcessing: forceBypassVoiceProcessing,
      );
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

      await webrtc.AppleNativeAudioManagement.setAppleAudioConfiguration(
        _callAudioConfiguration(
          nativeEnabled:
              nativeVoiceProcessingEnabled && !forceBypassVoiceProcessing,
        ),
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

  static Future<void> ensureVoiceProcessingConfigured({
    required String source,
    bool forceBypassVoiceProcessing = false,
  }) async {
    if (!PlatformUtils.isIOS) {
      return;
    }

    final bypass = forceBypassVoiceProcessing || shouldBypassVoiceProcessing;
    final wasInitialized = wasWebRtcInitialized();
    if (!wasInitialized) {
      await livekit.LiveKitClient.initialize(bypassVoiceProcessing: bypass);
    } else if (!_loggedAlreadyInitialized) {
      Log.w(
        'Flutter WebRTC was already initialized before iOS call-audio '
        'preflight; applying runtime voice-processing configuration',
        category: LogCategory.livekit,
        source: source,
      );
      _loggedAlreadyInitialized = true;
    }

    await webrtc.NativeAudioManagement.setIsVoiceProcessingBypassed(bypass);

    final bypassed =
        await webrtc.NativeAudioManagement.isVoiceProcessingBypassed();
    final enabled =
        await webrtc.NativeAudioManagement.isVoiceProcessingEnabled();
    Log.i(
      'Configured iOS WebRTC voice processing '
      'intent=${bypass ? 'bypassed' : 'native-enabled'} '
      'factoryPreinitialized=$wasInitialized bypassed=$bypassed '
      'voiceProcessingEnabled=$enabled',
      category: LogCategory.livekit,
      source: source,
    );
  }
}
