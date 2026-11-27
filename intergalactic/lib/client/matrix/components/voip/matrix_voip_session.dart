import 'dart:async';

import 'package:intergalactic/client/bug_report/pending_native_call_crash_guard.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/android_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/matrix/components/rtc_data_channel/matrix_rtc_data_channel_component.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_camera_release.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_media_operation_gate.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_owner.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_stream.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart' as matrix;

typedef DirectCallStreamDisposeOperation = Future<void> Function();

@visibleForTesting
Future<void> debugCancelDirectCallSessionSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelDirectCallSessionSubscription(subscription);
}

Future<void> _cancelDirectCallSessionSubscription(
  StreamSubscription? subscription,
) async {
  try {
    await subscription?.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered direct-call session subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'direct-call-session-subscription',
    );
  }
}

@visibleForTesting
Future<void> debugDisposeDirectCallStreamForTesting(
  DirectCallStreamDisposeOperation dispose,
) {
  return _disposeDirectCallStream(dispose);
}

Future<void> _disposeDirectCallStream(
  DirectCallStreamDisposeOperation dispose, {
  String content = 'Failed to dispose direct-call stream',
}) async {
  try {
    await dispose();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: content,
      category: LogCategory.webrtc,
      source: 'direct-call-stream-dispose',
    );
  }
}

class MatrixVoipSession implements DirectCallSession {
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

  bool get _isEnded => state == VoipState.ended;

  bool get _canRunDirectCallMediaOperation =>
      DirectCallMediaOperationGate.shouldRun(
        active: _active,
        ended: _isEnded,
        disposed: _disposed,
      );

  bool get _canProcessDirectCallStreamListEvent =>
      DirectCallMediaOperationGate.shouldProcessStreamListEvent(
        active: _active,
        ended: _isEnded,
        disposed: _disposed,
      );

  bool get _canRunCameraOperation => _canRunDirectCallMediaOperation;

  bool _canNotifyDirectCallTransient({required bool closed}) {
    return DirectCallMediaOperationGate.shouldNotifyTransient(
      active: _active,
      ended: _isEnded,
      disposed: _disposed,
      closed: closed,
    );
  }

  void _notifyStateChanged() {
    if (DirectCallMediaOperationGate.shouldNotify(
      disposed: _disposed,
      closed: _onStateChanged.isClosed,
    )) {
      _onStateChanged.add(null);
    }
  }

  void _notifyConnectionChanged() {
    if (DirectCallMediaOperationGate.shouldNotify(
      disposed: _disposed,
      closed: _onConnectionChanged.isClosed,
    )) {
      _onConnectionChanged.add(state);
    }
  }

  void _notifyVolumeChanged() {
    if (_canNotifyDirectCallTransient(closed: _onVolumeChanged.isClosed)) {
      _onVolumeChanged.add(());
    }
  }

  void _notifyDiagnosticsChanged() {
    if (_canNotifyDirectCallTransient(closed: _onDiagnosticsChanged.isClosed)) {
      _onDiagnosticsChanged.add(null);
    }
  }

  ScreenCaptureSource? currentScreenshare;

  final StreamController<VoipState> _onConnectionChanged =
      StreamController.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _onConnectionChanged.stream;

  MatrixVoipSession(this.session, MatrixClient this.client) {
    _subscriptions.add(
      session.onCallStateChanged.stream.listen((event) {
        _notifyStateChanged();
        _notifyConnectionChanged();
        if (state == VoipState.ended) {
          _active = false;
          unawaited(_disposeCallResources());
        }
      }),
    );

    _volumeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_canNotifyDirectCallTransient(closed: _onVolumeChanged.isClosed)) {
        timer.cancel();
        return;
      }
      _notifyVolumeChanged();
    });

    initStreams();
    _subscriptions.add(session.onStreamAdd.stream.listen(onStreamAdded));
    _subscriptions.add(session.onStreamRemoved.stream.listen(onStreamRemoved));

    final dataComponent = client.getComponent<MatrixRTCDataChannelComponent>();
    if (dataComponent != null) {
      session.pc?.onDataChannel = (channel) =>
          dataComponent.dataChannelOpenedCallback(this, channel);
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
      _ => VoipState.unknown,
    };
  }

  @override
  String get roomName => session.room.getLocalizedDisplayname();

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) async {
    final nativeCrashGuard = await PendingNativeCallCrashGuard.record(
      source: 'matrix-direct-native-call-accept',
      callKind: 'Direct Matrix incoming call',
    );

    try {
      final audioReady = await IosCallAudioSession.prepareForCall(
        source: "matrix-direct-call-accept",
        // Direct 1:1 calls always bypass native voice processing (BUG-168);
        // native NS is scoped to the LiveKit/group path only.
        forceBypassVoiceProcessing: true,
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

      await IosCallAudioSession.ensureVoiceProcessingConfigured(
        source: "matrix-direct-call-accept-answer",
        forceBypassVoiceProcessing: true,
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
            voip: session.voip,
          ),
        ]);
      } else {
        return session.answer();
      }
    } finally {
      await nativeCrashGuard?.clear();
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
        await _stopScreenshare(
          recordNativeCrashGuard: false,
          allowDuringTeardown: true,
        );
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
  Future<void> setMicrophoneMute(bool muted, {bool stopOnMute = true}) async {
    if (!_canRunDirectCallMediaOperation) {
      return;
    }

    final nativeCrashGuard = muted
        ? null
        : await PendingNativeCallCrashGuard.recordAction(
            source: 'matrix-direct-native-call-action-microphone-enable',
            actionKind: 'Direct Matrix microphone enable',
          );
    try {
      if (!_canRunDirectCallMediaOperation) {
        return;
      }
      await session.setMicrophoneMuted(muted);
    } finally {
      await nativeCrashGuard?.clear();
    }
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

    if (!_canRunDirectCallMediaOperation) {
      return;
    }

    stats = await session.pc?.getStats();
    if (!_canRunDirectCallMediaOperation) {
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
      callHealth: _buildCallHealthSnapshot(now),
    );
    _notifyDiagnosticsChanged();
  }

  CallHealthSnapshot _buildCallHealthSnapshot(DateTime collectedAt) {
    return CallHealthSnapshot.derive(
      collectedAt: collectedAt,
      lifecycle: _callLifecycleForState(state),
      participants: _directCallHealthParticipants(stats),
    );
  }

  List<CallHealthParticipantSnapshot> _directCallHealthParticipants(
    List<StatsReport>? reports,
  ) {
    final currentReports = reports ?? const <StatsReport>[];
    final networkQuality = _directCallNetworkQuality(currentReports);
    final remoteAudioStatsAvailable = _hasDirectCallInboundAudioStats(
      currentReports,
    );
    final remoteAudioLevel = _directCallInboundAudioLevel(currentReports);

    return [
      CallHealthParticipantSnapshot(
        sanitizedId: 'local',
        label: 'You',
        isLocal: true,
        userId: client.self?.identifier,
        connectionQuality: networkQuality,
      ),
      if (currentReports.isNotEmpty)
        CallHealthParticipantSnapshot(
          sanitizedId: 'remote_1',
          label: _directCallRemoteParticipantLabel,
          isLocal: false,
          userId: remoteUserId,
          connectionQuality: _directCallRemoteQuality(currentReports),
          hasExpectedMicrophoneAudio: remoteAudioStatsAvailable,
          audioPublicationExists: remoteAudioStatsAvailable,
          audioTrackSubscribed: remoteAudioStatsAvailable,
          audioSinkAttached: remoteAudioStatsAvailable,
          remoteAudioAudible: remoteAudioLevel == null
              ? null
              : remoteAudioLevel > 0,
          remoteAudioReason: remoteAudioStatsAvailable
              ? 'direct_call_audio_stats'
              : null,
        ),
    ];
  }

  String get _directCallRemoteParticipantLabel {
    final displayName = remoteUserName?.trim();
    final userId = remoteUserId?.trim();
    if (displayName != null &&
        displayName.isNotEmpty &&
        displayName != userId) {
      return displayName;
    }

    return 'Remote participant 1';
  }

  CallConnectionQuality _directCallNetworkQuality(List<StatsReport> reports) {
    var quality = CallConnectionQuality.unknown;
    for (final report in reports) {
      if (report.type != 'candidate-pair' ||
          !_isSelectedCandidatePair(report)) {
        continue;
      }
      quality = _worseDirectCallQuality(
        quality,
        _qualityForRoundTripTimeSeconds(
          _statsDouble(report, 'currentRoundTripTime') ??
              _statsDouble(report, 'roundTripTime'),
        ),
      );
    }
    return quality;
  }

  CallConnectionQuality _directCallRemoteQuality(List<StatsReport> reports) {
    var quality = _directCallNetworkQuality(reports);
    for (final report in reports) {
      if (!_isAudioStatsReport(report) ||
          report.type != 'inbound-rtp' && report.type != 'remote-inbound-rtp') {
        continue;
      }
      quality = _worseDirectCallQuality(
        quality,
        _qualityForPacketLoss(
          packetsLost: _statsDouble(report, 'packetsLost'),
          packetsReceived: _statsDouble(report, 'packetsReceived'),
        ),
      );
      quality = _worseDirectCallQuality(
        quality,
        _qualityForJitterSeconds(_statsDouble(report, 'jitter')),
      );
      quality = _worseDirectCallQuality(
        quality,
        _qualityForRoundTripTimeSeconds(_statsDouble(report, 'roundTripTime')),
      );
    }
    return quality;
  }

  bool _hasDirectCallInboundAudioStats(List<StatsReport> reports) {
    return reports.any(
      (report) => report.type == 'inbound-rtp' && _isAudioStatsReport(report),
    );
  }

  double? _directCallInboundAudioLevel(List<StatsReport> reports) {
    for (final report in reports) {
      if (report.type != 'inbound-rtp' || !_isAudioStatsReport(report)) {
        continue;
      }
      final audioLevel = _statsDouble(report, 'audioLevel');
      if (audioLevel != null) {
        return audioLevel;
      }
    }
    return null;
  }

  bool _isSelectedCandidatePair(StatsReport report) {
    final selected = report.values['selected'];
    if (selected == true || selected == 'true') {
      return true;
    }
    final nominated = report.values['nominated'];
    final state = report.values['state']?.toString().toLowerCase();
    return (nominated == true || nominated == 'true') &&
        (state == null || state == 'succeeded');
  }

  bool _isAudioStatsReport(StatsReport report) {
    final values = report.values;
    return values['kind'] == 'audio' ||
        values['mediaType'] == 'audio' ||
        values['trackKind'] == 'audio' ||
        report.id.toLowerCase().contains('audio');
  }

  double? _statsDouble(StatsReport report, String key) {
    final value = report.values[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  CallConnectionQuality _qualityForRoundTripTimeSeconds(double? rttSeconds) {
    if (rttSeconds == null || !rttSeconds.isFinite) {
      return CallConnectionQuality.unknown;
    }
    if (rttSeconds >= 1.5) {
      return CallConnectionQuality.lost;
    }
    if (rttSeconds >= 0.45) {
      return CallConnectionQuality.poor;
    }
    if (rttSeconds >= 0.25) {
      return CallConnectionQuality.fair;
    }
    return CallConnectionQuality.unknown;
  }

  CallConnectionQuality _qualityForJitterSeconds(double? jitterSeconds) {
    if (jitterSeconds == null || !jitterSeconds.isFinite) {
      return CallConnectionQuality.unknown;
    }
    if (jitterSeconds >= 0.15) {
      return CallConnectionQuality.poor;
    }
    if (jitterSeconds >= 0.06) {
      return CallConnectionQuality.fair;
    }
    return CallConnectionQuality.unknown;
  }

  CallConnectionQuality _qualityForPacketLoss({
    required double? packetsLost,
    required double? packetsReceived,
  }) {
    if (packetsLost == null ||
        packetsReceived == null ||
        !packetsLost.isFinite ||
        !packetsReceived.isFinite) {
      return CallConnectionQuality.unknown;
    }
    final total = packetsLost + packetsReceived;
    if (total <= 0) {
      return CallConnectionQuality.unknown;
    }
    final lossPercent = packetsLost / total * 100;
    if (lossPercent >= 20) {
      return CallConnectionQuality.lost;
    }
    if (lossPercent >= 8) {
      return CallConnectionQuality.poor;
    }
    if (lossPercent >= 2) {
      return CallConnectionQuality.fair;
    }
    return CallConnectionQuality.unknown;
  }

  CallConnectionQuality _worseDirectCallQuality(
    CallConnectionQuality current,
    CallConnectionQuality next,
  ) {
    return _directCallQualitySeverity(next) >
            _directCallQualitySeverity(current)
        ? next
        : current;
  }

  int _directCallQualitySeverity(CallConnectionQuality quality) {
    return switch (quality) {
      CallConnectionQuality.lost => 4,
      CallConnectionQuality.poor => 3,
      CallConnectionQuality.fair => 2,
      CallConnectionQuality.unknown ||
      CallConnectionQuality.excellent ||
      CallConnectionQuality.good => 1,
    };
  }

  CallConnectionLifecycle _callLifecycleForState(VoipState state) {
    return switch (state) {
      VoipState.connected => CallConnectionLifecycle.connected,
      VoipState.connecting ||
      VoipState.outgoing ||
      VoipState.incoming => CallConnectionLifecycle.connecting,
      // Direct 1:1 calls never enter `leaving` - it is set only by the
      // MatrixRTC session's bounded hang-up - but the switch is exhaustive, so
      // the value needs a home. It is on its way to `ended`, so report that.
      VoipState.leaving || VoipState.ended => CallConnectionLifecycle.ended,
      VoipState.unknown => CallConnectionLifecycle.unknown,
    };
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    if (!_canRunDirectCallMediaOperation) {
      return;
    }

    final nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
      source: 'matrix-direct-native-call-action-screen-share-start',
      actionKind: 'Direct Matrix screen share start',
    );
    MediaStream? stream;
    final shareSource = source is ShareCaptureSource ? source : null;
    final videoSource = shareSource?.videoSource ?? source;

    try {
      if (videoSource is WebrtcAndroidScreencaptureSource) {
        stream = await webrtc.navigator.mediaDevices.getDisplayMedia({
          'audio': true,
          'video': {
            'mandatory': {'frameRate': preferences.streamFramerate.value},
          },
        });
      }

      if (videoSource is WebrtcScreencaptureSource) {
        // Windows shared-content audio is owned by ShareSession, not the
        // microphone or getDisplayMedia constraints. Non-Windows desktop paths
        // may still receive a native audio track when the user asked for it.
        stream = await webrtc.navigator.mediaDevices.getDisplayMedia({
          'audio':
              !PlatformUtils.isWindows &&
              (shareSource?.shareSession.sharedAudioRequested ?? true),
          'video': {
            'width': 1920,
            'height': 1080,
            'deviceId': {'exact': videoSource.source.id},
            'mandatory': {'frameRate': preferences.streamFramerate.value},
          },
        });
      }

      if (stream != null) {
        if (!_canRunDirectCallMediaOperation) {
          await _disposeAbandonedScreenshareCandidate(
            stream,
            shareSource?.shareSession,
          );
          return;
        }

        final shareSession = shareSource?.shareSession;
        await _attachWindowsSharedAudioTrack(stream, shareSession);
        if (!_canRunDirectCallMediaOperation) {
          await _disposeAbandonedScreenshareCandidate(stream, shareSession);
          return;
        }

        // Stop any existing screenshare before adding the new one, then
        // update currentScreenshare only after a clean stop so that any
        // code that references it during teardown still sees the old value.
        // Keep the outer screen-share-start crash marker active through the
        // replacement publish. The pending crash store is single-marker, so a
        // nested stop marker would overwrite and then clear the start marker.
        await _stopScreenshare(recordNativeCrashGuard: false);
        if (!_canRunDirectCallMediaOperation) {
          await _disposeAbandonedScreenshareCandidate(stream, shareSession);
          return;
        }
        currentScreenshare = source;
        await session.addLocalStream(
          stream,
          matrix.SDPStreamMetadataPurpose.Screenshare,
        );
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
        _notifyStateChanged();
      }
    } catch (e, s) {
      if (stream != null) {
        await _disposeAbandonedScreenshareCandidate(
          stream,
          shareSource?.shareSession,
        );
      } else {
        await shareSource?.shareSession.stop();
      }
      currentScreenshare = null;
      // Swallow the error so a failed screen-share attempt does not terminate
      // the call.  The screenshare simply stays inactive.
      Log.onError(e, s, content: "Failed to set direct-call screen share");
    } finally {
      await nativeCrashGuard?.clear();
    }
  }

  Future<void> _disposeAbandonedScreenshareCandidate(
    MediaStream stream,
    ShareSession? shareSession,
  ) async {
    try {
      await shareSession?.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop abandoned direct-call screen share session',
      );
    }

    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop abandoned direct-call screen share track',
        );
      }
    }

    try {
      await stream.dispose();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to dispose abandoned direct-call screen share stream',
      );
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
  Future<void> stopScreenshare() {
    if (!_canRunDirectCallMediaOperation) {
      return Future<void>.value();
    }

    return _stopScreenshare();
  }

  Future<void> _stopScreenshare({
    bool recordNativeCrashGuard = true,
    bool allowDuringTeardown = false,
  }) async {
    if (!allowDuringTeardown && !_canRunDirectCallMediaOperation) {
      return;
    }

    final nativeCrashGuard = recordNativeCrashGuard
        ? await PendingNativeCallCrashGuard.recordAction(
            source: 'matrix-direct-native-call-action-screen-share-stop',
            actionKind: 'Direct Matrix screen share stop',
          )
        : null;
    final shareSession = currentShareSession;

    try {
      // Snapshot the list before iterating: removeLocalStream modifies
      // session.getLocalStreams in-place, which would throw
      // ConcurrentModificationException on a lazy where()-iterable.
      final toRemove = session.getLocalStreams
          .where(
            (e) => e.purpose == matrix.SDPStreamMetadataPurpose.Screenshare,
          )
          .toList();
      for (final element in toRemove) {
        await session.removeLocalStream(element);
      }

      await shareSession?.stop();
      currentScreenshare = null;
      _notifyStateChanged();
    } finally {
      await nativeCrashGuard?.clear();
    }
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

    if (localUserMediaStream.getTracks().any(
          (element) => element.kind == "video",
        ) ==
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
    _notifyStateChanged();
  }

  void initStreams() {
    List<MatrixVoipStream> result = List.empty(growable: true);

    var s = List<matrix.WrappedMediaStream>.from(
      session.getLocalStreams,
      growable: true,
    );
    s.addAll(session.getRemoteStreams);

    for (var stream in s) {
      if (!shouldAddStream(stream)) {
        continue;
      }

      if (!result.any(
        (element) => element.stream.stream?.id == stream.stream?.id,
      )) {
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
      matrix.SDPStreamMetadataPurpose.Usermedia,
    ].contains(stream.purpose)) {
      return false;
    }

    return true;
  }

  void onStreamAdded(matrix.WrappedMediaStream event) {
    if (!_canProcessDirectCallStreamListEvent) {
      return;
    }

    if (shouldAddStream(event) &&
        !streams.any((stream) => stream.streamId == event.stream?.id)) {
      streams.add(MatrixVoipStream(event, this));
      _notifyStateChanged();
    }
  }

  void onStreamRemoved(matrix.WrappedMediaStream event) {
    if (!_canProcessDirectCallStreamListEvent) {
      return;
    }

    final removed = streams
        .where((e) => e.streamId == event.stream?.id)
        .toList();
    streams.removeWhere((e) => e.streamId == event.stream?.id);
    for (final stream in removed) {
      if (stream is MatrixVoipStream) {
        unawaited(
          _disposeDirectCallStream(
            stream.dispose,
            content: 'Failed to dispose removed direct-call stream',
          ),
        );
      }
    }
    _notifyStateChanged();
  }

  Future<void> _disposeCallResources() {
    _active = false;

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

  /// Releases wrapper-owned direct-call resources without sending a hang-up.
  ///
  /// The Matrix SDK invokes its ended callback after it has already finished
  /// the underlying call. Its owner uses this to release the matching wrapper.
  Future<void> dispose() => _disposeCallResources();

  Future<void> _disposeCallResourcesOnce() async {
    final shareSession = currentShareSession;
    if (shareSession != null || isSharingScreen) {
      try {
        await _stopScreenshare(
          recordNativeCrashGuard: false,
          allowDuringTeardown: true,
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop direct-call screen share during teardown',
        );
      }
    }

    _disposed = true;
    _volumeTimer?.cancel();
    _volumeTimer = null;
    await _onDiagnosticsChanged.close();
    await _onStateChanged.close();
    await _onVolumeChanged.close();
    await _onConnectionChanged.close();
    for (final subscription in _subscriptions) {
      await _cancelDirectCallSessionSubscription(subscription);
    }
    _subscriptions.clear();

    if (_streamsInitialized) {
      for (final stream in streams.whereType<MatrixVoipStream>()) {
        await _disposeDirectCallStream(
          stream.dispose,
          content: 'Failed to dispose direct-call stream during teardown',
        );
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
