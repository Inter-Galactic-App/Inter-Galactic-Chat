import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  testWidgets('Tiamat IconToggle exposes state and keyboard activation',
      (tester) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Center(
                child: tiamat.IconToggle(
                  icon: Icons.favorite,
                  state: enabled,
                  onPressed: (value) {
                    setState(() {
                      enabled = value;
                    });
                  },
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.bySemanticsLabel('Favorite'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    var semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Favorite');
    expect(semantics.properties.toggled, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(enabled, isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Favorite');
    expect(semantics.properties.toggled, isTrue);
  });

  testWidgets('Tiamat success button uses theme container color',
      (tester) async {
    const scheme = ColorScheme.dark(
      tertiaryContainer: Color(0xFF123456),
      onTertiaryContainer: Color(0xFFF0F0F0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.from(colorScheme: scheme),
        home: const Scaffold(
          body: Center(
            child: tiamat.Button.success(text: 'Done'),
          ),
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      scheme.tertiaryContainer,
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      scheme.onTertiaryContainer,
    );
  });
}
