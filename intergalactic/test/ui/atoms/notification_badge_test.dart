import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';

void main() {
  testWidgets('notification badge displays count text and clamps large counts',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              NotificationBadge(2),
              NotificationBadge(12),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('notification badge displays room-wide mention exclamation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NotificationBadge(
            1,
            exclamation: true,
            tone: NotificationBadgeTone.warning,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('!'), findsOneWidget);
  });
}
