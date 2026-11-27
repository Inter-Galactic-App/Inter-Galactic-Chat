import 'dart:async';

import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/organisms/mini_call_menu/mini_call_menu.dart';
import 'package:intergalactic/ui/organisms/sidebar_call_icon/sidebar_call_icon.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' show Seperator;

@visibleForTesting
Future<void> debugCancelSidebarCallsListSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelSidebarCallsListSubscription(subscription);
}

Future<void> _cancelSidebarCallsListSubscription(
  StreamSubscription? subscription,
) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered sidebar calls list subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'sidebar-calls-list',
    );
  }
}

class SidebarCallsList extends StatefulWidget {
  const SidebarCallsList(this.callManager, this.width, {super.key});
  final CallManager callManager;
  final double width;

  @override
  State<SidebarCallsList> createState() => _SidebarCallsListState();
}

class _SidebarCallsListState extends State<SidebarCallsList> {
  int count = 0;
  final GlobalKey listKey = GlobalKey();

  OverlayEntry? overlay;
  final List<StreamSubscription> subscriptions = [];

  VoipSession? selectedSession;
  LayerLink? link;

  /// Tracks [selectedSession]'s own state changes; see
  /// [_listenToSelectedSessionState]. Held separately from `subscriptions`
  /// because it is replaced on every selection change rather than at dispose.
  StreamSubscription? _selectedSessionStateSubscription;

  /// The session [_selectedSessionStateSubscription] is listening to, so a
  /// hover over the already-selected session does not cancel-and-relisten.
  VoipSession? _stateSubscriptionSession;

  NotifyingList<VoipSession> get sessions => widget.callManager.currentSessions;

  bool isHovered = false;
  bool showWhileUnhovered = false;

  @override
  void initState() {
    count = widget.callManager.currentSessions.length;

    subscriptions.addAll([
      sessions.onListUpdated.listen((event) {
        if (!mounted) {
          return;
        }
        setState(() {});
      }),
      sessions.onRemove.listen(_onSessionRemoved),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      addOverlay();
    });

    super.initState();
  }

  /// [NotifyingList] emits the removal index *before* removing the item, so
  /// the session is still readable at [index] here. The bounds check only
  /// guards against a future emitter that does not honour that contract.
  void _onSessionRemoved(int index) {
    if (!mounted || index < 0 || index >= sessions.length) {
      return;
    }

    if (sessions[index] != selectedSession) {
      return;
    }

    final stateSubscription = _selectedSessionStateSubscription;
    _selectedSessionStateSubscription = null;
    _stateSubscriptionSession = null;
    unawaited(_cancelSidebarCallsListSubscription(stateSubscription));

    setState(() {
      selectedSession = null;
      link = null;
      overlay?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    final pendingSubscriptions = List<StreamSubscription>.of(subscriptions);
    subscriptions.clear();
    for (final subscription in pendingSubscriptions) {
      unawaited(_cancelSidebarCallsListSubscription(subscription));
    }

    final stateSubscription = _selectedSessionStateSubscription;
    _selectedSessionStateSubscription = null;
    _stateSubscriptionSession = null;
    unawaited(_cancelSidebarCallsListSubscription(stateSubscription));

    removeOverlay();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool hasSessions = widget.callManager.currentSessions.isNotEmpty;

    return ScaledSafeArea(
      top: false,
      bottom: hasSessions,
      child: Column(
        children: [
          if (hasSessions) const Seperator(),
          ImplicitlyAnimatedList(
            padding: EdgeInsets.zero,
            key: listKey,
            shrinkWrap: true,
            itemData: widget.callManager.currentSessions,
            itemBuilder: (context, data) {
              return buildItem(data);
            },
          ),
        ],
      ),
    );
  }

  Widget buildItem(VoipSession data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: SidebarCallIconEntry(
        data,
        widget.width,
        updateSelection: onSelectionUpdate,
        onUnhovered: onUnhovered,
      ),
    );
  }

  void addOverlay() {
    if (overlay != null || !mounted) {
      return;
    }

    final entry = OverlayEntry(builder: buildOverlay);
    overlay = entry;
    Overlay.of(context).insert(entry);
  }

  void removeOverlay() {
    final currentEntry = overlay;
    if (currentEntry == null) {
      return;
    }

    overlay = null;
    currentEntry.remove();
    currentEntry.dispose();
  }

  Widget buildOverlay(BuildContext context) {
    if (Layout.mobile) {
      return Container();
    }

    if (link == null || selectedSession == null) {
      return Container();
    }

    // `leaving` suppresses the overlay just like `connected`. It is reached at
    // the start of hang-up, so treating it as "not connected" would pop this
    // overlay back up for the whole teardown - a flash on every leave.
    final selectedState = selectedSession?.state;
    if (selectedState == VoipState.connected ||
        selectedState == VoipState.leaving) {
      return Container();
    }

    if (showWhileUnhovered == false && isHovered == false) {
      return Container();
    }

    return CompositedTransformFollower(
      link: link!,
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.bottomLeft,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              onExit: (event) {
                updateHover(false);
              },
              onEnter: (event) {
                updateHover(true);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Tile.lowest(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: MiniCallMenu(selectedSession!),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void updateHover(bool hovered) {
    setState(() {
      isHovered = hovered;
      showWhileUnhovered =
          selectedSession?.state == VoipState.incoming ||
          selectedSession?.state == VoipState.connecting;
      overlay?.markNeedsBuild();
    });
  }

  void onUnhovered() {
    updateHover(false);
  }

  void onSelectionUpdate(
    LayerLink link,
    VoipSession session,
    bool showWhileUnhovered,
  ) {
    setState(() {
      this.link = link;
      selectedSession = session;
    });
    _listenToSelectedSessionState(session);
    updateHover(true);
  }

  /// Rebuilds the overlay when the selected session's own state changes.
  ///
  /// `buildOverlay` decides whether to show the call controls by reading
  /// `selectedSession.state`, but an `OverlayEntry` only rebuilds when it is
  /// told to, and `NotifyingList.onListUpdated` fires on membership changes -
  /// not on a state transition within a session that is already in the list.
  /// So the accept/decline overlay stayed up after the call connected, and the
  /// `leaving` suppression added for hang-up never actually ran, until some
  /// unrelated rebuild happened to repaint it.
  void _listenToSelectedSessionState(VoipSession session) {
    // `onSelectionUpdate` fires on every pointer-enter. Re-subscribing to the
    // session already listened to is not merely wasted work: an event emitted
    // between the cancel below and the new listen is lost, and a lost
    // transition is exactly the stale-overlay defect this listener exists to
    // fix.
    if (_selectedSessionStateSubscription != null &&
        identical(_stateSubscriptionSession, session)) {
      return;
    }
    _stateSubscriptionSession = session;
    final previous = _selectedSessionStateSubscription;
    _selectedSessionStateSubscription = null;
    unawaited(_cancelSidebarCallsListSubscription(previous));

    _selectedSessionStateSubscription = session.onStateChanged.listen((_) {
      // Identity-checked: a subscription cancelled while an event was already
      // in flight can still deliver once, and rebuilding the overlay against a
      // session that is no longer selected is exactly the stale-surface shape
      // this is here to fix.
      if (!mounted || !identical(selectedSession, session)) {
        return;
      }
      overlay?.markNeedsBuild();
    });
  }
}
