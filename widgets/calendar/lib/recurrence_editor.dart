import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class RecurrenceRuleEditor extends StatefulWidget {
  const RecurrenceRuleEditor({
    super.key,
    this.initialRule,
    this.anchorDate,
  });
  final RFC8984RecurrenceRule? initialRule;
  final DateTime? anchorDate;
  @override
  State<RecurrenceRuleEditor> createState() => _RecurrenceRuleEditorState();
}

class RecurrenceRuleEditorResult {
  RFC8984RecurrenceRule? rule;

  RecurrenceRuleEditorResult(this.rule);
}

class _RecurrenceRuleEditorState extends State<RecurrenceRuleEditor> {
  late String repeatValue;
  Set<String> selectedDays = {};
  Set<int> selectedOrdinals = {};

  static const List<String> _weekdayOrder = [
    "mo",
    "tu",
    "we",
    "th",
    "fr",
    "sa",
    "su",
  ];

  @override
  void initState() {
    repeatValue = dropdownValueForRule(widget.initialRule);
    if (widget.initialRule?.byDay != null) {
      for (var day in widget.initialRule!.byDay!) {
        selectedDays.add(day.day);
        if (day.nthOfPeriod != null) {
          selectedOrdinals.add(day.nthOfPeriod!);
        }
      }
    }

    if (repeatValue == "custom") {
      selectedDays = selectedDays.isEmpty
          ? {
              weekdayToCode(
                  widget.anchorDate?.weekday ?? DateTime.now().weekday)
            }
          : selectedDays;
      selectedOrdinals = selectedOrdinals.isEmpty
          ? {ordinalForDate(widget.anchorDate ?? DateTime.now())}
          : selectedOrdinals;
    }

    super.initState();
  }

  RFC8984RecurrenceRule? get result {
    return switch (repeatValue) {
      "never" => null,
      "weekly" => RFC8984RecurrenceRule(
          frequency: "weekly",
          firstDayOfWeek: "su",
          byDay: selectedDays.isNotEmpty
              ? _weekdayOrder
                  .where(selectedDays.contains)
                  .map((e) => Rfc8984NDay(e))
                  .toList()
              : null,
        ),
      "weekly:2" => RFC8984RecurrenceRule(
          frequency: "weekly",
          interval: 2,
          firstDayOfWeek: "su",
          byDay: selectedDays.isNotEmpty
              ? _weekdayOrder
                  .where(selectedDays.contains)
                  .map((e) => Rfc8984NDay(e))
                  .toList()
              : null,
        ),
      "custom" => RFC8984RecurrenceRule(
          frequency: "monthly",
          firstDayOfWeek: "su",
          byDay: _buildCustomMonthlyDays(),
        ),
      final value => RFC8984RecurrenceRule(
          frequency: value,
          firstDayOfWeek: "su",
        ),
    };
  }

  bool get canSubmit {
    if (repeatValue != "custom") {
      return true;
    }

    return selectedOrdinals.isNotEmpty && selectedDays.isNotEmpty;
  }

  String dropdownValueForRule(RFC8984RecurrenceRule? rule) {
    if (rule == null) {
      return "never";
    }

    if (rule.frequency == "weekly" && rule.interval == 2) {
      return "weekly:2";
    }

    if (rule.frequency == "monthly" &&
        rule.byDay?.any((day) => day.nthOfPeriod != null) == true) {
      return "custom";
    }

    return rule.frequency;
  }

  List<Rfc8984NDay> _buildCustomMonthlyDays() {
    final results = <Rfc8984NDay>[];
    for (final ordinal
        in monthlyOrdinalOptions.where(selectedOrdinals.contains)) {
      for (final day in _weekdayOrder.where(selectedDays.contains)) {
        results.add(Rfc8984NDay(day, nthOfPeriod: ordinal));
      }
    }

    return results;
  }

  String weekdayToCode(int weekday) {
    return _weekdayOrder[weekday - 1];
  }

  int ordinalForDate(DateTime date) {
    final occurrenceFromStart = ((date.day - 1) ~/ 7) + 1;
    final lastDayOfMonth = DateTime(date.year, date.month + 1, 0);
    final lastOccurrenceDay =
        lastDayOfMonth.day - ((lastDayOfMonth.weekday - date.weekday + 7) % 7);
    final totalOccurrences = ((lastOccurrenceDay - 1) ~/ 7) + 1;
    final occurrenceFromEnd = occurrenceFromStart - totalOccurrences - 1;

    if (occurrenceFromEnd == -1 || occurrenceFromEnd == -2) {
      return occurrenceFromEnd;
    }

    return occurrenceFromStart.clamp(1, 5).toInt();
  }

  Widget buildOrdinalSelector() {
    final firstRow = monthlyOrdinalOptions.take(5).toList();
    final secondRow = monthlyOrdinalOptions.skip(5).toList();

    Widget buildRow(List<int> ordinals) {
      return SegmentedButton<int>(
        emptySelectionAllowed: true,
        multiSelectionEnabled: true,
        showSelectedIcon: false,
        segments: [
          for (final ordinal in ordinals)
            ButtonSegment<int>(
              value: ordinal,
              label: Text(recurrenceOrdinalLabel(ordinal)),
            ),
        ],
        expandedInsets: EdgeInsets.zero,
        selected: selectedOrdinals,
        onSelectionChanged: (values) => setState(() {
          selectedOrdinals = values;
        }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow("Week of month:"),
        const SizedBox(height: 8),
        buildRow(firstRow),
        const SizedBox(height: 8),
        buildRow(secondRow),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tiamat.Text.labelLow("Repeat:"),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: DropdownButtonFormField<String>(
              initialValue: repeatValue,
              items: [
                DropdownMenuItem(
                  child: Text("Never"),
                  value: "never",
                ),
                DropdownMenuItem(
                  child: Text("Daily"),
                  value: "daily",
                ),
                DropdownMenuItem(
                  child: Text("Weekly"),
                  value: "weekly",
                ),
                DropdownMenuItem(
                  child: Text("Every Other Week"),
                  value: "weekly:2",
                ),
                DropdownMenuItem(
                  child: Text("Monthly"),
                  value: "monthly",
                ),
                DropdownMenuItem(
                  child: Text("Custom"),
                  value: "custom",
                ),
                DropdownMenuItem(
                  child: Text("Yearly"),
                  value: "yearly",
                ),
              ],
              onChanged: (result) => setState(() {
                if (result == null) {
                  return;
                }

                repeatValue = result;
                if (repeatValue == "custom") {
                  selectedDays = selectedDays.isEmpty
                      ? {
                          weekdayToCode(
                            widget.anchorDate?.weekday ??
                                DateTime.now().weekday,
                          )
                        }
                      : selectedDays;
                  selectedOrdinals = selectedOrdinals.isEmpty
                      ? {ordinalForDate(widget.anchorDate ?? DateTime.now())}
                      : selectedOrdinals;
                }
              }),
            ),
          ),
          if (repeatValue == "custom") ...[
            buildOrdinalSelector(),
            const SizedBox(height: 12),
          ],
          if (repeatValue == "weekly" ||
              repeatValue == "weekly:2" ||
              repeatValue == "custom")
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: SegmentedButton(
                emptySelectionAllowed: repeatValue != "custom",
                multiSelectionEnabled: true,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: "mo", label: Text("M")),
                  ButtonSegment(value: "tu", label: Text("T")),
                  ButtonSegment(value: "we", label: Text("W")),
                  ButtonSegment(value: "th", label: Text("T")),
                  ButtonSegment(value: "fr", label: Text("F")),
                  ButtonSegment(value: "sa", label: Text("S")),
                  ButtonSegment(value: "su", label: Text("S")),
                ],
                expandedInsets: EdgeInsets.all(0),
                selected: selectedDays,
                onSelectionChanged: (v) => setState(() {
                  selectedDays = v;
                }),
              ),
            ),
          if (!canSubmit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: tiamat.Text.error(
                "Choose at least one week and one weekday for a custom repeat",
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            child: Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: tiamat.Button.secondary(
                    text: "Cancel",
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                ),
                Expanded(
                  child: IgnorePointer(
                    ignoring: !canSubmit,
                    child: Opacity(
                      opacity: canSubmit ? 1 : 0.35,
                      child: tiamat.Button(
                        text: "Submit",
                        onTap: () {
                          Navigator.of(context).pop(
                            RecurrenceRuleEditorResult(result),
                          );
                        },
                      ),
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
