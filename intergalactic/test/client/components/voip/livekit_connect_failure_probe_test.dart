@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_connect_failure_probe.dart';

void main() {
  group('LivekitConnectFailureProbeResult', () {
    test('leads with the connectivity verdict LiveKit gates on', () {
      // SignalClient.connect throws ConnectException('no internet connection')
      // at signal_client.dart:117 when this reports `none`, before any socket
      // is opened. A captured stack trace put the reported lockout on exactly
      // that line, so this field is what separates a real network failure from
      // the plugin wrongly claiming there is no network.
      const lying = LivekitConnectFailureProbeResult(
        host: 'matrix.ourgalaxy.space',
        resolved: true,
        elapsed: Duration(milliseconds: 9),
        addresses: ['172.67.192.69'],
        connectivity: 'none',
      );

      final fields = lying.toLogFields();

      expect(fields, startsWith('probe_connectivity=none'));
      // Resolution working while connectivity says "none" is the signature of
      // the plugin being wrong rather than the network being down.
      expect(fields, contains('probe_resolved=true'));
      expect(fields, contains('probe_address_count=1'));
      expect(fields, isNot(contains('matrix.ourgalaxy.space')));
      expect(fields, isNot(contains('172.67.192.69')));
    });

    test('records connectivity as unknown rather than guessing', () {
      const result = LivekitConnectFailureProbeResult(
        host: 'example.test',
        resolved: false,
        elapsed: Duration(milliseconds: 5),
      );

      expect(result.toLogFields(), startsWith('probe_connectivity=unknown'));
    });

    test('reports the OS error code, which toString() hides', () {
      const result = LivekitConnectFailureProbeResult(
        host: 'matrix.ourgalaxy.space',
        resolved: false,
        elapsed: Duration(milliseconds: 14),
        errorType: 'SocketException',
        osErrorCode: 11004,
        osErrorMessage:
            'The requested name is valid, but no data of the requested type '
            'was found',
        connectivity: 'ethernet',
      );

      final fields = result.toLogFields();

      // 11004 is WSANO_DATA. It is the difference between "the network is
      // gone" and "the resolver answered, with nothing" - and it was the one
      // field no existing log line carried.
      expect(fields, contains('probe_os_error=11004'));
      expect(fields, contains('probe_resolved=false'));
      expect(fields, contains('probe_error_type=SocketException'));
      expect(fields, contains('probe_os_message_present=true'));
      expect(fields, isNot(contains('requested name is valid')));
    });

    test('flags a sub-30ms failure as served from cache', () {
      const cached = LivekitConnectFailureProbeResult(
        host: 'example.test',
        resolved: false,
        elapsed: Duration(milliseconds: 14),
        osErrorCode: 11004,
      );
      const queried = LivekitConnectFailureProbeResult(
        host: 'example.test',
        resolved: false,
        elapsed: Duration(milliseconds: 850),
        osErrorCode: 11004,
      );

      expect(cached.looksCached, isTrue);
      expect(queried.looksCached, isFalse);
      expect(cached.toLogFields(), contains('probe_likely_cached=true'));
      expect(queried.toLogFields(), contains('probe_likely_cached=false'));
    });

    test('keeps a success on one line without the endpoint details', () {
      const result = LivekitConnectFailureProbeResult(
        host: 'matrix.ourgalaxy.space',
        resolved: true,
        elapsed: Duration(milliseconds: 9),
        addresses: ['172.67.192.69', '104.21.43.252'],
      );

      final fields = result.toLogFields();

      expect(fields, contains('probe_resolved=true'));
      expect(fields, contains('probe_address_count=2'));
      expect(fields, isNot(contains('matrix.ourgalaxy.space')));
      expect(fields, isNot(contains('172.67.192.69')));
      expect(fields, isNot(contains('104.21.43.252')));
      expect(fields, isNot(contains('\n')));
    });

    test('keeps failure classification while redacting exception text', () {
      const probe = LivekitConnectFailureProbeResult(
        host: 'sfu.internal.example',
        resolved: false,
        elapsed: Duration(milliseconds: 14),
        errorType: 'SocketException',
        osErrorCode: 11004,
        osErrorMessage: 'Failed host lookup: sfu.internal.example',
      );

      final fields = formatLivekitConnectFailureLogFields(
        error: Exception(
          'WebSocket failed for https://sfu.internal.example?token=secret',
        ),
        attempt: 3,
        maxAttempts: 3,
        classifiedTransient: true,
        osErrorCode: 11004,
        probe: probe,
      );

      expect(fields, contains('error_type='));
      expect(fields, contains('classified_transient=true'));
      expect(fields, contains('os_error=11004'));
      expect(fields, contains('error_message=redacted'));
      expect(fields, isNot(contains('sfu.internal.example')));
      expect(fields, isNot(contains('token=secret')));
      expect(fields, isNot(contains('Failed host lookup')));
    });
  });

  group('livekitConnectOsErrorCode', () {
    test('unwraps a SocketException OS error', () {
      final error = SocketException(
        'Failed host lookup',
        osError: const OSError('no data of the requested type', 11004),
      );

      expect(livekitConnectOsErrorCode(error), 11004);
    });

    test('returns null for errors that carry no OS code', () {
      expect(livekitConnectOsErrorCode(Exception('boom')), isNull);
      expect(
        livekitConnectOsErrorCode(const SocketException('no osError')),
        isNull,
      );
    });
  });

  group('probeLivekitConnectFailure', () {
    test('never throws, and reports the failure instead', () async {
      // A syntactically valid name that cannot resolve. The probe runs on an
      // error path, so throwing here would break the join it is describing.
      final result = await probeLivekitConnectFailure(
        'this-host-does-not-exist.invalid',
      );

      expect(result, isNotNull);
      expect(result!.resolved, isFalse);
      expect(result.host, 'this-host-does-not-exist.invalid');
    });

    test('returns null rather than probing an empty host', () async {
      expect(await probeLivekitConnectFailure(''), isNull);
    });
  });
}
