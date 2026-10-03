import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_related.dart';
import 'package:intergalactic/diagnostic/benchmark_values.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;

class TimelineEventViewReply extends StatefulWidget {
  const TimelineEventViewReply({
    super.key,
    required this.timeline,
    required this.index,
    this.jumpToEvent,
    this.bubbleMessages = false,
    this.alignRight = false,
    this.bubbleColor,
    this.avatarSize = 32,
  });
  final Timeline timeline;
  final Function(String eventId)? jumpToEvent;
  final int index;
  final bool bubbleMessages;
  final bool alignRight;
  final Color? bubbleColor;
  final double avatarSize;

  @override
  State<TimelineEventViewReply> createState() => _TimelineEventViewReplyState();
}

class _TimelineEventViewReplyState extends State<TimelineEventViewReply> {
  String? senderName;
  String? body;
  Color? senderColor;

  bool loading = false;
  String? replyEventId;

  /// False when [widget.index] did not resolve to an event. See
  /// [getStateFromIndex]; `build` short-circuits on it.
  bool indexResolved = true;

  /// The id of the event at [widget.index] that the fields above were
  /// resolved from, or null when the index resolved to nothing.
  ///
  /// "The index did not change" does not mean "this row still shows the same
  /// event". The owning [TimelineEventViewMessage] re-issues this child's
  /// EXISTING index whenever the entry above it calls `update(i)` - which
  /// `onRoomUpdated` does for every mounted row on every room update, and
  /// `onEventChanged` does after a decrypt - and by then a removal may have
  /// shifted a different event into that position. Comparing the event itself
  /// is what catches a replacement at an unchanged index.
  String? _sourceEventId;

  /// Bumped by [clearResolvedState] so a [Room.getEvent] issued for a previous
  /// index cannot repaint this row after it has moved on.
  ///
  /// Without it the late completion looks exactly like a successful resolve:
  /// the row renders a sender and body, so nothing downstream can tell it is
  /// the wrong reply. `mounted` does not help - the State is still mounted,
  /// it is just showing a different event now.
  int _resolveGeneration = 0;

  @override
  void initState() {
    getStateFromIndex(widget.index);
    super.initState();
  }

  /// Re-resolve when this row is handed a different position or timeline.
  ///
  /// The owning [TimelineEventViewMessage] rebuilds this child with a new
  /// `index` every time its own `loadEventState` runs - after a removal
  /// shifts the rows below it, or on a revision bump - and the element is
  /// reused because nothing here is keyed. Without this the reply body stays
  /// pinned to whatever event this State resolved at `initState`, under a
  /// message body that has already moved on: a reply attributed to the wrong
  /// message, which is worse than the blank row the range guard produces.
  ///
  /// It also recovers the blank row. An index that was past the end when this
  /// mounted left [indexResolved] false forever; a corrected index now
  /// resolves it.
  ///
  /// Every other index-taking child of that widget already does exactly this:
  /// TimelineEventViewReactions (:54), TimelineEventViewUrlPreviews (:114)
  /// and TimelineEventViewPoll (:113). Reply and thread were the two that
  /// never had it.
  ///
  /// The third clause is the one the index comparison cannot see: a
  /// replacement at an unchanged index. See [_sourceEventId].
  ///
  /// It compares the event rather than the owning widget's `updateRevision`,
  /// which is the other way to learn that something changed. The revision is
  /// bumped for EVERY mounted row on every room update, and re-resolving on
  /// it would clear this row and re-issue [Room.getEvent] each time a message
  /// arrives - so a reply whose target is not in the timeline dictionary
  /// would drop back to "Replying to Loading" on every incoming message, and
  /// under a fast enough room would never finish resolving at all. The
  /// comparison here fires exactly when this row's event actually changed.
  @override
  void didUpdateWidget(TimelineEventViewReply oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index ||
        widget.timeline != oldWidget.timeline ||
        _eventIdAt(widget.index) != _sourceEventId) {
      // No `setState` around these: `Element.update` rebuilds this element as
      // soon as `didUpdateWidget` returns, so the fields are read on the very
      // next build. The asynchronous completion inside [getStateFromIndex]
      // does need one, and has its own.
      clearResolvedState();
      getStateFromIndex(widget.index);
    }
  }

  /// The id of the event [index] currently names, or null when it names none.
  String? _eventIdAt(int index) {
    final events = widget.timeline.events;
    if (index < 0 || index >= events.length) {
      return null;
    }
    return events[index].eventId;
  }

  /// Drops everything the previous index resolved to.
  ///
  /// Clearing rather than leaving the old values is the same rule the range
  /// guard follows: a stale sender and body under a new message claims a
  /// reply that is not the one on screen. If the new index resolves, these
  /// are overwritten in the same frame; if it does not, the row renders
  /// nothing.
  void clearResolvedState() {
    _resolveGeneration++;
    senderName = null;
    body = null;
    senderColor = null;
    replyEventId = null;
    _sourceEventId = null;
    loading = false;
    indexResolved = true;
  }

  void getStateFromIndex(int index) {
    // The index is the position the owning entry handed over, and it is only
    // accurate at that moment. TimelineViewEntry has no `didUpdateWidget`, so
    // after a removal it keeps its old index until the next `update()`
    // corrects it, and this row can be mounted - or, since [didUpdateWidget],
    // re-entered - in between against a list that has already shrunk.
    //
    // Render nothing rather than fall through to the null fields below. Their
    // "Replying to Loading" / "Unknown" placeholder is the honest render for a
    // reply target still being fetched; reusing it for an index with no event
    // would claim a reply that is not on screen. Same rule as
    // TimelineEventViewPoll.
    if (index < 0 || index >= widget.timeline.events.length) {
      indexResolved = false;
      return;
    }

    var event = widget.timeline.events[index];
    // Recorded before the content checks below, both of which return early:
    // [didUpdateWidget] compares this against the event the index names, so
    // leaving it unset for an event this row renders nothing for would make
    // every later rebuild re-enter here for nothing.
    _sourceEventId = event.eventId;
    if (event is! TimelineEventFeatureRelated) {
      return;
    }

    var e = event as TimelineEventFeatureRelated;
    if (e.relatedEventId == null) {
      return;
    }

    var replyEvent = widget.timeline.tryGetEvent(e.relatedEventId!);

    if (replyEvent == null) {
      loading = true;
      final generation = _resolveGeneration;
      widget.timeline.room.getEvent(e.relatedEventId!).then((value) {
        if (!mounted || value == null) {
          return;
        }
        // This row may have been handed a different index while the fetch was
        // in flight. See [_resolveGeneration].
        if (generation != _resolveGeneration) {
          return;
        }
        setStateFromEvent(value);
      });
    } else {
      setStateFromEvent(replyEvent);
    }
  }

  void setStateFromEvent(TimelineEvent event) {
    setState(() {
      replyEventId = event.eventId;
      var sender = widget.timeline.room.getMemberOrFallback(event.senderId);
      senderName = sender.displayName;
      senderColor = sender.defaultColor;
      body = event.plainTextBody;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineReplyBodyBuilt += 1;
    if (!indexResolved) {
      return const SizedBox.shrink();
    }

    if (widget.bubbleMessages) {
      return bubbleReply(context);
    }

    final scheme = material.Theme.of(context).colorScheme;
    final senderNameColor = AccessibilityScope.tokensOf(
      context,
    ).resolveIdentityTextColor(senderColor, scheme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: jumpToReply,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 45,
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: ReplyLinePainter2(
                        pathColor: material.Theme.of(
                          context,
                        ).colorScheme.secondary,
                        avatarSize: widget.avatarSize,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: "${senderName ?? "Loading"} ",
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: senderNameColor),
                        ),
                        TextSpan(
                          text: body ?? "Unknown",
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: material.Theme.of(
                                  context,
                                ).colorScheme.secondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Column(
                //   children: [
                //     tiamat.Text(
                //       senderName ?? "Loading",
                //       color: senderColor,
                //       autoAdjustBrightness: true,
                //     ),
                //   ],
                // ),
                // Flexible(
                //   child: Padding(
                //     padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                //     child: tiamat.Text(
                //       body ?? "Unknown",
                //       maxLines: 2,
                //       overflow: TextOverflow.ellipsis,
                //       color: material.Theme.of(context).colorScheme.secondary,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget bubbleReply(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = widget.bubbleColor ?? scheme.surfaceContainerLow;
    final senderNameColor = AccessibilityScope.tokensOf(
      context,
    ).resolveIdentityTextColor(senderColor, scheme, background: bubbleColor);
    final crossAxisAlignment = widget.alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.alignRight ? 0 : widget.avatarSize + 12,
        0,
        widget.alignRight ? 28 : 0,
        4,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: jumpToReply,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor.withValues(alpha: 0.54),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Text(
                    'Replying to ${senderName ?? "Loading"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: senderNameColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body ?? 'Unknown',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.alignRight
                        ? TextAlign.right
                        : TextAlign.left,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

  void jumpToReply() {
    final id = replyEventId;
    if (id == null) {
      return;
    }
    widget.jumpToEvent?.call(id);
  }
}

class ReplyLinePainter2 extends CustomPainter {
  Color pathColor;
  double strokeWidth;
  double radius;
  double padding;
  double avatarSize;
  ReplyLinePainter2({
    this.pathColor = Colors.white,
    this.strokeWidth = 1.5,
    this.radius = 5,
    this.avatarSize = 32,
    this.padding = 4,
  }) {
    _paint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
  }

  late Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    Path path = Path();
    path.moveTo(avatarSize / 2, size.height - padding);
    path.relativeLineTo(0, (-size.height + 9 + padding) + radius);
    path.relativeArcToPoint(
      Offset(radius, -radius),
      radius: Radius.circular(radius),
    );
    path.relativeLineTo(size.width - (avatarSize / 2) - radius - padding, 0);
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
