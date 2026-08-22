import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  testWidgets('Tiamat text buttons can shrink-wrap in unconstrained width',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnconstrainedBox(
            child: tiamat.TextButton(
              'Save changes',
              icon: Icons.save,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
