import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_page.dart';

void main() {
  testWidgets('empty destination state can refresh or cancel without sending', (
    tester,
  ) async {
    var refreshCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InboundShareDestinationPage(
          destinations: const [],
          onSelected: (_) {},
          onCancelled: () => cancelCount++,
          refreshDestinations: () {
            refreshCount++;
            return const [];
          },
        ),
      ),
    );

    expect(find.text('No writable conversations found.'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(refreshCount, 1);

    await tester.tap(find.byTooltip('Cancel share'));
    expect(cancelCount, 1);
  });
}
