import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:flutter/material.dart';

class CallWidget extends StatefulWidget {
  const CallWidget(
    this.session, {
    super.key,
    this.showSessionPopoutButton = true,
    this.transparentBackground = false,
    this.forceControlsVisible = false,
  });
  final VoipSession session;
  final bool showSessionPopoutButton;
  final bool transparentBackground;
  final bool forceControlsVisible;

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
      if (source != null) {
        await widget.session.setScreenShare(source);
      }
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
    await widget.session.setCamera(camera);
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
