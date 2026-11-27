import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/forward_message/forward_destination_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner design pass, 2026-09-05: the forward picker should work like the
/// mobile share picker - room icons, search, and a submit button that is
/// always visible.
///
/// The last of those is the one a test can hold onto. The dialog this replaced
/// laid the room list and the submit button out as siblings inside ONE
/// scrolling column, so the button's position depended on how many rooms the
/// account had. On a small account it looked fine; past a screenful it was
/// below the fold with nothing on screen to say it existed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject(List<ForwardDestination> destinations, {int maximum = 10}) {
    return MaterialApp(
      home: ForwardDestinationPage(
        destinations: destinations,
        maximumSelections: maximum,
      ),
    );
  }

  testWidgets('the action bar stays on screen with a long room list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(subject(_destinations(60)));
    await tester.pump();

    final button = find.widgetWithText(FilledButton, 'Forward');
    expect(button, findsOneWidget);

    final rect = tester.getRect(button);
    expect(
      rect.bottom,
      lessThanOrEqualTo(800),
      reason:
          'the Forward button is below the fold - the list and the action bar '
          'are sharing one scrollable again',
    );
    expect(
      rect.top,
      greaterThanOrEqualTo(0),
      reason: 'the Forward button scrolled off the top',
    );
  });

  testWidgets('the same layout holds with only one room', (tester) async {
    // The old layout looked correct at this size, which is why the defect
    // survived: a short list happens to leave the button on screen. Pinning it
    // has to work at BOTH ends, or this test passes against the old code.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(subject(_destinations(1)));
    await tester.pump();

    final rect = tester.getRect(find.widgetWithText(FilledButton, 'Forward'));
    expect(rect.bottom, lessThanOrEqualTo(800));
    expect(
      rect.bottom,
      greaterThan(600),
      reason:
          'the action bar is pinned to the bottom, so a single-room list must '
          'not pull it up under the first row',
    );
  });

  testWidgets('nothing selected means nothing to submit', (tester) async {
    await tester.pumpWidget(subject(_destinations(3)));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Forward'))
          .onPressed,
      isNull,
    );
    expect(find.text('Choose up to 10 conversations'), findsOneWidget);
  });

  testWidgets('the count and limit are shown as rooms are chosen', (
    tester,
  ) async {
    await tester.pumpWidget(subject(_destinations(3)));
    await tester.pump();

    await tester.tap(find.text('Room 0'));
    await tester.pump();

    expect(find.text('1 of 10 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Forward'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('the limit stops the next selection rather than the submit', (
    tester,
  ) async {
    // The dialog this replaces accepted an eleventh room and then refused the
    // whole choice with a snack bar, discarding the other ten.
    await tester.pumpWidget(subject(_destinations(4), maximum: 2));
    await tester.pump();

    await tester.tap(find.text('Room 0'));
    await tester.pump();
    await tester.tap(find.text('Room 1'));
    await tester.pump();

    expect(find.text('2 of 2 selected'), findsOneWidget);

    final third = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Room 2'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(third.enabled, isFalse);

    final chosen = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Room 0'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(
      chosen.enabled,
      isTrue,
      reason: 'a chosen room must stay tappable so it can be UNchosen',
    );
  });

  testWidgets('search narrows the list', (tester) async {
    await tester.pumpWidget(subject(_destinations(12)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Room 7');
    await tester.pump();

    // Matched against the rows, not find.text: the search field's own content
    // is a Text too, so a bare text finder counts the query itself.
    expect(find.widgetWithText(CheckboxListTile, 'Room 7'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Room 6'), findsNothing);
  });

  testWidgets('a selection made before searching survives the filter', (
    tester,
  ) async {
    // Selection is keyed by room id, not by the visible list, so filtering
    // must not quietly drop a room the user already picked.
    await tester.pumpWidget(subject(_destinations(12)));
    await tester.pump();

    await tester.tap(find.text('Room 0'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Room 7');
    await tester.pump();

    expect(find.text('1 of 10 selected'), findsOneWidget);
  });

  testWidgets('each row is identified by its own conversation', (tester) async {
    await tester.pumpWidget(subject(_destinations(2)));
    await tester.pump();

    expect(find.text('Room 0'), findsOneWidget);
    expect(find.text('Group conversation'), findsNWidgets(2));
  });
}

List<ForwardDestination> _destinations(int count) => [
  for (var i = 0; i < count; i++)
    ForwardDestination(room: _FakeRoom('Room $i', i), isDirect: false),
];

class _FakeRoom implements Room {
  _FakeRoom(this.displayName, this.index);

  final int index;

  @override
  final String displayName;

  @override
  String get identifier => '!room-$index:example.org';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
