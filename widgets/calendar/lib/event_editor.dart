import 'dart:io';

import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet_calendar_widget/calendar_event_metadata.dart';
import 'package:commet_calendar_widget/recurrence_editor.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:intl/intl.dart' as intl;

class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({
    this.initialEvent,
    required this.submitEvent,
    required this.config,
    required this.editingExistingEvent,
    this.editable = true,
    this.canDelete = false,
    this.deleteEvent,
    this.deleteOccurrenceEvent,
    this.eventType,
    this.calendar,
    this.calendarEventState,
    this.occurrenceDate,
    super.key,
  });
  final RFC8984CalendarEvent? initialEvent;
  final MatrixCalendarConfig config;
  final bool editable;
  final bool canDelete;
  final String? eventType;
  final MatrixCalendar? calendar;
  final MatrixCalendarEventState? calendarEventState;
  final DateTime? occurrenceDate;
  final bool editingExistingEvent;
  final Future<bool> Function(RFC8984CalendarEvent event, {String? eventType})
      submitEvent;
  final Future<void> Function(RFC8984CalendarEvent event)? deleteEvent;
  final Future<void> Function(
    RFC8984CalendarEvent event,
    DateTime occurrenceDate, {
    String? eventType,
  })? deleteOccurrenceEvent;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  late DateTime pickedStartDate;
  late TimeOfDay pickedStartTime;

  late DateTime pickedEndDate;
  late TimeOfDay pickedEndTime;

  String? timezone;

  RFC8984RecurrenceRule? recurrenceRule;

  late bool allDayEvent;
  late List<int> attendeeReminderOffsets;
  late bool attending;
  late List<int> personalReminderOffsets;

  String eventType = "event";

  bool get requiresTimezone =>
      !allDayEvent &&
      (recurrenceRule != null && recurrenceRule?.frequency != "yearly");

  DateTime get startTime => allDayEvent
      ? DateTime(
          pickedStartDate.year,
          pickedStartDate.month,
          pickedStartDate.day,
        )
      : DateTime(
          pickedStartDate.year,
          pickedStartDate.month,
          pickedStartDate.day,
          pickedStartTime.hour,
          pickedStartTime.minute,
        );

  DateTime get endTime => DateTime(
        pickedEndDate.year,
        pickedEndDate.month,
        pickedEndDate.day,
        pickedEndTime.hour,
        pickedEndTime.minute,
      );

  String eventName = "";

  bool submitting = false;
  String? submitError;

  bool get canEditAttendance =>
      widget.editingExistingEvent &&
      widget.initialEvent != null &&
      widget.calendar != null;

  bool get isRecurringEvent =>
      widget.initialEvent?.recurrenceRules?.isNotEmpty == true;

  DateTime get selectedOccurrenceDate => widget.occurrenceDate ?? startTime;

  @override
  void initState() {
    var time = widget.initialEvent?.start ?? DateTime.now();
    time =
        widget.config.convertToLocalTime(time, widget.initialEvent?.timeZone);
    eventName = widget.initialEvent?.title ?? "";
    pickedStartDate = time;
    pickedStartTime = TimeOfDay.fromDateTime(time);
    timezone = widget.initialEvent?.timeZone;
    if (widget.eventType != null) {
      eventType = widget.eventType!;
    }
    recurrenceRule = widget.initialEvent?.recurrenceRules?.firstOrNull;

    if (timezone == null) {
      FlutterTimezone.getLocalTimezone().then((info) {
        if (!mounted) {
          return;
        }

        setState(() {
          timezone = info.identifier;
        });
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint("CalendarEventEditor: timezone lookup failed: $error");
      });
    }

    allDayEvent = widget.initialEvent?.duration == Duration(hours: 24) &&
        widget.initialEvent?.start.isUtc == false;
    attendeeReminderOffsets = normalizeReminderOffsets(
      widget.initialEvent?.attendeeReminderOffsetsMinutes ?? const <int>[],
    );
    attending = widget.calendar
            ?.getAttendanceStateForUser(
              widget.initialEvent?.uid ?? "",
              widget.calendar?.widgetApi.userId ?? "",
            )
            ?.attending ??
        false;
    personalReminderOffsets = widget.initialEvent == null
        ? <int>[]
        : widget.calendar?.getEffectiveReminderOffsets(
              event: widget.initialEvent!,
            ) ??
            <int>[];

    var end = time.add(widget.initialEvent?.duration ?? Duration(hours: 1));
    pickedEndDate = end;
    pickedEndTime = TimeOfDay.fromDateTime(end);

    super.initState();
  }

  Widget buildReminderSelector({
    required String title,
    required String description,
    required List<int> selectedOffsets,
    required void Function(List<int> offsets) onChanged,
    bool enabled = true,
  }) {
    void toggleOffset(int offset, bool selected) {
      final next = selectedOffsets.toList();
      if (selected) {
        next.add(offset);
      } else {
        next.remove(offset);
      }

      onChanged(normalizeReminderOffsets(next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: tiamat.Text.labelLow(description),
        ),
        IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: MenuAnchor(
              menuChildren: [
                for (final option in calendarReminderOptions)
                  CheckboxMenuButton(
                    value: selectedOffsets.contains(option.minutesBefore),
                    onChanged: enabled
                        ? (selected) => toggleOffset(
                              option.minutesBefore,
                              selected == true,
                            )
                        : null,
                    child: Text(option.label),
                  ),
              ],
              builder: (context, controller, child) {
                return OutlinedButton.icon(
                  onPressed: enabled
                      ? () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        }
                      : null,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      summarizeReminderOffsets(selectedOffsets),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> saveAttendancePreferences() async {
    if (!canEditAttendance || widget.initialEvent == null) {
      return;
    }

    await widget.calendar!.saveAttendanceState(
      event: widget.initialEvent!,
      attending: attending,
      reminderOffsets: personalReminderOffsets,
    );
  }

  Widget buildAttendeeList() {
    final eventUid = widget.initialEvent?.uid;
    if (eventUid == null || widget.calendar == null) {
      return const SizedBox.shrink();
    }

    final attendees = widget.calendar!.getAttendanceStates(eventUid);
    if (attendees.isEmpty) {
      return tiamat.Text.labelLow(
          "No one has marked themselves as attending yet.");
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attendees.map((attendance) {
        final userId = attendance.userId;
        final displayName = widget.config.getUserDisplayname(userId) ?? userId;
        return Chip(
          avatar: tiamat.Avatar(
            radius: 10,
            placeholderColor: widget.config.getColorFromUser(userId),
            placeholderText: displayName,
            image: widget.config.getUserAvatar(userId),
          ),
          label: Text(displayName),
        );
      }).toList(),
    );
  }

  bool get hasDeleteActions =>
      widget.editingExistingEvent &&
      widget.canDelete &&
      widget.initialEvent != null &&
      (widget.deleteEvent != null || widget.deleteOccurrenceEvent != null);

  Widget buildDeleteActions() {
    final event = widget.initialEvent;
    if (event == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isRecurringEvent && widget.deleteOccurrenceEvent != null) ...[
          tiamat.Button.danger(
            text: "Delete This Occurrence",
            onTap: () async {
              await widget.deleteOccurrenceEvent?.call(
                event,
                selectedOccurrenceDate,
                eventType: eventType,
              );
              if (!mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
          ),
          if (widget.deleteEvent != null) const SizedBox(height: 8),
        ],
        if (widget.deleteEvent != null)
          tiamat.Button.danger(
            text: isRecurringEvent ? "Delete Series" : "Delete",
            onTap: () async {
              await widget.deleteEvent!(event);
              if (!mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  Widget buildCancelButton() {
    return tiamat.Button.secondary(
      text: "Cancel",
      onTap: () {
        Navigator.of(context).pop();
      },
    );
  }

  String? get submissionValidationError {
    if (eventName.trim().isEmpty) {
      return "Event must have a name";
    }

    if (!allDayEvent && !endTime.isAfter(startTime)) {
      return "End time must be after start time";
    }

    if (requiresTimezone && timezone == null) {
      return "Timezone is still loading";
    }

    return null;
  }

  Widget buildSubmitButton(String? validationError) {
    final isValidInput = validationError == null;
    return Opacity(
      opacity: isValidInput ? 1.0 : 0.3,
      child: tiamat.Button(
        text: "Submit",
        isLoading: submitting,
        onTap: isValidInput
            ? submitEvent
            : () {
                setState(() {
                  submitError = validationError;
                });
              },
      ),
    );
  }

  Widget buildEditorActions(String? validationError) {
    final compactWithDelete =
        hasDeleteActions && MediaQuery.sizeOf(context).width < 560;

    if (compactWithDelete) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildDeleteActions(),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              Expanded(child: buildCancelButton()),
              Expanded(child: buildSubmitButton(validationError)),
            ],
          ),
        ],
      );
    }

    return Row(
      spacing: 8,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasDeleteActions) Expanded(child: buildDeleteActions()),
        Expanded(child: buildCancelButton()),
        Expanded(child: buildSubmitButton(validationError)),
      ],
    );
  }

  Widget buildEditorActionFooter(String? validationError) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (submitting)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: tiamat.Text.labelLow("Saving event..."),
            ),
          if (submitError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: tiamat.Text.error(submitError!),
            ),
          buildEditorActions(validationError),
        ],
      ),
    );
  }

  RFC8984RecurrenceRule? buildSubmissionRecurrence() {
    if (recurrenceRule == null) {
      return null;
    }

    final submissionRecurrence = RFC8984RecurrenceRule.fromJson(
      Map<String, dynamic>.from(recurrenceRule!.toJson()),
    );

    if (submissionRecurrence.frequency == "weekly" &&
        (submissionRecurrence.byDay == null ||
            submissionRecurrence.byDay!.isEmpty)) {
      submissionRecurrence.byDay = [
        Rfc8984NDay(
            ["mo", "tu", "we", "th", "fr", "sa", "su"][startTime.weekday - 1])
      ];
      submissionRecurrence.firstDayOfWeek = "su";
    }

    if (submissionRecurrence.frequency == "monthly" &&
        (submissionRecurrence.byMonthDay == null ||
            submissionRecurrence.byMonthDay!.isEmpty) &&
        (submissionRecurrence.byDay == null ||
            submissionRecurrence.byDay!.isEmpty)) {
      submissionRecurrence.byMonthDay = [startTime.day];
    }

    return submissionRecurrence;
  }

  void markSubmitFailed({Object? error}) {
    if (error != null) {
      debugPrint("CalendarEventEditor: submit failed: $error");
    }

    setState(() {
      submitting = false;
      submitError =
          "Could not save this event. Check your connection and try again.";
    });
  }

  Future<void> submitEvent() async {
    if (submitting) {
      return;
    }

    setState(() {
      submitting = true;
      submitError = null;
    });

    try {
      var duration = switch (allDayEvent) {
        true => Duration(hours: 24),
        false => endTime.difference(startTime)
      };

      var start = switch (allDayEvent) {
        true => DateTime(startTime.year, startTime.month, startTime.day),
        false => requiresTimezone ? startTime.toLocal() : startTime.toUtc(),
      };

      var tz = requiresTimezone ? timezone : null;

      final submissionRecurrence = buildSubmissionRecurrence();

      var event = RFC8984CalendarEvent(
        uid: widget.initialEvent?.uid ?? "",
        updated: DateTime.now().toUtc(),
        title: eventName,
        description: widget.initialEvent?.description,
        timeZone: tz,
        attendeeReminderOffsetsMinutes: attendeeReminderOffsets,
        recurrenceRules:
            submissionRecurrence != null ? [submissionRecurrence] : null,
        recurrenceOverrides: widget.initialEvent?.recurrenceOverrides,
        start: start,
        duration: duration,
      );

      var succeeded =
          await widget.submitEvent(event, eventType: eventType).timeout(
                Duration(seconds: 10),
                onTimeout: () async => false,
              );

      if (succeeded == true) {
        if (!mounted) {
          return;
        }
        await saveAttendancePreferences();
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(true);
      } else {
        if (!mounted) {
          return;
        }
        markSubmitFailed();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      markSubmitFailed(error: error);
    }
  }

  Widget buildAdaptiveControlRow({
    required Widget label,
    required List<Widget> controls,
  }) {
    final controlGroup = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: controls,
    );

    if (MediaQuery.sizeOf(context).width < 460) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          Align(
            alignment: Alignment.centerRight,
            child: controlGroup,
          ),
        ],
      );
    }

    return Row(
      children: [
        label,
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: controlGroup,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool use24h = false;
    if (kIsWeb == false) {
      if (Platform.isAndroid || Platform.isIOS) {
        use24h = MediaQuery.of(context).alwaysUse24HourFormat;
      }
    }

    var formatter = switch (use24h) {
      true => intl.DateFormat.Hm(),
      false => intl.DateFormat.jm()
    };

    bool hasValidName = eventName.trim().isNotEmpty;
    final validationError = submissionValidationError;

    final scrollContent = SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.editable ? 12 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: "Back",
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.editingExistingEvent ? "Event Details" : "New Event",
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          IgnorePointer(
            ignoring: !widget.editable,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                    child: TextFormField(
                      initialValue: eventName,
                      readOnly: !widget.editable,
                      decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                        labelText: 'Event Name',
                      ),
                      onChanged: (value) => setState(() {
                        eventName = value;
                        submitError = null;
                      }),
                    ),
                  ),
                  SegmentedButton(
                    emptySelectionAllowed: true,
                    multiSelectionEnabled: false,
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: "event", label: Text("Event")),
                      ButtonSegment(
                          value: "unavailability",
                          label: Text("Unavailability")),
                    ],
                    expandedInsets: EdgeInsets.all(0),
                    selected: {eventType},
                    onSelectionChanged: (a) => setState(() {
                      if (a.isNotEmpty) {
                        eventType = a.first;
                      }
                    }),
                  ),
                  // Start Time
                  buildAdaptiveControlRow(
                    label: allDayEvent ? Text("Date:") : Text("From:"),
                    controls: [
                      TextButton.icon(
                        onPressed: () => showDatePicker(
                          context: context,
                          firstDate: DateTime.fromMicrosecondsSinceEpoch(0),
                          lastDate: DateTime(2100),
                          initialDate: pickedStartDate,
                        ).then(
                          (v) => setState(() {
                            pickedStartDate = v ?? pickedStartDate;
                          }),
                        ),
                        label: Text(
                          DateFormat(
                            DateFormat.YEAR_MONTH_WEEKDAY_DAY,
                          ).format(pickedStartDate),
                        ),
                      ),
                      if (!allDayEvent)
                        TextButton.icon(
                          onPressed: () => showTimePicker(
                            context: context,
                            builder: (context, child) {
                              return MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: use24h),
                                child: child!,
                              );
                            },
                            initialTime: pickedStartTime,
                          ).then(
                            (result) => setState(() {
                              pickedStartTime = result ?? pickedStartTime;
                            }),
                          ),
                          label: SizedBox(
                            width: 70,
                            child: Align(
                              alignment: AlignmentGeometry.centerRight,
                              child: Text(formatter.format(startTime)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // End Time
                  if (!allDayEvent)
                    buildAdaptiveControlRow(
                      label: Text("To:"),
                      controls: [
                        TextButton.icon(
                          onPressed: () => showDatePicker(
                            context: context,
                            firstDate: DateTime.fromMicrosecondsSinceEpoch(0),
                            lastDate: DateTime(2100),
                            initialDate: pickedEndDate,
                          ).then(
                            (v) => setState(() {
                              pickedEndDate = v ?? pickedEndDate;
                            }),
                          ),
                          label: Text(
                            DateFormat(
                              DateFormat.YEAR_MONTH_WEEKDAY_DAY,
                            ).format(pickedEndDate),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showTimePicker(
                            context: context,
                            builder: (context, child) {
                              return MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: use24h),
                                child: child!,
                              );
                            },
                            initialTime: pickedEndTime,
                          ).then(
                            (result) => setState(() {
                              pickedEndTime = result ?? pickedEndTime;
                            }),
                          ),
                          label: SizedBox(
                            width: 70,
                            child: Align(
                              alignment: AlignmentGeometry.centerRight,
                              child: Text(formatter.format(endTime)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: buildAdaptiveControlRow(
                      label: Text("Repeat:"),
                      controls: [
                        TextButton.icon(
                          onPressed: () {
                            widget.config
                                .dialog<RecurrenceRuleEditorResult?>(
                              context: context,
                              builder: (context) => RecurrenceRuleEditor(
                                initialRule: recurrenceRule,
                                anchorDate: startTime,
                              ),
                            )
                                .then((result) {
                              if (result != null) {
                                setState(() {
                                  recurrenceRule = result.rule;
                                  submitError = null;
                                });
                              }
                            });
                          },
                          label: Text(recurrenceRule == null
                              ? "Never Repeats"
                              : recurrenceRule!.toString()),
                        ),
                      ],
                    ),
                  ),
                  if (widget.editable)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                      child: buildReminderSelector(
                        title: "Attendee Reminders",
                        description:
                            "Choose the reminder times attendees will get by default when they mark themselves as attending.",
                        selectedOffsets: attendeeReminderOffsets,
                        onChanged: (offsets) => setState(() {
                          attendeeReminderOffsets = offsets;
                        }),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("All Day: "),
                      tiamat.Switch(
                        state: allDayEvent,
                        onChanged: (value) => setState(() {
                          allDayEvent = value;
                        }),
                      )
                    ],
                  ),

                  if (requiresTimezone && timezone != null)
                    tiamat.Tooltip(
                      child: tiamat.Text.labelLow(timezone!),
                      text:
                          "A timezone is required when an event repeats more than once a year, and is not an all-day event",
                    ),

                  if (startTime.isAfter(endTime))
                    tiamat.Text.error("End time must be after start time"),

                  if (!hasValidName)
                    tiamat.Text.error("Event must have a name"),
                ],
              ),
            ),
          ),
          if (canEditAttendance)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Attending"),
                      tiamat.Switch(
                        state: attending,
                        onChanged: (value) => setState(() {
                          attending = value;
                        }),
                      ),
                    ],
                  ),
                  tiamat.Text.labelLow(
                    "${widget.calendar?.getAttendanceCount(widget.initialEvent!.uid) ?? 0} attending",
                  ),
                  const SizedBox(height: 8),
                  buildAttendeeList(),
                  const SizedBox(height: 12),
                  buildReminderSelector(
                    title: "My Reminders",
                    description:
                        "Select which reminders should notify you for this event.",
                    selectedOffsets: personalReminderOffsets,
                    enabled: attending,
                    onChanged: (offsets) => setState(() {
                      personalReminderOffsets = offsets;
                    }),
                  ),
                  if (!widget.editable)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                      child: Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: tiamat.Button.secondary(
                              text: "Close",
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ),
                          Expanded(
                            child: tiamat.Button(
                              text: "Save",
                              onTap: () async {
                                await saveAttendancePreferences();
                                if (mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (!widget.editable &&
              widget.editingExistingEvent &&
              widget.canDelete &&
              widget.initialEvent != null &&
              widget.deleteEvent != null)
            Center(
              child: tiamat.Button.danger(
                text: "Delete Synced Events",
                onTap: () async {
                  final event = widget.initialEvent;
                  if (event == null) {
                    return;
                  }
                  await widget.deleteEvent?.call(event);
                  if (!mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );

    if (!widget.editable) {
      return scrollContent;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: scrollContent),
        buildEditorActionFooter(validationError),
      ],
    );
  }
}
