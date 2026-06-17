import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/screen_share_adaptive_fallback.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/native_webrtc_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/stream_live_tuning_harness.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';
import 'package:intergalactic/client/components/voip/android_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/ios_broadcast_control.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:logger/logger.dart' as native_logger;
import 'package:matrix/matrix_api_lite.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class _StatsSample {
  const _StatsSample({required this.bytes, required this.timestamp});

  final num? bytes;
  final num? timestamp;
}

class _JitterBufferSample {
  const _JitterBufferSample({
    required this.delaySeconds,
    required this.emittedCount,
  });

  final num? delaySeconds;
  final num? emittedCount;
}

class _DurationCounterSample {
  const _DurationCounterSample({
    required this.totalSeconds,
    required this.count,
  });

  final num? totalSeconds;
  final num? count;
}

class _IntergalacticScreenShareCaptureOptions
    extends lk.ScreenShareCaptureOptions {
  const _IntergalacticScreenShareCaptureOptions({
    this.windowsCaptureBackendMode,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureMode,
    this.gameCaptureProcessId,
    this.nativeFramePacingEnabled = false,
    this.dummyNv12LiveSender = false,
    super.captureScreenAudio,
    super.sourceId,
    super.maxFrameRate,
    super.params,
  });

  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode;
  final int? gameCaptureProcessId;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;

  @override
  Map<String, dynamic> toMediaConstraintsMap() {
    final constraints = Map<String, dynamic>.from(
      super.toMediaConstraintsMap(),
    );
    final backendMode = windowsCaptureBackendMode;
    if (backendMode != null) {
      constraints['intergalacticCaptureBackend'] = backendMode.constraintValue;
    }
    if (windowsCaptureDirtyRegionMode !=
        WindowsScreenCaptureDirtyRegionMode.auto) {
      constraints['intergalacticCaptureDirtyRegion'] =
          windowsCaptureDirtyRegionMode.constraintValue;
    }
    final windowGdiMode = windowsWindowGdiCaptureMode;
    if (windowGdiMode != null) {
      constraints['intergalacticWindowGdiMode'] = windowGdiMode.constraintValue;
    }
    if (nativeFramePacingEnabled) {
      constraints['intergalacticCaptureFramePacing'] = 'latest';
    }
    final processId = gameCaptureProcessId;
    if (processId != null && processId > 0) {
      constraints['intergalacticGameCaptureProcessId'] = processId;
    }
    if (dummyNv12LiveSender) {
      constraints['intergalacticGameCaptureSourceMode'] =
          'dummy-nv12-live-sender';
    }
    return constraints;
  }
}

class _SenderSourceDiagnostics {
  const _SenderSourceDiagnostics({
    this.width,
    this.height,
    this.captureFps,
    this.framesCaptured,
    this.framesDroppedBeforeEncode,
  });

  final int? width;
  final int? height;
  final double? captureFps;
  final int? framesCaptured;
  final int? framesDroppedBeforeEncode;
}

class _VideoTrackSettingsDiagnostics {
  const _VideoTrackSettingsDiagnostics({
    this.width,
    this.height,
    this.frameRate,
  });

  final int? width;
  final int? height;
  final double? frameRate;
}

class _SenderRawDiagnostics {
  const _SenderRawDiagnostics({
    this.rid,
    this.encodeFps,
    this.framesEncoded,
    this.framesDroppedByEncoder,
    this.averageEncodeTimeMs,
    this.averagePacketSendDelayMs,
    this.qualityLimitationDurations,
    this.retransmittedBytesSent,
    this.retransmitBitrateBps,
  });

  final String? rid;
  final double? encodeFps;
  final int? framesEncoded;
  final int? framesDroppedByEncoder;
  final double? averageEncodeTimeMs;
  final double? averagePacketSendDelayMs;
  final String? qualityLimitationDurations;
  final int? retransmittedBytesSent;
  final int? retransmitBitrateBps;
}

class _SenderRawDiagnosticsBundle {
  const _SenderRawDiagnosticsBundle({
    this.source,
    this.byOutboundId = const {},
  });

  final _SenderSourceDiagnostics? source;
  final Map<String, _SenderRawDiagnostics> byOutboundId;
}

class _ReceiverRawDiagnostics {
  const _ReceiverRawDiagnostics({
    this.jitterBufferDelayMs,
    this.averageDecodeTimeMs,
    this.framesRendered,
    this.renderFps,
    this.freezeCount,
    this.pauseCount,
    this.totalFreezesDurationMs,
    this.totalPausesDurationMs,
  });

  final double? jitterBufferDelayMs;
  final double? averageDecodeTimeMs;
  final int? framesRendered;
  final double? renderFps;
  final int? freezeCount;
  final int? pauseCount;
  final double? totalFreezesDurationMs;
  final double? totalPausesDurationMs;
}

class _IceTransportDiagnostics {
  const _IceTransportDiagnostics({
    required this.summary,
    this.availableOutgoingBitrateBps,
    this.availableIncomingBitrateBps,
  });

  final String summary;
  final int? availableOutgoingBitrateBps;
  final int? availableIncomingBitrateBps;
}

class _WebrtcNativeLogPrinter extends native_logger.LogPrinter {
  @override
  List<String> log(native_logger.LogEvent event) {
    return [event.message.toString()];
  }
}

class _WebrtcNativeEncoderLogOutput extends native_logger.LogOutput {
  static const _keywords = [
    'encoder',
    'inter galactic',
    'desktop capture',
    'capture pipeline',
    'pre_encode',
    'openh264',
    'h264',
    'libvpx',
    'hardware',
    'mediafoundation',
    'd3d11',
    'dxva',
    'nvenc',
    'amf',
    'qsv',
    'vesfw',
  ];

  @override
  void output(native_logger.OutputEvent event) {
    for (final line in event.lines) {
      final trimmed = line.trim();
      final normalized = trimmed.toLowerCase();
      if (trimmed.isEmpty ||
          !_keywords.any((keyword) => normalized.contains(keyword))) {
        continue;
      }
      Log.i(
        'WebRTC native stream log: $trimmed',
        category: LogCategory.webrtc,
        source: 'native-encoder',
      );
    }
  }
}

class MatrixLivekitVoipSession implements VoipSession {
  static const _serverAudioLoopbackTokenTimeout = Duration(seconds: 10);
  static const _diagnosticsStatsTimeout = Duration(milliseconds: 1200);
  static const _streamTestPublishVideoTrackTimeout = Duration(seconds: 20);
  static const _streamTestSenderLimitsTimeout = Duration(seconds: 5);
  static const _iosReplayKitPublishTimeout = Duration(seconds: 8);
  static const _iosReplayKitPublishPollInterval = Duration(milliseconds: 250);
  static const _streamTestRawDiagnosticsSampleInterval = 5;
  static const _streamTestIceDiagnosticsInitialSamples = 1;

  MatrixRoom room;
  lk.Room livekitRoom;
  final String stateKey;
  final List<Uri> foci;
  Timer? heartbeatTimer;
  Timer? membershipRefreshTimer;
  String? heartbeatDelayId;
  AppLifecycleListener? _lifecycleListener;
  ShareSession? _currentShareSession;
  lk.LocalTrackPublication<lk.LocalAudioTrack>? _windowsSharedAudioPublication;
  lk.LocalAudioTrack? _windowsSharedAudioTrack;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  StreamSubscription? _noiseSuppressionStatusSub;
  Timer? _volumeTimer;
  Timer? _diagnosticsTimer;
  Timer? _streamLiveTuningTimer;
  Future<void>? _transientCallResourcesDisposeFuture;
  Future<void> _noiseSuppressionCaptureRefresh = Future<void>.value();
  Future<void> _serverAudioLoopbackOperation = Future<void>.value();
  Future<void> _cameraOperation = Future<void>.value();
  bool _transientCallResourcesDisposed = false;
  bool _ending = false;
  String _microphoneCaptureProfileSignature =
      NoiseSuppressionCaptureProfile.captureFrontendSignature(
    bypassVoiceProcessing: PlatformUtils.isIOS,
  );
  bool _desiredServerAudioLoopbackEnabled = false;
  bool _serverAudioLoopbackStarting = false;
  bool _serverAudioLoopbackStopping = false;
  String? _serverAudioLoopbackError;
  lk.Room? _serverAudioLoopbackRoom;
  lk.EventsListener<lk.RoomEvent>? _serverAudioLoopbackListener;
  int _serverAudioLoopbackGeneration = 0;
  ScreenCaptureSource? _activeScreenShareSource;
  WindowsScreenCaptureBackendMode? _activeWindowsCaptureBackendMode;
  WindowsScreenCaptureDirtyRegionMode? _activeWindowsCaptureDirtyRegionMode;
  WindowsWindowGdiCaptureMode? _activeWindowsWindowGdiCaptureMode;
  bool _activeNativeFramePacingEnabled = false;
  ScreenShareProfileConfig? _requestedScreenShareProfile;
  ScreenShareProfileConfig? _activeScreenShareProfile;
  DateTime _lastUpdatedDiagnostics = DateTime.fromMillisecondsSinceEpoch(0);
  VoipCallDiagnosticsSnapshot _diagnosticsSnapshot =
      VoipCallDiagnosticsSnapshot.empty();
  final Map<String, _StatsSample> _senderStatsSamples = {};
  final Map<String, _StatsSample> _receiverStatsSamples = {};
  final Map<String, _JitterBufferSample> _receiverJitterBufferSamples = {};
  final Map<String, _DurationCounterSample> _senderEncodeTimeSamples = {};
  final Map<String, _DurationCounterSample> _senderPacketSendDelaySamples = {};
  final Map<String, _DurationCounterSample> _receiverDecodeTimeSamples = {};
  final Map<String, _StatsSample> _senderRetransmitStatsSamples = {};
  final Map<String, String> _appliedScreenShareLimitKeys = {};
  final Map<String, ({int width, int height})> _screenShareObservedSizes = {};
  final Set<String> _cpuRescueLayerDisabledStreams = {};
  bool _screenShareCaptureRefreshInFlight = false;
  bool _streamTestScreenSharePublishInProgress = false;
  bool _streamTestScreenShareActive = false;
  bool _streamTestObservedLimitRefreshDeferred = false;
  int _streamTestDiagnosticsSampleOrdinal = 0;
  bool _streamLiveTuningTickInFlight = false;
  String? _streamLiveTuningAppliedSignature;
  DateTime _lastStatsSanityLog = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDiagnosticsStatsTimeoutLog =
      DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDiagnosticsSummaryLog = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastIceDiagnosticsLog = DateTime.fromMillisecondsSinceEpoch(0);
  String? _latestIceTransportSummary;
  int? _latestAvailableOutgoingBitrateBps;
  int? _latestAvailableIncomingBitrateBps;
  bool _webrtcNativeEncoderLoggingConfigured = false;
  static final native_logger.Logger _webrtcNativeEncoderLogger =
      native_logger.Logger(
    printer: _WebrtcNativeLogPrinter(),
    output: _WebrtcNativeEncoderLogOutput(),
    level: native_logger.Level.info,
  );
  final ScreenShareAdaptiveFallbackController _adaptiveFallbackController =
      ScreenShareAdaptiveFallbackController();

  final StreamController<void> _onVolumeChanged = StreamController.broadcast();
  final StreamController<void> _onDiagnosticsChanged =
      StreamController.broadcast();

  MatrixLivekitVoipSession(
    this.room,
    this.livekitRoom, {
    required this.stateKey,
    required List<Uri> foci,
  }) : foci = List.unmodifiable(foci) {
    clientManager?.callManager.onClientSessionStarted(this);
    addInitialStreams();

    _roomListener = livekitRoom.createListener();
    _roomListener!.on(onTrackPublished);
    _roomListener!.on(onTrackUnpublished);
    _roomListener!.on(onLocalTrackPublished);
    _roomListener!.on(onLocalTrackUnpublished);
    _roomListener!.on(onTrackStreamEvent);
    _roomListener!.on(onTrackMutedEvent);
    _roomListener!.on(onTrackUnmutedEvent);
    _roomListener!.on(onParticipantConnected);
    _roomListener!.on(onParticipantDisconnected);
    _noiseSuppressionStatusSub = NoiseSuppressionService
        .instance.onStatusChanged
        .listen((_) => _syncMicrophoneNoiseSuppressionCaptureProfile());

    _volumeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (state == VoipState.ended) timer.cancel();
      _onVolumeChanged.add(());
    });
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(updateStats());
    });
    if (StreamLiveTuningHarness.instance.isSupported) {
      _streamLiveTuningTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_updateStreamLiveTuningHarness());
      });
    }

    startHeartbeat();

    // Clean up call state when the OS terminates or detaches the app without
    // the user pressing hang-up.  This clears the Matrix call member state
    // event so other participants don't see a persistent ghost tile.
    _lifecycleListener = AppLifecycleListener(
      onDetach: () {
        if (state != VoipState.ended) {
          hangUpCall();
        }
      },
    );
  }

  StreamController _stateChanged = StreamController.broadcast();
  final StreamController<VoipState> _onConnectionChanged =
      StreamController.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _onConnectionChanged.stream;

  void addInitialStreams() {
    if (livekitRoom.localParticipant != null) {
      for (var entry
          in livekitRoom.localParticipant!.trackPublications.entries) {
        if (entry.value.muted && entry.value.kind == lk.TrackType.VIDEO) {
          continue;
        }

        _addLivekitStream(
          entry.value,
          room.client.self!.identifier,
          participantIdentity: livekitRoom.localParticipant!.identity,
        );
      }
    }

    for (var entry in livekitRoom.remoteParticipants.entries) {
      for (var stream in entry.value.trackPublications.entries) {
        if (stream.value.kind == lk.TrackType.VIDEO && stream.value.muted) {
          continue;
        }

        final userId = _userIdFromParticipantIdentity(entry.key);

        _addLivekitStream(stream.value, userId, participantIdentity: entry.key);
      }
    }
  }

  bool _addLivekitStream(
    lk.TrackPublication publication,
    String userId, {
    String? participantIdentity,
  }) {
    if (publication.kind == lk.TrackType.VIDEO && publication.muted) {
      return false;
    }

    if (streams.any((stream) => stream.streamId == publication.sid)) {
      return false;
    }

    streams.add(
      MatrixLivekitVoipStream(
        publication,
        userId,
        participantIdentity: participantIdentity,
      ),
    );
    return true;
  }

  void _removeLivekitStreamsWhere(
    bool Function(MatrixLivekitVoipStream stream) test,
  ) {
    final removed = streams
        .whereType<MatrixLivekitVoipStream>()
        .where(test)
        .toList(growable: false);
    streams.removeWhere(
      (stream) => stream is MatrixLivekitVoipStream && test(stream),
    );
    for (final stream in removed) {
      _appliedScreenShareLimitKeys.remove(stream.streamId);
      _screenShareObservedSizes.remove(stream.streamId);
      _cpuRescueLayerDisabledStreams.remove(stream.streamId);
      unawaited(stream.dispose());
    }
  }

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) {
    throw UnimplementedError();
  }

  void onTrackStreamEvent(lk.TrackStreamStateUpdatedEvent event) {
    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }
  }

  ScreenShareProfileConfig _screenShareProfile() {
    final developerModeEnabled = preferences.developerMode.value;
    final gpuPipelineTestModeEnabled = _gpuPipelineTestModeEnabled;
    final advancedOverrideEnabled = !gpuPipelineTestModeEnabled &&
        developerModeEnabled &&
        preferences.streamAdvancedOverride.value;
    final preferHardwareEncoding = PlatformUtils.isWindows &&
        (gpuPipelineTestModeEnabled ||
            preferences.streamHardwareEncodingFirst.value);
    return ScreenShareProfileConfig.resolve(
      profileKey: gpuPipelineTestModeEnabled
          ? ScreenShareQualityProfile.smooth.storageKey
          : preferences.screenShareQualityProfile.value,
      advancedOverrideEnabled: advancedOverrideEnabled,
      allowSimulcast:
          gpuPipelineTestModeEnabled ? false : preferences.doSimulcast.value,
      advancedBitrateMbps: preferences.streamBitrate.value,
      advancedFramerate: preferences.streamFramerate.value,
      advancedCodec: preferences.streamCodec.value,
      advancedResolution: preferences.streamResolution.value,
      preferHardwareEncoding: preferHardwareEncoding,
    );
  }

  bool get _gpuPipelineTestModeEnabled {
    return PlatformUtils.isWindows &&
        preferences.developerMode.value &&
        preferences.streamGpuPipelineTestMode.value;
  }

  ScreenShareProfileConfig _screenShareProfileForSource(
    ScreenShareProfileConfig requestedProfile,
    ScreenCaptureSource videoSource,
  ) {
    final isWindowsWindowSource = PlatformUtils.isWindows &&
        videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Window;
    final isWindowsDisplaySource = PlatformUtils.isWindows &&
        videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Screen;
    return requestedProfile
        .withWindowsWindowCaptureCompatibility(
          isWindowsWindowSource: isWindowsWindowSource,
        )
        .withWindowsDisplayCaptureCadenceCompatibility(
          isWindowsDisplaySource: isWindowsDisplaySource,
        );
  }

  bool get _adaptiveFallbackEnabled {
    if (_gpuPipelineTestModeEnabled) {
      return false;
    }

    if (preferences.developerMode.value &&
        preferences.streamAdaptiveFallbackEnabled.value) {
      return true;
    }

    final profile = _activeScreenShareProfile ?? _requestedScreenShareProfile;
    if (profile == null) {
      return false;
    }
    return profile.profile != null && !profile.advancedOverride;
  }

  lk.VideoDimensions _dimensionsForLayer(ScreenShareVideoLayer layer) {
    return lk.VideoDimensions(layer.width, layer.height);
  }

  lk.VideoEncoding _encodingForLayer(ScreenShareVideoLayer layer) {
    return lk.VideoEncoding(
      maxFramerate: layer.maxFramerate,
      maxBitrate: layer.maxBitrateBps,
    );
  }

  lk.VideoParameters _parametersForLayer(ScreenShareVideoLayer layer) {
    return lk.VideoParameters(
      dimensions: _dimensionsForLayer(layer),
      encoding: _encodingForLayer(layer),
    );
  }

  lk.VideoPublishOptions _publishOptionsForProfile(
    ScreenShareProfileConfig profile,
  ) {
    final useSimulcast = profile.useSimulcast && profile.lowLayer != null;
    return lk.VideoPublishOptions(
      simulcast: useSimulcast,
      screenShareSimulcastLayers:
          useSimulcast ? [_parametersForLayer(profile.lowLayer!)] : const [],
      screenShareEncoding: _encodingForLayer(profile.mainLayer),
      videoEncoding: _encodingForLayer(profile.mainLayer),
      videoCodec: profile.codec,
      degradationPreference: _degradationPreferenceForProfile(profile),
      backupVideoCodec: lk.BackupVideoCodec(enabled: false),
    );
  }

  lk.DegradationPreference _degradationPreferenceForProfile(
    ScreenShareProfileConfig profile,
  ) {
    if (PlatformUtils.isWindows && profile.hardwareEncodeFirst) {
      return lk.DegradationPreference.maintainResolution;
    }
    return lk.DegradationPreference.maintainFramerate;
  }

  Future<void> _stopCreatedScreenShareTracks(
    Iterable<lk.LocalTrack> tracks,
  ) async {
    for (final track in tracks) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to stop a screen share track during cleanup",
        );
      }
    }
  }

  Future<void> _rollbackPublishedScreenShareTracks({
    required lk.LocalParticipant participant,
    required List<lk.LocalTrackPublication> publications,
    required Iterable<lk.LocalTrack> tracks,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    Log.onError(
      error,
      stackTrace,
      content: "Screen share publish failed; rolling back partial publications",
    );

    for (final publication in publications.reversed) {
      try {
        await participant.removePublishedTrack(publication.sid);
      } catch (rollbackError, rollbackStackTrace) {
        Log.onError(
          rollbackError,
          rollbackStackTrace,
          content: "Failed to remove a partially published screen share track",
        );
      }
    }

    await _stopCreatedScreenShareTracks(
      tracks.where((track) => !track.isPublished),
    );
  }

  Future<lk.LocalTrackPublication> _publishScreenShareVideoTrack({
    required lk.LocalParticipant participant,
    required lk.LocalVideoTrack track,
    required ScreenShareProfileConfig publishProfile,
    required bool guardPrePublication,
    required String sourceTypeLabel,
    required String sourceIdHash,
    required WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    required WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode,
    required WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    required bool nativeFramePacingEnabled,
    required int? gameCaptureProcessId,
  }) async {
    final publishOptions = _publishOptionsForProfile(publishProfile);
    if (!guardPrePublication) {
      return participant.publishVideoTrack(
        track,
        publishOptions: publishOptions,
      );
    }

    final timeout = _streamTestPublishVideoTrackTimeout;
    final context = 'stage=publishVideoTrack_pre_event '
        'sourceType=$sourceTypeLabel '
        'sourceIdHash=$sourceIdHash '
        'profile=${publishProfile.label} '
        'windowsCaptureBackend='
        '${windowsCaptureBackendMode?.constraintValue ?? 'unchanged'} '
        'windowsCaptureDirtyRegion='
        '${windowsCaptureDirtyRegionMode.constraintValue} '
        'windowsWindowGdi='
        '${windowsWindowGdiCaptureMode?.constraintValue ?? 'default'} '
        'nativeFramePacing=$nativeFramePacingEnabled '
        'gameCapturePid=${gameCaptureProcessId ?? 'none'} '
        'timeout=${timeout.inSeconds}s';
    Log.i(
      'LiveKit screen-share video publish enter: $context',
      category: LogCategory.livekit,
      source: 'screen-share-publish',
    );

    var timedOut = false;
    final publishFuture = participant.publishVideoTrack(
      track,
      publishOptions: publishOptions,
    );
    unawaited(
      publishFuture.then<void>(
        (publication) async {
          if (!timedOut) {
            Log.i(
              'LiveKit screen-share video publish completed: '
              '$context sid=${publication.sid}',
              category: LogCategory.livekit,
              source: 'screen-share-publish',
            );
            return;
          }
          Log.w(
            'LiveKit screen-share video publish completed after timeout; '
            'rolling back late publication: $context sid=${publication.sid}',
            category: LogCategory.livekit,
            source: 'screen-share-publish',
          );
          await _rollbackPublishedScreenShareTracks(
            participant: participant,
            publications: [publication],
            tracks: [track],
            error: TimeoutException(
              'Late LiveKit screen-share publish completed after the '
              'stream-test publish guard timed out.',
              timeout,
            ),
            stackTrace: StackTrace.current,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!timedOut) {
            return;
          }
          Log.onError(
            error,
            stackTrace,
            content:
                'LiveKit screen-share video publish completed with an error '
                'after timeout; $context',
          );
        },
      ),
    );

    return publishFuture.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException(
          'LiveKit publishVideoTrack timed out before local track publication '
          'after ${timeout.inSeconds}s ($context)',
          timeout,
        );
      },
    );
  }

  String _trackPublicationSummary(lk.TrackPublication publication) {
    final dimensions = publication.dimensions;
    final size = dimensions == null
        ? 'unknown'
        : '${dimensions.width}x${dimensions.height}';
    return 'sid=${publication.sid} name=${publication.name} '
        'kind=${publication.kind} source=${publication.source} '
        'muted=${publication.muted} simulcast=${publication.simulcasted} '
        'size=$size';
  }

  List<lk.LocalTrackPublication<lk.LocalVideoTrack>>
      _localCameraPublications() {
    final participant = livekitRoom.localParticipant;
    if (participant == null) {
      return const <lk.LocalTrackPublication<lk.LocalVideoTrack>>[];
    }

    return participant.videoTrackPublications
        .where((publication) => publication.source == lk.TrackSource.camera)
        .toList(growable: false);
  }

  List<lk.LocalTrackPublication<lk.LocalVideoTrack>>
      _localScreenShareVideoPublications() {
    final participant = livekitRoom.localParticipant;
    if (participant == null) {
      return const <lk.LocalTrackPublication<lk.LocalVideoTrack>>[];
    }

    return participant.videoTrackPublications
        .where(
          (publication) =>
              publication.isScreenShare ||
              publication.source == lk.TrackSource.screenShareVideo ||
              publication.name == 'screenshare',
        )
        .toList(growable: false);
  }

  Future<void> _queueCameraOperation(Future<void> Function() operation) {
    if (_ending || state == VoipState.ended) {
      return Future<void>.value();
    }

    Future<void> runIfActive() {
      if (_ending || state == VoipState.ended) {
        return Future<void>.value();
      }
      return operation();
    }

    final queued = _cameraOperation.then(
      (_) => runIfActive(),
      onError: (Object _, StackTrace __) => runIfActive(),
    );
    _cameraOperation = queued.catchError((Object _) {});
    return queued;
  }

  Future<void> _stopLocalCameraPublications({required String reason}) async {
    final participant = livekitRoom.localParticipant;
    if (participant == null) {
      return;
    }

    final publications = _localCameraPublications();
    if (publications.isEmpty) {
      return;
    }

    Log.i(
      'Cleaning up ${publications.length} local camera publication(s) '
      'for $reason: '
      '${publications.map(_trackPublicationSummary).join(' | ')}',
    );
    for (final publication in publications) {
      final track = publication.track;
      try {
        await participant.removePublishedTrack(publication.sid);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to unpublish local camera track during $reason',
        );
      }

      if (track != null) {
        try {
          await track.stop();
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to stop local camera track during $reason',
          );
        }
      }
    }
  }

  Future<void> _stopLocalScreenShareVideoPublications({
    required String reason,
    Set<String> exceptPublicationSids = const {},
  }) async {
    final participant = livekitRoom.localParticipant;
    if (participant == null) {
      return;
    }

    final publications = _localScreenShareVideoPublications()
        .where(
          (publication) => !exceptPublicationSids.contains(publication.sid),
        )
        .toList(growable: false);
    if (publications.isEmpty) {
      return;
    }

    Log.i(
      'Cleaning up ${publications.length} local screen-share video '
      'publication(s) for $reason: '
      '${publications.map(_trackPublicationSummary).join(' | ')}',
    );
    for (final publication in publications) {
      final track = publication.track;
      if (track != null) {
        try {
          Log.i(
            'Stopping local screen-share video track before unpublish '
            'during $reason: ${_trackPublicationSummary(publication)}',
          );
          await track.stop();
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to stop local screen-share video during $reason',
          );
        }
      }

      try {
        await participant.removePublishedTrack(publication.sid);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Failed to unpublish local screen-share video during $reason',
        );
      }
    }
  }

  Future<void> _publishWindowsSharedAudio(
    ShareSession? shareSession,
    lk.LocalParticipant localParticipant,
  ) async {
    if (!PlatformUtils.isWindows ||
        shareSession == null ||
        !shareSession.sharedAudioRequested) {
      return;
    }

    lk.LocalAudioTrack? localAudioTrack;
    try {
      final status = await shareSession.startSharedAudio();
      if (status.state != SharedAudioState.active ||
          !status.pcmBridgeSupported) {
        return;
      }

      final mediaStream =
          await shareSession.createSharedAudioPublicationStream();
      final audioTracks = mediaStream?.getAudioTracks() ?? const [];
      if (mediaStream == null || audioTracks.isEmpty) {
        await shareSession.disposeSharedAudioPublicationStream();
        return;
      }

      // LiveKit's public screen-share-audio helper cannot wrap a pre-created
      // MediaStream with our Windows shared-audio options, so this is pinned by
      // the livekit_client >=2.5.1 pubspec constraint and should be revisited
      // when the SDK exposes a public constructor for this path.
      // ignore: invalid_use_of_internal_member
      localAudioTrack = lk.LocalAudioTrack(
        lk.TrackSource.screenShareAudio,
        mediaStream,
        audioTracks.first,
        const lk.AudioCaptureOptions(
          noiseSuppression: false,
          echoCancellation: false,
          autoGainControl: false,
          typingNoiseDetection: false,
          voiceIsolation: false,
        ),
      );

      _windowsSharedAudioPublication = await localParticipant.publishAudioTrack(
        localAudioTrack,
        publishOptions: const lk.AudioPublishOptions(
          name: 'screenShareAudio',
          stream: 'screenShareAudio',
          dtx: false,
          red: true,
          audioBitrate: lk.AudioPreset.musicStereo,
        ),
      );
      _windowsSharedAudioTrack = localAudioTrack;
      Log.i("Published Windows shared-content audio track");
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            "Failed to publish Windows shared-content audio; continuing video-only",
      );

      try {
        await localAudioTrack?.stop();
      } catch (stopError, stopStackTrace) {
        Log.onError(
          stopError,
          stopStackTrace,
          content: "Failed to stop unpublished Windows shared-content audio",
        );
      }

      await shareSession.disposeSharedAudioPublicationStream();
    }
  }

  Future<void> _stopWindowsSharedAudioPublication(
    ShareSession? shareSession,
  ) async {
    final publication = _windowsSharedAudioPublication;
    final track = _windowsSharedAudioTrack;
    _windowsSharedAudioPublication = null;
    _windowsSharedAudioTrack = null;

    if (publication != null) {
      try {
        await livekitRoom.localParticipant?.removePublishedTrack(
          publication.sid,
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to unpublish Windows shared-content audio",
        );
      }
    }

    if (track != null) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to stop Windows shared-content audio track",
        );
      }
    }

    await shareSession?.disposeSharedAudioPublicationStream();
  }

  Future<void> _stopScreenShareBeforeHangUp() async {
    if (isSharingScreen) {
      await stopScreenshare();
      return;
    }

    if (PlatformUtils.isIOS) {
      await IosBroadcastControl.requestStop();
    }
  }

  void onTrackMutedEvent(lk.TrackMutedEvent event) {
    if (event.publication.track?.mediaType ==
        RTCRtpMediaType.RTCRtpMediaTypeVideo) {
      _removeLivekitStreamsWhere(
        (stream) => stream.publication.sid == event.publication.sid,
      );
    }

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    _stateChanged.add(());
  }

  void onTrackUnmutedEvent(lk.TrackUnmutedEvent event) {
    final participant = _userIdFromParticipantIdentity(
      event.participant.identity,
    );

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    if (_addLivekitStream(
      event.publication,
      participant,
      participantIdentity: event.participant.identity,
    )) {
      _stateChanged.add(());
    }
  }

  void onTrackPublished(lk.TrackPublishedEvent event) {
    Log.i(
      'LiveKit remote track published: '
      '${_trackPublicationSummary(event.publication)} '
      'participant=${event.participant.identity}',
    );
    final participant = _userIdFromParticipantIdentity(
      event.participant.identity,
    );

    if (_addLivekitStream(
      event.publication,
      participant,
      participantIdentity: event.participant.identity,
    )) {
      _stateChanged.add(());
    }
  }

  void onParticipantConnected(lk.ParticipantConnectedEvent event) {
    clientManager?.callManager.joinCallSound();
  }

  void onParticipantDisconnected(lk.ParticipantDisconnectedEvent event) {
    _removeLivekitStreamsWhere(
      (stream) => stream.participantIdentity == event.participant.identity,
    );
    clientManager?.callManager.endCallSound();
    _stateChanged.add(());
  }

  void onLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    Log.i(
      'LiveKit local track published: '
      '${_trackPublicationSummary(event.publication)} '
      'participant=${event.participant.identity}',
    );
    final participant = _userIdFromParticipantIdentity(
      event.participant.identity,
    );

    final added = _addLivekitStream(
      event.publication,
      participant,
      participantIdentity: event.participant.identity,
    );
    final track = event.publication.track;
    final activeProfile = _activeScreenShareProfile;
    if (activeProfile != null &&
        event.publication.isScreenShare &&
        track is lk.LocalVideoTrack &&
        !_streamTestScreenSharePublishInProgress) {
      unawaited(_applyScreenShareSenderLimits(activeProfile));
    }

    if (added) {
      _stateChanged.add(());
    }
  }

  void onLocalTrackUnpublished(lk.LocalTrackUnpublishedEvent event) {
    Log.i(
      'LiveKit local track unpublished: '
      '${_trackPublicationSummary(event.publication)} '
      'participant=${event.participant.identity}',
    );
    _removeLivekitStreamsWhere(
      (stream) => stream.publication.sid == event.publication.sid,
    );

    _stateChanged.add(());
  }

  void onTrackUnpublished(lk.TrackUnpublishedEvent event) {
    Log.i(
      'LiveKit remote track unpublished: '
      '${_trackPublicationSummary(event.publication)} '
      'participant=${event.participant.identity}',
    );
    _removeLivekitStreamsWhere(
      (stream) => stream.publication.sid == event.publication.sid,
    );

    _stateChanged.add(());
  }

  @override
  Client get client => room.client;

  @override
  VoipState state = VoipState.connected;

  @override
  Future<void> declineCall() {
    throw UnimplementedError();
  }

  @override
  Future<void> hangUpCall() async {
    Log.i("Hanging up call");
    _ending = true;
    membershipRefreshTimer?.cancel();
    membershipRefreshTimer = null;

    // Stop the lifecycle listener first so it doesn't re-trigger hang-up
    // if the OS sends a second detach event during cleanup.
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await _disposeTransientCallResources();

    try {
      await _stopScreenShareBeforeHangUp();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to stop screen sharing before hanging up the call",
      );
    }

    await Future.wait([
      clearRoomCallState(),
      disconnectCall(),
      stopHeartbeat(),
    ]);

    state = VoipState.ended;
    _stateChanged.add(());
    _onConnectionChanged.add(state);

    clientManager?.callManager.onSessionEnded(this);
  }

  Future<void> _disposeTransientCallResources() {
    if (_transientCallResourcesDisposed) {
      return Future<void>.value();
    }

    final pendingDispose = _transientCallResourcesDisposeFuture;
    if (pendingDispose != null) {
      return pendingDispose;
    }

    final disposeFuture = _disposeTransientCallResourcesOnce();
    _transientCallResourcesDisposeFuture = disposeFuture;
    return disposeFuture;
  }

  Future<void> _disposeTransientCallResourcesOnce() async {
    try {
      await _stopServerAudioLoopback(notify: false);
      _volumeTimer?.cancel();
      _volumeTimer = null;
      _diagnosticsTimer?.cancel();
      _diagnosticsTimer = null;
      _streamLiveTuningTimer?.cancel();
      _streamLiveTuningTimer = null;
      await _noiseSuppressionStatusSub?.cancel();
      _noiseSuppressionStatusSub = null;
      try {
        await _roomListener?.dispose();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to dispose LiveKit room listener',
        );
      }
      _roomListener = null;
      _adaptiveFallbackController.reset();
      _senderStatsSamples.clear();
      _receiverStatsSamples.clear();
      _receiverJitterBufferSamples.clear();
      _senderEncodeTimeSamples.clear();
      _senderPacketSendDelaySamples.clear();
      _receiverDecodeTimeSamples.clear();
      _senderRetransmitStatsSamples.clear();
      _appliedScreenShareLimitKeys.clear();
      _screenShareObservedSizes.clear();
      _cpuRescueLayerDisabledStreams.clear();
      _activeScreenShareSource = null;
      _activeWindowsCaptureBackendMode = null;
      _activeWindowsWindowGdiCaptureMode = null;
      _screenShareCaptureRefreshInFlight = false;
      _latestIceTransportSummary = null;
      _latestAvailableOutgoingBitrateBps = null;
      _latestAvailableIncomingBitrateBps = null;

      for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
        try {
          await stream.dispose();
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to dispose LiveKit stream',
          );
        }
      }
      streams.clear();
      _transientCallResourcesDisposed = true;
    } finally {
      _transientCallResourcesDisposeFuture = null;
    }
  }

  @override
  bool get isCameraEnabled => _localCameraPublications().any(
        (publication) => !publication.muted && publication.track != null,
      );

  @override
  bool get isMicrophoneMuted => livekitRoom.localParticipant?.isMuted ?? false;

  @override
  bool get isSharingScreen =>
      (livekitRoom.localParticipant?.isScreenShareEnabled() ?? false) ||
      _hasActiveLocalScreenShareVideo;

  @override
  ShareSession? get currentShareSession => _currentShareSession;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot => _diagnosticsSnapshot;

  @override
  Stream<void> get onDiagnosticsChanged => _onDiagnosticsChanged.stream;

  bool get isServerAudioLoopbackEnabled => _serverAudioLoopbackRoom != null;

  bool get isServerAudioLoopbackStarting => _serverAudioLoopbackStarting;

  String? get serverAudioLoopbackError => _serverAudioLoopbackError;

  String get serverAudioLoopbackDiagnosticLabel {
    if (_serverAudioLoopbackStarting) {
      return 'starting';
    }
    if (_serverAudioLoopbackRoom != null) {
      return _serverAudioLoopbackError == null
          ? 'receiving from LiveKit'
          : 'active (${_serverAudioLoopbackError})';
    }
    if (_serverAudioLoopbackError != null) {
      return 'error: $_serverAudioLoopbackError';
    }
    return 'off';
  }

  Future<void> setServerAudioLoopbackEnabled(bool enabled) {
    _desiredServerAudioLoopbackEnabled = enabled;
    _serverAudioLoopbackOperation =
        _serverAudioLoopbackOperation.catchError((_) {}).then((_) async {
      if (enabled) {
        if (!_desiredServerAudioLoopbackEnabled) {
          return;
        }
        await _startServerAudioLoopback();
      } else {
        await _stopServerAudioLoopback();
      }
    });
    return _serverAudioLoopbackOperation;
  }

  @override
  String? get remoteUserId => null;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  String? get remoteUserName => null;

  @override
  String get roomId => room.identifier;

  @override
  String get roomName => room.displayName;

  @override
  String get sessionId =>
      "${room.client.identifier}_${room.identifier}_$stateKey";

  @override
  Future<void> setMicrophoneMute(bool state) async {
    if (state) {
      await livekitRoom.localParticipant?.setMicrophoneEnabled(false);
    } else {
      final audioReady = await IosCallAudioSession.prepareForCall(
        source: 'matrix-livekit-session',
      );
      if (!audioReady) {
        return;
      }
      final audioCaptureOptions = await _currentMicrophoneCaptureOptions();
      await livekitRoom.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: audioCaptureOptions,
      );
      _microphoneCaptureProfileSignature =
          NoiseSuppressionCaptureProfile.captureFrontendSignature(
        bypassVoiceProcessing: PlatformUtils.isIOS,
      );
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
    _stateChanged.add(());
  }

  Future<lk.AudioCaptureOptions> _currentMicrophoneCaptureOptions() async {
    final baseOptions =
        NoiseSuppressionCaptureProfile.buildLivekitAudioCaptureOptions(
      inputVolume:
          NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
        preferences.voipMicrophoneVolume.value,
      ),
      bypassVoiceProcessing: PlatformUtils.isIOS,
    );
    final device = await WebrtcDefaultDevices.getDefaultMicrophoneId();
    final options =
        device != null ? baseOptions.copyWith(deviceId: device) : baseOptions;
    Log.i(
      "LiveKit microphone capture options: "
      "${NoiseSuppressionCaptureProfile.captureFrontendSummary(
        bypassVoiceProcessing: PlatformUtils.isIOS,
      )} "
      "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(options)}",
    );
    return options;
  }

  void _syncMicrophoneNoiseSuppressionCaptureProfile() {
    if (!PlatformUtils.isWindows || _ending || state == VoipState.ended) {
      return;
    }

    final captureProfileSignature =
        NoiseSuppressionCaptureProfile.captureFrontendSignature(
      bypassVoiceProcessing: PlatformUtils.isIOS,
    );
    if (captureProfileSignature == _microphoneCaptureProfileSignature) {
      return;
    }

    _noiseSuppressionCaptureRefresh =
        _noiseSuppressionCaptureRefresh.catchError((_) {}).then(
              (_) => _refreshMicrophoneCaptureForNoiseSuppression(
                captureProfileSignature,
              ),
            );
  }

  Future<void> _refreshMicrophoneCaptureForNoiseSuppression(
    String expectedCaptureProfileSignature,
  ) async {
    if (_ending || state == VoipState.ended) {
      return;
    }

    final localParticipant = livekitRoom.localParticipant;
    if (localParticipant == null || localParticipant.isMuted) {
      return;
    }

    final audioCaptureOptions = await _currentMicrophoneCaptureOptions();
    if (_ending ||
        state == VoipState.ended ||
        NoiseSuppressionCaptureProfile.captureFrontendSignature(
              bypassVoiceProcessing: PlatformUtils.isIOS,
            ) !=
            expectedCaptureProfileSignature) {
      return;
    }

    try {
      Log.i(
        "Refreshing microphone capture profile; "
        "${NoiseSuppressionCaptureProfile.captureFrontendSummary(
          bypassVoiceProcessing: PlatformUtils.isIOS,
        )} "
        "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(audioCaptureOptions)}",
      );
      await localParticipant.setMicrophoneEnabled(false);
      if (_ending || state == VoipState.ended) {
        return;
      }
      await localParticipant.setMicrophoneEnabled(
        true,
        audioCaptureOptions: audioCaptureOptions,
      );
      _microphoneCaptureProfileSignature = expectedCaptureProfileSignature;
      NoiseSuppressionService.instance.scheduleHealthRefresh();
      _stateChanged.add(());
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh microphone capture for RNNoise profile',
      );
    }
  }

  Future<({String sfuUrl, String jwt})>
      _requestServerAudioLoopbackCredentials() async {
    final matrixClient = room.matrixRoom.client;
    final userId = matrixClient.userID;
    final deviceId = matrixClient.deviceID;
    if (userId == null || deviceId == null) {
      throw Exception(
        'Cannot start server audio loopback without Matrix user '
        'and device identifiers.',
      );
    }
    if (foci.isEmpty) {
      throw Exception(
        'Cannot start server audio loopback without a LiveKit '
        'focus URL.',
      );
    }

    Uri? selectedFocus;
    for (final focus in foci) {
      if (focus.scheme == 'https') {
        selectedFocus = focus;
        break;
      }
    }
    if (selectedFocus == null) {
      throw Exception(
        'Cannot start server audio loopback without an HTTPS LiveKit focus URL.',
      );
    }

    final openIdToken = await matrixClient.requestOpenIdToken(userId, {});
    final focusBase = selectedFocus.toString().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$focusBase/sfu/get');
    final body = {
      'device_id': '${deviceId}_rnnoise_loopback',
      'room': room.matrixRoom.id,
      MatrixVoipRoomComponent.callClientInfoKey:
          BuildConfig.matrixClientMetadata,
      'openid_token': {
        'matrix_server_name': openIdToken.matrixServerName,
        'access_token': openIdToken.accessToken,
        'expires_in': openIdToken.expiresIn,
      },
    };

    var result = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_serverAudioLoopbackTokenTimeout);
    if (result.statusCode == 400) {
      final fallbackBody = Map<String, dynamic>.from(body)
        ..remove(MatrixVoipRoomComponent.callClientInfoKey);
      if (fallbackBody.length != body.length) {
        Log.w(
          'LiveKit loopback auth rejected client metadata; retrying token '
          'request without it',
        );
        result = await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(fallbackBody),
            )
            .timeout(_serverAudioLoopbackTokenTimeout);
      }
    }
    if (result.statusCode != 200) {
      throw Exception(
        'Failed to get LiveKit loopback token: HTTP ${result.statusCode}',
      );
    }

    final data = jsonDecode(result.body) as Map<String, dynamic>;
    final sfuUrl = data['url'];
    final jwt = data['jwt'];
    if (sfuUrl is! String || jwt is! String) {
      throw Exception('LiveKit loopback token response was malformed.');
    }

    return (sfuUrl: sfuUrl, jwt: jwt);
  }

  Future<void> _startServerAudioLoopback() async {
    if (!_desiredServerAudioLoopbackEnabled) {
      return;
    }
    if (_serverAudioLoopbackRoom != null || _serverAudioLoopbackStarting) {
      return;
    }

    _serverAudioLoopbackStarting = true;
    _serverAudioLoopbackError = null;
    final startGeneration = ++_serverAudioLoopbackGeneration;
    _notifyStateChanged();

    lk.Room? loopbackRoom;
    lk.EventsListener<lk.RoomEvent>? loopbackListener;
    try {
      final publisherIdentity = livekitRoom.localParticipant?.identity;
      if (publisherIdentity == null) {
        throw Exception('LiveKit publisher identity is unavailable.');
      }

      final credentials = await _requestServerAudioLoopbackCredentials();
      if (_ending ||
          state == VoipState.ended ||
          !_desiredServerAudioLoopbackEnabled ||
          !_serverAudioLoopbackStarting ||
          startGeneration != _serverAudioLoopbackGeneration) {
        return;
      }

      loopbackRoom = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: false,
          dynacast: false,
        ),
      );
      loopbackListener = loopbackRoom.createListener();
      loopbackListener.on(_onServerAudioLoopbackTrackPublished);
      loopbackListener.on(_onServerAudioLoopbackTrackSubscribed);
      loopbackListener.on(_onServerAudioLoopbackDisconnected);

      await loopbackRoom.connect(
        credentials.sfuUrl,
        credentials.jwt,
        connectOptions: const lk.ConnectOptions(autoSubscribe: false),
      );
      if (_ending ||
          state == VoipState.ended ||
          !_desiredServerAudioLoopbackEnabled ||
          !_serverAudioLoopbackStarting ||
          startGeneration != _serverAudioLoopbackGeneration) {
        await loopbackListener.dispose();
        await loopbackRoom.disconnect();
        await loopbackRoom.dispose();
        return;
      }

      _serverAudioLoopbackRoom = loopbackRoom;
      _serverAudioLoopbackListener = loopbackListener;
      _subscribeServerAudioLoopbackTracks();
      Log.i('Server audio loopback started via LiveKit for $publisherIdentity');
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to start server audio loopback',
      );
      _serverAudioLoopbackError = error.toString();
      _serverAudioLoopbackRoom = null;
      _serverAudioLoopbackListener = null;
      await loopbackListener?.dispose();
      await loopbackRoom?.disconnect();
      await loopbackRoom?.dispose();
    } finally {
      _serverAudioLoopbackStarting = false;
      _notifyStateChanged();
    }
  }

  Future<void> _stopServerAudioLoopback({bool notify = true}) async {
    _desiredServerAudioLoopbackEnabled = false;
    final loopbackRoom = _serverAudioLoopbackRoom;
    final loopbackListener = _serverAudioLoopbackListener;
    _serverAudioLoopbackRoom = null;
    _serverAudioLoopbackListener = null;
    _serverAudioLoopbackStarting = false;
    _serverAudioLoopbackGeneration++;
    _serverAudioLoopbackStopping = true;

    try {
      await loopbackListener?.dispose();
      await loopbackRoom?.disconnect();
      await loopbackRoom?.dispose();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop server audio loopback cleanly',
      );
      _serverAudioLoopbackError = error.toString();
    } finally {
      _serverAudioLoopbackStopping = false;
      if (notify) {
        _notifyStateChanged();
      }
    }
  }

  void _onServerAudioLoopbackDisconnected(lk.RoomDisconnectedEvent event) {
    if (_serverAudioLoopbackStopping || _serverAudioLoopbackRoom == null) {
      return;
    }

    _serverAudioLoopbackError =
        'disconnected${event.reason == null ? '' : ': ${event.reason}'}';
    unawaited(_stopServerAudioLoopback());
  }

  void _onServerAudioLoopbackTrackPublished(lk.TrackPublishedEvent event) {
    if (!_desiredServerAudioLoopbackEnabled) {
      return;
    }
    if (event.participant.identity != livekitRoom.localParticipant?.identity) {
      return;
    }

    if (_isServerAudioLoopbackMicrophone(event.publication)) {
      unawaited(event.publication.subscribe());
    }
  }

  void _onServerAudioLoopbackTrackSubscribed(lk.TrackSubscribedEvent event) {
    if (!_desiredServerAudioLoopbackEnabled ||
        event.participant.identity != livekitRoom.localParticipant?.identity ||
        !_isServerAudioLoopbackMicrophone(event.publication)) {
      unawaited(event.publication.unsubscribe());
      return;
    }

    _serverAudioLoopbackError = null;
    Log.i(
      'Server audio loopback subscribed to microphone track '
      '${event.publication.sid}',
    );
    _notifyStateChanged();
  }

  void _subscribeServerAudioLoopbackTracks() {
    final loopbackRoom = _serverAudioLoopbackRoom;
    final publisherIdentity = livekitRoom.localParticipant?.identity;
    if (!_desiredServerAudioLoopbackEnabled ||
        loopbackRoom == null ||
        publisherIdentity == null) {
      return;
    }

    var subscribed = false;
    for (final participant in loopbackRoom.remoteParticipants.values) {
      if (participant.identity != publisherIdentity) {
        continue;
      }

      for (final publication in participant.trackPublications.values) {
        if (_isServerAudioLoopbackMicrophone(publication)) {
          subscribed = true;
          unawaited(publication.subscribe());
        }
      }
    }

    if (!subscribed) {
      _serverAudioLoopbackError = 'waiting for local microphone publication';
      _notifyStateChanged();
    }
  }

  bool _isServerAudioLoopbackMicrophone(lk.RemoteTrackPublication publication) {
    return publication.kind == lk.TrackType.AUDIO &&
        publication.source != lk.TrackSource.screenShareAudio &&
        publication.name != 'screenShareAudio';
  }

  void _notifyStateChanged() {
    if (!_stateChanged.isClosed) {
      _stateChanged.add(());
    }
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    final requestedProfile = _screenShareProfile();
    return _setScreenShareWithProfile(source, requestedProfile);
  }

  Future<void> setScreenShareForStreamTest(
    ScreenCaptureSource source,
    ScreenShareProfileConfig requestedProfile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled = false,
    bool dummyNv12LiveSender = false,
  }) async {
    if (!preferences.developerMode.value) {
      throw StateError('Stream test runner requires developer mode.');
    }

    Log.i(
      'Stream test runner starting screen share preset '
      '${requestedProfile.label}: '
      '${_diagnosticsProfileDetails(requestedProfile)} '
      'windowsCaptureBackend='
      '${windowsCaptureBackendMode?.constraintValue ?? 'unchanged'} '
      'windowsCaptureDirtyRegion=${windowsCaptureDirtyRegionMode.constraintValue} '
      'windowsWindowGdi=${windowsWindowGdiCaptureMode?.constraintValue ?? 'default'} '
      'nativeFramePacing=$nativeFramePacingEnabled '
      'dummyNv12LiveSender=$dummyNv12LiveSender',
      category: LogCategory.livekit,
      source: 'stream-test-runner',
    );

    final videoSource =
        source is ShareCaptureSource ? source.videoSource : source;
    final useD3d11StreamTestPublishGuard = PlatformUtils.isWindows &&
        videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Window &&
        _windowsCaptureBackendModeForPublish(
              requestedMode: windowsCaptureBackendMode,
              isWindowSource: true,
              sourceTitle: videoSource.source.name,
            ) ==
            WindowsScreenCaptureBackendMode.gameD3d11HookExperimental;

    if (!useD3d11StreamTestPublishGuard) {
      await _setScreenShareWithProfile(
        source,
        requestedProfile,
        windowsCaptureBackendMode: windowsCaptureBackendMode,
        windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
        nativeFramePacingEnabled: nativeFramePacingEnabled,
        dummyNv12LiveSender: dummyNv12LiveSender,
      );
      return;
    }

    _streamTestScreenShareActive = true;
    _streamTestObservedLimitRefreshDeferred = false;
    _streamTestDiagnosticsSampleOrdinal = 0;
    _streamTestScreenSharePublishInProgress = true;
    try {
      return await _setScreenShareWithProfile(
        source,
        requestedProfile,
        windowsCaptureBackendMode: windowsCaptureBackendMode,
        windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
        restartSharedAudio: false,
        postPublishSenderLimitsTimeout: _streamTestSenderLimitsTimeout,
        nativeFramePacingEnabled: nativeFramePacingEnabled,
        dummyNv12LiveSender: dummyNv12LiveSender,
      );
    } catch (_) {
      _streamTestScreenShareActive = false;
      _streamTestObservedLimitRefreshDeferred = false;
      _streamTestDiagnosticsSampleOrdinal = 0;
      rethrow;
    } finally {
      _streamTestScreenSharePublishInProgress = false;
    }
  }

  Future<void> _setScreenShareWithProfile(
    ScreenCaptureSource source,
    ScreenShareProfileConfig requestedProfile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode? windowsCaptureDirtyRegionMode,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool updateRequestedProfile = true,
    bool resetAdaptiveFallback = true,
    bool restartSharedAudio = true,
    bool replaceExistingScreenShareVideo = false,
    bool awaitPostPublishSenderLimits = true,
    Duration? postPublishSenderLimitsTimeout,
    bool? nativeFramePacingEnabled,
    bool dummyNv12LiveSender = false,
  }) async {
    if (resetAdaptiveFallback) {
      _adaptiveFallbackController.reset();
    }
    final shareSource = source is ShareCaptureSource ? source : null;
    final videoSource = shareSource?.videoSource ?? source;
    var publishProfile = _screenShareProfileForSource(
      requestedProfile,
      videoSource,
    );
    if (updateRequestedProfile) {
      _requestedScreenShareProfile = publishProfile;
    }
    _activeScreenShareProfile = publishProfile;
    final requestedNativeFramePacingEnabled =
        nativeFramePacingEnabled ?? _defaultNativeFramePacingEnabledFor(source);
    final effectiveNativeFramePacingEnabled = PlatformUtils.isWindows &&
        (_gpuPipelineTestModeEnabled || requestedNativeFramePacingEnabled);
    final screenShareDimensions = _dimensionsForLayer(publishProfile.mainLayer);
    final captureParams = lk.VideoParameters(
      dimensions: screenShareDimensions,
      encoding: _encodingForLayer(publishProfile.mainLayer),
    );
    final baseCaptureOptions = lk.ScreenShareCaptureOptions(
      maxFrameRate: publishProfile.mainLayer.maxFramerate.toDouble(),
      params: captureParams,
    );

    if (videoSource is IosReplaykitScreencaptureSource) {
      final localParticipant = livekitRoom.localParticipant;
      if (localParticipant == null) {
        throw StateError(
          'Unable to start iOS screen share without a local participant.',
        );
      }

      final requested = await IosBroadcastControl.requestActivation();
      if (!requested) {
        throw StateError('Unable to open the iOS screen broadcast picker.');
      }

      final captureOptions = baseCaptureOptions.copyWith(
        useiOSBroadcastExtension: true,
      );

      await localParticipant.setScreenShareEnabled(
        true,
        screenShareCaptureOptions: captureOptions,
      );
      final published = await _waitForLocalScreenShareVideoPublication();
      if (!published) {
        Log.w(
          'iOS ReplayKit screen share activation did not publish a local '
          'screen-share video track within '
          '${_iosReplayKitPublishTimeout.inSeconds}s; rolling back.',
          category: LogCategory.livekit,
          source: 'ios-replaykit',
        );
        await _rollbackIosReplayKitScreenShareStart(localParticipant);
        throw StateError(
          'iOS screen broadcast did not publish a screen-share track.',
        );
      }

      await _applyScreenShareSenderLimits(publishProfile);
      _rememberScreenSharePublish(
        source,
        windowsCaptureBackendMode,
        null,
        null,
        effectiveNativeFramePacingEnabled,
      );
      _stateChanged.add(());
      return;
    }

    if (videoSource is WebrtcAndroidScreencaptureSource) {
      final localParticipant = livekitRoom.localParticipant;
      if (localParticipant == null) {
        Log.w("Android screen share requested without a local participant.");
        return;
      }

      final track = await lk.LocalVideoTrack.createScreenShareTrack(
        baseCaptureOptions,
      );

      try {
        await localParticipant.publishVideoTrack(
          track,
          publishOptions: _publishOptionsForProfile(publishProfile),
        );
      } catch (error, stackTrace) {
        await _rollbackPublishedScreenShareTracks(
          participant: localParticipant,
          publications: const [],
          tracks: [track],
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }

      Log.i("Got android screen capture source!");
      await _applyScreenShareSenderLimits(publishProfile);
      _rememberScreenSharePublish(
        source,
        windowsCaptureBackendMode,
        null,
        null,
        effectiveNativeFramePacingEnabled,
      );
      _stateChanged.add(());
      return;
    }

    final desktopVideoSource = videoSource as WebrtcScreencaptureSource;
    var src = desktopVideoSource.source;
    final effectiveWindowsCaptureBackendMode =
        _windowsCaptureBackendModeForPublish(
      requestedMode: windowsCaptureBackendMode,
      isWindowSource: src.type == SourceType.Window,
      sourceTitle: src.name,
    );
    final effectiveWindowsCaptureDirtyRegionMode =
        windowsCaptureDirtyRegionMode ??
            defaultWindowsCaptureDirtyRegionMode(
              isWindows: PlatformUtils.isWindows,
              isWebrtcDesktopSource: true,
              isWindowSource: src.type == SourceType.Window,
              effectiveBackendMode: effectiveWindowsCaptureBackendMode,
            );
    final shareSession = shareSource?.shareSession;
    final useExperimentalGameCaptureBackend =
        effectiveWindowsCaptureBackendMode ==
            WindowsScreenCaptureBackendMode.gameD3d11HookExperimental;
    final gpuPipelineTestModeForcedGameCapture = _gpuPipelineTestModeEnabled &&
        windowsCaptureBackendMode == null &&
        useExperimentalGameCaptureBackend;
    final automaticGameCaptureBackend = !gpuPipelineTestModeForcedGameCapture &&
        isAutomaticWindowsGameCaptureBackend(
          requestedMode: windowsCaptureBackendMode,
          effectiveMode: effectiveWindowsCaptureBackendMode,
        );
    final gameCaptureAdjustedProfile =
        publishProfile.withWindowsGameCaptureCadenceCompatibility(
      isExperimentalGameCaptureSource: useExperimentalGameCaptureBackend,
    );
    if (!identical(gameCaptureAdjustedProfile, publishProfile)) {
      final previousMaxFramerate = publishProfile.mainLayer.maxFramerate;
      publishProfile = gameCaptureAdjustedProfile;
      if (updateRequestedProfile) {
        _requestedScreenShareProfile = publishProfile;
      }
      _activeScreenShareProfile = publishProfile;
      Log.i(
        'D3D11 game-hook screen-share cadence compatibility applied: '
        'profile=${requestedProfile.label} '
        'sourceIdHash=${shortShareSourceIdHash(src.id)} '
        'fps=$previousMaxFramerate->'
        '${publishProfile.mainLayer.maxFramerate} '
        'reason=game_hook_async_readback_pacing',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
    }
    final desktopCaptureLayer = publishProfile.mainLayer;
    final desktopCaptureParams = lk.VideoParameters(
      dimensions: _dimensionsForLayer(desktopCaptureLayer),
      encoding: _encodingForLayer(desktopCaptureLayer),
    );
    _ensureWebrtcNativeEncoderLogging();

    Log.i(
      "Starting screen share profile ${publishProfile.label}: "
      "${_diagnosticsProfileDetails(publishProfile)}",
    );
    final refreshedSrc = await _refreshDesktopCaptureSourcesForPublish(src);
    if (!identical(refreshedSrc, src)) {
      desktopVideoSource.source = refreshedSrc;
      src = refreshedSrc;
    }
    final gameCaptureProcessId =
        useExperimentalGameCaptureBackend && !dummyNv12LiveSender
            ? await _resolveGameCaptureProcessId(src, shareSession)
            : null;
    final sourceTypeLabel = _desktopCaptureSourceTypeLabel(src.type);
    Future<void> retryLegacyWindowCaptureFallback({
      required String reason,
      Object? error,
      StackTrace? stackTrace,
    }) {
      final message = 'Automatic D3D11 game-hook screen share fallback: '
          'reason=$reason '
          'sourceType=$sourceTypeLabel '
          'sourceIdHash=${shortShareSourceIdHash(src.id)} '
          'gameCapturePid=${gameCaptureProcessId ?? 'none'} '
          'fallback=${WindowsScreenCaptureBackendMode.directxOnly.constraintValue}';
      if (error != null && stackTrace != null) {
        Log.onError(error, stackTrace, content: message);
      } else {
        Log.w(
          message,
          category: LogCategory.livekit,
          source: 'screen-share-publish',
        );
      }
      return _setScreenShareWithProfile(
        source,
        requestedProfile,
        windowsCaptureBackendMode: WindowsScreenCaptureBackendMode.directxOnly,
        windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
        updateRequestedProfile: updateRequestedProfile,
        resetAdaptiveFallback: false,
        restartSharedAudio: restartSharedAudio,
        replaceExistingScreenShareVideo: replaceExistingScreenShareVideo,
        nativeFramePacingEnabled: nativeFramePacingEnabled,
        dummyNv12LiveSender: dummyNv12LiveSender,
      );
    }

    if (publishProfile.useSimulcast != requestedProfile.useSimulcast) {
      Log.i(
        'Windows window screen-share publish compatibility applied: '
        'profile=${requestedProfile.label} '
        'sourceIdHash=${shortShareSourceIdHash(src.id)} '
        'simulcast=${requestedProfile.useSimulcast}->'
        '${publishProfile.useSimulcast} '
        'reason=window_simulcast_non_16_9_guard',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
    }
    if (useExperimentalGameCaptureBackend) {
      if (src.type != SourceType.Window) {
        throw StateError(
          'Experimental D3D11 game capture requires a window source.',
        );
      }
      if (!dummyNv12LiveSender &&
          (gameCaptureProcessId == null || gameCaptureProcessId <= 0)) {
        if (automaticGameCaptureBackend) {
          return retryLegacyWindowCaptureFallback(
            reason: 'game_capture_process_id_unavailable',
          );
        }
        throw StateError(
          'Experimental D3D11 game capture could not resolve the '
          'selected window process id.',
        );
      }
    }
    if (shareSession != null) {
      Log.i(
        'Starting LiveKit screen-share publish: '
        '${shareSession.diagnosticsSummary(includeTitle: _includePrivateShareDiagnostics).toLogLine()}',
      );
    }

    // Windows shared-content audio is owned by ShareSession, not the
    // microphone or the getDisplayMedia constraint. Other desktop platforms may
    // still receive a native screenshare-audio track when the user requested it.
    var captureOptions = baseCaptureOptions.copyWith(
      sourceId: src.id,
      captureScreenAudio: !PlatformUtils.isWindows &&
          (shareSource?.shareSession.sharedAudioRequested ?? true),
    );
    if (effectiveWindowsCaptureBackendMode != null ||
        effectiveWindowsCaptureDirtyRegionMode !=
            WindowsScreenCaptureDirtyRegionMode.auto ||
        windowsWindowGdiCaptureMode != null ||
        effectiveNativeFramePacingEnabled ||
        dummyNv12LiveSender) {
      captureOptions = _IntergalacticScreenShareCaptureOptions(
        windowsCaptureBackendMode: effectiveWindowsCaptureBackendMode,
        windowsCaptureDirtyRegionMode: effectiveWindowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
        gameCaptureProcessId: gameCaptureProcessId,
        nativeFramePacingEnabled: effectiveNativeFramePacingEnabled,
        dummyNv12LiveSender: dummyNv12LiveSender,
        sourceId: src.id,
        maxFrameRate: desktopCaptureLayer.maxFramerate.toDouble(),
        params: desktopCaptureParams,
        captureScreenAudio: false,
      );
    }

    Log.i(
      'LiveKit screen-share capture request: '
      'sourceType=$sourceTypeLabel '
      'sourceIdHash=${shortShareSourceIdHash(src.id)} '
      'requestedMax=${desktopCaptureLayer.width}x'
      '${desktopCaptureLayer.height} '
      'fps=${desktopCaptureLayer.maxFramerate} '
      'publishFps=${publishProfile.mainLayer.maxFramerate} '
      'windowsCaptureBackend='
      '${effectiveWindowsCaptureBackendMode?.constraintValue ?? 'unchanged'} '
      'windowsCaptureDirtyRegion=${effectiveWindowsCaptureDirtyRegionMode.constraintValue} '
      'windowsWindowGdi=${windowsWindowGdiCaptureMode?.constraintValue ?? 'default'} '
      'nativeFramePacing=$effectiveNativeFramePacingEnabled '
      'dummyNv12LiveSender=$dummyNv12LiveSender '
      'gpuPipelineTestMode=$gpuPipelineTestModeForcedGameCapture '
      'gameCapturePid=${gameCaptureProcessId ?? 'none'} '
      'captureScreenAudio=${captureOptions.captureScreenAudio}',
      category: LogCategory.livekit,
      source: 'screen-share-publish',
    );

    final stopExistingVideoBeforePublish =
        replaceExistingScreenShareVideo && PlatformUtils.isWindows;
    if (stopExistingVideoBeforePublish) {
      // Windows desktop capture backends do not reliably produce frames when a
      // replacement capturer starts before the previous screen-share video
      // capturer has stopped. Accept a short stream gap to keep the new sender
      // from publishing as a zero-frame track.
      await _stopLocalScreenShareVideoPublications(
        reason: 'screen-share capture refresh before republish',
      );
    }

    late final List<lk.LocalTrack> tracks;
    try {
      if (PlatformUtils.isWindows) {
        tracks = <lk.LocalTrack>[
          await lk.LocalVideoTrack.createScreenShareTrack(captureOptions),
        ];
      } else {
        tracks = await lk.LocalVideoTrack.createScreenShareTracksWithAudio(
          captureOptions,
        );
      }
    } catch (error, stackTrace) {
      if (stopExistingVideoBeforePublish) {
        await _clearScreenShareAfterFailedRefresh(
          shareSession: _currentShareSession ?? shareSession,
          reason: 'track creation failed',
        );
      } else if (!replaceExistingScreenShareVideo) {
        _resetScreenShareState();
        _stateChanged.add(());
      }
      if (automaticGameCaptureBackend) {
        return retryLegacyWindowCaptureFallback(
          reason: 'game_capture_track_creation_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to create LiveKit screen-share tracks '
            'sourceType=$sourceTypeLabel '
            'sourceIdHash=${shortShareSourceIdHash(src.id)} '
            'requestedMax=${desktopCaptureLayer.width}x'
            '${desktopCaptureLayer.height} '
            'fps=${desktopCaptureLayer.maxFramerate} '
            'publishFps=${publishProfile.mainLayer.maxFramerate} '
            'windowsCaptureBackend='
            '${effectiveWindowsCaptureBackendMode?.constraintValue ?? 'unchanged'} '
            'windowsCaptureDirtyRegion=${effectiveWindowsCaptureDirtyRegionMode.constraintValue} '
            'windowsWindowGdi=${windowsWindowGdiCaptureMode?.constraintValue ?? 'default'} '
            'nativeFramePacing=$effectiveNativeFramePacingEnabled '
            'gameCapturePid=${gameCaptureProcessId ?? 'none'} '
            'captureScreenAudio=${captureOptions.captureScreenAudio}',
      );
      rethrow;
    }
    final localParticipant = livekitRoom.localParticipant;
    if (localParticipant == null) {
      Log.w(
        "Screen share tracks were created without a local participant; "
        "cleaning them up.",
      );
      await _stopCreatedScreenShareTracks(tracks);
      if (stopExistingVideoBeforePublish) {
        await _clearScreenShareAfterFailedRefresh(
          shareSession: _currentShareSession ?? shareSession,
          reason: 'missing local participant',
        );
      } else if (!replaceExistingScreenShareVideo) {
        _resetScreenShareState();
        _stateChanged.add(());
      }
      return;
    }
    final publishedPublications = <lk.LocalTrackPublication>[];

    final hasAudio = tracks.any((t) => t is lk.LocalAudioTrack);
    Log.i(
      "Screen share tracks created: ${tracks.length} "
      "(${tracks.map((t) => t.runtimeType).join(', ')})",
    );
    if (!hasAudio && PlatformUtils.isWindows) {
      Log.i(
        "Windows screen share uses the separate shared-content audio "
        "pipeline; getDisplayMedia audio was not requested.",
      );
    } else if (!hasAudio) {
      Log.w(
        "No getDisplayMedia screen-share audio track was returned. "
        "Video-only WebRTC publishing will proceed.",
      );
    }

    try {
      for (final track in tracks) {
        if (track is lk.LocalVideoTrack) {
          final publication = await _publishScreenShareVideoTrack(
            participant: localParticipant,
            track: track,
            publishProfile: publishProfile,
            guardPrePublication: _streamTestScreenSharePublishInProgress &&
                useExperimentalGameCaptureBackend,
            sourceTypeLabel: sourceTypeLabel,
            sourceIdHash: shortShareSourceIdHash(src.id),
            windowsCaptureBackendMode: effectiveWindowsCaptureBackendMode,
            windowsCaptureDirtyRegionMode:
                effectiveWindowsCaptureDirtyRegionMode,
            windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
            nativeFramePacingEnabled: effectiveNativeFramePacingEnabled,
            gameCaptureProcessId: gameCaptureProcessId,
          );
          publishedPublications.add(publication);
        } else if (track is lk.LocalAudioTrack) {
          // Publish the captured desktop/application audio as a separate audio
          // track tagged screenShareAudio.  Remote participants receive it just
          // like any other audio track; no special handling is needed on their
          // end.
          Log.i("Publishing screen share audio track");
          final publication = await localParticipant.publishAudioTrack(track);
          publishedPublications.add(publication);
        }
      }
      if (replaceExistingScreenShareVideo && !stopExistingVideoBeforePublish) {
        await _stopLocalScreenShareVideoPublications(
          reason: 'screen-share capture bounds refresh',
          exceptPublicationSids: publishedPublications
              .where((publication) => publication.kind == lk.TrackType.VIDEO)
              .map((publication) => publication.sid)
              .toSet(),
        );
      }
    } catch (error, stackTrace) {
      await _rollbackPublishedScreenShareTracks(
        participant: localParticipant,
        publications: publishedPublications,
        tracks: tracks,
        error: error,
        stackTrace: stackTrace,
      );
      if (stopExistingVideoBeforePublish) {
        await _clearScreenShareAfterFailedRefresh(
          shareSession: _currentShareSession ?? shareSession,
          reason: 'replacement publish failed',
        );
      }
      rethrow;
    }

    if (awaitPostPublishSenderLimits) {
      await _applyScreenShareSenderLimits(
        publishProfile,
        localPublications: publishedPublications,
        timeout: postPublishSenderLimitsTimeout,
      );
    }

    _currentShareSession = shareSource?.shareSession;
    _rememberScreenSharePublish(
      source,
      effectiveWindowsCaptureBackendMode,
      effectiveWindowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode,
      effectiveNativeFramePacingEnabled,
    );
    if (!restartSharedAudio) {
      Log.i(
        "Screen-share video capture refreshed; shared audio state was "
        "left unchanged.",
      );
    } else if (PlatformUtils.isWindows) {
      await _publishWindowsSharedAudio(_currentShareSession, localParticipant);
    } else {
      try {
        await _currentShareSession?.startSharedAudio();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to start shared audio; continuing video-only',
        );
      }
    }
    _stateChanged.add(());
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) {
    return _queueCameraOperation(() => _setCamera(device));
  }

  Future<void> _setCamera(MediaDeviceInfo? device) async {
    if (_ending || state == VoipState.ended) {
      return;
    }

    final localParticipant = livekitRoom.localParticipant;
    if (localParticipant == null) {
      Log.e('Tried to enable camera before LiveKit local participant existed.');
      return;
    }

    if (isCameraEnabled) {
      Log.e("Tried to enable camera when camera already enabled!");
      return;
    }

    await _stopLocalCameraPublications(reason: 'camera enable cleanup');
    if (_ending || state == VoipState.ended) {
      return;
    }

    // Build the camera track explicitly so we can control capture resolution,
    // framerate cap, codec, and degradation preference.  setCameraEnabled(true)
    // with no options defaults to 720p with no framerate limit and balanced
    // degradation — all of which increase CPU load in grid-call scenarios.
    lk.LocalVideoTrack? track;
    try {
      Log.i(
        'LiveKit camera enable requested '
        'device=${device?.deviceId == null ? 'default' : 'selected'}',
      );
      track = await lk.LocalVideoTrack.createCameraTrack(
        lk.CameraCaptureOptions(
          deviceId: device?.deviceId,
          // 640x360, 15fps cap looks fine in participant tiles and cuts the
          // encoder's pixel workload to about 25% of 720p.
          params: lk.VideoParametersPresets.h360_169,
          maxFrameRate: 15,
        ),
      );
      if (_ending || state == VoipState.ended) {
        try {
          await track.stop();
        } catch (stopError, stopStackTrace) {
          Log.onError(
            stopError,
            stopStackTrace,
            content: 'Failed to stop camera track after call teardown began',
          );
        }
        return;
      }

      final publication = await localParticipant.publishVideoTrack(
        track,
        publishOptions: lk.VideoPublishOptions(
          // Keep camera tiles on the lightweight VP8 path. Gameplay screen
          // share uses its own profile-derived codec and sender limits above.
          videoCodec: 'vp8',
          // Camera re-publish diagnostics showed dead q/h simulcast senders
          // after stop/re-enable. Use one camera layer; screen sharing owns the
          // high-quality media path.
          simulcast: false,
          // Preserve motion (framerate) and drop resolution under pressure.
          degradationPreference: lk.DegradationPreference.maintainFramerate,
          backupVideoCodec: lk.BackupVideoCodec(enabled: false),
        ),
      );
      Log.i(
        'LiveKit camera published: '
        '${_trackPublicationSummary(publication)}',
      );
    } catch (error, stackTrace) {
      if (track != null) {
        try {
          await track.stop();
        } catch (stopError, stopStackTrace) {
          Log.onError(
            stopError,
            stopStackTrace,
            content: 'Failed to stop camera track after publish failure',
          );
        }
      }
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to enable LiveKit camera',
      );
      rethrow;
    }

    _stateChanged.add(());
  }

  @override
  Future<void> stopCamera() {
    return _queueCameraOperation(_stopCamera);
  }

  Future<void> _stopCamera() async {
    if (_ending || state == VoipState.ended) {
      return;
    }

    Log.i('LiveKit camera disable requested');
    await _stopLocalCameraPublications(reason: 'camera disable');
    if (_ending || state == VoipState.ended) {
      return;
    }
    _stateChanged.add(());
  }

  @override
  Future<void> stopScreenshare() async {
    final shareSession = _currentShareSession;
    try {
      if (PlatformUtils.isIOS) {
        await IosBroadcastControl.requestStop();
      }

      await _stopWindowsSharedAudioPublication(shareSession);
      await _stopLocalScreenShareVideoPublications(
        reason: 'screen-share stop',
      );
      await livekitRoom.localParticipant?.setScreenShareEnabled(false);
      await shareSession?.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop LiveKit screen share',
      );
      rethrow;
    }

    _resetScreenShareState();

    if (PlatformUtils.isAndroid) {
      try {
        await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        Log.e('error disabling screen share: $error');
      }
    }

    _stateChanged.add(());
  }

  void _resetScreenShareState() {
    _currentShareSession = null;
    _activeScreenShareSource = null;
    _activeWindowsCaptureBackendMode = null;
    _activeWindowsCaptureDirtyRegionMode = null;
    _activeWindowsWindowGdiCaptureMode = null;
    _activeNativeFramePacingEnabled = false;
    _requestedScreenShareProfile = null;
    _activeScreenShareProfile = null;
    _adaptiveFallbackController.reset();
    _senderStatsSamples.clear();
    _receiverJitterBufferSamples.clear();
    _senderEncodeTimeSamples.clear();
    _senderPacketSendDelaySamples.clear();
    _receiverDecodeTimeSamples.clear();
    _senderRetransmitStatsSamples.clear();
    _appliedScreenShareLimitKeys.clear();
    _screenShareObservedSizes.clear();
    _cpuRescueLayerDisabledStreams.clear();
    _screenShareCaptureRefreshInFlight = false;
    _streamTestScreenSharePublishInProgress = false;
    _streamTestScreenShareActive = false;
    _streamTestObservedLimitRefreshDeferred = false;
    _streamTestDiagnosticsSampleOrdinal = 0;
    _latestIceTransportSummary = null;
    _latestAvailableOutgoingBitrateBps = null;
    _latestAvailableIncomingBitrateBps = null;
  }

  Future<void> _clearScreenShareAfterFailedRefresh({
    required ShareSession? shareSession,
    required String reason,
  }) async {
    try {
      await _stopWindowsSharedAudioPublication(shareSession);
      await livekitRoom.localParticipant?.setScreenShareEnabled(false);
      await shareSession?.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear screen share after failed refresh: $reason',
      );
    }

    _resetScreenShareState();
    _stateChanged.add(());
  }

  @override
  List<VoipStream> streams = List<VoipStream>.empty(growable: true);

  @override
  bool get supportsScreenshare => true;

  @override
  Future<void> updateStats() async {
    final now = DateTime.now();
    if (_streamTestScreenShareActive) {
      return;
    }
    if (now.difference(_lastUpdatedDiagnostics) < const Duration(seconds: 2)) {
      return;
    }

    final adaptiveFallbackEnabled = _adaptiveFallbackEnabled;
    final shouldCollect =
        preferences.showCallStreamStats.value || adaptiveFallbackEnabled;
    if (!shouldCollect || state == VoipState.ended) {
      return;
    }

    _lastUpdatedDiagnostics = now;
    final tracks = await _collectDiagnosticsTracks();
    final fallbackReason = await _applyAdaptiveScreenShareFallback(
      now: now,
      tracks: tracks,
    );

    _diagnosticsSnapshot = _buildDiagnosticsSnapshot(
      collectedAt: now,
      tracks: tracks,
      adaptiveFallbackReason: fallbackReason,
    );
    _maybeLogDiagnosticsSnapshot(_diagnosticsSnapshot);
    _onDiagnosticsChanged.add(null);
  }

  Future<String?> _applyAdaptiveScreenShareFallback({
    required DateTime now,
    required List<VoipTrackDiagnostics> tracks,
  }) async {
    String? fallbackReason = _adaptiveFallbackController.reason;
    final requestedProfile = _requestedScreenShareProfile;
    final activeProfile = _activeScreenShareProfile;
    if (_adaptiveFallbackEnabled &&
        requestedProfile != null &&
        activeProfile != null) {
      final decision = _adaptiveFallbackController.evaluate(
        requestedProfile: requestedProfile,
        snapshot: _buildDiagnosticsSnapshot(
          collectedAt: now,
          tracks: tracks,
          adaptiveFallbackReason: fallbackReason,
        ),
        now: now,
      );
      fallbackReason = decision.reason;
      if (decision.changed) {
        final captureRefreshed = await _refreshScreenShareCaptureForProfile(
          previousProfile: activeProfile,
          nextProfile: decision.profile,
          reason: decision.reason ?? 'adaptive fallback profile change',
        );
        if (!captureRefreshed && _hasActiveLocalScreenShareVideo) {
          _activeScreenShareProfile = decision.profile;
          await _applyScreenShareSenderLimits(decision.profile);
        }
      }
    } else if (requestedProfile != null &&
        activeProfile != null &&
        !_profileLimitsEqual(requestedProfile, activeProfile)) {
      _adaptiveFallbackController.reset();
      final captureRefreshed = await _refreshScreenShareCaptureForProfile(
        previousProfile: activeProfile,
        nextProfile: requestedProfile,
        reason: 'adaptive fallback recovered',
      );
      if (!captureRefreshed && _hasActiveLocalScreenShareVideo) {
        _activeScreenShareProfile = requestedProfile;
        await _applyScreenShareSenderLimits(requestedProfile);
      }
      fallbackReason = null;
    }

    return fallbackReason;
  }

  Future<bool> _refreshScreenShareCaptureForProfile({
    required ScreenShareProfileConfig previousProfile,
    required ScreenShareProfileConfig nextProfile,
    required String reason,
  }) async {
    if (!_shouldRefreshScreenShareCaptureForProfile(
      previousProfile: previousProfile,
      nextProfile: nextProfile,
    )) {
      return false;
    }
    if (_screenShareCaptureRefreshInFlight) {
      Log.i(
        'Screen-share capture refresh already in flight; skipping duplicate '
        'request for ${nextProfile.label}.',
      );
      return true;
    }

    final source = _activeScreenShareSource;
    if (source == null) {
      return false;
    }

    _screenShareCaptureRefreshInFlight = true;
    try {
      Log.i(
        'Recreating Windows screen-share capture for ${nextProfile.label}: '
        '${previousProfile.mainLayer.resolutionLabel}@'
        '${previousProfile.mainLayer.maxFramerate}fps -> '
        '${nextProfile.mainLayer.resolutionLabel}@'
        '${nextProfile.mainLayer.maxFramerate}fps; reason=$reason',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
      await _setScreenShareWithProfile(
        source,
        nextProfile,
        windowsCaptureBackendMode: _activeWindowsCaptureBackendMode,
        windowsCaptureDirtyRegionMode: _activeWindowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: _activeWindowsWindowGdiCaptureMode,
        updateRequestedProfile: false,
        resetAdaptiveFallback: false,
        restartSharedAudio: false,
        replaceExistingScreenShareVideo: true,
        nativeFramePacingEnabled: _activeNativeFramePacingEnabled,
      );
      return true;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to recreate Windows screen-share capture for ${nextProfile.label}; '
            'falling back to sender-parameter limits',
      );
      return false;
    } finally {
      _screenShareCaptureRefreshInFlight = false;
    }
  }

  bool _shouldRefreshScreenShareCaptureForProfile({
    required ScreenShareProfileConfig previousProfile,
    required ScreenShareProfileConfig nextProfile,
  }) {
    if (!PlatformUtils.isWindows ||
        !_screenShareCaptureLayerChanged(
          previousProfile.mainLayer,
          nextProfile.mainLayer,
        ) ||
        !_isDesktopScreenShareSource(_activeScreenShareSource)) {
      return false;
    }

    return _localScreenShareVideoPublications().isNotEmpty;
  }

  bool _screenShareCaptureLayerChanged(
    ScreenShareVideoLayer previous,
    ScreenShareVideoLayer next,
  ) {
    return previous.width != next.width ||
        previous.height != next.height ||
        previous.maxFramerate != next.maxFramerate;
  }

  bool _isDesktopScreenShareSource(ScreenCaptureSource? source) {
    final videoSource =
        source is ShareCaptureSource ? source.videoSource : source;
    return videoSource is WebrtcScreencaptureSource;
  }

  Future<VoipCallDiagnosticsSnapshot> collectStreamTestDiagnostics({
    bool applyAdaptiveFallback = false,
  }) async {
    if (!preferences.developerMode.value) {
      throw StateError('Stream test diagnostics require developer mode.');
    }

    final now = DateTime.now();
    final sampleOrdinal = _streamTestScreenShareActive
        ? ++_streamTestDiagnosticsSampleOrdinal
        : 0;
    final streamTestSampleOrdinal = sampleOrdinal > 0 ? sampleOrdinal : null;
    final collectRawStats = streamTestSampleOrdinal == null ||
        streamTestSampleOrdinal == 1 ||
        streamTestSampleOrdinal % _streamTestRawDiagnosticsSampleInterval == 0;
    final refreshIceDiagnostics = streamTestSampleOrdinal == null ||
        streamTestSampleOrdinal <= _streamTestIceDiagnosticsInitialSamples;
    final diagnosticsStartedAt = DateTime.now();
    if (streamTestSampleOrdinal != null) {
      Log.i(
        'Stream-test diagnostics sample $streamTestSampleOrdinal started '
        'rawStats=$collectRawStats iceStats=$refreshIceDiagnostics',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      await Future<void>.delayed(Duration.zero);
    }
    final tracks = await _collectDiagnosticsTracks(
      forceStatsDebug: true,
      collectRawStats: collectRawStats,
      refreshIceDiagnostics: refreshIceDiagnostics,
      streamTestSampleOrdinal: streamTestSampleOrdinal,
    );
    // Stream tests are measurement runs; applying fallback here republished the
    // stream during sampling and contaminated backend/preset comparisons.
    final fallbackReason = applyAdaptiveFallback
        ? await _applyAdaptiveScreenShareFallback(now: now, tracks: tracks)
        : _adaptiveFallbackController.reason;
    final snapshot = _buildDiagnosticsSnapshot(
      collectedAt: now,
      tracks: tracks,
      adaptiveFallbackReason: fallbackReason,
    );
    _lastUpdatedDiagnostics = now;
    _diagnosticsSnapshot = snapshot;
    _maybeLogDiagnosticsSnapshot(snapshot);
    _onDiagnosticsChanged.add(null);
    if (streamTestSampleOrdinal != null) {
      final elapsedMs =
          DateTime.now().difference(diagnosticsStartedAt).inMilliseconds;
      Log.i(
        'Stream-test diagnostics sample $streamTestSampleOrdinal completed '
        'elapsedMs=$elapsedMs tracks=${tracks.length}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
    }
    return snapshot;
  }

  Future<void> _updateStreamLiveTuningHarness() async {
    final harness = StreamLiveTuningHarness.instance;
    if (!harness.isSupported ||
        _streamLiveTuningTickInFlight ||
        _streamTestScreenShareActive ||
        _gpuPipelineTestModeEnabled ||
        _ending ||
        state == VoipState.ended) {
      return;
    }

    _streamLiveTuningTickInFlight = true;
    try {
      final config = await harness.readConfig();
      if (!config.enabled) {
        _streamLiveTuningAppliedSignature = null;
        if (config.loadError != null) {
          await harness.writeStatus(
            config: config,
            activeScreenShare: _hasActiveLocalScreenShareVideo,
            applicationNotes: config.applicationNotes,
            activeProfile: _activeScreenShareProfile,
            windowsCaptureBackendLabel: _streamLiveTuningBackendLabel(
              _activeWindowsCaptureBackendMode,
            ),
          );
        }
        return;
      }

      final applicationNotes = <String>[...config.applicationNotes];
      final activeProfile =
          _activeScreenShareProfile ?? _requestedScreenShareProfile;
      final fallbackProfile = activeProfile ?? _screenShareProfile();
      final requestedProfile = config.toScreenShareProfile(fallbackProfile);
      final requestedBackend = config.hasWindowsCaptureBackendOverride
          ? config.effectiveWindowsCaptureBackendMode
          : _activeWindowsCaptureBackendMode;
      final requestedBackendLabel = config.hasWindowsCaptureBackendOverride
          ? (config.windowsCaptureBackendMode?.constraintValue ?? 'app-default')
          : _streamLiveTuningBackendLabel(_activeWindowsCaptureBackendMode);

      if (!preferences.developerMode.value ||
          !preferences.showCallStreamStats.value) {
        applicationNotes.add('waiting_for_developer_diagnostics_enabled');
        await harness.writeStatus(
          config: config,
          activeScreenShare: _hasActiveLocalScreenShareVideo,
          applicationNotes: applicationNotes,
          activeProfile: activeProfile,
          windowsCaptureBackendLabel: requestedBackendLabel,
        );
        return;
      }

      applicationNotes.addAll(
        await _applyStreamLiveTuningConfig(
          config: config,
          requestedProfile: requestedProfile,
          requestedWindowsCaptureBackendMode: requestedBackend,
          requestedWindowsCaptureBackendLabel: requestedBackendLabel,
        ),
      );

      final snapshot = await collectStreamTestDiagnostics();
      final effectiveProfile = _activeScreenShareProfile ?? requestedProfile;
      final nativeLogText = await NativeWebrtcDiagnostics.recentText(
        maxFileBytes: 192 * 1024,
      );
      await harness.appendSnapshot(
        config: config,
        snapshot: snapshot,
        activeProfile: effectiveProfile,
        activeScreenShare: _hasActiveLocalScreenShareVideo,
        windowsCaptureBackendLabel: _streamLiveTuningBackendLabel(
          _activeWindowsCaptureBackendMode,
        ),
        applicationNotes: applicationNotes,
        nativeDiagnosticLogText: nativeLogText,
      );
      await harness.writeStatus(
        config: config,
        activeScreenShare: _hasActiveLocalScreenShareVideo,
        applicationNotes: applicationNotes,
        activeProfile: effectiveProfile,
        windowsCaptureBackendLabel: _streamLiveTuningBackendLabel(
          _activeWindowsCaptureBackendMode,
        ),
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Stream live tuning harness tick failed',
      );
    } finally {
      _streamLiveTuningTickInFlight = false;
    }
  }

  Future<List<String>> _applyStreamLiveTuningConfig({
    required StreamLiveTuningConfig config,
    required ScreenShareProfileConfig requestedProfile,
    required WindowsScreenCaptureBackendMode?
        requestedWindowsCaptureBackendMode,
    required String requestedWindowsCaptureBackendLabel,
  }) async {
    final notes = <String>[];
    if (!config.applyProfileLive) {
      notes.add('live_apply_disabled');
      return notes;
    }
    if (!PlatformUtils.isWindows) {
      notes.add('live_apply_skipped_non_windows');
      return notes;
    }
    final source = _activeScreenShareSource;
    if (source == null || !_hasActiveLocalScreenShareVideo) {
      notes.add('waiting_for_active_screen_share');
      return notes;
    }
    if (!_isDesktopScreenShareSource(source)) {
      notes.add('live_apply_skipped_non_desktop_source');
      return notes;
    }
    if (_screenShareCaptureRefreshInFlight) {
      notes.add('live_apply_waiting_for_capture_refresh');
      return notes;
    }
    final effectiveRequestedWindowsCaptureBackendMode =
        _windowsCaptureBackendModeForPublish(
      requestedMode: requestedWindowsCaptureBackendMode,
      isWindowSource: _isWindowsWindowScreenShareSource(source),
      sourceTitle: _currentShareSession?.target.title,
    );
    final switchingAwayFromDirectx = _activeWindowsCaptureBackendMode ==
            WindowsScreenCaptureBackendMode.directxOnly &&
        effectiveRequestedWindowsCaptureBackendMode !=
            WindowsScreenCaptureBackendMode.directxOnly;
    if (switchingAwayFromDirectx) {
      notes.add('directx_live_backend_restart_required_before_switch');
      Log.w(
        'Stream live tuning skipped backend switch away from DirectX-only; '
        'stop and restart the screen share before measuring another backend.',
        category: LogCategory.livekit,
        source: 'stream-live-tuning',
      );
      return notes;
    }

    final currentProfile =
        _activeScreenShareProfile ?? _requestedScreenShareProfile;
    final profileChanged = currentProfile == null ||
        !_profileLimitsEqual(currentProfile, requestedProfile);
    final backendChanged = config.hasWindowsCaptureBackendOverride &&
        effectiveRequestedWindowsCaptureBackendMode !=
            _activeWindowsCaptureBackendMode;
    final signature = config.liveApplySignature(
      profile: requestedProfile,
      windowsCaptureBackendLabel: requestedWindowsCaptureBackendLabel,
    );
    if (!profileChanged &&
        !backendChanged &&
        _streamLiveTuningAppliedSignature == signature) {
      notes.add('already_applied');
      return notes;
    }

    _screenShareCaptureRefreshInFlight = true;
    try {
      Log.i(
        'Stream live tuning applying screen-share config: '
        '${_diagnosticsProfileDetails(requestedProfile)} '
        'windowsCaptureBackend=$requestedWindowsCaptureBackendLabel',
        category: LogCategory.livekit,
        source: 'stream-live-tuning',
      );
      await _setScreenShareWithProfile(
        source,
        requestedProfile,
        windowsCaptureBackendMode: requestedWindowsCaptureBackendMode,
        updateRequestedProfile: true,
        resetAdaptiveFallback: true,
        restartSharedAudio: false,
        replaceExistingScreenShareVideo: true,
        nativeFramePacingEnabled: PlatformUtils.isWindows &&
            (_activeNativeFramePacingEnabled ||
                _defaultNativeFramePacingEnabledFor(source)),
      );
      _streamLiveTuningAppliedSignature = signature;
      notes.add('applied_live_republish');
    } catch (error, stackTrace) {
      notes.add('live_apply_failed=$error');
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to apply stream live tuning config',
      );
    } finally {
      _screenShareCaptureRefreshInFlight = false;
    }
    return notes;
  }

  bool get _hasActiveLocalScreenShareVideo {
    return _localScreenShareVideoPublications().isNotEmpty;
  }

  Future<bool> _waitForLocalScreenShareVideoPublication() async {
    if (_hasActiveLocalScreenShareVideo) {
      return true;
    }

    final deadline = DateTime.now().add(_iosReplayKitPublishTimeout);
    while (!_ending &&
        state != VoipState.ended &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_iosReplayKitPublishPollInterval);
      if (_hasActiveLocalScreenShareVideo) {
        return true;
      }
    }

    return _hasActiveLocalScreenShareVideo;
  }

  Future<void> _rollbackIosReplayKitScreenShareStart(
    lk.LocalParticipant localParticipant,
  ) async {
    try {
      await IosBroadcastControl.requestStop();
    } catch (error) {
      Log.w(
        'Failed to request iOS ReplayKit stop during rollback: $error',
        category: LogCategory.livekit,
        source: 'ios-replaykit',
      );
    }

    try {
      await _stopLocalScreenShareVideoPublications(
        reason: 'iOS ReplayKit start rollback',
      );
      await localParticipant.setScreenShareEnabled(false);
    } catch (error) {
      Log.w(
        'Failed to clear LiveKit screen-share state during iOS rollback: '
        '$error',
        category: LogCategory.livekit,
        source: 'ios-replaykit',
      );
    }

    _resetScreenShareState();
    _stateChanged.add(());
  }

  String _streamLiveTuningBackendLabel(
    WindowsScreenCaptureBackendMode? backend,
  ) {
    return backend?.constraintValue ?? 'app-default';
  }

  VoipCallDiagnosticsSnapshot _buildDiagnosticsSnapshot({
    required DateTime collectedAt,
    required List<VoipTrackDiagnostics> tracks,
    String? adaptiveFallbackReason,
  }) {
    final profile = _activeScreenShareProfile ?? _screenShareProfile();
    return VoipCallDiagnosticsSnapshot(
      collectedAt: collectedAt,
      screenShareProfileLabel: _diagnosticsProfileLabel(profile),
      screenShareProfileDetails: _diagnosticsProfileDetails(profile),
      adaptiveStreamEnabled: true,
      dynacastEnabled: true,
      screenShareSimulcastEnabled: profile.useSimulcast,
      adaptiveFallbackEnabled: _adaptiveFallbackEnabled,
      adaptiveFallbackReason: adaptiveFallbackReason,
      iceTransportSummary: _latestIceTransportSummary,
      shareSessionDiagnostics: _currentShareSession?.diagnosticsSummary(
        includeTitle: _includePrivateShareDiagnostics,
      ),
      participants: List.unmodifiable(_collectParticipantDiagnostics()),
      tracks: List.unmodifiable(tracks),
    );
  }

  bool get _includePrivateShareDiagnostics =>
      preferences.developerMode.value && preferences.showCallStreamStats.value;

  void _rememberScreenSharePublish(
    ScreenCaptureSource source,
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode? windowsCaptureDirtyRegionMode,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled,
  ) {
    _activeScreenShareSource = source;
    _activeWindowsCaptureBackendMode = windowsCaptureBackendMode;
    _activeWindowsCaptureDirtyRegionMode = windowsCaptureDirtyRegionMode;
    _activeWindowsWindowGdiCaptureMode = windowsWindowGdiCaptureMode;
    _activeNativeFramePacingEnabled = nativeFramePacingEnabled;
  }

  String _desktopCaptureSourceTypeLabel(SourceType type) {
    return type == SourceType.Screen ? 'display' : 'window';
  }

  bool _defaultNativeFramePacingEnabledFor(ScreenCaptureSource source) {
    if (!PlatformUtils.isWindows) {
      return false;
    }
    final videoSource =
        source is ShareCaptureSource ? source.videoSource : source;
    return videoSource is WebrtcScreencaptureSource;
  }

  bool _isWindowsWindowScreenShareSource(ScreenCaptureSource source) {
    if (!PlatformUtils.isWindows) {
      return false;
    }
    final videoSource =
        source is ShareCaptureSource ? source.videoSource : source;
    return videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Window;
  }

  WindowsScreenCaptureBackendMode? _windowsCaptureBackendModeForPublish({
    required WindowsScreenCaptureBackendMode? requestedMode,
    required bool isWindowSource,
    String? sourceTitle,
  }) {
    if (_gpuPipelineTestModeEnabled && isWindowSource) {
      return WindowsScreenCaptureBackendMode.gameD3d11HookExperimental;
    }

    return defaultWindowsCaptureBackendMode(
      isWindows: PlatformUtils.isWindows,
      isWebrtcDesktopSource: true,
      isWindowSource: isWindowSource,
      requestedMode: requestedMode,
      preferGameCaptureForWindowSource: preferences.developerMode.value,
      sourceTitle: sourceTitle,
    );
  }

  Future<DesktopCapturerSource> _refreshDesktopCaptureSourcesForPublish(
    DesktopCapturerSource source,
  ) async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return source;
    }

    final sourceTypes = PlatformUtils.displayServer == 'wayland'
        ? const [SourceType.Screen]
        : const [SourceType.Window, SourceType.Screen];
    try {
      await desktopCapturer.updateSources(types: sourceTypes);
      final refreshedSources = await desktopCapturer.getSources(
        types: [source.type],
        thumbnailSize: ThumbnailSize(1, 1),
      );
      var matchKind = 'id';
      DesktopCapturerSource? refreshedSource;
      for (final candidate in refreshedSources) {
        if (candidate.id == source.id) {
          refreshedSource = candidate;
          break;
        }
      }
      if (refreshedSource == null) {
        matchKind = 'name';
        final sourceName = _normalizedDesktopSourceName(source.name);
        final nameMatches = refreshedSources
            .where(
              (candidate) =>
                  _normalizedDesktopSourceName(candidate.name) == sourceName,
            )
            .toList(growable: false);
        if (nameMatches.length == 1) {
          refreshedSource = nameMatches.single;
        } else if (nameMatches.length > 1) {
          matchKind = 'ambiguous-name';
        }
      }
      if (refreshedSource == null) {
        matchKind = 'none';
      }
      final resolvedSource = refreshedSource ?? source;
      Log.i(
        'Refreshed desktop capture source cache before publish: '
        'requestedType=${_desktopCaptureSourceTypeLabel(source.type)} '
        'sourceIdHash=${shortShareSourceIdHash(source.id)} '
        'resolvedSourceIdHash=${shortShareSourceIdHash(resolvedSource.id)} '
        'match=$matchKind '
        'candidates=${refreshedSources.length} '
        'cacheTypes=${sourceTypes.map((type) => type.name).join(',')}',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
      return resolvedSource;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh desktop capture source cache before '
            'screen-share publish; continuing with the existing cache '
            'sourceType=${_desktopCaptureSourceTypeLabel(source.type)} '
            'sourceIdHash=${shortShareSourceIdHash(source.id)}',
      );
      return source;
    }
  }

  Future<int?> _resolveGameCaptureProcessId(
    DesktopCapturerSource source,
    ShareSession? shareSession,
  ) async {
    try {
      final refreshedTarget = await resolveShareTargetForDesktopSource(source);
      final refreshedProcessId = refreshedTarget.processId;
      if (refreshedProcessId != null && refreshedProcessId > 0) {
        return refreshedProcessId;
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to resolve refreshed game-capture process id',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
    }

    final sessionProcessId = shareSession?.target.processId;
    return sessionProcessId != null && sessionProcessId > 0
        ? sessionProcessId
        : null;
  }

  String _normalizedDesktopSourceName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _diagnosticsProfileLabel(ScreenShareProfileConfig profile) {
    final lowLayerOnlyFallback =
        profile.shouldPublishLowLayerOnly && !profile.cpuRescueMode;
    final baseLabel = lowLayerOnlyFallback
        ? '${profile.label} (low-layer rescue)'
        : profile.label;
    return profile.hardwareEncodeFirst
        ? '$baseLabel (hardware-first)'
        : baseLabel;
  }

  String _diagnosticsProfileDetails(ScreenShareProfileConfig profile) {
    final lowLayer = profile.lowLayer == null
        ? 'none'
        : '${profile.lowLayer!.resolutionLabel}@'
            '${profile.lowLayer!.diagnosticFramerateLabel}/'
            '${_formatDiagnosticBitrate(profile.lowLayer!.maxBitrateBps)}'
            '${_diagnosticMinBitrateSuffix(profile.lowLayer!)}';
    final degradation = _degradationPreferenceForProfile(profile).name;
    return 'advanced=${profile.advancedOverride} '
        'requested=${profile.mainLayer.resolutionLabel}@'
        '${profile.mainLayer.diagnosticFramerateLabel}/'
        '${_formatDiagnosticBitrate(profile.mainLayer.maxBitrateBps)}'
        '${_diagnosticMinBitrateSuffix(profile.mainLayer)} '
        'codec=${profile.codec} '
        'hardwarePreference=${profile.hardwareEncodeFirst ? 'prefer' : 'off'} '
        'simulcast=${profile.useSimulcast} '
        'lowLayer=$lowLayer '
        'degradation=$degradation';
  }

  String _diagnosticMinBitrateSuffix(ScreenShareVideoLayer layer) {
    final minBitrate = layer.minBitrateBps;
    if (minBitrate == null || minBitrate <= 0) {
      return '';
    }
    return '_min${_formatDiagnosticBitrate(minBitrate)}';
  }

  void _ensureWebrtcNativeEncoderLogging() {
    if (_webrtcNativeEncoderLoggingConfigured ||
        !PlatformUtils.isWindows ||
        !preferences.showCallStreamStats.value) {
      return;
    }

    _webrtcNativeEncoderLoggingConfigured = true;
    try {
      Helper.setLogger(_webrtcNativeEncoderLogger, 'info');
      Log.i(
        'Enabled filtered WebRTC native stream logging for Windows stream diagnostics.',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to enable WebRTC native encoder logging',
      );
    }
  }

  List<VoipParticipantDiagnostics> _collectParticipantDiagnostics() {
    final identities = <String>{
      if (livekitRoom.localParticipant?.identity != null)
        livekitRoom.localParticipant!.identity,
      ...livekitRoom.remoteParticipants.keys,
      for (final stream in streams.whereType<MatrixLivekitVoipStream>())
        stream.participantIdentity,
    }.where((identity) => !identity.contains('_rnnoise_loopback')).toList()
      ..sort();

    return [
      for (final identity in identities)
        VoipParticipantDiagnostics(
          identity: identity,
          userId: _userIdFromParticipantIdentity(identity),
          clientLabel:
              _clientLabelForParticipantIdentity(identity) ?? 'Unknown client',
        ),
    ];
  }

  String? _clientLabelForParticipantIdentity(String identity) {
    final eventContent = _callMemberContentForParticipantIdentity(identity);
    if (eventContent == null) {
      if (identity == livekitRoom.localParticipant?.identity) {
        return BuildConfig.matrixClientDiagnosticsLabel;
      }
      return null;
    }

    final clientInfo =
        MatrixVoipRoomComponent.getClientInfoFromCallMemberContent(
      eventContent,
    );
    final diagnosticsLabel = clientInfo?['diagnostics_label'];
    if (diagnosticsLabel is String && diagnosticsLabel.trim().isNotEmpty) {
      return diagnosticsLabel;
    }

    final appName = clientInfo?['app_name'];
    final version = clientInfo?['version'];
    if (appName is String && version is String) {
      return '$appName $version';
    }

    return null;
  }

  Map<String, Object?>? _callMemberContentForParticipantIdentity(
    String identity,
  ) {
    final state =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (state == null) {
      return null;
    }

    final userId = _userIdFromParticipantIdentity(identity);
    final deviceId = _deviceIdFromParticipantIdentity(identity);
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entry in state.entries) {
      final event = entry.value;
      if (!MatrixVoipRoomComponent.isCallMembershipActive(event, nowMs: now)) {
        continue;
      }

      if (entry.key == identity ||
          (deviceId != null &&
              entry.key ==
                  MatrixVoipRoomComponent.callMemberStateKeyFor(
                    userId: userId,
                    deviceId: deviceId,
                  ))) {
        return event.content;
      }

      if (event.senderId != userId) {
        continue;
      }

      if (deviceId == null ||
          event.content['device_id'] == deviceId ||
          entry.key.startsWith('_${userId}_${deviceId}_')) {
        return event.content;
      }
    }

    return null;
  }

  String _userIdFromParticipantIdentity(String identity) {
    final firstColon = identity.indexOf(':');
    final lastColon = identity.lastIndexOf(':');
    if (lastColon <= 0 || firstColon == lastColon) {
      return identity;
    }

    return identity.substring(0, lastColon);
  }

  String? _deviceIdFromParticipantIdentity(String identity) {
    final firstColon = identity.indexOf(':');
    final lastColon = identity.lastIndexOf(':');
    if (lastColon <= 0 ||
        firstColon == lastColon ||
        lastColon == identity.length - 1) {
      return null;
    }

    return identity.substring(lastColon + 1);
  }

  Future<List<VoipTrackDiagnostics>> _collectDiagnosticsTracks({
    bool forceStatsDebug = false,
    bool collectRawStats = true,
    bool refreshIceDiagnostics = true,
    int? streamTestSampleOrdinal,
  }) async {
    final result = <VoipTrackDiagnostics>[];
    final statsDebugEnabled = forceStatsDebug ||
        preferences.showCallStreamStats.value ||
        Log.webrtcStatsEnabled;

    final streamSnapshot = streams.whereType<MatrixLivekitVoipStream>().toList(
          growable: false,
        );
    if (streamTestSampleOrdinal != null) {
      Log.i(
        'Stream-test diagnostics sample $streamTestSampleOrdinal '
        'streamSnapshot=${streamSnapshot.length} rawStats=$collectRawStats '
        'iceStats=$refreshIceDiagnostics',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      await Future<void>.delayed(Duration.zero);
    }
    for (final stream in streamSnapshot) {
      final track = stream.publication.track;
      if (track is lk.LocalVideoTrack) {
        try {
          if (streamTestSampleOrdinal != null) {
            Log.i(
              'Stream-test diagnostics sample $streamTestSampleOrdinal '
              'collecting sender stats stream=${stream.streamId}',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
            await Future<void>.delayed(Duration.zero);
          }
          final stats = await _withDiagnosticsStatsTimeout(
            track.getSenderStats(),
            label: 'LiveKit sender stats',
          );
          if (stats == null) {
            continue;
          }
          if (streamTestSampleOrdinal != null) {
            Log.i(
              'Stream-test diagnostics sample $streamTestSampleOrdinal '
              'collected sender stats reports=${stats.length} '
              'stream=${stream.streamId}',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
          }
          final trackSettings = _trackSettingsDiagnostics(track);
          _SenderRawDiagnosticsBundle rawDiagnostics =
              const _SenderRawDiagnosticsBundle();
          if (statsDebugEnabled && collectRawStats) {
            if (streamTestSampleOrdinal != null) {
              Log.i(
                'Stream-test diagnostics sample $streamTestSampleOrdinal '
                'collecting raw sender stats stream=${stream.streamId}',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
              await Future<void>.delayed(Duration.zero);
            }
            rawDiagnostics = await _collectSenderRawDiagnostics(track, stream);
            if (streamTestSampleOrdinal != null) {
              Log.i(
                'Stream-test diagnostics sample $streamTestSampleOrdinal '
                'collected raw sender stats stream=${stream.streamId}',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
            }
          }
          if (statsDebugEnabled &&
              refreshIceDiagnostics &&
              stream.type == VoipStreamType.screenshare &&
              stream.direction == VoipStreamDirection.outgoing) {
            if (streamTestSampleOrdinal != null) {
              Log.i(
                'Stream-test diagnostics sample $streamTestSampleOrdinal '
                'collecting ICE stats stream=${stream.streamId}',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
              await Future<void>.delayed(Duration.zero);
            }
            await _refreshIceTransportDiagnostics(track);
            if (streamTestSampleOrdinal != null) {
              Log.i(
                'Stream-test diagnostics sample $streamTestSampleOrdinal '
                'collected ICE stats stream=${stream.streamId}',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
            }
          }

          int? observedWidth;
          int? observedHeight;
          for (final stat in stats) {
            final key = _statsKey(stream, stat.streamId, stat.rid, 'sender');
            final previous = _senderStatsSamples[key];
            final bitrate = VoipDiagnosticsMath.bitrateBps(
              previousBytes: previous?.bytes,
              currentBytes: stat.bytesSent,
              previousTimestamp: previous?.timestamp,
              currentTimestamp: stat.timestamp,
            );
            _senderStatsSamples[key] = _StatsSample(
              bytes: stat.bytesSent,
              timestamp: stat.timestamp,
            );
            _maybeLogStatsSample(
              enabled: statsDebugEnabled,
              direction: 'sender',
              stream: stream,
              statsKey: key,
              previousSample: previous,
              currentBytes: stat.bytesSent,
              currentTimestamp: stat.timestamp,
              bitrateBps: bitrate,
            );

            final width = stat.frameWidth?.round();
            final height = stat.frameHeight?.round();
            if (width != null && width > 0) {
              observedWidth = max(observedWidth ?? 0, width);
            }
            if (height != null && height > 0) {
              observedHeight = max(observedHeight ?? 0, height);
            }
            final raw = rawDiagnostics.byOutboundId[stat.streamId];
            final source = rawDiagnostics.source;
            final targetLayer = _targetLayerForSenderStat(stream, stat.rid);
            final requestedBitrateBps =
                targetLayer?.maxBitrateBps ?? _targetBitrateForStream(stream);

            result.add(
              VoipTrackDiagnostics(
                streamId: stream.streamId,
                label: stream.label,
                type: stream.type,
                direction: VoipDiagnosticsTrackDirection.sender,
                requestedWidth: targetLayer?.width,
                requestedHeight: targetLayer?.height,
                requestedFps: targetLayer?.targetFramerateForScoring.toDouble(),
                requestedBitrateBps: requestedBitrateBps,
                preEncodeWidth: source?.width ?? trackSettings.width,
                preEncodeHeight: source?.height ?? trackSettings.height,
                width: width,
                height: height,
                fps: stat.framesPerSecond?.toDouble(),
                captureFps: source?.captureFps ?? trackSettings.frameRate,
                encodeFps: raw?.encodeFps,
                sendFps: stat.framesPerSecond?.toDouble(),
                bitrateBps: bitrate,
                targetBitrateBps: requestedBitrateBps,
                availableOutgoingBitrateBps: _latestAvailableOutgoingBitrateBps,
                availableIncomingBitrateBps: _latestAvailableIncomingBitrateBps,
                retransmitBitrateBps: raw?.retransmitBitrateBps,
                packetsLost: stat.packetsLost?.round(),
                packetsSent: stat.packetsSent?.round(),
                nackCount: stat.nackCount?.round(),
                pliCount: stat.pliCount?.round(),
                firCount: stat.firCount?.round(),
                packetLossPercent: VoipDiagnosticsMath.packetLossPercent(
                  packetsLost: stat.packetsLost,
                  packetsReceived: stat.packetsSent,
                ),
                jitterMs: VoipDiagnosticsMath.jitterMs(stat.jitter),
                roundTripTimeMs: VoipDiagnosticsMath.secondsToMs(
                  stat.roundTripTime,
                ),
                codec: _codecLabel(stat.mimeType),
                qualityLimitationReason: stat.qualityLimitationReason,
                framesSent: stat.framesSent?.round(),
                framesCaptured: source?.framesCaptured,
                framesEncoded: raw?.framesEncoded,
                framesDroppedBeforeEncode: source?.framesDroppedBeforeEncode,
                framesDroppedByEncoder: raw?.framesDroppedByEncoder,
                averageEncodeTimeMs: raw?.averageEncodeTimeMs,
                averagePacketSendDelayMs: raw?.averagePacketSendDelayMs,
                retransmittedPacketsSent:
                    stat.retransmittedPacketsSent?.round(),
                retransmittedBytesSent: raw?.retransmittedBytesSent,
                qualityLimitationResolutionChanges:
                    stat.qualityLimitationResolutionChanges?.round(),
                qualityLimitationDurations: raw?.qualityLimitationDurations,
                rid: stat.rid,
                activeLayer: stat.rid ?? 'single',
                encoderImplementation: stat.encoderImplementation,
                hardwareEncodeActive:
                    VoipDiagnosticsMath.isLikelyHardwareEncoder(
                  stat.encoderImplementation,
                ),
              ),
            );
          }
          final activeProfile = _activeScreenShareProfile;
          if (activeProfile != null &&
              stream.type == VoipStreamType.screenshare &&
              stream.direction == VoipStreamDirection.outgoing &&
              (observedWidth != null || observedHeight != null)) {
            if (_streamTestScreenShareActive) {
              if (!_streamTestObservedLimitRefreshDeferred) {
                _streamTestObservedLimitRefreshDeferred = true;
                Log.w(
                  'Deferred observed-dimension sender-limit refresh while '
                  'stream-test screen share is active; keeping the '
                  'post-publish profile limits already applied.',
                  category: LogCategory.webrtc,
                  source: 'stream-test-runner',
                );
              }
            } else {
              await _applyScreenShareSenderLimits(
                activeProfile,
                observedWidth: observedWidth,
                observedHeight: observedHeight,
              );
            }
          }
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: "Failed to collect LiveKit sender diagnostics",
          );
        }
      } else if (track is lk.RemoteVideoTrack) {
        try {
          if (streamTestSampleOrdinal != null) {
            Log.i(
              'Stream-test diagnostics sample $streamTestSampleOrdinal '
              'collecting receiver stats stream=${stream.streamId}',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
            await Future<void>.delayed(Duration.zero);
          }
          final stat = await _withDiagnosticsStatsTimeout(
            track.getReceiverStats(),
            label: 'LiveKit receiver stats',
          );
          if (stat == null) {
            continue;
          }
          if (streamTestSampleOrdinal != null) {
            Log.i(
              'Stream-test diagnostics sample $streamTestSampleOrdinal '
              'collected receiver stats stream=${stream.streamId}',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
          }

          final key = _statsKey(stream, stat.streamId, null, 'receiver');
          final previous = _receiverStatsSamples[key];
          final bitrate = VoipDiagnosticsMath.bitrateBps(
            previousBytes: previous?.bytes,
            currentBytes: stat.bytesReceived,
            previousTimestamp: previous?.timestamp,
            currentTimestamp: stat.timestamp,
          );
          _receiverStatsSamples[key] = _StatsSample(
            bytes: stat.bytesReceived,
            timestamp: stat.timestamp,
          );
          _maybeLogStatsSample(
            enabled: statsDebugEnabled,
            direction: 'receiver',
            stream: stream,
            statsKey: key,
            previousSample: previous,
            currentBytes: stat.bytesReceived,
            currentTimestamp: stat.timestamp,
            bitrateBps: bitrate,
          );

          final rawDiagnostics = statsDebugEnabled && collectRawStats
              ? await _collectReceiverRawDiagnostics(track, key)
              : null;

          result.add(
            VoipTrackDiagnostics(
              streamId: stream.streamId,
              label: stream.label,
              type: stream.type,
              direction: VoipDiagnosticsTrackDirection.receiver,
              receivePriority: stream.receivePriority,
              width: stat.frameWidth?.round(),
              height: stat.frameHeight?.round(),
              fps: stat.framesPerSecond?.toDouble(),
              decodeFps: stat.framesPerSecond?.toDouble(),
              renderFps: rawDiagnostics?.renderFps,
              bitrateBps: bitrate,
              packetsLost: stat.packetsLost?.round(),
              packetsReceived: stat.packetsReceived?.round(),
              nackCount: stat.nackCount?.round(),
              pliCount: stat.pliCount?.round(),
              firCount: stat.firCount?.round(),
              packetLossPercent: VoipDiagnosticsMath.packetLossPercent(
                packetsLost: stat.packetsLost,
                packetsReceived: stat.packetsReceived,
              ),
              jitterMs: VoipDiagnosticsMath.jitterMs(stat.jitter),
              jitterBufferDelayMs: rawDiagnostics?.jitterBufferDelayMs,
              codec: _codecLabel(stat.mimeType),
              framesDecoded: stat.framesDecoded?.round(),
              framesReceived: stat.framesReceived?.round(),
              framesRendered: rawDiagnostics?.framesRendered,
              framesDropped: stat.framesDropped?.round(),
              averageDecodeTimeMs: rawDiagnostics?.averageDecodeTimeMs,
              activeLayer:
                  stream.receiveQualityLabel ?? stream.receivePriority.name,
              decoderImplementation: stat.decoderImplementation,
              freezeCount: rawDiagnostics?.freezeCount,
              pauseCount: rawDiagnostics?.pauseCount,
              totalFreezesDurationMs: rawDiagnostics?.totalFreezesDurationMs,
              totalPausesDurationMs: rawDiagnostics?.totalPausesDurationMs,
            ),
          );
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: "Failed to collect LiveKit receiver diagnostics",
          );
        }
      }
    }

    return result;
  }

  Future<T?> _withDiagnosticsStatsTimeout<T>(
    Future<T> future, {
    required String label,
  }) async {
    try {
      return await future.timeout(_diagnosticsStatsTimeout);
    } on TimeoutException {
      final now = DateTime.now();
      if (now.difference(_lastDiagnosticsStatsTimeoutLog) >=
          const Duration(seconds: 10)) {
        _lastDiagnosticsStatsTimeoutLog = now;
        Log.w(
          'LiveKit diagnostics stats timeout: $label exceeded '
          '${_diagnosticsStatsTimeout.inMilliseconds}ms; continuing with '
          'partial diagnostics.',
          category: LogCategory.webrtc,
          source: 'stream-stats',
        );
      }
      return null;
    }
  }

  void _maybeLogStatsSample({
    required bool enabled,
    required String direction,
    required MatrixLivekitVoipStream stream,
    required String statsKey,
    required _StatsSample? previousSample,
    required num? currentBytes,
    required num? currentTimestamp,
    required int? bitrateBps,
  }) {
    if (!enabled) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastStatsSanityLog) < const Duration(seconds: 10)) {
      return;
    }

    _lastStatsSanityLog = now;
    Log.i(
      'LiveKit stats sanity $direction ${stream.type.name} '
      'key=$statsKey '
      'bytes:${previousSample?.bytes ?? '?'}->$currentBytes '
      'ts:${previousSample?.timestamp ?? '?'}->$currentTimestamp '
      'rate:${_formatDiagnosticBitrate(bitrateBps)}',
      category: LogCategory.webrtc,
      source: 'stream-stats',
    );
  }

  void _maybeLogDiagnosticsSnapshot(VoipCallDiagnosticsSnapshot snapshot) {
    if (!preferences.showCallStreamStats.value && !Log.webrtcStatsEnabled) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastDiagnosticsSummaryLog) <
        const Duration(seconds: 10)) {
      return;
    }

    _lastDiagnosticsSummaryLog = now;
    final lines = <String>[
      'LiveKit stream diagnostics profile=${snapshot.screenShareProfileLabel} '
          'profile_details=${snapshot.screenShareProfileDetails ?? 'unknown'} '
          'adaptive=${snapshot.adaptiveStreamEnabled} '
          'dynacast=${snapshot.dynacastEnabled} '
          'simulcast=${snapshot.screenShareSimulcastEnabled} '
          'fallback=${snapshot.adaptiveFallbackReason ?? 'none'} '
          'ice=${snapshot.iceTransportSummary ?? 'unknown'}',
      if (snapshot.shareSessionDiagnostics != null)
        'share_source ${snapshot.shareSessionDiagnostics!.toLogLine()}',
      for (final track in snapshot.tracks) _diagnosticTrackLogLine(track),
    ];
    Log.i(
      lines.join('\n'),
      category: LogCategory.livekit,
      source: 'stream-diagnostics',
    );
  }

  String _diagnosticTrackLogLine(VoipTrackDiagnostics track) {
    final direction = track.direction == VoipDiagnosticsTrackDirection.sender
        ? 'send'
        : 'recv';
    final type = track.type.name;
    final requested =
        track.requestedWidth == null || track.requestedHeight == null
            ? ''
            : ' req=${track.requestedWidth}x${track.requestedHeight}'
                '/${_formatDiagnosticFps(track.requestedFps)}'
                '/${_formatDiagnosticBitrate(track.requestedBitrateBps)}';
    final actual = ' actual=${track.resolutionLabel}'
        '/${_formatDiagnosticFps(track.fps)}'
        '/${_formatDiagnosticBitrate(track.bitrateBps)}';
    final senderSize = track.direction == VoipDiagnosticsTrackDirection.sender
        ? [
            if (track.preEncodeResolutionLabel != 'unknown')
              'pre_encode=${track.preEncodeResolutionLabel}',
            if (track.resolutionLabel != 'unknown')
              'encoded_size=${track.resolutionLabel}',
          ].join(' ')
        : [
            if (track.resolutionLabel != 'unknown')
              'received_size=${track.resolutionLabel}',
          ].join(' ');
    final fps = [
      if (track.captureFps != null)
        'capture_fps=${track.captureFps!.toStringAsFixed(0)}',
      if (track.direction == VoipDiagnosticsTrackDirection.sender &&
          track.captureFps != null)
        'pre_encode_fps=${track.captureFps!.toStringAsFixed(0)}',
      if (track.encodeFps != null)
        'encode_fps=${track.encodeFps!.toStringAsFixed(0)}',
      if (track.sendFps != null)
        'send_fps=${track.sendFps!.toStringAsFixed(0)}',
      if (track.decodeFps != null)
        'decode_fps=${track.decodeFps!.toStringAsFixed(0)}',
      if (track.renderFps != null)
        'render_fps=${track.renderFps!.toStringAsFixed(0)}',
    ].join(' ');
    final packets = [
      if (track.packetsSent != null) 'pkts_sent=${track.packetsSent}',
      if (track.packetsReceived != null) 'pkts_recv=${track.packetsReceived}',
      if (track.packetsLost != null) 'pkts_lost=${track.packetsLost}',
      if (track.nackCount != null) 'nack=${track.nackCount}',
      if (track.pliCount != null) 'pli=${track.pliCount}',
      if (track.firCount != null) 'fir=${track.firCount}',
    ].join(' ');
    final frames = [
      if (track.framesCaptured != null) 'captured=${track.framesCaptured}',
      if (track.framesEncoded != null) 'encoded=${track.framesEncoded}',
      if (track.framesSent != null) 'sent=${track.framesSent}',
      if (track.framesReceived != null) 'received=${track.framesReceived}',
      if (track.framesDecoded != null) 'decoded=${track.framesDecoded}',
      if (track.framesRendered != null) 'rendered=${track.framesRendered}',
      if (track.framesDroppedBeforeEncode != null)
        'drop_pre_encode=${track.framesDroppedBeforeEncode}',
      if (track.framesDroppedByEncoder != null)
        'drop_encoder=${track.framesDroppedByEncoder}',
      if (track.framesDropped != null) 'drop_decode=${track.framesDropped}',
    ].join(' ');
    final timings = [
      if (track.averageEncodeTimeMs != null)
        'encode_ms=${track.averageEncodeTimeMs!.toStringAsFixed(1)}',
      if (track.averageDecodeTimeMs != null)
        'decode_ms=${track.averageDecodeTimeMs!.toStringAsFixed(1)}',
      if (track.jitterMs != null)
        'jitter_ms=${track.jitterMs!.toStringAsFixed(0)}',
      if (track.jitterBufferDelayMs != null)
        'jbuf_avg_ms=${track.jitterBufferDelayMs!.toStringAsFixed(0)}',
      if (track.roundTripTimeMs != null)
        'rtt_ms=${track.roundTripTimeMs!.toStringAsFixed(0)}',
      if (track.averagePacketSendDelayMs != null)
        'send_delay_ms=${track.averagePacketSendDelayMs!.toStringAsFixed(1)}',
    ].join(' ');
    final bitrate = [
      if (track.targetBitrateBps != null)
        'target=${_formatDiagnosticBitrate(track.targetBitrateBps)}',
      if (track.availableOutgoingBitrateBps != null)
        'avail_out=${_formatDiagnosticBitrate(track.availableOutgoingBitrateBps)}',
      if (track.availableIncomingBitrateBps != null)
        'avail_in=${_formatDiagnosticBitrate(track.availableIncomingBitrateBps)}',
      if (track.retransmitBitrateBps != null)
        'retrans=${_formatDiagnosticBitrate(track.retransmitBitrateBps)}',
    ].join(' ');
    final engine =
        track.encoderImplementation ?? track.decoderImplementation ?? '?';
    return '$direction $type layer=${track.activeLayer ?? track.rid ?? '?'}'
        '$requested$actual'
        '${senderSize.isEmpty ? '' : ' $senderSize'}'
        '${fps.isEmpty ? '' : ' $fps'}'
        '${bitrate.isEmpty ? '' : ' $bitrate'}'
        '${packets.isEmpty ? '' : ' $packets'}'
        '${frames.isEmpty ? '' : ' $frames'}'
        '${timings.isEmpty ? '' : ' $timings'}'
        ' codec=${track.codec ?? '?'} engine=$engine'
        ' hw=${track.hardwareEncodeActive == null ? '?' : track.hardwareEncodeActive}'
        ' webrtc_limit=${track.qualityLimitationReason ?? 'unknown'}'
        '${_resolutionMismatchLabel(track)}'
        '${track.qualityLimitationDurations == null ? '' : ' limit_durations=${track.qualityLimitationDurations}'}'
        '${track.freezeCount == null ? '' : ' freezes=${track.freezeCount}'}'
        '${track.pauseCount == null ? '' : ' pauses=${track.pauseCount}'}';
  }

  String _resolutionMismatchLabel(VoipTrackDiagnostics track) {
    if (track.direction != VoipDiagnosticsTrackDirection.sender ||
        track.requestedWidth == null ||
        track.requestedHeight == null ||
        track.width == null ||
        track.height == null ||
        track.requestedWidth! <= 0 ||
        track.requestedHeight! <= 0 ||
        track.width! <= 0 ||
        track.height! <= 0) {
      return '';
    }

    final encodedTooWide = track.width! > track.requestedWidth! + 32 &&
        track.width! > track.requestedWidth! * 1.1;
    final encodedTooTall = track.height! > track.requestedHeight! + 18 &&
        track.height! > track.requestedHeight! * 1.1;
    if (!encodedTooWide && !encodedTooTall) {
      return '';
    }

    return ' resolution_mismatch=req_${track.requestedWidth}x'
        '${track.requestedHeight}_encoded_${track.width}x${track.height}';
  }

  String _formatDiagnosticFps(double? fps) {
    if (fps == null || fps <= 0) {
      return '?fps';
    }
    return '${fps.toStringAsFixed(0)}fps';
  }

  String _formatDiagnosticBitrate(int? bitrateBps) {
    if (bitrateBps == null || bitrateBps <= 0) {
      return '?bps';
    }
    if (bitrateBps >= 1000000) {
      return '${(bitrateBps / 1000000).toStringAsFixed(1)}Mbps';
    }
    return '${(bitrateBps / 1000).toStringAsFixed(0)}kbps';
  }

  Future<_SenderRawDiagnosticsBundle> _collectSenderRawDiagnostics(
    lk.LocalVideoTrack track,
    MatrixLivekitVoipStream stream,
  ) async {
    final sender = track.sender;
    if (sender == null) {
      return const _SenderRawDiagnosticsBundle();
    }

    try {
      final reports = await _withDiagnosticsStatsTimeout(
        sender.getStats(),
        label: 'raw LiveKit sender stats',
      );
      if (reports == null) {
        return const _SenderRawDiagnosticsBundle();
      }
      _SenderSourceDiagnostics? sourceDiagnostics;
      final outboundDiagnostics = <String, _SenderRawDiagnostics>{};

      for (final report in reports) {
        final type = _statsReportType(report);
        final values = _statsReportValues(report);
        if (values == null) {
          continue;
        }

        final mediaType = _stringFromStatsValue(
          values['kind'] ?? values['mediaType'],
        );
        if (mediaType != null && mediaType.toLowerCase() != 'video') {
          continue;
        }

        if (type == 'media-source' || type == 'track') {
          final previousSource = sourceDiagnostics;
          sourceDiagnostics = _SenderSourceDiagnostics(
            width:
                _intFromStatsValue(values['width'] ?? values['frameWidth']) ??
                    previousSource?.width,
            height:
                _intFromStatsValue(values['height'] ?? values['frameHeight']) ??
                    previousSource?.height,
            captureFps:
                _numFromStatsValue(values['framesPerSecond'])?.toDouble() ??
                    previousSource?.captureFps,
            framesCaptured: _intFromStatsValue(
                  values['framesCaptured'] ?? values['frames'],
                ) ??
                previousSource?.framesCaptured,
            framesDroppedBeforeEncode: _intFromStatsValue(
                  values['framesDroppedBeforeEncode'] ??
                      values['framesDropped'],
                ) ??
                previousSource?.framesDroppedBeforeEncode,
          );
          continue;
        }

        if (type != 'outbound-rtp') {
          continue;
        }

        final id = _statsReportId(report);
        if (id == null) {
          continue;
        }

        final timestamp = _statsReportTimestamp(report);
        final rid = _stringFromStatsValue(values['rid']);
        final framesEncoded = _numFromStatsValue(values['framesEncoded']);
        final totalEncodeTime = _numFromStatsValue(values['totalEncodeTime']);
        final encodeKey = _statsKey(stream, id, rid, 'sender-encode');
        final previousEncode = _senderEncodeTimeSamples[encodeKey];
        if (totalEncodeTime != null || framesEncoded != null) {
          _senderEncodeTimeSamples[encodeKey] = _DurationCounterSample(
            totalSeconds: totalEncodeTime,
            count: framesEncoded,
          );
        }

        final totalPacketSendDelay = _numFromStatsValue(
          values['totalPacketSendDelay'],
        );
        final packetsSentForDelay = _numFromStatsValue(values['packetsSent']);
        final sendDelayKey = _statsKey(
          stream,
          id,
          rid,
          'sender-packet-send-delay',
        );
        final previousPacketSendDelay =
            _senderPacketSendDelaySamples[sendDelayKey];
        if (totalPacketSendDelay != null || packetsSentForDelay != null) {
          _senderPacketSendDelaySamples[sendDelayKey] = _DurationCounterSample(
            totalSeconds: totalPacketSendDelay,
            count: packetsSentForDelay,
          );
        }

        final retransmittedBytes = _numFromStatsValue(
          values['retransmittedBytesSent'],
        );
        final retransmitKey = _statsKey(stream, id, rid, 'sender-retransmit');
        final previousRetransmit = _senderRetransmitStatsSamples[retransmitKey];
        final retransmitBitrate = VoipDiagnosticsMath.bitrateBps(
          previousBytes: previousRetransmit?.bytes,
          currentBytes: retransmittedBytes,
          previousTimestamp: previousRetransmit?.timestamp,
          currentTimestamp: timestamp,
        );
        if (retransmittedBytes != null || timestamp != null) {
          _senderRetransmitStatsSamples[retransmitKey] = _StatsSample(
            bytes: retransmittedBytes,
            timestamp: timestamp,
          );
        }

        outboundDiagnostics[id] = _SenderRawDiagnostics(
          rid: rid,
          encodeFps: _numFromStatsValue(values['framesPerSecond'])?.toDouble(),
          framesEncoded: framesEncoded?.round(),
          framesDroppedByEncoder: _intFromStatsValue(
            values['framesDroppedByEncoder'],
          ),
          averageEncodeTimeMs: VoipDiagnosticsMath.averageDurationMs(
            previousTotalSeconds: previousEncode?.totalSeconds,
            currentTotalSeconds: totalEncodeTime,
            previousCount: previousEncode?.count,
            currentCount: framesEncoded,
          ),
          averagePacketSendDelayMs: VoipDiagnosticsMath.averageDurationMs(
            previousTotalSeconds: previousPacketSendDelay?.totalSeconds,
            currentTotalSeconds: totalPacketSendDelay,
            previousCount: previousPacketSendDelay?.count,
            currentCount: packetsSentForDelay,
          ),
          qualityLimitationDurations: _qualityLimitationDurationsLabel(
            values['qualityLimitationDurations'],
          ),
          retransmittedBytesSent: retransmittedBytes?.round(),
          retransmitBitrateBps: retransmitBitrate,
        );
      }

      return _SenderRawDiagnosticsBundle(
        source: sourceDiagnostics,
        byOutboundId: outboundDiagnostics,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to collect raw LiveKit sender diagnostics',
      );
      return const _SenderRawDiagnosticsBundle();
    }
  }

  Future<_ReceiverRawDiagnostics?> _collectReceiverRawDiagnostics(
    lk.RemoteVideoTrack track,
    String key,
  ) async {
    final receiver = track.receiver;
    if (receiver == null) {
      return null;
    }

    try {
      final reports = await _withDiagnosticsStatsTimeout(
        receiver.getStats(),
        label: 'raw LiveKit receiver stats',
      );
      if (reports == null) {
        return null;
      }
      double? jitterBufferDelayMs;
      double? averageDecodeTimeMs;
      int? framesRendered;
      double? renderFps;
      int? freezeCount;
      int? pauseCount;
      double? totalFreezesDurationMs;
      double? totalPausesDurationMs;

      for (final report in reports) {
        final type = _statsReportType(report);
        final values = _statsReportValues(report);
        final mediaType = _stringFromStatsValue(
          values?['kind'] ?? values?['mediaType'],
        );
        if (mediaType != null && mediaType.toLowerCase() != 'video') {
          continue;
        }

        if (type == 'track') {
          framesRendered ??= _intFromStatsValue(values?['framesRendered']);
          renderFps ??= _numFromStatsValue(
            values?['framesPerSecond'],
          )?.toDouble();
          continue;
        }

        if (type != 'inbound-rtp') {
          continue;
        }

        final delaySeconds = _numFromStatsValue(values?['jitterBufferDelay']);
        final emittedCount = _numFromStatsValue(
          values?['jitterBufferEmittedCount'],
        );
        if (delaySeconds != null && emittedCount != null) {
          final previous = _receiverJitterBufferSamples[key];
          _receiverJitterBufferSamples[key] = _JitterBufferSample(
            delaySeconds: delaySeconds,
            emittedCount: emittedCount,
          );
          jitterBufferDelayMs = VoipDiagnosticsMath.jitterBufferDelayAverageMs(
            previousDelaySeconds: previous?.delaySeconds,
            currentDelaySeconds: delaySeconds,
            previousEmittedCount: previous?.emittedCount,
            currentEmittedCount: emittedCount,
          );
        }

        final totalDecodeTime = _numFromStatsValue(values?['totalDecodeTime']);
        final framesDecoded = _numFromStatsValue(values?['framesDecoded']);
        final previousDecode = _receiverDecodeTimeSamples[key];
        if (totalDecodeTime != null || framesDecoded != null) {
          _receiverDecodeTimeSamples[key] = _DurationCounterSample(
            totalSeconds: totalDecodeTime,
            count: framesDecoded,
          );
        }
        averageDecodeTimeMs = VoipDiagnosticsMath.averageDurationMs(
          previousTotalSeconds: previousDecode?.totalSeconds,
          currentTotalSeconds: totalDecodeTime,
          previousCount: previousDecode?.count,
          currentCount: framesDecoded,
        );

        framesRendered ??= _intFromStatsValue(values?['framesRendered']);
        renderFps ??= _numFromStatsValue(
          values?['framesPerSecond'],
        )?.toDouble();
        freezeCount = _intFromStatsValue(values?['freezeCount']);
        pauseCount = _intFromStatsValue(values?['pauseCount']);
        totalFreezesDurationMs = VoipDiagnosticsMath.secondsToMs(
          _numFromStatsValue(values?['totalFreezesDuration']),
        );
        totalPausesDurationMs = VoipDiagnosticsMath.secondsToMs(
          _numFromStatsValue(values?['totalPausesDuration']),
        );
      }

      return _ReceiverRawDiagnostics(
        jitterBufferDelayMs: jitterBufferDelayMs,
        averageDecodeTimeMs: averageDecodeTimeMs,
        framesRendered: framesRendered,
        renderFps: renderFps,
        freezeCount: freezeCount,
        pauseCount: pauseCount,
        totalFreezesDurationMs: totalFreezesDurationMs,
        totalPausesDurationMs: totalPausesDurationMs,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to collect LiveKit receiver diagnostics',
      );
      return null;
    }
  }

  Future<void> _refreshIceTransportDiagnostics(lk.LocalVideoTrack track) async {
    final sender = track.sender;
    if (sender == null) {
      return;
    }

    try {
      final reports = await _withDiagnosticsStatsTimeout(
        sender.getStats(),
        label: 'LiveKit ICE stats',
      );
      if (reports == null) {
        return;
      }
      final diagnostics = _selectedIceCandidateDiagnostics(reports);
      if (diagnostics == null) {
        return;
      }

      final previousSummary = _latestIceTransportSummary;
      _latestIceTransportSummary = diagnostics.summary;
      _latestAvailableOutgoingBitrateBps =
          diagnostics.availableOutgoingBitrateBps;
      _latestAvailableIncomingBitrateBps =
          diagnostics.availableIncomingBitrateBps;
      final now = DateTime.now();
      if (diagnostics.summary != previousSummary ||
          now.difference(_lastIceDiagnosticsLog) >=
              const Duration(seconds: 30)) {
        _lastIceDiagnosticsLog = now;
        Log.i(
          'LiveKit ICE selected route: ${diagnostics.summary} '
          'availOut=${_formatDiagnosticBitrate(diagnostics.availableOutgoingBitrateBps)} '
          'availIn=${_formatDiagnosticBitrate(diagnostics.availableIncomingBitrateBps)}',
        );
      }
    } catch (error, stackTrace) {
      final now = DateTime.now();
      if (now.difference(_lastIceDiagnosticsLog) >=
          const Duration(seconds: 30)) {
        _lastIceDiagnosticsLog = now;
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to collect LiveKit ICE diagnostics',
        );
      }
    }
  }

  _IceTransportDiagnostics? _selectedIceCandidateDiagnostics(
    Iterable<Object?> reports,
  ) {
    final byId = <String, Object?>{};
    for (final report in reports) {
      final id = _statsReportId(report);
      if (id != null) {
        byId[id] = report;
      }
    }

    Object? selectedPair;
    for (final report in reports) {
      if (_statsReportType(report) != 'transport') {
        continue;
      }
      final values = _statsReportValues(report);
      final selectedPairId = _stringFromStatsValue(
        values?['selectedCandidatePairId'],
      );
      if (selectedPairId != null) {
        selectedPair = byId[selectedPairId];
        if (selectedPair != null) {
          break;
        }
      }
    }

    selectedPair ??= reports.cast<Object?>().firstWhere((report) {
      if (_statsReportType(report) != 'candidate-pair') {
        return false;
      }
      final values = _statsReportValues(report);
      return _boolFromStatsValue(values?['selected']) ||
          (_boolFromStatsValue(values?['nominated']) &&
              _stringFromStatsValue(values?['state'])?.toLowerCase() ==
                  'succeeded');
    }, orElse: () => null);
    if (selectedPair == null) {
      return null;
    }

    final values = _statsReportValues(selectedPair);
    final localId = _stringFromStatsValue(
      values?['localCandidateId'] ?? values?['localId'],
    );
    final remoteId = _stringFromStatsValue(
      values?['remoteCandidateId'] ?? values?['remoteId'],
    );
    final localValues = _statsReportValues(byId[localId]);
    final remoteValues = _statsReportValues(byId[remoteId]);
    if (localValues == null && remoteValues == null) {
      return null;
    }

    final summary = '${_candidateLabel(localValues, side: 'local')} -> '
        '${_candidateLabel(remoteValues, side: 'remote')}';
    return _IceTransportDiagnostics(
      summary: summary,
      availableOutgoingBitrateBps: _intFromStatsValue(
        values?['availableOutgoingBitrate'],
      ),
      availableIncomingBitrateBps: _intFromStatsValue(
        values?['availableIncomingBitrate'],
      ),
    );
  }

  String _candidateLabel(
    Map<dynamic, dynamic>? values, {
    required String side,
  }) {
    if (values == null) {
      return '$side unknown';
    }

    final candidateType =
        _stringFromStatsValue(values['candidateType']) ?? 'candidate';
    final protocol =
        _stringFromStatsValue(values['protocol'])?.toLowerCase() ?? '?';
    return '$side $candidateType/$protocol/${_addressClass(values['address'] ?? values['ip'])}';
  }

  String _addressClass(Object? value) {
    final address = _stringFromStatsValue(value)?.toLowerCase();
    if (address == null || address.isEmpty) {
      return 'unknown';
    }
    if (address.endsWith('.local')) {
      return 'mdns';
    }
    if (address == '::1' || address.startsWith('127.')) {
      return 'loopback';
    }
    if (address.startsWith('10.') ||
        address.startsWith('192.168.') ||
        address.startsWith('169.254.') ||
        address.startsWith('fc') ||
        address.startsWith('fd') ||
        address.startsWith('fe80:')) {
      return 'private';
    }

    final parts = address.split('.');
    if (parts.length == 4) {
      final second = int.tryParse(parts[1]);
      if (parts.first == '172' &&
          second != null &&
          second >= 16 &&
          second <= 31) {
        return 'private';
      }
      return 'public';
    }

    return 'unknown';
  }

  Map<dynamic, dynamic>? _statsReportValues(Object? report) {
    if (report == null) {
      return null;
    }
    try {
      final values = (report as dynamic).values;
      if (values is Map<dynamic, dynamic>) {
        return values;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _statsReportId(Object? report) {
    if (report == null) {
      return null;
    }
    try {
      final id = (report as dynamic).id;
      return _stringFromStatsValue(id);
    } catch (_) {
      return null;
    }
  }

  String? _statsReportType(Object? report) {
    if (report == null) {
      return null;
    }
    try {
      final type = (report as dynamic).type;
      return _stringFromStatsValue(type);
    } catch (_) {
      return null;
    }
  }

  num? _statsReportTimestamp(Object? report) {
    if (report == null) {
      return null;
    }
    try {
      final timestamp = (report as dynamic).timestamp;
      return _numFromStatsValue(timestamp);
    } catch (_) {
      return null;
    }
  }

  String? _stringFromStatsValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  String? _qualityLimitationDurationsLabel(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      final parts = <String>[];
      for (final entry in value.entries) {
        final seconds = _numFromStatsValue(entry.value);
        if (seconds == null || seconds <= 0) {
          continue;
        }
        parts.add('${entry.key}:${seconds.toStringAsFixed(1)}s');
      }
      return parts.isEmpty ? null : parts.join(',');
    }
    final label = _stringFromStatsValue(value);
    return label == null || label.isEmpty ? null : label;
  }

  bool _boolFromStatsValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  num? _numFromStatsValue(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  int? _intFromStatsValue(Object? value) {
    return _numFromStatsValue(value)?.round();
  }

  _VideoTrackSettingsDiagnostics _trackSettingsDiagnostics(
    lk.LocalVideoTrack track,
  ) {
    try {
      final settings = track.mediaStreamTrack.getSettings();
      return _VideoTrackSettingsDiagnostics(
        width: _intFromStatsValue(settings['width']),
        height: _intFromStatsValue(settings['height']),
        frameRate: _numFromStatsValue(
          settings['frameRate'] ?? settings['frame_rate'],
        )?.toDouble(),
      );
    } catch (_) {
      return const _VideoTrackSettingsDiagnostics();
    }
  }

  ({int? width, int? height}) _largestObservedScreenShareSize(
    String streamId, {
    required int? observedWidth,
    required int? observedHeight,
  }) {
    if (observedWidth == null ||
        observedHeight == null ||
        observedWidth <= 0 ||
        observedHeight <= 0) {
      final existing = _screenShareObservedSizes[streamId];
      return (width: existing?.width, height: existing?.height);
    }

    final existing = _screenShareObservedSizes[streamId];
    final largestWidth = existing == null || observedWidth > existing.width
        ? observedWidth
        : existing.width;
    final largestHeight = existing == null || observedHeight > existing.height
        ? observedHeight
        : existing.height;
    final largest = (width: largestWidth, height: largestHeight);
    _screenShareObservedSizes[streamId] = largest;
    return largest;
  }

  ({int? width, int? height}) _largestScreenShareSize(
    ({int? width, int? height}) left,
    ({int? width, int? height}) right,
  ) {
    final leftWidth = left.width;
    final leftHeight = left.height;
    final rightWidth = right.width;
    final rightHeight = right.height;
    final width = leftWidth == null
        ? rightWidth
        : rightWidth == null
            ? leftWidth
            : leftWidth > rightWidth
                ? leftWidth
                : rightWidth;
    final height = leftHeight == null
        ? rightHeight
        : rightHeight == null
            ? leftHeight
            : leftHeight > rightHeight
                ? leftHeight
                : rightHeight;
    return (width: width, height: height);
  }

  ScreenShareVideoLayer? _targetLayerForSenderStat(
    MatrixLivekitVoipStream stream,
    String? rid,
  ) {
    if (stream.type != VoipStreamType.screenshare ||
        stream.direction != VoipStreamDirection.outgoing) {
      return null;
    }

    final profile = _activeScreenShareProfile;
    if (profile == null) {
      return null;
    }

    if (profile.shouldPublishLowLayerOnly) {
      return profile.mainLayer;
    }
    if ((rid == 'q' || rid == 'l') && profile.lowLayer != null) {
      return profile.lowLayer;
    }
    return profile.mainLayer;
  }

  String _statsKey(
    MatrixLivekitVoipStream stream,
    String statsStreamId,
    String? rid,
    String direction,
  ) {
    return '${stream.streamId}:$statsStreamId:${rid ?? 'single'}:$direction';
  }

  int? _targetBitrateForStream(MatrixLivekitVoipStream stream) {
    if (stream.type != VoipStreamType.screenshare ||
        stream.direction != VoipStreamDirection.outgoing) {
      return null;
    }
    final profile = _activeScreenShareProfile;
    if (profile == null) {
      return null;
    }
    return profile.mainLayer.maxBitrateBps;
  }

  String? _codecLabel(String? mimeType) {
    if (mimeType == null) {
      return null;
    }
    final parts = mimeType.split('/');
    return parts.isEmpty ? mimeType : parts.last.toLowerCase();
  }

  bool _profileLimitsEqual(
    ScreenShareProfileConfig left,
    ScreenShareProfileConfig right,
  ) {
    return left.mainLayer.maxBitrateBps == right.mainLayer.maxBitrateBps &&
        left.mainLayer.minBitrateBps == right.mainLayer.minBitrateBps &&
        left.mainLayer.maxFramerate == right.mainLayer.maxFramerate &&
        left.mainLayer.targetFramerateForScoring ==
            right.mainLayer.targetFramerateForScoring &&
        left.mainLayer.width == right.mainLayer.width &&
        left.mainLayer.height == right.mainLayer.height &&
        left.codec == right.codec &&
        left.useSimulcast == right.useSimulcast &&
        left.hardwareEncodeFirst == right.hardwareEncodeFirst &&
        left.cpuRescueMode == right.cpuRescueMode;
  }

  Future<void> _applyScreenShareSenderLimits(
    ScreenShareProfileConfig profile, {
    int? observedWidth,
    int? observedHeight,
    Iterable<lk.LocalTrackPublication>? localPublications,
    Duration? timeout,
  }) async {
    final applyFuture = _applyScreenShareSenderLimitsNow(
      profile,
      observedWidth: observedWidth,
      observedHeight: observedHeight,
      localPublications: localPublications,
    );
    if (timeout == null || timeout <= Duration.zero) {
      await applyFuture;
      return;
    }
    await applyFuture.timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException(
          'screen-share sender limits timed out after ${timeout.inSeconds}s',
          timeout,
        );
      },
    );
  }

  Future<void> _applyScreenShareSenderLimitsNow(
    ScreenShareProfileConfig profile, {
    int? observedWidth,
    int? observedHeight,
    Iterable<lk.LocalTrackPublication>? localPublications,
  }) async {
    final candidates = <({String streamId, lk.TrackPublication publication})>[];
    final seenPublicationIds = <String>{};

    void addCandidate(String streamId, lk.TrackPublication publication) {
      if (!seenPublicationIds.add(publication.sid)) {
        return;
      }
      candidates.add((streamId: streamId, publication: publication));
    }

    for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
      if (stream.type != VoipStreamType.screenshare ||
          stream.direction != VoipStreamDirection.outgoing) {
        continue;
      }
      addCandidate(stream.streamId, stream.publication);
    }

    for (final publication
        in localPublications ?? const <lk.LocalTrackPublication>[]) {
      if (publication.isScreenShare) {
        addCandidate(publication.sid, publication);
      }
    }

    for (final candidate in candidates) {
      final streamId = candidate.streamId;
      final publication = candidate.publication;

      final track = publication.track;
      if (track is! lk.LocalVideoTrack) {
        continue;
      }

      final sender = track.sender;
      final parameters = sender?.parameters;
      final encodings = parameters?.encodings;
      if (sender == null || parameters == null || encodings == null) {
        continue;
      }

      final trackSettings = _trackSettingsDiagnostics(track);
      final settingsDimensions = (
        width: trackSettings.width,
        height: trackSettings.height,
      );
      final observedDimensions = _largestObservedScreenShareSize(
        streamId,
        observedWidth: observedWidth,
        observedHeight: observedHeight,
      );
      final effectiveDimensions = _largestScreenShareSize(
        settingsDimensions,
        observedDimensions,
      );
      final effectiveWidth = effectiveDimensions.width;
      final effectiveHeight = effectiveDimensions.height;
      final limitParts = <String>[];
      var disabledHighLayerForCpuRescue = false;
      final forceLowLayerOnly = profile.shouldPublishLowLayerOnly;
      final shouldRestoreAfterCpuRescue = !forceLowLayerOnly &&
          _cpuRescueLayerDisabledStreams.contains(streamId);
      final lowLayer = forceLowLayerOnly
          ? profile.mainLayer
          : (profile.lowLayer ?? profile.mainLayer);
      for (var index = 0; index < encodings.length; index++) {
        final encoding = encodings[index];
        final isLowLayer = _isLowScreenShareEncoding(
          encoding,
          index: index,
          encodingCount: encodings.length,
        );
        final layerLabel = _screenShareEncodingLabel(
          encoding,
          index: index,
          isLowLayer: isLowLayer,
          encodingCount: encodings.length,
        );
        final disableForCpuRescue =
            forceLowLayerOnly && encodings.length > 1 && !isLowLayer;
        final layer = forceLowLayerOnly
            ? lowLayer
            : (isLowLayer ? lowLayer : profile.mainLayer);
        final scale = ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: effectiveWidth,
          observedHeight: effectiveHeight,
          targetLayer: layer,
        );
        if (disableForCpuRescue) {
          disabledHighLayerForCpuRescue = true;
          encoding.active = false;
          encoding.maxBitrate = 1;
          encoding.minBitrate = 1;
          encoding.maxFramerate = 1;
          encoding.scaleResolutionDownBy = scale;
          limitParts.add(
            '$layerLabel:off/'
            '${scale.toStringAsFixed(2)}',
          );
          continue;
        }
        if (forceLowLayerOnly || shouldRestoreAfterCpuRescue) {
          encoding.active = true;
        }
        encoding.maxBitrate = layer.maxBitrateBps;
        encoding.minBitrate = layer.minBitrateBps;
        encoding.maxFramerate = layer.maxFramerate;
        encoding.scaleResolutionDownBy = scale;
        final minBitrateLabel = layer.minBitrateBps == null
            ? 'none'
            : layer.minBitrateBps.toString();
        limitParts.add(
          '$layerLabel:on/${layer.maxBitrateBps}/'
          'min=$minBitrateLabel/'
          '${layer.maxFramerate}/${scale.toStringAsFixed(2)}',
        );
      }

      final limitKey = '${profile.storageKey}:${profile.label}:'
          '${effectiveWidth ?? 0}x${effectiveHeight ?? 0}:'
          '${limitParts.join(',')}';
      if (_appliedScreenShareLimitKeys[streamId] == limitKey) {
        continue;
      }

      parameters.encodings = encodings;
      try {
        await sender.setParameters(parameters);
        _appliedScreenShareLimitKeys[streamId] = limitKey;
        if (disabledHighLayerForCpuRescue) {
          _cpuRescueLayerDisabledStreams.add(streamId);
        } else if (!forceLowLayerOnly) {
          _cpuRescueLayerDisabledStreams.remove(streamId);
        }
        Log.i(
          "Applied screen share sender limits: ${profile.label} "
          "${effectiveWidth ?? '?'}x${effectiveHeight ?? '?'} "
          "${limitParts.join(' ')}",
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to apply screen share sender limits",
        );
      }
    }
  }

  bool _isLowScreenShareEncoding(
    dynamic encoding, {
    required int index,
    required int encodingCount,
  }) {
    final rid = encoding.rid;
    if (rid is! String) {
      return encodingCount > 1 && index == 0;
    }
    if (rid == 'q' || rid == 'l') {
      return true;
    }
    if (rid == 'h' || rid == 'f') {
      return false;
    }
    // Some Windows/WebRTC H.264 sender parameters omit RID labels even though
    // stats still expose q/h simulcast layers. LiveKit inserts the lower
    // screen-share layer first, so infer it by index when labels are missing.
    return encodingCount > 1 && index == 0;
  }

  String _screenShareEncodingLabel(
    dynamic encoding, {
    required int index,
    required bool isLowLayer,
    required int encodingCount,
  }) {
    final rid = encoding.rid;
    if (rid is String && rid.isNotEmpty) {
      return rid;
    }
    if (encodingCount > 1) {
      return isLowLayer ? 'q*' : 'h*';
    }
    return 'main';
  }

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      return WebrtcAndroidScreencaptureSource.getCaptureSource(context);
    }
    if (PlatformUtils.isIOS) {
      return const IosReplaykitScreencaptureSource();
    }
    return WebrtcScreencaptureSource.showSelectSourcePrompt(context);
  }

  Future<void> clearRoomCallState() async {
    Log.i("Clearing call state");

    await room.matrixRoom.client.setRoomStateWithKey(
      room.matrixRoom.id,
      MatrixVoipRoomComponent.callMemberStateEvent,
      stateKey,
      {},
    );

    Log.i("Cleared call state");
  }

  Future<void> stopHeartbeat() async {
    membershipRefreshTimer?.cancel();
    membershipRefreshTimer = null;

    heartbeatTimer?.cancel();
    heartbeatTimer = null;

    if (heartbeatDelayId == null) {
      return;
    }

    await room.matrixRoom.client.request(
      RequestType.POST,
      "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(heartbeatDelayId!)}",
      contentType: "application/json",
      data: jsonEncode({"action": "cancel"}),
    );

    heartbeatDelayId = null;
    Log.i("Stopped heartbeat");
  }

  Future<void> startHeartbeat() async {
    startMembershipRefresh();

    final capabilities = await room.matrixRoom.client.getVersions();
    Log.d("${capabilities}");
    if (capabilities.unstableFeatures?["org.matrix.msc4140"] != true) {
      Log.e("Homeserver does not support delayed events");
      return;
    }

    final timerLength = Duration(seconds: 30);

    final result = await room.matrixRoom.client.request(
      RequestType.PUT,
      "/client/v3/rooms/${Uri.encodeComponent(room.matrixRoom.id)}/state/${Uri.encodeComponent(MatrixVoipRoomComponent.callMemberStateEvent)}/${Uri.encodeComponent(stateKey)}",
      contentType: "application/json",
      data: "{}",
      query: {
        "org.matrix.msc4140.delay": timerLength.inMilliseconds.toString(),
      },
    );

    final delayId = result["delay_id"] as String;
    heartbeatDelayId = delayId;

    heartbeatTimer = Timer.periodic(timerLength - Duration(seconds: 5), (
      timer,
    ) async {
      await room.matrixRoom.client.request(
        RequestType.POST,
        "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(delayId)}",
        contentType: "application/json",
        data: jsonEncode({"action": "restart"}),
      );
      Log.d("Restarted MatrixRTC delayed-event heartbeat");
    });
  }

  void startMembershipRefresh() {
    membershipRefreshTimer?.cancel();
    membershipRefreshTimer = Timer.periodic(
      MatrixVoipRoomComponent.callMembershipRefreshInterval,
      (_) => unawaited(refreshCallMembershipState()),
    );
  }

  Future<void> refreshCallMembershipState() async {
    if (_ending || state == VoipState.ended) {
      return;
    }

    try {
      await room.matrixRoom.client.setRoomStateWithKey(
        room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent,
        stateKey,
        MatrixVoipRoomComponent.buildCallMemberContent(
          deviceId: room.matrixRoom.client.deviceID!,
          roomId: room.identifier,
          foci: foci,
        ),
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to refresh MatrixRTC call membership state",
      );
    }
  }

  @override
  double get generalAudioLevel {
    double result = streams.fold(
      0.0,
      (value, stream) => max(value, stream.audiolevel),
    );
    return result;
  }

  @override
  Stream<void> get onUpdateVolumeVisualizers => _onVolumeChanged.stream;

  Future<void> disconnectCall() async {
    Log.i("Disconnecting livekit room");
    await livekitRoom.disconnect();
    Log.i("Disconnected livekit room");
  }
}
