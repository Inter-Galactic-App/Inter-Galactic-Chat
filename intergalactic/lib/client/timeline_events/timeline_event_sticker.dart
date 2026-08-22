import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:flutter/material.dart';

abstract class TimelineEventSticker extends TimelineEvent {
  String get stickerName;

  ImageProvider get stickerImage;
}

abstract interface class TimelineEventAnimatedSticker {
  bool get isAnimatedSticker;
}

/// Keeps timeline and background notification sticker classification aligned.
///
/// `body` is not required to be a filename - a picker can send `Picker` - so
/// the `.gif` suffix alone misses animated stickers and labels them static.
/// `info.mimetype` is the authoritative signal when it is present.
bool timelineStickerIsAnimated(Map<String, dynamic> content, String name) {
  final info = content['info'];
  final mimeType = info is Map ? info['mimetype'] : null;
  return content['chat.commet.animated'] == true ||
      (info is Map && info['chat.commet.animated'] == true) ||
      (mimeType is String && mimeType.toLowerCase() == 'image/gif') ||
      name.toLowerCase().endsWith('.gif');
}
