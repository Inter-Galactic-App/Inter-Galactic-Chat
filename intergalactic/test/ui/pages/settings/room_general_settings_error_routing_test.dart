// A rejected room-profile write has to reach the user, not the zone.
//
// `RoomAppearanceSettingsView` declares `onImagePicked` and `onNameChanged` as
// VOID callbacks and drops what they return. So an awaited future has nowhere
// to go: a homeserver rejection - permission revoked between the permission
// read and the tap, a rate limit, a transport error - completes a future with
// no listener, which becomes an unhandled zone error. The dialog closes,
// nothing changes, and the user is told nothing. `RoomGeneralSettingsPage`
// routes both through `ErrorUtils.tryRun` for that reason.
//
// WHAT WOULD MAKE THESE WRONG, stated first: asserting only that the room
// method was called would pass against the unrouted version, because the
// unrouted version calls it too - the difference is entirely in what happens
// to the failure afterwards. So the load-bearing assertion is
// `tester.takeException()` returning null, and the dialog is checked second
// to pin that the error was HANDLED (reported to the user) rather than merely
// swallowed by a bare catch.
//
// WHY THE CALLBACKS ARE INVOKED DIRECTLY rather than through the picker and
// the editable label: the void-ness of these two callbacks IS the defect's
// cause, so the callback boundary is the seam under test. Driving
// `ImagePickerButton` would mean standing up the platform file picker, which
// would be testing the picker.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fixed `toString`, because it is what the error dialog renders and what
/// the assertion below looks for.
class _HomeserverRejected implements Exception {
  @override
  String toString() => 'the homeserver rejected this write';
}

void main() {
  late _FakeRoom room;

  setUp(() async {
    // `AdaptiveDialog.show` asks `Layout.desktop`, which reads preferences.
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    room = _FakeRoom();
  });

  tearDown(() async {
    await room.dispose();
  });

  Future<RoomAppearanceSettingsView> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomGeneralSettingsPage(room: room),
          ),
        ),
      ),
    );
    return tester.widget<RoomAppearanceSettingsView>(
      find.byType(RoomAppearanceSettingsView),
    );
  }

  testWidgets('a rejected avatar write is shown, not thrown into the zone', (
    tester,
  ) async {
    final view = await pumpPage(tester);

    view.onImagePicked!(Uint8List.fromList(const <int>[1, 2, 3]), 'image/png');
    await tester.pumpAndSettle();

    expect(
      room.avatarCalls,
      1,
      reason: 'the page must still perform the write it is routing',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'a void callback drops the future, so an unrouted failure lands in '
          'the zone with no listener; this is the whole fix',
    );
    expect(
      find.text('the homeserver rejected this write'),
      findsOneWidget,
      reason: 'handled has to mean the user is told, not silently caught',
    );
  });

  testWidgets('a rejected name write is shown, not thrown into the zone', (
    tester,
  ) async {
    final view = await pumpPage(tester);

    view.onNameChanged!('New Room Name');
    await tester.pumpAndSettle();

    expect(room.nameCalls, <String>['New Room Name']);
    expect(tester.takeException(), isNull);
    expect(find.text('the homeserver rejected this write'), findsOneWidget);
  });

  testWidgets('a write that succeeds raises no dialog', (tester) async {
    // The control. Without it, a page that popped an error dialog on EVERY
    // write would pass both tests above.
    room.rejectWrites = false;
    final view = await pumpPage(tester);

    view.onNameChanged!('New Room Name');
    await tester.pumpAndSettle();

    expect(room.nameCalls, <String>['New Room Name']);
    expect(tester.takeException(), isNull);
    expect(find.text('the homeserver rejected this write'), findsNothing);
  });
}

/// Enough of a `Room` for this page to build. Deliberately not a `MatrixRoom`,
/// so the Addresses section - which is irrelevant here and needs a live SDK
/// room - is not built.
class _FakeRoom implements Room {
  final StreamController<void> _updates = StreamController<void>.broadcast();

  bool rejectWrites = true;
  int avatarCalls = 0;
  final List<String> nameCalls = <String>[];

  Future<void> dispose() => _updates.close();

  @override
  Stream<void> get onUpdate => _updates.stream;

  @override
  Client get client => _FakeClient();

  @override
  String get identifier => '!room:example.org';

  @override
  String get displayName => 'Test Room';

  @override
  String? get topic => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => const Color(0xFF336699);

  @override
  Permissions get permissions => _FakePermissions();

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {
    avatarCalls += 1;
    if (rejectWrites) {
      throw _HomeserverRejected();
    }
  }

  @override
  Future<void> setDisplayName(String newName) async {
    nameCalls.add(newName);
    if (rejectWrites) {
      throw _HomeserverRejected();
    }
  }

  @override
  Future<void> setTopic(String topic) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The appearance view only consults the client when rendering markdown in a
/// topic, which this room does not have.
class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Both editors are enabled, so the widgets that own these callbacks in
/// production are the ones built here.
class _FakePermissions extends Permissions {
  @override
  bool get canEditName => true;

  @override
  bool get canEditAvatar => true;

  @override
  bool get canEditTopic => false;
}
