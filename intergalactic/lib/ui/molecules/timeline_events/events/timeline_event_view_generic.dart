import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_generic.dart';
import 'package:intergalactic/ui/molecules/read_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart' as m;

import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:tiamat/atoms/avatar.dart';

class TimelineEventViewGeneric extends StatefulWidget {
  const TimelineEventViewGeneric({
    this.timeline,
    this.initialEvent,
    required this.index,
    this.room,
    this.onReadReceiptsTapped,
    this.readReceipts = const [],
    super.key,
  });
  final Timeline? timeline;
  final int index;
  final Room? room;
  final Function()? onReadReceiptsTapped;
  final List<String> readReceipts;
  final TimelineEvent? initialEvent;
  @override
  State<TimelineEventViewGeneric> createState() =>
      _TimelineEventViewGenericState();
}

class _TimelineEventViewGenericState extends State<TimelineEventViewGeneric> {
  String? text;
  IconData? icon;
  ImageProvider? senderAvatar;

  String messagePlaceholderSticker(String user) => Intl.message(
    "$user sent a sticker",
    desc: "Message body for when a user sends a sticker",
    args: [user],
    name: "messagePlaceholderSticker",
  );

  // messagePlaceholderUserCreatedRoom deliberately does NOT live here. It is
  // declared once, on the event model that actually renders it —
  // MatrixTimelineEventCreateRoom.getBody(). A second declaration existed here
  // with the same explicit `name:`, was never called, and made
  // generate_from_arb emit the message twice: a duplicate `static m5(...)` and
  // a duplicate map key in every messages_<locale>.dart, so the generated
  // library failed to compile with "'m5' is already declared in this scope"
  // across 17 locales.
  //
  // That was invisible on a checkout with a stale lib/generated/intl and hit
  // every fresh one. If a view here ever needs this string, call the model
  // rather than re-declaring the name.

  String get errorMessageFailedToSend => Intl.message(
    "Failed to send",
    desc: "Text that is placed below a message when the message fails to send",
    name: "errorMessageFailedToSend",
  );

  @override
  void initState() {
    if (widget.timeline != null) {
      setStateFromindex(widget.index);
    }

    if (widget.initialEvent != null) {
      loadStateFromEvent(widget.initialEvent!);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return Container();
    }

    return m.Material(
      color: m.Colors.transparent,
      child: Row(
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      if (icon != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(44, 0, 8, 0),
                          child: Icon(
                            icon,
                            size: 20,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      if (senderAvatar != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(44, 0, 8, 0),
                          child: Avatar(image: senderAvatar, radius: 10),
                        ),
                      Flexible(
                        child: Row(
                          children: [
                            Flexible(child: tiamat.Text.labelLow(text!)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.room != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
              child: SizedBox(
                width: 35,
                child: ReadIndicator(
                  room: widget.room!,
                  users: widget.readReceipts,
                  onTap: widget.onReadReceiptsTapped,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(TimelineEventViewGeneric oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The `timeline != null` test is not redundant with the comparison above
    // it: [setStateFromindex] dereferences `widget.timeline!`, and a timeline
    // that goes away satisfies the comparison. `initState` guards the same
    // call the same way.
    //
    // A withdrawn timeline is not the same as "nothing to do", though, which
    // is why it is a branch and not a `&&`. When it was one, a timeline going
    // from non-null to null while `initialEvent` stayed null skipped this
    // reload AND the `initialEvent` comparison below, so the previous text,
    // icon and avatar stayed on screen with no source left behind them - the
    // stale-row render both guards inside [setStateFromindex] and
    // [loadStateFromEvent] exist to avoid.
    //
    // `initialEvent` outranks the timeline in BOTH directions, which is what
    // the `initialEvent == null` test on the reload is for. Without it the
    // sentence above was true of the withdrawal branch and false of this one:
    // an index change with both sources present replaced the directly passed
    // event with whatever the timeline held at that index, so the row's own
    // source of truth lost to the fallback. CodeRabbit round 5 found that, and
    // found it as a CONTRADICTED COMMENT rather than a bug report - no caller
    // passes both today (`timeline_view_entry` passes timeline and index,
    // `timeline_event_view_single` passes initialEvent and no timeline), so
    // nothing could observe it. Fixed here rather than in the prose because
    // the branch below already resolves the same conflict this way, and two
    // branches of one method disagreeing about precedence is the defect.
    if (widget.index != oldWidget.index ||
        widget.timeline != oldWidget.timeline) {
      if (widget.initialEvent == null && widget.timeline != null) {
        setStateFromindex(widget.index);
      } else if (widget.initialEvent == null) {
        // `build` renders an empty row for a null `text`. No `setState`:
        // `Element.update` rebuilds this element as soon as
        // `didUpdateWidget` returns, which is the same assumption every
        // other assignment in this method makes.
        text = null;
        icon = null;
        senderAvatar = null;
      }
    }

    // The other half of this widget's input, and the one `didUpdateWidget`
    // used to ignore entirely. `initialEvent` is how TimelineEventViewSingle
    // drives this view - it passes no timeline and a constant index of 0, so
    // the branch above can never fire there and the event was read once, at
    // `initState`, and never again.
    //
    // That is reachable: room_event_search_widget.dart:96 feeds an
    // ImplicitlyAnimatedList whose results arrive over a stream
    // (onResultsChanged, :154) and replace `currentResults` in place, and the
    // underlying AnimatedList builds its children positionally with no keys.
    // A result inserted above this row hands the same State a different
    // event, and without this the row keeps rendering the previous one.
    //
    // Applied after the index branch, which is the order `initState` uses.
    //
    // An event that goes away is handled too, and is why this is a comparison
    // with a null branch rather than `initialEvent != null &&`. No current
    // caller does it - TimelineEventViewSingle's own `event` is non-nullable -
    // but this widget's parameter is nullable, so "the event was withdrawn"
    // is a state a caller can express, and the only render for it that is not
    // a lie is the empty row. Falling through would have left the previous
    // event's text, icon and avatar on screen indefinitely.
    if (widget.initialEvent != oldWidget.initialEvent) {
      final event = widget.initialEvent;
      if (event != null) {
        loadStateFromEvent(event);
      } else if (widget.timeline != null) {
        // A timeline is the other source of truth for this row, and it
        // outranks nothing-at-all: fall back to what the index resolves to
        // rather than blanking a row that still has an event behind it.
        setStateFromindex(widget.index);
      } else {
        // `build` renders an empty row for a null `text`.
        text = null;
        icon = null;
        senderAvatar = null;
      }
    }
  }

  void setStateFromindex(int index) {
    // Unlike TimelineEventViewReply and TimelineEventViewThread, this is also
    // called from `didUpdateWidget`, so it can mean "this row now shows a
    // different event". The index it is given is only accurate at the moment
    // the owning entry handed it over: TimelineViewEntry has no
    // `didUpdateWidget`, so
    // after a removal it keeps its old index until the next `update()`
    // corrects it, and a frame built in between reaches here with an index
    // past the end of a list that has already shrunk.
    //
    // Clear rather than keep the previous render. `build` already returns an
    // empty row when `text` is null, so clearing is exactly "an index with no
    // event renders as an empty row" - the choice
    // TimelineViewEntryState.loadState and TimelineEventViewPoll both make.
    // Keeping it would caption this row with a neighbouring event's text.
    if (index < 0 || index >= widget.timeline!.events.length) {
      text = null;
      icon = null;
      senderAvatar = null;
      return;
    }

    var event = widget.timeline!.events[index];
    loadStateFromEvent(event);
  }

  void loadStateFromEvent(TimelineEvent event) {
    var room = widget.room ?? widget.timeline?.room;
    // "This row now shows THIS event", so nothing from the previous one may
    // survive. `text` and `icon` are assigned on every path below;
    // `senderAvatar` is not - only an event with `showSenderAvatar` sets it -
    // so without this line a row that swapped to an event without one kept
    // the previous sender's avatar beside the new text.
    senderAvatar = null;
    if (event is! TimelineEventGeneric) {
      text = event.plainTextBody;
      icon = Icons.question_mark;
      return;
    }

    text = event.getBody(timeline: widget.timeline);
    icon = event.icon;

    var sender = room!.getMemberOrFallback(event.senderId);
    if (event.showSenderAvatar) {
      senderAvatar = sender.avatar;
    }
  }
}
