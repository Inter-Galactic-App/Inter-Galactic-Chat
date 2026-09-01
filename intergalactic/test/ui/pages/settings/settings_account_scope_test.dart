import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notification_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/soundboard_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../client/components/soundboard/soundboard_pack_test_fakes.dart';

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

  test(
    'settings account controller selection does not rewrite focus',
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
    },
  );

  test(
    'settings account controller follows newly added focused account',
    () async {
      final manager = ClientManager();
      addTearDown(manager.close);

      final firstClient = _FakeClient('first-client');
      final secondClient = _FakeClient('second-client');

      manager.addClient(firstClient);

      final controller = SettingsAccountController(clientManager: manager);
      addTearDown(controller.dispose);

      expect(controller.selectedClient, same(firstClient));

      await preferences.filterClient.set(secondClient.identifier);
      manager.addClient(secondClient);
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedClient, same(secondClient));
    },
  );

  testWidgets('context account scope pins the header to the acting account', (
    tester,
  ) async {
    final actingClient = _FakeClient('account-a');
    final focusedClient = _FakeClient('account-b');
    addTearDown(actingClient.close);
    addTearDown(focusedClient.close);
    await preferences.filterClient.set(focusedClient.identifier);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsContextAccountScope(
          client: actingClient,
          child: const Scaffold(body: SettingsAccountHeader()),
        ),
      ),
    );

    expect(find.text('account-a'), findsOneWidget);
    expect(find.text('account-b'), findsNothing);
    expect(find.byTooltip('Choose settings account'), findsNothing);
  });

  test('soundboard summaries include only the selected account spaces', () {
    final manager = ClientManager();
    addTearDown(manager.close);
    final firstClient = _FakeClient('account-a');
    final selectedClient = _FakeClient('account-b');
    final firstComponent = FakePackSoundboardComponent();
    final selectedComponent = FakePackSoundboardComponent();
    final firstSpace = _FakeSpace(
      client: firstClient,
      identifier: '!shared:example.org',
      soundboard: firstComponent,
    );
    final selectedSpace = _FakeSpace(
      client: selectedClient,
      identifier: '!shared:example.org',
      soundboard: selectedComponent,
    );
    firstClient.spaces.add(firstSpace);
    selectedClient.spaces.add(selectedSpace);
    manager.addClient(firstClient);
    manager.addClient(selectedClient);

    final summaries = collectVisibleSoundboards(
      manager,
      client: selectedClient,
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.space, same(selectedSpace));
  });

  test('soundboard summaries distinguish derived legacy pack captions', () {
    final manager = ClientManager();
    addTearDown(manager.close);
    final client = _FakeClient('account-a');
    final component = FakePackSoundboardComponent();
    component.sounds2.add(
      fakeSound(
        'other-legacy',
        name: 'Other legacy sound',
        uploadedBy: fakeOtherUser,
      ),
    );
    final space = _FakeSpace(
      client: client,
      identifier: '!space:example.org',
      soundboard: component,
    );
    client.spaces.add(space);
    manager.addClient(client);

    final summaries = collectVisibleSoundboards(manager, client: client);

    // `containsAll` would also pass if an unnumbered 'Legacy sounds' caption
    // survived alongside the two numbered ones, which is the exact regression
    // this test exists to reject. Filter to the legacy captions and require
    // those two and nothing else.
    final legacyNames = summaries.single.packs
        .map((pack) => pack.displayName)
        .where((name) => name.startsWith('Legacy sounds'));
    expect(
      legacyNames,
      unorderedEquals(['Legacy sounds 1', 'Legacy sounds 2']),
    );
  });

  test('notification overrides include only the selected account rooms', () {
    final manager = ClientManager();
    addTearDown(manager.close);
    final firstClient = _FakeClient('account-a');
    final selectedClient = _FakeClient('account-b');
    final firstRoom = _FakeRoom(
      client: firstClient,
      identifier: '!shared:example.org',
      pushRule: PushRule.mentionsOnly,
    );
    final selectedRoom = _FakeRoom(
      client: selectedClient,
      identifier: '!shared:example.org',
      pushRule: PushRule.dontNotify,
    );
    firstClient.rooms.add(firstRoom);
    selectedClient.rooms.add(selectedRoom);
    manager.addClient(firstClient);
    manager.addClient(selectedClient);

    final summaries = collectNotificationOverrides(
      manager,
      client: selectedClient,
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.room, same(selectedRoom));
    expect(summaries.single.pushRule, PushRule.dontNotify);
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
  final List<Room> rooms = [];

  @override
  final List<Space> spaces = [];

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
  const _FakeProfile({required this.identifier, required this.displayName});

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

class _FakeRoom implements Room {
  const _FakeRoom({
    required this.client,
    required this.identifier,
    required this.pushRule,
  });

  @override
  final Client client;

  @override
  final String identifier;

  @override
  String get displayName => 'Shared Room';

  @override
  final PushRule pushRule;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpace implements Space {
  const _FakeSpace({
    required this.client,
    required this.identifier,
    required this.soundboard,
  });

  @override
  final Client client;

  @override
  final String identifier;

  @override
  String get displayName => 'Shared Space';

  final SoundboardComponent soundboard;

  @override
  PushRule get pushRule => PushRule.notify;

  @override
  T? getComponent<T extends SpaceComponent>() =>
      soundboard is T ? soundboard as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
