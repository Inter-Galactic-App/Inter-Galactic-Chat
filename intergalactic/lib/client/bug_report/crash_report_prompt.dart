import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CrashReportPrompt extends StatefulWidget {
  const CrashReportPrompt({
    required this.child,
    this.store = const PendingCrashReportStore(),
    super.key,
  });

  final Widget child;
  final PendingCrashReportStore store;

  @override
  State<CrashReportPrompt> createState() => _CrashReportPromptState();
}

class _CrashReportPromptState extends State<CrashReportPrompt> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_offerPendingCrashReport());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _offerPendingCrashReport() async {
    if (_checked || !mounted) {
      return;
    }
    _checked = true;

    final report = await widget.store.readPending();
    if (report == null || !mounted) {
      return;
    }

    final choice = await AdaptiveDialog.show<_CrashPromptChoice>(
      context,
      title: 'Inter Galactic closed unexpectedly',
      builder: (context) => _CrashReportPromptContent(report: report),
    );
    if (!mounted) {
      return;
    }

    await widget.store.clearPending();
    if (choice != _CrashPromptChoice.report || !mounted) {
      Log.i(
        'crash_report event=prompt_dismissed source=${report.source}',
        category: LogCategory.app,
        source: 'crash-report',
      );
      return;
    }

    Log.i(
      'crash_report event=prompt_accepted source=${report.source}',
      category: LogCategory.app,
      source: 'crash-report',
    );
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    await showReportBugDialog(
      context,
      initialTitle: 'Crash after previous app run',
      initialSeverity: BugReportSeverity.critical,
      initialReproductionSteps:
          'Inter Galactic offered this report after detecting an unhandled error from the previous app run.',
      initialExpectedBehavior: 'The app should stay open without crashing.',
      initialActualBehavior: [
        'Detected crash:',
        report.summary,
        '',
        'Captured details:',
        report.details,
      ].join('\n'),
      includeLogs: true,
      includeDiagnostics: true,
    );
  }
}

enum _CrashPromptChoice { report, dismiss }

class _CrashReportPromptContent extends StatelessWidget {
  const _CrashReportPromptContent({required this.report});

  final PendingCrashReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.body(
          'Inter Galactic saved a redacted crash summary and recent diagnostic logs from the previous run. You can review the full report before anything is sent.',
          softwrap: true,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: tiamat.Text.label(report.summary, softwrap: true),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            tiamat.Button.secondary(
              text: 'Dismiss',
              onTap: () =>
                  Navigator.of(context).pop(_CrashPromptChoice.dismiss),
            ),
            tiamat.Button(
              text: 'Report Crash',
              onTap: () => Navigator.of(context).pop(_CrashPromptChoice.report),
            ),
          ],
        ),
      ],
    );
  }
}
