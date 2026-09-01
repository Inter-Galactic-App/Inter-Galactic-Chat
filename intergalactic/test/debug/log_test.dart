import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/log.dart';

void main() {
  group('Log.isTransientNetworkZoneError', () {
    test('classifies iOS bad-file-descriptor socket teardown as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          'SocketException: Bad file descriptor (OS Error: Bad file '
          'descriptor, errno = 9), address = matrix.ourgalaxy.space, '
          'port = 49416',
        ),
        isTrue,
      );
    });

    test('classifies the HttpException bad-fd wording as transient too', () {
      expect(
        Log.isTransientNetworkZoneError(
          'HttpException: Bad file descriptor, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/sync?since=s123',
        ),
        isTrue,
      );
    });

    test('classifies no-route-to-host as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          'SocketException: Connection failed (OS Error: No route to host, '
          'errno = 65), address = matrix.ourgalaxy.space, port = 443',
        ),
        isTrue,
      );
    });

    test('still classifies the pre-existing transient wordings', () {
      expect(
        Log.isTransientNetworkZoneError(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync',
        ),
        isTrue,
      );
      expect(
        Log.isTransientNetworkZoneError(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space'",
        ),
        isTrue,
      );
    });

    test('does not classify a genuine app error as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          "type 'Null' is not a subtype of type 'Map<String, dynamic>' "
          'in type cast',
        ),
        isFalse,
      );
      expect(
        Log.isTransientNetworkZoneError(
          'FormatException: Unexpected character',
        ),
        isFalse,
      );
    });
  });

  group('Log.matrixRequestPathHint', () {
    test('labels a sync request', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync?since=x',
        ),
        'sync',
      );
    });

    test('labels a presence request', () {
      expect(
        Log.matrixRequestPathHint(
          'MatrixException: Too many requests, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/presence/'
          '@user:ourgalaxy.space/status',
        ),
        'presence',
      );
    });

    test('labels a media request', () {
      expect(
        Log.matrixRequestPathHint(
          'ClientException: Failed, uri = '
          'https://matrix.ourgalaxy.space/_matrix/media/v3/download/'
          'ourgalaxy.space/abc123',
        ),
        'media',
      );
    });

    test('labels a key request', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Bad file descriptor, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/keys/query',
        ),
        'keys',
      );
    });

    test('falls back to socket when the error carries no URI', () {
      expect(
        Log.matrixRequestPathHint(
          'SocketException: Bad file descriptor (OS Error: Bad file '
          'descriptor, errno = 9), address = matrix.ourgalaxy.space, '
          'port = 49416',
        ),
        'socket',
      );
    });

    test('separates DNS failures from the generic socket bucket', () {
      // Windows/Winsock wording (WSANO_DATA). A host lookup fails before any
      // connection exists, so it can never carry a URI.
      expect(
        Log.matrixRequestPathHint(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
          '(OS Error: The requested name is valid, but no data of the '
          'requested type was found, errno = 11004)',
        ),
        'dns',
      );
      // Darwin wording for the same class of failure.
      expect(
        Log.matrixRequestPathHint(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
          '(OS Error: nodename nor servname provided, errno = 8)',
        ),
        'dns',
      );
    });

    test('separates keep-alive teardown from the generic socket bucket', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received',
        ),
        'http-keepalive',
      );
    });

    test('a known endpoint still wins over the failure-mode fallbacks', () {
      // The refined buckets only apply once no endpoint could be identified;
      // an error naming /sync must still report sync.
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync',
        ),
        'sync',
      );
    });

    test('labels an unclassified matrix client-api URI', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection reset, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/capabilities',
        ),
        'client-api',
      );
    });
  });
}
