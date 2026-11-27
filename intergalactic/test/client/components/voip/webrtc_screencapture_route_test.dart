import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

/// Route-level coverage entered where a screen share actually acquires audio.
///
/// These go in through `WebrtcScreencaptureSource.captureSourceFor` rather than
/// constructing a `ShareSession` directly, so they cover the step that decides
/// whether audio is requested at all and how a failure there is handled. What
/// sits above it - `desktopCapturer` discovery, thumbnail warming, the picker
/// dialog - is source selection and carries no shared-audio behaviour.
void main() {
  group('screen-capture route: audio request', () {
    test(
      'a share asked for without audio never opens a capture session',
      () async {
        final binding = _FakeBinding();

        final capture = await WebrtcScreencaptureSource.captureSourceFor(
          _FakeSource(id: 'window:1', name: 'Some Game'),
          shareAudio: false,
          nativeBinding: binding,
        );

        expect(capture.shareSession.sharedAudioRequested, isFalse);
        await capture.shareSession.startSharedAudio();
        expect(
          binding.createdSessions,
          isEmpty,
          reason: 'Declining audio must not reach the native layer at all.',
        );
      },
    );

    test(
      'a share asked for with audio requests it on the way through',
      () async {
        final binding = _FakeBinding();

        final capture = await WebrtcScreencaptureSource.captureSourceFor(
          _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
          shareAudio: true,
          nativeBinding: binding,
        );

        expect(capture.shareSession.sharedAudioRequested, isTrue);
        expect(capture.videoSource, isA<WebrtcScreencaptureSource>());

        // The flag alone proves only that the route recorded the request. The
        // negative test above asserts the native side; without the same
        // assertion here the positive claim in this test's name is unverified.
        await capture.shareSession.startSharedAudio();
        expect(
          binding.createdSessions,
          isNotEmpty,
          reason: 'Requesting audio must reach the native layer.',
        );
      },
    );
  });

  group('screen-capture route: lifecycle', () {
    test('a failed start leaves the share running video-only', () async {
      final binding = _FakeBinding(
        startState: WindowsSharedAudioState.failed,
        startReason: 'process_loopback_activation_failed',
      );

      final capture = await WebrtcScreencaptureSource.captureSourceFor(
        _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
        shareAudio: true,
        nativeBinding: binding,
      );
      final status = await capture.shareSession.startSharedAudio();

      expect(status.state, SharedAudioState.failed);
      expect(
        capture.shareSession.lifecycle,
        ShareSessionLifecycle.videoOnly,
        reason: 'Audio failing must not take the screen share down with it.',
      );
    });

    test('a native throw during start is contained, not propagated', () async {
      final binding = _FakeBinding(throwOnStart: true);

      final capture = await WebrtcScreencaptureSource.captureSourceFor(
        _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
        shareAudio: true,
        nativeBinding: binding,
      );

      final status = await capture.shareSession.startSharedAudio();

      expect(status.state, SharedAudioState.failed);
      expect(capture.shareSession.lifecycle, ShareSessionLifecycle.videoOnly);
    });

    test('stopping a share releases the session it created', () async {
      final binding = _FakeBinding();

      final capture = await WebrtcScreencaptureSource.captureSourceFor(
        _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
        shareAudio: true,
        nativeBinding: binding,
      );
      await capture.shareSession.startSharedAudio();
      await capture.shareSession.stop();

      expect(binding.createdSessions, isNotEmpty);
      expect(
        binding.disposedSessions,
        containsAll(binding.createdSessions),
        reason: 'Every session the route created must be released.',
      );
    });

    // Named for what it actually exercises. `captureSourceFor` builds a fresh
    // `WindowsSharedAudioSource` per call, and each of those constructs its own
    // `WindowsSharedAudioBackend` because no backend is injected - the two share
    // only the fake binding. So the second start supersedes nothing inside any
    // backend, and the disposal asserted below is caused solely by the explicit
    // stop. Backend-level supersede is covered in
    // `windows_shared_audio_backend_test.dart`, where one backend is reused.
    test(
      'stopping an outgoing share after a replacement releases it',
      () async {
        final binding = _FakeBinding();

        final first = await WebrtcScreencaptureSource.captureSourceFor(
          _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
          shareAudio: true,
          nativeBinding: binding,
        );
        await first.shareSession.startSharedAudio();

        final second = await WebrtcScreencaptureSource.captureSourceFor(
          _FakeSource(id: 'screen:2', name: 'Screen 2', isWindow: false),
          shareAudio: true,
          nativeBinding: binding,
        );
        await second.shareSession.startSharedAudio();

        // The replaced share is stopped by the caller that swapped it out.
        await first.shareSession.stop();

        expect(binding.createdSessions, hasLength(2));
        expect(
          binding.disposedSessions,
          contains(binding.createdSessions.first),
        );
      },
    );

    test('stopping twice does not double-release', () async {
      final binding = _FakeBinding();

      final capture = await WebrtcScreencaptureSource.captureSourceFor(
        _FakeSource(id: 'screen:1', name: 'Screen 1', isWindow: false),
        shareAudio: true,
        nativeBinding: binding,
      );
      await capture.shareSession.startSharedAudio();

      await capture.shareSession.stop();
      await capture.shareSession.stop();

      final disposed = binding.disposedSessions;
      expect(
        disposed.toSet().length,
        disposed.length,
        reason: 'A session must not be disposed twice.',
      );
    });
  });
}

class _FakeSource implements DesktopCapturerSource {
  _FakeSource({required this.id, required this.name, this.isWindow = true});

  @override
  final String id;

  @override
  final String name;

  final bool isWindow;

  @override
  SourceType get type => isWindow ? SourceType.Window : SourceType.Screen;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBinding implements WindowsShareNativeBinding {
  _FakeBinding({
    this.startState = WindowsSharedAudioState.active,
    this.startReason = 'capturing',
    this.throwOnStart = false,
  });

  final WindowsSharedAudioState startState;
  final String startReason;
  final bool throwOnStart;

  final List<int> createdSessions = [];
  final List<int> disposedSessions = [];

  int _next = 1;

  // The route only reaches the native layer on Windows; forcing this true is
  // what lets the route be exercised on any host.
  @override
  bool get isSupported => true;

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
      osBuild: 19045,
      documentedProcessLoopbackBuild: 20348,
      processLoopbackHresult: '0x0',
      processLoopbackStage: WindowsSharedAudioFailureStage.none,
      reason: 'ready',
    );
  }

  @override
  Future<List<WindowsAudioEndpointInfo>> listAudioEndpoints() async => const [];

  @override
  Future<List<WindowsShareTargetInfo>> listTargets() async => const [];

  @override
  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
    String deviceId = '',
  }) async {
    final id = _next++;
    createdSessions.add(id);
    return id;
  }

  @override
  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) async {
    if (throwOnStart) {
      throw StateError('native start refused');
    }
    return _status(sessionId, startState);
  }

  @override
  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) async =>
      _status(sessionId, WindowsSharedAudioState.stopped);

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async =>
      _status(sessionId, startState);

  WindowsShareSessionStatus _status(
    int sessionId,
    WindowsSharedAudioState state,
  ) {
    return WindowsShareSessionStatus(
      sessionId: sessionId,
      supported: true,
      requestedAudio: true,
      targetType: WindowsShareTargetType.display,
      audioMode: WindowsSharedAudioMode.systemLoopback,
      audioState: state,
      active: state == WindowsSharedAudioState.active,
      sampleRateHz: 44100,
      numChannels: 2,
      bitsPerSample: 16,
      packetsCaptured: 10,
      framesCaptured: 100,
      bytesCaptured: 400,
      nonsilentBytesCaptured: 400,
      targetElevated: false,
      targetElevationKnown: true,
      pcmBridgeSupported: true,
      wgcReady: true,
      lastHresult: '0x0',
      failureStage: WindowsSharedAudioFailureStage.none,
      selectedDeviceId: '',
      reason: startReason,
    );
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
    int sessionId,
  ) async => WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);

  @override
  Future<void> disposeSharedAudioStream(int sessionId) async {}

  @override
  Future<void> disposeSession(int sessionId) async {
    disposedSessions.add(sessionId);
  }
}
