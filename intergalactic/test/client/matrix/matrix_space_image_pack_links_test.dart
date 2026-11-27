import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  test(
    'adding a room without a primary Space makes the new link canonical',
    () async {
      final client = _WriteClient();
      final space = _room(client, '!space:example.org', isSpace: true);
      final child = _room(client, '!child:example.org');

      await setSpaceChildWithCanonicalParent(space, child);

      expect(client.writes, hasLength(2));
      expect(client.writes.first.type, matrix.EventTypes.SpaceChild);
      expect(client.writes.last.type, matrix.EventTypes.SpaceParent);
      expect(client.writes.last.content['canonical'], isTrue);
      expect(
        child
            .getState(matrix.EventTypes.SpaceParent, space.id)
            ?.content['canonical'],
        isTrue,
      );
      expect(
        space.getState(matrix.EventTypes.SpaceChild, child.id)?.content['via'],
        ['example.org'],
      );
    },
  );

  test('adding a room preserves an existing primary Space', () async {
    final client = _WriteClient();
    final space = _room(client, '!space:example.org', isSpace: true);
    final child = _room(client, '!child:example.org');
    _state(child, matrix.EventTypes.SpaceParent, '!other:example.org', {
      'canonical': true,
      'via': ['example.org'],
    });

    await setSpaceChildWithCanonicalParent(space, child);

    expect(client.writes.last.content.containsKey('canonical'), isFalse);
    expect(
      child
          .getState(matrix.EventTypes.SpaceParent, '!other:example.org')
          ?.content['canonical'],
      isTrue,
    );
  });

  test('re-adding its primary Space does not erase canonical state', () async {
    final client = _WriteClient();
    final space = _room(client, '!space:example.org', isSpace: true);
    final child = _room(client, '!child:example.org');
    _state(child, matrix.EventTypes.SpaceParent, space.id, {
      'canonical': true,
      'via': ['example.org'],
    });

    await setSpaceChildWithCanonicalParent(space, child);

    expect(client.writes.last.content['canonical'], isTrue);
  });

  test('repair only writes editable children with no primary Space', () async {
    final client = _WriteClient();
    final space = _room(client, '!space:example.org', isSpace: true);
    final needsRepair = _room(client, '!repair:example.org');
    final already = _room(client, '!already:example.org');
    final other = _room(client, '!other:example.org');
    final denied = _room(client, '!denied:example.org', canEditParent: false);
    final moderator = _room(client, '!moderator:example.org', powerLevel: 50);
    final failed = _room(client, '!failed:example.org');
    client.failRoomId = failed.id;
    for (final id in [
      needsRepair.id,
      already.id,
      other.id,
      denied.id,
      moderator.id,
      failed.id,
      '!unavailable:example.org',
    ]) {
      _state(space, matrix.EventTypes.SpaceChild, id, {
        'via': ['example.org'],
      });
    }
    _state(already, matrix.EventTypes.SpaceParent, space.id, {
      'canonical': true,
      'via': ['example.org'],
    });
    _state(other, matrix.EventTypes.SpaceParent, '!primary:example.org', {
      'canonical': true,
      'via': ['example.org'],
    });

    final result = await repairSpaceImagePackParentLinks(space);

    expect(result.repaired, 1);
    expect(result.alreadyCanonical, 1);
    expect(result.otherCanonicalParent, 1);
    expect(result.noPermission, 2);
    expect(result.unavailable, 1);
    expect(result.failed, 1);
    expect(client.writes.map((write) => write.roomId), [
      needsRepair.id,
      failed.id,
    ]);
    expect(
      needsRepair
          .getState(matrix.EventTypes.SpaceParent, space.id)
          ?.content['canonical'],
      isTrue,
    );
    expect(other.getState(matrix.EventTypes.SpaceParent, space.id), isNull);
    expect(moderator.getState(matrix.EventTypes.SpaceParent, space.id), isNull);
  });

  test(
    'repair uses a snapshot when child links change during a write',
    () async {
      final client = _WriteClient();
      final space = _room(client, '!space:example.org', isSpace: true);
      final first = _room(client, '!first:example.org');
      final second = _room(client, '!second:example.org');
      for (final child in [first, second]) {
        _state(space, matrix.EventTypes.SpaceChild, child.id, {
          'via': ['example.org'],
        });
      }
      client.onWrite = () {
        _state(space, matrix.EventTypes.SpaceChild, '!new:example.org', {
          'via': ['example.org'],
        });
        client.onWrite = null;
      };

      final result = await repairSpaceImagePackParentLinks(space);

      expect(result.repaired, 2);
      expect(client.writes.map((write) => write.roomId), [first.id, second.id]);
    },
  );

  test('Space moderator cannot run the bulk repair', () async {
    final client = _WriteClient();
    final space = _room(
      client,
      '!space:example.org',
      isSpace: true,
      powerLevel: 50,
    );
    final child = _room(client, '!child:example.org');
    _state(space, matrix.EventTypes.SpaceChild, child.id, {
      'via': ['example.org'],
    });

    expect(canRepairSpaceImagePackParentLinks(space), isFalse);
    await expectLater(
      repairSpaceImagePackParentLinks(space),
      throwsA(isA<StateError>()),
    );
    expect(client.writes, isEmpty);
  });
}

_TestRoom _room(
  _WriteClient client,
  String id, {
  bool isSpace = false,
  bool canEditParent = true,
  int powerLevel = 100,
}) {
  final room = _TestRoom(client, id, canEditParent: canEditParent);
  client.testRooms[id] = room;
  if (isSpace) {
    _state(room, matrix.EventTypes.RoomCreate, '', {
      'type': matrix.RoomCreationTypes.mSpace,
    });
  }
  _state(room, matrix.EventTypes.RoomPowerLevels, '', {
    'users': {'@admin:example.org': powerLevel},
    'state_default': 50,
  });
  return room;
}

void _state(
  matrix.Room room,
  String type,
  String key,
  Map<String, Object?> content,
) {
  (room.states[type] ??=
      <String, matrix.StrippedStateEvent>{})[key] = matrix.StrippedStateEvent(
    type: type,
    content: content,
    senderId: '@admin:example.org',
    stateKey: key,
  );
}

class _WriteClient extends matrix.Client {
  _WriteClient() : super('space-link-test', database: _FakeMatrixDatabase());

  final testRooms = <String, matrix.Room>{};
  final writes = <_Write>[];
  String? failRoomId;
  void Function()? onWrite;

  @override
  String? get userID => '@admin:example.org';

  @override
  matrix.Room? getRoomById(String id) => testRooms[id];

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    writes.add(_Write(roomId, eventType, stateKey, body));
    onWrite?.call();
    if (roomId == failRoomId) throw StateError('write failed');
    return 'event-${writes.length}';
  }
}

class _TestRoom extends matrix.Room {
  _TestRoom(_WriteClient client, String id, {required this.canEditParent})
    : super(id: id, client: client);

  final bool canEditParent;

  @override
  bool canChangeStateEvent(String action) =>
      action == matrix.EventTypes.SpaceParent ? canEditParent : true;
}

class _Write {
  _Write(this.roomId, this.type, this.stateKey, this.content);
  final String roomId;
  final String type;
  final String stateKey;
  final Map<String, Object?> content;
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
