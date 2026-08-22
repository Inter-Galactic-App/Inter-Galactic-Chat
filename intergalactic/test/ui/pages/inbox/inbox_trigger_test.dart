import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/inbox/inbox_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  Widget host(ClientManager manager, {double? iconSize, double size = 50}) =>
      MaterialApp(
        home: Scaffold(
          body: InboxTrigger(
            clientManager: manager,
            size: size,
            iconSize: iconSize,
            onPressed: () {},
          ),
        ),
      );

  testWidgets('sizes its glyph from size / 4 when no icon size is given', (
    tester,
  ) async {
    final manager = ClientManager();
    addTearDown(manager.close);

    await tester.pumpWidget(host(manager, size: 50));
    await tester.pump();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size,
      12.5,
      reason: 'the full rail depends on the size / 4 default',
    );
  });

  testWidgets('honours an explicit icon size so compact rails can match', (
    tester,
  ) async {
    // The compact desktop rail is 38px buttons with 15px glyphs. Without this
    // override the default would draw 9.5px there - visibly smaller than every
    // button beside it - which is why the trigger could not simply be dropped
    // into that rail at its default ratio.
    final manager = ClientManager();
    addTearDown(manager.close);

    await tester.pumpWidget(host(manager, size: 38, iconSize: 15));
    await tester.pump();

    expect(tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size, 15.0);
    expect(tester.getSize(find.byType(InboxTrigger)), const Size(38, 38));
  });

  testWidgets('announces itself as a button with its unread count', (
    tester,
  ) async {
    // Disposed in a finally, not addTearDown: flutter_test verifies semantics
    // handles at the END OF THE TEST BODY, before teardowns run, so
    // addTearDown(semantics.dispose) is too late and fails the test outright.
    // A bare dispose() after the expectations is also wrong - a failing one
    // throws past it and leaves the handle open.
    final semantics = tester.ensureSemantics();
    try {
      final manager = ClientManager();
      addTearDown(manager.close);

      await tester.pumpWidget(host(manager));
      await tester.pump();

      expect(
        find.bySemanticsLabel('Inbox, No unread Inbox conversations'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
