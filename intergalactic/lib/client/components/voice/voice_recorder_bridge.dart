import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:flutter/services.dart';

class VoiceRecorderBridge {
  static const MethodChannel _channel =
      MethodChannel('chat.intergalactic.app/voice_recorder');

  static bool get isSupported =>
      BuildConfig.IOS ||
      BuildConfig.ANDROID ||
      PlatformUtils.isIOS ||
      PlatformUtils.isAndroid;

  static Future<void> startRecording() async {
    if (!isSupported) {
      throw UnsupportedError(
          'Voice recording is not supported on this platform.');
    }

    await _channel.invokeMethod<void>('startRecording');
  }

  static Future<PendingFileAttachment?> stopRecording() async {
    if (!isSupported) {
      throw UnsupportedError(
          'Voice recording is not supported on this platform.');
    }

    final result = await _channel.invokeMapMethod<String, Object?>(
      'stopRecording',
    );
    if (result == null) {
      return null;
    }

    final path = result['path'] as String?;
    if (path == null || path.isEmpty) {
      return null;
    }

    final durationMs = result['duration_ms'] as int?;
    final attachment = PendingFileAttachment(
      name: result['name'] as String? ?? 'voice-message.m4a',
      path: path,
      mimeType: result['mime_type'] as String? ?? 'audio/mp4',
      size: result['size'] as int?,
    );

    if (durationMs != null && durationMs > 0) {
      attachment.length = Duration(milliseconds: durationMs);
    }

    return attachment;
  }

  static Future<void> cancelRecording() async {
    if (!isSupported) {
      return;
    }

    await _channel.invokeMethod<void>('cancelRecording');
  }
}
