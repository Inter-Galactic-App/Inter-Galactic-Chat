import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/drift_quarantine_foreground_notice.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/drift_quarantine_recovery_panel.dart';

DriftQuarantinePresentationCase _case({String? accountLabel}) =>
    DriftQuarantinePresentationCase(
      caseId: 'opaque-case',
      expectedRevision: 1,
      acknowledgementToken: 'opaque-token',
      state: DriftQuarantinePresentationState.unresolved,
      reason: DriftQuarantinePresentationReason.none,
      historicalValidation: DriftQuarantineHistoricalValidation.unavailable,
      notice: DriftQuarantineNoticeKind.none,
      timingVerdict: DriftQuarantineTimingVerdict.normalCountdown,
      daysRemaining: 3,
      verifiedAssociatedAccountLabel: accountLabel,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'uses the shared loading panel and does not expose a cleanup action',
    (tester) async {
      await tester.pumpWidget(
        _host(
          DriftQuarantineRecoveryPanel(
            snapshot: DriftQuarantinePresentationSnapshot.loading(),
          ),
        ),
      );
      expect(find.text('Checking protected local data'), findsOneWidget);
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('Retry'), findsNothing);
    },
  );

  testWidgets(
    'keeps an unverified account anonymous and only displays a verified local label',
    (tester) async {
      await tester.pumpWidget(
        _host(
          DriftQuarantineRecoveryPanel(
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 1,
              cases: [_case()],
            ),
          ),
        ),
      );
      expect(find.textContaining('Associated account:'), findsNothing);
      expect(find.text('opaque-case'), findsNothing);

      await tester.pumpWidget(
        _host(
          DriftQuarantineRecoveryPanel(
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 2,
              cases: [_case(accountLabel: 'Local account')],
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Associated account: Local account'),
        findsOneWidget,
      );
    },
  );

  testWidgets('retains unsafe cases as manual review without a countdown', (
    tester,
  ) async {
    final unsafe = DriftQuarantinePresentationCase(
      caseId: 'opaque-case',
      expectedRevision: 1,
      acknowledgementToken: 'opaque-token',
      state: DriftQuarantinePresentationState.unsafeOrAmbiguous,
      reason: DriftQuarantinePresentationReason.clockUntrusted,
      historicalValidation: DriftQuarantineHistoricalValidation.unavailable,
      notice: DriftQuarantineNoticeKind.none,
      daysRemaining: null,
    );
    await tester.pumpWidget(
      _host(
        DriftQuarantineRecoveryPanel(
          snapshot: DriftQuarantinePresentationSnapshot.ready(
            recordRevision: 1,
            cases: [unsafe],
          ),
        ),
      ),
    );
    expect(find.text('Manual review needed'), findsOneWidget);
    expect(find.textContaining('days'), findsNothing);
  });

  testWidgets(
    'summarizes multiple unresolved cases without attributing an account',
    (tester) async {
      await tester.pumpWidget(
        _host(
          DriftQuarantineRecoveryPanel(
            snapshot: DriftQuarantinePresentationSnapshot.ready(
              recordRevision: 1,
              cases: [
                _case(accountLabel: 'First account'),
                _case(accountLabel: 'Second account'),
              ],
            ),
          ),
        ),
      );
      expect(
        find.textContaining('2 protected local-data items need attention.'),
        findsOneWidget,
      );
      expect(find.textContaining('Associated account:'), findsNothing);
    },
  );
}
