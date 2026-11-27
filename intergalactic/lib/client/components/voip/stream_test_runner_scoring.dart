part of 'stream_test_runner.dart';

class StreamTestScore {
  const StreamTestScore({
    required this.stableFps,
    required this.targetResolution,
    required this.lowLoss,
    required this.lowRtt,
    required this.downgradePenalty,
    required this.bottleneck,
    required this.summary,
    required this.temporalAnalysis,
  });

  factory StreamTestScore.fromSamples({
    required ScreenShareProfileConfig profile,
    required List<StreamTestSample> samples,
    String? error,
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
    List<String> diagnosticLogMarkers = const [],
    DateTime? measurementStartedAt,
    DateTime? measurementEndedAt,
  }) {
    final summary = StreamTestSummary.fromSamples(
      samples,
      nativeDiagnostics: nativeDiagnostics,
    );
    final targetFps = profile.mainLayer.targetFramerateForScoring.toDouble();
    final temporalAnalysis = StreamTestTemporalAnalysis.fromSamplesAndMarkers(
      samples: samples,
      nativeDiagnosticMarkers: diagnosticLogMarkers,
      measurementStartedAt: measurementStartedAt,
      measurementEndedAt: measurementEndedAt,
      targetFps: targetFps,
    );
    final captureOutputProbablyInvalid =
        summary.nativeDiagnostics.gdiOutputProbablyInvalid;
    final averageFps = summary.averageFps;
    final fpsRatio = _effectiveFpsRatio(
      summary: summary,
      targetFps: targetFps,
      averageFps: averageFps,
    );
    final baseStableFps = captureOutputProbablyInvalid
        ? 0
        : _fpsScore(fpsRatio);
    final targetResolution = captureOutputProbablyInvalid
        ? 0
        : _resolutionScore(profile, summary);
    final lowLoss = _lossScore(summary);
    final lowRtt = _rttScore(summary);
    final downgradePenalty = _downgradePenalty(
      profile: profile,
      summary: summary,
      fpsRatio: fpsRatio,
      error: error,
    );
    final bottleneck = _classifyBottleneck(
      profile: profile,
      summary: summary,
      temporalAnalysis: temporalAnalysis,
      fpsRatio: fpsRatio,
      error: error,
    );
    final stableFps = _stableFpsScoreForBottleneck(
      baseStableFps: baseStableFps,
      bottleneck: bottleneck,
    );

    return StreamTestScore(
      stableFps: stableFps,
      targetResolution: targetResolution,
      lowLoss: lowLoss,
      lowRtt: lowRtt,
      downgradePenalty: downgradePenalty,
      bottleneck: bottleneck,
      summary: summary,
      temporalAnalysis: temporalAnalysis,
    );
  }

  final int stableFps;
  final int targetResolution;
  final int lowLoss;
  final int lowRtt;
  final int downgradePenalty;
  final StreamTestBottleneck bottleneck;
  final StreamTestSummary summary;
  final StreamTestTemporalAnalysis temporalAnalysis;

  int get totalScore =>
      stableFps + targetResolution + lowLoss + lowRtt - downgradePenalty;

  Map<String, Object?> toJson() {
    return {
      'formula':
          'stable_fps + target_resolution + low_loss + low_rtt - downgrade_penalty; stable_fps uses average FPS capped by sampled sender/native p95/max frame pacing',
      'stable_fps': stableFps,
      'target_resolution': targetResolution,
      'low_loss': lowLoss,
      'low_rtt': lowRtt,
      'downgrade_penalty': downgradePenalty,
      'bottleneck': bottleneck.toJson(),
      'temporalAnalysis': temporalAnalysis.toJson(),
      'total': totalScore,
    };
  }

  static int _fpsScore(double ratio) {
    if (ratio >= 0.9) return 25;
    if (ratio >= 0.75) return 20;
    if (ratio > 0) {
      return (ratio * 25).round().clamp(1, 18).toInt();
    }
    return 0;
  }

  static int _stableFpsScoreForBottleneck({
    required int baseStableFps,
    required StreamTestBottleneck bottleneck,
  }) {
    if (bottleneck.label == 'frame_pacing_unstable' ||
        bottleneck.label == 'delivery_queue_limited' ||
        bottleneck.label == 'native_nv12_gpu_queue_delay_limited' ||
        bottleneck.label == 'native_nv12_ready_limited' ||
        bottleneck.label == 'encoder_handoff_limited') {
      return min(baseStableFps, 10);
    }
    return baseStableFps;
  }

  static int _resolutionScore(
    ScreenShareProfileConfig profile,
    StreamTestSummary summary,
  ) {
    final width = summary.encodedWidth;
    final height = summary.encodedHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 0;
    }

    final targetWidth = profile.mainLayer.width;
    final targetHeight = profile.mainLayer.height;
    final exceedsTarget =
        width > targetWidth + 32 || height > targetHeight + 18;
    final pixelRatio = (width * height) / (targetWidth * targetHeight);
    if (exceedsTarget) return 5;
    if (pixelRatio >= 0.9) return 25;
    if (pixelRatio >= 0.75) return 18;
    if (pixelRatio >= 0.5) return 10;
    return 4;
  }

  static int _lossScore(StreamTestSummary summary) {
    final loss = summary.maxPacketLossPercent;
    if (loss == null) return 0;
    final nack = summary.maxNackCount ?? 0;
    if (loss <= 0.5 && nack <= 2) return 25;
    if (loss <= 1.0 && nack <= 8) return 20;
    if (loss <= 3.0) return 12;
    return 0;
  }

  static int _rttScore(StreamTestSummary summary) {
    final rtt = summary.maxRoundTripTimeMs;
    if (rtt == null) return 0;
    if (rtt <= 60) return 15;
    if (rtt <= 120) return 10;
    if (rtt <= 250) return 5;
    return 0;
  }

  static int _downgradePenalty({
    required ScreenShareProfileConfig profile,
    required StreamTestSummary summary,
    required double fpsRatio,
    String? error,
  }) {
    var penalty = 0;
    if (error != null) {
      penalty += 30;
    }
    if (summary.qualityLimitationReasons.any(
      (reason) => reason.toLowerCase() != 'none',
    )) {
      penalty += 10;
    }
    if (summary.activeLayers.any(_isDowngradedLayer)) {
      penalty += 10;
    }
    if (summary.nativeDiagnostics.gdiOutputProbablyInvalid) {
      penalty += 30;
    }
    if (fpsRatio > 0 && fpsRatio < 0.5) {
      penalty += 10;
    }
    final width = summary.encodedWidth;
    final height = summary.encodedHeight;
    if (width != null && height != null) {
      final pixelRatio =
          (width * height) /
          (profile.mainLayer.width * profile.mainLayer.height);
      if (pixelRatio < 0.5) {
        penalty += 10;
      }
    }
    return penalty.clamp(0, 30).toInt();
  }

  static bool _isDowngradedLayer(String layer) {
    final normalized = layer.toLowerCase();
    return normalized == 'q' ||
        normalized == 'l' ||
        normalized == 'low' ||
        normalized.contains('low-layer') ||
        normalized.contains('rescue');
  }

  static bool _isLiveKitPublishPreEventError(String? error) {
    if (error == null) {
      return false;
    }
    final normalized = error.toLowerCase();
    return normalized.contains('publishvideotrack') &&
        (normalized.contains('before local track publication') ||
            normalized.contains('stage=publishvideotrack_pre_event'));
  }

  static StreamTestBottleneck _classifyBottleneck({
    required ScreenShareProfileConfig profile,
    required StreamTestSummary summary,
    required StreamTestTemporalAnalysis temporalAnalysis,
    required double fpsRatio,
    String? error,
  }) {
    final reasons = <String>[];
    final native = summary.nativeDiagnostics;
    if (_isLiveKitPublishPreEventError(error)) {
      final reportedError = error ?? 'unknown';
      return StreamTestBottleneck(
        label: 'livekit_publish_pre_event_limited',
        reasons: [
          'LiveKit publishVideoTrack timed out before local publication',
        ],
        confidence: 'high',
        evidenceFor: ['runner reported error: $reportedError'],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: [
          'LiveKit local publication event',
          'sender track stats',
          'native WebRTC source startup markers',
        ],
        recommendedNextAction: 'fix game-capture handoff',
      );
    }
    if (_nativeEncoderHandoffLimited(summary)) {
      return _nativeEncoderHandoffLimitedBottleneck(summary);
    }
    if (_gameCaptureGpuHandoffUnproven(summary)) {
      return _gameCaptureGpuHandoffUnprovenBottleneck(summary);
    }
    if (error != null) {
      return StreamTestBottleneck(
        label: 'runner_error',
        reasons: ['runner error: $error'],
        confidence: 'high',
        evidenceFor: ['runner reported error: $error'],
        missingFields: _classificationMissingFields(summary),
        recommendedNextAction: 'fix source selection',
      );
    }
    if (summary.senderSampleCount == 0) {
      return const StreamTestBottleneck(
        label: 'no_sent_frames',
        reasons: ['no sender screenshare stats were collected'],
        confidence: 'medium',
        missingFields: ['sender track stats', 'encoded frame size', 'send FPS'],
        evidenceFor: ['no sender screenshare stats were collected'],
        recommendedNextAction: 'fix source selection',
      );
    }

    if (native.gdiOutputProbablyInvalid) {
      return StreamTestBottleneck(
        label: 'invalid_capture_output',
        reasons: [
          native.gdiOutputValidityLabel,
          if (native.gdiFrameSummaryLabel != 'unknown')
            'window-GDI substage ${native.gdiFrameSummaryLabel}',
        ],
        confidence: 'high',
        evidenceFor: [
          native.gdiOutputValidityLabel,
          'final window-GDI frame producer mix: '
              '${native.gdiFinalMethodMixLabel}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix window-GDI substage',
      );
    }

    if (_resolutionLimitNotApplied(summary)) {
      return StreamTestBottleneck(
        label: 'resolution_limit_not_applied',
        reasons: [
          'requested ${summary.requestedResolutionLabel} but encoded '
              '${summary.encodedResolutionLabel}',
          if (summary.preEncodeResolutionLabel != 'unknown')
            'pre-encode ${summary.preEncodeResolutionLabel}',
        ],
        confidence: 'high',
        evidenceFor: [
          'requested ${summary.requestedResolutionLabel} but encoded '
              '${summary.encodedResolutionLabel}',
          if (summary.preEncodeResolutionLabel != 'unknown')
            'pre-encode ${summary.preEncodeResolutionLabel}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix geometry/scaling',
      );
    }

    final targetFps = profile.mainLayer.targetFramerateForScoring.toDouble();
    final captureFps = summary.averageCaptureFps;
    final encodeFps = summary.averageEncodeFps;
    final sendFps = summary.averageSendFps;
    final frameBudgetMs = targetFps <= 0 ? null : 1000 / targetFps;
    final averageEncodeTimeMs = summary.averageEncodeTimeMs;
    final nativeCaptureLimited = native.isCaptureLimitedFor(
      targetFps: targetFps,
      frameBudgetMs: frameBudgetMs,
    );
    final captureEncodeSendTrack =
        captureFps == null ||
        (_stageFpsTracks(encodeFps, captureFps) &&
            _stageFpsTracks(sendFps, encodeFps ?? captureFps));
    final nativeNv12SourceActive =
        native.gameCaptureNativeNv12SubmittedFrames > 0 &&
        native.gameCaptureNativeNv12Failures == 0 &&
        native.gameCaptureCpuFallbackFrames == 0;
    if (nativeNv12SourceActive) {
      final missingNativeEncoderFenceTiming =
          _gameCaptureNativeEncoderFenceTimingMissingBottleneck(
            summary: summary,
            native: native,
            frameBudgetMs: frameBudgetMs,
          );
      if (missingNativeEncoderFenceTiming != null) {
        return missingNativeEncoderFenceTiming;
      }
      final liveSenderHandoffBackpressure =
          _gameCaptureLiveSenderHandoffBackpressureBottleneck(
            summary: summary,
            native: native,
            frameBudgetMs: frameBudgetMs,
            targetFps: targetFps,
          );
      if (liveSenderHandoffBackpressure != null) {
        return liveSenderHandoffBackpressure;
      }
      final averagePassWithNativeTailReview =
          _gameCaptureAveragePassWithNativeTailReviewBottleneck(
            summary: summary,
            native: native,
            temporalAnalysis: temporalAnalysis,
            frameBudgetMs: frameBudgetMs,
            targetFps: targetFps,
          );
      if (averagePassWithNativeTailReview != null) {
        return averagePassWithNativeTailReview;
      }
      final nativeNv12GpuQueueDelayLimited =
          _gameCaptureNativeNv12GpuQueueDelayBottleneck(
            summary: summary,
            native: native,
            frameBudgetMs: frameBudgetMs,
          );
      if (nativeNv12GpuQueueDelayLimited != null) {
        return nativeNv12GpuQueueDelayLimited;
      }
      final nativeNv12ReadyLimited = _gameCaptureNativeNv12ReadyBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (nativeNv12ReadyLimited != null) {
        return nativeNv12ReadyLimited;
      }
      final gameCaptureOnFrameLimited = _gameCaptureOnFrameLimitedBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (gameCaptureOnFrameLimited != null) {
        return gameCaptureOnFrameLimited;
      }
      final gameCaptureNativeDeliveryBackpressure =
          _gameCaptureDeliveryBackpressureBottleneck(
            summary: summary,
            native: native,
            frameBudgetMs: frameBudgetMs,
          );
      if (gameCaptureNativeDeliveryBackpressure != null) {
        return gameCaptureNativeDeliveryBackpressure;
      }
      if (native.isNativeEncoderOverBudgetFor(frameBudgetMs)) {
        return _mediaFoundationEncoderLimitedBottleneck(
          summary: summary,
          frameBudgetMs: frameBudgetMs,
        );
      }
    }
    final loss = summary.maxPacketLossPercent ?? 0;
    final rtt = summary.maxRoundTripTimeMs ?? 0;
    final nack = summary.maxNackCount ?? 0;
    if (loss > 1.0 || rtt > 150 || nack > 8) {
      if (loss > 1.0) {
        reasons.add('packet loss ${loss.toStringAsFixed(1)}%');
      }
      if (rtt > 150) {
        reasons.add('RTT ${rtt.toStringAsFixed(0)}ms');
      }
      if (nack > 8) {
        reasons.add('NACK count $nack');
      }
      return StreamTestBottleneck(
        label: 'network_limited',
        reasons: reasons,
        confidence: 'high',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('network evidence'))
            .toList(growable: false),
        recommendedNextAction: 'inspect server/network',
      );
    }
    final gameCaptureHasSourceFramesBeyondSubmitted =
        native.gameCaptureCopiedFrames >
        native.gameCaptureSubmittedFrames +
            max(10, native.gameCaptureDuplicateSkippedFrames * 2);
    final gameCaptureSubmitGap =
        native.gameCaptureCopiedFrames - native.gameCaptureSubmittedFrames;
    final gameCaptureReadbackDropsHigh =
        native.gameCaptureReadbackLatencyDroppedFrames >
        max(10, gameCaptureSubmitGap ~/ 4);
    final gameCaptureReadbackDeliveryLimited =
        gameCaptureHasSourceFramesBeyondSubmitted &&
        native.gameCaptureGpuScaledFrames > 0 &&
        native.gameCaptureCpuFallbackFrames == 0 &&
        gameCaptureReadbackDropsHigh;
    if (gameCaptureReadbackDeliveryLimited) {
      final copiedEvidence =
          'game hook copied ${native.gameCaptureCopiedFrames} source frames '
          'but submitted ${native.gameCaptureSubmittedFrames}';
      final readbackEvidence =
          'readback latency dropped '
          '${native.gameCaptureReadbackLatencyDroppedFrames} frames with '
          '${native.gameCaptureReadbackNotReadyFrames} not-ready maps';
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          copiedEvidence,
          readbackEvidence,
          if (native.gameCaptureMaxReadbackLatencyFrames > 0)
            'readback latency reached '
                '${native.gameCaptureMaxReadbackLatencyFrames} frames',
        ],
        confidence: 'high',
        evidenceFor: [copiedEvidence, readbackEvidence],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
          ..._evidenceAgainstCommonFalseCauses(summary)
              .where((evidence) => !evidence.startsWith('native encoder'))
              .toList(growable: false),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    final gameCaptureSubmittedFrames = native.gameCaptureSubmittedFrames;
    final gameCaptureRepeatRatio = gameCaptureSubmittedFrames <= 0
        ? 0.0
        : native.gameCaptureRepeatedFrames / gameCaptureSubmittedFrames;
    final repeatedFrameThreshold = max(
      (targetFps * 2).round(),
      (gameCaptureSubmittedFrames * 0.02).round(),
    );
    final gameCaptureRepeatedDeliveryLimited =
        native.gameCaptureRepeatedFrames > repeatedFrameThreshold &&
        native.gameCaptureGpuScaledFrames > 0 &&
        native.gameCaptureCpuFallbackFrames == 0 &&
        native.gameCaptureSourceFrameRegressions == 0 &&
        native.gameCaptureSharedSlotMismatches == 0;
    if (gameCaptureRepeatedDeliveryLimited) {
      final repeatedEvidence =
          'game hook repeated ${native.gameCaptureRepeatedFrames} of '
          '$gameCaptureSubmittedFrames submitted frames '
          '(${(gameCaptureRepeatRatio * 100).toStringAsFixed(1)}%)';
      final readbackEvidence = [
        if (native.averageGameCaptureReadbackLatencyFrames != null)
          'readback latency averaged '
              '${native.averageGameCaptureReadbackLatencyFrames!.toStringAsFixed(1)} '
              'queued frames',
        if (native.gameCaptureMaxReadbackLatencyFrames > 0)
          'readback latency peaked at '
              '${native.gameCaptureMaxReadbackLatencyFrames} queued frames',
        if (native.gameCaptureReadbackNotReadyFrames > 0)
          '${native.gameCaptureReadbackNotReadyFrames} readback map attempts '
              'were not ready',
      ];
      final nativeNv12Evidence = [
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        if (native.gameCaptureNativeNv12ReadyDroppedFrames > 0)
          'native NV12 ready queue dropped '
              '${native.gameCaptureNativeNv12ReadyDroppedFrames} frames',
        if (native.gameCaptureNativeNv12NotReadyPolls > 0)
          'native NV12 readiness polled not-ready '
              '${native.gameCaptureNativeNv12NotReadyPolls} times',
      ];
      final repeatedPathEvidence = nativeNv12SourceActive
          ? nativeNv12Evidence
          : readbackEvidence;
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          repeatedEvidence,
          ...repeatedPathEvidence,
          'encoded/sent FPS can remain near target while visual cadence stutters '
              'because repeated source frames are delivered at paced timestamps',
        ],
        confidence: 'high',
        evidenceFor: [repeatedEvidence, ...repeatedPathEvidence],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
          ..._evidenceAgainstCommonFalseCauses(summary)
              .where((evidence) => !evidence.startsWith('native encoder'))
              .toList(growable: false),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    final gameCaptureSourcePresentLimited =
        native.gameCaptureDuplicateSkippedFrames > 0 &&
        !gameCaptureHasSourceFramesBeyondSubmitted &&
        native.gameCaptureRepeatedFrames == 0 &&
        native.gameCaptureSourceFrameDuplicates == 0 &&
        native.gameCaptureSourceFrameRegressions == 0 &&
        native.gameCaptureSharedSlotMismatches == 0 &&
        native.gameCaptureGpuScaleFailures == 0 &&
        native.gameCaptureCpuFallbackFrames == 0 &&
        native.averageGameCaptureFps != null &&
        targetFps > 0 &&
        native.averageGameCaptureFps! < targetFps * 0.75 &&
        captureEncodeSendTrack;
    if (gameCaptureSourcePresentLimited) {
      final sourceFps = native.averageGameCaptureFps!;
      final sourceLimitEvidence =
          'game hook saw ${sourceFps.toStringAsFixed(1)} unique source FPS '
          'while preset requested ${targetFps.toStringAsFixed(0)}';
      final duplicateSkipEvidence =
          'skipped ${native.gameCaptureDuplicateSkippedFrames} duplicate '
          'source ticks instead of resubmitting stale frames';
      return StreamTestBottleneck(
        label: 'source_present_limited',
        reasons: [
          sourceLimitEvidence,
          duplicateSkipEvidence,
          if (captureFps != null)
            'capture/encode/send FPS all track around '
                '${captureFps.toStringAsFixed(1)}fps',
        ],
        confidence: 'high',
        evidenceFor: [sourceLimitEvidence, duplicateSkipEvidence],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
        ],
        missingFields: const [],
        recommendedNextAction: 'no stream change recommended',
      );
    }
    if (temporalAnalysis.hasLateDegradation) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: temporalAnalysis.lateDegradationSignals,
        confidence: 'high',
        evidenceFor: temporalAnalysis.lateDegradationSignals,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    if (nativeCaptureLimited && captureEncodeSendTrack) {
      return _nativeCaptureLimitedBottleneck(
        native: native,
        targetFps: targetFps,
        frameBudgetMs: frameBudgetMs,
        captureFps: captureFps,
      );
    }
    final gameCaptureOnFrameLimited = _gameCaptureOnFrameLimitedBottleneck(
      summary: summary,
      native: native,
      frameBudgetMs: frameBudgetMs,
    );
    if (gameCaptureOnFrameLimited != null) {
      return gameCaptureOnFrameLimited;
    }
    final gameCaptureDeliveryBackpressure =
        _gameCaptureDeliveryBackpressureBottleneck(
          summary: summary,
          native: native,
          frameBudgetMs: frameBudgetMs,
        );
    if (gameCaptureDeliveryBackpressure != null) {
      return gameCaptureDeliveryBackpressure;
    }

    final lowStageCadence =
        captureFps != null &&
        targetFps > 0 &&
        captureFps < targetFps * 0.75 &&
        _stageFpsTracks(encodeFps, captureFps) &&
        _stageFpsTracks(sendFps, encodeFps ?? captureFps);
    if (lowStageCadence) {
      if (averageEncodeTimeMs != null &&
          frameBudgetMs != null &&
          averageEncodeTimeMs > frameBudgetMs * 1.25) {
        return StreamTestBottleneck(
          label: 'encoder_pipeline_limited',
          reasons: [
            'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
                '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
            'capture/encode/send FPS all track around '
                '${captureFps.toStringAsFixed(1)}fps, consistent with encoder '
                'pipeline backpressure',
            if (summary.averagePacketSendDelayMs != null &&
                summary.averagePacketSendDelayMs! > 40)
              'send queue delay ${summary.averagePacketSendDelayMs!.toStringAsFixed(0)}ms',
            if (summary.preEncodeSampleCount == 0)
              'pre-encode dimensions were unavailable in sender stats',
          ],
          confidence: 'high',
          evidenceFor: [
            'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
                '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
            'capture/encode/send FPS track around '
                '${captureFps.toStringAsFixed(1)}fps',
          ],
          evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(
            summary,
          ),
          missingFields: summary.preEncodeSampleCount == 0
              ? const ['pre-encode dimensions']
              : const [],
          recommendedNextAction: 'fix encoder path',
        );
      }
      return StreamTestBottleneck(
        label: 'capture_or_preencode_limited',
        reasons: [
          'capture/pre-encode FPS ${captureFps.toStringAsFixed(1)} is below '
              'target ${targetFps.toStringAsFixed(0)} while encode/send FPS '
              'track the same cadence',
          if (summary.preEncodeSampleCount == 0)
            'pre-encode dimensions were unavailable in sender stats',
        ],
        confidence: summary.preEncodeSampleCount > 0 ? 'medium' : 'low',
        evidenceFor: [
          'capture/pre-encode FPS ${captureFps.toStringAsFixed(1)} is below '
              'target ${targetFps.toStringAsFixed(0)} and encode/send track it',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.nativeDiagnostics.hasEvidence
            ? const []
            : const ['native capture markers'],
        recommendedNextAction: summary.nativeDiagnostics.hasEvidence
            ? 'fix capture backend'
            : 'collect one specific missing field',
      );
    }

    if (captureFps != null &&
        encodeFps != null &&
        captureFps > 0 &&
        encodeFps < captureFps * 0.8) {
      reasons.add(
        'encode FPS ${encodeFps.toStringAsFixed(1)} trails capture FPS '
        '${captureFps.toStringAsFixed(1)}',
      );
    }
    if (averageEncodeTimeMs != null &&
        frameBudgetMs != null &&
        averageEncodeTimeMs > frameBudgetMs * 1.25) {
      reasons.add(
        'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
        '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      );
    }
    if (summary.framesDroppedByEncoderMax != null &&
        summary.framesDroppedByEncoderMax! > 0) {
      reasons.add(
        'encoder dropped ${summary.framesDroppedByEncoderMax} frames',
      );
    }
    if (summary.qualityLimitationReasons.any(
      (reason) => reason.toLowerCase() == 'cpu',
    )) {
      reasons.add('WebRTC quality limitation is cpu');
    }
    if (reasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'encode_limited',
        reasons: [
          ...reasons,
          if (summary.averagePacketSendDelayMs != null &&
              summary.averagePacketSendDelayMs! > 40)
            'send queue delay ${summary.averagePacketSendDelayMs!.toStringAsFixed(0)}ms follows encoder/backpressure',
        ],
        confidence:
            averageEncodeTimeMs != null ||
                summary.framesDroppedByEncoderMax != null
            ? 'high'
            : 'medium',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: averageEncodeTimeMs == null
            ? const ['average encode time']
            : const [],
        recommendedNextAction: 'fix encoder path',
      );
    }

    if (encodeFps != null &&
        sendFps != null &&
        encodeFps > 0 &&
        sendFps < encodeFps * 0.8) {
      reasons.add(
        'send FPS ${sendFps.toStringAsFixed(1)} trails encode FPS '
        '${encodeFps.toStringAsFixed(1)}',
      );
    }
    final sendDelay = summary.averagePacketSendDelayMs;
    if (sendDelay != null && sendDelay > 40) {
      reasons.add('send queue delay ${sendDelay.toStringAsFixed(0)}ms');
    }
    if (reasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'send_limited',
        reasons: reasons,
        confidence: 'medium',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.averagePacketSendDelayMs == null
            ? const ['packet send delay']
            : const [],
        recommendedNextAction: 'inspect server/network',
      );
    }

    if (captureFps != null &&
        targetFps > 0 &&
        captureFps < targetFps * 0.75 &&
        (encodeFps == null || encodeFps >= captureFps * 0.8) &&
        (sendFps == null || sendFps >= (encodeFps ?? captureFps) * 0.8)) {
      return StreamTestBottleneck(
        label: 'capture_limited',
        reasons: [
          'capture FPS ${captureFps.toStringAsFixed(1)} is below target '
              '${targetFps.toStringAsFixed(0)}',
        ],
        confidence: summary.nativeDiagnostics.hasEvidence ? 'medium' : 'low',
        evidenceFor: [
          'capture FPS ${captureFps.toStringAsFixed(1)} is below target '
              '${targetFps.toStringAsFixed(0)}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.nativeDiagnostics.hasEvidence
            ? const []
            : const ['native capture markers'],
        recommendedNextAction: summary.nativeDiagnostics.hasEvidence
            ? 'fix capture backend'
            : 'collect one specific missing field',
      );
    }

    if (summary.activeLayers.any(_isDowngradedLayer)) {
      return StreamTestBottleneck(
        label: 'downgraded_layer',
        reasons: ['active layers: ${summary.activeLayersLabel}'],
        confidence: 'medium',
        evidenceFor: ['active layers: ${summary.activeLayersLabel}'],
        missingFields: const ['receiver subscribed layer reason'],
        recommendedNextAction: 'fix receiver subscription/rendering',
      );
    }

    final sourceOrderReasons = <String>[];
    if (native.gameCaptureSourceFrameRegressions > 0) {
      sourceOrderReasons.add(
        'source frame index regressed '
        '${native.gameCaptureSourceFrameRegressions} times',
      );
    }
    if (native.gameCaptureSharedSlotMismatches > 0) {
      sourceOrderReasons.add(
        'shared slot frame index mismatched latest frame '
        '${native.gameCaptureSharedSlotMismatches} times',
      );
    }
    if (sourceOrderReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'source_frame_order_unstable',
        reasons: sourceOrderReasons,
        confidence: 'high',
        evidenceFor: [
          ...sourceOrderReasons,
          'source frame ${native.gameCaptureSourceFrameIndex}, '
              'last submitted source frame '
              '${native.gameCaptureLastSubmittedSourceFrameIndex}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix game-capture handoff',
      );
    }

    final timestampReasons = <String>[];
    final maxTimestampDelta = native.maxGameCaptureTimestampDeltaMs;
    final timestampMode = native.gameCaptureTimestampMode;
    final timestampPolicyDeliveryWallMax =
        native.maxGameCaptureDeliveryWallDeltaMs;
    final timestampPolicySourceQpcMax = native.maxGameCaptureSourceQpcDeltaMs;
    final timestampDeltaLooksPaced =
        maxTimestampDelta != null &&
        frameBudgetMs != null &&
        maxTimestampDelta <= frameBudgetMs * 1.25;
    final wallOrSourceGapDiverged =
        frameBudgetMs != null &&
        ((timestampPolicyDeliveryWallMax != null &&
                timestampPolicyDeliveryWallMax > frameBudgetMs * 2.0) ||
            native.gameCaptureDeliveryWallOver2xFrames > 0 ||
            (timestampPolicySourceQpcMax != null &&
                timestampPolicySourceQpcMax > frameBudgetMs * 2.0));
    if (timestampMode == 'paced' &&
        native.gameCaptureRepeatedFrames == 0 &&
        timestampDeltaLooksPaced &&
        wallOrSourceGapDiverged) {
      final reasons = <String>[
        'paced timestamps stayed near '
            '${maxTimestampDelta.toStringAsFixed(1)}ms while delivery/source '
            'cadence exceeded a ${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
        if (timestampPolicyDeliveryWallMax != null)
          'delivery wall-clock gap peaked at '
              '${timestampPolicyDeliveryWallMax.toStringAsFixed(1)}ms',
        if (timestampPolicySourceQpcMax != null)
          'source QPC gap peaked at '
              '${timestampPolicySourceQpcMax.toStringAsFixed(1)}ms',
      ];
      return StreamTestBottleneck(
        label: 'timestamp_policy_mismatch',
        reasons: reasons,
        confidence:
            native.gameCaptureDeliveryWallSamples > 0 ||
                native.gameCaptureSourceQpcSamples > 0
            ? 'high'
            : 'medium',
        evidenceFor: [
          ...reasons,
          'timestamp source-QPC frames '
              '${native.gameCaptureTimestampSourceQpcFrames}, paced fallback '
              '${native.gameCaptureTimestampPacedFallbackFrames}, repeated '
              '${native.gameCaptureTimestampRepeatedFrames}',
          'delivery wall gap distribution >2x='
              '${native.gameCaptureDeliveryWallOver2xFrames}, >3x='
              '${native.gameCaptureDeliveryWallOver3xFrames}, <0.5x='
              '${native.gameCaptureDeliveryWallUnderHalfFrames}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }
    if (maxTimestampDelta != null &&
        frameBudgetMs != null &&
        timestampMode != 'paced' &&
        maxTimestampDelta > frameBudgetMs * 1.25) {
      timestampReasons.add(
        'game-capture delivery timestamp delta peaked at '
        '${maxTimestampDelta.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }
    if (native.gameCaptureTimestampAdjustments > 0) {
      timestampReasons.add(
        'game-capture adjusted '
        '${native.gameCaptureTimestampAdjustments} non-monotonic timestamps',
      );
    }
    if (timestampReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: timestampReasons,
        confidence: 'high',
        evidenceFor: [
          ...timestampReasons,
          'timestamp mode ${timestampMode ?? 'unknown'}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final deliveryWallReasons = <String>[];
    final deliveryWallEvidence = <String>[];
    final deliveryWallMissingFields = <String>[];
    final maxDeliveryWallDelta = native.maxGameCaptureDeliveryWallDeltaMs;
    if (maxDeliveryWallDelta != null &&
        frameBudgetMs != null &&
        maxDeliveryWallDelta > frameBudgetMs * 2.0) {
      deliveryWallReasons.add(
        'game-capture actual OnFrame wall-clock gap peaked at '
        '${maxDeliveryWallDelta.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
      final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
      final readyToSubmitMax = native.maxGameCaptureReadyToSubmitMs;
      final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
      if (queueWaitMax != null &&
          native.gameCaptureDeliveryQueueWaitSamples > 0) {
        deliveryWallEvidence.add(
          'delivery queue wait max '
          '${queueWaitMax.toStringAsFixed(1)}ms',
        );
        if (queueWaitMax > frameBudgetMs * 2.0) {
          deliveryWallReasons.add(
            'delivery thread queue wait alone exceeded budget at '
            '${queueWaitMax.toStringAsFixed(1)}ms',
          );
        }
      } else {
        deliveryWallMissingFields.add('game-capture delivery queue wait');
      }
      if (readyToSubmitMax != null &&
          native.gameCaptureReadyToSubmitSamples > 0) {
        deliveryWallEvidence.add(
          'ready-to-submit max ${readyToSubmitMax.toStringAsFixed(1)}ms',
        );
      } else {
        deliveryWallMissingFields.add('game-capture ready-to-submit timing');
      }
      if (sourceToSubmitMax != null &&
          native.gameCaptureSourceToSubmitSamples > 0) {
        deliveryWallEvidence.add(
          'source-to-submit max ${sourceToSubmitMax.toStringAsFixed(1)}ms',
        );
        if (sourceToSubmitMax > frameBudgetMs * 3.0) {
          deliveryWallReasons.add(
            'source-to-submit latency exceeded three frame budgets at '
            '${sourceToSubmitMax.toStringAsFixed(1)}ms',
          );
        }
      } else {
        deliveryWallMissingFields.add('game-capture source-to-submit timing');
      }
      if (native.gameCaptureDeliveryWallOver2xFrames > 0 ||
          native.gameCaptureDeliveryWallOver3xFrames > 0 ||
          native.gameCaptureDeliveryWallUnderHalfFrames > 0) {
        deliveryWallEvidence.add(
          'wall-gap distribution >2x=${native.gameCaptureDeliveryWallOver2xFrames}, '
          '>3x=${native.gameCaptureDeliveryWallOver3xFrames}, '
          '<0.5x=${native.gameCaptureDeliveryWallUnderHalfFrames}',
        );
      } else {
        deliveryWallMissingFields.add('game-capture wall-gap distribution');
      }
    }
    if (deliveryWallReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: deliveryWallReasons,
        confidence: deliveryWallMissingFields.isEmpty ? 'high' : 'medium',
        missingFields: deliveryWallMissingFields,
        evidenceFor: [
          ...deliveryWallReasons,
          ...deliveryWallEvidence,
          'timestamp mode ${timestampMode ?? 'unknown'}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final sourceToSubmitReasons = <String>[];
    final sourceToSubmitEvidence = <String>[];
    final sourceToSubmitAverage = native.averageGameCaptureSourceToSubmitMs;
    final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
    final sourceToSubmitSamples = native.gameCaptureSourceToSubmitSamples;
    if (frameBudgetMs != null &&
        native.gameCaptureSubmittedFrames > 0 &&
        native.gameCaptureGpuScaledFrames > 0 &&
        native.gameCaptureCpuFallbackFrames == 0 &&
        sourceToSubmitSamples > 0 &&
        sourceToSubmitAverage != null &&
        sourceToSubmitMax != null &&
        sourceToSubmitAverage > frameBudgetMs * 2.0 &&
        sourceToSubmitMax > frameBudgetMs * 4.0) {
      sourceToSubmitReasons.add(
        'game-capture source-to-submit latency averaged '
        '${sourceToSubmitAverage.toStringAsFixed(1)}ms and peaked at '
        '${sourceToSubmitMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
      if (queueWaitAverage != null &&
          queueWaitMax != null &&
          native.gameCaptureDeliveryQueueWaitSamples > 0) {
        sourceToSubmitEvidence.add(
          'delivery queue wait averaged '
          '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
          '${queueWaitMax.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureSourceToReadbackReadySamples > 0 &&
          native.averageGameCaptureSourceToReadbackReadyMs != null &&
          native.maxGameCaptureSourceToReadbackReadyMs != null) {
        sourceToSubmitEvidence.add(
          'source-to-readback-ready averaged '
          '${native.averageGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureReadbackQueueToMapSamples > 0 &&
          native.averageGameCaptureReadbackQueueToMapMs != null &&
          native.maxGameCaptureReadbackQueueToMapMs != null) {
        sourceToSubmitEvidence.add(
          'readback queue-to-map averaged '
          '${native.averageGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureMapToI420Samples > 0 &&
          native.averageGameCaptureMapToI420Ms != null &&
          native.maxGameCaptureMapToI420Ms != null) {
        sourceToSubmitEvidence.add(
          'map-to-I420 averaged '
          '${native.averageGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureSourceToQueueSamples > 0 &&
          native.averageGameCaptureSourceToQueueMs != null &&
          native.maxGameCaptureSourceToQueueMs != null) {
        sourceToSubmitEvidence.add(
          'source-to-delivery-queue averaged '
          '${native.averageGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.averageGameCaptureReadbackLatencyFrames != null) {
        sourceToSubmitEvidence.add(
          'readback latency averaged '
          '${native.averageGameCaptureReadbackLatencyFrames!.toStringAsFixed(1)} '
          'queued frames',
        );
      }
      if (native.gameCaptureReadbackNotReadyFrames > 0) {
        sourceToSubmitEvidence.add(
          '${native.gameCaptureReadbackNotReadyFrames} readback map attempts '
          'were not ready',
        );
      }
    }
    if (sourceToSubmitReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          ...sourceToSubmitReasons,
          'encoded/sent FPS can stay near target while displayed frames are '
              'several frame budgets behind the game source',
        ],
        confidence: 'high',
        evidenceFor: [...sourceToSubmitReasons, ...sourceToSubmitEvidence],
        evidenceAgainstFalseCauses: [
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          ..._evidenceAgainstCommonFalseCauses(summary),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final readbackLatencyReasons = <String>[];
    final readbackDropCorroboration = <String>[];
    final averageReadbackLatencyFrames =
        native.averageGameCaptureReadbackLatencyFrames;
    if (averageReadbackLatencyFrames != null &&
        averageReadbackLatencyFrames > 3.0) {
      readbackLatencyReasons.add(
        'game-capture readback averages '
        '${averageReadbackLatencyFrames.toStringAsFixed(1)} queued frames',
      );
    }
    if (native.gameCaptureMaxReadbackLatencyFrames > 4 &&
        averageReadbackLatencyFrames != null &&
        averageReadbackLatencyFrames > 2.0) {
      readbackLatencyReasons.add(
        'game-capture readback peaked at '
        '${native.gameCaptureMaxReadbackLatencyFrames} queued frames',
      );
    }
    if (native.gameCaptureReadbackLatencyDroppedFrames > 0) {
      if (averageReadbackLatencyFrames != null &&
          averageReadbackLatencyFrames > 2.0) {
        readbackDropCorroboration.add(
          'average game-capture readback latency '
          '${averageReadbackLatencyFrames.toStringAsFixed(1)} frames '
          'exceeds the healthy one-to-two frame range',
        );
      }
      if (native.gameCaptureMaxReadbackLatencyFrames > 2) {
        readbackDropCorroboration.add(
          'game-capture readback latency peaked at '
          '${native.gameCaptureMaxReadbackLatencyFrames} frames',
        );
      }
      final queuedReadbacks = native.gameCaptureReadbackQueuedFrames;
      if (queuedReadbacks > 0) {
        final dropRatio =
            native.gameCaptureReadbackLatencyDroppedFrames / queuedReadbacks;
        if (dropRatio >= 0.03) {
          readbackDropCorroboration.add(
            'stale-readback drop ratio '
            '${(dropRatio * 100).toStringAsFixed(1)}%',
          );
        }
      }
      readbackDropCorroboration.addAll(
        _framePacingReasons(summary: summary, frameBudgetMs: frameBudgetMs),
      );
    }
    if (readbackDropCorroboration.isNotEmpty) {
      readbackLatencyReasons.add(
        'game-capture dropped '
        '${native.gameCaptureReadbackLatencyDroppedFrames} stale readbacks '
        'to bound motion latency',
      );
      readbackLatencyReasons.addAll(readbackDropCorroboration);
    }
    if (readbackLatencyReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: readbackLatencyReasons,
        confidence: 'high',
        evidenceFor: [
          ...readbackLatencyReasons,
          'source regressions '
              '${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final pacingReasons = _framePacingReasons(
      summary: summary,
      frameBudgetMs: frameBudgetMs,
    );
    if (pacingReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: pacingReasons,
        confidence: 'high',
        evidenceFor: pacingReasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    if (fpsRatio >= 0.85) {
      return const StreamTestBottleneck(
        label: 'healthy',
        reasons: [
          'send FPS is near target and no network or encoder limiter was detected',
        ],
        confidence: 'high',
        evidenceFor: [
          'send FPS is near target and no network or encoder limiter was detected',
        ],
        recommendedNextAction: 'no stream change recommended',
      );
    }

    return StreamTestBottleneck(
      label: 'insufficient_evidence',
      reasons: [
        'insufficient corroborating stats; capture=${_number(captureFps)}, '
            'encode=${_number(encodeFps)}, send=${_number(sendFps)}',
      ],
      confidence: 'insufficient',
      missingFields: _classificationMissingFields(summary),
      evidenceFor: [
        'observed FPS ratio ${fpsRatio.toStringAsFixed(2)} lacks a supported '
            'network, encoder, capture, pacing, or receiver cause',
      ],
      evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
      recommendedNextAction: 'collect one specific missing field',
    );
  }

  static StreamTestBottleneck _nativeCaptureLimitedBottleneck({
    required StreamTestNativeDiagnostics native,
    required double targetFps,
    required double? frameBudgetMs,
    required double? captureFps,
  }) {
    final reasons = [
      if (native.averageCaptureCallMs != null && frameBudgetMs != null)
        'native capture calls average '
            '${native.averageCaptureCallMs!.toStringAsFixed(0)}ms '
            'against ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      if (native.averageSourceCaptureMs != null &&
          frameBudgetMs != null &&
          native.averageSourceCaptureMs! > frameBudgetMs)
        'source capture averages '
            '${native.averageSourceCaptureMs!.toStringAsFixed(0)}ms, '
            'so acquisition is consuming the frame budget before local '
            'convert/scale work',
      if (native.wgcFrameSummaryLabel != 'unknown')
        'WGC substage ${native.wgcFrameSummaryLabel}',
      if (native.gdiFrameSummaryLabel != 'unknown')
        'window-GDI substage ${native.gdiFrameSummaryLabel}',
      if (native.p95FrameIntervalMs != null && frameBudgetMs != null)
        'native p95 frame interval '
            '${native.p95FrameIntervalMs!.toStringAsFixed(0)}ms '
            'against ${frameBudgetMs.toStringAsFixed(0)}ms cadence',
      if (native.maxFrameIntervalMs != null && frameBudgetMs != null)
        'native max frame gap '
            '${native.maxFrameIntervalMs!.toStringAsFixed(0)}ms',
      if (native.averageNativeFps != null)
        'native emitted FPS ${native.averageNativeFps!.toStringAsFixed(1)} '
            'is below target ${targetFps.toStringAsFixed(0)}',
      if (native.averageEncoderTotalMs != null)
        'native MediaFoundation encoder averages '
            '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms',
      if (native.updatedRegionEmptyCount > 0 ||
          native.updatedRegionNonEmptyCount > 0)
        'updated regions: ${native.updatedRegionNonEmptyCount} dirty / '
            '${native.updatedRegionEmptyCount} empty; '
            '${native.updatedRegionShapeLabel}',
      if (captureFps != null)
        'capture/encode/send FPS all track around '
            '${captureFps.toStringAsFixed(1)}fps',
      if (native.preEncodeResolutionLabel != 'unknown')
        'native pre-encode ${native.preEncodeResolutionLabel}',
      if (native.backendLabel != 'unknown') 'backend ${native.backendLabel}',
    ];
    final recommendedAction = native.wgcFrameSummaryLabel != 'unknown'
        ? 'fix WGC substage'
        : native.gdiFrameSummaryLabel != 'unknown'
        ? 'fix window-GDI substage'
        : native.updatedRegionShapeLabel != 'unknown' &&
              native.updatedRegionTinyFrameCount >
                  native.updatedRegionFullFrameCount
        ? 'fix dirty-region behavior'
        : 'fix capture backend';
    return StreamTestBottleneck(
      label: 'native_capture_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        if (native.averageEncoderTotalMs != null &&
            frameBudgetMs != null &&
            !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
          'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      ],
      missingFields: [
        if (native.wgcFrameSummaryLabel == 'unknown' &&
            native.observedCapturerLabel.toLowerCase().contains('wgc'))
          'WGC substage markers',
        if (native.gdiFrameSummaryLabel == 'unknown' &&
            native.observedCapturerLabel.toLowerCase().contains('window-gdi'))
          'window-GDI substage markers',
      ],
      recommendedNextAction: recommendedAction,
    );
  }

  static StreamTestBottleneck?
  _gameCaptureNativeEncoderFenceTimingMissingBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (!native.nativeEncoderFenceWaitMissing) {
      return null;
    }

    final candidates = <String>[];
    final frameBudget = frameBudgetMs ?? 33.3;
    if (native.averageGameCaptureDeliveryOnFrameCallMs != null ||
        native.maxGameCaptureDeliveryOnFrameCallMs != null) {
      candidates.add(
        'candidate webrtc_onframe_limited: OnFrame call '
        '${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)}',
      );
    }
    if (native.averageGameCaptureDeliveryQueueWaitMs != null ||
        native.averageGameCaptureSourceToSubmitMs != null ||
        native.gameCaptureDeliveryPacerResyncs > 0) {
      candidates.add(
        'candidate delivery_queue_limited: delivery queue wait '
        '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)}, '
        'source-to-submit '
        '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}, '
        'pacer resyncs ${native.gameCaptureDeliveryPacerResyncs}',
      );
    }
    if (native.gameCaptureNativeNv12BgraScaleDrawSamples > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples >
            0) {
      candidates.add(
        'candidate native_nv12_ready_limited: BGRA scale '
        '${_milliseconds(native.averageGameCaptureNativeNv12BgraScaleDrawMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12BgraScaleDrawMs)}, '
        'Blt-to-ready '
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs)}, '
        'Blt GPU '
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)}, '
        'estimated queue '
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)}',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      candidates.add(
        'candidate media_foundation_encoder_limited: aggregate encoder '
        '${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)} with '
        '${native.encoderSlowFrameCount}/${native.encoderSampleCount} slow '
        'samples, but no native fence-wait substage timing',
      );
    }

    return StreamTestBottleneck(
      label: 'insufficient_evidence',
      reasons: [
        'D3D11 native NV12 input reached Media Foundation, but parsed '
            'native_ready_fence_wait_ms timing is missing',
        'cannot separate encoder fence wait, WebRTC OnFrame, and delivery '
            'queue pressure for a ${frameBudget.toStringAsFixed(1)}ms frame budget',
      ],
      confidence: 'insufficient',
      evidenceFor: [
        'native NV12 submitted '
            '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
            '${native.gameCaptureNativeNv12Failures} failures and '
            '${native.gameCaptureCpuFallbackFrames} CPU fallback frames',
        'encoder input path ${native.encoderInputPathLabel}; native '
            '${native.encoderNativeInputFrames}, cpu_i420 '
            '${native.encoderCpuI420InputFrames}',
        ...candidates,
      ],
      evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary)
          .where(
            (evidence) =>
                !evidence.startsWith('native MediaFoundation encoder timing'),
          )
          .toList(growable: false),
      missingFields: const [
        'native_ready_fence',
        'native_ready_fence_timeout',
        'native_ready_fence_wait_ms',
        'process_input_ms',
        'process_output_ms',
      ],
      recommendedNextAction: 'collect one specific missing field',
    );
  }

  static StreamTestBottleneck? _gameCaptureNativeNv12GpuQueueDelayBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples <= 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples <=
            0) {
      return null;
    }

    final queueAverage = native
        .averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs;
    final queueMax = native
        .maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs;
    final gpuAverage =
        native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs;
    final gpuMax =
        native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs;
    final bltToReadyAverage =
        native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    final bltToReadyMax =
        native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    if (queueAverage == null ||
        queueMax == null ||
        gpuAverage == null ||
        gpuMax == null) {
      return null;
    }

    final queueDelayMaterial =
        queueAverage > frameBudgetMs * 0.20 || queueMax > frameBudgetMs * 1.25;
    final queueDominatesGpu =
        queueAverage > gpuAverage * 2.0 || queueMax > gpuMax * 1.5;
    final bltTailPresent =
        (bltToReadyMax != null && bltToReadyMax > frameBudgetMs * 2.0) ||
        native.gameCaptureNativeNv12BltToReadyOver2xFrames > 0 ||
        native.gameCaptureNativeNv12BltToReadyOver3xFrames > 0 ||
        native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames > 0;
    if (!queueDelayMaterial || !queueDominatesGpu || !bltTailPresent) {
      return null;
    }

    final queueAverageRatio = gpuAverage > 0 ? queueAverage / gpuAverage : null;
    final queueMaxRatio = gpuMax > 0 ? queueMax / gpuMax : null;
    final reasons = <String>[
      'native NV12 VideoProcessorBlt estimated GPU queue delay averaged '
          '${queueAverage.toStringAsFixed(1)}ms and peaked at '
          '${queueMax.toStringAsFixed(1)}ms while GPU execution averaged '
          '${gpuAverage.toStringAsFixed(1)}ms and peaked at '
          '${gpuMax.toStringAsFixed(1)}ms',
      if (bltToReadyMax != null)
        'native NV12 VideoProcessorBlt-to-ready peaked at '
            '${bltToReadyMax.toStringAsFixed(1)}ms for a '
            '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
    ];
    final evidence = <String>[
      if (queueAverageRatio != null)
        'estimated GPU queue delay averaged '
            '${queueAverageRatio.toStringAsFixed(1)}x measured GPU execution',
      if (queueMaxRatio != null)
        'estimated GPU queue delay peak was '
            '${queueMaxRatio.toStringAsFixed(1)}x measured GPU execution peak',
      if (bltToReadyAverage != null && bltToReadyMax != null)
        'VideoProcessorBlt-to-ready averaged '
            '${bltToReadyAverage.toStringAsFixed(1)}ms and peaked at '
            '${bltToReadyMax.toStringAsFixed(1)}ms',
      if (native.gameCaptureNativeNv12BltToReadyOver1xFrames > 0 ||
          native.gameCaptureNativeNv12BltToReadyOver2xFrames > 0 ||
          native.gameCaptureNativeNv12BltToReadyOver3xFrames > 0)
        'BLT-to-ready over-budget counts '
            '${native.gameCaptureNativeNv12BltToReadyOver1xFrames}/'
            '${native.gameCaptureNativeNv12BltToReadyOver2xFrames}/'
            '${native.gameCaptureNativeNv12BltToReadyOver3xFrames}',
      if (native.gameCaptureNativeNv12NotReadyPolls > 0)
        'native NV12 readiness polled not-ready '
            '${native.gameCaptureNativeNv12NotReadyPolls} times',
      if (native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames > 0)
        'GPU queue backoff triggered '
            '${native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames} '
            'times and suppressed '
            '${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames} '
            'frames',
      if (native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames > 0)
        'GPU queue backoff suppressed '
            '${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames} '
            'fresh frames',
      if (native.gameCaptureNativeNv12SingleInFlightDeferredFrames > 0)
        'single-in-flight admission deferred '
            '${native.gameCaptureNativeNv12SingleInFlightDeferredFrames} '
            'frames',
      if (native.gameCaptureSourceToSubmitSamples > 0 &&
          native.averageGameCaptureSourceToSubmitMs != null &&
          native.maxGameCaptureSourceToSubmitMs != null)
        'source-to-submit averaged '
            '${native.averageGameCaptureSourceToSubmitMs!.toStringAsFixed(1)}ms '
            'and peaked at '
            '${native.maxGameCaptureSourceToSubmitMs!.toStringAsFixed(1)}ms',
      if (native.averageEncoderTotalMs != null)
        'native MediaFoundation encoder timing averaged '
            '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
            'with ${native.encoderSlowFrameCount}/'
            '${native.encoderSampleCount} slow samples',
    ];

    return StreamTestBottleneck(
      label: 'native_nv12_gpu_queue_delay_limited',
      reasons: reasons,
      confidence: evidence.length >= 3 ? 'high' : 'medium',
      evidenceFor: [...reasons, ...evidence],
      evidenceAgainstFalseCauses: [
        'VideoProcessorBlt GPU execution was '
            '${gpuAverage.toStringAsFixed(1)}ms avg / '
            '${gpuMax.toStringAsFixed(1)}ms max, below the estimated queue '
            'delay',
        'native NV12 WebRTC source submitted '
            '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
            '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (evidence) =>
                  !evidence.startsWith('native MediaFoundation encoder timing'),
            )
            .toList(growable: false),
      ],
      missingFields: const [],
      recommendedNextAction: 'inspect GPU scheduling and conversion admission',
    );
  }

  static StreamTestBottleneck? _gameCaptureNativeNv12ReadyBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0) {
      return null;
    }

    final reasons = <String>[];
    final evidence = <String>[];
    final readyDrops = native.gameCaptureNativeNv12ReadyDroppedFrames;
    final readyDroppedFresh =
        native.gameCaptureNativeNv12ReadyDroppedFreshFrames;
    if (readyDrops >
            max(10, native.gameCaptureNativeNv12SubmittedFrames ~/ 50) ||
        readyDroppedFresh > 0) {
      reasons.add(
        'native NV12 ready queue dropped $readyDrops frames'
        '${readyDroppedFresh > 0 ? ' ($readyDroppedFresh fresh)' : ''}',
      );
    }

    final convertAverage = native.averageGameCaptureNativeNv12ConvertMs;
    final convertMax = native.maxGameCaptureNativeNv12ConvertMs;
    if (native.gameCaptureNativeNv12ConvertSamples > 0 &&
        convertAverage != null &&
        convertMax != null &&
        (convertAverage > frameBudgetMs * 0.75 ||
            convertMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'native NV12 readiness averaged '
        '${convertAverage.toStringAsFixed(1)}ms and peaked at '
        '${convertMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }

    final bltToReadyMax =
        native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    if (native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 &&
        bltToReadyMax != null &&
        bltToReadyMax > frameBudgetMs * 2.0) {
      reasons.add(
        'native NV12 VideoProcessorBlt-to-ready peaked at '
        '${bltToReadyMax.toStringAsFixed(1)}ms',
      );
    }
    final conversionStartAgeAvg =
        native.averageGameCaptureNativeNv12ConversionStartAgeMs;
    final conversionStartAgeMax =
        native.maxGameCaptureNativeNv12ConversionStartAgeMs;
    if (native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 &&
        conversionStartAgeAvg != null &&
        conversionStartAgeMax != null &&
        (conversionStartAgeAvg > frameBudgetMs ||
            conversionStartAgeMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'native NV12 conversion admission saw source age average '
        '${conversionStartAgeAvg.toStringAsFixed(1)}ms and peak '
        '${conversionStartAgeMax.toStringAsFixed(1)}ms',
      );
    }

    if (reasons.isEmpty) {
      return null;
    }

    if (native.gameCaptureNativeNv12NotReadyPolls > 0) {
      evidence.add(
        'native NV12 readiness polled not-ready '
        '${native.gameCaptureNativeNv12NotReadyPolls} times',
      );
    }
    if (native.gameCaptureDeliveryPacerResyncs > 0) {
      evidence.add(
        'delivery pacer resynced '
        '${native.gameCaptureDeliveryPacerResyncs} times '
        '(max lag ${native.gameCaptureDeliveryPacerLagMaxMs}ms)',
      );
    }
    if (readyDroppedFresh > 0) {
      evidence.add(
        'native NV12 ready drain dropped $readyDroppedFresh fresh frames',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDropAgeSamples > 0 &&
        native.maxGameCaptureNativeNv12ReadyDropAgeMs != null) {
      evidence.add(
        'native NV12 ready-drop max source age '
        '${native.maxGameCaptureNativeNv12ReadyDropAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12BgraScaleDrawSamples > 0 &&
        native.averageGameCaptureNativeNv12BgraScaleDrawMs != null &&
        native.maxGameCaptureNativeNv12BgraScaleDrawMs != null) {
      evidence.add(
        'BGRA scale draw averaged '
        '${native.averageGameCaptureNativeNv12BgraScaleDrawMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12BgraScaleDrawMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltSubmitSamples > 0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs != null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs != null) {
      evidence.add(
        'VideoProcessorBlt submit averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples > 0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs !=
            null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs !=
            null) {
      evidence.add(
        'VideoProcessorBlt GPU execution averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples >
            0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs !=
            null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs !=
            null) {
      evidence.add(
        'VideoProcessorBlt estimated GPU queue delay averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint > 0) {
      evidence.add(
        'VideoProcessorBlt GPU timestamp counters fail/not_ready/disjoint '
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures}/'
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady}/'
        '${native.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint}',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs != null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs != null) {
      evidence.add(
        'VideoProcessorBlt-to-ready averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12BufferCreateSamples > 0 &&
        native.averageGameCaptureNativeNv12BufferCreateMs != null) {
      evidence.add(
        'native NV12 buffer creation averaged '
        '${native.averageGameCaptureNativeNv12BufferCreateMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12FrameReadyToQueueSamples > 0 &&
        native.averageGameCaptureNativeNv12FrameReadyToQueueMs != null) {
      evidence.add(
        'native frame ready-to-queue averaged '
        '${native.averageGameCaptureNativeNv12FrameReadyToQueueMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 &&
        native.averageGameCaptureNativeNv12ConversionStartAgeMs != null &&
        native.maxGameCaptureNativeNv12ConversionStartAgeMs != null) {
      evidence.add(
        'native conversion admission source age averaged '
        '${native.averageGameCaptureNativeNv12ConversionStartAgeMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12ConversionStartAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12StaleBeforeQueueFrames > 0) {
      evidence.add(
        'native NV12 skipped '
        '${native.gameCaptureNativeNv12StaleBeforeQueueFrames} stale frames '
        'before queueing',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }

    return StreamTestBottleneck(
      label: 'native_nv12_ready_limited',
      reasons: reasons,
      confidence: evidence.length >= 2 ? 'high' : 'medium',
      evidenceFor: [...reasons, ...evidence],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        'native NV12 WebRTC source submitted '
            '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
            '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (evidence) =>
                  !evidence.startsWith('native MediaFoundation encoder timing'),
            )
            .toList(growable: false),
      ],
      missingFields:
          native.gameCaptureNativeNv12VideoProcessorBltToReadySamples == 0
          ? const ['native NV12 split timing substages']
          : const [],
      recommendedNextAction: 'fix game-capture handoff',
    );
  }

  static StreamTestBottleneck?
  _gameCaptureAveragePassWithNativeTailReviewBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required StreamTestTemporalAnalysis temporalAnalysis,
    required double? frameBudgetMs,
    required double targetFps,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        targetFps <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureNativeNv12NotReadyPolls > 0 ||
        native.gameCaptureNativeNv12ReadyDroppedFrames > 0 ||
        native.gameCaptureNativeNv12ReadyDroppedFreshFrames > 0 ||
        native.gameCaptureNativeNv12FenceSignalFailures > 0 ||
        native.encoderNativeReadyFenceTimeoutFrames > 0 ||
        native.encoderNativeSampleFailures > 0 ||
        native.webrtcSourceAdapterDrops > 0 ||
        temporalAnalysis.hasLateDegradation ||
        _resolutionLimitNotApplied(summary) ||
        native.isNativeEncoderOverBudgetFor(frameBudgetMs)) {
      return null;
    }

    final fpsValues = <double?>[
      summary.averageCaptureFps,
      summary.averageEncodeFps,
      summary.averageSendFps,
    ];
    if (fpsValues.any((fps) => fps == null || fps <= targetFps * 0.95)) {
      return null;
    }

    final loss = summary.maxPacketLossPercent;
    final rtt = summary.maxRoundTripTimeMs;
    final nack = summary.maxNackCount;
    if (loss == null ||
        rtt == null ||
        nack == null ||
        loss > 1.0 ||
        rtt > 150 ||
        nack > 8) {
      return null;
    }

    if (native.gameCaptureDeliveryOnFrameCallSamples <= 0 ||
        native.averageGameCaptureDeliveryOnFrameCallMs == null ||
        native.maxGameCaptureDeliveryOnFrameCallMs == null ||
        native.averageGameCaptureDeliveryOnFrameCallMs! > frameBudgetMs ||
        native.maxGameCaptureDeliveryOnFrameCallMs! > frameBudgetMs * 2.0) {
      return null;
    }

    if (native.encoderNativeReadyFenceWaitSamples <= 0 ||
        native.averageEncoderNativeReadyFenceWaitMs == null ||
        native.maxEncoderNativeReadyFenceWaitMs == null ||
        native.averageEncoderNativeReadyFenceWaitMs! > frameBudgetMs * 0.25 ||
        native.maxEncoderNativeReadyFenceWaitMs! > frameBudgetMs) {
      return null;
    }

    final fenceHealthy =
        native.gameCaptureNativeNv12FenceAvailable != false &&
        native.gameCaptureNativeNv12FenceSignaledFrames > 0;
    final sourceAdapterHealthy =
        native.hasWebrtcRawSenderBoundaryDiagnostics &&
        native.webrtcSourceAdapterDrops == 0;
    if (!fenceHealthy || !sourceAdapterHealthy) {
      return null;
    }

    final nativeTailEvidence = _nativeTailSpikeReviewEvidence(
      native: native,
      frameBudgetMs: frameBudgetMs,
    );
    if (nativeTailEvidence.isEmpty) {
      return null;
    }

    final fpsEvidence =
        'capture/encode/send averages meet the ${targetFps.toStringAsFixed(0)}fps target '
        '(capture ${_number(summary.averageCaptureFps)}fps, encode '
        '${_number(summary.averageEncodeFps)}fps, send '
        '${_number(summary.averageSendFps)}fps)';
    final cleanNativeEvidence =
        'native NV12 path is clean: submitted '
        '${native.gameCaptureNativeNv12SubmittedFrames}, failures '
        '${native.gameCaptureNativeNv12Failures}, CPU fallback '
        '${native.gameCaptureCpuFallbackFrames}, not-ready polls '
        '${native.gameCaptureNativeNv12NotReadyPolls}, ready drops '
        '${native.gameCaptureNativeNv12ReadyDroppedFrames}, source adapter drops '
        '${native.webrtcSourceAdapterDrops}';

    return StreamTestBottleneck(
      label: 'healthy',
      reasons: [
        fpsEvidence,
        'native_tail_spike_review: isolated native/source max tails remain '
            'diagnostic-only because clean averages and sender handoff '
            'evidence show no sustained send-FPS impact',
      ],
      confidence: 'high',
      evidenceFor: [
        fpsEvidence,
        cleanNativeEvidence,
        'WebRTC OnFrame call '
            '${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)}/'
            '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)} and '
            'MF fence wait '
            '${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
            '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)} are '
            'under budget',
        ...nativeTailEvidence,
      ],
      evidenceAgainstFalseCauses: [
        'native readiness counters are clean despite max-tail evidence',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (evidence) =>
                  !evidence.startsWith('native MediaFoundation encoder timing'),
            )
            .toList(growable: false),
      ],
      recommendedNextAction: 'no stream change recommended',
    );
  }

  static List<String> _nativeTailSpikeReviewEvidence({
    required StreamTestNativeDiagnostics native,
    required double frameBudgetMs,
  }) {
    final tails = <String>[];
    void addTail({
      required String label,
      required double? averageMs,
      required double? maxMs,
      required int samples,
      required double multiplier,
    }) {
      if (samples <= 0 ||
          maxMs == null ||
          maxMs <= frameBudgetMs * multiplier) {
        return;
      }
      tails.add('$label ${_milliseconds(averageMs)}/${_milliseconds(maxMs)}');
    }

    addTail(
      label: 'BGRA scale',
      averageMs: native.averageGameCaptureNativeNv12BgraScaleDrawMs,
      maxMs: native.maxGameCaptureNativeNv12BgraScaleDrawMs,
      samples: native.gameCaptureNativeNv12BgraScaleDrawSamples,
      multiplier: 2.0,
    );
    addTail(
      label: 'VideoProcessorBlt submit',
      averageMs: native.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      maxMs: native.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      samples: native.gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
      multiplier: 2.0,
    );
    addTail(
      label: 'VideoProcessorBlt GPU execution',
      averageMs:
          native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
      maxMs: native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
      samples: native.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples,
      multiplier: 2.0,
    );
    addTail(
      label: 'VideoProcessorBlt estimated GPU queue delay',
      averageMs: native
          .averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
      maxMs: native
          .maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
      samples: native
          .gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples,
      multiplier: 2.0,
    );
    addTail(
      label: 'VideoProcessorBlt-to-ready',
      averageMs: native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      maxMs: native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      samples: native.gameCaptureNativeNv12VideoProcessorBltToReadySamples,
      multiplier: 2.0,
    );
    addTail(
      label: 'source-to-submit',
      averageMs: native.averageGameCaptureSourceToSubmitMs,
      maxMs: native.maxGameCaptureSourceToSubmitMs,
      samples: native.gameCaptureSourceToSubmitSamples,
      multiplier: 3.0,
    );

    if (tails.isEmpty) {
      return const [];
    }
    return ['native_tail_spike_review: isolated max tails ${tails.join(', ')}'];
  }

  static StreamTestBottleneck?
  _gameCaptureLiveSenderHandoffBackpressureBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
    required double targetFps,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        targetFps <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureDeliveryOnFrameCallSamples <= 0 ||
        native.encoderNativeInputFrames <= 0 ||
        native.encoderNativeReadyFenceWaitSamples <= 0) {
      return null;
    }

    final callAverage = native.averageGameCaptureDeliveryOnFrameCallMs;
    final callMax = native.maxGameCaptureDeliveryOnFrameCallMs;
    if (callAverage == null || callMax == null) {
      return null;
    }
    final onFrameOverBudget =
        callAverage > frameBudgetMs * 0.75 || callMax > frameBudgetMs * 2.0;
    if (!onFrameOverBudget) {
      return null;
    }

    final fenceHealthy =
        native.gameCaptureNativeNv12FenceAvailable != false &&
        native.gameCaptureNativeNv12FenceSignaledFrames > 0 &&
        native.gameCaptureNativeNv12FenceSignalFailures == 0 &&
        native.encoderNativeReadyFenceTimeoutFrames == 0;
    final readyQueueHealthy =
        native.gameCaptureNativeNv12NotReadyPolls == 0 &&
        native.gameCaptureNativeNv12ReadyDroppedFrames == 0 &&
        native.gameCaptureNativeNv12ReadyDroppedFreshFrames == 0 &&
        native.encoderNativeSampleFailures == 0;
    final convertAverage = native.averageGameCaptureNativeNv12ConvertMs;
    final bltReadyAverage =
        native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    final conversionAgeAverage =
        native.averageGameCaptureNativeNv12ConversionStartAgeMs;
    final nativeReadyTimingHealthy =
        (convertAverage == null || convertAverage <= frameBudgetMs * 0.75) &&
        (bltReadyAverage == null || bltReadyAverage <= frameBudgetMs * 0.5) &&
        (conversionAgeAverage == null || conversionAgeAverage <= frameBudgetMs);
    if (!fenceHealthy || !readyQueueHealthy || !nativeReadyTimingHealthy) {
      return null;
    }

    final fpsValues = <double>[
      if (summary.averageCaptureFps != null) summary.averageCaptureFps!,
      if (summary.averageEncodeFps != null) summary.averageEncodeFps!,
      if (summary.averageSendFps != null) summary.averageSendFps!,
    ];
    final liveCadenceSlow = fpsValues.any(
      (fps) => fps > 0 && fps < targetFps * 0.75,
    );
    final nativeEncoderSlow = native.isNativeEncoderOverBudgetFor(
      frameBudgetMs,
    );
    final senderEncodeSlow =
        summary.averageEncodeTimeMs != null &&
        summary.averageEncodeTimeMs! > frameBudgetMs;
    if (!liveCadenceSlow && !nativeEncoderSlow && !senderEncodeSlow) {
      return null;
    }

    final reasons = <String>[
      'live_sender_handoff_backpressure: live WebRTC OnFrame call averaged '
          '${callAverage.toStringAsFixed(1)}ms and peaked at '
          '${callMax.toStringAsFixed(1)}ms for a '
          '${frameBudgetMs.toStringAsFixed(1)}ms frame budget while native '
          'NV12 fences and failures were healthy',
      if (liveCadenceSlow)
        'capture/encode/send cadence stayed below the '
            '${targetFps.toStringAsFixed(0)}fps target '
            '(capture ${_number(summary.averageCaptureFps)}fps, encode '
            '${_number(summary.averageEncodeFps)}fps, send '
            '${_number(summary.averageSendFps)}fps)',
      if (nativeEncoderSlow && native.averageEncoderTotalMs != null)
        'native MediaFoundation timing averaged '
            '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms with '
            '${native.encoderSlowFrameCount}/${native.encoderSampleCount} '
            'slow samples',
    ];
    final evidence = <String>[
      ...reasons,
      'native NV12 fence/ready path: policy '
          '${native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown'}, '
          'fenceAvailable=${native.gameCaptureNativeNv12FenceAvailable}, '
          'fenceSignaled=${native.gameCaptureNativeNv12FenceSignaledFrames}, '
          'notReadyPolls=${native.gameCaptureNativeNv12NotReadyPolls}, '
          'readyDropped=${native.gameCaptureNativeNv12ReadyDroppedFrames}, '
          'failures=${native.gameCaptureNativeNv12Failures}, '
          'cpuFallback=${native.gameCaptureCpuFallbackFrames}',
      'delivery queue wait '
          '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
          '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)} and '
          'source-to-submit '
          '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
          '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}',
      'native frame age at conversion start '
          '${_milliseconds(conversionAgeAverage)}/'
          '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)}',
      'encoder fence wait '
          '${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
          '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)}, '
          'processInput '
          '${_milliseconds(native.averageEncoderProcessInputMs)}/'
          '${_milliseconds(native.maxEncoderProcessInputMs)}, '
          'processOutput '
          '${_milliseconds(native.averageEncoderProcessOutputMs)}/'
          '${_milliseconds(native.maxEncoderProcessOutputMs)}, '
          'encodedCallback '
          '${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
          '${_milliseconds(native.maxEncoderEncodedCallbackMs)}, '
          'callbackWait '
          '${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
          '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)}, '
          'callbackQueueMax=${native.encoderMaxEncodedCallbackQueueDepth}, '
          'callbackDropsMax=${native.encoderMaxEncodedCallbackDrops}, '
          'queueMax=${native.encoderMaxQueueDepth}, '
          'retainedMax=${native.encoderMaxRetainedSamples}, '
          'encodedOutputsMax=${native.encoderMaxEncodedOutputs}',
    ];

    return StreamTestBottleneck(
      label: 'encoder_handoff_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: evidence,
      evidenceAgainstFalseCauses: [
        'native NV12 readiness was healthy: '
            '${native.gameCaptureNativeNv12NotReadyPolls} not-ready polls, '
            '${native.gameCaptureNativeNv12ReadyDroppedFrames} ready drops, '
            '${native.gameCaptureNativeNv12Failures} native failures, '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        'native fence handoff was available/signaled: '
            '${native.gameCaptureNativeNv12FenceAvailable} / '
            '${native.gameCaptureNativeNv12FenceSignaledFrames}',
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (evidence) =>
                  !evidence.startsWith(
                    'native MediaFoundation encoder timing',
                  ) &&
                  !evidence.startsWith('WebRTC average encode time'),
            )
            .toList(growable: false),
      ],
      missingFields: [
        if (native.gameCaptureDeliverySubmitPrepSamples == 0)
          'delivery submit prep timing',
        if (native.gameCaptureDeliveryPostOnFrameSamples == 0)
          'delivery post-OnFrame timing',
        if (native.gameCaptureNativeBufferReleaseSamples == 0)
          'native buffer release timing',
        if (summary.framesDroppedBeforeEncodeMax == null &&
            summary.framesDroppedByEncoderMax == null)
          'sender drop counters',
        if (native.encoderEncodedCallbackSamples == 0)
          'encoded callback timing',
      ],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static StreamTestBottleneck? _gameCaptureOnFrameLimitedBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureSubmittedFrames <= 0 ||
        native.gameCaptureGpuScaledFrames <= 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureDeliveryOnFrameCallSamples <= 0) {
      return null;
    }

    final callAverage = native.averageGameCaptureDeliveryOnFrameCallMs;
    final callMax = native.maxGameCaptureDeliveryOnFrameCallMs;
    if (callAverage == null || callMax == null) {
      return null;
    }

    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitIsDominant =
        queueWaitAverage != null &&
        queueWaitAverage > frameBudgetMs * 0.75 &&
        queueWaitAverage > callAverage;
    final onFrameOverBudget =
        callAverage > frameBudgetMs * 0.75 || callMax > frameBudgetMs * 2.0;
    if (!onFrameOverBudget || queueWaitIsDominant) {
      return null;
    }

    final reasons = <String>[
      'WebRTC OnFrame call averaged ${callAverage.toStringAsFixed(1)}ms '
          'and peaked at ${callMax.toStringAsFixed(1)}ms for a '
          '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
    ];
    final evidence = <String>[...reasons];
    if (native.gameCaptureDeliverySubmitPrepSamples > 0 &&
        native.averageGameCaptureDeliverySubmitPrepMs != null &&
        native.maxGameCaptureDeliverySubmitPrepMs != null) {
      evidence.add(
        'submit prep averaged '
        '${native.averageGameCaptureDeliverySubmitPrepMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliverySubmitPrepMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureDeliveryPostOnFrameSamples > 0 &&
        native.averageGameCaptureDeliveryPostOnFrameMs != null &&
        native.maxGameCaptureDeliveryPostOnFrameMs != null) {
      evidence.add(
        'post-OnFrame cleanup averaged '
        '${native.averageGameCaptureDeliveryPostOnFrameMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliveryPostOnFrameMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeBufferReleaseSamples > 0 &&
        native.averageGameCaptureNativeBufferReleaseMs != null &&
        native.maxGameCaptureNativeBufferReleaseMs != null) {
      evidence.add(
        'native buffer release averaged '
        '${native.averageGameCaptureNativeBufferReleaseMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeBufferReleaseMs!.toStringAsFixed(1)}ms',
      );
    }
    if (queueWaitAverage != null &&
        native.maxGameCaptureDeliveryQueueWaitMs != null) {
      evidence.add(
        'delivery queue wait averaged '
        '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
        '${native.maxGameCaptureDeliveryQueueWaitMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }
    if (native.encoderEncodedCallbackSamples > 0) {
      evidence.add(
        'encoded callback averaged '
        '${_milliseconds(native.averageEncoderEncodedCallbackMs)} and peaked at '
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)} '
        '(async frames ${native.encoderEncodedCallbackAsyncFrames}, '
        'queue max ${native.encoderMaxEncodedCallbackQueueDepth}, '
        'drops max ${native.encoderMaxEncodedCallbackDrops})',
      );
    }

    return StreamTestBottleneck(
      label: 'webrtc_onframe_limited',
      reasons: reasons,
      confidence: callAverage > frameBudgetMs ? 'high' : 'medium',
      evidenceFor: evidence,
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (item) =>
                  !item.startsWith('WebRTC average encode time') &&
                  !item.startsWith('native MediaFoundation encoder timing'),
            )
            .toList(growable: false),
      ],
      missingFields: [
        if (native.gameCaptureDeliverySubmitPrepSamples == 0)
          'delivery submit prep timing',
        if (native.gameCaptureDeliveryPostOnFrameSamples == 0)
          'delivery post-OnFrame timing',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0 &&
            native.gameCaptureNativeBufferReleaseSamples == 0)
          'native buffer release timing',
        if (native.encoderEncodedCallbackSamples == 0)
          'encoded callback timing',
      ],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static StreamTestBottleneck? _gameCaptureDeliveryBackpressureBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureSubmittedFrames <= 0 ||
        native.gameCaptureGpuScaledFrames <= 0 ||
        native.gameCaptureCpuFallbackFrames > 0) {
      return null;
    }

    final reasons = <String>[];
    final evidence = <String>[];
    final nativeNv12SourceActive =
        native.gameCaptureNativeNv12SubmittedFrames > 0 &&
        native.gameCaptureCpuFallbackFrames == 0;
    final readbackIsPrimaryPath =
        !nativeNv12SourceActive ||
        native.gameCaptureReadbackReadyFrames >
            max(10, native.gameCaptureNativeNv12SubmittedFrames ~/ 2);
    final sourceToSubmitAverage = native.averageGameCaptureSourceToSubmitMs;
    final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
    if (native.gameCaptureSourceToSubmitSamples > 0 &&
        sourceToSubmitAverage != null &&
        sourceToSubmitMax != null &&
        (sourceToSubmitAverage > frameBudgetMs * 1.75 ||
            sourceToSubmitMax > frameBudgetMs * 3.0)) {
      reasons.add(
        'game-capture source-to-submit latency averaged '
        '${sourceToSubmitAverage.toStringAsFixed(1)}ms and peaked at '
        '${sourceToSubmitMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }

    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
    if (native.gameCaptureDeliveryQueueWaitSamples > 0 &&
        queueWaitAverage != null &&
        queueWaitMax != null &&
        (queueWaitAverage > frameBudgetMs * 0.75 ||
            queueWaitMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'delivery queue wait averaged '
        '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
        '${queueWaitMax.toStringAsFixed(1)}ms',
      );
    }

    final deliveryWallMax = native.maxGameCaptureDeliveryWallDeltaMs;
    if (native.gameCaptureDeliveryWallSamples > 0 &&
        deliveryWallMax != null &&
        deliveryWallMax > frameBudgetMs * 3.0) {
      reasons.add(
        'delivery wall-clock gap peaked at '
        '${deliveryWallMax.toStringAsFixed(1)}ms',
      );
    }

    if (reasons.isEmpty) {
      return null;
    }

    if (native.gameCaptureDeliveryOverwrittenFrames > 0) {
      evidence.add(
        'delivery queue overwrote '
        '${native.gameCaptureDeliveryOverwrittenFrames} ready frames',
      );
    }
    if (native.gameCaptureDeliveryPacerResyncs > 0) {
      evidence.add(
        'delivery pacer resynced '
        '${native.gameCaptureDeliveryPacerResyncs} times '
        '(max lag ${native.gameCaptureDeliveryPacerLagMaxMs}ms)',
      );
    }
    if (native.gameCaptureDeliveryRepeatNoQueuedFrames > 0) {
      final repeatAge = native.maxGameCaptureDeliveryRepeatSourceAgeMs;
      evidence.add(
        'delivery pacer repeated '
        '${native.gameCaptureDeliveryRepeatNoQueuedFrames} frames with no '
        'fresh queued frame'
        '${repeatAge == null ? '' : ' (max source age ${repeatAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureDeliverySkipNoQueuedFrames > 0) {
      evidence.add(
        'delivery pacer skipped '
        '${native.gameCaptureDeliverySkipNoQueuedFrames} ticks with no fresh '
        'queued frame',
      );
    }
    if (native.gameCaptureDeliveryFreshWakeAfterSkipFrames > 0) {
      evidence.add(
        'delivery woke immediately after skipped ticks '
        '${native.gameCaptureDeliveryFreshWakeAfterSkipFrames} times',
      );
    }
    if (native.gameCaptureDeliveryOnFrameCallSamples > 0 &&
        native.averageGameCaptureDeliveryOnFrameCallMs != null &&
        native.maxGameCaptureDeliveryOnFrameCallMs != null) {
      evidence.add(
        'WebRTC OnFrame call averaged '
        '${native.averageGameCaptureDeliveryOnFrameCallMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliveryOnFrameCallMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureSourceDuplicateSkipAgeSamples > 0 &&
        native.maxGameCaptureSourceDuplicateSkipAgeMs != null) {
      evidence.add(
        'capture loop skipped unchanged source frames with max source age '
        '${native.maxGameCaptureSourceDuplicateSkipAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureDeliveryOverwrittenFreshFrames > 0) {
      final overwriteAge = native.maxGameCaptureDeliveryOverwriteAgeMs;
      evidence.add(
        'delivery queue overwrote '
        '${native.gameCaptureDeliveryOverwrittenFreshFrames} fresh frames'
        '${overwriteAge == null ? '' : ' (max age ${overwriteAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureSourceToQueueSamples > 0 &&
        native.averageGameCaptureSourceToQueueMs != null &&
        native.maxGameCaptureSourceToQueueMs != null) {
      evidence.add(
        'source-to-delivery-queue averaged '
        '${native.averageGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDroppedFrames > 0) {
      evidence.add(
        'native NV12 ready queue dropped '
        '${native.gameCaptureNativeNv12ReadyDroppedFrames} frames',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDroppedFreshFrames > 0) {
      final readyDropAge = native.maxGameCaptureNativeNv12ReadyDropAgeMs;
      evidence.add(
        'native NV12 ready drain dropped '
        '${native.gameCaptureNativeNv12ReadyDroppedFreshFrames} fresh frames'
        '${readyDropAge == null ? '' : ' (max age ${readyDropAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureNativeNv12OverwrittenFreshFrames > 0) {
      final overwriteAge = native.maxGameCaptureNativeNv12OverwriteAgeMs;
      evidence.add(
        'native NV12 ring overwrote '
        '${native.gameCaptureNativeNv12OverwrittenFreshFrames} fresh pending frames'
        '${overwriteAge == null ? '' : ' (max age ${overwriteAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureNativeNv12NotReadyPolls > 0) {
      evidence.add(
        'native NV12 readiness polled not-ready '
        '${native.gameCaptureNativeNv12NotReadyPolls} times',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureSourceToReadbackReadySamples > 0 &&
        native.averageGameCaptureSourceToReadbackReadyMs != null &&
        native.maxGameCaptureSourceToReadbackReadyMs != null) {
      evidence.add(
        'source-to-readback-ready averaged '
        '${native.averageGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureReadbackQueueToMapSamples > 0 &&
        native.averageGameCaptureReadbackQueueToMapMs != null &&
        native.maxGameCaptureReadbackQueueToMapMs != null) {
      evidence.add(
        'readback queue-to-map averaged '
        '${native.averageGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureMapToI420Samples > 0 &&
        native.averageGameCaptureMapToI420Ms != null &&
        native.maxGameCaptureMapToI420Ms != null) {
      evidence.add(
        'map-to-I420 averaged '
        '${native.averageGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ConvertSamples > 0 &&
        native.averageGameCaptureNativeNv12ConvertMs != null &&
        native.maxGameCaptureNativeNv12ConvertMs != null) {
      evidence.add(
        'native NV12 readiness averaged '
        '${native.averageGameCaptureNativeNv12ConvertMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12ConvertMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }

    final falseCauseEvidence = _evidenceAgainstCommonFalseCauses(summary)
        .where(
          (item) =>
              !item.startsWith('WebRTC average encode time') &&
              !item.startsWith('native MediaFoundation encoder timing'),
        )
        .toList(growable: false);

    return StreamTestBottleneck(
      label: 'delivery_queue_limited',
      reasons: [
        ...reasons,
        'encoded/sent FPS can stay near target while displayed frames are '
            'several frame budgets behind the game source',
        'native game-capture delivery/source-to-submit pressure appears before '
            'the generic sender encoder-pipeline label',
      ],
      confidence: evidence.length >= 2 ? 'high' : 'medium',
      evidenceFor: [...reasons, ...evidence],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ...falseCauseEvidence,
      ],
      missingFields: const [],
      recommendedNextAction: 'fix frame pacing',
    );
  }

  static bool _nativeEncoderHandoffLimited(StreamTestSummary summary) {
    final native = summary.nativeDiagnostics;
    if (!native.nativeEncoderHandoffNoOutput) {
      return false;
    }
    if (summary.senderSampleCount == 0) {
      return true;
    }
    final encodeFps = summary.averageEncodeFps;
    final sendFps = summary.averageSendFps;
    return encodeFps == null ||
        encodeFps <= 0.1 ||
        sendFps == null ||
        sendFps <= 0.1 ||
        native.encoderMaxQueueDepth >= max(2, native.encoderSampleCount);
  }

  static StreamTestBottleneck _mediaFoundationEncoderLimitedBottleneck({
    required StreamTestSummary summary,
    required double? frameBudgetMs,
  }) {
    final native = summary.nativeDiagnostics;
    final average = native.averageEncoderTotalMs;
    final budget = frameBudgetMs ?? 33.0;
    final reasons = <String>[
      if (average != null)
        'native MediaFoundation encoder averaged '
            '${average.toStringAsFixed(1)}ms against a '
            '${budget.toStringAsFixed(1)}ms frame budget',
      if (native.encoderSampleCount > 0)
        'native MediaFoundation slow samples '
            '${native.encoderSlowFrameCount}/${native.encoderSampleCount} '
            '(${(native.encoderSlowSampleRatio * 100).toStringAsFixed(1)}%)',
      if (native.encoderInputPaths.isNotEmpty)
        'encoder input path ${native.encoderInputPathLabel}',
    ];
    return StreamTestBottleneck(
      label: 'media_foundation_encoder_limited',
      reasons: reasons,
      confidence: average != null ? 'high' : 'medium',
      evidenceFor: [
        ...reasons,
        if (summary.averageEncodeTimeMs != null)
          'WebRTC average encode time '
              '${summary.averageEncodeTimeMs!.toStringAsFixed(1)}ms',
        if (native.encoderMaxQueueDepth > 0)
          'native encoder queue max ${native.encoderMaxQueueDepth}',
        if (native.encoderMaxRetainedSamples > 0)
          'native encoder retained DXGI samples max '
              '${native.encoderMaxRetainedSamples}',
      ],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where(
              (evidence) =>
                  !evidence.startsWith(
                    'native MediaFoundation encoder timing',
                  ) &&
                  !evidence.startsWith('WebRTC average encode time'),
            )
            .toList(growable: false),
      ],
      missingFields: native.encoderSampleCount == 0
          ? const ['native MediaFoundation encoder timing samples']
          : const [],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static bool _gameCaptureGpuHandoffUnproven(StreamTestSummary summary) {
    final native = summary.nativeDiagnostics;
    if (!native.gameCaptureGpuHandoffUnproven) {
      return false;
    }
    final loss = summary.maxPacketLossPercent ?? 0;
    final rtt = summary.maxRoundTripTimeMs ?? 0;
    final nack = summary.maxNackCount ?? 0;
    return loss <= 1.0 && rtt <= 150 && nack <= 8;
  }

  static StreamTestBottleneck _gameCaptureGpuHandoffUnprovenBottleneck(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final disabledReason = native.gameCaptureNativeNv12HandoffDisabledReason;
    final reasons = [
      if (disabledReason != null)
        'native NV12 encoder handoff disabled: $disabledReason',
      'game-capture GPU scale produced '
          '${native.gameCaptureGpuScaledFrames} frames but native NV12 source '
          'submitted 0',
      if (native.encoderCpuI420InputFrames > 0)
        'Media Foundation consumed CPU I420 input '
            '${native.encoderCpuI420InputFrames} times instead of native NV12',
      if (native.gameCaptureReadbackQueuedFrames > 0 ||
          native.gameCaptureReadbackNotReadyFrames > 0)
        'fallback path used scaled readback '
            '${native.gameCaptureReadbackQueuedFrames}/'
            '${native.gameCaptureReadbackReadyFrames} with '
            '${native.gameCaptureReadbackNotReadyFrames} not-ready maps',
    ];
    return StreamTestBottleneck(
      label: 'gpu_handoff_unproven',
      reasons: reasons,
      confidence: disabledReason == null ? 'medium' : 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        'game-capture source/output '
            '${native.gameCaptureSourceResolutionLabel} -> '
            '${native.gameCaptureOutputResolutionLabel}',
        'game-capture GPU scale failures '
            '${native.gameCaptureGpuScaleFailures} and CPU fallbacks '
            '${native.gameCaptureCpuFallbackFrames}',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('native encoder'))
            .toList(growable: false),
      ],
      missingFields: disabledReason == null
          ? const ['native_nv12_encoder_handoff_disabled reason']
          : const [],
      recommendedNextAction: 'fix game-capture handoff',
    );
  }

  static StreamTestBottleneck _nativeEncoderHandoffLimitedBottleneck(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final reasons = [
      'native NV12 input reached Media Foundation '
          '${native.encoderNativeInputFrames} timing samples',
      'Media Foundation output stayed at ${native.encoderOutputFrames} frames '
          'and ${native.encoderOutputBytes} bytes',
      'encoder queue reached ${native.encoderMaxQueueDepth} pending frames '
          'with ${native.encoderMaxRetainedSamples} retained DXGI samples',
      if (native.encoderNativeSuspendedFrames > 0)
        'native NV12 input was suspended '
            '${native.encoderNativeSuspendedFrames} times',
      if (summary.senderSampleCount == 0)
        'no sender stats were collected after the native handoff marker',
    ];
    return StreamTestBottleneck(
      label: 'encoder_handoff_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        'native sample creation failures: '
            '${native.encoderNativeSampleFailures}',
        if (native.gameCaptureGpuScaledFrames > 0)
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches ${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('native encoder'))
            .toList(growable: false),
      ],
      missingFields: const [],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static List<String> _classificationMissingFields(StreamTestSummary summary) {
    final missing = <String>{
      if (summary.averageCaptureFps == null) 'capture FPS',
      if (summary.averageEncodeFps == null) 'encode FPS',
      if (summary.averageSendFps == null) 'send FPS',
      if (summary.preEncodeSampleCount == 0) 'pre-encode dimensions',
      if (summary.averageEncodeTimeMs == null) 'average encode time',
      if (summary.framesDroppedByEncoderMax == null) 'encoder dropped frames',
      if (summary.maxPacketLossPercent == null) 'packet loss',
      if (summary.maxRoundTripTimeMs == null) 'RTT',
      if (summary.maxNackCount == null) 'NACK count',
      if (!summary.nativeDiagnostics.hasEvidence) 'native capture markers',
      if (!summary.framePacing.rendered.hasEvidence) 'receiver render FPS',
    };
    return missing.toList(growable: false)..sort();
  }

  static List<String> _evidenceAgainstCommonFalseCauses(
    StreamTestSummary summary,
  ) {
    final evidence = <String>[];
    final loss = summary.maxPacketLossPercent;
    final rtt = summary.maxRoundTripTimeMs;
    final nack = summary.maxNackCount;
    if (loss != null && rtt != null && nack != null) {
      if (loss <= 1.0 && rtt <= 150 && nack <= 8) {
        evidence.add(
          'network evidence is clean: loss=${loss.toStringAsFixed(1)}%, '
          'RTT=${rtt.toStringAsFixed(0)}ms, NACK=$nack',
        );
      }
    }
    final native = summary.nativeDiagnostics;
    if (summary.averageEncodeTimeMs != null) {
      evidence.add(
        'WebRTC average encode time is '
        '${summary.averageEncodeTimeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null &&
        !native.isNativeEncoderOverBudgetFor(33.0)) {
      evidence.add(
        'native MediaFoundation encoder timing is '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms avg',
      );
    }
    if (native.gameCaptureNativeNv12SubmittedFrames > 0) {
      evidence.add(
        'native NV12 source submission is active: '
        '${native.gameCaptureNativeNv12SubmittedFrames} frames, '
        '${native.gameCaptureNativeNv12Failures} failures, '
        '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
      );
    }
    if (native.encoderInputPaths.isNotEmpty) {
      evidence.add(
        'native encoder input path ${native.encoderInputPathLabel}; '
        'native=${native.encoderNativeInputFrames}, '
        'cpu_i420=${native.encoderCpuI420InputFrames}, '
        'native_sample_failures=${native.encoderNativeSampleFailures}',
      );
    }
    if (summary.requestedResolutionLabel != 'unknown' &&
        summary.encodedResolutionLabel != 'unknown' &&
        !_resolutionLimitNotApplied(summary)) {
      evidence.add(
        'resolution cap appears applied: requested '
        '${summary.requestedResolutionLabel}, encoded '
        '${summary.encodedResolutionLabel}',
      );
    }
    if (summary.activeLayers.isEmpty ||
        !summary.activeLayers.any(_isDowngradedLayer)) {
      evidence.add('no downgraded sender layer was reported');
    }
    return evidence;
  }

  static bool _stageFpsTracks(double? value, double reference) {
    if (value == null || value <= 0 || reference <= 0) {
      return true;
    }
    return value >= reference * 0.8 && value <= reference * 1.25;
  }

  static double _effectiveFpsRatio({
    required StreamTestSummary summary,
    required double targetFps,
    required double? averageFps,
  }) {
    if (targetFps <= 0) {
      return 0;
    }
    var ratio = averageFps == null || averageFps <= 0
        ? 0.0
        : averageFps / targetFps;
    final frameBudgetMs = 1000 / targetFps;
    for (final stage in _senderPacingStages(summary)) {
      final p95IntervalMs = stage.p95IntervalMs;
      if (p95IntervalMs != null && p95IntervalMs > 0) {
        ratio = min(ratio, (1000 / p95IntervalMs) / targetFps);
      }
      final maxIntervalMs = stage.maxIntervalMs;
      if (maxIntervalMs != null && maxIntervalMs > frameBudgetMs * 3) {
        ratio = min(ratio, (frameBudgetMs * 3) / maxIntervalMs);
      }
      if (stage.staleFrameReuseCount > 0) {
        ratio = min(ratio, 0.49);
      }
    }
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  static List<String> _framePacingReasons({
    required StreamTestSummary summary,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null || frameBudgetMs <= 0) {
      return const [];
    }
    final reasons = <String>[];
    for (final stage in _senderPacingStages(summary)) {
      final p95IntervalMs = stage.p95IntervalMs;
      if (p95IntervalMs != null && p95IntervalMs > frameBudgetMs * 1.15) {
        reasons.add(
          '${stage.stage} p95 frame interval '
          '${p95IntervalMs.toStringAsFixed(0)}ms exceeds '
          '${frameBudgetMs.toStringAsFixed(0)}ms target cadence',
        );
      }
      final maxIntervalMs = stage.maxIntervalMs;
      if (maxIntervalMs != null && maxIntervalMs > frameBudgetMs * 3) {
        reasons.add(
          '${stage.stage} max frame gap '
          '${maxIntervalMs.toStringAsFixed(0)}ms exceeds '
          '${frameBudgetMs.toStringAsFixed(0)}ms target cadence',
        );
      }
      if (stage.staleFrameReuseCount > 0) {
        reasons.add(
          '${stage.stage} had ${stage.staleFrameReuseCount} stale '
          'frame-counter window(s)',
        );
      }
      if (reasons.length >= 3) {
        break;
      }
    }
    return reasons;
  }

  static List<StreamTestFramePacingStageSummary> _senderPacingStages(
    StreamTestSummary summary,
  ) {
    final pacing = summary.framePacing;
    return [pacing.sent, pacing.encoded, pacing.capture, pacing.nativeCapture];
  }

  static bool _resolutionLimitNotApplied(StreamTestSummary summary) {
    final requestedWidth = summary.requestedWidth;
    final requestedHeight = summary.requestedHeight;
    final encodedWidth = summary.encodedWidth;
    final encodedHeight = summary.encodedHeight;
    if (requestedWidth == null ||
        requestedHeight == null ||
        encodedWidth == null ||
        encodedHeight == null ||
        requestedWidth <= 0 ||
        requestedHeight <= 0 ||
        encodedWidth <= 0 ||
        encodedHeight <= 0) {
      return false;
    }

    final widthTooLarge =
        encodedWidth > requestedWidth + 32 &&
        encodedWidth > requestedWidth * 1.1;
    final heightTooLarge =
        encodedHeight > requestedHeight + 18 &&
        encodedHeight > requestedHeight * 1.1;
    return widthTooLarge || heightTooLarge;
  }
}

class StreamTestBottleneck {
  const StreamTestBottleneck({
    required this.label,
    this.reasons = const [],
    this.confidence = 'medium',
    this.missingFields = const [],
    this.evidenceFor = const [],
    this.evidenceAgainstFalseCauses = const [],
    this.recommendedNextAction = 'collect one specific missing field',
  });

  final String label;
  final List<String> reasons;
  final String confidence;
  final List<String> missingFields;
  final List<String> evidenceFor;
  final List<String> evidenceAgainstFalseCauses;
  final String recommendedNextAction;

  List<String> get effectiveEvidenceFor =>
      evidenceFor.isEmpty ? reasons : evidenceFor;

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'reasons': reasons,
      'confidence': confidence,
      'missingFields': missingFields,
      'evidenceFor': effectiveEvidenceFor,
      'evidenceAgainstFalseCauses': evidenceAgainstFalseCauses,
      'recommendedNextAction': recommendedNextAction,
    };
  }
}
