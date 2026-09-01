import 'dart:async';

import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/code_block.dart';
import 'package:intergalactic/ui/atoms/tiny_pill.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/developer_log_actions.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

export 'developer_log_actions.dart' show diagnosticLogFolderExportStatus;

const _bugReportTitleMaxLength = 120;
const _bugReportActualMaxLength = 1200;

typedef LogExceptionBugReportPrefill = ({String title, String actualBehavior});

@visibleForTesting
LogExceptionBugReportPrefill buildLogExceptionBugReportPrefill(
  LogEntryException entry,
) {
  final stackTrace = Log.redactSensitiveInfo(
    entry.trace?.toString() ?? '',
  ).trim();
  final content = Log.redactSensitiveInfo(entry.content).trim();
  final title = _truncateBugReportField(
    content.split("\n").first.trim(),
    _bugReportTitleMaxLength,
  );
  final actualBehavior = _truncateBugReportField(
    [
      "Exception:",
      content,
      if (stackTrace.isNotEmpty) ...["", "Stack trace:", stackTrace],
    ].join("\n"),
    _bugReportActualMaxLength,
  );

  return (
    title: title.isEmpty ? 'Captured runtime error' : title,
    actualBehavior: actualBehavior,
  );
}

String _truncateBugReportField(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }

  const suffix = "\n\n[truncated; full details are included in logs]";
  final prefixLength = maxLength - suffix.length;
  if (prefixLength <= 0) {
    return trimmed.substring(0, maxLength);
  }
  return '${trimmed.substring(0, prefixLength).trimRight()}$suffix';
}

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  bool savingLogs = false;
  bool copyingLogs = false;
  bool clearingLogs = false;
  bool openingFolder = false;

  StreamSubscription? sub;

  @override
  void initState() {
    sub = Log.log.onListUpdated.listen(onLogsUpdated);
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = List<LogEntry>.of(Log.log.reversed);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button.secondary(
                text: openingFolder ? "Opening..." : "Open Log Folder",
                onTap: openingFolder ? null : openLogFolder,
              ),
              tiamat.Button.secondary(
                text: copyingLogs ? "Copying..." : "Copy Recent Logs",
                onTap: copyingLogs ? null : copyRecentLogs,
              ),
              tiamat.Button.secondary(
                text: clearingLogs ? "Clearing..." : "Clear Logs",
                onTap: clearingLogs ? null : clearLogs,
              ),
              tiamat.Button.secondary(
                text: savingLogs ? "Saving..." : "Save Logs",
                onTap: savingLogs ? null : saveLogs,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final item = entries[index];
              return buildLog(item, index);
            },
          ),
        ),
      ],
    );
  }

  Widget buildLog(LogEntry entry, int index) {
    IconData icon = Icons.info;

    Color color = Colors.white38;

    switch (entry.type) {
      case LogType.info:
        icon = Icons.info;
        break;
      case LogType.debug:
        icon = Icons.bug_report;
        color = Colors.amberAccent;
        break;
      case LogType.error:
        icon = Icons.error_outline;
        color = AccessibilityScope.tokensOf(context).danger;
        break;
      case LogType.warning:
        color = Colors.amberAccent;
        icon = Icons.warning;
        break;
    }

    var background = index % 2 == 0
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : Theme.of(context).colorScheme.surfaceContainerHigh;

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: InkWell(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: background,
          ),
          child: InkWell(
            onTap: () => showLogDetail(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (entry.count > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                          child: TinyPill("${entry.count}"),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Icon(icon, size: 15, color: color),
                      ),
                      tiamat.Text.labelLow(entry.type.name),
                      const SizedBox(width: 10, child: tiamat.Seperator()),
                      tiamat.Text.labelLow(
                        DateFormat(
                          DateFormat.HOUR_MINUTE_SECOND,
                        ).format(entry.time.toLocal()),
                      ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      children: buildAnsiStyledTest(context, entry.content),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, TextStyle> ansiStyleMap(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = AccessibilityScope.tokensOf(context);
    return {
      "\x1b[30m": const TextStyle(color: Colors.black),
      "\x1b[31m": TextStyle(color: tokens.danger),
      "\x1b[32m": TextStyle(color: tokens.success),
      "\x1b[33m": TextStyle(color: tokens.warning),
      "\x1b[34m": TextStyle(color: tokens.linkText),
      "\x1b[35m": TextStyle(color: scheme.tertiary),
      "\x1b[36m": TextStyle(color: scheme.secondary),
      "\x1b[37m": const TextStyle(color: Colors.white),
      "\x1b[40m": const TextStyle(backgroundColor: Colors.black),
      "\x1b[41m": TextStyle(
        backgroundColor: tokens.danger.withValues(alpha: 0.28),
      ),
      "\x1b[42m": TextStyle(
        backgroundColor: tokens.success.withValues(alpha: 0.28),
      ),
      "\x1b[43m": TextStyle(
        backgroundColor: tokens.warning.withValues(alpha: 0.28),
      ),
      "\x1b[44m": TextStyle(
        backgroundColor: tokens.linkText.withValues(alpha: 0.28),
      ),
      "\x1b[45m": TextStyle(
        backgroundColor: scheme.tertiary.withValues(alpha: 0.28),
      ),
      "\x1b[46m": TextStyle(
        backgroundColor: scheme.secondary.withValues(alpha: 0.28),
      ),
      "\x1b[47m": const TextStyle(backgroundColor: Colors.white),
      "\x1b[0m": const TextStyle(),
    };
  }

  List<InlineSpan> buildAnsiStyledTest(BuildContext context, String text) {
    text = text.trim();
    List<InlineSpan> spans = List.empty(growable: true);
    int prevIndex = 0;
    var style = const TextStyle();
    final styles = ansiStyleMap(context);
    for (int i = 0; i < text.length; i++) {
      for (var entry in styles.entries) {
        if (text.startsWith(entry.key, i)) {
          var sub = text.substring(prevIndex, i);
          i += entry.key.length;
          prevIndex = i;
          spans.add(TextSpan(text: sub, style: style));
          style = entry.value;
          break;
        }
      }
    }

    if (prevIndex <= text.length - 1) {
      spans.add(TextSpan(text: text.substring(prevIndex), style: style));
    }

    return spans;
  }

  Widget logDetail(LogEntry entry) {
    return SelectionArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (entry is LogEntryException)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: Builder(
                  builder: (buttonContext) => tiamat.Button.secondary(
                    text: "Report Issue",
                    onTap: () => Navigator.of(
                      buttonContext,
                    ).pop(buildLogExceptionBugReportPrefill(entry)),
                  ),
                ),
              ),
            Text.rich(
              TextSpan(children: buildAnsiStyledTest(context, entry.content)),
            ),
            if (entry is LogEntryException && entry.trace != null)
              Codeblock(text: entry.trace!.toString()),
          ],
        ),
      ),
    );
  }

  void onLogsUpdated(event) {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> showLogDetail(LogEntry entry) async {
    final prefill = await AdaptiveDialog.show<LogExceptionBugReportPrefill>(
      context,
      builder: (context) => logDetail(entry),
      title: entry.type.name,
    );
    if (prefill == null || !mounted) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await showReportBugDialog(
      context,
      initialTitle: prefill.title,
      initialReproductionSteps:
          "Opened from Developer Logs for a captured runtime error.",
      initialActualBehavior: prefill.actualBehavior,
      includeLogs: true,
      includeDiagnostics: true,
    );
  }

  Future<void> saveLogs() async {
    setState(() => savingLogs = true);
    try {
      final destinationPath = await DeveloperLogActions.saveLogs();

      if (!mounted || destinationPath.isEmpty) {
        return;
      }

      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text("Saved logs")));
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to save logs");
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Failed to save logs")));
      }
    } finally {
      if (mounted) {
        setState(() => savingLogs = false);
      }
    }
  }

  Future<void> openLogFolder() async {
    setState(() => openingFolder = true);
    try {
      await DeveloperLogActions.openLogFolder();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Opened diagnostic log folder")),
        );
      }
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: "Failed to open diagnostic log folder",
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Failed to open log folder")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => openingFolder = false);
      }
    }
  }

  Future<void> copyRecentLogs() async {
    setState(() => copyingLogs = true);
    try {
      await DeveloperLogActions.copyRecentLogs();
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Copied recent logs")));
      }
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to copy recent logs");
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Failed to copy logs")));
      }
    } finally {
      if (mounted) {
        setState(() => copyingLogs = false);
      }
    }
  }

  Future<void> clearLogs() async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: "Clear diagnostic logs?",
      prompt:
          "This removes saved diagnostic log files and clears the current in-app log list.",
      confirmationText: "Clear Logs",
      cancelText: "Cancel",
      dangerous: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => clearingLogs = true);
    try {
      await DeveloperLogActions.clearLogs();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Cleared logs")));
      }
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to clear logs");
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Failed to clear logs")));
      }
    } finally {
      if (mounted) {
        setState(() => clearingLogs = false);
      }
    }
  }

  Future<String> getAllLogData() async {
    return DeveloperLogActions.getAllLogData();
  }

  Future<String> getRecentLogData() async {
    return DeveloperLogActions.getRecentLogData();
  }
}
