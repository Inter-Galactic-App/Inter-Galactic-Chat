import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet_calendar_widget/event_view.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rotated unavailability events fit narrow mobile columns',
      (tester) async {
    final event = MatrixCalendarEventState(
      senderId: '@alice:example.org',
      type: 'unavailability',
      data: RFC8984CalendarEvent(
        uid: 'unavailable-a',
        updated: DateTime.utc(2026, 6, 23, 12),
        title: 'Unavailable for focus block',
        start: DateTime.utc(2026, 6, 23, 13),
        duration: const Duration(hours: 1),
      ),
    )..loaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 66,
              height: 100,
              child: EventViewBox(
                event,
                const MatrixCalendarConfig(),
                boundary: const Rect.fromLTWH(0, 0, 66, 100),
                occurrenceDate: DateTime.utc(2026, 6, 23),
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
