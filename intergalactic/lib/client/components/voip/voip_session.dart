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

  /// Hang-up has started but has not finished releasing the call.
  ///
  /// Exists because the three flags that used to describe this - `_ending`,
  /// `_hangUpFuture` and `_transientCallResourcesDisposed` - are all private to
  /// the session, so the join guard could not see that a session was dying and
  /// handed the dying session back to the next `joinCall()`.
  ///
  /// A session in this state is not joinable and is not a usable call. Treat it
  /// as "on its way to [ended]", never as a live session.
  leaving,
  ended,
}

extension VoipStateLifecycle on VoipState {
  /// True once the call is over or is on its way out.
  ///
  /// Use this instead of `state == VoipState.ended` anywhere the question is
  /// "should this session still be treated as a live call". Before [leaving]
  /// existed the two were the same question, so consumers spelled it as an
  /// equality check against [ended]; adding a state silently made every one of
  /// those sites treat a dying call as live for the whole teardown window.
  ///
  /// Kept here, beside the enum, so the next state added has one place to be
  /// classified rather than N call sites to be found.
  bool get isFinishing => this == VoipState.leaving || this == VoipState.ended;
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

  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  });

  Future<void> declineCall();

  Future<void> hangUpCall();

  Stream<VoipState> get onConnectionStateChanged;

  Stream<void> get onStateChanged;

  Stream<void> get onUpdateVolumeVisualizers;

  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot;

  Stream<void> get onDiagnosticsChanged;

  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true});

  Future<void> updateStats();

  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context);

  Future<void> setScreenShare(ScreenCaptureSource source);

  Future<void> stopScreenshare();

  Future<void> setCamera(MediaDeviceInfo? device);

  Future<void> stopCamera();
}
