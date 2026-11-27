import 'dart:async';

import 'package:flutter/widgets.dart';
import 'dart:ui' as ui;

class ImageUtils {
  /// Resolves [provider] to its first frame.
  ///
  /// Completes with the stream's error when the load fails, and with a
  /// [TimeoutException] when [timeout] is given and no frame or error arrives
  /// in time. Before this, the listener had no error callback and there was
  /// no timeout, so a failed load never completed and every caller awaiting
  /// it hung - for the notification preview path that meant a notification
  /// that was never shown rather than one without a picture (BUG-293
  /// residual). The listener is removed once the future settles, so a
  /// multi-frame image does not keep delivering frames to a dead completer.
  static Future<ui.Image> imageProviderToImage(
    ImageProvider provider, {
    Duration? timeout,
  }) async {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!completer.isCompleted) {
          completer.complete(info.image);
        } else {
          info.image.dispose();
        }
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    try {
      final future = completer.future;
      return await (timeout == null ? future : future.timeout(timeout));
    } finally {
      stream.removeListener(listener);
    }
  }
}
