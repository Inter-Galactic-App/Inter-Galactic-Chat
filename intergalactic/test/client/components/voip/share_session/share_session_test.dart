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

    test('video-only desktop source still resolves window process metadata',
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
    });

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

    test('publication bridge delegates to capable shared audio source',
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
    });

    test('publication bridge is null for non-publication audio source',
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
    });

    test('windows audio source waits for native starting state to settle',
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
    });
  });
}

ShareSession _buildSession({
  required SharedAudioSource audioSource,
}) {
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
  }) : _status = const SharedAudioStatus(
          state: SharedAudioState.stopped,
          mode: SharedAudioMode.none,
          reason: 'not_started',
        );

  @override
  final bool requested;

  @override
  final SharedAudioMode mode;

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
  }) async {
    return 1;
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
      int sessionId) async {
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
      osBuild: 20348,
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
    return _nativeStatus(
      WindowsSharedAudioState.stopped,
      reason: 'stopped',
    );
  }
}

WindowsShareSessionStatus _nativeStatus(
  WindowsSharedAudioState state, {
  bool active = false,
  String reason = 'ready',
  bool pcmBridgeSupported = false,
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
    packetsCaptured: 0,
    framesCaptured: 0,
    bytesCaptured: 0,
    pcmBridgeSupported: pcmBridgeSupported,
    wgcReady: false,
    reason: reason,
  );
}
