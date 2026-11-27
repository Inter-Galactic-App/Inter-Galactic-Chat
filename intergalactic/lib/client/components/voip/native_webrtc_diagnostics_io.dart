import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class NativeWebrtcDiagnostics {
  static const fileName = 'intergalactic-native-webrtc-diagnostics.log';

  static File get _file {
    return File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
  }

  static Future<void> clear() async {
    final file = _file;
    if (!await file.exists()) {
      return;
    }
    await file.writeAsString('');
  }

  static Future<String> recentText({
    int maxFileBytes = 160 * 1024,
  }) async {
    final file = _file;
    if (!await file.exists()) {
      return '';
    }

    final length = await file.length();
    if (length <= 0) {
      return '';
    }

    final clampedMax = maxFileBytes <= 0 ? length : maxFileBytes;
    final offset = length > clampedMax ? length - clampedMax : 0;
    final bytes = <int>[];
    final reader = await file.open();
    try {
      await reader.setPosition(offset);
      while (true) {
        final chunk = await reader.read(32 * 1024);
        if (chunk.isEmpty) {
          break;
        }
        bytes.addAll(chunk);
      }
    } finally {
      await reader.close();
    }

    if (bytes.isEmpty) {
      return '';
    }

    final text = utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);
    if (offset <= 0) {
      return text;
    }
    return '... native WebRTC diagnostic sidecar truncated ...\n$text';
  }
}
