import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';

void main() {
  test('addClient publishes an already-loaded self profile', () async {
    final manager = ClientManager();
    addTearDown(manager.close);
    final client = _FakeClient(
      self: _FakeProfile(
        avatar: MemoryImage(Uint8List.fromList(const [1])),
      ),
    );

    final update = expectLater(
      manager.onClientUpdated.stream,
      emits(
        predicate<Client>(
          (updated) =>
              identical(updated, client) && updated.self?.avatar != null,
          'the added client with its loaded self avatar',
        ),
      ),
    );

    manager.addClient(client);

    await update;
  });

  test('forwards self profile refreshes after a client is added', () async {
    final manager = ClientManager();
    addTearDown(manager.close);
    final client = _FakeClient();
    manager.addClient(client);

    final update = expectLater(
      manager.onClientUpdated.stream,
      emits(
        predicate<Client>(
          (updated) =>
              identical(updated, client) && updated.self?.avatar != null,
          'the existing client after its self avatar refreshes',
        ),
      ),
    );

    client.publishSelfUpdated(
      _FakeProfile(
        avatar: MemoryImage(Uint8List.fromList(const [2])),
      ),
    );

    await update;
  });

  test('close cancels space subscriptions owned by the manager', () async {
    final manager = ClientManager();
    final client = _FakeClient();
    final space = _FakeSpace(client);
    client.spacesInternal.add(space);

    manager.addClient(client);
    await Future<void>.delayed(Duration.zero);

    await manager.close();

    expect(space.updateCancelCount, 1);
    expect(space.childRoomCancelCount, 1);
  });

  test('close cancels direct message aggregate component subscriptions',
      () async {
    final manager = ClientManager();
    final directMessages = _FakeDirectMessagesComponent();
    final client = _FakeClient(directMessages: directMessages);
    directMessages.client = client;

    manager.addClient(client);
    await Future<void>.delayed(Duration.zero);

    expect(directMessages.roomsListListenCount, 1);
    expect(directMessages.highlightedListListenCount, 1);

    await manager.close();

    expect(directMessages.roomsListCancelCount, 1);
    expect(directMessages.highlightedListCancelCount, 1);
  });
}

class _FakeClient implements Client {
  _FakeClient({
    this.self,
    this.directMessages,
  });

  final _onSync = StreamController<void>.broadcast();
  final _onSelfUpdated = StreamController<void>.broadcast();
  final _onRoomAdded = StreamController<int>.broadcast();
  final _onRoomRemoved = StreamController<int>.broadcast();
  final _onSpaceAdded = StreamController<int>.broadcast();
  final _onSpaceRemoved = StreamController<int>.broadcast();

  @override
  final String identifier = 'fake-client';

  @override
  Profile? self;
  final List<Space> spacesInternal = [];
  final DirectMessagesComponent<_FakeClient>? directMessages;
  bool _closed = false;

  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
      connectionStatusChanged = StoredStreamController();

  @override
  List<Room> get rooms => const [];

  @override
  List<Space> get spaces => spacesInternal;

  void publishSelfUpdated(Profile profile) {
    self = profile;
    _onSelfUpdated.add(null);
  }

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  Stream<void> get onSelfUpdated => _onSelfUpdated.stream;

  @override
  Stream<int> get onRoomAdded => _onRoomAdded.stream;

  @override
  Stream<int> get onRoomRemoved => _onRoomRemoved.stream;

  @override
  Stream<int> get onSpaceAdded => _onSpaceAdded.stream;

  @override
  Stream<int> get onSpaceRemoved => _onSpaceRemoved.stream;

  @override
  T? getComponent<T extends Component>() {
    final directMessagesComponent = directMessages;
    if (directMessagesComponent is T) {
      return directMessagesComponent as T;
    }

    return null;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    final fakeSpaces = spacesInternal.whereType<_FakeSpace>().toList();
    final fakeDirectMessages = directMessages is _FakeDirectMessagesComponent
        ? directMessages as _FakeDirectMessagesComponent
        : null;
    await Future.wait([
      _onSync.close(),
      _onSelfUpdated.close(),
      _onRoomAdded.close(),
      _onRoomRemoved.close(),
      _onSpaceAdded.close(),
      _onSpaceRemoved.close(),
      connectionStatusChanged.close(),
      ...fakeSpaces.map((space) => space.close()),
      if (fakeDirectMessages != null) fakeDirectMessages.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpace implements Space {
  _FakeSpace(this.client);

  late final StreamController<void> _onUpdate =
      StreamController<void>.broadcast(
    onListen: () => updateListenCount += 1,
    onCancel: () => updateCancelCount += 1,
  );
  late final StreamController<Room> _onChildRoomUpdated =
      StreamController<Room>.broadcast(
    onListen: () => childRoomListenCount += 1,
    onCancel: () => childRoomCancelCount += 1,
  );
  int updateListenCount = 0;
  int updateCancelCount = 0;
  int childRoomListenCount = 0;
  int childRoomCancelCount = 0;
  bool _closed = false;

  @override
  final Client client;

  @override
  String get identifier => 'fake-space';

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  Stream<Room> get onChildRoomUpdated => _onChildRoomUpdated.stream;

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    await Future.wait([
      _onUpdate.close(),
      _onChildRoomUpdated.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDirectMessagesComponent
    implements DirectMessagesComponent<_FakeClient> {
  @override
  late _FakeClient client;
  int roomsListListenCount = 0;
  int roomsListCancelCount = 0;
  int highlightedListListenCount = 0;
  int highlightedListCancelCount = 0;

  late final StreamController<void> _roomsListController =
      StreamController<void>.broadcast(
    onListen: () => roomsListListenCount += 1,
    onCancel: () => roomsListCancelCount += 1,
  );
  late final StreamController<void> _highlightedListController =
      StreamController<void>.broadcast(
    onListen: () => highlightedListListenCount += 1,
    onCancel: () => highlightedListCancelCount += 1,
  );

  @override
  List<Room> directMessageRooms = const [];

  @override
  List<Room> highlightedRoomsList = const [];

  @override
  Stream<void> get onRoomsListUpdated => _roomsListController.stream;

  @override
  Stream<void> get onHighlightedRoomsListUpdated =>
      _highlightedListController.stream;

  @override
  bool isRoomDirectMessage(Room room) => false;

  Future<void> close() async {
    await Future.wait([
      _roomsListController.close(),
      _highlightedListController.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile({this.avatar});

  @override
  final ImageProvider? avatar;

  @override
  String get identifier => '@user:example.org';

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Test User';

  @override
  String? get detail => identifier;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => '';
}
