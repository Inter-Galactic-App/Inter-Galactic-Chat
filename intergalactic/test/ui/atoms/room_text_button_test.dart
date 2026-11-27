import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.dmLockController.init(globals.preferences);
  });

  testWidgets('ignores late call participant updates after disposal', (
    tester,
  ) async {
    final previousOnError = FlutterError.onError;
    final flutterErrors = <FlutterErrorDetails>[];
    FlutterError.onError = flutterErrors.add;
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    final client = _FakeClient();
    final room = _FakeRoom(client: client);
    final voipRoom = _FakeVoipRoomComponent(client: client, room: room);
    room.voipRoom = voipRoom;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RoomTextButton(room))),
    );

    voipRoom.participants = ['@alice:example.org'];
    voipRoom.emitParticipantsChanged();
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);

    voipRoom.participants = ['@bob:example.org'];
    voipRoom.emitParticipantsChanged();
    room.emitUpdate();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    voipRoom.emitParticipantsChanged();
    room.emitUpdate();
    await tester.pump();

    expect(flutterErrors, isEmpty);
  });
}

class _FakeVoipRoomComponent
    implements VoipRoomComponent<_FakeClient, _FakeRoom> {
  _FakeVoipRoomComponent({required this.client, required this.room});

  @override
  final _FakeClient client;

  @override
  final _FakeRoom room;

  List<String> participants = const [];
  final StreamController<void> _participantsChanged =
      StreamController<void>.broadcast();

  void emitParticipantsChanged() {
    _participantsChanged.add(null);
  }

  @override
  List<String> getCurrentParticipants() => List<String>.of(participants);

  @override
  Stream<void> get onParticipantsChanged => _participantsChanged.stream;

  @override
  VoipSession? get currentSession => null;

  @override
  bool get canJoinCall => true;

  @override
  Future<void> clearAllCallMembershipStatus() async {}

  @override
  Future<String?> getCallServerUrl() async => null;

  @override
  Future<VoipSession?> joinCall() async => null;
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final _FakeClient client;

  _FakeVoipRoomComponent? voipRoom;
  final StreamController<void> _updates = StreamController<void>.broadcast();

  void emitUpdate() {
    _updates.add(null);
  }

  @override
  String get identifier => '!voice:example.org';

  @override
  String get displayName => 'Test Voice';

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  String get favoriteStorageId => localId;

  @override
  ImageProvider? get avatar => null;

  @override
  String? get avatarId => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  Stream<void> get onUpdate => _updates.stream;

  @override
  PushRule get pushRule => PushRule.notify;

  @override
  int get notificationCount => 0;

  @override
  int get highlightedNotificationCount => 0;

  @override
  int get displayNotificationCount => 0;

  @override
  int get displayHighlightedNotificationCount => 0;

  @override
  bool get displayRoomWideMentionNotification => false;

  @override
  bool get isE2EE => false;

  @override
  bool get isSpecialRoomType => false;

  @override
  bool get shouldPreviewMedia => false;

  @override
  IconData get icon => Icons.volume_up;

  @override
  T? getComponent<T extends RoomComponent>() {
    final component = voipRoom;
    if (component != null && component is T) {
      return component as T;
    }
    return null;
  }

  @override
  Member getMemberOrFallback(String id) {
    return _FakeMember(
      identifier: id,
      displayName: id == '@alice:example.org' ? 'Alice' : 'Bob',
    );
  }

  @override
  Future<Member> fetchMember(String id) async => getMemberOrFallback(id);

  @override
  Future<void> markAsRead() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  String get identifier => 'client-a';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  const _FakeMember({required this.identifier, required this.displayName});

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => displayName;

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;
}
