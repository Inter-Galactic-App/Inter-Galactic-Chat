import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/polls/poll_component.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_call.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_emote.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_generic.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/diagnostic/benchmark_values.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_poll.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_date_time_marker.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_diagnostics_visibility.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineViewEntry extends StatefulWidget {
  const TimelineViewEntry({
    required this.timeline,
    required this.initialIndex,
    this.onEventHovered,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.jumpToEvent,
    this.showDetailed = false,
    this.singleEvent = false,
    this.isThreadTimeline = false,
    this.previewMedia = false,
    this.highlightedEventId,
    super.key,
  });
  final Timeline timeline;
  final int initialIndex;
  final Function(String eventId)? onEventHovered;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(String eventId)? jumpToEvent;
  final bool showDetailed;
  final bool isThreadTimeline;
  final String? highlightedEventId;
  final bool previewMedia;

  // Should be true if we are showing this event on its own, and not as part of a timeline
  final bool singleEvent;

  @override
  State<TimelineViewEntry> createState() => TimelineViewEntryState();
}

// This enum exists because we need to know which type of message to render
// But if we try to check the actual type of the event during build e.g: (`event is TimelineEventMessage`)
// It causes extra widget rebuilds, so we check type only during the event update and store it with this enum
// I thought maybe if we override hashcode of TimelineEventBase it would allow us to just check the type
// But it didnt. I dont know if there is a way to fix that
enum TimelineEventWidgetDisplayType { message, generic, poll, hidden }

class TimelineViewEntryState extends State<TimelineViewEntry>
    implements TimelineEventViewWidget, SelectableEventViewWidget {
  late String eventId;
  late TimelineEventStatus status;

  // Note that this index is only reliable on builds - if an item is inserted in to the list, this index will be out of sync until its updated.
  // If you need to get the event which this widget represents, use the ID
  late int index;

  bool selected = false;
  bool isThreadReply = false;
  bool isThreadRootEvent = false;
  bool highlighted = false;
  bool redacted = false;
  int eventUpdateRevision = 0;
  TimelineEventWidgetDisplayType _widgetType =
      TimelineEventWidgetDisplayType.hidden;
  LayerLink? timelineLayerLink;

  late DateTime time;
  bool showDateSeperator = false;

  String get originalThreadMessageLabel => Intl.message(
    'Original message',
    name: 'originalThreadMessageLabel',
    desc: 'Label for the root message pinned at the top of a thread',
  );

  String quickReactionSemanticLabel(String reactionName) => Intl.message(
    'React with $reactionName',
    name: 'quickReactionSemanticLabel',
    desc: 'Accessibility label for a timeline quick reaction action',
    args: [reactionName],
  );

  String get genericQuickReactionSemanticLabel => Intl.message(
    'React',
    name: 'genericQuickReactionSemanticLabel',
    desc:
        'Accessibility label for a timeline quick reaction action when the reaction name is unavailable',
  );

  ThreadsComponent? threads;
  PollComponent? polls;

  List<String> readReceipts = [];

  @override
  void initState() {
    threads = widget.timeline.room.client.getComponent<ThreadsComponent>();
    polls = widget.timeline.client.getComponent<PollComponent>();

    // Guarded separately from `loadState`, and BEFORE it: this read runs first
    // and would throw on a fresh mount at a stale index, so the guard inside
    // `loadState` never gets the chance. A row whose index does not resolve is
    // not a thread reply, which is also what an absent `threads` component
    // yields.
    final initialIndexResolves =
        widget.initialIndex >= 0 &&
        widget.initialIndex < widget.timeline.events.length;
    isThreadReply =
        initialIndexResolves &&
        (threads?.isEventInResponseToThread(
              widget.timeline.events[widget.initialIndex],
              widget.timeline,
            ) ??
            false);

    loadState(widget.initialIndex);
    super.initState();
  }

  void loadState(int eventIndex) {
    // Not for the `update()` path: that loop is bounded by
    // `timeline.events.length` in `onRoomUpdated`, so the index it passes is
    // always in range.
    //
    // CORRECTED. This comment previously said the window was
    // `Timeline.removeEvent` calling `onRemove.add(index)` and having the
    // listener run on a LATER MICROTASK while `events.removeAt(index)` had
    // already shortened the list. That is wrong: all three controllers are
    // `StreamController.broadcast(sync: true)` (timeline.dart:66-68), so the
    // listener runs BEFORE the removal. `onEventRemoved`'s own
    // `assert(timeline.events[index].eventId == removed.$2)` proves it - that
    // assertion only holds while the list is still long.
    //
    // The real mechanism is staleness, not a race. This class has no
    // `didUpdateWidget`, so `index` is refreshed only by `initState` and
    // `update()`. `onEventRemoved` shrinks `eventKeys` and `recentItemsCount`
    // and calls `setState`, but never calls `update()`. So after a removal
    // every mounted entry below the removed row keeps an index one too large,
    // and the entry that was last ends up with exactly `index ==
    // events.length` - which it then hands to the event views below.
    //
    // `redacted` is what `build` already short-circuits on, so reusing it is
    // the whole remedy: an index with no event renders as an empty row rather
    // than as the neighbouring message, the same choice the views below make.
    if (eventIndex < 0 || eventIndex >= widget.timeline.events.length) {
      redacted = true;
      index = eventIndex;
      return;
    }

    var event = widget.timeline.events[eventIndex];
    redacted = widget.timeline.isEventRedacted(event);

    var receipts = widget.timeline.room
        .getComponent<ReadReceiptComponent>()
        ?.getReceipts(event);
    if (receipts != null) {
      readReceipts = receipts;
    }

    eventId = event.eventId;
    status = event.status;
    index = eventIndex;
    time = event.originServerTs;
    isThreadRootEvent =
        widget.isThreadTimeline &&
        (threads?.isHeadOfThread(event, widget.timeline) ?? false);

    _widgetType = eventToDisplayType(
      event,
      polls: polls,
      room: widget.timeline.room,
    );

    showDateSeperator = shouldEventShowDate(eventIndex);
    highlighted = event.eventId == widget.highlightedEventId;
  }

  static TimelineEventWidgetDisplayType eventToDisplayType(
    TimelineEvent event, {
    PollComponent? polls,
    Room? room,
  }) {
    if (event is MatrixTimelineEventMembership &&
        room != null &&
        event.shouldHideFromRoomTimeline) {
      return TimelineEventWidgetDisplayType.hidden;
    }

    // In a call room the call itself is the room, so "X started a call" and
    // "X ended the call" describe what the user is already looking at. The chat
    // beside a call is for what people say to each other.
    //
    // Scoped to call rooms deliberately. In a direct message the same lines are
    // useful history - a missed call is worth a record - so this must not become
    // a global rule. See DECISIONS.md and the 2026-08-21 call-room audit.
    //
    // This is the four legacy 1:1 VoIP events. The MatrixRTC membership
    // (`org.matrix.msc3401.call.member`) never reaches here: it has no case in
    // the timeline-event switch, so it is already unknown and falls through to
    // hidden at the bottom of this method.
    if (event is MatrixTimelineEventCall &&
        room?.getComponent<VoipRoomComponent>() != null) {
      return TimelineEventWidgetDisplayType.hidden;
    }

    if (event is TimelineEventMessage ||
        event is TimelineEventSticker ||
        event is TimelineEventEncrypted) {
      return TimelineEventWidgetDisplayType.message;
    }

    if (event is TimelineEventGeneric) {
      return TimelineEventWidgetDisplayType.generic;
    }

    if (polls?.isPollEvent(event) == true) {
      return TimelineEventWidgetDisplayType.poll;
    }

    if (event.status == TimelineEventStatus.error) {
      return TimelineEventWidgetDisplayType.generic;
    }

    return TimelineEventWidgetDisplayType.hidden;
  }

  bool shouldEventShowDate(int index) {
    if (widget.singleEvent) {
      return false;
    }

    if (widget.isThreadTimeline) {
      if (threads?.isHeadOfThread(
            widget.timeline.events[index],
            widget.timeline,
          ) ==
          true) {
        return true;
      }
    }

    var offsetIndex = index + 1;

    if (widget.timeline.events.length <= offsetIndex) {
      return false;
    }

    var event = widget.timeline.events[index];
    if (event is! TimelineEventMessage &&
        event is! TimelineEventEmote &&
        event is! TimelineEventSticker) {
      return false;
    }

    if (widget.timeline.events[index].originServerTs.toLocal().day !=
        widget.timeline.events[offsetIndex].originServerTs.toLocal().day) {
      return true;
    }

    if (widget.timeline.events[index].originServerTs
            .difference(widget.timeline.events[offsetIndex].originServerTs)
            .inHours >
        2)
      return true;

    return false;
  }

  @override
  void update(int newIndex) {
    if (!mounted) {
      return;
    }

    // The event view used to be refreshed imperatively here, through
    // `eventKey`, in a post-frame callback. It now takes `index` as a
    // parameter and reacts in its own didUpdateWidget, so this rebuild is
    // enough - and the event view no longer carries a GlobalKey that could be
    // reparented mid-layout (BUG-298).
    index = newIndex;
    setState(() {
      eventUpdateRevision++;
      loadState(newIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineEventsBuilt += 1;

    if (redacted) return Container();
    var result = buildEvent();

    if (result == null) {
      return Container();
    }

    if (status == TimelineEventStatus.sending ||
        status == TimelineEventStatus.error) {
      result = Opacity(opacity: 0.5, child: result);
    }

    if (status == TimelineEventStatus.error) {
      result = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Icon(
              Icons.error,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          Expanded(child: result),
        ],
      );
    }

    if (Layout.desktop) {
      result = MouseRegion(
        onEnter: (_) => widget.onEventHovered?.call(eventId),
        child: result,
      );
    }

    if (Layout.mobile) {
      result = InkWell(
        onLongPress: () {
          var event = widget.timeline.tryGetEvent(eventId);
          if (event == null) {
            return;
          }

          showModalBottomSheet(
            showDragHandle: false,
            isScrollControlled: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            context: context,
            builder: (context) => TimelineEventMenuDialog(
              event: event,
              timeline: widget.timeline,
              menu: TimelineEventMenu(
                timeline: widget.timeline,
                isThreadTimeline: widget.isThreadTimeline,
                event: event,
                setEditingEvent: widget.setEditingEvent,
                setReplyingEvent: widget.setReplyingEvent,
                onActionFinished: () => Navigator.of(context).pop(),
              ),
            ),
          );
        },
        child: result,
      );
    }

    if (Layout.desktop) {
      var event = widget.timeline.tryGetEvent(eventId);
      if (event != null) {
        var menu = TimelineEventMenu(
          timeline: widget.timeline,
          event: event,
          setEditingEvent: widget.setEditingEvent,
          setReplyingEvent: widget.setReplyingEvent,
        );
        result = AdaptiveContextMenu(
          items: [
            if (menu.addReactionAction != null)
              ContextMenuItem(
                text: "Add Reaction",
                customBuilder: (context, onClick) => Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (
                        var i = 0;
                        i < RecentEmoticonComponent.quickReactionCount &&
                            i < menu.quickReactions.length;
                        i++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final emote = menu.quickReactions[i];
                            return _TimelineQuickReactionButton(
                              label: emote.shortcode == null
                                  ? genericQuickReactionSemanticLabel
                                  : quickReactionSemanticLabel(
                                      emote.shortcode!,
                                    ),
                              onPressed: () {
                                widget.timeline.room.addReaction(event, emote);
                                onClick();
                              },
                              child: EmojiWidget(emote),
                            );
                          },
                        ),
                      ],
                      tiamat.IconButton(
                        icon: Icons.add_reaction,
                        size: 24,
                        semanticLabel: CommonStrings.promptAddReaction,
                        tooltip: CommonStrings.promptAddReaction,
                        onPressed: () {
                          onClick();

                          AdaptiveDialog.show(
                            context,
                            builder: (newContext) {
                              return SizedBox(
                                width: 500,
                                height: 500,
                                child: menu
                                    .addReactionAction!
                                    .secondaryMenuBuilder!
                                    .call(newContext, () {
                                      Navigator.of(newContext).pop();
                                    }),
                              );
                            },
                          );
                          menu.addReactionAction?.action?.call(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            for (var i in menu.primaryActions)
              ContextMenuItem(
                text: i.name,
                icon: i.icon,
                onPressed: () => i.action?.call(context),
              ),
            for (var i in menu.secondaryActions)
              ContextMenuItem(
                text: i.name,
                icon: i.icon,
                onPressed: () => i.action?.call(context),
              ),
          ],
          child: result,
        );
      }
    }

    // Unconditional, like the Stack below (BUG-298). `select()` sets both
    // `selected` and `timelineLayerLink`, so on every hover these two wrappers
    // appeared and disappeared together over the whole event subtree, and each
    // one re-inflated everything under it.
    result = ColoredBox(
      color: selected
          ? Theme.of(context).hoverColor.withAlpha(5)
          : Colors.transparent,
      child: result,
    );

    result = DecoratedBox(
      decoration: highlighted
          ? highlightDecoration(Theme.of(context).colorScheme)
          : const BoxDecoration(),
      child: result,
    );

    // This Stack is unconditional on purpose (BUG-298).
    //
    // It only exists to hold a zero-size anchor for the hover menu, but adding
    // and removing it as `timelineLayerLink` comes and goes changes the widget
    // type at this slot. That deactivates and re-inflates everything below -
    // including the `eventKey`-keyed event view - so the event's subtree gets
    // *reparented* rather than updated. When that happens mid-layout, any
    // OverlayPortal inside it (a custom emoji's tooltip, say) re-attaches to
    // its _RenderTheater and mutates layout in flight, killing the surface.
    //
    // Keeping the Stack always present keeps the tree shape stable; only the
    // leaf anchor toggles, and it owns nothing.
    result = Stack(
      alignment: Alignment.topRight,
      children: [
        if (timelineLayerLink != null)
          CompositedTransformTarget(
            link: timelineLayerLink!,
            child: const SizedBox(),
          )
        else
          const SizedBox(),
        result,
      ],
    );

    if (isThreadRootEvent) {
      result = Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerLow.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.36),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.forum_rounded,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: tiamat.Text.labelEmphasised(
                        originalThreadMessageLabel,
                        color: Theme.of(context).colorScheme.primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: Layout.mobile ? 142 : 96,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                  child: result,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (showDateSeperator) {
      result = Column(
        children: [
          TimelineEventDateTimeMarker(time: time),
          result,
        ],
      );
    }

    return result;
  }

  Widget? buildEvent() {
    if (redacted) {
      return null;
    }

    if (widget.singleEvent == false &&
        widget.isThreadTimeline == false &&
        isThreadReply) {
      return null;
    }

    if (_widgetType == TimelineEventWidgetDisplayType.message)
      return TimelineEventViewMessage(
        timeline: widget.timeline,
        isThreadTimeline: widget.isThreadTimeline,
        suppressBubble: isThreadRootEvent,
        detailed: widget.showDetailed || selected,
        onReadReceiptsTapped: onReadReceiptsTapped,
        readReceipts: readReceipts,
        overrideShowSender: widget.singleEvent || showDateSeperator,
        jumpToEvent: widget.jumpToEvent,
        previewMedia: widget.previewMedia,
        setEditingEvent: widget.setEditingEvent,
        setReplyingEvent: widget.setReplyingEvent,
        index: index,
        updateRevision: eventUpdateRevision,
      );

    if (_widgetType == TimelineEventWidgetDisplayType.generic)
      return TimelineEventViewGeneric(
        timeline: widget.timeline,
        index: index,
        room: widget.timeline.room,
        readReceipts: readReceipts,
        onReadReceiptsTapped: onReadReceiptsTapped,
      );

    if (_widgetType == TimelineEventWidgetDisplayType.poll) {
      return TimelineEventViewPoll(
        index: index,
        timeline: widget.timeline,
        updateRevision: eventUpdateRevision,
      );
    }

    if (_widgetType == TimelineEventWidgetDisplayType.hidden) {
      final showTimelineDiagnostics = shouldShowTimelineDiagnostics(
        developerMode: preferences.developerMode.value,
        developerUiHidden: preferences.hideDeveloperSettings.value,
        showTimelineDiagnostics: preferences.showTimelineDiagnostics.value,
      );

      if (!showTimelineDiagnostics) {
        return null;
      }

      return TimelineEventViewGeneric(
        timeline: widget.timeline,
        room: widget.timeline.room,
        index: index,
        onReadReceiptsTapped: onReadReceiptsTapped,
        readReceipts: readReceipts,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void deselect() {
    if (mounted)
      setState(() {
        selected = false;
        timelineLayerLink = null;
      });
  }

  @override
  void select(LayerLink link) {
    if (mounted)
      setState(() {
        selected = true;
        timelineLayerLink = link;
      });
  }

  /// Decoration for the row a jump-to-message landed on.
  ///
  /// Two constraints, and they pull against each other.
  ///
  /// The fill must be TRANSLUCENT. A custom message background image is painted
  /// behind the whole timeline, so the opaque `surfaceContainer` this used to
  /// carry did not tint the highlighted row - it replaced the user's wallpaper
  /// for that row with the default theme colour.
  ///
  /// The fill must come off the SURFACE RAMP, not from `primary`. Every colour
  /// role here is independently user-authored in a custom theme
  /// (`previewThemeForCustomDraft`) and nothing in this app validates contrast,
  /// so a `primary` wash under body text has no bound anyone can reason about.
  /// The surface roles at least share the job `onSurface` text is already read
  /// against. `surfaceContainerHighest` at 0.4 lands within a few thousandths
  /// of the old opaque fill's luminance delta in every bundled theme while
  /// letting 60% of the wallpaper through.
  ///
  /// The accent border stays fully opaque: it is the part of the cue that
  /// survives any wallpaper, which is why the fill does not have to be strong.
  static BoxDecoration highlightDecoration(ColorScheme colors) => BoxDecoration(
    border: Border(left: BorderSide(color: colors.primary, width: 3)),
    color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
  );

  void setHighlighted(bool value) {
    if (mounted)
      setState(() {
        highlighted = value;
      });
  }

  onReadReceiptsTapped() {
    AdaptiveDialog.show(
      context,
      title: "Read Receipts",
      builder: (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: readReceipts
              .map(
                (i) => UserPanel(
                  userId: i,
                  client: widget.timeline.client,
                  contextRoom: widget.timeline.room,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _TimelineQuickReactionButton extends StatelessWidget {
  const _TimelineQuickReactionButton({
    required this.label,
    required this.child,
    required this.onPressed,
  });

  final String label;
  final Widget child;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return tiamat.Tooltip(
      text: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        onTap: onPressed,
        child: SizedBox(
          height: 30,
          width: 30,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              excludeFromSemantics: true,
              onTap: onPressed,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
