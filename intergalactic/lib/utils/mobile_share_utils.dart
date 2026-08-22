import 'package:flutter/services.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

class MobileShareUtils {
  static const MethodChannel _channel =
      MethodChannel('chat.intergalactic.app/media_share');

  static Future<bool> shareAttachment(FileAttachment attachment) async {
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) {
      return false;
    }

    final Uint8List? bytes = await attachment.file.getFileData();
    if (bytes == null || bytes.isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'shareFile',
        {
          'bytes': bytes,
          'filename': attachment.name,
          'mimeType': attachment.mimeType ?? 'application/octet-stream',
        },
      );
      return result == true;
    } on MissingPluginException catch (error) {
      Log.w(
        'Native media share bridge unavailable: $error',
        category: LogCategory.media,
        source: 'mobile-share',
      );
      return false;
    } on PlatformException catch (error) {
      Log.w(
        'Native media share failed: ${error.code}',
        category: LogCategory.media,
        source: 'mobile-share',
      );
      return false;
    }
  }
}
