import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/utils/image/lod_image.dart';

/// Resolves a notification image only after a non-placeholder LOD is ready.
///
/// [LODImageProvider] may emit its 10x10 blurhash before Matrix media finishes
/// loading. Notification staging is a one-shot encode, so accepting that first
/// frame permanently embeds the placeholder in the Android notification.
Future<T?> resolveAndroidNotificationImage<T>(
  ImageProvider provider,
  Future<T> Function(ImageProvider provider) resolve, {
  Duration mediaLoadTimeout = const Duration(seconds: 15),
}) async {
  if (provider case LODImageProvider lodProvider) {
    try {
      if (lodProvider.loadThumbnail != null) {
        await lodProvider.fetchThumbnail().timeout(mediaLoadTimeout);
      } else if (lodProvider.loadFullRes != null) {
        await lodProvider.fetchFullRes().timeout(mediaLoadTimeout);
      }
    } on TimeoutException {
      // A delayed notification is worse than omitting its optional preview.
      return null;
    }
  }

  return resolve(provider);
}
