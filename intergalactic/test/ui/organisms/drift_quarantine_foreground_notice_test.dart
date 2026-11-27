import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/drift_quarantine_foreground_notice.dart';

DriftQuarantinePresentationCase _case({
  DriftQuarantineNoticeKind notice = DriftQuarantineNoticeKind.firstForeground,
  int? daysRemaining,
  DriftQuarantineTimingVerdict? timingVerdict,
  DriftQuarantinePresentationState state =
      DriftQuarantinePresentationState.unresolved,
  DriftQuarantinePresentationReason reason =
      DriftQuarantinePresentationReason.none,
}) => DriftQuarantinePresentationCase(
  caseId: 'opaque-case',
  expectedRevision: 4,
  acknowledgementToken: 'opaque-token',
  state: state,
  reason: reason,
  historicalValidation: DriftQuarantineHistoricalValidation.notChecked,
  notice: notice,
  timingVerdict: timingVerdict,
  daysRemaining: daysRemaining,
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'renders the first foreground consequence copy and acknowledges after a frame',
    (tester) async {
      var acknowledgements = 0;
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 8,
              cases: [_case()],
            ),
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  acknowledgements += 1;
                  expect(caseId, 'opaque-case');
                  expect(expectedRevision, 4);
                  expect(acknowledgementToken, 'opaque-token');
                  expect(notice, DriftQuarantineNoticeKind.firstForeground);
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Local data needs attention'), findsOneWidget);
      expect(find.textContaining('permanently lost'), findsOneWidget);
      expect(find.text('Review details'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(acknowledgements, 1);
      final liveRegion = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .singleWhere((widget) => widget.properties.liveRegion == true);
      expect(liveRegion.container, isTrue);
      expect(liveRegion.properties.label, isNull);
      expect(find.text('opaque-case'), findsNothing);
      expect(find.text('opaque-token'), findsNothing);
    },
  );

  testWidgets(
    'does not acknowledge while backgrounded and dismissing only hides the current notice',
    (tester) async {
      var acknowledgements = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: false,
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 1,
              cases: [_case()],
            ),
            onDismiss: () => dismissed += 1,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  acknowledgements += 1;
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );
      await tester.pump();
      expect(acknowledgements, 0);
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(dismissed, 1);
      expect(find.text('Local data needs attention'), findsNothing);
    },
  );

  test(
    'timing verdict copy distinguishes normal and fallback expiry paths',
    () {
      final before = DriftQuarantinePresentationCopy.forCase(
        _case(
          timingVerdict: DriftQuarantineTimingVerdict.normalCountdown,
          daysRemaining: 2,
        ),
      );
      final ordinaryEligibility = DriftQuarantinePresentationCopy.forCase(
        _case(timingVerdict: DriftQuarantineTimingVerdict.ordinaryEligibility),
      );
      final grace = DriftQuarantinePresentationCopy.forCase(
        _case(timingVerdict: DriftQuarantineTimingVerdict.clockUncertainGrace),
      );
      final lastResort = DriftQuarantinePresentationCopy.forCase(
        _case(
          timingVerdict: DriftQuarantineTimingVerdict.lastResortEligibility,
        ),
      );
      final blocked = DriftQuarantinePresentationCopy.forCase(
        _case(
          timingVerdict: DriftQuarantineTimingVerdict.safetyBlockedRetention,
        ),
      );
      expect(before.title, 'Automatic removal eligibility in 2 days');
      final oneDay = DriftQuarantinePresentationCopy.forCase(
        _case(
          timingVerdict: DriftQuarantineTimingVerdict.normalCountdown,
          daysRemaining: 1,
        ),
      );
      expect(oneDay.title, 'Automatic removal eligibility in 1 day');
      expect(before.description, contains('automatically remove'));
      expect(before.description, contains('permanently lost'));
      expect(ordinaryEligibility.title, 'Automatic safety check pending');
      expect(before.description, contains('720 hours (30 full days)'));
      expect(ordinaryEligibility.description, contains('normal 720-hour'));
      expect(ordinaryEligibility.description, isNot(contains('37 real days')));
      expect(grace.title, 'Timing needs an additional safety check');
      expect(grace.description, contains('168-hour (seven full days)'));
      expect(
        grace.description,
        contains('does not authorize automatic removal'),
      );
      expect(lastResort.title, 'Automatic safety check pending');
      expect(lastResort.description, contains('888-hour (37 full days)'));
      expect(
        lastResort.description,
        contains('not proof that 37 real days passed'),
      );
      expect(lastResort.description, contains('permanently lost'));
      expect(blocked.title, 'Automatic removal paused for safety');
      expect(blocked.description, contains('no removal is being performed'));
      for (final item in [
        _case(),
        _case(state: DriftQuarantinePresentationState.pendingRetry),
        _case(notice: DriftQuarantineNoticeKind.daySeven),
      ]) {
        final description = DriftQuarantinePresentationCopy.forCase(
          item,
        ).description;
        expect(description, contains('720 hours (30 full days)'));
        expect(description, isNot(contains('calendar days')));
      }
    },
  );

  test('requires IOS to provide internally consistent timing verdict data', () {
    for (final days in [null, -1, 0, 30, 31]) {
      expect(
        () => _case(
          timingVerdict: DriftQuarantineTimingVerdict.normalCountdown,
          daysRemaining: days,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => _case(
        timingVerdict: DriftQuarantineTimingVerdict.clockUncertainGrace,
        daysRemaining: 3,
      ),
      throwsArgumentError,
    );
  });

  test('defensively freezes and bounds caller case lists', () {
    final cases = [_case()];
    final snapshot = DriftQuarantinePresentationSnapshot.ready(
      recordRevision: 1,
      cases: cases,
    );
    cases.clear();
    expect(snapshot.cases, hasLength(1));
    expect(
      () => DriftQuarantinePresentationSnapshot.ready(
        recordRevision: 1,
        cases: List.generate(65, (_) => _case()),
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'abandons a queued acknowledgement when foreground is lost before its frame',
    (tester) async {
      var foreground = true;
      var acknowledgements = 0;
      tester.binding.addPostFrameCallback((_) => foreground = false);
      final snapshot = DriftQuarantinePresentationSnapshot.ready(
        recordRevision: 1,
        cases: [_case()],
      );
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            isForegroundNow: () => foreground,
            snapshot: snapshot,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  acknowledgements += 1;
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );
      expect(acknowledgements, 0);

      foreground = true;
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            isForegroundNow: () => foreground,
            snapshot: snapshot,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  acknowledgements += 1;
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(acknowledgements, 1);
    },
  );

  testWidgets(
    'settles unavailable and throwing acknowledgement callbacks without retrying a revision',
    (tester) async {
      var unavailable = 0;
      var throwing = 0;
      final first = DriftQuarantinePresentationSnapshot.ready(
        recordRevision: 1,
        cases: [_case()],
      );
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: first,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  unavailable += 1;
                  return DriftQuarantineAcknowledgementResult.unavailable;
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: first,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  unavailable += 1;
                  return DriftQuarantineAcknowledgementResult.unavailable;
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(unavailable, 1);

      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 2,
              cases: [_case()],
            ),
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  throwing += 1;
                  throw StateError('test failure');
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(throwing, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queues the replacement callback when it changes before an acknowledgement dispatches',
    (tester) async {
      var oldAcknowledgements = 0;
      var replacementAcknowledgements = 0;
      final scheduled = <FrameCallback>[];
      final snapshot = DriftQuarantinePresentationSnapshot.ready(
        recordRevision: 1,
        cases: [_case()],
      );

      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: snapshot,
            schedulePostFrame: scheduled.add,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  oldAcknowledgements += 1;
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );

      await tester.pumpWidget(
        _host(
          DriftQuarantineForegroundNotice(
            isForeground: true,
            snapshot: snapshot,
            schedulePostFrame: scheduled.add,
            onAcknowledgeRenderedNotice:
                ({
                  required caseId,
                  required expectedRevision,
                  required acknowledgementToken,
                  required notice,
                }) async {
                  replacementAcknowledgements += 1;
                  return DriftQuarantineAcknowledgementResult.recorded;
                },
          ),
        ),
      );

      expect(scheduled, hasLength(2));
      scheduled.removeAt(0)(Duration.zero);
      scheduled.removeAt(0)(Duration.zero);
      await tester.pump();

      expect(oldAcknowledgements, 0);
      expect(replacementAcknowledgements, 1);
    },
  );
}
