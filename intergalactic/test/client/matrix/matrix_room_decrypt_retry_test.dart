import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('MatrixRoom stale session decrypt retry', () {
    test(
      'requests corrupted sessions from original encrypted event fields',
      () {
        final originalEvent = _encryptedEvent(
          content: const {
            'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
            'session_id': 'session-1',
            'sender_key': 'sender-key-1',
            'ciphertext': 'ciphertext',
          },
        );
        final failedEvent = _encryptedEvent(
          content: const {
            'msgtype': matrix.MessageTypes.BadEncrypted,
            'body': 'The secure channel with the sender was corrupted.',
          },
          originalSource: originalEvent,
        );

        expect(
          matrixRoomShouldRequestSessionForBadEncryptedEvent(failedEvent),
          isTrue,
        );
        expect(matrixRoomSessionRequestInfoForBadEncryptedEvent(failedEvent), (
          sessionId: 'session-1',
          senderKey: 'sender-key-1',
        ));
      },
    );

    test(
      'requests corrupted sessions from persisted original source fields',
      () {
        final originalEvent = matrix.MatrixEvent(
          content: const {
            'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
            'session_id': 'session-persisted',
            'sender_key': 'sender-key-persisted',
            'ciphertext': 'ciphertext',
          },
          type: matrix.EventTypes.Encrypted,
          eventId: r'$persisted-original',
          senderId: '@sender:example.org',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
          roomId: '!room:example.org',
        );
        final failedEvent = _encryptedEvent(
          content: const {
            'msgtype': matrix.MessageTypes.BadEncrypted,
            'body': 'The secure channel with the sender was corrupted.',
          },
          originalSource: originalEvent,
        );

        expect(
          matrixRoomShouldRequestSessionForBadEncryptedEvent(failedEvent),
          isTrue,
        );
        expect(matrixRoomSessionRequestInfoForBadEncryptedEvent(failedEvent), (
          sessionId: 'session-persisted',
          senderKey: 'sender-key-persisted',
        ));
      },
    );

    test('keeps unrelated non-requestable decrypt failures skipped', () {
      final failedEvent = _encryptedEvent(
        content: const {
          'msgtype': matrix.MessageTypes.BadEncrypted,
          'body': 'Unable to decrypt this event.',
        },
      );

      expect(
        matrixRoomShouldRequestSessionForBadEncryptedEvent(failedEvent),
        isFalse,
      );
      expect(
        matrixRoomSessionRequestInfoForBadEncryptedEvent(failedEvent),
        isNull,
      );
    });

    test('skips corrupted sessions without request identifiers', () {
      final failedEvent = _encryptedEvent(
        content: const {
          'msgtype': matrix.MessageTypes.BadEncrypted,
          'body': 'The secure channel with the sender was corrupted.',
        },
      );

      expect(
        matrixRoomShouldRequestSessionForBadEncryptedEvent(failedEvent),
        isFalse,
      );
      expect(
        matrixRoomSessionRequestInfoForBadEncryptedEvent(failedEvent),
        isNull,
      );
    });

    test('keeps normal requestable missing-session behavior', () {
      final failedEvent = _encryptedEvent(
        content: const {
          'msgtype': matrix.MessageTypes.BadEncrypted,
          'body': 'The sender has not sent us the session key.',
          'can_request_session': true,
          'session_id': 'session-2',
          'sender_key': 'sender-key-2',
        },
      );

      expect(matrixRoomSessionRequestInfoForBadEncryptedEvent(failedEvent), (
        sessionId: 'session-2',
        senderKey: 'sender-key-2',
      ));
    });
  });
}

matrix.Event _encryptedEvent({
  required Map<String, dynamic> content,
  matrix.MatrixEvent? originalSource,
}) {
  return matrix.Event(
    content: content,
    type: matrix.EventTypes.Encrypted,
    eventId: r'$encrypted-event',
    senderId: '@sender:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    room: _FakeSdkRoom(),
    originalSource: originalSource,
  );
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
