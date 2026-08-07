import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  testWidgets('Tiamat IconButton exposes semantics and keyboard activation',
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: tiamat.IconButton(
              icon: Icons.download,
              semanticLabel: 'Download attachment',
              onPressed: () {
                activations += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Download attachment'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('Tiamat IconButton floors explicit minimum size', (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: tiamat.IconButton(
              icon: Icons.download,
              semanticLabel: 'Tiny download',
              minimumSize: 24,
              onPressed: () {
                activations += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Tiny download'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byIcon(Icons.download)) + const Offset(19, 0),
    );
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('Tiamat CircleButton uses tooltip label for keyboard activation',
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: tiamat.CircleButton(
              icon: Icons.add,
              tooltip: 'Add room',
              onPressed: () {
                activations += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Add room'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('Tiamat CircleButton floors explicit minimum size',
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: tiamat.CircleButton(
              icon: Icons.add,
              semanticLabel: 'Tiny add',
              minimumSize: 24,
              onPressed: () {
                activations += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Tiny add'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byIcon(Icons.add)) + const Offset(19, 0),
    );
    await tester.pump();

    expect(activations, 1);
  });
}
