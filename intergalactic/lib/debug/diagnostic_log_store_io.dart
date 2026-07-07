import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

class DiagnosticLogStore {
  static const _filePrefix = 'intergalactic-';
  static const _fileExtension = '.log';

  late Directory _directory;
  late int _maxFileBytes;
  late int _maxFiles;
  late int _maxTotalBytes;
  late Duration _retention;

  File? _currentFile;
  String? _currentDateStamp;
  Future<void> _pending = Future<void>.value();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  String? get logDirectoryPath => _initialized ? _directory.path : null;

  Future<void> initialize({
    String? directoryPath,
    int maxFileBytes = 5 * 1024 * 1024,
    int maxFiles = 10,
    int maxTotalBytes = 25 * 1024 * 1024,
    Duration retention = const Duration(days: 14),
  }) async {
    _directory =
        Directory(directoryPath ?? await AppConfig.getLogDirectoryPath());
    _maxFileBytes = maxFileBytes;
    _maxFiles = maxFiles;
    _maxTotalBytes = maxTotalBytes;
    _retention = retention;

    await _directory.create(recursive: true);
    _initialized = true;
    await _prune();
    await append(
      '--- Inter Galactic diagnostic log started ${DateTime.now().toUtc().toIso8601String()} ---\n',
      flush: true,
    );
  }

  Future<void> append(String line, {bool flush = false}) {
    if (!_initialized) {
      return Future<void>.value();
    }

    _pending = _pending.then((_) => _appendInternal(line, flush: flush));
    return _pending;
  }

  void appendSync(String line) {
    if (!_initialized) {
      return;
    }

    try {
      final file = _resolveWritableFileSync(utf8.encode(line).length);
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Diagnostics must never crash the app.
    }
  }

  Future<void> flush() async {
    try {
      await _pending;
    } catch (_) {
      // Diagnostics must never crash the app.
    }
  }

  Future<String> recentText({int maxBytes = 200 * 1024}) async {
    if (!_initialized) {
      return '';
    }

    await flush();
    final files = await _logFiles();
    files.sort((a, b) {
      final bModified = b.statSync().modified;
      final aModified = a.statSync().modified;
      return bModified.compareTo(aModified);
    });

    var remaining = maxBytes;
    final chunks = <String>[];
    for (final file in files) {
      if (remaining <= 0) {
        break;
      }

      final bytes = await file.readAsBytes();
      final start = bytes.length > remaining ? bytes.length - remaining : 0;
      final selected = bytes.sublist(start);
      remaining -= selected.length;
      chunks.add(
        '--- ${path.basename(file.path)} ---\n${utf8.decode(selected, allowMalformed: true)}',
      );
    }

    return chunks.reversed.join('\n');
  }

  Future<void> clear() async {
    if (!_initialized) {
      return;
    }

    await flush();
    for (final file in await _logFiles()) {
      try {
        await file.delete();
      } catch (_) {
        // Best-effort developer action.
      }
    }
    _currentFile = null;
    _currentDateStamp = null;
  }

  Future<void> _appendInternal(String line, {required bool flush}) async {
    try {
      final file = await _resolveWritableFile(utf8.encode(line).length);
      await file.writeAsString(line, mode: FileMode.append, flush: flush);
    } catch (_) {
      // Diagnostics must never crash the app.
    }
  }

  Future<File> _resolveWritableFile(int nextBytes) async {
    final today = _dateStamp(DateTime.now());
    if (_currentFile != null &&
        _currentDateStamp == today &&
        await _currentFile!.exists() &&
        await _currentFile!.length() + nextBytes <= _maxFileBytes) {
      return _currentFile!;
    }

    _currentDateStamp = today;
    _currentFile = await _findWritableFile(today, nextBytes);
    return _currentFile!;
  }

  File _resolveWritableFileSync(int nextBytes) {
    final today = _dateStamp(DateTime.now());
    if (_currentFile != null &&
        _currentDateStamp == today &&
        _currentFile!.existsSync() &&
        _currentFile!.lengthSync() + nextBytes <= _maxFileBytes) {
      return _currentFile!;
    }

    _currentDateStamp = today;
    _currentFile = _findWritableFileSync(today, nextBytes);
    return _currentFile!;
  }

  Future<File> _findWritableFile(String dateStamp, int nextBytes) async {
    for (var index = 0; index < _maxFiles; index++) {
      final file = _fileFor(dateStamp, index);
      if (!await file.exists() ||
          await file.length() + nextBytes <= _maxFileBytes) {
        return file;
      }
    }
    await _prune(forceOne: true);
    for (var index = 0; index < _maxFiles; index++) {
      final file = _fileFor(dateStamp, index);
      if (!await file.exists() ||
          await file.length() + nextBytes <= _maxFileBytes) {
        return file;
      }
    }
    return _fileFor(dateStamp, _maxFiles);
  }

  File _findWritableFileSync(String dateStamp, int nextBytes) {
    for (var index = 0; index < _maxFiles; index++) {
      final file = _fileFor(dateStamp, index);
      if (!file.existsSync() ||
          file.lengthSync() + nextBytes <= _maxFileBytes) {
        return file;
      }
    }
    return _fileFor(dateStamp, _maxFiles - 1);
  }

  File _fileFor(String dateStamp, int index) {
    final suffix = index == 0 ? '' : '.$index';
    return File(path.join(
        _directory.path, '$_filePrefix$dateStamp$suffix$_fileExtension'));
  }

  Future<List<File>> _logFiles() async {
    if (!await _directory.exists()) {
      return const <File>[];
    }

    return _directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
      final name = path.basename(file.path);
      return name.startsWith(_filePrefix) && name.endsWith(_fileExtension);
    }).toList();
  }

  Future<void> _prune({bool forceOne = false}) async {
    final files = await _logFiles();
    final now = DateTime.now();

    for (final file in files) {
      try {
        final stat = await file.stat();
        if (now.difference(stat.modified) > _retention) {
          await file.delete();
        }
      } catch (_) {
        // Best effort.
      }
    }

    final remaining = await _logFiles();
    remaining
        .sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    var totalBytes = 0;
    for (final file in remaining) {
      try {
        totalBytes += await file.length();
      } catch (_) {}
    }

    while (remaining.length > (forceOne ? _maxFiles - 1 : _maxFiles) ||
        totalBytes > _maxTotalBytes) {
      final file = remaining.removeAt(0);
      try {
        totalBytes -= await file.length();
        await file.delete();
      } catch (_) {
        // Best effort.
      }
    }
  }

  String _dateStamp(DateTime time) {
    final utc = time.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
