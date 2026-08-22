import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  testWidgets('Tiamat Switch can expose label and on/off value',
      (tester) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: tiamat.Switch(
                state: enabled,
                semanticLabel: 'Notifications',
                semanticOnTapHint: 'Toggle notifications',
                onLabel: 'On',
                offLabel: 'Off',
                onChanged: (value) {
                  setState(() {
                    enabled = value;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    var semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Notifications');

    expect(semantics.properties.value, 'Off');
    expect(semantics.properties.toggled, isFalse);

    await tester.tap(find.bySemanticsLabel('Notifications'));
    await tester.pump();

    semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Notifications');

    expect(enabled, isTrue);
    expect(semantics.properties.value, 'On');
    expect(semantics.properties.toggled, isTrue);
  });

  testWidgets('Tiamat Switch supports omitted on/off labels', (tester) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: tiamat.Switch(
                state: enabled,
                semanticLabel: 'Presence',
                semanticOnTapHint: 'Toggle presence',
                onChanged: (value) {
                  setState(() {
                    enabled = value;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    var semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Presence');

    expect(semantics.properties.value, isNull);
    expect(semantics.properties.toggled, isFalse);

    await tester.tap(find.bySemanticsLabel('Presence'));
    await tester.pump();

    semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Presence');

    expect(enabled, isTrue);
    expect(semantics.properties.value, isNull);
    expect(semantics.properties.toggled, isTrue);
  });
}
