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
      if (stack.isNotEmpty) ...[
        '',
        'Stack trace:',
        stack,
      ],
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

  static String _redact(String value) {
    return LogRedactor.redactForBugReport(
      TextUtils.redactSensitiveInfo(value),
    );
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
