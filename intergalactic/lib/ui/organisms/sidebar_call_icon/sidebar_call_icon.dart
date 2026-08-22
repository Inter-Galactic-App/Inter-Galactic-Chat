import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:intergalactic/ui/organisms/sidebar_call_icon/sidebar_call_icon_view.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';

@visibleForTesting
Future<void> debugCancelSidebarCallIconSubscriptionForTesting(
  StreamSubscription subscription,
) {
  return _cancelSidebarCallIconSubscription(subscription);
}

Future<void> _cancelSidebarCallIconSubscription(
  StreamSubscription subscription,
) async {
  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered sidebar call icon subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'sidebar-call-icon',
    );
  }
}

class SidebarCallIconEntry extends StatefulWidget {
  const SidebarCallIconEntry(
    this.session,
    this.width, {
    this.updateSelection,
    this.onUnhovered,
    super.key,
  });
  final double width;
  final VoipSession session;

  final Function(LayerLink link, VoipSession session, bool showWhileUnhovered)?
  updateSelection;

  final Function()? onUnhovered;

  @override
  State<SidebarCallIconEntry> createState() => _SidebarCallIconEntryState();
}

class _SidebarCallIconEntryState extends State<SidebarCallIconEntry>
    with TickerProviderStateMixin {
  Room? room;
  final LayerLink link = LayerLink();
  late List<StreamSubscription> subs;

  /// Whether the pointer is currently over this entry.
  ///
  /// Tracked because `didUpdateWidget` needs it: a session swap under a
  /// stationary pointer produces no enter event, so nothing would tell the
  /// parent that the hover controls are now pointing at a dead session.
  bool _hovered = false;
  Timer? statUpdateTimer;
  late AnimationController audioLevel;
  bool _disposed = false;

  @override
  void initState() {
    audioLevel = AnimationController(
      vsync: this,
      duration: CallView.volumeAnimationDuration,
    );

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!mounted) {
        return;
      }
      widget.updateSelection?.call(
        link,
        widget.session,
        widget.session.state == VoipState.incoming,
      );
    });

    subs = [];
    _bindSession();

    super.initState();
  }

  @override
  void didUpdateWidget(covariant SidebarCallIconEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) {
      return;
    }

    // The list builds these entries positionally with no key, so a leave and
    // rejoin of the same room hands this element a different session object.
    // Without rebinding, both listeners stay attached to the dead session.
    _cancelBoundSubscriptions();
    _bindSession();

    // The parent is told which session it is pointing at only on pointer-enter.
    // If the pointer never left during the swap there is no enter event, so the
    // hover controls stayed bound to the session that just ended until the user
    // moved the mouse away and back. Re-announce the replacement, but only if
    // the pointer is still here and the widget still holds the session we are
    // announcing - both can change before the frame lands.
    if (_hovered) {
      final session = widget.session;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_hovered || !identical(widget.session, session)) {
          return;
        }
        widget.updateSelection?.call(
          link,
          session,
          session.state == VoipState.incoming,
        );
      });
    }
    setState(() {});
  }

  /// Cancels and clears every session-bound listener.
  ///
  /// `cancel()` is awaited inside the helper rather than dropped: a stream
  /// whose `onCancel` throws would otherwise surface as an unhandled async
  /// error from a widget lifecycle callback, which is unattributable in a
  /// capture. Same shape as `_cancelSidebarCallsListSubscription`.
  void _cancelBoundSubscriptions() {
    final cancelling = subs;
    subs = [];
    for (final sub in cancelling) {
      unawaited(_cancelSidebarCallIconSubscription(sub));
    }
  }

  void _bindSession() {
    room = widget.session.client.getRoom(widget.session.roomId);

    subs = [
      widget.session.onStateChanged.listen((event) {
        if (!mounted) {
          return;
        }
        setState(() {});
      }),
      widget.session.onUpdateVolumeVisualizers.listen(
        (_) => unawaited(_refreshAudioLevel()),
      ),
    ];
  }

  Future<void> _refreshAudioLevel() async {
    // Captured before the await. Cancelling the old subscription in
    // `didUpdateWidget` does not retract a refresh that is already in flight,
    // so a stats update started for the previous session can land after this
    // element has been rebound - and animating from `widget.session` then
    // drives the icon from the wrong call.
    final session = widget.session;

    try {
      await session.updateStats();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered sidebar call icon stats update failure',
        category: LogCategory.webrtc,
        source: 'sidebar-call-icon',
      );
      return;
    }

    // `updateStats` is awaited, so the entry can have been disposed by the
    // time it returns; driving a disposed AnimationController throws.
    if (!mounted || _disposed || !identical(session, widget.session)) {
      return;
    }

    audioLevel.animateTo(session.generalAudioLevel);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelBoundSubscriptions();
    statUpdateTimer?.cancel();
    audioLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) {
        _hovered = true;
        widget.updateSelection?.call(
          link,
          widget.session,
          widget.session.state == VoipState.incoming,
        );
      },
      onExit: (_) {
        _hovered = false;
        widget.onUnhovered?.call();
      },
      child: CompositedTransformTarget(
        link: link,
        child: AnimatedBuilder(
          animation: audioLevel,
          builder: (context, child) {
            return SidebarCallIconView(
              widget.session.state,
              width: widget.width,
              roomName: room?.displayName,
              color: room?.defaultColor,
              avatar: room?.avatar,
              audioLevel: audioLevel.value,
              onTap: () => EventBus.openRoom.add((
                widget.session.roomId,
                widget.session.client.identifier,
              )),
            );
          },
        ),
      ),
    );
  }
}
