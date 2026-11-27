import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_local_sound_cache.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const int _minSoundBytes = 16;
const int _maxSoundboardCacheFiles = 64;
const int _maxSoundboardCacheBytes = 64 * 1024 * 1024;
const Duration _maxSoundboardCacheAge = Duration(days: 14);

Future<Uri?> resolveSoundboardLocalUri(
  MatrixClient client,
  SoundboardSound sound,
) async {
  final directory = await _soundboardCacheDirectory();
  await directory.create(recursive: true);

  final extension = _extensionForMime(
    sound.mimeType,
    originalName: sound.name,
  );
  final file =
      File(path.join(directory.path, '${_cacheToken(sound)}$extension'));
  if (await file.exists() && await file.length() == sound.sizeBytes) {
    await _touchCacheFile(file);
    return file.uri;
  }

  final response = await client.matrixClient.getContentFromUri(sound.mxcUri);
  final bytes = response.data;
  if (!_isValidSoundPayload(bytes.length, sound.sizeBytes)) {
    if (await file.exists()) {
      await file.delete();
    }
    return null;
  }

  await file.writeAsBytes(bytes, flush: true);
  await _touchCacheFile(file);
  return file.uri;
}

Future<SoundboardCachePruneResult> pruneSoundboardLocalCache({
  Uri? protectedUri,
  Directory? directory,
  DateTime? now,
  int maxFiles = _maxSoundboardCacheFiles,
  int maxBytes = _maxSoundboardCacheBytes,
  Duration maxAge = _maxSoundboardCacheAge,
}) async {
  final cacheDirectory = directory ?? await _soundboardCacheDirectory();
  if (!await cacheDirectory.exists()) {
    return const SoundboardCachePruneResult.empty();
  }

  final protectedPath = _protectedFilePath(protectedUri);
  final cacheFiles = <_SoundboardCacheFile>[];
  try {
    await for (final entity in cacheDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      FileStat stat;
      try {
        stat = await entity.stat();
      } on FileSystemException {
        continue;
      }
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final normalizedPath = _normalizedPath(entity.path);
      cacheFiles.add(
        _SoundboardCacheFile(
          file: entity,
          length: stat.size,
          modifiedAt: stat.modified.toUtc(),
          isProtected: protectedPath != null &&
              path.equals(normalizedPath, protectedPath),
        ),
      );
    }
  } on FileSystemException {
    return const SoundboardCachePruneResult.empty();
  }

  final deletePaths = <String>{};
  final referenceTime = (now ?? DateTime.now().toUtc()).toUtc();
  for (final cacheFile in cacheFiles) {
    if (!cacheFile.isProtected &&
        referenceTime.difference(cacheFile.modifiedAt) > maxAge) {
      deletePaths.add(cacheFile.normalizedPath);
    }
  }

  final retained = cacheFiles
      .where((cacheFile) => !deletePaths.contains(cacheFile.normalizedPath))
      .toList()
    ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));

  var retainedFiles = retained.length;
  var retainedBytes =
      retained.fold<int>(0, (total, cacheFile) => total + cacheFile.length);
  final fileLimit = maxFiles < 1 ? 1 : maxFiles;
  final byteLimit = maxBytes < 1 ? 1 : maxBytes;

  for (final cacheFile in retained) {
    if (retainedFiles <= fileLimit && retainedBytes <= byteLimit) {
      break;
    }

    if (cacheFile.isProtected) {
      continue;
    }

    deletePaths.add(cacheFile.normalizedPath);
    retainedFiles -= 1;
    retainedBytes -= cacheFile.length;
  }

  var deletedFiles = 0;
  var deletedBytes = 0;
  for (final cacheFile in cacheFiles) {
    if (!deletePaths.contains(cacheFile.normalizedPath)) {
      continue;
    }

    try {
      await cacheFile.file.delete();
      deletedFiles += 1;
      deletedBytes += cacheFile.length;
    } on FileSystemException {
      // Cache cleanup is best-effort; playback should not fail because an
      // older temp file is locked by the OS or antivirus.
    }
  }

  return SoundboardCachePruneResult(
    scannedFiles: cacheFiles.length,
    deletedFiles: deletedFiles,
    deletedBytes: deletedBytes,
  );
}

Future<Directory> _soundboardCacheDirectory() async {
  return Directory(
    path.join((await getTemporaryDirectory()).path, 'intergalactic_soundboard'),
  );
}

Future<void> _touchCacheFile(File file) async {
  try {
    await file.setLastModified(DateTime.now().toUtc());
  } on FileSystemException {
    // Last-modified time only drives retention order. If touching fails,
    // playback can still use the cached file.
  }
}

String? _protectedFilePath(Uri? protectedUri) {
  if (protectedUri == null || !protectedUri.isScheme('file')) {
    return null;
  }

  return _normalizedPath(protectedUri.toFilePath());
}

String _normalizedPath(String value) {
  return path.normalize(path.absolute(value));
}

String _cacheToken(SoundboardSound sound) {
  final payload = jsonEncode({
    'id': sound.id,
    'mxc': sound.mxcUri.toString(),
    'mime': sound.mimeType,
    'size': sound.sizeBytes,
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

class _SoundboardCacheFile {
  _SoundboardCacheFile({
    required this.file,
    required this.length,
    required this.modifiedAt,
    required this.isProtected,
  });

  final File file;
  final int length;
  final DateTime modifiedAt;
  final bool isProtected;

  String get normalizedPath => _normalizedPath(file.path);
}

bool _isValidSoundPayload(int actualBytes, int expectedBytes) {
  if (actualBytes < _minSoundBytes) {
    return false;
  }
  return expectedBytes <= 0 || actualBytes == expectedBytes;
}

String _extensionForMime(String mimeType, {String? originalName}) {
  final normalized = mimeType.toLowerCase().split(';').first.trim();
  final mappedExtension = switch (normalized) {
    'audio/aac' => '.aac',
    'audio/x-aac' => '.aac',
    'audio/flac' => '.flac',
    'audio/x-flac' => '.flac',
    'audio/mp4' => '.m4a',
    'audio/x-m4a' => '.m4a',
    'audio/mp3' => '.mp3',
    'audio/mpeg3' => '.mp3',
    'audio/mpeg' => '.mp3',
    'audio/x-mp3' => '.mp3',
    'audio/x-mpeg' => '.mp3',
    'audio/x-mpeg-3' => '.mp3',
    'audio/ogg' => '.ogg',
    'audio/opus' => '.opus',
    'audio/wav' => '.wav',
    'audio/wave' => '.wav',
    'audio/x-wav' => '.wav',
    'audio/vnd.wave' => '.wav',
    'audio/webm' => '.webm',
    _ => null,
  };

  if (mappedExtension != null) {
    return mappedExtension;
  }

  final originalExtension =
      originalName == null ? '' : path.extension(originalName).toLowerCase();
  return switch (originalExtension) {
    '.aac' ||
    '.flac' ||
    '.m4a' ||
    '.mp3' ||
    '.ogg' ||
    '.opus' ||
    '.wav' ||
    '.webm' =>
      originalExtension,
    _ => '.sound',
  };
}
