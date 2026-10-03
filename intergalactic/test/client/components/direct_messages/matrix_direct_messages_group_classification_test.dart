import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/direct_messages/matrix_direct_messages_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

const _roomId = '!room:ourgalaxy.space';
const _selfId = '@self:ourgalaxy.space';
const _partnerId = '@friend:ourgalaxy.space';

/// The room every test here starts from is one the homeserver still calls a
/// direct chat: `m.direct` names [_partnerId]. That is the only room where
/// either fix can be observed - a room that is not a direct message anyway
/// would report "not a direct message, no partner" whether the gates exist or
/// not.
///
/// `matrix_direct_messages_component_test.dart` covers the static snapshot and
/// account-data helpers; neither of them can see a call site.
void main() {
  late _FakeSdkClient sdkClient;
  late _FakeSdkRoom sdkRoom;
  late MatrixDirectMessagesComponent component;
  late _FakeMatrixRoom room;

  setUp(() {
    sdkClient = _FakeSdkClient();
    sdkRoom = _FakeSdkRoom();
    room = _FakeMatrixRoom(sdkRoom);
    component = MatrixDirectMessagesComponent(_FakeMatrixClient(sdkClient));
  });

  tearDown(() async {
    await component.dispose();
  });

  group('MatrixDirectMessagesComponent explicit group classification', () {
    test('a room the account has not grouped stays a direct message', () {
      // The control. Without it, the case below could pass because the fake
      // never looked like a direct message to begin with.
      expect(component.isRoomExplicitlyGroup(room), isFalse);
      expect(component.isRoomDirectMessage(room), isTrue);
      expect(component.getDirectMessagePartnerId(room), _partnerId);
    });

    test(
      'a room the account has grouped reports no direct-message partner id',
      () {
        sdkClient.setExplicitGroupRoomIds(const [_roomId]);

        expect(
          component.isRoomExplicitlyGroup(room),
          isTrue,
          reason:
              'the group marker never reached the component, so the two '
              'expectations below would hold for the wrong reason.',
        );
        expect(component.isRoomDirectMessage(room), isFalse);
        expect(
          component.getDirectMessagePartnerId(room),
          isNull,
          reason:
              'consumers key direct-message presentation on a non-null '
              'partner id, so the two predicates disagreeing puts a room the '
              'account grouped back into direct-message presentation.',
        );
      },
    );
  });

  group('MatrixDirectMessagesComponent markRoomAsGroup', () {
    test(
      'keeps the direct marker when the group classification cannot be saved',
      () async {
        sdkClient.accountDataWriteError = _HomeserverFailure();

        await expectLater(
          component.markRoomAsGroup(room),
          throwsA(isA<_HomeserverFailure>()),
        );

        expect(
          sdkClient.accountDataWrites,
          hasLength(1),
          reason:
              'the write that was supposed to fail never happened, so this '
              'says nothing about what happens when it does.',
        );
        expect(
          sdkRoom.removeFromDirectChatCalls,
          0,
          reason:
              'the `m.direct` entry was removed before the group '
              'classification was saved, so the failed save leaves the room '
              'with neither marker.',
        );
        expect(component.isRoomExplicitlyGroup(room), isFalse);
        expect(component.getDirectMessagePartnerId(room), _partnerId);
      },
    );

    test(
      'restores the classification when the direct marker cannot be removed',
      () async {
        sdkRoom.removeFromDirectChatError = _HomeserverFailure();

        await expectLater(
          component.markRoomAsGroup(room),
          throwsA(isA<_HomeserverFailure>()),
        );

        expect(
          sdkRoom.removeFromDirectChatCalls,
          1,
          reason:
              'the removal never ran, so its failure path was never entered.',
        );
        expect(
          sdkClient.accountDataWrites,
          hasLength(2),
          reason: 'the classification was saved and never rolled back.',
        );
        expect(
          component.isRoomExplicitlyGroup(room),
          isFalse,
          reason:
              'the `m.direct` entry survived, so keeping the group '
              'classification leaves the room classified two ways at once.',
        );
        expect(component.getDirectMessagePartnerId(room), _partnerId);
      },
    );
  });
}

class _HomeserverFailure implements Exception {
  @override
  String toString() => 'homeserver refused the write';
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this._sdkClient);

  final _FakeSdkClient _sdkClient;

  @override
  matrix.Client get matrixClient => _sdkClient;

  @override
  matrix.Client getMatrixClient() => _sdkClient;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixRoom implements MatrixRoom {
  _FakeMatrixRoom(this._sdkRoom);

  final _FakeSdkRoom _sdkRoom;

  @override
  String get identifier => _roomId;

  @override
  matrix.Room get matrixRoom => _sdkRoom;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements matrix.Client {
  final Map<String, matrix.BasicEvent> _accountData = {};

  /// Every attempted account-data write, including one that then failed:
  /// recorded before [accountDataWriteError] is thrown so a test can tell an
  /// attempt that failed from a write that was never made.
  final List<Map<String, Object?>> accountDataWrites = [];

  Object? accountDataWriteError;

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  String? get userID => _selfId;

  @override
  Map<String, matrix.BasicEvent> get accountData => _accountData;

  void setExplicitGroupRoomIds(Iterable<String> roomIds) {
    _accountData[interGalacticGroupRoomsAccountDataKey] = matrix.BasicEvent(
      type: interGalacticGroupRoomsAccountDataKey,
      content: MatrixDirectMessagesComponent.explicitGroupRoomIdsToContent(
        roomIds,
      ),
    );
  }

  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> body,
  ) async {
    // Snapshotted: the component builds this map itself, and a recorded
    // reference to a map it later edits would report the wrong history.
    accountDataWrites.add(Map<String, Object?>.from(body));

    final error = accountDataWriteError;
    if (error != null) {
      throw error;
    }

    _accountData[type] = matrix.BasicEvent(
      type: type,
      content: Map<String, Object?>.from(body),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkRoom implements matrix.Room {
  String? _directChatMatrixID = _partnerId;

  int removeFromDirectChatCalls = 0;

  Object? removeFromDirectChatError;

  @override
  String get id => _roomId;

  @override
  String? get directChatMatrixID => _directChatMatrixID;

  @override
  bool get isDirectChat => _directChatMatrixID != null;

  @override
  Future<void> removeFromDirectChat() async {
    removeFromDirectChatCalls += 1;

    final error = removeFromDirectChatError;
    if (error != null) {
      throw error;
    }

    _directChatMatrixID = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
