import 'dart:async';

import 'package:intergalactic/client/components/message_effects/message_effect_component.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_overlay.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_diagnostics_visibility.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MobileChatScrollPhysics extends ClampingScrollPhysics {
  const MobileChatScrollPhysics({super.parent});

  @override
  MobileChatScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return MobileChatScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 2.0;

  @override
  double get minFlingVelocity => 18.0;
}

class RoomTimelineWidgetView extends StatefulWidget {
  const RoomTimelineWidgetView({
    required this.timeline,
    this.markAsRead,
    this.onViewScrolled,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onAttachedToBottom,
    this.isThreadTimeline = false,
    this.bottomInset = 0,
    this.keyboardVisible = false,
    this.autoLoadTimelineBoundaries = true,
    this.showTimelineBoundaryLoadingIndicators = true,
    this.onHistoryPageLoaded,
    super.key,
  });
  final Timeline timeline;
  final Function(TimelineEvent event)? markAsRead;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function()? onAttachedToBottom;
  final bool isThreadTimeline;
  final double bottomInset;
  final bool keyboardVisible;
  final bool autoLoadTimelineBoundaries;
  final bool showTimelineBoundaryLoadingIndicators;
  final Future<bool> Function(Timeline timeline)? onHistoryPageLoaded;

  final Function({
    required double offset,
    required double maxScrollExtent,
    required double minScrollExtent,
  })?
  onViewScrolled;

  @override
  State<RoomTimelineWidgetView> createState() => RoomTimelineWidgetViewState();
}

class RoomTimelineWidgetViewState extends State<RoomTimelineWidgetView> {
  // The IME already animates viewInsets on mobile. Follow inset changes
  // directly so timeline clearance and the composer stay in sync.
  static const bottomInsetAnimationDuration = Duration.zero;
  static const bottomInsetAnimationCurve = Curves.linear;
  static const historyDecryptRecoveryMinLoaderDuration = Duration(
    milliseconds: 240,
  );

  int numBuilds = 0;

  int recentItemsCount = 0;
  int get historyItemsCount => timeline.events.length - recentItemsCount;

  bool firstFrame = true;
  bool animatingToBottom = false;

  late ScrollController controller;
  late List<(GlobalKey, String)> eventKeys;
  late Timeline timeline;

  /// Stable for the widget's lifetime. It is deliberately never reassigned -
  /// changing a `GlobalKey`'s identity discards the element it names, and for
  /// this key that means the whole timeline subtree. See BUG-298.
  final GlobalKey scrollViewKey = GlobalKey();
  GlobalKey centerKey = GlobalKey();
  GlobalKey recentItemsKey = GlobalKey();
  GlobalKey overlayKey = GlobalKey();
  GlobalKey stackKey = GlobalKey();

  LayerLink selectedEventLayerLink = LayerLink();
  SelectableEventViewWidget? selectedEventView;

  String? highlightedEventId;
  TimelineViewEntryState? highlightedEventState;
  GlobalKey? highlightedEventOffstageKey;
  int? highlightedEventOffstageIndex;
  List<StreamSubscription>? subscriptions;

  bool wasLastScrollAttachedToBottom = false;
  bool loading = false;
  int neutralRestoreGeneration = 0;

  bool get attachedToBottom => controller.hasClients
      ? controller.offset - controller.positions.first.minScrollExtent < 50 ||
            animatingToBottom
      : true;

  bool get showTimelineDiagnostics => shouldShowTimelineDiagnostics(
    developerMode: preferences.developerMode.value,
    developerUiHidden: preferences.hideDeveloperSettings.value,
    showTimelineDiagnostics: preferences.showTimelineDiagnostics.value,
  );

  bool isLoadingFuture = false;
  bool isLoadingHistory = false;
  bool isLoadingHistoryPage = false;
  bool isHistoryDecryptRecoveryPending = false;

  /// How many consecutive automatic history loads produced no extra scroll
  /// extent before automatic loading gives up and waits for the user.
  ///
  /// Auto-loading is driven by scroll extent, and an event the timeline cannot
  /// display renders as a zero-height `Container` - so a page made entirely of
  /// them leaves the boundary condition true. `loadMoreHistory` posts
  /// `onScroll` to the next frame, so that is a self-driving loop: one network
  /// fetch per frame, indefinitely, while the visible list never grows.
  ///
  /// A call room is the case that made this visible. Every participant
  /// republishes `org.matrix.msc3401.call.member` every 25 seconds, none of it
  /// is displayable, and a measured run did 30 loads in 30 frames.
  ///
  /// This is a circuit breaker, not a fix for the underlying noise: it stops
  /// the runaway, and a scroll gesture re-arms it so the user can still reach
  /// older history.
  static const int _maxUnproductiveHistoryLoads = 3;

  int _unproductiveHistoryLoads = 0;
  double? _extentBeforeHistoryLoad;
  int? _displayableHistoryRowsBeforeLoad;

  /// Displayable rows in the HISTORY portion only - index [recentItemsCount]
  /// onward - as opposed to every event the timeline holds.
  ///
  /// Scoped to history deliberately. Counting the whole list lets a live
  /// message arriving during `await loadMoreHistory()` look like history
  /// progress, which resets the breaker on a page that fetched nothing but
  /// hidden events. An active call room produces exactly that traffic, so the
  /// wider count would defeat the breaker in the one case it exists for.
  ///
  /// The slice is stable under live arrivals: a new event at index 0 increments
  /// `recentItemsCount` as well as the length, so the history portion is
  /// unchanged and only a real history page can move this number.
  ///
  /// Walked per history load rather than per frame - three times before the
  /// breaker trips - so the linear scan is not on a hot path.
  int _displayableHistoryRowCount() {
    final room = timeline.room;
    final events = timeline.events;
    var count = 0;
    for (var i = recentItemsCount; i < events.length; i++) {
      if (TimelineViewEntryState.eventToDisplayType(events[i], room: room) !=
          TimelineEventWidgetDisplayType.hidden) {
        count++;
      }
    }
    return count;
  }

  bool get isHistoryBoundaryBusy =>
      timeline.isLoadingHistory ||
      isLoadingHistoryPage ||
      isHistoryDecryptRecoveryPending;

  bool get showHistoryLoadingIndicator =>
      widget.showTimelineBoundaryLoadingIndicators &&
      (isLoadingHistory ||
          isLoadingHistoryPage ||
          isHistoryDecryptRecoveryPending);

  bool get showFutureLoadingIndicator =>
      widget.showTimelineBoundaryLoadingIndicators && isLoadingFuture;

  MessageEffectComponent? effects;
  StreamSubscription<String>? _jumpToEventSubscription;
  VoidCallback? _removeInboxJumpTarget;
  RoomTimelineLease? _jumpTimelineLease;

  @override
  void initState() {
    effects = widget.timeline.client.getComponent<MessageEffectComponent>();

    initFromTimeline(widget.timeline);

    controller = ScrollController(initialScrollOffset: -999999);
    _jumpToEventSubscription = EventBus.jumpToEvent.stream.listen(jumpToEvent);
    WidgetsBinding.instance.addPostFrameCallback(onAfterFirstFrame);
    super.initState();
  }

  void initFromTimeline(Timeline timeline) {
    if (subscriptions != null) {
      for (var sub in subscriptions!) {
        sub.cancel();
      }
    }

    isLoadingFuture = false;
    isLoadingHistory = false;
    isLoadingHistoryPage = false;
    isHistoryDecryptRecoveryPending = false;

    // The breaker counts consecutive unproductive loads against ONE timeline.
    // A different timeline is a different history, so carrying the count over
    // would arrive pre-tripped - a jump-to-event or a room switch could land
    // on a timeline whose automatic loading was already disabled by the
    // previous one, with nothing on screen to explain it.
    _unproductiveHistoryLoads = 0;
    _extentBeforeHistoryLoad = null;
    _displayableHistoryRowsBeforeLoad = null;

    this.timeline = timeline;
    _removeInboxJumpTarget?.call();
    // Inbox jump targets are keyed by account and room only, so a thread
    // timeline for a room would register under the same key as that room's main
    // timeline and displace it - and the two are mounted at the same time
    // whenever the thread side panel is open. An Inbox jump names an event in
    // the room, not in one thread, so only the main timeline may claim it.
    _removeInboxJumpTarget = widget.isThreadTimeline
        ? null
        : EventBus.registerInboxJumpTarget(
            clientIdentifier: timeline.room.client.identifier,
            roomIdentifier: timeline.room.identifier,
            onJump: jumpToEvent,
          );
    recentItemsCount = timeline.events.length;
    var receipts = timeline.room.getComponent<ReadReceiptComponent>();
    subscriptions = [
      timeline.onEventAdded.stream.listen(onEventAdded),
      timeline.onChange.stream.listen(onEventChanged),
      timeline.onRemove.stream.listen(onEventRemoved),
      timeline.onLoadingStatusChanged.listen(onLoadingStatusChanged),
      timeline.room.onUpdate.listen(onRoomUpdated),
      if (receipts != null)
        receipts.onReadReceiptsUpdated.listen(onReadReceiptUpdated),
    ];

    if (preferences.messageEffectsEnabled.value) {
      for (int i = 0; i < 5; i++) {
        if (i >= timeline.events.length) break;

        var event = timeline.events[i];
        if (effects?.hasEffect(event) == true) {
          effects?.doEffect(event);
          break;
        }
      }
    }

    eventKeys = _newEventKeys();
  }

  List<(GlobalKey, String)> _newEventKeys() => List.generate(
    timeline.events.length,
    (index) => (
      GlobalKey(debugLabel: timeline.events[index].eventId),
      timeline.events[index].eventId,
    ),
    growable: true,
  );

  @override
  void dispose() {
    for (var element in subscriptions!) {
      element.cancel();
    }
    _jumpToEventSubscription?.cancel();
    _removeInboxJumpTarget?.call();
    _releaseJumpTimelineLease();

    super.dispose();
  }

  void _releaseJumpTimelineLease() {
    final lease = _jumpTimelineLease;
    _jumpTimelineLease = null;
    if (lease != null) {
      unawaited(lease.close());
    }
  }

  @override
  void didUpdateWidget(covariant RoomTimelineWidgetView oldWidget) {
    final wasAttachedToBottom = controller.hasClients && attachedToBottom;
    final keyboardOpened = !oldWidget.keyboardVisible && widget.keyboardVisible;
    super.didUpdateWidget(oldWidget);

    if (keyboardOpened && wasAttachedToBottom) {
      restoreNeutralPosition(animated: true);
    } else if (oldWidget.bottomInset != widget.bottomInset &&
        wasAttachedToBottom) {
      restoreNeutralPosition(animated: false);
    }
  }

  void onEventAdded(int index) {
    eventKeys.insert(index, (
      GlobalKey(debugLabel: timeline.events[index].eventId),
      timeline.events[index].eventId,
    ));

    // A photo stack is derived from neighbouring timeline rows. Rows before
    // an insertion retain their index, so the normal shifted-row refresh below
    // does not notify a mounted stack anchor when an older photo joins its
    // group. Refresh those mounted rows too; a newly inserted row has no state
    // yet and will receive the current grouping when the sliver builds it.
    for (var timelineIndex = 0; timelineIndex < index; timelineIndex++) {
      final state = eventKeys[timelineIndex].$1.currentState;
      if (state is TimelineEventViewWidget) {
        (state as TimelineEventViewWidget).update(timelineIndex);
      }
    }

    // Sliver child keys keep mounted entries alive when a new event shifts
    // their timeline indexes. Update those states before the slivers rebuild
    // so attachment subtrees are not reused for the newly inserted event.
    for (
      var timelineIndex = index + 1;
      timelineIndex < eventKeys.length;
      timelineIndex++
    ) {
      final state = eventKeys[timelineIndex].$1.currentState;
      if (state is TimelineEventViewWidget) {
        (state as TimelineEventViewWidget).update(timelineIndex);
      }
    }

    if (index == 0 || index < recentItemsCount) {
      recentItemsCount += 1;
    }

    if (index == 0) {
      final isOwnEvent =
          timeline.events[index].senderId ==
          timeline.room.client.self?.identifier;

      if (attachedToBottom) {
        scrollToBottom();

        widget.markAsRead?.call(timeline.events[0]);
      } else if (Layout.mobile && isOwnEvent) {
        restoreNeutralPosition(animated: true);
        widget.markAsRead?.call(timeline.events[0]);
      }

      if (preferences.messageEffectsEnabled.value) {
        effects?.doEffect(timeline.events[index]);
      }
    }

    setState(() {});
  }

  void onEventChanged(int index) {
    var event = timeline.events[index];
    var existing = eventKeys[index];
    eventKeys[index] = (existing.$1, event.eventId);

    var key = eventKeys.firstWhere((element) => element.$2 == event.eventId);

    assert(event.eventId == key.$2);

    var state = key.$1.currentState;

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }

    if (index == 0) {
      if (attachedToBottom) {
        scrollToBottom();

        widget.markAsRead?.call(timeline.events[0]);
      }
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.animateTo(
        controller.position.minScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutExpo,
      );
    });
  }

  void restoreNeutralPosition({required bool animated}) {
    final generation = neutralRestoreGeneration += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }

      final targetOffset = controller.position.minScrollExtent;
      if ((controller.offset - targetOffset).abs() < 1) {
        controller.jumpTo(targetOffset);
        onScroll();
        scheduleNeutralPositionSettle(generation);
        return;
      }

      if (!animated || bottomInsetAnimationDuration == Duration.zero) {
        controller.jumpTo(targetOffset);
        onScroll();
        scheduleNeutralPositionSettle(generation);
        return;
      }

      setState(() {
        animatingToBottom = true;
      });
      controller
          .animateTo(
            targetOffset,
            duration: bottomInsetAnimationDuration,
            curve: bottomInsetAnimationCurve,
          )
          .then((_) {
            if (mounted && controller.hasClients) {
              setState(() {
                animatingToBottom = false;
              });
              onScroll();
              scheduleNeutralPositionSettle(generation);
            }
          });
    });
  }

  Future<void> scheduleNeutralPositionSettle(int generation) async {
    await Future<void>.delayed(
      bottomInsetAnimationDuration + const Duration(milliseconds: 32),
    );
    if (!mounted || generation != neutralRestoreGeneration) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != neutralRestoreGeneration ||
          !controller.hasClients) {
        return;
      }

      controller.jumpTo(controller.position.minScrollExtent);
      onScroll();
    });
  }

  void onEventRemoved(int index) {
    if (index < recentItemsCount) {
      recentItemsCount -= 1;
    }

    var removed = eventKeys.removeAt(index);

    assert(timeline.events[index].eventId == removed.$2);

    setState(() {});
  }

  void onRoomUpdated(void event) {
    for (int i = 0; i < eventKeys.length && i < timeline.events.length; i++) {
      final state = eventKeys[i].$1.currentState;
      if (state is TimelineEventViewWidget) {
        (state as TimelineEventViewWidget).update(i);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onAfterFirstFrame(_) {
    if (timeline.events.isNotEmpty) {
      widget.markAsRead?.call(timeline.events.first);
    }

    if (controller.hasClients) {
      // Land on the latest message without rebuilding the scroll view.
      //
      // This used to build a second `ScrollController` at the measured extent
      // and swap `scrollViewKey` for a fresh `GlobalKey`, because
      // `initialScrollOffset` only takes effect when a new `ScrollPosition` is
      // created - and that only happens if the element is discarded. Swapping
      // the key is what discarded it.
      //
      // The cost was BUG-298: that swap tore down and re-inflated the entire
      // timeline subtree, every `Tooltip` in it included. A tooltip is an
      // `OverlayPortal` (`RawTooltip` -> `OverlayPortal.overlayChildLayoutBuilder`),
      // so re-inflating one re-attaches a deferred child to the enclosing
      // `_RenderTheater`, and doing that while a `_RenderLayoutBuilder` is
      // mid-`performLayout` is the assertion that killed the timeline.
      //
      // Jumping the existing position needs no new position, so no new key and
      // no teardown. `animateAndSnapToBottom` already relies on exactly this
      // (`controller.jumpTo(controller.position.minScrollExtent)` in its
      // post-frame callback), so the landing behaviour is not novel here.
      //
      // Still keyed off `minScrollExtent` rather than `0.0`: with `reverse:
      // true` and a `center:` sliver, and the mobile composer spacer sitting
      // before the centre, the neutral position can legitimately be below zero.
      controller.jumpTo(controller.position.minScrollExtent);
      controller.addListener(onScroll);
      widget.onAttachedToBottom?.call();
      setState(() {
        firstFrame = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onScroll();
    });
  }

  void onScroll() {
    if (!controller.hasClients) {
      return;
    }

    widget.onViewScrolled?.call(
      offset: controller.offset,
      maxScrollExtent: controller.position.maxScrollExtent,
      minScrollExtent: controller.position.minScrollExtent,
    );

    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(attachedToBottom);

    if (wasLastScrollAttachedToBottom == false && attachedToBottom) {
      widget.onAttachedToBottom?.call();
    }

    wasLastScrollAttachedToBottom = attachedToBottom;

    double loadingThreshold = 500;

    // When the history items are empty, the sliver takes up exactly the height of the viewport, so we should use that height instead
    if (historyItemsCount == 0) {
      var renderBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        loadingThreshold = renderBox.size.height;
      }
    }

    if (widget.autoLoadTimelineBoundaries &&
        controller.offset >
            controller.position.maxScrollExtent - loadingThreshold &&
        !isHistoryBoundaryBusy &&
        _unproductiveHistoryLoads < _maxUnproductiveHistoryLoads &&
        timeline.canLoadHistory) {
      unawaited(loadMoreHistory());
    }

    if (widget.autoLoadTimelineBoundaries &&
        controller.offset <
            (controller.position.minScrollExtent + loadingThreshold) &&
        !timeline.isLoadingFuture &&
        timeline.canLoadFuture) {
      timeline.loadMoreFuture();
    }
  }

  Future<void> loadMoreHistory() async {
    if (isHistoryBoundaryBusy) {
      return;
    }
    final historyTimeline = timeline;

    _extentBeforeHistoryLoad = controller.hasClients
        ? controller.position.maxScrollExtent
        : null;
    _displayableHistoryRowsBeforeLoad = _displayableHistoryRowCount();

    if (mounted) {
      setState(() {
        isLoadingHistoryPage = true;
      });
    }

    try {
      await historyTimeline.loadMoreHistory();
      if (!mounted) {
        return;
      }

      final historyRecovery = widget.onHistoryPageLoaded;
      if (historyRecovery != null) {
        final recoveryStartedAt = DateTime.now();
        if (identical(timeline, historyTimeline)) {
          setState(() {
            isHistoryDecryptRecoveryPending = true;
          });
        }

        var retried = false;
        try {
          retried = await historyRecovery(historyTimeline);
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to run timeline history decrypt recovery',
            category: LogCategory.matrix,
            source: 'timeline-history-recovery',
          );
        }

        if (retried && mounted && identical(timeline, historyTimeline)) {
          await _holdHistoryLoaderUntil(recoveryStartedAt);
        }
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to load timeline history',
        category: LogCategory.matrix,
        source: 'timeline-history',
      );
    } finally {
      if (mounted && identical(timeline, historyTimeline)) {
        setState(() {
          isLoadingHistoryPage = false;
          isHistoryDecryptRecoveryPending = false;
          isLoadingHistory = historyTimeline.isLoadingHistory;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _recordHistoryLoadProductivity();
          onScroll();
        });
      }
    }
  }

  /// Judges whether the load that just finished actually bought anything.
  ///
  /// Progress is measured in scroll extent rather than event count on purpose:
  /// the events arrive either way, and the whole defect is that arriving
  /// events can be undisplayable. Extent is what the boundary test reads, so
  /// extent is what has to grow for another automatic load to be justified.
  void _recordHistoryLoadProductivity() {
    final before = _extentBeforeHistoryLoad;
    _extentBeforeHistoryLoad = null;

    if (before == null || !controller.hasClients) {
      return;
    }

    // Extent alone is not sufficient. While the displayable content is still
    // shorter than the viewport there is nothing to scroll, so maxScrollExtent
    // stays put even as real messages arrive - and the breaker would stop
    // automatic loading after three GENUINELY productive loads. That is the
    // opposite of the defect it exists to prevent, and in a call room, where
    // most events are hidden, it is the likely case rather than the corner
    // one: pages arrive carrying one or two visible messages at a time.
    //
    // So a load counts as productive if it bought scroll extent OR put more
    // displayable rows on screen.
    final historyRows = _displayableHistoryRowCount();
    final gainedRows =
        _displayableHistoryRowsBeforeLoad != null &&
        historyRows > _displayableHistoryRowsBeforeLoad!;
    _displayableHistoryRowsBeforeLoad = null;

    if (controller.position.maxScrollExtent > before || gainedRows) {
      _unproductiveHistoryLoads = 0;
      return;
    }

    _unproductiveHistoryLoads++;

    if (_unproductiveHistoryLoads == _maxUnproductiveHistoryLoads) {
      Log.w(
        'Automatic history loading paused after '
        '$_unproductiveHistoryLoads loads that added no scroll extent. The '
        'timeline is receiving events it cannot display; a scroll gesture '
        'will resume it.',
        category: LogCategory.matrix,
        source: 'timeline-history',
      );
    }
  }

  /// Raw wheel/trackpad input, taken before `ScrollPosition` decides whether
  /// the gesture is expressible as a scroll.
  ///
  /// Scrolling toward history is what asks for more of it. Direction is
  /// checked so that scrolling the other way - away from the boundary - does
  /// not re-arm, which would defeat the breaker on a timeline that is simply
  /// noisy.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }

    // NEGATIVE dy is toward older history here, and getting this backwards
    // makes the handler worse than useless - it would ignore the gesture that
    // asks for history and re-arm on the one that walks away from it.
    //
    // The list is `reverse: true` (see the CustomScrollView below), and
    // Scrollable._pointerSignalEventDelta negates the raw delta for a reversed
    // axis before applying it (scrollable.dart:950). So the raw dy that ends up
    // increasing the offset - scrolling back through history - is the negative
    // one.
    if (event.scrollDelta.dy >= 0) {
      return;
    }

    _rearmHistoryLoadingOnUserScroll();
  }

  /// A deliberate scroll is the signal that the user still wants older
  /// history, so it re-arms automatic loading after the circuit breaker.
  void _rearmHistoryLoadingOnUserScroll() {
    if (_unproductiveHistoryLoads == 0) {
      return;
    }
    _unproductiveHistoryLoads = 0;

    // Re-check immediately rather than waiting for the next scroll callback.
    // Clearing the counter alone only takes effect the next time something
    // happens to call onScroll(), so a user who scrolled once and stopped -
    // exactly what someone does when they reach the top and wait - would
    // re-arm the breaker and still see nothing load.
    onScroll();
  }

  Future<void> _holdHistoryLoaderUntil(DateTime recoveryStartedAt) async {
    final elapsed = DateTime.now().difference(recoveryStartedAt);
    final remaining = historyDecryptRecoveryMinLoaderDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  bool onScrollNotification(ScrollNotification notification) {
    final userDragged =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;

    // Re-arming must NOT require `dragDetails`. Only a drag-backed activity
    // attaches them - `ScrollDragController` overrides
    // dispatchScrollStartNotification to do so, and nothing else does. A mouse
    // wheel goes through `ScrollPosition.pointerScroll`, which calls
    // `didStartScroll()` on an idle activity, so it raises a
    // ScrollStartNotification with `dragDetails == null`.
    //
    // Requiring a drag therefore left the circuit breaker latched forever for
    // anyone scrolling with a wheel, which is most desktop users - and desktop
    // is where the runaway was reported. Smoke-tested 2026-08-21: the runaway
    // stopped and older messages then never loaded at all.
    //
    // Any scroll start counts, including a programmatic jumpTo/animateTo from
    // jump-to-event. That over-triggers, and deliberately so: a false re-arm
    // costs at most _maxUnproductiveHistoryLoads further loads before the
    // breaker trips again, while a missed re-arm strands the user with
    // unreachable history. The asymmetry decides it.
    final userScrolled = notification is ScrollStartNotification;

    if (userScrolled) {
      _rearmHistoryLoadingOnUserScroll();
    }

    if (!Layout.mobile) {
      return false;
    }

    if (userDragged) {
      neutralRestoreGeneration += 1;
    }

    return false;
  }

  Widget animatedBottomInset(double height) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: height),
      duration: bottomInsetAnimationDuration,
      curve: bottomInsetAnimationCurve,
      builder: (context, value, child) => SizedBox(height: value),
    );
  }

  void animateAndSnapToBottom() {
    if (!controller.hasClients) {
      return;
    }

    controller.position.hold(() {});

    setState(() {
      initFromTimeline(widget.timeline);
      _releaseJumpTimelineLease();
      animatingToBottom = true;
    });

    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(true);
    widget.onAttachedToBottom?.call();

    controller
        .animateTo(
          controller.position.minScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutExpo,
        )
        .then((_) {
          if (!mounted || !controller.hasClients) {
            return;
          }

          // The entries about to be disposed include whatever was selected,
          // and the secondary menu outlives them - it stayed on screen
          // pointing at a widget that no longer exists. Cleared before the
          // rebuild rather than after, so nothing repaints against the old
          // keys.
          selectedEventView = null;
          highlightedEventState = null;
          (overlayKey.currentState as TimelineOverlayState?)?.clearSelection();

          setState(() {
            // Moving an entry with the same GlobalKey between the two sliver
            // delegates can reparent active media overlays. Recreate the
            // entries so the old delegate disposes them before history builds.
            eventKeys = _newEventKeys();
            recentItemsCount = 0;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !controller.hasClients) {
              return;
            }

            // The mobile composer spacer lives before the center sliver, so the
            // latest-message neutral position can remain below zero after the
            // recent/future split is collapsed.
            controller.jumpTo(controller.position.minScrollExtent);
            setState(() {
              animatingToBottom = false;
            });
            onScroll();
          });
        });
  }

  void eventHovered(String eventId) {
    var key = eventKeys.firstWhere((element) => element.$2 == eventId);

    assert(eventId == key.$2);

    var state = key.$1.currentState;

    if (state is SelectableEventViewWidget) {
      var selectable = state as SelectableEventViewWidget;

      if (selectable != selectedEventView) {
        if (BuildConfig.DEBUG || kDebugMode) {
          // Debug level, not warning: this runs on pointer movement, so one
          // hovered message produced one warning and buried the real ones.
          Log.d(
            'overlay_lifecycle transition=timeline_entry_selected',
            category: LogCategory.media,
            source: 'overlay-lifecycle',
          );
        }
        deselectEvent();

        selectable.select(selectedEventLayerLink);
        selectedEventView = selectable;

        var overlayState = overlayKey.currentState as TimelineOverlayState?;
        var event = timeline.tryGetEvent(eventId)!;
        overlayState?.setMenu(
          TimelineEventMenu(
            timeline: timeline,
            isThreadTimeline: widget.isThreadTimeline,
            event: event,
            setEditingEvent: (event) => widget.setEditingEvent?.call(event),
            setReplyingEvent: (event) => widget.setReplyingEvent?.call(event),
          ),
        );
      }
    } else {
      Log.w("Failed to get selectable state");
    }
  }

  void deselectEvent() {
    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.clearSelection();

    selectedEventView?.deselect();
    selectedEventView = null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.bottomInset.clamp(0.0, double.infinity);
    final recentSliverChildCount = recentItemsCount + (bottomInset > 0 ? 1 : 0);

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onExit: (_) => deselectEvent(),
        child: ClipRect(
          child: Stack(
            key: stackKey,
            children: [
              Offstage(
                offstage: firstFrame,
                child: Listener(
                  // A wheel does not always reach onScrollNotification.
                  // ScrollPosition.pointerScroll clamps its target to the
                  // scroll range and returns WITHOUT dispatching anything when
                  // that target equals the current pixels - which is exactly
                  // the case the circuit breaker leaves behind: parked at the
                  // history boundary, or a timeline whose displayable content
                  // is shorter than the viewport so the range is zero.
                  //
                  // So the re-arm cannot rely on notifications alone. This
                  // sees the raw signal first, and is the only path that works
                  // when there is no scrollable range at all.
                  onPointerSignal: _onPointerSignal,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: onScrollNotification,
                    child: CustomScrollView(
                      // One stable key for the life of the widget. This was
                      // `firstFrame ? firstFrameScrollViewKey : scrollViewKey` -
                      // a deliberate key-identity swap used to force a rebuild,
                      // and the BUG-298 teardown. `firstFrame` still gates the
                      // `Offstage` above, which is what actually hides the
                      // unpositioned first frame.
                      key: scrollViewKey,
                      controller: controller,
                      physics: Layout.mobile
                          ? const MobileChatScrollPhysics()
                          : null,
                      keyboardDismissBehavior: Layout.mobile
                          ? ScrollViewKeyboardDismissBehavior.manual
                          : ScrollViewKeyboardDismissBehavior.onDrag,
                      reverse: true,
                      center: centerKey,
                      slivers: <Widget>[
                        if (showFutureLoadingIndicator)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              childCount: 1,
                              (BuildContext context, int index) {
                                return const SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                            ),
                          ),
                        SliverList(
                          key: recentItemsKey,
                          // Recent Items
                          delegate: SliverChildBuilderDelegate(
                            childCount: recentSliverChildCount,
                            addAutomaticKeepAlives: false,
                            (BuildContext context, int sliverIndex) {
                              if (bottomInset > 0 &&
                                  sliverIndex == recentItemsCount) {
                                return animatedBottomInset(bottomInset);
                              }

                              int timelineIndex =
                                  recentItemsCount - sliverIndex - 1;
                              numBuilds += 1;

                              var key = eventKeys[timelineIndex];
                              assert(
                                key.$2 ==
                                    timeline.events[timelineIndex].eventId,
                              );

                              return Container(
                                alignment: Alignment.center,
                                color:
                                    showTimelineDiagnostics && BuildConfig.DEBUG
                                    ? Colors.blue[200 + sliverIndex % 4 * 100]!
                                          .withAlpha(30)
                                    : null,
                                child: TimelineViewEntry(
                                  key: key.$1,
                                  timeline: timeline,
                                  onEventHovered: eventHovered,
                                  setEditingEvent: widget.setEditingEvent,
                                  setReplyingEvent: widget.setReplyingEvent,
                                  isThreadTimeline: widget.isThreadTimeline,
                                  highlightedEventId: highlightedEventId,
                                  previewMedia:
                                      widget.timeline.room.shouldPreviewMedia,
                                  jumpToEvent: jumpToEvent,
                                  initialIndex: timelineIndex,
                                ),
                              );
                            },
                            findChildIndexCallback: (key) {
                              var timelineIndex = eventKeys.indexWhere(
                                (element) => element.$1 == key,
                              );
                              if (timelineIndex == -1) {
                                Log.w(
                                  "Failed to get timeline index for key: $timelineIndex",
                                );
                                return null;
                              }

                              return recentItemsCount - timelineIndex - 1;
                            },
                          ),
                        ),
                        SliverList(
                          key: centerKey,
                          // History Items
                          delegate: SliverChildBuilderDelegate(
                            addAutomaticKeepAlives: false,
                            childCount: historyItemsCount,
                            (BuildContext context, int sliverIndex) {
                              numBuilds += 1;
                              // ignore: avoid_print
                              var timelineIndex =
                                  recentItemsCount + sliverIndex;

                              var key = eventKeys[timelineIndex];
                              assert(
                                key.$2 ==
                                    timeline.events[timelineIndex].eventId,
                              );

                              return Container(
                                alignment: Alignment.center,
                                color:
                                    showTimelineDiagnostics && BuildConfig.DEBUG
                                    ? Colors.red[200 + sliverIndex % 4 * 100]!
                                          .withAlpha(30)
                                    : null,
                                child: TimelineViewEntry(
                                  key: key.$1,
                                  onEventHovered: eventHovered,
                                  timeline: timeline,
                                  setEditingEvent: widget.setEditingEvent,
                                  setReplyingEvent: widget.setReplyingEvent,
                                  isThreadTimeline: widget.isThreadTimeline,
                                  highlightedEventId: highlightedEventId,
                                  previewMedia:
                                      widget.timeline.room.shouldPreviewMedia,
                                  jumpToEvent: jumpToEvent,
                                  initialIndex: timelineIndex,
                                ),
                              );
                            },
                            findChildIndexCallback: (key) {
                              var timelineIndex = eventKeys.indexWhere(
                                (element) => element.$1 == key,
                              );
                              if (timelineIndex == -1) {
                                Log.w(
                                  "Failed to get timeline index for key: $timelineIndex",
                                );
                                return null;
                              }

                              return timelineIndex - recentItemsCount;
                            },
                          ),
                        ),
                        if (showHistoryLoadingIndicator)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              childCount: 1,
                              (BuildContext context, int index) {
                                return const SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              TimelineOverlay(
                key: overlayKey,
                showMessageMenu: Layout.desktop,
                jumpToLatest: animateAndSnapToBottom,
                bottomInset: Layout.mobile ? bottomInset : 0,
                link: selectedEventLayerLink,
              ),
              if (highlightedEventOffstageIndex != null &&
                  highlightedEventOffstageKey != null)
                Offstage(
                  offstage: true,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.red,
                        child: TimelineViewEntry(
                          key: highlightedEventOffstageKey,
                          timeline: timeline,
                          isThreadTimeline: widget.isThreadTimeline,
                          initialIndex: highlightedEventOffstageIndex!,
                        ),
                      ),
                    ],
                  ),
                ),
              if (loading)
                Container(
                  color: Colors.black.withAlpha(50),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void jumpToEvent(String eventId) async {
    if (highlightedEventState?.mounted == true) {
      highlightedEventState!.setHighlighted(false);
      highlightedEventState = null;
    }

    int index = timeline.events.indexWhere((event) => event.eventId == eventId);
    if (index == -1) {
      setState(() {
        loading = true;
      });
      late final RoomTimelineLease newLease;
      try {
        newLease = await timeline.room.getTimelineForEventContext(eventId);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to load timeline event context',
          category: LogCategory.matrix,
          source: 'timeline-event-context',
        );
        if (mounted) setState(() => loading = false);
        return;
      }
      final newTimeline = newLease.timeline;

      if (!mounted) {
        await newLease.close();
        return;
      }

      index = newTimeline.events.indexWhere(
        (event) => event.eventId == eventId,
      );

      if (index == -1) {
        await newLease.close();
        if (mounted) {
          setState(() {
            loading = false;
          });
        }
        return;
      }

      final oldLease = _jumpTimelineLease;
      setState(() {
        _jumpTimelineLease = newLease;
        initFromTimeline(newTimeline);
      });
      if (oldLease != null) {
        unawaited(oldLease.close());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      var key = eventKeys[index].$1;
      final state = key.currentState;

      if (state is TimelineViewEntryState) {
        state.setHighlighted(true);
        highlightedEventState = state;
      }

      var boundsSize = stackKey.globalPaintBounds?.height;
      var offset = 0.0;
      if (boundsSize != null) {
        offset = -(boundsSize / 2);
      }

      final eventHeight =
          highlightedEventOffstageKey?.globalPaintBounds?.height;
      if (eventHeight != null) {
        offset += eventHeight / 2;
      }

      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Easing.emphasizedDecelerate,
      );

      if (mounted) {
        setState(() {
          highlightedEventOffstageIndex = null;
          highlightedEventOffstageKey = null;
        });
      }
    });

    setState(() {
      recentItemsCount = index;
      highlightedEventId = timeline.events[index].eventId;
      highlightedEventOffstageIndex = index;
      highlightedEventOffstageKey = GlobalKey();
      loading = false;
    });
  }

  void onLoadingStatusChanged(void event) {
    setState(() {
      isLoadingFuture = timeline.isLoadingFuture;
      isLoadingHistory = timeline.isLoadingHistory;
    });
  }

  void onReadReceiptUpdated(String event) {
    // A receipt routinely names an event this view has not loaded. Remote
    // markers sit wherever that user last read, `m.receipt` replays each
    // user's *previous* marker as well as the new one, and either can be
    // older than the oldest loaded event - or paged out, or redacted, since
    // it was recorded.
    //
    // Both of the old lookups mishandled that. `eventKeys.firstWhere` with no
    // `orElse` threw `Bad state: No element` out of the receipt stream
    // listener, and the `index == -1` branch below it only printed before
    // handing -1 to `update()`, which rebuilt an entry that then indexed the
    // event list out of range. Resolve the row once, and drop the receipt when
    // there is no row to refresh.
    final index = timeline.events.indexWhere((i) => i.eventId == event);

    if (index == -1 || index >= eventKeys.length) {
      return;
    }

    final key = eventKeys[index];

    assert(event == key.$2);

    final state = key.$1.currentState;

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }
  }
}

extension GlobalKeyExtension on GlobalKey {
  Rect? get globalPaintBounds {
    final renderObject = currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      return renderObject!.paintBounds.shift(offset);
    } else {
      return null;
    }
  }
}
