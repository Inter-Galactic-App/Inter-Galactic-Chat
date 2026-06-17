import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet_calendar_widget/event_editor.dart';
import 'package:commet_calendar_widget/recurrence_editor.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits a recurring event from the editor', (tester) async {
    RFC8984CalendarEvent? submittedEvent;

    await tester.pumpWidget(
      _editorHarness(
        config: _ImmediateDialogCalendarConfig(
          RecurrenceRuleEditorResult(
            RFC8984RecurrenceRule(frequency: 'weekly'),
          ),
        ),
        submitEvent: (event, {String? eventType}) async {
          submittedEvent = event;
          return true;
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Weekly standup');
    await tester.pump();
    await tester.tap(find.text('Never Repeats'));
    await tester.pump();

    expect(find.text('Repeats Weekly'), findsOneWidget);

    final submitButton = find.widgetWithText(ElevatedButton, 'Submit');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(submittedEvent, isNotNull);
    final rule = submittedEvent!.recurrenceRules?.single;
    expect(rule, isNotNull);
    expect(rule!.frequency, 'weekly');
    expect(rule.byDay?.single.day, 'mo');
    expect(rule.firstDayOfWeek, 'su');
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error when saving fails', (tester) async {
    await tester.pumpWidget(
      _editorHarness(
        config: const MatrixCalendarConfig(),
        submitEvent: (event, {String? eventType}) async => false,
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Retry event');
    await tester.pump();
    final submitButton = find.widgetWithText(ElevatedButton, 'Submit');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(
      find.text(
          'Could not save this event. Check your connection and try again.'),
      findsOneWidget,
    );
  });
}

Widget _editorHarness({
  required MatrixCalendarConfig config,
  required Future<bool> Function(RFC8984CalendarEvent event,
          {String? eventType})
      submitEvent,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CalendarEventEditor(
        config: config,
        submitEvent: submitEvent,
        initialEvent: RFC8984CalendarEvent(
          uid: '',
          updated: DateTime.utc(2026, 6, 14, 12),
          title: '',
          start: DateTime(2026, 6, 15, 9),
          duration: const Duration(hours: 1),
        ),
        editingExistingEvent: false,
      ),
    ),
  );
}

class _ImmediateDialogCalendarConfig extends MatrixCalendarConfig {
  const _ImmediateDialogCalendarConfig(this.result);

  final Object? result;

  @override
  Future<T?> dialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
  }) async {
    return result as T?;
  }
}
