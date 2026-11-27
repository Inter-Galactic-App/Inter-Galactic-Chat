part of 'stream_test_runner.dart';

class StreamTestPresetResult {
  StreamTestPresetResult({
    required this.profile,
    required this.startedAt,
    required this.endedAt,
    required this.samples,
    DateTime? diagnosticStartedAt,
    DateTime? diagnosticEndedAt,
    this.windowsCaptureBackendMode,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureMode,
    this.error,
    this.nativeDiagnostics = const StreamTestNativeDiagnostics(),
    this.diagnosticLogMarkers = const [],
    this.receiverProbeResult,
    List<String>? analysisDiagnosticLogMarkers,
  }) : diagnosticStartedAt = diagnosticStartedAt ?? startedAt,
       diagnosticEndedAt = diagnosticEndedAt ?? endedAt,
       score = StreamTestScore.fromSamples(
         profile: profile,
         samples: samples,
         error: error,
         nativeDiagnostics: nativeDiagnostics,
         diagnosticLogMarkers:
             analysisDiagnosticLogMarkers ?? diagnosticLogMarkers,
         measurementStartedAt: startedAt,
         measurementEndedAt: diagnosticEndedAt ?? endedAt,
       );

  final ScreenShareProfileConfig profile;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime diagnosticStartedAt;
  final DateTime diagnosticEndedAt;
  final List<StreamTestSample> samples;
  final String? error;
  final StreamTestNativeDiagnostics nativeDiagnostics;
  final List<String> diagnosticLogMarkers;
  final StreamTestReceiverProbeResult? receiverProbeResult;
  final StreamTestScore score;

  String get backendSelectionLabel =>
      windowsCaptureBackendMode?.label ?? 'App default';

  String get windowGdiSelectionLabel =>
      windowsWindowGdiCaptureMode?.label ?? 'Default window GDI';

  String get nativeBackendLabel {
    final backend = nativeDiagnostics.backendLabel;
    if (backend == 'unknown') {
      return backendSelectionLabel;
    }
    return backend;
  }

  String get resultLabel => '$backendSelectionLabel / ${profile.label}';

  StreamDiagnosticCoverageMatrix get diagnosticCoverage =>
      StreamDiagnosticCoverageMatrix.forPreset(this);

  StreamTestPresetResult withNativeDiagnostics(
    StreamTestNativeDiagnostics diagnostics,
  ) {
    return StreamTestPresetResult(
      profile: profile,
      windowsCaptureBackendMode: windowsCaptureBackendMode,
      windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
      startedAt: startedAt,
      endedAt: endedAt,
      diagnosticStartedAt: diagnosticStartedAt,
      diagnosticEndedAt: diagnosticEndedAt,
      samples: samples,
      error: error,
      nativeDiagnostics: diagnostics,
      diagnosticLogMarkers: diagnosticLogMarkers,
      receiverProbeResult: receiverProbeResult,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'profile': _profileToJson(profile),
      'windowsCaptureBackendMode': windowsCaptureBackendMode?.constraintValue,
      'windowsCaptureBackendSelection':
          windowsCaptureBackendMode?.label ?? 'App default',
      'windowsCaptureDirtyRegionMode':
          windowsCaptureDirtyRegionMode.constraintValue,
      'windowsCaptureDirtyRegionSelection': windowsCaptureDirtyRegionMode.label,
      'windowsWindowGdiCaptureMode':
          windowsWindowGdiCaptureMode?.constraintValue,
      'windowsWindowGdiCaptureSelection': windowGdiSelectionLabel,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'diagnosticStartedAt': diagnosticStartedAt.toUtc().toIso8601String(),
      'diagnosticEndedAt': diagnosticEndedAt.toUtc().toIso8601String(),
      'durationMs': endedAt.difference(startedAt).inMilliseconds,
      'error': error,
      'nativeDiagnostics': nativeDiagnostics.toJson(),
      'receiverProbe': receiverProbeResult?.toJson(),
      'subjectiveNotes': '',
      'diagnosticCoverage': diagnosticCoverage.toJson(),
      'score': score.toJson(),
      'summary': score.summary.toJson(),
      'timeWindows': score.temporalAnalysis.toJson(),
      'samples': samples.map((sample) => sample.toJson()).toList(),
    };
  }
}

class StreamTestRunResult {
  const StreamTestRunResult({
    required this.startedAt,
    required this.endedAt,
    required this.targetLabel,
    required this.roomId,
    required this.config,
    required this.presetResults,
    this.error,
    this.diagnosticLogMarkers = const [],
    this.loadedLibwebrtcArtifact,
    this.gameCaptureTestTargetResult,
    this.gameCaptureProbeResult,
    this.hostLoadReport,
  });

  factory StreamTestRunResult.failure({
    required DateTime startedAt,
    required DateTime endedAt,
    required String targetLabel,
    required String roomId,
    required StreamTestRunConfig config,
    required String error,
    String diagnosticLogText = '',
    int diagnosticLogMarkerLimit = streamTestDefaultDiagnosticLogMarkerLimit,
    StreamTestLoadedLibwebrtcArtifact? loadedLibwebrtcArtifact,
    GameCaptureTestTargetResult? gameCaptureTestTargetResult,
    GameCaptureProbeResult? gameCaptureProbeResult,
    StreamTestHostLoadReport? hostLoadReport,
  }) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: const [],
      error: Log.redactSensitiveInfo(error),
      diagnosticLogMarkers: streamTestDiagnosticMarkersFromText(
        diagnosticLogText,
        limit: diagnosticLogMarkerLimit,
      ),
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: hostLoadReport,
    );
  }

  final DateTime startedAt;
  final DateTime endedAt;
  final String targetLabel;
  final String roomId;
  final StreamTestRunConfig config;
  final List<StreamTestPresetResult> presetResults;
  final String? error;
  final List<String> diagnosticLogMarkers;
  final StreamTestLoadedLibwebrtcArtifact? loadedLibwebrtcArtifact;
  final GameCaptureTestTargetResult? gameCaptureTestTargetResult;
  final GameCaptureProbeResult? gameCaptureProbeResult;
  final StreamTestHostLoadReport? hostLoadReport;

  StreamDiagnosticCoverageMatrix get diagnosticCoverage =>
      StreamDiagnosticCoverageMatrix.forRun(this);

  StreamTestPresetResult? get primaryResult {
    if (presetResults.isEmpty) {
      return null;
    }
    final candidates = presetResults
        .where((result) => result.score.bottleneck.label != 'healthy')
        .toList(growable: false);
    final considered = (candidates.isEmpty ? presetResults : candidates)
        .toList();
    considered.sort((a, b) => a.score.totalScore.compareTo(b.score.totalScore));
    return considered.first;
  }

  String get recommendedNextAction {
    final probe = gameCaptureProbeResult;
    if (probe != null && probe.hasSlowPublicationHandoff) {
      return 'fix game-capture handoff';
    }
    return primaryResult?.score.bottleneck.recommendedNextAction ??
        'collect one specific missing field';
  }

  StreamTestRunResult withGameCaptureTestTargetResult(
    GameCaptureTestTargetResult? result,
  ) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: presetResults,
      error: error,
      diagnosticLogMarkers: diagnosticLogMarkers,
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: result,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: hostLoadReport,
    );
  }

  StreamTestRunResult withHostLoadReport(StreamTestHostLoadReport? report) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: presetResults,
      error: error,
      diagnosticLogMarkers: diagnosticLogMarkers,
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: report,
    );
  }

  Map<String, Object?> toJson() {
    final configJson = config.toJson();
    configJson['receiverProbe'] = config.receiverProbe.toDiagnosticJson();
    return {
      'schema': 'intergalactic.streamTestRun.v1',
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'durationMs': endedAt.difference(startedAt).inMilliseconds,
      'targetLabel': _redactedFreeformLabel(targetLabel),
      'roomId': _redactedRoomId(roomId),
      'config': configJson,
      'error': error == null ? null : Log.redactSensitiveInfo(error!),
      'diagnosticCoverage': diagnosticCoverage.toJson(),
      'recommendedNextAction': recommendedNextAction,
      'loadedLibwebrtc': loadedLibwebrtcArtifact?.toJson(),
      'hostLoad': hostLoadReport?.toJson(),
      'diagnosticLogMarkers': diagnosticLogMarkers
          .map(_redactedDiagnosticMarker)
          .toList(),
      'gameCaptureTestTarget': gameCaptureTestTargetResult?.toJson(),
      'gameCaptureProbe': gameCaptureProbeResult?.toJson(),
      'presetResults': presetResults.map((result) => result.toJson()).toList(),
    };
  }

  String toJsonText() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toMarkdown() {
    final coverage = diagnosticCoverage;
    final primary = primaryResult;
    final buffer = StringBuffer()
      ..writeln('# Inter Galactic Stream Test Run')
      ..writeln()
      ..writeln('- Started: ${startedAt.toLocal()}')
      ..writeln('- Ended: ${endedAt.toLocal()}')
      ..writeln('- Scenario: ${_redactedFreeformLabel(config.scenarioLabel)}')
      ..writeln('- Target: ${_redactedFreeformLabel(targetLabel)}')
      ..writeln('- Room: ${_redactedRoomId(roomId)}')
      ..writeln('- Source: ${config.sourceMetadata?.label ?? 'unknown'}')
      ..writeln('- Run status: ${error == null ? 'completed' : 'failed'}')
      ..writeln(
        '- Windows capture backend: '
        '${config.windowsCaptureBackendSelectionLabel}',
      )
      ..writeln(
        '- Native dirty-region mode: '
        '${config.windowsCaptureDirtyRegionMode.label}',
      )
      ..writeln(
        '- Window GDI capture methods: '
        '${config.windowsWindowGdiSelectionLabel}',
      )
      ..writeln(
        '- Native latest-frame pacer: '
        '${config.nativeFramePacingEnabled ? 'enabled' : 'disabled'}',
      )
      ..writeln('- Preset duration: ${config.durationPerPreset.inSeconds}s')
      ..writeln('- Warmup before sampling: ${config.warmupDuration.inSeconds}s')
      ..writeln('- Sample interval: ${config.sampleInterval.inSeconds}s')
      ..writeln(
        '- Score: stable_fps + target_resolution + low_loss + low_rtt - downgrade_penalty',
      )
      ..writeln(
        '- Stable FPS scoring uses average FPS capped by sampled sender/native frame pacing, with p95/max frame gaps reflected in the score.',
      )
      ..writeln()
      ..writeln('## Executive Summary')
      ..writeln()
      ..writeln(
        '- Primary classification: '
        '${primary?.score.bottleneck.label ?? 'insufficient_evidence'} '
        '(${primary?.score.bottleneck.confidence ?? 'insufficient'} confidence)',
      )
      ..writeln(
        '- Primary bottleneck: '
        '${primary == null ? 'no preset results' : primary.resultLabel}',
      )
      ..writeln('- Recommended next action: $recommendedNextAction')
      ..writeln(
        '- Run error: ${error == null ? 'none' : Log.redactSensitiveInfo(error!)}',
      )
      ..writeln(
        '- Missing evidence: '
        '${coverage.missingFields.isEmpty ? 'none' : coverage.missingFields.join('; ')}',
      );
    if (loadedLibwebrtcArtifact != null) {
      buffer.writeln(
        '- Loaded libwebrtc: ${loadedLibwebrtcArtifact!.diagnosticLabel}',
      );
    }
    if (hostLoadReport != null) {
      buffer.writeln('- Host load: ${_hostLoadCompactLabel(hostLoadReport!)}');
    }
    if (gameCaptureProbeResult?.hasSlowPublicationHandoff == true) {
      buffer.writeln(
        '- Game-capture handoff: slow at '
        '${_number(gameCaptureProbeResult!.publicationHandoffOutputFps)}fps '
        'for target '
        '${gameCaptureProbeResult!.publicationHandoffRequestedTargetFps ?? gameCaptureProbeResult!.config.publicationHandoffTargetFps}fps',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Diagnostic Coverage')
      ..writeln()
      ..write(coverage.toMarkdownTable())
      ..writeln()
      ..writeln('## Host/System Load')
      ..writeln();
    if (hostLoadReport == null) {
      buffer.writeln('Host/system load diagnostics were not collected.');
    } else {
      buffer.write(_hostLoadMarkdown(hostLoadReport!));
    }

    buffer
      ..writeln()
      ..writeln('## Game Capture Test Target')
      ..writeln();
    if (gameCaptureTestTargetResult == null) {
      buffer.writeln(
        'No deterministic D3D11 capture target was requested for this run.',
      );
    } else {
      buffer.write(gameCaptureTestTargetResult!.toMarkdown());
    }

    buffer
      ..writeln()
      ..writeln('## Game Capture Probe')
      ..writeln();
    if (gameCaptureProbeResult == null) {
      buffer.writeln('No D3D11 game-capture probe was requested for this run.');
    } else {
      buffer.write(gameCaptureProbeResult!.toMarkdown());
    }

    buffer
      ..writeln()
      ..writeln('## Receiver Probe')
      ..writeln();
    if (!config.receiverProbe.enabled) {
      buffer.writeln(
        'No in-process true-receiver probe was requested for this run.',
      );
    } else {
      buffer
        ..writeln(
          '| Preset | Backend | Mode | Status | Source | Events | Decode | Renderer Callback | Unique FPS | Quality / Presentation |',
        )
        ..writeln(
          '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |',
        );
      for (final result in presetResults) {
        final probe = result.receiverProbeResult;
        final uniqueFps = probe?.latestUniqueFps;
        final source = probe?.latestFreshnessSource ?? '?';
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.backendSelectionLabel)} '
          '| ${_markdownCell(probe?.mode.label ?? config.receiverProbe.mode.label)} '
          '| ${_markdownCell(probe?.status ?? 'not_recorded')} '
          '| ${_markdownCell(source)} '
          '| ${probe?.events.length ?? 0} '
          '| ${probe?.remoteDecodeEventCount ?? 0} '
          '| ${probe?.remoteRendererCallbackEventCount ?? 0} '
          '| ${_number(uniqueFps)} '
          '| ${_markdownCell(probe?.latestQualityMarkdownLabel ?? 'n/a')} |',
        );
      }
      buffer.writeln(
        'Stats-only receiver probe events remain inconclusive until frame_hash_tap reports unique_fps. The legacy remote_render lane is reported as remote_renderer_callback; Phase 4 receiver probes can also report remote_texture_ready, remote_ui_paint, and external receiver-window remote_screen_present frame-timing events when the diagnostic renderer texture is bound to the Flutter surface. remote_screen_present is presentation cadence evidence, not source-linked visual-content freshness by itself. Quality/presentation fields distinguish low layer/bitrate, stale content, and uneven callback cadence.',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln(
        '| Preset | Backend | GDI Mode | Capturer | Bottleneck | Score | Capture FPS | Encode FPS | Send FPS | Encoded | Pre-encode | Encode Time | Bitrate | Loss | RTT | Limit | Penalty |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | ---: |',
      );

    for (final result in presetResults) {
      final summary = result.score.summary;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_markdownCell(result.windowGdiSelectionLabel)} '
        '| ${_markdownCell(summary.nativeDiagnostics.observedCapturerLabel)} '
        '| ${_markdownCell(result.score.bottleneck.label)} '
        '| ${result.score.totalScore} '
        '| ${_number(summary.averageCaptureFps)} '
        '| ${_number(summary.averageEncodeFps)} '
        '| ${_number(summary.averageSendFps)} '
        '| ${summary.encodedResolutionLabel} '
        '| ${summary.preEncodeResolutionLabel} '
        '| ${_milliseconds(summary.averageEncodeTimeMs)} '
        '| ${_bitrate(summary.averageBitrateBps)} '
        '| ${_percent(summary.maxPacketLossPercent)} '
        '| ${_milliseconds(summary.maxRoundTripTimeMs)} '
        '| ${_markdownCell(summary.qualityLimitationReasonsLabel)} '
        '| ${result.score.downgradePenalty} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Frame Pacing')
      ..writeln()
      ..writeln(
        'Sampled stages are derived from cumulative WebRTC frame counters at the runner sample cadence. Native capture uses native cadence markers when present.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Native Capture | Capture | Pre-encode | Encoded | Sent | Received | Decoded | Rendered |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final pacing = result.score.summary.framePacing;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_markdownCell(pacing.nativeCapture.markdownLabel)} '
        '| ${_markdownCell(pacing.capture.markdownLabel)} '
        '| ${_markdownCell(pacing.preEncode.markdownLabel)} '
        '| ${_markdownCell(pacing.encoded.markdownLabel)} '
        '| ${_markdownCell(pacing.sent.markdownLabel)} '
        '| ${_markdownCell(pacing.received.markdownLabel)} '
        '| ${_markdownCell(pacing.decoded.markdownLabel)} '
        '| ${_markdownCell(pacing.rendered.markdownLabel)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Visual Freshness Diagnostics')
      ..writeln()
      ..writeln(
        'This block separates submitted/encoded FPS from distinct visible-frame cadence. Missing data means the report cannot prove whether the receiver/output looked smooth.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Visual Freshness | Source Proof | Receiver/Output Proof |',
      )
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final result in presetResults) {
      final native = result.score.summary.nativeDiagnostics;
      final sourceProof =
          'pre-I420 ${native.gameCaptureProofFrames}/'
          '${native.gameCaptureVisibleProofFrames}; I420 '
          '${native.gameCaptureI420ProofFrames}/'
          '${native.gameCaptureVisibleI420ProofFrames}; '
          'visibleSourceSeen=${native.gameCaptureVisibleSourceSeen ?? '?'}';
      final outputProof = native.hasGameCaptureVisualFreshnessEvidence
          ? 'artifact=${native.gameCaptureVisualFreshnessArtifactSet ?? '?'}'
          : 'missing';
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_markdownCell(native.gameCaptureVisualFreshnessLabel)} '
        '| ${_markdownCell(sourceProof)} '
        '| ${_markdownCell(outputProof)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Sender Handoff Diagnostics')
      ..writeln()
      ..writeln(
        'This block follows the live D3D11 game-hook sender boundary: WebRTC OnFrame call duration, source/broadcaster dispatch, VideoStreamEncoder queue/encode timing, native NV12 fence/readiness, Media Foundation input/output timing, and sender drop counters.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | OnFrame Call | Native Frame Age | Delivery Queue | Native Ready | WebRTC Raw Sender | Media Foundation | Sender Counters | Missing Fields |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final summary = result.score.summary;
      final native = summary.nativeDiagnostics;
      final missing = summary.senderHandoffDiagnosticMissingFields;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)} avg / '
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)} max / '
        '${native.gameCaptureDeliveryOnFrameCallSamples} samples '
        '| ${_milliseconds(native.averageGameCaptureNativeNv12ConversionStartAgeMs)} avg / '
        '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)} max / '
        '${native.gameCaptureNativeNv12ConversionStartAgeSamples} samples '
        '| wait ${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)}; '
        'source-submit ${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)} '
        '| deliveryDepth=${native.gameCaptureDeliveryQueueDepth ?? '?'} '
        'readyDrain=${native.gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'policy=${_markdownCell(native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown')} '
        'ownership=${_markdownCell(native.gameCaptureNativeNv12FrameOwnership ?? 'unknown')} '
        'singleFlight=${native.gameCaptureNativeNv12SingleInFlightEnabled ?? '?'} '
        'defer=${native.gameCaptureNativeNv12SingleInFlightDeferredFrames}/'
        '${native.gameCaptureNativeNv12SingleInFlightDeferredFreshFrames} '
        'pendingMax=${native.gameCaptureNativeNv12SingleInFlightPendingMax} '
        'deferAge=${_milliseconds(native.averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs)} '
        'gpuBackoff=${native.gameCaptureNativeNv12GpuQueueBackoffEnabled ?? '?'} '
        'trigger=${native.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames} '
        'suppress=${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames}/'
        '${native.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames} '
        'backoff=${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffMs)} '
        'triggerBlt=${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)} '
        'suppressAge=${_milliseconds(native.averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)} '
        'ownedCopy=${native.gameCaptureNativeNv12OwnedCopies} '
        '${_milliseconds(native.averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12OwnedCopyMs)} '
        'bltCpu=${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)} '
        'bltFence=${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)} '
        'bltGpu=${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)} '
        'bltQueue=${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)} '
        'fence=${native.gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'signaled=${native.gameCaptureNativeNv12FenceSignaledFrames} '
        'notReady=${native.gameCaptureNativeNv12NotReadyPolls} '
        'readyDropped=${native.gameCaptureNativeNv12ReadyDroppedFrames} '
        'observed=immediate:${native.gameCaptureNativeNv12ReadyObservedImmediateFrames} '
        'post:${native.gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames} '
        'event:${native.gameCaptureNativeNv12ReadyObservedFenceEventFrames} '
        'source:${native.gameCaptureNativeNv12ReadyObservedSourceEventFrames} '
        'idle:${native.gameCaptureNativeNv12ReadyObservedLoopIdleFrames} '
        'late>${native.gameCaptureNativeNv12BltToReadyOver1xFrames}/'
        '${native.gameCaptureNativeNv12BltToReadyOver2xFrames}/'
        '${native.gameCaptureNativeNv12BltToReadyOver3xFrames} '
        'failures=${native.gameCaptureNativeNv12Failures} '
        'cpuFallback=${native.gameCaptureCpuFallbackFrames} '
        '| ${_markdownCell(native.webrtcRawSenderBoundaryLabel)} '
        '| total ${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)}; '
        'fenceWait ${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
        '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)}; '
        'input ${_milliseconds(native.averageEncoderProcessInputMs)}/'
        '${_milliseconds(native.maxEncoderProcessInputMs)}; '
        'output ${_milliseconds(native.averageEncoderProcessOutputMs)}/'
        '${_milliseconds(native.maxEncoderProcessOutputMs)}; '
        'callback ${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)}; '
        'callbackWait ${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)}; '
        'callbackEnqueue ${_milliseconds(native.averageEncoderEncodedCallbackEnqueueMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackEnqueueMs)}; '
        'callbackQueue=${native.encoderMaxEncodedCallbackQueueDepth}; '
        'callbackDrops=${native.encoderMaxEncodedCallbackDrops}; '
        'callbackOutputs=${native.encoderMaxEncodedCallbackOutputs}; '
        'queue=${native.encoderMaxQueueDepth}; '
        'retained=${native.encoderMaxRetainedSamples}; '
        'encodedOutputs=${native.encoderMaxEncodedOutputs} '
        '| droppedBeforeEncode=${summary.framesDroppedBeforeEncodeMax ?? '?'}; '
        'droppedByEncoder=${summary.framesDroppedByEncoderMax ?? '?'}; '
        'frames=${summary.framesCapturedMax ?? '?'}/'
        '${summary.framesEncodedMax ?? '?'}/${summary.framesSentMax ?? '?'} '
        '| ${_markdownCell(missing.isEmpty ? 'none' : missing.join(', '))} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Time-Window Degradation')
      ..writeln()
      ..writeln(
        'These windows split the sampled run so a stream that starts smooth and decays later is visible without manually reading raw counters.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Window | Samples | Capture FPS | Encode FPS | Send FPS | Sent Gap | Render FPS | Native Submitted | D3D11 Readback | Signals |',
      )
      ..writeln(
        '| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final temporal = result.score.temporalAnalysis;
      if (!temporal.hasEvidence) {
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.backendSelectionLabel)} '
          '| none | 0 | ? | ? | ? | ? | ? | ? | ? | no time-window evidence |',
        );
        continue;
      }
      for (final window in temporal.windows) {
        final framePacing = window.framePacing;
        final gameCapture = window.gameCapture;
        final windowSignals = <String>[
          if (temporal.hasLateDegradation &&
              (window.label == 'late' || window.label == 'tail_10s'))
            ...temporal.lateDegradationSignals,
        ];
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.backendSelectionLabel)} '
          '| ${_markdownCell('${window.label} ${window.offsetLabel}')} '
          '| ${window.sampleCount} '
          '| ${_number(window.summary.averageCaptureFps)} '
          '| ${_number(window.summary.averageEncodeFps)} '
          '| ${_number(window.summary.averageSendFps)} '
          '| ${_milliseconds(framePacing.sent.p95IntervalMs)} p95 / '
          '${_milliseconds(framePacing.sent.maxIntervalMs)} max '
          '| ${_number(framePacing.rendered.averageFps)} '
          '| ${_markdownCell(gameCapture == null ? 'native window unavailable' : '${_number(gameCapture.submittedFps)}fps (+${gameCapture.submittedDelta})')} '
          '| ${_markdownCell(gameCapture?.compactLabel ?? 'native window unavailable')} '
          '| ${_markdownCell(windowSignals.isEmpty ? 'none' : windowSignals.join('; '))} |',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('## Capture Cause Attribution')
      ..writeln()
      ..writeln(
        'These fields split native capture-call cost into the likely causes being investigated. `unknown` means the current log did not contain that evidence.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Full Source Acquisition | Blocking Acquire Wait | CPU Readback / Copy | Dirty-Region Processing | Frame Lifetime / Lock / Sync | Full-Frame Copy Before Downscale |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final result in presetResults) {
      final native = result.nativeDiagnostics;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.nativeBackendLabel)} '
        '| ${_markdownCell(native.fullSourceAcquisitionAttributionLabel)} '
        '| ${_markdownCell(native.blockingAcquireAttributionLabel)} '
        '| ${_markdownCell(native.cpuReadbackAttributionLabel)} '
        '| ${_markdownCell(native.dirtyRegionProcessingAttributionLabel)} '
        '| ${_markdownCell(native.frameLifetimeSyncAttributionLabel)} '
        '| ${_markdownCell(native.fullFrameCopyBeforeDownscaleAttributionLabel)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Native Diagnostic Markers')
      ..writeln();
    if (presetResults.any((result) => result.nativeDiagnostics.hasEvidence)) {
      buffer
        ..writeln(
          '| Preset | Backend | Observed Capturer | Dirty Mode | Native Source | Window Rect | Content | Pre-encode | Canvas | Native FPS | Submitted FPS | Frame Interval | Dominant Phase | Capture Call | Source Capture | WGC Substage | GDI Substage | Callback Entry | Acquire Wait | Post Callback | Unaccounted Wait | Frame Work | Updated Region | Dirty Shape | Dirty Work | Native Encoder | Crop |',
        )
        ..writeln(
          '| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
        );
      for (final result in presetResults) {
        final native = result.nativeDiagnostics;
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.nativeBackendLabel)} '
          '| ${_markdownCell(native.observedCapturerLabel)} '
          '| ${_markdownCell(native.dirtyRegionModeLabel)} '
          '| ${native.nativeSourceResolutionLabel} '
          '| ${native.nativeWindowRectResolutionLabel} '
          '| ${native.contentResolutionLabel} '
          '| ${native.preEncodeResolutionLabel} '
          '| ${_markdownCell(native.canvasLabel)} '
          '| ${_number(native.averageNativeFps)} '
          '| ${_number(native.averageSubmittedFps)} '
          '| ${_milliseconds(native.p95FrameIntervalMs)} p95 / '
          '${_milliseconds(native.maxFrameIntervalMs)} max '
          '| ${_markdownCell(native.dominantCaptureDelayStageLabel)} '
          '| ${_milliseconds(native.averageCaptureCallMs)} avg / '
          '${_milliseconds(native.maxCaptureCallMs)} max '
          '| ${_milliseconds(native.averageSourceCaptureMs)} avg / '
          '${_milliseconds(native.maxSourceCaptureMs)} max '
          '| ${_markdownCell(native.reportWgcFrameSummaryLabel)} '
          '| ${_markdownCell(native.reportGdiFrameSummaryLabel)} '
          '| ${_milliseconds(native.averageCallbackEntryDelayMs)} avg / '
          '${_milliseconds(native.maxCallbackEntryDelayMs)} max '
          '| ${_milliseconds(native.averageCaptureAcquireWaitMs)} avg / '
          '${_milliseconds(native.maxCaptureAcquireWaitMs)} max '
          '| ${_milliseconds(native.averagePostCallbackWaitMs)} avg / '
          '${_milliseconds(native.maxPostCallbackWaitMs)} max '
          '| ${_milliseconds(native.averageUnaccountedWaitMs)} avg / '
          '${_milliseconds(native.maxUnaccountedWaitMs)} max '
          '| ${_milliseconds(native.averageFrameCallbackMs)} callback '
          '(${_milliseconds(native.averageFrameConvertMs)} convert, '
          '${_milliseconds(native.averageFrameScaleMs)} scale, '
          '${_milliseconds(native.averageFrameOnFrameMs)} onFrame) '
          '| ${native.updatedRegionNonEmptyCount} dirty / '
          '${native.updatedRegionEmptyCount} empty '
          '| ${_markdownCell(native.updatedRegionShapeLabel)} '
          '| ${_milliseconds(native.averageUpdatedRegionAnalysisMs)} avg / '
          '${_milliseconds(native.maxUpdatedRegionAnalysisMs)} max '
          '| ${_milliseconds(native.averageEncoderTotalMs)} avg / '
          '${_milliseconds(native.maxEncoderTotalMs)} max '
          '| ${native.cropRegion == null
              ? '?'
              : native.cropRegion!
              ? 'true'
              : 'false'} |',
        );
      }
      buffer.writeln();
    }
    if (diagnosticLogMarkers.isEmpty) {
      buffer.writeln(
        'No matching native capture or encoder log markers were found in the recent diagnostic log tail.',
      );
    } else {
      buffer
        ..writeln('```text')
        ..writeln(
          diagnosticLogMarkers.map(_redactedDiagnosticMarker).join('\n'),
        )
        ..writeln('```');
    }

    for (final result in presetResults) {
      final score = result.score;
      final summary = score.summary;
      buffer
        ..writeln()
        ..writeln('## ${result.resultLabel}')
        ..writeln()
        ..writeln('- Total score: ${score.totalScore}')
        ..writeln('- Requested backend: ${result.backendSelectionLabel}')
        ..writeln('- Native backend: ${result.nativeBackendLabel}')
        ..writeln(
          '- Observed native capturer: '
          '${summary.nativeDiagnostics.observedCapturerLabel}',
        )
        ..writeln(
          '- Native dirty-region mode: '
          '${summary.nativeDiagnostics.dirtyRegionModeLabel}',
        )
        ..writeln('- Applied profile details: ${summary.profileDetailsLabel}')
        ..writeln(
          '- Sender codec/encoder: '
          'codec=${summary.senderCodecsLabel} '
          'engine=${summary.encoderImplementationsLabel} '
          'hw=${summary.hardwareEncodeStatesLabel}',
        )
        ..writeln('- Stable FPS: ${score.stableFps}')
        ..writeln('- Target resolution: ${score.targetResolution}')
        ..writeln('- Low loss: ${score.lowLoss}')
        ..writeln('- Low RTT: ${score.lowRtt}')
        ..writeln('- Downgrade penalty: ${score.downgradePenalty}')
        ..writeln(
          '- Classification: ${score.bottleneck.label} '
          '(${score.bottleneck.confidence} confidence)',
        )
        ..writeln('- Bottleneck: ${score.bottleneck.label}')
        ..writeln(
          '- Bottleneck evidence: '
          '${score.bottleneck.reasons.isEmpty ? 'none' : score.bottleneck.reasons.join('; ')}',
        )
        ..writeln(
          '- Evidence for bottleneck: '
          '${score.bottleneck.effectiveEvidenceFor.isEmpty ? 'none' : score.bottleneck.effectiveEvidenceFor.join('; ')}',
        )
        ..writeln(
          '- Evidence against common false causes: '
          '${score.bottleneck.evidenceAgainstFalseCauses.isEmpty ? 'none' : score.bottleneck.evidenceAgainstFalseCauses.join('; ')}',
        )
        ..writeln(
          '- Missing evidence: '
          '${score.bottleneck.missingFields.isEmpty ? 'none' : score.bottleneck.missingFields.join('; ')}',
        )
        ..writeln(
          '- Recommended next action: '
          '${score.bottleneck.recommendedNextAction}',
        )
        ..writeln(
          '- Average capture FPS: ${_number(summary.averageCaptureFps)}',
        )
        ..writeln(
          '- Minimum capture FPS: ${_number(summary.minimumCaptureFps)}',
        )
        ..writeln('- Average encode FPS: ${_number(summary.averageEncodeFps)}')
        ..writeln('- Minimum encode FPS: ${_number(summary.minimumEncodeFps)}')
        ..writeln('- Average send FPS: ${_number(summary.averageSendFps)}')
        ..writeln('- Minimum send FPS: ${_number(summary.minimumSendFps)}')
        ..writeln('- Average FPS: ${_number(summary.averageFps)}')
        ..writeln('- Minimum FPS: ${_number(summary.minimumFps)}')
        ..writeln('- Average bitrate: ${_bitrate(summary.averageBitrateBps)}')
        ..writeln(
          '- Available outgoing bitrate: '
          '${_bitrate(summary.minimumAvailableOutgoingBitrateBps)} min / '
          '${_bitrate(summary.averageAvailableOutgoingBitrateBps)} avg / '
          '${_bitrate(summary.maximumAvailableOutgoingBitrateBps)} max',
        )
        ..writeln(
          '- Average encode time: '
          '${_milliseconds(summary.averageEncodeTimeMs)}',
        )
        ..writeln(
          '- Max encode time: ${_milliseconds(summary.maxEncodeTimeMs)}',
        )
        ..writeln(
          '- Average packet send delay: '
          '${_milliseconds(summary.averagePacketSendDelayMs)}',
        )
        ..writeln('- Encoded resolution: ${summary.encodedResolutionLabel}')
        ..writeln('- Requested resolution: ${summary.requestedResolutionLabel}')
        ..writeln(
          '- Pre-encode resolution: '
          '${summary.preEncodeResolutionLabel} '
          '(${summary.preEncodeSampleCount}/${summary.senderSampleCount} samples)',
        )
        ..writeln('- Capture pipeline: ${summary.capturePipelineLabel}')
        ..writeln('- Frame pacing: ${summary.framePacing.compactLabel}')
        ..writeln(
          '- Time-window signals: '
          '${score.temporalAnalysis.lateDegradationSignals.isEmpty ? 'none' : score.temporalAnalysis.lateDegradationSignals.join('; ')}',
        )
        ..writeln(
          '- Native capture pipeline: '
          '${summary.nativeDiagnostics.summaryLabel}',
        )
        ..writeln(
          '- Capture output validity: '
          '${summary.nativeDiagnostics.gdiOutputValidityLabel}',
        )
        ..writeln('- Subjective notes: ')
        ..writeln(
          '- Max packet loss: ${_percent(summary.maxPacketLossPercent)}',
        )
        ..writeln('- Max RTT: ${_milliseconds(summary.maxRoundTripTimeMs)}')
        ..writeln(
          '- Quality limitation: ${summary.qualityLimitationReasonsLabel}',
        )
        ..writeln('- Active layers: ${summary.activeLayersLabel}');
      if (result.error != null) {
        buffer.writeln('- Error: `${Log.redactSensitiveInfo(result.error!)}`');
      }
    }

    return buffer.toString();
  }
}

Map<String, Object?> _profileToJson(ScreenShareProfileConfig profile) {
  return {
    'storageKey': profile.storageKey,
    'label': profile.label,
    'description': profile.description,
    'profile': profile.profile?.name,
    'codec': profile.codec,
    'useSimulcast': profile.useSimulcast,
    'hardwareEncodeFirst': profile.hardwareEncodeFirst,
    'advancedOverride': profile.advancedOverride,
    'mainLayer': _layerToJson(profile.mainLayer),
    'lowLayer': profile.lowLayer == null
        ? null
        : _layerToJson(profile.lowLayer!),
  };
}

Map<String, Object?> _layerToJson(ScreenShareVideoLayer layer) {
  return {
    'width': layer.width,
    'height': layer.height,
    'maxFramerate': layer.maxFramerate,
    'targetFramerate': layer.targetFramerateForScoring,
    'maxBitrateBps': layer.maxBitrateBps,
    'minBitrateBps': layer.minBitrateBps,
  };
}

Map<String, Object?> _trackToJson(VoipTrackDiagnostics track) {
  return {
    'streamId': track.streamId,
    'label': track.label,
    'type': track.type.name,
    'direction': track.direction.name,
    'receivePriority': track.receivePriority?.name,
    'requestedWidth': track.requestedWidth,
    'requestedHeight': track.requestedHeight,
    'requestedFps': track.requestedFps,
    'requestedBitrateBps': track.requestedBitrateBps,
    'preEncodeWidth': track.preEncodeWidth,
    'preEncodeHeight': track.preEncodeHeight,
    'width': track.width,
    'height': track.height,
    'fps': track.fps,
    'captureFps': track.captureFps,
    'encodeFps': track.encodeFps,
    'sendFps': track.sendFps,
    'decodeFps': track.decodeFps,
    'renderFps': track.renderFps,
    'bitrateBps': track.bitrateBps,
    'targetBitrateBps': track.targetBitrateBps,
    'availableOutgoingBitrateBps': track.availableOutgoingBitrateBps,
    'availableIncomingBitrateBps': track.availableIncomingBitrateBps,
    'retransmitBitrateBps': track.retransmitBitrateBps,
    'packetsLost': track.packetsLost,
    'packetsSent': track.packetsSent,
    'packetsReceived': track.packetsReceived,
    'nackCount': track.nackCount,
    'pliCount': track.pliCount,
    'firCount': track.firCount,
    'packetLossPercent': track.packetLossPercent,
    'jitterMs': track.jitterMs,
    'jitterBufferDelayMs': track.jitterBufferDelayMs,
    'roundTripTimeMs': track.roundTripTimeMs,
    'codec': track.codec,
    'qualityLimitationReason': track.qualityLimitationReason,
    'framesSent': track.framesSent,
    'framesCaptured': track.framesCaptured,
    'framesEncoded': track.framesEncoded,
    'framesDecoded': track.framesDecoded,
    'framesReceived': track.framesReceived,
    'framesRendered': track.framesRendered,
    'framesDropped': track.framesDropped,
    'framesDroppedBeforeEncode': track.framesDroppedBeforeEncode,
    'framesDroppedByEncoder': track.framesDroppedByEncoder,
    'averageEncodeTimeMs': track.averageEncodeTimeMs,
    'averagePacketSendDelayMs': track.averagePacketSendDelayMs,
    'averageDecodeTimeMs': track.averageDecodeTimeMs,
    'qualityLimitationResolutionChanges':
        track.qualityLimitationResolutionChanges,
    'qualityLimitationDurations': track.qualityLimitationDurations,
    'rid': track.rid,
    'activeLayer': track.activeLayer,
    'encoderImplementation': track.encoderImplementation,
    'decoderImplementation': track.decoderImplementation,
    'hardwareEncodeActive': track.hardwareEncodeActive,
    'freezeCount': track.freezeCount,
    'pauseCount': track.pauseCount,
  };
}

String _hostLoadCompactLabel(StreamTestHostLoadReport report) {
  if (!report.available) {
    return 'unavailable (${report.unavailableReason ?? 'no samples'})';
  }
  return 'samples=${report.samples.length}; '
      'CPU avg/max=${_hostLoadMetricPercent(report.systemCpuPercent)}; '
      'RAM avg/max=${_hostLoadMetricPercent(report.memoryUsedPercent)}; '
      'GPU 3D avg/max=${_hostLoadMetricPercent(report.gpu3dPercent)}; '
      'Video Encode avg/max='
      '${_hostLoadMetricPercent(report.gpuVideoEncodePercent)}; '
      'Video Decode avg/max='
      '${_hostLoadMetricPercent(report.gpuVideoDecodePercent)}';
}

String _hostLoadMarkdown(StreamTestHostLoadReport report) {
  final buffer = StringBuffer();
  if (!report.available) {
    buffer
      ..writeln(
        'Host/system load diagnostics were unavailable: '
        '${report.unavailableReason ?? 'no samples'}.',
      )
      ..writeln();
    return buffer.toString();
  }
  if (report.unavailableReason != null) {
    buffer
      ..writeln(
        'Host/system load diagnostics were collected with warning: '
        '${report.unavailableReason}.',
      )
      ..writeln();
  }
  buffer
    ..writeln('- Samples: ${report.samples.length}')
    ..writeln('- Interval: ${report.sampleIntervalMs}ms')
    ..writeln(
      '- Range: ${report.startedAtUtc?.toIso8601String() ?? '?'} to '
      '${report.endedAtUtc?.toIso8601String() ?? '?'}',
    )
    ..writeln(
      '- Missing metrics: '
      '${report.missingMetricLabels.isEmpty ? 'none' : report.missingMetricLabels.join(', ')}',
    )
    ..writeln()
    ..writeln('| Metric | Samples | Average | Max | Min |')
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  _writeHostLoadMetricRow(
    buffer,
    label: 'System CPU',
    metric: report.systemCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Memory Used',
    metric: report.memoryUsedPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Memory Available',
    metric: report.memoryAvailableMb,
    formatter: (value) => value == null ? '?' : '${value.toStringAsFixed(0)}MB',
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'App CPU',
    metric: report.appCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Target CPU',
    metric: report.targetCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU 3D',
    metric: report.gpu3dPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Copy',
    metric: report.gpuCopyPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Video Encode',
    metric: report.gpuVideoEncodePercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Video Decode',
    metric: report.gpuVideoDecodePercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Compute',
    metric: report.gpuComputePercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Dedicated Memory',
    metric: report.gpuDedicatedMemoryMb,
    formatter: (value) => value == null ? '?' : '${value.toStringAsFixed(0)}MB',
  );
  return buffer.toString();
}

void _writeHostLoadMetricRow(
  StringBuffer buffer, {
  required String label,
  required StreamTestHostLoadMetricSummary metric,
  required String Function(double? value) formatter,
}) {
  buffer.writeln(
    '| ${_markdownCell(label)} '
    '| ${metric.sampleCount} '
    '| ${formatter(metric.average)} '
    '| ${formatter(metric.maximum)} '
    '| ${formatter(metric.minimum)} |',
  );
}

String _hostLoadMetricPercent(StreamTestHostLoadMetricSummary metric) {
  return '${_percent(metric.average)}/${_percent(metric.maximum)}';
}

String _number(double? value) => value == null ? '?' : value.toStringAsFixed(1);

String _percent(double? value) =>
    value == null ? '?' : '${value.toStringAsFixed(1)}%';

String _ratioPercent(double? value) =>
    value == null ? '?' : '${(value * 100).toStringAsFixed(1)}%';

String _milliseconds(double? value) =>
    value == null ? '?' : '${value.toStringAsFixed(0)}ms';

String _bitrate(int? bitrateBps) {
  if (bitrateBps == null || bitrateBps <= 0) {
    return '?';
  }
  if (bitrateBps >= 1000000) {
    return '${(bitrateBps / 1000000).toStringAsFixed(1)} Mbps';
  }
  return '${(bitrateBps / 1000).toStringAsFixed(0)} kbps';
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _markdownInline(String value) {
  return value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _resolutionLabel(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 'unknown';
  }
  return '${width}x$height';
}

double? _pixelRatio(
  int? numeratorWidth,
  int? numeratorHeight,
  int? denominatorWidth,
  int? denominatorHeight,
) {
  if (numeratorWidth == null ||
      numeratorHeight == null ||
      denominatorWidth == null ||
      denominatorHeight == null ||
      numeratorWidth <= 0 ||
      numeratorHeight <= 0 ||
      denominatorWidth <= 0 ||
      denominatorHeight <= 0) {
    return null;
  }
  return (numeratorWidth * numeratorHeight) /
      (denominatorWidth * denominatorHeight);
}

String _megapixels(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return '?MP';
  }
  return '${(width * height / 1000000).toStringAsFixed(2)}MP';
}

String _ratioMultiplier(double? ratio) =>
    ratio == null ? '?' : '${ratio.toStringAsFixed(2)}x';
