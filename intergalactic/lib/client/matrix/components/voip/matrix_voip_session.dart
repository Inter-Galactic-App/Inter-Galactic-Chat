import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/android_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/matrix/components/rtc_data_channel/matrix_rtc_data_channel_component.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_camera_release.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_stream.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart' as matrix;

class MatrixVoipSession implements VoipSession {
  matrix.CallSession session;

  @override
  late Client client;

  final StreamController<void> _onStateChanged = StreamController.broadcast();
  final StreamController<void> _onVolumeChanged = StreamController.broadcast();
  final StreamController<void> _onDiagnosticsChanged =
      StreamController.broadcast();
  VoipCallDiagnosticsSnapshot _diagnosticsSnapshot =
      VoipCallDiagnosticsSnapshot.empty();

  List<StatsReport>? stats;

  RTCDataChannel? channel;

  bool _active = true;
  bool _disposed = false;
  bool _streamsInitialized = false;
  Future<void>? _disposeFuture;
  Timer? _volumeTimer;
  final List<StreamSubscription> _subscriptions = [];
  final DirectCallCameraOperationQueue _cameraOperationQueue =
      DirectCallCameraOperationQueue();

  bool get _canRunCameraOperation => _active && !_disposed;

  ScreenCaptureSource? currentScreenshare;

  final StreamController<VoipState> _onConnectionChanged =
      StreamController.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _onConnectionChanged.stream;

  MatrixVoipSession(this.session, MatrixClient this.client) {
    _subscriptions.add(session.onCallStateChanged.stream.listen((event) {
      _onStateChanged.add(null);
      _onConnectionChanged.add(state);
      if (state == VoipState.ended) {
        unawaited(_disposeCallResources());
      }
    }));

    _volumeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (state == VoipState.ended) timer.cancel();
      _onVolumeChanged.add(());
    });

    initStreams();
    _subscriptions.add(session.onStreamAdd.stream.listen(onStreamAdded));
    _subscriptions.add(session.onStreamRemoved.stream.listen(onStreamRemoved));

    final dataComponent = client.getComponent<MatrixRTCDataChannelComponent>();
    if (dataComponent != null) {
      session.pc?.onDataChannel =
          (channel) => dataComponent.dataChannelOpenedCallback(this, channel);
    }
  }

  @override
  String? get remoteUserId => session.remoteUserId;

  @override
  String get roomId => session.room.id;

  @override
  String get sessionId => "${client.identifier}_${session.callId}";

  @override
  Stream<void> get onStateChanged => _onStateChanged.stream;

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot => _diagnosticsSnapshot;

  @override
  Stream<void> get onDiagnosticsChanged => _onDiagnosticsChanged.stream;

  @override
  bool get isMicrophoneMuted => session.isMicrophoneMuted;

  @override
  String? get remoteUserName => session.remoteUser?.displayName;

  @override
  bool get supportsScreenshare => !PlatformUtils.isIOS;

  @override
  bool get isSharingScreen => session.localScreenSharingStream != null;

  @override
  ShareSession? get currentShareSession {
    final source = currentScreenshare;
    if (source is ShareCaptureSource) {
      return source.shareSession;
    }

    return null;
  }

  @override
  bool get isCameraEnabled =>
      session.localUserMediaStream?.isVideoMuted() == false;

  @override
  VoipStream? get remoteUserMediaStream {
    final remoteStream = session.remoteUserMediaStream;
    if (remoteStream == null || !_streamsInitialized) {
      return null;
    }

    final remoteMediaStreamId = remoteStream.stream?.id;
    for (final stream in streams) {
      if (stream is! MatrixVoipStream) {
        continue;
      }

      if (identical(stream.stream, remoteStream) ||
          (remoteMediaStreamId != null &&
              stream.stream.stream?.id == remoteMediaStreamId)) {
        return stream;
      }
    }

    return null;
  }

  @override
  late List<VoipStream> streams;

  @override
  bool operator ==(Object other) {
    if (other is! MatrixVoipSession) return false;
    return sessionId == other.sessionId;
  }

  @override
  int get hashCode => sessionId.hashCode;

  @override
  VoipState get state {
    return switch (session.state) {
      matrix.CallState.kInviteSent => VoipState.outgoing,
      matrix.CallState.kCreateOffer => VoipState.outgoing,
      matrix.CallState.kCreateAnswer => VoipState.connecting,
      matrix.CallState.kConnecting => VoipState.connecting,
      matrix.CallState.kConnected => VoipState.connected,
      matrix.CallState.kRinging => VoipState.incoming,
      matrix.CallState.kEnded => VoipState.ended,
      _ => VoipState.unknown
    };
  }

  @override
  String get roomName => session.room.getLocalizedDisplayname();

  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) async {
    final audioReady = await IosCallAudioSession.prepareForCall(
      source: "matrix-direct-call-accept",
    );
    if (!audioReady) {
      throw Exception("iOS direct call audio session could not be prepared");
    }
    await WebrtcDefaultDevices.selectCallOutputDevice(
      source: "matrix-direct-call-accept",
    );

    var defaultStream = await WebrtcDefaultDevices.getDefaultMicrophone(
      bypassVoiceProcessing: PlatformUtils.isIOS,
    );

    if (defaultStream != null) {
      return session.answerWithStreams([
        matrix.WrappedMediaStream(
            stream: defaultStream,
            room: session.room,
            participant: session.localParticipant!,
            purpose: matrix.SDPStreamMetadataPurpose.Usermedia,
            client: session.room.client,
            audioMuted: false,
            videoMuted: true,
            isGroupCall: false,
            voip: session.voip),
      ]);
    } else {
      return session.answer();
    }
  }

  @override
  Future<void> declineCall() {
    return session.hangup(reason: matrix.CallErrorCode.userHangup);
  }

  @override
  Future<void> hangUpCall() async {
    _active = false;
    try {
      try {
        await stopScreenshare();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop direct-call screen share before hang-up',
        );
      }
      await session.hangup(reason: matrix.CallErrorCode.userHangup);
    } finally {
      await _disposeCallResources();
    }
  }

  @override
  Future<void> setMicrophoneMute(bool state) {
    return session.setMicrophoneMuted(state);
  }

  Future<void> setCameraEnabled(bool state) {
    if (state) {
      return _cameraOperationQueue.run(() async {
        if (!_canRunCameraOperation) {
          return;
        }
        await _setCamera(null);
      });
    }
    return stopCamera();
  }

  DateTime _lastUpdatedStats = DateTime.fromMicrosecondsSinceEpoch(0);
  @override
  Future<void> updateStats() async {
    var now = DateTime.now();
    var diff = now.difference(_lastUpdatedStats).inMilliseconds;

    if (diff < 500) {
      return;
    }

    if (_active) {
      stats = await session.pc?.getStats();
      if (_disposed || !_active || _onDiagnosticsChanged.isClosed) {
        return;
      }
      _lastUpdatedStats = now;
      _diagnosticsSnapshot = VoipCallDiagnosticsSnapshot(
        collectedAt: now,
        screenShareProfileLabel: 'Direct Matrix call',
        adaptiveStreamEnabled: false,
        dynacastEnabled: false,
        screenShareSimulcastEnabled: false,
        adaptiveFallbackEnabled: false,
        participants: const [],
        tracks: const [],
      );
      _onDiagnosticsChanged.add(null);
    }
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    MediaStream? stream;
    final shareSource = source is ShareCaptureSource ? source : null;
    final videoSource = shareSource?.videoSource ?? source;

    try {
      if (videoSource is WebrtcAndroidScreencaptureSource) {
        stream = await webrtc.navigator.mediaDevices.getDisplayMedia({
          'audio': true,
          'video': {
            'mandatory': {'frameRate': preferences.streamFramerate.value}
          }
        });
      }

      if (videoSource is WebrtcScreencaptureSource) {
        // Windows shared-content audio is owned by ShareSession, not the
        // microphone or getDisplayMedia constraints. Non-Windows desktop paths
        // may still receive a native audio track when the user asked for it.
        stream = await webrtc.navigator.mediaDevices.getDisplayMedia({
          'audio': !PlatformUtils.isWindows &&
              (shareSource?.shareSession.sharedAudioRequested ?? true),
          'video': {
            'width': 1920,
            'height': 1080,
            'deviceId': {'exact': videoSource.source.id},
            'mandatory': {'frameRate': preferences.streamFramerate.value}
          }
        });
      }

      if (stream != null) {
        final audioTracks = stream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          // Audio loopback was captured (platform supports it).
        }

        final shareSession = shareSource?.shareSession;
        await _attachWindowsSharedAudioTrack(stream, shareSession);

        // Stop any existing screenshare before adding the new one, then
        // update currentScreenshare only after a clean stop so that any
        // code that references it during teardown still sees the old value.
        await stopScreenshare();
        currentScreenshare = source;
        await session.addLocalStream(
            stream, matrix.SDPStreamMetadataPurpose.Screenshare);
        if (!PlatformUtils.isWindows) {
          try {
            await shareSession?.startSharedAudio();
          } catch (error, stackTrace) {
            Log.onError(
              error,
              stackTrace,
              content: 'Failed to start shared audio; continuing video-only',
            );
          }
        }
        _onStateChanged.add(null);
      }
    } catch (e, s) {
      await shareSource?.shareSession.stop();
      // Swallow the error so a failed screen-share attempt does not terminate
      // the call.  The screenshare simply stays inactive.
      Log.onError(e, s, content: "Failed to set direct-call screen share");
    }
  }

  Future<void> _attachWindowsSharedAudioTrack(
    MediaStream stream,
    ShareSession? shareSession,
  ) async {
    if (!PlatformUtils.isWindows ||
        shareSession == null ||
        !shareSession.sharedAudioRequested) {
      return;
    }

    final status = await shareSession.startSharedAudio();
    if (status.state != SharedAudioState.active || !status.pcmBridgeSupported) {
      return;
    }

    final audioStream = await shareSession.createSharedAudioPublicationStream();
    final audioTracks = audioStream?.getAudioTracks() ?? const [];
    if (audioTracks.isEmpty) {
      await shareSession.disposeSharedAudioPublicationStream();
      return;
    }

    try {
      await stream.addTrack(audioTracks.first);
    } catch (error, stackTrace) {
      await shareSession.disposeSharedAudioPublicationStream();
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to attach shared audio track to display stream',
      );
    }
  }

  @override
  Future<void> stopScreenshare() async {
    final shareSession = currentShareSession;

    // Snapshot the list before iterating: removeLocalStream modifies
    // session.getLocalStreams in-place, which would throw
    // ConcurrentModificationException on a lazy where()-iterable.
    final toRemove = session.getLocalStreams
        .where((e) => e.purpose == matrix.SDPStreamMetadataPurpose.Screenshare)
        .toList();
    for (final element in toRemove) {
      await session.removeLocalStream(element);
    }

    await shareSession?.stop();
    currentScreenshare = null;
    _onStateChanged.add(null);
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) {
    return _cameraOperationQueue.run(() async {
      if (!_canRunCameraOperation) {
        return;
      }
      await _setCamera(device);
    });
  }

  Future<void> _setCamera(MediaDeviceInfo? device) async {
    if (!_canRunCameraOperation) {
      return;
    }

    final localUserMediaStream = session.localUserMediaStream?.stream;
    if (localUserMediaStream == null) {
      if (!_canRunCameraOperation) {
        return;
      }
      await session.setLocalVideoMuted(false);
      return;
    }

    if (localUserMediaStream
            .getTracks()
            .any((element) => element.kind == "video") ==
        false) {
      if (!_canRunCameraOperation) {
        return;
      }
      await session.insertVideoTrackToAudioOnlyStream();
    }

    if (!_canRunCameraOperation) {
      return;
    }
    await session.setLocalVideoMuted(false);
  }

  @override
  Future<void> stopCamera() {
    return _cameraOperationQueue.run(() async {
      if (!_canRunCameraOperation) {
        return;
      }
      await _stopCamera();
    });
  }

  Future<void> _stopCamera() async {
    if (!_canRunCameraOperation) {
      return;
    }

    try {
      if (!_canRunCameraOperation) {
        return;
      }
      await session.setLocalVideoMuted(true);
    } finally {
      if (_canRunCameraOperation) {
        await _releaseLocalCameraCapture();
      }
    }
  }

  Future<void> _releaseLocalCameraCapture() async {
    final localUserMediaStream = session.localUserMediaStream;
    if (localUserMediaStream == null) {
      return;
    }

    final stream = localUserMediaStream.stream;
    if (stream == null) {
      return;
    }

    final stoppedTracks = await stopAndRemoveDirectCallCameraTracks(
      stream,
      onError: (error, stackTrace, content) {
        Log.onError(error, stackTrace, content: content);
      },
    );

    if (stoppedTracks == 0) {
      return;
    }

    Log.i(
      'Direct Matrix call camera capture released: '
      'stopped $stoppedTracks video track(s)',
    );
    localUserMediaStream.onStreamChanged.add(stream);
    if (!_disposed && !_onStateChanged.isClosed) {
      _onStateChanged.add(null);
    }
  }

  void initStreams() {
    List<MatrixVoipStream> result = List.empty(growable: true);

    var s = List<matrix.WrappedMediaStream>.from(session.getLocalStreams,
        growable: true);
    s.addAll(session.getRemoteStreams);

    for (var stream in s) {
      if (!shouldAddStream(stream)) {
        continue;
      }

      if (!result
          .any((element) => element.stream.stream?.id == stream.stream?.id)) {
        result.add(MatrixVoipStream(stream, this));
      }
    }

    streams = result;
    _streamsInitialized = true;
  }

  bool shouldAddStream(matrix.WrappedMediaStream stream) {
    if (stream.purpose == matrix.SDPStreamMetadataPurpose.Screenshare &&
        stream.videoMuted) {
      return false;
    }

    if (![
      matrix.SDPStreamMetadataPurpose.Screenshare,
      matrix.SDPStreamMetadataPurpose.Usermedia
    ].contains(stream.purpose)) {
      return false;
    }

    return true;
  }

  void onStreamAdded(matrix.WrappedMediaStream event) {
    if (_disposed) {
      return;
    }

    if (shouldAddStream(event) &&
        !streams.any((stream) => stream.streamId == event.stream?.id)) {
      streams.add(MatrixVoipStream(event, this));
      if (!_disposed) {
        _onStateChanged.add(null);
      }
    }
  }

  void onStreamRemoved(matrix.WrappedMediaStream event) {
    if (_disposed) {
      return;
    }

    final removed =
        streams.where((e) => e.streamId == event.stream?.id).toList();
    streams.removeWhere((e) => e.streamId == event.stream?.id);
    for (final stream in removed) {
      if (stream is MatrixVoipStream) {
        unawaited(stream.dispose());
      }
    }
    if (!_disposed) {
      _onStateChanged.add(null);
    }
  }

  Future<void> _disposeCallResources() {
    if (_disposed) {
      return Future<void>.value();
    }

    final existingDispose = _disposeFuture;
    if (existingDispose != null) {
      return existingDispose;
    }

    _disposeFuture = _disposeCallResourcesOnce();
    return _disposeFuture!;
  }

  Future<void> _disposeCallResourcesOnce() async {
    final shareSession = currentShareSession;
    if (shareSession != null || isSharingScreen) {
      try {
        await stopScreenshare();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop direct-call screen share during teardown',
        );
      }
    }

    _disposed = true;
    _active = false;
    _volumeTimer?.cancel();
    _volumeTimer = null;
    await _onDiagnosticsChanged.close();
    await _onStateChanged.close();
    await _onVolumeChanged.close();
    await _onConnectionChanged.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    if (_streamsInitialized) {
      for (final stream in streams.whereType<MatrixVoipStream>()) {
        await stream.dispose();
      }
      streams = [];
    }
  }

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    if (PlatformUtils.isIOS) {
      return null;
    }
    return WebrtcScreencaptureSource.showSelectSourcePrompt(context);
  }

  @override
  double get generalAudioLevel => (remoteUserMediaStream?.audiolevel ?? 0) * 3;

  @override
  Stream<void> get onUpdateVolumeVisualizers => _onVolumeChanged.stream;
}
