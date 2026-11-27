import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  testWidgets('defers context menu overlay insertion until after the frame',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const [
            ThemeSettings(),
          ],
        ),
        home: Scaffold(
          body: ContextMenu(
            modal: true,
            items: const [
              ContextMenuItem(text: 'Copy'),
            ],
            child: const Text('Open menu'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));

    expect(tester.takeException(), isNull);
    expect(find.text('Copy'), findsNothing);

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.text('Copy'), findsOneWidget);
  });
}
