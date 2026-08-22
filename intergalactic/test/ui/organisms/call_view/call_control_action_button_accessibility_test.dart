import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_control_action_button.dart';

void main() {
  testWidgets('call control action exposes semantics and keyboard activation',
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CallControlActionButton(
              icon: Icons.fullscreen,
              semanticLabel: 'Open fullscreen',
              persistentLabel: 'Full',
              onPressed: () {
                activations += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Open fullscreen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets(
      'call control action uses larger targets and persistent labels when requested',
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Center(
              child: CallControlActionButton(
                icon: Icons.volume_off_rounded,
                semanticLabel: 'Mute participant audio',
                persistentLabel: 'Mute',
                onPressed: () {
                  activations += 1;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mute'), findsOneWidget);

    final constrainedBox = tester.widget<ConstrainedBox>(
      find.descendant(
        of: find.byType(CallControlActionButton),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minWidth >= 48 &&
              widget.constraints.minHeight >= 48,
        ),
      ),
    );

    expect(constrainedBox.constraints.minWidth, 48);
    expect(constrainedBox.constraints.minHeight, 48);

    await tester.tap(find.text('Mute'));
    await tester.pump();

    expect(activations, 1);
  });
}
