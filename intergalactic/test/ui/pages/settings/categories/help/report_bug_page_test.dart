import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';

void main() {
  testWidgets('report bug form exposes severity selector', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportBugPage(
              initialIncludeLogs: false,
              initialIncludeDiagnostics: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Severity'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Contact info'), findsNothing);
  });

  testWidgets('call stream template shows fixed report body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportBugPage(
              initialTemplate: BugReportTemplate.callStreamLogs,
              initialIncludeLogs: true,
              initialIncludeDiagnostics: true,
            ),
          ),
        ),
      ),
    );

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
