import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';

Widget _host({
  BugReportTemplate template = BugReportTemplate.genericAppBug,
  BugReportCategory? initialCategory,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReportBugPage(
          initialTemplate: template,
          initialCategory: initialCategory,
          initialIncludeLogs: false,
          initialIncludeDiagnostics: false,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('guided form shows plain-language severity labels', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.text('Minor'), findsOneWidget);
    expect(find.text('Disruptive'), findsOneWidget);
    expect(find.text('Blocking'), findsOneWidget);
    expect(find.text('Crash or data concern'), findsOneWidget);
    // No unexplained severity terms or contact collection.
    expect(find.text('P0'), findsNothing);
    expect(find.text('Contact info'), findsNothing);
  });

  testWidgets('guided form offers frequency choices', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('How often does it happen?'), findsOneWidget);
    expect(find.text('Every time'), findsOneWidget);
    expect(find.text('Sometimes'), findsOneWidget);
    expect(find.text('Only happened once'), findsOneWidget);
  });

  testWidgets('category selection reveals its follow-up questions and tips', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(initialCategory: BugReportCategory.callAudio),
    );

    // Category-specific follow-up questions for calls and audio.
    expect(find.text('Could you hear other participants?'), findsOneWidget);
    expect(find.text('Could they hear you?'), findsOneWidget);
    // Contextual troubleshooting card heading.
    expect(find.text('Having call audio trouble?'), findsOneWidget);
    // Category-specific troubleshooting action.
    expect(find.text('Left and rejoined the call'), findsOneWidget);
  });

  testWidgets('changing category changes the visible follow-up questions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(initialCategory: BugReportCategory.notifications),
    );

    expect(find.textContaining('Were notifications missing'), findsOneWidget);
    // Call-audio questions must not appear for the notifications category.
    expect(find.text('Could you hear other participants?'), findsNothing);
  });

  testWidgets(
    'switching category clears the previous category-specific troubleshooting '
    'selection but keeps universal ones',
    (tester) async {
      await tester.pumpWidget(
        _host(initialCategory: BugReportCategory.callAudio),
      );

      CheckboxListTile tileFor(String label) => tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, label),
      );

      Future<void> check(String label) async {
        final option = find.text(label);
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }

      // Check one universal action and one category-specific action. The
      // specific action ("Left and rejoined the call") is deliberately one that
      // the destination category (video calls) also offers, so its checkbox is
      // still rendered after the switch and its state is directly observable.
      await check('Restarted the app');
      await check('Left and rejoined the call');
      expect(tileFor('Restarted the app').value, isTrue);
      expect(tileFor('Left and rejoined the call').value, isTrue);

      // Switch category by tapping the inner DropdownButton (the real gesture
      // target) and picking the destination from the opened overlay.
      final button = find.byType(DropdownButton<BugReportCategory>);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Video calls and camera'), findsWidgets);
      await tester.tap(find.text('Video calls and camera').last);
      await tester.pumpAndSettle();

      // The universal selection is preserved across the switch, but the
      // category-specific selection is cleared — even though the destination
      // category also offers that action, the user must re-affirm it rather
      // than have a stale selection carried over invisibly.
      expect(tileFor('Restarted the app').value, isTrue);
      expect(tileFor('Left and rejoined the call').value, isFalse);
    },
  );

  testWidgets('performance category shows crash follow-up questions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(initialCategory: BugReportCategory.performanceCrash),
    );

    expect(
      find.text('Did the app freeze, close, or become unresponsive?'),
      findsOneWidget,
    );
    expect(find.text('App freezing, closing, or slow?'), findsOneWidget);
  });

  testWidgets('other category shows universal troubleshooting only', (
    tester,
  ) async {
    await tester.pumpWidget(_host(initialCategory: BugReportCategory.other));

    // Universal troubleshooting option is always present.
    expect(find.text('Restarted the app'), findsOneWidget);
    // "Other" has no category-specific follow-up questions.
    expect(find.text('Could you hear other participants?'), findsNothing);
  });

  testWidgets('category is required before preview', (tester) async {
    await tester.pumpWidget(_host());

    final previewButton = find.text('Preview Report');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Select which part of the app is affected.'),
      findsOneWidget,
    );
  });

  testWidgets('frequency is required once a problem is described', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(initialCategory: BugReportCategory.callAudio),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'What happened? (required)'),
      'I could not hear one participant.',
    );

    final previewButton = find.text('Preview Report');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.text('Choose how often the problem happens.'), findsOneWidget);
  });

  testWidgets('opening troubleshooting tips preserves entered form data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(initialCategory: BugReportCategory.callAudio),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'What happened? (required)'),
      'No audio from one person.',
    );

    final viewTips = find.text('View troubleshooting');
    await tester.ensureVisible(viewTips);
    await tester.tap(viewTips);
    await tester.pumpAndSettle();

    // Tip text is now shown, and the entered description is preserved.
    expect(find.text('Leave and rejoin the call.'), findsOneWidget);
    expect(find.text('No audio from one person.'), findsOneWidget);
  });

  testWidgets('call stream template shows fixed report body', (tester) async {
    await tester.pumpWidget(_host(template: BugReportTemplate.callStreamLogs));

    expect(find.text('Call/stream logs'), findsWidgets);
    expect(find.text('Call/stream log details'), findsOneWidget);
    expect(find.text('Report body'), findsOneWidget);
    expect(
      find.textContaining(
        'Recent redacted logs include the current call diagnostics snapshot',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('confirm the call/stream log payload'),
      findsOneWidget,
    );
  });
}
