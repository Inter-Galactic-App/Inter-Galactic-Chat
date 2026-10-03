import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/bug_report/pending_native_call_crash_guard.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/client/components/voip/call_session_event_gate.dart';
import 'package:intergalactic/client/components/voip/stream_lifecycle_cue.dart';
import 'package:intergalactic/client/components/voip/screen_share_adaptive_fallback.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/native_webrtc_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_inbound_audio_energy.dart';
import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/stream_live_tuning_harness.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';
import 'package:intergalactic/client/components/voip/android_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/microphone_capture_liveness.dart';
import 'package:intergalactic/client/components/voip/ios_broadcast_control.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_microphone_sender_gate.dart';
import 'package:intergalactic/client/matrix/components/voip_room/voip_phantom_stream_prune.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_room_teardown_barrier.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_receiver_probe.dart';
import 'package:intergalactic/client/matrix/components/voip_room/receiver_probe_credential_handoff.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/stream_viewer_presence.dart';
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

@visibleForTesting
Future<bool> recreateStalledMicrophonePublication({
  required lk.LocalParticipant participant,
  required String stalledPublicationSid,
  required Future<lk.LocalTrackPublication?> Function() publishFresh,
  required bool Function() mayPublish,
  Future<void> Function()? onRemovedWithoutReplacement,
}) async {
  if (!mayPublish()) return false;
  var removedStalled = false;
  var hasReplacement = false;
  try {
    await participant.removePublishedTrack(stalledPublicationSid);
    removedStalled = true;
    if (!mayPublish()) return false;

    final replacement = await publishFresh();
    if (replacement == null) return false;
    hasReplacement = true;
    if (mayPublish()) return true;

    try {
      await participant.removePublishedTrack(replacement.sid);
    } finally {
      hasReplacement = false;
      await replacement.track?.stop();
    }
    return false;
  } finally {
    if (removedStalled && !hasReplacement) {
      await onRemovedWithoutReplacement?.call();
    }
  }
}

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

/// The raw WebRTC audio metrics from a LiveKit inbound-rtp report.
///
/// These are measurement-only values. In particular, they remain separate
/// from the visualizer magnitude used for speaking indicators until AUDIO has
/// evaluated the cumulative energy/sample-duration source.
class LiveKitInboundAudioRtpStats {
  const LiveKitInboundAudioRtpStats({
    this.audioLevel,
    this.totalAudioEnergy,
    this.totalSamplesDuration,
  });

  final double? audioLevel;
  final double? totalAudioEnergy;
  final double? totalSamplesDuration;
}

@visibleForTesting
LiveKitInboundAudioRtpStats? debugLiveKitInboundAudioRtpStatsFromReports(
  Iterable<Object?> reports,
) {
  for (final report in reports) {
    String? type;
    Map<dynamic, dynamic>? values;
    try {
      type = (report as dynamic).type?.toString();
      final candidate = (report as dynamic).values;
      if (candidate is Map<dynamic, dynamic>) {
        values = candidate;
      }
    } catch (_) {
      continue;
    }

    if (type != 'inbound-rtp' || values == null) {
      continue;
    }
    final mediaType = (values['kind'] ?? values['mediaType'])
        ?.toString()
        .toLowerCase();
    if (mediaType != null && mediaType != 'audio') {
      continue;
    }

    return LiveKitInboundAudioRtpStats(
      audioLevel: _inboundAudioStatDouble(values['audioLevel']),
      totalAudioEnergy: _inboundAudioStatDouble(values['totalAudioEnergy']),
      totalSamplesDuration: _inboundAudioStatDouble(
        values['totalSamplesDuration'],
      ),
    );
  }
  return null;
}

double? _inboundAudioStatDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

@visibleForTesting
Future<void> debugCancelLiveKitSessionSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelLiveKitSessionSubscription(subscription);
}

Future<void> _cancelLiveKitSessionSubscription(
  StreamSubscription? subscription, {
  String content = 'Recovered LiveKit session subscription cancel failure',
  String source = 'livekit-session-subscription',
}) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: content,
      category: LogCategory.webrtc,
      source: source,
    );
  }
}

@visibleForTesting
Future<bool> debugRunMatrixLivekitVoipSessionCleanupForTesting({
  required String operation,
  required FutureOr<void> Function()? cleanup,
}) {
  return _runMatrixLivekitVoipSessionCleanup(
    operation: operation,
    cleanup: cleanup,
  );
}

Future<bool> _runMatrixLivekitVoipSessionCleanup({
  required String operation,
  required FutureOr<void> Function()? cleanup,
}) async {
  if (cleanup == null) {
    return true;
  }

  try {
    await cleanup();
    return true;
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered LiveKit session cleanup failure: $operation',
      category: LogCategory.webrtc,
      source: 'livekit-session-cleanup',
    );
    return false;
  }
}

@visibleForTesting
Future<void> debugReleaseReplacedScreenShareForTesting({
  required Future<void> Function() releasePublication,
  required Future<void> Function() stopSession,
}) {
  return _releaseReplacedScreenShare(
    releasePublication: releasePublication,
    stopSession: stopSession,
  );
}

/// Releases a replaced share's publication and its session as two independent
/// steps.
///
/// They used to share one `try`, which made the session stop conditional on the
/// publication teardown succeeding. `ShareSession.stop()` is what performs the
/// native shared-audio stop and disposal, and by this point
/// `_currentShareSession` already points at the incoming share - so one throw
/// from `disposeSharedAudioPublicationStream()` left the outgoing Windows
/// capture running with nothing holding a handle to it. Neither failure may
/// take down the incoming share, which is already published.
Future<void> _releaseReplacedScreenShare({
  required Future<void> Function() releasePublication,
  required Future<void> Function() stopSession,
}) async {
  try {
    await releasePublication();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Failed to release the replaced screen-share publication',
    );
  }
  try {
    await stopSession();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Failed to stop the replaced screen-share session',
    );
  }
}

@visibleForTesting
Future<bool> debugRunBoundedHangUpStepForTesting({
  required String stepName,
  required Future<void> step,
  required Duration timeout,
}) {
  return _runBoundedHangUpStep(
    stepName: stepName,
    step: step,
    timeout: timeout,
  );
}

/// Awaits a single hang-up teardown step but never lets it propagate a failure
/// or block past [timeout]. A wedged homeserver membership-clear or LiveKit
/// disconnect during hang-up must not keep the session from reaching
/// VoipState.ended, so timeouts and errors are logged and abandoned.
Future<bool> _runBoundedHangUpStep({
  required String stepName,
  required Future<void> step,
  required Duration timeout,
}) async {
  try {
    await step.timeout(timeout);
    return true;
  } on TimeoutException {
    Log.w(
      'Hang-up teardown step timed out; abandoning it so the call still '
      'ends: step=$stepName timeout_ms=${timeout.inMilliseconds}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    return false;
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content:
          'Hang-up teardown step failed; continuing hang-up: '
          'step=$stepName',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    return false;
  }
}

@visibleForTesting
Future<bool> debugRunMatrixLivekitVoipSessionPublicationOperationForTesting({
  required String operation,
  required FutureOr<void> Function()? publicationOperation,
}) {
  return _runMatrixLivekitVoipSessionPublicationOperation(
    operation: operation,
    publicationOperation: publicationOperation,
  );
}

Future<bool> _runMatrixLivekitVoipSessionPublicationOperation({
  required String operation,
  required FutureOr<void> Function()? publicationOperation,
}) async {
  if (publicationOperation == null) {
    return true;
  }

  try {
    await publicationOperation();
    return true;
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered LiveKit session publication failure: $operation',
      category: LogCategory.webrtc,
      source: 'livekit-session-publication-operation',
    );
    return false;
  }
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
  static const _diagnosticMarker = 'inter galactic';

  @override
  void output(native_logger.OutputEvent event) {
    for (final line in event.lines) {
      final trimmed = line.trim();
      final normalized = trimmed.toLowerCase();
      if (trimmed.isEmpty || !normalized.contains(_diagnosticMarker)) {
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

class MatrixLivekitInitialMicrophoneEnableState {
  bool _callActive = true;
  bool _desiredMicrophoneEnabled = true;
  bool _desiredMuteStopOnMute = true;
  int _generation = 0;
  final Completer<void> _initialEnableSettled = Completer<void>();
  String? _initialEnableOutcome;

  /// Completes once the join-time microphone enable has SETTLED - completed,
  /// completed late after the Windows timeout, rolled back as stale, failed,
  /// or skipped. The backend runs that enable before the session exists, and
  /// on Windows it can settle seconds later than the join; anything the
  /// session wants to do to the join-time publication has to wait for this
  /// rather than race it (BUG-320).
  Future<void> get initialEnableSettled => _initialEnableSettled.future;

  bool get initialEnableIsSettled => _initialEnableSettled.isCompleted;

  /// How the join-time enable settled, for the log line that follows it.
  String? get initialEnableOutcome => _initialEnableOutcome;

  /// Idempotent: the first outcome wins, later calls are ignored.
  void markInitialEnableSettled({required String outcome}) {
    if (_initialEnableSettled.isCompleted) {
      return;
    }
    _initialEnableOutcome = outcome;
    _initialEnableSettled.complete();
  }

  bool get isCallActive => _callActive;
  bool get desiredMicrophoneEnabled => _desiredMicrophoneEnabled;
  bool get desiredMuteStopOnMute => _desiredMuteStopOnMute;
  int get generation => _generation;

  bool get shouldKeepLateCompletionEnabled =>
      _callActive && _desiredMicrophoneEnabled;

  bool shouldKeepEnabledForGeneration(int generation) {
    return _callActive &&
        _desiredMicrophoneEnabled &&
        _generation == generation;
  }

  /// Once a profile refresh has disabled the old capture, only call intent
  /// may prevent its replacement. A newer profile is serialized behind this
  /// refresh and must not leave the microphone unpublished in the meantime.
  bool shouldReenableAfterCaptureRefreshRemoval(int generation) =>
      shouldKeepEnabledForGeneration(generation);

  /// The user wants the mic **off** but the publication still says it is live:
  /// the hot-mic leak direction.
  bool shouldReconcileMutedPublication({required bool publicationMuted}) {
    return _callActive && !_desiredMicrophoneEnabled && !publicationMuted;
  }

  /// The user wants the mic **on** but it is not actually sending: the
  /// silent-mic direction.
  ///
  /// This branch did not exist. Only the mute direction above was ever
  /// reconciled, so a publication that came back muted - or, worse, one whose
  /// RTP sender was left detached while `publicationMuted` read false - stayed
  /// that way until the user rejoined the call.
  ///
  /// [senderDetached] must come from real sender state
  /// (`LivekitMicrophoneSenderGate.isDetached`) rather than from the
  /// publication flag, because the silent-mic steady state is precisely the
  /// one where those two disagree.
  bool shouldReconcileUnmutedPublication({
    required bool publicationMuted,
    required bool senderDetached,
  }) {
    return _callActive &&
        _desiredMicrophoneEnabled &&
        (publicationMuted || senderDetached);
  }

  void markDesiredMicrophoneEnabled(bool enabled) {
    if (_desiredMicrophoneEnabled == enabled) {
      return;
    }
    _desiredMicrophoneEnabled = enabled;
    _generation++;
  }

  void markDesiredMicrophoneMuted({required bool stopOnMute}) {
    final changed =
        _desiredMicrophoneEnabled || _desiredMuteStopOnMute != stopOnMute;
    _desiredMicrophoneEnabled = false;
    _desiredMuteStopOnMute = stopOnMute;
    if (changed) {
      _generation++;
    }
  }

  void markCallInactive() {
    if (!_callActive) {
      return;
    }
    _callActive = false;
    _generation++;
  }
}

/// The outcomes of ensuring a remote media stream exists for a publication.
///
/// Separate from `bool` because the old `bool` answered two questions at once
/// and they disagree on [notifiedOnly]. See `_ensureRemoteMediaStream`.
enum _RemoteMediaEnsureOutcome {
  /// A stream object was created for this publication.
  streamAdded,

  /// A stream already existed and the delivered track was attached to it.
  sinkAttached,

  /// A stream already existed, the SDK has delivered no track, and all that
  /// happened was a change notification. NOT a repair.
  notifiedOnly,

  /// No stream existed and one was not created.
  notAdded,
}

class MatrixLivekitVoipSession implements VoipSession {
  static const _serverAudioLoopbackTokenTimeout = Duration(seconds: 10);
  static const _receiverProbeConnectTimeout = Duration(seconds: 10);
  static const _diagnosticsStatsTimeout = Duration(milliseconds: 1200);

  /// Bounds the receiver-stats sample the remote-media reconciler takes.
  ///
  /// The reconciler is a single serialized future chain, and this await sits
  /// inside a per-publication loop, so one hang disabled remote-media
  /// self-healing for the rest of the call. The diagnostics `getStats()` call
  /// in this same file has been bounded for exactly this reason since it was
  /// written; this one never was (C-L2).
  static const _reconcilerStatsTimeout = Duration(milliseconds: 1200);

  /// How often the reconciler logs that it ran even when it repaired nothing.
  ///
  /// Without this the reconciler is invisible unless it repairs, so a wedged
  /// queue and a healthy quiet call are indistinguishable in every log ever
  /// exported.
  static const _remoteMediaSweepLivenessInterval = Duration(seconds: 60);
  static const _streamTestPublishVideoTrackTimeout = Duration(seconds: 20);
  static const _streamTestPrePublishSourceWarmup = Duration(seconds: 1);
  static const _streamTestPostPublishSenderLimitsDelay = Duration(seconds: 2);
  static const _iosReplayKitPublishTimeout = Duration(seconds: 8);
  static const _iosReplayKitPublishPollInterval = Duration(milliseconds: 250);
  static const _runtimeMicrophoneEnableTimeout = Duration(seconds: 12);
  static const _staleRuntimeMicrophoneDisableTimeout = Duration(seconds: 4);
  static const _streamTestRawDiagnosticsSampleInterval = 5;
  static const _streamTestIceDiagnosticsInitialSamples = 1;
  static const _callHealthQualityRefreshDebounce = Duration(milliseconds: 250);

  MatrixRoom room;
  lk.Room livekitRoom;
  final String stateKey;
  final List<Uri> foci;
  Timer? heartbeatTimer;
  Timer? membershipRefreshTimer;
  String? heartbeatDelayId;
  AppLifecycleListener? _lifecycleListener;
  ShareSession? _currentShareSession;

  /// Published shared-audio tracks, keyed by share.
  ///
  /// Step 2 of the per-share audio plan. These were two single fields, and
  /// that was half of BUG-301: starting a second share overwrote the
  /// publication without ever removing the first from the room, so listeners
  /// went on hearing the first app that was ever shared with audio. Keying
  /// makes "one publication per share" the container's property rather than a
  /// rule the publish path has to remember.
  ///
  /// The pair is held together so the publication and the track it wraps
  /// cannot disagree about what is live - the same reason the backend holds a
  /// session object rather than loose fields.
  ///
  /// Exactly one key is in use ([_defaultSharedAudioKey]); the caller does not
  /// yet register a share per video publication, so this behaves as the two
  /// fields did.
  final Map<Object, _WindowsSharedAudioPublication>
  _windowsSharedAudioPublications = <Object, _WindowsSharedAudioPublication>{};

  /// The single key in use while one share carries audio at a time.
  static const Object _defaultSharedAudioKey = 'default';
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  StreamSubscription? _noiseSuppressionStatusSub;
  StreamSubscription? _microphoneInputDeviceSub;

  /// Device id the currently published microphone track was created with.
  ///
  /// The noise-suppression capture signature deliberately excludes the device
  /// id, so this is the only record of which microphone is actually live.
  String? _appliedMicrophoneCaptureDeviceId;
  Timer? _volumeTimer;
  Timer? _diagnosticsTimer;
  Timer? _remoteAudioFlowTimer;
  final VoipRemoteAudioFlowMonitor _remoteAudioFlowMonitor =
      VoipRemoteAudioFlowMonitor();
  final VoipRemoteMediaAttachMonitor _remoteMediaAttachMonitor =
      VoipRemoteMediaAttachMonitor();
  DateTime _lastRemoteMediaSweepLog = DateTime.fromMillisecondsSinceEpoch(0);
  int _remoteMediaSweepCount = 0;
  int _gameCaptureFrameWatchdogGeneration = 0;
  Timer? _streamLiveTuningTimer;
  Timer? _inboundAudioEnergyTimer;
  Timer? _microphoneCaptureLivenessTimer;
  final MicrophoneCaptureRecoveryGate _microphoneCaptureRecoveryGate =
      MicrophoneCaptureRecoveryGate();

  /// BUG-325. Watches the native capture hook's frame counter so a
  /// microphone that publishes and sends nothing is named in the log rather
  /// than inferred from a user saying nobody could hear them.
  // The sampler REFRESHES the native status before evaluating. Reading
  // `NoiseSuppressionService.instance.status` here instead was the whole
  // defect: that is a cached field with no event channel and no periodic
  // refresh, so in a call it only moves when the user touches an audio
  // control, and the probe measured cache refreshes rather than capture.
  late final MicrophoneCaptureLivenessSampler
  _microphoneCaptureLivenessSampler = MicrophoneCaptureLivenessSampler(
    refreshStatus: () async {
      // observeStatus, NOT refresh. refresh() re-initialises the backend on a
      // retryable unavailable state, and re-initialisation zeroes
      // frames_processed - so a probe polling refresh() every 5s could
      // manufacture the very recovery it then reported, and would drive an
      // unbounded re-init loop on exactly the unhealthy path this diagnostic
      // exists for.
      final status = await NoiseSuppressionService.instance.observeStatus();
      return (
        available: status.available,
        enabled: status.enabled,
        framesProcessed: status.framesProcessed,
      );
    },
  );

  MicrophoneCaptureLivenessProbe get _microphoneCaptureLivenessProbe =>
      _microphoneCaptureLivenessSampler.probe;
  static const _microphoneCaptureLivenessInterval = Duration(seconds: 5);
  bool _inboundAudioEnergyCollectionInFlight = false;
  bool _inboundAudioEnergyCollectionActive = false;
  int? _lastInboundAudioEnergyLogMs;
  Timer? _callHealthDiagnosticsRefreshTimer;
  Future<void>? _transientCallResourcesDisposeFuture;
  Future<void>? _liveKitRoomTeardownFuture;
  Future<void>? _nativeLiveKitRoomDisposeFuture;
  LiveKitRoomTeardownTicket? _liveKitRoomTeardownTicket;
  final CallSessionEventGate _liveKitRoomEventGate = CallSessionEventGate();
  Future<void> _noiseSuppressionCaptureRefresh = Future<void>.value();
  Future<void> _serverAudioLoopbackOperation = Future<void>.value();
  Future<void> _receiverProbeOperation = Future<void>.value();
  Future<void> _localPreviewProbeOperation = Future<void>.value();
  Future<void> _remoteAudioReconciliationOperation = Future<void>.value();
  final Set<String> _activeLocalScreenShareVideoPublicationSids = <String>{};
  final RemoteStreamLifecycleCueState _remoteStreamCueState =
      RemoteStreamLifecycleCueState();
  final LocalStreamLifecycleCueState _localStreamCueState =
      LocalStreamLifecycleCueState();
  final StreamViewerPresence _streamViewerPresence = StreamViewerPresence();
  final Map<Object, Set<String>> _watchedSharesBySurface = {};
  final Set<String> _watchIntentDestinations = {};
  Future<void> _watchIntentSend = Future<void>.value();
  Timer? _streamViewerTimer;
  Future<void> _cameraOperation = Future<void>.value();
  bool _transientCallResourcesDisposed = false;
  bool _ending = false;
  bool _sessionDisposed = false;
  Future<void>? _hangUpFuture;
  // The homeserver membership-clear and delayed-event cancel, plus the LiveKit
  // websocket disconnect, are network calls with no inherent bound. Hang-up
  // must reach VoipState.ended even if one of them wedges on a flaky network,
  // otherwise the session never releases and every later join is handed back
  // the dead session until the app restarts. The server-side delayed-event
  // heartbeat removes a ghost membership on its own, so abandoning a stuck
  // clear is safe.
  static const _hangUpTeardownTimeout = Duration(seconds: 5);
  static const _nativeLiveKitRoomDisposeTimeout = Duration(seconds: 2);

  /// Steps recorded in the hang-up completion vector: dispose_transient
  /// resources, stop_screen_share, clear_call_state and stop_heartbeat. The
  /// LiveKit room disposal runs alongside them and reports separately, through
  /// `join_quarantined`.
  static const _hangUpStepCount = 4;
  final MatrixLivekitInitialMicrophoneEnableState _initialMicrophoneEnableState;
  String _microphoneCaptureProfileSignature =
      NoiseSuppressionCaptureProfile.captureFrontendSignature(
        bypassVoiceProcessing: IosCallAudioSession.shouldBypassVoiceProcessing,
      );
  bool _desiredServerAudioLoopbackEnabled = false;
  bool _serverAudioLoopbackStarting = false;
  bool _serverAudioLoopbackStopping = false;
  String? _serverAudioLoopbackError;
  lk.Room? _serverAudioLoopbackRoom;
  lk.EventsListener<lk.RoomEvent>? _serverAudioLoopbackListener;
  int _serverAudioLoopbackGeneration = 0;
  bool _desiredReceiverProbeEnabled = false;
  bool _receiverProbeStarting = false;
  bool _receiverProbeStopping = false;
  String? _receiverProbeError;
  MatrixLivekitReceiverProbeController? _receiverProbe;
  StreamSubscription<MatrixLivekitReceiverProbeEvent>? _receiverProbeEventsSub;
  bool _desiredLocalPreviewProbeEnabled = false;
  bool _localPreviewProbeStarting = false;
  bool _localPreviewProbeStopping = false;
  String? _localPreviewProbeError;
  MatrixLivekitLocalPreviewProbeController? _localPreviewProbe;
  StreamSubscription<MatrixLivekitReceiverProbeEvent>?
  _localPreviewProbeEventsSub;
  final StreamController<MatrixLivekitReceiverProbeEvent>
  _onReceiverProbeEvent = StreamController.broadcast();
  int _receiverProbeGeneration = 0;
  int _localPreviewProbeGeneration = 0;
  ScreenCaptureSource? _activeScreenShareSource;
  WindowsScreenCaptureBackendMode? _activeWindowsCaptureBackendMode;
  WindowsScreenCaptureDirtyRegionMode? _activeWindowsCaptureDirtyRegionMode;
  WindowsWindowGdiCaptureMode? _activeWindowsWindowGdiCaptureMode;
  bool _activeNativeFramePacingEnabled = false;
  ScreenShareProfileConfig? _requestedScreenShareProfile;
  ScreenShareProfileConfig? _activeScreenShareProfile;
  DateTime _lastUpdatedDiagnostics = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while a diagnostics collection pass is awaiting `getStats()`.
  ///
  /// The two-second throttle alone does not bound concurrency: it is stamped
  /// when a pass *starts*, and a pass walks every remote receiver in sequence
  /// with each `getStats()` allowed up to 1200ms. A few stalled receivers push
  /// one pass past the throttle window, and the next tick then starts a second
  /// pass over the same participants. This guard keeps exactly one in flight.
  bool _diagnosticsCollectionInFlight = false;
  VoipCallDiagnosticsSnapshot _diagnosticsSnapshot =
      VoipCallDiagnosticsSnapshot.empty();
  CallConnectionLifecycle _roomLifecycle = CallConnectionLifecycle.connected;
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
    MatrixLivekitInitialMicrophoneEnableState? initialMicrophoneEnableState,
  }) : foci = List.unmodifiable(foci),
       _initialMicrophoneEnableState =
           initialMicrophoneEnableState ??
           MatrixLivekitInitialMicrophoneEnableState() {
    clientManager?.callManager.onClientSessionStarted(this);
    addInitialStreams();
    for (final participant in livekitRoom.remoteParticipants.values) {
      if (participant.getTrackPublicationBySource(
            lk.TrackSource.screenShareVideo,
          ) !=
          null) {
        _remoteStreamCueState.seedActive(participant.identity);
      }
    }

    _roomListener = livekitRoom.createListener();
    _roomListener!.on(onTrackPublished);
    _roomListener!.on(onTrackSubscribed);
    _roomListener!.on(onTrackUnsubscribed);
    _roomListener!.on(onTrackUnpublished);
    _roomListener!.on(onLocalTrackPublished);
    _roomListener!.on(onLocalTrackUnpublished);
    _roomListener!.on(onTrackStreamEvent);
    _roomListener!.on(onTrackMutedEvent);
    _roomListener!.on(onTrackUnmutedEvent);
    _roomListener!.on(onParticipantConnected);
    _roomListener!.on(onParticipantDisconnected);
    _roomListener!.on(onParticipantConnectionQualityUpdated);
    _roomListener!.on(onRoomReconnecting);
    _roomListener!.on(onRoomAttemptReconnect);
    _roomListener!.on(onRoomReconnected);
    _roomListener!.on(onRoomDisconnected);
    _roomListener!.on(onDataReceived);
    unawaited(_queueRemoteMediaReconciliation('initial_snapshot'));
    _noiseSuppressionStatusSub = NoiseSuppressionService
        .instance
        .onStatusChanged
        .listen((_) => _syncMicrophoneNoiseSuppressionCaptureProfile());
    _microphoneInputDeviceSub = preferences.voipDefaultAudioInput.onChanged
        .listen((_) => _handleMicrophoneInputDeviceChanged());
    unawaited(_seedAppliedMicrophoneCaptureDevice());
    unawaited(_reconcileInitialJoinMicrophoneSender());

    _volumeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_notifyVolumeChanged()) {
        timer.cancel();
      }
    });
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(updateStats());
    });
    // The only reconciliation that does not depend on an SDK event arriving.
    //
    // It covers two distinct failures. First, subscriptions that are healthy
    // at the control plane but never deliver media (the "new joiner cannot be
    // heard until everyone rejoins" failure), which the flow monitor repairs
    // with a resubscribe. Second — and this is why it now sweeps every
    // publication kind rather than microphone audio only — publications the
    // app was never told about, because `TrackPublishedEvent` is emitted only
    // while the room is `connected` and the join path discards the
    // publications it builds for participants already in the room. This sweep
    // is what makes a camera or screen share that appeared during a reconnect
    // render without a rejoin.
    _remoteAudioFlowTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_queueRemoteMediaReconciliation('periodic_sweep'));
    });
    if (StreamLiveTuningHarness.instance.isSupported) {
      _streamLiveTuningTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_updateStreamLiveTuningHarness());
      });
    }
    // Always armed, but the tick returns immediately unless a consumer has
    // asked for the measurement. The preference is a developer toggle that can
    // be flipped mid-call, so the check has to happen per tick rather than
    // deciding here whether to create the timer at all.
    _inboundAudioEnergyTimer = Timer.periodic(
      _inboundAudioEnergyInterval,
      (_) => unawaited(_refreshInboundAudioEnergy()),
    );
    // This probe reads the Windows native capture hook. Other platforms do not
    // expose the frame counter and must not trigger a capture refresh from it.
    if (MicrophoneCaptureLivenessPlatformGate.shouldMonitor(
      isWindows: PlatformUtils.isWindows,
    )) {
      _microphoneCaptureLivenessTimer = Timer.periodic(
        _microphoneCaptureLivenessInterval,
        (_) => unawaited(_checkMicrophoneCaptureLiveness()),
      );
    }

    startHeartbeat();
    _refreshCallHealthDiagnostics();

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
      if (stream.direction == VoipStreamDirection.outgoing &&
          _isScreenShareVideoPublication(stream.publication)) {
        _activeLocalScreenShareVideoPublicationSids.remove(
          stream.publication.sid,
        );
      }
      _appliedScreenShareLimitKeys.remove(stream.streamId);
      _screenShareObservedSizes.remove(stream.streamId);
      _cpuRescueLayerDisabledStreams.remove(stream.streamId);
      unawaited(stream.dispose());
    }
    if (removed.any(
      (stream) =>
          stream.direction == VoipStreamDirection.outgoing &&
          stream.type == VoipStreamType.screenshare,
    )) {
      _pruneStreamViewers();
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
    _runLiveKitRoomEvent(() {
      for (var track in streams) {
        final t = track as MatrixLivekitVoipStream;
        if (t.publication.sid == event.publication.sid) {
          t.onStreamUpdatedEvent();
        }
      }
    });
  }

  bool _notifyLivekitStreamChanged(
    lk.TrackPublication publication,
    void Function(MatrixLivekitVoipStream stream) notify,
  ) {
    var notified = false;
    for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
      if (stream.publication.sid == publication.sid) {
        notify(stream);
        notified = true;
      }
    }
    return notified;
  }

  MatrixLivekitVoipStream? _findLivekitStream(lk.TrackPublication publication) {
    for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
      if (stream.publication.sid == publication.sid) {
        return stream;
      }
    }
    return null;
  }

  bool _isRemoteMicrophoneAudioPublication(lk.TrackPublication publication) {
    return publication is lk.RemoteTrackPublication &&
        publication.kind == lk.TrackType.AUDIO &&
        publication.source != lk.TrackSource.screenShareAudio &&
        publication.name != 'screenShareAudio';
  }

  bool _isLocalMicrophoneAudioPublication(lk.TrackPublication publication) {
    return publication is lk.LocalTrackPublication &&
        publication.kind == lk.TrackType.AUDIO &&
        publication.source == lk.TrackSource.microphone;
  }

  bool _runLiveKitRoomEvent(void Function() handleEvent) {
    return _liveKitRoomEventGate.runIfActive(
      isEnding: _ending,
      isEnded: state == VoipState.ended,
      transientResourcesDisposed: _transientCallResourcesDisposed,
      handleEvent: handleEvent,
    );
  }

  bool get _canProcessLiveKitRoomEvent => _liveKitRoomEventGate.shouldProcess(
    isEnding: _ending,
    isEnded: state == VoipState.ended,
    transientResourcesDisposed: _transientCallResourcesDisposed,
  );

  bool _notifyLiveKitTransientSignal({
    required bool closed,
    required void Function() notify,
  }) {
    return _liveKitRoomEventGate.notifyIfActive(
      isEnding: _ending,
      isEnded: state == VoipState.ended,
      transientResourcesDisposed: _transientCallResourcesDisposed,
      closed: closed,
      notify: notify,
    );
  }

  bool _notifyVolumeChanged() {
    return _notifyLiveKitTransientSignal(
      closed: _onVolumeChanged.isClosed,
      notify: () => _onVolumeChanged.add(()),
    );
  }

  bool _notifyDiagnosticsChanged() {
    return _notifyLiveKitTransientSignal(
      closed: _onDiagnosticsChanged.isClosed,
      notify: () => _onDiagnosticsChanged.add(null),
    );
  }

  void _refreshCallHealthDiagnostics() {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    final collectedAt = DateTime.now();
    _diagnosticsSnapshot = _diagnosticsSnapshot.withCallHealth(
      _buildCallHealthSnapshot(collectedAt: collectedAt),
    );
    _notifyDiagnosticsChanged();
  }

  void _queueCallHealthDiagnosticsRefresh() {
    if (!_canProcessLiveKitRoomEvent ||
        _callHealthDiagnosticsRefreshTimer != null) {
      return;
    }
    _callHealthDiagnosticsRefreshTimer = Timer(
      _callHealthQualityRefreshDebounce,
      () {
        _callHealthDiagnosticsRefreshTimer = null;
        _refreshCallHealthDiagnostics();
      },
    );
  }

  bool _notifyReceiverProbeEvent(MatrixLivekitReceiverProbeEvent event) {
    return _notifyLiveKitTransientSignal(
      closed: _onReceiverProbeEvent.isClosed,
      notify: () => _onReceiverProbeEvent.add(event),
    );
  }

  bool _notifyLiveKitProbeStateChanged() {
    return _notifyLiveKitTransientSignal(
      closed: _stateChanged.isClosed,
      notify: () => _stateChanged.add(()),
    );
  }

  /// Classifies a remote publication for the reconciliation policy.
  ///
  /// Returns null for anything that is not a remote publication, so the
  /// reconciler never touches local media (that is the local-publication
  /// lane's territory).
  VoipRemoteMediaKind? _remoteMediaKind(lk.TrackPublication publication) {
    if (publication is! lk.RemoteTrackPublication) {
      return null;
    }
    if (publication.kind == lk.TrackType.AUDIO) {
      return publication.source == lk.TrackSource.screenShareAudio ||
              publication.name == 'screenShareAudio'
          ? VoipRemoteMediaKind.screenShareAudio
          : VoipRemoteMediaKind.microphoneAudio;
    }
    if (publication.kind == lk.TrackType.VIDEO) {
      return _isScreenShareVideoPublication(publication)
          ? VoipRemoteMediaKind.screenShareVideo
          : VoipRemoteMediaKind.cameraVideo;
    }
    return null;
  }

  Future<void> _queueRemoteMediaReconciliation(String trigger) {
    if (!_canProcessLiveKitRoomEvent) {
      return Future<void>.value();
    }

    final queued = _remoteAudioReconciliationOperation
        .catchError((Object _) {})
        .then((_) => _reconcileRemoteMedia(trigger));
    _remoteAudioReconciliationOperation = queued.catchError((Object _) {});
    return queued;
  }

  /// Runs one desired-vs-actual sweep over every remote publication.
  ///
  /// Exposed so tests can drive the same sweep the 10s timer runs without
  /// waiting for wall-clock time.
  @visibleForTesting
  /// Drives the local-microphone drift reconcile, which is otherwise reachable
  /// only from the join path and a device change.
  ///
  /// Added for the BUG-320 x BUG-322 interaction: the join-time reconcile
  /// repairs DETACHED senders, and a Push to Talk join deliberately leaves the
  /// sender detached, so the two had to be exercised together rather than
  /// reasoned about.
  @visibleForTesting
  Future<void> debugReconcileLocalMicrophoneDriftForTesting(
    lk.LocalTrackPublication publication, {
    String trigger = 'test',
  }) => _reconcileLocalMicrophoneMuteDrift(publication, trigger: trigger);

  Future<void> debugReconcileRemoteMediaForTesting({String trigger = 'test'}) =>
      _queueRemoteMediaReconciliation(trigger);

  /// Desired-vs-actual reconciliation for **all** remote publication kinds.
  ///
  /// Widened from microphone audio only (P0-3). Remote camera video,
  /// screen-share video and screen-share audio previously had no reconciler at
  /// any point in a session's life and were purely event-driven against an SDK
  /// that drops those events while the room is `connecting`/`reconnecting`,
  /// for anyone already in the room at join, and for any publication whose
  /// track is detached.
  Future<void> _reconcileRemoteMedia(String trigger) async {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }

    var notifySession = false;
    var repairCount = 0;
    var publicationCount = 0;
    final liveAudioPublicationSids = <String>{};
    final livePublicationSids = <String>{};
    // Identity -> the sids that identity is currently publishing, for the
    // phantom-stream prune below (BUG-321). Only participants present in this
    // snapshot appear here, so a participant missing mid-reconnect is never a
    // prune target.
    final liveSidsByConnectedIdentity = <String, Set<String>>{};
    final participantSnapshot = livekitRoom.remoteParticipants.values.toList(
      growable: false,
    );
    for (final participant in participantSnapshot) {
      // Presence is what this key means, so it is seeded from the snapshot
      // rather than from the publication loop below. Filling it only inside
      // that loop left a still-connected participant who unpublished
      // EVERYTHING with no key at all, and the prune reads a missing key as
      // "mid-reconnect, leave them alone" - so it skipped the most complete
      // form of the dropped-TrackUnpublishedEvent case it exists for. An empty
      // set says "connected and publishing nothing"; absent still says "not in
      // this snapshot".
      liveSidsByConnectedIdentity.putIfAbsent(
        participant.identity,
        () => <String>{},
      );
      final publications = participant.trackPublications.values.toList(
        growable: false,
      );
      for (final publication in publications) {
        // `publication` is already an lk.RemoteTrackPublication here:
        // RemoteParticipant declares trackPublications as
        // Map<String, RemoteTrackPublication>. _remoteMediaKind still takes the
        // base type because the event handlers call it with event.publication,
        // which is not narrowed.
        final kind = _remoteMediaKind(publication);
        if (kind == null) {
          continue;
        }
        publicationCount++;
        livePublicationSids.add(publication.sid);
        (liveSidsByConnectedIdentity[participant.identity] ??= <String>{}).add(
          publication.sid,
        );
        if (kind == VoipRemoteMediaKind.microphoneAudio) {
          liveAudioPublicationSids.add(publication.sid);
        }

        final stream = _findLivekitStream(publication);
        final mediaStalled = kind == VoipRemoteMediaKind.microphoneAudio
            ? await _sampleRemoteAudioFlow(publication)
            : false;
        if (!_canProcessLiveKitRoomEvent) {
          return;
        }

        final sinkAttached = publication.track != null;
        // The app disables and unsubscribes off-screen screen shares itself,
        // so a detached hidden tile is the desired state, not drift.
        final receiveDisabled =
            stream?.receivePriority == VoipStreamReceivePriority.disabled;
        final wanted =
            !publication.muted &&
            !receiveDisabled &&
            publication.subscriptionAllowed;
        final attachStalled = _remoteMediaAttachMonitor.recordObservation(
          sid: publication.sid,
          wanted: wanted,
          sinkAttached: sinkAttached,
          now: DateTime.now(),
        );

        final reconciliation = VoipRemoteAudioReconciliationPolicy.evaluate(
          VoipRemoteAudioState(
            kind: kind,
            participantConnected: livekitRoom.remoteParticipants.containsKey(
              participant.identity,
            ),
            audioPublicationExists: true,
            publicationMuted: publication.muted,
            // NOT `publication.subscribed`: that getter is defined as
            // `subscriptionAllowed && track != null`, so it is guaranteed
            // false at publish time and a `!subscribed -> subscribe` rule
            // fed from it restates a definition instead of detecting a
            // fault. `enabled` is the app's own receive switch and is the
            // only bit here that can actually diverge from intent.
            trackSubscribed: publication.enabled,
            subscriptionPermitted: publication.subscriptionAllowed,
            receiveDisabled: receiveDisabled,
            streamObjectExists: stream != null,
            audioSinkAttached: sinkAttached,
            mediaAttachStalled: attachStalled,
            localVolume: stream?.localVolume ?? 1.0,
            locallyMuted: stream?.locallyMuted ?? false,
            userMuted:
                stream != null &&
                stream.hasLocalPlaybackVolumeOverride &&
                stream.localVolume <= 0,
            mediaStalled: mediaStalled,
          ),
        );

        // Set by the rebuildStreamOrSink step below, read by the reconciler
        // after it runs. Declared here so it is false for every other action
        // rather than carrying a stale value between publications.
        var rebuildWasIneffective = false;

        final result = await VoipRemoteAudioReconciler.repair(
          reconciliation,
          isActive: () => _canProcessLiveKitRoomEvent,
          subscribe: () async {
            await publication.subscribe();
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            await publication.enable();
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            notifySession =
                _ensureRemoteMediaStreamNotifies(
                  _ensureRemoteMediaStream(participant, publication),
                ) ||
                notifySession;
          },
          resubscribe: () async {
            // Either the subscription looked healthy but never delivered
            // packets, or the media sink never attached at all for longer
            // than the attach window. Tear it down and set it up again, which
            // renegotiates the receiver the same way a full rejoin would.
            final now = DateTime.now();
            _remoteAudioFlowMonitor.recordRepair(publication.sid, now);
            _remoteMediaAttachMonitor.recordRepair(publication.sid, now);
            await publication.unsubscribe();
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            await publication.subscribe();
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            await publication.enable();
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            notifySession =
                _ensureRemoteMediaStreamNotifies(
                  _ensureRemoteMediaStream(participant, publication),
                ) ||
                notifySession;
          },
          rebuildStreamOrSink: () {
            final outcome = _ensureRemoteMediaStream(participant, publication);
            notifySession =
                _ensureRemoteMediaStreamNotifies(outcome) || notifySession;
            // The one step that can tell it did nothing. Reported rather than
            // thrown: there is no error here, the SDK simply has not delivered
            // a track, and calling that a failure would put it in front of the
            // user as one.
            rebuildWasIneffective =
                outcome == _RemoteMediaEnsureOutcome.notifiedOnly;
          },
          removeStream: () {
            _removeLivekitStreamsWhere(
              (candidate) => candidate.publication.sid == publication.sid,
            );
            notifySession = true;
          },
          restoreLocalPlayback: () async {
            final targetStream = stream ?? _findLivekitStream(publication);
            if (targetStream == null) {
              return;
            }
            if (targetStream.hasLocalPlaybackVolumeOverride) {
              await targetStream.setLocalVolume(targetStream.localVolume);
            } else {
              await targetStream.setDefaultLocalVolume(
                targetStream.localVolume,
              );
            }
            if (!_canProcessLiveKitRoomEvent) {
              return;
            }
            notifySession = true;
          },
          stepWasIneffective: () => rebuildWasIneffective,
          onError: (error, stackTrace, failedReconciliation) {
            Log.onError(
              error,
              stackTrace,
              content:
                  'remote_media_reconciliation event=repair_failed '
                  'trigger=$trigger '
                  'kind=${kind.name} '
                  'action=${failedReconciliation.action.name} '
                  'reason=${failedReconciliation.reason} '
                  'receive_enabled=${publication.enabled} '
                  'subscription_allowed=${publication.subscriptionAllowed} '
                  'has_track=${publication.track != null}',
              category: LogCategory.livekit,
              source: 'remote-media-reconciliation',
            );
          },
        );

        if (!_canProcessLiveKitRoomEvent) {
          return;
        }

        if (!result.attempted) {
          continue;
        }

        if (result.ineffective) {
          // Logged at the same level as an applied repair, deliberately. This
          // is the line whose ABSENCE made the field failure unreadable: the
          // reconciler named the fault, named the action, and the action could
          // not touch the fault. The attach-monitor gates come with it because
          // the follow-up question is always "so why has it not escalated to
          // resubscribe yet", and one capture should answer that rather than
          // leaving three hypotheses.
          final gates =
              _remoteMediaAttachMonitor.describeGateState(
                publication.sid,
                DateTime.now(),
              ) ??
              'no_observation';
          Log.w(
            'remote_media_reconciliation event=repair_ineffective '
            'trigger=$trigger '
            'kind=${kind.name} '
            'action=${result.action.name} '
            'reason=${result.reason} '
            'detail=stream_exists_without_sink '
            'has_track=${publication.track != null} '
            'receive_enabled=${publication.enabled} '
            'subscription_allowed=${publication.subscriptionAllowed} '
            '$gates',
            category: LogCategory.livekit,
            source: 'remote-media-reconciliation',
          );
        }

        if (result.repaired) {
          repairCount++;
          Log.i(
            'remote_media_reconciliation event=repair_applied '
            'trigger=$trigger '
            'kind=${kind.name} '
            'action=${result.action.name} '
            'reason=${result.reason} '
            'receive_enabled=${publication.enabled} '
            'subscription_allowed=${publication.subscriptionAllowed} '
            'has_track=${publication.track != null}',
            category: LogCategory.livekit,
            source: 'remote-media-reconciliation',
          );
          if (result.action != VoipRemoteAudioRepairAction.subscribe) {
            notifySession = true;
          }
        }
      }
    }

    // Prune phantom incoming streams: a still-connected participant whose old
    // publication sid vanished under a reconnect republish, whose
    // TrackUnpublishedEvent this observer never received (BUG-321). Only while
    // fully connected - a reconnecting snapshot can be incomplete, and the
    // tight identity-present condition plus this gate keep a transient from
    // dropping live tiles.
    if (_roomLifecycle == CallConnectionLifecycle.connected) {
      final phantomSids = phantomIncomingStreamSidsToPrune(
        liveSidsByConnectedIdentity: liveSidsByConnectedIdentity,
        streams: streams.whereType<MatrixLivekitVoipStream>().map(
          (stream) => PhantomStreamCandidate(
            sid: stream.publication.sid,
            participantIdentity: stream.participantIdentity,
            incoming: stream.direction == VoipStreamDirection.incoming,
          ),
        ),
      );
      if (phantomSids.isNotEmpty) {
        Log.i(
          'remote_media_reconciliation event=phantom_stream_pruned '
          'trigger=$trigger count=${phantomSids.length} '
          'sids=${phantomSids.join(',')}',
          category: LogCategory.livekit,
          source: 'remote-media-reconciliation',
        );
        _removeLivekitStreamsWhere(
          (stream) => phantomSids.contains(stream.publication.sid),
        );
        notifySession = true;
      }
    }

    _remoteAudioFlowMonitor.retainOnly(liveAudioPublicationSids);
    _remoteMediaAttachMonitor.retainOnly(livePublicationSids);
    _logRemoteMediaSweepLiveness(
      trigger: trigger,
      publicationCount: publicationCount,
      repairCount: repairCount,
    );

    if (notifySession && _canProcessLiveKitRoomEvent) {
      _notifyStateChanged();
    }
  }

  /// Emits a throttled "the sweep still runs" marker.
  ///
  /// The reconciler only ever logged when it repaired something, so a queue
  /// wedged behind an unbounded await (C-L2) looked exactly like a healthy
  /// quiet call in every exported log. A periodic marker makes the difference
  /// readable: the absence of these lines is now itself the symptom.
  void _logRemoteMediaSweepLiveness({
    required String trigger,
    required int publicationCount,
    required int repairCount,
  }) {
    _remoteMediaSweepCount++;
    final now = DateTime.now();
    if (now.difference(_lastRemoteMediaSweepLog) <
        _remoteMediaSweepLivenessInterval) {
      return;
    }
    _lastRemoteMediaSweepLog = now;
    Log.i(
      'remote_media_reconciliation event=sweep_alive '
      'trigger=$trigger '
      'sweeps=$_remoteMediaSweepCount '
      'remote_publications=$publicationCount '
      'repairs_this_sweep=$repairCount',
      category: LogCategory.livekit,
      source: 'remote-media-reconciliation',
    );
  }

  /// Samples the receiver packet counter for a subscribed, unmuted remote
  /// microphone publication and reports whether the flow monitor considers
  /// it media-stalled. Unavailable stats never count as a stall.
  Future<bool> _sampleRemoteAudioFlow(
    lk.RemoteTrackPublication publication,
  ) async {
    if (!publication.subscribed || publication.muted) {
      return false;
    }
    final track = publication.track;
    if (track is! lk.RemoteAudioTrack) {
      return false;
    }
    num? packetsReceived;
    try {
      // Bounded (C-L2). This await sits inside a per-publication loop behind
      // a single serialized future chain, so an unbounded hang here disabled
      // remote-media self-healing for the whole rest of the call. A timeout
      // yields null, which the flow monitor already treats as "no evidence"
      // rather than as a stall.
      packetsReceived = (await track.getReceiverStats().timeout(
        _reconcilerStatsTimeout,
      ))?.packetsReceived;
    } on TimeoutException {
      Log.w(
        'remote_media_reconciliation event=stats_timeout '
        'sid=${publication.sid} '
        'timeout_ms=${_reconcilerStatsTimeout.inMilliseconds}',
        category: LogCategory.livekit,
        source: 'remote-media-reconciliation',
      );
      packetsReceived = null;
    } catch (_) {
      packetsReceived = null;
    }
    if (!_canProcessLiveKitRoomEvent) {
      return false;
    }
    return _remoteAudioFlowMonitor.recordSample(
      sid: publication.sid,
      packetsReceived: packetsReceived,
      now: DateTime.now(),
    );
  }

  /// One line per session stream for the call diagnostics export (BUG-321).
  ///
  /// The export's `Streams: total=... share=...` count is what showed an
  /// observer holding nine share entries against one live receiver, but a
  /// count cannot say WHICH entries are stale or whose they are. Each line
  /// names the sid, the (redacted) owner, the kind and direction, and whether
  /// that sid is still among a participant's live publications: a phantom
  /// reads `publication_live=false` while its owner is still connected.
  List<String> diagnosticsStreamLines() {
    if (state == VoipState.ended) {
      return const <String>[];
    }
    final liveSids = <String>{};
    for (final participant in livekitRoom.remoteParticipants.values) {
      liveSids.addAll(participant.trackPublications.keys);
    }
    final local = livekitRoom.localParticipant;
    if (local != null) {
      liveSids.addAll(local.trackPublications.keys);
    }
    return <String>[
      for (final stream in streams.whereType<MatrixLivekitVoipStream>())
        describeSessionStreamForDiagnostics(
          sid: stream.publication.sid,
          redactedOwner: _redactedParticipantIdentity(
            stream.participantIdentity,
          ),
          type: stream.type.name,
          direction: stream.direction.name,
          publicationLive: liveSids.contains(stream.publication.sid),
          trackAttached: stream.publication.track != null,
          ownerConnected:
              stream.direction == VoipStreamDirection.outgoing ||
              livekitRoom.remoteParticipants.containsKey(
                stream.participantIdentity,
              ),
        ),
    ];
  }

  /// What [_ensureRemoteMediaStream] actually did.
  ///
  /// It used to return a bare `bool`, and the two callers read that one value
  /// as two different answers: the session read it as "notify listeners", and
  /// the reconciler read it as "the repair worked". Those questions have
  /// different answers on the [notifiedOnly] path, which is how a repair for a
  /// missing audio sink could report success while attaching nothing.
  ///
  /// Nothing on this side can attach a track the SDK has not delivered, so
  /// [notifiedOnly] is not a bug to fix here - it is a fact the caller has to
  /// be able to see.
  bool _ensureRemoteMediaStreamNotifies(_RemoteMediaEnsureOutcome outcome) {
    switch (outcome) {
      case _RemoteMediaEnsureOutcome.sinkAttached:
      case _RemoteMediaEnsureOutcome.notifiedOnly:
      case _RemoteMediaEnsureOutcome.streamAdded:
        return true;
      case _RemoteMediaEnsureOutcome.notAdded:
        return false;
    }
  }

  _RemoteMediaEnsureOutcome _ensureRemoteMediaStream(
    lk.RemoteParticipant participant,
    lk.RemoteTrackPublication publication,
  ) {
    // BUG-321 origin, established from a 68-minute capture: an unpublish that
    // lands while a repair for that publication is in flight is followed by
    // the repair re-adding the stream, and no further unpublish can arrive
    // for a publication the SDK has already dropped. Every caller of this
    // method is a repair callback, so the live-publication check belongs
    // here.
    if (!mayBuildStreamForPublication(
      participantPublicationSids: participant.trackPublications.keys.toSet(),
      publicationSid: publication.sid,
    )) {
      Log.i(
        'remote_media_reconciliation event=stream_build_skipped '
        'reason=publication_gone sid=${publication.sid} '
        'participant=${_redactedParticipantIdentity(participant.identity)}',
        category: LogCategory.livekit,
        source: 'remote-media-reconciliation',
      );
      return _RemoteMediaEnsureOutcome.notAdded;
    }

    final existingStream = _findLivekitStream(publication);
    if (existingStream != null) {
      final track = publication.track;
      if (track != null) {
        existingStream.onTrackSubscribedEvent(track);
        return _RemoteMediaEnsureOutcome.sinkAttached;
      }
      // NOTHING IS REPAIRED HERE. onStreamUpdatedEvent re-applies local
      // playback volume and notifies listeners; it cannot attach a sink, and
      // `publication.track` being null is the definition of the condition that
      // selected this repair. Saying so is the whole point of the enum.
      existingStream.onStreamUpdatedEvent();
      return _RemoteMediaEnsureOutcome.notifiedOnly;
    }

    final userId = _userIdFromParticipantIdentity(participant.identity);
    final added = _addLivekitStream(
      publication,
      userId,
      participantIdentity: participant.identity,
    );
    return added
        ? _RemoteMediaEnsureOutcome.streamAdded
        : _RemoteMediaEnsureOutcome.notAdded;
  }

  ScreenShareProfileConfig _screenShareProfile() {
    final developerModeEnabled = preferences.developerMode.value;
    final gpuPipelineTestModeEnabled = _gpuPipelineTestModeEnabled;
    final advancedOverrideEnabled =
        !gpuPipelineTestModeEnabled &&
        developerModeEnabled &&
        preferences.streamAdvancedOverride.value;
    final preferHardwareEncoding =
        PlatformUtils.isWindows &&
        (gpuPipelineTestModeEnabled ||
            preferences.streamHardwareEncodingFirst.value);
    return ScreenShareProfileConfig.resolve(
      profileKey: gpuPipelineTestModeEnabled
          ? ScreenShareQualityProfile.smooth.storageKey
          : preferences.screenShareQualityProfile.value,
      advancedOverrideEnabled: advancedOverrideEnabled,
      allowSimulcast: gpuPipelineTestModeEnabled
          ? false
          : preferences.doSimulcast.value,
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
    final isWindowsWindowSource =
        PlatformUtils.isWindows &&
        videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Window;
    final isWindowsDisplaySource =
        PlatformUtils.isWindows &&
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
    ScreenShareProfileConfig profile, {
    bool preserveGameCaptureResolution = false,
  }) {
    final useSimulcast = profile.useSimulcast && profile.lowLayer != null;
    return lk.VideoPublishOptions(
      simulcast: useSimulcast,
      screenShareSimulcastLayers: useSimulcast
          ? [_parametersForLayer(profile.lowLayer!)]
          : const [],
      screenShareEncoding: _encodingForLayer(profile.mainLayer),
      videoEncoding: _encodingForLayer(profile.mainLayer),
      videoCodec: profile.codec,
      degradationPreference: _degradationPreferenceForProfile(
        profile,
        preserveGameCaptureResolution: preserveGameCaptureResolution,
      ),
      backupVideoCodec: lk.BackupVideoCodec(enabled: false),
    );
  }

  lk.DegradationPreference _degradationPreferenceForProfile(
    ScreenShareProfileConfig profile, {
    bool preserveGameCaptureResolution = false,
  }) {
    if (PlatformUtils.isWindows &&
        (profile.hardwareEncodeFirst || preserveGameCaptureResolution)) {
      return lk.DegradationPreference.maintainResolution;
    }
    return lk.DegradationPreference.maintainFramerate;
  }

  bool _preserveGameCaptureResolutionForBackend(
    WindowsScreenCaptureBackendMode? backend,
  ) {
    return PlatformUtils.isWindows &&
        backend == WindowsScreenCaptureBackendMode.gameD3d11HookExperimental;
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
    required bool preserveGameCaptureResolution,
  }) async {
    final publishOptions = _publishOptionsForProfile(
      publishProfile,
      preserveGameCaptureResolution: preserveGameCaptureResolution,
    );
    if (!guardPrePublication) {
      return participant.publishVideoTrack(
        track,
        publishOptions: publishOptions,
      );
    }

    final timeout = _streamTestPublishVideoTrackTimeout;
    final context =
        'stage=publishVideoTrack_pre_event '
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
    await Future<void>.delayed(_streamTestPrePublishSourceWarmup);

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
        .where((publication) => _isScreenShareVideoPublication(publication))
        .toList(growable: false);
  }

  bool _isScreenShareVideoPublication(lk.TrackPublication publication) {
    return publication.kind == lk.TrackType.VIDEO &&
        (publication.isScreenShare ||
            publication.source == lk.TrackSource.screenShareVideo ||
            publication.name == 'screenshare');
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

      final mediaStream = await shareSession
          .createSharedAudioPublicationStream();
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

      final publication = await localParticipant.publishAudioTrack(
        localAudioTrack,
        publishOptions: const lk.AudioPublishOptions(
          name: 'screenShareAudio',
          stream: 'screenShareAudio',
          dtx: false,
          red: true,
          audioBitrate: lk.AudioPreset.musicStereo,
        ),
      );
      // Recorded as a pair, and only once the publish has returned: a track
      // stored without its publication is one nothing can unpublish.
      _windowsSharedAudioPublications[_defaultSharedAudioKey] =
          _WindowsSharedAudioPublication(
            publication: publication,
            track: localAudioTrack,
          );
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
    final published = _windowsSharedAudioPublications.remove(
      _defaultSharedAudioKey,
    );
    final publication = published?.publication;
    final track = published?.track;

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
    _runLiveKitRoomEvent(() {
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

      _notifyStateChanged();
    });
  }

  void onTrackUnmutedEvent(lk.TrackUnmutedEvent event) {
    _runLiveKitRoomEvent(() {
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
        _notifyStateChanged();
      }
      if (_remoteMediaKind(event.publication) != null) {
        unawaited(_queueRemoteMediaReconciliation('track_unmuted'));
      }
    });
  }

  void onTrackPublished(lk.TrackPublishedEvent event) {
    _runLiveKitRoomEvent(() {
      Log.i(
        'LiveKit remote track published: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
      );
      final participant = _userIdFromParticipantIdentity(
        event.participant.identity,
      );

      if (_addLivekitStream(
        event.publication,
        participant,
        participantIdentity: event.participant.identity,
      )) {
        _notifyStateChanged();
      }
      if (_remoteMediaKind(event.publication) != null) {
        unawaited(_queueRemoteMediaReconciliation('track_published'));
      }
    });
  }

  void onTrackSubscribed(lk.TrackSubscribedEvent event) {
    _runLiveKitRoomEvent(() {
      // New diagnostic, not a restoration: "was the remote track ever
      // subscribed?" has never been answerable from an exported log, because
      // this handler has logged nothing for the entire life of the repository
      // while the publish side has always logged.
      Log.i(
        'LiveKit remote track subscribed: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)} '
        'kind=${_remoteMediaKind(event.publication)?.name ?? 'other'}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      final participant = _userIdFromParticipantIdentity(
        event.participant.identity,
      );

      final added = _addLivekitStream(
        event.publication,
        participant,
        participantIdentity: event.participant.identity,
      );
      final notified = _notifyLivekitStreamChanged(
        event.publication,
        (stream) => stream.onTrackSubscribedEvent(event.track),
      );

      if (added || notified) {
        _notifyStateChanged();
      }
      if (_remoteMediaKind(event.publication) != null) {
        unawaited(_queueRemoteMediaReconciliation('track_subscribed'));
      }
    });
  }

  void onTrackUnsubscribed(lk.TrackUnsubscribedEvent event) {
    _runLiveKitRoomEvent(() {
      Log.i(
        'LiveKit remote track unsubscribed: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      final notified = _notifyLivekitStreamChanged(
        event.publication,
        (stream) => stream.onTrackUnsubscribedEvent(event.track),
      );

      if (notified) {
        _notifyStateChanged();
      }
      if (_remoteMediaKind(event.publication) != null) {
        unawaited(_queueRemoteMediaReconciliation('track_unsubscribed'));
      }
    });
  }

  void onParticipantConnected(lk.ParticipantConnectedEvent event) {
    _runLiveKitRoomEvent(() {
      // Remote participant connect/disconnect were unlogged on every build,
      // which is why "who was actually in the room" could never be recovered
      // from a capture.
      Log.i(
        'LiveKit remote participant connected: '
        'participant=${_redactedParticipantIdentity(event.participant.identity)} '
        'publications=${event.participant.trackPublications.length}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      clientManager?.callManager.joinCallSound();
      unawaited(_queueRemoteMediaReconciliation('participant_connected'));
    });
  }

  void onParticipantDisconnected(lk.ParticipantDisconnectedEvent event) {
    _runLiveKitRoomEvent(() {
      _remoteStreamCueState.participantLeft(event.participant.identity);
      _streamViewerPresence.removeParticipant(event.participant.identity);
      _refreshStreamViewerTimer();
      Log.i(
        'LiveKit remote participant disconnected: '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      _removeLivekitStreamsWhere(
        (stream) => stream.participantIdentity == event.participant.identity,
      );
      clientManager?.callManager.endCallSound();
      _notifyStateChanged();
      _refreshCallHealthDiagnostics();
    });
  }

  void onDataReceived(lk.DataReceivedEvent event) {
    _runLiveKitRoomEvent(() {
      final participant = event.participant;
      final viewerIntent = StreamViewerIntent.decode(event.topic, event.data);
      if (viewerIntent != null) {
        if (participant != null) {
          final changed = _streamViewerPresence.update(
            participantIdentity: participant.identity,
            publishedStreamIds: _publishedScreenShareIds,
            reportedStreamIds: viewerIntent.streamIds,
            now: DateTime.now(),
          );
          if (changed) _notifyStateChanged();
          _refreshStreamViewerTimer();
        }
        return;
      }
      final cue = StreamLifecycleCueProtocol.decode(event.topic, event.data);
      if (participant == null ||
          cue == null ||
          !_remoteStreamCueState.shouldPlay(participant.identity, cue)) {
        return;
      }
      _playStreamLifecycleCue(cue);
    });
  }

  List<String> get localScreenShareViewerUserIds {
    return _streamViewerPresence.viewerIdentities
        .map(_userIdFromParticipantIdentity)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  Set<String> get _publishedScreenShareIds => streams
      .whereType<MatrixLivekitVoipStream>()
      .where(
        (stream) =>
            stream.direction == VoipStreamDirection.outgoing &&
            stream.type == VoipStreamType.screenshare,
      )
      .map((stream) => stream.streamId)
      .toSet();

  void setVisibleRemoteScreenShares(Object surface, Set<String> streamIds) {
    if (_ending || _sessionDisposed) return;
    final previous = _watchedSharesBySurface[surface] ?? const <String>{};
    if (previous.length == streamIds.length &&
        previous.containsAll(streamIds)) {
      return;
    }
    if (streamIds.isEmpty) {
      _watchedSharesBySurface.remove(surface);
    } else {
      _watchedSharesBySurface[surface] = Set.of(streamIds);
    }
    _queueWatchIntentSnapshot();
    _refreshStreamViewerTimer();
  }

  void _queueWatchIntentSnapshot() {
    _watchIntentSend = _watchIntentSend.catchError((_) {}).then((_) async {
      if (_ending || _sessionDisposed) return;
      final participant = livekitRoom.localParticipant;
      if (participant == null) return;
      final watchedIds = _watchedSharesBySurface.values
          .expand((ids) => ids)
          .toSet();
      final byDestination = groupWatchedScreenSharesByPublisher(
        remoteShares: streams
            .whereType<MatrixLivekitVoipStream>()
            .where(
              (stream) =>
                  stream.direction == VoipStreamDirection.incoming &&
                  stream.type == VoipStreamType.screenshare,
            )
            .map(
              (stream) => (
                streamId: stream.streamId,
                publisherIdentity: stream.participantIdentity,
              ),
            ),
        watchedIds: watchedIds,
      );
      final destinations = {..._watchIntentDestinations, ...byDestination.keys};
      _watchIntentDestinations
        ..clear()
        ..addAll(byDestination.keys);
      await Future.wait(
        destinations.map((destination) async {
          try {
            await participant
                .publishData(
                  StreamViewerIntent(
                    byDestination[destination] ?? const <String>{},
                  ).encode(),
                  reliable: true,
                  destinationIdentities: [destination],
                  topic: streamViewerIntentTopic,
                )
                .timeout(const Duration(seconds: 2));
          } catch (error, stackTrace) {
            Log.onError(
              error,
              stackTrace,
              content: 'Failed to update stream viewer intent',
              category: LogCategory.livekit,
              source: 'matrix-livekit-session',
            );
          }
        }),
      );
    });
  }

  void _refreshStreamViewerTimer() {
    if (_ending || _sessionDisposed) {
      _streamViewerTimer?.cancel();
      _streamViewerTimer = null;
      return;
    }
    final active =
        _watchedSharesBySurface.isNotEmpty ||
        _streamViewerPresence.viewerIdentities.isNotEmpty;
    if (!active) {
      _streamViewerTimer?.cancel();
      _streamViewerTimer = null;
    } else {
      _streamViewerTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (_watchedSharesBySurface.isNotEmpty) _queueWatchIntentSnapshot();
        _pruneStreamViewers();
        _refreshStreamViewerTimer();
      });
    }
  }

  void _pruneStreamViewers() {
    if (_streamViewerPresence.prune(
      publishedStreamIds: _publishedScreenShareIds,
      now: DateTime.now(),
    )) {
      _notifyStateChanged();
    }
  }

  void _playStreamLifecycleCue(StreamLifecycleCue cue) {
    final manager = clientManager?.callManager;
    if (cue == StreamLifecycleCue.start) {
      manager?.playStreamStartSound();
    } else {
      manager?.playStreamEndSound();
    }
  }

  Future<void> _announceStreamLifecycleCue(StreamLifecycleCue cue) async {
    _playStreamLifecycleCue(cue);
    try {
      await livekitRoom.localParticipant
          ?.publishData(
            StreamLifecycleCueProtocol.encode(cue),
            reliable: true,
            topic: StreamLifecycleCueProtocol.topic,
          )
          .timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to announce screen-share ${cue.name} cue',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  void _announceEndCueIfShareCleared() {
    if (!_ending &&
        _localStreamCueState.onShareOperationFinished(
          shareActive: isSharingScreen,
        )) {
      unawaited(_announceStreamLifecycleCue(StreamLifecycleCue.end));
    }
  }

  void onParticipantConnectionQualityUpdated(
    lk.ParticipantConnectionQualityUpdatedEvent event,
  ) {
    _runLiveKitRoomEvent(() {
      _queueCallHealthDiagnosticsRefresh();
    });
  }

  // Reconnect mode, verified against livekit_client 2.5.4 rather than assumed.
  //
  // The SDK has two reconnect paths and only one of them reaches the app:
  //
  //  * FULL RESTART - `EngineFullRestartingEvent` emits `RoomReconnectingEvent`
  //    (`core/room.dart:519-520`) and `EngineRestartedEvent` emits
  //    `RoomReconnectedEvent` (`:541-552`) after `rePublishAllTracks()`. Both
  //    of the events this session listens for therefore mean full restart, and
  //    only full restart.
  //  * RESUME - `EngineResumingEvent`/`EngineResumedEvent` are handled at
  //    `:514-517` and `:555-558`, which send sync state and track permissions
  //    and emit *no* room event at all.
  //
  // So a resume is invisible to this session, and the two paths were never
  // sharing a log line the way it looked. Reading a capture: a
  // `reconnect_attempt` line with no following `mode=full_restart` line is a
  // resume. Tagging the mode explicitly is what lets the local-publication and
  // remote-media lanes tell the two apart, because `rePublishAllTracks()` -
  // which is what breaks track/publication mute state - runs on the full path
  // only.
  int _reconnectAttempts = 0;
  DateTime? _reconnectStartedAt;

  void onRoomReconnecting(lk.RoomReconnectingEvent event) {
    _runLiveKitRoomEvent(() {
      _roomLifecycle = CallConnectionLifecycle.reconnecting;
      _reconnectStartedAt ??= DateTime.now();
      Log.w(
        'call_reconnect event=started mode=full_restart '
        'republishes_local_tracks=true '
        'attempt=$_reconnectAttempts',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      _refreshCallHealthDiagnostics();
    });
  }

  void onRoomAttemptReconnect(lk.RoomAttemptReconnectEvent event) {
    _runLiveKitRoomEvent(() {
      _reconnectAttempts = event.attempt;
      _reconnectStartedAt ??= DateTime.now();
      Log.i(
        'call_reconnect event=attempt mode=undetermined '
        'attempt=${event.attempt} '
        'max_attempts=${event.maxAttemptsRetry} '
        'next_retry_ms=${event.nextRetryDelaysInMs}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    });
  }

  void onRoomReconnected(lk.RoomReconnectedEvent event) {
    _runLiveKitRoomEvent(() {
      _roomLifecycle = CallConnectionLifecycle.connected;
      final startedAt = _reconnectStartedAt;
      Log.i(
        'call_reconnect event=completed result=ok mode=full_restart '
        'republished_local_tracks=true '
        'attempts=$_reconnectAttempts '
        'duration_ms=${startedAt == null ? 'unknown' : DateTime.now().difference(startedAt).inMilliseconds}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      _reconnectAttempts = 0;
      _reconnectStartedAt = null;
      final microphonePublication = livekitRoom.localParticipant
          ?.getTrackPublicationBySource(lk.TrackSource.microphone);
      if (microphonePublication != null) {
        unawaited(
          _reconcileLocalMicrophoneMuteDrift(
            microphonePublication,
            trigger: 'room_reconnected',
          ),
        );
      }
      unawaited(_queueRemoteMediaReconciliation('room_reconnected'));
      _refreshCallHealthDiagnostics();
    });
  }

  void onRoomDisconnected(lk.RoomDisconnectedEvent event) {
    _runLiveKitRoomEvent(() {
      _roomLifecycle = CallConnectionLifecycle.disconnected;
      Log.w(
        'LiveKit room disconnected unexpectedly: '
        'reason=${event.reason ?? 'unknown'}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      _refreshCallHealthDiagnostics();
      unawaited(_handleUnexpectedRoomDisconnected(event));
    });
  }

  Future<void> _handleUnexpectedRoomDisconnected(
    lk.RoomDisconnectedEvent event,
  ) async {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }

    try {
      await hangUpCall();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to clean up after unexpected LiveKit room disconnect: ${event.reason ?? 'unknown'}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  void onLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    _runLiveKitRoomEvent(() {
      Log.i(
        'LiveKit local track published: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
      );
      final participant = _userIdFromParticipantIdentity(
        event.participant.identity,
      );

      final added = _addLivekitStream(
        event.publication,
        participant,
        participantIdentity: event.participant.identity,
      );
      final publishedScreenShareVideo = _isScreenShareVideoPublication(
        event.publication,
      );
      if (publishedScreenShareVideo) {
        _activeLocalScreenShareVideoPublicationSids.add(event.publication.sid);
        if (_desiredLocalPreviewProbeEnabled) {
          unawaited(_startLocalPreviewProbe());
        }
      }
      if (_isLocalMicrophoneAudioPublication(event.publication)) {
        unawaited(
          _reconcileLocalMicrophoneMuteDrift(
            event.publication,
            trigger: 'local_track_published',
          ),
        );
      }
      final track = event.publication.track;
      final activeProfile = _activeScreenShareProfile;
      if (activeProfile != null &&
          publishedScreenShareVideo &&
          track is lk.LocalVideoTrack &&
          !_streamTestScreenSharePublishInProgress &&
          !_streamTestScreenShareActive) {
        unawaited(_applyScreenShareSenderLimits(activeProfile));
      }

      if (added || publishedScreenShareVideo) {
        _notifyStateChanged();
      }
    });
  }

  void onLocalTrackUnpublished(lk.LocalTrackUnpublishedEvent event) {
    _runLiveKitRoomEvent(() {
      Log.i(
        'LiveKit local track unpublished: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
      );
      _removeLivekitStreamsWhere(
        (stream) => stream.publication.sid == event.publication.sid,
      );
      _activeLocalScreenShareVideoPublicationSids.remove(event.publication.sid);
      if (_localPreviewProbe?.publicationSid == event.publication.sid) {
        unawaited(_restartLocalPreviewProbeAfterPublicationChange());
      }

      _notifyStateChanged();
    });
  }

  void onTrackUnpublished(lk.TrackUnpublishedEvent event) {
    _runLiveKitRoomEvent(() {
      Log.i(
        'LiveKit remote track unpublished: '
        '${_trackPublicationSummary(event.publication)} '
        'participant=${_redactedParticipantIdentity(event.participant.identity)}',
      );
      _removeLivekitStreamsWhere(
        (stream) => stream.publication.sid == event.publication.sid,
      );

      _notifyStateChanged();
    });
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
  Future<void> hangUpCall() {
    // Hang-up can be triggered from the UI, an unexpected room disconnect, and
    // the OS lifecycle listener at once; run the teardown exactly once and let
    // every caller await the same completion.
    return _hangUpFuture ??= _hangUpCallOnce();
  }

  Future<void> _hangUpCallOnce() async {
    Log.i("Hanging up call");
    final hangUpStartedAt = DateTime.now();
    final stepResults = <String, bool>{};
    _ending = true;
    _streamViewerTimer?.cancel();
    _streamViewerTimer = null;
    _watchedSharesBySurface.clear();
    // Publish the intent the join guard needs. `_ending` is private, so
    // `joinCall()` could only ask `state != ended` and was handed this session
    // back while it was dying. Only the connection-state stream is signalled:
    // `_stateChanged` drives the call surfaces, and how a leaving call should
    // *look* is a separate change from making it unjoinable.
    state = VoipState.leaving;
    _notifyConnectionChanged();
    _liveKitRoomTeardownTicket ??= LiveKitRoomTeardownBarrier.register(
      room.client.identifier,
    );
    _initialMicrophoneEnableState.markCallInactive();
    membershipRefreshTimer?.cancel();
    membershipRefreshTimer = null;

    // Stop the lifecycle listener first so it doesn't re-trigger hang-up
    // if the OS sends a second detach event during cleanup.
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    try {
      // Bounded like its siblings below, and for a sharper reason: each
      // `stream.dispose()` inside used to await `close()` on a *broadcast*
      // controller that every mounted call tile subscribes to, which can hang
      // indefinitely. This was the one step in the block that was not bounded,
      // and a hang here skips the `finally` entirely - state never reaches
      // `ended`, `_hangUpFuture` never completes, and every later `joinCall()`
      // is handed back this dead session.
      stepResults['dispose_transient_resources'] = await _runBoundedHangUpStep(
        stepName: 'dispose_transient_resources',
        step: _disposeTransientCallResources(),
        timeout: _hangUpTeardownTimeout,
      );

      // Unpublishing the screen share is LiveKit signaling over the same
      // socket that may already be dead; bound it so it cannot wedge hang-up.
      stepResults['stop_screen_share'] = await _runBoundedHangUpStep(
        stepName: 'stop_screen_share',
        step: _stopScreenShareBeforeHangUp(),
        timeout: _hangUpTeardownTimeout,
      );

      // Bound each teardown so a wedged homeserver call or LiveKit disconnect
      // cannot keep the session from reaching ended. Failures/timeouts are
      // logged and abandoned rather than propagated.
      await Future.wait<void>([
        _runBoundedHangUpStep(
          stepName: 'clear_call_state',
          step: clearRoomCallState(),
          timeout: _hangUpTeardownTimeout,
        ).then<void>((ok) => stepResults['clear_call_state'] = ok),
        _disposeLiveKitRoom(),
        _runBoundedHangUpStep(
          stepName: 'stop_heartbeat',
          step: stopHeartbeat(),
          timeout: _hangUpTeardownTimeout,
        ).then<void>((ok) => stepResults['stop_heartbeat'] = ok),
      ]);
    } finally {
      // This retries a native teardown when an earlier cleanup step failed.
      // The barrier ticket remains pending until Room.dispose itself settles.
      await _disposeLiveKitRoom();

      // Always release the session, even if teardown timed out or threw, so a
      // later join is not handed back this dead session.
      state = VoipState.ended;
      _roomLifecycle = CallConnectionLifecycle.ended;
      _notifyStateChanged();
      _notifyConnectionChanged();

      _logHangUpCompleted(startedAt: hangUpStartedAt, stepResults: stepResults);

      clientManager?.callManager.onSessionEnded(this);

      // Last: `onSessionEnded` drops the session from `CallManager` and its
      // listeners cancel, so nothing is left that expects another event.
      await dispose();
    }
  }

  void _notifyConnectionChanged() {
    if (!_onConnectionChanged.isClosed) {
      _onConnectionChanged.add(state);
    }
  }

  /// Releases the session's own stream controllers.
  ///
  /// The class had no `dispose()` at all: its five broadcast controllers were
  /// never closed and the session simply stopped being referenced. That is why
  /// "restart the app" was a general-purpose remedy for this subsystem rather
  /// than a workaround for one bug.
  ///
  /// Idempotent, and called from the end of hang-up rather than by an external
  /// owner, because nothing outside owns a session's lifetime.
  Future<void> dispose() async {
    if (_sessionDisposed) {
      return;
    }
    _sessionDisposed = true;
    _streamViewerTimer?.cancel();
    _streamViewerTimer = null;

    // Broadcast close() futures only complete once every past subscriber has
    // cancelled after close, so awaiting them can hang dispose forever - the
    // same hazard `CallManager.dispose` documents and the same one that made
    // the transient-resource teardown able to strand hang-up.
    unawaited(_stateChanged.close());
    unawaited(_onConnectionChanged.close());
    unawaited(_onVolumeChanged.close());
    unawaited(_onDiagnosticsChanged.close());
    unawaited(_onReceiverProbeEvent.close());
  }

  /// The terminal line for a hang-up.
  ///
  /// Start (`Hanging up call`) and per-step failures were already logged, but
  /// nothing marked the end, so a capture could not distinguish "all five
  /// steps succeeded" from "the block never got past its first await". The
  /// step count is what carries that: a wedged step is visible as a short
  /// `steps_run` rather than as an absent line.
  void _logHangUpCompleted({
    required DateTime startedAt,
    required Map<String, bool> stepResults,
  }) {
    final failedSteps = stepResults.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    final quarantined = LiveKitRoomTeardownBarrier.hasFailedTeardown(
      room.client.identifier,
    );
    final degraded =
        failedSteps.isNotEmpty ||
        quarantined ||
        stepResults.length < _hangUpStepCount;

    Log.i(
      'call_hangup event=completed '
      'result=${degraded ? 'degraded' : 'ok'} '
      'duration_ms=${DateTime.now().difference(startedAt).inMilliseconds} '
      'steps_run=${stepResults.length}/$_hangUpStepCount '
      'steps_failed=${failedSteps.isEmpty ? 'none' : failedSteps.join('+')} '
      'join_quarantined=$quarantined',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
  }

  Future<void> _disposeLiveKitRoom() {
    final pendingTeardown = _liveKitRoomTeardownFuture;
    if (pendingTeardown != null) {
      return pendingTeardown;
    }

    final teardown = _disposeLiveKitRoomOnce();
    _liveKitRoomTeardownFuture = teardown;
    return teardown;
  }

  Future<void> _disposeLiveKitRoomOnce() async {
    final disconnect = disconnectCall();
    unawaited(_disposeNativeLiveKitRoomAfterDisconnect(disconnect));
    final disconnected = await _runBoundedHangUpStep(
      stepName: 'disconnect_livekit_room',
      step: disconnect,
      timeout: _hangUpTeardownTimeout,
    );
    if (!disconnected) {
      _failLiveKitRoomTeardown('disconnect_timeout');
    }
  }

  /// Records that this session could not confirm its native room was released,
  /// which quarantines joins for the whole Matrix account until the barrier
  /// lifts it.
  ///
  /// Logged loudly and with an explicit outcome because two different 2000 ms
  /// timeouts in this stack read almost identically in a capture: this one, in
  /// the session teardown path, and `_disconnectFailedLiveKitRoom` in
  /// `matrix_livekit_backend.dart`, which cleans up after a *failed join* and
  /// cannot quarantine anything. Confusing the two already produced a
  /// contradiction between two of our own documents, so the quarantining path
  /// says so in the line itself.
  void _failLiveKitRoomTeardown(String reason) {
    final ticket = _liveKitRoomTeardownTicket;
    if (ticket == null) {
      return;
    }

    ticket.fail();
    Log.w(
      'call_hangup event=native_room_release_unconfirmed '
      'path=session_teardown '
      'reason=$reason '
      'result=join_quarantine_set '
      'scope=matrix_account '
      'clears_in_ms='
      '${LiveKitRoomTeardownBarrier.failedTeardownQuarantine.inMilliseconds} '
      'retryable=true',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
  }

  /// Records that the native room really was released.
  ///
  /// Reached after [_failLiveKitRoomTeardown] whenever a dispose overran its
  /// budget and then finished, so the "quarantine lifted" case has to be
  /// visible in a capture too - otherwise the only evidence in the log is the
  /// warning that set it.
  void _completeLiveKitRoomTeardown() {
    final ticket = _liveKitRoomTeardownTicket;
    if (ticket == null) {
      return;
    }

    final wasQuarantined = LiveKitRoomTeardownBarrier.hasFailedTeardown(
      room.client.identifier,
    );
    ticket.complete();
    if (wasQuarantined) {
      Log.i(
        'call_hangup event=native_room_released_late '
        'path=session_teardown '
        'result=join_quarantine_cleared',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  Future<void> _disposeNativeLiveKitRoomAfterDisconnect(
    Future<void> disconnect,
  ) async {
    try {
      await disconnect;
    } catch (error, stackTrace) {
      Log.w('LiveKit room disconnect failed before disposal: $error');
      Log.w(stackTrace.toString());
    }
    final disposed = await _runBoundedHangUpStep(
      stepName: 'dispose_livekit_room',
      step: _disposeNativeLiveKitRoom(),
      timeout: _nativeLiveKitRoomDisposeTimeout,
    );
    if (!disposed) {
      _failLiveKitRoomTeardown('native_dispose_timeout');
    }
  }

  Future<void> _disposeNativeLiveKitRoom() {
    final pendingDispose = _nativeLiveKitRoomDisposeFuture;
    if (pendingDispose != null) {
      return pendingDispose;
    }

    final dispose = _disposeNativeLiveKitRoomOnce();
    _nativeLiveKitRoomDisposeFuture = dispose;
    return dispose;
  }

  Future<void> _disposeNativeLiveKitRoomOnce() async {
    var disposed = false;
    try {
      Log.i('Disposing LiveKit room');
      await livekitRoom.dispose();
      disposed = true;
      Log.i('Disposed LiveKit room');
    } catch (error, stackTrace) {
      Log.w('LiveKit room disposal failed: $error');
      Log.w(stackTrace.toString());
    } finally {
      if (disposed) {
        _completeLiveKitRoomTeardown();
      } else {
        _failLiveKitRoomTeardown('native_dispose_threw');
      }
    }
  }

  /// Short pseudonymous form of a LiveKit participant identity, for logs only.
  ///
  /// A participant identity carries the Matrix user id and device id, and these
  /// logs are collected by the bug-report export, so writing it verbatim widens
  /// the identifier surface in diagnostics users hand to us. This matches the
  /// redaction already applied to the user id in `MatrixLivekitVoipStream` and
  /// to the room id in `MatrixVoipRoomComponent`.
  ///
  /// Log sites only. Every non-log use of `event.participant.identity` - the
  /// arguments to `_userIdFromParticipantIdentity` and `_addLivekitStream` -
  /// must keep the real value.
  /// BUG-325. One tick of the microphone capture-liveness probe.
  ///
  /// Reads the native suppression hook's frame counter, which advances once
  /// per captured frame, and logs the three transitions that matter. The
  /// stall line carries every stage fact at once so a single capture says
  /// which stage failed: the publication and its RTP sender (LiveKit's view),
  /// the media track's own enabled/muted state (the device's view), and the
  /// native hook's reason and counter (the capture path's view). On the
  /// tester's machine the first two read healthy while the third reported
  /// zero frames, and that combination had no log line until now.
  Future<void> _checkMicrophoneCaptureLiveness() async {
    if (!MicrophoneCaptureLivenessPlatformGate.shouldMonitor(
          isWindows: PlatformUtils.isWindows,
        ) ||
        !_canProcessLiveKitRoomEvent) {
      return;
    }
    final publication = livekitRoom.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.microphone);
    final track = publication?.track;
    final mediaTrack = track is lk.LocalAudioTrack
        ? track.mediaStreamTrack
        : null;
    final trackEnabled = mediaTrack?.enabled ?? false;
    // The LiveKit half of "capture is expected". The native half - the hook
    // being installed and counting, which is where `waiting_for_audio` is
    // reported from - comes from the sampler's own fresh reading, so a stale
    // `available` cannot answer it.
    final publicationLive =
        publication != null &&
        !publication.muted &&
        trackEnabled &&
        _initialMicrophoneEnableState.desiredMicrophoneEnabled;

    final event = await _microphoneCaptureLivenessSampler.sample(
      publicationLive: publicationLive,
      now: DateTime.now(),
      captureDeviceId: _appliedMicrophoneCaptureDeviceId,
    );
    if (event == MicrophoneCaptureLivenessEvent.none) {
      return;
    }
    // Re-checked after the await: the refresh is a platform round trip and
    // the call can end under it.
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    final status = NoiseSuppressionService.instance.status;

    final detail =
        'microphone_capture_liveness event=${event.name} '
        'elapsed_ms=${_microphoneCaptureLivenessProbe.lastElapsed.inMilliseconds} '
        'frames=${status.framesProcessed} '
        'ns_reason=${status.reason} ns_active=${status.active} '
        'capture_device=${_redactedCaptureDeviceId(_appliedMicrophoneCaptureDeviceId)} '
        'publication_sid=${publication?.sid ?? 'none'} '
        'publication_muted=${publication?.muted} '
        'sender_attachment=${publication == null ? 'none' : LivekitMicrophoneSenderGate.attachmentOf(publication).name} '
        'track_enabled=$trackEnabled track_muted=${mediaTrack?.muted}';
    if (event == MicrophoneCaptureLivenessEvent.stalled) {
      Log.w(
        detail,
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      _recoverStalledMicrophoneCapture();
      return;
    }
    Log.i(
      detail,
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
  }

  /// Recreates a microphone capture once when its native frame counter stops
  /// despite a live local publication.
  void _recoverStalledMicrophoneCapture() {
    if (!MicrophoneCaptureLivenessPlatformGate.shouldMonitor(
      isWindows: PlatformUtils.isWindows,
    )) {
      return;
    }
    final captureDeviceId = _appliedMicrophoneCaptureDeviceId;
    final microphoneEnableGeneration = _initialMicrophoneEnableState.generation;
    if (!_microphoneCaptureRecoveryGate.shouldAttempt(
      event: MicrophoneCaptureLivenessEvent.stalled,
      microphoneEnableGeneration: microphoneEnableGeneration,
      captureDeviceId: captureDeviceId,
    )) {
      return;
    }

    Log.w(
      'LiveKit microphone capture stalled; scheduling one fresh-track '
      'recovery: generation=$microphoneEnableGeneration '
      'capture_device=${_redactedCaptureDeviceId(captureDeviceId)}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    final signature = NoiseSuppressionCaptureProfile.captureFrontendSignature(
      bypassVoiceProcessing: IosCallAudioSession.shouldBypassVoiceProcessing,
    );
    _noiseSuppressionCaptureRefresh = _noiseSuppressionCaptureRefresh
        .catchError((_) {})
        .then(
          (_) => _recreateStalledMicrophoneCapture(
            signature,
            microphoneEnableGeneration,
          ),
        );
  }

  Future<void> _recreateStalledMicrophoneCapture(
    String signature,
    int generation,
  ) async {
    if (!_shouldContinueMicrophoneCaptureRefresh(
      generation: generation,
      expectedCaptureProfileSignature: signature,
    )) {
      return;
    }

    final participant = livekitRoom.localParticipant;
    final publication = participant?.getTrackPublicationBySource(
      lk.TrackSource.microphone,
    );
    if (participant == null || publication == null || publication.muted) {
      return;
    }

    try {
      final options = await _currentMicrophoneCaptureOptions();
      bool mayPublish() =>
          _shouldContinueMicrophoneCaptureRefresh(
            generation: generation,
            expectedCaptureProfileSignature: signature,
          ) &&
          !_ending &&
          state != VoipState.ended;
      if (!mayPublish() ||
          participant
                  .getTrackPublicationBySource(lk.TrackSource.microphone)
                  ?.sid !=
              publication.sid) {
        return;
      }

      final recreated = await recreateStalledMicrophonePublication(
        participant: participant,
        stalledPublicationSid: publication.sid,
        mayPublish: mayPublish,
        publishFresh: () => participant.setMicrophoneEnabled(
          true,
          audioCaptureOptions: options,
        ),
        onRemovedWithoutReplacement:
            _restoreMicrophoneAfterAbandonedCaptureRefresh,
      );
      if (!recreated) return;

      _microphoneCaptureProfileSignature = signature;
      _appliedMicrophoneCaptureDeviceId = options.deviceId;
      NoiseSuppressionService.instance.scheduleHealthRefresh();
      await _reconcileMicrophoneSenderAfterCaptureRefresh(participant);
      _notifyStateChanged();
      Log.i(
        'LiveKit microphone fresh-track recovery completed: '
        'capture_device=${_redactedCaptureDeviceId(options.deviceId)}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to recreate stalled LiveKit microphone capture',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  /// A capture device id is not an identity, but a device LABEL can carry a
  /// person's name, and the id is stable enough to correlate captures. Hashed
  /// like every other identifier in this log.
  static String _redactedCaptureDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return 'default';
    }
    return sha256.convert(utf8.encode(deviceId)).toString().substring(0, 12);
  }

  static String _redactedParticipantIdentity(String? identity) {
    if (identity == null || identity.isEmpty) {
      return 'none';
    }
    return sha256.convert(utf8.encode(identity)).toString().substring(0, 12);
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
      // Stop every periodic timer and close the room-event gate *before* any
      // awaited teardown. These callbacks (stats, remote-audio flow sampling,
      // stream live tuning, call-health) reach into the LiveKit room and its
      // native tracks; letting them keep firing while the room is being torn
      // down - especially during a rapid hang-up-then-join-another-call switch -
      // races native disposal and can crash the process. Cancelling first is
      // always safe and closes that window.
      _volumeTimer?.cancel();
      _volumeTimer = null;
      _diagnosticsTimer?.cancel();
      _diagnosticsTimer = null;
      _remoteAudioFlowTimer?.cancel();
      _remoteAudioFlowTimer = null;
      _remoteAudioFlowMonitor.reset();
      _remoteMediaAttachMonitor.reset();
      _streamLiveTuningTimer?.cancel();
      _streamLiveTuningTimer = null;
      _inboundAudioEnergyTimer?.cancel();
      _inboundAudioEnergyTimer = null;
      _inboundAudioEnergyCollectionActive = false;
      _microphoneCaptureLivenessTimer?.cancel();
      _microphoneCaptureLivenessTimer = null;
      _microphoneCaptureLivenessProbe.reset();
      _lastInboundAudioEnergyLogMs = null;
      _callHealthDiagnosticsRefreshTimer?.cancel();
      _callHealthDiagnosticsRefreshTimer = null;
      _liveKitRoomEventGate.dispose();

      await _stopServerAudioLoopback(notify: false);
      await _stopInProcessReceiverProbe(notify: false);
      await _stopLocalPreviewProbe(notify: false);
      await _cancelLiveKitSessionSubscription(
        _noiseSuppressionStatusSub,
        content:
            'Recovered LiveKit noise suppression status subscription cancel failure',
        source: 'livekit-noise-suppression-subscription',
      );
      _noiseSuppressionStatusSub = null;
      await _cancelLiveKitSessionSubscription(
        _microphoneInputDeviceSub,
        content:
            'Recovered LiveKit microphone input device subscription cancel failure',
        source: 'livekit-microphone-device-subscription',
      );
      _microphoneInputDeviceSub = null;
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'room-listener-dispose',
        cleanup: _roomListener?.dispose,
      );
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
  bool get isCameraEnabled => _localCameraPublications().any((publication) {
    final track = publication.track;
    // `track != null` alone only proves the publication still holds an object.
    // `Track.isActive` (`livekit_client-2.5.4 track/track.dart:56`) is cleared
    // by `stop()`, so a camera that was stopped without its publication being
    // removed - a partially failed teardown - no longer keeps the button lit.
    return !publication.muted && track != null && track.isActive;
  });

  @override
  bool get isMicrophoneMuted {
    final participant = livekitRoom.localParticipant;
    if (participant == null) {
      return false;
    }

    // `Participant.isMuted` is `audioTrackPublications.firstOrNull?.muted`
    // (`livekit_client-2.5.4 participant/participant.dart:104`) - an
    // *unfiltered* local audio publication list. While sharing screen audio
    // that list can lead with the screen-share publication, so the microphone
    // indicator was rendering the screen-share track's mute state. Select by
    // source instead.
    final publication = participant.getTrackPublicationBySource(
      lk.TrackSource.microphone,
    );
    if (publication == null) {
      // Matches the SDK's derivation for "nothing published": no microphone
      // means nothing is being sent.
      return true;
    }

    // A detached sender sends nothing regardless of what the publication
    // metadata says, and that disagreement is the whole silent-mic defect.
    // Report the state the remote participants actually experience.
    if (LivekitMicrophoneSenderGate.isDetached(publication)) {
      return true;
    }

    return publication.muted;
  }

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
    _serverAudioLoopbackOperation = _serverAudioLoopbackOperation
        .catchError((_) {})
        .then((_) async {
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

  bool get isInProcessReceiverProbeEnabled => _receiverProbe != null;

  bool get isInProcessReceiverProbeStarting => _receiverProbeStarting;

  String? get inProcessReceiverProbeError => _receiverProbeError;

  MatrixLivekitReceiverProbeSnapshot? get inProcessReceiverProbeSnapshot =>
      _receiverProbe?.snapshot;

  RTCVideoRenderer? get inProcessReceiverProbeRenderer =>
      _receiverProbe?.renderer;

  Stream<MatrixLivekitReceiverProbeEvent> get inProcessReceiverProbeEvents =>
      _onReceiverProbeEvent.stream;

  bool get isLocalPreviewProbeEnabled => _localPreviewProbe != null;

  bool get isLocalPreviewProbeStarting => _localPreviewProbeStarting;

  String? get localPreviewProbeError => _localPreviewProbeError;

  Map<String, Object?>? get localPreviewProbeSnapshot =>
      _localPreviewProbe?.snapshot;

  String get inProcessReceiverProbeDiagnosticLabel {
    if (_receiverProbeStarting) {
      return 'starting';
    }
    if (_receiverProbe != null) {
      return _receiverProbeError == null
          ? _receiverProbe!.snapshot.status ?? 'active'
          : 'active ($_receiverProbeError)';
    }
    if (_receiverProbeError != null) {
      return 'error: $_receiverProbeError';
    }
    return 'off';
  }

  Future<void> setInProcessReceiverProbeEnabled(
    bool enabled, {
    MatrixLivekitReceiverProbeMode mode =
        MatrixLivekitReceiverProbeMode.decodeOnly,
  }) {
    if (enabled && !_canProcessLiveKitRoomEvent) {
      _desiredReceiverProbeEnabled = false;
      return Future<void>.value();
    }
    _desiredReceiverProbeEnabled = enabled;
    _receiverProbeOperation = _receiverProbeOperation.catchError((_) {}).then((
      _,
    ) async {
      if (enabled) {
        if (!_desiredReceiverProbeEnabled || !_canProcessLiveKitRoomEvent) {
          _desiredReceiverProbeEnabled = false;
          return;
        }
        await _startInProcessReceiverProbe(mode: mode);
      } else {
        await _stopInProcessReceiverProbe();
      }
    });
    return _receiverProbeOperation;
  }

  void setInProcessReceiverProbeRendererVisible(bool visible) {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    _receiverProbe?.setRendererVisible(visible);
  }

  void recordInProcessReceiverProbeTextureReady({
    String source = 'in_process_receiver_probe_texture_view',
  }) {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    _receiverProbe?.recordRendererTextureReady(source: source);
  }

  void recordInProcessReceiverProbeUiPaint({
    String source = 'in_process_receiver_probe_flutter_paint',
  }) {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    _receiverProbe?.recordRendererUiPaint(source: source);
  }

  Future<void> setLocalPreviewProbeEnabled(bool enabled) {
    if (enabled && !_canProcessLiveKitRoomEvent) {
      _desiredLocalPreviewProbeEnabled = false;
      return Future<void>.value();
    }
    _desiredLocalPreviewProbeEnabled = enabled;
    _localPreviewProbeOperation = _localPreviewProbeOperation
        .catchError((_) {})
        .then((_) async {
          if (enabled) {
            if (!_desiredLocalPreviewProbeEnabled ||
                !_canProcessLiveKitRoomEvent) {
              _desiredLocalPreviewProbeEnabled = false;
              return;
            }
            await _startLocalPreviewProbe();
          } else {
            await _stopLocalPreviewProbe();
          }
        });
    return _localPreviewProbeOperation;
  }

  lk.LocalTrackPublication<lk.LocalVideoTrack>?
  _latestLocalScreenShareVideoPublicationWithTrack() {
    for (final publication in _localScreenShareVideoPublications().reversed) {
      if (publication.track != null) {
        return publication;
      }
    }
    return null;
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
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {
    PendingNativeCallCrashGuard? nativeCrashGuard;
    var clearNativeCrashGuard = true;
    try {
      final localParticipant = livekitRoom.localParticipant;
      if (state) {
        _initialMicrophoneEnableState.markDesiredMicrophoneMuted(
          stopOnMute: stopOnMute,
        );
        final participant = localParticipant;
        if (participant == null) {
          _notifyStateChanged();
          return;
        }
        final publication = participant.getTrackPublicationBySource(
          lk.TrackSource.microphone,
        );
        if (publication == null) {
          _notifyStateChanged();
          return;
        }
        final useWindowsSenderDetach = PlatformUtils.isWindows;
        // On Windows the sender, not `publication.muted`, decides whether
        // audio flows. Returning early on the flag alone leaves a hot mic
        // whenever the flag says muted but the sender is still attached.
        final alreadyNotSending =
            publication.muted &&
            (!useWindowsSenderDetach ||
                LivekitMicrophoneSenderGate.isDetached(publication));
        if (alreadyNotSending) {
          _notifyStateChanged();
          return;
        }
        nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
          source: useWindowsSenderDetach
              ? stopOnMute
                    ? 'matrix-livekit-native-call-action-microphone-sender-detach'
                    : 'matrix-livekit-native-call-action-microphone-ptt-sender-detach'
              : 'matrix-livekit-native-call-action-microphone-mute',
          actionKind: useWindowsSenderDetach
              ? stopOnMute
                    ? 'LiveKit microphone sender detach'
                    : 'LiveKit Push to Talk microphone sender detach'
              : 'LiveKit microphone mute',
        );
        if (useWindowsSenderDetach) {
          await _setMicrophoneSenderDetachedForWindows(
            publication,
            detached: true,
            reason: stopOnMute ? 'mute' : 'push_to_talk_release',
          );
        } else {
          await publication.mute(stopOnMute: stopOnMute);
        }
        _notifyStateChanged();
        return;
      } else {
        final audioReady = await IosCallAudioSession.prepareForCall(
          source: 'matrix-livekit-session',
        );
        if (!audioReady) {
          return;
        }
        final audioCaptureOptions = await _currentMicrophoneCaptureOptions();
        _initialMicrophoneEnableState.markDesiredMicrophoneEnabled(true);
        if (localParticipant == null) {
          return;
        }
        final publication = localParticipant.getTrackPublicationBySource(
          lk.TrackSource.microphone,
        );
        if (publication != null) {
          // The reattach used to be nested inside `if (publication.muted)`.
          // That is exactly the state the silent-mic defect does *not* leave
          // behind: any SDK-native unmute clears the publication flag without
          // reattaching the sender (`skipStopForTrackMute()` is true on
          // Windows, so `LocalTrack.unmute()` skips `restartTrack()`), so the
          // flag reads false while the sender carries nothing and unmute did
          // nothing at all. Gate on real sender state instead.
          final senderDetached =
              PlatformUtils.isWindows &&
              LivekitMicrophoneSenderGate.isDetached(publication);
          if (publication.muted || senderDetached) {
            if (PlatformUtils.isWindows) {
              nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
                source: stopOnMute
                    ? 'matrix-livekit-native-call-action-microphone-sender-reattach'
                    : 'matrix-livekit-native-call-action-microphone-ptt-sender-reattach',
                actionKind: stopOnMute
                    ? 'LiveKit microphone sender reattach'
                    : 'LiveKit Push to Talk microphone sender reattach',
              );
              await _setMicrophoneSenderDetachedForWindows(
                publication,
                detached: false,
                reason: stopOnMute ? 'unmute' : 'push_to_talk_press',
              );
            } else {
              if (stopOnMute) {
                nativeCrashGuard =
                    await PendingNativeCallCrashGuard.recordAction(
                      source:
                          'matrix-livekit-native-call-action-microphone-enable',
                      actionKind: 'LiveKit microphone enable',
                    );
              } else {
                nativeCrashGuard =
                    await PendingNativeCallCrashGuard.recordAction(
                      source:
                          'matrix-livekit-native-call-action-microphone-unmute',
                      actionKind: 'LiveKit microphone unmute',
                    );
              }
              await publication.unmute(stopOnMute: stopOnMute);
            }
          }
          _microphoneCaptureProfileSignature =
              NoiseSuppressionCaptureProfile.captureFrontendSignature(
                bypassVoiceProcessing:
                    IosCallAudioSession.shouldBypassVoiceProcessing,
              );
          NoiseSuppressionService.instance.scheduleHealthRefresh();
          // A device change made while muted is deferred:
          // `_refreshMicrophoneCaptureForNoiseSuppression` returns early while
          // `isMicrophoneMuted`. This unmute path resumes the EXISTING
          // publication and never applies the computed capture options, so
          // without this the user came back on the microphone they had
          // switched away from - selected in settings, silent in the call.
          // The helper no-ops when the device already matches and routes
          // through the same refresh queue, so it cannot race a suppression
          // change.
          unawaited(_refreshMicrophoneCaptureDeviceIfChanged());
          _notifyStateChanged();
          return;
        }
        nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
          source: 'matrix-livekit-native-call-action-microphone-enable',
          actionKind: 'LiveKit microphone enable',
        );
        clearNativeCrashGuard = await _enableRuntimeMicrophone(
          localParticipant,
          audioCaptureOptions: audioCaptureOptions,
          nativeActionGuard: nativeCrashGuard,
        );
      }
      _notifyStateChanged();
    } finally {
      if (clearNativeCrashGuard) {
        await nativeCrashGuard?.clear();
      }
    }
  }

  Future<void> _reconcileLocalMicrophoneMuteDrift(
    lk.LocalTrackPublication publication, {
    required String trigger,
  }) async {
    if (!_canProcessLiveKitRoomEvent ||
        !_isLocalMicrophoneAudioPublication(publication)) {
      return;
    }

    final senderDetached =
        PlatformUtils.isWindows &&
        LivekitMicrophoneSenderGate.isDetached(publication);
    final shouldMute = _initialMicrophoneEnableState
        .shouldReconcileMutedPublication(publicationMuted: publication.muted);
    // The unmute direction did not exist. Without it the reconciler could only
    // ever push the mic further off: a publication that came back muted, or
    // one whose sender was left detached behind an unmuted flag, was never
    // restored and the user stayed silent until they rejoined.
    final shouldUnmute =
        !shouldMute &&
        _initialMicrophoneEnableState.shouldReconcileUnmutedPublication(
          publicationMuted: publication.muted,
          senderDetached: senderDetached,
        );
    if (!shouldMute && !shouldUnmute) {
      return;
    }

    final stopOnMute = _initialMicrophoneEnableState.desiredMuteStopOnMute;
    Log.w(
      'LiveKit local microphone publication drift detected: '
      'trigger=$trigger direction=${shouldMute ? 'mute' : 'unmute'} '
      'publication_muted=${publication.muted} '
      'sender_attachment=${LivekitMicrophoneSenderGate.attachmentOf(publication).name} '
      'desired_enabled=${_initialMicrophoneEnableState.desiredMicrophoneEnabled} '
      'stop_on_mute=$stopOnMute',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    try {
      await setMicrophoneMute(shouldMute, stopOnMute: stopOnMute);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to reconcile local microphone mute after LiveKit publication drift',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  Future<void> _setMicrophoneSenderDetachedForWindows(
    lk.LocalTrackPublication publication, {
    required bool detached,
    required String reason,
  }) async {
    await LivekitMicrophoneSenderGate.setDetached(
      publication,
      detached: detached,
      reason: reason,
      source: 'matrix-livekit-session',
    );
  }

  Future<bool> _enableRuntimeMicrophone(
    lk.LocalParticipant participant, {
    required lk.AudioCaptureOptions audioCaptureOptions,
    required PendingNativeCallCrashGuard? nativeActionGuard,
  }) async {
    final stopwatch = Stopwatch()..start();
    final generation = _initialMicrophoneEnableState.generation;
    Log.i(
      'LiveKit runtime microphone enable starting: '
      'timeout_ms=${_runtimeMicrophoneEnableTimeout.inMilliseconds} '
      'generation=$generation',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );

    final enableFuture = participant.setMicrophoneEnabled(
      true,
      audioCaptureOptions: audioCaptureOptions,
    );

    try {
      if (PlatformUtils.isWindows) {
        await enableFuture.timeout(_runtimeMicrophoneEnableTimeout);
      } else {
        await enableFuture;
      }
      _appliedMicrophoneCaptureDeviceId = audioCaptureOptions.deviceId;
      if (!_shouldKeepRuntimeMicrophoneEnable(generation)) {
        await _rollbackStaleRuntimeMicrophoneEnable(
          participant,
          generation,
          stopwatch,
        );
        return true;
      }
      _logRuntimeMicrophoneEnableCompleted(stopwatch);
    } on TimeoutException catch (error, stackTrace) {
      if (!PlatformUtils.isWindows) {
        rethrow;
      }
      Log.onError(
        error,
        stackTrace,
        content:
            'LiveKit runtime microphone enable timed out on Windows; continuing while native publish settles',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      unawaited(
        _observeLateRuntimeMicrophoneEnable(
          enableFuture,
          stopwatch,
          nativeActionGuard,
          participant: participant,
          generation: generation,
        ),
      );
      return false;
    } catch (error, stackTrace) {
      if (!PlatformUtils.isWindows) {
        rethrow;
      }
      Log.onError(
        error,
        stackTrace,
        content: 'LiveKit runtime microphone enable failed on Windows',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }

    return true;
  }

  Future<void> _observeLateRuntimeMicrophoneEnable(
    Future<void> enableFuture,
    Stopwatch stopwatch,
    PendingNativeCallCrashGuard? nativeActionGuard, {
    required lk.LocalParticipant participant,
    required int generation,
  }) async {
    try {
      await enableFuture;
      if (!_shouldKeepRuntimeMicrophoneEnable(generation)) {
        await _rollbackStaleRuntimeMicrophoneEnable(
          participant,
          generation,
          stopwatch,
        );
        return;
      }
      _logRuntimeMicrophoneEnableCompleted(stopwatch, afterTimeout: true);
      _notifyStateChanged();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'LiveKit runtime microphone enable failed after Windows timeout',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    } finally {
      await nativeActionGuard?.clear();
    }
  }

  bool _shouldKeepRuntimeMicrophoneEnable(int generation) {
    return !_ending &&
        state != VoipState.ended &&
        _initialMicrophoneEnableState.shouldKeepEnabledForGeneration(
          generation,
        );
  }

  Future<void> _rollbackStaleRuntimeMicrophoneEnable(
    lk.LocalParticipant participant,
    int generation,
    Stopwatch stopwatch,
  ) async {
    stopwatch.stop();
    Log.w(
      'LiveKit runtime microphone enable completed but is stale; '
      'active=${_initialMicrophoneEnableState.isCallActive} '
      'desired_enabled=${_initialMicrophoneEnableState.desiredMicrophoneEnabled} '
      'generation=${_initialMicrophoneEnableState.generation} '
      'enable_generation=$generation '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    try {
      await _disableStaleRuntimeMicrophoneEnable(
        participant,
      ).timeout(_staleRuntimeMicrophoneDisableTimeout);
      Log.i(
        'LiveKit stale runtime microphone enable rollback completed',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to disable stale LiveKit runtime microphone enable after timeout',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  Future<void> _disableStaleRuntimeMicrophoneEnable(
    lk.LocalParticipant participant,
  ) async {
    if (PlatformUtils.isWindows) {
      final publication = participant.getTrackPublicationBySource(
        lk.TrackSource.microphone,
      );
      if (publication != null) {
        await _setMicrophoneSenderDetachedForWindows(
          publication,
          detached: true,
          reason: 'stale_runtime_enable',
        );
        return;
      }
    }

    await participant.setMicrophoneEnabled(false);
  }

  void _logRuntimeMicrophoneEnableCompleted(
    Stopwatch stopwatch, {
    bool afterTimeout = false,
  }) {
    stopwatch.stop();
    _microphoneCaptureProfileSignature =
        NoiseSuppressionCaptureProfile.captureFrontendSignature(
          bypassVoiceProcessing:
              IosCallAudioSession.shouldBypassVoiceProcessing,
        );
    NoiseSuppressionService.instance.scheduleHealthRefresh();
    Log.i(
      'LiveKit runtime microphone enable completed'
      '${afterTimeout ? ' after timeout' : ''}: '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    _logLocalMicrophonePublication(trigger: 'runtime_enable');
  }

  /// Logs the current microphone publication in the same shape as the
  /// screen-share and camera lines in [onLocalTrackPublished].
  ///
  /// Microphone publishes are otherwise absent from the logs entirely: the
  /// only local publish/unpublish log sites are room-event handlers, and the
  /// microphone is published before the session installs its room listener, so
  /// its event is dropped. Screen share and camera are published mid-call and
  /// therefore do appear, which is what made this gap look like a
  /// microphone-specific silence rather than a listener-timing one.
  void _logLocalMicrophonePublication({required String trigger}) {
    final publication = livekitRoom.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.microphone);
    if (publication == null) {
      Log.w(
        'LiveKit local track published: source=TrackSource.microphone '
        'result=absent trigger=$trigger',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      return;
    }

    Log.i(
      'LiveKit local track published: '
      '${_trackPublicationSummary(publication)} '
      'sender_attachment=${LivekitMicrophoneSenderGate.attachmentOf(publication).name} '
      'trigger=$trigger',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
  }

  Future<lk.AudioCaptureOptions> _currentMicrophoneCaptureOptions() async {
    final baseOptions =
        NoiseSuppressionCaptureProfile.buildLivekitAudioCaptureOptions(
          inputVolume:
              NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
                preferences.voipMicrophoneVolume.value,
              ),
          bypassVoiceProcessing:
              IosCallAudioSession.shouldBypassVoiceProcessing,
        );
    // A device-enumeration failure must not be able to block an unmute. It
    // used to propagate straight out of `setMicrophoneMute(false)`, so a
    // transient enumeration error left the user unable to turn their
    // microphone back on at all; falling back to the system default is always
    // better than not publishing.
    String? device;
    try {
      device = await WebrtcDefaultDevices.getDefaultMicrophoneId();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to resolve the preferred microphone; using the system default',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
    final options = device != null
        ? baseOptions.copyWith(deviceId: device)
        : baseOptions;
    Log.i(
      "LiveKit microphone capture options: "
      "${NoiseSuppressionCaptureProfile.callAudioInstrumentationSummary(callType: 'group-livekit', bypassVoiceProcessing: IosCallAudioSession.shouldBypassVoiceProcessing)} "
      "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(options)}",
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    return options;
  }

  void _syncMicrophoneNoiseSuppressionCaptureProfile() {
    if (!PlatformUtils.isWindows || _ending || state == VoipState.ended) {
      return;
    }

    final captureProfileSignature =
        NoiseSuppressionCaptureProfile.captureFrontendSignature(
          bypassVoiceProcessing:
              IosCallAudioSession.shouldBypassVoiceProcessing,
        );
    if (captureProfileSignature == _microphoneCaptureProfileSignature) {
      return;
    }

    _queueMicrophoneCaptureRefresh(captureProfileSignature);
  }

  void _queueMicrophoneCaptureRefresh(String captureProfileSignature) {
    _noiseSuppressionCaptureRefresh = _noiseSuppressionCaptureRefresh
        .catchError((_) {})
        .then(
          (_) => _refreshMicrophoneCaptureForNoiseSuppression(
            captureProfileSignature,
          ),
        );
  }

  /// Republishes the microphone when the user picks a different input device
  /// mid-call.
  ///
  /// The pickers only write the preference and call `selectAudioInput`, which
  /// does not touch an already-published track: the published track keeps the
  /// `deviceId` it was created with, so the user keeps talking into the old
  /// microphone. The noise-suppression signature cannot rescue this either -
  /// it is built from suppression settings only and never includes the device
  /// id - so the device has to be compared on its own.
  void _handleMicrophoneInputDeviceChanged() {
    if (_ending || state == VoipState.ended) {
      return;
    }

    unawaited(_refreshMicrophoneCaptureDeviceIfChanged());
  }

  /// How long to wait for the join-time enable to settle before reconciling
  /// anyway. Every settle path marks the state, so this only fires if one is
  /// missed; it mirrors the join's own enable timeouts.
  static const _initialJoinSenderReconcileFallback = Duration(seconds: 15);

  /// BUG-320. Reconciles the join-time microphone publication's RTP sender
  /// once, AFTER the join enable has settled.
  ///
  /// On Windows `sender.replaceTrack(null)` is invisible to LiveKit and
  /// `skipStopForTrackMute()` is true, so the join can leave the publication
  /// with its sender detached while `muted` reads false: the UI shows a live
  /// mic and nobody hears the user. `_reconcileLocalMicrophoneMuteDrift`
  /// repairs exactly that state, but it ran only on `room_reconnected` and
  /// after a capture refresh - never on the join itself - so a fresh join
  /// stayed silent until a device change or a restart. Sequenced on
  /// `initialEnableSettled` rather than run from the constructor: the backend
  /// enable can settle seconds after the join on Windows, and reconciling
  /// underneath it would race the very publication it is checking.
  ///
  /// The attachment line is logged whether or not drift is found, so a device
  /// capture establishes the join-time state instead of inferring it.
  Future<void> _reconcileInitialJoinMicrophoneSender() async {
    try {
      await _initialMicrophoneEnableState.initialEnableSettled.timeout(
        _initialJoinSenderReconcileFallback,
      );
    } on TimeoutException {
      Log.w(
        'initial_join_microphone_sender event=settle_timeout '
        'waited_ms=${_initialJoinSenderReconcileFallback.inMilliseconds}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    final publication = livekitRoom.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.microphone);
    if (publication == null) {
      Log.i(
        'initial_join_microphone_sender event=no_publication '
        'enable_outcome=${_initialMicrophoneEnableState.initialEnableOutcome ?? 'unsettled'}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      return;
    }
    Log.i(
      'initial_join_microphone_sender event=checked '
      'enable_outcome=${_initialMicrophoneEnableState.initialEnableOutcome ?? 'unsettled'} '
      'sender_attachment=${LivekitMicrophoneSenderGate.attachmentOf(publication).name} '
      'publication_muted=${publication.muted} '
      'desired_enabled=${_initialMicrophoneEnableState.desiredMicrophoneEnabled}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    await _reconcileLocalMicrophoneMuteDrift(
      publication,
      trigger: 'initial_join',
    );
  }

  /// Records the device the join-time microphone enable used.
  ///
  /// That enable runs in `MatrixLivekitBackend` before this session exists, so
  /// without seeding it here the first device change would compare against
  /// `null` and republish even when nothing actually changed.
  Future<void> _seedAppliedMicrophoneCaptureDevice() async {
    if (_appliedMicrophoneCaptureDeviceId != null) {
      return;
    }

    try {
      final deviceId = await WebrtcDefaultDevices.getDefaultMicrophoneId();
      if (_ending || state == VoipState.ended) {
        return;
      }
      _appliedMicrophoneCaptureDeviceId ??= deviceId;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to record the microphone device used to join the call',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  Future<void> _refreshMicrophoneCaptureDeviceIfChanged() async {
    if (!_initialMicrophoneEnableState.isCallActive ||
        _ending ||
        state == VoipState.ended) {
      return;
    }

    String? deviceId;
    try {
      deviceId = await WebrtcDefaultDevices.getDefaultMicrophoneId();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to resolve the selected microphone after a device change',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      return;
    }

    final deviceChanged = deviceId != _appliedMicrophoneCaptureDeviceId;
    final publication = livekitRoom.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.microphone);
    final senderDetached =
        PlatformUtils.isWindows &&
        publication != null &&
        LivekitMicrophoneSenderGate.isDetached(publication);
    if (!LivekitMicrophoneSenderGate.shouldRepublishForDeviceChange(
      deviceChanged: deviceChanged,
      senderDetached: senderDetached,
    )) {
      return;
    }

    Log.i(
      'LiveKit microphone input device changed mid-call; republishing: '
      'applied_device=${_appliedMicrophoneCaptureDeviceId == null ? 'default' : 'selected'} '
      'requested_device=${deviceId == null ? 'default' : 'selected'} '
      'device_changed=$deviceChanged sender_detached=$senderDetached',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );

    // Reuse the capture-refresh queue so a device change and a suppression
    // change cannot republish the microphone concurrently.
    //
    // Queue the LIVE frontend signature, not the stored marker.
    // `_shouldContinueMicrophoneCaptureRefresh` compares the live signature
    // against whatever is passed here, so passing the stored field made the
    // refresh abort whenever the two had diverged - and
    // `_restoreMicrophoneAfterAbandonedCaptureRefresh` deliberately sets that
    // field to '' to force the next suppression change to re-run. After an
    // abandoned refresh the device change was therefore dropped silently, and
    // the user kept talking into the previous microphone until some unrelated
    // suppression change happened to repair it.
    _queueMicrophoneCaptureRefresh(
      NoiseSuppressionCaptureProfile.captureFrontendSignature(
        bypassVoiceProcessing: IosCallAudioSession.shouldBypassVoiceProcessing,
      ),
    );
  }

  Future<void> _refreshMicrophoneCaptureForNoiseSuppression(
    String expectedCaptureProfileSignature,
  ) async {
    if (_ending || state == VoipState.ended) {
      return;
    }

    final generation = _initialMicrophoneEnableState.generation;
    if (!_shouldKeepRuntimeMicrophoneEnable(generation)) {
      return;
    }

    final localParticipant = livekitRoom.localParticipant;
    // `localParticipant.isMuted` reads an unfiltered audio publication list,
    // so while sharing screen audio it can report the screen-share track's
    // state and abandon a refresh the microphone actually needed.
    if (localParticipant == null || isMicrophoneMuted) {
      return;
    }

    final audioCaptureOptions = await _currentMicrophoneCaptureOptions();
    if (!_shouldContinueMicrophoneCaptureRefresh(
      generation: generation,
      expectedCaptureProfileSignature: expectedCaptureProfileSignature,
    )) {
      return;
    }

    final refreshStopwatch = Stopwatch()..start();
    var microphoneDisabled = false;
    try {
      Log.i(
        "Refreshing microphone capture profile; "
        "${NoiseSuppressionCaptureProfile.captureFrontendSummary(bypassVoiceProcessing: IosCallAudioSession.shouldBypassVoiceProcessing)} "
        "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(audioCaptureOptions)}",
      );
      await localParticipant.setMicrophoneEnabled(false);
      microphoneDisabled = true;
      if (!_initialMicrophoneEnableState
          .shouldReenableAfterCaptureRefreshRemoval(generation)) {
        // A current profile token is deliberately not part of this decision.
        // Another profile change is queued behind this operation; abandoning
        // here would leave the user's still-active microphone unpublished.
        return;
      }
      await localParticipant.setMicrophoneEnabled(
        true,
        audioCaptureOptions: audioCaptureOptions,
      );
      microphoneDisabled = false;
      if (!_shouldContinueMicrophoneCaptureRefresh(
        generation: generation,
        expectedCaptureProfileSignature: expectedCaptureProfileSignature,
      )) {
        if (!_shouldKeepRuntimeMicrophoneEnable(generation)) {
          await _rollbackStaleRuntimeMicrophoneEnable(
            localParticipant,
            generation,
            refreshStopwatch,
          );
        }
        return;
      }
      _microphoneCaptureProfileSignature = expectedCaptureProfileSignature;
      _appliedMicrophoneCaptureDeviceId = audioCaptureOptions.deviceId;
      NoiseSuppressionService.instance.scheduleHealthRefresh();
      _notifyStateChanged();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh microphone capture for RNNoise profile',
      );
    } finally {
      if (microphoneDisabled) {
        await _restoreMicrophoneAfterAbandonedCaptureRefresh();
      } else {
        // `setMicrophoneEnabled(true)` routes to `publication.unmute()`, which
        // on Windows never reattaches the RTP sender the app detached. Without
        // this the refresh silently leaves the mic published, unmuted, and
        // sending nothing.
        await _reconcileMicrophoneSenderAfterCaptureRefresh(localParticipant);
      }
    }
  }

  /// Restores the microphone after a capture refresh gave up between its
  /// disable and its re-enable.
  Future<void> _restoreMicrophoneAfterAbandonedCaptureRefresh() async {
    if (!_initialMicrophoneEnableState.isCallActive ||
        !_initialMicrophoneEnableState.desiredMicrophoneEnabled ||
        _ending ||
        state == VoipState.ended) {
      return;
    }

    Log.w(
      'Microphone capture refresh was abandoned after disabling the '
      'microphone; restoring the user\'s desired unmuted state',
      category: LogCategory.livekit,
      source: 'matrix-livekit-session',
    );
    try {
      await setMicrophoneMute(false);
      // `setMicrophoneMute(false)` stamps the current frontend signature as
      // applied, but this refresh never applied it. Clear the marker so the
      // next suppression change re-runs rather than being skipped as
      // already-current.
      _microphoneCaptureProfileSignature = '';
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to restore the microphone after an abandoned capture refresh',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
    }
  }

  Future<void> _reconcileMicrophoneSenderAfterCaptureRefresh(
    lk.LocalParticipant participant,
  ) async {
    if (!PlatformUtils.isWindows || _ending || state == VoipState.ended) {
      return;
    }

    final publication = participant.getTrackPublicationBySource(
      lk.TrackSource.microphone,
    );
    if (publication == null) {
      return;
    }

    await _reconcileLocalMicrophoneMuteDrift(
      publication,
      trigger: 'capture_profile_refresh',
    );
  }

  bool _shouldContinueMicrophoneCaptureRefresh({
    required int generation,
    required String expectedCaptureProfileSignature,
  }) {
    return _shouldKeepRuntimeMicrophoneEnable(generation) &&
        NoiseSuppressionCaptureProfile.captureFrontendSignature(
              bypassVoiceProcessing:
                  IosCallAudioSession.shouldBypassVoiceProcessing,
            ) ==
            expectedCaptureProfileSignature;
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

  Future<MatrixLivekitReceiverProbeCredentials>
  _requestReceiverProbeCredentials({required String runId}) async {
    final matrixClient = room.matrixRoom.client;
    final userId = matrixClient.userID;
    final deviceId = matrixClient.deviceID;
    if (userId == null || deviceId == null) {
      throw Exception(
        'Cannot start receiver probe without Matrix user and device '
        'identifiers.',
      );
    }
    if (foci.isEmpty) {
      throw Exception(
        'Cannot start receiver probe without a LiveKit focus URL.',
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
        'Cannot start receiver probe without an HTTPS LiveKit focus URL.',
      );
    }

    Log.i(
      'Receiver probe credential request starting '
      'run=$runId focusHost=${selectedFocus.host}',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
    final openIdToken = await matrixClient
        .requestOpenIdToken(userId, {})
        .timeout(_serverAudioLoopbackTokenTimeout);
    Log.i(
      'Receiver probe OpenID token acquired '
      'run=$runId expiresIn=${openIdToken.expiresIn}',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
    final focusBase = selectedFocus.toString().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$focusBase/probe/get_token');
    final body = {
      'room_id': room.matrixRoom.id,
      'slot_id': 'm.call#ROOM',
      'run_id': runId,
      'openid_token': {
        'matrix_server_name': openIdToken.matrixServerName,
        'access_token': openIdToken.accessToken,
        'expires_in': openIdToken.expiresIn,
        'token_type': 'Bearer',
      },
      'member': {
        'id': MatrixVoipRoomComponent.callMemberStateKeyFor(
          userId: userId,
          deviceId: deviceId,
        ),
        'claimed_user_id': userId,
        'claimed_device_id': deviceId,
      },
      MatrixVoipRoomComponent.callClientInfoKey:
          BuildConfig.matrixClientMetadata,
    };

    final result = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_serverAudioLoopbackTokenTimeout);
    Log.i(
      'Receiver probe token request completed '
      'run=$runId status=${result.statusCode}',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
    if (result.statusCode != 200) {
      throw Exception(
        'Failed to get receiver probe token: HTTP ${result.statusCode}',
      );
    }

    final data = jsonDecode(result.body) as Map<String, dynamic>;
    final sfuUrl = data['url'];
    final jwt = data['jwt'];
    final probeIdentity = data['probe_identity'];
    final expiresIn = data['expires_in'];
    if (sfuUrl is! String || jwt is! String || probeIdentity is! String) {
      throw Exception('Receiver probe token response was malformed.');
    }
    Log.i(
      'Receiver probe credentials decoded '
      'run=$runId expiresIn=${expiresIn is int ? expiresIn : 'unknown'}s',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );

    return MatrixLivekitReceiverProbeCredentials(
      sfuUrl: sfuUrl,
      jwt: jwt,
      probeIdentity: probeIdentity,
      expiresInSeconds: expiresIn is int ? expiresIn : null,
    );
  }

  Future<void> writeReceiverProbeCredentialsToPipe({
    required String controlPipe,
  }) async {
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    if (!preferences.developerMode.value) {
      throw StateError('developer mode required');
    }
    final normalizedPipe = controlPipe.trim();
    if (normalizedPipe.isEmpty) {
      throw StateError('External receiver probe control pipe is empty.');
    }

    final publisherIdentity = livekitRoom.localParticipant?.identity;
    if (publisherIdentity == null) {
      throw StateError('LiveKit publisher identity is unavailable.');
    }

    final runId = _newExternalReceiverProbeRunId();
    Log.i(
      'External receiver probe credential handoff starting run=$runId',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );

    final credentials = await _requestReceiverProbeCredentials(runId: runId);
    if (!_canProcessLiveKitRoomEvent) {
      return;
    }
    await writeReceiverProbeCredentialEnvelope(
      controlPipe: normalizedPipe,
      envelope: <String, Object?>{
        'sfu_url': credentials.sfuUrl,
        'jwt': credentials.jwt,
        'room_id': room.matrixRoom.id,
        'publisher_identity': publisherIdentity,
        'probe_identity': credentials.probeIdentity,
        'expires_in': credentials.expiresInSeconds,
        'issued_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
    );
    Log.i(
      'External receiver probe credential handoff completed run=$runId '
      'expiresIn=${credentials.expiresInSeconds ?? 'unknown'}s',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
  }

  Future<void> _startLocalPreviewProbe() async {
    if (!_desiredLocalPreviewProbeEnabled || !_canProcessLiveKitRoomEvent) {
      _desiredLocalPreviewProbeEnabled = false;
      return;
    }
    if (_localPreviewProbe != null || _localPreviewProbeStarting) {
      return;
    }
    if (!preferences.developerMode.value) {
      _localPreviewProbeError = 'developer mode required';
      _notifyLiveKitProbeStateChanged();
      return;
    }

    _localPreviewProbeStarting = true;
    _localPreviewProbeError = null;
    final startGeneration = ++_localPreviewProbeGeneration;
    Log.i(
      'Local preview probe start requested',
      category: LogCategory.webrtc,
      source: 'local-preview-probe',
    );
    _notifyLiveKitProbeStateChanged();

    MatrixLivekitLocalPreviewProbeController? probe;
    StreamSubscription<MatrixLivekitReceiverProbeEvent>? probeEventsSub;
    try {
      final publisherIdentity = livekitRoom.localParticipant?.identity;
      if (publisherIdentity == null) {
        throw Exception('LiveKit publisher identity is unavailable.');
      }

      final publication = _latestLocalScreenShareVideoPublicationWithTrack();
      if (publication == null) {
        throw Exception(
          'No local screen-share video publication is available for '
          'local preview probe.',
        );
      }

      final runId = _newLocalPreviewProbeRunId();
      probe = MatrixLivekitLocalPreviewProbeController(
        options: MatrixLivekitLocalPreviewProbeOptions(
          runId: runId,
          roomId: room.matrixRoom.id,
          publisherIdentity: publisherIdentity,
        ),
      );
      probeEventsSub = probe.events.listen(_onLocalPreviewProbeEvent);
      await probe.start(publication);
      if (!_canProcessLiveKitRoomEvent ||
          !_desiredLocalPreviewProbeEnabled ||
          !_localPreviewProbeStarting ||
          startGeneration != _localPreviewProbeGeneration) {
        await _cancelLiveKitSessionSubscription(
          probeEventsSub,
          content:
              'Recovered LiveKit local-preview probe subscription cancel failure',
          source: 'local-preview-probe-subscription',
        );
        await _runMatrixLivekitVoipSessionCleanup(
          operation: 'local-preview-probe-dispose-after-abandoned-start',
          cleanup: probe.dispose,
        );
        return;
      }

      _localPreviewProbe = probe;
      _localPreviewProbeEventsSub = probeEventsSub;
      Log.i(
        'Local preview probe started run=$runId '
        'source=${publication.source.name}',
        category: LogCategory.webrtc,
        source: 'local-preview-probe',
      );
    } catch (error, stackTrace) {
      if (_canProcessLiveKitRoomEvent) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to start local preview probe',
        );
        _localPreviewProbeError = error.toString();
      }
      _localPreviewProbe = null;
      _localPreviewProbeEventsSub = null;
      await _cancelLiveKitSessionSubscription(
        probeEventsSub,
        content:
            'Recovered LiveKit local-preview probe subscription cancel failure',
        source: 'local-preview-probe-subscription',
      );
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'local-preview-probe-dispose-after-start-failure',
        cleanup: probe?.dispose,
      );
    } finally {
      _localPreviewProbeStarting = false;
      _notifyLiveKitProbeStateChanged();
    }
  }

  Future<void> _stopLocalPreviewProbe({
    bool notify = true,
    bool preserveDesired = false,
  }) async {
    if (!preserveDesired) {
      _desiredLocalPreviewProbeEnabled = false;
    }
    final probe = _localPreviewProbe;
    final probeEventsSub = _localPreviewProbeEventsSub;
    _localPreviewProbe = null;
    _localPreviewProbeEventsSub = null;
    _localPreviewProbeStarting = false;
    _localPreviewProbeGeneration++;
    _localPreviewProbeStopping = true;

    try {
      final cleanupSucceeded = await _runMatrixLivekitVoipSessionCleanup(
        operation: 'local-preview-probe-dispose',
        cleanup: () async {
          await _cancelLiveKitSessionSubscription(
            probeEventsSub,
            content:
                'Recovered LiveKit local-preview probe subscription cancel failure',
            source: 'local-preview-probe-subscription',
          );
          await probe?.dispose();
        },
      );
      if (!cleanupSucceeded) {
        _localPreviewProbeError = 'Failed to stop local preview probe cleanly';
      }
    } finally {
      _localPreviewProbeStopping = false;
      if (notify) {
        _notifyLiveKitProbeStateChanged();
      }
    }
  }

  Future<void> _restartLocalPreviewProbeAfterPublicationChange() async {
    if (!_desiredLocalPreviewProbeEnabled) {
      _notifyLiveKitProbeStateChanged();
      return;
    }

    await _stopLocalPreviewProbe(notify: false, preserveDesired: true);
    if (!_desiredLocalPreviewProbeEnabled || !_canProcessLiveKitRoomEvent) {
      _notifyLiveKitProbeStateChanged();
      return;
    }

    await _startLocalPreviewProbe();
  }

  void _onLocalPreviewProbeEvent(MatrixLivekitReceiverProbeEvent event) {
    if (_localPreviewProbeStopping || !_canProcessLiveKitRoomEvent) {
      return;
    }
    _localPreviewProbeError = null;
    Log.i(
      'Local preview probe event ${jsonEncode(event.toJson())}',
      category: LogCategory.webrtc,
      source: 'local-preview-probe',
    );
    if (!_notifyReceiverProbeEvent(event)) {
      return;
    }
    _notifyLiveKitProbeStateChanged();
  }

  String _newLocalPreviewProbeRunId() {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'local-preview-$stamp';
  }

  Future<void> _startInProcessReceiverProbe({
    required MatrixLivekitReceiverProbeMode mode,
  }) async {
    if (!_desiredReceiverProbeEnabled || !_canProcessLiveKitRoomEvent) {
      _desiredReceiverProbeEnabled = false;
      return;
    }
    if (_receiverProbe != null || _receiverProbeStarting) {
      return;
    }
    if (!preferences.developerMode.value) {
      _receiverProbeError = 'developer mode required';
      _notifyLiveKitProbeStateChanged();
      return;
    }

    _receiverProbeStarting = true;
    _receiverProbeError = null;
    final startGeneration = ++_receiverProbeGeneration;
    Log.i(
      'In-process receiver probe start requested mode=${mode.label}',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
    _notifyLiveKitProbeStateChanged();

    MatrixLivekitReceiverProbeController? probe;
    StreamSubscription<MatrixLivekitReceiverProbeEvent>? probeEventsSub;
    try {
      final publisherIdentity = livekitRoom.localParticipant?.identity;
      if (publisherIdentity == null) {
        throw Exception('LiveKit publisher identity is unavailable.');
      }

      final runId = _newInProcessReceiverProbeRunId();
      final credentials = await _requestReceiverProbeCredentials(runId: runId);
      if (!_canProcessLiveKitRoomEvent ||
          !_desiredReceiverProbeEnabled ||
          !_receiverProbeStarting ||
          startGeneration != _receiverProbeGeneration) {
        return;
      }

      probe = MatrixLivekitReceiverProbeController(
        options: MatrixLivekitReceiverProbeOptions(
          runId: runId,
          roomId: room.matrixRoom.id,
          publisherIdentity: publisherIdentity,
          mode: mode,
          connectTimeout: _receiverProbeConnectTimeout,
        ),
      );
      probeEventsSub = probe.events.listen(_onInProcessReceiverProbeEvent);
      Log.i(
        'In-process receiver probe connecting run=$runId '
        'timeout=${_receiverProbeConnectTimeout.inSeconds}s',
        category: LogCategory.webrtc,
        source: 'receiver-probe',
      );
      await probe.start(credentials);
      if (!_canProcessLiveKitRoomEvent ||
          !_desiredReceiverProbeEnabled ||
          !_receiverProbeStarting ||
          startGeneration != _receiverProbeGeneration) {
        await _cancelLiveKitSessionSubscription(
          probeEventsSub,
          content:
              'Recovered LiveKit receiver probe subscription cancel failure',
          source: 'receiver-probe-subscription',
        );
        await _runMatrixLivekitVoipSessionCleanup(
          operation: 'receiver-probe-dispose-after-abandoned-start',
          cleanup: probe.dispose,
        );
        return;
      }

      _receiverProbe = probe;
      _receiverProbeEventsSub = probeEventsSub;
      Log.i(
        'In-process receiver probe started '
        'run=$runId mode=${mode.label} '
        'expiresIn=${credentials.expiresInSeconds ?? 'unknown'}s',
        category: LogCategory.webrtc,
        source: 'receiver-probe',
      );
    } catch (error, stackTrace) {
      if (_canProcessLiveKitRoomEvent) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to start in-process receiver probe',
        );
        _receiverProbeError = error.toString();
      }
      _receiverProbe = null;
      _receiverProbeEventsSub = null;
      await _cancelLiveKitSessionSubscription(
        probeEventsSub,
        content: 'Recovered LiveKit receiver probe subscription cancel failure',
        source: 'receiver-probe-subscription',
      );
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'receiver-probe-dispose-after-start-failure',
        cleanup: probe?.dispose,
      );
    } finally {
      _receiverProbeStarting = false;
      _notifyLiveKitProbeStateChanged();
    }
  }

  Future<void> _stopInProcessReceiverProbe({bool notify = true}) async {
    _desiredReceiverProbeEnabled = false;
    final probe = _receiverProbe;
    final probeEventsSub = _receiverProbeEventsSub;
    _receiverProbe = null;
    _receiverProbeEventsSub = null;
    _receiverProbeStarting = false;
    _receiverProbeGeneration++;
    _receiverProbeStopping = true;

    try {
      final cleanupSucceeded = await _runMatrixLivekitVoipSessionCleanup(
        operation: 'receiver-probe-dispose',
        cleanup: () async {
          await _cancelLiveKitSessionSubscription(
            probeEventsSub,
            content:
                'Recovered LiveKit receiver probe subscription cancel failure',
            source: 'receiver-probe-subscription',
          );
          await probe?.dispose();
        },
      );
      if (!cleanupSucceeded) {
        _receiverProbeError =
            'Failed to stop in-process receiver probe cleanly';
      }
    } finally {
      _receiverProbeStopping = false;
      if (notify) {
        _notifyLiveKitProbeStateChanged();
      }
    }
  }

  void _onInProcessReceiverProbeEvent(MatrixLivekitReceiverProbeEvent event) {
    if (_receiverProbeStopping || !_canProcessLiveKitRoomEvent) {
      return;
    }
    _receiverProbeError = null;
    Log.i(
      'In-process receiver probe event ${jsonEncode(event.toJson())}',
      category: LogCategory.webrtc,
      source: 'receiver-probe',
    );
    if (!_notifyReceiverProbeEvent(event)) {
      return;
    }
    _notifyLiveKitProbeStateChanged();
  }

  String _newInProcessReceiverProbeRunId() {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'in-process-receiver-$stamp';
  }

  String _newExternalReceiverProbeRunId() {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'external-receiver-$stamp';
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
        await _runMatrixLivekitVoipSessionCleanup(
          operation:
              'server-audio-loopback-listener-dispose-after-abandoned-start',
          cleanup: loopbackListener.dispose,
        );
        await _runMatrixLivekitVoipSessionCleanup(
          operation:
              'server-audio-loopback-room-disconnect-after-abandoned-start',
          cleanup: loopbackRoom.disconnect,
        );
        await _runMatrixLivekitVoipSessionCleanup(
          operation: 'server-audio-loopback-room-dispose-after-abandoned-start',
          cleanup: loopbackRoom.dispose,
        );
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
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'server-audio-loopback-listener-dispose-after-start-failure',
        cleanup: loopbackListener?.dispose,
      );
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'server-audio-loopback-room-disconnect-after-start-failure',
        cleanup: loopbackRoom?.disconnect,
      );
      await _runMatrixLivekitVoipSessionCleanup(
        operation: 'server-audio-loopback-room-dispose-after-start-failure',
        cleanup: loopbackRoom?.dispose,
      );
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
      final listenerCleanupSucceeded =
          await _runMatrixLivekitVoipSessionCleanup(
            operation: 'server-audio-loopback-listener-dispose',
            cleanup: loopbackListener?.dispose,
          );
      final roomDisconnectSucceeded = await _runMatrixLivekitVoipSessionCleanup(
        operation: 'server-audio-loopback-room-disconnect',
        cleanup: loopbackRoom?.disconnect,
      );
      final roomDisposeSucceeded = await _runMatrixLivekitVoipSessionCleanup(
        operation: 'server-audio-loopback-room-dispose',
        cleanup: loopbackRoom?.dispose,
      );
      if (!listenerCleanupSucceeded ||
          !roomDisconnectSucceeded ||
          !roomDisposeSucceeded) {
        _serverAudioLoopbackError =
            'Failed to stop server audio loopback cleanly';
      }
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
      unawaited(
        _runMatrixLivekitVoipSessionPublicationOperation(
          operation: 'server-audio-loopback-track-published-subscribe',
          publicationOperation: event.publication.subscribe,
        ),
      );
    }
  }

  void _onServerAudioLoopbackTrackSubscribed(lk.TrackSubscribedEvent event) {
    if (!_desiredServerAudioLoopbackEnabled ||
        event.participant.identity != livekitRoom.localParticipant?.identity ||
        !_isServerAudioLoopbackMicrophone(event.publication)) {
      unawaited(
        _runMatrixLivekitVoipSessionPublicationOperation(
          operation: 'server-audio-loopback-unselected-track-unsubscribe',
          publicationOperation: event.publication.unsubscribe,
        ),
      );
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
          unawaited(
            _runMatrixLivekitVoipSessionPublicationOperation(
              operation: 'server-audio-loopback-existing-track-subscribe',
              publicationOperation: publication.subscribe,
            ),
          );
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

  /// Emits on [onStateChanged], ignoring the emit once the session's
  /// controllers have been closed.
  ///
  /// Every state-change emit in this class goes through here: the controller is
  /// closed by [dispose], and an `add` after close throws.
  void _notifyStateChanged() {
    if (!_stateChanged.isClosed) {
      _stateChanged.add(());
    }
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    final wasSharing = isSharingScreen;
    final requestedProfile = _screenShareProfile();
    final nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
      source: 'matrix-livekit-native-call-action-screen-share-start',
      actionKind: 'LiveKit screen share start',
    );
    try {
      await _setScreenShareWithProfile(source, requestedProfile);
      if (!wasSharing &&
          _localStreamCueState.onDeliberateStart(
            shareActive: isSharingScreen,
          )) {
        unawaited(_announceStreamLifecycleCue(StreamLifecycleCue.start));
      }
    } finally {
      _announceEndCueIfShareCleared();
      await nativeCrashGuard?.clear();
    }
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

    final videoSource = source is ShareCaptureSource
        ? source.videoSource
        : source;
    final useD3d11StreamTestPublishGuard =
        PlatformUtils.isWindows &&
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
      await _setScreenShareWithProfile(
        source,
        requestedProfile,
        windowsCaptureBackendMode: windowsCaptureBackendMode,
        windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
        windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
        restartSharedAudio: false,
        awaitPostPublishSenderLimits: false,
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
    final effectiveNativeFramePacingEnabled =
        PlatformUtils.isWindows &&
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
      _notifyStateChanged();
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
      _notifyStateChanged();
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
    final gpuPipelineTestModeForcedGameCapture =
        _gpuPipelineTestModeEnabled &&
        windowsCaptureBackendMode == null &&
        useExperimentalGameCaptureBackend;
    final automaticGameCaptureBackend =
        !gpuPipelineTestModeForcedGameCapture &&
        isAutomaticWindowsGameCaptureBackend(
          requestedMode: windowsCaptureBackendMode,
          effectiveMode: effectiveWindowsCaptureBackendMode,
        );
    final gameCaptureAdjustedProfile = publishProfile
        .withWindowsGameCaptureCadenceCompatibility(
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
    if (useExperimentalGameCaptureBackend &&
        !publishProfile.hardwareEncodeFirst) {
      final previousCodec = publishProfile.codec;
      final previousMaxBitrate = publishProfile.mainLayer.maxBitrateBps;
      publishProfile = publishProfile.withHardwareEncodingPreference();
      if (updateRequestedProfile) {
        _requestedScreenShareProfile = publishProfile;
      }
      _activeScreenShareProfile = publishProfile;
      Log.i(
        'D3D11 game-hook screen-share hardware encode preference applied: '
        'profile=${requestedProfile.label} '
        'sourceIdHash=${shortShareSourceIdHash(src.id)} '
        'codec=$previousCodec->${publishProfile.codec} '
        'maxBitrate=$previousMaxBitrate->'
        '${publishProfile.mainLayer.maxBitrateBps} '
        'reason=game_hook_fixed_resolution_hardware_encode',
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
      "${_diagnosticsProfileDetails(publishProfile, preserveGameCaptureResolution: useExperimentalGameCaptureBackend)}",
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
      final message =
          'Automatic D3D11 game-hook screen share fallback: '
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
      captureScreenAudio:
          !PlatformUtils.isWindows &&
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
        _notifyStateChanged();
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
        content:
            'Failed to create LiveKit screen-share tracks '
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
        _notifyStateChanged();
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
            guardPrePublication:
                _streamTestScreenSharePublishInProgress &&
                useExperimentalGameCaptureBackend,
            sourceTypeLabel: sourceTypeLabel,
            sourceIdHash: shortShareSourceIdHash(src.id),
            windowsCaptureBackendMode: effectiveWindowsCaptureBackendMode,
            windowsCaptureDirtyRegionMode:
                effectiveWindowsCaptureDirtyRegionMode,
            windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
            nativeFramePacingEnabled: effectiveNativeFramePacingEnabled,
            gameCaptureProcessId: gameCaptureProcessId,
            preserveGameCaptureResolution: useExperimentalGameCaptureBackend,
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
    } else if (postPublishSenderLimitsTimeout != null) {
      unawaited(
        _applyPostPublishSenderLimitsInBackground(
          publishProfile,
          localPublications: List.unmodifiable(publishedPublications),
          timeout: postPublishSenderLimitsTimeout,
        ),
      );
    }

    // Starting a share while one is already running used to overwrite this
    // field and nothing else, which orphaned the outgoing share twice over:
    // its native capture kept running, and because the shared-audio
    // publication and track were single fields, _publishWindowsSharedAudio
    // below overwrote its publication without ever removing it from the room.
    // Listeners went on hearing the FIRST app that was ever shared with audio,
    // no matter what was targeted afterwards.
    //
    // Those fields are now keyed, but that is not what closes this: one key is
    // still in use, so a second share would still overwrite the entry. The
    // teardown below is what closes it, and it stays load-bearing until the
    // caller registers a key per share.
    //
    // Torn down here, before the new share publishes over those fields, and in
    // the same order stopScreenshare() uses: unpublish, then stop the session.
    final replacedShareSession = _currentShareSession;
    _currentShareSession = shareSource?.shareSession;
    if (replacedShareSession != null &&
        !identical(replacedShareSession, _currentShareSession)) {
      Log.i(
        'Replacing an active screen share; releasing the outgoing shared '
        'audio: ${replacedShareSession.diagnosticsSummary().toLogLine()}',
      );
      await _releaseReplacedScreenShare(
        releasePublication: () =>
            _stopWindowsSharedAudioPublication(replacedShareSession),
        stopSession: replacedShareSession.stop,
      );
    }

    _rememberScreenSharePublish(
      source,
      effectiveWindowsCaptureBackendMode,
      effectiveWindowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode,
      effectiveNativeFramePacingEnabled,
    );
    if (useExperimentalGameCaptureBackend && !dummyNv12LiveSender) {
      // The D3D11 hook can attach to a windowed game and come up black or
      // frameless with the track creation itself succeeding, which users
      // could previously only fix by stopping and restarting the stream.
      // Watch the sender frame counters shortly after publish and fall back
      // to the legacy capturer automatically when no frames are flowing.
      unawaited(
        _runGameCaptureFrameWatchdog(
          generation: ++_gameCaptureFrameWatchdogGeneration,
          publications: List.unmodifiable(publishedPublications),
          sourceIdHash: shortShareSourceIdHash(src.id),
          automaticFallback: automaticGameCaptureBackend,
          retryFallback: retryLegacyWindowCaptureFallback,
        ),
      );
    } else {
      _gameCaptureFrameWatchdogGeneration++;
    }
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
    _notifyStateChanged();
  }

  Future<void> _applyPostPublishSenderLimitsInBackground(
    ScreenShareProfileConfig profile, {
    required Iterable<lk.LocalTrackPublication> localPublications,
    required Duration timeout,
  }) async {
    try {
      await Future<void>.delayed(_streamTestPostPublishSenderLimitsDelay);
      Log.i(
        'Stream test post-publish sender limits applying '
        'profile=${profile.label} timeout=${timeout.inSeconds}s',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      await _applyScreenShareSenderLimits(
        profile,
        localPublications: localPublications,
        timeout: timeout,
      );
      Log.i(
        'Stream test post-publish sender limits applied '
        'profile=${profile.label}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Stream test post-publish sender limits failed after screen-share '
            'publication; continuing active measurement',
      );
    }
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) {
    return _queueCameraOperation(() => _setCamera(device));
  }

  Future<void> flipCamera() {
    return _queueCameraOperation(() async {
      if ((!PlatformUtils.isAndroid && !PlatformUtils.isIOS) ||
          state.isFinishing ||
          !isCameraEnabled) {
        return;
      }

      for (final publication in _localCameraPublications()) {
        final track = publication.track;
        if (publication.muted || track == null || !track.isActive) {
          continue;
        }
        final options = track.currentOptions;
        if (options is! lk.CameraCaptureOptions) {
          return;
        }
        await track.setCameraPosition(options.cameraPosition.switched());
        if (!_ending && !state.isFinishing) {
          _notifyStateChanged();
        }
        return;
      }
    });
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

    _notifyStateChanged();
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
    _notifyStateChanged();
  }

  @override
  Future<void> stopScreenshare() async {
    final nativeCrashGuard = await PendingNativeCallCrashGuard.recordAction(
      source: 'matrix-livekit-native-call-action-screen-share-stop',
      actionKind: 'LiveKit screen share stop',
    );
    final shareSession = _currentShareSession;
    try {
      if (PlatformUtils.isIOS) {
        await IosBroadcastControl.requestStop();
      }

      await _stopWindowsSharedAudioPublication(shareSession);
      await _stopLocalScreenShareVideoPublications(reason: 'screen-share stop');
      await livekitRoom.localParticipant?.setScreenShareEnabled(false);
      await shareSession?.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop LiveKit screen share',
      );
      rethrow;
    } finally {
      await nativeCrashGuard?.clear();
    }

    _resetScreenShareState();
    _announceEndCueIfShareCleared();

    if (PlatformUtils.isAndroid) {
      try {
        await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        Log.e('error disabling screen share: $error');
      }
    }

    _notifyStateChanged();
  }

  void _resetScreenShareState() {
    _gameCaptureFrameWatchdogGeneration++;
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
    _activeLocalScreenShareVideoPublicationSids.clear();
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
    _notifyStateChanged();
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
        preferences.showCallStreamStats.value ||
        adaptiveFallbackEnabled ||
        preferences.voipRemoteParticipantLoudnessMeasurement.value;
    if (!shouldCollect || state == VoipState.ended) {
      return;
    }
    // Skip rather than queue: this is periodic sampling, so a pass that arrives
    // while the previous one is still walking receivers has nothing to add - the
    // next tick will sample fresher data anyway.
    if (_diagnosticsCollectionInFlight) {
      return;
    }

    _lastUpdatedDiagnostics = now;
    _diagnosticsCollectionInFlight = true;
    try {
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
      _notifyDiagnosticsChanged();
    } finally {
      // finally, not a trailing assignment: a throw anywhere above would
      // otherwise wedge the flag true and stop diagnostics for the whole call.
      _diagnosticsCollectionInFlight = false;
    }
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
      _announceEndCueIfShareCleared();
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
    final videoSource = source is ShareCaptureSource
        ? source.videoSource
        : source;
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
    final collectRawStats =
        streamTestSampleOrdinal == null ||
        streamTestSampleOrdinal == 1 ||
        streamTestSampleOrdinal % _streamTestRawDiagnosticsSampleInterval == 0;
    final refreshIceDiagnostics =
        streamTestSampleOrdinal == null ||
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
    _notifyDiagnosticsChanged();
    if (streamTestSampleOrdinal != null) {
      final elapsedMs = DateTime.now()
          .difference(diagnosticsStartedAt)
          .inMilliseconds;
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
    final switchingAwayFromDirectx =
        _activeWindowsCaptureBackendMode ==
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
    final profileChanged =
        currentProfile == null ||
        !_profileLimitsEqual(currentProfile, requestedProfile);
    final backendChanged =
        config.hasWindowsCaptureBackendOverride &&
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
        // Preserve whatever pacing mode the running session was actually
        // using; live tuning must not re-enable the diagnostic default.
        nativeFramePacingEnabled:
            PlatformUtils.isWindows && _activeNativeFramePacingEnabled,
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
      _announceEndCueIfShareCleared();
      _screenShareCaptureRefreshInFlight = false;
    }
    return notes;
  }

  bool get _hasActiveLocalScreenShareVideo {
    final livePublications = _localScreenShareVideoPublications();
    if (livePublications.isNotEmpty) {
      return true;
    }

    // Local publish events can reach the UI stream list before LiveKit's
    // participant publication map reflects the screen-share track.
    final outgoingScreenShareStreamSids = streams
        .whereType<MatrixLivekitVoipStream>()
        .where(
          (stream) =>
              stream.direction == VoipStreamDirection.outgoing &&
              _isScreenShareVideoPublication(stream.publication),
        )
        .map((stream) => stream.publication.sid)
        .toSet();

    // The sid cache exists only to cover that window, but it was pruned solely
    // by a local-unpublish event - and a full LiveKit reconnect republishes
    // through `rePublishAllTracks()`, which never emits one. The old sids then
    // pinned this getter true for the rest of the call, so "you are streaming"
    // could not be turned off. Trust a cached sid only while some live
    // publication or outgoing stream still corresponds to it.
    _activeLocalScreenShareVideoPublicationSids.retainWhere(
      outgoingScreenShareStreamSids.contains,
    );
    if (_activeLocalScreenShareVideoPublicationSids.isNotEmpty) {
      return true;
    }

    return streams.whereType<MatrixLivekitVoipStream>().any((stream) {
      final publication = stream.publication;
      return stream.direction == VoipStreamDirection.outgoing &&
          _isScreenShareVideoPublication(publication) &&
          !publication.muted;
    });
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
    _notifyStateChanged();
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
      screenShareProfileDetails: _diagnosticsProfileDetails(
        profile,
        preserveGameCaptureResolution: _preserveGameCaptureResolutionForBackend(
          _activeWindowsCaptureBackendMode,
        ),
      ),
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
      callHealth: _buildCallHealthSnapshot(collectedAt: collectedAt),
    );
  }

  CallHealthSnapshot _buildCallHealthSnapshot({required DateTime collectedAt}) {
    return CallHealthSnapshot.derive(
      collectedAt: collectedAt,
      lifecycle: _roomLifecycle,
      participants: _collectCallHealthParticipants(),
    );
  }

  List<CallHealthParticipantSnapshot> _collectCallHealthParticipants() {
    final participants = <CallHealthParticipantSnapshot>[];
    final localParticipant = livekitRoom.localParticipant;
    if (localParticipant != null) {
      participants.add(
        CallHealthParticipantSnapshot(
          sanitizedId: 'local',
          label: 'You',
          isLocal: true,
          userId: room.client.self?.identifier,
          connectionQuality: _callConnectionQuality(
            localParticipant.connectionQuality,
          ),
        ),
      );
    }

    final remoteParticipants = livekitRoom.remoteParticipants.values.toList(
      growable: false,
    )..sort((a, b) => a.identity.compareTo(b.identity));
    for (var i = 0; i < remoteParticipants.length; i++) {
      final participant = remoteParticipants[i];
      final userId = _userIdFromParticipantIdentity(participant.identity);
      final microphonePublications = participant.audioTrackPublications
          .where(_isRemoteMicrophoneAudioPublication)
          .toList(growable: false);
      final microphonePublication = microphonePublications.firstOrNull;
      final stream = microphonePublication == null
          ? null
          : _findLivekitStream(microphonePublication);
      final remoteAudio = microphonePublication == null
          ? null
          : VoipRemoteAudioReconciliationPolicy.evaluate(
              VoipRemoteAudioState(
                participantConnected: livekitRoom.remoteParticipants
                    .containsKey(participant.identity),
                audioPublicationExists: true,
                publicationMuted: microphonePublication.muted,
                trackSubscribed: microphonePublication.subscribed,
                streamObjectExists: stream != null,
                audioSinkAttached: microphonePublication.track is lk.AudioTrack,
                localVolume: stream?.localVolume ?? 1.0,
                locallyMuted: stream?.locallyMuted ?? false,
                userMuted:
                    stream != null &&
                    stream.hasLocalPlaybackVolumeOverride &&
                    stream.localVolume <= 0,
              ),
            );

      participants.add(
        CallHealthParticipantSnapshot(
          sanitizedId: 'remote_${i + 1}',
          label: _participantDisplayNameForUserId(
            userId,
            fallback: 'Remote participant ${i + 1}',
          ),
          isLocal: false,
          userId: userId,
          connectionQuality: _callConnectionQuality(
            participant.connectionQuality,
          ),
          hasExpectedMicrophoneAudio: microphonePublication != null,
          audioPublicationExists: microphonePublication != null,
          audioPublicationMuted: microphonePublication?.muted ?? false,
          audioTrackSubscribed: microphonePublication?.subscribed ?? false,
          audioSinkAttached: microphonePublication?.track is lk.AudioTrack,
          effectiveVolume: stream?.localVolume,
          locallyMuted: stream?.locallyMuted ?? false,
          userMuted:
              stream != null &&
              stream.hasLocalPlaybackVolumeOverride &&
              stream.localVolume <= 0,
          remoteAudioAudible: remoteAudio?.audible,
          remoteAudioReason: remoteAudio?.reason,
        ),
      );
    }
    return participants;
  }

  String _participantDisplayNameForUserId(
    String userId, {
    required String fallback,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return fallback;
    }

    final displayName = room
        .getMemberOrFallback(trimmedUserId)
        .displayName
        .trim();
    if (displayName.isNotEmpty && displayName != trimmedUserId) {
      return displayName;
    }

    return fallback;
  }

  CallConnectionQuality _callConnectionQuality(lk.ConnectionQuality quality) {
    return switch (quality) {
      lk.ConnectionQuality.excellent => CallConnectionQuality.excellent,
      lk.ConnectionQuality.good => CallConnectionQuality.good,
      lk.ConnectionQuality.poor => CallConnectionQuality.poor,
      lk.ConnectionQuality.lost => CallConnectionQuality.lost,
      lk.ConnectionQuality.unknown => CallConnectionQuality.unknown,
    };
  }

  bool get _includePrivateShareDiagnostics =>
      preferences.developerMode.value && preferences.showCallStreamStats.value;

  /// Watches the sender frame counters shortly after a D3D11 game-capture
  /// publish. Track creation can succeed while the hook never delivers a
  /// frame (most often for windowed DX11 games), leaving remote users with a
  /// black tile until the stream is manually restarted. When no frames have
  /// been sent ~8s after publish, retry with the legacy capture fallback if
  /// the game backend was chosen automatically; explicit backend choices only
  /// log so diagnostics stay honest.
  Future<void> _runGameCaptureFrameWatchdog({
    required int generation,
    required List<lk.LocalTrackPublication> publications,
    required String sourceIdHash,
    required bool automaticFallback,
    required Future<void> Function({
      required String reason,
      Object? error,
      StackTrace? stackTrace,
    })
    retryFallback,
  }) async {
    bool active() =>
        generation == _gameCaptureFrameWatchdogGeneration &&
        _canProcessLiveKitRoomEvent;

    Future<num?> sampleFramesSent() async {
      num total = 0;
      var sampled = false;
      for (final publication in publications) {
        final track = publication.track;
        if (track is! lk.LocalVideoTrack) {
          continue;
        }
        try {
          for (final stats in await track.getSenderStats()) {
            final frames = stats.framesSent;
            if (frames != null) {
              total += frames;
              sampled = true;
            }
          }
        } catch (_) {}
      }
      return sampled ? total : null;
    }

    await Future<void>.delayed(const Duration(seconds: 4));
    if (!active()) {
      return;
    }
    final firstSample = await sampleFramesSent();
    if (!active() || (firstSample != null && firstSample > 0)) {
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 4));
    if (!active()) {
      return;
    }
    final secondSample = await sampleFramesSent();
    if (!active()) {
      return;
    }
    if (secondSample == null) {
      Log.w(
        'Game-capture frame watchdog could not read sender stats '
        'sourceIdHash=$sourceIdHash; skipping automatic fallback.',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
      return;
    }
    if (secondSample > 0) {
      return;
    }

    if (!automaticFallback) {
      Log.w(
        'Game-capture publish has sent zero frames ~8s after start '
        'sourceIdHash=$sourceIdHash with an explicitly requested backend; '
        'not falling back automatically. Restart the stream or switch the '
        'capture backend.',
        category: LogCategory.livekit,
        source: 'screen-share-publish',
      );
      return;
    }

    await runScreenShareFallbackWithCueReconciliation(
      fallback: () async {
        // The wedged track is already published; stop it before the fallback
        // republish so the retry does not add a second screen-share video track.
        await _stopLocalScreenShareVideoPublications(
          reason: 'game-capture zero-frame watchdog fallback',
        );
        // Stopping is an async gap: the user may have stopped the share, the
        // call may be ending, or a newer share may have started (all bump the
        // watchdog generation). Never resurrect a stopped or superseded share.
        if (!active()) {
          Log.i(
            'Game-capture zero-frame fallback skipped after publications '
            'stopped; the share was stopped or superseded during teardown '
            'sourceIdHash=$sourceIdHash.',
            category: LogCategory.livekit,
            source: 'screen-share-publish',
          );
          return;
        }
        await retryFallback(reason: 'game_capture_zero_frames_after_publish');
      },
      cueState: _localStreamCueState,
      shareActive: () =>
          _ending || _localScreenShareVideoPublications().isNotEmpty,
      announceEnd: () =>
          unawaited(_announceStreamLifecycleCue(StreamLifecycleCue.end)),
    );
  }

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
    // Latest-frame pacing is documented in the native capturer contract as a
    // debug/test harness mode: "Normal desktop capture should leave it
    // disabled unless a stream-test run explicitly enables it". Defaulting it
    // on for every Windows webrtc capture (2026-05-28 dirty-diff batch) kept
    // the acquisition loop free-running against DXGI/WGC for the whole
    // stream, which starves DWM/pointer composition and shows up as
    // system-wide mouse lag while streaming. Stream tests and explicit
    // callers can still opt in via the nativeFramePacingEnabled parameter.
    return false;
  }

  bool _isWindowsWindowScreenShareSource(ScreenCaptureSource source) {
    if (!PlatformUtils.isWindows) {
      return false;
    }
    final videoSource = source is ShareCaptureSource
        ? source.videoSource
        : source;
    return videoSource is WebrtcScreencaptureSource &&
        videoSource.source.type == SourceType.Window;
  }

  WindowsScreenCaptureBackendMode? _windowsCaptureBackendModeForPublish({
    required WindowsScreenCaptureBackendMode? requestedMode,
    required bool isWindowSource,
    String? sourceTitle,
  }) {
    return defaultWindowsCaptureBackendMode(
      isWindows: PlatformUtils.isWindows,
      isWebrtcDesktopSource: true,
      isWindowSource: isWindowSource,
      requestedMode: requestedMode,
      preferGameCaptureForWindowSource:
          _gpuPipelineTestModeEnabled || preferences.developerMode.value,
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
        content:
            'Failed to refresh desktop capture source cache before '
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

  String _diagnosticsProfileDetails(
    ScreenShareProfileConfig profile, {
    bool preserveGameCaptureResolution = false,
  }) {
    final lowLayer = profile.lowLayer == null
        ? 'none'
        : '${profile.lowLayer!.resolutionLabel}@'
              '${profile.lowLayer!.diagnosticFramerateLabel}/'
              '${_formatDiagnosticBitrate(profile.lowLayer!.maxBitrateBps)}'
              '${_diagnosticMinBitrateSuffix(profile.lowLayer!)}';
    final degradation = _degradationPreferenceForProfile(
      profile,
      preserveGameCaptureResolution: preserveGameCaptureResolution,
    ).name;
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
    final identities =
        <String>{
              if (livekitRoom.localParticipant?.identity != null)
                livekitRoom.localParticipant!.identity,
              ...livekitRoom.remoteParticipants.keys,
              for (final stream in streams.whereType<MatrixLivekitVoipStream>())
                stream.participantIdentity,
            }
            .where((identity) => !identity.contains('_rnnoise_loopback'))
            .toList()
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
    final statsDebugEnabled =
        forceStatsDebug ||
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
      if (stream.type == VoipStreamType.audio) {
        final remoteAudio = stream.remoteAudioReconciliation;
        // Gated like every other raw getStats() in this method. Without the
        // guard this ran on adaptive-fallback-only ticks, where nothing
        // consumes it, and it ignored the collectRawStats throttle that
        // collectStreamTestDiagnostics computes from
        // _streamTestRawDiagnosticsSampleInterval to keep stream-test sampling
        // cheap. The loudness preference is included because that measurement
        // is what these values are collected for.
        final collectInboundAudio =
            collectRawStats &&
            (statsDebugEnabled ||
                preferences.voipRemoteParticipantLoudnessMeasurement.value);
        final inboundAudioStats =
            collectInboundAudio && track is lk.RemoteAudioTrack
            ? await _collectInboundAudioRtpStats(track)
            : null;
        result.add(
          VoipTrackDiagnostics(
            streamId: stream.streamId,
            label: stream.label,
            type: stream.type,
            direction: stream.direction == VoipStreamDirection.outgoing
                ? VoipDiagnosticsTrackDirection.sender
                : VoipDiagnosticsTrackDirection.receiver,
            receivePriority: stream.receivePriority,
            inboundAudioLevel: inboundAudioStats?.audioLevel,
            inboundTotalAudioEnergy: inboundAudioStats?.totalAudioEnergy,
            inboundTotalSamplesDuration:
                inboundAudioStats?.totalSamplesDuration,
            remoteAudioAudible: remoteAudio?.audible,
            remoteAudioRepairAction: remoteAudio?.action,
            remoteAudioReason: remoteAudio?.reason,
          ),
        );
      }
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
                retransmittedPacketsSent: stat.retransmittedPacketsSent
                    ?.round(),
                retransmittedBytesSent: raw?.retransmittedBytesSent,
                qualityLimitationResolutionChanges: stat
                    .qualityLimitationResolutionChanges
                    ?.round(),
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

  /// Cadence for the receiver-side energy poll.
  ///
  /// The measurement itself is poll-rate independent - it is a ratio of
  /// counter deltas - so this only sets how finely the session is sliced, and
  /// one second keeps a call's worth of `getStats()` calls modest while still
  /// resolving individual utterances.
  static const Duration _inboundAudioEnergyInterval = Duration(seconds: 1);

  static const Duration _inboundAudioEnergyLogInterval = Duration(seconds: 30);

  /// Polls subscribed remote microphone tracks for their inbound-rtp energy
  /// counters and publishes the readings on their streams.
  ///
  /// Measurement only: nothing here changes playback, subscription state, or
  /// any track. It exists so receiver-side loudness work has a source that is
  /// a real RMS statistic upstream of local playback gain, rather than the
  /// display-normalised visualizer magnitude that live evidence rejected.
  Future<void> _refreshInboundAudioEnergy() async {
    if (_transientCallResourcesDisposed || state == VoipState.ended) {
      return;
    }

    // NOT gated on the loudness preference alone, deliberately. The only
    // consumer of the published sample is ParticipantLoudnessMonitor, which is
    // itself gated on voipRemoteParticipantLoudnessMeasurement - but the 30 s
    // summary below is diagnostic output the stats overlay and webrtc-stats
    // logging both want on their own. All three toggles default false, and the
    // latter two are developer-only, so nothing here runs for an ordinary user.
    // The cost when a developer enables only the overlay is a flat 1 Hz
    // getStats sweep whose samples nothing reads; that buys the summary log.
    // Narrow this to the loudness preference if that trade stops being worth it.
    final enabled =
        preferences.voipRemoteParticipantLoudnessMeasurement.value ||
        preferences.showCallStreamStats.value ||
        Log.webrtcStatsEnabled;

    if (!enabled) {
      if (_inboundAudioEnergyCollectionActive) {
        _inboundAudioEnergyCollectionActive = false;
        _lastInboundAudioEnergyLogMs = null;
        for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
          stream.updateInboundAudioEnergy(null);
        }
      }
      return;
    }
    _inboundAudioEnergyCollectionActive = true;

    // `getStats()` is allowed up to 1200ms and the tick is 1000ms, so a slow
    // receiver would otherwise stack overlapping passes and multiply the cost
    // of exactly the condition that caused the delay. Skipping a tick is free:
    // the next pair of readings simply spans a longer window.
    if (_inboundAudioEnergyCollectionInFlight) {
      return;
    }
    _inboundAudioEnergyCollectionInFlight = true;

    try {
      final targets = streams
          .whereType<MatrixLivekitVoipStream>()
          .where(
            (stream) =>
                stream.direction == VoipStreamDirection.incoming &&
                stream.isMicrophoneAudio &&
                stream.publication.track is lk.RemoteAudioTrack,
          )
          .toList(growable: false);

      for (final stream in targets) {
        final track = stream.publication.track;
        if (track is! lk.RemoteAudioTrack) {
          continue;
        }

        final stats = await _collectInboundAudioRtpStats(track);
        if (_transientCallResourcesDisposed || state == VoipState.ended) {
          return;
        }
        if (stats == null) {
          continue;
        }

        stream.updateInboundAudioEnergy(
          VoipInboundAudioEnergySample(
            capturedAtMs: DateTime.now().millisecondsSinceEpoch,
            totalAudioEnergy: stats.totalAudioEnergy,
            totalSamplesDuration: stats.totalSamplesDuration,
            audioLevel: stats.audioLevel,
          ),
        );
      }

      _maybeLogInboundAudioEnergySummary(targets);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered inbound audio energy collection failure',
        category: LogCategory.webrtc,
        source: 'inbound-audio-energy',
      );
    } finally {
      _inboundAudioEnergyCollectionInFlight = false;
    }
  }

  /// Throttled evidence line for the measurement-source comparison.
  ///
  /// Carries no participant, track, or room identifier - only the per-stream
  /// numbers, unlabelled. The question this has to answer is whether the new
  /// source separates participants at all (the rejected one compressed five
  /// people into 0.73 dB), and the spread of the values answers it without
  /// naming anyone.
  void _maybeLogInboundAudioEnergySummary(
    List<MatrixLivekitVoipStream> streamsSampled,
  ) {
    if (streamsSampled.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final last = _lastInboundAudioEnergyLogMs;
    if (last != null &&
        nowMs - last < _inboundAudioEnergyLogInterval.inMilliseconds) {
      return;
    }
    _lastInboundAudioEnergyLogMs = nowMs;

    final energies = <String>[];
    final levels = <String>[];
    for (final stream in streamsSampled) {
      final sample = stream.inboundAudioEnergy;
      energies.add(sample?.totalAudioEnergy?.toStringAsFixed(3) ?? 'none');
      levels.add(sample?.audioLevel?.toStringAsFixed(4) ?? 'none');
    }

    Log.i(
      'Inbound audio energy (measurement only, no playback change): '
      'streams=${streamsSampled.length} '
      'totalAudioEnergy=[${energies.join(',')}] '
      'audioLevel=[${levels.join(',')}]',
      category: LogCategory.webrtc,
      source: 'inbound-audio-energy',
    );
  }

  Future<LiveKitInboundAudioRtpStats?> _collectInboundAudioRtpStats(
    lk.RemoteAudioTrack track,
  ) async {
    final receiver = track.receiver;
    if (receiver == null) {
      return null;
    }

    try {
      final reports = await _withDiagnosticsStatsTimeout(
        receiver.getStats(),
        label: 'LiveKit inbound audio stats',
      );
      if (reports == null) {
        return null;
      }
      return debugLiveKitInboundAudioRtpStatsFromReports(reports);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to collect LiveKit inbound audio diagnostics',
      );
      return null;
    }
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
    final actual =
        ' actual=${track.resolutionLabel}'
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
    final inboundAudio = [
      if (track.inboundAudioLevel != null)
        'audio_level=${track.inboundAudioLevel!.toStringAsFixed(4)}',
      if (track.inboundTotalAudioEnergy != null)
        'audio_energy=${track.inboundTotalAudioEnergy!.toStringAsFixed(4)}',
      if (track.inboundTotalSamplesDuration != null)
        'audio_samples_s=${track.inboundTotalSamplesDuration!.toStringAsFixed(3)}',
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
        '${inboundAudio.isEmpty ? '' : ' $inboundAudio'}'
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

    final encodedTooWide =
        track.width! > track.requestedWidth! + 32 &&
        track.width! > track.requestedWidth! * 1.1;
    final encodedTooTall =
        track.height! > track.requestedHeight! + 18 &&
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
            framesCaptured:
                _intFromStatsValue(
                  values['framesCaptured'] ?? values['frames'],
                ) ??
                previousSource?.framesCaptured,
            framesDroppedBeforeEncode:
                _intFromStatsValue(
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

    final summary =
        '${_candidateLabel(localValues, side: 'local')} -> '
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
      if (_isScreenShareVideoPublication(publication)) {
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
      final shouldRestoreAfterCpuRescue =
          !forceLowLayerOnly &&
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

      final limitKey =
          '${profile.storageKey}:${profile.label}:'
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

    // Logged before the early return. The timers above were cancelled either
    // way, and on a homeserver without MSC4140 support - or on a second
    // stopHeartbeat() call - there is no delayed event, so the terminal
    // heartbeat line disappeared from the capture entirely.
    Log.i("Stopped heartbeat");

    final delayId = heartbeatDelayId;
    if (delayId == null) {
      return;
    }

    heartbeatDelayId = null;
    await _cancelHeartbeatDelayedEvent(delayId);
  }

  Future<void> _cancelHeartbeatDelayedEvent(String delayId) {
    return room.matrixRoom.client.request(
      RequestType.POST,
      "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(delayId)}",
      contentType: "application/json",
      data: jsonEncode({"action": "cancel"}),
    );
  }

  Future<void> startHeartbeat() async {
    startMembershipRefresh();

    final capabilities = await room.matrixRoom.client.getVersions();
    Log.d("${capabilities}");
    if (capabilities.unstableFeatures?["org.matrix.msc4140"] != true) {
      Log.e("Homeserver does not support delayed events");
      return;
    }

    // A leave that lands while the capability probe is in flight has already
    // run `stopHeartbeat`, so there is nothing left for it to cancel. Bailing
    // here keeps the delayed event from being registered at all.
    if (_isLeavingOrEnded) {
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

    // The delayed event now exists on the server. A fast leave - joining and
    // hanging up inside this request - would otherwise arm a 25s timer that
    // outlives the session and keeps refreshing a membership the user already
    // left, because `stopHeartbeat` ran before `heartbeatDelayId` was set and
    // had nothing to cancel.
    if (_isLeavingOrEnded) {
      Log.w(
        'call_heartbeat event=discarded_after_leave '
        'reason=session_ending result=delayed_event_cancelled',
        category: LogCategory.livekit,
        source: 'matrix-livekit-session',
      );
      try {
        await _cancelHeartbeatDelayedEvent(delayId);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Failed to cancel a MatrixRTC delayed event registered during '
              'hang-up; the server-side expiry clears it',
          category: LogCategory.livekit,
          source: 'matrix-livekit-session',
        );
      }
      return;
    }

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

  bool get _isLeavingOrEnded =>
      _ending || state == VoipState.leaving || state == VoipState.ended;

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

/// One share's published shared-audio track.
///
/// The publication and the track it wraps are held together so neither can be
/// recorded without the other: a track with no publication is one nothing can
/// unpublish, and a publication with no track leaves the capture running after
/// the room has stopped carrying it.
class _WindowsSharedAudioPublication {
  const _WindowsSharedAudioPublication({
    required this.publication,
    required this.track,
  });

  final lk.LocalTrackPublication<lk.LocalAudioTrack> publication;
  final lk.LocalAudioTrack track;
}
