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

  testWidgets('submits a weekly recurrence that already has a weekday',
      (tester) async {
    RFC8984CalendarEvent? submittedEvent;

    await tester.pumpWidget(
      _editorHarness(
        config: _ImmediateDialogCalendarConfig(
          RecurrenceRuleEditorResult(
            RFC8984RecurrenceRule(
              frequency: 'weekly',
              firstDayOfWeek: 'su',
              byDay: [Rfc8984NDay('fr')],
            ),
          ),
        ),
        submitEvent: (event, {String? eventType}) async {
          submittedEvent = event;
          return true;
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Friday sync');
    await tester.pump();
    await tester.tap(find.text('Never Repeats'));
    await tester.pump();

    expect(find.text('Repeats Weekly on Fri'), findsOneWidget);

    final submitButton = find.widgetWithText(ElevatedButton, 'Submit');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(submittedEvent, isNotNull);
    final rule = submittedEvent!.recurrenceRules?.single;
    expect(rule, isNotNull);
    expect(rule!.frequency, 'weekly');
    expect(rule.byDay?.single.day, 'fr');
    expect(rule.firstDayOfWeek, 'su');
    await tester.pumpAndSettle();
  });

  testWidgets('compact editor keeps recurring event submit reachable',
      (tester) async {
    RFC8984CalendarEvent? submittedEvent;

    await tester.pumpWidget(
      _editorHarness(
        viewportSize: const Size(360, 360),
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

    await tester.enterText(find.byType(TextFormField), 'Compact weekly');
    await tester.pump();
    await tester.ensureVisible(find.text('Never Repeats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never Repeats'));
    await tester.pump();

    expect(find.text('Repeats Weekly'), findsOneWidget);

    final submitButton = find.widgetWithText(ElevatedButton, 'Submit');
    await tester.tap(submitButton);
    await tester.pump();

    expect(submittedEvent, isNotNull);
    expect(submittedEvent!.recurrenceRules?.single.frequency, 'weekly');
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

  testWidgets('lays out inside an AlertDialog without intrinsic errors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertDialog(
          content: CalendarEventEditor(
            config: const MatrixCalendarConfig(),
            submitEvent: (event, {String? eventType}) async => true,
            initialEvent: RFC8984CalendarEvent(
              uid: '',
              updated: DateTime.utc(2026, 6, 14, 12),
              title: '',
              start: DateTime(2026, 6, 15, 9),
              timeZone: 'America/New_York',
              duration: const Duration(hours: 1),
            ),
            editingExistingEvent: false,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('New Event'), findsOneWidget);
  });
}

Widget _editorHarness({
  required MatrixCalendarConfig config,
  required Future<bool> Function(RFC8984CalendarEvent event,
          {String? eventType})
      submitEvent,
  Size? viewportSize,
}) {
  final editor = CalendarEventEditor(
    config: config,
    submitEvent: submitEvent,
    initialEvent: RFC8984CalendarEvent(
      uid: '',
      updated: DateTime.utc(2026, 6, 14, 12),
      title: '',
      start: DateTime(2026, 6, 15, 9),
      timeZone: 'America/New_York',
      duration: const Duration(hours: 1),
    ),
    editingExistingEvent: false,
  );

  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => viewportSize == null
            ? editor
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(size: viewportSize),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: viewportSize.width,
                    height: viewportSize.height,
                    child: editor,
                  ),
                ),
              ),
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
