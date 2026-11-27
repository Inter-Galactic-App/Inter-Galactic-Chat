import 'dart:convert';

import 'package:intergalactic/debug/log_redactor.dart';
import 'package:intergalactic/utils/text_utils.dart';

class PendingCrashReport {
  const PendingCrashReport({
    required this.occurredAt,
    required this.source,
    required this.summary,
    required this.details,
  });

  final DateTime occurredAt;
  final String source;
  final String summary;
  final String details;

  factory PendingCrashReport.nativeCallJoinGuard({
    required String source,
    required String callKind,
    DateTime? occurredAt,
  }) {
    return _nativeCallGuardReport(
      source: source,
      kindLabel: 'Call type',
      kindValue: callKind.trim().isEmpty ? 'call' : callKind,
      guardTitle: 'Native call join crash guard',
      explanation:
          'Inter Galactic wrote this marker before entering native WebRTC call '
          'setup and clears it after Dart observes a successful or handled '
          'failed join. If this marker is offered on next launch, the previous '
          'run likely ended during native call setup before Dart could capture '
          'a stack trace.',
      occurredAt: occurredAt,
    );
  }

  factory PendingCrashReport.nativeCallActionGuard({
    required String source,
    required String actionKind,
    DateTime? occurredAt,
  }) {
    return _nativeCallGuardReport(
      source: source,
      kindLabel: 'Call action',
      kindValue: actionKind.trim().isEmpty ? 'call action' : actionKind,
      guardTitle: 'Native call action crash guard',
      explanation:
          'Inter Galactic wrote this marker before entering native WebRTC/LiveKit '
          'call action work and clears it after Dart observes a successful or '
          'handled failed completion. If this marker is offered on next launch, '
          'the previous run likely ended during native call action work before '
          'Dart could capture a stack trace.',
      occurredAt: occurredAt,
    );
  }

  static PendingCrashReport _nativeCallGuardReport({
    required String source,
    required String kindLabel,
    required String kindValue,
    required String guardTitle,
    required String explanation,
    DateTime? occurredAt,
  }) {
    final safeSource = _redact(source.trim().isEmpty ? 'unknown' : source);
    final safeKind = _limitLine(_redact(kindValue), 80);
    final timestamp = (occurredAt ?? DateTime.now()).toUtc();
    final summary = '$guardTitle: $safeKind did not complete';
    final details = [
      guardTitle,
      'Crash source: $safeSource',
      '$kindLabel: $safeKind',
      'Started at: ${timestamp.toIso8601String()}',
      '',
      explanation,
    ].join('\n');

    return PendingCrashReport(
      occurredAt: timestamp,
      source: safeSource,
      summary: _limitLine(summary, 180),
      details: _limitText(details, 12000),
    );
  }

  factory PendingCrashReport.fromError({
    required Object error,
    required StackTrace? stackTrace,
    required String source,
    String? content,
    DateTime? occurredAt,
  }) {
    final safeSource = _redact(source.trim().isEmpty ? 'unknown' : source);
    final errorType = _redact(_safeObjectDescription(error.runtimeType));
    final errorText = _redact(_safeObjectDescription(error));
    final stack = _redact(stackTrace?.toString() ?? '').trim();
    final safeContent = _redact(content ?? errorText).trim();
    final summary = _limitLine(
      safeContent.isEmpty ? '$errorType from $safeSource' : safeContent,
      180,
    );
    final details = [
      'Crash source: $safeSource',
      'Error type: $errorType',
      'Error:',
      errorText,
      if (stack.isNotEmpty) ...['', 'Stack trace:', stack],
    ].join('\n');

    return PendingCrashReport(
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
      source: safeSource,
      summary: summary,
      details: _limitText(details, 12000),
    );
  }

  factory PendingCrashReport.fromJson(Map<String, Object?> json) {
    return PendingCrashReport(
      occurredAt:
          DateTime.tryParse(json['occurred_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: _redact(json['source']?.toString() ?? 'unknown'),
      summary: _limitLine(_redact(json['summary']?.toString() ?? ''), 180),
      details: _limitText(_redact(json['details']?.toString() ?? ''), 12000),
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'source': source,
    'summary': summary,
    'details': details,
  };

  String toJsonString() => jsonEncode(toJson());

  bool get shouldOfferCrashPrompt =>
      shouldRecordForBoundary(source: source, content: summary) ||
      shouldRecordForBoundary(source: source, content: details);

  static bool shouldRecordForBoundary({
    String? source,
    required String content,
  }) {
    if (_isTrustedCrashMarkerSource(source)) {
      return true;
    }

    final normalizedContent = content.toLowerCase();
    if (_containsCrashBoundary(normalizedContent)) {
      return true;
    }

    return false;
  }

  static PendingCrashReport? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return PendingCrashReport.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  static bool _containsCrashBoundary(String normalizedContent) {
    return normalizedContent
        .split('\n')
        .map((line) => line.trimLeft())
        .any(_isCrashBoundaryLine);
  }

  static bool _isCrashBoundaryLine(String normalizedLine) {
    return normalizedLine.startsWith('fatal startup error') ||
        normalizedLine.startsWith('native call join crash guard') ||
        normalizedLine.startsWith('native call action crash guard') ||
        normalizedLine.startsWith('unhandled unified push entrypoint error') ||
        normalizedLine.startsWith('unhandled bubble entrypoint error');
  }

  static bool _isTrustedCrashMarkerSource(String? source) {
    final normalizedSource = source?.trim().toLowerCase();
    return normalizedSource == 'startup' ||
        normalizedSource == 'matrix-livekit-native-call-join' ||
        (normalizedSource?.startsWith('matrix-livekit-native-call-action-') ??
            false) ||
        (normalizedSource?.startsWith('matrix-direct-native-call-action-') ??
            false);
  }

  static String _redact(String value) {
    return LogRedactor.redactForBugReport(TextUtils.redactSensitiveInfo(value));
  }

  static String _safeObjectDescription(Object? value) {
    try {
      return value.toString();
    } catch (_) {
      return '[omitted unsafe value]';
    }
  }

  static String _limitLine(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) {
      return singleLine;
    }
    return '${singleLine.substring(0, maxLength - 3).trimRight()}...';
  }

  static String _limitText(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength).trimRight()}\n\n[truncated]';
  }
}
