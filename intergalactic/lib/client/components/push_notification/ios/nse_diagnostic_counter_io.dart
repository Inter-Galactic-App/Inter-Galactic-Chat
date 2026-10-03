import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path/path.dart' as p;

/// The host's half of the extension's diagnostic counter (S&C D1-D6).
///
/// The Notification Service Extension writes one aggregate file of database
/// open outcomes into its own App Group directory. The host does three
/// things with it and nothing else: at launch it logs the aggregate as ONE
/// line of integers and literals (D5: never the raw contents, never a path,
/// never a directory listing); it deletes the file once the measurement
/// window is older than 90 days (D6); and it deletes the file on data reset
/// and when the last account is removed (D6), through the same hooks the
/// notification policy snapshot uses. The host never writes the file.
class NseDiagnosticCounter {
  static const String directoryName = 'nse-diagnostics';
  static const String fileName = 'db-read-counter.json';
  static const int version = 1;
  static const int maxBytes = 4 * 1024;
  static const int windowDays = 90;
  static const List<String> outcomes = [
    'ok',
    'busy',
    'hot_journal',
    'missing',
    'timeout',
  ];
  static const String _source = 'nse-diagnostics';

  @visibleForTesting
  static AppGroupStorageHost? host;

  @visibleForTesting
  static bool? platformIsIOS;

  static bool get _enabled => platformIsIOS ?? PlatformUtils.isIOS;

  /// Logs the aggregate, or deletes an expired file. Safe to call on every
  /// launch and after every account change; it reads and never writes.
  static Future<void> onLaunch({DateTime? now}) async {
    if (!_enabled) {
      return;
    }
    try {
      final path = await _path();
      if (path == null) {
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        return;
      }
      final length = await file.length();
      if (length > maxBytes) {
        // A file over the ceiling is a defect by D2; it is not read.
        await file.delete();
        Log.w(
          'nse_db_read counter over ceiling, deleted bytes=$length',
          category: LogCategory.notifications,
          source: _source,
        );
        return;
      }
      // A file that will not decode is the corruption an appended-to file
      // gets when the extension is cut off at its background deadline. It
      // would otherwise land in the outer catch, which logs and leaves the
      // file on disk to warn again on every launch and every account change;
      // the malformed path below already deletes, so this one does too.
      Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on FormatException {
        await file.delete();
        Log.w(
          'nse_db_read counter undecodable, deleted',
          category: LogCategory.notifications,
          source: _source,
        );
        return;
      }
      final summary = summarize(decoded, now: now ?? DateTime.now().toUtc());
      if (summary == null) {
        await file.delete();
        Log.w(
          'nse_db_read counter malformed, deleted',
          category: LogCategory.notifications,
          source: _source,
        );
        return;
      }
      if (summary.expired) {
        await file.delete();
        Log.i(
          'nse_db_read counter expired, deleted window_age_days=${summary.windowAgeDays}',
          category: LogCategory.notifications,
          source: _source,
        );
        return;
      }
      Log.i(summary.line, category: LogCategory.notifications, source: _source);
    } catch (error) {
      Log.w(
        'nse_db_read counter read failed: ${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
  }

  static Future<void> delete() async {
    if (!_enabled) {
      return;
    }
    try {
      final path = await _path();
      if (path == null) {
        return;
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        Log.i(
          'nse_db_read counter deleted',
          category: LogCategory.notifications,
          source: _source,
        );
      }
    } catch (error) {
      Log.w(
        'nse_db_read counter delete failed: ${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
  }

  static Future<String?> _path() async {
    final target = host ?? const ChannelAppGroupStorageHost();
    final container = await target.containerPath();
    if (container == null || container.isEmpty) {
      return null;
    }
    return p.join(container, directoryName, fileName);
  }

  /// The aggregate line for a decoded document, or null when the document
  /// is not the shape the extension writes. Pure; tested directly.
  @visibleForTesting
  static NseDiagnosticSummary? summarize(
    Object? decoded, {
    required DateTime now,
  }) {
    if (decoded is! Map || decoded['version'] != version) {
      return null;
    }
    // The day is a UTC calendar date; parsed as such, not as local time.
    final opened = DateTime.tryParse(
      '${decoded['window_opened_day']}T00:00:00Z',
    );
    if (opened == null) {
      return null;
    }
    final windowAgeDays = now.difference(opened.toUtc()).inDays;
    final counters = _intMap(decoded['counters']);
    final codes = _intMap(decoded['extended_codes']);
    final buffer = StringBuffer('nse_db_read window_age_days=$windowAgeDays');
    for (final outcome in outcomes) {
      var total = 0;
      for (final entry in counters.entries) {
        if (entry.key == outcome || entry.key.startsWith('$outcome.')) {
          total += entry.value;
        }
      }
      buffer.write(' $outcome=$total');
    }
    final streak = decoded['streak'];
    if (streak is Map &&
        outcomes.contains(streak['outcome']) &&
        streak['runs'] is int) {
      buffer.write(' streak=${streak['outcome']}:${streak['runs']}');
    } else {
      buffer.write(' streak=none');
    }
    final closed = decoded['closed_streaks'];
    final closedParts = <String>[];
    if (closed is Map) {
      for (final outcome in outcomes) {
        final histogram = _intMap(closed[outcome]);
        for (final entry in histogram.entries) {
          if (_isBucket(entry.key)) {
            closedParts.add('$outcome:${entry.key}=${entry.value}');
          }
        }
      }
    }
    buffer.write(
      ' closed=${closedParts.isEmpty ? 'none' : closedParts.join(',')}',
    );
    final codeParts = <String>[
      for (final entry in codes.entries)
        if (int.tryParse(entry.key) != null || entry.key == 'other')
          '${entry.key}:${entry.value}',
    ];
    buffer.write(' ext=${codeParts.isEmpty ? 'none' : codeParts.join(',')}');
    return NseDiagnosticSummary(
      line: buffer.toString(),
      windowAgeDays: windowAgeDays,
      expired: windowAgeDays > windowDays,
    );
  }

  static bool _isBucket(String key) => const {
    'lt1m',
    'lt5m',
    'lt30m',
    'lt2h',
    'lt12h',
    'lt24h',
    'ge24h',
  }.contains(key);

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is int)
          entry.key as String: entry.value as int,
    };
  }
}

class NseDiagnosticSummary {
  const NseDiagnosticSummary({
    required this.line,
    required this.windowAgeDays,
    required this.expired,
  });

  final String line;
  final int windowAgeDays;
  final bool expired;
}
