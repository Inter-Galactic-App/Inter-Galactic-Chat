import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';

void main() {
  group('MatrixLivekitConnectRetryPolicy', () {
    const policy = MatrixLivekitConnectRetryPolicy();

    test('retries bounded transient network failures', () {
      expect(
        policy.retryDelayFor(
          Exception('ConnectException: no internet connection'),
          failedAttempt: 1,
        ),
        const Duration(milliseconds: 900),
      );
      expect(
        policy.retryDelayFor(
          Exception(
            'HttpException: Connection closed before full header was received',
          ),
          failedAttempt: 2,
        ),
        const Duration(milliseconds: 2200),
      );
      expect(
        policy.retryDelayFor(
          Exception('SocketException: Failed host lookup'),
          failedAttempt: 3,
        ),
        isNull,
      );
    });

    test('does not retry auth and permission failures', () {
      for (final error in [
        Exception('LiveKit statusCode: 400 bad request'),
        Exception('LiveKit statusCode: 401 unauthorized'),
        Exception('LiveKit status code: 403 forbidden'),
        Exception('LiveKit permission denied'),
        Exception('LiveKit invalid token'),
      ]) {
        expect(
          policy.retryDelayFor(error, failedAttempt: 1),
          isNull,
          reason: error.toString(),
        );
      }
    });

    test('classifies gateway and websocket transport failures as transient',
        () {
      for (final error in [
        Exception('WebSocketChannelException: connection timed out'),
        Exception('HandshakeException: connection reset by peer'),
        Exception('LiveKit statusCode: 503 service unavailable'),
        Exception('LiveKit status code: 522 connection timed out'),
      ]) {
        expect(
          policy.retryDelayFor(error, failedAttempt: 1),
          isNotNull,
          reason: error.toString(),
        );
      }
    });

    test('transient exception can include local retry cooldown guidance', () {
      const exception = MatrixLivekitCallJoinTransientNetworkException(
        attempts: 3,
        lastError: 'SocketException: Failed host lookup',
        retryAfter: Duration(seconds: 20),
      );

      expect(exception.message, contains('after 3 attempts'));
      expect(exception.message, contains('about 20 seconds'));
    });

    test('transient exception rounds fractional retry cooldown up', () {
      const exception = MatrixLivekitCallJoinTransientNetworkException(
        attempts: 3,
        lastError: 'SocketException: Failed host lookup',
        retryAfter: Duration(milliseconds: 19001),
      );

      expect(exception.message, contains('about 20 seconds'));
    });

    test('transient exception formats one-second retry cooldown singularly',
        () {
      const exception = MatrixLivekitCallJoinTransientNetworkException(
        attempts: 3,
        lastError: 'SocketException: Failed host lookup',
        retryAfter: Duration(seconds: 1),
      );

      expect(exception.message, contains('about 1 second'));
      expect(exception.message, isNot(contains('about 1 seconds')));
    });
  });
}
