import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_image_pack_compatibility.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

const _packContent = <String, dynamic>{
  'pack': {'display_name': 'Space pack'},
  'images': {
    'image': {'url': 'mxc://example.org/image'},
  },
};

void main() {
  test(
    'the real room state manager refreshes a pack after both writes',
    () async {
      final client = _WriteClient();
      final room = _WriteRoom(client);
      final state = MatrixEmoticonRoomStateManager(room);
      addTearDown(state.onStateChangedController.close);
      final component = MatrixEmoticonComponent(_FakeMatrixClient(), state);

      expect(component.ownedPacks, isEmpty);
      await state.setState('space-pack', _packContent);
      await Future<void>.delayed(Duration.zero);

      expect(client.writeTypes, [
        MatrixImagePackCompatibility.stableRoomEventType,
        MatrixImagePackCompatibility.legacyRoomEventType,
      ]);
      expect(component.ownedPacks.single.identifier, 'space-pack');
      expect(state.getState('space-pack'), _packContent);
    },
  );

  for (final failedType in [
    MatrixImagePackCompatibility.stableRoomEventType,
    MatrixImagePackCompatibility.legacyRoomEventType,
  ]) {
    test(
      'partial $failedType failure still refreshes the successful write',
      () async {
        final client = _WriteClient()..failedType = failedType;
        final room = _WriteRoom(client);
        final state = MatrixEmoticonRoomStateManager(room);
        addTearDown(state.onStateChangedController.close);
        final component = MatrixEmoticonComponent(_FakeMatrixClient(), state);

        await expectLater(
          state.setState('space-pack', _packContent),
          throwsA(isA<StateError>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(client.writeTypes, [
          MatrixImagePackCompatibility.stableRoomEventType,
          MatrixImagePackCompatibility.legacyRoomEventType,
        ]);
        expect(component.ownedPacks.single.identifier, 'space-pack');
        expect(state.getState('space-pack'), _packContent);
      },
    );
  }
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WriteClient extends matrix.Client {
  _WriteClient() : super('image-pack-test', database: _FakeMatrixDatabase());

  String? failedType;
  final writeTypes = <String>[];
  final written = <String, matrix.MatrixEvent>{};
  var nextEvent = 0;

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    writeTypes.add(eventType);
    if (eventType == failedType) throw StateError('write failed');
    final eventId = 'event-${++nextEvent}';
    written[eventId] = matrix.MatrixEvent(
      type: eventType,
      content: Map<String, dynamic>.from(body),
      senderId: '@admin:example.org',
      eventId: eventId,
      originServerTs: DateTime.utc(2026, 9, 24),
      stateKey: stateKey,
    );
    return eventId;
  }
}

class _WriteRoom extends matrix.Room {
  _WriteRoom(_WriteClient client)
    : super(id: '!space:example.org', client: client);

  @override
  Future<matrix.Event?> getEventById(String eventId) async {
    final event = (client as _WriteClient).written[eventId];
    return event == null ? null : matrix.Event.fromMatrixEvent(event, this);
  }
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
