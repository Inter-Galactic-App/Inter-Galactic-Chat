import 'dart:async';

import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/mini_call_menu/mini_call_menu_connected.dart';
import 'package:intergalactic/ui/organisms/mini_call_menu/mini_call_menu_incoming.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@visibleForTesting
Future<void> debugCancelMiniCallMenuSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelMiniCallMenuSubscription(subscription);
}

Future<void> _cancelMiniCallMenuSubscription(
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
      content: 'Recovered mini call menu subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'mini-call-menu',
    );
  }
}

class MiniCallMenu extends StatefulWidget {
  const MiniCallMenu(this.session, {super.key});
  final VoipSession session;

  @override
  State<MiniCallMenu> createState() => _MiniCallMenuState();
}

class _MiniCallMenuState extends State<MiniCallMenu> {
  StreamSubscription? sub;
  Room? room;
  String? _failureMessage;
  Timer? _failureClearTimer;

  /// [room], re-resolved when the insert-time lookup missed.
  ///
  /// `room` is assigned once in `initState`. A room that has not synced yet
  /// therefore stayed null for the life of this menu, and the incoming-call
  /// branch reads it to decide `isRoomDirectMessage` - so a direct call that
  /// arrived before its room synced rendered as a group call until the widget
  /// was rebuilt with a different session. Retrying the lookup costs one map
  /// read and is the same shape used in `CallView`. A method rather than a
  /// getter because it refreshes the [room] cache on a hit - a write that a
  /// getter read from `build` would hide.
  Room? _resolveRoom() {
    final resolved = widget.session.client.getRoom(widget.session.roomId);
    if (resolved != null) {
      room = resolved;
      return resolved;
    }
    final cached = room;
    if (cached != null &&
        cached.identifier == widget.session.roomId &&
        cached.client.identifier == widget.session.client.identifier) {
      return cached;
    }
    return null;
  }

  @override
  void initState() {
    _bindSession();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant MiniCallMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) {
      return;
    }

    final previous = sub;
    sub = null;
    unawaited(_cancelMiniCallMenuSubscription(previous));
    _bindSession();
    // A failure belongs to the session whose control produced it.
    _clearFailure();
    setState(() {});
  }

  void _bindSession() {
    sub = widget.session.onStateChanged.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    // A room can legitimately be missing here (not yet synced, or left while
    // the menu is open). Null-asserting it turned that into a crash in
    // initState, which takes the whole sidebar down with it.
    room = widget.session.client.getRoom(widget.session.roomId);
  }

  @override
  void dispose() {
    final pending = sub;
    sub = null;
    unawaited(_cancelMiniCallMenuSubscription(pending));
    _failureClearTimer?.cancel();
    super.dispose();
  }

  /// Renders the failure inline in the menu, NOT via SnackBar. A SnackBar is
  /// presented by a Scaffold registered with the ScaffoldMessenger, and there
  /// is no Scaffold anywhere on the main navigation path - the previous
  /// `showSnackBar` call here queued the message and drew nothing. The same
  /// silent no-op is documented at `MainPage._showInboundShareFailure` and
  /// `CallSoundboardPanel._showPlaybackFailure`.
  void _showFailure(String message) {
    if (!mounted) {
      return;
    }

    _failureClearTimer?.cancel();
    _failureClearTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() => _failureMessage = null);
    });
    setState(() => _failureMessage = message);
  }

  void _clearFailure() {
    _failureClearTimer?.cancel();
    _failureClearTimer = null;
    _failureMessage = null;
  }

  Future<void> _runControlAction(
    Future<void> Function() action, {
    required String failureMessage,
    required String logContent,
  }) async {
    // This State survives a selectedSession swap (the menu sits at a stable
    // slot in the overlay tree, so reconciliation reuses it and only
    // didUpdateWidget runs). An action still in flight for the OLD session
    // must not paint its outcome onto the new one's menu.
    final issuedFor = widget.session;
    try {
      // Issue first, then rebuild, then await. The mute path records the user's
      // intent synchronously and returns a future that completes only once the
      // coalescing drain settles - so rebuilding solely after the await left
      // the icon showing the pre-press state for the whole drain. The user
      // reads that as "the press did nothing" and presses again, and the
      // second press correctly inverts the intent, cancelling the mute they
      // asked for. Rebuilding as soon as the request is in makes the control
      // reflect what was asked, which is the same value the toggle reads.
      final pending = action();
      if (mounted) {
        // The same rebuild also retires any failure banner from the previous
        // attempt - the user has retried, so the old message is stale.
        setState(_clearFailure);
      }
      await pending;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: logContent,
        category: LogCategory.webrtc,
        source: 'mini-call-menu',
      );
      if (!mounted || !identical(widget.session, issuedFor)) {
        return;
      }
      _showFailure(failureMessage);
      return;
    }

    if (!mounted || !identical(widget.session, issuedFor)) {
      return;
    }
    setState(() {});
  }

  /// Route through CallManager rather than calling
  /// `session.setMicrophoneMute` directly. The direct call skipped the
  /// manual-intent map and the coalescing drain, so this menu was a second
  /// independent mute writer: a mute made here was invisible to push-to-talk,
  /// which reads that map to decide what state to restore.
  Future<void> _setMicrophoneMuted(bool muted) {
    final callManager = clientManager?.callManager;
    if (callManager == null) {
      return widget.session.setMicrophoneMute(muted);
    }

    return callManager.setMicrophoneMuteForSession(
      widget.session,
      muted,
      trigger: 'mini-call-menu',
    );
  }

  /// The state a press should toggle away from.
  ///
  /// `session.isMicrophoneMuted` is the APPLIED state and lags the drain. Two
  /// quick presses both read the pre-drain value, so the second one re-requests
  /// what is already queued and is absorbed as a duplicate - the button appears
  /// to ignore the press. `CallManager.effectiveManualMuteState` returns the
  /// pending intent when there is one, so the second press correctly asks for
  /// the opposite. Falls back to the session when no manager is wired, which is
  /// the same source the mute call itself falls back to.
  bool get _muteToggleSource {
    final callManager = clientManager?.callManager;
    return callManager == null
        ? widget.session.isMicrophoneMuted
        : callManager.effectiveManualMuteState(widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final menu = _buildForState(context);
    final failureMessage = _failureMessage;
    if (failureMessage == null) {
      return menu;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        menu,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          // A live region, because this banner is the ONLY feedback a failed
          // control gives; without it a screen-reader user gets exactly the
          // "the button did nothing" experience this exists to remove.
          child: Semantics(
            liveRegion: true,
            container: true,
            child: tiamat.Text.error(failureMessage),
          ),
        ),
      ],
    );
  }

  Widget _buildForState(BuildContext context) {
    switch (widget.session.state) {
      case VoipState.incoming:
        final currentRoom = _resolveRoom();
        return MiniCallMenuIncoming(
          callingUserName: widget.session.remoteUserName ?? "Unknown User",
          roomDisplayName: widget.session.roomName,
          isRoomDirectMessage: currentRoom == null
              ? false
              : widget.session.client
                        .getComponent<DirectMessagesComponent>()
                        ?.isRoomDirectMessage(currentRoom) ??
                    false,
          onAccept: () => unawaited(
            _runControlAction(
              widget.session.acceptCall,
              failureMessage: 'Could not answer the call.',
              logContent: 'Failed to accept call from mini call menu',
            ),
          ),
          onDecline: () => unawaited(
            _runControlAction(
              widget.session.declineCall,
              failureMessage: 'Could not decline the call.',
              logContent: 'Failed to decline call from mini call menu',
            ),
          ),
        );
      // `leaving` renders the connected menu, exactly as `CallView` does.
      // Teardown is normally under 100ms but has been measured near 2s, and
      // for that whole window the session is still a call the user is in.
      // Without this case it falls to the `default:` below and the menu
      // renders the literal text "leaving".
      case VoipState.connected:
      case VoipState.leaving:
        return MiniCallMenuConnected(
          roomDisplayName: widget.session.roomName,
          // The SAME source the toggle reads. Rendering the applied state while
          // toggling from the pending intent makes the two disagree for the
          // length of the drain: the icon still says "unmuted" after a press,
          // so the user presses again, and that second press correctly flips
          // the intent back - cancelling the mute they asked for twice.
          isMicrophoneMuted: _muteToggleSource,
          onHangUp: () => unawaited(
            _runControlAction(
              widget.session.hangUpCall,
              failureMessage: 'Could not leave the call. Please try again.',
              logContent: 'Failed to leave call from mini call menu',
            ),
          ),
          onToggleMute: () => unawaited(
            _runControlAction(
              () => _setMicrophoneMuted(!_muteToggleSource),
              failureMessage: 'Could not change your microphone.',
              logContent: 'Failed to toggle microphone from mini call menu',
            ),
          ),
        );
      case VoipState.connecting:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(),
        );
      // Deliberately exhaustive: no `default:`. `VoipState.leaving` was added
      // for the join guard and reached this switch through the old `default:`,
      // which rendered the raw enum name where the call controls belong. An
      // exhaustive switch turns the next such addition into an analyzer
      // failure at the CI gate instead of a string on screen.
      case VoipState.outgoing:
      case VoipState.unknown:
      case VoipState.ended:
        return tiamat.Text.body(widget.session.state.name);
    }
  }
}
