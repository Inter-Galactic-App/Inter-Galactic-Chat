import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/bug_report/call_stream_bug_report_diagnostics.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  test('collect builds an identifier-free active stream snapshot', () async {
    final snapshot = VoipCallDiagnosticsSnapshot(
      collectedAt: DateTime.utc(2026, 7, 23, 11, 59, 58),
      screenShareProfileLabel: 'High',
      screenShareProfileDetails: '1920x1080 at 60 fps',
      adaptiveStreamEnabled: true,
      dynacastEnabled: true,
      screenShareSimulcastEnabled: false,
      adaptiveFallbackEnabled: true,
      adaptiveFallbackReason: 'receiver constrained',
      iceTransportSummary: 'connected/udp',
      participants: const [
        VoipParticipantDiagnostics(
          identity: 'private-livekit-identity',
          userId: '@private-user:example.test',
          clientLabel: 'Private Display Name',
        ),
      ],
      tracks: const [
        VoipTrackDiagnostics(
          streamId: 'private-stream-id',
          label: 'Private Display Name screen',
          type: VoipStreamType.screenshare,
          direction: VoipDiagnosticsTrackDirection.sender,
          width: 1920,
          height: 1080,
          captureFps: 60,
          encodeFps: 58,
          sendFps: 57,
          bitrateBps: 8_000_000,
          packetLossPercent: 0.5,
          codec: 'VP9',
          hardwareEncodeActive: true,
        ),
      ],
      callHealth: CallHealthSnapshot(
        collectedAt: DateTime.utc(2026, 7, 23, 11, 59, 59),
        lifecycle: CallConnectionLifecycle.connected,
        state: CallConnectionHealthState.good,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote-1',
            label: 'Private Display Name',
            isLocal: false,
            userId: '@private-user:example.test',
            connectionQuality: CallConnectionQuality.good,
            hasExpectedMicrophoneAudio: true,
            audioPublicationExists: true,
            audioTrackSubscribed: true,
            audioSinkAttached: true,
            effectiveVolume: 1,
            remoteAudioAudible: true,
          ),
        ],
      ),
    );
    final session = _FakeVoipSession(
      diagnosticsSnapshot: snapshot,
      streams: const [
        _FakeVoipStream(
          type: VoipStreamType.screenshare,
          direction: VoipStreamDirection.outgoing,
          streamId: 'private-stream-id',
          streamUserId: '@private-user:example.test',
          label: 'Private Display Name screen',
        ),
      ],
    );
    final collector = CallStreamBugReportDiagnostics.fromSources(
      sessions: () => [session],
      isDeafened: () => false,
      clock: () => DateTime.utc(2026, 7, 23, 12),
    );

    final result = await collector.collect(
      const BugReportInput(
        title: 'Stream stutters',
        reproductionSteps: 'Started sharing a game.',
        category: BugReportCategory.streaming,
        whatHappened: 'Viewers saw stutter.',
        frequency: BugReportFrequency.sometimes,
      ),
    );

    expect(result, isNotNull);
    expect(result!.scope, 'call_stream');
    expect(result.data['status'], 'active_call');
    expect(result.data['active_session_count'], 1);
    final sessions = result.data['sessions']! as List<Map<String, Object?>>;
    final sessionData = sessions.single;
    expect(sessionData['state'], 'connected');
    expect(sessionData['screen_sharing'], true);
    final diagnostics = sessionData['diagnostics']! as Map<String, Object?>;
    expect(diagnostics['participant_count'], 1);
    expect(diagnostics['track_count'], 1);
    final tracks = diagnostics['tracks']! as List<Map<String, Object?>>;
    expect(tracks.single, containsPair('width', 1920));
    expect(tracks.single, containsPair('codec', 'VP9'));

    final encoded = jsonEncode(result.toJson());
    expect(encoded, isNot(contains('private-livekit-identity')));
    expect(encoded, isNot(contains('@private-user:example.test')));
    expect(encoded, isNot(contains('Private Display Name')));
    expect(encoded, isNot(contains('private-stream-id')));
  });

  test(
    'collect skips unrelated categories and reports no active call',
    () async {
      final collector = CallStreamBugReportDiagnostics.fromSources(
        sessions: () => const [],
        isDeafened: () => true,
        clock: () => DateTime.utc(2026, 7, 23, 12),
      );

      final unrelated = await collector.collect(
        const BugReportInput(
          title: 'Message delayed',
          reproductionSteps: 'Opened a room.',
          category: BugReportCategory.messagesRooms,
          whatHappened: 'The message appeared late.',
          frequency: BugReportFrequency.once,
        ),
      );
      final call = await collector.collect(
        const BugReportInput(
          title: 'Call audio missing',
          reproductionSteps: 'Joined a call.',
          category: BugReportCategory.callAudio,
          whatHappened: 'No audio played.',
          frequency: BugReportFrequency.once,
        ),
      );

      expect(unrelated, isNull);
      expect(call, isNotNull);
      expect(call!.data['status'], 'no_active_call');
      expect(call.data['active_session_count'], 0);
      expect(call.data['deafened'], true);
      expect(call.logSummary, contains('states=none'));
    },
  );

  test(
    'caps serialized call-health participants and reports the omission',
    () async {
      // A large call must not push feature_diagnostics past the payload limit:
      // BugReportService drops the ENTIRE diagnostics map when it does, which
      // would lose every diagnostic in exactly the busy-call case this collector
      // exists to capture. Sessions and tracks were already capped; participants
      // were not.
      const totalParticipants = 40;
      final snapshot = VoipCallDiagnosticsSnapshot(
        collectedAt: DateTime.utc(2026, 7, 23, 11, 59, 58),
        screenShareProfileLabel: 'High',
        adaptiveStreamEnabled: true,
        dynacastEnabled: true,
        screenShareSimulcastEnabled: false,
        adaptiveFallbackEnabled: false,
        participants: const [],
        tracks: const [],
        callHealth: CallHealthSnapshot(
          collectedAt: DateTime.utc(2026, 7, 23, 11, 59, 59),
          lifecycle: CallConnectionLifecycle.connected,
          state: CallConnectionHealthState.good,
          participants: List<CallHealthParticipantSnapshot>.generate(
            totalParticipants,
            (index) => CallHealthParticipantSnapshot(
              sanitizedId: 'remote-$index',
              label: 'Crowd Member $index',
              isLocal: false,
              userId: '@crowd-$index:example.test',
              connectionQuality: CallConnectionQuality.good,
              hasExpectedMicrophoneAudio: true,
              audioPublicationExists: true,
              audioTrackSubscribed: true,
              audioSinkAttached: true,
              effectiveVolume: 1,
              remoteAudioAudible: true,
            ),
          ),
        ),
      );
      final collector = CallStreamBugReportDiagnostics.fromSources(
        sessions: () => [
          _FakeVoipSession(diagnosticsSnapshot: snapshot, streams: const []),
        ],
        isDeafened: () => false,
        clock: () => DateTime.utc(2026, 7, 23, 12),
      );

      final result = await collector.collect(
        const BugReportInput(
          title: 'Nobody can hear the host',
          reproductionSteps: 'Joined a large call.',
          category: BugReportCategory.callAudio,
          whatHappened: 'Audio dropped for most people.',
          frequency: BugReportFrequency.sometimes,
        ),
      );

      expect(result, isNotNull);
      final sessions = result!.data['sessions']! as List<Map<String, Object?>>;
      final diagnostics =
          sessions.single['diagnostics']! as Map<String, Object?>;
      final health = diagnostics['call_health']! as Map<String, Object?>;
      final participants =
          health['participants']! as List<Map<String, Object?>>;
      expect(participants, hasLength(16));
      expect(health['participants_omitted_count'], totalParticipants - 16);

      // The omission must not leak the identities it dropped.
      final encoded = jsonEncode(result.toJson());
      expect(encoded, isNot(contains('Crowd Member')));
      expect(encoded, isNot(contains('@crowd-')));
    },
  );
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession({required this.diagnosticsSnapshot, required this.streams});

  @override
  Never get client => throw UnimplementedError();

  @override
  String get sessionId => 'private-session-id';

  @override
  String get roomId => '!private-room:example.test';

  @override
  String? get remoteUserId => '@private-user:example.test';

  @override
  String? get remoteUserName => 'Private Display Name';

  @override
  String get roomName => 'Private Room Name';

  @override
  VoipState get state => VoipState.connected;

  @override
  bool get isMicrophoneMuted => false;

  @override
  bool get supportsScreenshare => true;

  @override
  bool get isSharingScreen => true;

  @override
  ShareSession? get currentShareSession => null;

  @override
  bool get isCameraEnabled => true;

  @override
  double get generalAudioLevel => 0.5;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  final List<VoipStream> streams;

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
  final VoipCallDiagnosticsSnapshot diagnosticsSnapshot;

  @override
  Stream<void> get onDiagnosticsChanged => const Stream<void>.empty();

  @override
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {}

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

class _FakeVoipStream implements VoipStream {
  const _FakeVoipStream({
    required this.type,
    required this.direction,
    required this.streamId,
    required this.streamUserId,
    required this.label,
  });

  @override
  final VoipStreamType type;

  @override
  final VoipStreamDirection direction;

  @override
  final String streamId;

  @override
  final String streamUserId;

  @override
  final String label;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.high;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}

  @override
  double get audiolevel => 0;

  @override
  bool get isMuted => false;

  @override
  double? get aspectRatio => 16 / 9;
}
