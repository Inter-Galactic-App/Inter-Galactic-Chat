import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_local_sound_resolver_io.dart';

void main() {
  group('pruneSoundboardLocalCache', () {
    late Directory cacheDirectory;

    setUp(() {
      cacheDirectory =
          Directory.systemTemp.createTempSync('ig_soundboard_cache_test_');
    });

    tearDown(() {
      if (cacheDirectory.existsSync()) {
        cacheDirectory.deleteSync(recursive: true);
      }
    });

    test('deletes aged files while preserving protected and recent files',
        () async {
      final now = DateTime.utc(2026, 6, 19, 12);
      final oldFile = await _writeCacheFile(
        cacheDirectory,
        'old.wav',
        bytes: 10,
        modifiedAt: now.subtract(const Duration(days: 30)),
      );
      final protectedFile = await _writeCacheFile(
        cacheDirectory,
        'protected.wav',
        bytes: 20,
        modifiedAt: now.subtract(const Duration(days: 30)),
      );
      final recentFile = await _writeCacheFile(
        cacheDirectory,
        'recent.wav',
        bytes: 30,
        modifiedAt: now.subtract(const Duration(days: 1)),
      );

      final result = await pruneSoundboardLocalCache(
        directory: cacheDirectory,
        protectedUri: protectedFile.uri,
        now: now,
        maxAge: const Duration(days: 14),
        maxFiles: 10,
        maxBytes: 1024,
      );

      expect(result.scannedFiles, 3);
      expect(result.deletedFiles, 1);
      expect(result.deletedBytes, 10);
      expect(oldFile.existsSync(), isFalse);
      expect(protectedFile.existsSync(), isTrue);
      expect(recentFile.existsSync(), isTrue);
    });

    test('enforces count and size limits using oldest unprotected files',
        () async {
      final now = DateTime.utc(2026, 6, 19, 12);
      final protectedFile = await _writeCacheFile(
        cacheDirectory,
        'protected.wav',
        bytes: 20,
        modifiedAt: now.subtract(const Duration(days: 4)),
      );
      final oldestFile = await _writeCacheFile(
        cacheDirectory,
        'oldest.wav',
        bytes: 20,
        modifiedAt: now.subtract(const Duration(days: 3)),
      );
      final middleFile = await _writeCacheFile(
        cacheDirectory,
        'middle.wav',
        bytes: 20,
        modifiedAt: now.subtract(const Duration(days: 2)),
      );
      final newestFile = await _writeCacheFile(
        cacheDirectory,
        'newest.wav',
        bytes: 20,
        modifiedAt: now.subtract(const Duration(days: 1)),
      );

      final result = await pruneSoundboardLocalCache(
        directory: cacheDirectory,
        protectedUri: protectedFile.uri,
        now: now,
        maxAge: const Duration(days: 365),
        maxFiles: 2,
        maxBytes: 40,
      );

      expect(result.scannedFiles, 4);
      expect(result.deletedFiles, 2);
      expect(result.deletedBytes, 40);
      expect(protectedFile.existsSync(), isTrue);
      expect(oldestFile.existsSync(), isFalse);
      expect(middleFile.existsSync(), isFalse);
      expect(newestFile.existsSync(), isTrue);
    });
  });
}

Future<File> _writeCacheFile(
  Directory directory,
  String name, {
  required int bytes,
  required DateTime modifiedAt,
}) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(List<int>.filled(bytes, 1), flush: true);
  await file.setLastModified(modifiedAt);
  return file;
}
