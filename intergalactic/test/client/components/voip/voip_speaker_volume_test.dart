import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/config/preferences.dart';

void main() {
  group('VoIP speaker volume', () {
    test('defaults above normal playback gain for quieter calls', () {
      expect(Preferences.defaultVoipSpeakerVolume, 125.0);
      expect(
        Preferences.voipSpeakerVolumeToLocalPlayback(
          Preferences.defaultVoipSpeakerVolume,
        ),
        1.25,
      );
    });

    test('maps speaker preference to the local playback range', () {
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(-20), 0.0);
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(0), 0.0);
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(50), 0.5);
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(100), 1.0);
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(200), 2.0);
      expect(Preferences.voipSpeakerVolumeToLocalPlayback(250), 2.0);
    });

    test('uses a stream snapshot while applying current speaker volume',
        () async {
      final manager = ClientManager().callManager;
      final streams = <VoipStream>[];
      final removedStream = _FakeLocalPlaybackStream(streamId: 'removed');
      final firstStream = _FakeLocalPlaybackStream(
        streamId: 'first',
        onSetDefaultLocalVolume: () {
          streams.remove(removedStream);
        },
      );
      streams.addAll([firstStream, removedStream]);

      await manager.applySpeakerVolumeToSessionForTesting(
        _FakeVoipSession(streams),
      );

      expect(streams, [firstStream]);
      expect(firstStream.defaultLocalVolumes, [1.25]);
      expect(removedStream.defaultLocalVolumes, [1.25]);
    });
  });
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession(this.streams);

  @override
  final List<VoipStream> streams;

  @override
  Client get client => throw UnimplementedError();

  @override
  String get sessionId => 'session';

  @override
  String get roomId => '!room:example.test';

  @override
  String? get remoteUserId => '@remote:example.test';

  @override
  String? get remoteUserName => 'Remote';

  @override
  String get roomName => 'Room';

  @override
  VoipState get state => VoipState.connected;

  @override
  bool get isMicrophoneMuted => false;

  @override
  bool get supportsScreenshare => false;

  @override
  bool get isSharingScreen => false;

  @override
  ShareSession? get currentShareSession => null;

  @override
  bool get isCameraEnabled => false;

  @override
  double get generalAudioLevel => 0;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) async {}

  @override
  Future<void> declineCall() async {}

  @override
  Future<void> hangUpCall() async {}

  @override
  Stream<VoipState> get onConnectionStateChanged =>
      const Stream<VoipState>.empty();

  @override
  Stream<void> get onStateChanged => const Stream<void>.empty();

  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream<void>.empty();

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot =>
      throw UnimplementedError();

  @override
  Stream<void> get onDiagnosticsChanged => const Stream<void>.empty();

  @override
  Future<void> setMicrophoneMute(bool state) async {}

  @override
  Future<void> updateStats() async {}

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    return null;
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {}

  @override
  Future<void> stopScreenshare() async {}

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {}

  @override
  Future<void> stopCamera() async {}
}

class _FakeLocalPlaybackStream
    implements VoipStream, LocalPlaybackVolumeStream {
  _FakeLocalPlaybackStream({
    required this.streamId,
    this.onSetDefaultLocalVolume,
  });

  final void Function()? onSetDefaultLocalVolume;
  final List<double> defaultLocalVolumes = [];

  @override
  final String streamId;

  @override
  VoipStreamType get type => VoipStreamType.audio;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.medium;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}

  @override
  String get streamUserId => '@remote:example.test';

  @override
  String get label => streamId;

  @override
  double get audiolevel => 0;

  @override
  bool get isMuted => false;

  @override
  double? get aspectRatio => null;

  @override
  bool get hasLocalPlaybackAudio => true;

  @override
  bool get hasLocalPlaybackVolumeOverride => false;

  @override
  double get localVolume =>
      defaultLocalVolumes.isEmpty ? 1 : defaultLocalVolumes.last;

  @override
  bool get locallyMuted => false;

  @override
  Future<void> setLocalVolume(double volume) async {}

  @override
  Future<void> setDefaultLocalVolume(double volume) async {
    defaultLocalVolumes.add(volume);
    onSetDefaultLocalVolume?.call();
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void clearLocalPlaybackVolumeOverride() {}
}
