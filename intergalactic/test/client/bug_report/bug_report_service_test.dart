import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/bug_report/bug_report_service.dart';

void main() {
  test('buildPayload redacts logs and report fields before preview', () async {
    final fixtureRoot = _windowsFixtureRoot;
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({
        'productName': 'Windows host',
        'version': '10.0',
        'localPath':
            '$fixtureRoot'
            r'\AppData\Local\InterGalactic',
        'owner': 'owner@example.com',
      }),
      logLoader: ({int maxFileBytes = 200 * 1024}) async {
        return 'Authorization: Bearer live-token\n'
            '$fixtureRoot'
            r'\AppData\Local\secret.txt'
            '\n'
            'session_key=megolm-secret\n'
            'reporter@example.com';
      },
      reportHashGenerator: (_) => 'ig-test-hash',
      clock: () => DateTime.utc(2026, 5, 14, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Crash on send from user@example.com',
        reproductionSteps: 'Type password=hunter2 and send.',
        severity: BugReportSeverity.high,
        expectedBehavior: 'Message sends.',
        actualBehavior: 'It crashes with access_token=secret.',
      ),
    );

    final preview = payload.toPrettyJson();
    expect(preview, isNot(contains('live-token')));
    expect(preview, isNot(contains('hunter2')));
    expect(preview, isNot(contains('megolm-secret')));
    expect(preview, isNot(contains('owner@example.com')));
    expect(preview, isNot(contains('reporter@example.com')));
    expect(preview, isNot(contains('user@example.com')));
    expect(preview, isNot(contains(fixtureRoot)));
    expect(preview, contains('[LOCAL_PATH]/secret.txt'));
    expect(payload.data['title'], 'Crash on send from [REDACTED]');
    expect(payload.data['summary'], payload.data['title']);
    expect(payload.data['severity'], 'high');
    expect(payload.data['description'], contains('Reproduction steps:'));
    expect(payload.data['message'], payload.data['description']);
    expect(payload.data, isNot(contains('contact')));
    expect(payload.data, isNot(contains('contact_info')));
    expect(payload.data, isNot(contains('reporterContact')));
    expect(payload.data['report_hash'], 'ig-test-hash');
    expect(payload.data['reportHash'], 'ig-test-hash');
    expect(payload.data['app_version'], isA<String>());
    expect(payload.data['appVersion'], isA<String>());
    expect(payload.data['platform'], isA<String>());
    expect(
      payload.data['report'],
      allOf(
        containsPair('severity', 'high'),
        containsPair('report_hash', 'ig-test-hash'),
        containsPair('reportHash', 'ig-test-hash'),
      ),
    );
    expect(payload.data['logs'], isNull);
    expect(payload.data['log_preview'], isA<String>());
    expect(payload.attachments, hasLength(2));

    final attachments = payload.data['attachments']! as List<Object?>;
    final logAttachment = attachments.first! as Map<String, Object?>;
    expect(logAttachment['name'], 'diagnostic-logs.txt');
    expect(logAttachment['mimeType'], 'text/plain');
    expect(logAttachment, isNot(containsPair('content_type', anything)));
    expect(logAttachment['contentBase64'], isA<String>());
    final decodedLogAttachment = utf8.decode(
      base64Decode(logAttachment['contentBase64']! as String),
    );
    expect(decodedLogAttachment, contains('[REDACTED]'));
    expect(decodedLogAttachment, isNot(contains('live-token')));
  });

  test('buildPayload defaults bug report severity to medium', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 5, 20, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Default severity',
        reproductionSteps:
            'Open the reporter and preview without changing severity.',
      ),
    );

    expect(payload.data['severity'], 'medium');
    expect(payload.data['report'], containsPair('severity', 'medium'));
    expect(payload.data['template_tag'], 'generic_app_bug');
    expect(payload.data['templateTag'], 'generic_app_bug');
    expect(payload.data['template_label'], 'Generic app bug');
  });

  test('buildPayload carries call stream template tag', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async =>
          'call diagnostics report snapshot',
      featureDiagnosticsLoader: (input) async =>
          const BugReportFeatureDiagnostics(
            scope: 'call_stream',
            data: {'status': 'active_call'},
            logSummary: 'scope=call_stream active_sessions=1',
          ),
      clock: () => DateTime.utc(2026, 6, 11, 12),
    );

    final payload = await service.buildPayload(
      BugReportInput(
        title: BugReportTemplate.callStreamLogs.defaultTitle,
        reproductionSteps:
            BugReportTemplate.callStreamLogs.defaultReproductionSteps,
        template: BugReportTemplate.callStreamLogs,
        expectedBehavior:
            BugReportTemplate.callStreamLogs.defaultExpectedBehavior,
        actualBehavior: BugReportTemplate.callStreamLogs.defaultActualBehavior,
      ),
    );

    expect(payload.data['title'], 'Call/stream logs');
    expect(payload.data['template_tag'], 'call_stream_logs');
    expect(payload.data['templateTag'], 'call_stream_logs');
    expect(payload.data['template_label'], 'Call/stream logs');
    expect(payload.data['feature_diagnostics_scope'], 'call_stream');
    expect(
      payload.data['report'],
      allOf(
        containsPair('template_tag', 'call_stream_logs'),
        containsPair('templateTag', 'call_stream_logs'),
        containsPair('template_label', 'Call/stream logs'),
      ),
    );
    expect(
      payload.data['description'],
      contains('Recent redacted logs include the current call diagnostics'),
    );
    expect(payload.data['included'], containsPair('logs', true));
    expect(
      payload.attachments.map((attachment) => attachment.name),
      contains('diagnostic-logs.txt'),
    );
  });

  test(
    'buildPayload attaches redacted call diagnostics for guided call reports',
    () async {
      var loaderCalls = 0;
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        featureDiagnosticsLoader: (input) async {
          loaderCalls++;
          expect(input.category, BugReportCategory.callAudio);
          return const BugReportFeatureDiagnostics(
            scope: 'call_stream',
            data: {
              'status': 'active_call',
              'access_token': 'feature-secret',
              'room_id': '!private-room:example.test',
            },
            logSummary: 'scope=call_stream active_sessions=1',
          );
        },
        clock: () => DateTime.utc(2026, 7, 23, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Call audio stopped',
          reproductionSteps: 'Joined a room call.',
          category: BugReportCategory.callAudio,
          whatHappened: 'Remote audio stopped.',
          frequency: BugReportFrequency.sometimes,
          includeLogs: false,
        ),
      );

      expect(loaderCalls, 1);
      expect(payload.data['feature_diagnostics_scope'], 'call_stream');
      expect(
        payload.data['report'],
        containsPair('feature_diagnostics_scope', 'call_stream'),
      );
      final diagnostics = payload.data['diagnostics']! as Map<String, Object?>;
      final feature =
          diagnostics['feature_diagnostics']! as Map<String, Object?>;
      expect(feature['scope'], 'call_stream');
      expect(feature['data'], containsPair('status', 'active_call'));
      expect(payload.toPrettyJson(), isNot(contains('feature-secret')));
      expect(
        payload.toPrettyJson(),
        isNot(contains('!private-room:example.test')),
      );
      expect(
        payload.attachments.map((attachment) => attachment.name),
        contains('diagnostics.json'),
      );
    },
  );

  test(
    'buildPayload skips call diagnostics for unrelated or disabled reports',
    () async {
      var loaderCalls = 0;
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        featureDiagnosticsLoader: (input) async {
          loaderCalls++;
          return const BugReportFeatureDiagnostics(
            scope: 'call_stream',
            data: {'status': 'active_call'},
            logSummary: 'scope=call_stream active_sessions=1',
          );
        },
      );

      final messagesPayload = await service.buildPayload(
        const BugReportInput(
          title: 'Messages delayed',
          reproductionSteps: 'Opened a room.',
          category: BugReportCategory.messagesRooms,
          whatHappened: 'Messages appeared late.',
          frequency: BugReportFrequency.sometimes,
          includeLogs: false,
        ),
      );
      final disabledPayload = await service.buildPayload(
        const BugReportInput(
          title: 'Stream is black',
          reproductionSteps: 'Started sharing a window.',
          category: BugReportCategory.streaming,
          whatHappened: 'Viewers saw black.',
          frequency: BugReportFrequency.sometimes,
          includeLogs: false,
          includeDiagnostics: false,
        ),
      );

      expect(loaderCalls, 0);
      expect(
        messagesPayload.data,
        isNot(contains('feature_diagnostics_scope')),
      );
      expect(
        disabledPayload.data,
        isNot(contains('feature_diagnostics_scope')),
      );
      expect(
        disabledPayload.data['included'],
        containsPair('diagnostics', false),
      );
    },
  );

  test('buildPayload tolerates call diagnostics collection failure', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      featureDiagnosticsLoader: (input) {
        throw StateError('collector failed');
      },
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Camera stayed black',
        reproductionSteps: 'Joined a room call.',
        category: BugReportCategory.callVideo,
        whatHappened: 'Remote video stayed black.',
        frequency: BugReportFrequency.sometimes,
        includeLogs: false,
      ),
    );

    expect(payload.data, isNot(contains('feature_diagnostics_scope')));
    final diagnostics = payload.data['diagnostics'] as Map<String, Object?>;
    expect(diagnostics, isNot(contains('feature_diagnostics')));
  });

  test(
    'buildPayload omits RNNoise WAV metadata and audio attachments',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 6, 11, 13),
      );
      final wavBytes = <int>[0, 255, 1, 254, 2, 253];

      final payload = await service.buildPayload(
        BugReportInput(
          title: 'Audio diagnostic upload',
          reproductionSteps:
              'Try to attach local RNNoise WAV artifacts to a bug report.',
          reportNotice: 'RNNoise WAV capture is local-only.',
          additionalMetadata: const {
            'rnnoise_wav_artifacts': {
              'transport_status': 'local_only',
              'wav_count': 1,
            },
          },
          additionalAttachments: [
            BugReportAttachmentSummary(
              field: 'rnnoise_wav_artifacts',
              name: 'rnnoise-final_to_webrtc.wav',
              contentType: 'audio/wav',
              sizeBytes: wavBytes.length,
              contentBase64: base64Encode(wavBytes),
            ),
          ],
        ),
      );

      expect(
        payload.attachments.map((attachment) => attachment.name),
        isNot(contains('rnnoise-final_to_webrtc.wav')),
      );
      expect(payload.data.containsKey('additional_metadata'), isFalse);
      final fallback =
          payload.data['attachment_transport_fallback']!
              as Map<String, Object?>;
      expect(
        fallback,
        containsPair(
          'unsupported_attachments_omitted',
          containsPair('attachment_count', 1),
        ),
      );
      expect(
        fallback,
        containsPair(
          'unsupported_metadata_omitted',
          containsPair('fields', contains('rnnoise_wav_artifacts')),
        ),
      );
      expect(payload.toPrettyJson(), isNot(contains(base64Encode(wavBytes))));
    },
  );

  test(
    'buildPayload omits additional attachments that exceed upload limit',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 6, 11, 13),
      );
      final oversizedAudio = List<int>.filled(100 * 1024, 3);

      final payload = await service.buildPayload(
        BugReportInput(
          title: 'Large audio',
          reproductionSteps: 'Attach a large non-audio diagnostic artifact.',
          additionalAttachments: [
            BugReportAttachmentSummary(
              field: 'diagnostic_artifacts',
              name: 'diagnostic-bundle.zip',
              contentType: 'application/zip',
              sizeBytes: oversizedAudio.length,
              contentBase64: base64Encode(oversizedAudio),
            ),
          ],
        ),
      );

      expect(
        payload.attachments.map((attachment) => attachment.name),
        isNot(contains('diagnostic-bundle.zip')),
      );
      expect(payload.data['attachment_transport_fallback'], isA<Map>());
      expect(
        payload.sizeBytes,
        lessThanOrEqualTo(BugReportService.maxBugReportPayloadBytes),
      );
    },
  );

  test(
    'buildPayload omits oversized report metadata to stay under upload limit',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 6, 11, 13),
      );
      final oversizedText = 'metadata'.padRight(
        BugReportService.maxBugReportPayloadBytes + 4096,
        'x',
      );

      final payload = await service.buildPayload(
        BugReportInput(
          title: 'Large metadata',
          reproductionSteps: 'Attach large diagnostic metadata.',
          includeLogs: false,
          includeDiagnostics: false,
          reportNotice: oversizedText,
          additionalMetadata: {
            'large_diagnostic_artifacts': {
              'transport_status': 'metadata_only',
              'large_note': oversizedText,
            },
          },
        ),
      );

      expect(payload.data.containsKey('report_notice'), isFalse);
      expect(payload.data.containsKey('additional_metadata'), isFalse);
      expect(payload.data['attachment_transport_fallback'], isA<Map>());
      expect(
        payload.data['attachment_transport_fallback'],
        containsPair(
          'metadata_omitted',
          containsPair(
            'fields',
            containsAll(['report_notice', 'additional_metadata']),
          ),
        ),
      );
      expect(
        payload.sizeBytes,
        lessThanOrEqualTo(BugReportService.maxBugReportPayloadBytes),
      );
    },
  );

  test('buildPayload bounds fallback details after metadata omission', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 6, 12, 12),
    );
    final oversizedAttachment = List<int>.filled(4 * 1024, 7);

    final payload = await service.buildPayload(
      BugReportInput(
        title: 'Large fallback metadata',
        reproductionSteps:
            'Attach enough tiny diagnostic entries to stress fallback output.',
        includeLogs: false,
        includeDiagnostics: false,
        reportNotice: 'notice'.padRight(
          BugReportService.maxBugReportPayloadBytes,
          'n',
        ),
        additionalMetadata: {
          for (var index = 0; index < 96; index++)
            'very_long_metadata_key_${index}_${'k' * 512}':
                'metadata value $index',
        },
        additionalAttachments: [
          for (var index = 0; index < 64; index++)
            BugReportAttachmentSummary(
              field: 'diagnostic_text_artifacts_${'f' * 512}_$index',
              name: 'diagnostic-${'attachment-name' * 40}-$index.txt',
              contentType: 'text/plain',
              sizeBytes: oversizedAttachment.length,
              contentBase64: base64Encode(oversizedAttachment),
            ),
        ],
      ),
    );

    final fallback =
        payload.data['attachment_transport_fallback']! as Map<String, Object?>;
    final attachments = fallback['attachments'] as List<Object?>?;
    expect(attachments, hasLength(lessThanOrEqualTo(16)));
    expect(fallback['attachments_omitted_count'], greaterThan(0));
    final metadata = fallback['metadata_omitted']! as Map<String, Object?>;
    final metadataKeys = metadata['additional_metadata_keys'] as List<Object?>?;
    expect(metadataKeys, hasLength(lessThanOrEqualTo(32)));
    expect(metadata['additional_metadata_keys_omitted_count'], greaterThan(0));
    expect(
      payload.sizeBytes,
      lessThanOrEqualTo(BugReportService.maxBugReportPayloadBytes),
    );
  });

  test('submit posts redacted json and parses success response', () async {
    String? uploadedBody;
    final service = BugReportService(
      endpoint: Uri.parse('https://example.test/report'),
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/report');
        expect(request.headers['content-type'], 'application/json');
        uploadedBody = request.body;
        return http.Response(
          '{"reportId":"BR-123","emailStatus":"sent"}',
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
    );

    final result = await service.submit(
      const BugReportPayload(
        data: {
          'schema_version': 1,
          'report': {
            'title': 'Token leak',
            'contact_info': 'person@example.com',
          },
          'logs': 'Authorization: Bearer upload-secret',
        },
        attachments: [],
      ),
    );

    expect(result.reportId, 'BR-123');
    expect(result.message, 'Bug report sent.');
    expect(uploadedBody, isNotNull);
    expect(uploadedBody, isNot(contains('upload-secret')));
    expect(uploadedBody, isNot(contains('person@example.com')));
    expect(
      jsonDecode(uploadedBody!)['report'],
      containsPair('contact_info', '[REDACTED]'),
    );
    expect(jsonDecode(uploadedBody!)['logs'], contains('[REDACTED]'));
  });

  test('submit redacts decoded base64 attachment contents', () async {
    String? uploadedBody;
    final service = BugReportService(
      endpoint: Uri.parse('https://example.test/report'),
      httpClient: MockClient((request) async {
        uploadedBody = request.body;
        return http.Response('{}', 200);
      }),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
    );

    await service.submit(
      BugReportPayload(
        data: {
          'schema_version': 1,
          'attachments': [
            {
              'name': 'diagnostic-logs.txt',
              'mimeType': 'text/plain',
              'contentBase64': base64Encode(
                utf8.encode(
                  'Authorization: Bearer attachment-secret\n'
                  'session_key=attachment-session-secret',
                ),
              ),
            },
          ],
        },
        attachments: const [],
      ),
    );

    final uploaded = jsonDecode(uploadedBody!) as Map<String, Object?>;
    final attachments = uploaded['attachments']! as List<Object?>;
    final attachment = attachments.single! as Map<String, Object?>;
    final decodedAttachment = utf8.decode(
      base64Decode(attachment['contentBase64']! as String),
    );

    expect(decodedAttachment, contains('[REDACTED]'));
    expect(decodedAttachment, isNot(contains('attachment-secret')));
    expect(decodedAttachment, isNot(contains('attachment-session-secret')));
  });

  test('buildPayload caps included logs before upload', () async {
    final largeLog =
        'old line\n'
        '${List<String>.filled(140 * 1024, 'a').join()}'
        '\ntail line with accessToken=tail-secret';
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => largeLog,
      clock: () => DateTime.utc(2026, 5, 14, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Large logs',
        reproductionSteps: 'Preview with lots of logs.',
      ),
    );

    final logs = _decodedAttachment(payload, 'diagnostic-logs.txt');
    expect(
      utf8.encode(logs).length,
      lessThanOrEqualTo(BugReportService.maxBugReportLogBytes),
    );
    expect(
      payload.sizeBytes,
      lessThanOrEqualTo(BugReportService.maxBugReportPayloadBytes),
    );
    expect(payload.data['logs'], isNull);
    expect(payload.data['log_preview'], contains('Earlier log output omitted'));
    expect(logs, contains('Earlier log output omitted'));
    expect(logs, contains('tail line'));
    expect(logs, isNot(contains('tail-secret')));
  });

  test('buildPayload omits noisy Windows device identifiers', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({
        'productName': 'Windows host',
        'digitalProductID': List<int>.generate(20, (index) => index),
        'digitalProductId': List<int>.generate(20, (index) => index + 20),
        'productId': '00330-80000-00000-AA000',
        'computerName': 'Fixture-PC',
        'nested': {
          'deviceId': 'device-secret',
          'safeField': 'kept',
          'largeNumbers': List<int>.generate(18, (index) => index),
          'smallNumbers': [1, 2, 3],
        },
      }),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 5, 18, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Readable diagnostics',
        reproductionSteps: 'Preview Windows diagnostics.',
      ),
    );

    final preview = payload.toPrettyJson();
    final diagnosticsAttachment = _decodedAttachment(
      payload,
      'diagnostics.json',
    );
    for (final text in [preview, diagnosticsAttachment]) {
      expect(text, contains('Windows host'));
      expect(text, contains('safeField'));
      expect(text, contains('kept'));
      expect(text, contains('[omitted numeric array, length=18]'));
      expect(text, contains('smallNumbers'));
      expect(text, isNot(contains('digitalProductID')));
      expect(text, isNot(contains('digitalProductId')));
      expect(text, isNot(contains('productId')));
      expect(text, isNot(contains('00330-80000-00000-AA000')));
      expect(text, isNot(contains('computerName')));
      expect(text, isNot(contains('Fixture-PC')));
      expect(text, isNot(contains('deviceId')));
      expect(text, isNot(contains('device-secret')));
    }
  });

  test(
    'buildPayload sends a bounded device field for verbose Android metadata',
    () async {
      final longModel = 'Android model ${'x' * 300}';
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({
          'model': longModel,
          'product': 'test-product',
          'version': 'Android 15',
        }),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 4, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Android report submission',
          reproductionSteps: 'Submit a bug report from an Android device.',
        ),
      );

      final device = payload.data['device']! as String;
      final environment = payload.data['environment']! as Map<String, Object?>;
      final deviceSummary =
          environment['device_summary']! as Map<String, Object?>;

      expect(device.length, lessThanOrEqualTo(200));
      expect(device, startsWith('model: Android model '));
      // device_summary used to carry the whole 314-character value, which is
      // how the 200-character transport bound stayed an assumption rather than
      // something this layer enforced. It is now capped per value.
      final summarizedModel = deviceSummary['model']! as String;
      expect(summarizedModel.length, lessThanOrEqualTo(100));
      expect(summarizedModel, startsWith('Android model xxx'));
      expect(summarizedModel, endsWith('...'));
      expect(summarizedModel, isNot(longModel));
    },
  );

  test(
    'buildPayload avoids splitting a non-BMP device name at the server limit',
    () async {
      // Two fields, each inside the per-value cap, that together push the
      // joined device string one code unit past the server limit with a
      // surrogate pair straddling the cut. A single over-long field can no
      // longer reach this boundary, so the boundary is reached the way it now
      // actually occurs.
      // Two fields that both reach the legacy flat `device` string. `name` was
      // the second one until it was dropped as a user-assigned identifier, so
      // the pair is now model + productName. Sized so the join lands exactly
      // one code unit past the 200-character server limit, with the surrogate
      // pair straddling the cut.
      final model = 'x' * 86;
      final productName = '${'x' * 91}😀';
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async =>
            BaseDeviceInfo({'model': model, 'productName': productName}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 5, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Unicode device report',
          reproductionSteps:
              'Submit a report from a device with a Unicode name.',
        ),
      );

      final device = payload.data['device']! as String;
      final deviceSummary =
          (payload.data['environment']!
                  as Map<String, Object?>)['device_summary']
              as Map<String, Object?>;
      expect(device.length, 199);
      expect(device, endsWith('x'));
      expect(deviceSummary['model'], model);
      expect(deviceSummary['productName'], productName);
    },
  );

  test('the user-assigned device name never leaves the device', () async {
    // THREE exit paths, all of them open at once:
    //   1. `environment.device_summary` (its own key allowlist)
    //   2. the legacy flat `device` string (a second, separate key list)
    //   3. `diagnostics.device_info` and the base64 `diagnostics.json`
    //      attachment, which carry the raw device map and are attached by
    //      DEFAULT - `BugReportInput.includeDiagnostics` is `true`
    // Closing any one or two of them still sent the value. The whole-payload
    // assertion below is what catches that; the per-field ones would not.
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({
        'name': "Alice's iPhone",
        'model': 'iPhone15,2',
        'systemName': 'iOS',
      }),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 8, 9, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'iOS report',
        reproductionSteps: 'Submit a report from an iOS device.',
      ),
    );

    final device = payload.data['device']! as String;
    final deviceSummary =
        (payload.data['environment']!
                as Map<String, Object?>)['device_summary']!
            as Map<String, Object?>;

    expect(device, isNot(contains('Alice')));
    expect(deviceSummary.containsKey('name'), isFalse);
    expect(jsonEncode(payload.data), isNot(contains('Alice')));
    // The encoded payload above carries the attachment only as base64, so a
    // plaintext check cannot see inside it - it observes path 3 through the
    // plaintext `diagnostics` object alone. Decode the attachment and assert on
    // it directly, or the file that actually ships is unchecked.
    expect(
      _decodedAttachment(payload, 'diagnostics.json'),
      isNot(contains('Alice')),
    );
    // The hardware identification this block exists for is still there.
    expect(deviceSummary['model'], 'iPhone15,2');
    expect(device, contains('model: iPhone15,2'));
    expect(
      _decodedAttachment(payload, 'diagnostics.json'),
      contains('iPhone15,2'),
    );
  });

  test(
    'buildPayload avoids splitting a non-BMP value at the per-value cap',
    () async {
      // The same hazard one layer earlier: the per-value cut must not leave a
      // lone high surrogate behind either.
      final model = '${'x' * 96}😀${'y' * 50}';
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'model': model}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 5, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Unicode device report',
          reproductionSteps:
              'Submit a report from a device with a Unicode name.',
        ),
      );

      final deviceSummary =
          (payload.data['environment']!
                  as Map<String, Object?>)['device_summary']
              as Map<String, Object?>;
      // Cut back to before the emoji rather than through it.
      expect(deviceSummary['model'], '${'x' * 96}...');
    },
  );

  test(
    'buildPayload preserves browser and Windows product device metadata',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({
          'productName': 'Windows 11 Pro',
          'browserName': 123,
        }),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 5, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Platform metadata report',
          reproductionSteps: 'Submit a report from a browser or Windows host.',
        ),
      );

      final device = payload.data['device']! as String;
      expect(device, contains('productName: Windows 11 Pro'));
      expect(device, contains('browserName: 123'));
    },
  );

  group('environment.device_summary is never silently empty', () {
    Future<Map<String, Object?>> payloadFor(Map<String, dynamic> data) async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo(data),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 8, 12),
      );
      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Device summary report',
          reproductionSteps: 'Submit a report.',
        ),
      );
      return payload.data;
    }

    Map<String, Object?> deviceSummaryOf(Map<String, Object?> data) =>
        (data['environment']! as Map<String, Object?>)['device_summary']!
            as Map<String, Object?>;

    Future<Map<String, Object?>> summaryFor(Map<String, dynamic> data) async =>
        deviceSummaryOf(await payloadFor(data));

    // What _deviceSummary emits when a platform supplies none of the
    // recognised identity keys. Spelled out rather than imported so the test
    // fails if the wording silently changes on a field users read.
    const noIdentityReported =
        'No device identity fields were reported by this platform.';

    // Mirrors _maxDeviceSummaryValueCharacters and _maxServerDeviceCharacters.
    const maxValueCharacters = 100;
    const maxTransportCharacters = 200;

    // Real key shapes from device_info_plus 11.5.0, trimmed to the identity
    // fields. Every platform must yield something: an empty summary here is
    // the exact symptom that made submitted reports carry no device identity.
    final platformFixtures = <String, Map<String, dynamic>>{
      'android': {
        'name': 'Buffalo_Boost',
        'model': 'T767W',
        'product': 'Buffalo_Boost',
        'version': {'release': '12', 'sdkInt': 31},
      },
      'ios': {
        'name': 'iPhone',
        'model': 'iPhone',
        'systemName': 'iOS',
        'systemVersion': '18.2',
        'machine': 'iPhone15,2',
      },
      'windows': {'productName': 'Windows 11 Pro'},
      'linux': {'name': 'ubuntu', 'prettyName': 'Ubuntu 24.04 LTS'},
      'macos': {'model': 'MacBookPro18,3'},
      'web': {'browserName': 'chrome', 'appVersion': '150.0'},
    };

    for (final entry in platformFixtures.entries) {
      test('${entry.key} reports device identity', () async {
        final summary = await summaryFor(entry.value);
        expect(summary, isNotEmpty);
        expect(
          summary.containsKey('omitted'),
          isFalse,
          reason: '${entry.key} supplies identity keys, so nothing was omitted',
        );
      });
    }

    test('a failed device-info load says so instead of sending {}', () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => throw StateError('device info exploded'),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 8, 8, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Failed device info report',
          reproductionSteps: 'Submit a report when device info is unavailable.',
        ),
      );
      final summary =
          (payload.data['environment']!
                  as Map<String, Object?>)['device_summary']!
              as Map<String, Object?>;

      // The whole point: a collection failure must not look identical to a
      // device that simply has no identity fields.
      expect(summary, isNotEmpty);
      expect(summary['omitted'], isNotNull);
      // `isNotNull` alone does not state that. The unrecognised-platform test
      // below asserts `noIdentityReported` under the same key, so an
      // implementation that returned it here too would satisfy both tests and
      // leave the distinction this test exists for entirely unverified.
      expect(
        summary['omitted'],
        isNot(noIdentityReported),
        reason:
            'a loader failure must be distinguishable from a platform that '
            'reported no identity fields',
      );
      expect(payload.data['device'], 'Unknown device');
    });

    test('an unrecognised platform names the gap', () async {
      final payloadData = await payloadFor({
        'boardName': 'futurephone',
        'osFlavour': 'FutureOS 1.0',
        'kernel': '9.9.9',
        'uptimeSeconds': 42,
      });

      // Not empty (the original defect) and not a guess at which unrecognised
      // fields are safe to send. Map equality, so this also pins that nothing
      // else came along for the ride.
      expect(deviceSummaryOf(payloadData), {'omitted': noIdentityReported});
      expect(payloadData['device'], 'Unknown device');
    });

    test('unlisted fields are excluded when no key matches', () async {
      // The shape that used to leak: an Android-flavoured map with none of the
      // recognised identity keys, so membership fell through to "any scalar
      // not on the denylist". None of these belong in a field sent on every
      // report, and none of them are on that denylist.
      final summary = await summaryFor({
        'fingerprint':
            'google/sunfish/sunfish:12/SP2A.220505.008/8782922:user/release-keys',
        'host': 'abfarm-release-2004-0913',
        'id': 'SP2A.220505.008',
        'bootloader': 'unknown',
        'board': 'sunfish',
        'hardware': 'sunfish',
        'display': 'SP2A.220505.008',
      });

      expect(summary, {'omitted': noIdentityReported});
    });

    test('unlisted fields are excluded beside recognised ones', () async {
      final summary = await summaryFor({
        'name': 'Buffalo_Boost',
        'model': 'T767W',
        'fingerprint':
            'google/sunfish/sunfish:12/SP2A.220505.008/8782922:user/release-keys',
        'host': 'abfarm-release-2004-0913',
        'id': 'SP2A.220505.008',
        'bootloader': 'unknown',
        'board': 'sunfish',
        'hardware': 'sunfish',
        'display': 'SP2A.220505.008',
      });

      expect(summary['model'], 'T767W');
      // `name` is NOT reported. On iOS it is the user-assigned device name
      // ("Alice's iPhone"), and this summary rides on every bug report, so it
      // is excluded alongside the unrecognised fields below rather than
      // collected. `model` still identifies the hardware.
      expect(summary.containsKey('name'), isFalse);
      for (final key in const [
        'fingerprint',
        'host',
        'id',
        'bootloader',
        'board',
        'hardware',
        'display',
      ]) {
        expect(summary.containsKey(key), isFalse, reason: key);
      }
    });

    test('an over-long value is truncated to the per-value cap', () async {
      final longModel = List.filled(20, 'Pixel 9 Pro Fold').join(' ');
      expect(longModel.length, greaterThan(maxValueCharacters));

      final payloadData = await payloadFor({'model': longModel});
      final model = deviceSummaryOf(payloadData)['model']! as String;

      expect(model.length, lessThanOrEqualTo(maxValueCharacters));
      expect(model, startsWith('Pixel 9 Pro Fold'));
      expect(model, endsWith('...'));
      expect(model, isNot(longModel));
      // The cap is applied here, not by the transport serializer downstream:
      // the device field is well inside its own bound and still carries the
      // already-shortened value.
      expect(payloadData['device'], 'model: $model');
    });

    test('the device field stays bounded when values are over-long', () async {
      final overLong = List.filled(40, 'Verbose Device Name').join(' ');
      final fields = <String, dynamic>{
        for (final key in const [
          'name',
          'model',
          'product',
          'productName',
          'prettyName',
          'systemName',
          'operatingSystem',
          'browserName',
        ])
          key: overLong,
      };

      final payloadData = await payloadFor(fields);
      final summary = deviceSummaryOf(payloadData);

      expect(summary, isNotEmpty);
      for (final entry in summary.entries) {
        expect(
          (entry.value! as String).length,
          lessThanOrEqualTo(maxValueCharacters),
          reason: entry.key,
        );
      }
      expect(
        (payloadData['device']! as String).length,
        lessThanOrEqualTo(maxTransportCharacters),
      );
    });

    test('the server device field stays bounded for every fixture', () async {
      for (final entry in platformFixtures.entries) {
        final service = BugReportService(
          httpClient: MockClient((request) async => http.Response('{}', 200)),
          deviceInfoLoader: () async => BaseDeviceInfo(entry.value),
          logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
          clock: () => DateTime.utc(2026, 8, 8, 12),
        );
        final payload = await service.buildPayload(
          const BugReportInput(
            title: 'Bounded device report',
            reproductionSteps: 'Submit a report.',
          ),
        );
        final device = payload.data['device']! as String;
        expect(device.length, lessThanOrEqualTo(200), reason: entry.key);
        expect(device, isNotEmpty, reason: entry.key);
      }
    });
  });

  test('buildPayload tolerates recursive device info before preview', () async {
    final recursiveDeviceInfo = <String, dynamic>{
      'productName': 'Recursive test device',
      'authorization': 'Bearer recursive-secret',
    };
    final recursiveList = <Object?>['visible'];
    recursiveDeviceInfo['self'] = recursiveDeviceInfo;
    recursiveDeviceInfo['list'] = recursiveList;
    recursiveList.add(recursiveList);

    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo(recursiveDeviceInfo),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 5, 27, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Recursive preview',
        reproductionSteps: 'Open bug report preview with recursive metadata.',
      ),
    );

    final preview = payload.toPrettyJson();
    final diagnosticsAttachment = _decodedAttachment(
      payload,
      'diagnostics.json',
    );

    for (final text in [preview, diagnosticsAttachment]) {
      expect(text, contains('Recursive test device'));
      expect(text, contains('[omitted circular value]'));
      expect(text, isNot(contains('recursive-secret')));
    }
  });

  test('buildPayload omits unsafe device values before preview', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({
        'productName': 'Unsafe test device',
        'bad_value': _RecursiveToString(),
      }),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 5, 31, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Unsafe device info',
        reproductionSteps: 'Open bug report preview on mobile.',
      ),
    );

    final preview = payload.toPrettyJson();
    final diagnosticsAttachment = _decodedAttachment(
      payload,
      'diagnostics.json',
    );

    for (final text in [preview, diagnosticsAttachment]) {
      expect(text, contains('Unsafe test device'));
      expect(text, contains('[omitted unsafe value]'));
    }
  });

  test('buildPayload omits empty log attachments', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      clock: () => DateTime.utc(2026, 5, 15, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'No logs',
        reproductionSteps: 'Build a report with no available logs.',
        includeDiagnostics: false,
      ),
    );

    expect(payload.data['logs'], isNull);
    expect(payload.data['included'], containsPair('logs', false));
    expect(payload.data['log_preview'], isNull);
    expect(payload.data['log_attachment'], isNull);
    expect(payload.data['attachments'], isEmpty);
    expect(payload.attachments, isEmpty);
  });

  test(
    'buildPayload shrinks logs again when total payload would exceed limit',
    () async {
      final largeLog = List<String>.filled(140 * 1024, 'b').join();
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({
          'name': 'test',
          'extra': List<String>.filled(20 * 1024, 'd').join(),
        }),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => largeLog,
        clock: () => DateTime.utc(2026, 5, 15, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Payload cap',
          reproductionSteps: 'Include logs and diagnostics.',
        ),
      );

      expect(
        payload.sizeBytes,
        lessThanOrEqualTo(BugReportService.maxBugReportPayloadBytes),
      );
      expect(payload.data['logs'], isNull);
      expect(
        payload.data['log_preview'],
        contains('Earlier log output omitted'),
      );
      expect(
        _decodedAttachment(payload, 'diagnostic-logs.txt'),
        contains('Earlier log output omitted'),
      );
    },
  );

  test(
    'submit surfaces server failures without leaking response secrets',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error":"bad token access_token=server-secret"}',
            500,
          );
        }),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      );

      await expectLater(
        service.submit(
          const BugReportPayload(
            data: {
              'report': {'title': 'Failure'},
            },
            attachments: [],
          ),
        ),
        throwsA(
          isA<BugReportSubmissionException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('500'), isNot(contains('server-secret'))),
          ),
        ),
      );
    },
  );

  test(
    'submit surfaces redacted server failure details from short responses',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error":"Payload too large access_token=server-secret"}',
            400,
          );
        }),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      );

      await expectLater(
        service.submit(
          const BugReportPayload(
            data: {
              'report': {'title': 'Failure'},
            },
            attachments: [],
          ),
        ),
        throwsA(
          isA<BugReportSubmissionException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having(
                (error) => error.toString(),
                'message',
                allOf(
                  contains('Payload too large'),
                  isNot(contains('server-secret')),
                ),
              )
              .having(
                (error) => error.responseBody,
                'responseBody',
                isNot(contains('server-secret')),
              ),
        ),
      );
    },
  );

  test(
    'submit wraps unexpected network failures without leaking secrets',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async {
          throw Exception('Authorization: Bearer transport-secret');
        }),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      );

      await expectLater(
        service.submit(
          const BugReportPayload(
            data: {
              'report': {'title': 'Transport failure'},
            },
            attachments: [],
          ),
        ),
        throwsA(
          isA<BugReportSubmissionException>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('before receiving a server response'),
              isNot(contains('transport-secret')),
            ),
          ),
        ),
      );
    },
  );

  test('buildPayload includes structured guided interview fields', () async {
    final service = BugReportService(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
      logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
      reportHashGenerator: (_) => 'ig-test-hash',
      clock: () => DateTime.utc(2026, 7, 23, 12),
    );

    final payload = await service.buildPayload(
      const BugReportInput(
        title: 'Cannot hear one participant',
        reproductionSteps: 'I joined the call and changed their volume.',
        category: BugReportCategory.callAudio,
        whatHappened: 'I could see everyone but could not hear one person.',
        frequency: BugReportFrequency.sometimes,
        expectedBehavior: 'I expected to keep hearing everyone.',
        troubleshootingTried: ['call_left_rejoined', 'changed_setting'],
        troubleshootingNote: 'Also swapped my headphones.',
        categoryAnswers: {
          'could_hear_others': 'No',
          'audio_output': 'Headphones',
        },
        additionalDetails: 'Started after the latest update.',
        includeLogs: false,
        includeDiagnostics: false,
      ),
    );

    expect(payload.data['category'], 'call_audio');
    expect(payload.data['category_label'], 'Calls and audio');
    expect(payload.data['frequency'], 'sometimes');
    expect(payload.data['frequency_label'], 'Sometimes');
    expect(
      payload.data['what_happened'],
      'I could see everyone but could not hear one person.',
    );

    final report = payload.data['report']! as Map<String, Object?>;
    expect(report['category'], 'call_audio');
    expect(report['frequency'], 'sometimes');
    expect(report['severity_label'], 'Disruptive');
    expect(
      report['what_were_you_doing'],
      'I joined the call and changed their volume.',
    );

    final troubleshooting =
        report['troubleshooting_attempted']! as List<Object?>;
    final troubleshootingLabels = troubleshooting
        .cast<Map<String, Object?>>()
        .map((entry) => entry['label'])
        .toList();
    expect(troubleshootingLabels, contains('Left and rejoined the call'));
    expect(troubleshootingLabels, contains('Changed the relevant setting'));
    expect(report['troubleshooting_note'], 'Also swapped my headphones.');

    final answers = report['category_answers']! as List<Object?>;
    final answerPairs = answers
        .cast<Map<String, Object?>>()
        .map((entry) => '${entry['question']} => ${entry['answer']}')
        .toList();
    expect(answerPairs, contains('Could you hear other participants? => No'));
    expect(report['additional_details'], 'Started after the latest update.');

    final description = payload.data['description']! as String;
    expect(description, contains('Category: Calls and audio'));
    expect(description, contains('Frequency: Sometimes'));
    expect(description, contains('What happened:'));
    expect(description, contains('Troubleshooting attempted:'));
    expect(description, contains('- Left and rejoined the call'));
    expect(description, contains('Category-specific answers:'));
  });

  test(
    'buildPayload redacts guided free-text answers before preview',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 7, 23, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Upload failed',
          reproductionSteps: 'Tried to upload a file.',
          category: BugReportCategory.mediaUpload,
          whatHappened:
              'Upload failed and my access_token=secret-token leaked.',
          frequency: BugReportFrequency.always,
          troubleshootingNote: 'Emailed support at helper@example.com.',
          categoryAnswers: {'file_size': 'about 5MB from user@example.com'},
          additionalDetails: 'Contact me at reporter@example.com.',
          includeLogs: false,
          includeDiagnostics: false,
        ),
      );

      final preview = payload.toPrettyJson();
      expect(preview, isNot(contains('secret-token')));
      expect(preview, isNot(contains('helper@example.com')));
      expect(preview, isNot(contains('user@example.com')));
      expect(preview, isNot(contains('reporter@example.com')));
    },
  );

  test(
    'buildPayload keeps legacy description when no category is selected',
    () async {
      final service = BugReportService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        deviceInfoLoader: () async => BaseDeviceInfo({'name': 'test'}),
        logLoader: ({int maxFileBytes = 200 * 1024}) async => '',
        clock: () => DateTime.utc(2026, 7, 23, 12),
      );

      final payload = await service.buildPayload(
        const BugReportInput(
          title: 'Legacy programmatic report',
          reproductionSteps: 'Open the reporter from Developer Logs.',
          actualBehavior: 'An exception was captured.',
        ),
      );

      expect(payload.data.containsKey('category'), isFalse);
      expect(payload.data.containsKey('frequency'), isFalse);
      expect(payload.data['description'], contains('Reproduction steps:'));
    },
  );
}

String _decodedAttachment(BugReportPayload payload, String name) {
  final attachment = payload.attachments.singleWhere(
    (attachment) => attachment.name == name,
  );
  return utf8.decode(base64Decode(attachment.contentBase64));
}

class _RecursiveToString {
  @override
  String toString() => toString();
}

const _windowsFixtureDrive = 'C:';

String get _windowsFixtureRoot =>
    '$_windowsFixtureDrive${r'\redaction-fixtures'}';
