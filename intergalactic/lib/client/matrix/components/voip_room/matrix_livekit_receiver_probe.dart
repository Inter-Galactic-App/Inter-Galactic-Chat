import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

const intergalacticStreamViewProbeMarker = 'intergalactic_stream_view_probe';
const _nativeRendererFrameEvent = 'didIntergalacticFrameRendered';
const _nativeRendererFrameHashAlgorithm =
    'fnv1a-y64x36-uv32x18-native-renderer-onframe';
const _captureFrameHashAlgorithm = 'sha256-png-captureframe';

Future<void> debugRunMatrixLivekitReceiverProbeCleanupForTesting({
  required String operation,
  required FutureOr<void> Function()? cleanup,
}) {
  return _runMatrixLivekitReceiverProbeCleanup(
    operation: operation,
    cleanup: cleanup,
  );
}

Future<void> _runMatrixLivekitReceiverProbeCleanup({
  required String operation,
  required FutureOr<void> Function()? cleanup,
}) async {
  if (cleanup == null) {
    return;
  }

  try {
    await cleanup();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered receiver probe cleanup failure: $operation',
      category: LogCategory.webrtc,
      source: 'matrix-livekit-receiver-probe-cleanup',
    );
  }
}

Future<bool> debugRunMatrixLivekitReceiverProbePublicationOperationForTesting({
  required String operation,
  required FutureOr<void> Function()? publicationOperation,
}) {
  return _runMatrixLivekitReceiverProbePublicationOperation(
    operation: operation,
    publicationOperation: publicationOperation,
  );
}

Future<bool> _runMatrixLivekitReceiverProbePublicationOperation({
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
      content: 'Recovered receiver probe publication failure: $operation',
      category: LogCategory.webrtc,
      source: 'matrix-livekit-receiver-probe-publication',
    );
    return false;
  }
}

abstract final class MatrixLivekitReceiverProbePresentationStage {
  static const remoteDecode = 'remote_decode';
  static const remoteRendererCallback = 'remote_renderer_callback';
  static const remoteTextureReady = 'remote_texture_ready';
  static const remoteUiPaint = 'remote_ui_paint';
  static const remoteScreenPresent = 'remote_screen_present';
}

num? _numFromProbeValue(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

int? _intFromProbeValue(Object? value) {
  return _numFromProbeValue(value)?.round();
}

double? _doubleFromProbeValue(Object? value) {
  return _numFromProbeValue(value)?.toDouble();
}

double? _nativeFrameEventDelayMs({
  required DateTime capturedAtUtc,
  required int? nativeTimestampUnixMs,
}) {
  if (nativeTimestampUnixMs == null) {
    return null;
  }
  return capturedAtUtc
          .difference(
            DateTime.fromMillisecondsSinceEpoch(
              nativeTimestampUnixMs,
              isUtc: true,
            ),
          )
          .inMicroseconds /
      1000.0;
}

class MatrixLivekitReceiverProbeCredentials {
  const MatrixLivekitReceiverProbeCredentials({
    required this.sfuUrl,
    required this.jwt,
    required this.probeIdentity,
    this.expiresInSeconds,
  });

  final String sfuUrl;
  final String jwt;
  final String probeIdentity;
  final int? expiresInSeconds;
}

enum MatrixLivekitReceiverProbeMode { decodeOnly, render }

enum MatrixLivekitReceiverProbeFrameDiagnosticsMode {
  nativeRendererHash,
  statsOnly,
}

extension MatrixLivekitReceiverProbeModeLabel
    on MatrixLivekitReceiverProbeMode {
  String get label => switch (this) {
    MatrixLivekitReceiverProbeMode.decodeOnly => 'decode-only',
    MatrixLivekitReceiverProbeMode.render => 'render',
  };
}

extension MatrixLivekitReceiverProbeFrameDiagnosticsModeLabel
    on MatrixLivekitReceiverProbeFrameDiagnosticsMode {
  String get label => switch (this) {
    MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash =>
      'native-renderer-hash',
    MatrixLivekitReceiverProbeFrameDiagnosticsMode.statsOnly => 'stats-only',
  };
}

class MatrixLivekitReceiverProbeOptions {
  const MatrixLivekitReceiverProbeOptions({
    required this.runId,
    required this.roomId,
    required this.publisherIdentity,
    required this.mode,
    this.inProcess = true,
    this.sampleInterval = const Duration(seconds: 1),
    this.statsTimeout = const Duration(seconds: 3),
    this.connectTimeout = const Duration(seconds: 10),
    this.subscriptionDelay = const Duration(seconds: 6),
    this.subscriptionTimeout = const Duration(seconds: 5),
    this.frameHashTapEnabled = true,
    this.frameDiagnosticsMode =
        MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash,
    this.frameHashStartDelay = const Duration(seconds: 2),
    this.frameHashInterval = const Duration(milliseconds: 33),
    this.frameHashTimeout = const Duration(milliseconds: 500),
    this.frameHashWindow = const Duration(seconds: 3),
  });

  final String runId;
  final String roomId;
  final String publisherIdentity;
  final MatrixLivekitReceiverProbeMode mode;
  final bool inProcess;
  final Duration sampleInterval;
  final Duration statsTimeout;
  final Duration connectTimeout;
  final Duration subscriptionDelay;
  final Duration subscriptionTimeout;
  final bool frameHashTapEnabled;
  final MatrixLivekitReceiverProbeFrameDiagnosticsMode frameDiagnosticsMode;
  final Duration frameHashStartDelay;
  final Duration frameHashInterval;
  final Duration frameHashTimeout;
  final Duration frameHashWindow;
}

class MatrixLivekitReceiverProbeEvent {
  const MatrixLivekitReceiverProbeEvent({
    required this.marker,
    required this.runId,
    required this.inProcess,
    required this.lane,
    required this.sampleTimeUtc,
    required this.roomHash,
    required this.publisherIdentityHash,
    required this.receiverIdentityHash,
    required this.trackSidHash,
    required this.trackSource,
    required this.subscriptionState,
    required this.subscribedQuality,
    required this.simulcastLayer,
    required this.codec,
    required this.decoderImplementation,
    required this.hardwareDecode,
    required this.rendererAttached,
    required this.rendererVisible,
    required this.rendererWidth,
    required this.rendererHeight,
    required this.bitrateBps,
    required this.framesReceived,
    required this.framesDecoded,
    required this.framesRendered,
    required this.renderFps,
    required this.freshnessSource,
    required this.frameHashAlgorithm,
    required this.frameHashSampleCount,
    required this.frameHashErrorCount,
    required this.lastFrameCapturedAtUtc,
    required this.uniqueFrames,
    required this.duplicateFrames,
    required this.uniqueFps,
    required this.p50GapMs,
    required this.p95GapMs,
    required this.maxGapMs,
    required this.longestStaleRunMs,
    required this.jitterBufferDelayMs,
    required this.jitterBufferEmittedCount,
    required this.totalDecodeTimeMs,
    required this.averageDecodeTimeMs,
    required this.framesDropped,
    required this.freezeCount,
    required this.totalFreezeDurationMs,
    required this.receiveToDecodeMs,
    required this.decodeToRenderMs,
    required this.status,
    this.inboundBitrateBps,
    this.receivedWidth,
    this.receivedHeight,
    this.decodedWidth,
    this.decodedHeight,
    this.renderedWidth,
    this.renderedHeight,
    this.receiverFps,
    this.receivedFps,
    this.decodedFps,
    this.renderedFps,
    this.receiverStatsSampleWindowMs,
    this.packetsReceived,
    this.packetsLost,
    this.receiverJitterMs,
    this.pliCount,
    this.pliDelta,
    this.firCount,
    this.firDelta,
    this.nackCount,
    this.nackDelta,
    this.keyFramesDecoded,
    this.keyFramesDecodedDelta,
    this.keyframeIntervalFrames,
    this.keyframeIntervalMs,
    this.qpSum,
    this.averageQp,
    this.framePresentationP50GapMs,
    this.framePresentationP95GapMs,
    this.framePresentationMaxGapMs,
    this.framePresentationLatestGapMs,
    this.perceptualDifferenceScore,
    this.nativeFrameSequence,
    this.nativeFrameSequenceGaps,
    this.nativeFrameEventDelayMs,
    this.nativeFrameEventDelayMaxMs,
    this.droppedOrReplacedTextureUpdates,
    this.upscalingLowerLayerSuspected,
    this.adaptiveStreamLowLayerSuspected,
    this.stage,
    this.stageSource,
    this.stageObservedAtUtc,
    this.stageObservedGapMs,
    this.stageFrameAgeMs,
    this.stageNativeFrameSequence,
    this.stageFrameCapturedAtUtc,
    this.rendererTextureId,
    this.rendererCallbackToStageMs,
    this.frameId,
    this.frameIdSource,
    this.sourceFrameMarkerId,
    this.sourceFrameMarkerDecodedFrames,
    this.sourceFrameMarkerUniqueFrames,
    this.sourceFrameMarkerDuplicateFrames,
    this.sourceFrameMarkerUniqueFps,
    this.sourceFrameMarkerLongestStaleRunMs,
    this.sourceQpc,
    this.stageQpc,
    this.frameAgeMs,
    this.previousFrameId,
  });

  final String marker;
  final String runId;
  final bool inProcess;
  final String lane;
  final String? stage;
  final DateTime sampleTimeUtc;
  final String roomHash;
  final String publisherIdentityHash;
  final String receiverIdentityHash;
  final String? trackSidHash;
  final String trackSource;
  final String subscriptionState;
  final String subscribedQuality;
  final String simulcastLayer;
  final String? codec;
  final String? decoderImplementation;
  final bool? hardwareDecode;
  final bool rendererAttached;
  final bool rendererVisible;
  final int? rendererWidth;
  final int? rendererHeight;
  final int? bitrateBps;
  final int? framesReceived;
  final int? framesDecoded;
  final int? framesRendered;
  final double? renderFps;
  final int? inboundBitrateBps;
  final int? receivedWidth;
  final int? receivedHeight;
  final int? decodedWidth;
  final int? decodedHeight;
  final int? renderedWidth;
  final int? renderedHeight;
  final double? receiverFps;
  final double? receivedFps;
  final double? decodedFps;
  final double? renderedFps;
  final double? receiverStatsSampleWindowMs;
  final int? packetsReceived;
  final int? packetsLost;
  final double? receiverJitterMs;
  final int? pliCount;
  final int? pliDelta;
  final int? firCount;
  final int? firDelta;
  final int? nackCount;
  final int? nackDelta;
  final int? keyFramesDecoded;
  final int? keyFramesDecodedDelta;
  final int? keyframeIntervalFrames;
  final double? keyframeIntervalMs;
  final int? qpSum;
  final double? averageQp;
  final String? freshnessSource;
  final String? frameHashAlgorithm;
  final int? frameHashSampleCount;
  final int? frameHashErrorCount;
  final DateTime? lastFrameCapturedAtUtc;
  final int? uniqueFrames;
  final int? duplicateFrames;
  final double? uniqueFps;
  final double? p50GapMs;
  final double? p95GapMs;
  final double? maxGapMs;
  final double? longestStaleRunMs;
  final double? framePresentationP50GapMs;
  final double? framePresentationP95GapMs;
  final double? framePresentationMaxGapMs;
  final double? framePresentationLatestGapMs;
  final double? perceptualDifferenceScore;
  final int? nativeFrameSequence;
  final int? nativeFrameSequenceGaps;
  final double? nativeFrameEventDelayMs;
  final double? nativeFrameEventDelayMaxMs;
  final int? droppedOrReplacedTextureUpdates;
  final bool? upscalingLowerLayerSuspected;
  final bool? adaptiveStreamLowLayerSuspected;
  final String? stageSource;
  final DateTime? stageObservedAtUtc;
  final double? stageObservedGapMs;
  final double? stageFrameAgeMs;
  final int? stageNativeFrameSequence;
  final DateTime? stageFrameCapturedAtUtc;
  final int? rendererTextureId;
  final double? rendererCallbackToStageMs;
  final int? frameId;
  final String? frameIdSource;
  final int? sourceFrameMarkerId;
  final int? sourceFrameMarkerDecodedFrames;
  final int? sourceFrameMarkerUniqueFrames;
  final int? sourceFrameMarkerDuplicateFrames;
  final double? sourceFrameMarkerUniqueFps;
  final double? sourceFrameMarkerLongestStaleRunMs;
  final int? sourceQpc;
  final int? stageQpc;
  final double? frameAgeMs;
  final int? previousFrameId;
  final double? jitterBufferDelayMs;
  final int? jitterBufferEmittedCount;
  final double? totalDecodeTimeMs;
  final double? averageDecodeTimeMs;
  final int? framesDropped;
  final int? freezeCount;
  final double? totalFreezeDurationMs;
  final double? receiveToDecodeMs;
  final double? decodeToRenderMs;
  final String status;

  MatrixLivekitReceiverProbeEvent copyForPresentationStage({
    required String stage,
    required String status,
    required String stageSource,
    required DateTime observedAtUtc,
    int? rendererTextureId,
    double? stageObservedGapMs,
  }) {
    final callbackToStageMs = lastFrameCapturedAtUtc == null
        ? null
        : observedAtUtc.difference(lastFrameCapturedAtUtc!).inMicroseconds /
              1000.0;
    return MatrixLivekitReceiverProbeEvent(
      marker: marker,
      runId: runId,
      inProcess: inProcess,
      lane: lane,
      stage: stage,
      sampleTimeUtc: observedAtUtc,
      roomHash: roomHash,
      publisherIdentityHash: publisherIdentityHash,
      receiverIdentityHash: receiverIdentityHash,
      trackSidHash: trackSidHash,
      trackSource: trackSource,
      subscriptionState: subscriptionState,
      subscribedQuality: subscribedQuality,
      simulcastLayer: simulcastLayer,
      codec: codec,
      decoderImplementation: decoderImplementation,
      hardwareDecode: hardwareDecode,
      rendererAttached: rendererAttached,
      rendererVisible: rendererVisible,
      rendererWidth: rendererWidth,
      rendererHeight: rendererHeight,
      bitrateBps: bitrateBps,
      inboundBitrateBps: inboundBitrateBps,
      receivedWidth: receivedWidth,
      receivedHeight: receivedHeight,
      decodedWidth: decodedWidth,
      decodedHeight: decodedHeight,
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
      receiverFps: receiverFps,
      receivedFps: receivedFps,
      decodedFps: decodedFps,
      renderedFps: renderedFps,
      receiverStatsSampleWindowMs: receiverStatsSampleWindowMs,
      packetsReceived: packetsReceived,
      packetsLost: packetsLost,
      receiverJitterMs: receiverJitterMs,
      pliCount: pliCount,
      pliDelta: pliDelta,
      firCount: firCount,
      firDelta: firDelta,
      nackCount: nackCount,
      nackDelta: nackDelta,
      keyFramesDecoded: keyFramesDecoded,
      keyFramesDecodedDelta: keyFramesDecodedDelta,
      keyframeIntervalFrames: keyframeIntervalFrames,
      keyframeIntervalMs: keyframeIntervalMs,
      qpSum: qpSum,
      averageQp: averageQp,
      framesReceived: framesReceived,
      framesDecoded: framesDecoded,
      framesRendered: framesRendered,
      renderFps: renderFps,
      freshnessSource: freshnessSource,
      frameHashAlgorithm: frameHashAlgorithm,
      frameHashSampleCount: frameHashSampleCount,
      frameHashErrorCount: frameHashErrorCount,
      lastFrameCapturedAtUtc: lastFrameCapturedAtUtc,
      uniqueFrames: uniqueFrames,
      duplicateFrames: duplicateFrames,
      uniqueFps: uniqueFps,
      p50GapMs: p50GapMs,
      p95GapMs: p95GapMs,
      maxGapMs: maxGapMs,
      longestStaleRunMs: longestStaleRunMs,
      framePresentationP50GapMs: framePresentationP50GapMs,
      framePresentationP95GapMs: framePresentationP95GapMs,
      framePresentationMaxGapMs: framePresentationMaxGapMs,
      framePresentationLatestGapMs: framePresentationLatestGapMs,
      perceptualDifferenceScore: perceptualDifferenceScore,
      nativeFrameSequence: nativeFrameSequence,
      nativeFrameSequenceGaps: nativeFrameSequenceGaps,
      nativeFrameEventDelayMs: nativeFrameEventDelayMs,
      nativeFrameEventDelayMaxMs: nativeFrameEventDelayMaxMs,
      droppedOrReplacedTextureUpdates: droppedOrReplacedTextureUpdates,
      upscalingLowerLayerSuspected: upscalingLowerLayerSuspected,
      adaptiveStreamLowLayerSuspected: adaptiveStreamLowLayerSuspected,
      stageSource: stageSource,
      stageObservedAtUtc: observedAtUtc,
      stageObservedGapMs: stageObservedGapMs,
      stageFrameAgeMs: callbackToStageMs,
      stageNativeFrameSequence: nativeFrameSequence,
      stageFrameCapturedAtUtc: lastFrameCapturedAtUtc,
      rendererTextureId: rendererTextureId,
      rendererCallbackToStageMs: callbackToStageMs,
      frameId: frameId,
      frameIdSource: frameIdSource,
      sourceFrameMarkerId: sourceFrameMarkerId,
      sourceFrameMarkerDecodedFrames: sourceFrameMarkerDecodedFrames,
      sourceFrameMarkerUniqueFrames: sourceFrameMarkerUniqueFrames,
      sourceFrameMarkerDuplicateFrames: sourceFrameMarkerDuplicateFrames,
      sourceFrameMarkerUniqueFps: sourceFrameMarkerUniqueFps,
      sourceFrameMarkerLongestStaleRunMs: sourceFrameMarkerLongestStaleRunMs,
      sourceQpc: sourceQpc,
      stageQpc: stageQpc,
      frameAgeMs: frameAgeMs,
      previousFrameId: previousFrameId,
      jitterBufferDelayMs: jitterBufferDelayMs,
      jitterBufferEmittedCount: jitterBufferEmittedCount,
      totalDecodeTimeMs: totalDecodeTimeMs,
      averageDecodeTimeMs: averageDecodeTimeMs,
      framesDropped: framesDropped,
      freezeCount: freezeCount,
      totalFreezeDurationMs: totalFreezeDurationMs,
      receiveToDecodeMs: receiveToDecodeMs,
      decodeToRenderMs: decodeToRenderMs,
      status: status,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'marker': marker,
      'run_id': runId,
      'in_process': inProcess,
      'lane': lane,
      'stage': stage,
      'sample_time_utc': sampleTimeUtc.toIso8601String(),
      'room_hash': roomHash,
      'publisher_identity_hash': publisherIdentityHash,
      'receiver_identity_hash': receiverIdentityHash,
      'track_sid_hash': trackSidHash,
      'track_source': trackSource,
      'subscription_state': subscriptionState,
      'subscribed_quality': subscribedQuality,
      'simulcast_layer': simulcastLayer,
      'codec': codec,
      'decoder_implementation': decoderImplementation,
      'hardware_decode': hardwareDecode,
      'renderer_attached': rendererAttached,
      'renderer_visible': rendererVisible,
      'renderer_width': rendererWidth,
      'renderer_height': rendererHeight,
      'bitrate_bps': bitrateBps,
      'inbound_bitrate_bps': inboundBitrateBps ?? bitrateBps,
      'received_width': receivedWidth,
      'received_height': receivedHeight,
      'decoded_width': decodedWidth,
      'decoded_height': decodedHeight,
      'rendered_width': renderedWidth,
      'rendered_height': renderedHeight,
      'receiver_fps': receiverFps,
      'received_fps': receivedFps,
      'decoded_fps': decodedFps,
      'rendered_fps': renderedFps,
      'receiver_stats_sample_window_ms': receiverStatsSampleWindowMs,
      'packets_received': packetsReceived,
      'packets_lost': packetsLost,
      'receiver_jitter_ms': receiverJitterMs,
      'pli_count': pliCount,
      'pli_delta': pliDelta,
      'fir_count': firCount,
      'fir_delta': firDelta,
      'nack_count': nackCount,
      'nack_delta': nackDelta,
      'key_frames_decoded': keyFramesDecoded,
      'key_frames_decoded_delta': keyFramesDecodedDelta,
      'keyframe_interval_frames': keyframeIntervalFrames,
      'keyframe_interval_ms': keyframeIntervalMs,
      'qp_sum': qpSum,
      'average_qp': averageQp,
      'frames_received': framesReceived,
      'frames_decoded': framesDecoded,
      'frames_rendered': framesRendered,
      'render_fps': renderFps,
      'freshness_source': freshnessSource,
      'frame_hash_algorithm': frameHashAlgorithm,
      'frame_hash_sample_count': frameHashSampleCount,
      'frame_hash_error_count': frameHashErrorCount,
      'last_frame_captured_at_utc': lastFrameCapturedAtUtc?.toIso8601String(),
      'unique_frames': uniqueFrames,
      'duplicate_frames': duplicateFrames,
      'unique_fps': uniqueFps,
      'p50_gap_ms': p50GapMs,
      'p95_gap_ms': p95GapMs,
      'max_gap_ms': maxGapMs,
      'longest_stale_run_ms': longestStaleRunMs,
      'frame_presentation_p50_gap_ms': framePresentationP50GapMs,
      'frame_presentation_p95_gap_ms': framePresentationP95GapMs,
      'frame_presentation_max_gap_ms': framePresentationMaxGapMs,
      'frame_presentation_latest_gap_ms': framePresentationLatestGapMs,
      'perceptual_difference_score': perceptualDifferenceScore,
      'native_frame_sequence': nativeFrameSequence,
      'native_frame_sequence_gaps': nativeFrameSequenceGaps,
      'native_frame_event_delay_ms': nativeFrameEventDelayMs,
      'native_frame_event_delay_max_ms': nativeFrameEventDelayMaxMs,
      'dropped_or_replaced_texture_updates': droppedOrReplacedTextureUpdates,
      'upscaling_lower_layer_suspected': upscalingLowerLayerSuspected,
      'adaptive_stream_low_layer_suspected': adaptiveStreamLowLayerSuspected,
      'stage_source': stageSource,
      'stage_observed_at_utc': stageObservedAtUtc?.toIso8601String(),
      'stage_observed_gap_ms': stageObservedGapMs,
      'stage_frame_age_ms': stageFrameAgeMs,
      'stage_native_frame_sequence': stageNativeFrameSequence,
      'stage_frame_captured_at_utc': stageFrameCapturedAtUtc?.toIso8601String(),
      'renderer_texture_id': rendererTextureId,
      'renderer_callback_to_stage_ms': rendererCallbackToStageMs,
      'frame_id': frameId,
      'frame_id_source': frameIdSource,
      'source_frame_marker_id': sourceFrameMarkerId,
      'source_frame_marker_decoded_frames': sourceFrameMarkerDecodedFrames,
      'source_frame_marker_unique_frames': sourceFrameMarkerUniqueFrames,
      'source_frame_marker_duplicate_frames': sourceFrameMarkerDuplicateFrames,
      'source_frame_marker_unique_fps': sourceFrameMarkerUniqueFps,
      'source_frame_marker_longest_stale_run_ms':
          sourceFrameMarkerLongestStaleRunMs,
      'source_qpc': sourceQpc,
      'stage_qpc': stageQpc,
      'frame_age_ms': frameAgeMs,
      'previous_frame_id': previousFrameId,
      'jitter_buffer_delay_ms': jitterBufferDelayMs,
      'jitter_buffer_emitted_count': jitterBufferEmittedCount,
      'total_decode_time_ms': totalDecodeTimeMs,
      'average_decode_time_ms': averageDecodeTimeMs,
      'frames_dropped': framesDropped,
      'freeze_count': freezeCount,
      'total_freeze_duration_ms': totalFreezeDurationMs,
      'receive_to_decode_ms': receiveToDecodeMs,
      'decode_to_render_ms': decodeToRenderMs,
      'status': status,
    };
  }
}

class MatrixLivekitReceiverProbeSnapshot {
  const MatrixLivekitReceiverProbeSnapshot({
    required this.runId,
    required this.inProcess,
    required this.mode,
    required this.connected,
    required this.subscribed,
    required this.sampleCount,
    this.status,
    this.lastEvent,
  });

  final String runId;
  final bool inProcess;
  final MatrixLivekitReceiverProbeMode mode;
  final bool connected;
  final bool subscribed;
  final int sampleCount;
  final String? status;
  final MatrixLivekitReceiverProbeEvent? lastEvent;

  Map<String, Object?> toJson() {
    return {
      'run_id': runId,
      'in_process': inProcess,
      'mode': mode.label,
      'connected': connected,
      'subscribed': subscribed,
      'sample_count': sampleCount,
      'status': status,
      'last_event': lastEvent?.toJson(),
    };
  }
}

class MatrixLivekitLocalPreviewProbeOptions {
  const MatrixLivekitLocalPreviewProbeOptions({
    required this.runId,
    required this.roomId,
    required this.publisherIdentity,
    this.sampleInterval = const Duration(seconds: 1),
    this.frameHashStartDelay = const Duration(seconds: 2),
    this.frameHashWindow = const Duration(seconds: 3),
  });

  final String runId;
  final String roomId;
  final String publisherIdentity;
  final Duration sampleInterval;
  final Duration frameHashStartDelay;
  final Duration frameHashWindow;
}

class MatrixLivekitLocalPreviewProbeController {
  MatrixLivekitLocalPreviewProbeController({
    required MatrixLivekitLocalPreviewProbeOptions options,
  }) : _options = options;

  final MatrixLivekitLocalPreviewProbeOptions _options;
  final _events = StreamController<MatrixLivekitReceiverProbeEvent>.broadcast();
  final Map<String, _FrameHashFreshnessTracker> _frameHashTrackers = {};

  lk.LocalTrackPublication<lk.LocalVideoTrack>? _publication;
  rtc.RTCVideoRenderer? _renderer;
  Timer? _sampleTimer;
  DateTime? _frameHashAvailableAt;
  MatrixLivekitReceiverProbeEvent? _lastEvent;
  String? _status;
  int _sampleCount = 0;
  int _frameHashFailureCount = 0;
  bool _stopping = false;

  Stream<MatrixLivekitReceiverProbeEvent> get events => _events.stream;

  String? get publicationSid => _publication?.sid;

  Map<String, Object?> get snapshot {
    return {
      'run_id': _options.runId,
      'in_process': true,
      'mode': 'local-preview',
      'attached': _renderer != null,
      'sample_count': _sampleCount,
      'status': _status,
      'last_event': _lastEvent?.toJson(),
    };
  }

  Future<void> start(
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
  ) async {
    if (_renderer != null) {
      return;
    }
    final track = publication.track;
    if (track == null) {
      throw StateError('Local screen-share video track is unavailable.');
    }

    _stopping = false;
    _publication = publication;
    _frameHashAvailableAt = DateTime.now().toUtc().add(
      _options.frameHashStartDelay,
    );
    _status = 'local_preview_frame_hash_tap_pending';
    _frameHashTrackers.clear();
    _frameHashFailureCount = 0;

    await _startNativeFrameHashTap(track, publication);
    _startSampling();
    unawaited(_sampleLocalPreview());
  }

  Future<void> stop() async {
    _stopping = true;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _status = 'stopped';
    await _disposeNativeFrameHashTap();
    _publication = null;
    _frameHashAvailableAt = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  void _startSampling() {
    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(
      _options.sampleInterval,
      (_) => unawaited(_sampleLocalPreview()),
    );
  }

  Future<void> _startNativeFrameHashTap(
    lk.LocalVideoTrack track,
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
  ) async {
    await _disposeNativeFrameHashTap();
    final renderer = rtc.RTCVideoRenderer();
    try {
      await renderer.initialize();
      if (_stopping || _publication?.sid != publication.sid) {
        await _runMatrixLivekitReceiverProbeCleanup(
          operation: 'local-preview-stale-renderer-dispose',
          cleanup: renderer.dispose,
        );
        return;
      }

      final textureId = renderer.textureId;
      if (textureId == null) {
        throw StateError('local preview renderer texture was unavailable');
      }

      (renderer as dynamic).onIntergalacticFrameRendered = (dynamic event) =>
          _onNativeFrameTapEvent(publication, event);

      await rtc.WebRTC.invokeMethod<void, Map<String, Object?>>(
        'intergalacticVideoRendererSetFrameDiagnostics',
        {'textureId': textureId, 'enabled': true},
      );

      renderer.srcObject = track.mediaStream;
      _renderer = renderer;
      _status = 'local_preview_frame_hash_tap_attached';
      _log(
        'Local preview frame-hash tap attached '
        'trackSidHash=${_trackSidLogHash(publication)} textureId=$textureId',
      );
    } catch (_) {
      _frameHashFailureCount++;
      _renderer = null;
      _status = 'local_preview_frame_hash_tap_unavailable';
      _log(
        'Local preview frame-hash tap unavailable '
        'trackSidHash=${_trackSidLogHash(publication)}',
      );
      try {
        (renderer as dynamic).onIntergalacticFrameRendered = null;
      } catch (_) {
        // The unpatched package does not expose this callback.
      }
      try {
        renderer.srcObject = null;
      } catch (_) {
        // Best-effort cleanup for partially initialized renderers.
      }
      await _runMatrixLivekitReceiverProbeCleanup(
        operation: 'local-preview-partial-renderer-dispose',
        cleanup: renderer.dispose,
      );
    }
  }

  Future<void> _disposeNativeFrameHashTap() async {
    final renderer = _renderer;
    _renderer = null;
    if (renderer == null) {
      return;
    }

    try {
      (renderer as dynamic).onIntergalacticFrameRendered = null;
    } catch (_) {
      // The unpatched package does not expose this callback.
    }
    final textureId = renderer.textureId;
    if (textureId != null) {
      try {
        await rtc.WebRTC.invokeMethod<void, Map<String, Object?>>(
          'intergalacticVideoRendererSetFrameDiagnostics',
          {'textureId': textureId, 'enabled': false},
        );
      } catch (_) {
        // The method exists only in the Inter Galactic patched Windows bridge.
      }
    }
    try {
      renderer.srcObject = null;
    } catch (_) {
      // Best-effort cleanup.
    }
    await _runMatrixLivekitReceiverProbeCleanup(
      operation: 'local-preview-renderer-dispose',
      cleanup: renderer.dispose,
    );
  }

  void _onNativeFrameTapEvent(
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
    dynamic event,
  ) {
    if (_stopping || _publication?.sid != publication.sid) {
      return;
    }
    if (event is! Map<dynamic, dynamic> ||
        event['event'] != _nativeRendererFrameEvent) {
      return;
    }
    final frameHashAvailableAt = _frameHashAvailableAt;
    if (frameHashAvailableAt != null &&
        DateTime.now().toUtc().isBefore(frameHashAvailableAt)) {
      return;
    }

    final frameHash = _stringFromValue(event['luma_hash']);
    if (frameHash == null || frameHash.isEmpty) {
      _recordFrameHashFailure(publication);
      return;
    }

    final tracker = _frameHashTrackers.putIfAbsent(
      _frameHashKey(publication),
      () => _FrameHashFreshnessTracker(
        window: _options.frameHashWindow,
        hashAlgorithm: _nativeRendererFrameHashAlgorithm,
      ),
    );
    final capturedAtUtc = DateTime.now().toUtc();
    final nativeTimestampUnixMs = _intFromProbeValue(
      event['timestamp_unix_ms'],
    );
    final rtpFrameId = _intFromProbeValue(event['frame_id']);
    final sourceFrameMarkerId = _intFromProbeValue(
      event['source_frame_marker_id'],
    );
    final effectiveFrameId = rtpFrameId ?? sourceFrameMarkerId;
    final frameIdSource = rtpFrameId != null
        ? 'rtp_frame_id'
        : sourceFrameMarkerId != null
        ? 'source_frame_content_marker'
        : null;
    tracker.addSample(
      capturedAtUtc: capturedAtUtc,
      frameHash: frameHash,
      nativeSequence: _intFromProbeValue(event['sequence']),
      nativeTimestampUnixMs: nativeTimestampUnixMs,
      frameWidth: _intFromProbeValue(event['width']),
      frameHeight: _intFromProbeValue(event['height']),
      frameId: effectiveFrameId,
      frameIdSource: frameIdSource,
      sourceFrameMarkerId: sourceFrameMarkerId,
      sourceQpc: _intFromProbeValue(event['source_qpc']),
      stageQpc: _intFromProbeValue(event['stage_qpc']),
      frameAgeMs: _doubleFromProbeValue(event['frame_age_ms']),
      nativeEventDelayMs: _nativeFrameEventDelayMs(
        capturedAtUtc: capturedAtUtc,
        nativeTimestampUnixMs: nativeTimestampUnixMs,
      ),
    );
    _status = 'frame_hash_tap_active';
    if (tracker.sampleCount <= 3 || tracker.sampleCount % 30 == 0) {
      _log(
        'Local preview frame-hash sample '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'samples=${tracker.sampleCount}',
      );
    }
  }

  void _recordFrameHashFailure(
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
  ) {
    _frameHashFailureCount++;
    _status = 'frame_hash_tap_capture_failed';
    _log(
      'Local preview frame-hash capture failed '
      'trackSidHash=${_trackSidLogHash(publication)} '
      'failures=$_frameHashFailureCount',
    );
  }

  Future<void> _sampleLocalPreview() async {
    final publication = _publication;
    if (publication == null || _stopping) {
      return;
    }
    final frameHashKey = _frameHashKey(publication);
    final freshness = _frameHashTrackers[frameHashKey]?.summary(
      DateTime.now().toUtc(),
    );
    final status = freshness == null
        ? _frameHashFailureCount > 0
              ? 'frame_hash_tap_capture_failed'
              : 'local_preview_frame_hash_tap_pending'
        : 'frame_hash_tap_active';
    final event = _eventFromLocalPreview(
      publication: publication,
      freshness: freshness,
      status: status,
    );
    _sampleCount++;
    _lastEvent = event;
    _status = event.status;
    _log(
      'Local preview probe event emitted '
      'status=${event.status} uniqueFps=${event.uniqueFps ?? 'n/a'}',
    );
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  MatrixLivekitReceiverProbeEvent _eventFromLocalPreview({
    required lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
    required _FrameHashFreshnessSummary? freshness,
    required String status,
  }) {
    final renderer = _renderer;
    return MatrixLivekitReceiverProbeEvent(
      marker: intergalacticStreamViewProbeMarker,
      runId: _options.runId,
      inProcess: true,
      lane: 'local_preview',
      sampleTimeUtc: DateTime.now().toUtc(),
      roomHash: _hash(_options.roomId),
      publisherIdentityHash: _hash(_options.publisherIdentity),
      receiverIdentityHash: _hash(
        '${_options.publisherIdentity}:local-preview',
      ),
      trackSidHash: publication.sid.isEmpty ? null : _hash(publication.sid),
      trackSource: publication.source.name,
      subscriptionState: 'local',
      subscribedQuality: 'local',
      simulcastLayer: publication.simulcasted ? 'simulcast' : 'single',
      codec: null,
      decoderImplementation: null,
      hardwareDecode: null,
      rendererAttached: renderer != null,
      rendererVisible: renderer != null,
      rendererWidth: renderer?.videoWidth,
      rendererHeight: renderer?.videoHeight,
      bitrateBps: null,
      framesReceived: null,
      framesDecoded: null,
      framesRendered: freshness?.sampleCount,
      renderFps: freshness?.uniqueFps,
      renderedWidth: renderer?.videoWidth ?? freshness?.frameWidth,
      renderedHeight: renderer?.videoHeight ?? freshness?.frameHeight,
      freshnessSource: freshness?.source,
      frameHashAlgorithm: freshness?.hashAlgorithm,
      frameHashSampleCount: freshness?.sampleCount,
      frameHashErrorCount: _frameHashFailureCount > 0
          ? _frameHashFailureCount
          : null,
      lastFrameCapturedAtUtc: freshness?.lastCapturedAtUtc,
      uniqueFrames: freshness?.uniqueFrames,
      duplicateFrames: freshness?.duplicateFrames,
      uniqueFps: freshness?.uniqueFps,
      p50GapMs: freshness?.p50GapMs,
      p95GapMs: freshness?.p95GapMs,
      maxGapMs: freshness?.maxGapMs,
      longestStaleRunMs: freshness?.longestStaleRunMs,
      framePresentationP50GapMs: freshness?.presentationP50GapMs,
      framePresentationP95GapMs: freshness?.presentationP95GapMs,
      framePresentationMaxGapMs: freshness?.presentationMaxGapMs,
      framePresentationLatestGapMs: freshness?.presentationLatestGapMs,
      perceptualDifferenceScore: freshness?.perceptualDifferenceScore,
      nativeFrameSequence: freshness?.nativeFrameSequence,
      nativeFrameSequenceGaps: freshness?.nativeFrameSequenceGaps,
      nativeFrameEventDelayMs: freshness?.nativeFrameEventDelayMs,
      nativeFrameEventDelayMaxMs: freshness?.nativeFrameEventDelayMaxMs,
      droppedOrReplacedTextureUpdates:
          freshness?.droppedOrReplacedTextureUpdates,
      frameId: freshness?.frameId,
      frameIdSource: freshness?.frameIdSource,
      sourceFrameMarkerId: freshness?.sourceFrameMarkerId,
      sourceFrameMarkerDecodedFrames: freshness?.sourceFrameMarkerDecodedFrames,
      sourceFrameMarkerUniqueFrames: freshness?.sourceFrameMarkerUniqueFrames,
      sourceFrameMarkerDuplicateFrames:
          freshness?.sourceFrameMarkerDuplicateFrames,
      sourceFrameMarkerUniqueFps: freshness?.sourceFrameMarkerUniqueFps,
      sourceFrameMarkerLongestStaleRunMs:
          freshness?.sourceFrameMarkerLongestStaleRunMs,
      sourceQpc: freshness?.sourceQpc,
      stageQpc: freshness?.stageQpc,
      frameAgeMs: freshness?.frameAgeMs,
      previousFrameId: freshness?.previousFrameId,
      jitterBufferDelayMs: null,
      jitterBufferEmittedCount: null,
      totalDecodeTimeMs: null,
      averageDecodeTimeMs: null,
      framesDropped: null,
      freezeCount: null,
      totalFreezeDurationMs: null,
      receiveToDecodeMs: null,
      decodeToRenderMs: null,
      status: status,
    );
  }

  String _frameHashKey(
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
  ) {
    final sid = publication.sid;
    return sid.isEmpty ? 'unknown-local-publication' : sid;
  }

  String _trackSidLogHash(
    lk.LocalTrackPublication<lk.LocalVideoTrack> publication,
  ) {
    final sid = publication.sid;
    if (sid.isEmpty) {
      return 'sha256:unknown';
    }
    return 'sha256:${sha256.convert(utf8.encode(sid)).toString().substring(0, 12)}';
  }

  String _hash(String value) {
    return 'sha256:${sha256.convert(utf8.encode(value))}';
  }

  String? _stringFromValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  void _log(String message) {
    Log.i(message, category: LogCategory.webrtc, source: 'local-preview-probe');
  }
}

class MatrixLivekitReceiverProbeController {
  MatrixLivekitReceiverProbeController({
    required MatrixLivekitReceiverProbeOptions options,
  }) : _options = options;

  final MatrixLivekitReceiverProbeOptions _options;
  final _events = StreamController<MatrixLivekitReceiverProbeEvent>.broadcast();
  final Map<String, _StatsSample> _receiverStatsSamples = {};
  final Map<String, _JitterBufferSample> _jitterBufferSamples = {};
  final Map<String, _DurationCounterSample> _decodeTimeSamples = {};
  final Map<String, _ReceiverQualitySample> _receiverQualitySamples = {};
  final Map<String, _FrameHashFreshnessTracker> _frameHashTrackers = {};
  final Map<String, int> _frameHashFailures = {};

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  lk.RemoteTrackPublication? _activePublication;
  lk.RemoteVideoTrack? _activeTrack;
  rtc.RTCVideoRenderer? _frameTapRenderer;
  lk.RemoteTrackPublication? _frameTapPublication;
  Timer? _statsTimer;
  Timer? _frameHashTimer;
  DateTime? _frameHashAvailableAt;
  String? _receiverIdentity;
  String? _status;
  MatrixLivekitReceiverProbeEvent? _lastEvent;
  MatrixLivekitReceiverProbeEvent? _latestRendererCallbackEvent;
  final Map<String, int?> _lastPresentationStageSequence = {};
  final Map<String, DateTime> _lastPresentationStageObservedAt = {};
  int _sampleCount = 0;
  int _subscriptionGeneration = 0;
  int _frameTapGeneration = 0;
  int _nativeFrameTapFailures = 0;
  bool _stopping = false;
  bool _frameHashSampleInFlight = false;
  bool _nativeFrameTapEnabled = false;
  bool _rendererVisible = false;

  Stream<MatrixLivekitReceiverProbeEvent> get events => _events.stream;

  rtc.RTCVideoRenderer? get renderer => _frameTapRenderer;

  lk.RemoteVideoTrack? get visibleTrack => _activeTrack;

  bool get _nativeFrameHashDiagnosticsRequested =>
      _options.frameHashTapEnabled &&
      _options.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash;

  bool get _captureFrameHashFallbackRequested =>
      _options.frameHashTapEnabled &&
      _options.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash;

  bool get _frameDiagnosticsDisabled =>
      !_options.frameHashTapEnabled ||
      _options.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.statsOnly;

  void setRendererVisible(bool visible) {
    _rendererVisible = visible;
  }

  void recordRendererTextureReady({
    String source = 'receiver_probe_texture_view',
  }) {
    _emitPresentationStage(
      stage: MatrixLivekitReceiverProbePresentationStage.remoteTextureReady,
      status: 'remote_texture_ready_reported',
      source: source,
    );
  }

  void recordRendererUiPaint({String source = 'receiver_probe_flutter_paint'}) {
    _emitPresentationStage(
      stage: MatrixLivekitReceiverProbePresentationStage.remoteUiPaint,
      status: 'remote_ui_paint_reported',
      source: source,
    );
  }

  void recordRendererScreenPresent({
    String source = 'receiver_probe_flutter_frame_timing',
  }) {
    _emitPresentationStage(
      stage: MatrixLivekitReceiverProbePresentationStage.remoteScreenPresent,
      status: 'remote_screen_present_reported',
      source: source,
    );
  }

  MatrixLivekitReceiverProbeSnapshot get snapshot {
    return MatrixLivekitReceiverProbeSnapshot(
      runId: _options.runId,
      inProcess: _options.inProcess,
      mode: _options.mode,
      connected: _room != null,
      subscribed: _activeTrack != null,
      sampleCount: _sampleCount,
      status: _status,
      lastEvent: _lastEvent,
    );
  }

  Future<void> start(MatrixLivekitReceiverProbeCredentials credentials) async {
    if (_room != null) {
      return;
    }
    _stopping = false;

    final room = lk.Room(
      roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false),
    );
    lk.EventsListener<lk.RoomEvent>? listener;
    try {
      listener = room.createListener();
      listener.on(_onTrackPublished);
      listener.on(_onTrackSubscribed);
      listener.on(_onTrackUnsubscribed);
      listener.on(_onTrackUnpublished);
      listener.on(_onTrackSubscriptionException);
      listener.on(_onRoomDisconnected);

      await room
          .connect(
            credentials.sfuUrl,
            credentials.jwt,
            connectOptions: const lk.ConnectOptions(autoSubscribe: false),
          )
          .timeout(_options.connectTimeout);
      _room = room;
      _listener = listener;
      _receiverIdentity = credentials.probeIdentity;
      _status = 'connected_waiting_for_screenshare';
      await _subscribeExistingScreenshareTracks();
      _startSampling();
    } catch (_) {
      await _runMatrixLivekitReceiverProbeCleanup(
        operation: 'receiver-probe-start-failure-listener-dispose',
        cleanup: listener?.dispose,
      );
      await _runMatrixLivekitReceiverProbeCleanup(
        operation: 'receiver-probe-start-failure-room-disconnect',
        cleanup: room.disconnect,
      );
      await _runMatrixLivekitReceiverProbeCleanup(
        operation: 'receiver-probe-start-failure-room-dispose',
        cleanup: room.dispose,
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    _stopping = true;
    _statsTimer?.cancel();
    _frameHashTimer?.cancel();
    _statsTimer = null;
    _frameHashTimer = null;
    _subscriptionGeneration++;
    _frameTapGeneration++;
    _rendererVisible = false;
    await _disposeNativeFrameHashTap();
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    _activePublication = null;
    _activeTrack = null;
    _frameHashAvailableAt = null;
    _latestRendererCallbackEvent = null;
    _lastPresentationStageSequence.clear();
    _lastPresentationStageObservedAt.clear();
    _status = 'stopped';

    await _runMatrixLivekitReceiverProbeCleanup(
      operation: 'receiver-probe-listener-dispose',
      cleanup: listener?.dispose,
    );
    await _runMatrixLivekitReceiverProbeCleanup(
      operation: 'receiver-probe-room-disconnect',
      cleanup: room == null ? null : () => room.disconnect(),
    );
    await _runMatrixLivekitReceiverProbeCleanup(
      operation: 'receiver-probe-room-dispose',
      cleanup: room?.dispose,
    );
  }

  Future<void> dispose() async {
    await stop();
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  Future<void> _subscribeExistingScreenshareTracks() async {
    final room = _room;
    if (room == null) {
      return;
    }

    var found = false;
    for (final participant in room.remoteParticipants.values) {
      if (participant.identity != _options.publisherIdentity) {
        continue;
      }
      for (final publication in participant.trackPublications.values) {
        if (_isSelectedScreenShare(publication, participant.identity)) {
          found = true;
          _log(
            'Receiver probe selected existing screen share '
            'trackSidHash=${_trackSidLogHash(publication)} '
            'subscriptionDelayMs=${_options.subscriptionDelay.inMilliseconds}',
          );
          unawaited(_subscribeSelectedPublication(publication));
        }
      }
    }

    if (!found) {
      _status = 'waiting_for_selected_screenshare';
    }
  }

  void _onTrackPublished(lk.TrackPublishedEvent event) {
    if (!_isSelectedScreenShare(
      event.publication,
      event.participant.identity,
    )) {
      return;
    }
    _log(
      'Receiver probe selected published screen share '
      'trackSidHash=${_trackSidLogHash(event.publication)} '
      'subscriptionDelayMs=${_options.subscriptionDelay.inMilliseconds}',
    );
    unawaited(_subscribeSelectedPublication(event.publication));
  }

  void _onTrackSubscribed(lk.TrackSubscribedEvent event) {
    if (!_isSelectedScreenShare(
      event.publication,
      event.participant.identity,
    )) {
      unawaited(
        _runMatrixLivekitReceiverProbePublicationOperation(
          operation: 'unselected-track-unsubscribe',
          publicationOperation: event.publication.unsubscribe,
        ),
      );
      return;
    }
    final track = event.track;
    if (track is! lk.RemoteVideoTrack) {
      unawaited(
        _runMatrixLivekitReceiverProbePublicationOperation(
          operation: 'non-video-track-unsubscribe',
          publicationOperation: event.publication.unsubscribe,
        ),
      );
      return;
    }

    _activePublication = event.publication;
    _activeTrack = track;
    _frameHashAvailableAt = DateTime.now().toUtc().add(
      _options.frameHashStartDelay,
    );
    _receiverStatsSamples.clear();
    _jitterBufferSamples.clear();
    _decodeTimeSamples.clear();
    _receiverQualitySamples.clear();
    _frameHashTrackers.clear();
    _frameHashFailures.clear();
    _latestRendererCallbackEvent = null;
    _lastPresentationStageSequence.clear();
    _lastPresentationStageObservedAt.clear();
    _nativeFrameTapFailures = 0;
    _status = _frameDiagnosticsDisabled
        ? 'subscribed_stats_only_frame_diagnostics_disabled'
        : 'subscribed_stats_only_frame_hash_tap_pending';
    _log(
      'Receiver probe subscribed to screen share '
      'trackSidHash=${_trackSidLogHash(event.publication)} '
      'frameDiagnosticsMode=${_options.frameDiagnosticsMode.label} '
      'frameHashStartDelayMs=${_options.frameHashStartDelay.inMilliseconds}',
    );
    unawaited(_startNativeFrameHashTap(track, event.publication));
    unawaited(_sampleActiveFrameHash());
    unawaited(_sampleActiveTrack());
  }

  void _onTrackUnsubscribed(lk.TrackUnsubscribedEvent event) {
    if (event.publication.sid != _activePublication?.sid) {
      return;
    }
    _activePublication = null;
    _activeTrack = null;
    _frameHashAvailableAt = null;
    _latestRendererCallbackEvent = null;
    _lastPresentationStageSequence.clear();
    _lastPresentationStageObservedAt.clear();
    _status = 'unsubscribed';
    unawaited(_disposeNativeFrameHashTap());
  }

  void _onTrackUnpublished(lk.TrackUnpublishedEvent event) {
    if (event.publication.sid != _activePublication?.sid) {
      return;
    }
    _activePublication = null;
    _activeTrack = null;
    _frameHashAvailableAt = null;
    _status = 'ended';
    unawaited(_disposeNativeFrameHashTap());
  }

  void _onTrackSubscriptionException(lk.TrackSubscriptionExceptionEvent event) {
    _status = 'subscription_failed:${event.reason.name}';
  }

  void _onRoomDisconnected(lk.RoomDisconnectedEvent event) {
    if (_stopping) {
      return;
    }
    _status = 'disconnected${event.reason == null ? '' : ':${event.reason}'}';
    _activePublication = null;
    _activeTrack = null;
    _frameHashAvailableAt = null;
    unawaited(_disposeNativeFrameHashTap());
  }

  Future<void> _subscribe(lk.RemoteTrackPublication publication) async {
    _log(
      'Receiver probe subscription quality request starting '
      'trackSidHash=${_trackSidLogHash(publication)}',
    );
    await publication.setVideoQuality(lk.VideoQuality.HIGH);
    _log(
      'Receiver probe subscription enable request starting '
      'trackSidHash=${_trackSidLogHash(publication)}',
    );
    await publication.enable();
    _log(
      'Receiver probe subscription subscribe request starting '
      'trackSidHash=${_trackSidLogHash(publication)} '
      'timeoutMs=${_options.subscriptionTimeout.inMilliseconds}',
    );
    await publication.subscribe().timeout(_options.subscriptionTimeout);
    try {
      await publication.setVideoQuality(lk.VideoQuality.HIGH);
    } catch (error) {
      _log(
        'Receiver probe post-subscribe quality request failed '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'reason=${Log.redactSensitiveInfo(error.toString())}',
      );
    }
    _status = 'subscribe_requested';
    _log(
      'Receiver probe subscription subscribe request completed '
      'trackSidHash=${_trackSidLogHash(publication)}',
    );
  }

  Future<void> _subscribeSelectedPublication(
    lk.RemoteTrackPublication publication,
  ) async {
    final generation = ++_subscriptionGeneration;
    final delay = _options.subscriptionDelay;
    if (delay.inMilliseconds > 0) {
      _status = 'subscription_deferred';
      _log(
        'Receiver probe subscription deferred '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'delayMs=${delay.inMilliseconds}',
      );
      await Future<void>.delayed(delay);
      if (!_isCurrentSubscriptionAttempt(publication, generation)) {
        _log(
          'Receiver probe subscription deferred attempt skipped '
          'trackSidHash=${_trackSidLogHash(publication)}',
        );
        return;
      }
    }

    if (!_isCurrentSubscriptionAttempt(publication, generation)) {
      _log(
        'Receiver probe subscription attempt skipped '
        'trackSidHash=${_trackSidLogHash(publication)}',
      );
      return;
    }
    try {
      await _subscribe(publication);
    } catch (_) {
      _status = 'subscription_failed_or_timed_out';
      _log(
        'Receiver probe subscription request failed or timed out '
        'trackSidHash=${_trackSidLogHash(publication)}',
      );
    }
  }

  bool _isCurrentSubscriptionAttempt(
    lk.RemoteTrackPublication publication,
    int generation,
  ) {
    if (_stopping || _room == null || generation != _subscriptionGeneration) {
      return false;
    }
    final activePublication = _activePublication;
    return activePublication == null ||
        activePublication.sid != publication.sid;
  }

  bool _isSelectedScreenShare(
    lk.RemoteTrackPublication publication,
    String participantIdentity,
  ) {
    return participantIdentity == _options.publisherIdentity &&
        publication.kind == lk.TrackType.VIDEO &&
        (publication.source == lk.TrackSource.screenShareVideo ||
            publication.isScreenShare);
  }

  void _startSampling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      _options.sampleInterval,
      (_) => unawaited(_sampleActiveTrack()),
    );
    _frameHashTimer?.cancel();
    if (!_captureFrameHashFallbackRequested) {
      return;
    }
    _frameHashTimer = Timer.periodic(
      _options.frameHashInterval,
      (_) => unawaited(_sampleActiveFrameHash()),
    );
  }

  Future<void> _sampleActiveFrameHash() async {
    if (!_captureFrameHashFallbackRequested || _frameHashSampleInFlight) {
      return;
    }
    if (_nativeFrameTapEnabled || _frameTapRenderer != null) {
      return;
    }
    final track = _activeTrack;
    final publication = _activePublication;
    if (track == null || publication == null) {
      return;
    }
    final frameHashAvailableAt = _frameHashAvailableAt;
    if (frameHashAvailableAt != null &&
        DateTime.now().toUtc().isBefore(frameHashAvailableAt)) {
      return;
    }

    _frameHashSampleInFlight = true;
    try {
      final frameBuffer = await track.mediaStreamTrack.captureFrame().timeout(
        _options.frameHashTimeout,
      );
      final bytes = frameBuffer.asUint8List();
      if (bytes.isEmpty) {
        _recordFrameHashFailure(publication);
        return;
      }

      final tracker = _frameHashTrackers.putIfAbsent(
        _frameHashKey(publication),
        () => _FrameHashFreshnessTracker(
          window: _options.frameHashWindow,
          hashAlgorithm: _captureFrameHashAlgorithm,
        ),
      );
      tracker.addSample(
        capturedAtUtc: DateTime.now().toUtc(),
        frameHash: sha256.convert(bytes).toString(),
      );
      _status = 'frame_hash_tap_active';
      if (tracker.sampleCount <= 3 || tracker.sampleCount % 10 == 0) {
        _log(
          'Receiver probe frame-hash capture completed '
          'trackSidHash=${_trackSidLogHash(publication)} '
          'samples=${tracker.sampleCount}',
        );
      }
    } catch (_) {
      _recordFrameHashFailure(publication);
    } finally {
      _frameHashSampleInFlight = false;
    }
  }

  Future<void> _startNativeFrameHashTap(
    lk.RemoteVideoTrack track,
    lk.RemoteTrackPublication publication,
  ) async {
    final diagnosticsEnabled = _nativeFrameHashDiagnosticsRequested;
    final shouldAttachRenderer =
        diagnosticsEnabled ||
        _options.mode == MatrixLivekitReceiverProbeMode.render;
    if (!shouldAttachRenderer) {
      await _disposeNativeFrameHashTap();
      _status = 'stats_only_frame_diagnostics_disabled';
      return;
    }

    await _disposeNativeFrameHashTap();
    final generation = ++_frameTapGeneration;
    final renderer = rtc.RTCVideoRenderer();

    try {
      await renderer.initialize();
      if (!_isCurrentFrameTap(publication, generation)) {
        await _runMatrixLivekitReceiverProbeCleanup(
          operation: 'receiver-probe-stale-renderer-dispose',
          cleanup: renderer.dispose,
        );
        return;
      }

      final textureId = renderer.textureId;
      if (textureId == null) {
        throw StateError('receiver probe renderer texture was unavailable');
      }

      if (diagnosticsEnabled) {
        (renderer as dynamic).onIntergalacticFrameRendered = (dynamic event) =>
            _onNativeFrameTapEvent(publication, event);
      }
      renderer.srcObject = track.mediaStream;
      _frameTapRenderer = renderer;
      _frameTapPublication = publication;

      if (!_options.inProcess) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      if (diagnosticsEnabled) {
        await rtc.WebRTC.invokeMethod<void, Map<String, Object?>>(
          'intergalacticVideoRendererSetFrameDiagnostics',
          {'textureId': textureId, 'enabled': true},
        );
      }

      _nativeFrameTapEnabled = diagnosticsEnabled;
      _status = diagnosticsEnabled
          ? 'native_frame_hash_tap_attached'
          : 'stats_only_renderer_attached';
      _log(
        'Receiver probe renderer attached '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'textureId=$textureId '
        'frameDiagnosticsMode=${_options.frameDiagnosticsMode.label}',
      );
    } catch (error) {
      if (diagnosticsEnabled) {
        _nativeFrameTapFailures++;
      }
      _nativeFrameTapEnabled = false;
      _frameTapRenderer = null;
      _frameTapPublication = null;
      _status = diagnosticsEnabled
          ? 'native_frame_hash_tap_unavailable'
          : 'stats_only_renderer_unavailable';
      _log(
        'Receiver probe renderer unavailable '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'frameDiagnosticsMode=${_options.frameDiagnosticsMode.label} '
        'reason=${Log.redactSensitiveInfo(error.toString())}',
      );
      try {
        (renderer as dynamic).onIntergalacticFrameRendered = null;
      } catch (_) {
        // The unpatched package does not expose this callback.
      }
      try {
        renderer.srcObject = null;
      } catch (_) {
        // Best-effort cleanup for partially initialized renderers.
      }
      await _runMatrixLivekitReceiverProbeCleanup(
        operation: 'receiver-probe-partial-renderer-dispose',
        cleanup: renderer.dispose,
      );
    }
  }

  bool _isCurrentFrameTap(
    lk.RemoteTrackPublication publication,
    int generation,
  ) {
    return !_stopping &&
        generation == _frameTapGeneration &&
        _activePublication?.sid == publication.sid &&
        _activeTrack != null;
  }

  Future<void> _disposeNativeFrameHashTap() async {
    final renderer = _frameTapRenderer;
    _frameTapRenderer = null;
    _frameTapPublication = null;
    _nativeFrameTapEnabled = false;
    if (renderer == null) {
      return;
    }

    try {
      (renderer as dynamic).onIntergalacticFrameRendered = null;
    } catch (_) {
      // The unpatched package does not expose this callback.
    }
    final textureId = renderer.textureId;
    if (textureId != null) {
      try {
        await rtc.WebRTC.invokeMethod<void, Map<String, Object?>>(
          'intergalacticVideoRendererSetFrameDiagnostics',
          {'textureId': textureId, 'enabled': false},
        );
      } catch (_) {
        // The method exists only in the Inter Galactic patched Windows bridge.
      }
    }
    try {
      renderer.srcObject = null;
    } catch (_) {
      // Best-effort cleanup.
    }
    await _runMatrixLivekitReceiverProbeCleanup(
      operation: 'receiver-probe-renderer-dispose',
      cleanup: renderer.dispose,
    );
  }

  void _onNativeFrameTapEvent(
    lk.RemoteTrackPublication publication,
    dynamic event,
  ) {
    if (_stopping || _activePublication?.sid != publication.sid) {
      return;
    }
    if (event is! Map<dynamic, dynamic> ||
        event['event'] != _nativeRendererFrameEvent) {
      return;
    }
    final frameHash = _stringFromStatsValue(event['luma_hash']);
    if (frameHash == null || frameHash.isEmpty) {
      _recordFrameHashFailure(publication);
      return;
    }

    final tracker = _frameHashTrackers.putIfAbsent(
      _frameHashKey(publication),
      () => _FrameHashFreshnessTracker(
        window: _options.frameHashWindow,
        hashAlgorithm: _nativeRendererFrameHashAlgorithm,
      ),
    );
    final capturedAtUtc = DateTime.now().toUtc();
    final nativeTimestampUnixMs = _intFromProbeValue(
      event['timestamp_unix_ms'],
    );
    final rtpFrameId = _intFromProbeValue(event['frame_id']);
    final sourceFrameMarkerId = _intFromProbeValue(
      event['source_frame_marker_id'],
    );
    final effectiveFrameId = rtpFrameId ?? sourceFrameMarkerId;
    final frameIdSource = rtpFrameId != null
        ? 'rtp_frame_id'
        : sourceFrameMarkerId != null
        ? 'source_frame_content_marker'
        : null;
    tracker.addSample(
      capturedAtUtc: capturedAtUtc,
      frameHash: frameHash,
      nativeSequence: _intFromProbeValue(event['sequence']),
      nativeTimestampUnixMs: nativeTimestampUnixMs,
      frameWidth: _intFromProbeValue(event['width']),
      frameHeight: _intFromProbeValue(event['height']),
      frameId: effectiveFrameId,
      frameIdSource: frameIdSource,
      sourceFrameMarkerId: sourceFrameMarkerId,
      sourceQpc: _intFromProbeValue(event['source_qpc']),
      stageQpc: _intFromProbeValue(event['stage_qpc']),
      frameAgeMs: _doubleFromProbeValue(event['frame_age_ms']),
      nativeEventDelayMs: _nativeFrameEventDelayMs(
        capturedAtUtc: capturedAtUtc,
        nativeTimestampUnixMs: nativeTimestampUnixMs,
      ),
    );
    _status = 'frame_hash_tap_active';
    if (tracker.sampleCount <= 3 || tracker.sampleCount % 30 == 0) {
      _log(
        'Receiver probe native frame-hash sample '
        'trackSidHash=${_trackSidLogHash(publication)} '
        'samples=${tracker.sampleCount}',
      );
    }
  }

  void _recordFrameHashFailure(lk.RemoteTrackPublication publication) {
    final key = _frameHashKey(publication);
    _frameHashFailures[key] = (_frameHashFailures[key] ?? 0) + 1;
    _status = 'frame_hash_tap_capture_failed';
    _log(
      'Receiver probe frame-hash capture failed '
      'trackSidHash=${_trackSidLogHash(publication)} '
      'failures=${_frameHashFailures[key]}',
    );
  }

  Future<void> _sampleActiveTrack() async {
    final track = _activeTrack;
    final publication = _activePublication;
    if (track == null || publication == null) {
      return;
    }

    final stat = await _getReceiverStats(track);
    if (stat == null) {
      _status = 'receiver_stats_unavailable';
      return;
    }

    final streamId =
        _stringFromStatsValue(_tryReadStatsValue(() => stat.streamId)) ??
        'unknown-stream';
    final bytesReceived = _numFromStatsValue(
      _tryReadStatsValue(() => stat.bytesReceived),
    );
    final timestamp = _numFromStatsValue(
      _tryReadStatsValue(() => stat.timestamp),
    );

    final key = '${publication.sid}:$streamId';
    final frameHashKey = _frameHashKey(publication);
    final previous = _receiverStatsSamples[key];
    _receiverStatsSamples[key] = _StatsSample(
      bytes: bytesReceived,
      timestamp: timestamp,
    );

    final sampleTimeUtc = DateTime.now().toUtc();
    final bitrateBps = VoipDiagnosticsMath.bitrateBps(
      previousBytes: previous?.bytes,
      currentBytes: bytesReceived,
      previousTimestamp: previous?.timestamp,
      currentTimestamp: timestamp,
    );
    final raw = await _collectRawReceiverDiagnostics(track, key);
    final receiverQuality = _collectReceiverQualityDiagnostics(
      publication: publication,
      stat: stat,
      raw: raw,
      key: key,
      sampleTimeUtc: sampleTimeUtc,
      bitrateBps: bitrateBps,
    );
    final events = _eventsFromStats(
      publication: publication,
      stat: stat,
      raw: raw,
      receiverQuality: receiverQuality,
      freshness: _frameHashTrackers[frameHashKey]?.summary(sampleTimeUtc),
      frameHashFailureCount: _frameHashFailures[frameHashKey] ?? 0,
      nativeFrameTapFailureCount: _nativeFrameTapFailures,
      bitrateBps: bitrateBps,
      sampleTimeUtc: sampleTimeUtc,
    );

    var sawRendererCallback = false;
    for (final event in events) {
      _sampleCount++;
      _lastEvent = event;
      _status = event.status;
      if (event.stage ==
          MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback) {
        _latestRendererCallbackEvent = event;
        sawRendererCallback = true;
      }
      _log(
        'Receiver probe event emitted lane=${event.lane} '
        'stage=${event.stage ?? event.lane} '
        'status=${event.status} uniqueFps=${event.uniqueFps ?? 'n/a'}',
      );
      if (!_events.isClosed) {
        _events.add(event);
      }
    }
    if (sawRendererCallback) {
      recordRendererTextureReady(
        source: 'native_renderer_callback_texture_available',
      );
    }
  }

  Future<dynamic> _getReceiverStats(lk.RemoteVideoTrack track) async {
    try {
      return await track.getReceiverStats().timeout(
        _options.statsTimeout,
        onTimeout: () => null,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Receiver probe failed to collect active track stats',
      );
      return null;
    }
  }

  List<MatrixLivekitReceiverProbeEvent> _eventsFromStats({
    required lk.RemoteTrackPublication publication,
    required dynamic stat,
    required _RawReceiverDiagnostics raw,
    required _ReceiverQualityDiagnostics receiverQuality,
    required _FrameHashFreshnessSummary? freshness,
    required int frameHashFailureCount,
    required int nativeFrameTapFailureCount,
    required int? bitrateBps,
    required DateTime sampleTimeUtc,
  }) {
    final totalFrameTapFailures =
        frameHashFailureCount + nativeFrameTapFailureCount;
    final rendererAttached = _isFrameTapRendererAttached(publication);
    final rendererVisible = rendererAttached && _rendererVisible;
    final decodeStatus = freshness == null
        ? _frameDiagnosticsDisabled
              ? 'stats_only_frame_diagnostics_disabled'
              : totalFrameTapFailures > 0
              ? 'frame_hash_tap_capture_failed'
              : 'stats_only_frame_hash_tap_pending'
        : 'frame_hash_tap_active';
    final decode = _eventFromStats(
      lane: 'remote_decode',
      status: decodeStatus,
      publication: publication,
      stat: stat,
      raw: raw,
      receiverQuality: receiverQuality,
      freshness: freshness,
      frameHashFailureCount: totalFrameTapFailures,
      bitrateBps: bitrateBps,
      sampleTimeUtc: sampleTimeUtc,
    );
    if (_options.mode != MatrixLivekitReceiverProbeMode.render) {
      return [decode];
    }
    final renderStatus = !rendererAttached
        ? 'invalid_unattached_renderer_frame_hash_tap_pending'
        : !rendererVisible
        ? 'invalid_renderer_not_visible'
        : decodeStatus;

    return [
      decode,
      _eventFromStats(
        lane:
            MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
        status: renderStatus,
        publication: publication,
        stat: stat,
        raw: raw,
        receiverQuality: receiverQuality,
        freshness: rendererVisible ? freshness : null,
        frameHashFailureCount: totalFrameTapFailures,
        bitrateBps: bitrateBps,
        sampleTimeUtc: sampleTimeUtc,
      ),
    ];
  }

  MatrixLivekitReceiverProbeEvent _eventFromStats({
    required String lane,
    required String status,
    required lk.RemoteTrackPublication publication,
    required dynamic stat,
    required _RawReceiverDiagnostics raw,
    required _ReceiverQualityDiagnostics receiverQuality,
    required _FrameHashFreshnessSummary? freshness,
    required int frameHashFailureCount,
    required int? bitrateBps,
    required DateTime sampleTimeUtc,
  }) {
    final rendererWidth = _frameTapPublication?.sid == publication.sid
        ? _frameTapRenderer?.videoWidth
        : null;
    final rendererHeight = _frameTapPublication?.sid == publication.sid
        ? _frameTapRenderer?.videoHeight
        : null;
    final renderedWidth =
        receiverQuality.renderedWidth ?? rendererWidth ?? freshness?.frameWidth;
    final renderedHeight =
        receiverQuality.renderedHeight ??
        rendererHeight ??
        freshness?.frameHeight;
    final upscalingLowerLayerSuspected =
        _dimensionUpscaleSuspected(
          decodedWidth: receiverQuality.decodedWidth,
          decodedHeight: receiverQuality.decodedHeight,
          renderedWidth: renderedWidth,
          renderedHeight: renderedHeight,
        ) ??
        receiverQuality.upscalingLowerLayerSuspected;
    final stage = switch (lane) {
      MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback =>
        MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
      'remote_render' =>
        MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
      'remote_decode' =>
        MatrixLivekitReceiverProbePresentationStage.remoteDecode,
      _ => lane,
    };
    return MatrixLivekitReceiverProbeEvent(
      marker: intergalacticStreamViewProbeMarker,
      runId: _options.runId,
      inProcess: _options.inProcess,
      lane: lane,
      stage: stage,
      sampleTimeUtc: sampleTimeUtc,
      roomHash: _hash(_options.roomId),
      publisherIdentityHash: _hash(_options.publisherIdentity),
      receiverIdentityHash: _hash(_receiverIdentity ?? 'unknown-receiver'),
      trackSidHash: publication.sid.isEmpty ? null : _hash(publication.sid),
      trackSource: publication.source.name,
      subscriptionState: publication.subscriptionState.name,
      subscribedQuality: publication.videoQuality.name.toLowerCase(),
      simulcastLayer:
          _stringFromStatsValue(_tryReadStatsValue(() => stat.rid)) ?? 'single',
      codec: _codecLabel(
        _stringFromStatsValue(_tryReadStatsValue(() => stat.mimeType)),
      ),
      decoderImplementation: _stringFromStatsValue(
        _tryReadStatsValue(() => stat.decoderImplementation),
      ),
      hardwareDecode: VoipDiagnosticsMath.isLikelyHardwareEncoder(
        _stringFromStatsValue(
          _tryReadStatsValue(() => stat.decoderImplementation),
        ),
      ),
      rendererAttached: _isFrameTapRendererAttached(publication),
      rendererVisible:
          _isFrameTapRendererAttached(publication) && _rendererVisible,
      rendererWidth: rendererWidth,
      rendererHeight: rendererHeight,
      bitrateBps: bitrateBps,
      inboundBitrateBps: receiverQuality.inboundBitrateBps ?? bitrateBps,
      receivedWidth: receiverQuality.receivedWidth,
      receivedHeight: receiverQuality.receivedHeight,
      decodedWidth: receiverQuality.decodedWidth,
      decodedHeight: receiverQuality.decodedHeight,
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
      receiverFps: receiverQuality.receiverFps,
      receivedFps: receiverQuality.receivedFps,
      decodedFps: receiverQuality.decodedFps,
      renderedFps: receiverQuality.renderedFps,
      receiverStatsSampleWindowMs: receiverQuality.statsSampleWindowMs,
      packetsReceived: receiverQuality.packetsReceived,
      packetsLost: receiverQuality.packetsLost,
      receiverJitterMs: receiverQuality.receiverJitterMs,
      pliCount: receiverQuality.pliCount,
      pliDelta: receiverQuality.pliDelta,
      firCount: receiverQuality.firCount,
      firDelta: receiverQuality.firDelta,
      nackCount: receiverQuality.nackCount,
      nackDelta: receiverQuality.nackDelta,
      keyFramesDecoded: receiverQuality.keyFramesDecoded,
      keyFramesDecodedDelta: receiverQuality.keyFramesDecodedDelta,
      keyframeIntervalFrames: receiverQuality.keyframeIntervalFrames,
      keyframeIntervalMs: receiverQuality.keyframeIntervalMs,
      qpSum: receiverQuality.qpSum,
      averageQp: receiverQuality.averageQp,
      framesReceived: receiverQuality.framesReceived,
      framesDecoded: receiverQuality.framesDecoded,
      framesRendered: receiverQuality.framesRendered,
      renderFps: raw.renderFps,
      freshnessSource: freshness?.source,
      frameHashAlgorithm: freshness?.hashAlgorithm,
      frameHashSampleCount: freshness?.sampleCount,
      frameHashErrorCount: frameHashFailureCount > 0
          ? frameHashFailureCount
          : null,
      lastFrameCapturedAtUtc: freshness?.lastCapturedAtUtc,
      uniqueFrames: freshness?.uniqueFrames,
      duplicateFrames: freshness?.duplicateFrames,
      uniqueFps: freshness?.uniqueFps,
      p50GapMs: freshness?.p50GapMs,
      p95GapMs: freshness?.p95GapMs,
      maxGapMs: freshness?.maxGapMs,
      longestStaleRunMs: freshness?.longestStaleRunMs,
      framePresentationP50GapMs: freshness?.presentationP50GapMs,
      framePresentationP95GapMs: freshness?.presentationP95GapMs,
      framePresentationMaxGapMs: freshness?.presentationMaxGapMs,
      framePresentationLatestGapMs: freshness?.presentationLatestGapMs,
      perceptualDifferenceScore: freshness?.perceptualDifferenceScore,
      nativeFrameSequence: freshness?.nativeFrameSequence,
      nativeFrameSequenceGaps: freshness?.nativeFrameSequenceGaps,
      nativeFrameEventDelayMs: freshness?.nativeFrameEventDelayMs,
      nativeFrameEventDelayMaxMs: freshness?.nativeFrameEventDelayMaxMs,
      droppedOrReplacedTextureUpdates:
          freshness?.droppedOrReplacedTextureUpdates,
      upscalingLowerLayerSuspected: upscalingLowerLayerSuspected,
      adaptiveStreamLowLayerSuspected:
          receiverQuality.adaptiveStreamLowLayerSuspected,
      frameId: freshness?.frameId,
      frameIdSource: freshness?.frameIdSource,
      sourceFrameMarkerId: freshness?.sourceFrameMarkerId,
      sourceFrameMarkerDecodedFrames: freshness?.sourceFrameMarkerDecodedFrames,
      sourceFrameMarkerUniqueFrames: freshness?.sourceFrameMarkerUniqueFrames,
      sourceFrameMarkerDuplicateFrames:
          freshness?.sourceFrameMarkerDuplicateFrames,
      sourceFrameMarkerUniqueFps: freshness?.sourceFrameMarkerUniqueFps,
      sourceFrameMarkerLongestStaleRunMs:
          freshness?.sourceFrameMarkerLongestStaleRunMs,
      sourceQpc: freshness?.sourceQpc,
      stageQpc: freshness?.stageQpc,
      frameAgeMs: freshness?.frameAgeMs,
      previousFrameId: freshness?.previousFrameId,
      jitterBufferDelayMs: raw.jitterBufferDelayMs,
      jitterBufferEmittedCount: raw.jitterBufferEmittedCount,
      totalDecodeTimeMs: raw.totalDecodeTimeMs,
      averageDecodeTimeMs: raw.averageDecodeTimeMs,
      framesDropped: _intFromStatsValue(
        _tryReadStatsValue(() => stat.framesDropped),
      ),
      freezeCount: raw.freezeCount,
      totalFreezeDurationMs: raw.totalFreezesDurationMs,
      receiveToDecodeMs: null,
      decodeToRenderMs: null,
      status: status,
    );
  }

  void _emitPresentationStage({
    required String stage,
    required String status,
    required String source,
  }) {
    if (_options.mode != MatrixLivekitReceiverProbeMode.render ||
        !_rendererVisible ||
        _events.isClosed) {
      return;
    }

    final base = _latestRendererCallbackEvent;
    final renderer = _frameTapRenderer;
    if (base == null ||
        renderer == null ||
        base.rendererAttached != true ||
        base.rendererVisible != true) {
      return;
    }

    final observedAtUtc = DateTime.now().toUtc();
    final key = '${base.trackSidHash ?? 'unknown'}:$stage';
    final nativeSequence = base.nativeFrameSequence;
    final previousSequence = _lastPresentationStageSequence[key];
    if (nativeSequence != null && previousSequence == nativeSequence) {
      return;
    }

    final previousObservedAt = _lastPresentationStageObservedAt[key];
    final observedGapMs = previousObservedAt == null
        ? null
        : observedAtUtc.difference(previousObservedAt).inMicroseconds / 1000.0;
    if (nativeSequence == null &&
        previousObservedAt != null &&
        observedAtUtc.difference(previousObservedAt) <
            const Duration(milliseconds: 250)) {
      return;
    }

    _lastPresentationStageSequence[key] = nativeSequence;
    _lastPresentationStageObservedAt[key] = observedAtUtc;

    final event = base.copyForPresentationStage(
      stage: stage,
      status: status,
      stageSource: source,
      observedAtUtc: observedAtUtc,
      rendererTextureId: renderer.textureId,
      stageObservedGapMs: observedGapMs,
    );
    _sampleCount++;
    _lastEvent = event;
    _status = event.status;
    _log(
      'Receiver probe presentation stage emitted '
      'stage=$stage status=$status '
      'nativeSequence=${event.nativeFrameSequence ?? 'n/a'} '
      'textureId=${renderer.textureId ?? 'n/a'}',
    );
    _events.add(event);
  }

  _ReceiverQualityDiagnostics _collectReceiverQualityDiagnostics({
    required lk.RemoteTrackPublication publication,
    required dynamic stat,
    required _RawReceiverDiagnostics raw,
    required String key,
    required DateTime sampleTimeUtc,
    required int? bitrateBps,
  }) {
    final receivedWidth =
        _intFromStatsValue(_tryReadStatsValue(() => stat.frameWidth)) ??
        raw.decodedWidth;
    final receivedHeight =
        _intFromStatsValue(_tryReadStatsValue(() => stat.frameHeight)) ??
        raw.decodedHeight;
    final decodedWidth = raw.decodedWidth ?? receivedWidth;
    final decodedHeight = raw.decodedHeight ?? receivedHeight;
    final renderedWidth = raw.renderedWidth;
    final renderedHeight = raw.renderedHeight;
    final framesDecoded = _intFromStatsValue(
      _tryReadStatsValue(() => stat.framesDecoded),
    );
    final framesReceived = _intFromStatsValue(
      _tryReadStatsValue(() => stat.framesReceived),
    );
    final framesRendered = raw.framesRendered;
    final pliCount = _intFromStatsValue(
      _tryReadStatsValue(() => stat.pliCount),
    );
    final firCount = _intFromStatsValue(
      _tryReadStatsValue(() => stat.firCount),
    );
    final nackCount = _intFromStatsValue(
      _tryReadStatsValue(() => stat.nackCount),
    );
    final packetsReceived = _intFromStatsValue(
      _tryReadStatsValue(() => stat.packetsReceived),
    );
    final packetsLost = _intFromStatsValue(
      _tryReadStatsValue(() => stat.packetsLost),
    );
    final previous = _receiverQualitySamples[key];
    final current = _ReceiverQualitySample(
      sampleTimeUtc: sampleTimeUtc,
      framesReceived: framesReceived,
      framesDecoded: framesDecoded,
      framesRendered: framesRendered,
      keyFramesDecoded: raw.keyFramesDecoded,
      qpSum: raw.qpSum,
      pliCount: pliCount,
      firCount: firCount,
      nackCount: nackCount,
    );
    _receiverQualitySamples[key] = current;

    final framesDecodedDelta = _counterDelta(
      current.framesDecoded,
      previous?.framesDecoded,
    );
    final sampleWindowMs = previous == null
        ? null
        : sampleTimeUtc.difference(previous.sampleTimeUtc).inMicroseconds /
              1000.0;
    final keyFramesDecodedDelta = _counterDelta(
      current.keyFramesDecoded,
      previous?.keyFramesDecoded,
    );
    final qpDelta = _counterDelta(current.qpSum, previous?.qpSum);
    final keyframeIntervalMs = previous != null && keyFramesDecodedDelta != null
        ? sampleTimeUtc.difference(previous.sampleTimeUtc).inMicroseconds /
              1000.0 /
              keyFramesDecodedDelta
        : null;
    final keyframeIntervalFrames =
        framesDecodedDelta != null && keyFramesDecodedDelta != null
        ? (framesDecodedDelta / keyFramesDecodedDelta).round()
        : null;
    final averageQp = qpDelta != null && framesDecodedDelta != null
        ? qpDelta / framesDecodedDelta
        : null;
    final subscribedQuality = publication.videoQuality.name.toLowerCase();
    final simulcastLayer =
        _stringFromStatsValue(_tryReadStatsValue(() => stat.rid)) ?? 'single';
    final upscalingLowerLayerSuspected = _dimensionUpscaleSuspected(
      decodedWidth: decodedWidth,
      decodedHeight: decodedHeight,
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
    );

    return _ReceiverQualityDiagnostics(
      inboundBitrateBps: bitrateBps,
      receivedWidth: receivedWidth,
      receivedHeight: receivedHeight,
      decodedWidth: decodedWidth,
      decodedHeight: decodedHeight,
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
      receiverFps: _numFromStatsValue(
        _tryReadStatsValue(() => stat.framesPerSecond),
      )?.toDouble(),
      receivedFps: _counterFps(
        current.framesReceived,
        previous?.framesReceived,
        sampleWindowMs,
      ),
      decodedFps: _counterFps(
        current.framesDecoded,
        previous?.framesDecoded,
        sampleWindowMs,
      ),
      renderedFps: _counterFps(
        current.framesRendered,
        previous?.framesRendered,
        sampleWindowMs,
      ),
      statsSampleWindowMs: sampleWindowMs,
      framesReceived: framesReceived,
      framesDecoded: framesDecoded,
      framesRendered: framesRendered,
      packetsReceived: packetsReceived,
      packetsLost: packetsLost,
      receiverJitterMs: VoipDiagnosticsMath.secondsToMs(
        _numFromStatsValue(_tryReadStatsValue(() => stat.jitter)),
      ),
      pliCount: pliCount,
      pliDelta: _counterDelta(pliCount, previous?.pliCount),
      firCount: firCount,
      firDelta: _counterDelta(firCount, previous?.firCount),
      nackCount: nackCount,
      nackDelta: _counterDelta(nackCount, previous?.nackCount),
      keyFramesDecoded: raw.keyFramesDecoded,
      keyFramesDecodedDelta: keyFramesDecodedDelta,
      keyframeIntervalFrames: keyframeIntervalFrames,
      keyframeIntervalMs: keyframeIntervalMs,
      qpSum: raw.qpSum,
      averageQp: averageQp,
      upscalingLowerLayerSuspected: upscalingLowerLayerSuspected,
      adaptiveStreamLowLayerSuspected:
          subscribedQuality != 'high' ||
          (simulcastLayer != 'single' && simulcastLayer != 'h'),
    );
  }

  Future<_RawReceiverDiagnostics> _collectRawReceiverDiagnostics(
    lk.RemoteVideoTrack track,
    String key,
  ) async {
    final receiver = track.receiver;
    if (receiver == null) {
      return const _RawReceiverDiagnostics();
    }

    Iterable<Object?> reports;
    try {
      reports = await receiver.getStats().timeout(_options.statsTimeout);
    } on TimeoutException {
      return const _RawReceiverDiagnostics();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Receiver probe failed to collect raw receiver diagnostics',
      );
      return const _RawReceiverDiagnostics();
    }

    double? jitterBufferDelayMs;
    int? jitterBufferEmittedCount;
    double? totalDecodeTimeMs;
    double? averageDecodeTimeMs;
    int? framesRendered;
    double? renderFps;
    int? freezeCount;
    double? totalFreezesDurationMs;
    int? decodedWidth;
    int? decodedHeight;
    int? renderedWidth;
    int? renderedHeight;
    int? keyFramesDecoded;
    int? qpSum;

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
        renderedWidth ??= _intFromStatsValue(values?['frameWidth']);
        renderedHeight ??= _intFromStatsValue(values?['frameHeight']);
        continue;
      }

      if (type != 'inbound-rtp') {
        continue;
      }

      final delaySeconds = _numFromStatsValue(values?['jitterBufferDelay']);
      final emittedCount = _numFromStatsValue(
        values?['jitterBufferEmittedCount'],
      );
      jitterBufferEmittedCount ??= _intFromStatsValue(emittedCount);
      if (delaySeconds != null && emittedCount != null) {
        final previous = _jitterBufferSamples[key];
        _jitterBufferSamples[key] = _JitterBufferSample(
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
      final previousDecode = _decodeTimeSamples[key];
      if (totalDecodeTime != null || framesDecoded != null) {
        _decodeTimeSamples[key] = _DurationCounterSample(
          totalSeconds: totalDecodeTime,
          count: framesDecoded,
        );
      }
      totalDecodeTimeMs = VoipDiagnosticsMath.secondsToMs(totalDecodeTime);
      averageDecodeTimeMs = VoipDiagnosticsMath.averageDurationMs(
        previousTotalSeconds: previousDecode?.totalSeconds,
        currentTotalSeconds: totalDecodeTime,
        previousCount: previousDecode?.count,
        currentCount: framesDecoded,
      );

      framesRendered ??= _intFromStatsValue(values?['framesRendered']);
      renderFps ??= _numFromStatsValue(values?['framesPerSecond'])?.toDouble();
      decodedWidth ??= _intFromStatsValue(values?['frameWidth']);
      decodedHeight ??= _intFromStatsValue(values?['frameHeight']);
      keyFramesDecoded ??= _intFromStatsValue(values?['keyFramesDecoded']);
      qpSum ??= _intFromStatsValue(values?['qpSum']);
      freezeCount = _intFromStatsValue(values?['freezeCount']);
      totalFreezesDurationMs = VoipDiagnosticsMath.secondsToMs(
        _numFromStatsValue(values?['totalFreezesDuration']),
      );
    }

    return _RawReceiverDiagnostics(
      jitterBufferDelayMs: jitterBufferDelayMs,
      jitterBufferEmittedCount: jitterBufferEmittedCount,
      totalDecodeTimeMs: totalDecodeTimeMs,
      averageDecodeTimeMs: averageDecodeTimeMs,
      framesRendered: framesRendered,
      renderFps: renderFps,
      freezeCount: freezeCount,
      totalFreezesDurationMs: totalFreezesDurationMs,
      decodedWidth: decodedWidth,
      decodedHeight: decodedHeight,
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
      keyFramesDecoded: keyFramesDecoded,
      qpSum: qpSum,
    );
  }

  String _frameHashKey(lk.RemoteTrackPublication publication) {
    final sid = publication.sid;
    return sid.isEmpty ? 'unknown-publication' : sid;
  }

  bool _isFrameTapRendererAttached(lk.RemoteTrackPublication publication) {
    return _frameTapPublication?.sid == publication.sid &&
        _frameTapRenderer != null;
  }

  String _trackSidLogHash(lk.RemoteTrackPublication publication) {
    final sid = publication.sid;
    if (sid.isEmpty) {
      return 'sha256:unknown';
    }
    return 'sha256:${sha256.convert(utf8.encode(sid)).toString().substring(0, 12)}';
  }

  String _hash(String value) {
    return 'sha256:${sha256.convert(utf8.encode(value))}';
  }

  void _log(String message) {
    Log.i(message, category: LogCategory.webrtc, source: 'receiver-probe');
  }

  String? _codecLabel(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) {
      return null;
    }
    final parts = mimeType.split('/');
    return parts.length > 1 ? parts.last : mimeType;
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

  String? _stringFromStatsValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  Object? _tryReadStatsValue(Object? Function() read) {
    try {
      return read();
    } on NoSuchMethodError {
      return null;
    } on TypeError {
      return null;
    }
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

  int? _counterDelta(int? current, int? previous) {
    if (current == null || previous == null) {
      return null;
    }
    final delta = current - previous;
    return delta > 0 ? delta : null;
  }

  double? _counterFps(int? current, int? previous, double? windowMs) {
    final delta = _counterDelta(current, previous);
    if (delta == null || windowMs == null || windowMs <= 0) {
      return null;
    }
    return delta * 1000.0 / windowMs;
  }

  bool? _dimensionUpscaleSuspected({
    required int? decodedWidth,
    required int? decodedHeight,
    required int? renderedWidth,
    required int? renderedHeight,
  }) {
    if (decodedWidth == null ||
        decodedHeight == null ||
        renderedWidth == null ||
        renderedHeight == null) {
      return null;
    }
    return renderedWidth > decodedWidth || renderedHeight > decodedHeight;
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

class _ReceiverQualitySample {
  const _ReceiverQualitySample({
    required this.sampleTimeUtc,
    required this.framesReceived,
    required this.framesDecoded,
    required this.framesRendered,
    required this.keyFramesDecoded,
    required this.qpSum,
    required this.pliCount,
    required this.firCount,
    required this.nackCount,
  });

  final DateTime sampleTimeUtc;
  final int? framesReceived;
  final int? framesDecoded;
  final int? framesRendered;
  final int? keyFramesDecoded;
  final int? qpSum;
  final int? pliCount;
  final int? firCount;
  final int? nackCount;
}

class _ReceiverQualityDiagnostics {
  const _ReceiverQualityDiagnostics({
    this.inboundBitrateBps,
    this.receivedWidth,
    this.receivedHeight,
    this.decodedWidth,
    this.decodedHeight,
    this.renderedWidth,
    this.renderedHeight,
    this.receiverFps,
    this.receivedFps,
    this.decodedFps,
    this.renderedFps,
    this.statsSampleWindowMs,
    this.framesReceived,
    this.framesDecoded,
    this.framesRendered,
    this.packetsReceived,
    this.packetsLost,
    this.receiverJitterMs,
    this.pliCount,
    this.pliDelta,
    this.firCount,
    this.firDelta,
    this.nackCount,
    this.nackDelta,
    this.keyFramesDecoded,
    this.keyFramesDecodedDelta,
    this.keyframeIntervalFrames,
    this.keyframeIntervalMs,
    this.qpSum,
    this.averageQp,
    this.upscalingLowerLayerSuspected,
    this.adaptiveStreamLowLayerSuspected,
  });

  final int? inboundBitrateBps;
  final int? receivedWidth;
  final int? receivedHeight;
  final int? decodedWidth;
  final int? decodedHeight;
  final int? renderedWidth;
  final int? renderedHeight;
  final double? receiverFps;
  final double? receivedFps;
  final double? decodedFps;
  final double? renderedFps;
  final double? statsSampleWindowMs;
  final int? framesReceived;
  final int? framesDecoded;
  final int? framesRendered;
  final int? packetsReceived;
  final int? packetsLost;
  final double? receiverJitterMs;
  final int? pliCount;
  final int? pliDelta;
  final int? firCount;
  final int? firDelta;
  final int? nackCount;
  final int? nackDelta;
  final int? keyFramesDecoded;
  final int? keyFramesDecodedDelta;
  final int? keyframeIntervalFrames;
  final double? keyframeIntervalMs;
  final int? qpSum;
  final double? averageQp;
  final bool? upscalingLowerLayerSuspected;
  final bool? adaptiveStreamLowLayerSuspected;
}

class _RawReceiverDiagnostics {
  const _RawReceiverDiagnostics({
    this.jitterBufferDelayMs,
    this.jitterBufferEmittedCount,
    this.totalDecodeTimeMs,
    this.averageDecodeTimeMs,
    this.framesRendered,
    this.renderFps,
    this.freezeCount,
    this.totalFreezesDurationMs,
    this.decodedWidth,
    this.decodedHeight,
    this.renderedWidth,
    this.renderedHeight,
    this.keyFramesDecoded,
    this.qpSum,
  });

  final double? jitterBufferDelayMs;
  final int? jitterBufferEmittedCount;
  final double? totalDecodeTimeMs;
  final double? averageDecodeTimeMs;
  final int? framesRendered;
  final double? renderFps;
  final int? freezeCount;
  final double? totalFreezesDurationMs;
  final int? decodedWidth;
  final int? decodedHeight;
  final int? renderedWidth;
  final int? renderedHeight;
  final int? keyFramesDecoded;
  final int? qpSum;
}

class _FrameHashFreshnessTracker {
  _FrameHashFreshnessTracker({
    required this.window,
    required this.hashAlgorithm,
  });

  final Duration window;
  final String hashAlgorithm;
  final List<_FrameHashSample> _samples = [];
  String? _previousFrameHash;

  int get sampleCount => _samples.length;

  void addSample({
    required DateTime capturedAtUtc,
    required String frameHash,
    int? nativeSequence,
    int? nativeTimestampUnixMs,
    int? frameWidth,
    int? frameHeight,
    int? frameId,
    String? frameIdSource,
    int? sourceFrameMarkerId,
    int? sourceQpc,
    int? stageQpc,
    double? frameAgeMs,
    double? nativeEventDelayMs,
  }) {
    final isUnique =
        _previousFrameHash == null || _previousFrameHash != frameHash;
    _previousFrameHash = frameHash;
    final previousFrameId = _samples.isEmpty ? null : _samples.last.frameId;
    _samples.add(
      _FrameHashSample(
        capturedAtUtc: capturedAtUtc,
        isUnique: isUnique,
        nativeSequence: nativeSequence,
        nativeTimestampUnixMs: nativeTimestampUnixMs,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        frameId: frameId,
        frameIdSource: frameIdSource,
        sourceFrameMarkerId: sourceFrameMarkerId,
        sourceQpc: sourceQpc,
        stageQpc: stageQpc,
        frameAgeMs: frameAgeMs,
        previousFrameId: previousFrameId,
        nativeEventDelayMs: nativeEventDelayMs,
      ),
    );
    _trim(capturedAtUtc);
  }

  _FrameHashFreshnessSummary? summary(DateTime now) {
    _trim(now);
    if (_samples.isEmpty) {
      return null;
    }

    final first = _samples.first.capturedAtUtc;
    final last = _samples.last.capturedAtUtc;
    final elapsedSeconds =
        max(0, last.difference(first).inMicroseconds) / 1000000.0;
    final uniqueSamples = _samples
        .where((sample) => sample.isUnique)
        .toList(growable: false);
    final gapsMs = <double>[];
    for (var index = 1; index < uniqueSamples.length; index++) {
      gapsMs.add(
        uniqueSamples[index].capturedAtUtc
                .difference(uniqueSamples[index - 1].capturedAtUtc)
                .inMicroseconds /
            1000.0,
      );
    }
    final presentationGapsMs = <double>[];
    var nativeFrameSequenceGaps = 0;
    for (var index = 1; index < _samples.length; index++) {
      final current = _samples[index];
      final previous = _samples[index - 1];
      presentationGapsMs.add(_framePresentationGapMs(previous, current));
      final currentSequence = current.nativeSequence;
      final previousSequence = previous.nativeSequence;
      if (currentSequence != null && previousSequence != null) {
        nativeFrameSequenceGaps += max(
          0,
          currentSequence - previousSequence - 1,
        );
      }
    }
    final nativeEventDelaysMs = _samples
        .map((sample) => sample.nativeEventDelayMs)
        .whereType<double>()
        .toList(growable: false);
    final changeTransitions = _samples
        .skip(1)
        .where((sample) => sample.isUnique)
        .length;
    final transitionCount = max(0, _samples.length - 1);
    final sourceFrameMarkerSamples = _samples
        .where((sample) => sample.sourceFrameMarkerId != null)
        .toList(growable: false);
    final sourceFrameMarkerUniqueSamples = <_FrameHashSample>[];
    int? previousSourceFrameMarkerId;
    for (final sample in sourceFrameMarkerSamples) {
      final markerId = sample.sourceFrameMarkerId;
      if (markerId != null && markerId != previousSourceFrameMarkerId) {
        sourceFrameMarkerUniqueSamples.add(sample);
      }
      previousSourceFrameMarkerId = markerId;
    }
    final sourceFrameMarkerElapsedSeconds = sourceFrameMarkerSamples.length < 2
        ? 0.0
        : max(
                0,
                sourceFrameMarkerSamples.last.capturedAtUtc
                    .difference(sourceFrameMarkerSamples.first.capturedAtUtc)
                    .inMicroseconds,
              ) /
              1000000.0;

    return _FrameHashFreshnessSummary(
      sampleCount: _samples.length,
      uniqueFrames: uniqueSamples.length,
      duplicateFrames: _samples.length - uniqueSamples.length,
      uniqueFps: elapsedSeconds > 0
          ? uniqueSamples.length / elapsedSeconds
          : null,
      p50GapMs: _percentile(gapsMs, 0.50),
      p95GapMs: _percentile(gapsMs, 0.95),
      maxGapMs: gapsMs.isEmpty ? null : gapsMs.reduce(max),
      longestStaleRunMs: _longestStaleRunMs(),
      presentationP50GapMs: _percentile(presentationGapsMs, 0.50),
      presentationP95GapMs: _percentile(presentationGapsMs, 0.95),
      presentationMaxGapMs: presentationGapsMs.isEmpty
          ? null
          : presentationGapsMs.reduce(max),
      presentationLatestGapMs: presentationGapsMs.isEmpty
          ? null
          : presentationGapsMs.last,
      perceptualDifferenceScore: transitionCount > 0
          ? changeTransitions.toDouble() / transitionCount
          : null,
      nativeFrameSequence: _samples.last.nativeSequence,
      nativeFrameSequenceGaps: nativeFrameSequenceGaps,
      nativeFrameEventDelayMs: nativeEventDelaysMs.isEmpty
          ? null
          : nativeEventDelaysMs.reduce((a, b) => a + b) /
                nativeEventDelaysMs.length,
      nativeFrameEventDelayMaxMs: nativeEventDelaysMs.isEmpty
          ? null
          : nativeEventDelaysMs.reduce(max),
      droppedOrReplacedTextureUpdates: nativeFrameSequenceGaps,
      frameWidth: _samples.last.frameWidth,
      frameHeight: _samples.last.frameHeight,
      frameId: _samples.last.frameId,
      frameIdSource: _samples.last.frameIdSource,
      sourceFrameMarkerId: _samples.last.sourceFrameMarkerId,
      sourceFrameMarkerDecodedFrames: sourceFrameMarkerSamples.length,
      sourceFrameMarkerUniqueFrames: sourceFrameMarkerUniqueSamples.length,
      sourceFrameMarkerDuplicateFrames:
          sourceFrameMarkerSamples.length -
          sourceFrameMarkerUniqueSamples.length,
      sourceFrameMarkerUniqueFps: sourceFrameMarkerElapsedSeconds > 0
          ? sourceFrameMarkerUniqueSamples.length /
                sourceFrameMarkerElapsedSeconds
          : null,
      sourceFrameMarkerLongestStaleRunMs: _sourceFrameMarkerLongestStaleRunMs(
        sourceFrameMarkerSamples,
      ),
      sourceQpc: _samples.last.sourceQpc,
      stageQpc: _samples.last.stageQpc,
      frameAgeMs: _samples.last.frameAgeMs,
      previousFrameId: _samples.last.previousFrameId,
      lastCapturedAtUtc: last,
      hashAlgorithm: hashAlgorithm,
    );
  }

  double _framePresentationGapMs(
    _FrameHashSample previous,
    _FrameHashSample current,
  ) {
    final previousNative = previous.nativeTimestampUnixMs;
    final currentNative = current.nativeTimestampUnixMs;
    if (previousNative != null && currentNative != null) {
      final delta = currentNative - previousNative;
      if (delta >= 0) {
        return delta.toDouble();
      }
    }
    return current.capturedAtUtc
            .difference(previous.capturedAtUtc)
            .inMicroseconds /
        1000.0;
  }

  void _trim(DateTime now) {
    final cutoff = now.subtract(window);
    while (_samples.isNotEmpty &&
        _samples.first.capturedAtUtc.isBefore(cutoff)) {
      _samples.removeAt(0);
    }
  }

  double? _longestStaleRunMs() {
    if (_samples.isEmpty) {
      return null;
    }

    DateTime? staleRunStartedAt;
    var longestMs = 0.0;
    for (final sample in _samples) {
      if (sample.isUnique) {
        if (staleRunStartedAt != null) {
          longestMs = max(
            longestMs,
            sample.capturedAtUtc.difference(staleRunStartedAt).inMicroseconds /
                1000.0,
          );
          staleRunStartedAt = null;
        }
        continue;
      }
      staleRunStartedAt ??= sample.capturedAtUtc;
    }

    if (staleRunStartedAt != null) {
      longestMs = max(
        longestMs,
        _samples.last.capturedAtUtc
                .difference(staleRunStartedAt)
                .inMicroseconds /
            1000.0,
      );
    }
    return longestMs;
  }

  double? _sourceFrameMarkerLongestStaleRunMs(List<_FrameHashSample> samples) {
    if (samples.isEmpty) {
      return null;
    }

    int? previousMarkerId;
    DateTime? staleRunStartedAt;
    var longestMs = 0.0;
    for (final sample in samples) {
      final markerId = sample.sourceFrameMarkerId;
      if (markerId == null || markerId != previousMarkerId) {
        if (staleRunStartedAt != null) {
          longestMs = max(
            longestMs,
            sample.capturedAtUtc.difference(staleRunStartedAt).inMicroseconds /
                1000.0,
          );
          staleRunStartedAt = null;
        }
        previousMarkerId = markerId;
        continue;
      }
      staleRunStartedAt ??= sample.capturedAtUtc;
    }

    if (staleRunStartedAt != null) {
      longestMs = max(
        longestMs,
        samples.last.capturedAtUtc
                .difference(staleRunStartedAt)
                .inMicroseconds /
            1000.0,
      );
    }
    return longestMs;
  }

  double? _percentile(List<double> values, double percentile) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = values.toList(growable: false)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index];
  }
}

class _FrameHashSample {
  const _FrameHashSample({
    required this.capturedAtUtc,
    required this.isUnique,
    this.nativeSequence,
    this.nativeTimestampUnixMs,
    this.frameWidth,
    this.frameHeight,
    this.frameId,
    this.frameIdSource,
    this.sourceFrameMarkerId,
    this.sourceQpc,
    this.stageQpc,
    this.frameAgeMs,
    this.previousFrameId,
    this.nativeEventDelayMs,
  });

  final DateTime capturedAtUtc;
  final bool isUnique;
  final int? nativeSequence;
  final int? nativeTimestampUnixMs;
  final int? frameWidth;
  final int? frameHeight;
  final int? frameId;
  final String? frameIdSource;
  final int? sourceFrameMarkerId;
  final int? sourceQpc;
  final int? stageQpc;
  final double? frameAgeMs;
  final int? previousFrameId;
  final double? nativeEventDelayMs;
}

class _FrameHashFreshnessSummary {
  const _FrameHashFreshnessSummary({
    required this.sampleCount,
    required this.uniqueFrames,
    required this.duplicateFrames,
    required this.uniqueFps,
    required this.p50GapMs,
    required this.p95GapMs,
    required this.maxGapMs,
    required this.longestStaleRunMs,
    required this.presentationP50GapMs,
    required this.presentationP95GapMs,
    required this.presentationMaxGapMs,
    required this.presentationLatestGapMs,
    required this.perceptualDifferenceScore,
    required this.nativeFrameSequence,
    required this.nativeFrameSequenceGaps,
    required this.nativeFrameEventDelayMs,
    required this.nativeFrameEventDelayMaxMs,
    required this.droppedOrReplacedTextureUpdates,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameId,
    required this.frameIdSource,
    required this.sourceFrameMarkerId,
    required this.sourceFrameMarkerDecodedFrames,
    required this.sourceFrameMarkerUniqueFrames,
    required this.sourceFrameMarkerDuplicateFrames,
    required this.sourceFrameMarkerUniqueFps,
    required this.sourceFrameMarkerLongestStaleRunMs,
    required this.sourceQpc,
    required this.stageQpc,
    required this.frameAgeMs,
    required this.previousFrameId,
    required this.lastCapturedAtUtc,
    required this.hashAlgorithm,
  });

  final String source = 'frame_hash_tap';
  final String hashAlgorithm;
  final int sampleCount;
  final int uniqueFrames;
  final int duplicateFrames;
  final double? uniqueFps;
  final double? p50GapMs;
  final double? p95GapMs;
  final double? maxGapMs;
  final double? longestStaleRunMs;
  final double? presentationP50GapMs;
  final double? presentationP95GapMs;
  final double? presentationMaxGapMs;
  final double? presentationLatestGapMs;
  final double? perceptualDifferenceScore;
  final int? nativeFrameSequence;
  final int nativeFrameSequenceGaps;
  final double? nativeFrameEventDelayMs;
  final double? nativeFrameEventDelayMaxMs;
  final int? droppedOrReplacedTextureUpdates;
  final int? frameWidth;
  final int? frameHeight;
  final int? frameId;
  final String? frameIdSource;
  final int? sourceFrameMarkerId;
  final int sourceFrameMarkerDecodedFrames;
  final int sourceFrameMarkerUniqueFrames;
  final int sourceFrameMarkerDuplicateFrames;
  final double? sourceFrameMarkerUniqueFps;
  final double? sourceFrameMarkerLongestStaleRunMs;
  final int? sourceQpc;
  final int? stageQpc;
  final double? frameAgeMs;
  final int? previousFrameId;
  final DateTime lastCapturedAtUtc;
}
