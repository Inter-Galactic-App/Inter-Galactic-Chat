import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
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
}

class _FakeClient implements Client {
  _FakeClient({this.self});

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

  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
      connectionStatusChanged = StoredStreamController();

  @override
  List<Room> get rooms => const [];

  @override
  List<Space> get spaces => const [];

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
  T? getComponent<T extends Component>() => null;

  @override
  Future<void> close() async {
    await Future.wait([
      _onSync.close(),
      _onSelfUpdated.close(),
      _onRoomAdded.close(),
      _onRoomRemoved.close(),
      _onSpaceAdded.close(),
      _onSpaceRemoved.close(),
      connectionStatusChanged.close(),
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
