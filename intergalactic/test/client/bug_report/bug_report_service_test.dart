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
        'name': 'Windows host',
        'version': '10.0',
        'localPath': '$fixtureRoot' r'\AppData\Local\InterGalactic',
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
    final decodedLogAttachment =
        utf8.decode(base64Decode(logAttachment['contentBase64']! as String));
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
        contains(
          'diagnostic-logs.txt',
        ));
  });

  test('buildPayload omits RNNoise WAV metadata and audio attachments',
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
        isNot(contains(
          'rnnoise-final_to_webrtc.wav',
        )));
    expect(payload.data.containsKey('additional_metadata'), isFalse);
    final fallback =
        payload.data['attachment_transport_fallback']! as Map<String, Object?>;
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
  });

  test('buildPayload omits additional attachments that exceed upload limit',
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
  });

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
  });

  test('buildPayload bounds fallback details after metadata omission',
      () async {
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
        return http.Response('{"reportId":"BR-123","emailStatus":"sent"}', 201,
            headers: {'content-type': 'application/json'});
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
    final largeLog = 'old line\n'
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
        'name': 'Windows host',
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

  test('buildPayload tolerates recursive device info before preview', () async {
    final recursiveDeviceInfo = <String, dynamic>{
      'name': 'Recursive test device',
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
        'name': 'Unsafe test device',
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

  test('buildPayload shrinks logs again when total payload would exceed limit',
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
    expect(payload.data['log_preview'], contains('Earlier log output omitted'));
    expect(
      _decodedAttachment(payload, 'diagnostic-logs.txt'),
      contains('Earlier log output omitted'),
    );
  });

  test('submit surfaces server failures without leaking response secrets',
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
            'report': {'title': 'Failure'}
          },
          attachments: [],
        ),
      ),
      throwsA(
        isA<BugReportSubmissionException>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('500'),
            isNot(contains('server-secret')),
          ),
        ),
      ),
    );
  });

  test('submit surfaces redacted server failure details from short responses',
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
            'report': {'title': 'Failure'}
          },
          attachments: [],
        ),
      ),
      throwsA(
        isA<BugReportSubmissionException>()
            .having(
              (error) => error.statusCode,
              'statusCode',
              400,
            )
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
  });

  test('submit wraps unexpected network failures without leaking secrets',
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
            'report': {'title': 'Transport failure'}
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
  });
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
