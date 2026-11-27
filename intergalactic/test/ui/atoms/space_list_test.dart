import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:intergalactic/client/space_child.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/space_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  testWidgets(
      'knock preview join shows knock feedback instead of selecting room',
      (tester) async {
    final client = _FakeClient();
    final space = _FakeSpace(client);
    final preview = GenericRoomPreview(
      '!knock:example.org',
      displayName: 'Knock Room',
      type: RoomType.defaultRoom,
      visibility: RoomVisibilityKnock(),
    );
    Room? selectedRoom;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpaceList(
            space,
            onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
              selectedRoom = room;
            },
          ),
        ),
      ),
    );

    unawaited(
      (tester.state(find.byType(SpaceList)) as dynamic)
          .joinRoomWithConfirmation(preview) as Future<void>,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(client.joinPreviewCount, 1);
    expect(selectedRoom, isNull);
    expect(find.text('Knock sent. An admin can approve your access.'),
        findsOneWidget);
  });
}

class _FakeClient implements Client {
  int joinPreviewCount = 0;

  @override
  String get identifier => 'fake-client';

  @override
  bool get supportsE2EE => true;

  @override
  Future<RoomPreviewJoinResult> joinRoomFromPreview(RoomPreview preview) async {
    joinPreviewCount++;
    return const RoomPreviewJoinResult.knockRequested();
  }

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpace implements Space {
  _FakeSpace(this.client);

  @override
  final Client client;

  @override
  String get identifier => '!space:example.org';

  @override
  String get displayName => 'Space';

  @override
  Permissions get permissions => _FakePermissions();

  @override
  List<Room> get rooms => const [];

  @override
  List<Space> get subspaces => const [];

  @override
  List<SpaceChild> get children => const [];

  @override
  List<RoomPreview> get childPreviews => const [];

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Stream<int> get onChildRoomPreviewAdded => const Stream<int>.empty();

  @override
  Stream<void> get onChildRoomPreviewsUpdated => const Stream<void>.empty();

  @override
  Stream<int> get onChildRoomPreviewRemoved => const Stream<int>.empty();

  @override
  Stream<int> get onChildSpaceAdded => const Stream<int>.empty();

  @override
  Stream<int> get onChildSpaceRemoved => const Stream<int>.empty();

  @override
  Stream<int> get onRoomAdded => const Stream<int>.empty();

  @override
  Stream<int> get onRoomRemoved => const Stream<int>.empty();

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  T? getComponent<T extends SpaceComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}
