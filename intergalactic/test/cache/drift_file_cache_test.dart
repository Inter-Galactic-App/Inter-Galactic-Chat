import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/drift_file_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;
  late TestDriftFileCache cache;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'intergalactic_drift_file_cache_test_',
    );
    cache = TestDriftFileCache(tempDirectory);
    cache.db = DriftFileCacheDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await cache.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('clean deletes stale files before removing database rows', () async {
    final staleFile = File(p.join(tempDirectory.path, 'stale.bin'));
    final freshFile = File(p.join(tempDirectory.path, 'fresh.bin'));
    await staleFile.writeAsBytes([1]);
    await freshFile.writeAsBytes([2]);

    final now = DateTime.now();
    await cache.db.into(cache.db.fileCacheEntry).insert(
          FileCacheEntryCompanion.insert(
            id: 'stale',
            path: staleFile.path,
            lastAccessedTimestamp:
                now.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
          ),
        );
    await cache.db.into(cache.db.fileCacheEntry).insert(
          FileCacheEntryCompanion.insert(
            id: 'fresh',
            path: freshFile.path,
            lastAccessedTimestamp: now.millisecondsSinceEpoch,
          ),
        );

    await cache.clean();

    expect(await staleFile.exists(), isFalse);
    expect(await freshFile.exists(), isTrue);
    expect(await _entryFor(cache, 'stale'), isNull);
    expect(await _entryFor(cache, 'fresh'), isNotNull);
  });

  test('putFile deletes the previous path for the same identifier', () async {
    final firstUri = await cache.putFile(
      'avatar',
      Uint8List.fromList([1, 2, 3]),
    );
    final firstFile = File.fromUri(firstUri);

    final secondUri = await cache.putFile(
      'avatar',
      Uint8List.fromList([4, 5]),
    );
    final secondFile = File.fromUri(secondUri);
    final entry = await _entryFor(cache, 'avatar');

    expect(secondUri, isNot(firstUri));
    expect(await firstFile.exists(), isFalse);
    expect(await secondFile.readAsBytes(), [4, 5]);
    expect(entry?.path, secondFile.path);
  });
}

Future<FileCacheEntryData?> _entryFor(
  TestDriftFileCache cache,
  String id,
) {
  return (cache.db.select(cache.db.fileCacheEntry)
        ..where((tbl) => tbl.id.equals(id)))
      .getSingleOrNull();
}

class TestDriftFileCache extends DriftFileCache {
  TestDriftFileCache(this.tempDirectory);

  final Directory tempDirectory;
  var _nextPathIndex = 0;

  @override
  Future<String> newPath() async {
    _nextPathIndex += 1;
    return p.join(tempDirectory.path, 'cache_$_nextPathIndex');
  }
}
