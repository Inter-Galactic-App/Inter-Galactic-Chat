import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/widgets.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// Preview preparation is best-effort and every failure path returns null, so a
// broken preview is invisible: the notification still displays with its
// "Sent an image" text and nothing is reported. That is exactly how a
// permanently failing protect step survived unnoticed. These markers name the
// stage that failed and nothing else -- no path, no attachment identifier, no
// decrypted media detail -- per docs/agent-control/log-guidance.md.
void _reportPreviewFailure(String stage) {
  Log.w(
    'notification_media_pipeline stage=ios_preview result=failed at=$stage',
    category: LogCategory.notifications,
    source: 'ios-notification-preview',
  );
}

const _previewDirectoryName = 'intergalactic-notification-previews';
const _previewMaximumAge = Duration(hours: 24);
const _previewLoadTimeout = Duration(seconds: 10);

Future<String?> prepareIosNotificationPreview(
  ImageProvider imageProvider,
  Future<bool> Function(String path) protectPreviewFile,
) async {
  try {
    final directory = Directory(
      path.join((await getTemporaryDirectory()).path, _previewDirectoryName),
    );
    await directory.create(recursive: true);
    await _purgeExpiredPreviewFiles(directory);

    // A load that fails or stalls degrades to the text-only notification
    // through the catch below; without the timeout it used to hang the
    // notification forever.
    final image = await ImageUtils.imageProviderToImage(
      imageProvider,
      timeout: _previewLoadTimeout,
    );
    final Uint8List? bytes;
    try {
      final imageData = await image.toByteData(format: ImageByteFormat.png);
      bytes = imageData?.buffer.asUint8List();
    } finally {
      // dart:ui Image holds native memory until its finalizer runs. A burst of
      // image notifications otherwise keeps several decoded frames alive at
      // once, having already copied the bytes it needs.
      image.dispose();
    }
    if (bytes == null || bytes.isEmpty) {
      _reportPreviewFailure('encode');
      return null;
    }

    final file = File(
      path.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}.png',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    if (!await protectPreviewFile(file.path)) {
      // The host rejected the file. Historically this was a silent, permanent
      // failure for every image/GIF/sticker notification, because the native
      // containment guard only accepted NSTemporaryDirectory() while
      // getTemporaryDirectory() resolves to the caches directory on Apple
      // platforms.
      _reportPreviewFailure('protect');
      await _deletePreviewFile(file);
      return null;
    }
    return file.path;
  } catch (_) {
    // A preview is optional. Do not expose a path, attachment identifier, or
    // decrypted media detail in diagnostics when preparation fails.
    _reportPreviewFailure('exception');
    return null;
  }
}

Future<void> _purgeExpiredPreviewFiles(Directory directory) async {
  try {
    final cutoff = DateTime.now().subtract(_previewMaximumAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final modified = await entity.lastModified();
      if (modified.isBefore(cutoff)) {
        await _deletePreviewFile(entity);
      }
    }
  } catch (_) {
    // Expiry cleanup must never prevent the current notification delivery.
  }
}

Future<void> _deletePreviewFile(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // The next bounded sweep may remove it. Do not disclose a local path.
  }
}
