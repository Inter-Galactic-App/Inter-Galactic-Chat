import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:matrix/encryption.dart' as matrix_crypto;
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('matrixRoomLoadDecryptedEvent', () {
    test('returns a stored encrypted event decrypted', () async {
      final stored = _encryptedEvent(
        eventId: r'$pinned',
        content: const {
          'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session-1',
          'sender_key': 'sender-key-1',
          'ciphertext': 'ciphertext',
        },
      );
      final encryption = _FakeEncryption(
        onDecrypt: (event) async =>
            _messageEvent(eventId: event.eventId, body: 'the pinned body'),
      );

      final loaded = await matrixRoomLoadDecryptedEvent(
        fetchEvent: () async => stored,
        encryption: encryption,
      );

      expect(loaded, isNotNull);
      expect(loaded!.type, matrix.EventTypes.Message);
      expect(loaded.content['body'], 'the pinned body');
      expect(encryption.decryptCalls, 1);
      // Read-side only: the SDK must not be asked to persist the plaintext.
      expect(encryption.storeFlags, [false]);
    });

    test('decrypts against the original source of a stored failure', () async {
      // The SDK records the pre-decryption event here, and it records it as an
      // `Event` - a bare `MatrixEvent` is deliberately not followed.
      final original = _encryptedEvent(
        eventId: r'$pinned',
        content: const {
          'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session-original',
          'sender_key': 'sender-key-original',
          'ciphertext': 'ciphertext',
        },
      );
      final stored = _encryptedEvent(
        eventId: r'$pinned',
        content: const {
          'msgtype': matrix.MessageTypes.BadEncrypted,
          'body': 'Unable to decrypt this event.',
        },
        originalSource: original,
      );
      final encryption = _FakeEncryption(
        onDecrypt: (event) async =>
            _messageEvent(eventId: event.eventId, body: 'recovered'),
      );

      final loaded = await matrixRoomLoadDecryptedEvent(
        fetchEvent: () async => stored,
        encryption: encryption,
      );

      expect(loaded!.content['body'], 'recovered');
      expect(
        encryption.decryptedSources.single.content['session_id'],
        'session-original',
      );
    });

    test(
      'keeps an undecryptable event rather than throwing or dropping it',
      () async {
        final stored = _encryptedEvent(
          eventId: r'$pinned',
          content: const {
            'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
            'session_id': 'session-missing',
            'sender_key': 'sender-key-missing',
            'ciphertext': 'ciphertext',
          },
        );
        final encryption = _FakeEncryption(
          // What the SDK actually does when the session key is missing: it
          // returns a BadEncrypted placeholder rather than throwing.
          onDecrypt: (event) async => _encryptedEvent(
            eventId: event.eventId,
            content: const {
              'msgtype': matrix.MessageTypes.BadEncrypted,
              'body': 'The sender has not sent us the session key.',
              'can_request_session': true,
              'session_id': 'session-missing',
              'sender_key': 'sender-key-missing',
            },
          ),
        );
        final logged = <String>[];

        final loaded = await matrixRoomLoadDecryptedEvent(
          fetchEvent: () async => stored,
          encryption: encryption,
          onLog: (message, error) => logged.add(message),
        );

        expect(loaded, isNotNull);
        expect(loaded!.type, matrix.EventTypes.Encrypted);
        expect(loaded.messageType, matrix.MessageTypes.BadEncrypted);
        expect(logged, isEmpty);
      },
    );

    test('keeps the event and logs when decryption throws', () async {
      final stored = _encryptedEvent(
        eventId: r'$pinned',
        content: const {
          'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session-1',
          'sender_key': 'sender-key-1',
          'ciphertext': 'ciphertext',
        },
      );
      final encryption = _FakeEncryption(
        onDecrypt: (event) async => throw StateError('decrypt exploded'),
      );
      final logged = <String>[];

      final loaded = await matrixRoomLoadDecryptedEvent(
        fetchEvent: () async => stored,
        encryption: encryption,
        onLog: (message, error) => logged.add(message),
      );

      expect(loaded, same(stored));
      expect(logged, isNotEmpty);
    });

    test('leaves plaintext events and missing events alone', () async {
      final plain = _messageEvent(eventId: r'$plain', body: 'hello');
      final encryption = _FakeEncryption(
        onDecrypt: (event) async => fail('must not decrypt a plaintext event'),
      );

      expect(
        await matrixRoomLoadDecryptedEvent(
          fetchEvent: () async => plain,
          encryption: encryption,
        ),
        same(plain),
      );
      expect(
        await matrixRoomLoadDecryptedEvent(
          fetchEvent: () async => null,
          encryption: encryption,
        ),
        isNull,
      );
      expect(encryption.decryptCalls, 0);
    });

    test('does not decrypt when encryption is unavailable or off', () async {
      final stored = _encryptedEvent(
        eventId: r'$pinned',
        content: const {
          'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session-1',
          'sender_key': 'sender-key-1',
          'ciphertext': 'ciphertext',
        },
      );
      final disabled = _FakeEncryption(
        enabled: false,
        onDecrypt: (event) async => fail('must not decrypt while disabled'),
      );

      expect(
        await matrixRoomLoadDecryptedEvent(
          fetchEvent: () async => stored,
          encryption: null,
        ),
        same(stored),
      );
      expect(
        await matrixRoomLoadDecryptedEvent(
          fetchEvent: () async => stored,
          encryption: disabled,
        ),
        same(stored),
      );
      expect(disabled.decryptCalls, 0);
    });
  });

  group('matrixRoomDecryptSourceForEvent', () {
    test('prefers the original source when it is an Event', () {
      final original = _encryptedEvent(
        eventId: r'$original',
        content: const {'ciphertext': 'ciphertext'},
      );
      final failure = _encryptedEvent(
        eventId: r'$failure',
        content: const {'msgtype': matrix.MessageTypes.BadEncrypted},
        originalSource: original,
      );

      expect(matrixRoomDecryptSourceForEvent(failure), same(original));
      expect(matrixRoomDecryptSourceForEvent(original), same(original));
    });
  });
}

matrix.Event _encryptedEvent({
  required String eventId,
  required Map<String, dynamic> content,
  matrix.MatrixEvent? originalSource,
}) {
  return matrix.Event(
    content: content,
    type: matrix.EventTypes.Encrypted,
    eventId: eventId,
    senderId: '@sender:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    room: _FakeSdkRoom(),
    originalSource: originalSource,
  );
}

matrix.Event _messageEvent({required String eventId, required String body}) {
  return matrix.Event(
    content: {'msgtype': matrix.MessageTypes.Text, 'body': body},
    type: matrix.EventTypes.Message,
    eventId: eventId,
    senderId: '@sender:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    room: _FakeSdkRoom(),
  );
}

class _FakeEncryption implements matrix_crypto.Encryption {
  _FakeEncryption({required this.onDecrypt, this.enabled = true});

  final Future<matrix.Event> Function(matrix.Event event) onDecrypt;

  @override
  final bool enabled;

  int decryptCalls = 0;
  final List<matrix.Event> decryptedSources = [];
  final List<bool> storeFlags = [];

  @override
  Future<matrix.Event> decryptRoomEvent(
    matrix.Event event, {
    bool store = false,
    matrix.EventUpdateType updateType = matrix.EventUpdateType.timeline,
  }) async {
    decryptCalls++;
    decryptedSources.add(event);
    storeFlags.add(store);
    return onDecrypt(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => '!room:example.org';

  @override
  Future<void> requestSessionKey(String sessionId, String senderKey) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
