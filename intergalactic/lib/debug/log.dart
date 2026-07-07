import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

export 'runtime_diagnostics_options.dart';

import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/diagnostic_log_store.dart';
import 'package:intergalactic/debug/log_redactor.dart';
import 'package:intergalactic/debug/matrix_decrypt_log_summarizer.dart';
import 'package:intergalactic/debug/runtime_diagnostics_options.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/foundation.dart';

enum LogType { info, debug, error, warning }

enum LogCategory { app, matrix, livekit, webrtc, notifications, media }

class LogEntry {
  late DateTime _time;
  LogType type;
  DateTime get time => _time;
  String rawContent;
  LogCategory category;
  String? source;
  int count = 1;

  LogEntry(
    this.type,
    String rawContent, {
    this.category = LogCategory.app,
    this.source,
  }) : rawContent = Log.redactSensitiveInfo(rawContent) {
    _time = DateTime.now();
  }

  String get content {
    return Log.redactSensitiveInfo(rawContent);
  }
}

class LogEntryException extends LogEntry {
  Object exception;
  StackTrace? trace;

  LogEntryException(
    super.type,
    super.rawContent,
    this.exception,
    this.trace, {
    super.category,
    super.source,
  });
}

class Log {
  static final NotifyingList<LogEntry> log =
      NotifyingList.empty(growable: true);
  static final DiagnosticLogStore _store = DiagnosticLogStore();
  static const PendingCrashReportStore _crashReportStore =
      PendingCrashReportStore();

  static String prefix = "";
  static RuntimeDiagnosticsOptions runtimeOptions =
      const RuntimeDiagnosticsOptions();

  static Function(FlutterErrorDetails)? _previousReporter;
  static bool Function(Object, StackTrace)? _previousPlatformErrorHandler;
  static bool _flutterErrorHandlerInstalled = false;
  static bool _platformErrorHandlerInstalled = false;
  static const Duration _callMemberPrintLogInterval = Duration(minutes: 5);
  static final MatrixDecryptLogSummarizer _matrixDecryptPrintSummarizer =
      MatrixDecryptLogSummarizer(sourceLabel: 'sdk-print');
  static DateTime? _lastCallMemberPrintLogAt;
  static int _suppressedCallMemberPrintLogCount = 0;

  static bool get _developerModeEnabled =>
      preferences.isInit && preferences.developerMode.value == true;

  static bool get verboseDiagnosticsEnabled =>
      runtimeOptions.debugLogs ||
      BuildConfig.DEBUG ||
      kDebugMode ||
      _developerModeEnabled;

  static bool get webrtcStatsEnabled => runtimeOptions.webrtcStats;

  static bool get _shouldEmitConsoleLogs => verboseDiagnosticsEnabled;

  static String? get logDirectoryPath => _store.logDirectoryPath;

  static Future<void> initialize({
    RuntimeDiagnosticsOptions options = const RuntimeDiagnosticsOptions(),
  }) async {
    runtimeOptions = options;
    if (_store.isInitialized) {
      return;
    }

    try {
      await _store.initialize();
    } catch (_) {
      // File logging is diagnostic-only and must never block app startup.
    }
  }

  static void configureRuntimeOptions(RuntimeDiagnosticsOptions options) {
    runtimeOptions = options;
  }

  static void installFlutterErrorHandler() {
    if (_flutterErrorHandlerInstalled) {
      return;
    }
    FlutterError.onError = getFlutterErrorReporter(FlutterError.onError);
    _flutterErrorHandlerInstalled = true;
  }

  static void installPlatformDispatcherErrorHandler() {
    if (_platformErrorHandlerInstalled) {
      return;
    }

    _previousPlatformErrorHandler = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = _onPlatformDispatcherError;
    _platformErrorHandlerInstalled = true;
  }

  static void add(
    LogEntry entry, {
    bool forcePersist = false,
    bool flush = false,
  }) {
    final isDuplicate = log.isNotEmpty &&
        log.last.type == entry.type &&
        log.last.category == entry.category &&
        log.last.source == entry.source &&
        log.last.rawContent == entry.rawContent;

    if (isDuplicate) {
      log.last.count += 1;
      return;
    }

    log.add(entry);

    if (forcePersist || _shouldPersist(entry)) {
      _writeEntry(entry, flush: flush);
    }
  }

  static ZoneSpecification spec = ZoneSpecification(
    print: (self, parent, zone, line) {
      if (_shouldEmitConsoleLogs) {
        parent.print(zone, "($prefix) $line");
      }

      if (line.startsWith("[Inter Galactic")) {
        return;
      }

      if (_isNoisyCallMemberPrint(line)) {
        _recordSuppressedCallMemberPrint();
        return;
      }

      if (!preferences.isInit || verboseDiagnosticsEnabled) {
        final handledDecryptLog = _matrixDecryptPrintSummarizer.record(
          line,
          emit: (message) => Log.i(
            message,
            category: LogCategory.matrix,
            source: 'matrix-sdk',
          ),
        );
        if (handledDecryptLog) {
          return;
        }
      }

      if (!preferences.isInit || verboseDiagnosticsEnabled) {
        add(LogEntry(
          LogType.info,
          line,
          category: _categoryForPrefix(),
          source: prefix.isEmpty ? 'print' : prefix,
        ));
      }
    },
    errorCallback: (self, parent, zone, error, stackTrace) {
      if (_isTransientNetworkZoneError(error)) {
        final message = error.toString();
        add(
          LogEntry(
            LogType.warning,
            'Transient async network error: $message',
            category: _categoryForMessage(message),
            source: 'zone-network-callback',
          ),
        );
        return null;
      }

      if (_shouldEmitConsoleLogs) {
        parent.print(zone, "ERROR CALLBACK");
        parent.print(zone, error.toString());
        parent.print(zone, stackTrace?.toString() ?? "");
      }
      String? info =
          stackTrace != null ? getDetailFromStackTrace(stackTrace) : null;
      add(
        LogEntryException(
          LogType.error,
          "${error.toString()}${info != null ? " ($info)" : ""}",
          error,
          stackTrace,
          category: LogCategory.app,
          source: 'zone-error-callback',
        ),
        forcePersist: true,
        flush: true,
      );
      return null;
    },
    handleUncaughtError: (self, parent, zone, error, stackTrace) {
      if (_shouldEmitConsoleLogs) {
        parent.print(zone, "HandleUncaughtError");
      }
      onError(
        error,
        stackTrace,
        content: "${error.toString()} (${getDetailFromStackTrace(stackTrace)})",
        source: 'zone-uncaught-error',
        flush: true,
      );
    },
  );

  static String _formatString(String logsStr, LogType type) {
    switch (type) {
      case LogType.error:
        logsStr = '\x1B[31m$logsStr\x1B[0m';
        break;
      case LogType.warning:
        logsStr = '\x1B[33m$logsStr\x1B[0m';
        break;
      case LogType.info:
        logsStr = '\x1B[32m$logsStr\x1B[0m';
        break;
      case LogType.debug:
        logsStr = '\x1B[34m$logsStr\x1B[0m';
        break;
    }

    return '[Inter Galactic (${Log.prefix})] $logsStr';
  }

  static bool _isNoisyCallMemberPrint(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('ignoring call event org.matrix.msc3401.call.member') &&
        lower.contains('because we do not have the call')) {
      return true;
    }

    return lower.contains('[voip] handling event of type: '
            'org.matrix.msc3401.call.member') &&
        lower.contains('content {}');
  }

  static void _recordSuppressedCallMemberPrint() {
    _suppressedCallMemberPrintLogCount++;
    final now = DateTime.now();
    final last = _lastCallMemberPrintLogAt;
    if (last != null && now.difference(last) < _callMemberPrintLogInterval) {
      return;
    }

    Log.d(
      'Suppressed Matrix SDK call-member print spam '
      'count=$_suppressedCallMemberPrintLogCount',
      category: LogCategory.matrix,
      source: 'matrix-sdk',
    );
    _suppressedCallMemberPrintLogCount = 0;
    _lastCallMemberPrintLogAt = now;
  }

  static void _print(LogEntry entry, {bool forcePersist = false}) {
    add(entry, forcePersist: forcePersist);

    if (_shouldEmitConsoleLogs) {
      // ignore: avoid_print
      print(entry.rawContent);
    }
  }

  static void i(Object o, {LogCategory? category, String? source}) {
    final message = o.toString();
    var str = _formatString(message, LogType.info);
    _print(LogEntry(
      LogType.info,
      str,
      category: category ?? _categoryForMessage(message),
      source: source ?? _sourceForPrefix(),
    ));
  }

  static void e(Object o, {LogCategory? category, String? source}) {
    final message = o.toString();
    var str = _formatString(message, LogType.error);
    _print(
      LogEntry(
        LogType.error,
        str,
        category: category ?? _categoryForMessage(message),
        source: source ?? _sourceForPrefix(),
      ),
      forcePersist: true,
    );
  }

  static void d(Object o, {LogCategory? category, String? source}) {
    if (verboseDiagnosticsEnabled) {
      final message = o.toString();
      var str = _formatString(message, LogType.debug);
      _print(LogEntry(
        LogType.debug,
        str,
        category: category ?? _categoryForMessage(message),
        source: source ?? _sourceForPrefix(),
      ));
    }
  }

  static void w(Object o, {LogCategory? category, String? source}) {
    final message = o.toString();
    var str = _formatString(message, LogType.warning);
    _print(
      LogEntry(
        LogType.warning,
        str,
        category: category ?? _categoryForMessage(message),
        source: source ?? _sourceForPrefix(),
      ),
      forcePersist: true,
    );
  }

  static void onError(
    Object object,
    StackTrace trace, {
    String? content,
    LogCategory? category,
    String? source,
    bool flush = false,
  }) {
    String? info = getDetailFromStackTrace(trace);
    final message = content ?? "${object.toString()} ($info)";
    var entry = LogEntryException(
      LogType.error,
      message,
      object,
      trace,
      category: category ?? _categoryForMessage(message),
      source: source ?? _sourceForPrefix(),
    );
    add(entry, forcePersist: true, flush: flush);
    _recordPendingCrashReportIfNeeded(
      object,
      trace,
      content: message,
      source: source ?? _sourceForPrefix() ?? 'unknown',
    );
    if (_shouldEmitConsoleLogs) {
      // ignore: avoid_print
      print(trace);
    }
  }

  static Function(FlutterErrorDetails) getFlutterErrorReporter(
      Function(FlutterErrorDetails)? current) {
    _previousReporter = current;
    return _onFlutterError;
  }

  static Future<void> flush() => _store.flush();

  static Future<void> clear() async {
    log.clear();
    await _store.clear();
  }

  static Future<String> recentText({int maxFileBytes = 200 * 1024}) async {
    final maxBytes = maxFileBytes;
    final buffer = StringBuffer();
    if (log.isNotEmpty) {
      buffer.writeln('--- In-memory logs ---');
      for (final entry in log) {
        buffer
          ..writeln(
            "[${entry.time.toUtc().toIso8601String()}] "
            "${entry.type.name.toUpperCase()} "
            "${entry.category.name} "
            "${entry.source ?? '-'} x${entry.count}",
          )
          ..writeln(_stripAnsi(entry.content).trim());
        if (entry is LogEntryException && entry.trace != null) {
          buffer
            ..writeln('Stack Trace:')
            ..writeln(entry.trace);
        }
        buffer.writeln();
      }
    }

    final remainingBytes = maxBytes - utf8.encode(buffer.toString()).length;
    final diskLogs = remainingBytes <= 0
        ? ''
        : await _store.recentText(maxBytes: remainingBytes);
    if (diskLogs.trim().isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('--- File logs ---');
      buffer.write(redactSensitiveInfo(diskLogs));
    }
    return _tailByUtf8Bytes(buffer.toString(), maxBytes);
  }

  static void _onFlutterError(FlutterErrorDetails details) {
    String? info =
        details.stack != null ? getDetailFromStackTrace(details.stack!) : null;
    add(
      LogEntryException(
        LogType.error,
        "${details.exception.toString()}${info != null ? " ($info)" : ""}",
        details.exception,
        details.stack,
        category: LogCategory.app,
        source: 'flutter-error',
      ),
      forcePersist: true,
      flush: true,
    );

    _previousReporter?.call(details);
  }

  static bool _onPlatformDispatcherError(Object error, StackTrace stackTrace) {
    onError(
      error,
      stackTrace,
      content: 'Unhandled platform dispatcher error: $error',
      category: LogCategory.app,
      source: 'platform-dispatcher',
      flush: true,
    );
    return _previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
  }

  static void _recordPendingCrashReportIfNeeded(
    Object error,
    StackTrace? stackTrace, {
    required String content,
    required String source,
  }) {
    if (!_shouldRecordPendingCrashReport(source: source, content: content)) {
      return;
    }

    _crashReportStore.recordSync(
      PendingCrashReport.fromError(
        error: error,
        stackTrace: stackTrace,
        source: source,
        content: content,
      ),
      directoryPath: logDirectoryPath,
    );
  }

  @visibleForTesting
  static bool shouldRecordPendingCrashReportForTesting({
    required String source,
    required String content,
  }) =>
      _shouldRecordPendingCrashReport(source: source, content: content);

  static bool _shouldRecordPendingCrashReport({
    required String source,
    required String content,
  }) {
    if (PendingCrashReport.shouldRecordForBoundary(
      source: source,
      content: content,
    )) {
      return true;
    }

    // Runtime handlers also catch recoverable async callback failures. Those
    // belong in diagnostics, but they are not proof that the app closed.
    final normalizedSource = source.toLowerCase();
    final normalizedContent = content.toLowerCase();
    if (normalizedSource == 'zone-uncaught-error' ||
        normalizedSource == 'run-zoned-guarded' ||
        normalizedSource == 'zone-error-callback' ||
        normalizedSource == 'flutter-error' ||
        normalizedSource == 'platform-dispatcher' ||
        normalizedContent.startsWith('unhandled app zone error')) {
      return false;
    }

    return false;
  }

  static bool _shouldPersist(LogEntry entry) {
    if (entry.type == LogType.error || entry.type == LogType.warning) {
      return true;
    }
    return verboseDiagnosticsEnabled;
  }

  static void _writeEntry(LogEntry entry, {required bool flush}) {
    final line = _formatFileEntry(entry);
    if (flush) {
      _store.appendSync(line);
    } else {
      unawaited(_store.append(line));
    }
  }

  static String _formatFileEntry(LogEntry entry) {
    final buffer = StringBuffer()
      ..write('[${entry.time.toUtc().toIso8601String()}] ')
      ..write(entry.type.name.toUpperCase())
      ..write(' ')
      ..write(entry.category.name);

    final source = entry.source;
    if (source != null && source.isNotEmpty) {
      buffer.write('/$source');
    }

    if (entry.count > 1) {
      buffer.write(' x${entry.count}');
    }

    buffer
      ..write(' ')
      ..writeln(_stripAnsi(entry.content).trimRight());

    if (entry is LogEntryException && entry.trace != null) {
      buffer
        ..writeln('Stack Trace:')
        ..writeln(entry.trace);
    }

    return redactSensitiveInfo(buffer.toString());
  }

  static LogCategory _categoryForPrefix() {
    final normalized = prefix.toLowerCase();
    if (normalized.contains('fcm') ||
        normalized.contains('push') ||
        normalized.contains('notification') ||
        normalized.contains('background-service')) {
      return LogCategory.notifications;
    }
    if (normalized.contains('matrix')) {
      return LogCategory.matrix;
    }
    if (normalized.contains('livekit')) {
      return LogCategory.livekit;
    }
    if (normalized.contains('webrtc') || normalized.contains('rtc')) {
      return LogCategory.webrtc;
    }
    if (normalized.contains('media') ||
        normalized.contains('image') ||
        normalized.contains('download')) {
      return LogCategory.media;
    }
    return LogCategory.app;
  }

  static LogCategory _categoryForMessage(String message) {
    final prefixCategory = _categoryForPrefix();
    if (prefixCategory != LogCategory.app) {
      return prefixCategory;
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('notification') ||
        normalized.contains('pusher') ||
        normalized.contains('fcm') ||
        normalized.contains('push ')) {
      return LogCategory.notifications;
    }
    if (normalized.contains('livekit')) {
      return LogCategory.livekit;
    }
    if (normalized.contains('webrtc') || normalized.contains('matrixrtc')) {
      return LogCategory.webrtc;
    }
    if (normalized.contains('matrix') ||
        normalized.contains('sync') ||
        normalized.contains('vodozemac') ||
        normalized.contains('decrypt')) {
      return LogCategory.matrix;
    }
    if (normalized.contains('media') ||
        normalized.contains('image') ||
        normalized.contains('download') ||
        normalized.contains('audio') ||
        normalized.contains('video')) {
      return LogCategory.media;
    }
    return LogCategory.app;
  }

  static bool _isTransientNetworkZoneError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('socketexception: failed host lookup') ||
        normalized.contains(
          'httpexception: connection closed before full header was received',
        ) ||
        normalized.contains('socketexception: connection reset') ||
        normalized.contains('socketexception: connection refused') ||
        normalized.contains('socketexception: connection timed out');
  }

  static String? _sourceForPrefix() {
    return prefix.isEmpty ? null : prefix;
  }

  static String redactSensitiveInfo(String text) {
    return LogRedactor.redactForBugReport(TextUtils.redactSensitiveInfo(text));
  }

  static String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  static String _tailByUtf8Bytes(String text, int maxBytes) {
    if (maxBytes <= 0) {
      return '';
    }

    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) {
      return text;
    }

    const marker =
        '--- Earlier log output omitted to keep this export bounded ---\n';
    final markerBytes = utf8.encode(marker);
    if (markerBytes.length >= maxBytes) {
      return utf8.decode(
        bytes.sublist(bytes.length - maxBytes),
        allowMalformed: true,
      );
    }

    final tailBudget = maxBytes - markerBytes.length;
    return marker +
        utf8.decode(
          bytes.sublist(bytes.length - tailBudget),
          allowMalformed: true,
        );
  }

  static String? getDetailFromStackTrace(StackTrace stack) {
    String? info;

    var str = stack.toString();
    var match = RegExp(r"([a-zA-Z0-9_]*)\.([a-zA-Z0-9_]*)").firstMatch(str);
    if (match != null) {
      info = str.substring(match.start, match.end);
    }

    return info;
  }
}
