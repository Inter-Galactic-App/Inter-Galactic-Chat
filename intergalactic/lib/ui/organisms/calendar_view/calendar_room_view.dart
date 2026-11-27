import 'dart:async';

import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/matrix/room_open_decrypt_retry.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:commet_calendar_widget/main.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class CalendarRoomView extends StatefulWidget {
  const CalendarRoomView(this.calendar, {super.key});
  final CalendarRoom calendar;

  @override
  State<CalendarRoomView> createState() => _CalendarRoomViewState();
}

class _CalendarRoomViewState extends State<CalendarRoomView> {
  CalendarViewMode? get savedDefaultMode {
    return switch (preferences.calendarDefaultView.value) {
      "day" => CalendarViewMode.day,
      "month" => CalendarViewMode.month,
      "week" => CalendarViewMode.week,
      _ => null,
    };
  }

  String? toPreferenceValue(CalendarViewMode mode) {
    return switch (mode) {
      CalendarViewMode.day => "day",
      CalendarViewMode.week => "week",
      CalendarViewMode.month => "month",
    };
  }

  @override
  void initState() {
    super.initState();
    unawaited(_retryDecryptLoadedTimeline());
  }

  @override
  void didUpdateWidget(covariant CalendarRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.calendar, widget.calendar)) {
      unawaited(_retryDecryptLoadedTimeline());
    }
  }

  Future<void> _retryDecryptLoadedTimeline() async {
    try {
      final room = widget.calendar.room;
      final timeline = room.timeline ?? await room.getTimeline();
      await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
        timeline,
        trigger: 'calendar_open',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to retry decrypt loaded calendar room timeline',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var query = MediaQuery.of(context);

    // I dont know why, but I had to manually specify the height like this
    // in order to get the month view to fill all the space
    Widget result = LayoutBuilder(
      builder: (context, constraints) {
        var newQuery = query.copyWith(
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
        return SizedBox(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          child: MediaQuery(
            data: newQuery,
            child: ScaledSafeArea(
              bottom: true,
              top: false,
              child: CalendarWidgetView(
                calendar: widget.calendar.calendar!,
                autoDisposeCalendar: false,
                useMobileLayout: Layout.mobile,
                watermark: false,
                initialMode: savedDefaultMode ?? CalendarViewMode.week,
                defaultMode: savedDefaultMode,
                onDefaultViewChanged: (mode, enabled) async {
                  if (enabled) {
                    await preferences.calendarDefaultView
                        .set(toPreferenceValue(mode));
                  } else if (preferences.calendarDefaultView.value ==
                      toPreferenceValue(mode)) {
                    await preferences.calendarDefaultView.set(null);
                  }

                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
          ),
        );
      },
    );

    if (Layout.desktop) {
      result = tiamat.Tile.lowest(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: ClipRRect(
            borderRadius: BorderRadiusGeometry.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            child: result,
          ),
        ),
      );
    }

    return result;
  }
}
