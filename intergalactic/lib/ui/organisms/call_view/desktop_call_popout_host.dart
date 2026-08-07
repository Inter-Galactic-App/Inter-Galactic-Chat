import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/floating_tile.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_panel.dart';
import 'package:intergalactic/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopCallPopoutHost extends StatefulWidget {
  const DesktopCallPopoutHost(this.callManager, {super.key});

  final CallManager callManager;

  @override
  State<DesktopCallPopoutHost> createState() => _DesktopCallPopoutHostState();
}

@visibleForTesting
Widget debugBuildCallPopoutFrameForTesting({
  required String title,
  required Widget Function(bool transparentChrome) childBuilder,
  VoidCallback? onClose,
}) {
  return _PopoutFrame(
    title: title,
    childBuilder: childBuilder,
    onClose: onClose ?? () {},
  );
}

@visibleForTesting
Future<void> debugCancelDesktopCallPopoutSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelDesktopCallPopoutSubscription(subscription);
}

Future<void> _cancelDesktopCallPopoutSubscription(
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
      content: 'Recovered desktop call popout host subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'desktop-call-popout-host',
    );
  }
}

class _DesktopCallPopoutHostState extends State<DesktopCallPopoutHost> {
  late final List<StreamSubscription> subscriptions;

  @override
  void initState() {
    super.initState();
    subscriptions = [
      callPopoutController.onChanged.listen((_) => _refresh()),
      widget.callManager.currentSessions.onListUpdated.listen(
        (_) => _refresh(),
      ),
    ];
    _refresh();
  }

  @override
  void dispose() {
    final pendingSubscriptions = List<StreamSubscription>.of(subscriptions);
    subscriptions.clear();
    for (final subscription in pendingSubscriptions) {
      unawaited(_cancelDesktopCallPopoutSubscription(subscription));
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
    final poppedStreams = callPopoutController.usesNativeDetachedStreamPopouts
        ? const <ResolvedCallStreamPopout>[]
        : callPopoutController.poppedStreams
              .map(
                (entry) => resolveCallStreamPopout(
                  callManager: widget.callManager,
                  sessionId: entry.sessionId,
                  streamId: entry.streamId,
                ),
              )
              .whereType<ResolvedCallStreamPopout>()
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
          child: _CallPopoutCard(session: session),
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
          child: _StreamPopoutCard(popout: stream),
        ),
      );
    }

    return IgnorePointer(ignoring: true, child: Column(children: panels));
  }

  VoipSession? _findSession(String sessionId) {
    return widget.callManager.currentSessions.firstWhereOrNull(
      (session) => session.sessionId == sessionId,
    );
  }
}

class _CallPopoutCard extends StatelessWidget {
  const _CallPopoutCard({required this.session});

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
  const _StreamPopoutCard({required this.popout});

  final ResolvedCallStreamPopout popout;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width * 0.32, 460.0).clamp(250.0, 460.0);
    final height = popout.isAudio
        ? 260.0
        : math.min(size.height * 0.34, 340.0).clamp(220.0, 340.0);

    return _PopoutFrame(
      title: popout.title,
      onClose: () {
        callPopoutController.restoreStream(
          popout.session.sessionId,
          popout.popoutId,
        );
      },
      childBuilder: (transparentChrome) => SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: CallStreamPopoutContent(
          popout: popout,
          transparentChrome: transparentChrome,
        ),
      ),
    );
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
    if (!mounted) {
      return;
    }
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
          border: Border.all(color: Colors.white.withAlpha(expanded ? 76 : 48)),
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
        decoration: BoxDecoration(color: Colors.transparent),
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
