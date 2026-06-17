import 'dart:io';

import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

class PendingCrashReportStore {
  const PendingCrashReportStore();

  static const _fileName = 'pending-crash-report.json';

  Future<void> record(
    PendingCrashReport report, {
    String? directoryPath,
  }) async {
    try {
      final file = await _file(directoryPath: directoryPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(report.toJsonString(), flush: true);
    } catch (_) {
      // Crash report markers are best-effort diagnostics only.
    }
  }

  void recordSync(
    PendingCrashReport report, {
    String? directoryPath,
  }) {
    final normalized = _normalizedDirectoryPath(directoryPath);
    if (normalized == null) {
      return;
    }

    try {
      final file = _fileSync(normalized);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(report.toJsonString(), flush: true);
    } catch (_) {
      // Crash report markers are best-effort diagnostics only.
    }
  }

  Future<PendingCrashReport?> readPending({String? directoryPath}) async {
    try {
      final file = await _file(directoryPath: directoryPath);
      if (!await file.exists()) {
        return null;
      }
      final report = PendingCrashReport.tryParse(await file.readAsString());
      if (report == null) {
        await _delete(file);
      }
      return report;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPending({String? directoryPath}) async {
    try {
      await _delete(await _file(directoryPath: directoryPath));
    } catch (_) {
      // Best-effort user choice persistence.
    }
  }

  Future<File> _file({String? directoryPath}) async {
    final normalized = _normalizedDirectoryPath(directoryPath);
    final baseDirectory = normalized ?? await AppConfig.getLogDirectoryPath();
    return _fileSync(baseDirectory);
  }

  String? _normalizedDirectoryPath(String? directoryPath) {
    final normalized = directoryPath?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  File _fileSync(String directoryPath) {
    return File(path.join(directoryPath, _fileName));
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
