import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/file_utils.dart';
import 'package:intergalactic/utils/local_file.dart';

String diagnosticLogFolderExportStatus(String? directoryPath) {
  return directoryPath == null || directoryPath.trim().isEmpty
      ? 'unavailable'
      : 'available';
}

class DeveloperLogActions {
  const DeveloperLogActions._();

  static Future<String> saveLogs() async {
    final data = await getAllLogData();
    final bytes = Uint8List.fromList(utf8.encode(data));
    final fileName =
        "inter-galactic-logs-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.txt";
    String? destinationPath;

    if (kIsWeb || PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      destinationPath = await FilePicker.platform.saveFile(
        fileName: fileName,
        bytes: bytes,
      );
    } else {
      destinationPath = await FilePicker.platform.saveFile(fileName: fileName);
      if (destinationPath != null) {
        await writeLocalFileBytes(destinationPath, bytes);
      }
    }

    return destinationPath ?? '';
  }

  static Future<void> openLogFolder() async {
    await Log.initialize(options: Log.runtimeOptions);
    final directory = Log.logDirectoryPath;
    if (directory == null) {
      throw StateError('Diagnostic log folder is unavailable');
    }
    await FileUtils.openDirectory(directory);
  }

  static Future<void> copyRecentLogs() async {
    final data = await getRecentLogData();
    await Clipboard.setData(ClipboardData(text: data));
  }

  static Future<void> clearLogs() async {
    await Log.clear();
    Log.i("Diagnostic logs cleared", source: "developer-logs");
  }

  static Future<String> getAllLogData() async {
    final buffer = await _buildLogHeader("Inter Galactic Logs");
    for (final entry in Log.log) {
      buffer
        ..writeln(
          "[${entry.time.toUtc().toIso8601String()}] ${entry.type.name.toUpperCase()} ${entry.category.name} ${entry.source ?? '-'} x${entry.count}",
        )
        ..writeln(entry.content.trim());

      if (entry is LogEntryException && entry.trace != null) {
        buffer
          ..writeln("Stack Trace:")
          ..writeln(entry.trace);
      }

      buffer.writeln();
    }

    final fileLogs = await Log.recentText();
    if (fileLogs.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(fileLogs);
    }

    return Log.redactSensitiveInfo(buffer.toString());
  }

  static Future<String> getRecentLogData() async {
    final buffer = await _buildLogHeader("Inter Galactic Recent Logs");
    final recent = await Log.recentText();
    buffer.writeln(recent.trim().isEmpty ? "No logs available." : recent);
    return Log.redactSensitiveInfo(buffer.toString());
  }

  static Future<StringBuffer> _buildLogHeader(String title) async {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln("Exported: ${DateTime.now().toUtc().toIso8601String()}")
      ..writeln("Platform: ${BuildConfig.PLATFORM}")
      ..writeln("Version: ${BuildConfig.VERSION_TAG}")
      ..writeln("Git Hash: ${BuildConfig.GIT_HASH}")
      ..writeln("Build: ${BuildConfig.buildDetailDisplay}")
      ..writeln(
        "Log Folder: ${diagnosticLogFolderExportStatus(Log.logDirectoryPath)}",
      )
      ..writeln();
    return buffer;
  }
}
