import 'dart:ui' as ui;

import 'package:intergalactic/client/room.dart';
import 'package:flutter/material.dart';

enum ShortcutIconFormat {
  jpeg,
  png,
  rawRgba,
}

class ShortcutsManager {
  Future? loading;

  void init() {}

  Future<void> createShortcutForRoom(Room room) async {}

  Future<void> clearAllShortcuts() async {}

  void onRoomOpenedInUI(Room? event) {}

  static Future<Uri?> getCachedAvatarImage({
    required Color placeholderColor,
    required String placeholderText,
    required String identifier,
    required ShortcutIconFormat format,
    String? imageId,
    ImageProvider? imageProvider,
    bool shouldZoomOut = true,
    bool doCircleMask = true,
  }) async {
    return null;
  }

  static Future<ui.Image> createAvatarImage({
    required Color placeholderColor,
    required String placeholderText,
    ImageProvider? imageProvider,
    bool shouldZoomOut = true,
    bool doCircleMask = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(128, 128);
    final paint = Paint()..color = placeholderColor;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128), paint);

    final textSpan = TextSpan(
      text: placeholderText.isEmpty ? '?' : placeholderText.characters.first.toUpperCase(),
      style: const TextStyle(color: Colors.white, fontSize: 50),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
    );

    return recorder.endRecording().toImage(size.width.round(), size.height.round());
  }

  static Future<ui.Image> combineRoomAndUserImages(ui.Image roomImage, ui.Image userImage) async {
    return userImage;
  }
}
