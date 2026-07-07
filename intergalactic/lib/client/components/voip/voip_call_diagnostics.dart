import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

enum VoipDiagnosticsTrackDirection { sender, receiver }

class VoipParticipantDiagnostics {
  const VoipParticipantDiagnostics({
    required this.identity,
    required this.userId,
    required this.clientLabel,
  });

  final String identity;
  final String userId;
  final String clientLabel;
}

class VoipTrackDiagnostics {
  const VoipTrackDiagnostics({
    required this.streamId,
    required this.label,
    required this.type,
    required this.direction,
    this.receivePriority,
    this.requestedWidth,
    this.requestedHeight,
    this.requestedFps,
    this.requestedBitrateBps,
    this.preEncodeWidth,
    this.preEncodeHeight,
    this.width,
    this.height,
    this.fps,
    this.captureFps,
    this.encodeFps,
    this.sendFps,
    this.decodeFps,
    this.renderFps,
    this.bitrateBps,
    this.targetBitrateBps,
    this.availableOutgoingBitrateBps,
    this.availableIncomingBitrateBps,
    this.retransmitBitrateBps,
    this.packetsLost,
    this.packetsSent,
    this.packetsReceived,
    this.nackCount,
    this.pliCount,
    this.firCount,
    this.packetLossPercent,
    this.jitterMs,
    this.jitterBufferDelayMs,
    this.roundTripTimeMs,
    this.codec,
    this.qualityLimitationReason,
    this.framesSent,
    this.framesCaptured,
    this.framesEncoded,
    this.framesDecoded,
    this.framesReceived,
    this.framesRendered,
    this.framesDropped,
    this.framesDroppedBeforeEncode,
    this.framesDroppedByEncoder,
    this.averageEncodeTimeMs,
    this.averagePacketSendDelayMs,
    this.averageDecodeTimeMs,
    this.retransmittedPacketsSent,
    this.retransmittedBytesSent,
    this.qualityLimitationResolutionChanges,
    this.qualityLimitationDurations,
    this.rid,
    this.activeLayer,
    this.encoderImplementation,
    this.decoderImplementation,
    this.hardwareEncodeActive,
    this.freezeCount,
    this.pauseCount,
    this.totalFreezesDurationMs,
    this.totalPausesDurationMs,
    this.remoteAudioAudible,
    this.remoteAudioRepairAction,
    this.remoteAudioReason,
  });

  final String streamId;
  final String label;
  final VoipStreamType type;
  final VoipDiagnosticsTrackDirection direction;
  final VoipStreamReceivePriority? receivePriority;
  final int? requestedWidth;
  final int? requestedHeight;
  final double? requestedFps;
  final int? requestedBitrateBps;
  final int? preEncodeWidth;
  final int? preEncodeHeight;
  final int? width;
  final int? height;
  final double? fps;
  final double? captureFps;
  final double? encodeFps;
  final double? sendFps;
  final double? decodeFps;
  final double? renderFps;
  final int? bitrateBps;
  final int? targetBitrateBps;
  final int? availableOutgoingBitrateBps;
  final int? availableIncomingBitrateBps;
  final int? retransmitBitrateBps;
  final int? packetsLost;
  final int? packetsSent;
  final int? packetsReceived;
  final int? nackCount;
  final int? pliCount;
  final int? firCount;
  final double? packetLossPercent;
  final double? jitterMs;
  final double? jitterBufferDelayMs;
  final double? roundTripTimeMs;
  final String? codec;
  final String? qualityLimitationReason;
  final int? framesSent;
  final int? framesCaptured;
  final int? framesEncoded;
  final int? framesDecoded;
  final int? framesReceived;
  final int? framesRendered;
  final int? framesDropped;
  final int? framesDroppedBeforeEncode;
  final int? framesDroppedByEncoder;
  final double? averageEncodeTimeMs;
  final double? averagePacketSendDelayMs;
  final double? averageDecodeTimeMs;
  final int? retransmittedPacketsSent;
  final int? retransmittedBytesSent;
  final int? qualityLimitationResolutionChanges;
  final String? qualityLimitationDurations;
  final String? rid;
  final String? activeLayer;
  final String? encoderImplementation;
  final String? decoderImplementation;
  final bool? hardwareEncodeActive;
  final int? freezeCount;
  final int? pauseCount;
  final double? totalFreezesDurationMs;
  final double? totalPausesDurationMs;
  final bool? remoteAudioAudible;
  final VoipRemoteAudioRepairAction? remoteAudioRepairAction;
  final String? remoteAudioReason;

  String? get remoteAudioSummaryLabel {
    final reason = remoteAudioReason;
    if (reason == null) {
      return null;
    }

    final action = remoteAudioRepairAction?.name ?? 'unknown';
    final audible = remoteAudioAudible == null
        ? ''
        : ' audible=${remoteAudioAudible! ? 'yes' : 'no'}';
    return '$reason action=$action$audible';
  }

  String get resolutionLabel {
    if (width == null || height == null || width == 0 || height == 0) {
      return 'unknown';
    }
    return '${width}x$height';
  }

  String get preEncodeResolutionLabel {
    if (preEncodeWidth == null ||
        preEncodeHeight == null ||
        preEncodeWidth == 0 ||
        preEncodeHeight == 0) {
      return 'unknown';
    }
    return '${preEncodeWidth}x$preEncodeHeight';
  }
}

class VoipCallDiagnosticsSnapshot {
  const VoipCallDiagnosticsSnapshot({
    required this.collectedAt,
    required this.screenShareProfileLabel,
    this.screenShareProfileDetails,
    required this.adaptiveStreamEnabled,
    required this.dynacastEnabled,
    required this.screenShareSimulcastEnabled,
    required this.adaptiveFallbackEnabled,
    required this.participants,
    required this.tracks,
    this.callHealth = const CallHealthSnapshot.unknown(),
    this.adaptiveFallbackReason,
    this.iceTransportSummary,
    this.shareSessionDiagnostics,
  });

  factory VoipCallDiagnosticsSnapshot.empty() {
    return VoipCallDiagnosticsSnapshot(
      collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
      screenShareProfileLabel: 'None',
      adaptiveStreamEnabled: false,
      dynacastEnabled: false,
      screenShareSimulcastEnabled: false,
      adaptiveFallbackEnabled: false,
      participants: const [],
      tracks: const [],
    );
  }

  final DateTime collectedAt;
  final String screenShareProfileLabel;
  final String? screenShareProfileDetails;
  final bool adaptiveStreamEnabled;
  final bool dynacastEnabled;
  final bool screenShareSimulcastEnabled;
  final bool adaptiveFallbackEnabled;
  final String? adaptiveFallbackReason;
  final String? iceTransportSummary;
  final ShareSessionDiagnosticSummary? shareSessionDiagnostics;
  final List<VoipParticipantDiagnostics> participants;
  final List<VoipTrackDiagnostics> tracks;
  final CallHealthSnapshot callHealth;

  bool get hasTracks => tracks.isNotEmpty;

  bool get hasParticipants => participants.isNotEmpty;

  VoipCallDiagnosticsSnapshot withCallHealth(CallHealthSnapshot callHealth) {
    return VoipCallDiagnosticsSnapshot(
      collectedAt: collectedAt,
      screenShareProfileLabel: screenShareProfileLabel,
      screenShareProfileDetails: screenShareProfileDetails,
      adaptiveStreamEnabled: adaptiveStreamEnabled,
      dynacastEnabled: dynacastEnabled,
      screenShareSimulcastEnabled: screenShareSimulcastEnabled,
      adaptiveFallbackEnabled: adaptiveFallbackEnabled,
      adaptiveFallbackReason: adaptiveFallbackReason,
      iceTransportSummary: iceTransportSummary,
      shareSessionDiagnostics: shareSessionDiagnostics,
      participants: participants,
      tracks: tracks,
      callHealth: callHealth,
    );
  }
}

class VoipDiagnosticsMath {
  const VoipDiagnosticsMath._();

  static int? bitrateBps({
    required num? previousBytes,
    required num? currentBytes,
    required num? previousTimestamp,
    required num? currentTimestamp,
  }) {
    if (previousBytes == null ||
        currentBytes == null ||
        previousTimestamp == null ||
        currentTimestamp == null) {
      return null;
    }

    final byteDelta = currentBytes - previousBytes;
    final timestampDelta = currentTimestamp - previousTimestamp;
    final timeDeltaSeconds = _timestampDeltaSeconds(timestampDelta);
    if (byteDelta <= 0 || timeDeltaSeconds == null || timeDeltaSeconds <= 0) {
      return null;
    }

    return ((byteDelta * 8) / timeDeltaSeconds).round();
  }

  static double? _timestampDeltaSeconds(num delta) {
    if (delta <= 0) {
      return null;
    }

    // Web stats commonly report DOMHighResTimeStamp values in milliseconds.
    // Native LiveKit/flutter_webrtc stats can report epoch-style microseconds.
    if (delta >= 100000) {
      return delta / 1000000;
    }
    if (delta > 60) {
      return delta / 1000;
    }
    return delta.toDouble();
  }

  static double? packetLossPercent({
    required num? packetsLost,
    required num? packetsReceived,
  }) {
    if (packetsLost == null || packetsReceived == null) {
      return null;
    }

    final total = packetsLost + packetsReceived;
    if (total <= 0) {
      return null;
    }

    return (packetsLost / total) * 100;
  }

  static double? jitterMs(num? seconds) {
    return secondsToMs(seconds);
  }

  static double? secondsToMs(num? seconds) {
    if (seconds == null) {
      return null;
    }
    return (seconds * 1000).toDouble();
  }

  static double? jitterBufferDelayAverageMs({
    required num? previousDelaySeconds,
    required num? currentDelaySeconds,
    required num? previousEmittedCount,
    required num? currentEmittedCount,
  }) {
    if (previousDelaySeconds == null ||
        currentDelaySeconds == null ||
        previousEmittedCount == null ||
        currentEmittedCount == null) {
      return null;
    }

    final delayDeltaSeconds = currentDelaySeconds - previousDelaySeconds;
    final emittedDelta = currentEmittedCount - previousEmittedCount;
    if (delayDeltaSeconds < 0 || emittedDelta <= 0) {
      return null;
    }

    return (delayDeltaSeconds / emittedDelta * 1000).toDouble();
  }

  static double? averageDurationMs({
    required num? previousTotalSeconds,
    required num? currentTotalSeconds,
    required num? previousCount,
    required num? currentCount,
  }) {
    if (previousTotalSeconds == null ||
        currentTotalSeconds == null ||
        previousCount == null ||
        currentCount == null) {
      return null;
    }

    final secondsDelta = currentTotalSeconds - previousTotalSeconds;
    final countDelta = currentCount - previousCount;
    if (secondsDelta < 0 || countDelta <= 0) {
      return null;
    }

    return (secondsDelta / countDelta * 1000).toDouble();
  }

  static bool? isLikelyHardwareEncoder(String? implementation) {
    if (implementation == null || implementation.trim().isEmpty) {
      return null;
    }

    final normalized = implementation.toLowerCase();
    if (normalized.contains('libvpx') ||
        normalized.contains('openh264') ||
        normalized.contains('software')) {
      return false;
    }

    if (normalized.contains('hardware') ||
        normalized.contains('mediafoundation') ||
        normalized.contains('d3d11') ||
        normalized.contains('dxva') ||
        normalized.contains('nvenc') ||
        normalized.contains('qsv') ||
        normalized.contains('amf') ||
        normalized.contains('mediacodec') ||
        normalized.contains('videotoolbox') ||
        normalized.contains('vaapi') ||
        normalized.contains('v4l2')) {
      return true;
    }

    return null;
  }
}
