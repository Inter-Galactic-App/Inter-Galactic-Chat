import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  test(
    'newly added room inherits packs from its primary Space immediately',
    () async {
      final mx = _LinkClient();
      final child = matrix.Room(id: '!child:example.org', client: mx);
      final space = matrix.Room(id: '!space:example.org', client: mx);
      _state(space, matrix.EventTypes.RoomCreate, '', {
        'type': matrix.RoomCreationTypes.mSpace,
      });

      await setSpaceChildWithCanonicalParent(space, child);

      final client = _FakeClient();
      client.testSpaces.add(_FakeSpace(client, space));
      final component = MatrixRoomEmoticonComponent(
        client,
        _FakeRoom(client, child),
      );
      expect(
        component.canonicalSpaceAncestors().map(
          (ancestor) => ancestor.identifier,
        ),
        [space.id],
      );
    },
  );

  test('room component inherits only valid canonical Space ancestry', () {
    final mx = matrix.Client('ancestry-test', database: _FakeMatrixDatabase());
    final child = matrix.Room(id: '!child:example.org', client: mx);
    final forged = matrix.Room(id: '!a-forged:example.org', client: mx);
    final valid = matrix.Room(id: '!z-valid:example.org', client: mx);
    final root = matrix.Room(id: '!root:example.org', client: mx);

    _state(child, matrix.EventTypes.SpaceParent, forged.id, {
      'canonical': true,
      'via': ['example.org'],
    });
    _state(child, matrix.EventTypes.SpaceParent, valid.id, {
      'canonical': true,
      'via': ['example.org'],
    });
    _state(child, matrix.EventTypes.SpaceParent, root.id, {
      'canonical': true,
      'via': [],
    });
    _state(valid, matrix.EventTypes.SpaceChild, child.id, {
      'via': ['example.org'],
    });
    _state(valid, matrix.EventTypes.SpaceParent, root.id, {
      'canonical': true,
      'via': ['example.org'],
    });
    _state(root, matrix.EventTypes.SpaceChild, valid.id, {
      'via': ['example.org'],
    });

    final client = _FakeClient();
    client.testSpaces.addAll([
      _FakeSpace(client, forged),
      _FakeSpace(client, valid),
      _FakeSpace(client, root),
    ]);
    final component = MatrixRoomEmoticonComponent(
      client,
      _FakeRoom(client, child),
    );

    expect(
      component.canonicalSpaceAncestors().map((space) => space.identifier),
      [valid.id, root.id],
    );
  });

  test('parent sender with child-link power can establish ancestry', () {
    final mx = matrix.Client(
      'ancestry-power-test',
      database: _FakeMatrixDatabase(),
    );
    final child = matrix.Room(id: '!child:example.org', client: mx);
    final parent = matrix.Room(id: '!parent:example.org', client: mx);
    const sender = '@admin:example.org';
    _state(child, matrix.EventTypes.SpaceParent, parent.id, {
      'canonical': true,
      'via': ['example.org'],
    }, sender: sender);
    _state(parent, matrix.EventTypes.RoomMember, sender, {
      'membership': 'join',
    });
    _state(parent, matrix.EventTypes.RoomPowerLevels, '', {
      'users': {sender: 50},
      'state_default': 50,
    });

    final client = _FakeClient();
    client.testSpaces.add(_FakeSpace(client, parent));
    final component = MatrixRoomEmoticonComponent(
      client,
      _FakeRoom(client, child),
    );
    expect(
      component.canonicalSpaceAncestors().map((space) => space.identifier),
      [parent.id],
    );
  });
}

void _state(
  matrix.Room room,
  String type,
  String key,
  Map<String, Object?> content, {
  String sender = '@sender:example.org',
}) {
  (room.states[type] ??=
      <String, matrix.StrippedStateEvent>{})[key] = matrix.StrippedStateEvent(
    type: type,
    content: content,
    senderId: sender,
    stateKey: key,
  );
}

class _FakeClient implements MatrixClient {
  final testSpaces = <Space>[];

  @override
  List<Space> get spaces => testSpaces;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoom implements MatrixRoom {
  _FakeRoom(this.testClient, this.testRoom);
  final _FakeClient testClient;
  final matrix.Room testRoom;

  @override
  _FakeClient get client => testClient;

  @override
  matrix.Room get matrixRoom => testRoom;

  @override
  String get identifier => testRoom.id;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSpace implements MatrixSpace {
  _FakeSpace(this.testClient, this.testRoom);
  final _FakeClient testClient;
  final matrix.Room testRoom;

  @override
  _FakeClient get client => testClient;

  @override
  matrix.Room get matrixRoom => testRoom;

  @override
  String get identifier => testRoom.id;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LinkClient extends matrix.Client {
  _LinkClient() : super('new-space-link-test', database: _FakeMatrixDatabase());

  @override
  String? get userID => '@admin:example.org';

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async => 'event';
}
