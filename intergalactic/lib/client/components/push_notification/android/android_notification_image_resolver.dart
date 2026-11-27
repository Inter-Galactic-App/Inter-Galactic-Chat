import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/utils/image/lod_image.dart';

/// Resolves a notification image from notification-quality media bytes.
///
/// [LODImageProvider] may emit its 10x10 blurhash before Matrix media finishes
/// loading. It may also emit a 90x90 Matrix thumbnail first. Notification
/// staging is a one-shot encode, so resolving the mutable LOD stream after a
/// fetch can still encode a previously emitted blurred or tiny frame. Stage a
/// new [MemoryImage] from the chosen bytes instead.
Future<T?> resolveAndroidNotificationImage<T>(
  ImageProvider provider,
  Future<T> Function(ImageProvider provider) resolve, {
  Duration mediaLoadTimeout = const Duration(seconds: 15),
}) async {
  if (provider case LODImageProvider lodProvider) {
    final timer = Stopwatch()..start();
    var fullResTimedOut = false;
    try {
      final loadFullRes = lodProvider.loadFullRes;
      if (loadFullRes != null) {
        final reserve = lodProvider.loadThumbnail == null
            ? Duration.zero
            : Duration(microseconds: mediaLoadTimeout.inMicroseconds ~/ 3);
        try {
          final bytes = await loadFullRes().timeout(mediaLoadTimeout - reserve);
          if (bytes != null && bytes.isNotEmpty) {
            return resolve(MemoryImage(bytes));
          }
        } on TimeoutException {
          // The remaining budget is reserved for the thumbnail.
          fullResTimedOut = true;
        }
      }

      final loadThumbnail = lodProvider.loadThumbnail;
      final remaining = mediaLoadTimeout - timer.elapsed;
      if (remaining <= Duration.zero) return null;
      if (loadThumbnail != null) {
        final bytes = await loadThumbnail().timeout(remaining);
        if (bytes == null || bytes.isEmpty) return null;
        return resolve(MemoryImage(bytes));
      }
      if (fullResTimedOut) return null;
    } on TimeoutException {
      // A delayed notification is worse than omitting its optional preview.
      return null;
    }
  }

  return resolve(provider);
}
