part of 'stream_test_runner.dart';

class StreamTestTemporalAnalysis {
  const StreamTestTemporalAnalysis({
    required this.windows,
    this.lateDegradationSignals = const [],
  });

  factory StreamTestTemporalAnalysis.fromSamplesAndMarkers({
    required List<StreamTestSample> samples,
    required List<String> nativeDiagnosticMarkers,
    required double targetFps,
    DateTime? measurementStartedAt,
    DateTime? measurementEndedAt,
  }) {
    final totalDuration = _measurementDuration(
      samples: samples,
      measurementStartedAt: measurementStartedAt,
      measurementEndedAt: measurementEndedAt,
    );
    if (totalDuration.inMilliseconds <= 0) {
      return const StreamTestTemporalAnalysis(windows: []);
    }

    final markerSamples =
        _GameCaptureMarkerSample.fromMarkers(nativeDiagnosticMarkers);
    final specs = _temporalWindowSpecs(totalDuration);
    final windows = specs
        .map(
          (spec) => StreamTestTimeWindowSummary.fromSamplesAndMarkers(
            spec: spec,
            samples: samples,
            markerSamples: markerSamples,
            measurementStartedAt: measurementStartedAt,
          ),
        )
        .toList(growable: false);

    return StreamTestTemporalAnalysis(
      windows: List.unmodifiable(windows),
      lateDegradationSignals: List.unmodifiable(
        _lateDegradationSignals(
          windows: windows,
          targetFps: targetFps,
        ),
      ),
    );
  }

  final List<StreamTestTimeWindowSummary> windows;
  final List<String> lateDegradationSignals;

  bool get hasEvidence => windows.any((window) => window.hasEvidence);

  bool get hasLateDegradation => lateDegradationSignals.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'windows': windows.map((window) => window.toJson()).toList(),
      'lateDegradationDetected': hasLateDegradation,
      'lateDegradationSignals': lateDegradationSignals,
    };
  }
}

class StreamTestTimeWindowSummary {
  const StreamTestTimeWindowSummary({
    required this.label,
    required this.startOffset,
    required this.endOffset,
    required this.sampleCount,
    required this.summary,
    required this.framePacing,
    this.gameCapture,
  });

  factory StreamTestTimeWindowSummary.fromSamplesAndMarkers({
    required _StreamTestWindowSpec spec,
    required List<StreamTestSample> samples,
    required List<_GameCaptureMarkerSample> markerSamples,
    DateTime? measurementStartedAt,
  }) {
    final windowSamples = samples.where((sample) {
      final elapsed = sample.elapsed;
      return elapsed >= spec.start && elapsed <= spec.end;
    }).toList(growable: false);
    return StreamTestTimeWindowSummary(
      label: spec.label,
      startOffset: spec.start,
      endOffset: spec.end,
      sampleCount: windowSamples.length,
      summary: StreamTestSummary.fromSamples(windowSamples),
      framePacing: StreamTestFramePacingSummary.fromSamples(windowSamples),
      gameCapture: StreamTestGameCaptureWindowCounters.fromMarkerPairs(
        markerSamples: markerSamples,
        measurementStartedAt: measurementStartedAt,
        startOffset: spec.start,
        endOffset: spec.end,
      ),
    );
  }

  final String label;
  final Duration startOffset;
  final Duration endOffset;
  final int sampleCount;
  final StreamTestSummary summary;
  final StreamTestFramePacingSummary framePacing;
  final StreamTestGameCaptureWindowCounters? gameCapture;

  bool get hasEvidence =>
      sampleCount > 0 || (gameCapture?.hasEvidence ?? false);

  String get offsetLabel =>
      '${(startOffset.inMilliseconds / 1000).toStringAsFixed(0)}-'
      '${(endOffset.inMilliseconds / 1000).toStringAsFixed(0)}s';

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'startMs': startOffset.inMilliseconds,
      'endMs': endOffset.inMilliseconds,
      'sampleCount': sampleCount,
      'averageCaptureFps': summary.averageCaptureFps,
      'minimumCaptureFps': summary.minimumCaptureFps,
      'averageEncodeFps': summary.averageEncodeFps,
      'minimumEncodeFps': summary.minimumEncodeFps,
      'averageSendFps': summary.averageSendFps,
      'minimumSendFps': summary.minimumSendFps,
      'averageBitrateBps': summary.averageBitrateBps,
      'maxPacketLossPercent': summary.maxPacketLossPercent,
      'maxRoundTripTimeMs': summary.maxRoundTripTimeMs,
      'framePacing': framePacing.toJson(),
      'gameCapture': gameCapture?.toJson(),
    };
  }
}

class StreamTestFramePacingSummary {
  const StreamTestFramePacingSummary({
    this.nativeCapture = const StreamTestFramePacingStageSummary(
      stage: 'nativeCapture',
      evidence: 'none',
    ),
    this.capture = const StreamTestFramePacingStageSummary(
      stage: 'capture',
      evidence: 'none',
    ),
    this.preEncode = const StreamTestFramePacingStageSummary(
      stage: 'preEncode',
      evidence: 'none',
    ),
    this.encoded = const StreamTestFramePacingStageSummary(
      stage: 'encoded',
      evidence: 'none',
    ),
    this.sent = const StreamTestFramePacingStageSummary(
      stage: 'sent',
      evidence: 'none',
    ),
    this.received = const StreamTestFramePacingStageSummary(
      stage: 'received',
      evidence: 'none',
    ),
    this.decoded = const StreamTestFramePacingStageSummary(
      stage: 'decoded',
      evidence: 'none',
    ),
    this.rendered = const StreamTestFramePacingStageSummary(
      stage: 'rendered',
      evidence: 'none',
    ),
  });

  factory StreamTestFramePacingSummary.fromSamples(
    List<StreamTestSample> samples, {
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
  }) {
    return StreamTestFramePacingSummary(
      nativeCapture:
          StreamTestFramePacingStageSummary.fromNative(nativeDiagnostics),
      capture: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'capture',
        evidence: 'sampled framesCaptured counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesCaptured,
        ),
      ),
      preEncode: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'preEncode',
        evidence: 'sampled framesCaptured counter with pre-encode dimensions',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesCaptured,
          include: (track) =>
              (track.preEncodeWidth ?? 0) > 0 &&
              (track.preEncodeHeight ?? 0) > 0,
        ),
      ),
      encoded: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'encoded',
        evidence: 'sampled framesEncoded counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesEncoded,
        ),
      ),
      sent: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'sent',
        evidence: 'sampled framesSent counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesSent,
        ),
      ),
      received: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'received',
        evidence: 'sampled framesReceived counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesReceived,
        ),
      ),
      decoded: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'decoded',
        evidence: 'sampled framesDecoded counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesDecoded,
        ),
      ),
      rendered: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'rendered',
        evidence: 'sampled framesRendered counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesRendered,
        ),
      ),
    );
  }

  final StreamTestFramePacingStageSummary nativeCapture;
  final StreamTestFramePacingStageSummary capture;
  final StreamTestFramePacingStageSummary preEncode;
  final StreamTestFramePacingStageSummary encoded;
  final StreamTestFramePacingStageSummary sent;
  final StreamTestFramePacingStageSummary received;
  final StreamTestFramePacingStageSummary decoded;
  final StreamTestFramePacingStageSummary rendered;

  List<StreamTestFramePacingStageSummary> get stages => [
        nativeCapture,
        capture,
        preEncode,
        encoded,
        sent,
        received,
        decoded,
        rendered,
      ];

  bool get hasEvidence => stages.any((stage) => stage.hasEvidence);

  String get compactLabel {
    final labels = <String>[];
    for (final stage in stages) {
      if (stage.hasEvidence) {
        labels.add('${stage.stage}=${stage.compactLabel}');
      }
    }
    return labels.isEmpty ? 'unknown' : labels.join(' ');
  }

  Map<String, Object?> toJson() {
    return {
      'nativeCapture': nativeCapture.toJson(),
      'capture': capture.toJson(),
      'preEncode': preEncode.toJson(),
      'encoded': encoded.toJson(),
      'sent': sent.toJson(),
      'received': received.toJson(),
      'decoded': decoded.toJson(),
      'rendered': rendered.toJson(),
    };
  }
}

class StreamTestFramePacingStageSummary {
  const StreamTestFramePacingStageSummary({
    required this.stage,
    required this.evidence,
    this.sampleCount = 0,
    this.averageFps,
    this.minimumFps,
    this.p50IntervalMs,
    this.p95IntervalMs,
    this.maxIntervalMs,
    this.largestFrameDelta,
    this.lastFrameCount,
    this.duplicatedFrameCount = 0,
    this.staleFrameReuseCount = 0,
    this.waitTimeoutCount = 0,
    this.permanentErrorCount = 0,
  });

  factory StreamTestFramePacingStageSummary.fromNative(
    StreamTestNativeDiagnostics diagnostics,
  ) {
    final hasMarkerEvidence = diagnostics.p95FrameIntervalMs != null ||
        diagnostics.maxFrameIntervalMs != null ||
        diagnostics.p95PacerIntervalMs != null ||
        diagnostics.maxPacerIntervalMs != null ||
        diagnostics.averageSubmittedFps != null ||
        diagnostics.averageNativeFps != null ||
        diagnostics.duplicatedFrameCount > 0 ||
        diagnostics.staleFrameReuseCount > 0 ||
        diagnostics.captureWaitTimeoutCount > 0 ||
        diagnostics.capturePermanentErrorCount > 0;
    return StreamTestFramePacingStageSummary(
      stage: 'nativeCapture',
      evidence:
          hasMarkerEvidence ? 'native desktop capture cadence marker' : 'none',
      sampleCount: hasMarkerEvidence ? 1 : 0,
      averageFps:
          diagnostics.averageSubmittedFps ?? diagnostics.averageNativeFps,
      p95IntervalMs:
          diagnostics.p95PacerIntervalMs ?? diagnostics.p95FrameIntervalMs,
      maxIntervalMs:
          diagnostics.maxPacerIntervalMs ?? diagnostics.maxFrameIntervalMs,
      duplicatedFrameCount: diagnostics.pacerDuplicateSubmitCount > 0
          ? diagnostics.pacerDuplicateSubmitCount
          : diagnostics.duplicatedFrameCount,
      staleFrameReuseCount: diagnostics.staleFrameReuseCount,
      waitTimeoutCount: diagnostics.captureWaitTimeoutCount,
      permanentErrorCount: diagnostics.capturePermanentErrorCount,
    );
  }

  factory StreamTestFramePacingStageSummary.fromCounterSamples({
    required String stage,
    required String evidence,
    required List<_FrameCounterSample> samples,
  }) {
    final intervals = <double>[];
    final fpsValues = <double>[];
    int? largestFrameDelta;
    int? lastFrameCount;
    var staleFrameReuseCount = 0;
    _FrameCounterSample? previous;

    for (final sample in samples) {
      final frameCount = sample.frameCount;
      if (frameCount == null || frameCount < 0) {
        continue;
      }
      lastFrameCount = frameCount;
      final lastSample = previous;
      if (lastSample != null) {
        final elapsedMs = sample.collectedAt
                .difference(lastSample.collectedAt)
                .inMicroseconds /
            1000.0;
        final frameDelta = frameCount - lastSample.frameCount!;
        if (elapsedMs > 0 && frameDelta > 0) {
          intervals.add(elapsedMs / frameDelta);
          fpsValues.add(frameDelta * 1000 / elapsedMs);
          largestFrameDelta = largestFrameDelta == null
              ? frameDelta
              : max(largestFrameDelta, frameDelta);
        } else if (elapsedMs > 0 && frameDelta == 0) {
          intervals.add(elapsedMs);
          fpsValues.add(0);
          staleFrameReuseCount++;
        }
      }
      previous = sample;
    }

    return StreamTestFramePacingStageSummary(
      stage: stage,
      evidence: intervals.isEmpty ? 'none' : evidence,
      sampleCount: intervals.length,
      averageFps: _average(fpsValues),
      minimumFps: fpsValues.isEmpty ? null : fpsValues.reduce(min),
      p50IntervalMs: _percentile(intervals, 0.50),
      p95IntervalMs: _percentile(intervals, 0.95),
      maxIntervalMs: _maxDouble(intervals),
      largestFrameDelta: largestFrameDelta,
      lastFrameCount: lastFrameCount,
      staleFrameReuseCount: staleFrameReuseCount,
    );
  }

  final String stage;
  final String evidence;
  final int sampleCount;
  final double? averageFps;
  final double? minimumFps;
  final double? p50IntervalMs;
  final double? p95IntervalMs;
  final double? maxIntervalMs;
  final int? largestFrameDelta;
  final int? lastFrameCount;
  final int duplicatedFrameCount;
  final int staleFrameReuseCount;
  final int waitTimeoutCount;
  final int permanentErrorCount;

  bool get hasEvidence =>
      sampleCount > 0 ||
      averageFps != null ||
      minimumFps != null ||
      p50IntervalMs != null ||
      p95IntervalMs != null ||
      maxIntervalMs != null ||
      largestFrameDelta != null ||
      duplicatedFrameCount > 0 ||
      staleFrameReuseCount > 0 ||
      waitTimeoutCount > 0 ||
      permanentErrorCount > 0;

  String get compactLabel {
    if (!hasEvidence) {
      return 'unknown';
    }
    return 'p50=${_milliseconds(p50IntervalMs)} '
        'p95=${_milliseconds(p95IntervalMs)} '
        'max=${_milliseconds(maxIntervalMs)} '
        'avg_fps=${_number(averageFps)}';
  }

  String get markdownLabel {
    if (!hasEvidence) {
      return '?';
    }
    final extras = <String>[
      'avg ${_number(averageFps)}fps',
      if (minimumFps != null) 'min ${_number(minimumFps)}fps',
      if (sampleCount > 0) '$sampleCount windows',
      if (largestFrameDelta != null) 'largest delta $largestFrameDelta',
      if (staleFrameReuseCount > 0 || duplicatedFrameCount > 0)
        'stale $staleFrameReuseCount / duplicate $duplicatedFrameCount',
      if (waitTimeoutCount > 0) 'wait timeouts $waitTimeoutCount',
      if (permanentErrorCount > 0) 'permanent errors $permanentErrorCount',
    ];
    return '${_milliseconds(p50IntervalMs)} p50 / '
        '${_milliseconds(p95IntervalMs)} p95 / '
        '${_milliseconds(maxIntervalMs)} max (${extras.join(', ')})';
  }

  Map<String, Object?> toJson() {
    return {
      'stage': stage,
      'evidence': evidence,
      'sampleCount': sampleCount,
      'averageFps': averageFps,
      'minimumFps': minimumFps,
      'p50IntervalMs': p50IntervalMs,
      'p95IntervalMs': p95IntervalMs,
      'maxIntervalMs': maxIntervalMs,
      'largestFrameDelta': largestFrameDelta,
      'lastFrameCount': lastFrameCount,
      'duplicatedFrameCount': duplicatedFrameCount,
      'staleFrameReuseCount': staleFrameReuseCount,
      'waitTimeoutCount': waitTimeoutCount,
      'permanentErrorCount': permanentErrorCount,
    };
  }
}

class _FrameCounterSample {
  const _FrameCounterSample({
    required this.collectedAt,
    required this.frameCount,
  });

  final DateTime collectedAt;
  final int? frameCount;
}

class _StreamTestWindowSpec {
  const _StreamTestWindowSpec({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final Duration start;
  final Duration end;
}

class _GameCaptureMarkerSample {
  const _GameCaptureMarkerSample({
    required this.timestamp,
    required this.submitted,
    required this.copied,
    required this.gpuScaled,
    required this.gpuScaleFailures,
    required this.cpuFallback,
    required this.nativeNv12Submitted,
    required this.nativeNv12Queued,
    required this.nativeNv12Ready,
    required this.nativeNv12NotReadyPolls,
    required this.nativeNv12Overwritten,
    required this.nativeNv12OverwrittenFresh,
    required this.nativeNv12ReadyDropped,
    required this.nativeNv12ReadyDroppedFresh,
    required this.nativeNv12Failures,
    required this.readbackQueued,
    required this.readbackReady,
    required this.readbackNotReady,
    required this.readbackStaleDropped,
    required this.readbackLatencyDropped,
    required this.sourceFrameRegressions,
    required this.sourceFrameGaps,
    required this.sharedSlotMismatches,
    required this.deliveryRepeatNoQueued,
    required this.deliveryOverwrittenFresh,
    this.deliveryRepeatSourceAgeMaxMs,
    this.deliveryOverwriteAgeMaxMs,
    this.sourceDuplicateSkipAgeMaxMs,
    this.nativeNv12OverwriteAgeMaxMs,
    this.nativeNv12ReadyDropAgeMaxMs,
    this.deliveryWallDeltaMaxMs,
    this.deliveryQueueWaitMaxMs,
    this.readyToSubmitMaxMs,
    this.sourceToSubmitMaxMs,
    this.sourceToReadbackReadyMaxMs,
    this.readbackQueueToMapMaxMs,
    this.mapToI420MaxMs,
    this.sourceToI420ReadyMaxMs,
    this.sourceToQueueMaxMs,
    required this.deliveryWallOver2x,
    required this.deliveryWallOver3x,
    required this.deliveryWallUnderHalf,
    required this.readbackLatencyFramesMax,
    this.readbackLatencyFramesAvg,
  });

  factory _GameCaptureMarkerSample.fromMarker(String marker) {
    return _GameCaptureMarkerSample(
      timestamp: _markerTimestamp(marker),
      submitted: _intFromMarker(marker, 'submitted') ?? 0,
      copied: _intFromMarker(marker, 'copied') ?? 0,
      gpuScaled: _intFromMarker(marker, 'gpuScaled') ?? 0,
      gpuScaleFailures: _intFromMarker(marker, 'gpuScaleFailures') ?? 0,
      cpuFallback: _intFromMarker(marker, 'cpuFallback') ?? 0,
      nativeNv12Submitted: _intFromMarker(marker, 'nativeNv12Submitted') ?? 0,
      nativeNv12Queued: _intFromMarker(marker, 'nativeNv12Queued') ?? 0,
      nativeNv12Ready: _intFromMarker(marker, 'nativeNv12Ready') ?? 0,
      nativeNv12NotReadyPolls:
          _intFromMarker(marker, 'nativeNv12NotReadyPolls') ?? 0,
      nativeNv12Overwritten:
          _intFromMarker(marker, 'nativeNv12Overwritten') ?? 0,
      nativeNv12OverwrittenFresh:
          _intFromMarker(marker, 'nativeNv12OverwrittenFresh') ?? 0,
      nativeNv12ReadyDropped:
          _intFromMarker(marker, 'nativeNv12ReadyDropped') ?? 0,
      nativeNv12ReadyDroppedFresh:
          _intFromMarker(marker, 'nativeNv12ReadyDroppedFresh') ?? 0,
      nativeNv12Failures: _intFromMarker(marker, 'nativeNv12Failures') ?? 0,
      readbackQueued: _intFromMarker(marker, 'readbackQueued') ?? 0,
      readbackReady: _intFromMarker(marker, 'readbackReady') ?? 0,
      readbackNotReady: _intFromMarker(marker, 'readbackNotReady') ?? 0,
      readbackStaleDropped: _intFromMarker(marker, 'readbackStaleDropped') ?? 0,
      readbackLatencyDropped:
          _intFromMarker(marker, 'readbackLatencyDropped') ?? 0,
      sourceFrameRegressions:
          _intFromMarker(marker, 'sourceFrameRegressions') ?? 0,
      sourceFrameGaps: _intFromMarker(marker, 'sourceFrameGaps') ?? 0,
      sharedSlotMismatches: _intFromMarker(marker, 'sharedSlotMismatches') ?? 0,
      deliveryRepeatNoQueued:
          _intFromMarker(marker, 'deliveryRepeatNoQueued') ?? 0,
      deliveryOverwrittenFresh:
          _intFromMarker(marker, 'deliveryOverwrittenFresh') ?? 0,
      deliveryRepeatSourceAgeMaxMs:
          _doubleFromMarker(marker, 'deliveryRepeatSourceAgeMaxMs'),
      deliveryOverwriteAgeMaxMs:
          _doubleFromMarker(marker, 'deliveryOverwriteAgeMaxMs'),
      sourceDuplicateSkipAgeMaxMs:
          _doubleFromMarker(marker, 'sourceDuplicateSkipAgeMaxMs'),
      nativeNv12OverwriteAgeMaxMs:
          _doubleFromMarker(marker, 'nativeNv12OverwriteAgeMaxMs'),
      nativeNv12ReadyDropAgeMaxMs:
          _doubleFromMarker(marker, 'nativeNv12ReadyDropAgeMaxMs'),
      deliveryWallDeltaMaxMs:
          _doubleFromMarker(marker, 'deliveryWallDeltaMaxMs'),
      deliveryQueueWaitMaxMs:
          _doubleFromMarker(marker, 'deliveryQueueWaitMaxMs'),
      readyToSubmitMaxMs: _doubleFromMarker(marker, 'readyToSubmitMaxMs'),
      sourceToSubmitMaxMs: _doubleFromMarker(marker, 'sourceToSubmitMaxMs'),
      sourceToReadbackReadyMaxMs:
          _doubleFromMarker(marker, 'sourceToReadbackReadyMaxMs'),
      readbackQueueToMapMaxMs:
          _doubleFromMarker(marker, 'readbackQueueToMapMaxMs'),
      mapToI420MaxMs: _doubleFromMarker(marker, 'mapToI420MaxMs'),
      sourceToI420ReadyMaxMs:
          _doubleFromMarker(marker, 'sourceToI420ReadyMaxMs'),
      sourceToQueueMaxMs: _doubleFromMarker(marker, 'sourceToQueueMaxMs'),
      deliveryWallOver2x: _intFromMarker(marker, 'deliveryWallOver2x') ?? 0,
      deliveryWallOver3x: _intFromMarker(marker, 'deliveryWallOver3x') ?? 0,
      deliveryWallUnderHalf:
          _intFromMarker(marker, 'deliveryWallUnderHalf') ?? 0,
      readbackLatencyFramesMax:
          _intFromMarker(marker, 'readbackLatencyFramesMax') ?? 0,
      readbackLatencyFramesAvg:
          _doubleFromMarker(marker, 'readbackLatencyFramesAvg'),
    );
  }

  static List<_GameCaptureMarkerSample> fromMarkers(List<String> markers) {
    final samples = <_GameCaptureMarkerSample>[];
    for (final marker in markers) {
      if (!marker.toLowerCase().contains('game_capture_webrtc_source') ||
          !marker.toLowerCase().contains('stats')) {
        continue;
      }
      final sample = _GameCaptureMarkerSample.fromMarker(marker);
      if (sample.timestamp != null) {
        samples.add(sample);
      }
    }
    samples.sort((left, right) => left.timestamp!.compareTo(right.timestamp!));
    return List.unmodifiable(samples);
  }

  final DateTime? timestamp;
  final int submitted;
  final int copied;
  final int gpuScaled;
  final int gpuScaleFailures;
  final int cpuFallback;
  final int nativeNv12Submitted;
  final int nativeNv12Queued;
  final int nativeNv12Ready;
  final int nativeNv12NotReadyPolls;
  final int nativeNv12Overwritten;
  final int nativeNv12OverwrittenFresh;
  final int nativeNv12ReadyDropped;
  final int nativeNv12ReadyDroppedFresh;
  final int nativeNv12Failures;
  final int readbackQueued;
  final int readbackReady;
  final int readbackNotReady;
  final int readbackStaleDropped;
  final int readbackLatencyDropped;
  final int sourceFrameRegressions;
  final int sourceFrameGaps;
  final int sharedSlotMismatches;
  final int deliveryRepeatNoQueued;
  final int deliveryOverwrittenFresh;
  final double? deliveryRepeatSourceAgeMaxMs;
  final double? deliveryOverwriteAgeMaxMs;
  final double? sourceDuplicateSkipAgeMaxMs;
  final double? nativeNv12OverwriteAgeMaxMs;
  final double? nativeNv12ReadyDropAgeMaxMs;
  final double? deliveryWallDeltaMaxMs;
  final double? deliveryQueueWaitMaxMs;
  final double? readyToSubmitMaxMs;
  final double? sourceToSubmitMaxMs;
  final double? sourceToReadbackReadyMaxMs;
  final double? readbackQueueToMapMaxMs;
  final double? mapToI420MaxMs;
  final double? sourceToI420ReadyMaxMs;
  final double? sourceToQueueMaxMs;
  final int deliveryWallOver2x;
  final int deliveryWallOver3x;
  final int deliveryWallUnderHalf;
  final int readbackLatencyFramesMax;
  final double? readbackLatencyFramesAvg;
}

class StreamTestGameCaptureWindowCounters {
  const StreamTestGameCaptureWindowCounters({
    required this.markerPairCount,
    required this.elapsedMs,
    required this.submittedDelta,
    required this.copiedDelta,
    required this.gpuScaledDelta,
    required this.gpuScaleFailuresDelta,
    required this.cpuFallbackDelta,
    required this.nativeNv12SubmittedDelta,
    required this.nativeNv12QueuedDelta,
    required this.nativeNv12ReadyDelta,
    required this.nativeNv12NotReadyPollsDelta,
    required this.nativeNv12OverwrittenDelta,
    required this.nativeNv12OverwrittenFreshDelta,
    required this.nativeNv12ReadyDroppedDelta,
    required this.nativeNv12ReadyDroppedFreshDelta,
    required this.nativeNv12FailuresDelta,
    required this.readbackQueuedDelta,
    required this.readbackReadyDelta,
    required this.readbackNotReadyDelta,
    required this.readbackStaleDroppedDelta,
    required this.readbackLatencyDroppedDelta,
    required this.sourceFrameRegressionsDelta,
    required this.sourceFrameGapsDelta,
    required this.sharedSlotMismatchesDelta,
    required this.deliveryRepeatNoQueuedDelta,
    required this.deliveryOverwrittenFreshDelta,
    this.maxDeliveryRepeatSourceAgeMs,
    this.maxDeliveryOverwriteAgeMs,
    this.maxSourceDuplicateSkipAgeMs,
    this.maxNativeNv12OverwriteAgeMs,
    this.maxNativeNv12ReadyDropAgeMs,
    this.maxDeliveryWallDeltaMs,
    this.maxDeliveryQueueWaitMs,
    this.maxReadyToSubmitMs,
    this.maxSourceToSubmitMs,
    this.maxSourceToReadbackReadyMs,
    this.maxReadbackQueueToMapMs,
    this.maxMapToI420Ms,
    this.maxSourceToI420ReadyMs,
    this.maxSourceToQueueMs,
    required this.deliveryWallOver2xDelta,
    required this.deliveryWallOver3xDelta,
    required this.deliveryWallUnderHalfDelta,
    required this.maxReadbackLatencyFrames,
    this.maxAverageReadbackLatencyFrames,
  });

  factory StreamTestGameCaptureWindowCounters.fromMarkerPairs({
    required List<_GameCaptureMarkerSample> markerSamples,
    required DateTime? measurementStartedAt,
    required Duration startOffset,
    required Duration endOffset,
  }) {
    if (measurementStartedAt == null || markerSamples.length < 2) {
      return const StreamTestGameCaptureWindowCounters.empty();
    }
    var markerPairCount = 0;
    var elapsedMs = 0.0;
    var submittedDelta = 0;
    var copiedDelta = 0;
    var gpuScaledDelta = 0;
    var gpuScaleFailuresDelta = 0;
    var cpuFallbackDelta = 0;
    var nativeNv12SubmittedDelta = 0;
    var nativeNv12QueuedDelta = 0;
    var nativeNv12ReadyDelta = 0;
    var nativeNv12NotReadyPollsDelta = 0;
    var nativeNv12OverwrittenDelta = 0;
    var nativeNv12OverwrittenFreshDelta = 0;
    var nativeNv12ReadyDroppedDelta = 0;
    var nativeNv12ReadyDroppedFreshDelta = 0;
    var nativeNv12FailuresDelta = 0;
    var readbackQueuedDelta = 0;
    var readbackReadyDelta = 0;
    var readbackNotReadyDelta = 0;
    var readbackStaleDroppedDelta = 0;
    var readbackLatencyDroppedDelta = 0;
    var sourceFrameRegressionsDelta = 0;
    var sourceFrameGapsDelta = 0;
    var sharedSlotMismatchesDelta = 0;
    var deliveryRepeatNoQueuedDelta = 0;
    var deliveryOverwrittenFreshDelta = 0;
    double? maxDeliveryRepeatSourceAgeMs;
    double? maxDeliveryOverwriteAgeMs;
    double? maxSourceDuplicateSkipAgeMs;
    double? maxNativeNv12OverwriteAgeMs;
    double? maxNativeNv12ReadyDropAgeMs;
    double? maxDeliveryWallDeltaMs;
    double? maxDeliveryQueueWaitMs;
    double? maxReadyToSubmitMs;
    double? maxSourceToSubmitMs;
    double? maxSourceToReadbackReadyMs;
    double? maxReadbackQueueToMapMs;
    double? maxMapToI420Ms;
    double? maxSourceToI420ReadyMs;
    double? maxSourceToQueueMs;
    var deliveryWallOver2xDelta = 0;
    var deliveryWallOver3xDelta = 0;
    var deliveryWallUnderHalfDelta = 0;
    var maxReadbackLatencyFrames = 0;
    double? maxAverageReadbackLatencyFrames;

    for (var index = 1; index < markerSamples.length; index++) {
      final previous = markerSamples[index - 1];
      final current = markerSamples[index];
      final currentTimestamp = current.timestamp;
      final previousTimestamp = previous.timestamp;
      if (currentTimestamp == null || previousTimestamp == null) {
        continue;
      }
      final offset = currentTimestamp.difference(measurementStartedAt);
      if (offset < startOffset || offset > endOffset) {
        continue;
      }
      markerPairCount++;
      elapsedMs +=
          currentTimestamp.difference(previousTimestamp).inMicroseconds /
              1000.0;
      submittedDelta += _counterDelta(previous.submitted, current.submitted);
      copiedDelta += _counterDelta(previous.copied, current.copied);
      gpuScaledDelta += _counterDelta(previous.gpuScaled, current.gpuScaled);
      gpuScaleFailuresDelta +=
          _counterDelta(previous.gpuScaleFailures, current.gpuScaleFailures);
      cpuFallbackDelta +=
          _counterDelta(previous.cpuFallback, current.cpuFallback);
      nativeNv12SubmittedDelta += _counterDelta(
        previous.nativeNv12Submitted,
        current.nativeNv12Submitted,
      );
      nativeNv12QueuedDelta += _counterDelta(
        previous.nativeNv12Queued,
        current.nativeNv12Queued,
      );
      nativeNv12ReadyDelta += _counterDelta(
        previous.nativeNv12Ready,
        current.nativeNv12Ready,
      );
      nativeNv12NotReadyPollsDelta += _counterDelta(
        previous.nativeNv12NotReadyPolls,
        current.nativeNv12NotReadyPolls,
      );
      nativeNv12OverwrittenDelta += _counterDelta(
        previous.nativeNv12Overwritten,
        current.nativeNv12Overwritten,
      );
      nativeNv12OverwrittenFreshDelta += _counterDelta(
        previous.nativeNv12OverwrittenFresh,
        current.nativeNv12OverwrittenFresh,
      );
      nativeNv12ReadyDroppedDelta += _counterDelta(
        previous.nativeNv12ReadyDropped,
        current.nativeNv12ReadyDropped,
      );
      nativeNv12ReadyDroppedFreshDelta += _counterDelta(
        previous.nativeNv12ReadyDroppedFresh,
        current.nativeNv12ReadyDroppedFresh,
      );
      nativeNv12FailuresDelta += _counterDelta(
        previous.nativeNv12Failures,
        current.nativeNv12Failures,
      );
      readbackQueuedDelta +=
          _counterDelta(previous.readbackQueued, current.readbackQueued);
      readbackReadyDelta +=
          _counterDelta(previous.readbackReady, current.readbackReady);
      readbackNotReadyDelta +=
          _counterDelta(previous.readbackNotReady, current.readbackNotReady);
      readbackStaleDroppedDelta += _counterDelta(
        previous.readbackStaleDropped,
        current.readbackStaleDropped,
      );
      readbackLatencyDroppedDelta += _counterDelta(
        previous.readbackLatencyDropped,
        current.readbackLatencyDropped,
      );
      sourceFrameRegressionsDelta += _counterDelta(
        previous.sourceFrameRegressions,
        current.sourceFrameRegressions,
      );
      sourceFrameGapsDelta +=
          _counterDelta(previous.sourceFrameGaps, current.sourceFrameGaps);
      sharedSlotMismatchesDelta += _counterDelta(
        previous.sharedSlotMismatches,
        current.sharedSlotMismatches,
      );
      deliveryRepeatNoQueuedDelta += _counterDelta(
        previous.deliveryRepeatNoQueued,
        current.deliveryRepeatNoQueued,
      );
      deliveryOverwrittenFreshDelta += _counterDelta(
        previous.deliveryOverwrittenFresh,
        current.deliveryOverwrittenFresh,
      );
      final repeatSourceAgeMax = current.deliveryRepeatSourceAgeMaxMs;
      if (repeatSourceAgeMax != null) {
        maxDeliveryRepeatSourceAgeMs = max(
          maxDeliveryRepeatSourceAgeMs ?? repeatSourceAgeMax,
          repeatSourceAgeMax,
        );
      }
      final deliveryOverwriteAgeMax = current.deliveryOverwriteAgeMaxMs;
      if (deliveryOverwriteAgeMax != null) {
        maxDeliveryOverwriteAgeMs = max(
          maxDeliveryOverwriteAgeMs ?? deliveryOverwriteAgeMax,
          deliveryOverwriteAgeMax,
        );
      }
      final sourceDuplicateSkipAgeMax = current.sourceDuplicateSkipAgeMaxMs;
      if (sourceDuplicateSkipAgeMax != null) {
        maxSourceDuplicateSkipAgeMs = max(
          maxSourceDuplicateSkipAgeMs ?? sourceDuplicateSkipAgeMax,
          sourceDuplicateSkipAgeMax,
        );
      }
      final nativeOverwriteAgeMax = current.nativeNv12OverwriteAgeMaxMs;
      if (nativeOverwriteAgeMax != null) {
        maxNativeNv12OverwriteAgeMs = max(
          maxNativeNv12OverwriteAgeMs ?? nativeOverwriteAgeMax,
          nativeOverwriteAgeMax,
        );
      }
      final nativeReadyDropAgeMax = current.nativeNv12ReadyDropAgeMaxMs;
      if (nativeReadyDropAgeMax != null) {
        maxNativeNv12ReadyDropAgeMs = max(
          maxNativeNv12ReadyDropAgeMs ?? nativeReadyDropAgeMax,
          nativeReadyDropAgeMax,
        );
      }
      final deliveryWallDeltaMax = current.deliveryWallDeltaMaxMs;
      if (deliveryWallDeltaMax != null) {
        maxDeliveryWallDeltaMs = max(
          maxDeliveryWallDeltaMs ?? deliveryWallDeltaMax,
          deliveryWallDeltaMax,
        );
      }
      final queueWaitMax = current.deliveryQueueWaitMaxMs;
      if (queueWaitMax != null) {
        maxDeliveryQueueWaitMs = max(
          maxDeliveryQueueWaitMs ?? queueWaitMax,
          queueWaitMax,
        );
      }
      final readyToSubmitMax = current.readyToSubmitMaxMs;
      if (readyToSubmitMax != null) {
        maxReadyToSubmitMs = max(
          maxReadyToSubmitMs ?? readyToSubmitMax,
          readyToSubmitMax,
        );
      }
      final sourceToSubmitMax = current.sourceToSubmitMaxMs;
      if (sourceToSubmitMax != null) {
        maxSourceToSubmitMs = max(
          maxSourceToSubmitMs ?? sourceToSubmitMax,
          sourceToSubmitMax,
        );
      }
      final sourceToReadbackReadyMax = current.sourceToReadbackReadyMaxMs;
      if (sourceToReadbackReadyMax != null) {
        maxSourceToReadbackReadyMs = max(
          maxSourceToReadbackReadyMs ?? sourceToReadbackReadyMax,
          sourceToReadbackReadyMax,
        );
      }
      final readbackQueueToMapMax = current.readbackQueueToMapMaxMs;
      if (readbackQueueToMapMax != null) {
        maxReadbackQueueToMapMs = max(
          maxReadbackQueueToMapMs ?? readbackQueueToMapMax,
          readbackQueueToMapMax,
        );
      }
      final mapToI420Max = current.mapToI420MaxMs;
      if (mapToI420Max != null) {
        maxMapToI420Ms = max(maxMapToI420Ms ?? mapToI420Max, mapToI420Max);
      }
      final sourceToI420ReadyMax = current.sourceToI420ReadyMaxMs;
      if (sourceToI420ReadyMax != null) {
        maxSourceToI420ReadyMs = max(
          maxSourceToI420ReadyMs ?? sourceToI420ReadyMax,
          sourceToI420ReadyMax,
        );
      }
      final sourceToQueueMax = current.sourceToQueueMaxMs;
      if (sourceToQueueMax != null) {
        maxSourceToQueueMs = max(
          maxSourceToQueueMs ?? sourceToQueueMax,
          sourceToQueueMax,
        );
      }
      deliveryWallOver2xDelta += _counterDelta(
        previous.deliveryWallOver2x,
        current.deliveryWallOver2x,
      );
      deliveryWallOver3xDelta += _counterDelta(
        previous.deliveryWallOver3x,
        current.deliveryWallOver3x,
      );
      deliveryWallUnderHalfDelta += _counterDelta(
        previous.deliveryWallUnderHalf,
        current.deliveryWallUnderHalf,
      );
      maxReadbackLatencyFrames = max(
        maxReadbackLatencyFrames,
        current.readbackLatencyFramesMax,
      );
      final averageLatency = current.readbackLatencyFramesAvg;
      if (averageLatency != null) {
        maxAverageReadbackLatencyFrames = max(
          maxAverageReadbackLatencyFrames ?? averageLatency,
          averageLatency,
        );
      }
    }

    return StreamTestGameCaptureWindowCounters(
      markerPairCount: markerPairCount,
      elapsedMs: elapsedMs,
      submittedDelta: submittedDelta,
      copiedDelta: copiedDelta,
      gpuScaledDelta: gpuScaledDelta,
      gpuScaleFailuresDelta: gpuScaleFailuresDelta,
      cpuFallbackDelta: cpuFallbackDelta,
      nativeNv12SubmittedDelta: nativeNv12SubmittedDelta,
      nativeNv12QueuedDelta: nativeNv12QueuedDelta,
      nativeNv12ReadyDelta: nativeNv12ReadyDelta,
      nativeNv12NotReadyPollsDelta: nativeNv12NotReadyPollsDelta,
      nativeNv12OverwrittenDelta: nativeNv12OverwrittenDelta,
      nativeNv12OverwrittenFreshDelta: nativeNv12OverwrittenFreshDelta,
      nativeNv12ReadyDroppedDelta: nativeNv12ReadyDroppedDelta,
      nativeNv12ReadyDroppedFreshDelta: nativeNv12ReadyDroppedFreshDelta,
      nativeNv12FailuresDelta: nativeNv12FailuresDelta,
      readbackQueuedDelta: readbackQueuedDelta,
      readbackReadyDelta: readbackReadyDelta,
      readbackNotReadyDelta: readbackNotReadyDelta,
      readbackStaleDroppedDelta: readbackStaleDroppedDelta,
      readbackLatencyDroppedDelta: readbackLatencyDroppedDelta,
      sourceFrameRegressionsDelta: sourceFrameRegressionsDelta,
      sourceFrameGapsDelta: sourceFrameGapsDelta,
      sharedSlotMismatchesDelta: sharedSlotMismatchesDelta,
      deliveryRepeatNoQueuedDelta: deliveryRepeatNoQueuedDelta,
      deliveryOverwrittenFreshDelta: deliveryOverwrittenFreshDelta,
      maxDeliveryRepeatSourceAgeMs: maxDeliveryRepeatSourceAgeMs,
      maxDeliveryOverwriteAgeMs: maxDeliveryOverwriteAgeMs,
      maxSourceDuplicateSkipAgeMs: maxSourceDuplicateSkipAgeMs,
      maxNativeNv12OverwriteAgeMs: maxNativeNv12OverwriteAgeMs,
      maxNativeNv12ReadyDropAgeMs: maxNativeNv12ReadyDropAgeMs,
      maxDeliveryWallDeltaMs: maxDeliveryWallDeltaMs,
      maxDeliveryQueueWaitMs: maxDeliveryQueueWaitMs,
      maxReadyToSubmitMs: maxReadyToSubmitMs,
      maxSourceToSubmitMs: maxSourceToSubmitMs,
      maxSourceToReadbackReadyMs: maxSourceToReadbackReadyMs,
      maxReadbackQueueToMapMs: maxReadbackQueueToMapMs,
      maxMapToI420Ms: maxMapToI420Ms,
      maxSourceToI420ReadyMs: maxSourceToI420ReadyMs,
      maxSourceToQueueMs: maxSourceToQueueMs,
      deliveryWallOver2xDelta: deliveryWallOver2xDelta,
      deliveryWallOver3xDelta: deliveryWallOver3xDelta,
      deliveryWallUnderHalfDelta: deliveryWallUnderHalfDelta,
      maxReadbackLatencyFrames: maxReadbackLatencyFrames,
      maxAverageReadbackLatencyFrames: maxAverageReadbackLatencyFrames,
    );
  }

  const StreamTestGameCaptureWindowCounters.empty()
      : markerPairCount = 0,
        elapsedMs = 0,
        submittedDelta = 0,
        copiedDelta = 0,
        gpuScaledDelta = 0,
        gpuScaleFailuresDelta = 0,
        cpuFallbackDelta = 0,
        nativeNv12SubmittedDelta = 0,
        nativeNv12QueuedDelta = 0,
        nativeNv12ReadyDelta = 0,
        nativeNv12NotReadyPollsDelta = 0,
        nativeNv12OverwrittenDelta = 0,
        nativeNv12OverwrittenFreshDelta = 0,
        nativeNv12ReadyDroppedDelta = 0,
        nativeNv12ReadyDroppedFreshDelta = 0,
        nativeNv12FailuresDelta = 0,
        readbackQueuedDelta = 0,
        readbackReadyDelta = 0,
        readbackNotReadyDelta = 0,
        readbackStaleDroppedDelta = 0,
        readbackLatencyDroppedDelta = 0,
        sourceFrameRegressionsDelta = 0,
        sourceFrameGapsDelta = 0,
        sharedSlotMismatchesDelta = 0,
        deliveryRepeatNoQueuedDelta = 0,
        deliveryOverwrittenFreshDelta = 0,
        maxDeliveryRepeatSourceAgeMs = null,
        maxDeliveryOverwriteAgeMs = null,
        maxSourceDuplicateSkipAgeMs = null,
        maxNativeNv12OverwriteAgeMs = null,
        maxNativeNv12ReadyDropAgeMs = null,
        maxDeliveryWallDeltaMs = null,
        maxDeliveryQueueWaitMs = null,
        maxReadyToSubmitMs = null,
        maxSourceToSubmitMs = null,
        maxSourceToReadbackReadyMs = null,
        maxReadbackQueueToMapMs = null,
        maxMapToI420Ms = null,
        maxSourceToI420ReadyMs = null,
        maxSourceToQueueMs = null,
        deliveryWallOver2xDelta = 0,
        deliveryWallOver3xDelta = 0,
        deliveryWallUnderHalfDelta = 0,
        maxReadbackLatencyFrames = 0,
        maxAverageReadbackLatencyFrames = null;

  final int markerPairCount;
  final double elapsedMs;
  final int submittedDelta;
  final int copiedDelta;
  final int gpuScaledDelta;
  final int gpuScaleFailuresDelta;
  final int cpuFallbackDelta;
  final int nativeNv12SubmittedDelta;
  final int nativeNv12QueuedDelta;
  final int nativeNv12ReadyDelta;
  final int nativeNv12NotReadyPollsDelta;
  final int nativeNv12OverwrittenDelta;
  final int nativeNv12OverwrittenFreshDelta;
  final int nativeNv12ReadyDroppedDelta;
  final int nativeNv12ReadyDroppedFreshDelta;
  final int nativeNv12FailuresDelta;
  final int readbackQueuedDelta;
  final int readbackReadyDelta;
  final int readbackNotReadyDelta;
  final int readbackStaleDroppedDelta;
  final int readbackLatencyDroppedDelta;
  final int sourceFrameRegressionsDelta;
  final int sourceFrameGapsDelta;
  final int sharedSlotMismatchesDelta;
  final int deliveryRepeatNoQueuedDelta;
  final int deliveryOverwrittenFreshDelta;
  final double? maxDeliveryRepeatSourceAgeMs;
  final double? maxDeliveryOverwriteAgeMs;
  final double? maxSourceDuplicateSkipAgeMs;
  final double? maxNativeNv12OverwriteAgeMs;
  final double? maxNativeNv12ReadyDropAgeMs;
  final double? maxDeliveryWallDeltaMs;
  final double? maxDeliveryQueueWaitMs;
  final double? maxReadyToSubmitMs;
  final double? maxSourceToSubmitMs;
  final double? maxSourceToReadbackReadyMs;
  final double? maxReadbackQueueToMapMs;
  final double? maxMapToI420Ms;
  final double? maxSourceToI420ReadyMs;
  final double? maxSourceToQueueMs;
  final int deliveryWallOver2xDelta;
  final int deliveryWallOver3xDelta;
  final int deliveryWallUnderHalfDelta;
  final int maxReadbackLatencyFrames;
  final double? maxAverageReadbackLatencyFrames;

  bool get hasEvidence => markerPairCount > 0;

  double? get submittedFps =>
      elapsedMs > 0 ? submittedDelta * 1000 / elapsedMs : null;

  String get compactLabel {
    if (!hasEvidence) {
      return 'native window unavailable';
    }
    return 'submitted ${_number(submittedFps)}fps, '
        'gpu +$gpuScaledDelta/cpu +$cpuFallbackDelta, '
        'native-nv12 +$nativeNv12SubmittedDelta/'
        'queued +$nativeNv12QueuedDelta/'
        'ready +$nativeNv12ReadyDelta/'
        'not-ready +$nativeNv12NotReadyPollsDelta/'
        'overwrite +$nativeNv12OverwrittenDelta/'
        'overwrite-fresh +$nativeNv12OverwrittenFreshDelta/'
        'ready-drop +$nativeNv12ReadyDroppedDelta/'
        'ready-drop-fresh +$nativeNv12ReadyDroppedFreshDelta/'
        'fail +$nativeNv12FailuresDelta, '
        'readback ready +$readbackReadyDelta/not-ready +$readbackNotReadyDelta, '
        'repeat-no-queue +$deliveryRepeatNoQueuedDelta, '
        'repeat-age ${_milliseconds(maxDeliveryRepeatSourceAgeMs)}, '
        'source-duplicate-age ${_milliseconds(maxSourceDuplicateSkipAgeMs)}, '
        'overwrite-age ${_milliseconds(maxDeliveryOverwriteAgeMs)}, '
        'overwrite-fresh +$deliveryOverwrittenFreshDelta, '
        'nv12-overwrite-age ${_milliseconds(maxNativeNv12OverwriteAgeMs)}, '
        'nv12-ready-drop-age ${_milliseconds(maxNativeNv12ReadyDropAgeMs)}, '
        'wall-gap ${_milliseconds(maxDeliveryWallDeltaMs)}, '
        'queue-wait ${_milliseconds(maxDeliveryQueueWaitMs)}, '
        'ready-submit ${_milliseconds(maxReadyToSubmitMs)}, '
        'source-submit ${_milliseconds(maxSourceToSubmitMs)}, '
        'source-readback ${_milliseconds(maxSourceToReadbackReadyMs)}, '
        'queue-map ${_milliseconds(maxReadbackQueueToMapMs)}, '
        'map-i420 ${_milliseconds(maxMapToI420Ms)}, '
        'source-i420 ${_milliseconds(maxSourceToI420ReadyMs)}, '
        'source-queue ${_milliseconds(maxSourceToQueueMs)}, '
        'gap-counts >2x +$deliveryWallOver2xDelta/'
        '>3x +$deliveryWallOver3xDelta/'
        '<0.5x +$deliveryWallUnderHalfDelta, '
        'latency-drop +$readbackLatencyDroppedDelta, '
        'stale +$readbackStaleDroppedDelta, '
        'max latency ${maxReadbackLatencyFrames}f';
  }

  Map<String, Object?> toJson() {
    return {
      'markerPairCount': markerPairCount,
      'elapsedMs': elapsedMs,
      'submittedDelta': submittedDelta,
      'submittedFps': submittedFps,
      'copiedDelta': copiedDelta,
      'gpuScaledDelta': gpuScaledDelta,
      'gpuScaleFailuresDelta': gpuScaleFailuresDelta,
      'cpuFallbackDelta': cpuFallbackDelta,
      'nativeNv12SubmittedDelta': nativeNv12SubmittedDelta,
      'nativeNv12QueuedDelta': nativeNv12QueuedDelta,
      'nativeNv12ReadyDelta': nativeNv12ReadyDelta,
      'nativeNv12NotReadyPollsDelta': nativeNv12NotReadyPollsDelta,
      'nativeNv12OverwrittenDelta': nativeNv12OverwrittenDelta,
      'nativeNv12OverwrittenFreshDelta': nativeNv12OverwrittenFreshDelta,
      'nativeNv12ReadyDroppedDelta': nativeNv12ReadyDroppedDelta,
      'nativeNv12ReadyDroppedFreshDelta': nativeNv12ReadyDroppedFreshDelta,
      'nativeNv12FailuresDelta': nativeNv12FailuresDelta,
      'readbackQueuedDelta': readbackQueuedDelta,
      'readbackReadyDelta': readbackReadyDelta,
      'readbackNotReadyDelta': readbackNotReadyDelta,
      'readbackStaleDroppedDelta': readbackStaleDroppedDelta,
      'readbackLatencyDroppedDelta': readbackLatencyDroppedDelta,
      'sourceFrameRegressionsDelta': sourceFrameRegressionsDelta,
      'sourceFrameGapsDelta': sourceFrameGapsDelta,
      'sharedSlotMismatchesDelta': sharedSlotMismatchesDelta,
      'deliveryRepeatNoQueuedDelta': deliveryRepeatNoQueuedDelta,
      'deliveryOverwrittenFreshDelta': deliveryOverwrittenFreshDelta,
      'maxDeliveryRepeatSourceAgeMs': maxDeliveryRepeatSourceAgeMs,
      'maxDeliveryOverwriteAgeMs': maxDeliveryOverwriteAgeMs,
      'maxSourceDuplicateSkipAgeMs': maxSourceDuplicateSkipAgeMs,
      'maxNativeNv12OverwriteAgeMs': maxNativeNv12OverwriteAgeMs,
      'maxNativeNv12ReadyDropAgeMs': maxNativeNv12ReadyDropAgeMs,
      'maxDeliveryWallDeltaMs': maxDeliveryWallDeltaMs,
      'maxDeliveryQueueWaitMs': maxDeliveryQueueWaitMs,
      'maxReadyToSubmitMs': maxReadyToSubmitMs,
      'maxSourceToSubmitMs': maxSourceToSubmitMs,
      'maxSourceToReadbackReadyMs': maxSourceToReadbackReadyMs,
      'maxReadbackQueueToMapMs': maxReadbackQueueToMapMs,
      'maxMapToI420Ms': maxMapToI420Ms,
      'maxSourceToI420ReadyMs': maxSourceToI420ReadyMs,
      'maxSourceToQueueMs': maxSourceToQueueMs,
      'deliveryWallOver2xDelta': deliveryWallOver2xDelta,
      'deliveryWallOver3xDelta': deliveryWallOver3xDelta,
      'deliveryWallUnderHalfDelta': deliveryWallUnderHalfDelta,
      'maxReadbackLatencyFrames': maxReadbackLatencyFrames,
      'maxAverageReadbackLatencyFrames': maxAverageReadbackLatencyFrames,
    };
  }
}

class StreamTestSummary {
  const StreamTestSummary({
    required this.senderSampleCount,
    required this.preEncodeSampleCount,
    this.screenShareProfileDetails = const {},
    this.senderCodecs = const {},
    this.encoderImplementations = const {},
    this.hardwareEncodeStates = const {},
    this.averageFps,
    this.minimumFps,
    this.averageCaptureFps,
    this.minimumCaptureFps,
    this.averageEncodeFps,
    this.minimumEncodeFps,
    this.averageSendFps,
    this.minimumSendFps,
    this.averageBitrateBps,
    this.averageAvailableOutgoingBitrateBps,
    this.minimumAvailableOutgoingBitrateBps,
    this.maximumAvailableOutgoingBitrateBps,
    this.requestedWidth,
    this.requestedHeight,
    this.requestedFps,
    this.requestedBitrateBps,
    this.preEncodeWidth,
    this.preEncodeHeight,
    this.encodedWidth,
    this.encodedHeight,
    this.averageEncodeTimeMs,
    this.maxEncodeTimeMs,
    this.averagePacketSendDelayMs,
    this.maxPacketSendDelayMs,
    this.maxPacketLossPercent,
    this.maxRoundTripTimeMs,
    this.maxNackCount,
    this.framesCapturedMax,
    this.framesEncodedMax,
    this.framesSentMax,
    this.framesDroppedBeforeEncodeMax,
    this.framesDroppedByEncoderMax,
    this.qualityLimitationReasons = const {},
    this.activeLayers = const {},
    this.nativeDiagnostics = const StreamTestNativeDiagnostics(),
    this.framePacing = const StreamTestFramePacingSummary(),
  });

  factory StreamTestSummary.fromSamples(
    List<StreamTestSample> samples, {
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
  }) {
    final senderTracks = samples
        .map((sample) => _bestSenderTrack(sample.snapshot))
        .whereType<VoipTrackDiagnostics>()
        .toList(growable: false);
    final profileDetails = samples
        .map((sample) => sample.snapshot.screenShareProfileDetails)
        .whereType<String>()
        .where((details) => details.trim().isNotEmpty)
        .toSet();
    final senderCodecs = senderTracks
        .map((track) => track.codec)
        .whereType<String>()
        .where((codec) => codec.trim().isNotEmpty)
        .toSet();
    final encoderImplementations = senderTracks
        .map((track) => track.encoderImplementation)
        .whereType<String>()
        .where((implementation) => implementation.trim().isNotEmpty)
        .toSet();
    final hardwareEncodeStates = senderTracks
        .map((track) => track.hardwareEncodeActive)
        .whereType<bool>()
        .toSet();
    final fpsValues = senderTracks
        .map((track) => track.sendFps ?? track.encodeFps ?? track.fps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final captureFpsValues = senderTracks
        .map((track) => track.captureFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final encodeFpsValues = senderTracks
        .map((track) => track.encodeFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final sendFpsValues = senderTracks
        .map((track) => track.sendFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final bitrateValues = senderTracks
        .map((track) => track.bitrateBps)
        .whereType<int>()
        .where((bitrate) => bitrate > 0)
        .toList(growable: false);
    final availableOutgoingBitrateValues = senderTracks
        .map((track) => track.availableOutgoingBitrateBps)
        .whereType<int>()
        .where((bitrate) => bitrate > 0)
        .toList(growable: false);
    final encodeTimeValues = senderTracks
        .map((track) => track.averageEncodeTimeMs)
        .whereType<double>()
        .where((duration) => duration > 0)
        .toList(growable: false);
    final sendDelayValues = senderTracks
        .map((track) => track.averagePacketSendDelayMs)
        .whereType<double>()
        .where((duration) => duration > 0)
        .toList(growable: false);
    final bestResolution = senderTracks.fold<({int width, int height})?>(
      null,
      (best, track) {
        final width = track.width;
        final height = track.height;
        if (width == null || height == null || width <= 0 || height <= 0) {
          return best;
        }
        if (best == null || width * height > best.width * best.height) {
          return (width: width, height: height);
        }
        return best;
      },
    );
    final bestPreEncodeResolution =
        senderTracks.fold<({int width, int height})?>(
      null,
      (best, track) {
        final width = track.preEncodeWidth;
        final height = track.preEncodeHeight;
        if (width == null || height == null || width <= 0 || height <= 0) {
          return best;
        }
        if (best == null || width * height > best.width * best.height) {
          return (width: width, height: height);
        }
        return best;
      },
    );
    final requestedTrack = senderTracks.firstWhere(
      (track) =>
          track.requestedWidth != null ||
          track.requestedHeight != null ||
          track.requestedFps != null ||
          track.requestedBitrateBps != null,
      orElse: () => senderTracks.isEmpty
          ? const VoipTrackDiagnostics(
              streamId: '',
              label: '',
              type: VoipStreamType.screenshare,
              direction: VoipDiagnosticsTrackDirection.sender,
            )
          : senderTracks.first,
    );
    final framePacing = StreamTestFramePacingSummary.fromSamples(
      samples,
      nativeDiagnostics: nativeDiagnostics,
    );

    return StreamTestSummary(
      senderSampleCount: senderTracks.length,
      preEncodeSampleCount: senderTracks
          .where((track) =>
              (track.preEncodeWidth ?? 0) > 0 &&
              (track.preEncodeHeight ?? 0) > 0)
          .length,
      screenShareProfileDetails: profileDetails,
      senderCodecs: senderCodecs,
      encoderImplementations: encoderImplementations,
      hardwareEncodeStates: hardwareEncodeStates,
      averageFps: _average(fpsValues),
      minimumFps: fpsValues.isEmpty ? null : fpsValues.reduce(min),
      averageCaptureFps: _average(captureFpsValues),
      minimumCaptureFps:
          captureFpsValues.isEmpty ? null : captureFpsValues.reduce(min),
      averageEncodeFps: _average(encodeFpsValues),
      minimumEncodeFps:
          encodeFpsValues.isEmpty ? null : encodeFpsValues.reduce(min),
      averageSendFps: _average(sendFpsValues),
      minimumSendFps: sendFpsValues.isEmpty ? null : sendFpsValues.reduce(min),
      averageBitrateBps: _averageInt(bitrateValues),
      averageAvailableOutgoingBitrateBps:
          _averageInt(availableOutgoingBitrateValues),
      minimumAvailableOutgoingBitrateBps:
          _minInt(availableOutgoingBitrateValues),
      maximumAvailableOutgoingBitrateBps:
          _maxInt(availableOutgoingBitrateValues),
      requestedWidth: requestedTrack.requestedWidth,
      requestedHeight: requestedTrack.requestedHeight,
      requestedFps: requestedTrack.requestedFps,
      requestedBitrateBps: requestedTrack.requestedBitrateBps,
      preEncodeWidth: bestPreEncodeResolution?.width,
      preEncodeHeight: bestPreEncodeResolution?.height,
      encodedWidth: bestResolution?.width,
      encodedHeight: bestResolution?.height,
      averageEncodeTimeMs: _average(encodeTimeValues),
      maxEncodeTimeMs: _maxDouble(encodeTimeValues),
      averagePacketSendDelayMs: _average(sendDelayValues),
      maxPacketSendDelayMs: _maxDouble(sendDelayValues),
      maxPacketLossPercent: _maxDouble(senderTracks
          .map((track) => track.packetLossPercent)
          .whereType<double>()),
      maxRoundTripTimeMs: _maxDouble(senderTracks
          .map((track) => track.roundTripTimeMs)
          .whereType<double>()),
      maxNackCount: _maxInt(
          senderTracks.map((track) => track.nackCount).whereType<int>()),
      framesCapturedMax: _maxInt(
          senderTracks.map((track) => track.framesCaptured).whereType<int>()),
      framesEncodedMax: _maxInt(
          senderTracks.map((track) => track.framesEncoded).whereType<int>()),
      framesSentMax: _maxInt(
          senderTracks.map((track) => track.framesSent).whereType<int>()),
      framesDroppedBeforeEncodeMax: _maxInt(senderTracks
          .map((track) => track.framesDroppedBeforeEncode)
          .whereType<int>()),
      framesDroppedByEncoderMax: _maxInt(senderTracks
          .map((track) => track.framesDroppedByEncoder)
          .whereType<int>()),
      qualityLimitationReasons: senderTracks
          .map((track) => track.qualityLimitationReason)
          .whereType<String>()
          .where((reason) => reason.trim().isNotEmpty)
          .toSet(),
      activeLayers: senderTracks
          .map((track) => track.activeLayer ?? track.rid)
          .whereType<String>()
          .where((layer) => layer.trim().isNotEmpty)
          .toSet(),
      nativeDiagnostics: nativeDiagnostics,
      framePacing: framePacing,
    );
  }

  final double? averageFps;
  final double? minimumFps;
  final int senderSampleCount;
  final int preEncodeSampleCount;
  final Set<String> screenShareProfileDetails;
  final Set<String> senderCodecs;
  final Set<String> encoderImplementations;
  final Set<bool> hardwareEncodeStates;
  final double? averageCaptureFps;
  final double? minimumCaptureFps;
  final double? averageEncodeFps;
  final double? minimumEncodeFps;
  final double? averageSendFps;
  final double? minimumSendFps;
  final int? averageBitrateBps;
  final int? averageAvailableOutgoingBitrateBps;
  final int? minimumAvailableOutgoingBitrateBps;
  final int? maximumAvailableOutgoingBitrateBps;
  final int? requestedWidth;
  final int? requestedHeight;
  final double? requestedFps;
  final int? requestedBitrateBps;
  final int? preEncodeWidth;
  final int? preEncodeHeight;
  final int? encodedWidth;
  final int? encodedHeight;
  final double? averageEncodeTimeMs;
  final double? maxEncodeTimeMs;
  final double? averagePacketSendDelayMs;
  final double? maxPacketSendDelayMs;
  final double? maxPacketLossPercent;
  final double? maxRoundTripTimeMs;
  final int? maxNackCount;
  final int? framesCapturedMax;
  final int? framesEncodedMax;
  final int? framesSentMax;
  final int? framesDroppedBeforeEncodeMax;
  final int? framesDroppedByEncoderMax;
  final Set<String> qualityLimitationReasons;
  final Set<String> activeLayers;
  final StreamTestNativeDiagnostics nativeDiagnostics;
  final StreamTestFramePacingSummary framePacing;

  String get encodedResolutionLabel {
    if (encodedWidth == null || encodedHeight == null) {
      return 'unknown';
    }
    return '${encodedWidth}x$encodedHeight';
  }

  String get preEncodeResolutionLabel {
    if (preEncodeWidth == null || preEncodeHeight == null) {
      return 'unknown';
    }
    return '${preEncodeWidth}x$preEncodeHeight';
  }

  String get requestedResolutionLabel {
    if (requestedWidth == null || requestedHeight == null) {
      return 'unknown';
    }
    final fpsLabel = requestedFps == null ? '' : '@${_number(requestedFps)}fps';
    return '${requestedWidth}x$requestedHeight$fpsLabel';
  }

  String get qualityLimitationReasonsLabel => qualityLimitationReasons.isEmpty
      ? 'unknown'
      : qualityLimitationReasons.join(', ');

  String get activeLayersLabel =>
      activeLayers.isEmpty ? 'unknown' : activeLayers.join(', ');

  String get profileDetailsLabel => screenShareProfileDetails.isEmpty
      ? 'unknown'
      : screenShareProfileDetails.join(' | ');

  String get senderCodecsLabel =>
      senderCodecs.isEmpty ? 'unknown' : senderCodecs.join(', ');

  String get encoderImplementationsLabel => encoderImplementations.isEmpty
      ? 'unknown'
      : encoderImplementations.join(', ');

  String get hardwareEncodeStatesLabel => hardwareEncodeStates.isEmpty
      ? 'unknown'
      : hardwareEncodeStates.map((active) => active ? 'yes' : 'no').join(', ');

  String get capturePipelineLabel {
    return 'requested=$requestedResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'encoded=$encodedResolutionLabel '
        'capture=${_number(averageCaptureFps)}fps '
        'encode=${_number(averageEncodeFps)}fps '
        'send=${_number(averageSendFps)}fps';
  }

  List<String> get senderHandoffDiagnosticMissingFields {
    final native = nativeDiagnostics;
    return <String>[
      if (native.gameCaptureDeliveryOnFrameCallSamples == 0)
        'delivery_on_frame_call_ms',
      if (native.gameCaptureNativeNv12ConversionStartAgeSamples == 0)
        'native_nv12_conversion_start_age_ms',
      if (native.gameCaptureNativeNv12SubmittedFrames > 0 &&
          native.gameCaptureNativeNv12FrameOwnership == null)
        'native_nv12_frame_ownership',
      if (native.gameCaptureNativeNv12FrameOwnership == 'owned_texture_copy' &&
          native.gameCaptureNativeNv12OwnedCopySamples == 0)
        'native_nv12_owned_copy_ms',
      if (native.gameCaptureNativeNv12QueuedFrames > 0 &&
          native.gameCaptureNativeNv12ReadyObservedFrames == 0)
        'native_nv12_ready_observation_split',
      if (native.gameCaptureNativeNv12SubmittedFrames > 0 &&
          native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples == 0)
        'native_nv12_blt_gpu_execution_ms',
      if (native.gameCaptureConsumerAdapterLuid == null)
        'consumer_adapter_luid',
      if (native.encoderNativeReadyFenceWaitSamples == 0)
        'native_ready_fence_wait_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeSourceAgeSamples == 0)
        'native_source_age_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeBufferAgeSamples == 0)
        'native_buffer_age_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeSampleLifetimeSamples == 0)
        'native_sample_lifetime_ms',
      if (native.encoderProcessInputSamples == 0) 'process_input_ms',
      if (native.encoderProcessOutputSamples == 0) 'process_output_ms',
      if (native.encoderEncodedCallbackSamples == 0) 'encoded_callback_ms',
      if (!native.hasWebrtcRawSenderBoundaryDiagnostics)
        'webrtc raw sender boundary timing',
      if (native.webrtcSourceOnFrameSamples > 0 &&
          native.webrtcVideoBroadcasterSamples == 0)
        'VideoBroadcaster sink dispatch timing',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterSlowSinkId == null)
        'VideoBroadcaster slow-sink attribution',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterSinkRoster == null)
        'VideoBroadcaster sink roster',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterInactiveSinks > 0 &&
          !native.webrtcVideoBroadcasterInactiveNativeSinkBypassReported)
        'VideoBroadcaster inactive native bypass counter',
      if (native.encoderMaxQueueDepth == 0) 'encoder queue depth',
      if (framesDroppedBeforeEncodeMax == null &&
          framesDroppedByEncoderMax == null)
        'sender drop counters',
    ];
  }

  bool get hasSenderHandoffDiagnostics {
    final native = nativeDiagnostics;
    return native.gameCaptureDeliveryOnFrameCallSamples > 0 ||
        native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 ||
        native.encoderNativeReadyFenceWaitSamples > 0 ||
        native.encoderProcessInputSamples > 0 ||
        native.encoderProcessOutputSamples > 0 ||
        native.encoderEncodedCallbackSamples > 0 ||
        native.encoderEncodedCallbackQueueWaitSamples > 0 ||
        native.encoderEncodedCallbackEnqueueSamples > 0 ||
        native.encoderMaxEncodedCallbackQueueDepth > 0 ||
        native.encoderMaxEncodedCallbackDrops > 0 ||
        native.gameCaptureConsumerAdapterLuid != null ||
        native.gameCaptureNativeNv12GpuQueueBackoffEnabled != null ||
        native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames > 0 ||
        native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames > 0 ||
        native.gameCaptureNativeNv12GpuQueueBackoffSamples > 0 ||
        native.gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples >
            0 ||
        native.gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples >
            0 ||
        native.gameCaptureNativeNv12FrameOwnership != null ||
        native.gameCaptureNativeNv12OwnedCopySamples > 0 ||
        native.gameCaptureNativeNv12ReadyObservedFrames > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples >
            0 ||
        native.gameCaptureNativeNv12BltToReadyOver1xFrames > 0 ||
        native.gameCaptureNativeNv12OnFrameBackpressureEnabled != null ||
        native.gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure != null ||
        native.encoderNativeSourceAgeSamples > 0 ||
        native.encoderNativeBufferAgeSamples > 0 ||
        native.encoderNativeSampleLifetimeSamples > 0 ||
        native.encoderNativeAdapterLuid != null ||
        native.encoderMaxQueueDepth > 0 ||
        native.hasWebrtcRawSenderBoundaryDiagnostics ||
        native.webrtcVideoBroadcasterSamples > 0 ||
        framesDroppedBeforeEncodeMax != null ||
        framesDroppedByEncoderMax != null;
  }

  String get senderHandoffDiagnosticsLabel {
    final native = nativeDiagnostics;
    final missing = senderHandoffDiagnosticMissingFields;
    final missingLabel = missing.isEmpty ? 'none' : missing.join(', ');
    return 'on_frame_call='
        '${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)} '
        'native_age='
        '${_milliseconds(native.averageGameCaptureNativeNv12ConversionStartAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)} '
        'adapter=consumer:${native.gameCaptureConsumerAdapterLuid ?? 'unknown'} '
        'source:${native.gameCaptureSourceAdapterLuid ?? 'unknown'} '
        'cross:${native.gameCaptureCrossAdapterSuspected ?? 'unknown'} '
        'queue_wait='
        '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)} '
        'source_submit='
        '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)} '
        'source_latest=observed:${native.gameCaptureSourceLatestObservedFrames} '
        'gaps:${native.gameCaptureSourceLatestFrameGaps} '
        'regressions:${native.gameCaptureSourceLatestFrameRegressions} '
        'qpc:${_milliseconds(native.averageGameCaptureSourceLatestQpcDeltaMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceLatestQpcDeltaMs)} '
        'qpc_over:${native.gameCaptureSourceLatestQpcOver2xFrames}/'
        '${native.gameCaptureSourceLatestQpcOver3xFrames} '
        'observe:'
        '${_milliseconds(native.averageGameCaptureSourceLatestObservationDeltaMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceLatestObservationDeltaMs)} '
        'observe_over:'
        '${native.gameCaptureSourceLatestObservationOver2xFrames}/'
        '${native.gameCaptureSourceLatestObservationOver3xFrames} '
        'event_age:'
        '${_milliseconds(native.averageGameCaptureSourceLatestEventAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceLatestEventAgeMs)} '
        'event_over:${native.gameCaptureSourceLatestEventAgeOver1xFrames}/'
        '${native.gameCaptureSourceLatestEventAgeOver2xFrames}/'
        '${native.gameCaptureSourceLatestEventAgeOver3xFrames} '
        'source_publish_age:'
        '${_milliseconds(native.averageGameCaptureSourcePublishObservationAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureSourcePublishObservationAgeMs)} '
        'publish_over:'
        '${native.gameCaptureSourcePublishObservationAgeOver1xFrames}/'
        '${native.gameCaptureSourcePublishObservationAgeOver2xFrames}/'
        '${native.gameCaptureSourcePublishObservationAgeOver3xFrames} '
        'producer=present:'
        '${_milliseconds(native.averageGameCaptureProducerPresentGapMs)}/'
        '${_milliseconds(native.maxGameCaptureProducerPresentGapMs)} '
        'capture:'
        '${_milliseconds(native.averageGameCaptureProducerCaptureGapMs)}/'
        '${_milliseconds(native.maxGameCaptureProducerCaptureGapMs)} '
        'present_publish:'
        '${_milliseconds(native.averageGameCaptureProducerPresentToPublishMs)}/'
        '${_milliseconds(native.maxGameCaptureProducerPresentToPublishMs)} '
        'copy:${_milliseconds(native.averageGameCaptureProducerCopyMs)}/'
        '${_milliseconds(native.maxGameCaptureProducerCopyMs)} '
        'resolve:${_milliseconds(native.averageGameCaptureProducerResolveMs)}/'
        '${_milliseconds(native.maxGameCaptureProducerResolveMs)} '
        'throttled:${native.gameCaptureProducerThrottledFrames} '
        'admission=deadline:${native.gameCaptureNativeAdmissionDeadlineDueFrames} '
        'late:'
        '${_milliseconds(native.averageGameCaptureNativeAdmissionDeadlineLatenessMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeAdmissionDeadlineLatenessMs)} '
        'over:'
        '${native.gameCaptureNativeAdmissionDeadlineOver1xFrames}/'
        '${native.gameCaptureNativeAdmissionDeadlineOver2xFrames}/'
        '${native.gameCaptureNativeAdmissionDeadlineOver3xFrames} '
        'source:none:${native.gameCaptureNativeAdmissionNoSourceOnDeadlineFrames} '
        'repeated:${native.gameCaptureNativeAdmissionRepeatedOnDeadlineFrames} '
        'submit:${native.gameCaptureNativeAdmissionSubmitOnDeadlineFrames}/'
        '${native.gameCaptureNativeAdmissionSubmitOnEarlySourceFrames} '
        'delivery_depth:${native.gameCaptureDeliveryQueueDepth ?? '?'} '
        'native_ready=policy:${native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown'} '
        'deadline_pending:${native.gameCaptureNativeNv12PendingOnDeadlineFrames}/'
        '${native.gameCaptureNativeNv12NoPendingOnDeadlineFrames} '
        'deadline_ready:${native.gameCaptureNativeNv12ReadyOnDeadlineFrames}/'
        '${native.gameCaptureNativeNv12NoReadyOnDeadlineFrames} '
        'ready_drain:${native.gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'ownership:${native.gameCaptureNativeNv12FrameOwnership ?? 'unknown'} '
        'owned_copy:${native.gameCaptureNativeNv12OwnedCopies} '
        '${_milliseconds(native.averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12OwnedCopyMs)} '
        'gpu_backoff:${native.gameCaptureNativeNv12GpuQueueBackoffEnabled ?? '?'} '
        'threshold:${native.gameCaptureNativeNv12GpuQueueBackoffThresholdFrames ?? '?'}/'
        '${native.gameCaptureNativeNv12GpuQueueBackoffDurationFrames ?? '?'} '
        'trigger:${native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames} '
        'suppress:${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames}/'
        '${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames} '
        'backoff:${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffMs)} '
        'trigger_blt:${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)} '
        'suppress_age:${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)} '
        'blt_cpu_submit:'
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)} '
        'blt_submit_fence:'
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)} '
        'blt_gpu_exec:'
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)} '
        'blt_queue_delay:'
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)} '
        'blt_timestamp_fail/not_ready/disjoint:'
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures}/'
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady}/'
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint} '
        'fence:${native.gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'signaled:${native.gameCaptureNativeNv12FenceSignaledFrames} '
        'not_ready:${native.gameCaptureNativeNv12NotReadyPolls} '
        'ready_dropped:${native.gameCaptureNativeNv12ReadyDroppedFrames} '
        'observed=immediate:'
        '${native.gameCaptureNativeNv12ReadyObservedImmediateFrames} '
        'post:'
        '${native.gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames} '
        'event:${native.gameCaptureNativeNv12ReadyObservedFenceEventFrames} '
        'source:${native.gameCaptureNativeNv12ReadyObservedSourceEventFrames} '
        'idle:${native.gameCaptureNativeNv12ReadyObservedLoopIdleFrames} '
        'duplicate:'
        '${native.gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames} '
        'pre:${native.gameCaptureNativeNv12ReadyObservedPreSubmitFrames} '
        'write:${native.gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames} '
        'other:${native.gameCaptureNativeNv12ReadyObservedWaitOtherFrames} '
        'unknown:${native.gameCaptureNativeNv12ReadyObservedUnknownFrames} '
        'blt_to_ready_over='
        '${native.gameCaptureNativeNv12BltToReadyOver1xFrames}/'
        '${native.gameCaptureNativeNv12BltToReadyOver2xFrames}/'
        '${native.gameCaptureNativeNv12BltToReadyOver3xFrames} '
        'failures:${native.gameCaptureNativeNv12Failures} '
        'onframe_backpressure=enabled:'
        '${native.gameCaptureNativeNv12OnFrameBackpressureEnabled ?? '?'} '
        'threshold:'
        '${native.gameCaptureNativeNv12OnFrameBackpressureThresholdMs ?? '?'} '
        'frames:${native.gameCaptureNativeNv12OnFrameBackpressureFrames} '
        'streak:${native.gameCaptureNativeNv12OnFrameBackpressureStreak}/'
        '${native.gameCaptureNativeNv12OnFrameBackpressureFrameLimit ?? '?'} '
        'max:'
        '${_milliseconds(native.gameCaptureNativeNv12OnFrameBackpressureMaxMs)} '
        'suspended:'
        '${native.gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure ?? '?'} '
        'cpu_i420:${native.encoderCpuI420InputFrames} '
        'mf=total:${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)} '
        'rate_control:${native.encoderRateControlMode ?? 'unknown'} '
        'target_bitrate:${native.encoderTargetBitrateBps ?? '?'} '
        'source:${native.encoderNativeSourceMode ?? 'unknown'}/'
        '${native.encoderNativeSourceFormat ?? '?'} '
        'source_age:${_milliseconds(native.averageEncoderNativeSourceAgeMs)}/'
        '${_milliseconds(native.maxEncoderNativeSourceAgeMs)} '
        'buffer_age:${_milliseconds(native.averageEncoderNativeBufferAgeMs)}/'
        '${_milliseconds(native.maxEncoderNativeBufferAgeMs)} '
        'sample_lifetime:${_milliseconds(native.averageEncoderNativeSampleLifetimeMs)}/'
        '${_milliseconds(native.maxEncoderNativeSampleLifetimeMs)} '
        'adapter:${native.encoderNativeAdapterLuid ?? 'unknown'} '
        'fence_wait:${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
        '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)} '
        'process_input:${_milliseconds(native.averageEncoderProcessInputMs)}/'
        '${_milliseconds(native.maxEncoderProcessInputMs)} '
        'process_output:${_milliseconds(native.averageEncoderProcessOutputMs)}/'
        '${_milliseconds(native.maxEncoderProcessOutputMs)} '
        'encoded_callback:${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)} '
        'callback_wait:${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)} '
        'callback_enqueue:${_milliseconds(native.averageEncoderEncodedCallbackEnqueueMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackEnqueueMs)} '
        'callback_async:${native.encoderEncodedCallbackAsyncFrames} '
        'callback_queue_max:${native.encoderMaxEncodedCallbackQueueDepth} '
        'callback_drops_max:${native.encoderMaxEncodedCallbackDrops} '
        'callback_outputs_max:${native.encoderMaxEncodedCallbackOutputs} '
        'queue_max:${native.encoderMaxQueueDepth} '
        'retained_max:${native.encoderMaxRetainedSamples} '
        'encoded_outputs_max:${native.encoderMaxEncodedOutputs} '
        'webrtc_raw_sender:${native.webrtcRawSenderBoundaryLabel} '
        'sender_drops=before_encode:${framesDroppedBeforeEncodeMax ?? '?'} '
        'by_encoder:${framesDroppedByEncoderMax ?? '?'} '
        'frames=${framesCapturedMax ?? '?'}/${framesEncodedMax ?? '?'}/'
        '${framesSentMax ?? '?'} '
        'missing=[$missingLabel]';
  }

  Map<String, Object?> get senderHandoffDiagnosticsJson {
    final native = nativeDiagnostics;
    return {
      'available': hasSenderHandoffDiagnostics,
      'missingFields': senderHandoffDiagnosticMissingFields,
      'liveOnFrame': {
        'averageMs': native.averageGameCaptureDeliveryOnFrameCallMs,
        'maxMs': native.maxGameCaptureDeliveryOnFrameCallMs,
        'samples': native.gameCaptureDeliveryOnFrameCallSamples,
      },
      'nativeFrameAgeAtConversionStart': {
        'averageMs': native.averageGameCaptureNativeNv12ConversionStartAgeMs,
        'maxMs': native.maxGameCaptureNativeNv12ConversionStartAgeMs,
        'samples': native.gameCaptureNativeNv12ConversionStartAgeSamples,
      },
      'deliveryQueueWait': {
        'averageMs': native.averageGameCaptureDeliveryQueueWaitMs,
        'maxMs': native.maxGameCaptureDeliveryQueueWaitMs,
        'samples': native.gameCaptureDeliveryQueueWaitSamples,
        'queueDepth': native.gameCaptureDeliveryQueueDepth,
      },
      'sourceToSubmit': {
        'averageMs': native.averageGameCaptureSourceToSubmitMs,
        'maxMs': native.maxGameCaptureSourceToSubmitMs,
        'samples': native.gameCaptureSourceToSubmitSamples,
      },
      'sourceLatest': {
        'observedFrames': native.gameCaptureSourceLatestObservedFrames,
        'frameGaps': native.gameCaptureSourceLatestFrameGaps,
        'frameRegressions': native.gameCaptureSourceLatestFrameRegressions,
        'qpcDelta': {
          'averageMs': native.averageGameCaptureSourceLatestQpcDeltaMs,
          'maxMs': native.maxGameCaptureSourceLatestQpcDeltaMs,
          'samples': native.gameCaptureSourceLatestQpcSamples,
          'regressions': native.gameCaptureSourceLatestQpcRegressions,
          'over2xFrames': native.gameCaptureSourceLatestQpcOver2xFrames,
          'over3xFrames': native.gameCaptureSourceLatestQpcOver3xFrames,
          'underHalfFrames': native.gameCaptureSourceLatestQpcUnderHalfFrames,
        },
        'observationDelta': {
          'averageMs': native.averageGameCaptureSourceLatestObservationDeltaMs,
          'maxMs': native.maxGameCaptureSourceLatestObservationDeltaMs,
          'samples': native.gameCaptureSourceLatestObservationSamples,
          'over2xFrames': native.gameCaptureSourceLatestObservationOver2xFrames,
          'over3xFrames': native.gameCaptureSourceLatestObservationOver3xFrames,
        },
        'eventAge': {
          'averageMs': native.averageGameCaptureSourceLatestEventAgeMs,
          'maxMs': native.maxGameCaptureSourceLatestEventAgeMs,
          'samples': native.gameCaptureSourceLatestEventAgeSamples,
          'over1xFrames': native.gameCaptureSourceLatestEventAgeOver1xFrames,
          'over2xFrames': native.gameCaptureSourceLatestEventAgeOver2xFrames,
          'over3xFrames': native.gameCaptureSourceLatestEventAgeOver3xFrames,
        },
        'publishObservationAge': {
          'averageMs': native.averageGameCaptureSourcePublishObservationAgeMs,
          'maxMs': native.maxGameCaptureSourcePublishObservationAgeMs,
          'samples': native.gameCaptureSourcePublishObservationAgeSamples,
          'over1xFrames':
              native.gameCaptureSourcePublishObservationAgeOver1xFrames,
          'over2xFrames':
              native.gameCaptureSourcePublishObservationAgeOver2xFrames,
          'over3xFrames':
              native.gameCaptureSourcePublishObservationAgeOver3xFrames,
        },
      },
      'sourceProducer': {
        'presentGap': {
          'averageMs': native.averageGameCaptureProducerPresentGapMs,
          'maxMs': native.maxGameCaptureProducerPresentGapMs,
          'samples': native.gameCaptureProducerPresentGapSamples,
        },
        'captureGap': {
          'averageMs': native.averageGameCaptureProducerCaptureGapMs,
          'maxMs': native.maxGameCaptureProducerCaptureGapMs,
          'samples': native.gameCaptureProducerCaptureGapSamples,
        },
        'presentToPublish': {
          'averageMs': native.averageGameCaptureProducerPresentToPublishMs,
          'maxMs': native.maxGameCaptureProducerPresentToPublishMs,
          'samples': native.gameCaptureProducerPresentToPublishSamples,
        },
        'copy': {
          'averageMs': native.averageGameCaptureProducerCopyMs,
          'maxMs': native.maxGameCaptureProducerCopyMs,
          'samples': native.gameCaptureProducerCopySamples,
        },
        'resolve': {
          'averageMs': native.averageGameCaptureProducerResolveMs,
          'maxMs': native.maxGameCaptureProducerResolveMs,
          'samples': native.gameCaptureProducerResolveSamples,
        },
        'throttledFrames': native.gameCaptureProducerThrottledFrames,
      },
      'nativeAdmission': {
        'strictDeadlineEnabled':
            native.gameCaptureNativeAdmissionStrictDeadlineEnabled,
        'sourceDrivenFreshDue':
            native.gameCaptureNativeAdmissionSourceDrivenFreshDueFrames,
        'sourceQpcDue': native.gameCaptureNativeAdmissionSourceQpcDueFrames,
        'earlySourceDueSuppressed':
            native.gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames,
        'deadlineDue': native.gameCaptureNativeAdmissionDeadlineDueFrames,
        'averageDeadlineLatenessMs':
            native.averageGameCaptureNativeAdmissionDeadlineLatenessMs,
        'maxDeadlineLatenessMs':
            native.maxGameCaptureNativeAdmissionDeadlineLatenessMs,
        'deadlineLatenessSamples':
            native.gameCaptureNativeAdmissionDeadlineLatenessSamples,
        'deadlineOver1x': native.gameCaptureNativeAdmissionDeadlineOver1xFrames,
        'deadlineOver2x': native.gameCaptureNativeAdmissionDeadlineOver2xFrames,
        'deadlineOver3x': native.gameCaptureNativeAdmissionDeadlineOver3xFrames,
        'noSourceOnDeadline':
            native.gameCaptureNativeAdmissionNoSourceOnDeadlineFrames,
        'repeatedOnDeadline':
            native.gameCaptureNativeAdmissionRepeatedOnDeadlineFrames,
        'submitOnDeadline':
            native.gameCaptureNativeAdmissionSubmitOnDeadlineFrames,
        'submitOnEarlySource':
            native.gameCaptureNativeAdmissionSubmitOnEarlySourceFrames,
        'nativeNv12PendingOnDeadline':
            native.gameCaptureNativeNv12PendingOnDeadlineFrames,
        'nativeNv12NoPendingOnDeadline':
            native.gameCaptureNativeNv12NoPendingOnDeadlineFrames,
        'nativeNv12ReadyOnDeadline':
            native.gameCaptureNativeNv12ReadyOnDeadlineFrames,
        'nativeNv12NoReadyOnDeadline':
            native.gameCaptureNativeNv12NoReadyOnDeadlineFrames,
        'sourceQpcOver2x': native.gameCaptureSourceQpcOver2xFrames,
        'sourceQpcOver3x': native.gameCaptureSourceQpcOver3xFrames,
        'sourceQpcUnderHalf': native.gameCaptureSourceQpcUnderHalfFrames,
      },
      'adapter': {
        'consumerLuid': native.gameCaptureConsumerAdapterLuid,
        'consumerVendorId': native.gameCaptureConsumerAdapterVendorId,
        'consumerDeviceId': native.gameCaptureConsumerAdapterDeviceId,
        'sourceLuid': native.gameCaptureSourceAdapterLuid,
        'crossAdapterSuspected': native.gameCaptureCrossAdapterSuspected,
      },
      'nativeNv12Ready': {
        'policy': native.gameCaptureNativeNv12ReadyPolicy,
        'fenceAvailable': native.gameCaptureNativeNv12FenceAvailable,
        'fenceSignaled': native.gameCaptureNativeNv12FenceSignaledFrames,
        'fenceReady': native.gameCaptureNativeNv12FenceReadyFrames,
        'fenceSignalFailures': native.gameCaptureNativeNv12FenceSignalFailures,
        'notReadyPolls': native.gameCaptureNativeNv12NotReadyPolls,
        'readyDrainDepth': native.gameCaptureNativeNv12ReadyDrainDepth,
        'frameOwnership': native.gameCaptureNativeNv12FrameOwnership,
        'ownedCopies': native.gameCaptureNativeNv12OwnedCopies,
        'averageOwnedCopyMs': native.averageGameCaptureNativeNv12OwnedCopyMs,
        'maxOwnedCopyMs': native.maxGameCaptureNativeNv12OwnedCopyMs,
        'ownedCopySamples': native.gameCaptureNativeNv12OwnedCopySamples,
        'readyDropped': native.gameCaptureNativeNv12ReadyDroppedFrames,
        'readyDroppedFresh':
            native.gameCaptureNativeNv12ReadyDroppedFreshFrames,
        'submitted': native.gameCaptureNativeNv12SubmittedFrames,
        'failures': native.gameCaptureNativeNv12Failures,
        'readyObserved': {
          'immediateAfterBlt':
              native.gameCaptureNativeNv12ReadyObservedImmediateFrames,
          'postFenceRegistration': native
              .gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames,
          'fenceEvent':
              native.gameCaptureNativeNv12ReadyObservedFenceEventFrames,
          'sourceEvent':
              native.gameCaptureNativeNv12ReadyObservedSourceEventFrames,
          'waitOther': native.gameCaptureNativeNv12ReadyObservedWaitOtherFrames,
          'loopIdle': native.gameCaptureNativeNv12ReadyObservedLoopIdleFrames,
          'duplicateSkip':
              native.gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames,
          'preSubmit': native.gameCaptureNativeNv12ReadyObservedPreSubmitFrames,
          'writeSlotScan':
              native.gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames,
          'unknown': native.gameCaptureNativeNv12ReadyObservedUnknownFrames,
        },
        'bltToReadyOverBudget': {
          'over1xFrames': native.gameCaptureNativeNv12BltToReadyOver1xFrames,
          'over2xFrames': native.gameCaptureNativeNv12BltToReadyOver2xFrames,
          'over3xFrames': native.gameCaptureNativeNv12BltToReadyOver3xFrames,
        },
        'videoProcessorBlt': {
          'averageCpuSubmitMs':
              native.averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
          'maxCpuSubmitMs':
              native.maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
          'cpuSubmitSamples':
              native.gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples,
          'averageSubmitToFenceMs': native
              .averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
          'maxSubmitToFenceMs':
              native.maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
          'submitToFenceSamples':
              native.gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples,
          'averageGpuExecutionMs': native
              .averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
          'maxGpuExecutionMs':
              native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
          'gpuExecutionSamples':
              native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples,
          'averageEstimatedGpuQueueDelayMs': native
              .averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
          'maxEstimatedGpuQueueDelayMs': native
              .maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
          'estimatedGpuQueueDelaySamples': native
              .gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples,
          'gpuTimestampFailures':
              native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures,
          'gpuTimestampNotReady':
              native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady,
          'gpuTimestampDisjoint':
              native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint,
        },
        'cpuFallbackFrames': native.gameCaptureCpuFallbackFrames,
        'staleBeforeQueue': native.gameCaptureNativeNv12StaleBeforeQueueFrames,
        'gpuQueueBackoff': {
          'enabled': native.gameCaptureNativeNv12GpuQueueBackoffEnabled,
          'thresholdFrames':
              native.gameCaptureNativeNv12GpuQueueBackoffThresholdFrames,
          'durationFrames':
              native.gameCaptureNativeNv12GpuQueueBackoffDurationFrames,
          'triggered':
              native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames,
          'suppressed':
              native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames,
          'suppressedFresh':
              native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames,
          'averageMs': native.averageGameCaptureNativeNv12GpuQueueBackoffMs,
          'maxMs': native.maxGameCaptureNativeNv12GpuQueueBackoffMs,
          'samples': native.gameCaptureNativeNv12GpuQueueBackoffSamples,
          'averageTriggerBltToReadyMs': native
              .averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
          'maxTriggerBltToReadyMs':
              native.maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
          'triggerBltToReadySamples': native
              .gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples,
          'averageSuppressedSourceAgeMs': native
              .averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
          'maxSuppressedSourceAgeMs': native
              .maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
          'suppressedSourceAgeSamples': native
              .gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples,
        },
        'onFrameBackpressure': {
          'enabled': native.gameCaptureNativeNv12OnFrameBackpressureEnabled,
          'thresholdMs':
              native.gameCaptureNativeNv12OnFrameBackpressureThresholdMs,
          'frameLimit':
              native.gameCaptureNativeNv12OnFrameBackpressureFrameLimit,
          'frames': native.gameCaptureNativeNv12OnFrameBackpressureFrames,
          'streak': native.gameCaptureNativeNv12OnFrameBackpressureStreak,
          'maxMs': native.gameCaptureNativeNv12OnFrameBackpressureMaxMs,
          'suspended':
              native.gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure,
        },
      },
      'mediaFoundation': {
        'averageTotalMs': native.averageEncoderTotalMs,
        'maxTotalMs': native.maxEncoderTotalMs,
        'slowSamples': native.encoderSlowFrameCount,
        'samples': native.encoderSampleCount,
        'rateControlMode': native.encoderRateControlMode,
        'targetBitrateBps': native.encoderTargetBitrateBps,
        'inputPath': native.encoderInputPathLabel,
        'nativeInputFrames': native.encoderNativeInputFrames,
        'cpuI420InputFrames': native.encoderCpuI420InputFrames,
        'nativeSampleFailures': native.encoderNativeSampleFailures,
        'nativeReadyFenceFrames': native.encoderNativeReadyFenceFrames,
        'nativeReadyFenceTimeoutFrames':
            native.encoderNativeReadyFenceTimeoutFrames,
        'averageNativeReadyFenceWaitMs':
            native.averageEncoderNativeReadyFenceWaitMs,
        'maxNativeReadyFenceWaitMs': native.maxEncoderNativeReadyFenceWaitMs,
        'nativeReadyFenceWaitSamples':
            native.encoderNativeReadyFenceWaitSamples,
        'nativeSourceMode': native.encoderNativeSourceMode,
        'nativeSourceFormat': native.encoderNativeSourceFormat,
        'nativeSourceFrameIndex': native.encoderNativeSourceFrameIndex,
        'averageNativeSourceAgeMs': native.averageEncoderNativeSourceAgeMs,
        'maxNativeSourceAgeMs': native.maxEncoderNativeSourceAgeMs,
        'nativeSourceAgeSamples': native.encoderNativeSourceAgeSamples,
        'averageNativeSourceAgeAtCreateMs':
            native.averageEncoderNativeSourceAgeAtCreateMs,
        'maxNativeSourceAgeAtCreateMs':
            native.maxEncoderNativeSourceAgeAtCreateMs,
        'averageNativeBufferAgeMs': native.averageEncoderNativeBufferAgeMs,
        'maxNativeBufferAgeMs': native.maxEncoderNativeBufferAgeMs,
        'nativeBufferAgeSamples': native.encoderNativeBufferAgeSamples,
        'averageNativeSampleLifetimeMs':
            native.averageEncoderNativeSampleLifetimeMs,
        'maxNativeSampleLifetimeMs': native.maxEncoderNativeSampleLifetimeMs,
        'nativeSampleLifetimeSamples':
            native.encoderNativeSampleLifetimeSamples,
        'nativeAdapterLuid': native.encoderNativeAdapterLuid,
        'nativeAdapterVendorId': native.encoderNativeAdapterVendorId,
        'nativeAdapterDeviceId': native.encoderNativeAdapterDeviceId,
        'averageProcessInputMs': native.averageEncoderProcessInputMs,
        'maxProcessInputMs': native.maxEncoderProcessInputMs,
        'processInputSamples': native.encoderProcessInputSamples,
        'averageProcessOutputMs': native.averageEncoderProcessOutputMs,
        'maxProcessOutputMs': native.maxEncoderProcessOutputMs,
        'processOutputSamples': native.encoderProcessOutputSamples,
        'averageEncodedCallbackMs': native.averageEncoderEncodedCallbackMs,
        'maxEncodedCallbackMs': native.maxEncoderEncodedCallbackMs,
        'encodedCallbackSamples': native.encoderEncodedCallbackSamples,
        'averageEncodedCallbackQueueWaitMs':
            native.averageEncoderEncodedCallbackQueueWaitMs,
        'maxEncodedCallbackQueueWaitMs':
            native.maxEncoderEncodedCallbackQueueWaitMs,
        'encodedCallbackQueueWaitSamples':
            native.encoderEncodedCallbackQueueWaitSamples,
        'averageEncodedCallbackEnqueueMs':
            native.averageEncoderEncodedCallbackEnqueueMs,
        'maxEncodedCallbackEnqueueMs':
            native.maxEncoderEncodedCallbackEnqueueMs,
        'encodedCallbackEnqueueSamples':
            native.encoderEncodedCallbackEnqueueSamples,
        'encodedCallbackAsyncFrames': native.encoderEncodedCallbackAsyncFrames,
        'encodedCallbackQueueMax': native.encoderMaxEncodedCallbackQueueDepth,
        'encodedCallbackDropsMax': native.encoderMaxEncodedCallbackDrops,
        'encodedCallbackOutputsMax': native.encoderMaxEncodedCallbackOutputs,
        'queueMax': native.encoderMaxQueueDepth,
        'retainedSamplesMax': native.encoderMaxRetainedSamples,
        'encodedOutputsMax': native.encoderMaxEncodedOutputs,
        'outputFrames': native.encoderOutputFrames,
        'outputBytes': native.encoderOutputBytes,
        'stage': native.encoderStageLabel,
      },
      'webrtcRawSenderBoundary': {
        'available': native.hasWebrtcRawSenderBoundaryDiagnostics,
        'sourceOnFrame': {
          'averageMs': native.averageWebrtcSourceOnFrameMs,
          'maxMs': native.maxWebrtcSourceOnFrameMs,
          'samples': native.webrtcSourceOnFrameSamples,
          'averageBroadcastMs': native.averageWebrtcSourceBroadcastMs,
          'maxBroadcastMs': native.maxWebrtcSourceBroadcastMs,
          'adapterDrops': native.webrtcSourceAdapterDrops,
          'scaledFrames': native.webrtcSourceScaledFrames,
        },
        'videoBroadcaster': {
          'averageMs': native.averageWebrtcVideoBroadcasterMs,
          'maxMs': native.maxWebrtcVideoBroadcasterMs,
          'samples': native.webrtcVideoBroadcasterSamples,
          'averageLockWaitMs': native.averageWebrtcVideoBroadcasterLockWaitMs,
          'maxLockWaitMs': native.maxWebrtcVideoBroadcasterLockWaitMs,
          'averageSinkDispatchMs':
              native.averageWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSinkDispatchMs': native.maxWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSingleSinkMs': native.maxWebrtcVideoBroadcasterSingleSinkMs,
          'slowSinkId': native.webrtcVideoBroadcasterSlowSinkId,
          'slowSinkMs': native.webrtcVideoBroadcasterSlowSinkMs,
          'slowSinkLabel': native.webrtcVideoBroadcasterSlowSinkLabel,
          'slowestSinkId': native.webrtcVideoBroadcasterSlowestSinkId,
          'slowestSinkMs': native.webrtcVideoBroadcasterSlowestSinkMs,
          'slowestSinkAverageMs':
              native.webrtcVideoBroadcasterSlowestSinkAverageMs,
          'slowestSinkFrames': native.webrtcVideoBroadcasterSlowestSinkFrames,
          'slowestSinkLabel': native.webrtcVideoBroadcasterSlowestSinkLabel,
          'sinkCount': native.webrtcVideoBroadcasterSinkCount,
          'maxSinkCount': native.webrtcVideoBroadcasterMaxSinkCount,
          'activeSinks': native.webrtcVideoBroadcasterActiveSinks,
          'inactiveSinks': native.webrtcVideoBroadcasterInactiveSinks,
          'requestedSinks': native.webrtcVideoBroadcasterRequestedSinks,
          'blackFrameSinks': native.webrtcVideoBroadcasterBlackFrameSinks,
          'rotationAppliedSinks':
              native.webrtcVideoBroadcasterRotationAppliedSinks,
          'inactiveNativeSinkBypassReported':
              native.webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
          'inactiveNativeSinksBypassed':
              native.webrtcVideoBroadcasterInactiveNativeSinksBypassed,
          'inactiveNativeSinksBypassedLast':
              native.webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
          'inactiveNativeSinksRefreshed':
              native.webrtcVideoBroadcasterInactiveNativeSinksRefreshed,
          'inactiveNativeSinksRefreshedLast':
              native.webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast,
          'sinkRoster': native.webrtcVideoBroadcasterSinkRoster,
          'blackSinks': native.webrtcVideoBroadcasterBlackSinks,
          'rotationDiscards': native.webrtcVideoBroadcasterRotationDiscards,
          'updateRectCleared': native.webrtcVideoBroadcasterUpdateRectCleared,
          'discardedFrames': native.webrtcVideoBroadcasterDiscardedFrames,
        },
        'videoStreamEncoder': {
          'averagePostToOnFrameMs': native.averageWebrtcVsePostToOnFrameMs,
          'maxPostToOnFrameMs': native.maxWebrtcVsePostToOnFrameMs,
          'averageOnFrameMs': native.averageWebrtcVseOnFrameMs,
          'maxOnFrameMs': native.maxWebrtcVseOnFrameMs,
          'onFrameSamples': native.webrtcVseOnFrameSamples,
          'queueOverloadDrops': native.webrtcVseQueueOverloadDrops,
          'encoderQueueDrops': native.webrtcVseEncoderQueueDrops,
          'cwndDrops': native.webrtcVseCwndDrops,
          'badTimestampDrops': native.webrtcVseBadTimestampDrops,
          'averageMaybeEncodeMs': native.averageWebrtcVseMaybeEncodeMs,
          'maxMaybeEncodeMs': native.maxWebrtcVseMaybeEncodeMs,
          'maybeEncodeSamples': native.webrtcVseMaybeEncodeSamples,
          'averageEncodeFrameMs': native.averageWebrtcVseEncodeFrameMs,
          'maxEncodeFrameMs': native.maxWebrtcVseEncodeFrameMs,
          'encodeFrameSamples': native.webrtcVseEncodeFrameSamples,
          'averageVideoEncoderEncodeMs':
              native.averageWebrtcVideoEncoderEncodeMs,
          'maxVideoEncoderEncodeMs': native.maxWebrtcVideoEncoderEncodeMs,
          'videoEncoderEncodeSamples': native.webrtcVideoEncoderEncodeSamples,
          'encodeFailures': native.webrtcVseEncodeFailures,
          'encodeSkippedBeforeEncoder':
              native.webrtcVseEncodeSkippedBeforeEncoder,
        },
        'label': native.webrtcRawSenderBoundaryLabel,
      },
      'senderCounters': {
        'framesCapturedMax': framesCapturedMax,
        'framesEncodedMax': framesEncodedMax,
        'framesSentMax': framesSentMax,
        'framesDroppedBeforeEncodeMax': framesDroppedBeforeEncodeMax,
        'framesDroppedByEncoderMax': framesDroppedByEncoderMax,
      },
      'label': senderHandoffDiagnosticsLabel,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'senderSampleCount': senderSampleCount,
      'preEncodeSampleCount': preEncodeSampleCount,
      'screenShareProfileDetails': screenShareProfileDetails.toList()..sort(),
      'senderCodecs': senderCodecs.toList()..sort(),
      'encoderImplementations': encoderImplementations.toList()..sort(),
      'hardwareEncodeStates': _sortedBoolList(hardwareEncodeStates),
      'averageFps': averageFps,
      'minimumFps': minimumFps,
      'averageCaptureFps': averageCaptureFps,
      'minimumCaptureFps': minimumCaptureFps,
      'averageEncodeFps': averageEncodeFps,
      'minimumEncodeFps': minimumEncodeFps,
      'averageSendFps': averageSendFps,
      'minimumSendFps': minimumSendFps,
      'averageBitrateBps': averageBitrateBps,
      'averageAvailableOutgoingBitrateBps': averageAvailableOutgoingBitrateBps,
      'minimumAvailableOutgoingBitrateBps': minimumAvailableOutgoingBitrateBps,
      'maximumAvailableOutgoingBitrateBps': maximumAvailableOutgoingBitrateBps,
      'requestedWidth': requestedWidth,
      'requestedHeight': requestedHeight,
      'requestedFps': requestedFps,
      'requestedBitrateBps': requestedBitrateBps,
      'preEncodeWidth': preEncodeWidth,
      'preEncodeHeight': preEncodeHeight,
      'encodedWidth': encodedWidth,
      'encodedHeight': encodedHeight,
      'averageEncodeTimeMs': averageEncodeTimeMs,
      'maxEncodeTimeMs': maxEncodeTimeMs,
      'averagePacketSendDelayMs': averagePacketSendDelayMs,
      'maxPacketSendDelayMs': maxPacketSendDelayMs,
      'maxPacketLossPercent': maxPacketLossPercent,
      'maxRoundTripTimeMs': maxRoundTripTimeMs,
      'maxNackCount': maxNackCount,
      'framesCapturedMax': framesCapturedMax,
      'framesEncodedMax': framesEncodedMax,
      'framesSentMax': framesSentMax,
      'framesDroppedBeforeEncodeMax': framesDroppedBeforeEncodeMax,
      'framesDroppedByEncoderMax': framesDroppedByEncoderMax,
      'capturePipeline': capturePipelineLabel,
      'framePacing': framePacing.toJson(),
      'visualFreshnessDiagnostics':
          nativeDiagnostics.gameCaptureVisualFreshnessJson,
      'senderHandoffDiagnostics': senderHandoffDiagnosticsJson,
      'nativeDiagnostics': nativeDiagnostics.toJson(),
      'diagnosticCoverage':
          StreamDiagnosticCoverageMatrix.forSummary(this).toJson(),
      'qualityLimitationReasons': qualityLimitationReasons.toList()..sort(),
      'activeLayers': activeLayers.toList()..sort(),
    };
  }
}

VoipTrackDiagnostics? _bestSenderTrack(VoipCallDiagnosticsSnapshot snapshot) {
  final candidates = snapshot.tracks.where(
    (track) =>
        track.type == VoipStreamType.screenshare &&
        track.direction == VoipDiagnosticsTrackDirection.sender,
  );
  VoipTrackDiagnostics? best;
  var bestPixels = -1;
  for (final track in candidates) {
    final pixels = (track.width ?? 0) * (track.height ?? 0);
    if (pixels > bestPixels) {
      best = track;
      bestPixels = pixels;
    }
  }
  return best;
}

VoipTrackDiagnostics? _bestReceiverTrack(VoipCallDiagnosticsSnapshot snapshot) {
  final candidates = snapshot.tracks.where(
    (track) =>
        track.type == VoipStreamType.screenshare &&
        track.direction == VoipDiagnosticsTrackDirection.receiver,
  );
  VoipTrackDiagnostics? best;
  var bestPixels = -1;
  for (final track in candidates) {
    final pixels = (track.width ?? 0) * (track.height ?? 0);
    if (pixels > bestPixels) {
      best = track;
      bestPixels = pixels;
    }
  }
  return best;
}

List<_FrameCounterSample> _counterSamples(
  List<StreamTestSample> samples,
  VoipTrackDiagnostics? Function(VoipCallDiagnosticsSnapshot snapshot)
      trackSelector,
  int? Function(VoipTrackDiagnostics track) counterSelector, {
  bool Function(VoipTrackDiagnostics track)? include,
}) {
  final counterSamples = <_FrameCounterSample>[];
  for (final sample in samples) {
    final track = trackSelector(sample.snapshot);
    if (track == null || !(include?.call(track) ?? true)) {
      continue;
    }
    counterSamples.add(
      _FrameCounterSample(
        collectedAt: sample.snapshot.collectedAt,
        frameCount: counterSelector(track),
      ),
    );
  }
  return counterSamples;
}

Duration _measurementDuration({
  required List<StreamTestSample> samples,
  DateTime? measurementStartedAt,
  DateTime? measurementEndedAt,
}) {
  var durationMs = 0;
  if (measurementStartedAt != null && measurementEndedAt != null) {
    durationMs = max(
      durationMs,
      measurementEndedAt.difference(measurementStartedAt).inMilliseconds,
    );
  }
  for (final sample in samples) {
    durationMs = max(durationMs, sample.elapsed.inMilliseconds);
  }
  return Duration(milliseconds: max(0, durationMs));
}

List<_StreamTestWindowSpec> _temporalWindowSpecs(Duration totalDuration) {
  final totalMs = max(1, totalDuration.inMilliseconds);
  Duration ms(int value) =>
      Duration(milliseconds: value.clamp(0, totalMs).toInt());
  if (totalMs < 12000) {
    final midpoint = (totalMs / 2).round();
    return [
      _StreamTestWindowSpec(
        label: 'early',
        start: Duration.zero,
        end: ms(midpoint),
      ),
      _StreamTestWindowSpec(
        label: 'late',
        start: ms(midpoint),
        end: ms(totalMs),
      ),
    ];
  }
  final firstCut = (totalMs / 3).round();
  final secondCut = (totalMs * 2 / 3).round();
  final tailStart = max(0, totalMs - 10000);
  return [
    _StreamTestWindowSpec(
      label: 'early',
      start: Duration.zero,
      end: ms(firstCut),
    ),
    _StreamTestWindowSpec(
      label: 'middle',
      start: ms(firstCut),
      end: ms(secondCut),
    ),
    _StreamTestWindowSpec(
      label: 'late',
      start: ms(secondCut),
      end: ms(totalMs),
    ),
    _StreamTestWindowSpec(
      label: 'tail_10s',
      start: ms(tailStart),
      end: ms(totalMs),
    ),
  ];
}

List<String> _lateDegradationSignals({
  required List<StreamTestTimeWindowSummary> windows,
  required double targetFps,
}) {
  final early = _temporalWindowByLabel(windows, 'early');
  final late = _temporalWindowByLabel(windows, 'late');
  final tail = _temporalWindowByLabel(windows, 'tail_10s') ?? late;
  if (early == null || tail == null) {
    return const [];
  }
  final signals = <String>[];
  final frameBudgetMs = targetFps > 0 ? 1000 / targetFps : null;
  final earlySentFps = early.summary.averageSendFps;
  final tailSentFps = tail.summary.averageSendFps;
  if (targetFps > 0 &&
      earlySentFps != null &&
      tailSentFps != null &&
      earlySentFps >= targetFps * 0.80 &&
      tailSentFps < earlySentFps * 0.85) {
    signals.add(
      'send FPS fell from ${earlySentFps.toStringAsFixed(1)} in the early window to ${tailSentFps.toStringAsFixed(1)} in ${tail.label}',
    );
  }

  final earlySentP95 = early.framePacing.sent.p95IntervalMs;
  final tailSentP95 = tail.framePacing.sent.p95IntervalMs;
  if (earlySentP95 != null && tailSentP95 != null && frameBudgetMs != null) {
    final gapThreshold = max(frameBudgetMs * 1.25, earlySentP95 * 1.25);
    if (tailSentP95 > gapThreshold) {
      signals.add(
        'sent p95 gap grew from ${earlySentP95.toStringAsFixed(0)}ms early to ${tailSentP95.toStringAsFixed(0)}ms in ${tail.label}',
      );
    }
  }

  final earlySentMax = early.framePacing.sent.maxIntervalMs;
  final tailSentMax = tail.framePacing.sent.maxIntervalMs;
  if (earlySentMax != null && tailSentMax != null && frameBudgetMs != null) {
    final maxGapThreshold = max(frameBudgetMs * 2.0, earlySentMax * 1.5);
    if (tailSentMax > maxGapThreshold) {
      signals.add(
        'sent max gap grew from ${earlySentMax.toStringAsFixed(0)}ms early to ${tailSentMax.toStringAsFixed(0)}ms in ${tail.label}',
      );
    }
  }

  final gameCapture = tail.gameCapture;
  if (gameCapture != null && gameCapture.hasEvidence) {
    final earlyGameCapture = early.gameCapture;
    final tailDeliveryWallMax = gameCapture.maxDeliveryWallDeltaMs;
    final earlyDeliveryWallMax = earlyGameCapture?.maxDeliveryWallDeltaMs;
    if (tailDeliveryWallMax != null && frameBudgetMs != null) {
      final deliveryWallThreshold = max(
        frameBudgetMs * 1.75,
        (earlyDeliveryWallMax ?? frameBudgetMs) * 1.25,
      );
      if (tailDeliveryWallMax > deliveryWallThreshold) {
        signals.add(
          '${tail.label} D3D11 delivery wall gap reached '
          '${tailDeliveryWallMax.toStringAsFixed(0)}ms '
          'after early max '
          '${(earlyDeliveryWallMax ?? 0).toStringAsFixed(0)}ms',
        );
      }
    }
    final readbackDropPressure = gameCapture.readbackLatencyDroppedDelta > 0 &&
        gameCapture.maxReadbackLatencyFrames >= 3;
    final staleDropPressure = gameCapture.readbackStaleDroppedDelta >= 20 &&
        gameCapture.maxReadbackLatencyFrames >= 3;
    if (readbackDropPressure || staleDropPressure) {
      signals.add(
        '${tail.label} D3D11 readback pressure: latency-drop +${gameCapture.readbackLatencyDroppedDelta}, stale +${gameCapture.readbackStaleDroppedDelta}, not-ready +${gameCapture.readbackNotReadyDelta}, max latency ${gameCapture.maxReadbackLatencyFrames} frames',
      );
    }
  }
  return signals;
}

StreamTestTimeWindowSummary? _temporalWindowByLabel(
  List<StreamTestTimeWindowSummary> windows,
  String label,
) {
  for (final window in windows) {
    if (window.label == label) {
      return window;
    }
  }
  return null;
}

int _counterDelta(int previous, int current) {
  if (current >= previous) {
    return current - previous;
  }
  return current;
}

double? _average(Iterable<double> values) {
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    total += value;
    count++;
  }
  return count == 0 ? null : total / count;
}

double? _percentile(Iterable<double> values, double percentile) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) {
    return null;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }

  final bounded = max(0.0, min(1.0, percentile));
  final position = (sorted.length - 1) * bounded;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final weight = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * weight;
}

int? _averageInt(Iterable<int> values) {
  var total = 0;
  var count = 0;
  for (final value in values) {
    total += value;
    count++;
  }
  return count == 0 ? null : (total / count).round();
}

double? _maxDouble(Iterable<double> values) {
  double? result;
  for (final value in values) {
    result = result == null ? value : max(result, value);
  }
  return result;
}

double? _minDouble(Iterable<double> values) {
  double? result;
  for (final value in values) {
    result = result == null ? value : min(result, value);
  }
  return result;
}

int? _maxInt(Iterable<int> values) {
  int? result;
  for (final value in values) {
    result = result == null ? value : max(result, value);
  }
  return result;
}

int? _minInt(Iterable<int> values) {
  int? result;
  for (final value in values) {
    result = result == null ? value : min(result, value);
  }
  return result;
}

List<bool> _sortedBoolList(Iterable<bool> values) {
  final sorted = values.toList();
  sorted.sort((left, right) {
    if (left == right) {
      return 0;
    }
    return left ? 1 : -1;
  });
  return sorted;
}
