import 'dart:convert';

enum BugReportSeverity {
  critical,
  high,
  medium,
  low,
  unknown;

  String get wireValue => name;

  String get label {
    return switch (this) {
      BugReportSeverity.critical => 'Critical',
      BugReportSeverity.high => 'High',
      BugReportSeverity.medium => 'Medium',
      BugReportSeverity.low => 'Low',
      BugReportSeverity.unknown => 'Unknown',
    };
  }
}

enum BugReportTemplate {
  genericAppBug,
  callStreamLogs;

  String get tag {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'generic_app_bug',
      BugReportTemplate.callStreamLogs => 'call_stream_logs',
    };
  }

  String get label {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Generic app bug',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  bool get usesFixedDetails => this == BugReportTemplate.callStreamLogs;

  String get defaultTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  String get defaultReproductionSteps {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs => 'Call/stream logs template.\n\n'
          'Opened from Call Diagnostics > stream logs. Recent redacted logs '
          'include the current call diagnostics snapshot for support review.',
    };
  }

  String get defaultExpectedBehavior {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs =>
        'Call and stream diagnostics should include enough route, sender, '
            'receiver, stream-test, and recent redacted log context to classify '
            'the issue without changing the active media path.',
    };
  }

  String get defaultActualBehavior {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs =>
        'The current call diagnostics snapshot was written into recent '
            'redacted logs. Keep logs enabled to attach that snapshot with this '
            'call/stream report.',
    };
  }
}

class BugReportInput {
  const BugReportInput({
    required this.title,
    required this.reproductionSteps,
    this.template = BugReportTemplate.genericAppBug,
    this.severity = BugReportSeverity.medium,
    this.expectedBehavior = '',
    this.actualBehavior = '',
    this.includeLogs = true,
    this.includeDiagnostics = true,
    this.additionalMetadata = const {},
    this.additionalAttachments = const [],
    this.reportNotice,
  });

  final String title;
  final String reproductionSteps;
  final BugReportTemplate template;
  final BugReportSeverity severity;
  final String expectedBehavior;
  final String actualBehavior;
  final bool includeLogs;
  final bool includeDiagnostics;
  final Map<String, Object?> additionalMetadata;
  final List<BugReportAttachmentSummary> additionalAttachments;
  final String? reportNotice;

  String? validate() {
    if (title.trim().isEmpty) {
      return 'Enter a title for the bug report.';
    }
    if (reproductionSteps.trim().isEmpty) {
      return 'Enter reproduction steps before previewing the report.';
    }
    return null;
  }
}

class BugReportAttachmentSummary {
  const BugReportAttachmentSummary({
    required this.field,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.contentBase64,
  });

  final String field;
  final String name;
  final String contentType;
  final int sizeBytes;
  final String contentBase64;

  Map<String, Object?> toJson() => {
        'name': name,
        'mimeType': contentType,
        'contentBase64': contentBase64,
      };
}

class BugReportPayload {
  const BugReportPayload({
    required this.data,
    required this.attachments,
  });

  final Map<String, Object?> data;
  final List<BugReportAttachmentSummary> attachments;

  int get sizeBytes => utf8.encode(toCompactJson()).length;

  String toCompactJson() => jsonEncode(data);

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(data);
}

class BugReportSubmissionResult {
  const BugReportSubmissionResult({
    this.reportId,
    required this.message,
    this.responseBody,
  });

  final String? reportId;
  final String message;
  final Map<String, Object?>? responseBody;
}

class BugReportSubmissionException implements Exception {
  const BugReportSubmissionException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}
