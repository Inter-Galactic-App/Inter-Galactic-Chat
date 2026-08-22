import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

void main() {
  group('ShareSession', () {
    test('keeps mic source separate from shared audio source', () {
      final session = _buildSession(
        audioSource: _FakeSharedAudioSource(
          requested: true,
          mode: SharedAudioMode.systemLoopback,
          startStatus: const SharedAudioStatus(
            state: SharedAudioState.active,
            mode: SharedAudioMode.systemLoopback,
            reason: 'capturing',
          ),
        ),
      );

      expect(session.micSource.enabled, isTrue);
      expect(session.micSource.rnnoiseApplies, isTrue);
      expect(session.sharedAudioSource.mode, SharedAudioMode.systemLoopback);
    });

    test('marks session as sharing when shared audio starts', () async {
      final audioSource = _FakeSharedAudioSource(
        requested: true,
        mode: SharedAudioMode.systemLoopback,
        startStatus: const SharedAudioStatus(
          state: SharedAudioState.active,
          mode: SharedAudioMode.systemLoopback,
          reason: 'capturing',
        ),
      );
      final session = _buildSession(audioSource: audioSource);

      final status = await session.startSharedAudio();

      expect(status.state, SharedAudioState.active);
      expect(session.lifecycle, ShareSessionLifecycle.sharing);
      expect(audioSource.startCalls, 1);
    });

    test('continues video-only when shared audio is unavailable', () async {
      final session = _buildSession(
        audioSource: _FakeSharedAudioSource(
          requested: true,
          mode: SharedAudioMode.unavailable,
          startStatus: const SharedAudioStatus(
            state: SharedAudioState.unavailable,
            mode: SharedAudioMode.unavailable,
            reason: 'target_process_unresolved',
          ),
        ),
      );

      final status = await session.startSharedAudio();

      expect(status.state, SharedAudioState.unavailable);
      expect(status.reason, 'target_process_unresolved');
      expect(session.lifecycle, ShareSessionLifecycle.videoOnly);
    });

    test('disabled shared audio also runs video-only', () async {
      final session = _buildSession(
        audioSource: const DisabledSharedAudioSource(),
      );

      final status = await session.startSharedAudio();

      expect(status.state, SharedAudioState.disabled);
      expect(session.lifecycle, ShareSessionLifecycle.videoOnly);
    });

    test(
      'video-only desktop source still resolves window process metadata',
      () async {
        final binding = _FakeWindowsShareBinding(
          startStatus: _nativeStatus(
            WindowsSharedAudioState.inactive,
            reason: 'not_started',
          ),
          targets: const [
            WindowsShareTargetInfo(
              windowHandle: 98765,
              processId: 4321,
              title: 'Baldur\'s Gate 3',
            ),
          ],
        );
        final source = _FakeDesktopCapturerSource(
          id: 'window:98765',
          name: 'Baldur\'s Gate 3',
          type: SourceType.Window,
        );

        final session = await ShareSession.forDesktopCapturerSource(
          source,
          shareAudio: false,
          nativeBinding: binding,
        );

        expect(session.target.processId, 4321);
        expect(session.sharedAudioSource, isA<DisabledSharedAudioSource>());
        expect(binding.listTargetCalls, 1);
      },
    );

    test('stop tears down shared audio source', () async {
      final audioSource = _FakeSharedAudioSource(
        requested: true,
        mode: SharedAudioMode.processTreeLoopback,
        startStatus: const SharedAudioStatus(
          state: SharedAudioState.active,
          mode: SharedAudioMode.processTreeLoopback,
          reason: 'capturing',
        ),
      );
      final session = _buildSession(audioSource: audioSource);

      await session.startSharedAudio();
      await session.stop();

      expect(audioSource.stopCalls, 1);
      expect(audioSource.disposeCalls, 1);
      expect(session.lifecycle, ShareSessionLifecycle.stopped);
    });

    test('a failing dispose still completes the stop', () async {
      // `WindowsSharedAudioBackend.dispose()` reports a failed native release
      // rather than swallowing it, so `stop()` can throw after the capture has
      // already stopped cleanly. When it did, `lifecycle` stayed at `stopping`
      // forever and the stop evidence line - the only durable record of what
      // the capture did - was never emitted.
      final audioSource = _FakeSharedAudioSource(
        requested: true,
        mode: SharedAudioMode.processTreeLoopback,
        startStatus: const SharedAudioStatus(
          state: SharedAudioState.active,
          mode: SharedAudioMode.processTreeLoopback,
          reason: 'capturing',
        ),
        throwOnDispose: true,
      );
      final session = _buildSession(audioSource: audioSource);

      await session.startSharedAudio();

      await expectLater(session.stop(), completes);
      expect(audioSource.stopCalls, 1);
      expect(audioSource.disposeCalls, 1);
      expect(
        session.lifecycle,
        ShareSessionLifecycle.stopped,
        reason: 'A share left at `stopping` can never be reported as ended.',
      );
    });

    test(
      'publication bridge delegates to capable shared audio source',
      () async {
        final audioSource = _FakePublishingSharedAudioSource(
          requested: true,
          mode: SharedAudioMode.systemLoopback,
          startStatus: const SharedAudioStatus(
            state: SharedAudioState.active,
            mode: SharedAudioMode.systemLoopback,
            reason: 'capturing',
            pcmBridgeSupported: true,
          ),
        );
        final session = _buildSession(audioSource: audioSource);

        await session.startSharedAudio();

        expect(await session.createSharedAudioPublicationStream(), isNull);
        expect(audioSource.createPublicationCalls, 1);

        await session.disposeSharedAudioPublicationStream();

        expect(audioSource.disposePublicationCalls, 1);
      },
    );

    test('an attempt that never reached the native layer reports a '
        'single-token reason', () async {
      // `reason=` is a field of the space-separated `key=value` evidence line
      // (`_audioEvidenceLine`, `ShareSessionDiagnosticSummary.audioLine`).
      // The fallback status for an attempt that never reached the native layer
      // used to put the user-facing sentence in `nativeReason`, which is
      // defined as the platform's own token, and it was copied straight into
      // that field - so one refusal broke the parse of the whole line.
      final binding = _FakeWindowsShareBinding(
        startStatus: _nativeStatus(
          WindowsSharedAudioState.inactive,
          reason: 'not_started',
        ),
      );
      final source = WindowsSharedAudioSource(
        nativeBinding: binding,
        // A window share whose owning process could not be resolved: refused
        // by the backend before any native session is created.
        target: const ShareTarget(
          type: ShareTargetType.window,
          sourceId: 'window:1',
          title: 'Some Game',
        ),
        requested: true,
        mode: SharedAudioMode.processTreeLoopback,
      );

      final status = await source.start();

      expect(status.state, SharedAudioState.unavailable);
      expect(status.reason, 'target_process_unresolved');
      expect(
        status.reason,
        isNot(contains(' ')),
        reason: 'a sentence here runs into the next key=value field',
      );
    });

    test(
      'publication bridge is null for non-publication audio source',
      () async {
        final session = _buildSession(
          audioSource: _FakeSharedAudioSource(
            requested: true,
            mode: SharedAudioMode.systemLoopback,
            startStatus: const SharedAudioStatus(
              state: SharedAudioState.active,
              mode: SharedAudioMode.systemLoopback,
              reason: 'capturing',
            ),
          ),
        );

        expect(await session.createSharedAudioPublicationStream(), isNull);
      },
    );

    test(
      'windows audio source waits for native starting state to settle',
      () async {
        const target = ShareTarget(
          type: ShareTargetType.display,
          sourceId: 'screen:0',
          title: 'Display 1',
        );
        final binding = _FakeWindowsShareBinding(
          startStatus: _nativeStatus(
            WindowsSharedAudioState.starting,
            reason: 'starting',
          ),
          statusResponses: [
            _nativeStatus(
              WindowsSharedAudioState.active,
              active: true,
              reason: 'capturing',
              pcmBridgeSupported: true,
            ),
          ],
        );
        final audioSource = WindowsSharedAudioSource(
          nativeBinding: binding,
          target: target,
          requested: true,
          mode: SharedAudioMode.systemLoopback,
        );

        final status = await audioSource.start();

        expect(status.state, SharedAudioState.active);
        expect(status.reason, 'capturing');
        expect(status.pcmBridgeSupported, isTrue);
        expect(binding.statusCalls, 1);
      },
    );
  });

  group('SharedAudioStatus.advisory', () {
    SharedAudioStatus status({
      SharedAudioState state = SharedAudioState.active,
      int packetsCaptured = 0,
      int nonsilentBytesCaptured = 0,
      bool targetProcessElevated = false,
      bool targetElevationKnown = false,
      String reason = 'capturing',
    }) {
      return SharedAudioStatus(
        state: state,
        mode: SharedAudioMode.processTreeLoopback,
        reason: reason,
        packetsCaptured: packetsCaptured,
        nonsilentBytesCaptured: nonsilentBytesCaptured,
        targetProcessElevated: targetProcessElevated,
        targetElevationKnown: targetElevationKnown,
      );
    }

    test('none when active audio is flowing', () {
      final advisory = status(
        packetsCaptured: 1000,
        nonsilentBytesCaptured: 88200,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.none);
      expect(advisory.hasAdvisory, isFalse);
    });

    test('elevated target takes priority even before silence is confirmed', () {
      final advisory = status(
        packetsCaptured: 0,
        targetProcessElevated: true,
        targetElevationKnown: true,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.targetElevated);
      expect(advisory.detail, contains('administrator'));
    });

    test('elevated target wins over the silence heuristic', () {
      final advisory = status(
        packetsCaptured: 5000,
        nonsilentBytesCaptured: 0,
        targetProcessElevated: true,
        targetElevationKnown: true,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.targetElevated);
    });

    test('silence advisory only after enough evidence packets', () {
      final tooEarly = status(
        packetsCaptured: kSharedAudioSilenceEvidencePackets - 1,
        nonsilentBytesCaptured: 0,
      );
      expect(tooEarly.isCapturingOnlySilence, isFalse);
      expect(tooEarly.advisory.kind, SharedAudioAdvisoryKind.none);

      final confirmed = status(
        packetsCaptured: kSharedAudioSilenceEvidencePackets,
        nonsilentBytesCaptured: 0,
      );
      expect(confirmed.isCapturingOnlySilence, isTrue);
      expect(confirmed.advisory.kind, SharedAudioAdvisoryKind.capturingSilence);
    });

    test('no silence advisory when non-silent audio has been captured', () {
      final advisory = status(
        packetsCaptured: 5000,
        nonsilentBytesCaptured: 1,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.none);
    });

    test('no silence advisory before the session is active', () {
      final advisory = status(
        state: SharedAudioState.starting,
        packetsCaptured: 5000,
        nonsilentBytesCaptured: 0,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.none);
    });

    test('offers the whole-computer alternative when Windows refuses '
        'per-application capture', () {
      final advisory = status(
        state: SharedAudioState.unavailable,
        reason: kSharedAudioProcessLoopbackUnsupportedReason,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.processLoopbackRefused);
      expect(advisory.hasAdvisory, isTrue);

      final detail = advisory.detail.toLowerCase();
      // Whole-screen audio now has a real endpoint-loopback path that does
      // not need process loopback, so it is a genuine alternative rather
      // than a dead end.
      expect(detail, contains('all sound from this computer'));
      expect(detail, contains('video'));
      // The refusal is measured, so the copy must not blame the Windows
      // version or send the user off to update it.
      expect(detail, isNot(contains('20348')));
      expect(detail, isNot(contains('windows 11')));
      expect(detail, isNot(contains('update')));
      // Broadening the capture must be stated, not slipped in.
      expect(detail, contains('other apps'));
    });

    test('elevated target still wins over the refused-capture advisory', () {
      final advisory = status(
        state: SharedAudioState.unavailable,
        reason: kSharedAudioProcessLoopbackUnsupportedReason,
        targetProcessElevated: true,
        targetElevationKnown: true,
      ).advisory;
      expect(advisory.kind, SharedAudioAdvisoryKind.targetElevated);
    });
  });
}

ShareSession _buildSession({required SharedAudioSource audioSource}) {
  const target = ShareTarget(
    type: ShareTargetType.display,
    sourceId: 'screen:0',
    title: 'Display 1',
  );

  return ShareSession(
    target: target,
    videoSource: const _FakeScreenVideoSource(target),
    sharedAudioSource: audioSource,
  );
}

class _FakeScreenVideoSource implements ScreenVideoSource {
  const _FakeScreenVideoSource(this.target);

  @override
  final ShareTarget target;
}

class _FakeSharedAudioSource implements SharedAudioSource {
  _FakeSharedAudioSource({
    required this.requested,
    required this.mode,
    required this.startStatus,
    this.throwOnDispose = false,
  }) : _status = const SharedAudioStatus(
         state: SharedAudioState.stopped,
         mode: SharedAudioMode.none,
         reason: 'not_started',
       );

  @override
  final bool requested;

  @override
  final SharedAudioMode mode;

  /// Reproduces `WindowsSharedAudioSource.dispose()`, which forwards
  /// `WindowsSharedAudioBackend.dispose()` and therefore rethrows when the
  /// native session release fails.
  final bool throwOnDispose;

  final SharedAudioStatus startStatus;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  SharedAudioStatus _status;

  @override
  SharedAudioState get state => _status.state;

  @override
  SharedAudioStatus get status => _status;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (throwOnDispose) {
      throw StateError('native session dispose failed');
    }
  }

  @override
  Future<SharedAudioStatus> start() async {
    startCalls += 1;
    _status = startStatus;
    return _status;
  }

  @override
  Future<SharedAudioStatus> stop() async {
    stopCalls += 1;
    _status = SharedAudioStatus(
      state: SharedAudioState.stopped,
      mode: mode,
      reason: 'stopped',
    );
    return _status;
  }
}

class _FakePublishingSharedAudioSource extends _FakeSharedAudioSource
    implements SharedAudioPublicationSource {
  _FakePublishingSharedAudioSource({
    required super.requested,
    required super.mode,
    required super.startStatus,
  });

  int createPublicationCalls = 0;
  int disposePublicationCalls = 0;

  @override
  Future<MediaStream?> createPublicationStream() async {
    createPublicationCalls += 1;
    return null;
  }

  @override
  Future<void> disposePublicationStream() async {
    disposePublicationCalls += 1;
  }
}

class _FakeDesktopCapturerSource implements DesktopCapturerSource {
  _FakeDesktopCapturerSource({
    required this.id,
    required this.name,
    required this.type,
  });

  @override
  final String id;

  @override
  final String name;

  @override
  final SourceType type;

  @override
  Uint8List? get thumbnail => null;

  @override
  ThumbnailSize get thumbnailSize => ThumbnailSize(360, 220);

  @override
  final StreamController<String> onNameChanged =
      StreamController<String>.broadcast(sync: true);

  @override
  final StreamController<Uint8List> onThumbnailChanged =
      StreamController<Uint8List>.broadcast(sync: true);
}

class _FakeWindowsShareBinding implements WindowsShareNativeBinding {
  _FakeWindowsShareBinding({
    required this.startStatus,
    this.statusResponses = const [],
    this.targets = const [],
  });

  final WindowsShareSessionStatus startStatus;
  final List<WindowsShareSessionStatus> statusResponses;
  final List<WindowsShareTargetInfo> targets;
  int statusCalls = 0;
  int listTargetCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
    String deviceId = '',
  }) async {
    return 1;
  }

  @override
  Future<List<WindowsAudioEndpointInfo>> listAudioEndpoints() async => const [];

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
    int sessionId,
  ) async {
    return WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);
  }

  @override
  Future<void> disposeSession(int sessionId) async {}

  @override
  Future<void> disposeSharedAudioStream(int sessionId) async {}

  @override
  Future<WindowsShareCapabilities> getCapabilities() async {
    return const WindowsShareCapabilities(
      supported: true,
      applicationLoopbackSupported: true,
      processTreeLoopbackSupported: true,
      wgcSupported: true,
      pcmBridgeSupported: true,
      endpointLoopbackSupported: true,
      deviceCaptureSupported: true,
      hasVirtualAudioDevice: false,
      osBuild: 20348,
      documentedProcessLoopbackBuild: 20348,
      processLoopbackHresult: '0x0',
      processLoopbackStage: WindowsSharedAudioFailureStage.none,
      reason: 'ready',
    );
  }

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async {
    final index = statusCalls;
    statusCalls += 1;
    if (index < statusResponses.length) {
      return statusResponses[index];
    }

    return startStatus;
  }

  @override
  Future<List<WindowsShareTargetInfo>> listTargets() async {
    listTargetCalls += 1;
    return targets;
  }

  @override
  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) async {
    return startStatus;
  }

  @override
  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) async {
    return _nativeStatus(WindowsSharedAudioState.stopped, reason: 'stopped');
  }
}

WindowsShareSessionStatus _nativeStatus(
  WindowsSharedAudioState state, {
  bool active = false,
  String reason = 'ready',
  bool pcmBridgeSupported = false,
  int packetsCaptured = 0,
  int nonsilentBytesCaptured = 0,
  bool targetElevated = false,
  bool targetElevationKnown = false,
}) {
  return WindowsShareSessionStatus(
    sessionId: 1,
    supported: true,
    requestedAudio: true,
    targetType: WindowsShareTargetType.display,
    audioMode: WindowsSharedAudioMode.systemLoopback,
    audioState: state,
    active: active,
    sampleRateHz: active ? 44100 : 0,
    numChannels: active ? 2 : 0,
    bitsPerSample: active ? 16 : 0,
    packetsCaptured: packetsCaptured,
    framesCaptured: 0,
    bytesCaptured: 0,
    nonsilentBytesCaptured: nonsilentBytesCaptured,
    targetElevated: targetElevated,
    targetElevationKnown: targetElevationKnown,
    pcmBridgeSupported: pcmBridgeSupported,
    wgcReady: false,
    lastHresult: '0x0',
    failureStage: WindowsSharedAudioFailureStage.none,
    selectedDeviceId: '',
    reason: reason,
  );
}
