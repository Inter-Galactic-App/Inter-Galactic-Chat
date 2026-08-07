import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MessageBackgroundManager {
  static final Map<String, Future<void>> _importsByKey = {};
  static Future<Directory> Function()? debugBackgroundDirectoryOverride;
  static String? _cachedBackgroundDirectoryPath;

  static bool get supportsLocalImages => true;

  static Future<String> importBackground(
    Uint8List bytes, {
    required String storageKey,
  }) async {
    final key = _fileKey(storageKey);
    return _withImportLock(key, () async {
      final dir = await _backgroundDirectory();
      await dir.create(recursive: true);

      final destination = File(path.join(dir.path, '$key.png'));
      if (await destination.exists()) {
        await _evictFromImageCache(destination);
        await destination.delete();
      }

      await destination.writeAsBytes(bytes, flush: true);
      await _evictFromImageCache(destination);
      return destination.path;
    });
  }

  static Future<void> deleteBackground(String? storedPath) async {
    final file = await resolveBackgroundFile(storedPath);
    if (file == null || !await file.exists()) {
      return;
    }

    final dir = await _backgroundDirectory();
    final normalizedDir = path.normalize(dir.path);
    final normalizedFile = path.normalize(file.path);
    if (normalizedFile == normalizedDir ||
        path.isWithin(normalizedDir, normalizedFile)) {
      await _evictFromImageCache(file);
      await file.delete();
    }
  }

  static ImageProvider? imageProvider(String? storedPath) {
    if (storedPath == null || storedPath.isEmpty) {
      return null;
    }

    final file = _syncResolvedFile(storedPath);
    if (!file.existsSync()) {
      return null;
    }

    return FileImage(file);
  }

  static Future<ImageProvider?> resolveImageProvider(String? storedPath) async {
    final file = await resolveBackgroundFile(storedPath);
    if (file == null || !await file.exists()) {
      return null;
    }

    return FileImage(file);
  }

  static Future<File?> resolveBackgroundFile(String? storedPath) async {
    if (storedPath == null || storedPath.isEmpty) {
      return null;
    }

    final directFile = File(storedPath);
    if (await directFile.exists()) {
      return directFile;
    }

    final fileName = path.basename(storedPath);
    if (!_isManagedBackgroundFileName(fileName)) {
      return null;
    }

    final dir = await _backgroundDirectory();
    final rehomedFile = File(path.join(dir.path, fileName));
    if (await rehomedFile.exists()) {
      return rehomedFile;
    }

    return null;
  }

  static Future<bool> referencesSameBackground(
    String? first,
    String? second,
  ) async {
    if (first == null || first.isEmpty || second == null || second.isEmpty) {
      return false;
    }

    final firstFile = await resolveBackgroundFile(first);
    final secondFile = await resolveBackgroundFile(second);
    if (firstFile != null && secondFile != null) {
      return path.normalize(firstFile.path) == path.normalize(secondFile.path);
    }

    final firstName = path.basename(first);
    final secondName = path.basename(second);
    return _isManagedBackgroundFileName(firstName) && firstName == secondName;
  }

  static Future<Directory> _backgroundDirectory() async {
    if (debugBackgroundDirectoryOverride != null) {
      final dir = await debugBackgroundDirectoryOverride!();
      _cachedBackgroundDirectoryPath = dir.path;
      return dir;
    }

    final dir = await getApplicationSupportDirectory();
    final backgroundDir = Directory(path.join(dir.path, 'message_backgrounds'));
    _cachedBackgroundDirectoryPath = backgroundDir.path;
    return backgroundDir;
  }

  static File _syncResolvedFile(String storedPath) {
    final directFile = File(storedPath);
    if (directFile.existsSync()) {
      return directFile;
    }

    final cachedDir = _cachedBackgroundDirectoryPath;
    final fileName = path.basename(storedPath);
    if (cachedDir != null && _isManagedBackgroundFileName(fileName)) {
      final rehomedFile = File(path.join(cachedDir, fileName));
      if (rehomedFile.existsSync()) {
        return rehomedFile;
      }
    }

    return directFile;
  }

  static String _fileKey(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  static bool _isManagedBackgroundFileName(String fileName) {
    return fileName.isNotEmpty &&
        fileName == path.basename(fileName) &&
        fileName.endsWith('.png');
  }

  static Future<void> _evictFromImageCache(File file) async {
    try {
      await FileImage(file).evict();
    } on FlutterError {
      // File operations can run in no-widget tests or startup utilities before
      // Flutter's painting binding exists. The disk update is still valid; the
      // next widget-bound render will populate the image cache normally.
    }
  }

  static Future<T> _withImportLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _importsByKey[key] ?? Future<void>.value();
    final completer = Completer<void>();
    final current = previous.then((_) => completer.future);
    _importsByKey[key] = current;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_importsByKey[key], current)) {
        _importsByKey.remove(key);
      }
    }
  }
}
