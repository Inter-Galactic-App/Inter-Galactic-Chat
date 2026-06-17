import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/debug/log_redactor.dart';

typedef BugReportDeviceInfoLoader = Future<BaseDeviceInfo> Function();
typedef BugReportLogLoader = Future<String> Function({int maxFileBytes});
typedef BugReportHashGenerator = String Function(DateTime timestamp);

class BugReportService {
  BugReportService({
    http.Client? httpClient,
    Uri? endpoint,
    BugReportDeviceInfoLoader? deviceInfoLoader,
    BugReportLogLoader? logLoader,
    BugReportHashGenerator? reportHashGenerator,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 20),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _endpoint = endpoint ?? defaultEndpoint,
        _deviceInfoLoader =
            deviceInfoLoader ?? (() => DeviceInfoPlugin().deviceInfo),
        _logLoader = logLoader ?? Log.recentText,
        _reportHashGenerator = reportHashGenerator ?? _defaultReportHash,
        _clock = clock ?? DateTime.now,
        _timeout = timeout;

  static final Uri defaultEndpoint =
      Uri.parse('https://ourgalaxy.space/api/intergalactic/bug-report');
  static const int maxBugReportLogBytes = 64 * 1024;
  static const int maxBugReportPayloadBytes = 90 * 1024;
  static const int maxBugReportLogPreviewBytes = 4 * 1024;
  static const int _payloadLimitHeadroomBytes = 4 * 1024;
  static const int _maxJsonSafeDepth = 32;
  static const int _maxFallbackAttachmentDetails = 16;
  static const int _maxFallbackMetadataKeys = 32;
  static const int _maxFallbackStringBytes = 192;
  static const String _omittedCircularValue = '[omitted circular value]';
  static const String _omittedNestedValue = '[omitted nested value]';
  static const String _omittedUnsafeValue = '[omitted unsafe value]';
  static const String _omittedUnsafeAttachment =
      '[omitted unsafe attachment content]';

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri _endpoint;
  final BugReportDeviceInfoLoader _deviceInfoLoader;
  final BugReportLogLoader _logLoader;
  final BugReportHashGenerator _reportHashGenerator;
  final DateTime Function() _clock;
  final Duration _timeout;

  static String _defaultReportHash(DateTime timestamp) {
    final random = Random.secure();
    final entropy = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = crypto.sha256.convert(<int>[
      ...utf8.encode(timestamp.toIso8601String()),
      ...entropy,
    ]).toString();
    return 'ig-${digest.substring(0, 24)}';
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<BugReportPayload> buildPayload(BugReportInput input) async {
    final validationError = input.validate();
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final timestamp = _clock().toUtc();
    final reportHash = _reportHashGenerator(timestamp);
    final deviceData = await _loadSafeDeviceData();

    var logs = input.includeLogs ? await _loadSafeLogs() : null;
    final attachmentFilter =
        _filterUnsupportedAdditionalAttachments(input.additionalAttachments);
    var additionalAttachments =
        List<BugReportAttachmentSummary>.of(attachmentFilter.allowed);
    Map<String, Object?>? attachmentTransportFallback;
    var reportNotice = _emptyToNull(input.reportNotice?.trim() ?? '');
    final metadataFilter =
        _filterUnsupportedAdditionalMetadata(input.additionalMetadata);
    var additionalMetadata = Map<String, Object?>.from(metadataFilter.allowed);

    if (attachmentFilter.omitted.isNotEmpty) {
      attachmentTransportFallback = _mergeAttachmentTransportFallback(
        attachmentTransportFallback,
        _unsupportedAttachmentTransportFallback(attachmentFilter.omitted),
      );
    }
    if (metadataFilter.omittedKeys.isNotEmpty) {
      attachmentTransportFallback = _mergeAttachmentTransportFallback(
        attachmentTransportFallback,
        _unsupportedMetadataTransportFallback(metadataFilter.omittedKeys),
      );
    }

    var diagnostics = input.includeDiagnostics
        ? <String, Object?>{
            'device_info': _redactPayloadValue(deviceData, const [
              'diagnostics',
              'device_info',
            ]),
            'runtime_options': {
              'debug_logs': Log.runtimeOptions.debugLogs,
              'webrtc_stats': Log.runtimeOptions.webrtcStats,
              'verbose_diagnostics': Log.verboseDiagnosticsEnabled,
            },
            'log_directory_available': Log.logDirectoryPath != null,
          }
        : null;

    Map<String, Object?> rebuildPayload() => _redactPayload(_payloadData(
          input: input,
          reportNotice: reportNotice,
          additionalMetadata: additionalMetadata,
          timestamp: timestamp,
          reportHash: reportHash,
          deviceData: deviceData,
          logs: logs,
          diagnostics: diagnostics,
          additionalAttachments: additionalAttachments,
          attachmentTransportFallback: attachmentTransportFallback,
        ));

    var payload = rebuildPayload();

    while (_encodedSize(payload) > maxBugReportPayloadBytes && logs != null) {
      final currentPayloadBytes = _encodedSize(payload);
      final currentLogBytes = utf8.encode(logs).length;
      final targetLogBytes = (currentLogBytes -
              (currentPayloadBytes - maxBugReportPayloadBytes) -
              _payloadLimitHeadroomBytes)
          .clamp(0, maxBugReportLogBytes)
          .toInt();
      if (targetLogBytes >= currentLogBytes) {
        break;
      }
      logs = targetLogBytes <= 0
          ? null
          : _emptyToNull(_limitTextBytes(logs, targetLogBytes));
      payload = rebuildPayload();
    }

    if (_encodedSize(payload) > maxBugReportPayloadBytes &&
        diagnostics != null) {
      diagnostics = const {
        'omitted':
            'Detailed diagnostics omitted to keep bug report upload bounded.',
      };
      payload = rebuildPayload();
    }

    while (_encodedSize(payload) > maxBugReportPayloadBytes && logs != null) {
      final currentPayloadBytes = _encodedSize(payload);
      final currentLogBytes = utf8.encode(logs).length;
      final targetLogBytes = (currentLogBytes -
              (currentPayloadBytes - maxBugReportPayloadBytes) -
              _payloadLimitHeadroomBytes)
          .clamp(0, maxBugReportLogBytes)
          .toInt();
      if (targetLogBytes >= currentLogBytes) {
        break;
      }
      logs = targetLogBytes <= 0
          ? null
          : _emptyToNull(_limitTextBytes(logs, targetLogBytes));
      payload = rebuildPayload();
    }

    if (_encodedSize(payload) > maxBugReportPayloadBytes &&
        additionalAttachments.isNotEmpty) {
      attachmentTransportFallback = _attachmentTransportFallback(
        additionalAttachments,
      );
      additionalAttachments = const [];
      payload = rebuildPayload();
    }

    while (_encodedSize(payload) > maxBugReportPayloadBytes && logs != null) {
      final currentPayloadBytes = _encodedSize(payload);
      final currentLogBytes = utf8.encode(logs).length;
      final targetLogBytes = (currentLogBytes -
              (currentPayloadBytes - maxBugReportPayloadBytes) -
              _payloadLimitHeadroomBytes)
          .clamp(0, maxBugReportLogBytes)
          .toInt();
      if (targetLogBytes >= currentLogBytes) {
        break;
      }
      logs = targetLogBytes <= 0
          ? null
          : _emptyToNull(_limitTextBytes(logs, targetLogBytes));
      payload = rebuildPayload();
    }

    if (_encodedSize(payload) > maxBugReportPayloadBytes &&
        (additionalMetadata.isNotEmpty || reportNotice != null)) {
      attachmentTransportFallback = _mergeAttachmentTransportFallback(
        attachmentTransportFallback,
        _metadataTransportFallback(
          additionalMetadata: additionalMetadata,
          omittedReportNotice: reportNotice != null,
        ),
      );
      additionalMetadata = const <String, Object?>{};
      reportNotice = null;
      payload = rebuildPayload();
    }

    if (_encodedSize(payload) > maxBugReportPayloadBytes &&
        attachmentTransportFallback != null) {
      attachmentTransportFallback = _minimalAttachmentTransportFallback(
        attachmentTransportFallback,
      );
      payload = rebuildPayload();
    }

    if (_encodedSize(payload) > maxBugReportPayloadBytes) {
      throw ArgumentError(
        'Bug report payload exceeds upload limit after fallback bounding.',
      );
    }

    return BugReportPayload(
      data: payload,
      attachments: _attachmentsFor(
        logs,
        diagnostics,
        additionalAttachments,
      ),
    );
  }

  Future<Map<String, Object?>> _loadSafeDeviceData() async {
    try {
      final deviceInfo = await _deviceInfoLoader();
      return _sanitizeDeviceInfo(_jsonSafeMap(deviceInfo.data));
    } catch (error) {
      Log.w(
        'Bug report device diagnostics omitted after safe serialization '
        'failure error_type=${_safeErrorType(error)}',
        category: LogCategory.app,
        source: 'bug-report',
      );
      return const {
        'omitted':
            'Device diagnostics omitted because device metadata could not be serialized safely.',
      };
    }
  }

  Future<String?> _loadSafeLogs() async {
    try {
      final rawLogs = await _logLoader(maxFileBytes: maxBugReportLogBytes);
      final redactedLogs = _redactBugReportTextSafely(
        rawLogs,
        context: 'log_attachment',
      );
      return _emptyToNull(
        _limitTextBytes(redactedLogs, maxBugReportLogBytes),
      );
    } catch (error) {
      Log.w(
        'Bug report logs omitted after collection/redaction failure '
        'error_type=${_safeErrorType(error)}',
        category: LogCategory.app,
        source: 'bug-report',
      );
      return _omittedUnsafeAttachment;
    }
  }

  Future<BugReportSubmissionResult> submit(BugReportPayload payload) async {
    final body = jsonEncode(_redactPayload(payload.data));
    final payloadBytes = utf8.encode(body).length;

    http.Response response;
    try {
      Log.d(
        'Submitting bug report to ${_endpointLabel()} '
        'payload_bytes=$payloadBytes',
        category: LogCategory.app,
        source: 'bug-report',
      );
      response = await _httpClient
          .post(
            _endpoint,
            headers: const {
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Bug report upload timed out endpoint=${_endpointLabel()} '
            'payload_bytes=$payloadBytes',
        category: LogCategory.app,
        source: 'bug-report',
        flush: true,
      );
      throw const BugReportSubmissionException(
        'Bug report upload timed out. Check your connection and try again.',
      );
    } on http.ClientException catch (error, stackTrace) {
      final message = _redactBugReportTextSafely(
        error.message,
        context: 'upload_client_exception',
      );
      Log.onError(
        error,
        stackTrace,
        content: 'Bug report upload failed before server response '
            'endpoint=${_endpointLabel()} payload_bytes=$payloadBytes '
            'error=$message',
        category: LogCategory.app,
        source: 'bug-report',
        flush: true,
      );
      throw BugReportSubmissionException(
        'Bug report upload failed before reaching the server: $message',
      );
    } catch (error, stackTrace) {
      final message = _redactBugReportTextSafely(
        _safeObjectDescription(error),
        context: 'upload_exception',
      );
      Log.onError(
        error,
        stackTrace,
        content: 'Bug report upload failed before server response '
            'endpoint=${_endpointLabel()} payload_bytes=$payloadBytes '
            'error=$message',
        category: LogCategory.app,
        source: 'bug-report',
        flush: true,
      );
      throw BugReportSubmissionException(
        'Bug report upload failed before receiving a server response: $message',
      );
    }

    final rawResponseBody = response.body;
    final responseBody = _redactBugReportTextSafely(
      rawResponseBody,
      redactEmails: true,
      context: 'upload_response',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseSummary = _serverResponseSummary(rawResponseBody);
      Log.w(
        'Bug report upload rejected endpoint=${_endpointLabel()} '
        'status=${response.statusCode} payload_bytes=$payloadBytes '
        'response_bytes=${utf8.encode(responseBody).length}'
        '${responseSummary == null ? '' : ' response_message=$responseSummary'}',
        category: LogCategory.app,
        source: 'bug-report',
      );
      throw BugReportSubmissionException(
        _serverErrorMessage(response.statusCode, rawResponseBody),
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    }

    if (responseBody.trim().isEmpty) {
      return const BugReportSubmissionResult(message: 'Bug report sent.');
    }

    final decoded = _decodeMap(responseBody);
    final reportId =
        _stringField(decoded, const ['id', 'report_id', 'reportId']);
    final emailStatus = _stringField(decoded, const ['emailStatus']);
    final message = _stringField(decoded, const ['message']) ??
        (emailStatus == 'failed'
            ? 'Bug report stored. Support email delivery failed.'
            : 'Bug report sent.');

    return BugReportSubmissionResult(
      reportId: reportId,
      message: message,
      responseBody: decoded,
    );
  }

  static Map<String, Object?> _payloadData({
    required BugReportInput input,
    required String? reportNotice,
    required Map<String, Object?> additionalMetadata,
    required DateTime timestamp,
    required String reportHash,
    required Map<String, Object?> deviceData,
    required String? logs,
    required Map<String, Object?>? diagnostics,
    required List<BugReportAttachmentSummary> additionalAttachments,
    required Map<String, Object?>? attachmentTransportFallback,
  }) {
    final title = _redactUserText(input.title);
    final severity = input.severity.wireValue;
    final templateTag = input.template.tag;
    final templateLabel = input.template.label;
    final reproductionSteps = _redactUserText(input.reproductionSteps);
    final expectedBehavior = _redactUserText(input.expectedBehavior);
    final actualBehavior = _redactUserText(input.actualBehavior);
    final description = _supportDescription(
      reproductionSteps: reproductionSteps,
      expectedBehavior: expectedBehavior,
      actualBehavior: actualBehavior,
    );
    final attachments = _attachmentsFor(
      logs,
      diagnostics,
      additionalAttachments,
    );

    return {
      'schema_version': 1,
      'source': 'intergalactic_app',
      'template_tag': templateTag,
      'templateTag': templateTag,
      'template_label': templateLabel,
      'title': title,
      'summary': title,
      'severity': severity,
      'description': description,
      'message': description,
      'reproduction_steps': reproductionSteps,
      'reproductionSteps': reproductionSteps,
      if (expectedBehavior.isNotEmpty) 'expected_behavior': expectedBehavior,
      if (expectedBehavior.isNotEmpty) 'expectedBehavior': expectedBehavior,
      if (actualBehavior.isNotEmpty) 'actual_behavior': actualBehavior,
      if (actualBehavior.isNotEmpty) 'actualBehavior': actualBehavior,
      'app_version': BuildConfig.VERSION_TAG,
      'appVersion': BuildConfig.VERSION_TAG,
      'platform': BuildConfig.platformDisplay,
      'timestamp': timestamp.toIso8601String(),
      'report_hash': reportHash,
      'reportHash': reportHash,
      'app': {
        'name': BuildConfig.app,
        'version': BuildConfig.VERSION_TAG,
        'git_hash': BuildConfig.GIT_HASH,
        'build_detail': BuildConfig.BUILD_DETAIL,
        'build_display': BuildConfig.buildDetailDisplay,
        'build_fingerprint': BuildConfig.buildFingerprintDisplay,
      },
      'environment': {
        'platform': BuildConfig.platformDisplay,
        'configured_platform': BuildConfig.PLATFORM,
        'target_platform': defaultTargetPlatform.name,
        'is_web': kIsWeb,
        'device_summary': _deviceSummary(deviceData),
      },
      'report': {
        'template_tag': templateTag,
        'templateTag': templateTag,
        'template_label': templateLabel,
        'title': title,
        'severity': severity,
        'reproduction_steps': reproductionSteps,
        'expected_behavior': expectedBehavior,
        'actual_behavior': actualBehavior,
        'report_hash': reportHash,
        'reportHash': reportHash,
      },
      'included': {
        'logs': logs != null,
        'diagnostics': diagnostics != null,
        'additional_attachments': additionalAttachments.isNotEmpty,
      },
      if (reportNotice != null) 'report_notice': reportNotice,
      if (additionalMetadata.isNotEmpty)
        'additional_metadata': additionalMetadata,
      if (attachmentTransportFallback != null)
        'attachment_transport_fallback': attachmentTransportFallback,
      if (logs != null)
        'log_attachment': {
          'name': 'diagnostic-logs.txt',
          'mimeType': 'text/plain',
          'sizeBytes': utf8.encode(logs).length,
        },
      if (logs != null)
        'log_preview': _limitTextBytes(logs, maxBugReportLogPreviewBytes),
      'attachments':
          attachments.map((attachment) => attachment.toJson()).toList(),
      if (diagnostics != null) 'diagnostics': diagnostics,
    };
  }

  static List<BugReportAttachmentSummary> _attachmentsFor(
    String? logs,
    Map<String, Object?>? diagnostics,
    List<BugReportAttachmentSummary> additionalAttachments,
  ) {
    return [
      if (logs != null)
        BugReportAttachmentSummary(
          field: 'logs',
          name: 'diagnostic-logs.txt',
          contentType: 'text/plain',
          sizeBytes: utf8.encode(logs).length,
          contentBase64: base64Encode(utf8.encode(logs)),
        ),
      if (diagnostics != null)
        BugReportAttachmentSummary(
          field: 'diagnostics',
          name: 'diagnostics.json',
          contentType: 'application/json',
          sizeBytes: utf8.encode(jsonEncode(diagnostics)).length,
          contentBase64: base64Encode(utf8.encode(jsonEncode(diagnostics))),
        ),
      ...additionalAttachments,
    ];
  }

  static Map<String, Object?> _attachmentTransportFallback(
    List<BugReportAttachmentSummary> attachments,
  ) {
    final listed = attachments.take(_maxFallbackAttachmentDetails).toList();
    return {
      'omitted': true,
      'reason':
          'Additional attachments exceeded the bug report upload limit after logs and diagnostics were bounded.',
      'attachment_count': attachments.length,
      'total_bytes':
          attachments.fold<int>(0, (total, item) => total + item.sizeBytes),
      'attachments': [
        for (final attachment in listed)
          {
            'name': _fallbackString(attachment.name),
            'mimeType': _fallbackString(attachment.contentType),
            'sizeBytes': attachment.sizeBytes,
            'field': _fallbackString(attachment.field),
          },
      ],
      if (attachments.length > listed.length)
        'attachments_omitted_count': attachments.length - listed.length,
    };
  }

  static _AdditionalAttachmentFilter _filterUnsupportedAdditionalAttachments(
    List<BugReportAttachmentSummary> attachments,
  ) {
    final allowed = <BugReportAttachmentSummary>[];
    final omitted = <BugReportAttachmentSummary>[];
    for (final attachment in attachments) {
      if (_isAudioDiagnosticAttachment(attachment)) {
        omitted.add(attachment);
      } else {
        allowed.add(attachment);
      }
    }
    return _AdditionalAttachmentFilter(
      allowed: allowed,
      omitted: omitted,
    );
  }

  static bool _isAudioDiagnosticAttachment(
    BugReportAttachmentSummary attachment,
  ) {
    final mimeType = attachment.contentType.trim().toLowerCase();
    final name = attachment.name.trim().toLowerCase();
    return mimeType.startsWith('audio/') ||
        name.endsWith('.wav') ||
        name.endsWith('.wave');
  }

  static Map<String, Object?> _unsupportedAttachmentTransportFallback(
    List<BugReportAttachmentSummary> attachments,
  ) {
    final listed = attachments.take(_maxFallbackAttachmentDetails).toList();
    return {
      'unsupported_attachments_omitted': {
        'reason':
            'Audio diagnostic attachments are no longer supported by bug reports. Keep RNNoise WAV captures local.',
        'attachment_count': attachments.length,
        'attachments': [
          for (final attachment in listed)
            {
              'name': _fallbackString(attachment.name),
              'mimeType': _fallbackString(attachment.contentType),
              'sizeBytes': attachment.sizeBytes,
              'field': _fallbackString(attachment.field),
            },
        ],
        if (attachments.length > listed.length)
          'attachments_omitted_count': attachments.length - listed.length,
      },
    };
  }

  static _AdditionalMetadataFilter _filterUnsupportedAdditionalMetadata(
    Map<String, Object?> metadata,
  ) {
    final allowed = <String, Object?>{};
    final omittedKeys = <String>[];
    for (final entry in metadata.entries) {
      if (_isUnsupportedAdditionalMetadataKey(entry.key)) {
        omittedKeys.add(entry.key);
      } else {
        allowed[entry.key] = entry.value;
      }
    }
    return _AdditionalMetadataFilter(
      allowed: allowed,
      omittedKeys: omittedKeys,
    );
  }

  static bool _isUnsupportedAdditionalMetadataKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'rnnoisewavartifacts';
  }

  static Map<String, Object?> _unsupportedMetadataTransportFallback(
    List<String> omittedKeys,
  ) {
    return {
      'unsupported_metadata_omitted': {
        'reason':
            'RNNoise WAV report metadata is no longer supported by bug reports.',
        'fields': omittedKeys.take(_maxFallbackMetadataKeys).toList(),
        if (omittedKeys.length > _maxFallbackMetadataKeys)
          'fields_omitted_count': omittedKeys.length - _maxFallbackMetadataKeys,
      },
    };
  }

  static Map<String, Object?> _mergeAttachmentTransportFallback(
    Map<String, Object?>? current,
    Map<String, Object?> next,
  ) {
    return {
      if (current != null) ...current,
      ...next,
    };
  }

  static Map<String, Object?> _metadataTransportFallback({
    required Map<String, Object?> additionalMetadata,
    required bool omittedReportNotice,
  }) {
    final metadataKeys = additionalMetadata.keys.map(_safeKeyString).toList()
      ..sort();
    final listedMetadataKeys =
        metadataKeys.take(_maxFallbackMetadataKeys).map(_fallbackString);
    return {
      'metadata_omitted': {
        'reason':
            'Report notice and metadata exceeded the bug report upload limit after logs, diagnostics, and attachments were bounded.',
        'fields': [
          if (omittedReportNotice) 'report_notice',
          if (additionalMetadata.isNotEmpty) 'additional_metadata',
        ],
        if (metadataKeys.isNotEmpty)
          'additional_metadata_key_count': metadataKeys.length,
        if (metadataKeys.isNotEmpty)
          'additional_metadata_keys': listedMetadataKeys.toList(),
        if (metadataKeys.length > _maxFallbackMetadataKeys)
          'additional_metadata_keys_omitted_count':
              metadataKeys.length - _maxFallbackMetadataKeys,
      },
    };
  }

  static Map<String, Object?> _minimalAttachmentTransportFallback(
    Map<String, Object?> current,
  ) {
    final metadata = current['metadata_omitted'];
    final metadataSummary = metadata is Map
        ? <String, Object?>{
            'reason':
                'Report notice and metadata were omitted to keep the upload bounded.',
            if (metadata['fields'] case final List<Object?> fields)
              'fields': fields
                  .whereType<String>()
                  .take(_maxFallbackMetadataKeys)
                  .map(_fallbackString)
                  .toList(),
            if (metadata['additional_metadata_key_count'] is int)
              'additional_metadata_key_count':
                  metadata['additional_metadata_key_count'],
          }
        : null;
    return {
      'omitted': true,
      'reason':
          'Fallback details minimized because the bug report payload still exceeded the upload limit.',
      if (current['attachment_count'] is int)
        'attachment_count': current['attachment_count'],
      if (current['total_bytes'] is int) 'total_bytes': current['total_bytes'],
      if (current['attachments_omitted_count'] is int)
        'attachments_omitted_count': current['attachments_omitted_count'],
      if (metadataSummary != null) 'metadata_omitted': metadataSummary,
    };
  }

  static String _fallbackString(Object? value) {
    final text = _safeKeyString(value);
    final bytes = utf8.encode(text);
    if (bytes.length <= _maxFallbackStringBytes) {
      return text;
    }
    const marker = '...[truncated]';
    final markerBytes = utf8.encode(marker);
    final headBudget = (_maxFallbackStringBytes - markerBytes.length)
        .clamp(0, _maxFallbackStringBytes)
        .toInt();
    return utf8.decode(
          bytes.take(headBudget).toList(),
          allowMalformed: true,
        ) +
        marker;
  }

  static Map<String, Object?> _redactPayload(Map<String, Object?> payload) {
    return _redactPayloadValue(payload, const []) as Map<String, Object?>;
  }

  static Object? _redactPayloadValue(
    Object? value,
    List<String> path, {
    int depth = 0,
    Set<Object>? seen,
  }) {
    if (_shouldRedactPayloadField(path)) {
      return '[REDACTED]';
    }

    if (value is String && _isAttachmentContentBase64(path)) {
      return _redactAttachmentContentBase64(value);
    }

    if (value is String) {
      return _redactBugReportTextSafely(
        value,
        redactEmails: true,
        context: 'payload_string',
      );
    }

    if (depth > _maxJsonSafeDepth) {
      return _omittedNestedValue;
    }

    if (value is Map) {
      final activeSeen = seen ?? LinkedHashSet<Object>.identity();
      if (!activeSeen.add(value)) {
        return _omittedCircularValue;
      }
      try {
        final redacted = <String, Object?>{};
        value.forEach((key, child) {
          final keyString = _safeKeyString(key);
          redacted[keyString] = _redactPayloadValue(
            child,
            [...path, keyString],
            depth: depth + 1,
            seen: activeSeen,
          );
        });
        return redacted;
      } finally {
        activeSeen.remove(value);
      }
    }

    if (value is Iterable) {
      final activeSeen = seen ?? LinkedHashSet<Object>.identity();
      if (!activeSeen.add(value)) {
        return _omittedCircularValue;
      }
      try {
        return value
            .map<Object?>(
              (child) => _redactPayloadValue(
                child,
                path,
                depth: depth + 1,
                seen: activeSeen,
              ),
            )
            .toList();
      } finally {
        activeSeen.remove(value);
      }
    }

    if (value == null || value is num || value is bool) {
      return value;
    }

    return _redactBugReportTextSafely(
      _safeObjectDescription(value),
      context: 'payload_object',
    );
  }

  static bool _shouldRedactPayloadField(List<String> path) {
    if (path.isEmpty) {
      return false;
    }

    final normalized =
        path.last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return const {
          'authorization',
          'proxyauthorization',
          'accesstoken',
          'refreshtoken',
          'matrixaccesstoken',
          'openidtoken',
          'idtoken',
          'authtoken',
          'password',
          'passwd',
          'cookie',
          'sessionid',
          'sessionkey',
          'sessionkeys',
          'clientsecret',
          'apikey',
          'privatekey',
          'recoverykey',
          'backupkey',
          'contact',
          'contactinfo',
          'reportercontact',
        }.contains(normalized) ||
        normalized.endsWith('token') ||
        normalized.endsWith('secret');
  }

  static bool _isAttachmentContentBase64(List<String> path) {
    return path.length >= 2 &&
        path.last == 'contentBase64' &&
        path.contains('attachments');
  }

  static String _redactAttachmentContentBase64(String value) {
    try {
      final decoded = utf8.decode(base64Decode(value), allowMalformed: true);
      final redacted = _redactBugReportTextSafely(
        decoded,
        context: 'attachment_content',
      );
      return base64Encode(utf8.encode(redacted));
    } catch (error) {
      Log.w(
        'Bug report attachment content omitted after invalid base64 '
        'or decode failure error_type=${_safeErrorType(error)}',
        category: LogCategory.app,
        source: 'bug-report',
      );
      return base64Encode(utf8.encode(_omittedUnsafeAttachment));
    }
  }

  static String _redactBugReportTextSafely(
    String value, {
    bool redactEmails = true,
    required String context,
  }) {
    try {
      return LogRedactor.redactForBugReport(
        value,
        redactEmails: redactEmails,
      );
    } catch (error) {
      Log.w(
        'Bug report redaction omitted unsafe text context=$context '
        'error_type=${_safeErrorType(error)}',
        category: LogCategory.app,
        source: 'bug-report',
      );
      return _omittedUnsafeValue;
    }
  }

  static String _safeKeyString(Object? key) {
    if (key is String) {
      return key;
    }
    return _safeObjectDescription(key);
  }

  static String _safeObjectDescription(Object? value) {
    try {
      return value.toString();
    } catch (_) {
      return _omittedUnsafeValue;
    }
  }

  static String _safeErrorType(Object error) {
    try {
      return error.runtimeType.toString();
    } catch (_) {
      return 'unknown';
    }
  }

  static String _limitTextBytes(String value, int maxBytes) {
    if (maxBytes <= 0) {
      return '';
    }

    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) {
      return value;
    }

    const marker =
        '--- Earlier log output omitted to keep bug report upload bounded ---\n';
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

  static String? _emptyToNull(String value) {
    return value.trim().isEmpty ? null : value;
  }

  static int _encodedSize(Map<String, Object?> value) {
    return utf8.encode(jsonEncode(value)).length;
  }

  static String _supportDescription({
    required String reproductionSteps,
    required String expectedBehavior,
    required String actualBehavior,
  }) {
    final sections = <String>[
      'Reproduction steps:\n$reproductionSteps',
      if (expectedBehavior.isNotEmpty) 'Expected behavior:\n$expectedBehavior',
      if (actualBehavior.isNotEmpty) 'Actual behavior:\n$actualBehavior',
    ];
    return sections.join('\n\n').trim();
  }

  static Map<String, Object?> _jsonSafeMap(Map<String, dynamic> input) {
    final seen = LinkedHashSet<Object>.identity();
    final output = <String, Object?>{};
    seen.add(input);
    try {
      input.forEach((key, value) {
        output[_safeKeyString(key)] = _jsonSafeValue(
          value,
          depth: 1,
          seen: seen,
        );
      });
    } finally {
      seen.remove(input);
    }
    return output;
  }

  static Map<String, Object?> _sanitizeDeviceInfo(
    Map<String, Object?> input,
  ) {
    return _sanitizeDeviceInfoMap(
      input,
      depth: 0,
      seen: LinkedHashSet<Object>.identity(),
    );
  }

  static Map<String, Object?> _sanitizeDeviceInfoMap(
    Map<String, Object?> input, {
    required int depth,
    required Set<Object> seen,
  }) {
    if (depth > _maxJsonSafeDepth) {
      return const {'omitted': _omittedNestedValue};
    }

    if (!seen.add(input)) {
      return const {'omitted': _omittedCircularValue};
    }

    final sanitized = <String, Object?>{};
    try {
      for (final entry in input.entries) {
        if (_shouldOmitDeviceInfoField(entry.key)) {
          continue;
        }
        sanitized[entry.key] = _sanitizeDeviceInfoValue(
          entry.value,
          depth: depth + 1,
          seen: seen,
        );
      }
    } finally {
      seen.remove(input);
    }
    return sanitized;
  }

  static Object? _sanitizeDeviceInfoValue(
    Object? value, {
    required int depth,
    required Set<Object> seen,
  }) {
    if (depth > _maxJsonSafeDepth) {
      return _omittedNestedValue;
    }

    if (value is Map) {
      if (!seen.add(value)) {
        return _omittedCircularValue;
      }
      final normalized = <String, Object?>{};
      try {
        value.forEach((key, child) {
          normalized[_safeKeyString(key)] = child;
        });
        return _sanitizeDeviceInfoMap(
          normalized,
          depth: depth,
          seen: seen,
        );
      } finally {
        seen.remove(value);
      }
    }

    if (value is List) {
      if (!seen.add(value)) {
        return _omittedCircularValue;
      }
      if (_isLargeNumericList(value)) {
        seen.remove(value);
        return '[omitted numeric array, length=${value.length}]';
      }
      try {
        return value
            .map(
              (child) => _sanitizeDeviceInfoValue(
                child,
                depth: depth + 1,
                seen: seen,
              ),
            )
            .toList();
      } finally {
        seen.remove(value);
      }
    }

    return value;
  }

  static bool _shouldOmitDeviceInfoField(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return const {
      'digitalproductid',
      'digitalproductid4',
      'productid',
      'computername',
      'deviceid',
      'hardwareid',
      'machineguid',
      'serialnumber',
      'systemserialnumber',
      'identifierforvendor',
      'androidid',
      'usersid',
      'username',
    }.contains(normalized);
  }

  static bool _isLargeNumericList(List<Object?> value) {
    const maxInlineNumericValues = 16;
    return value.length > maxInlineNumericValues &&
        value.every((item) => item is num || item == null);
  }

  static Object? _jsonSafeValue(
    Object? value, {
    int depth = 0,
    Set<Object>? seen,
  }) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (depth > _maxJsonSafeDepth) {
      return _omittedNestedValue;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Map) {
      final activeSeen = seen ?? LinkedHashSet<Object>.identity();
      if (!activeSeen.add(value)) {
        return _omittedCircularValue;
      }
      try {
        final safe = <String, Object?>{};
        value.forEach((key, child) {
          safe[_safeKeyString(key)] = _jsonSafeValue(
            child,
            depth: depth + 1,
            seen: activeSeen,
          );
        });
        return safe;
      } finally {
        activeSeen.remove(value);
      }
    }
    if (value is Iterable) {
      final activeSeen = seen ?? LinkedHashSet<Object>.identity();
      if (!activeSeen.add(value)) {
        return _omittedCircularValue;
      }
      try {
        return value
            .map(
              (child) => _jsonSafeValue(
                child,
                depth: depth + 1,
                seen: activeSeen,
              ),
            )
            .toList();
      } finally {
        activeSeen.remove(value);
      }
    }
    return _safeObjectDescription(value);
  }

  static Map<String, Object?> _deviceSummary(Map<String, Object?> deviceData) {
    const summaryKeys = [
      'name',
      'model',
      'product',
      'prettyName',
      'version',
      'systemName',
      'systemVersion',
      'operatingSystem',
      'machine',
      'browserName',
      'appVersion',
    ];

    final summary = <String, Object?>{};
    for (final key in summaryKeys) {
      final value = deviceData[key];
      if (value != null) {
        summary[key] = value;
      }
    }
    return _redactPayloadValue(summary, const [
      'environment',
      'device_summary',
    ]) as Map<String, Object?>;
  }

  static String _redactUserText(String value) {
    return _redactBugReportTextSafely(
      value.trim(),
      context: 'user_text',
    );
  }

  static Map<String, Object?>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map<String, Object?>(
          (key, value) => MapEntry(_safeKeyString(key), _jsonSafeValue(value)),
        );
      }
    } catch (_) {}
    return null;
  }

  static String? _stringField(
    Map<String, Object?>? map,
    List<String> keys,
  ) {
    if (map == null) {
      return null;
    }
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String _serverErrorMessage(int statusCode, String responseBody) {
    final decoded = _decodeMap(responseBody);
    final message =
        _stringField(decoded, const ['error', 'message', 'detail']) ??
            _serverResponseSummary(responseBody);
    if (message != null) {
      return 'Bug report upload failed ($statusCode): '
          '${_redactBugReportTextSafely(
        message,
        context: 'server_error_message',
      )}';
    }
    return 'Bug report upload failed with server status $statusCode.';
  }

  static String? _serverResponseSummary(String responseBody) {
    final decoded = _decodeMap(responseBody);
    final decodedMessage =
        _stringField(decoded, const ['error', 'message', 'detail']);
    final raw = (decodedMessage ?? responseBody).trim();
    if (raw.isEmpty) {
      return null;
    }

    final singleLine = _redactBugReportTextSafely(
      raw,
      context: 'server_response_summary',
    ).replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= 180) {
      return singleLine;
    }
    return '${singleLine.substring(0, 177)}...';
  }

  String _endpointLabel() {
    final port = _endpoint.hasPort ? ':${_endpoint.port}' : '';
    return '${_endpoint.scheme}://${_endpoint.host}$port${_endpoint.path}';
  }
}

class _AdditionalAttachmentFilter {
  const _AdditionalAttachmentFilter({
    required this.allowed,
    required this.omitted,
  });

  final List<BugReportAttachmentSummary> allowed;
  final List<BugReportAttachmentSummary> omitted;
}

class _AdditionalMetadataFilter {
  const _AdditionalMetadataFilter({
    required this.allowed,
    required this.omittedKeys,
  });

  final Map<String, Object?> allowed;
  final List<String> omittedKeys;
}
