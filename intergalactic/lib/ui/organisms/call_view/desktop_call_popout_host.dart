import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/floating_tile.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';
import 'package:intergalactic/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopCallPopoutHost extends StatefulWidget {
  const DesktopCallPopoutHost(
    this.callManager, {
    super.key,
  });

  final CallManager callManager;

  @override
  State<DesktopCallPopoutHost> createState() => _DesktopCallPopoutHostState();
}

class _DesktopCallPopoutHostState extends State<DesktopCallPopoutHost> {
  late final List<StreamSubscription> subscriptions;

  @override
  void initState() {
    super.initState();
    subscriptions = [
      callPopoutController.onChanged.listen((_) => _refresh()),
      widget.callManager.currentSessions.onListUpdated
          .listen((_) => _refresh()),
    ];
    _refresh();
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _refresh() {
    callPopoutController.clearMissingSessions(
      widget.callManager.currentSessions.map((session) => session.sessionId),
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!BuildConfig.DESKTOP) {
      return const SizedBox.shrink();
    }

    final poppedSessions = callPopoutController.usesNativeDetachedSessionPopouts
        ? const <VoipSession>[]
        : callPopoutController.poppedSessionIds
            .map(_findSession)
            .whereType<VoipSession>()
            .toList(growable: false);
    final poppedStreams = callPopoutController.poppedStreams
        .map((entry) => _resolveStreamEntry(entry.sessionId, entry.streamId))
        .whereType<_ResolvedPoppedStream>()
        .toList(growable: false);

    if (poppedSessions.isEmpty && poppedStreams.isEmpty) {
      return const SizedBox.shrink();
    }

    final panels = <Widget>[];
    final positions = [
      Alignment.topRight,
      Alignment.bottomRight,
      Alignment.bottomLeft,
      Alignment.topLeft,
    ];

    for (var i = 0; i < poppedSessions.length; i++) {
      final session = poppedSessions[i];
      panels.add(
        FloatingTile(
          key: ValueKey("session-popout-${session.sessionId}"),
          initialPosition: positions[i % positions.length],
          child: _CallPopoutCard(
            session: session,
          ),
        ),
      );
    }

    for (var i = 0; i < poppedStreams.length; i++) {
      final stream = poppedStreams[i];
      panels.add(
        FloatingTile(
          key: ValueKey(
            "stream-popout-${stream.session.sessionId}-${stream.stream.streamId}",
          ),
          initialPosition:
              positions[(i + poppedSessions.length) % positions.length],
          child: _StreamPopoutCard(
            session: stream.session,
            stream: stream.stream,
            audioStream: stream.audioStream,
            volumeStream: stream.volumeStream,
            popoutId: stream.popoutId,
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: true,
      child: Column(
        children: panels,
      ),
    );
  }

  VoipSession? _findSession(String sessionId) {
    return widget.callManager.currentSessions
        .firstWhereOrNull((session) => session.sessionId == sessionId);
  }

  _ResolvedPoppedStream? _resolveStreamEntry(
      String sessionId, String streamId) {
    final session = _findSession(sessionId);
    if (session == null) {
      return null;
    }

    final matchingStreams = session.streams
        .where((item) => callStreamPopoutIdForStream(item) == streamId)
        .toList(growable: false);
    final stream = matchingStreams.firstWhereOrNull(
          (item) =>
              item.type == VoipStreamType.video ||
              item.type == VoipStreamType.screenshare,
        ) ??
        matchingStreams.firstOrNull ??
        session.streams.firstWhereOrNull((item) => item.streamId == streamId);
    if (stream == null) {
      return null;
    }

    final popoutId = matchingStreams.isEmpty
        ? streamId
        : callStreamPopoutIdForStream(stream);

    final audioStream = session.streams.firstWhereOrNull(
      (item) =>
          item.streamUserId == stream.streamUserId &&
          item.type == VoipStreamType.audio &&
          (item is! MatrixLivekitVoipStream || item.isMicrophoneAudio),
    );

    return _ResolvedPoppedStream(
      session: session,
      stream: stream,
      audioStream: audioStream,
      volumeStream: _findVolumeStream(session, stream, audioStream),
      popoutId: popoutId,
    );
  }

  VoipStream? _findVolumeStream(
    VoipSession session,
    VoipStream stream,
    VoipStream? audioStream,
  ) {
    if (stream.type == VoipStreamType.screenshare) {
      final screenShareAudio = session.streams.firstWhereOrNull(
        (item) =>
            item.streamUserId == stream.streamUserId &&
            item is MatrixLivekitVoipStream &&
            item.isScreenShareAudio,
      );
      if (_supportsLocalPlaybackVolume(screenShareAudio)) {
        return screenShareAudio;
      }
    }

    if (_supportsLocalPlaybackVolume(audioStream)) {
      return audioStream;
    }

    if (_supportsLocalPlaybackVolume(stream)) {
      return stream;
    }

    return null;
  }

  bool _supportsLocalPlaybackVolume(VoipStream? stream) {
    return stream is LocalPlaybackVolumeStream &&
        (stream as LocalPlaybackVolumeStream).hasLocalPlaybackAudio;
  }
}

class _ResolvedPoppedStream {
  const _ResolvedPoppedStream({
    required this.session,
    required this.stream,
    required this.popoutId,
    this.audioStream,
    this.volumeStream,
  });

  final VoipSession session;
  final VoipStream stream;
  final String popoutId;
  final VoipStream? audioStream;
  final VoipStream? volumeStream;
}

class _CallPopoutCard extends StatelessWidget {
  const _CallPopoutCard({
    required this.session,
  });

  final VoipSession session;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width * 0.56, 940.0).clamp(360.0, 940.0);
    final height = math.min(size.height * 0.62, 760.0).clamp(280.0, 760.0);

    return _PopoutFrame(
      title: session.roomName,
      onClose: () {
        callPopoutController.restoreSession(session.sessionId);
      },
      childBuilder: (transparentChrome) => SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: CallWidget(
          session,
          showSessionPopoutButton: false,
          transparentBackground: transparentChrome,
        ),
      ),
    );
  }
}

class _StreamPopoutCard extends StatelessWidget {
  const _StreamPopoutCard({
    required this.session,
    required this.stream,
    required this.popoutId,
    this.audioStream,
    this.volumeStream,
  });

  final VoipSession session;
  final VoipStream stream;
  final String popoutId;
  final VoipStream? audioStream;
  final VoipStream? volumeStream;

  double get _defaultParticipantAudioVolume =>
      Preferences.voipSpeakerVolumeToLocalPlayback(
        preferences.voipSpeakerVolume.value,
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width * 0.32, 460.0).clamp(250.0, 460.0);
    final height = stream.type == VoipStreamType.audio
        ? 260.0
        : math.min(size.height * 0.34, 340.0).clamp(220.0, 340.0);

    return _PopoutFrame(
      title: stream.type == VoipStreamType.screenshare
          ? "${session.roomName} Screen"
          : session.roomName,
      onClose: () {
        callPopoutController.restoreStream(session.sessionId, popoutId);
      },
      childBuilder: (transparentChrome) => SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: Padding(
          padding: EdgeInsets.all(transparentChrome ? 0 : 8),
          child: VoipStreamView(
            key: ValueKey(
                "stream-popout-${session.sessionId}-${stream.streamId}"),
            stream,
            session,
            fit: stream.type == VoipStreamType.screenshare
                ? BoxFit.contain
                : BoxFit.cover,
            isFocused: true,
            edgeToEdge: transparentChrome,
            showTileScrim: !transparentChrome,
            isMicrophoneMuted: audioStream?.isMuted ?? false,
            volumeStream: volumeStream,
            defaultVolume: _defaultParticipantAudioVolume,
            onVolumeChanged:
                _canControlVolume ? (vol) => _setVolume(vol) : null,
            onFullscreen: () {
              unawaited(
                showVoipStreamFullscreen(
                  context,
                  session: session,
                  stream: stream,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool get _canControlVolume =>
      volumeStream is LocalPlaybackVolumeStream &&
      stream.streamUserId != session.client.self?.identifier;

  void _setVolume(double volume) {
    final target = volumeStream;
    if (target is! LocalPlaybackVolumeStream) {
      return;
    }
    final volumeTarget = target as LocalPlaybackVolumeStream;

    final clampedVolume = Preferences.clampScreenShareAudioVolume(volume);
    unawaited(volumeTarget.setLocalVolume(clampedVolume));
    if (target is MatrixLivekitVoipStream && target.isScreenShareAudio) {
      final room = session.client.getRoom(session.roomId);
      if (room != null) {
        unawaited(
          preferences.setScreenShareAudioVolume(
            roomLocalId: room.localId,
            streamUserId: target.streamUserId,
            volume: clampedVolume,
          ),
        );
      }
    } else if ((clampedVolume - _defaultParticipantAudioVolume).abs() < 0.001) {
      volumeTarget.clearLocalPlaybackVolumeOverride();
    }
  }
}

class _PopoutFrame extends StatefulWidget {
  const _PopoutFrame({
    required this.title,
    required this.childBuilder,
    required this.onClose,
  });

  final String title;
  final Widget Function(bool transparentChrome) childBuilder;
  final VoidCallback onClose;

  @override
  State<_PopoutFrame> createState() => _PopoutFrameState();
}

class _PopoutFrameState extends State<_PopoutFrame> {
  static const double _chromeHeight = 50;

  bool isAlwaysOnTop = false;
  bool isHovered = false;
  bool _transparentChrome = false;

  @override
  void initState() {
    super.initState();
    _refreshPinState();
  }

  Future<void> _refreshPinState() async {
    final value = await WindowManagement.isAlwaysOnTop();
    if (mounted) {
      setState(() {
        isAlwaysOnTop = value;
      });
    }
  }

  Future<void> _toggleAlwaysOnTop() async {
    await WindowManagement.setAlwaysOnTop(!isAlwaysOnTop);
    await _refreshPinState();
  }

  void _toggleTransparentChrome() {
    setState(() {
      _transparentChrome = !_transparentChrome;
      if (!_transparentChrome) {
        isHovered = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final transparentChrome = _transparentChrome;
    final showChrome = !transparentChrome || isHovered;
    final reserveChromeSpace = !transparentChrome;
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      ignoring: false,
      child: MouseRegion(
        onEnter: (_) {
          if (transparentChrome) {
            setState(() => isHovered = true);
          }
        },
        onExit: (_) {
          if (transparentChrome) {
            setState(() => isHovered = false);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: reserveChromeSpace
                  ? colorScheme.surfaceContainerHighest.withAlpha(238)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: reserveChromeSpace
                  ? Border.all(color: colorScheme.outlineVariant.withAlpha(90))
                  : null,
              boxShadow: reserveChromeSpace
                  ? [
                      BoxShadow(
                        color: Colors.black.withAlpha(70),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: reserveChromeSpace ? _chromeHeight : 0,
                  ),
                  child: widget.childBuilder(transparentChrome),
                ),
                Positioned(
                  top: transparentChrome ? 8 : 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _PopoutChrome(
                      title: widget.title,
                      transparentChrome: transparentChrome,
                      expanded: showChrome,
                      isAlwaysOnTop: isAlwaysOnTop,
                      onToggleTransparentChrome: _toggleTransparentChrome,
                      onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                      onClose: widget.onClose,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoutChrome extends StatelessWidget {
  const _PopoutChrome({
    required this.title,
    required this.transparentChrome,
    required this.expanded,
    required this.isAlwaysOnTop,
    required this.onToggleTransparentChrome,
    required this.onToggleAlwaysOnTop,
    required this.onClose,
  });

  final String title;
  final bool transparentChrome;
  final bool expanded;
  final bool isAlwaysOnTop;
  final VoidCallback onToggleTransparentChrome;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (transparentChrome) {
      final chromeColor = Colors.black.withAlpha(expanded ? 154 : 106);
      final actions = [
        tiamat.IconButton(
          icon: Icons.opacity_rounded,
          size: 16,
          onPressed: onToggleTransparentChrome,
        ),
        if (expanded) ...[
          const SizedBox(width: 4),
          tiamat.IconButton(
            icon: isAlwaysOnTop
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            size: 16,
            onPressed: onToggleAlwaysOnTop,
          ),
          const SizedBox(width: 4),
          tiamat.IconButton(
            icon: Icons.close_rounded,
            size: 16,
            onPressed: onClose,
          ),
        ],
      ];

      return AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(
          minHeight: 38,
          maxWidth: expanded ? 420 : 48,
        ),
        decoration: BoxDecoration(
          color: chromeColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withAlpha(expanded ? 76 : 48),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(expanded ? 70 : 34),
              blurRadius: expanded ? 18 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 7,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expanded) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ...actions,
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: _PopoutFrameState._chromeHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: tiamat.Text.label(
                  title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                height: 34,
                child: tiamat.IconButton(
                  icon: transparentChrome
                      ? Icons.opacity_rounded
                      : Icons.opacity_outlined,
                  size: 16,
                  onPressed: onToggleTransparentChrome,
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: tiamat.IconButton(
                  icon: isAlwaysOnTop
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 16,
                  onPressed: onToggleAlwaysOnTop,
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: tiamat.IconButton(
                  icon: Icons.close_rounded,
                  size: 16,
                  onPressed: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
