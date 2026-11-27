import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_receiver_probe.dart';

void main() {
  test('receiver probe cleanup failures are recovered', () async {
    var attempts = 0;

    await expectLater(
      debugRunMatrixLivekitReceiverProbeCleanupForTesting(
        operation: 'test-cleanup',
        cleanup: () {
          attempts++;
          throw StateError('receiver probe cleanup failed');
        },
      ),
      completes,
    );

    expect(attempts, 1);
  });

  test('receiver probe cleanup continues after recovered failure', () async {
    final attempts = <String>[];

    await debugRunMatrixLivekitReceiverProbeCleanupForTesting(
      operation: 'listener-dispose',
      cleanup: () {
        attempts.add('listener');
        throw StateError('listener dispose failed');
      },
    );
    await debugRunMatrixLivekitReceiverProbeCleanupForTesting(
      operation: 'room-dispose',
      cleanup: () {
        attempts.add('room');
      },
    );

    expect(attempts, ['listener', 'room']);
  });

  test('receiver probe cleanup ignores absent cleanup target', () async {
    await expectLater(
      debugRunMatrixLivekitReceiverProbeCleanupForTesting(
        operation: 'missing-cleanup',
        cleanup: null,
      ),
      completes,
    );
  });

  test('receiver probe publication operation failures are recovered', () async {
    var attempts = 0;

    final recovered =
        await debugRunMatrixLivekitReceiverProbePublicationOperationForTesting(
          operation: 'test-publication',
          publicationOperation: () {
            attempts++;
            throw StateError('receiver probe publication failed');
          },
        );

    expect(recovered, isFalse);
    expect(attempts, 1);
  });

  test('receiver probe publication operation ignores absent target', () async {
    final recovered =
        await debugRunMatrixLivekitReceiverProbePublicationOperationForTesting(
          operation: 'missing-publication',
          publicationOperation: null,
        );

    expect(recovered, isTrue);
  });
}
