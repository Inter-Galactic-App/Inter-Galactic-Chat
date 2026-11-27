import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/call_surface_mode.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallWidget extends StatefulWidget {
  const CallWidget(
    this.session, {
    super.key,
    this.showSessionPopoutButton = true,
    this.transparentBackground = false,
    this.forceControlsVisible = false,
    this.suppressControls = false,
    this.surfaceMode = CallSurfaceMode.inRoom,
  });
  final VoipSession session;
  final bool showSessionPopoutButton;
  final bool transparentBackground;
  final bool forceControlsVisible;
  final bool suppressControls;
  final CallSurfaceMode surfaceMode;

  @override
  State<CallWidget> createState() => _CallWidgetState();
}

class _CallWidgetState extends State<CallWidget> {
  @override
  Widget build(BuildContext context) {
    return CallView(
      widget.session,
      showSessionPopoutButton: widget.showSessionPopoutButton,
      transparentBackground: widget.transparentBackground,
      forceControlsVisible: widget.forceControlsVisible,
      suppressControls: widget.suppressControls,
      surfaceMode: widget.surfaceMode,
      pickScreenshareSource: pickScreenShareSource,
      stopScreenshare: stopScreenshare,
      setMicrophoneMute: setMicrophoneMute,
      microphoneMuteIntent: microphoneMuteIntent,
      pickCamera: pickCamera,
      disableCamera: disableCamera,
      hangUp: hangUp,
      declineCall: declineCall,
      acceptCall: acceptCall,
    );
  }

  Future<void> pickScreenShareSource() async {
    try {
      final source = await widget.session.pickScreenCapture(context);
      await _applyPickedScreenShareIfMounted(
        isMounted: mounted,
        source: source,
        setScreenShare: widget.session.setScreenShare,
      );
    } catch (error) {
      Log.w(
        'Screen share start failed from call controls: $error',
        category: LogCategory.livekit,
        source: 'call-view',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Screen share could not be started')),
        );
    }
  }

  Future<void> stopScreenshare() {
    return widget.session.stopScreenshare();
  }

  /// The state the mute button should toggle away from.
  ///
  /// See [CallView.microphoneMuteIntent]: the session reports the APPLIED mute
  /// state, which lags the coalescing drain, so a toggle computed from it
  /// re-requests the queued value on a fast second press.
  bool microphoneMuteIntent() {
    final callManager = clientManager?.callManager;
    return callManager == null
        ? widget.session.isMicrophoneMuted
        : callManager.effectiveManualMuteState(widget.session);
  }

  Future<void> setMicrophoneMute(bool isMuted) {
    final callManager = clientManager?.callManager;

    // Route through CallManager rather than calling
    // `session.setMicrophoneMute` directly. The direct call skipped the
    // manual-intent map and the coalescing drain, so this surface and the
    // soundboard/push-to-talk paths were two independent mute writers with no
    // shared record of what the user actually asked for.
    if (callManager == null) {
      // Silent by design, and always has been: the sounds are owned by the
      // manager, so there is nothing to play without one. This path exists for
      // surfaces built without a manager (tests, the demo backdrop), where the
      // mute still has to apply.
      return widget.session.setMicrophoneMute(isMuted);
    }

    // The sound is played only for a request the manager will act on. The
    // manager drops a request when it is disposed or when the session is not
    // current, so playing first made a dropped press still click - feedback for
    // something that did not happen, on the one control where the sound IS the
    // confirmation. `acceptsMuteRequestFor` owns both conditions; reconstructing
    // them here would miss the disposed case, whose flag is private.
    if (!callManager.acceptsMuteRequestFor(widget.session)) {
      return Future<void>.value();
    }

    _playMuteFeedback(callManager, isMuted);
    return callManager.setMicrophoneMuteForSession(
      widget.session,
      isMuted,
      trigger: 'call-controls',
    );
  }

  void _playMuteFeedback(CallManager callManager, bool isMuted) {
    if (isMuted) {
      callManager.playMuteSound();
    } else {
      callManager.playUnmuteSound();
    }
  }

  Future<void> pickCamera() async {
    final camera = await WebrtcDefaultDevices.getDefaultCamera();
    await _applyPickedCameraIfMounted(
      isMounted: mounted,
      camera: camera,
      setCamera: widget.session.setCamera,
    );
  }

  Future<void> hangUp() {
    return widget.session.hangUpCall();
  }

  Future<void> disableCamera() {
    return widget.session.stopCamera();
  }

  Future<void> declineCall() {
    return widget.session.declineCall();
  }

  Future<void> acceptCall() {
    return widget.session.acceptCall();
  }
}

@visibleForTesting
Future<void> debugApplyPickedScreenShareForTesting({
  required bool isMounted,
  required ScreenCaptureSource? source,
  required Future<void> Function(ScreenCaptureSource source) setScreenShare,
}) {
  return _applyPickedScreenShareIfMounted(
    isMounted: isMounted,
    source: source,
    setScreenShare: setScreenShare,
  );
}

Future<void> _applyPickedScreenShareIfMounted({
  required bool isMounted,
  required ScreenCaptureSource? source,
  required Future<void> Function(ScreenCaptureSource source) setScreenShare,
}) async {
  if (!isMounted || source == null) {
    return;
  }

  await setScreenShare(source);
}

@visibleForTesting
Future<void> debugApplyPickedCameraForTesting({
  required bool isMounted,
  required MediaDeviceInfo? camera,
  required Future<void> Function(MediaDeviceInfo? camera) setCamera,
}) {
  return _applyPickedCameraIfMounted(
    isMounted: isMounted,
    camera: camera,
    setCamera: setCamera,
  );
}

Future<void> _applyPickedCameraIfMounted({
  required bool isMounted,
  required MediaDeviceInfo? camera,
  required Future<void> Function(MediaDeviceInfo? camera) setCamera,
}) async {
  if (!isMounted) {
    return;
  }

  await setCamera(camera);
}
