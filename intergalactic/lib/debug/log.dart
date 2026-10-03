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
import 'package:intergalactic/debug/resolver_native_probe.dart';
import 'package:intergalactic/debug/resolver_retry_probe.dart';
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
  /// Marks a request whose failure is already handled by its optional caller.
  ///
  /// The zone callback still sees such failures while they travel through the
  /// asynchronous runtime, even when the originating caller catches them.
  /// Keep this key private to in-memory zone state: it must never become a
  /// hostname, endpoint, or payload diagnostic.
  static final Object handledOptionalNetworkRequestZoneKey = Object();
  static final Object resolverDiagnosticOriginZoneKey = Object();

  /// Carries one of the explicitly allow-listed Matrix operation classes to
  /// the zone callback. A zone can be inherited by asynchronous SDK work, so
  /// operation names must describe their actual scope.
  static final Object matrixNetworkOperationZoneKey = Object();
  static const String matrixSdkLifecycleOperation = 'matrix_sdk_lifecycle';
  static const String matrixSyncDispatchOperation = 'matrix_sync_dispatch';
  static const String matrixPresenceUpdateOperation = 'matrix_presence_update';
  static const String matrixHttpSyncOperation = 'matrix_http_sync';
  static const String matrixHttpPresenceOperation = 'matrix_http_presence';
  static const String matrixHttpMediaOperation = 'matrix_http_media';
  static const String matrixHttpKeysOperation = 'matrix_http_keys';
  static const String matrixHttpTimelineOperation = 'matrix_http_timeline';
  static const String matrixHttpClientApiOperation = 'matrix_http_client_api';
  static const String matrixHttpOtherOperation = 'matrix_http_other';

  static final NotifyingList<LogEntry> log = NotifyingList.empty(
    growable: true,
  );
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
  static Stopwatch? _startupStopwatch;
  static String _startupPhase = 'unknown';
  static const Duration networkDiagnosticWindow = Duration(minutes: 45);
  static const Duration _resolverRetryProbeInterval = Duration(minutes: 1);
  static const Duration _callMemberPrintLogInterval = Duration(minutes: 5);
  static final MatrixDecryptLogSummarizer _matrixDecryptPrintSummarizer =
      MatrixDecryptLogSummarizer(sourceLabel: 'sdk-print');
  static DateTime? _lastCallMemberPrintLogAt;
  static int _suppressedCallMemberPrintLogCount = 0;
  static final Map<String, DateTime> _lastResolverRetryProbeAt = {};

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

  /// Starts the process-local clock used only to contextualize early startup
  /// network diagnostics. It intentionally stores neither host names nor
  /// interface details.
  static void beginStartupTelemetry() {
    _startupStopwatch ??= Stopwatch()..start();
    _startupPhase = 'entry';
  }

  /// Records the coarse application stage around startup-only diagnostics.
  static void recordStartupPhase(String phase) {
    _startupPhase = phase;
  }

  static int? get startupElapsedMilliseconds =>
      _startupStopwatch?.elapsedMilliseconds;

  static String get startupPhase => _startupPhase;

  /// Bounded, redacted context for transient network failures surfaced by the
  /// root zone before a Matrix HTTP request wrapper can observe them.
  @visibleForTesting
  static String startupNetworkDiagnosticFields(Object error, {Zone? zone}) {
    final elapsedMilliseconds = startupElapsedMilliseconds;
    if (elapsedMilliseconds == null ||
        elapsedMilliseconds > networkDiagnosticWindow.inMilliseconds) {
      return '';
    }

    final resolverOutcome =
        error.toString().toLowerCase().contains('errno = 11004')
        ? 'nodata'
        : 'other';
    final resolverTarget = resolverTargetClass(error);
    final matrixOperation = resolverTarget == 'matrix'
        ? _matrixNetworkOperation(zone ?? Zone.current)
        : null;
    return ' startup_ms=$elapsedMilliseconds startup_phase=$startupPhase '
        'resolver_outcome=$resolverOutcome resolver_target=$resolverTarget'
        '${matrixOperation == null ? '' : ' matrix_operation=$matrixOperation'}';
  }

  @visibleForTesting
  static bool shouldLogTransientNetworkZoneError(Object error, Zone zone) =>
      isTransientNetworkZoneError(error) &&
      zone[handledOptionalNetworkRequestZoneKey] != true;

  static String? _matrixNetworkOperation(Zone zone) {
    final operation = zone[matrixNetworkOperationZoneKey];
    return switch (operation) {
      matrixSdkLifecycleOperation ||
      matrixSyncDispatchOperation ||
      matrixPresenceUpdateOperation ||
      matrixHttpSyncOperation ||
      matrixHttpPresenceOperation ||
      matrixHttpMediaOperation ||
      matrixHttpKeysOperation ||
      matrixHttpTimelineOperation ||
      matrixHttpClientApiOperation ||
      matrixHttpOtherOperation => operation as String,
      _ => null,
    };
  }

  /// Returns a fixed diagnostic host only for the existing allow-list. This
  /// prevents an exception message from becoming a new lookup target.
  @visibleForTesting
  static String? resolverRetryProbeHost(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('matrix.ourgalaxy.space')) {
      return 'matrix.ourgalaxy.space';
    }
    if (normalized.contains('app.ourgalaxy.space'))
      return 'app.ourgalaxy.space';
    if (normalized.contains('www.tiktok.com')) return 'www.tiktok.com';
    if (normalized.contains('ourgalaxy.space')) return 'ourgalaxy.space';
    return null;
  }

  /// Redacts a transient error stack to the smallest caller family useful for
  /// choosing a future, idempotent recovery layer. Never return stack text,
  /// source paths, symbols, hosts, or payloads.
  @visibleForTesting
  static String transientNetworkCallerClass(StackTrace? stackTrace) {
    final normalized = stackTrace?.toString().toLowerCase() ?? '';
    if (normalized.contains('package:intergalactic/client/matrix/')) {
      return 'matrix_client';
    }
    if (normalized.contains('package:matrix/')) return 'matrix_sdk';
    if (normalized.contains('spotify')) return 'spotify';
    if (normalized.contains('package:intergalactic/')) return 'app_other';
    return 'unknown';
  }

  @visibleForTesting
  static String resolverLookupStackClass(StackTrace? trace) {
    final frames = RegExp(
      // VM frame names can contain spaces in <anonymous closure>. Capture
      // only this line, up to the complete allow-listed SDK source location.
      r'^#\d+[ \t]+([^\r\n]+?)[ \t]+\(dart:io(?:-patch)?/socket_patch\.dart:\d+:\d+\)[ \t]*\r?$',
      multiLine: true,
    ).allMatches(trace?.toString() ?? '').map((match) => match.group(1)).toSet();
    if (frames.contains('_NativeSocket.staggeredLookup.lookupAddresses') ||
        frames.contains(
          '_NativeSocket.staggeredLookup.<anonymous closure>.lookupAddresses',
        )) {
      return 'staggered_family_lookup';
    }
    // The private lookup closure alone is common to both paths, not proof
    // of a direct lookup. Require the public direct-lookup frame.
    if (frames.contains('InternetAddress.lookup') &&
        !frames.any(
          (frame) =>
              frame?.startsWith('_NativeSocket.staggeredLookup') ?? false,
        )) {
      return 'direct_lookup';
    }
    return 'unknown';
  }

  static void _scheduleResolverRetryProbe(Object error, StackTrace? trace) {
    if (!verboseDiagnosticsEnabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.windows ||
        Zone.current[resolverDiagnosticOriginZoneKey] == true)
      return;

    final startupFields = startupNetworkDiagnosticFields(error);
    if (startupFields.isEmpty) return;

    final host = resolverRetryProbeHost(error);
    if (host == null) return;

    final now = DateTime.now();
    final lastAttempt = _lastResolverRetryProbeAt[host];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _resolverRetryProbeInterval) {
      return;
    }
    _lastResolverRetryProbeAt[host] = now;

    final initialOutcome =
        error.toString().toLowerCase().contains('errno = 11004')
        ? 'nodata'
        : 'other';
    final target = resolverTargetClass(error);
    runOptionalResolverDiagnostic(
      () => _recordResolverRetryProbe(
        host: host,
        target: target,
        initialOutcome: initialOutcome,
        startupFields: startupFields,
        stackClass: resolverLookupStackClass(trace),
      ),
    );
  }

  /// The paired lookup is optional evidence. Its own failure must never enter
  /// the root error callback that started it (or launch another probe).
  @visibleForTesting
  static void runOptionalResolverDiagnostic(Future<void> Function() operation) {
    runZoned(() {
      unawaited(
        Future<void>.sync(
          operation,
        ).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
    }, zoneValues: {resolverDiagnosticOriginZoneKey: true});
  }

  static Future<void> _recordResolverRetryProbe({
    required String host,
    required String target,
    required String initialOutcome,
    required String startupFields,
    required String stackClass,
  }) async {
    final families = probeResolverFamilies(host);
    if (families == null) return;
    final results = await Future.wait([
      probeResolverRetry(host),
      probeNativeResolver(host),
      families,
    ]);
    final result = results[0] as ResolverRetryProbeResult;
    final nativeResult = results[1] as NativeResolverProbeResult;
    add(
      LogEntry(
        LogType.warning,
        'Resolver retry probe initial_outcome=$initialOutcome '
        'resolver_target=$target retry_outcome=${result.outcome} '
        'retry_ms=${result.elapsed.inMilliseconds}'
        '${nativeResolverProbeFields(nativeResult)}'
        '${resolverFamilyProbeFields(results[2] as ResolverFamilyProbeResult)}'
        ' lookup_stack=$stackClass$startupFields',
        category: LogCategory.app,
        source: 'zone-network-retry-probe',
      ),
    );
  }

  /// Fixed-field native probe context. It intentionally has no host, address,
  /// interface, or provider data.
  @visibleForTesting
  static String nativeResolverProbeFields(NativeResolverProbeResult result) {
    final errorCode = result.errorCode?.toString() ?? 'none';
    return ' native_outcome=${result.outcome} native_code=$errorCode '
        'native_ms=${result.elapsed.inMilliseconds}';
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
    final isDuplicate =
        log.isNotEmpty &&
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
        add(
          LogEntry(
            LogType.info,
            line,
            category: _categoryForPrefix(),
            source: prefix.isEmpty ? 'print' : prefix,
          ),
        );
      }
    },
    errorCallback: (self, parent, zone, error, stackTrace) {
      // This observes error introduction, not just uncaught errors. Probe
      // work must not masquerade as another original failure or recurse.
      if (zone[resolverDiagnosticOriginZoneKey] == true) return null;
      final requestPath = matrixRequestPathHint(error);
      if (isTransientNetworkZoneError(error)) {
        if (!shouldLogTransientNetworkZoneError(error, zone)) {
          return null;
        }
        final message = error.toString();
        final startupFields = startupNetworkDiagnosticFields(error, zone: zone);
        final callerClass = transientNetworkCallerClass(stackTrace);
        _scheduleResolverRetryProbe(error, stackTrace);
        add(
          LogEntry(
            LogType.warning,
            'Transient async network error: $message request_path=$requestPath'
            '$startupFields caller_class=$callerClass',
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
      String? info = stackTrace != null
          ? getDetailFromStackTrace(stackTrace)
          : null;
      add(
        LogEntryException(
          LogType.error,
          "${error.toString()}${info != null ? " ($info)" : ""} "
          "request_path=$requestPath",
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

    return lower.contains(
          '[voip] handling event of type: '
          'org.matrix.msc3401.call.member',
        ) &&
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
    _print(
      LogEntry(
        LogType.info,
        str,
        category: category ?? _categoryForMessage(message),
        source: source ?? _sourceForPrefix(),
      ),
    );
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
      _print(
        LogEntry(
          LogType.debug,
          str,
          category: category ?? _categoryForMessage(message),
          source: source ?? _sourceForPrefix(),
        ),
      );
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
    Function(FlutterErrorDetails)? current,
  ) {
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
    return _tailByUtf8Bytes(redactSensitiveInfo(buffer.toString()), maxBytes);
  }

  static void _onFlutterError(FlutterErrorDetails details) {
    String? info = details.stack != null
        ? getDetailFromStackTrace(details.stack!)
        : null;
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
  }) => _shouldRecordPendingCrashReport(source: source, content: content);

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

  @visibleForTesting
  static bool isTransientNetworkZoneError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('socketexception: failed host lookup') ||
        normalized.contains(
          'httpexception: connection closed before full header was received',
        ) ||
        normalized.contains('socketexception: connection reset') ||
        normalized.contains('socketexception: connection refused') ||
        normalized.contains('socketexception: connection timed out') ||
        // iOS background/resume tears sockets down underneath in-flight
        // requests, so the fd is already closed (or the host unreachable) by
        // the time the error surfaces. This is lifecycle churn, not a fault
        // worth force-persisting as an error. Matches both the SocketException
        // and HttpException wordings the platform emits.
        //
        // Scoped to those two exception types on purpose: an unscoped
        // substring match would reclassify any unrelated error whose message
        // happens to contain this wording as a transient warning, and it would
        // then skip force-persisting and be lost to crash-report harvesting.
        (_isSocketOrHttpException(normalized) &&
            (normalized.contains('bad file descriptor') ||
                normalized.contains('no route to host')));
  }

  static bool _isSocketOrHttpException(String normalizedError) {
    return normalizedError.contains('socketexception') ||
        normalizedError.contains('httpexception');
  }

  /// Best-effort endpoint label for a network error, derived from any request
  /// URI the error carried. Computed before bug-report redaction collapses the
  /// whole `/_matrix/...` path to a single placeholder, so exported logs can
  /// still distinguish `/sync` from `/presence` from media.
  ///
  /// Also accepts a request URL directly: `MatrixUserAgentHttpClient` classifies
  /// its in-flight request through this same function so the endpoint labels it
  /// logs match the ones emitted here for errors that do carry a URI.
  ///
  /// Errors carrying no URI at all fall back to a failure-mode label (`dns`,
  /// `http-keepalive`) or, failing that, `socket`.
  static String matrixRequestPathHint(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('/sync')) return 'sync';
    if (normalized.contains('/presence/')) return 'presence';
    if (normalized.contains('/_matrix/media/') ||
        normalized.contains('/thumbnail') ||
        normalized.contains('/download/')) {
      return 'media';
    }
    if (normalized.contains('/keys/') || normalized.contains('/room_keys/')) {
      return 'keys';
    }
    if (normalized.contains('/messages') ||
        normalized.contains('/send/') ||
        normalized.contains('/context/')) {
      return 'timeline';
    }
    if (normalized.contains('/_matrix/client')) return 'client-api';
    if (normalized.contains('uri =') || normalized.contains('uri=')) {
      return 'other';
    }
    // No endpoint anywhere in the message. Two failures dominate this bucket
    // and can never carry a URI: a host lookup fails before any connection
    // exists, and Dart omits the URI when a connection dies before response
    // headers arrive. Naming them separately keeps the unknown bucket from
    // collapsing every distinct cause into a single opaque `socket`.
    if (normalized.contains('failed host lookup')) return 'dns';
    if (normalized.contains('connection closed before full header')) {
      return 'http-keepalive';
    }
    return 'socket';
  }

  /// Maps the fixed, redacted request-path vocabulary to the only endpoint
  /// operation labels permitted at the root network callback.
  static String matrixHttpOperationForRequestPath(String requestPath) {
    return switch (requestPath) {
      'sync' => matrixHttpSyncOperation,
      'presence' => matrixHttpPresenceOperation,
      'media' => matrixHttpMediaOperation,
      'keys' => matrixHttpKeysOperation,
      'timeline' => matrixHttpTimelineOperation,
      'client-api' => matrixHttpClientApiOperation,
      _ => matrixHttpOtherOperation,
    };
  }

  /// Returns an allow-listed diagnostic target class, never a hostname.
  @visibleForTesting
  static String resolverTargetClass(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('matrix.ourgalaxy.space')) return 'matrix';
    if (normalized.contains('app.ourgalaxy.space')) return 'app';
    if (normalized.contains('ourgalaxy.space')) return 'root';
    if (normalized.contains('www.tiktok.com')) return 'third_party';
    return 'other';
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
