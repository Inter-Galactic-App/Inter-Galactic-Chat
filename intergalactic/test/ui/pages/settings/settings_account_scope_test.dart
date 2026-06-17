import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('preferred settings account uses the focused account first', () async {
    final manager = ClientManager();
    addTearDown(manager.close);

    final firstClient = _FakeClient('first-client');
    final focusedClient = _FakeClient('focused-client');

    manager.addClient(firstClient);
    manager.addClient(focusedClient);
    await preferences.filterClient.set(focusedClient.identifier);

    expect(
      SettingsAccountController.resolvePreferredClient(manager),
      same(focusedClient),
    );
  });

  test('settings account controller selection does not rewrite focus',
      () async {
    final manager = ClientManager();
    addTearDown(manager.close);

    final firstClient = _FakeClient('first-client');
    final focusedClient = _FakeClient('focused-client');

    manager.addClient(firstClient);
    manager.addClient(focusedClient);
    await preferences.filterClient.set(focusedClient.identifier);

    final controller = SettingsAccountController(clientManager: manager);
    addTearDown(controller.dispose);

    expect(controller.selectedClient, same(focusedClient));

    controller.selectClient(firstClient);

    expect(controller.selectedClient, same(firstClient));
    expect(preferences.filterClient.value, focusedClient.identifier);
  });
}

class _FakeClient implements Client {
  _FakeClient(this.identifier)
      : self = _FakeProfile(
          identifier: '@$identifier:example.org',
          displayName: identifier,
        );

  final _onSync = StreamController<void>.broadcast();
  final _onSelfUpdated = StreamController<void>.broadcast();
  final _onRoomAdded = StreamController<int>.broadcast();
  final _onRoomRemoved = StreamController<int>.broadcast();
  final _onSpaceAdded = StreamController<int>.broadcast();
  final _onSpaceRemoved = StreamController<int>.broadcast();

  @override
  final String identifier;

  @override
  Profile? self;

  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
      connectionStatusChanged = StoredStreamController(
    ClientConnectionStatusUpdate(ClientConnectionStatus.connected),
  );

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
  const _FakeProfile({
    required this.identifier,
    required this.displayName,
  });

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => identifier;

  @override
  String? get detail => identifier;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => '';
}
