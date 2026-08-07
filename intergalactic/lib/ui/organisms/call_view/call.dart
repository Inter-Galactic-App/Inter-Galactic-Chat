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

  Future<void> setMicrophoneMute(bool isMuted) {
    if (isMuted) {
      clientManager?.callManager.playMuteSound();
    } else {
      clientManager?.callManager.playUnmuteSound();
    }

    return widget.session.setMicrophoneMute(isMuted);
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
