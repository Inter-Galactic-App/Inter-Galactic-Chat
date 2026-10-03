// The room-version section was DELIBERATELY read-only, and this file used to
// pin that. The gate has now been satisfied, so it pins the replacement.
//
// `d1f24ece` removed the upgrade action, the version picker and the
// capabilities fetch, because Matrix cannot change a room in place: an upgrade
// tombstones this room and creates a successor carrying neither members nor
// history. The old file said, in as many words, that if it ever failed "the
// question is whether a safe migration exists yet, not whether the test is
// stale". It exists: `feature/safe-room-migration` adds the member snapshot,
// the successor invite pass, resumable recovery and both timeline links, and
// row "FEATURES Safe Matrix Room Migration Flow" is the queue item DESIGN
// pointed at.
//
// So the control is back, and the guard moves with it rather than coming off.
// What must hold now is not "no button" but that the button cannot be the
// destructive one it replaced: it is admin-gated, it says what migration does
// and does not carry, and a room that has ALREADY been tombstoned offers
// recovery instead of a second upgrade. That last one is the data-safety
// property - a second upgrade would create a second successor and strand the
// members invited to the first.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/room/admin/room_admin_room_classification_settings.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite/generated/model.dart' as matrix_api;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    _FakeAdminSdkClient.capabilityRequests = 0;
    _FakeAdminSdkClient.capabilityResponse = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    String version = '10',
    bool developerMode = true,
    bool canTombstone = true,
    bool canInvite = true,
    bool settle = true,
    String? successorRoomId,
    String? predecessorRoomId,
  }) async {
    await globals.preferences.developerMode.set(developerMode);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomAdminRoomClassificationSettings(
              room: _FakeAdminRoom(
                version: version,
                canTombstone: canTombstone,
                canInvite: canInvite,
                successorRoomId: successorRoomId,
                predecessorRoomId: predecessorRoomId,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('the current room version is still shown', (tester) async {
    await pump(tester, version: '10');

    expect(find.text('Current Matrix room version'), findsOneWidget);
    // The chip and the version picker both legitimately read "Room v10" when
    // the room is already on the newest stable version.
    expect(find.text('Room v10'), findsWidgets);
  });

  testWidgets('migration controls are hidden outside developer mode', (
    tester,
  ) async {
    await pump(
      tester,
      version: '9',
      successorRoomId: '!successor:example.org',
      developerMode: false,
    );

    expect(find.text('Current Matrix room version'), findsOneWidget);
    expect(find.text('Migrate to a new room version'), findsNothing);
    expect(find.text('Room migration recovery'), findsNothing);
    expect(find.widgetWithText(tiamat.Button, 'Start migration'), findsNothing);
    expect(find.widgetWithText(tiamat.Button, 'Recover members'), findsNothing);
    expect(_FakeAdminSdkClient.capabilityRequests, 0);
  });

  testWidgets('enabling developer mode loads versions while mounted', (
    tester,
  ) async {
    await pump(tester, version: '9', developerMode: false);
    expect(_FakeAdminSdkClient.capabilityRequests, 0);

    await globals.preferences.developerMode.set(true);
    await tester.pumpAndSettle();

    expect(_FakeAdminSdkClient.capabilityRequests, 1);
    expect(
      find.widgetWithText(tiamat.Button, 'Start migration'),
      findsOneWidget,
    );
  });

  testWidgets('changing rooms defers capability loading until after rebuild', (
    tester,
  ) async {
    await pump(tester, version: '9');
    expect(_FakeAdminSdkClient.capabilityRequests, 1);
    final beforeRoomChange = _FakeAdminSdkClient.capabilityRequests;

    await pump(tester, version: '10');
    expect(tester.takeException(), isNull);
    expect(
      _FakeAdminSdkClient.capabilityRequests,
      greaterThan(beforeRoomChange),
    );
  });

  testWidgets('disabled in-flight response cannot restore stale versions', (
    tester,
  ) async {
    final pending = Completer<matrix_api.Capabilities>();
    _FakeAdminSdkClient.capabilityResponse = () => pending.future;
    await pump(tester, version: '9', developerMode: true, settle: false);
    expect(_FakeAdminSdkClient.capabilityRequests, 1);

    await globals.preferences.developerMode.set(false);
    await tester.pump();
    _FakeAdminSdkClient.capabilityResponse = null;
    pending.complete(_FakeAdminSdkClient.stableCapabilities);
    await tester.pump();
    expect(find.widgetWithText(tiamat.Button, 'Start migration'), findsNothing);

    await globals.preferences.developerMode.set(true);
    await tester.pumpAndSettle();
    expect(_FakeAdminSdkClient.capabilityRequests, 2);
    expect(
      find.widgetWithText(tiamat.Button, 'Start migration'),
      findsOneWidget,
    );
  });

  // The consequence copy is the part that must not quietly disappear. A user
  // agreeing to a migration has to know history stays behind and members are
  // re-invited rather than moved, because neither is recoverable afterwards.
  testWidgets('the migration control states what it does not carry', (
    tester,
  ) async {
    // v9 with v10 stable available, so a migration is actually on offer.
    await pump(tester, version: '9');

    expect(
      find.widgetWithText(tiamat.Button, 'Start migration'),
      findsOneWidget,
    );
    final button = tester.widget<tiamat.Button>(
      find.widgetWithText(tiamat.Button, 'Start migration'),
    );
    expect(button.onTap, isNotNull);
    expect(
      find.textContaining('History remains in this room'),
      findsOneWidget,
      reason: 'the user must be told history does not move to the successor',
    );
    expect(
      find.textContaining('invites the current members'),
      findsOneWidget,
      reason:
          'members are re-invited, not transferred - the protocol moves neither',
    );
  });

  testWidgets('migration is admin-gated', (tester) async {
    await pump(tester, version: '9', canTombstone: false);

    expect(
      find.textContaining('Only room admins can migrate'),
      findsOneWidget,
      reason: 'a non-admin must be told why, not shown a dead control',
    );
    final button = tester.widget<tiamat.Button>(
      find.widgetWithText(tiamat.Button, 'Start migration'),
    );
    expect(
      button.onTap,
      isNull,
      reason: 'a non-admin must not be able to start a migration',
    );
  });

  // The anti-double-upgrade guard. An already-tombstoned room must offer the
  // resumable invite pass and NOT a second upgrade: upgrading again would
  // create a second successor and strand everyone invited to the first.
  testWidgets(
    'an already-migrated room offers recovery, not a second upgrade',
    (tester) async {
      await pump(tester, successorRoomId: '!successor:example.org');

      expect(find.text('Room migration recovery'), findsOneWidget);
      expect(
        find.widgetWithText(tiamat.Button, 'Start migration'),
        findsNothing,
        reason:
            'a second upgrade on a tombstoned room creates a second successor',
      );
      expect(
        find.widgetWithText(tiamat.Button, 'Open successor'),
        findsOneWidget,
      );
      final recovery = tester.widget<tiamat.Button>(
        find.widgetWithText(tiamat.Button, 'Recover members'),
      );
      expect(recovery.onTap, isNotNull);
    },
  );

  testWidgets('recovery needs invite permission', (tester) async {
    await pump(
      tester,
      successorRoomId: '!successor:example.org',
      canInvite: false,
    );

    final button = tester.widget<tiamat.Button>(
      find.widgetWithText(tiamat.Button, 'Recover members'),
    );
    expect(button.onTap, isNull);
  });

  // The other half of the bidirectional link: a successor room shows the way
  // back to the timeline that stayed behind.
  testWidgets('a successor room links back to its predecessor history', (
    tester,
  ) async {
    await pump(tester, predecessorRoomId: '!older:example.org');

    expect(find.text('Previous room history'), findsOneWidget);
    expect(find.widgetWithText(tiamat.Button, 'Open history'), findsOneWidget);
  });

  testWidgets('a room with no predecessor shows no history link', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Previous room history'), findsNothing);
  });
}

class _FakeAdminRoom implements MatrixRoom {
  _FakeAdminRoom({
    required this.version,
    required this.canTombstone,
    required this.canInvite,
    this.successorRoomId,
    this.predecessorRoomId,
  });

  final String version;
  final bool canTombstone;
  final bool canInvite;
  final String? successorRoomId;
  final String? predecessorRoomId;

  @override
  Client get client => _FakeAdminClient();

  @override
  matrix.Room get matrixRoom => _FakeAdminSdkRoom(
    version: version,
    canTombstone: canTombstone,
    successorRoomId: successorRoomId,
    predecessorRoomId: predecessorRoomId,
  );

  @override
  Permissions get permissions => _FakeAdminPermissions(canInvite: canInvite);

  @override
  String get identifier => '!source:example.org';

  @override
  List<String> get memberIds => const ['@me:test', '@friend:test'];

  @override
  bool get isMembersListComplete => true;

  @override
  bool get isSpecialRoomType => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminPermissions implements Permissions {
  _FakeAdminPermissions({required this.canInvite});

  final bool canInvite;

  @override
  bool get canInviteUser => canInvite;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminClient implements Client {
  @override
  Profile? get self => _FakeAdminProfile();

  @override
  String get identifier => 'fake-account';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminProfile implements Profile {
  @override
  String get identifier => '@me:test';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminSdkRoom implements matrix.Room {
  _FakeAdminSdkRoom({
    required this.version,
    required this.canTombstone,
    this.successorRoomId,
    this.predecessorRoomId,
  });

  final String version;
  final bool canTombstone;
  final String? successorRoomId;
  final String? predecessorRoomId;

  @override
  String? get roomVersion => version;

  @override
  String get id => '!source:example.org';

  @override
  matrix.Client get client => _FakeAdminSdkClient();

  @override
  bool canChangeStateEvent(String action) => canTombstone;

  // `extinctInformations` is a concrete getter on matrix.Room, so `implements`
  // plus noSuchMethod does not inherit it - it has to be spelled out here.
  @override
  matrix.TombstoneContent? get extinctInformations => successorRoomId == null
      ? null
      : matrix.TombstoneContent.fromJson({
          'body': 'This room has been replaced',
          'replacement_room': successorRoomId!,
        });

  @override
  matrix.Event? getState(String type, [String stateKey = '']) {
    if (type == matrix.EventTypes.RoomCreate) {
      return _stateEvent(type, {
        if (predecessorRoomId != null)
          'predecessor': {
            'room_id': predecessorRoomId!,
            'event_id': r'$tombstone:example.org',
          },
      });
    }
    return null;
  }

  matrix.Event _stateEvent(String type, Map<String, Object?> content) =>
      matrix.Event(
        type: type,
        content: content,
        senderId: '@me:test',
        eventId: '\$state-$type',
        originServerTs: DateTime.utc(2026),
        room: this,
        stateKey: '',
      );

  @override
  matrix.RoomSummary get summary => matrix.RoomSummary.fromJson(const {
    'm.joined_member_count': 2,
    'm.invited_member_count': 0,
    'm.heroes': <String>[],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminSdkClient implements matrix.Client {
  static int capabilityRequests = 0;
  static Future<matrix_api.Capabilities> Function()? capabilityResponse;
  static final stableCapabilities = matrix_api.Capabilities.fromJson(const {
    'm.room_versions': {
      'default': '10',
      'available': {'9': 'stable', '10': 'stable', '11': 'unstable'},
    },
  });

  @override
  Future<matrix_api.Capabilities> getCapabilities() async {
    capabilityRequests++;
    return capabilityResponse?.call() ?? stableCapabilities;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Unused here but kept explicit: the classification section reads the direct
// message components through getComponent, which returns null above, so the
// conversation-type half degrades to "no partner, no conversion" rather than
// throwing. That is the path this file does NOT cover.
// ignore: unused_element
typedef _Unused = DirectMessagesComponent;
