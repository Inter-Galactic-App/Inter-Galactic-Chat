import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class MessageBackgroundManager {
  static bool get supportsLocalImages => false;

  static Future<String?> importBackground(
    Uint8List bytes, {
    required String storageKey,
  }) async {
    return null;
  }

  static Future<void> deleteBackground(String? storedPath) async {}

  static ImageProvider? imageProvider(String? storedPath) {
    return null;
  }

  static Future<ImageProvider?> resolveImageProvider(String? storedPath) async {
    return null;
  }

  static Future<bool> referencesSameBackground(
    String? first,
    String? second,
  ) async {
    return false;
  }
}
