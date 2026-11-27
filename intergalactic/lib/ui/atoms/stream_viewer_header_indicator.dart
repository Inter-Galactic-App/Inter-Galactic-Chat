import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class StreamViewerHeaderIndicator extends StatefulWidget {
  const StreamViewerHeaderIndicator({
    required this.room,
    this.compact = false,
    super.key,
  });

  final Room room;
  final bool compact;

  @override
  State<StreamViewerHeaderIndicator> createState() =>
      _StreamViewerHeaderIndicatorState();
}

class _StreamViewerHeaderIndicatorState
    extends State<StreamViewerHeaderIndicator> {
  MatrixLivekitVoipSession? _session;
  StreamSubscription? _sessionSub;
  StreamSubscription? _sessionsSub;
  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    _sessionsSub = clientManager?.callManager.currentSessions.onListUpdated
        .listen((_) => _bindSession());
    _bindRoom(notify: false);
  }

  @override
  void didUpdateWidget(covariant StreamViewerHeaderIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.room, widget.room)) _bindRoom();
  }

  void _bindRoom({bool notify = true}) {
    unawaited(_roomSub?.cancel());
    _roomSub = widget.room
        .getComponent<VoipRoomComponent>()
        ?.onParticipantsChanged
        .listen((_) => _bindSession());
    _bindSession(notify: notify);
  }

  void _bindSession({bool notify = true}) {
    final current = widget.room
        .getComponent<VoipRoomComponent>()
        ?.currentSession;
    final next = current is MatrixLivekitVoipSession ? current : null;
    if (identical(_session, next)) return;
    unawaited(_sessionSub?.cancel());
    _session = next;
    _sessionSub = next?.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_sessionSub?.cancel());
    unawaited(_sessionsSub?.cancel());
    unawaited(_roomSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null || !session.isSharingScreen) {
      return const SizedBox.shrink();
    }
    final viewers = session.localScreenShareViewerUserIds;
    if (viewers.isEmpty) return const SizedBox.shrink();
    return StreamViewerHeaderContent(
      compact: widget.compact,
      viewers: viewers.map(_displayFor).toList(growable: false),
    );
  }

  StreamViewerDisplay _displayFor(String userId) {
    final member = widget.room.getMemberOrFallback(userId);
    return StreamViewerDisplay(
      userId: userId,
      displayName: member.displayName,
      avatar: member.avatar,
      placeholderColor: member.defaultColor,
    );
  }
}

class StreamViewerDisplay {
  const StreamViewerDisplay({
    required this.userId,
    required this.displayName,
    required this.placeholderColor,
    this.avatar,
  });

  final String userId;
  final String displayName;
  final ImageProvider? avatar;
  final Color placeholderColor;
}

class StreamViewerHeaderContent extends StatelessWidget {
  const StreamViewerHeaderContent({
    required this.viewers,
    this.compact = false,
    super.key,
  });

  final List<StreamViewerDisplay> viewers;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (viewers.isEmpty) return const SizedBox.shrink();

    final maxAvatars = compact ? 2 : 3;
    final color = Theme.of(context).colorScheme.onSurface;
    final count = viewers.length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<int>(
        tooltip: '$count watching your stream',
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
        itemBuilder: (context) => [
          for (var index = 0; index < viewers.length; index++)
            PopupMenuItem<int>(
              enabled: false,
              height: 44,
              value: index,
              child: _viewerRow(viewers[index], color),
            ),
        ],
        child: Semantics(
          button: true,
          label: '$count watching your stream',
          child: SizedBox(
            height: 36,
            child: Center(
              child: count > maxAvatars
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_outlined, size: 18, color: color),
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final viewer in viewers) ...[
                          _viewerAvatar(viewer, 12),
                          const SizedBox(width: 3),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewerRow(StreamViewerDisplay viewer, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _viewerAvatar(viewer, 14),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            viewer.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }

  Widget _viewerAvatar(StreamViewerDisplay viewer, double radius) {
    return tiamat.Avatar(
      radius: radius,
      image: viewer.avatar,
      placeholderText: viewer.displayName,
      placeholderColor: viewer.placeholderColor,
    );
  }
}
