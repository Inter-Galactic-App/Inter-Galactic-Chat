import 'package:commet_calendar_widget/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CalendarViewHeader extends StatelessWidget {
  const CalendarViewHeader({
    required this.mode,
    required this.date,
    required this.useMobileLayout,
    this.isDefaultView = false,
    this.secondaryDate,
    this.prevPage,
    this.nextPage,
    this.setViewMode,
    this.onDefaultViewChanged,
    super.key,
  });
  final CalendarViewMode mode;
  final DateTime date;
  final DateTime? secondaryDate;

  final Function()? nextPage;
  final Function()? prevPage;
  final Function(CalendarViewMode)? setViewMode;
  final bool isDefaultView;
  final ValueChanged<bool>? onDefaultViewChanged;
  final bool useMobileLayout;
  String getHeaderText() {
    if (mode == CalendarViewMode.month) {
      var format = DateFormat(DateFormat.YEAR_MONTH);
      var result = format.format(date);

      if (secondaryDate != null) {
        result += " - ${format.format(secondaryDate!)}";
      }

      return result;
    } else {
      var format = mode == CalendarViewMode.day
          ? DateFormat(DateFormat.YEAR_ABBR_MONTH_WEEKDAY_DAY)
          : DateFormat(DateFormat.YEAR_ABBR_MONTH_DAY);
      var result = format.format(date);
      var now = DateTime.now();
      if (secondaryDate == null &&
          (date.day == now.day &&
              date.month == now.month &&
              date.year == now.year)) {
        result = "Today (${result})";
      }

      if (secondaryDate != null) {
        result += " - ${format.format(secondaryDate!)}";
      }

      return result;
    }
  }

  @override
  Widget build(BuildContext context) {
    var result = useMobileLayout
        ? buildMobileLayout(context)
        : buildDesktopLayout(context);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        child: result,
      ),
    );
  }

  Widget buildMobileLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            getHeaderText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Align(
            alignment: AlignmentGeometry.centerRight,
            child: createLayoutButtons(context, compact: true),
          ),
        ],
      ),
    );
  }

  Widget buildDesktopLayout(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(onPressed: prevPage, icon: Icon(Icons.chevron_left)),
            Opacity(
              opacity: 0,
              child: IgnorePointer(
                child: Row(
                  children: [
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc))
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(getHeaderText()),
        Row(
          children: [
            createLayoutButtons(context),
            IconButton(
              onPressed: nextPage,
              icon: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget createLayoutButtons(BuildContext context, {bool compact = false}) {
    return Wrap(
      spacing: compact ? 4 : 8,
      runSpacing: compact ? 0 : 8,
      alignment: compact ? WrapAlignment.end : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Tooltip(
              text: "Day View",
              preferredDirection: AxisDirection.down,
              child: IconButton(
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  padding: compact ? EdgeInsets.zero : null,
                  constraints: compact
                      ? const BoxConstraints(minWidth: 38, minHeight: 38)
                      : null,
                  onPressed: () => setViewMode?.call(CalendarViewMode.day),
                  icon: Icon(
                      color: mode == CalendarViewMode.day
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      Icons.calendar_view_day)),
            ),
            tiamat.Tooltip(
              text: "Week View",
              preferredDirection: AxisDirection.down,
              child: IconButton(
                visualDensity:
                    compact ? VisualDensity.compact : VisualDensity.standard,
                padding: compact ? EdgeInsets.zero : null,
                constraints: compact
                    ? const BoxConstraints(minWidth: 38, minHeight: 38)
                    : null,
                onPressed: () => setViewMode?.call(CalendarViewMode.week),
                icon: Icon(
                    color: mode == CalendarViewMode.week
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    Icons.calendar_view_week),
              ),
            ),
            tiamat.Tooltip(
              text: "Month View",
              preferredDirection: AxisDirection.down,
              child: IconButton(
                visualDensity:
                    compact ? VisualDensity.compact : VisualDensity.standard,
                padding: compact ? EdgeInsets.zero : null,
                constraints: compact
                    ? const BoxConstraints(minWidth: 38, minHeight: 38)
                    : null,
                onPressed: () => setViewMode?.call(CalendarViewMode.month),
                icon: Icon(
                    color: mode == CalendarViewMode.month
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    Icons.calendar_view_month),
              ),
            ),
          ],
        ),
        if (onDefaultViewChanged != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                compact ? "Default" : "Default view",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(width: compact ? 2 : 6),
              Switch(
                materialTapTargetSize: compact
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
                value: isDefaultView,
                onChanged: onDefaultViewChanged,
              ),
            ],
          ),
      ],
    );
  }
}
