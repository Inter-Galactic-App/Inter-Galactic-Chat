import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  testWidgets('stream-test warning names the impact on all participants', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: buildStreamTestParticipantImpactWarning),
        ),
      ),
    );

    expect(find.text(streamTestParticipantImpactWarning), findsOneWidget);
    expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Shared call impact. $streamTestParticipantImpactWarning',
      ),
      findsOneWidget,
    );
  });
}
