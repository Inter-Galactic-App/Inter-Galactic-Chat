import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/log_page.dart';

void main() {
  setUp(() {
    Log.log.clear();
  });

  tearDown(() {
    Log.log.clear();
  });

  test('log exception bug report prefill is redacted and bounded', () {
    final entry = LogEntryException(
      LogType.error,
      'Failed to join call\n'
      'Authorization: Bearer livekit-secret\n'
      '${'detail ' * 260}',
      Exception('LiveKit connect failed'),
      StackTrace.fromString(
        '#0 SignalClient.connect access_token=stack-secret\n'
        '#1 Room.connect',
      ),
      category: LogCategory.livekit,
      source: 'test',
    );

    final prefill = buildLogExceptionBugReportPrefill(entry);

    expect(prefill.title, 'Failed to join call');
    expect(prefill.actualBehavior, contains('Exception:'));
    expect(prefill.actualBehavior, contains('[REDACTED]'));
    expect(prefill.actualBehavior, contains('[truncated;'));
    expect(prefill.actualBehavior.length, lessThanOrEqualTo(1200));
    expect(prefill.actualBehavior, isNot(contains('livekit-secret')));
    expect(prefill.actualBehavior, isNot(contains('stack-secret')));
  });

  testWidgets('report issue opens bug report form after closing log detail',
      (tester) async {
    Log.log.add(
      LogEntryException(
        LogType.error,
        'Failed to join call',
        Exception('LiveKit connect failed'),
        StackTrace.fromString('#0 SignalClient.connect\n#1 Room.connect'),
        category: LogCategory.livekit,
        source: 'test',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogPage(),
        ),
      ),
    );

    await tester.tap(find.text('Failed to join call'));
    await tester.pumpAndSettle();

    expect(find.text('Report Issue'), findsOneWidget);

    await tester.tap(find.text('Report Issue'));
    await tester.pumpAndSettle();

    expect(find.text('Report Issue'), findsNothing);
    expect(find.text('Report a Bug'), findsWidgets);
    expect(find.text('Severity'), findsOneWidget);
  });
}
