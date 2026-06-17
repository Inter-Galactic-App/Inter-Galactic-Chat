import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum VoipState {
  incoming,
  connecting,
  connected,
  unknown,
  outgoing,
  ended,
}

abstract class ScreenCaptureSource {}

class ShareCaptureSource implements ScreenCaptureSource {
  const ShareCaptureSource({
    required this.videoSource,
    required this.shareSession,
  });

  final ScreenCaptureSource videoSource;
  final ShareSession shareSession;
}

abstract class VoipSession {
  Client get client;

  String get sessionId;

  String get roomId;

  String? get remoteUserId;

  String? get remoteUserName;

  String get roomName;

  VoipState get state;

  bool get isMicrophoneMuted;

  bool get supportsScreenshare;

  bool get isSharingScreen;

  ShareSession? get currentShareSession;

  bool get isCameraEnabled;

  double get generalAudioLevel;

  VoipStream? get remoteUserMediaStream;

  List<VoipStream> get streams;

  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false});

  Future<void> declineCall();

  Future<void> hangUpCall();

  Stream<VoipState> get onConnectionStateChanged;

  Stream<void> get onStateChanged;

  Stream<void> get onUpdateVolumeVisualizers;

  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot;

  Stream<void> get onDiagnosticsChanged;

  Future<void> setMicrophoneMute(bool state);

  Future<void> updateStats();

  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context);

  Future<void> setScreenShare(ScreenCaptureSource source);

  Future<void> stopScreenshare();

  Future<void> setCamera(MediaDeviceInfo? device);

  Future<void> stopCamera();
}
