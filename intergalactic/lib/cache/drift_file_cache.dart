import 'dart:io';
import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';
import 'package:intergalactic/utils/rng.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_file_cache.g.dart';

FileCache? getFileCacheImplementation() {
  return DriftFileCache();
}

class FileCacheEntry extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();

  IntColumn get lastAccessedTimestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FileCacheEntry])
class DriftFileCacheDatabase extends _$DriftFileCacheDatabase {
  DriftFileCacheDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

class DriftFileCache implements FileCache {
  bool isInit = false;
  late DriftFileCacheDatabase db;

  static const String isolateName =
      "${BuildConfig.windowsTempNamespace}.isolate.file_cache";

  @override
  Future<void> clean() async {
    Log.i("Cleaning files");

    var now = DateTime.now();
    var cutoffTime = now.subtract(const Duration(days: 5));
    var timeMs = cutoffTime.millisecondsSinceEpoch;

    var removeFiles = await (db.select(db.fileCacheEntry)
          ..where(
              (tbl) => tbl.lastAccessedTimestamp.isSmallerThanValue(timeMs)))
        .get();

    var allFiles = await (db.select(db.fileCacheEntry).get());

    Log.i("Found: ${removeFiles.length}/${allFiles.length} files for cleaning");

    var removedIds = <String>[];
    for (var file in removeFiles) {
      if (await _cleanFile(file)) {
        removedIds.add(file.id);
      }
    }

    if (removedIds.isNotEmpty) {
      await (db.delete(db.fileCacheEntry)
            ..where((tbl) => tbl.id.isIn(removedIds)))
          .go();
    }
  }

  Future<bool> _cleanFile(FileCacheEntryData entry) async {
    return _deleteFileAtPath(
      entry.path,
      "Unable to delete cached file; cache row retained for retry",
    );
  }

  @override
  Future<void> close() {
    return db.close();
  }

  @override
  Future<Uri> fetchFile(
      String identifier, Future<Uint8List> Function() getter) async {
    var existing = await getFile(identifier);
    if (existing != null) return existing;

    var bytes = await getter();
    return _writeFile(identifier, bytes);
  }

  @override
  Future<Uri?> getFile(String identifier) async {
    if (!await hasFile(identifier)) return null;

    var entry = await _getByFileId(identifier);
    if (entry == null) return null;
    //var lastAccess = DateTime.fromMillisecondsSinceEpoch(entry!.lastAccessedTimestamp).toLocal().toString();

    try {
      await db.into(db.fileCacheEntry).insertOnConflictUpdate(entry.copyWith(
            lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch,
          ));
    } catch (e) {
      Log.w("Unable to update cached file access time (${e.runtimeType})");
    }

    var file = File(entry.path);

    return file.uri;
  }

  @override
  Future<bool> hasFile(String identifier) async {
    var file = await _getByFileId(identifier);
    if (file == null) return false;

    // if the file exists in the database but not on disk, we should remove it from db
    var exists = await File(file.path).exists();
    if (!exists) {
      try {
        await (db.delete(db.fileCacheEntry)
              ..where((tbl) => tbl.id.equals(file.id)))
            .go();
      } catch (e) {
        Log.w("Unable to remove missing cached file row (${e.runtimeType})");
      }
    }

    return exists;
  }

  @override
  Future<void> init() async {
    if (isInit) {
      return;
    }

    isInit = true;

    var tempDir = await getTemporaryDirectory();
    var temp =
        p.join(tempDir.path, BuildConfig.windowsTempNamespace, "file_cache");

    Log.i("Cache: $temp");

    final dir = p.join(await AppConfig.getDatabasePath(), "app");
    var directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(p.join(dir, "app_data.db"));

    var connection = await DatabaseIsolate.connect(file.absolute.path);
    db = DriftFileCacheDatabase(connection);

    if (!isHeadless) {
      clean();
    }
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    return _writeFile(identifier, bytes);
  }

  Future<Uri> _writeFile(String identifier, Uint8List bytes) async {
    var previousEntry = await _getByFileId(identifier);
    var path = await generateTempFilePath();
    if (BuildConfig.DEBUG) path += "_${Uri.encodeComponent(identifier)}";

    var file = File(path);
    try {
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);

      var entry = FileCacheEntryCompanion.insert(
          id: identifier,
          path: path,
          lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch);

      await db.into(db.fileCacheEntry).insertOnConflictUpdate(entry);
    } catch (_) {
      await _deleteFileAtPath(
        path,
        "Unable to delete cached file after write failure",
      );
      rethrow;
    }

    if (previousEntry != null && previousEntry.path != path) {
      await _deleteReplacedFile(previousEntry);
    }

    return file.uri;
  }

  Future<void> _deleteReplacedFile(FileCacheEntryData entry) async {
    await _deleteFileAtPath(
      entry.path,
      "Unable to delete replaced cached file",
    );
  }

  Future<bool> _deleteFileAtPath(String path, String failureMessage) async {
    var file = File(path);

    try {
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      Log.w("$failureMessage (${e.runtimeType})");
      return false;
    }
  }

  Future<String> newPath() async {
    final dir = await getTemporaryDirectory();
    String fileName = RandomUtils.getRandomString(30);
    return p.join(
        dir.path, BuildConfig.windowsTempNamespace, "file_cache", fileName);
  }

  Future<String> generateTempFilePath() async {
    var path = "";
    for (path = await newPath();
        await File(path).exists();
        path = await newPath()) {}

    return path;
  }

  Future<FileCacheEntryData?> _getByFileId(String fileId) async {
    return (db.select(db.fileCacheEntry)
          ..where((tbl) => tbl.id.equals(fileId))
          ..limit(1))
        .getSingleOrNull();
  }
}
