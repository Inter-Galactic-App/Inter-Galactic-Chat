import 'dart:async';

import 'package:intergalactic/client/components/rtc_screen_share_annotation/rtc_screen_share_annotation_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';
import 'package:intergalactic/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class VoipFullscreenStreamView extends StatefulWidget {
  const VoipFullscreenStreamView({
    required this.stream,
    required this.session,
    this.onClose,
    super.key,
  });
  final VoipStream stream;
  final VoipSession session;
  final VoidCallback? onClose;

  @override
  State<VoipFullscreenStreamView> createState() =>
      _VoipFullscreenStreamViewState();
}

class _VoipFullscreenStreamViewState extends State<VoipFullscreenStreamView> {
  RTCScreenShareAnnotationSession? annotationSession;
  RTCScreenShareAnnotationComponent? component;
  bool? _wasDesktopFullscreen;
  bool _desktopFullscreenApplied = false;
  bool _mobileFullscreenApplied = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    component = widget.session.client
        .getComponent<RTCScreenShareAnnotationComponent>();

    annotationSession = component?.getExistingSession(widget.session);
    unawaited(_enterFullscreenMode());
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_restoreFullscreenMode());
    super.dispose();
  }

  Future<void> _enterFullscreenMode() async {
    try {
      if (BuildConfig.DESKTOP) {
        final wasFullscreen = await WindowManagement.isFullScreen();
        _wasDesktopFullscreen = wasFullscreen;
        if (!wasFullscreen) {
          await WindowManagement.setFullScreen(true);
          _desktopFullscreenApplied = true;
        }
        if (_isDisposed) {
          await _restoreFullscreenMode();
        }
        return;
      }

      if (BuildConfig.MOBILE) {
        _mobileFullscreenApplied = true;
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (_isDisposed) {
          await _restoreFullscreenMode();
        }
      }
    } catch (error) {
      Log.w('Unable to enter stream fullscreen mode: $error');
    }
  }

  Future<void> _restoreFullscreenMode() async {
    try {
      if (_desktopFullscreenApplied && _wasDesktopFullscreen == false) {
        _desktopFullscreenApplied = false;
        await WindowManagement.setFullScreen(false);
      }

      if (_mobileFullscreenApplied) {
        _mobileFullscreenApplied = false;
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (error) {
      Log.w('Unable to restore stream fullscreen mode: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  child: VoipStreamView(
                    widget.stream,
                    widget.session,
                    canFullscreen: false,
                    edgeToEdge: true,
                    showTileChrome: false,
                    fit: widget.stream.type == VoipStreamType.screenshare
                        ? BoxFit.contain
                        : BoxFit.cover,
                  ),
                  onHover: (event) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    final x = width <= 0 ? 0.0 : event.localPosition.dx / width;
                    final y = height <= 0
                        ? 0.0
                        : event.localPosition.dy / height;

                    _setFullscreenAnnotationCursor(
                      session: annotationSession,
                      streamId: widget.stream.streamId,
                      x: x,
                      y: y,
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 12,
            child: _FullscreenCloseButton(onPressed: widget.onClose),
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Wrap(
              spacing: 5,
              children: [
                if (component != null)
                  tiamat.CircleButton(
                    icon: Icons.mouse,
                    onPressed: () async {
                      try {
                        final session = await component?.getOrCreateSession(
                          widget.session,
                        );
                        if (!mounted || _isDisposed) {
                          return;
                        }
                        setState(() {
                          annotationSession = session;
                        });
                      } catch (error, stackTrace) {
                        Log.onError(
                          error,
                          stackTrace,
                          content:
                              'Recovered fullscreen stream annotation action failure',
                          category: LogCategory.webrtc,
                          source: 'voip-fullscreen-stream',
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
void debugSetFullscreenAnnotationCursorForTesting({
  required RTCScreenShareAnnotationSession? session,
  required String streamId,
  required double x,
  required double y,
}) {
  _setFullscreenAnnotationCursor(
    session: session,
    streamId: streamId,
    x: x,
    y: y,
  );
}

void _setFullscreenAnnotationCursor({
  required RTCScreenShareAnnotationSession? session,
  required String streamId,
  required double x,
  required double y,
}) {
  if (session == null) {
    return;
  }

  try {
    session.setCursorPosition(
      streamId: streamId,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
    );
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered fullscreen stream annotation cursor failure',
      category: LogCategory.webrtc,
      source: 'voip-fullscreen-stream',
    );
  }
}

@visibleForTesting
Future<void> debugRunVoipFullscreenRouteForTesting(
  FutureOr<void> Function()? action,
) {
  return _runVoipFullscreenRouteAction(
    action,
    actionLabel: 'test fullscreen route',
  );
}

Future<void> _runVoipFullscreenRouteAction(
  FutureOr<void> Function()? action, {
  String? actionLabel,
}) async {
  if (action == null) {
    return;
  }

  try {
    await Future<void>.sync(action);
  } catch (error, stackTrace) {
    final label = actionLabel?.trim();
    Log.onError(
      error,
      stackTrace,
      content: label == null || label.isEmpty
          ? 'Recovered fullscreen stream route action failure'
          : 'Recovered fullscreen stream route action failure: $label',
      category: LogCategory.webrtc,
      source: 'voip-fullscreen-stream',
    );
  }
}

Future<void> showVoipStreamFullscreen(
  BuildContext context, {
  required VoipSession session,
  required VoipStream stream,
}) {
  final transitionDuration = InterGalacticMotion.duration(
    context,
    InterGalacticMotion.standard,
  );

  return _runVoipFullscreenRouteAction(
    () => Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: transitionDuration,
        reverseTransitionDuration: transitionDuration,
        pageBuilder: (routeContext, animation, secondaryAnimation) {
          return VoipFullscreenStreamView(
            session: session,
            stream: stream,
            onClose: () => Navigator.of(routeContext).maybePop(),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: InterGalacticMotion.standardOut,
              reverseCurve: InterGalacticMotion.standardIn,
            ),
            child: child,
          );
        },
      ),
    ),
    actionLabel: 'open fullscreen stream route',
  );
}

class _FullscreenCloseButton extends StatelessWidget {
  const _FullscreenCloseButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(70)),
      ),
      child: IconButton(
        tooltip: 'Close',
        color: Colors.white,
        icon: const Icon(Icons.close_rounded),
        onPressed: onPressed,
      ),
    );
  }
}
