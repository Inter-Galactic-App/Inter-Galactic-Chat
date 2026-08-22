import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/matrix/matrix_user_agent_http_client.dart';
import 'package:intergalactic/debug/log.dart';

/// Inner client that always fails, recording how many sends it saw so the
/// dedupe behaviour can be distinguished from the send behaviour.
class _FailingClient extends http.BaseClient {
  _FailingClient(this.error);

  final Object error;
  int sendCount = 0;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount++;
    requests.add(request);
    throw error;
  }
}

http.Request _get(String url) => http.Request('GET', Uri.parse(url));

void main() {
  const syncUrl =
      'https://matrix.ourgalaxy.space/_matrix/client/v3/sync?since=s123';

  group('MatrixUserAgentHttpClient failure attribution', () {
    test('rethrows the original error object untouched', () async {
      final failure = const SocketException(
        "Failed host lookup: 'matrix.ourgalaxy.space'",
      );
      final inner = _FailingClient(failure);
      final client = MatrixUserAgentHttpClient(inner);

      Object? thrown;
      try {
        await client.send(_get(syncUrl));
      } catch (error) {
        thrown = error;
      }

      // The SDK's own retry logic matches on exception type, so the wrapper
      // must not substitute or wrap what it caught.
      expect(identical(thrown, failure), isTrue);
      expect(inner.sendCount, 1);
    });

    test('still applies the user agent header before failing', () async {
      final inner = _FailingClient(const SocketException('Failed host lookup'));
      final client = MatrixUserAgentHttpClient(inner);

      await expectLater(
        client.send(_get(syncUrl)),
        throwsA(isA<SocketException>()),
      );
      expect(inner.requests.single.headers.containsKey('User-Agent'), isTrue);
    });

    test(
      'attributes the endpoint from the request URL, not the error text',
      () async {
        // This is the whole point: the error names no endpoint, but the request
        // does, so the failure is still attributable to /sync.
        final failure = const SocketException(
          "Failed host lookup: 'matrix.ourgalaxy.space'",
        );
        expect(Log.matrixRequestPathHint(failure.toString()), 'dns');
        expect(Log.matrixRequestPathHint(syncUrl), 'sync');

        final inner = _FailingClient(failure);
        final client = MatrixUserAgentHttpClient(inner);
        // Cleared rather than offset from. Log.add suppresses an entry
        // identical to the CURRENT last one by bumping its count instead of
        // appending, so an earlier test in this file emitting the same line
        // makes a skip(before) window come back empty even though the client
        // logged correctly.
        Log.log.clear();
        await expectLater(
          client.send(_get(syncUrl)),
          throwsA(isA<SocketException>()),
        );

        // Asserted against what was actually logged. Checking only
        // matrixRequestPathHint in isolation would pass even if the client
        // never logged at all, which is precisely the behaviour named here.
        final logged = Log.log
            .where((entry) => entry.source == 'matrix-http')
            .toList();
        expect(logged, hasLength(1));
        expect(logged.single.content, contains('request_path=sync'));
        expect(
          logged.single.content,
          isNot(contains('request_path=dns')),
          reason: 'the URL attributes the endpoint, not the error text',
        );
      },
    );

    test(
      'every send reaches the inner client even when logging is deduped',
      () async {
        final inner = _FailingClient(
          const SocketException('Failed host lookup'),
        );
        final client = MatrixUserAgentHttpClient(inner);

        Log.log.clear();
        for (var attempt = 0; attempt < 3; attempt++) {
          await expectLater(
            client.send(_get(syncUrl)),
            throwsA(isA<SocketException>()),
          );
        }

        // Dedupe suppresses repeated log lines, never the requests themselves.
        expect(inner.sendCount, 3);
        // The other half of that claim, which sendCount alone cannot show: if
        // dedupe regressed this would be 3, and if logging broke entirely it
        // would be 0. Only the middle value means what the name says.
        expect(
          Log.log.where((entry) => entry.source == 'matrix-http').length,
          1,
        );
      },
    );
  });

  group('MatrixUserAgentHttpClient.errorSummary', () {
    test('keeps the leading clause and drops the addressed detail', () {
      expect(
        MatrixUserAgentHttpClient.errorSummary(
          const SocketException(
            "Failed host lookup: 'matrix.ourgalaxy.space' (OS Error: The "
            'requested name is valid, but no data of the requested type was '
            'found, errno = 11004)',
          ),
        ),
        'SocketException',
      );
    });

    test('returns the whole text when there is no clause separator', () {
      expect(
        MatrixUserAgentHttpClient.errorSummary('plain failure'),
        'plain failure',
      );
    });
  });
}
