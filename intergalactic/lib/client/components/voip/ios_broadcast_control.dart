import 'package:flutter/services.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

class IosBroadcastControl {
  IosBroadcastControl._();

  static const MethodChannel _channel = MethodChannel('livekit_client');

  static Future<bool> requestActivation() async {
    if (!PlatformUtils.isIOS) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'broadcastRequestActivation',
        <String, dynamic>{},
      );
      Log.i(
        'Requested iOS ReplayKit broadcast picker '
        'result=${result ?? false}',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return result == true;
    } on MissingPluginException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'iOS ReplayKit broadcast activation plugin is unavailable.',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'iOS ReplayKit broadcast activation failed '
            'code=${error.code} message=${error.message}',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return false;
    }
  }

  static Future<bool> requestStop() async {
    if (!PlatformUtils.isIOS) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'broadcastRequestStop',
        <String, dynamic>{},
      );
      Log.i(
        'Requested iOS ReplayKit broadcast stop '
        'result=${result ?? false}',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return result == true;
    } on MissingPluginException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'iOS ReplayKit broadcast stop plugin is unavailable.',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'iOS ReplayKit broadcast stop failed '
            'code=${error.code} message=${error.message}',
        category: LogCategory.livekit,
        source: 'ios-broadcast',
      );
      return false;
    }
  }
}
