import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/ui/atoms/thread_reply_footer.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';

class TimelineEventViewThread extends StatefulWidget {
  const TimelineEventViewThread({
    super.key,
    required this.initialIndex,
    required this.timeline,
    required this.component,
    this.alignRight = false,
  });

  final int initialIndex;
  final Timeline timeline;
  final ThreadsComponent component;
  final bool alignRight;

  @override
  State<TimelineEventViewThread> createState() =>
      _TimelineEventViewThreadState();
}

class _TimelineEventViewThreadState extends State<TimelineEventViewThread> {
  String? senderName;
  String? body;
  ImageProvider? senderAvatar;
  Color? senderColor;

  /// Nullable, not `late`. An index that does not resolve leaves this unset,
  /// and it is read from the `onTap` closure rather than from `build`, so a
  /// bare early return would trade the RangeError below for a
  /// LateInitializationError on the next tap - the same trap
  /// TimelineEventViewPoll hit, just deferred until the user touches the row.
  String? threadEventId;

  /// The timeline entry the fields above were resolved from, held by IDENTITY
  /// rather than by id, and null when [initialIndex] resolved to nothing.
  ///
  /// This is the invalidation key, and the reason it is the object and not
  /// [threadEventId] is the whole point of the third clause in
  /// [didUpdateWidget]. See the comment there.
  TimelineEvent? _sourceEvent;

  @override
  void initState() {
    getStateFromIndex(widget.initialIndex);
    super.initState();
  }

  /// Re-resolve when this row is handed a different position or timeline.
  ///
  /// [TimelineEventViewThread.initialIndex] is named for how it was used, not
  /// for how it arrives: the owning [TimelineEventViewMessage] rebuilds this
  /// child with a new index every time its own `loadEventState` runs - after
  /// a removal shifts the rows below it, or on a revision bump - and the
  /// element is reused because nothing here is keyed. Without this the footer
  /// keeps naming the thread this State resolved at `initState`, so tapping
  /// it opens a thread on a message that is no longer the one above it.
  ///
  /// It also recovers the absent footer. An index that was past the end when
  /// this mounted left [threadEventId] null forever; a corrected index now
  /// resolves it.
  ///
  /// The same shape TimelineEventViewReactions (:54),
  /// TimelineEventViewUrlPreviews (:114) and TimelineEventViewPoll (:113)
  /// already have.
  ///
  /// The third clause is the one the index comparison cannot see, and it is
  /// the wrong-thread case rather than a stale-looking one: "the index did
  /// not change" does not mean "this row still shows the same event". The
  /// owning [TimelineEventViewMessage] re-issues this child's EXISTING index
  /// whenever the entry above it calls `update(i)` - which `onRoomUpdated`
  /// does for every mounted row on every room update, and `onEventChanged`
  /// does after a decrypt - and by then a removal may have shifted a
  /// different event into that position. [threadEventId] is what `onTap`
  /// opens, so without this the footer opens a thread on an event that is no
  /// longer the one above it.
  ///
  /// That third clause compares the entry OBJECT, not its id, and the
  /// difference is the whole invalidation key. Three signals were available
  /// and two of them are wrong:
  ///
  /// * The owning widget's `updateRevision` is too broad, and worse than
  ///   wasteful here. `getFirstReplyToThread` is not a pure read: on the
  ///   `m.relations`/`m.thread` path it calls `matrix.Timeline`
  ///   `.addAggregatedEvent`, which calls the SDK timeline's `onChange` for
  ///   the thread ROOT - this row's own event. That reaches
  ///   `MatrixTimeline.onEventChanged`, which REPLACES `events[i]` and calls
  ///   `notifyChanged`, and `Timeline.onChange` is a `sync: true` controller,
  ///   so `RoomTimelineWidgetView.onEventChanged` runs
  ///   `TimelineViewEntryState.update(i)` - bumping `updateRevision` -
  ///   synchronously inside our own resolve. Re-resolving on the revision
  ///   would therefore bump the revision, every frame, forever. The
  ///   measurement recorded against the reply view (a cleared row and a
  ///   re-issued `Room.getEvent` on every incoming message) is the milder
  ///   version of the same objection.
  ///
  /// * [threadEventId] alone is too narrow, which is what CodeRabbit round 4
  ///   found from two directions. A first reply arriving, a reply decrypting,
  ///   or a reply being redacted all leave the head event's id untouched, so
  ///   the footer kept an empty body, "Unknown Sender", or an obsolete reply.
  ///
  /// * The entry object is exactly in between, because the SDK replaces it
  ///   for precisely the events that matter. An incoming thread reply, a
  ///   decrypt and a redaction all reach `Timeline.addAggregatedEvent` or
  ///   `removeAggregatedEvent` for the reply, both of which fire `onChange`
  ///   on the ROOT, and `MatrixTimeline.onEventChanged` then hands `events[i]`
  ///   a freshly converted object. An unrelated message arriving does not:
  ///   `onRoomUpdated` bumps the revision and rebuilds this row, but leaves
  ///   the object at this index alone, so nothing is re-resolved.
  ///
  /// The re-entrancy above is also why this terminates: [getStateFromIndex]
  /// records the object it sees AFTER the lookup, so the replacement our own
  /// `addAggregatedEvent` causes is what gets stored, and the rebuild it
  /// schedules finds nothing left to do.
  @override
  void didUpdateWidget(TimelineEventViewThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex ||
        widget.timeline != oldWidget.timeline ||
        _eventAt(widget.initialIndex) != _sourceEvent) {
      // Clear before resolving, not after. [getStateFromIndex] returns early
      // both for an index with no event and for an event whose thread has no
      // first reply yet, and neither path overwrites these - so a leftover
      // sender and body would caption the new event with the previous
      // thread's reply.
      //
      // No `setState`: `Element.update` rebuilds this element as soon as
      // `didUpdateWidget` returns, and nothing here is asynchronous.
      threadEventId = null;
      _sourceEvent = null;
      senderName = null;
      body = null;
      senderAvatar = null;
      senderColor = null;
      getStateFromIndex(widget.initialIndex);
    }
  }

  /// The event [index] currently names, or null when it names none.
  ///
  /// Null on both sides of the comparison in [didUpdateWidget] is the honest
  /// answer for an index that still resolves to nothing: [_sourceEvent] is
  /// left null by the range guard below, so the two agree and nothing is
  /// re-resolved until the index names an event again.
  TimelineEvent? _eventAt(int index) {
    final events = widget.timeline.events;
    if (index < 0 || index >= events.length) {
      return null;
    }
    return events[index];
  }

  void getStateFromIndex(int index) {
    // The index is the position the owning entry handed over, and it is only
    // accurate at that moment. TimelineViewEntry has no `didUpdateWidget`, so
    // after a removal it keeps its old index until the next `update()`
    // corrects it, and this row can be mounted - or, since [didUpdateWidget],
    // re-entered - in between against a list that has already shrunk.
    //
    // Returning here leaves `threadEventId` null, and `build` renders no
    // footer at all for that. Deliberate: this footer names a thread on a
    // specific message and opens it on tap, so a footer with no event behind
    // it is a wrong thread rather than a blank one. That is distinct from the
    // existing "Unknown Sender" render, which is the honest answer when the
    // event IS on screen but its first reply is not yet known.
    if (index < 0 || index >= widget.timeline.events.length) {
      return;
    }

    var event = widget.timeline.events[index];
    threadEventId = event.eventId;
    var threadEvent = widget.component.getFirstReplyToThread(
      event,
      widget.timeline,
    );

    // Re-read rather than storing `event`, and recorded here rather than
    // beside [threadEventId] above: the lookup can replace this index's entry
    // as a side effect of its own aggregation write (see [didUpdateWidget]),
    // and storing the pre-lookup object would leave this row permanently
    // "changed" and re-resolving on every frame.
    //
    // Assigned before the early return below, not after. A head event whose
    // thread has no first reply yet still counts as resolved - it is what
    // renders the "Unknown Sender" footer - so leaving this null there would
    // re-enter the lookup on every rebuild for as long as the thread stays
    // empty.
    _sourceEvent = _eventAt(index);

    if (threadEvent == null) {
      return;
    }

    var sender = widget.timeline.room.getMemberOrFallback(threadEvent.senderId);

    if (threadEvent is TimelineEventMessage) {
      body = threadEvent.body;
    } else if (threadEvent is TimelineEventSticker) {
      body = threadEvent.stickerName;
    }

    senderName = sender.displayName;
    senderAvatar = sender.avatar;
    senderColor = sender.defaultColor;
  }

  @override
  Widget build(BuildContext context) {
    final threadEventId = this.threadEventId;
    if (threadEventId == null) {
      return const SizedBox.shrink();
    }

    return ThreadReplyFooter(
      body: body ?? "",
      senderName: senderName ?? "Unknown Sender",
      senderAvatar: senderAvatar,
      senderColor: senderColor,
      alignRight: widget.alignRight,
      onTap: () {
        EventBus.openThread.add((
          widget.timeline.client.identifier,
          widget.timeline.room.identifier,
          threadEventId,
        ));
        OverlappingPanels.of(context)?.reveal(RevealSide.right);
      },
    );
  }
}
