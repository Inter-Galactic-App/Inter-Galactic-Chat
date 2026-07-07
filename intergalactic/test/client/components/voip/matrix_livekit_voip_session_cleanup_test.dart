import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';

void main() {
  test('LiveKit session cleanup failures are recovered', () async {
    var attempts = 0;

    final recovered = await debugRunMatrixLivekitVoipSessionCleanupForTesting(
      operation: 'test-cleanup',
      cleanup: () {
        attempts++;
        throw StateError('LiveKit session cleanup failed');
      },
    );

    expect(recovered, isFalse);
    expect(attempts, 1);
  });

  test('LiveKit session cleanup continues after recovered failure', () async {
    final attempts = <String>[];

    final firstRecovered =
        await debugRunMatrixLivekitVoipSessionCleanupForTesting(
          operation: 'listener-dispose',
          cleanup: () {
            attempts.add('listener');
            throw StateError('listener dispose failed');
          },
        );
    final secondRecovered =
        await debugRunMatrixLivekitVoipSessionCleanupForTesting(
          operation: 'room-dispose',
          cleanup: () {
            attempts.add('room');
          },
        );

    expect(firstRecovered, isFalse);
    expect(secondRecovered, isTrue);
    expect(attempts, ['listener', 'room']);
  });

  test('LiveKit session cleanup ignores absent cleanup target', () async {
    final recovered = await debugRunMatrixLivekitVoipSessionCleanupForTesting(
      operation: 'missing-cleanup',
      cleanup: null,
    );

    expect(recovered, isTrue);
  });

  test(
    'LiveKit session publication operation failures are recovered',
    () async {
      var attempts = 0;

      final recovered =
          await debugRunMatrixLivekitVoipSessionPublicationOperationForTesting(
            operation: 'test-publication',
            publicationOperation: () {
              attempts++;
              throw StateError('LiveKit publication failed');
            },
          );

      expect(recovered, isFalse);
      expect(attempts, 1);
    },
  );

  test('LiveKit session publication operation ignores absent target', () async {
    final recovered =
        await debugRunMatrixLivekitVoipSessionPublicationOperationForTesting(
          operation: 'missing-publication',
          publicationOperation: null,
        );

    expect(recovered, isTrue);
  });
}
