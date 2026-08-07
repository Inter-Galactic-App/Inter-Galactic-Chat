part of 'stream_test_runner.dart';

enum StreamDiagnosticCoverageStatus {
  available,
  missing,
  unavailable,
  notApplicable,
}

class StreamDiagnosticCoverageItem {
  const StreamDiagnosticCoverageItem({
    required this.category,
    required this.status,
    required this.detail,
    this.missingFields = const [],
  });

  final String category;
  final StreamDiagnosticCoverageStatus status;
  final String detail;
  final List<String> missingFields;

  String get statusName {
    switch (status) {
      case StreamDiagnosticCoverageStatus.available:
        return 'available';
      case StreamDiagnosticCoverageStatus.missing:
        return 'missing';
      case StreamDiagnosticCoverageStatus.unavailable:
        return 'unavailable';
      case StreamDiagnosticCoverageStatus.notApplicable:
        return 'notApplicable';
    }
  }

  String get markdownMarker {
    switch (status) {
      case StreamDiagnosticCoverageStatus.available:
        return '[PASS]';
      case StreamDiagnosticCoverageStatus.missing:
        return '[WARN]';
      case StreamDiagnosticCoverageStatus.unavailable:
        return '[FAIL]';
      case StreamDiagnosticCoverageStatus.notApplicable:
        return '[N/A]';
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'status': statusName,
      'detail': detail,
      'missingFields': missingFields,
    };
  }
}

class StreamDiagnosticCoverageMatrix {
  const StreamDiagnosticCoverageMatrix(this.items);

  factory StreamDiagnosticCoverageMatrix.forRun(StreamTestRunResult result) {
    final sourceItem = result.config.sourceMetadata == null
        ? const StreamDiagnosticCoverageItem(
            category: 'source metadata',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: 'stream-test source metadata was not captured',
            missingFields: ['source type', 'source id hash'],
          )
        : StreamDiagnosticCoverageItem(
            category: 'source metadata',
            status: StreamDiagnosticCoverageStatus.available,
            detail: result.config.sourceMetadata!.label,
          );
    final requestedItem = result.config.presets.isEmpty
        ? const StreamDiagnosticCoverageItem(
            category: 'requested settings',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: 'no stream-test presets were configured',
            missingFields: ['profile name', 'target width', 'target FPS'],
          )
        : StreamDiagnosticCoverageItem(
            category: 'requested settings',
            status: StreamDiagnosticCoverageStatus.available,
            detail: result.config.presets
                .map((profile) =>
                    '${profile.label} ${profile.mainLayer.resolutionLabel}@${profile.mainLayer.diagnosticFramerateLabel}')
                .join(', '),
          );
    final perPresetMatrices = result.presetResults
        .map((preset) => preset.diagnosticCoverage)
        .toList(growable: false);
    return StreamDiagnosticCoverageMatrix([
      sourceItem,
      requestedItem,
      _gameCaptureTestTargetCoverage(result),
      _gameCaptureProbeCoverage(result),
      _receiverProbeCoverage(result),
      _receiverProbeQualityCoverage(result),
      _receiverProbePresentationStageCoverage(result),
      _loadedLibwebrtcArtifactCoverage(result),
      _hostLoadCoverage(result),
      ..._mergePerPresetCoverage(perPresetMatrices),
    ]);
  }

  factory StreamDiagnosticCoverageMatrix.forPreset(
    StreamTestPresetResult result,
  ) {
    return StreamDiagnosticCoverageMatrix.forSummary(result.score.summary);
  }

  factory StreamDiagnosticCoverageMatrix.forSummary(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final wgcObserved =
        native.observedCapturerLabel.toLowerCase().contains('wgc') ||
            native.backendLabel.toLowerCase().contains('wgc');
    final gdiObserved =
        native.observedCapturerLabel.toLowerCase().contains('window-gdi') ||
            native.observedCapturerLabel.toLowerCase().contains('windowgdi') ||
            native.observedCapturerLabel.toLowerCase().contains('wingdi');
    final gameHookObserved =
        native.observedCapturerLabel.toLowerCase().contains('game-d3d11') ||
            native.gameCaptureSubmittedFrames > 0 ||
            native.gameCaptureSourceFrameIndex > 0;
    final causeAttribution = native.captureCauseAttribution;
    final missingCauseFields = <String>[
      if (causeAttribution['fullSourceAcquisition'] == 'unknown')
        'source/acquisition size attribution',
      if (causeAttribution['blockingAcquireWait'] == 'unknown')
        'blocking acquire wait attribution',
      if (causeAttribution['cpuReadbackOrCopy'] == 'unknown')
        'CPU readback/copy attribution',
      if (causeAttribution['dirtyRegionProcessing'] == 'unknown')
        'dirty-region processing attribution',
      if (causeAttribution['frameLifetimeOrSynchronization'] == 'unknown')
        'frame lifetime/lock synchronization attribution',
      if (causeAttribution['fullFrameCopyBeforeDownscale'] == 'unknown')
        'pre-downscale full-frame copy attribution',
    ];
    final items = <StreamDiagnosticCoverageItem>[
      if (summary.requestedWidth != null ||
          summary.requestedHeight != null ||
          summary.requestedFps != null ||
          summary.requestedBitrateBps != null ||
          summary.screenShareProfileDetails.isNotEmpty)
        StreamDiagnosticCoverageItem(
          category: 'requested settings',
          status: StreamDiagnosticCoverageStatus.available,
          detail: summary.requestedResolutionLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'requested settings',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'requested sender settings were not present in stats',
          missingFields: [
            'requested width',
            'requested height',
            'requested FPS',
            'requested bitrate',
          ],
        ),
      if (summary.senderSampleCount > 0)
        StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              '${summary.senderSampleCount} sender samples; encoded ${summary.encodedResolutionLabel}; send ${_number(summary.averageSendFps)}fps',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'no sender screenshare stats were collected',
          missingFields: [
            'sender track stats',
            'encoded frame size',
            'send FPS',
            'send bitrate',
          ],
        ),
      native.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'native capture markers',
              status: StreamDiagnosticCoverageStatus.available,
              detail: native.summaryLabel,
            )
          : const StreamDiagnosticCoverageItem(
              category: 'native capture markers',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'no parsed native capture markers were present',
              missingFields: [
                'native capture cadence',
                'native source size',
                'native pre-encode size',
              ],
            ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureBackendContractVersion != null &&
          native.gameCaptureSourceApi != null &&
          native.gameCaptureSourceFormat != null &&
          native.gameCaptureSyncKind != null &&
          native.gameCaptureReadyState != null &&
          native.gameCaptureFailureReason != null)
        StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'v${native.gameCaptureBackendContractVersion} '
              'api=${native.gameCaptureSourceApi} '
              'format=${native.gameCaptureSourceFormat} '
              'sync=${native.gameCaptureSyncKind} '
              'ready=${native.gameCaptureReadyState} '
              'failure=${native.gameCaptureFailureReason}',
        )
      else
        StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include backend-neutral contract fields',
          missingFields: [
            if (native.gameCaptureBackendContractVersion == null)
              'game-capture backend contract version',
            if (native.gameCaptureSourceApi == null) 'game-capture source API',
            if (native.gameCaptureSourceFormat == null)
              'game-capture source format',
            if (native.gameCaptureSyncKind == null) 'game-capture sync kind',
            if (native.gameCaptureReadyState == null)
              'game-capture ready state',
            if (native.gameCaptureFailureReason == null)
              'game-capture failure reason',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureSourceFrameIndex > 0 ||
          native.gameCaptureLastSubmittedSourceFrameIndex > 0 ||
          native.gameCaptureSourceFrameRegressions > 0 ||
          native.gameCaptureSharedSlotMismatches > 0 ||
          native.gameCaptureTimestampMode != null ||
          native.gameCaptureTimestampSamples > 0 ||
          native.gameCaptureDeliveryWallSamples > 0 ||
          native.gameCaptureSourceQpcSamples > 0 ||
          native.gameCaptureSourceLatestObservedFrames > 0 ||
          native.gameCaptureSourceLatestQpcSamples > 0 ||
          native.gameCaptureSourceLatestObservationSamples > 0 ||
          native.gameCaptureSourceLatestEventAgeSamples > 0 ||
          native.gameCaptureSourcePublishObservationAgeSamples > 0 ||
          native.gameCaptureProducerPresentGapSamples > 0 ||
          native.gameCaptureProducerCaptureGapSamples > 0 ||
          native.gameCaptureProducerPresentToPublishSamples > 0 ||
          native.gameCaptureProducerCopySamples > 0 ||
          native.gameCaptureProducerResolveSamples > 0 ||
          native.gameCaptureProducerThrottledFrames > 0 ||
          native.gameCaptureNativeAdmissionDeadlineDueFrames > 0)
        StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'source=${native.gameCaptureSourceFrameIndex}; '
              'lastSubmitted='
              '${native.gameCaptureLastSubmittedSourceFrameIndex}; '
              'regressions=${native.gameCaptureSourceFrameRegressions}; '
              'slotMismatches=${native.gameCaptureSharedSlotMismatches}; '
              'timestamp=${native.gameCaptureTimestampMode ?? 'unknown'}; '
              'timestampMax='
              '${_milliseconds(native.maxGameCaptureTimestampDeltaMs)}; '
              'deliveryWallMax='
              '${_milliseconds(native.maxGameCaptureDeliveryWallDeltaMs)}; '
              'sourceQpcMax='
              '${_milliseconds(native.maxGameCaptureSourceQpcDeltaMs)}; '
              'sourceQpcOver='
              '${native.gameCaptureSourceQpcOver2xFrames}/'
              '${native.gameCaptureSourceQpcOver3xFrames}; '
              'sourceLatestObserved='
              '${native.gameCaptureSourceLatestObservedFrames}; '
              'sourceLatestGaps='
              '${native.gameCaptureSourceLatestFrameGaps}; '
              'sourceLatestQpcMax='
              '${_milliseconds(native.maxGameCaptureSourceLatestQpcDeltaMs)}; '
              'sourceLatestObservationMax='
              '${_milliseconds(native.maxGameCaptureSourceLatestObservationDeltaMs)}; '
              'sourceLatestEventAgeMax='
              '${_milliseconds(native.maxGameCaptureSourceLatestEventAgeMs)}; '
              'sourcePublishObservationAgeMax='
              '${_milliseconds(native.maxGameCaptureSourcePublishObservationAgeMs)}; '
              'sourcePublishObservationAgeOver='
              '${native.gameCaptureSourcePublishObservationAgeOver1xFrames}/'
              '${native.gameCaptureSourcePublishObservationAgeOver2xFrames}/'
              '${native.gameCaptureSourcePublishObservationAgeOver3xFrames}; '
              'producerPresentGapMax='
              '${_milliseconds(native.maxGameCaptureProducerPresentGapMs)}; '
              'producerCaptureGapMax='
              '${_milliseconds(native.maxGameCaptureProducerCaptureGapMs)}; '
              'producerPresentToPublishMax='
              '${_milliseconds(native.maxGameCaptureProducerPresentToPublishMs)}; '
              'producerCopyMax='
              '${_milliseconds(native.maxGameCaptureProducerCopyMs)}; '
              'producerResolveMax='
              '${_milliseconds(native.maxGameCaptureProducerResolveMs)}; '
              'producerThrottled='
              '${native.gameCaptureProducerThrottledFrames}; '
              'sourceLatestOver='
              '${native.gameCaptureSourceLatestQpcOver2xFrames}/'
              '${native.gameCaptureSourceLatestQpcOver3xFrames}; '
              'admissionDeadlineDue='
              '${native.gameCaptureNativeAdmissionDeadlineDueFrames}; '
              'admissionDeadlineMax='
              '${_milliseconds(native.maxGameCaptureNativeAdmissionDeadlineLatenessMs)}; '
              'deadlineNv12Ready/noReady='
              '${native.gameCaptureNativeNv12ReadyOnDeadlineFrames}/'
              '${native.gameCaptureNativeNv12NoReadyOnDeadlineFrames}; '
              'timestampAdjustments='
              '${native.gameCaptureTimestampAdjustments}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include frame-order or timestamp fields',
          missingFields: [
            'source frame index',
            'last submitted source frame index',
            'source frame regression count',
            'shared slot mismatch count',
            'delivery timestamp delta',
            'delivery wall-clock delta',
            'source QPC delta',
            'source latest observation cadence',
            'producer source publish cadence',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureSourceToSubmitSamples > 0 &&
          native.gameCaptureSourceToI420ReadySamples > 0 &&
          native.gameCaptureSourceToQueueSamples > 0)
        StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'source->readbackReady='
              '${_milliseconds(native.averageGameCaptureSourceToReadbackReadyMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToReadbackReadyMs)}; '
              'readbackQueue->map='
              '${_milliseconds(native.averageGameCaptureReadbackQueueToMapMs)}/'
              '${_milliseconds(native.maxGameCaptureReadbackQueueToMapMs)}; '
              'map->I420='
              '${_milliseconds(native.averageGameCaptureMapToI420Ms)}/'
              '${_milliseconds(native.maxGameCaptureMapToI420Ms)}; '
              'source->I420='
              '${_milliseconds(native.averageGameCaptureSourceToI420ReadyMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToI420ReadyMs)}; '
              'source->queue='
              '${_milliseconds(native.averageGameCaptureSourceToQueueMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToQueueMs)}; '
              'source->submit='
              '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include enough source/readback/I420 handoff split fields',
          missingFields: [
            'source to readback-ready timing',
            'readback queue to map timing',
            'map to I420 timing',
            'source to I420-ready timing',
            'source to delivery queue timing',
          ],
        ),
      if (native.hasEvidence && missingCauseFields.isEmpty)
        StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              'source/acquire/readback/dirty/sync/pre-downscale-copy buckets are populated',
        )
      else if (native.hasEvidence)
        StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native markers are present but one or more capture-cause buckets are incomplete',
          missingFields: missingCauseFields,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      if (!wgcObserved)
        const StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'WGC was not the observed native capturer',
        )
      else if (native.wgcFrameSummaryLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.wgcFrameSummaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'WGC capturer was observed without substage timing',
          missingFields: [
            'TryGetNextFrame timing',
            'Map timing',
            'row copy timing',
            'frame-pool empty count',
          ],
        ),
      if (!gdiObserved)
        const StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'window-GDI was not the observed native capturer',
        )
      else if (native.gdiFrameSummaryLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.gdiFrameSummaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'window-GDI capturer was observed without substage timing',
          missingFields: [
            'PrintWindow timing',
            'BitBlt timing',
            'crop timing',
            'owned-window timing',
          ],
        ),
      if (!gdiObserved)
        const StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'window-GDI was not the observed native capturer',
        )
      else if (native.gdiFinalFrameCount > 0)
        StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.gdiOutputValidityLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'window-GDI was observed without final-frame validity counters',
          missingFields: [
            'final producer counts',
            'black frame count',
            'low-variance frame count',
          ],
        ),
      if (native.updatedRegionShapeLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.updatedRegionShapeLabel,
        )
      else if (native.hasEvidence)
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'native markers were present without dirty-region shape',
          missingFields: [
            'updated-region rect count',
            'dirty-area ratio',
            'full-frame update count',
          ],
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      if (native.averageUpdatedRegionAnalysisMs != null ||
          native.maxUpdatedRegionAnalysisMs != null)
        StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.dirtyRegionProcessingAttributionLabel,
        )
      else if (native.hasEvidence)
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native markers were present without updated-region analysis timing',
          missingFields: ['updated-region analysis timing'],
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      summary.framePacing.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'frame pacing',
              status: StreamDiagnosticCoverageStatus.available,
              detail: summary.framePacing.compactLabel,
            )
          : const StreamDiagnosticCoverageItem(
              category: 'frame pacing',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'frame counter cadence was not available',
              missingFields: [
                'framesCaptured counter',
                'framesEncoded counter',
                'framesSent counter',
              ],
            ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'visual freshness cadence',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.hasGameCaptureVisualFreshnessEvidence)
        StreamDiagnosticCoverageItem(
          category: 'visual freshness cadence',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.gameCaptureVisualFreshnessLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'visual freshness cadence',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'sender frame counters do not prove unique visible receiver/output frames',
          missingFields: [
            'visual unique FPS',
            'longest stale visual run',
            'visual low-change frame count',
            'receiver/output proof artifact status',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.hasWebrtcRawSenderBoundaryDiagnostics)
        StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.webrtcRawSenderBoundaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook markers did not include source broadcast, VideoStreamEncoder, or VideoEncoder::Encode boundary timing',
          missingFields: [
            'WebRTC source sink dispatch timing',
            'VideoBroadcaster lock/sink dispatch timing',
            'VideoStreamEncoder OnFrame timing',
            'VideoStreamEncoder adaptation/drop counters',
            'VideoEncoder::Encode timing',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (summary.hasSenderHandoffDiagnostics)
        StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.available,
          detail: summary.senderHandoffDiagnosticsLabel,
          missingFields: summary.senderHandoffDiagnosticMissingFields,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook markers did not include live OnFrame, native frame age, encoder timing, or sender drop counters',
          missingFields: [
            'delivery_on_frame_call_ms',
            'native_nv12_conversion_start_age_ms',
            'native_ready_fence_wait_ms',
            'process_input_ms',
            'process_output_ms',
            'encoded_callback_ms',
            'sender drop counters',
          ],
        ),
      if (native.nativeEncoderFenceWaitMissing)
        StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native NV12 encoder timing was present without parsed fence-wait timing; codec=${summary.senderCodecsLabel} engine=${summary.encoderImplementationsLabel} hw=${summary.hardwareEncodeStatesLabel} native=${_milliseconds(native.averageEncoderTotalMs)}',
          missingFields: const [
            'native_ready_fence',
            'native_ready_fence_timeout',
            'native_ready_fence_wait_ms',
            'process_input_ms',
            'process_output_ms',
            'encoded_callback_ms',
          ],
        )
      else if (summary.encoderImplementations.isNotEmpty ||
          summary.hardwareEncodeStates.isNotEmpty ||
          summary.averageEncodeTimeMs != null ||
          native.averageEncoderTotalMs != null)
        StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              'codec=${summary.senderCodecsLabel} engine=${summary.encoderImplementationsLabel} hw=${summary.hardwareEncodeStatesLabel} native=${_milliseconds(native.averageEncoderTotalMs)} fenceWait=${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)} processInput=${_milliseconds(native.averageEncoderProcessInputMs)}/${_milliseconds(native.maxEncoderProcessInputMs)} processOutput=${_milliseconds(native.averageEncoderProcessOutputMs)}/${_milliseconds(native.maxEncoderProcessOutputMs)} encodedCallback=${_milliseconds(native.averageEncoderEncodedCallbackMs)}/${_milliseconds(native.maxEncoderEncodedCallbackMs)}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'encoder implementation/timing was not present',
          missingFields: [
            'encoder implementation',
            'hardware encode state',
            'encode time',
          ],
        ),
      summary.framePacing.received.hasEvidence ||
              summary.framePacing.decoded.hasEvidence ||
              summary.framePacing.rendered.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'receiver stats',
              status: StreamDiagnosticCoverageStatus.available,
              detail:
                  'received=${summary.framePacing.received.markdownLabel}; decoded=${summary.framePacing.decoded.markdownLabel}; rendered=${summary.framePacing.rendered.markdownLabel}',
            )
          : const StreamDiagnosticCoverageItem(
              category: 'receiver stats',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'no receiver render/decode cadence was captured',
              missingFields: [
                'receiver render FPS',
                'receiver decode FPS',
                'subscribed layer',
              ],
            ),
      summary.maxPacketLossPercent != null ||
              summary.maxRoundTripTimeMs != null ||
              summary.maxNackCount != null ||
              summary.averageAvailableOutgoingBitrateBps != null
          ? StreamDiagnosticCoverageItem(
              category: 'network/SFU',
              status: StreamDiagnosticCoverageStatus.available,
              detail:
                  'loss=${_percent(summary.maxPacketLossPercent)} RTT=${_milliseconds(summary.maxRoundTripTimeMs)} NACK=${summary.maxNackCount ?? '?'} availableOutgoing=${_bitrate(summary.averageAvailableOutgoingBitrateBps)}',
            )
          : const StreamDiagnosticCoverageItem(
              category: 'network/SFU',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'network stats were not present in sender samples',
              missingFields: [
                'packet loss',
                'RTT',
                'NACK',
                'available outgoing bitrate',
              ],
            ),
    ];
    return StreamDiagnosticCoverageMatrix(items);
  }

  final List<StreamDiagnosticCoverageItem> items;

  List<String> get missingFields {
    final fields = <String>{};
    for (final item in items) {
      if (item.status == StreamDiagnosticCoverageStatus.missing ||
          item.status == StreamDiagnosticCoverageStatus.unavailable) {
        fields.addAll(item.missingFields);
      }
    }
    return fields.toList(growable: false)..sort();
  }

  Map<String, Object?> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'missingFields': missingFields,
    };
  }

  String toMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('| Category | Status | Detail | Missing Fields |')
      ..writeln('| --- | --- | --- | --- |');
    for (final item in items) {
      buffer.writeln(
        '| ${_markdownCell(item.category)} '
        '| ${item.markdownMarker} ${item.statusName} '
        '| ${_markdownCell(item.detail)} '
        '| ${_markdownCell(item.missingFields.isEmpty ? 'none' : item.missingFields.join(', '))} |',
      );
    }
    return buffer.toString();
  }

  static List<StreamDiagnosticCoverageItem> _mergePerPresetCoverage(
    List<StreamDiagnosticCoverageMatrix> matrices,
  ) {
    if (matrices.isEmpty) {
      return const [
        StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'no preset results were generated',
          missingFields: ['preset result'],
        ),
      ];
    }
    final categories = <String>[];
    for (final matrix in matrices) {
      for (final item in matrix.items) {
        if (item.category == 'requested settings') {
          continue;
        }
        if (!categories.contains(item.category)) {
          categories.add(item.category);
        }
      }
    }
    return categories.map((category) {
      final categoryItems = matrices
          .expand((matrix) => matrix.items)
          .where((item) => item.category == category)
          .toList(growable: false);
      final status = _aggregateStatus(categoryItems);
      final missing = categoryItems
          .expand((item) => item.missingFields)
          .toSet()
          .toList(growable: false)
        ..sort();
      final counts = <String, int>{};
      for (final item in categoryItems) {
        counts[item.statusName] = (counts[item.statusName] ?? 0) + 1;
      }
      final detail = counts.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      return StreamDiagnosticCoverageItem(
        category: category,
        status: status,
        detail: detail,
        missingFields: missing,
      );
    }).toList(growable: false);
  }

  static StreamDiagnosticCoverageStatus _aggregateStatus(
    List<StreamDiagnosticCoverageItem> items,
  ) {
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.missing,
    )) {
      return StreamDiagnosticCoverageStatus.missing;
    }
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.unavailable,
    )) {
      return StreamDiagnosticCoverageStatus.unavailable;
    }
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.available,
    )) {
      return StreamDiagnosticCoverageStatus.available;
    }
    return StreamDiagnosticCoverageStatus.notApplicable;
  }

  static StreamDiagnosticCoverageItem _gameCaptureTestTargetCoverage(
    StreamTestRunResult result,
  ) {
    final config = result.config.gameCaptureTestTarget;
    final target = result.gameCaptureTestTargetResult;
    if (config?.enabled != true) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'deterministic D3D11 capture target was not requested',
      );
    }
    if (target == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'capture target was requested but no launch result was saved',
        missingFields: ['target launch result'],
      );
    }
    if (target.hasDiagnostics) {
      return StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.available,
        detail: 'present=${_number(target.presentFps)}fps '
            'p95=${_milliseconds(target.presentGapP95Ms)} '
            'max=${_milliseconds(target.presentGapMaxMs)}',
      );
    }
    if (target.status == 'unavailable' || target.status == 'notApplicable') {
      return StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail: target.reason ?? target.status,
        missingFields: const ['capture-target diagnostics'],
      );
    }
    return const StreamDiagnosticCoverageItem(
      category: 'game-capture test target',
      status: StreamDiagnosticCoverageStatus.missing,
      detail: 'capture target launched but diagnostics were not readable',
      missingFields: ['capture-target.json'],
    );
  }

  static StreamDiagnosticCoverageItem _gameCaptureProbeCoverage(
    StreamTestRunResult result,
  ) {
    final config = result.config.gameCaptureProbe;
    final probe = result.gameCaptureProbeResult;
    if (config?.enabled != true) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture probe',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'D3D11 local game-capture probe was not requested',
      );
    }
    if (probe == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture probe',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'game-capture probe was requested but no result was produced',
        missingFields: ['game-capture probe result'],
      );
    }
    switch (probe.status) {
      case StreamDiagnosticCoverageStatus.available:
        if (config?.hostTextureConsumerEnabled == true &&
            !probe.hasHostConsumerEvidence) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.missing,
            detail:
                '${probe.summaryLabel}; host shared-texture consumer missing',
            missingFields: const ['host shared-texture consumer result'],
          );
        }
        if (config?.hostTextureConsumerEnabled == true &&
            !probe.hasHealthyHostTextureConsumer) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.unavailable,
            detail:
                '${probe.summaryLabel}; host shared-texture consumer did not '
                'open/consume frames',
            missingFields: const [
              'host opened shared texture',
              'host consumed frames',
            ],
          );
        }
        if (config?.publicationHandoffEnabled == true &&
            !probe.hasPublicationHandoffEvidence) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: '${probe.summaryLabel}; publication handoff result missing',
            missingFields: const ['publication-handoff.json'],
          );
        }
        if (config?.publicationHandoffEnabled == true &&
            !probe.hasVisiblePublicationHandoff) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.unavailable,
            detail:
                '${probe.summaryLabel}; publication handoff did not produce '
                'visible scaled frames',
            missingFields: const [
              'publication handoff opened shared texture',
              'publication handoff output frames',
              'publication handoff visible frames',
            ],
          );
        }
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.available,
          detail: probe.summaryLabel,
        );
      case StreamDiagnosticCoverageStatus.missing:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: probe.reason,
          missingFields: const ['game-capture metadata.json'],
        );
      case StreamDiagnosticCoverageStatus.unavailable:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.unavailable,
          detail: probe.reason,
          missingFields: const [
            'D3D11 helper attach result',
            'game-capture metadata.json',
          ],
        );
      case StreamDiagnosticCoverageStatus.notApplicable:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: probe.reason,
        );
    }
  }

  static StreamDiagnosticCoverageItem _receiverProbeCoverage(
    StreamTestRunResult result,
  ) {
    if (!result.config.receiverProbe.enabled) {
      return const StreamDiagnosticCoverageItem(
        category: 'true receiver probe',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'in-process true-receiver probe was not requested',
      );
    }

    final probeResults = result.presetResults
        .map((preset) => preset.receiverProbeResult)
        .whereType<StreamTestReceiverProbeResult>()
        .toList(growable: false);
    if (probeResults.isEmpty) {
      return const StreamDiagnosticCoverageItem(
        category: 'true receiver probe',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'receiver probe was requested but no result was recorded',
        missingFields: ['receiver-probe result'],
      );
    }

    final eventCount = probeResults.fold<int>(
      0,
      (sum, probe) => sum + probe.events.length,
    );
    final decodeCount = probeResults.fold<int>(
      0,
      (sum, probe) => sum + probe.remoteDecodeEventCount,
    );
    final renderCount = probeResults.fold<int>(
      0,
      (sum, probe) => sum + probe.remoteRendererCallbackEventCount,
    );
    final localPreviewCount = probeResults.fold<int>(
      0,
      (sum, probe) => sum + probe.localPreviewEventCount,
    );
    final statuses = probeResults.map((probe) => probe.status).toSet();
    final detail = 'statuses=${statuses.join(', ')}; events=$eventCount; '
        'local=$localPreviewCount; decode=$decodeCount; '
        'rendererCallback=$renderCount';

    if (probeResults.any(
      (probe) => probe.status == 'completed_receiver_probe_events',
    )) {
      return StreamDiagnosticCoverageItem(
        category: 'true receiver probe',
        status: StreamDiagnosticCoverageStatus.available,
        detail: detail,
      );
    }
    if (probeResults.any(
      (probe) => probe.status == 'completed_local_preview_probe_events',
    )) {
      return StreamDiagnosticCoverageItem(
        category: 'local preview probe',
        status: StreamDiagnosticCoverageStatus.available,
        detail: detail,
      );
    }
    if (eventCount > 0) {
      return StreamDiagnosticCoverageItem(
        category: 'true receiver probe',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: detail,
        missingFields: const [
          'receiver frame hash taps',
          'receiver unique FPS',
        ],
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'true receiver probe',
      status: StreamDiagnosticCoverageStatus.unavailable,
      detail: detail,
      missingFields: const [
        'subscribe-only receiver probe events',
      ],
    );
  }

  static StreamDiagnosticCoverageItem _receiverProbeQualityCoverage(
    StreamTestRunResult result,
  ) {
    if (!result.config.receiverProbe.enabled) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver quality diagnostics',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'true-receiver probe was not requested',
      );
    }

    final probeResults = result.presetResults
        .map((preset) => preset.receiverProbeResult)
        .whereType<StreamTestReceiverProbeResult>()
        .toList(growable: false);
    if (probeResults.isNotEmpty &&
        probeResults.every(
          (probe) => probe.mode == StreamTestReceiverProbeMode.localPreview,
        )) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver quality diagnostics',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'local-preview probe is diagnostic-only',
      );
    }
    final targetEvents = probeResults
        .expand((probe) => probe.targetEvents)
        .toList(growable: false);
    if (targetEvents.isEmpty) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver quality diagnostics',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'receiver probe had no target-lane event to inspect',
        missingFields: ['receiver target-lane event'],
      );
    }

    final latest = targetEvents.last;
    final missingFields = <String>{
      for (final event in targetEvents) ..._missingReceiverQualityFields(event),
    }.toList(growable: false);
    final quality =
        _stringFromJson(latest['subscribed_quality']) ?? 'unknown-quality';
    final layer = _stringFromJson(latest['simulcast_layer']) ?? 'unknown-layer';
    final bitrate = _intFromJson(latest['inbound_bitrate_bps']) ??
        _intFromJson(latest['bitrate_bps']);
    final decoded = _receiverProbeSizeLabel(latest, 'decoded');
    final rendered = _receiverProbeSizeLabel(latest, 'rendered');
    final detail = 'quality=$quality/$layer; '
        'bitrate=${_bitrate(bitrate)}; decoded=$decoded; rendered=$rendered';

    if (missingFields.isEmpty) {
      return StreamDiagnosticCoverageItem(
        category: 'receiver quality diagnostics',
        status: StreamDiagnosticCoverageStatus.available,
        detail: detail,
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'receiver quality diagnostics',
      status: StreamDiagnosticCoverageStatus.missing,
      detail: detail,
      missingFields: missingFields,
    );
  }

  static List<String> _missingReceiverQualityFields(
    Map<String, Object?> event,
  ) {
    return [
      if (_stringFromJson(event['subscribed_quality']) == null)
        'subscribed layer/quality',
      if (_intFromJson(event['inbound_bitrate_bps']) == null &&
          _intFromJson(event['bitrate_bps']) == null)
        'receiver inbound bitrate',
      if (_intFromJson(event['received_width']) == null ||
          _intFromJson(event['received_height']) == null)
        'received frame dimensions',
      if (_intFromJson(event['decoded_width']) == null ||
          _intFromJson(event['decoded_height']) == null)
        'decoded frame dimensions',
      if (_intFromJson(event['rendered_width']) == null ||
          _intFromJson(event['rendered_height']) == null)
        'rendered frame dimensions',
      if (_doubleFromJson(event['average_qp']) == null)
        'average QP if exposed by WebRTC stats',
      if (_intFromJson(event['key_frames_decoded']) == null)
        'keyframe interval/counter if exposed by WebRTC stats',
      if (_intFromJson(event['pli_count']) == null ||
          _intFromJson(event['fir_count']) == null ||
          _intFromJson(event['nack_count']) == null)
        'PLI/FIR/NACK receiver counters',
      if (_doubleFromJson(event['frame_presentation_p95_gap_ms']) == null)
        'frame presentation intervals',
      if (_doubleFromJson(event['perceptual_difference_score']) == null)
        'perceptual difference score',
      if (_doubleFromJson(event['longest_stale_run_ms']) == null)
        'longest visually stale run',
      if (_doubleFromJson(event['decode_to_render_ms']) == null)
        'decode-to-render latency',
      if (_intFromJson(event['dropped_or_replaced_texture_updates']) == null)
        'dropped/replaced texture update count',
      if (_boolFromJson(event['upscaling_lower_layer_suspected']) == null)
        'receiver upscaling lower layer flag',
      if (_boolFromJson(event['adaptive_stream_low_layer_suspected']) == null)
        'adaptive stream/dynacast low-layer selection flag',
    ];
  }

  static StreamDiagnosticCoverageItem _receiverProbePresentationStageCoverage(
    StreamTestRunResult result,
  ) {
    if (!result.config.receiverProbe.enabled) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver presentation stages',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'true-receiver probe was not requested',
      );
    }

    final probeResults = result.presetResults
        .map((preset) => preset.receiverProbeResult)
        .whereType<StreamTestReceiverProbeResult>()
        .toList(growable: false);
    if (probeResults.isEmpty) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver presentation stages',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'receiver probe was requested but no stage report was saved',
        missingFields: ['receiver presentation stage report'],
      );
    }
    if (probeResults.every(
      (probe) => probe.mode == StreamTestReceiverProbeMode.localPreview,
    )) {
      return const StreamDiagnosticCoverageItem(
        category: 'receiver presentation stages',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'local-preview probe is diagnostic-only',
      );
    }

    final counts = <String, int>{
      for (final stage in _receiverProbePresentationStageOrder) stage: 0,
    };
    for (final probe in probeResults) {
      for (final stage in _receiverProbePresentationStageOrder) {
        counts[stage] = (counts[stage] ?? 0) +
            probe.receiverPresentationStageEventCount(stage);
      }
    }
    final missingStages = _receiverProbePresentationStageOrder
        .where((stage) => (counts[stage] ?? 0) == 0)
        .toList(growable: false);
    final detail = _receiverProbePresentationStageOrder
        .map(
          (stage) =>
              '$stage=${(counts[stage] ?? 0) > 0 ? 'reported' : 'missing'}',
        )
        .join('; ');

    if (missingStages.isEmpty) {
      return StreamDiagnosticCoverageItem(
        category: 'receiver presentation stages',
        status: StreamDiagnosticCoverageStatus.available,
        detail: detail,
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'receiver presentation stages',
      status: StreamDiagnosticCoverageStatus.missing,
      detail: detail,
      missingFields: missingStages
          .map((stage) => 'receiver presentation stage $stage')
          .toList(growable: false),
    );
  }

  static StreamDiagnosticCoverageItem _loadedLibwebrtcArtifactCoverage(
    StreamTestRunResult result,
  ) {
    final artifact = result.loadedLibwebrtcArtifact;
    if (artifact == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'loaded libwebrtc hash',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail:
            'the stream-test report does not expose the loaded libwebrtc artifact hash',
        missingFields: ['loaded libwebrtc artifact identity'],
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'loaded libwebrtc hash',
      status: StreamDiagnosticCoverageStatus.available,
      detail: artifact.diagnosticLabel,
    );
  }

  static StreamDiagnosticCoverageItem _hostLoadCoverage(
    StreamTestRunResult result,
  ) {
    final hostLoad = result.hostLoadReport;
    if (hostLoad == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'stream-test host load sampler did not run',
        missingFields: [
          'system CPU percent',
          'system memory percent',
          'GPU utilization percent',
        ],
      );
    }
    if (!hostLoad.available) {
      return StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail: hostLoad.unavailableReason ?? 'host load samples unavailable',
        missingFields: const [
          'system CPU percent',
          'system memory percent',
          'GPU utilization percent',
        ],
      );
    }
    final missingFields = hostLoad.missingMetricLabels;
    if (!hostLoad.hasSystemCpuMemoryGpuEvidence) {
      return StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: _hostLoadCompactLabel(hostLoad),
        missingFields: missingFields,
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'host/system load',
      status: StreamDiagnosticCoverageStatus.available,
      detail: _hostLoadCompactLabel(hostLoad),
      missingFields: missingFields,
    );
  }
}
