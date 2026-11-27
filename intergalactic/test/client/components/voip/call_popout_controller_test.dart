import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_panel.dart';
import 'package:intergalactic/utils/call_popout_controller.dart';

void main() {
  group('CallPopoutController', () {
    test('full session popout clears and blocks per-stream popouts', () {
      final controller = CallPopoutController();

      controller.popOutStream('session-1', 'participant:@friend:example.org');
      expect(controller.hasPoppedStreams('session-1'), isTrue);

      controller.popOutSession('session-1');
      expect(controller.isSessionPoppedOut('session-1'), isTrue);
      expect(controller.hasPoppedStreams('session-1'), isFalse);
      expect(controller.poppedStreams, isEmpty);

      controller.popOutStream('session-1', 'participant:@friend:example.org');
      expect(controller.hasPoppedStreams('session-1'), isFalse);
    });

    test('native detached configuration selects full-session route', () {
      final logs = <String>[];
      final controller = CallPopoutController(diagnosticLogger: logs.add);

      expect(controller.fullSessionPopoutRoute, 'desktop-fallback-session');

      controller.configureNativeDetachedSessions(
        enabled: true,
        focusSessionWindow: (_) async {},
      );

      expect(controller.usesNativeDetachedSessionPopouts, isTrue);
      expect(controller.fullSessionPopoutRoute, 'native-session');
      expect(
        logs,
        contains(contains('event=native_session_configured enabled=true')),
      );
      expect(logs, contains(contains('route=native-session')));

      controller.popOutSession('session-1');

      expect(
        logs,
        contains(contains('event=pop_out_session route=native-session')),
      );

      controller.configureNativeDetachedSessions(enabled: false);

      expect(controller.usesNativeDetachedSessionPopouts, isFalse);
      expect(controller.fullSessionPopoutRoute, 'desktop-fallback-session');
      expect(logs, contains(contains('route=desktop-fallback-session')));
    });

    test('stream popouts use overlay route until native streams configure', () {
      final logs = <String>[];
      final controller = CallPopoutController(diagnosticLogger: logs.add);

      expect(controller.usesNativeDetachedStreamPopouts, isFalse);
      expect(controller.streamPopoutRoute, 'stream-overlay');

      controller.popOutStream('session-1', 'participant:@friend:example.org');

      expect(
        logs,
        contains(contains('event=pop_out_stream route=stream-overlay')),
      );
      expect(controller.hasPoppedStreams('session-1'), isTrue);
    });

    test('native detached stream configuration selects stream route', () async {
      final logs = <String>[];
      final focused = <String>[];
      final pinChanges = <String, bool>{};
      final transparentChanges = <String, bool>{};
      final controller = CallPopoutController(diagnosticLogger: logs.add);

      controller.configureNativeDetachedStreams(
        enabled: true,
        focusStreamWindow: (sessionId, streamId) async {
          focused.add('$sessionId::$streamId');
        },
        isStreamAlwaysOnTop: (sessionId, streamId) async {
          return pinChanges['$sessionId::$streamId'] ?? false;
        },
        setStreamAlwaysOnTop: (sessionId, streamId, value) async {
          pinChanges['$sessionId::$streamId'] = value;
        },
        isStreamTransparentChrome: (sessionId, streamId) async {
          return transparentChanges['$sessionId::$streamId'] ?? false;
        },
        setStreamTransparentChrome: (sessionId, streamId, value) async {
          transparentChanges['$sessionId::$streamId'] = value;
        },
      );

      expect(controller.usesNativeDetachedStreamPopouts, isTrue);
      expect(controller.streamPopoutRoute, 'native-stream');
      expect(
        logs,
        contains(contains('event=native_stream_configured enabled=true')),
      );

      controller.popOutStream('session-1', 'participant:@friend:example.org');

      expect(
        logs,
        contains(contains('event=pop_out_stream route=native-stream')),
      );

      await controller.focusStreamWindow(
        'session-1',
        'participant:@friend:example.org',
      );
      await controller.setStreamWindowAlwaysOnTop(
        'session-1',
        'participant:@friend:example.org',
        true,
      );
      await controller.setStreamWindowTransparentChrome(
        'session-1',
        'participant:@friend:example.org',
        true,
      );

      expect(focused, ['session-1::participant:@friend:example.org']);
      expect(
        await controller.isStreamWindowAlwaysOnTop(
          'session-1',
          'participant:@friend:example.org',
        ),
        isTrue,
      );
      expect(
        await controller.isStreamWindowTransparentChrome(
          'session-1',
          'participant:@friend:example.org',
        ),
        isTrue,
      );

      controller.configureNativeDetachedStreams(enabled: false);

      expect(controller.usesNativeDetachedStreamPopouts, isFalse);
      expect(controller.streamPopoutRoute, 'stream-overlay');
      expect(logs, contains(contains('route=stream-overlay')));
      expect(
        await controller.isStreamWindowAlwaysOnTop(
          'session-1',
          'participant:@friend:example.org',
        ),
        isFalse,
      );
    });

    test(
      'native stream window failure falls back without restoring stream',
      () {
        final logs = <String>[];
        final controller = CallPopoutController(diagnosticLogger: logs.add);

        controller.configureNativeDetachedStreams(
          enabled: true,
          focusStreamWindow: (_, __) async {},
        );
        controller.popOutStream('session-1', 'participant:@friend:example.org');

        controller.markNativeDetachedStreamsUnavailable(
          reason: 'window_create_failed',
        );

        expect(controller.usesNativeDetachedStreamPopouts, isFalse);
        expect(controller.streamPopoutRoute, 'stream-overlay');
        expect(controller.hasPoppedStreams('session-1'), isTrue);
        expect(controller.poppedStreamCount, 1);
        expect(
          logs,
          contains(
            contains('event=native_stream_unavailable route=stream-overlay'),
          ),
        );
      },
    );

    test(
      'native stream fallback keeps active entries until explicit cleanup',
      () {
        final controller = CallPopoutController();
        const streamId = 'participant:@friend:example.org';

        controller.configureNativeDetachedStreams(
          enabled: true,
          focusStreamWindow: (_, __) async {},
        );
        controller.popOutStream('session-1', streamId);

        controller.markNativeDetachedStreamsUnavailable(
          reason: 'window_create_failed',
        );
        controller.clearMissingSessions(['session-1']);

        expect(controller.usesNativeDetachedStreamPopouts, isFalse);
        expect(controller.isStreamPoppedOut('session-1', streamId), isTrue);
        expect(controller.streamPopoutRoute, 'stream-overlay');

        controller.restoreStream('session-1', streamId);

        expect(controller.isStreamPoppedOut('session-1', streamId), isFalse);
        expect(controller.poppedStreams, isEmpty);
      },
    );

    test('sweep after the session leaves clears the popped-out flag', () {
      final controller = CallPopoutController();
      final session = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );

      controller.popOutSession('session-1', sessionInstance: session);
      expect(controller.isSessionPoppedOut('session-1'), isTrue);

      // A sweep taken while the dying session is still in the list - which is
      // what NotifyingList's emit-before-remove produces - must not clear it.
      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': session},
      );
      expect(controller.isSessionPoppedOut('session-1'), isTrue);

      controller.clearMissingSessions(
        const <String>[],
        activeSessionInstances: const {},
      );
      expect(controller.isSessionPoppedOut('session-1'), isFalse);
    });

    test(
      'rejoin with the same session id clears the stale popped-out flag',
      () {
        final logs = <String>[];
        final controller = CallPopoutController(diagnosticLogger: logs.add);
        final firstJoin = _FakeVoipSession(
          sessionId: 'session-1',
          streams: const [],
        );
        final rejoin = _FakeVoipSession(
          sessionId: 'session-1',
          streams: const [],
        );

        // See the guard in 'rejoin also clears stream popouts': these two are
        // distinct only because both literals are non-const.
        expect(identical(firstJoin, rejoin), isFalse);

        controller.popOutSession('session-1', sessionInstance: firstJoin);
        expect(controller.isSessionPoppedOut('session-1'), isTrue);

        // sessionId is client_room_stateKey: identical for every join of the
        // same room from the same device. Only the instance can tell the stale
        // flag from a live one.
        controller.clearMissingSessions(
          const ['session-1'],
          activeSessionInstances: {'session-1': rejoin},
        );

        expect(controller.isSessionPoppedOut('session-1'), isFalse);
        expect(logs, contains(contains('replaced_session_instances=1')));
      },
    );

    test('rejoin also clears stream popouts left over from the last call', () {
      final controller = CallPopoutController();
      const streamId = 'participant:@friend:example.org';
      final firstJoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      final rejoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      // `_FakeVoipSession` has a const constructor and these two are built from
      // identical arguments. They are distinct only because both invocations
      // are non-const; adding `const` to either literal would make Dart
      // canonicalize them into one object, and this test - whose entire subject
      // is instance identity - would then assert the opposite of what it says,
      // with no compile error. Fail here instead.
      expect(
        identical(firstJoin, rejoin),
        isFalse,
        reason:
            'the two joins must be distinct instances for this test to '
            'mean anything; do not make these literals const',
      );

      controller.popOutStream(
        'session-1',
        streamId,
        sessionInstance: firstJoin,
      );
      expect(controller.isStreamPoppedOut('session-1', streamId), isTrue);

      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': rejoin},
      );

      expect(controller.isStreamPoppedOut('session-1', streamId), isFalse);
    });

    test('callers that only know the session id keep the old behaviour', () {
      final controller = CallPopoutController();
      final rejoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );

      // The mobile picture-in-picture path pops out by id only.
      controller.popOutSession('session-1');

      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': rejoin},
      );
      expect(controller.isSessionPoppedOut('session-1'), isTrue);

      controller.clearMissingSessions(const ['session-1']);
      expect(controller.isSessionPoppedOut('session-1'), isTrue);
    });

    test('restoring a session forgets its recorded instance', () {
      final controller = CallPopoutController();
      final firstJoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      final rejoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );

      // See the guard in 'rejoin also clears stream popouts': these two are
      // distinct only because both literals are non-const.
      expect(identical(firstJoin, rejoin), isFalse);

      controller.popOutSession('session-1', sessionInstance: firstJoin);
      controller.restoreSession('session-1');
      controller.popOutSession('session-1', sessionInstance: rejoin);

      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': rejoin},
      );

      expect(controller.isSessionPoppedOut('session-1'), isTrue);
    });

    // The two sibling paths that also drop the recorded instance. If either
    // stops doing it, the stale identity hash survives and the next
    // `clearMissingSessions` sweep reads a LIVE popout as "replaced" and clears
    // it - rendering the popped-out placeholder over a call that is not popped
    // out. The restoreSession path above was covered; these were not.
    test('restoring the last stream forgets the recorded instance', () {
      final controller = CallPopoutController();
      const streamId = 'participant:@friend:example.org';
      final firstJoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      final rejoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      expect(identical(firstJoin, rejoin), isFalse);

      controller.popOutStream(
        'session-1',
        streamId,
        sessionInstance: firstJoin,
      );
      controller.restoreStream('session-1', streamId);

      // Re-pop against the NEW instance, then sweep with that same instance
      // active. A retained hash from `firstJoin` would make this read as a
      // replacement and clear it.
      controller.popOutStream('session-1', streamId, sessionInstance: rejoin);
      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': rejoin},
      );

      expect(controller.isStreamPoppedOut('session-1', streamId), isTrue);
    });

    test('clearForSession forgets the recorded instance', () {
      final controller = CallPopoutController();
      final firstJoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      final rejoin = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [],
      );
      expect(identical(firstJoin, rejoin), isFalse);

      controller.popOutSession('session-1', sessionInstance: firstJoin);
      controller.clearForSession('session-1');

      controller.popOutSession('session-1', sessionInstance: rejoin);
      controller.clearMissingSessions(
        const ['session-1'],
        activeSessionInstances: {'session-1': rejoin},
      );

      expect(controller.isSessionPoppedOut('session-1'), isTrue);
    });
  });

  group('callStreamPopoutIdForStream', () {
    test('uses participant identity for ordinary audio and video tiles', () {
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.audio,
            streamUserId: '@friend:example.org',
          ),
        ),
        'participant:@friend:example.org',
      );
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.video,
            streamUserId: '@friend:example.org',
          ),
        ),
        'participant:@friend:example.org',
      );
    });

    test('uses screenshare identity for non-LiveKit screenshares', () {
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.screenshare,
            streamUserId: '@friend:example.org',
          ),
        ),
        'screenshare:@friend:example.org',
      );
    });
  });

  group('resolveCallStreamPopoutFromSessions', () {
    test('resolves camera participant stream with participant audio', () {
      const video = _FakeVoipStream(
        type: VoipStreamType.video,
        streamUserId: '@friend:example.org',
        streamId: 'video-stream',
      );
      const audio = _FakeVolumeVoipStream(
        type: VoipStreamType.audio,
        streamUserId: '@friend:example.org',
        streamId: 'audio-stream',
      );
      final session = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [audio, video],
      );

      final resolved = resolveCallStreamPopoutFromSessions(
        sessions: [session],
        sessionId: 'session-1',
        streamId: 'participant:@friend:example.org',
      );

      expect(resolved, isNotNull);
      expect(resolved!.stream, same(video));
      expect(resolved.audioStream, same(audio));
      expect(resolved.volumeStream, same(audio));
      expect(resolved.popoutId, 'participant:@friend:example.org');
    });

    test(
      'resolves screenshare stream with screenshare audio volume target',
      () {
        const screen = _FakeVoipStream(
          type: VoipStreamType.screenshare,
          streamUserId: '@friend:example.org',
          streamId: 'screen-stream',
        );
        const microphone = _FakeLiveKitVolumeVoipStream(
          type: VoipStreamType.audio,
          streamUserId: '@friend:example.org',
          streamId: 'mic-audio-stream',
        );
        const screenAudio = _FakeLiveKitVolumeVoipStream(
          type: VoipStreamType.audio,
          streamUserId: '@friend:example.org',
          streamId: 'screen-audio-stream',
          isScreenShareAudio: true,
        );
        final session = _FakeVoipSession(
          sessionId: 'session-1',
          streams: const [microphone, screenAudio, screen],
        );

        final resolved = resolveCallStreamPopoutFromSessions(
          sessions: [session],
          sessionId: 'session-1',
          streamId: 'screenshare:@friend:example.org',
        );

        expect(resolved, isNotNull);
        expect(resolved!.stream, same(screen));
        expect(resolved.audioStream, same(microphone));
        expect(resolved.volumeStream, same(screenAudio));
        expect(resolved.popoutId, 'screenshare:@friend:example.org');
      },
    );

    test('returns null when the requested session or stream is gone', () {
      final session = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [
          _FakeVoipStream(
            type: VoipStreamType.video,
            streamUserId: '@friend:example.org',
          ),
        ],
      );

      expect(
        resolveCallStreamPopoutFromSessions(
          sessions: [session],
          sessionId: 'missing-session',
          streamId: 'participant:@friend:example.org',
        ),
        isNull,
      );
      expect(
        resolveCallStreamPopoutFromSessions(
          sessions: [session],
          sessionId: 'session-1',
          streamId: 'participant:@other:example.org',
        ),
        isNull,
      );
    });

    test('detects stopped local screenshare before native close docks it', () {
      const screen = _FakeVoipStream(
        type: VoipStreamType.screenshare,
        streamUserId: '@me:example.org',
        streamId: 'screen-stream',
      );
      final session = _FakeVoipSession(
        sessionId: 'session-1',
        streams: const [screen],
        diagnosticsSnapshot: _diagnosticsWithScreenCaptureFps(
          streamId: 'screen-stream',
          captureFps: 0,
        ),
      );

      final resolved = resolveCallStreamPopoutFromSessions(
        sessions: [session],
        sessionId: 'session-1',
        streamId: 'screenshare:@me:example.org',
      );

      expect(resolved, isNotNull);
      expect(
        shouldStopDeadLocalScreensharePopoutOnNativeClose(
          popout: resolved,
          localUserId: '@me:example.org',
        ),
        isTrue,
      );
    });

    test(
      'keeps active and remote screenshare native close behavior as dock',
      () {
        const localScreen = _FakeVoipStream(
          type: VoipStreamType.screenshare,
          streamUserId: '@me:example.org',
          streamId: 'local-screen-stream',
        );
        const remoteScreen = _FakeVoipStream(
          type: VoipStreamType.screenshare,
          streamUserId: '@friend:example.org',
          streamId: 'remote-screen-stream',
        );
        final session = _FakeVoipSession(
          sessionId: 'session-1',
          streams: const [localScreen, remoteScreen],
          diagnosticsSnapshot: VoipCallDiagnosticsSnapshot(
            collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
            screenShareProfileLabel: 'Balanced',
            adaptiveStreamEnabled: true,
            dynacastEnabled: true,
            screenShareSimulcastEnabled: false,
            adaptiveFallbackEnabled: false,
            participants: const [],
            tracks: const [
              VoipTrackDiagnostics(
                streamId: 'local-screen-stream',
                label: 'send screenshare',
                type: VoipStreamType.screenshare,
                direction: VoipDiagnosticsTrackDirection.sender,
                captureFps: 30,
              ),
              VoipTrackDiagnostics(
                streamId: 'remote-screen-stream',
                label: 'receive screenshare',
                type: VoipStreamType.screenshare,
                direction: VoipDiagnosticsTrackDirection.receiver,
                captureFps: 0,
              ),
            ],
          ),
        );

        final localResolved = resolveCallStreamPopoutFromSessions(
          sessions: [session],
          sessionId: 'session-1',
          streamId: 'screenshare:@me:example.org',
        );
        final remoteResolved = resolveCallStreamPopoutFromSessions(
          sessions: [session],
          sessionId: 'session-1',
          streamId: 'screenshare:@friend:example.org',
        );

        expect(
          shouldStopDeadLocalScreensharePopoutOnNativeClose(
            popout: localResolved,
            localUserId: '@me:example.org',
          ),
          isFalse,
        );
        expect(
          shouldStopDeadLocalScreensharePopoutOnNativeClose(
            popout: remoteResolved,
            localUserId: '@me:example.org',
          ),
          isFalse,
        );
      },
    );
  });
}

VoipCallDiagnosticsSnapshot _diagnosticsWithScreenCaptureFps({
  required String streamId,
  required double captureFps,
}) {
  return VoipCallDiagnosticsSnapshot(
    collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
    screenShareProfileLabel: 'Balanced',
    adaptiveStreamEnabled: true,
    dynacastEnabled: true,
    screenShareSimulcastEnabled: false,
    adaptiveFallbackEnabled: false,
    participants: const [],
    tracks: [
      VoipTrackDiagnostics(
        streamId: streamId,
        label: 'send screenshare',
        type: VoipStreamType.screenshare,
        direction: VoipDiagnosticsTrackDirection.sender,
        captureFps: captureFps,
      ),
    ],
  );
}

class _FakeVoipStream implements VoipStream {
  const _FakeVoipStream({
    required this.type,
    required this.streamUserId,
    this.streamId = 'fake-stream',
  });

  @override
  final VoipStreamType type;

  @override
  final String streamUserId;

  @override
  final String streamId;

  @override
  double? get aspectRatio => 1;

  @override
  double get audiolevel => 0;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get isMuted => false;

  @override
  String get label => 'fake';

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.high;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}
}

class _FakeVolumeVoipStream extends _FakeVoipStream
    implements LocalPlaybackVolumeStream {
  const _FakeVolumeVoipStream({
    required super.type,
    required super.streamUserId,
    super.streamId,
  });

  @override
  bool get hasLocalPlaybackAudio => true;

  @override
  bool get hasLocalPlaybackVolumeOverride => false;

  @override
  double get localVolume => 1.0;

  @override
  bool get locallyMuted => false;

  @override
  Future<void> setLocalVolumePreservingMute(double volume) async {}

  @override
  void clearLocalPlaybackVolumeOverride() {}

  @override
  Future<void> setLocalVolume(double volume) async {}

  @override
  Future<void> setDefaultLocalVolume(double volume) async {}
}

class _FakeLiveKitVolumeVoipStream extends _FakeVolumeVoipStream
    implements MatrixLivekitVoipStream {
  const _FakeLiveKitVolumeVoipStream({
    required super.type,
    required super.streamUserId,
    super.streamId,
    this.isScreenShareAudio = false,
  });

  @override
  final bool isScreenShareAudio;

  @override
  bool get isMicrophoneAudio => !isScreenShareAudio;

  @override
  String get participantIdentity => streamUserId;

  @override
  set audiolevel(double value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipSession implements VoipSession {
  const _FakeVoipSession({
    required this.sessionId,
    required this.streams,
    VoipCallDiagnosticsSnapshot? diagnosticsSnapshot,
  }) : _diagnosticsSnapshot = diagnosticsSnapshot;

  @override
  final String sessionId;

  @override
  final List<VoipStream> streams;

  final VoipCallDiagnosticsSnapshot? _diagnosticsSnapshot;

  @override
  String get roomName => 'Call Room';

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot =>
      _diagnosticsSnapshot ?? VoipCallDiagnosticsSnapshot.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
