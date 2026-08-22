import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/organisms/home_screen/home_screen.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets(
    'home room account avatar overlay refreshes on client profile update',
    (tester) async {
      final clientManager = ClientManager();
      addTearDown(clientManager.close);

      final firstClient = _FakeClient(
        'first-client',
        _FakeProfile(identifier: '@first:example.org', displayName: 'Alpha'),
      );
      final secondClient = _FakeClient(
        'second-client',
        _FakeProfile(identifier: '@second:example.org', displayName: 'Beta'),
      );

      firstClient.roomsInternal.add(_FakeRoom(firstClient));
      secondClient.roomsInternal.add(_FakeRoom(secondClient));
      clientManager.addClient(firstClient);
      clientManager.addClient(secondClient);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(
            useMaterial3: true,
          ).copyWith(extensions: [const ThemeSettings()]),
          home: Scaffold(
            body: SizedBox(
              width: 720,
              child: HomeScreen(clientManager: clientManager),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Z'), findsNothing);

      firstClient.publishSelfUpdated(
        _FakeProfile(identifier: '@first:example.org', displayName: 'Zulu'),
      );
      await tester.pump();

      // Exact, not at-least: only the first client's name changed, so a
      // regression that painted the refreshed initial on extra surfaces would
      // have satisfied findsAtLeastNWidgets(1) unnoticed.
      expect(find.text('Z'), findsNWidgets(2));
    },
  );
}

class _FakeClient implements Client {
  _FakeClient(this.identifier, this.self) {
    directMessages.client = this;
  }

  final _onSync = StreamController<void>.broadcast();
  final _onSelfUpdated = StreamController<void>.broadcast();
  final _onRoomAdded = StreamController<int>.broadcast();
  final _onRoomRemoved = StreamController<int>.broadcast();
  final _onSpaceAdded = StreamController<int>.broadcast();
  final _onSpaceRemoved = StreamController<int>.broadcast();
  final _FakeDirectMessagesComponent directMessages =
      _FakeDirectMessagesComponent();
  final List<Room> roomsInternal = [];

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
  List<Room> get rooms => roomsInternal;

  @override
  List<Space> get spaces => const [];

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
    final component = directMessages;
    if (component is T) {
      return component as T;
    }

    return null;
  }

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
      directMessages.close(),
      ...roomsInternal.whereType<_FakeRoom>().map((room) => room.close()),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom(this.client);

  final _onUpdate = StreamController<void>.broadcast();

  @override
  final Client client;

  @override
  String get identifier => '!shared-room:example.org';

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  String get favoriteStorageId => localId;

  @override
  String get displayName => 'Shared room';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  TimelineEvent? get lastEvent => null;

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  PushRule get pushRule => PushRule.notify;

  @override
  int get notificationCount => 0;

  @override
  int get highlightedNotificationCount => 0;

  @override
  bool get isSpecialRoomType => false;

  Future<void> close() => _onUpdate.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDirectMessagesComponent
    implements DirectMessagesComponent<_FakeClient> {
  final _roomsUpdated = StreamController<void>.broadcast();
  final _highlightedUpdated = StreamController<void>.broadcast();

  @override
  late _FakeClient client;

  @override
  List<Room> get directMessageRooms => const [];

  @override
  List<Room> get highlightedRoomsList => const [];

  @override
  Stream<void> get onRoomsListUpdated => _roomsUpdated.stream;

  @override
  Stream<void> get onHighlightedRoomsListUpdated => _highlightedUpdated.stream;

  @override
  bool isRoomDirectMessage(Room room) => false;

  Future<void> close() async {
    await Future.wait([_roomsUpdated.close(), _highlightedUpdated.close()]);
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
