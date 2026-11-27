import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// BUG-335. Three surfaces on the unjoined call view made claims about
/// encryption that the code contradicts, and NOTHING TESTED ANY OF THEM - the
/// first grep for a test naming `VoipRoomView`, `e2eeUnsupportedView` or those
/// strings returned nothing at all. That is how all three survived from the
/// 2026-04-20 upstream sync until an owner hit one of them.
///
/// What the code actually does, which is what makes the old claims false: this
/// app configures no call-media E2EE on any path. No `e2eeOptions` reaches
/// `lk.Room` (matrix_livekit_room_factory_io.dart), and
/// `matrix_voip_component.dart:291` declines the Matrix SDK's group-call key
/// hook outright with `throw UnimplementedError()`. `room.isE2EE` is the room's
/// TIMELINE encryption and says nothing about call media.
///
/// THE FIRST CASE IS THE OWNER'S BUG and it is the one worth keeping forever:
/// a RELEASE build used to swap the whole join view for "Sorry, End-to-end
/// encrypted voice rooms are not yet supported" when the room was encrypted, so
/// there was no Join control at all. It was reported as a mobile LAYOUT problem
/// - the button pushed off-screen - and it was not: it was a deliberate
/// `BuildConfig.RELEASE` block a hundred lines above the button, which is why
/// the owner's phone and desktop showed different text for the same room.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  Future<void> pumpUnjoined(WidgetTester tester, {required bool encrypted}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: AccessibilityScope(
          preferences: globals.preferences,
          child: Scaffold(
            body: VoipRoomView(_FakeVoipRoomComponent(encrypted: encrypted)),
          ),
        ),
      ),
    );
  }

  testWidgets('an encrypted room still offers the Join control', (
    tester,
  ) async {
    await pumpUnjoined(tester, encrypted: true);
    await tester.pump();

    expect(
      find.text(CommonStrings.promptJoin),
      findsOneWidget,
      reason:
          'THE BUG: encryption on the ROOM must not remove the ability to join '
          'the call. Nothing about call media changes when the timeline is '
          'encrypted, so there is nothing for a block to protect anyone from.',
    );
    expect(
      find.textContaining('not yet supported'),
      findsNothing,
      reason:
          'the release-only e2eeUnsupportedView that replaced the join view is '
          'gone; if it returns, this is the assertion that says so',
    );
  });

  testWidgets('an unencrypted room still offers the Join control', (
    tester,
  ) async {
    // The control case. Without it, a fix that broke joining for EVERY room
    // would leave the case above green and look like a pass.
    await pumpUnjoined(tester, encrypted: false);
    await tester.pump();

    expect(find.text(CommonStrings.promptJoin), findsOneWidget);
  });

  testWidgets('no surface claims the call itself is secure or encrypted', (
    tester,
  ) async {
    // The strongest of the three old claims was a tooltip reading "This room is
    // encrypted, your call is secure and private". Asserted as a ban on the
    // claim rather than a match on today's wording, so rephrasing the honest
    // text does not require touching this test, while reintroducing the false
    // one does.
    for (final encrypted in [true, false]) {
      await pumpUnjoined(tester, encrypted: encrypted);
      await tester.pump();

      // tiamat.Tooltip, NOT Material's. The first version of this scanned
      // `find.byType(Tooltip)`, which matched Material's - a widget that is not
      // in this tree at all - so the bans below ran over an EMPTY string and a
      // mutation restoring the false tooltip SURVIVED them. A ban that searches
      // the wrong widget reads exactly like a ban nothing violates, which is
      // why the arming assertion is here and not optional.
      final tooltips = tester
          .widgetList<tiamat.Tooltip>(find.byType(tiamat.Tooltip))
          .map((t) => t.text)
          .join('\n');
      expect(
        tooltips,
        isNotEmpty,
        reason:
            'ARMING: this surface carries a padlock tooltip. If nothing is '
            'found the bans below are vacuous and prove nothing.',
      );
      final combined = '$tooltips\n${_visibleText(tester)}'.toLowerCase();

      expect(
        combined,
        isNot(contains('your call is secure')),
        reason: 'encrypted=$encrypted: calls are not end-to-end encrypted',
      );
      expect(
        combined,
        isNot(contains('encrypted calls are still under development')),
        reason:
            'encrypted=$encrypted: this asserts the calls ARE end-to-end '
            'encrypted and merely immature, which overstates security in the '
            'most dangerous direction',
      );
    }
  });
}

String _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

class _FakeVoipRoomComponent implements VoipRoomComponent<Client, Room> {
  _FakeVoipRoomComponent({required bool encrypted})
    : room = _FakeRoom(isE2EE: encrypted);

  @override
  final Room room;

  @override
  bool get canJoinCall => true;

  @override
  VoipSession? get currentSession => null;

  @override
  List<String> getCurrentParticipants() => const [];

  @override
  Stream<void> get onParticipantsChanged => const Stream<void>.empty();

  // Deliberately never completes: the view resolves this in initState and the
  // shimmer placeholder stands in until it does, which is the state an unjoined
  // room is in when it is first opened.
  @override
  Future<String?> getCallServerUrl() => Completer<String?>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoom implements Room {
  _FakeRoom({required this.isE2EE});

  @override
  final bool isE2EE;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
