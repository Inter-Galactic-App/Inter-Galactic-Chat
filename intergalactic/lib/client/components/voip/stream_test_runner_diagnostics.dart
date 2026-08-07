part of 'stream_test_runner.dart';

class StreamTestNativeDiagnostics {
  const StreamTestNativeDiagnostics({
    this.captureBackendMode,
    this.observedCapturer,
    this.observedCapturerId,
    this.dirtyRegionMode,
    this.windowGdiCaptureMode,
    this.sourceType,
    this.nativeSourceWidth,
    this.nativeSourceHeight,
    this.requestedMaxWidth,
    this.requestedMaxHeight,
    this.nativeWindowRectWidth,
    this.nativeWindowRectHeight,
    this.contentWidth,
    this.contentHeight,
    this.preEncodeWidth,
    this.preEncodeHeight,
    this.canvas,
    this.cropRegion,
    this.averageNativeFps,
    this.averageSubmittedFps,
    this.targetNativeFps,
    this.averageCaptureCallMs,
    this.maxCaptureCallMs,
    this.averageSourceCaptureMs,
    this.maxSourceCaptureMs,
    this.sourceCaptureSampleCount = 0,
    this.wgcCaptureCalls = 0,
    this.wgcCaptureSuccessCount = 0,
    this.wgcSourceNotCapturableCount = 0,
    this.wgcEnsureFrameCalls = 0,
    this.wgcEnsureSleepCount = 0,
    this.wgcProcessFrameCalls = 0,
    this.wgcProcessFrameSuccessCount = 0,
    this.wgcFramePoolEmptyCount = 0,
    this.wgcFramePoolReuseCount = 0,
    this.wgcCaptureFrameNullCount = 0,
    this.wgcMappedTextureCreateCount = 0,
    this.wgcResizeCount = 0,
    this.wgcFramePoolRecreateCount = 0,
    this.averageWgcGetFrameMs,
    this.maxWgcGetFrameMs,
    this.averageWgcEnsureFrameMs,
    this.maxWgcEnsureFrameMs,
    this.averageWgcProcessFrameMs,
    this.maxWgcProcessFrameMs,
    this.averageWgcTryGetFrameMs,
    this.maxWgcTryGetFrameMs,
    this.averageWgcSurfaceMs,
    this.maxWgcSurfaceMs,
    this.averageWgcTextureMs,
    this.maxWgcTextureMs,
    this.averageWgcContentSizeMs,
    this.maxWgcContentSizeMs,
    this.averageWgcCopyTextureMs,
    this.maxWgcCopyTextureMs,
    this.averageWgcMapTextureMs,
    this.maxWgcMapTextureMs,
    this.averageWgcCopyRowsMs,
    this.maxWgcCopyRowsMs,
    this.averageWgcMonitorScaleMs,
    this.maxWgcMonitorScaleMs,
    this.averageWgcZeroHertzMs,
    this.maxWgcZeroHertzMs,
    this.gdiCaptureCalls = 0,
    this.gdiCaptureSuccessCount = 0,
    this.gdiTemporaryErrorCount = 0,
    this.gdiPermanentErrorCount = 0,
    this.gdiHiddenOrMinimizedCount = 0,
    this.gdiRectFailCount = 0,
    this.gdiDcFailCount = 0,
    this.gdiFrameCreateFailCount = 0,
    this.gdiPrintFullCallCount = 0,
    this.gdiPrintFullSuccessCount = 0,
    this.gdiPrintFallbackCallCount = 0,
    this.gdiPrintFallbackSuccessCount = 0,
    this.gdiBitBltCallCount = 0,
    this.gdiBitBltSuccessCount = 0,
    this.gdiFinalPrintFullCount = 0,
    this.gdiFinalPrintFallbackCount = 0,
    this.gdiFinalBitBltCount = 0,
    this.gdiFinalNoneCount = 0,
    this.gdiBlackFrameCount = 0,
    this.gdiLowVarianceFrameCount = 0,
    this.gdiOwnedWindowFrameCount = 0,
    this.gdiOwnedWindowCaptureCallCount = 0,
    this.gdiOwnedWindowCaptureSuccessCount = 0,
    this.gdiOriginalWidth,
    this.gdiOriginalHeight,
    this.gdiCroppedWidth,
    this.gdiCroppedHeight,
    this.gdiFrameWidth,
    this.gdiFrameHeight,
    this.averageGdiTotalMs,
    this.maxGdiTotalMs,
    this.averageGdiRectMs,
    this.maxGdiRectMs,
    this.averageGdiVisibilityMs,
    this.maxGdiVisibilityMs,
    this.averageGdiGetDcMs,
    this.maxGdiGetDcMs,
    this.averageGdiGetDcSizeMs,
    this.maxGdiGetDcSizeMs,
    this.averageGdiCreateFrameMs,
    this.maxGdiCreateFrameMs,
    this.averageGdiMemDcMs,
    this.maxGdiMemDcMs,
    this.averageGdiPrintFullMs,
    this.maxGdiPrintFullMs,
    this.averageGdiPrintFallbackMs,
    this.maxGdiPrintFallbackMs,
    this.averageGdiBitBltMs,
    this.maxGdiBitBltMs,
    this.averageGdiCleanupMs,
    this.maxGdiCleanupMs,
    this.averageGdiCropMs,
    this.maxGdiCropMs,
    this.averageGdiOwnedEnumMs,
    this.maxGdiOwnedEnumMs,
    this.averageGdiOwnedCaptureMs,
    this.maxGdiOwnedCaptureMs,
    this.averageGdiOwnedCompositeMs,
    this.maxGdiOwnedCompositeMs,
    this.averageCallbackEntryDelayMs,
    this.maxCallbackEntryDelayMs,
    this.averageCaptureResultCallbackMs,
    this.maxCaptureResultCallbackMs,
    this.averageCaptureAcquireWaitMs,
    this.maxCaptureAcquireWaitMs,
    this.averagePostCallbackWaitMs,
    this.maxPostCallbackWaitMs,
    this.averageUnaccountedWaitMs,
    this.maxUnaccountedWaitMs,
    this.captureResultCallbackCount = 0,
    this.maxFrameIntervalMs,
    this.p95FrameIntervalMs,
    this.captureWaitTimeoutCount = 0,
    this.capturePermanentErrorCount = 0,
    this.duplicatedFrameCount = 0,
    this.staleFrameReuseCount = 0,
    this.averageFrameConvertMs,
    this.averageFrameScaleMs,
    this.averageFrameOnFrameMs,
    this.averageFrameCallbackMs,
    this.maxFrameCallbackMs,
    this.updatedRegionEmptyCount = 0,
    this.updatedRegionNonEmptyCount = 0,
    this.updatedRegionRectCount = 0,
    this.updatedRegionMaxRectCount = 0,
    this.averageUpdatedRegionAreaRatio,
    this.maxUpdatedRegionAreaRatio,
    this.averageUpdatedRegionAnalysisMs,
    this.maxUpdatedRegionAnalysisMs,
    this.updatedRegionFullFrameCount = 0,
    this.updatedRegionTinyFrameCount = 0,
    this.latestFramePacerEnabled,
    this.averagePacerSubmittedFps,
    this.averagePacerUniqueFps,
    this.p95PacerIntervalMs,
    this.maxPacerIntervalMs,
    this.averagePacerFrameAgeMs,
    this.maxPacerFrameAgeMs,
    this.averagePacerOnFrameMs,
    this.maxPacerOnFrameMs,
    this.pacerDuplicateSubmitCount = 0,
    this.pacerOverwrittenFrameCount = 0,
    this.pacerSkippedTickCount = 0,
    this.gameCaptureSourceWidth,
    this.gameCaptureSourceHeight,
    this.gameCaptureOutputWidth,
    this.gameCaptureOutputHeight,
    this.gameCaptureFormat,
    this.gameCaptureBackendContractVersion,
    this.gameCaptureSourceMode,
    this.gameCaptureSourceApi,
    this.gameCaptureSourceApiId,
    this.gameCaptureSourceFormat,
    this.gameCaptureSourceFormatId,
    this.gameCaptureColorSpace,
    this.gameCaptureSyncKind,
    this.gameCaptureReadyState,
    this.gameCaptureFailureReason,
    this.gameCaptureNativeAdmissionStrictDeadlineEnabled,
    this.gameCaptureNativeAdmissionSourceDrivenFreshDueFrames = 0,
    this.gameCaptureNativeAdmissionSourceQpcDueFrames = 0,
    this.gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames = 0,
    this.gameCaptureNativeAdmissionDeadlineDueFrames = 0,
    this.averageGameCaptureNativeAdmissionDeadlineLatenessMs,
    this.maxGameCaptureNativeAdmissionDeadlineLatenessMs,
    this.gameCaptureNativeAdmissionDeadlineLatenessSamples = 0,
    this.gameCaptureNativeAdmissionDeadlineOver1xFrames = 0,
    this.gameCaptureNativeAdmissionDeadlineOver2xFrames = 0,
    this.gameCaptureNativeAdmissionDeadlineOver3xFrames = 0,
    this.gameCaptureNativeAdmissionNoSourceOnDeadlineFrames = 0,
    this.gameCaptureNativeAdmissionRepeatedOnDeadlineFrames = 0,
    this.gameCaptureNativeAdmissionSubmitOnDeadlineFrames = 0,
    this.gameCaptureNativeAdmissionSubmitOnEarlySourceFrames = 0,
    this.gameCaptureNativeNv12PendingOnDeadlineFrames = 0,
    this.gameCaptureNativeNv12NoPendingOnDeadlineFrames = 0,
    this.gameCaptureNativeNv12ReadyOnDeadlineFrames = 0,
    this.gameCaptureNativeNv12NoReadyOnDeadlineFrames = 0,
    this.gameCaptureConsumerAdapterLuid,
    this.gameCaptureConsumerAdapterVendorId,
    this.gameCaptureConsumerAdapterDeviceId,
    this.gameCaptureSourceAdapterLuid,
    this.gameCaptureCrossAdapterSuspected,
    this.averageGameCaptureFps,
    this.gameCaptureSubmittedFrames = 0,
    this.gameCaptureRepeatedFrames = 0,
    this.gameCaptureDuplicateSkippedFrames = 0,
    this.gameCaptureDeliveryQueuedFrames = 0,
    this.gameCaptureDeliverySubmittedFrames = 0,
    this.gameCaptureDeliveryOverwrittenFrames = 0,
    this.gameCaptureDeliveryPacerResyncs = 0,
    this.gameCaptureDeliveryPacerLagMaxMs = 0,
    this.gameCaptureDeliveryRepeatNoQueuedFrames = 0,
    this.gameCaptureDeliverySkipNoQueuedFrames = 0,
    this.gameCaptureDeliveryFreshWakeAfterSkipFrames = 0,
    this.gameCaptureDeliveryFreshImmediateFrames = 0,
    this.gameCaptureDeliveryRepeatPolicy,
    this.gameCaptureDeliveryQueueDepth,
    this.averageGameCaptureDeliveryRepeatSourceAgeMs,
    this.maxGameCaptureDeliveryRepeatSourceAgeMs,
    this.gameCaptureDeliveryRepeatSourceAgeSamples = 0,
    this.averageGameCaptureDeliveryOnFrameMs,
    this.maxGameCaptureDeliveryOnFrameMs,
    this.averageGameCaptureDeliverySubmitPrepMs,
    this.maxGameCaptureDeliverySubmitPrepMs,
    this.gameCaptureDeliverySubmitPrepSamples = 0,
    this.averageGameCaptureDeliveryOnFrameCallMs,
    this.maxGameCaptureDeliveryOnFrameCallMs,
    this.gameCaptureDeliveryOnFrameCallSamples = 0,
    this.averageGameCaptureDeliveryPostOnFrameMs,
    this.maxGameCaptureDeliveryPostOnFrameMs,
    this.gameCaptureDeliveryPostOnFrameSamples = 0,
    this.averageGameCaptureNativeBufferReleaseMs,
    this.maxGameCaptureNativeBufferReleaseMs,
    this.gameCaptureNativeBufferReleaseSamples = 0,
    this.averageGameCaptureReadyToQueueMs,
    this.maxGameCaptureReadyToQueueMs,
    this.gameCaptureReadyToQueueSamples = 0,
    this.averageGameCaptureDeliveryQueueWaitMs,
    this.maxGameCaptureDeliveryQueueWaitMs,
    this.gameCaptureDeliveryQueueWaitSamples = 0,
    this.averageGameCaptureDeliveryOverwriteAgeMs,
    this.maxGameCaptureDeliveryOverwriteAgeMs,
    this.gameCaptureDeliveryOverwriteAgeSamples = 0,
    this.gameCaptureDeliveryOverwrittenFreshFrames = 0,
    this.averageGameCaptureReadyToSubmitMs,
    this.maxGameCaptureReadyToSubmitMs,
    this.gameCaptureReadyToSubmitSamples = 0,
    this.averageGameCaptureSourceToSubmitMs,
    this.maxGameCaptureSourceToSubmitMs,
    this.gameCaptureSourceToSubmitSamples = 0,
    this.averageGameCaptureSourceToReadbackReadyMs,
    this.maxGameCaptureSourceToReadbackReadyMs,
    this.gameCaptureSourceToReadbackReadySamples = 0,
    this.averageGameCaptureReadbackQueueToMapMs,
    this.maxGameCaptureReadbackQueueToMapMs,
    this.gameCaptureReadbackQueueToMapSamples = 0,
    this.averageGameCaptureMapToI420Ms,
    this.maxGameCaptureMapToI420Ms,
    this.gameCaptureMapToI420Samples = 0,
    this.averageGameCaptureSourceToI420ReadyMs,
    this.maxGameCaptureSourceToI420ReadyMs,
    this.gameCaptureSourceToI420ReadySamples = 0,
    this.averageGameCaptureSourceToQueueMs,
    this.maxGameCaptureSourceToQueueMs,
    this.gameCaptureSourceToQueueSamples = 0,
    this.averageGameCaptureSourceDuplicateSkipAgeMs,
    this.maxGameCaptureSourceDuplicateSkipAgeMs,
    this.gameCaptureSourceDuplicateSkipAgeSamples = 0,
    this.gameCaptureCopiedFrames = 0,
    this.gameCaptureDroppedFrames = 0,
    this.gameCaptureOverwrittenFrames = 0,
    this.gameCaptureGpuScaledFrames = 0,
    this.gameCaptureGpuScaleFailures = 0,
    this.gameCaptureCpuFallbackFrames = 0,
    this.gameCaptureNativeNv12SubmittedFrames = 0,
    this.gameCaptureNativeNv12QueuedFrames = 0,
    this.gameCaptureNativeNv12ReadyFrames = 0,
    this.gameCaptureNativeNv12NotReadyPolls = 0,
    this.gameCaptureNativeNv12ReadyPolicy,
    this.gameCaptureNativeNv12FenceAvailable,
    this.gameCaptureNativeNv12PendingPollMs,
    this.gameCaptureNativeNv12MaxPendingSlots,
    this.gameCaptureNativeNv12ReadyDrainDepth,
    this.gameCaptureNativeNv12FrameOwnership,
    this.gameCaptureNativeNv12WarmupI420Frames,
    this.gameCaptureNativeNv12SingleInFlightEnabled,
    this.gameCaptureNativeNv12GpuQueueBackoffEnabled,
    this.gameCaptureNativeNv12GpuQueueBackoffThresholdFrames,
    this.gameCaptureNativeNv12GpuQueueBackoffDurationFrames,
    this.gameCaptureNativeNv12FenceSignaledFrames = 0,
    this.gameCaptureNativeNv12FenceReadyFrames = 0,
    this.gameCaptureNativeNv12FenceSignalFailures = 0,
    this.gameCaptureNativeNv12OwnedCopies = 0,
    this.averageGameCaptureNativeNv12OwnedCopyMs,
    this.maxGameCaptureNativeNv12OwnedCopyMs,
    this.gameCaptureNativeNv12OwnedCopySamples = 0,
    this.gameCaptureNativeNv12OverwrittenFrames = 0,
    this.averageGameCaptureNativeNv12OverwriteAgeMs,
    this.maxGameCaptureNativeNv12OverwriteAgeMs,
    this.gameCaptureNativeNv12OverwriteAgeSamples = 0,
    this.gameCaptureNativeNv12OverwrittenFreshFrames = 0,
    this.gameCaptureNativeNv12ReadyDroppedFrames = 0,
    this.averageGameCaptureNativeNv12ReadyDropAgeMs,
    this.maxGameCaptureNativeNv12ReadyDropAgeMs,
    this.gameCaptureNativeNv12ReadyDropAgeSamples = 0,
    this.gameCaptureNativeNv12ReadyDroppedFreshFrames = 0,
    this.gameCaptureNativeNv12LateReadyDropEnabled,
    this.gameCaptureNativeNv12LateReadyDropThresholdMs,
    this.gameCaptureNativeNv12LateReadyDroppedFrames = 0,
    this.averageGameCaptureNativeNv12LateReadyDropAgeMs,
    this.maxGameCaptureNativeNv12LateReadyDropAgeMs,
    this.gameCaptureNativeNv12LateReadyDropAgeSamples = 0,
    this.gameCaptureNativeNv12LateReadyDroppedFreshFrames = 0,
    this.averageGameCaptureNativeNv12LateReadyDropBltToReadyMs,
    this.maxGameCaptureNativeNv12LateReadyDropBltToReadyMs,
    this.gameCaptureNativeNv12LateReadyDropBltToReadySamples = 0,
    this.gameCaptureNativeNv12Failures = 0,
    this.averageGameCaptureNativeNv12ConvertMs,
    this.maxGameCaptureNativeNv12ConvertMs,
    this.gameCaptureNativeNv12ConvertSamples = 0,
    this.averageGameCaptureNativeNv12BgraScaleDrawMs,
    this.maxGameCaptureNativeNv12BgraScaleDrawMs,
    this.gameCaptureNativeNv12BgraScaleDrawSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs,
    this.gameCaptureNativeNv12VideoProcessorBltSubmitSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
    this.gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
    this.gameCaptureNativeNv12VideoProcessorBltToReadySamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
    this.gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
    this.gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
    this.gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples =
        0,
    this.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures = 0,
    this.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady = 0,
    this.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint = 0,
    this.gameCaptureNativeNv12ReadyObservedImmediateFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedFenceEventFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedSourceEventFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedWaitOtherFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedLoopIdleFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedPreSubmitFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames = 0,
    this.gameCaptureNativeNv12ReadyObservedUnknownFrames = 0,
    this.gameCaptureNativeNv12BltToReadyOver1xFrames = 0,
    this.gameCaptureNativeNv12BltToReadyOver2xFrames = 0,
    this.gameCaptureNativeNv12BltToReadyOver3xFrames = 0,
    this.averageGameCaptureNativeNv12BufferCreateMs,
    this.maxGameCaptureNativeNv12BufferCreateMs,
    this.gameCaptureNativeNv12BufferCreateSamples = 0,
    this.averageGameCaptureNativeNv12FrameReadyToQueueMs,
    this.maxGameCaptureNativeNv12FrameReadyToQueueMs,
    this.gameCaptureNativeNv12FrameReadyToQueueSamples = 0,
    this.averageGameCaptureNativeNv12ConversionStartAgeMs,
    this.maxGameCaptureNativeNv12ConversionStartAgeMs,
    this.gameCaptureNativeNv12ConversionStartAgeSamples = 0,
    this.gameCaptureNativeNv12SingleInFlightDeferredFrames = 0,
    this.gameCaptureNativeNv12SingleInFlightDeferredFreshFrames = 0,
    this.gameCaptureNativeNv12SingleInFlightPendingMax = 0,
    this.averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs,
    this.maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs,
    this.gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples = 0,
    this.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames = 0,
    this.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames = 0,
    this.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames = 0,
    this.averageGameCaptureNativeNv12GpuQueueBackoffMs,
    this.maxGameCaptureNativeNv12GpuQueueBackoffMs,
    this.gameCaptureNativeNv12GpuQueueBackoffSamples = 0,
    this.averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
    this.maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
    this.gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples = 0,
    this.averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
    this.maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
    this.gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples = 0,
    this.gameCaptureNativeNv12AdmissionMailboxEnabled,
    this.gameCaptureNativeNv12AdmissionMailboxPendingActive,
    this.gameCaptureNativeNv12AdmissionMailboxStoredFrames = 0,
    this.gameCaptureNativeNv12AdmissionMailboxReplacedFrames = 0,
    this.gameCaptureNativeNv12AdmissionMailboxSubmittedFrames = 0,
    this.gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames = 0,
    this.averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs,
    this.maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs,
    this.gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples = 0,
    this.averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs,
    this.maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs,
    this.gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples = 0,
    this.gameCaptureNativeNv12StaleBeforeQueueFrames = 0,
    this.gameCaptureNativeNv12HandoffDisabledReason,
    this.gameCaptureNativeNv12OnFrameBackpressureEnabled,
    this.gameCaptureNativeNv12OnFrameBackpressureThresholdMs,
    this.gameCaptureNativeNv12OnFrameBackpressureFrameLimit,
    this.gameCaptureNativeNv12OnFrameBackpressureFrames = 0,
    this.gameCaptureNativeNv12OnFrameBackpressureStreak = 0,
    this.gameCaptureNativeNv12OnFrameBackpressureMaxMs,
    this.gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure,
    this.gameCaptureReadbackQueuedFrames = 0,
    this.gameCaptureReadbackReadyFrames = 0,
    this.gameCaptureReadbackNotReadyFrames = 0,
    this.gameCaptureReadbackOverwrittenFrames = 0,
    this.gameCaptureReadbackStaleDroppedFrames = 0,
    this.gameCaptureReadbackLatencyDroppedFrames = 0,
    this.gameCaptureReadbackMapAttempts = 0,
    this.gameCaptureSourceFrameIndex = 0,
    this.gameCaptureLastSubmittedSourceFrameIndex = 0,
    this.gameCaptureSourceFrameRegressions = 0,
    this.gameCaptureSourceFrameDuplicates = 0,
    this.gameCaptureSourceFrameGaps = 0,
    this.gameCaptureSharedSlotMismatches = 0,
    this.gameCaptureTimestampMode,
    this.gameCaptureTimestampSourceQpcFrames = 0,
    this.gameCaptureTimestampPacedFallbackFrames = 0,
    this.gameCaptureTimestampRepeatedFrames = 0,
    this.averageGameCaptureTimestampDeltaMs,
    this.maxGameCaptureTimestampDeltaMs,
    this.gameCaptureTimestampSamples = 0,
    this.gameCaptureTimestampAdjustments = 0,
    this.averageGameCaptureDeliveryWallDeltaMs,
    this.maxGameCaptureDeliveryWallDeltaMs,
    this.minGameCaptureDeliveryWallDeltaMs,
    this.gameCaptureDeliveryWallSamples = 0,
    this.gameCaptureDeliveryWallOver2xFrames = 0,
    this.gameCaptureDeliveryWallOver3xFrames = 0,
    this.gameCaptureDeliveryWallUnderHalfFrames = 0,
    this.averageGameCaptureSourceQpcDeltaMs,
    this.maxGameCaptureSourceQpcDeltaMs,
    this.gameCaptureSourceQpcSamples = 0,
    this.gameCaptureSourceQpcRegressions = 0,
    this.gameCaptureSourceQpcOver2xFrames = 0,
    this.gameCaptureSourceQpcOver3xFrames = 0,
    this.gameCaptureSourceQpcUnderHalfFrames = 0,
    this.gameCaptureSourceLatestObservedFrames = 0,
    this.gameCaptureSourceLatestFrameGaps = 0,
    this.gameCaptureSourceLatestFrameRegressions = 0,
    this.averageGameCaptureSourceLatestQpcDeltaMs,
    this.maxGameCaptureSourceLatestQpcDeltaMs,
    this.gameCaptureSourceLatestQpcSamples = 0,
    this.gameCaptureSourceLatestQpcRegressions = 0,
    this.gameCaptureSourceLatestQpcOver2xFrames = 0,
    this.gameCaptureSourceLatestQpcOver3xFrames = 0,
    this.gameCaptureSourceLatestQpcUnderHalfFrames = 0,
    this.averageGameCaptureSourceLatestObservationDeltaMs,
    this.maxGameCaptureSourceLatestObservationDeltaMs,
    this.gameCaptureSourceLatestObservationSamples = 0,
    this.gameCaptureSourceLatestObservationOver2xFrames = 0,
    this.gameCaptureSourceLatestObservationOver3xFrames = 0,
    this.averageGameCaptureSourceLatestEventAgeMs,
    this.maxGameCaptureSourceLatestEventAgeMs,
    this.gameCaptureSourceLatestEventAgeSamples = 0,
    this.gameCaptureSourceLatestEventAgeOver1xFrames = 0,
    this.gameCaptureSourceLatestEventAgeOver2xFrames = 0,
    this.gameCaptureSourceLatestEventAgeOver3xFrames = 0,
    this.averageGameCaptureSourcePublishObservationAgeMs,
    this.maxGameCaptureSourcePublishObservationAgeMs,
    this.gameCaptureSourcePublishObservationAgeSamples = 0,
    this.gameCaptureSourcePublishObservationAgeOver1xFrames = 0,
    this.gameCaptureSourcePublishObservationAgeOver2xFrames = 0,
    this.gameCaptureSourcePublishObservationAgeOver3xFrames = 0,
    this.averageGameCaptureProducerPresentGapMs,
    this.maxGameCaptureProducerPresentGapMs,
    this.gameCaptureProducerPresentGapSamples = 0,
    this.averageGameCaptureProducerCaptureGapMs,
    this.maxGameCaptureProducerCaptureGapMs,
    this.gameCaptureProducerCaptureGapSamples = 0,
    this.averageGameCaptureProducerPresentToPublishMs,
    this.maxGameCaptureProducerPresentToPublishMs,
    this.gameCaptureProducerPresentToPublishSamples = 0,
    this.averageGameCaptureProducerCopyMs,
    this.maxGameCaptureProducerCopyMs,
    this.gameCaptureProducerCopySamples = 0,
    this.averageGameCaptureProducerResolveMs,
    this.maxGameCaptureProducerResolveMs,
    this.gameCaptureProducerResolveSamples = 0,
    this.gameCaptureProducerThrottledFrames = 0,
    this.averageGameCaptureCopyMs,
    this.averageGameCaptureMapMs,
    this.averageGameCaptureConvertMs,
    this.averageGameCaptureGpuScaleMs,
    this.averageGameCaptureReadbackLatencyMs,
    this.averageGameCaptureReadbackLatencyFrames,
    this.gameCaptureMaxReadbackLatencyFrames = 0,
    this.gameCaptureMapFailures = 0,
    this.gameCaptureConvertFailures = 0,
    this.gameCaptureProofFrames = 0,
    this.gameCaptureVisibleProofFrames = 0,
    this.gameCaptureProofVisible,
    this.gameCaptureProofPath,
    this.gameCaptureProofMinLuma,
    this.gameCaptureProofMaxLuma,
    this.gameCaptureProofNonzeroSamples,
    this.gameCaptureProofSamples,
    this.gameCaptureI420ProofFrames = 0,
    this.gameCaptureVisibleI420ProofFrames = 0,
    this.gameCaptureInitialBlackSkippedFrames = 0,
    this.gameCaptureVisibleSourceSeen,
    this.gameCaptureI420ProofVisible,
    this.gameCaptureI420ProofPath,
    this.gameCaptureI420ProofMinLuma,
    this.gameCaptureI420ProofMaxLuma,
    this.gameCaptureI420ProofNonzeroSamples,
    this.gameCaptureI420ProofSamples,
    this.gameCaptureVisualFreshnessSampleMode,
    this.gameCaptureVisualFreshnessSampleFrames = 0,
    this.gameCaptureVisualFreshnessUniqueFrames = 0,
    this.averageGameCaptureVisualFreshnessUniqueFps,
    this.gameCaptureVisualFreshnessLongestStaleMs,
    this.gameCaptureVisualFreshnessLongestStaleFrames = 0,
    this.gameCaptureVisualFreshnessLowChangeFrames = 0,
    this.gameCaptureVisualFreshnessArtifactSet,
    this.averageEncoderTotalMs,
    this.maxEncoderTotalMs,
    this.encoderSlowFrameCount = 0,
    this.encoderSampleCount = 0,
    this.encoderRateControlMode,
    this.encoderTargetBitrateBps,
    this.encoderInputPaths = const [],
    this.encoderNativeInputFrames = 0,
    this.encoderCpuI420InputFrames = 0,
    this.encoderNativeSampleFailures = 0,
    this.encoderNativeSuspendedFrames = 0,
    this.encoderNativeReadyFenceFrames = 0,
    this.encoderNativeReadyFenceTimeoutFrames = 0,
    this.averageEncoderNativeReadyFenceWaitMs,
    this.maxEncoderNativeReadyFenceWaitMs,
    this.encoderNativeReadyFenceWaitSamples = 0,
    this.encoderNativeSourceMode,
    this.encoderNativeSourceFormat,
    this.encoderNativeSourceFrameIndex = 0,
    this.averageEncoderNativeSourceAgeMs,
    this.maxEncoderNativeSourceAgeMs,
    this.encoderNativeSourceAgeSamples = 0,
    this.averageEncoderNativeSourceAgeAtCreateMs,
    this.maxEncoderNativeSourceAgeAtCreateMs,
    this.averageEncoderNativeBufferAgeMs,
    this.maxEncoderNativeBufferAgeMs,
    this.encoderNativeBufferAgeSamples = 0,
    this.averageEncoderNativeSampleLifetimeMs,
    this.maxEncoderNativeSampleLifetimeMs,
    this.encoderNativeSampleLifetimeSamples = 0,
    this.encoderNativeAdapterLuid,
    this.encoderNativeAdapterVendorId,
    this.encoderNativeAdapterDeviceId,
    this.averageEncoderProcessInputMs,
    this.maxEncoderProcessInputMs,
    this.encoderProcessInputSamples = 0,
    this.averageEncoderProcessOutputMs,
    this.maxEncoderProcessOutputMs,
    this.encoderProcessOutputSamples = 0,
    this.averageEncoderEncodedCallbackMs,
    this.maxEncoderEncodedCallbackMs,
    this.encoderEncodedCallbackSamples = 0,
    this.averageEncoderEncodedCallbackQueueWaitMs,
    this.maxEncoderEncodedCallbackQueueWaitMs,
    this.encoderEncodedCallbackQueueWaitSamples = 0,
    this.averageEncoderEncodedCallbackEnqueueMs,
    this.maxEncoderEncodedCallbackEnqueueMs,
    this.encoderEncodedCallbackEnqueueSamples = 0,
    this.encoderEncodedCallbackAsyncFrames = 0,
    this.encoderMaxEncodedCallbackQueueDepth = 0,
    this.encoderMaxEncodedCallbackDrops = 0,
    this.encoderMaxEncodedCallbackOutputs = 0,
    this.encoderStages = const [],
    this.encoderOutputFrames = 0,
    this.encoderOutputBytes = 0,
    this.encoderMaxQueueDepth = 0,
    this.encoderMaxRetainedSamples = 0,
    this.encoderMaxEncodedOutputs = 0,
    this.averageWebrtcSourceOnFrameMs,
    this.maxWebrtcSourceOnFrameMs,
    this.webrtcSourceOnFrameSamples = 0,
    this.averageWebrtcSourceAdaptMs,
    this.maxWebrtcSourceAdaptMs,
    this.averageWebrtcSourceScaleMs,
    this.maxWebrtcSourceScaleMs,
    this.averageWebrtcSourceBroadcastMs,
    this.maxWebrtcSourceBroadcastMs,
    this.webrtcSourceAdapterDrops = 0,
    this.webrtcSourceScaledFrames = 0,
    this.averageWebrtcVideoBroadcasterMs,
    this.maxWebrtcVideoBroadcasterMs,
    this.webrtcVideoBroadcasterSamples = 0,
    this.averageWebrtcVideoBroadcasterLockWaitMs,
    this.maxWebrtcVideoBroadcasterLockWaitMs,
    this.averageWebrtcVideoBroadcasterSinkDispatchMs,
    this.maxWebrtcVideoBroadcasterSinkDispatchMs,
    this.maxWebrtcVideoBroadcasterSingleSinkMs,
    this.webrtcVideoBroadcasterSlowSinkId,
    this.webrtcVideoBroadcasterSlowSinkMs,
    this.webrtcVideoBroadcasterSlowSinkLabel,
    this.webrtcVideoBroadcasterSlowestSinkId,
    this.webrtcVideoBroadcasterSlowestSinkMs,
    this.webrtcVideoBroadcasterSlowestSinkAverageMs,
    this.webrtcVideoBroadcasterSlowestSinkFrames = 0,
    this.webrtcVideoBroadcasterSlowestSinkLabel,
    this.webrtcVideoBroadcasterSinkCount = 0,
    this.webrtcVideoBroadcasterMaxSinkCount = 0,
    this.webrtcVideoBroadcasterActiveSinks = 0,
    this.webrtcVideoBroadcasterInactiveSinks = 0,
    this.webrtcVideoBroadcasterRequestedSinks = 0,
    this.webrtcVideoBroadcasterBlackFrameSinks = 0,
    this.webrtcVideoBroadcasterRotationAppliedSinks = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinkBypassReported = false,
    this.webrtcVideoBroadcasterInactiveNativeSinksBypassed = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinksRefreshed = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast = 0,
    this.webrtcVideoBroadcasterSinkRoster,
    this.webrtcVideoBroadcasterBlackSinks = 0,
    this.webrtcVideoBroadcasterRotationDiscards = 0,
    this.webrtcVideoBroadcasterUpdateRectCleared = 0,
    this.webrtcVideoBroadcasterDiscardedFrames = 0,
    this.averageWebrtcVsePostToOnFrameMs,
    this.maxWebrtcVsePostToOnFrameMs,
    this.averageWebrtcVseOnFrameMs,
    this.maxWebrtcVseOnFrameMs,
    this.webrtcVseOnFrameSamples = 0,
    this.webrtcVseQueueOverloadDrops = 0,
    this.webrtcVseEncoderQueueDrops = 0,
    this.webrtcVseCwndDrops = 0,
    this.webrtcVseBadTimestampDrops = 0,
    this.averageWebrtcVseMaybeEncodeMs,
    this.maxWebrtcVseMaybeEncodeMs,
    this.webrtcVseMaybeEncodeSamples = 0,
    this.webrtcVsePendingReplacedDrops = 0,
    this.webrtcVseSizeDrops = 0,
    this.webrtcVsePausedDrops = 0,
    this.webrtcVseMediaOptimizationDrops = 0,
    this.averageWebrtcVseEncodeFrameMs,
    this.maxWebrtcVseEncodeFrameMs,
    this.averageWebrtcVseMaybePreEncodeMs,
    this.maxWebrtcVseMaybePreEncodeMs,
    this.averageWebrtcVseMaybeEncodeCallMs,
    this.maxWebrtcVseMaybeEncodeCallMs,
    this.averageWebrtcVseMaybeFrameSizeMs,
    this.maxWebrtcVseMaybeFrameSizeMs,
    this.averageWebrtcVseMaybeParameterUpdateMs,
    this.maxWebrtcVseMaybeParameterUpdateMs,
    this.averageWebrtcVseMaybeReconfigureMs,
    this.maxWebrtcVseMaybeReconfigureMs,
    this.webrtcVsePendingReconfigureSignals = 0,
    this.webrtcVsePendingReconfigureConfigureEncoder = 0,
    this.webrtcVsePendingReconfigureFrameInfoChange = 0,
    this.webrtcVsePendingReconfigureSourceRestriction = 0,
    this.webrtcVsePendingReconfigureUnknown = 0,
    this.webrtcVsePendingReconfigureLastReason,
    this.averageWebrtcVseMaybeRateUpdateMs,
    this.maxWebrtcVseMaybeRateUpdateMs,
    this.averageWebrtcVseMaybeDropChecksMs,
    this.maxWebrtcVseMaybeDropChecksMs,
    this.averageWebrtcVseEncodePreEncoderMs,
    this.maxWebrtcVseEncodePreEncoderMs,
    this.averageWebrtcVseEncodeInfoMs,
    this.maxWebrtcVseEncodeInfoMs,
    this.averageWebrtcVseEncodeCropScaleMs,
    this.maxWebrtcVseEncodeCropScaleMs,
    this.averageWebrtcVseEncodeUpdateRectMs,
    this.maxWebrtcVseEncodeUpdateRectMs,
    this.averageWebrtcVseEncodeResourceMs,
    this.maxWebrtcVseEncodeResourceMs,
    this.averageWebrtcVseEncodeMetadataMs,
    this.maxWebrtcVseEncodeMetadataMs,
    this.webrtcVseEncodeFrameSamples = 0,
    this.averageWebrtcVideoEncoderEncodeMs,
    this.maxWebrtcVideoEncoderEncodeMs,
    this.webrtcVideoEncoderEncodeSamples = 0,
    this.webrtcVseEncodeFailures = 0,
    this.webrtcVseEncodeSkippedBeforeEncoder = 0,
    this.webrtcFrameLineageStage,
    this.webrtcFrameLineageFrameId,
    this.webrtcFrameLineageSourceQpc,
    this.webrtcFrameLineageStageQpc,
    this.webrtcFrameLineageFrameAgeMs,
    this.webrtcFrameLineagePreviousFrameId,
    this.averageWebrtcFrameCadencePostDelayMs,
    this.maxWebrtcFrameCadencePostDelayMs,
    this.averageWebrtcFrameCadenceCallbackMs,
    this.maxWebrtcFrameCadenceCallbackMs,
    this.averageWebrtcFrameCadenceFrameDurationMs,
    this.maxWebrtcFrameCadenceFrameDurationMs,
    this.webrtcFrameCadenceSends = 0,
    this.webrtcFrameCadenceRepeatedSends = 0,
    this.webrtcFrameCadencePostDelaySamples = 0,
    this.webrtcFrameCadenceOverFrameDurationSends = 0,
    this.webrtcFrameCadenceOverloadTriggerSends = 0,
    this.webrtcFrameCadenceOverloadActiveSends = 0,
    this.webrtcFrameCadenceOverloadDecaySends = 0,
    this.webrtcFrameCadenceOverloadEnabledSeen,
    this.webrtcFrameCadenceOverloadDisabledSeen,
    this.webrtcFrameCadenceMaxScheduledForProcessing = 0,
    this.webrtcFrameCadenceLastScheduledForProcessing = 0,
    this.webrtcFrameCadenceMaxQueueOverloadBefore = 0,
    this.webrtcFrameCadenceMaxQueueOverloadAfter = 0,
    this.webrtcFrameCadenceLastQueueOverloadBefore = 0,
    this.webrtcFrameCadenceLastQueueOverloadAfter = 0,
    this.averageWebrtcFrameCadenceQueuePostDelayMs,
    this.maxWebrtcFrameCadenceQueuePostDelayMs,
    this.webrtcFrameCadenceQueueFrames = 0,
    this.webrtcFrameCadenceQueueOverloadFrames = 0,
    this.webrtcFrameCadenceQueuePostDelaySamples = 0,
    this.webrtcFrameCadenceQueueMaxScheduledForProcessing = 0,
    this.webrtcFrameCadenceQueueLastScheduledForProcessing = 0,
    this.webrtcFrameCadenceQueuePassthroughFrames = 0,
    this.webrtcFrameCadenceQueueZeroHertzFrames = 0,
    this.webrtcFrameCadenceQueueVsyncFrames = 0,
    this.webrtcFrameCadenceQueueUnknownFrames = 0,
    this.webrtcFrameCadenceQueueCoalesceEnabledSeen,
    this.webrtcFrameCadenceQueueCoalesceDisabledSeen,
    this.webrtcFrameCadenceQueueCoalesceThreshold = 0,
    this.webrtcFrameCadenceQueueCoalescedDrops = 0,
    this.webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen,
    this.webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen,
    this.webrtcFrameCadenceQueuePrepostCoalescedDrops = 0,
    this.webrtcFrameCadenceQueuePrepostProcessingDrops = 0,
    this.webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing = 0,
    this.webrtcFrameCadenceQueueLastMode,
    this.webrtcFrameCadenceQueueMailboxEnabledSeen,
    this.webrtcFrameCadenceQueueMailboxFrames = 0,
    this.webrtcFrameCadenceQueueMailboxProcessedFrames = 0,
    this.webrtcFrameCadenceQueueMailboxReplacements = 0,
    this.webrtcFrameCadenceQueueMailboxStaleDrops = 0,
    this.webrtcFrameCadenceQueueMailboxProcessingActive,
    this.webrtcFrameCadenceQueueMailboxProcessingActiveSeen,
    this.webrtcFrameCadenceQueueMailboxPendingDepthMax = 0,
    this.webrtcFrameCadenceQueueMailboxPendingDepthLast = 0,
    this.averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
    this.maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
    this.webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples = 0,
    this.averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
    this.maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
    this.webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples = 0,
    this.webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses = 0,
    this.averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
    this.maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
    this.webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples = 0,
    this.averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
    this.maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
    this.webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples = 0,
    this.averageWebrtcFrameCadenceQueueMailboxVseCallMs,
    this.maxWebrtcFrameCadenceQueueMailboxVseCallMs,
    this.webrtcFrameCadenceQueueMailboxVseCallSamples = 0,
    this.webrtcFrameCadenceQueueMailboxStaleDropThresholdMs = 0,
  });

  factory StreamTestNativeDiagnostics.fromMarkers(List<String> markers) {
    markers = _expandDiagnosticLogMarkerLines(markers);
    String? captureBackendMode;
    String? observedCapturer;
    int? observedCapturerId;
    String? dirtyRegionMode;
    String? windowGdiCaptureMode;
    String? sourceType;
    int? nativeSourceWidth;
    int? nativeSourceHeight;
    int? requestedMaxWidth;
    int? requestedMaxHeight;
    int? nativeWindowRectWidth;
    int? nativeWindowRectHeight;
    int? contentWidth;
    int? contentHeight;
    int? preEncodeWidth;
    int? preEncodeHeight;
    String? canvas;
    bool? cropRegion;
    final nativeFpsValues = <double>[];
    final submittedFpsValues = <double>[];
    final targetFpsValues = <double>[];
    final captureCallValues = <double>[];
    final maxCaptureCallValues = <double>[];
    final sourceCaptureValues = <double>[];
    var sourceCaptureWeightedTotalMs = 0.0;
    var sourceCaptureWeightedSampleCount = 0;
    final maxSourceCaptureValues = <double>[];
    final callbackEntryDelayValues = <double>[];
    final maxCallbackEntryDelayValues = <double>[];
    final captureResultCallbackValues = <double>[];
    final maxCaptureResultCallbackValues = <double>[];
    final captureAcquireWaitValues = <double>[];
    final maxCaptureAcquireWaitValues = <double>[];
    final postCallbackWaitValues = <double>[];
    final maxPostCallbackWaitValues = <double>[];
    final unaccountedWaitValues = <double>[];
    final maxUnaccountedWaitValues = <double>[];
    final maxFrameIntervalValues = <double>[];
    final p95FrameIntervalValues = <double>[];
    final frameConvertValues = <double>[];
    final frameScaleValues = <double>[];
    final frameOnFrameValues = <double>[];
    final frameCallbackValues = <double>[];
    final maxFrameCallbackValues = <double>[];
    bool? latestFramePacerEnabled;
    final pacerSubmittedFpsValues = <double>[];
    final pacerUniqueFpsValues = <double>[];
    final p95PacerIntervalValues = <double>[];
    final maxPacerIntervalValues = <double>[];
    final pacerFrameAgeValues = <double>[];
    final maxPacerFrameAgeValues = <double>[];
    final pacerOnFrameValues = <double>[];
    final maxPacerOnFrameValues = <double>[];
    final encoderTotalValues = <double>[];
    var encoderSlowFrameCount = 0;
    String? encoderRateControlMode;
    int? encoderTargetBitrateBps;
    final encoderInputPaths = <String>{};
    var encoderNativeInputFrames = 0;
    var encoderCpuI420InputFrames = 0;
    var encoderNativeSampleFailures = 0;
    var encoderNativeSuspendedFrames = 0;
    var encoderNativeReadyFenceFrames = 0;
    var encoderNativeReadyFenceTimeoutFrames = 0;
    final encoderNativeReadyFenceWaitValues = <double>[];
    String? encoderNativeSourceMode;
    int? encoderNativeSourceFormat;
    var encoderNativeSourceFrameIndex = 0;
    final encoderNativeSourceAgeValues = <double>[];
    final encoderNativeSourceAgeAtCreateValues = <double>[];
    final encoderNativeBufferAgeValues = <double>[];
    final encoderNativeSampleLifetimeValues = <double>[];
    final encoderNativeSampleLifetimeMaxValues = <double>[];
    var encoderNativeSampleLifetimeSamples = 0;
    String? encoderNativeAdapterLuid;
    int? encoderNativeAdapterVendorId;
    int? encoderNativeAdapterDeviceId;
    final encoderProcessInputValues = <double>[];
    final encoderProcessOutputValues = <double>[];
    final encoderEncodedCallbackValues = <double>[];
    final encoderEncodedCallbackQueueWaitValues = <double>[];
    final encoderEncodedCallbackEnqueueValues = <double>[];
    var encoderEncodedCallbackAsyncFrames = 0;
    var encoderMaxEncodedCallbackQueueDepth = 0;
    var encoderMaxEncodedCallbackDrops = 0;
    var encoderMaxEncodedCallbackOutputs = 0;
    final encoderStages = <String>{};
    var encoderOutputFrames = 0;
    var encoderOutputBytes = 0;
    var encoderMaxQueueDepth = 0;
    var encoderMaxRetainedSamples = 0;
    var encoderMaxEncodedOutputs = 0;
    final webrtcSourceOnFrameMsValues = <double>[];
    final webrtcSourceOnFrameMaxMsValues = <double>[];
    final webrtcSourceAdaptMsValues = <double>[];
    final webrtcSourceAdaptMaxMsValues = <double>[];
    final webrtcSourceScaleMsValues = <double>[];
    final webrtcSourceScaleMaxMsValues = <double>[];
    final webrtcSourceBroadcastMsValues = <double>[];
    final webrtcSourceBroadcastMaxMsValues = <double>[];
    var webrtcSourceOnFrameSamples = 0;
    var webrtcSourceAdapterDrops = 0;
    var webrtcSourceScaledFrames = 0;
    final webrtcVideoBroadcasterMsValues = <double>[];
    final webrtcVideoBroadcasterMaxMsValues = <double>[];
    var webrtcVideoBroadcasterSamples = 0;
    final webrtcVideoBroadcasterLockWaitMsValues = <double>[];
    final webrtcVideoBroadcasterLockWaitMaxMsValues = <double>[];
    final webrtcVideoBroadcasterSinkDispatchMsValues = <double>[];
    final webrtcVideoBroadcasterSinkDispatchMaxMsValues = <double>[];
    final webrtcVideoBroadcasterMaxSingleSinkMsValues = <double>[];
    int? webrtcVideoBroadcasterSlowSinkId;
    double? webrtcVideoBroadcasterSlowSinkMs;
    String? webrtcVideoBroadcasterSlowSinkLabel;
    int? webrtcVideoBroadcasterSlowestSinkId;
    double? webrtcVideoBroadcasterSlowestSinkMs;
    double? webrtcVideoBroadcasterSlowestSinkAverageMs;
    var webrtcVideoBroadcasterSlowestSinkFrames = 0;
    String? webrtcVideoBroadcasterSlowestSinkLabel;
    var webrtcVideoBroadcasterSinkCount = 0;
    var webrtcVideoBroadcasterMaxSinkCount = 0;
    var webrtcVideoBroadcasterActiveSinks = 0;
    var webrtcVideoBroadcasterInactiveSinks = 0;
    var webrtcVideoBroadcasterRequestedSinks = 0;
    var webrtcVideoBroadcasterBlackFrameSinks = 0;
    var webrtcVideoBroadcasterRotationAppliedSinks = 0;
    var webrtcVideoBroadcasterInactiveNativeSinkBypassReported = false;
    var webrtcVideoBroadcasterInactiveNativeSinksBypassed = 0;
    var webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = 0;
    var webrtcVideoBroadcasterInactiveNativeSinksRefreshed = 0;
    var webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast = 0;
    String? webrtcVideoBroadcasterSinkRoster;
    var webrtcVideoBroadcasterBlackSinks = 0;
    var webrtcVideoBroadcasterRotationDiscards = 0;
    var webrtcVideoBroadcasterUpdateRectCleared = 0;
    var webrtcVideoBroadcasterDiscardedFrames = 0;
    final webrtcVsePostToOnFrameMsValues = <double>[];
    final webrtcVsePostToOnFrameMaxMsValues = <double>[];
    final webrtcVseOnFrameMsValues = <double>[];
    final webrtcVseOnFrameMaxMsValues = <double>[];
    var webrtcVseOnFrameSamples = 0;
    var webrtcVseQueueOverloadDrops = 0;
    var webrtcVseEncoderQueueDrops = 0;
    var webrtcVseCwndDrops = 0;
    var webrtcVseBadTimestampDrops = 0;
    final webrtcVseMaybeEncodeMsValues = <double>[];
    final webrtcVseMaybeEncodeMaxMsValues = <double>[];
    var webrtcVseMaybeEncodeSamples = 0;
    var webrtcVsePendingReplacedDrops = 0;
    var webrtcVseSizeDrops = 0;
    var webrtcVsePausedDrops = 0;
    var webrtcVseMediaOptimizationDrops = 0;
    final webrtcVseEncodeFrameMsValues = <double>[];
    final webrtcVseEncodeFrameMaxMsValues = <double>[];
    final webrtcVseMaybePreEncodeMsValues = <double>[];
    final webrtcVseMaybePreEncodeMaxMsValues = <double>[];
    final webrtcVseMaybeEncodeCallMsValues = <double>[];
    final webrtcVseMaybeEncodeCallMaxMsValues = <double>[];
    final webrtcVseMaybeFrameSizeMsValues = <double>[];
    final webrtcVseMaybeFrameSizeMaxMsValues = <double>[];
    final webrtcVseMaybeParameterUpdateMsValues = <double>[];
    final webrtcVseMaybeParameterUpdateMaxMsValues = <double>[];
    final webrtcVseMaybeReconfigureMsValues = <double>[];
    final webrtcVseMaybeReconfigureMaxMsValues = <double>[];
    var webrtcVsePendingReconfigureSignals = 0;
    var webrtcVsePendingReconfigureConfigureEncoder = 0;
    var webrtcVsePendingReconfigureFrameInfoChange = 0;
    var webrtcVsePendingReconfigureSourceRestriction = 0;
    var webrtcVsePendingReconfigureUnknown = 0;
    String? webrtcVsePendingReconfigureLastReason;
    final webrtcVseMaybeRateUpdateMsValues = <double>[];
    final webrtcVseMaybeRateUpdateMaxMsValues = <double>[];
    final webrtcVseMaybeDropChecksMsValues = <double>[];
    final webrtcVseMaybeDropChecksMaxMsValues = <double>[];
    final webrtcVseEncodePreEncoderMsValues = <double>[];
    final webrtcVseEncodePreEncoderMaxMsValues = <double>[];
    final webrtcVseEncodeInfoMsValues = <double>[];
    final webrtcVseEncodeInfoMaxMsValues = <double>[];
    final webrtcVseEncodeCropScaleMsValues = <double>[];
    final webrtcVseEncodeCropScaleMaxMsValues = <double>[];
    final webrtcVseEncodeUpdateRectMsValues = <double>[];
    final webrtcVseEncodeUpdateRectMaxMsValues = <double>[];
    final webrtcVseEncodeResourceMsValues = <double>[];
    final webrtcVseEncodeResourceMaxMsValues = <double>[];
    final webrtcVseEncodeMetadataMsValues = <double>[];
    final webrtcVseEncodeMetadataMaxMsValues = <double>[];
    var webrtcVseEncodeFrameSamples = 0;
    final webrtcVideoEncoderEncodeMsValues = <double>[];
    final webrtcVideoEncoderEncodeMaxMsValues = <double>[];
    var webrtcVideoEncoderEncodeSamples = 0;
    var webrtcVseEncodeFailures = 0;
    var webrtcVseEncodeSkippedBeforeEncoder = 0;
    String? webrtcFrameLineageStage;
    int? webrtcFrameLineageFrameId;
    int? webrtcFrameLineageSourceQpc;
    int? webrtcFrameLineageStageQpc;
    double? webrtcFrameLineageFrameAgeMs;
    int? webrtcFrameLineagePreviousFrameId;
    final webrtcFrameCadencePostDelayMsValues = <double>[];
    final webrtcFrameCadencePostDelayMaxMsValues = <double>[];
    final webrtcFrameCadenceCallbackMsValues = <double>[];
    final webrtcFrameCadenceCallbackMaxMsValues = <double>[];
    final webrtcFrameCadenceFrameDurationMsValues = <double>[];
    final webrtcFrameCadenceFrameDurationMaxMsValues = <double>[];
    var webrtcFrameCadenceSends = 0;
    var webrtcFrameCadenceRepeatedSends = 0;
    var webrtcFrameCadencePostDelaySamples = 0;
    var webrtcFrameCadenceOverFrameDurationSends = 0;
    var webrtcFrameCadenceOverloadTriggerSends = 0;
    var webrtcFrameCadenceOverloadActiveSends = 0;
    var webrtcFrameCadenceOverloadDecaySends = 0;
    bool? webrtcFrameCadenceOverloadEnabledSeen;
    bool? webrtcFrameCadenceOverloadDisabledSeen;
    var webrtcFrameCadenceMaxScheduledForProcessing = 0;
    var webrtcFrameCadenceLastScheduledForProcessing = 0;
    var webrtcFrameCadenceMaxQueueOverloadBefore = 0;
    var webrtcFrameCadenceMaxQueueOverloadAfter = 0;
    var webrtcFrameCadenceLastQueueOverloadBefore = 0;
    var webrtcFrameCadenceLastQueueOverloadAfter = 0;
    final webrtcFrameCadenceQueuePostDelayMsValues = <double>[];
    final webrtcFrameCadenceQueuePostDelayMaxMsValues = <double>[];
    var webrtcFrameCadenceQueueFrames = 0;
    var webrtcFrameCadenceQueueOverloadFrames = 0;
    var webrtcFrameCadenceQueuePostDelaySamples = 0;
    var webrtcFrameCadenceQueueMaxScheduledForProcessing = 0;
    var webrtcFrameCadenceQueueLastScheduledForProcessing = 0;
    var webrtcFrameCadenceQueuePassthroughFrames = 0;
    var webrtcFrameCadenceQueueZeroHertzFrames = 0;
    var webrtcFrameCadenceQueueVsyncFrames = 0;
    var webrtcFrameCadenceQueueUnknownFrames = 0;
    bool? webrtcFrameCadenceQueueCoalesceEnabledSeen;
    bool? webrtcFrameCadenceQueueCoalesceDisabledSeen;
    var webrtcFrameCadenceQueueCoalesceThreshold = 0;
    var webrtcFrameCadenceQueueCoalescedDrops = 0;
    bool? webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen;
    bool? webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen;
    var webrtcFrameCadenceQueuePrepostCoalescedDrops = 0;
    var webrtcFrameCadenceQueuePrepostProcessingDrops = 0;
    var webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing = 0;
    String? webrtcFrameCadenceQueueLastMode;
    bool? webrtcFrameCadenceQueueMailboxEnabledSeen;
    var webrtcFrameCadenceQueueMailboxFrames = 0;
    var webrtcFrameCadenceQueueMailboxProcessedFrames = 0;
    var webrtcFrameCadenceQueueMailboxReplacements = 0;
    var webrtcFrameCadenceQueueMailboxStaleDrops = 0;
    bool? webrtcFrameCadenceQueueMailboxProcessingActive;
    bool? webrtcFrameCadenceQueueMailboxProcessingActiveSeen;
    var webrtcFrameCadenceQueueMailboxPendingDepthMax = 0;
    var webrtcFrameCadenceQueueMailboxPendingDepthLast = 0;
    final webrtcFrameCadenceQueueMailboxPendingFrameAgeMsValues = <double>[];
    final webrtcFrameCadenceQueueMailboxPendingFrameAgeMaxMsValues = <double>[];
    var webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples = 0;
    final webrtcFrameCadenceQueueMailboxProcessingFrameAgeMsValues = <double>[];
    final webrtcFrameCadenceQueueMailboxProcessingFrameAgeMaxMsValues =
        <double>[];
    var webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples = 0;
    var webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses = 0;
    final webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMsValues =
        <double>[];
    final webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMaxMsValues =
        <double>[];
    var webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples = 0;
    final webrtcFrameCadenceQueueMailboxProcessingStartToVseMsValues =
        <double>[];
    final webrtcFrameCadenceQueueMailboxProcessingStartToVseMaxMsValues =
        <double>[];
    var webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples = 0;
    final webrtcFrameCadenceQueueMailboxVseCallMsValues = <double>[];
    final webrtcFrameCadenceQueueMailboxVseCallMaxMsValues = <double>[];
    var webrtcFrameCadenceQueueMailboxVseCallSamples = 0;
    var webrtcFrameCadenceQueueMailboxStaleDropThresholdMs = 0;
    var scheduleWaitTimeoutCount = 0;
    var schedulePermanentErrorCount = 0;
    var frameWaitTimeoutCount = 0;
    var framePermanentErrorCount = 0;
    var sourceCaptureSampleCount = 0;
    var wgcCaptureCalls = 0;
    var wgcCaptureSuccessCount = 0;
    var wgcSourceNotCapturableCount = 0;
    var wgcEnsureFrameCalls = 0;
    var wgcEnsureSleepCount = 0;
    var wgcProcessFrameCalls = 0;
    var wgcProcessFrameSuccessCount = 0;
    var wgcFramePoolEmptyCount = 0;
    var wgcFramePoolReuseCount = 0;
    var wgcCaptureFrameNullCount = 0;
    var wgcMappedTextureCreateCount = 0;
    var wgcResizeCount = 0;
    var wgcFramePoolRecreateCount = 0;
    final wgcGetFrameValues = <double>[];
    final wgcMaxGetFrameValues = <double>[];
    final wgcEnsureFrameValues = <double>[];
    final wgcMaxEnsureFrameValues = <double>[];
    final wgcProcessFrameValues = <double>[];
    final wgcMaxProcessFrameValues = <double>[];
    final wgcTryGetFrameValues = <double>[];
    final wgcMaxTryGetFrameValues = <double>[];
    final wgcSurfaceValues = <double>[];
    final wgcMaxSurfaceValues = <double>[];
    final wgcTextureValues = <double>[];
    final wgcMaxTextureValues = <double>[];
    final wgcContentSizeValues = <double>[];
    final wgcMaxContentSizeValues = <double>[];
    final wgcCopyTextureValues = <double>[];
    final wgcMaxCopyTextureValues = <double>[];
    final wgcMapTextureValues = <double>[];
    final wgcMaxMapTextureValues = <double>[];
    final wgcCopyRowsValues = <double>[];
    final wgcMaxCopyRowsValues = <double>[];
    final wgcMonitorScaleValues = <double>[];
    final wgcMaxMonitorScaleValues = <double>[];
    final wgcZeroHertzValues = <double>[];
    final wgcMaxZeroHertzValues = <double>[];
    var gdiCaptureCalls = 0;
    var gdiCaptureSuccessCount = 0;
    var gdiTemporaryErrorCount = 0;
    var gdiPermanentErrorCount = 0;
    var gdiHiddenOrMinimizedCount = 0;
    var gdiRectFailCount = 0;
    var gdiDcFailCount = 0;
    var gdiFrameCreateFailCount = 0;
    var gdiPrintFullCallCount = 0;
    var gdiPrintFullSuccessCount = 0;
    var gdiPrintFallbackCallCount = 0;
    var gdiPrintFallbackSuccessCount = 0;
    var gdiBitBltCallCount = 0;
    var gdiBitBltSuccessCount = 0;
    var gdiFinalPrintFullCount = 0;
    var gdiFinalPrintFallbackCount = 0;
    var gdiFinalBitBltCount = 0;
    var gdiFinalNoneCount = 0;
    var gdiBlackFrameCount = 0;
    var gdiLowVarianceFrameCount = 0;
    var gdiOwnedWindowFrameCount = 0;
    var gdiOwnedWindowCaptureCallCount = 0;
    var gdiOwnedWindowCaptureSuccessCount = 0;
    int? gdiOriginalWidth;
    int? gdiOriginalHeight;
    int? gdiCroppedWidth;
    int? gdiCroppedHeight;
    int? gdiFrameWidth;
    int? gdiFrameHeight;
    final gdiTotalValues = <double>[];
    final gdiMaxTotalValues = <double>[];
    final gdiRectValues = <double>[];
    final gdiMaxRectValues = <double>[];
    final gdiVisibilityValues = <double>[];
    final gdiMaxVisibilityValues = <double>[];
    final gdiGetDcValues = <double>[];
    final gdiMaxGetDcValues = <double>[];
    final gdiGetDcSizeValues = <double>[];
    final gdiMaxGetDcSizeValues = <double>[];
    final gdiCreateFrameValues = <double>[];
    final gdiMaxCreateFrameValues = <double>[];
    final gdiMemDcValues = <double>[];
    final gdiMaxMemDcValues = <double>[];
    final gdiPrintFullValues = <double>[];
    final gdiMaxPrintFullValues = <double>[];
    final gdiPrintFallbackValues = <double>[];
    final gdiMaxPrintFallbackValues = <double>[];
    final gdiBitBltValues = <double>[];
    final gdiMaxBitBltValues = <double>[];
    final gdiCleanupValues = <double>[];
    final gdiMaxCleanupValues = <double>[];
    final gdiCropValues = <double>[];
    final gdiMaxCropValues = <double>[];
    final gdiOwnedEnumValues = <double>[];
    final gdiMaxOwnedEnumValues = <double>[];
    final gdiOwnedCaptureValues = <double>[];
    final gdiMaxOwnedCaptureValues = <double>[];
    final gdiOwnedCompositeValues = <double>[];
    final gdiMaxOwnedCompositeValues = <double>[];
    var captureResultCallbackCount = 0;
    var updatedRegionEmptyCount = 0;
    var updatedRegionNonEmptyCount = 0;
    var updatedRegionRectCount = 0;
    var updatedRegionMaxRectCount = 0;
    final updatedRegionAreaRatioValues = <double>[];
    var updatedRegionAreaRatioWeightedTotal = 0.0;
    var updatedRegionAreaRatioWeightedFrames = 0;
    final maxUpdatedRegionAreaRatioValues = <double>[];
    final updatedRegionAnalysisValues = <double>[];
    var updatedRegionAnalysisWeightedTotal = 0.0;
    var updatedRegionAnalysisWeightedFrames = 0;
    final maxUpdatedRegionAnalysisValues = <double>[];
    var updatedRegionFullFrameCount = 0;
    var updatedRegionTinyFrameCount = 0;
    var parsedFrameCadence = false;
    var duplicatedFrameCount = 0;
    var staleFrameReuseCount = 0;
    var pacerDuplicateSubmitCount = 0;
    var pacerOverwrittenFrameCount = 0;
    var pacerSkippedTickCount = 0;
    int? gameCaptureSourceWidth;
    int? gameCaptureSourceHeight;
    int? gameCaptureOutputWidth;
    int? gameCaptureOutputHeight;
    int? gameCaptureFormat;
    int? gameCaptureBackendContractVersion;
    String? gameCaptureSourceMode;
    String? gameCaptureSourceApi;
    int? gameCaptureSourceApiId;
    String? gameCaptureSourceFormat;
    int? gameCaptureSourceFormatId;
    String? gameCaptureColorSpace;
    String? gameCaptureSyncKind;
    String? gameCaptureReadyState;
    String? gameCaptureFailureReason;
    bool? gameCaptureNativeAdmissionStrictDeadlineEnabled;
    var gameCaptureNativeAdmissionSourceDrivenFreshDueFrames = 0;
    var gameCaptureNativeAdmissionSourceQpcDueFrames = 0;
    var gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames = 0;
    var gameCaptureNativeAdmissionDeadlineDueFrames = 0;
    final gameCaptureNativeAdmissionDeadlineLatenessMsValues = <double>[];
    final gameCaptureNativeAdmissionDeadlineLatenessMaxMsValues = <double>[];
    var gameCaptureNativeAdmissionDeadlineLatenessSamples = 0;
    var gameCaptureNativeAdmissionDeadlineOver1xFrames = 0;
    var gameCaptureNativeAdmissionDeadlineOver2xFrames = 0;
    var gameCaptureNativeAdmissionDeadlineOver3xFrames = 0;
    var gameCaptureNativeAdmissionNoSourceOnDeadlineFrames = 0;
    var gameCaptureNativeAdmissionRepeatedOnDeadlineFrames = 0;
    var gameCaptureNativeAdmissionSubmitOnDeadlineFrames = 0;
    var gameCaptureNativeAdmissionSubmitOnEarlySourceFrames = 0;
    var gameCaptureNativeNv12PendingOnDeadlineFrames = 0;
    var gameCaptureNativeNv12NoPendingOnDeadlineFrames = 0;
    var gameCaptureNativeNv12ReadyOnDeadlineFrames = 0;
    var gameCaptureNativeNv12NoReadyOnDeadlineFrames = 0;
    String? gameCaptureConsumerAdapterLuid;
    int? gameCaptureConsumerAdapterVendorId;
    int? gameCaptureConsumerAdapterDeviceId;
    String? gameCaptureSourceAdapterLuid;
    String? gameCaptureCrossAdapterSuspected;
    final gameCaptureFpsValues = <double>[];
    var gameCaptureSubmittedFrames = 0;
    var gameCaptureRepeatedFrames = 0;
    var gameCaptureDuplicateSkippedFrames = 0;
    var gameCaptureDeliveryQueuedFrames = 0;
    var gameCaptureDeliverySubmittedFrames = 0;
    var gameCaptureDeliveryOverwrittenFrames = 0;
    var gameCaptureDeliveryPacerResyncs = 0;
    var gameCaptureDeliveryPacerLagMaxMs = 0;
    var gameCaptureDeliveryRepeatNoQueuedFrames = 0;
    var gameCaptureDeliverySkipNoQueuedFrames = 0;
    var gameCaptureDeliveryFreshWakeAfterSkipFrames = 0;
    var gameCaptureDeliveryFreshImmediateFrames = 0;
    String? gameCaptureDeliveryRepeatPolicy;
    int? gameCaptureDeliveryQueueDepth;
    final gameCaptureDeliveryRepeatSourceAgeMsValues = <double>[];
    final gameCaptureDeliveryRepeatSourceAgeMaxMsValues = <double>[];
    var gameCaptureDeliveryRepeatSourceAgeSamples = 0;
    final gameCaptureDeliveryOnFrameMsValues = <double>[];
    final gameCaptureDeliveryOnFrameMaxMsValues = <double>[];
    final gameCaptureDeliverySubmitPrepMsValues = <double>[];
    final gameCaptureDeliverySubmitPrepMaxMsValues = <double>[];
    var gameCaptureDeliverySubmitPrepSamples = 0;
    final gameCaptureDeliveryOnFrameCallMsValues = <double>[];
    final gameCaptureDeliveryOnFrameCallMaxMsValues = <double>[];
    var gameCaptureDeliveryOnFrameCallSamples = 0;
    final gameCaptureDeliveryPostOnFrameMsValues = <double>[];
    final gameCaptureDeliveryPostOnFrameMaxMsValues = <double>[];
    var gameCaptureDeliveryPostOnFrameSamples = 0;
    final gameCaptureNativeBufferReleaseMsValues = <double>[];
    final gameCaptureNativeBufferReleaseMaxMsValues = <double>[];
    var gameCaptureNativeBufferReleaseSamples = 0;
    final gameCaptureReadyToQueueMsValues = <double>[];
    final gameCaptureReadyToQueueMaxMsValues = <double>[];
    var gameCaptureReadyToQueueSamples = 0;
    final gameCaptureDeliveryQueueWaitMsValues = <double>[];
    final gameCaptureDeliveryQueueWaitMaxMsValues = <double>[];
    var gameCaptureDeliveryQueueWaitSamples = 0;
    final gameCaptureDeliveryOverwriteAgeMsValues = <double>[];
    final gameCaptureDeliveryOverwriteAgeMaxMsValues = <double>[];
    var gameCaptureDeliveryOverwriteAgeSamples = 0;
    var gameCaptureDeliveryOverwrittenFreshFrames = 0;
    final gameCaptureReadyToSubmitMsValues = <double>[];
    final gameCaptureReadyToSubmitMaxMsValues = <double>[];
    var gameCaptureReadyToSubmitSamples = 0;
    final gameCaptureSourceToSubmitMsValues = <double>[];
    final gameCaptureSourceToSubmitMaxMsValues = <double>[];
    var gameCaptureSourceToSubmitSamples = 0;
    final gameCaptureSourceToReadbackReadyMsValues = <double>[];
    final gameCaptureSourceToReadbackReadyMaxMsValues = <double>[];
    var gameCaptureSourceToReadbackReadySamples = 0;
    final gameCaptureReadbackQueueToMapMsValues = <double>[];
    final gameCaptureReadbackQueueToMapMaxMsValues = <double>[];
    var gameCaptureReadbackQueueToMapSamples = 0;
    final gameCaptureMapToI420MsValues = <double>[];
    final gameCaptureMapToI420MaxMsValues = <double>[];
    var gameCaptureMapToI420Samples = 0;
    final gameCaptureSourceToI420ReadyMsValues = <double>[];
    final gameCaptureSourceToI420ReadyMaxMsValues = <double>[];
    var gameCaptureSourceToI420ReadySamples = 0;
    final gameCaptureSourceToQueueMsValues = <double>[];
    final gameCaptureSourceToQueueMaxMsValues = <double>[];
    var gameCaptureSourceToQueueSamples = 0;
    final gameCaptureSourceDuplicateSkipAgeMsValues = <double>[];
    final gameCaptureSourceDuplicateSkipAgeMaxMsValues = <double>[];
    var gameCaptureSourceDuplicateSkipAgeSamples = 0;
    var gameCaptureCopiedFrames = 0;
    var gameCaptureDroppedFrames = 0;
    var gameCaptureOverwrittenFrames = 0;
    var gameCaptureGpuScaledFrames = 0;
    var gameCaptureGpuScaleFailures = 0;
    var gameCaptureCpuFallbackFrames = 0;
    var gameCaptureNativeNv12SubmittedFrames = 0;
    var gameCaptureNativeNv12QueuedFrames = 0;
    var gameCaptureNativeNv12ReadyFrames = 0;
    var gameCaptureNativeNv12NotReadyPolls = 0;
    String? gameCaptureNativeNv12ReadyPolicy;
    bool? gameCaptureNativeNv12FenceAvailable;
    int? gameCaptureNativeNv12PendingPollMs;
    int? gameCaptureNativeNv12MaxPendingSlots;
    int? gameCaptureNativeNv12ReadyDrainDepth;
    String? gameCaptureNativeNv12FrameOwnership;
    int? gameCaptureNativeNv12WarmupI420Frames;
    bool? gameCaptureNativeNv12SingleInFlightEnabled;
    bool? gameCaptureNativeNv12GpuQueueBackoffEnabled;
    int? gameCaptureNativeNv12GpuQueueBackoffThresholdFrames;
    int? gameCaptureNativeNv12GpuQueueBackoffDurationFrames;
    var gameCaptureNativeNv12FenceSignaledFrames = 0;
    var gameCaptureNativeNv12FenceReadyFrames = 0;
    var gameCaptureNativeNv12FenceSignalFailures = 0;
    var gameCaptureNativeNv12OwnedCopies = 0;
    final gameCaptureNativeNv12OwnedCopyMsValues = <double>[];
    final gameCaptureNativeNv12OwnedCopyMaxMsValues = <double>[];
    var gameCaptureNativeNv12OwnedCopySamples = 0;
    var gameCaptureNativeNv12OverwrittenFrames = 0;
    final gameCaptureNativeNv12OverwriteAgeMsValues = <double>[];
    final gameCaptureNativeNv12OverwriteAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12OverwriteAgeSamples = 0;
    var gameCaptureNativeNv12OverwrittenFreshFrames = 0;
    var gameCaptureNativeNv12ReadyDroppedFrames = 0;
    final gameCaptureNativeNv12ReadyDropAgeMsValues = <double>[];
    final gameCaptureNativeNv12ReadyDropAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12ReadyDropAgeSamples = 0;
    var gameCaptureNativeNv12ReadyDroppedFreshFrames = 0;
    bool? gameCaptureNativeNv12LateReadyDropEnabled;
    int? gameCaptureNativeNv12LateReadyDropThresholdMs;
    var gameCaptureNativeNv12LateReadyDroppedFrames = 0;
    final gameCaptureNativeNv12LateReadyDropAgeMsValues = <double>[];
    final gameCaptureNativeNv12LateReadyDropAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12LateReadyDropAgeSamples = 0;
    var gameCaptureNativeNv12LateReadyDroppedFreshFrames = 0;
    final gameCaptureNativeNv12LateReadyDropBltToReadyMsValues = <double>[];
    final gameCaptureNativeNv12LateReadyDropBltToReadyMaxMsValues = <double>[];
    var gameCaptureNativeNv12LateReadyDropBltToReadySamples = 0;
    var gameCaptureNativeNv12Failures = 0;
    final gameCaptureNativeNv12ConvertMsValues = <double>[];
    final gameCaptureNativeNv12ConvertMaxMsValues = <double>[];
    var gameCaptureNativeNv12ConvertSamples = 0;
    final gameCaptureNativeNv12BgraScaleDrawMsValues = <double>[];
    final gameCaptureNativeNv12BgraScaleDrawMaxMsValues = <double>[];
    var gameCaptureNativeNv12BgraScaleDrawSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltSubmitMsValues = <double>[];
    final gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues = <double>[];
    var gameCaptureNativeNv12VideoProcessorBltSubmitSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltCpuSubmitMsValues = <double>[];
    final gameCaptureNativeNv12VideoProcessorBltCpuSubmitMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltToReadyMsValues = <double>[];
    final gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues = <double>[];
    var gameCaptureNativeNv12VideoProcessorBltToReadySamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMsValues =
        <double>[];
    final gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltGpuExecutionMsValues =
        <double>[];
    final gameCaptureNativeNv12VideoProcessorBltGpuExecutionMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMsValues =
        <double>[];
    final gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples = 0;
    var gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures = 0;
    var gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady = 0;
    var gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint = 0;
    var gameCaptureNativeNv12ReadyObservedImmediateFrames = 0;
    var gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames = 0;
    var gameCaptureNativeNv12ReadyObservedFenceEventFrames = 0;
    var gameCaptureNativeNv12ReadyObservedSourceEventFrames = 0;
    var gameCaptureNativeNv12ReadyObservedWaitOtherFrames = 0;
    var gameCaptureNativeNv12ReadyObservedLoopIdleFrames = 0;
    var gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames = 0;
    var gameCaptureNativeNv12ReadyObservedPreSubmitFrames = 0;
    var gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames = 0;
    var gameCaptureNativeNv12ReadyObservedUnknownFrames = 0;
    var gameCaptureNativeNv12BltToReadyOver1xFrames = 0;
    var gameCaptureNativeNv12BltToReadyOver2xFrames = 0;
    var gameCaptureNativeNv12BltToReadyOver3xFrames = 0;
    final gameCaptureNativeNv12BufferCreateMsValues = <double>[];
    final gameCaptureNativeNv12BufferCreateMaxMsValues = <double>[];
    var gameCaptureNativeNv12BufferCreateSamples = 0;
    final gameCaptureNativeNv12FrameReadyToQueueMsValues = <double>[];
    final gameCaptureNativeNv12FrameReadyToQueueMaxMsValues = <double>[];
    var gameCaptureNativeNv12FrameReadyToQueueSamples = 0;
    final gameCaptureNativeNv12ConversionStartAgeMsValues = <double>[];
    final gameCaptureNativeNv12ConversionStartAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12ConversionStartAgeSamples = 0;
    var gameCaptureNativeNv12SingleInFlightDeferredFrames = 0;
    var gameCaptureNativeNv12SingleInFlightDeferredFreshFrames = 0;
    var gameCaptureNativeNv12SingleInFlightPendingMax = 0;
    final gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMsValues =
        <double>[];
    final gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples = 0;
    var gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames = 0;
    var gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames = 0;
    var gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames = 0;
    final gameCaptureNativeNv12GpuQueueBackoffMsValues = <double>[];
    final gameCaptureNativeNv12GpuQueueBackoffMaxMsValues = <double>[];
    var gameCaptureNativeNv12GpuQueueBackoffSamples = 0;
    final gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMsValues =
        <double>[];
    final gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples = 0;
    final gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMsValues =
        <double>[];
    final gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples = 0;
    bool? gameCaptureNativeNv12AdmissionMailboxEnabled;
    bool? gameCaptureNativeNv12AdmissionMailboxPendingActive;
    var gameCaptureNativeNv12AdmissionMailboxStoredFrames = 0;
    var gameCaptureNativeNv12AdmissionMailboxReplacedFrames = 0;
    var gameCaptureNativeNv12AdmissionMailboxSubmittedFrames = 0;
    var gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames = 0;
    final gameCaptureNativeNv12AdmissionMailboxPendingAgeMsValues = <double>[];
    final gameCaptureNativeNv12AdmissionMailboxPendingAgeMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples = 0;
    final gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMsValues =
        <double>[];
    final gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMaxMsValues =
        <double>[];
    var gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples = 0;
    var gameCaptureNativeNv12StaleBeforeQueueFrames = 0;
    String? gameCaptureNativeNv12HandoffDisabledReason;
    bool? gameCaptureNativeNv12OnFrameBackpressureEnabled;
    int? gameCaptureNativeNv12OnFrameBackpressureThresholdMs;
    int? gameCaptureNativeNv12OnFrameBackpressureFrameLimit;
    var gameCaptureNativeNv12OnFrameBackpressureFrames = 0;
    var gameCaptureNativeNv12OnFrameBackpressureStreak = 0;
    final gameCaptureNativeNv12OnFrameBackpressureMaxMsValues = <double>[];
    bool? gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure;
    var gameCaptureReadbackQueuedFrames = 0;
    var gameCaptureReadbackReadyFrames = 0;
    var gameCaptureReadbackNotReadyFrames = 0;
    var gameCaptureReadbackOverwrittenFrames = 0;
    var gameCaptureReadbackStaleDroppedFrames = 0;
    var gameCaptureReadbackLatencyDroppedFrames = 0;
    var gameCaptureReadbackMapAttempts = 0;
    var gameCaptureSourceFrameIndex = 0;
    var gameCaptureLastSubmittedSourceFrameIndex = 0;
    var gameCaptureSourceFrameRegressions = 0;
    var gameCaptureSourceFrameDuplicates = 0;
    var gameCaptureSourceFrameGaps = 0;
    var gameCaptureSharedSlotMismatches = 0;
    String? gameCaptureTimestampMode;
    var gameCaptureTimestampSourceQpcFrames = 0;
    var gameCaptureTimestampPacedFallbackFrames = 0;
    var gameCaptureTimestampRepeatedFrames = 0;
    final gameCaptureTimestampDeltaMsValues = <double>[];
    final gameCaptureTimestampDeltaMaxMsValues = <double>[];
    var gameCaptureTimestampSamples = 0;
    var gameCaptureTimestampAdjustments = 0;
    final gameCaptureDeliveryWallDeltaMsValues = <double>[];
    final gameCaptureDeliveryWallDeltaMaxMsValues = <double>[];
    final gameCaptureDeliveryWallDeltaMinMsValues = <double>[];
    var gameCaptureDeliveryWallSamples = 0;
    var gameCaptureDeliveryWallOver2xFrames = 0;
    var gameCaptureDeliveryWallOver3xFrames = 0;
    var gameCaptureDeliveryWallUnderHalfFrames = 0;
    final gameCaptureSourceQpcDeltaMsValues = <double>[];
    final gameCaptureSourceQpcDeltaMaxMsValues = <double>[];
    var gameCaptureSourceQpcSamples = 0;
    var gameCaptureSourceQpcRegressions = 0;
    var gameCaptureSourceQpcOver2xFrames = 0;
    var gameCaptureSourceQpcOver3xFrames = 0;
    var gameCaptureSourceQpcUnderHalfFrames = 0;
    var gameCaptureSourceLatestObservedFrames = 0;
    var gameCaptureSourceLatestFrameGaps = 0;
    var gameCaptureSourceLatestFrameRegressions = 0;
    final gameCaptureSourceLatestQpcDeltaMsValues = <double>[];
    final gameCaptureSourceLatestQpcDeltaMaxMsValues = <double>[];
    var gameCaptureSourceLatestQpcSamples = 0;
    var gameCaptureSourceLatestQpcRegressions = 0;
    var gameCaptureSourceLatestQpcOver2xFrames = 0;
    var gameCaptureSourceLatestQpcOver3xFrames = 0;
    var gameCaptureSourceLatestQpcUnderHalfFrames = 0;
    final gameCaptureSourceLatestObservationDeltaMsValues = <double>[];
    final gameCaptureSourceLatestObservationDeltaMaxMsValues = <double>[];
    var gameCaptureSourceLatestObservationSamples = 0;
    var gameCaptureSourceLatestObservationOver2xFrames = 0;
    var gameCaptureSourceLatestObservationOver3xFrames = 0;
    final gameCaptureSourceLatestEventAgeMsValues = <double>[];
    final gameCaptureSourceLatestEventAgeMaxMsValues = <double>[];
    var gameCaptureSourceLatestEventAgeSamples = 0;
    var gameCaptureSourceLatestEventAgeOver1xFrames = 0;
    var gameCaptureSourceLatestEventAgeOver2xFrames = 0;
    var gameCaptureSourceLatestEventAgeOver3xFrames = 0;
    final gameCaptureSourcePublishObservationAgeMsValues = <double>[];
    final gameCaptureSourcePublishObservationAgeMaxMsValues = <double>[];
    var gameCaptureSourcePublishObservationAgeSamples = 0;
    var gameCaptureSourcePublishObservationAgeOver1xFrames = 0;
    var gameCaptureSourcePublishObservationAgeOver2xFrames = 0;
    var gameCaptureSourcePublishObservationAgeOver3xFrames = 0;
    final gameCaptureProducerPresentGapMsValues = <double>[];
    final gameCaptureProducerPresentGapMaxMsValues = <double>[];
    var gameCaptureProducerPresentGapSamples = 0;
    final gameCaptureProducerCaptureGapMsValues = <double>[];
    final gameCaptureProducerCaptureGapMaxMsValues = <double>[];
    var gameCaptureProducerCaptureGapSamples = 0;
    final gameCaptureProducerPresentToPublishMsValues = <double>[];
    final gameCaptureProducerPresentToPublishMaxMsValues = <double>[];
    var gameCaptureProducerPresentToPublishSamples = 0;
    final gameCaptureProducerCopyMsValues = <double>[];
    final gameCaptureProducerCopyMaxMsValues = <double>[];
    var gameCaptureProducerCopySamples = 0;
    final gameCaptureProducerResolveMsValues = <double>[];
    final gameCaptureProducerResolveMaxMsValues = <double>[];
    var gameCaptureProducerResolveSamples = 0;
    var gameCaptureProducerThrottledFrames = 0;
    final gameCaptureCopyMsValues = <double>[];
    final gameCaptureMapMsValues = <double>[];
    final gameCaptureConvertMsValues = <double>[];
    final gameCaptureGpuScaleMsValues = <double>[];
    final gameCaptureReadbackLatencyMsValues = <double>[];
    final gameCaptureReadbackLatencyFrameValues = <double>[];
    var gameCaptureMaxReadbackLatencyFrames = 0;
    var gameCaptureMapFailures = 0;
    var gameCaptureConvertFailures = 0;
    var gameCaptureProofFrames = 0;
    var gameCaptureVisibleProofFrames = 0;
    bool? gameCaptureProofVisible;
    String? gameCaptureProofPath;
    int? gameCaptureProofMinLuma;
    int? gameCaptureProofMaxLuma;
    int? gameCaptureProofNonzeroSamples;
    int? gameCaptureProofSamples;
    var gameCaptureI420ProofFrames = 0;
    var gameCaptureVisibleI420ProofFrames = 0;
    var gameCaptureInitialBlackSkippedFrames = 0;
    bool? gameCaptureVisibleSourceSeen;
    bool? gameCaptureI420ProofVisible;
    String? gameCaptureI420ProofPath;
    int? gameCaptureI420ProofMinLuma;
    int? gameCaptureI420ProofMaxLuma;
    int? gameCaptureI420ProofNonzeroSamples;
    int? gameCaptureI420ProofSamples;
    String? gameCaptureVisualFreshnessSampleMode;
    var gameCaptureVisualFreshnessSampleFrames = 0;
    var gameCaptureVisualFreshnessUniqueFrames = 0;
    final gameCaptureVisualFreshnessUniqueFpsValues = <double>[];
    final gameCaptureVisualFreshnessLongestStaleMsValues = <double>[];
    var gameCaptureVisualFreshnessLongestStaleFrames = 0;
    var gameCaptureVisualFreshnessLowChangeFrames = 0;
    bool? gameCaptureVisualFreshnessArtifactSet;

    void addMarkerDouble(String marker, String key, List<double> values) {
      final value = _doubleFromMarker(marker, key);
      if (value != null && value >= 0) {
        values.add(value);
      }
    }

    void captureWebrtcFrameLineage(String marker) {
      final stage = _tokenFromMarker(marker, 'lineage_stage');
      final frameId = _intFromMarker(marker, 'frame_id');
      if (stage == null && frameId == null) {
        return;
      }
      webrtcFrameLineageStage = stage ?? webrtcFrameLineageStage;
      webrtcFrameLineageFrameId = frameId ?? webrtcFrameLineageFrameId;
      webrtcFrameLineageSourceQpc =
          _intFromMarker(marker, 'source_qpc') ?? webrtcFrameLineageSourceQpc;
      webrtcFrameLineageStageQpc =
          _intFromMarker(marker, 'stage_qpc') ?? webrtcFrameLineageStageQpc;
      webrtcFrameLineageFrameAgeMs =
          _doubleFromMarker(marker, 'frame_age_ms') ??
          webrtcFrameLineageFrameAgeMs;
      webrtcFrameLineagePreviousFrameId =
          _intFromMarker(marker, 'previous_frame_id') ??
          webrtcFrameLineagePreviousFrameId;
    }

    for (final marker in markers) {
      final lowerMarker = marker.toLowerCase();
      if (lowerMarker.contains('native_nv12_encoder_handoff_disabled')) {
        observedCapturer ??= 'game-d3d11-hook';
        sourceType ??= 'game';
        gameCaptureNativeNv12HandoffDisabledReason =
            _tokenFromMarker(marker, 'reason') ??
            gameCaptureNativeNv12HandoffDisabledReason ??
            'unknown';
      }
      if (lowerMarker.contains('native_nv12_encoder_handoff_suspended')) {
        observedCapturer ??= 'game-d3d11-hook';
        sourceType ??= 'game';
        final reason = _tokenFromMarker(marker, 'reason');
        gameCaptureNativeNv12HandoffDisabledReason =
            reason ?? gameCaptureNativeNv12HandoffDisabledReason ?? 'unknown';
        if (reason == 'live_onframe_backpressure') {
          gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure = true;
          gameCaptureNativeNv12OnFrameBackpressureThresholdMs =
              _intFromMarker(marker, 'thresholdMs') ??
              gameCaptureNativeNv12OnFrameBackpressureThresholdMs;
          gameCaptureNativeNv12OnFrameBackpressureFrameLimit =
              _intFromMarker(marker, 'frameLimit') ??
              gameCaptureNativeNv12OnFrameBackpressureFrameLimit;
          gameCaptureNativeNv12OnFrameBackpressureFrames = max(
            gameCaptureNativeNv12OnFrameBackpressureFrames,
            _intFromMarker(marker, 'slowFrames') ?? 0,
          );
          gameCaptureNativeNv12OnFrameBackpressureStreak = max(
            gameCaptureNativeNv12OnFrameBackpressureStreak,
            _intFromMarker(marker, 'streak') ?? 0,
          );
          addMarkerDouble(
            marker,
            'maxMs',
            gameCaptureNativeNv12OnFrameBackpressureMaxMsValues,
          );
          addMarkerDouble(
            marker,
            'onFrameCallMs',
            gameCaptureNativeNv12OnFrameBackpressureMaxMsValues,
          );
        }
      }

      if (lowerMarker.contains('game_capture_visual_freshness') ||
          lowerMarker.contains('game_capture_output_freshness')) {
        observedCapturer ??= 'game-d3d11-hook';
        sourceType ??= 'game';
        gameCaptureVisualFreshnessSampleMode =
            _tokenFromMarkerAny(marker, const [
              'visualFreshnessSampleMode',
              'sampleMode',
              'mode',
            ]) ??
            gameCaptureVisualFreshnessSampleMode;
        gameCaptureVisualFreshnessSampleFrames = max(
          gameCaptureVisualFreshnessSampleFrames,
          _intFromMarkerAny(marker, const [
                'visualFreshnessSampleFrames',
                'sampleFrames',
                'frames',
              ]) ??
              0,
        );
        gameCaptureVisualFreshnessUniqueFrames = max(
          gameCaptureVisualFreshnessUniqueFrames,
          _intFromMarkerAny(marker, const [
                'visualFreshnessUniqueFrames',
                'uniqueFrames',
              ]) ??
              0,
        );
        final uniqueFps = _doubleFromMarkerAny(marker, const [
          'visualFreshnessUniqueFps',
          'uniqueFps',
        ]);
        if (uniqueFps != null && uniqueFps >= 0) {
          gameCaptureVisualFreshnessUniqueFpsValues.add(uniqueFps);
        }
        final longestStaleMs = _doubleFromMarkerAny(marker, const [
          'visualFreshnessLongestStaleMs',
          'longestStaleMs',
        ]);
        if (longestStaleMs != null && longestStaleMs >= 0) {
          gameCaptureVisualFreshnessLongestStaleMsValues.add(longestStaleMs);
        }
        gameCaptureVisualFreshnessLongestStaleFrames = max(
          gameCaptureVisualFreshnessLongestStaleFrames,
          _intFromMarkerAny(marker, const [
                'visualFreshnessLongestStaleFrames',
                'longestStaleFrames',
              ]) ??
              0,
        );
        gameCaptureVisualFreshnessLowChangeFrames = max(
          gameCaptureVisualFreshnessLowChangeFrames,
          _intFromMarkerAny(marker, const [
                'visualFreshnessLowChangeFrames',
                'lowChangeFrames',
              ]) ??
              0,
        );
        gameCaptureVisualFreshnessArtifactSet =
            _boolFromMarkerAny(marker, const [
              'visualFreshnessArtifactSet',
              'artifactSet',
              'artifact',
            ]) ??
            gameCaptureVisualFreshnessArtifactSet;
      }

      if (marker.toLowerCase().contains('latest-frame pacer enabled')) {
        latestFramePacerEnabled = true;
      } else if (marker.toLowerCase().contains('latest-frame pacer disabled')) {
        latestFramePacerEnabled = false;
      }

      final optionsMatch = _captureOptionsPattern.firstMatch(marker);
      if (optionsMatch != null) {
        sourceType = _stringGroup(optionsMatch, 1) ?? sourceType;
        captureBackendMode =
            _stringGroup(optionsMatch, 2) ??
            captureBackendMode ??
            _legacyBackendLabelFromOptions(marker);
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
      }

      final bridgeMatch = _captureBridgePattern.firstMatch(marker);
      if (bridgeMatch != null) {
        sourceType = _stringGroup(bridgeMatch, 1) ?? sourceType;
        requestedMaxWidth = _intGroup(bridgeMatch, 2) ?? requestedMaxWidth;
        requestedMaxHeight = _intGroup(bridgeMatch, 3) ?? requestedMaxHeight;
        captureBackendMode = _stringGroup(bridgeMatch, 5) ?? captureBackendMode;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
        final framePacing = _tokenFromMarker(marker, 'frame_pacing');
        if (framePacing != null) {
          latestFramePacerEnabled = framePacing.toLowerCase() == 'latest';
        }
      }

      final sizeMatch = _captureFrameSizePattern.firstMatch(marker);
      if (sizeMatch != null) {
        nativeSourceWidth = _intGroup(sizeMatch, 1) ?? nativeSourceWidth;
        nativeSourceHeight = _intGroup(sizeMatch, 2) ?? nativeSourceHeight;
        requestedMaxWidth = _intGroup(sizeMatch, 3) ?? requestedMaxWidth;
        requestedMaxHeight = _intGroup(sizeMatch, 4) ?? requestedMaxHeight;
        preEncodeWidth = _intGroup(sizeMatch, 5) ?? preEncodeWidth;
        preEncodeHeight = _intGroup(sizeMatch, 6) ?? preEncodeHeight;
        cropRegion = _boolGroup(sizeMatch, 7) ?? cropRegion;
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
      }

      if (marker.toLowerCase().contains('desktop capture frame size')) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
        final source = _dimensionsFromMarker(marker, 'source');
        nativeSourceWidth = source?.width ?? nativeSourceWidth;
        nativeSourceHeight = source?.height ?? nativeSourceHeight;
        final nativeWindowRect = _dimensionsFromMarker(marker, 'window_rect');
        nativeWindowRectWidth =
            nativeWindowRect?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight =
            nativeWindowRect?.height ?? nativeWindowRectHeight;
        final requestedMax = _dimensionsFromMarker(marker, 'max');
        requestedMaxWidth = requestedMax?.width ?? requestedMaxWidth;
        requestedMaxHeight = requestedMax?.height ?? requestedMaxHeight;
        final content = _dimensionsFromMarker(marker, 'content');
        contentWidth = content?.width ?? contentWidth;
        contentHeight = content?.height ?? contentHeight;
        final output = _dimensionsFromMarker(marker, 'output');
        preEncodeWidth = output?.width ?? preEncodeWidth;
        preEncodeHeight = output?.height ?? preEncodeHeight;
        canvas = _tokenFromMarker(marker, 'canvas') ?? canvas;
        cropRegion = _boolFromMarker(marker, 'crop_region') ?? cropRegion;
      }

      if (marker.toLowerCase().contains('desktop capture pipeline')) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        final nativeSource = _dimensionsFromMarker(marker, 'native_source');
        nativeSourceWidth = nativeSource?.width ?? nativeSourceWidth;
        nativeSourceHeight = nativeSource?.height ?? nativeSourceHeight;
        final requestedMax = _dimensionsFromMarker(marker, 'requested_max');
        requestedMaxWidth = requestedMax?.width ?? requestedMaxWidth;
        requestedMaxHeight = requestedMax?.height ?? requestedMaxHeight;
        final nativeWindowRect = _dimensionsFromMarker(
          marker,
          'native_window_rect',
        );
        nativeWindowRectWidth =
            nativeWindowRect?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight =
            nativeWindowRect?.height ?? nativeWindowRectHeight;
        final content = _dimensionsFromMarker(marker, 'content');
        contentWidth = content?.width ?? contentWidth;
        contentHeight = content?.height ?? contentHeight;
        final preEncode = _dimensionsFromMarker(marker, 'pre_encode');
        preEncodeWidth = preEncode?.width ?? preEncodeWidth;
        preEncodeHeight = preEncode?.height ?? preEncodeHeight;
        final targetFps = _doubleFromMarker(marker, 'target_fps');
        final nativeFps = _doubleFromMarker(marker, 'native_fps');
        if (targetFps != null && targetFps > 0) {
          targetFpsValues.add(targetFps);
        }
        if (nativeFps != null && nativeFps > 0) {
          nativeFpsValues.add(nativeFps);
        }
        canvas = _tokenFromMarker(marker, 'canvas') ?? canvas;
        cropRegion = _boolFromMarker(marker, 'crop_region') ?? cropRegion;
      }

      if (marker.toLowerCase().contains('wgc frame timing')) {
        sourceType = _tokenFromMarker(marker, 'source_type') ?? sourceType;
        final size = _dimensionsFromMarker(marker, 'size');
        nativeSourceWidth = size?.width ?? nativeSourceWidth;
        nativeSourceHeight = size?.height ?? nativeSourceHeight;
        observedCapturer ??= 'wgc';
        wgcCaptureCalls += _intFromMarker(marker, 'calls') ?? 0;
        wgcCaptureSuccessCount += _intFromMarker(marker, 'successes') ?? 0;
        wgcSourceNotCapturableCount +=
            _intFromMarker(marker, 'source_not_capturable') ?? 0;
        wgcEnsureFrameCalls += _intFromMarker(marker, 'ensure_calls') ?? 0;
        wgcEnsureSleepCount += _intFromMarker(marker, 'ensure_sleeps') ?? 0;
        wgcProcessFrameCalls += _intFromMarker(marker, 'process_calls') ?? 0;
        wgcProcessFrameSuccessCount +=
            _intFromMarker(marker, 'process_successes') ?? 0;
        wgcFramePoolEmptyCount +=
            _intFromMarker(marker, 'frame_pool_empty') ?? 0;
        wgcFramePoolReuseCount +=
            _intFromMarker(marker, 'frame_pool_reuse') ?? 0;
        wgcCaptureFrameNullCount +=
            _intFromMarker(marker, 'capture_frame_null') ?? 0;
        wgcMappedTextureCreateCount +=
            _intFromMarker(marker, 'mapped_texture_creates') ?? 0;
        wgcResizeCount += _intFromMarker(marker, 'resizes') ?? 0;
        wgcFramePoolRecreateCount +=
            _intFromMarker(marker, 'frame_pool_recreates') ?? 0;
        addMarkerDouble(marker, 'avg_get_frame_ms', wgcGetFrameValues);
        addMarkerDouble(marker, 'max_get_frame_ms', wgcMaxGetFrameValues);
        addMarkerDouble(marker, 'avg_ensure_frame_ms', wgcEnsureFrameValues);
        addMarkerDouble(marker, 'max_ensure_frame_ms', wgcMaxEnsureFrameValues);
        addMarkerDouble(marker, 'avg_process_frame_ms', wgcProcessFrameValues);
        addMarkerDouble(
          marker,
          'max_process_frame_ms',
          wgcMaxProcessFrameValues,
        );
        addMarkerDouble(marker, 'avg_try_get_frame_ms', wgcTryGetFrameValues);
        addMarkerDouble(
          marker,
          'max_try_get_frame_ms',
          wgcMaxTryGetFrameValues,
        );
        addMarkerDouble(marker, 'avg_surface_ms', wgcSurfaceValues);
        addMarkerDouble(marker, 'max_surface_ms', wgcMaxSurfaceValues);
        addMarkerDouble(marker, 'avg_texture_ms', wgcTextureValues);
        addMarkerDouble(marker, 'max_texture_ms', wgcMaxTextureValues);
        addMarkerDouble(marker, 'avg_content_size_ms', wgcContentSizeValues);
        addMarkerDouble(marker, 'max_content_size_ms', wgcMaxContentSizeValues);
        addMarkerDouble(marker, 'avg_copy_texture_ms', wgcCopyTextureValues);
        addMarkerDouble(marker, 'max_copy_texture_ms', wgcMaxCopyTextureValues);
        addMarkerDouble(marker, 'avg_map_texture_ms', wgcMapTextureValues);
        addMarkerDouble(marker, 'max_map_texture_ms', wgcMaxMapTextureValues);
        addMarkerDouble(marker, 'avg_copy_rows_ms', wgcCopyRowsValues);
        addMarkerDouble(marker, 'max_copy_rows_ms', wgcMaxCopyRowsValues);
        addMarkerDouble(marker, 'avg_monitor_scale_ms', wgcMonitorScaleValues);
        addMarkerDouble(
          marker,
          'max_monitor_scale_ms',
          wgcMaxMonitorScaleValues,
        );
        addMarkerDouble(marker, 'avg_zero_hertz_ms', wgcZeroHertzValues);
        addMarkerDouble(marker, 'max_zero_hertz_ms', wgcMaxZeroHertzValues);
      }

      if (marker.toLowerCase().contains('window gdi frame timing')) {
        sourceType = _tokenFromMarker(marker, 'source_type') ?? sourceType;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'capture_mode') ?? windowGdiCaptureMode;
        observedCapturer ??= 'window-gdi';
        final originalSize = _dimensionsFromMarker(marker, 'original_size');
        gdiOriginalWidth = originalSize?.width ?? gdiOriginalWidth;
        gdiOriginalHeight = originalSize?.height ?? gdiOriginalHeight;
        nativeWindowRectWidth = originalSize?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight = originalSize?.height ?? nativeWindowRectHeight;
        final croppedSize = _dimensionsFromMarker(marker, 'cropped_size');
        gdiCroppedWidth = croppedSize?.width ?? gdiCroppedWidth;
        gdiCroppedHeight = croppedSize?.height ?? gdiCroppedHeight;
        nativeSourceWidth = croppedSize?.width ?? nativeSourceWidth;
        nativeSourceHeight = croppedSize?.height ?? nativeSourceHeight;
        final frameSize = _dimensionsFromMarker(marker, 'frame_size');
        gdiFrameWidth = frameSize?.width ?? gdiFrameWidth;
        gdiFrameHeight = frameSize?.height ?? gdiFrameHeight;
        gdiCaptureCalls += _intFromMarker(marker, 'calls') ?? 0;
        gdiCaptureSuccessCount += _intFromMarker(marker, 'successes') ?? 0;
        gdiTemporaryErrorCount += _intFromMarker(marker, 'temp_errors') ?? 0;
        gdiPermanentErrorCount +=
            _intFromMarker(marker, 'permanent_errors') ?? 0;
        gdiHiddenOrMinimizedCount +=
            _intFromMarker(marker, 'hidden_or_minimized') ?? 0;
        gdiRectFailCount += _intFromMarker(marker, 'rect_fail') ?? 0;
        gdiDcFailCount += _intFromMarker(marker, 'dc_fail') ?? 0;
        gdiFrameCreateFailCount +=
            _intFromMarker(marker, 'frame_create_fail') ?? 0;
        gdiPrintFullCallCount +=
            _intFromMarker(marker, 'print_full_calls') ?? 0;
        gdiPrintFullSuccessCount +=
            _intFromMarker(marker, 'print_full_successes') ?? 0;
        gdiPrintFallbackCallCount +=
            _intFromMarker(marker, 'print_fallback_calls') ?? 0;
        gdiPrintFallbackSuccessCount +=
            _intFromMarker(marker, 'print_fallback_successes') ?? 0;
        gdiBitBltCallCount += _intFromMarker(marker, 'bitblt_calls') ?? 0;
        gdiBitBltSuccessCount +=
            _intFromMarker(marker, 'bitblt_successes') ?? 0;
        gdiFinalPrintFullCount +=
            _intFromMarker(marker, 'final_print_full') ?? 0;
        gdiFinalPrintFallbackCount +=
            _intFromMarker(marker, 'final_print_fallback') ?? 0;
        gdiFinalBitBltCount += _intFromMarker(marker, 'final_bitblt') ?? 0;
        gdiFinalNoneCount += _intFromMarker(marker, 'final_none') ?? 0;
        gdiBlackFrameCount += _intFromMarker(marker, 'black_frame_count') ?? 0;
        gdiLowVarianceFrameCount +=
            _intFromMarker(marker, 'low_variance_frame_count') ?? 0;
        gdiOwnedWindowFrameCount +=
            _intFromMarker(marker, 'owned_window_frames') ?? 0;
        gdiOwnedWindowCaptureCallCount +=
            _intFromMarker(marker, 'owned_capture_calls') ?? 0;
        gdiOwnedWindowCaptureSuccessCount +=
            _intFromMarker(marker, 'owned_capture_successes') ?? 0;
        addMarkerDouble(marker, 'avg_total_ms', gdiTotalValues);
        addMarkerDouble(marker, 'max_total_ms', gdiMaxTotalValues);
        addMarkerDouble(marker, 'avg_rect_ms', gdiRectValues);
        addMarkerDouble(marker, 'max_rect_ms', gdiMaxRectValues);
        addMarkerDouble(marker, 'avg_visibility_ms', gdiVisibilityValues);
        addMarkerDouble(marker, 'max_visibility_ms', gdiMaxVisibilityValues);
        addMarkerDouble(marker, 'avg_get_dc_ms', gdiGetDcValues);
        addMarkerDouble(marker, 'max_get_dc_ms', gdiMaxGetDcValues);
        addMarkerDouble(marker, 'avg_get_dc_size_ms', gdiGetDcSizeValues);
        addMarkerDouble(marker, 'max_get_dc_size_ms', gdiMaxGetDcSizeValues);
        addMarkerDouble(marker, 'avg_create_frame_ms', gdiCreateFrameValues);
        addMarkerDouble(marker, 'max_create_frame_ms', gdiMaxCreateFrameValues);
        addMarkerDouble(marker, 'avg_mem_dc_ms', gdiMemDcValues);
        addMarkerDouble(marker, 'max_mem_dc_ms', gdiMaxMemDcValues);
        addMarkerDouble(marker, 'avg_print_full_ms', gdiPrintFullValues);
        addMarkerDouble(marker, 'max_print_full_ms', gdiMaxPrintFullValues);
        addMarkerDouble(
          marker,
          'avg_print_fallback_ms',
          gdiPrintFallbackValues,
        );
        addMarkerDouble(
          marker,
          'max_print_fallback_ms',
          gdiMaxPrintFallbackValues,
        );
        addMarkerDouble(marker, 'avg_bitblt_ms', gdiBitBltValues);
        addMarkerDouble(marker, 'max_bitblt_ms', gdiMaxBitBltValues);
        addMarkerDouble(marker, 'avg_cleanup_ms', gdiCleanupValues);
        addMarkerDouble(marker, 'max_cleanup_ms', gdiMaxCleanupValues);
        addMarkerDouble(marker, 'avg_crop_ms', gdiCropValues);
        addMarkerDouble(marker, 'max_crop_ms', gdiMaxCropValues);
        addMarkerDouble(marker, 'avg_owned_enum_ms', gdiOwnedEnumValues);
        addMarkerDouble(marker, 'max_owned_enum_ms', gdiMaxOwnedEnumValues);
        addMarkerDouble(marker, 'avg_owned_capture_ms', gdiOwnedCaptureValues);
        addMarkerDouble(
          marker,
          'max_owned_capture_ms',
          gdiMaxOwnedCaptureValues,
        );
        addMarkerDouble(
          marker,
          'avg_owned_composite_ms',
          gdiOwnedCompositeValues,
        );
        addMarkerDouble(
          marker,
          'max_owned_composite_ms',
          gdiMaxOwnedCompositeValues,
        );
      }

      final cadenceMatch = _captureCadencePattern.firstMatch(marker);
      if (cadenceMatch != null) {
        final avgCaptureCall = _doubleGroup(cadenceMatch, 2);
        final maxCaptureCall = _doubleGroup(cadenceMatch, 3);
        if (avgCaptureCall != null && avgCaptureCall > 0) {
          captureCallValues.add(avgCaptureCall);
        }
        if (maxCaptureCall != null && maxCaptureCall > 0) {
          maxCaptureCallValues.add(maxCaptureCall);
        }
        final submittedFps = _doubleGroup(cadenceMatch, 6);
        if (submittedFps != null && submittedFps > 0) {
          submittedFpsValues.add(submittedFps);
        }
        scheduleWaitTimeoutCount += _intGroup(cadenceMatch, 7) ?? 0;
        schedulePermanentErrorCount += _intGroup(cadenceMatch, 8) ?? 0;
        final avgResultCallback = _doubleFromMarker(
          marker,
          'avg_result_callback_ms',
        );
        final maxResultCallback = _doubleFromMarker(
          marker,
          'max_result_callback_ms',
        );
        final avgCallbackEntryDelay = _doubleFromMarker(
          marker,
          'avg_callback_entry_delay_ms',
        );
        final maxCallbackEntryDelay = _doubleFromMarker(
          marker,
          'max_callback_entry_delay_ms',
        );
        final avgSourceCapture = _doubleFromMarker(
          marker,
          'avg_source_capture_ms',
        );
        final maxSourceCapture = _doubleFromMarker(
          marker,
          'max_source_capture_ms',
        );
        final avgAcquireWait = _doubleFromMarker(marker, 'avg_acquire_wait_ms');
        final maxAcquireWait = _doubleFromMarker(marker, 'max_acquire_wait_ms');
        final avgPostCallbackWait = _doubleFromMarker(
          marker,
          'avg_post_callback_wait_ms',
        );
        final maxPostCallbackWait = _doubleFromMarker(
          marker,
          'max_post_callback_wait_ms',
        );
        final avgUnaccountedWait = _doubleFromMarker(
          marker,
          'avg_unaccounted_wait_ms',
        );
        final maxUnaccountedWait = _doubleFromMarker(
          marker,
          'max_unaccounted_wait_ms',
        );
        final markerSourceCaptureCount =
            _intFromMarker(marker, 'source_capture_count') ?? 0;
        if (avgSourceCapture != null && avgSourceCapture >= 0) {
          if (markerSourceCaptureCount > 0) {
            sourceCaptureWeightedTotalMs +=
                avgSourceCapture * markerSourceCaptureCount;
            sourceCaptureWeightedSampleCount += markerSourceCaptureCount;
          } else {
            sourceCaptureValues.add(avgSourceCapture);
          }
        }
        if (maxSourceCapture != null && maxSourceCapture >= 0) {
          maxSourceCaptureValues.add(maxSourceCapture);
        }
        sourceCaptureSampleCount += markerSourceCaptureCount;
        if (avgCallbackEntryDelay != null && avgCallbackEntryDelay >= 0) {
          callbackEntryDelayValues.add(avgCallbackEntryDelay);
        }
        if (maxCallbackEntryDelay != null && maxCallbackEntryDelay >= 0) {
          maxCallbackEntryDelayValues.add(maxCallbackEntryDelay);
        }
        if (avgResultCallback != null && avgResultCallback >= 0) {
          captureResultCallbackValues.add(avgResultCallback);
        }
        if (maxResultCallback != null && maxResultCallback >= 0) {
          maxCaptureResultCallbackValues.add(maxResultCallback);
        }
        if (avgAcquireWait != null && avgAcquireWait >= 0) {
          captureAcquireWaitValues.add(avgAcquireWait);
        }
        if (maxAcquireWait != null && maxAcquireWait >= 0) {
          maxCaptureAcquireWaitValues.add(maxAcquireWait);
        }
        if (avgPostCallbackWait != null && avgPostCallbackWait >= 0) {
          postCallbackWaitValues.add(avgPostCallbackWait);
        }
        if (maxPostCallbackWait != null && maxPostCallbackWait >= 0) {
          maxPostCallbackWaitValues.add(maxPostCallbackWait);
        }
        if (avgUnaccountedWait != null && avgUnaccountedWait >= 0) {
          unaccountedWaitValues.add(avgUnaccountedWait);
        }
        if (maxUnaccountedWait != null && maxUnaccountedWait >= 0) {
          maxUnaccountedWaitValues.add(maxUnaccountedWait);
        }
        captureResultCallbackCount +=
            _intFromMarker(marker, 'callback_count') ?? 0;
      }

      final frameCadenceMatch = _captureFrameCadencePattern.firstMatch(marker);
      if (frameCadenceMatch != null) {
        parsedFrameCadence = true;
        final nativeFps = _doubleGroup(frameCadenceMatch, 1);
        final submittedFps = _doubleGroup(frameCadenceMatch, 2);
        final maxIntervalMs = _doubleGroup(frameCadenceMatch, 3);
        final p95IntervalMs = _doubleGroup(frameCadenceMatch, 4);
        if (nativeFps != null && nativeFps > 0) {
          nativeFpsValues.add(nativeFps);
        }
        if (submittedFps != null && submittedFps > 0) {
          submittedFpsValues.add(submittedFps);
        }
        if (maxIntervalMs != null && maxIntervalMs > 0) {
          maxFrameIntervalValues.add(maxIntervalMs);
        }
        if (p95IntervalMs != null && p95IntervalMs > 0) {
          p95FrameIntervalValues.add(p95IntervalMs);
        }
        duplicatedFrameCount += _intGroup(frameCadenceMatch, 5) ?? 0;
        staleFrameReuseCount += _intGroup(frameCadenceMatch, 6) ?? 0;
        frameWaitTimeoutCount += _intGroup(frameCadenceMatch, 7) ?? 0;
        framePermanentErrorCount += _intGroup(frameCadenceMatch, 8) ?? 0;
      }

      final frameTimingMatch = _captureFrameTimingPattern.firstMatch(marker);
      if (frameTimingMatch != null) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        final avgConvert = _doubleGroup(frameTimingMatch, 1);
        final avgScale = _doubleGroup(frameTimingMatch, 2);
        final avgOnFrame = _doubleGroup(frameTimingMatch, 3);
        final avgCallback = _doubleGroup(frameTimingMatch, 4);
        final maxCallback = _doubleGroup(frameTimingMatch, 5);
        if (avgConvert != null && avgConvert >= 0) {
          frameConvertValues.add(avgConvert);
        }
        if (avgScale != null && avgScale >= 0) {
          frameScaleValues.add(avgScale);
        }
        if (avgOnFrame != null && avgOnFrame >= 0) {
          frameOnFrameValues.add(avgOnFrame);
        }
        if (avgCallback != null && avgCallback > 0) {
          frameCallbackValues.add(avgCallback);
        }
        if (maxCallback != null && maxCallback > 0) {
          maxFrameCallbackValues.add(maxCallback);
        }
        updatedRegionEmptyCount +=
            _intFromMarker(marker, 'updated_region_empty') ?? 0;
        updatedRegionNonEmptyCount +=
            _intFromMarker(marker, 'updated_region_nonempty') ?? 0;
        updatedRegionRectCount +=
            _intFromMarker(marker, 'updated_region_rects') ?? 0;
        updatedRegionMaxRectCount = max(
          updatedRegionMaxRectCount,
          _intFromMarker(marker, 'updated_region_max_rects') ?? 0,
        );
        final avgUpdatedRegionAreaRatio = _doubleFromMarker(
          marker,
          'avg_updated_region_area_ratio',
        );
        final maxUpdatedRegionAreaRatio = _doubleFromMarker(
          marker,
          'max_updated_region_area_ratio',
        );
        final markerFrameCount = _intGroup(frameTimingMatch, 6) ?? 0;
        if (avgUpdatedRegionAreaRatio != null &&
            avgUpdatedRegionAreaRatio >= 0) {
          if (markerFrameCount > 0) {
            updatedRegionAreaRatioWeightedTotal +=
                avgUpdatedRegionAreaRatio * markerFrameCount;
            updatedRegionAreaRatioWeightedFrames += markerFrameCount;
          } else {
            updatedRegionAreaRatioValues.add(avgUpdatedRegionAreaRatio);
          }
        }
        if (maxUpdatedRegionAreaRatio != null &&
            maxUpdatedRegionAreaRatio >= 0) {
          maxUpdatedRegionAreaRatioValues.add(maxUpdatedRegionAreaRatio);
        }
        final avgUpdatedRegionAnalysisMs = _doubleFromMarker(
          marker,
          'avg_updated_region_ms',
        );
        if (avgUpdatedRegionAnalysisMs != null &&
            avgUpdatedRegionAnalysisMs >= 0) {
          if (markerFrameCount > 0) {
            updatedRegionAnalysisWeightedTotal +=
                avgUpdatedRegionAnalysisMs * markerFrameCount;
            updatedRegionAnalysisWeightedFrames += markerFrameCount;
          } else {
            updatedRegionAnalysisValues.add(avgUpdatedRegionAnalysisMs);
          }
        }
        addMarkerDouble(
          marker,
          'max_updated_region_ms',
          maxUpdatedRegionAnalysisValues,
        );
        updatedRegionFullFrameCount +=
            _intFromMarker(marker, 'updated_region_full_frames') ?? 0;
        updatedRegionTinyFrameCount +=
            _intFromMarker(marker, 'updated_region_tiny_frames') ?? 0;
      }

      if (marker.toLowerCase().contains('latest-frame pacer cadence')) {
        latestFramePacerEnabled =
            _boolFromMarker(marker, 'enabled') ?? latestFramePacerEnabled;
        final submittedFps = _doubleFromMarker(marker, 'submitted_fps');
        final uniqueFps = _doubleFromMarker(marker, 'unique_fps');
        final p95IntervalMs = _doubleFromMarker(marker, 'p95_interval_ms');
        final maxIntervalMs = _doubleFromMarker(marker, 'max_interval_ms');
        final avgAgeMs = _doubleFromMarker(marker, 'avg_frame_age_ms');
        final maxAgeMs = _doubleFromMarker(marker, 'max_frame_age_ms');
        final avgOnFrameMs = _doubleFromMarker(marker, 'avg_on_frame_ms');
        final maxOnFrameMs = _doubleFromMarker(marker, 'max_on_frame_ms');
        if (submittedFps != null && submittedFps > 0) {
          pacerSubmittedFpsValues.add(submittedFps);
          submittedFpsValues.add(submittedFps);
        }
        if (uniqueFps != null && uniqueFps > 0) {
          pacerUniqueFpsValues.add(uniqueFps);
        }
        if (p95IntervalMs != null && p95IntervalMs > 0) {
          p95PacerIntervalValues.add(p95IntervalMs);
        }
        if (maxIntervalMs != null && maxIntervalMs > 0) {
          maxPacerIntervalValues.add(maxIntervalMs);
        }
        if (avgAgeMs != null && avgAgeMs >= 0) {
          pacerFrameAgeValues.add(avgAgeMs);
        }
        if (maxAgeMs != null && maxAgeMs >= 0) {
          maxPacerFrameAgeValues.add(maxAgeMs);
        }
        if (avgOnFrameMs != null && avgOnFrameMs >= 0) {
          pacerOnFrameValues.add(avgOnFrameMs);
        }
        if (maxOnFrameMs != null && maxOnFrameMs >= 0) {
          maxPacerOnFrameValues.add(maxOnFrameMs);
        }
        pacerDuplicateSubmitCount +=
            _intFromMarker(marker, 'duplicate_submits') ?? 0;
        pacerOverwrittenFrameCount +=
            _intFromMarker(marker, 'overwritten_frames') ?? 0;
        pacerSkippedTickCount += _intFromMarker(marker, 'skipped_ticks') ?? 0;
      }

      if (marker.toLowerCase().contains('game_capture_webrtc_source')) {
        observedCapturer = 'game-d3d11-hook';
        sourceType ??= 'game';

        final source = _dimensionsFromMarker(marker, 'source');
        gameCaptureSourceWidth = source?.width ?? gameCaptureSourceWidth;
        gameCaptureSourceHeight = source?.height ?? gameCaptureSourceHeight;
        nativeSourceWidth = source?.width ?? nativeSourceWidth;
        nativeSourceHeight = source?.height ?? nativeSourceHeight;

        final output = _dimensionsFromMarker(marker, 'output');
        gameCaptureOutputWidth = output?.width ?? gameCaptureOutputWidth;
        gameCaptureOutputHeight = output?.height ?? gameCaptureOutputHeight;
        preEncodeWidth = output?.width ?? preEncodeWidth;
        preEncodeHeight = output?.height ?? preEncodeHeight;

        gameCaptureFormat =
            _intFromMarker(marker, 'format') ?? gameCaptureFormat;
        gameCaptureBackendContractVersion =
            _intFromMarker(marker, 'backendContractVersion') ??
            gameCaptureBackendContractVersion;
        gameCaptureSourceMode =
            _tokenFromMarker(marker, 'sourceMode') ?? gameCaptureSourceMode;
        gameCaptureSourceApi =
            _tokenFromMarker(marker, 'sourceApi') ?? gameCaptureSourceApi;
        gameCaptureSourceApiId =
            _intFromMarker(marker, 'sourceApiId') ?? gameCaptureSourceApiId;
        gameCaptureSourceFormat =
            _tokenFromMarker(marker, 'sourceFormat') ?? gameCaptureSourceFormat;
        gameCaptureSourceFormatId =
            _intFromMarker(marker, 'sourceFormatId') ??
            gameCaptureSourceFormatId;
        gameCaptureColorSpace =
            _tokenFromMarker(marker, 'colorSpace') ?? gameCaptureColorSpace;
        gameCaptureSyncKind =
            _tokenFromMarker(marker, 'syncKind') ?? gameCaptureSyncKind;
        gameCaptureReadyState =
            _tokenFromMarker(marker, 'readyState') ?? gameCaptureReadyState;
        gameCaptureFailureReason =
            _tokenFromMarker(marker, 'failureReason') ??
            gameCaptureFailureReason;
        gameCaptureNativeAdmissionStrictDeadlineEnabled =
            _boolFromMarker(marker, 'nativeAdmissionStrictDeadlineEnabled') ??
            gameCaptureNativeAdmissionStrictDeadlineEnabled;
        gameCaptureNativeAdmissionSourceDrivenFreshDueFrames = max(
          gameCaptureNativeAdmissionSourceDrivenFreshDueFrames,
          _intFromMarker(marker, 'nativeAdmissionSourceDrivenFreshDue') ?? 0,
        );
        gameCaptureNativeAdmissionSourceQpcDueFrames = max(
          gameCaptureNativeAdmissionSourceQpcDueFrames,
          _intFromMarker(marker, 'nativeAdmissionSourceQpcDue') ?? 0,
        );
        gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames = max(
          gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames,
          _intFromMarker(marker, 'nativeAdmissionEarlySourceDueSuppressed') ??
              0,
        );
        gameCaptureNativeAdmissionDeadlineDueFrames = max(
          gameCaptureNativeAdmissionDeadlineDueFrames,
          _intFromMarker(marker, 'nativeAdmissionDeadlineDue') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeAdmissionDeadlineLatenessMs',
          gameCaptureNativeAdmissionDeadlineLatenessMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeAdmissionDeadlineLatenessMaxMs',
          gameCaptureNativeAdmissionDeadlineLatenessMaxMsValues,
        );
        gameCaptureNativeAdmissionDeadlineLatenessSamples = max(
          gameCaptureNativeAdmissionDeadlineLatenessSamples,
          _intFromMarker(marker, 'nativeAdmissionDeadlineLatenessSamples') ?? 0,
        );
        gameCaptureNativeAdmissionDeadlineOver1xFrames = max(
          gameCaptureNativeAdmissionDeadlineOver1xFrames,
          _intFromMarker(marker, 'nativeAdmissionDeadlineOver1x') ?? 0,
        );
        gameCaptureNativeAdmissionDeadlineOver2xFrames = max(
          gameCaptureNativeAdmissionDeadlineOver2xFrames,
          _intFromMarker(marker, 'nativeAdmissionDeadlineOver2x') ?? 0,
        );
        gameCaptureNativeAdmissionDeadlineOver3xFrames = max(
          gameCaptureNativeAdmissionDeadlineOver3xFrames,
          _intFromMarker(marker, 'nativeAdmissionDeadlineOver3x') ?? 0,
        );
        gameCaptureNativeAdmissionNoSourceOnDeadlineFrames = max(
          gameCaptureNativeAdmissionNoSourceOnDeadlineFrames,
          _intFromMarker(marker, 'nativeAdmissionNoSourceOnDeadline') ?? 0,
        );
        gameCaptureNativeAdmissionRepeatedOnDeadlineFrames = max(
          gameCaptureNativeAdmissionRepeatedOnDeadlineFrames,
          _intFromMarker(marker, 'nativeAdmissionRepeatedOnDeadline') ?? 0,
        );
        gameCaptureNativeAdmissionSubmitOnDeadlineFrames = max(
          gameCaptureNativeAdmissionSubmitOnDeadlineFrames,
          _intFromMarker(marker, 'nativeAdmissionSubmitOnDeadline') ?? 0,
        );
        gameCaptureNativeAdmissionSubmitOnEarlySourceFrames = max(
          gameCaptureNativeAdmissionSubmitOnEarlySourceFrames,
          _intFromMarker(marker, 'nativeAdmissionSubmitOnEarlySource') ?? 0,
        );
        gameCaptureNativeNv12PendingOnDeadlineFrames = max(
          gameCaptureNativeNv12PendingOnDeadlineFrames,
          _intFromMarker(marker, 'nativeNv12PendingOnDeadline') ?? 0,
        );
        gameCaptureNativeNv12NoPendingOnDeadlineFrames = max(
          gameCaptureNativeNv12NoPendingOnDeadlineFrames,
          _intFromMarker(marker, 'nativeNv12NoPendingOnDeadline') ?? 0,
        );
        gameCaptureNativeNv12ReadyOnDeadlineFrames = max(
          gameCaptureNativeNv12ReadyOnDeadlineFrames,
          _intFromMarker(marker, 'nativeNv12ReadyOnDeadline') ?? 0,
        );
        gameCaptureNativeNv12NoReadyOnDeadlineFrames = max(
          gameCaptureNativeNv12NoReadyOnDeadlineFrames,
          _intFromMarker(marker, 'nativeNv12NoReadyOnDeadline') ?? 0,
        );
        gameCaptureConsumerAdapterLuid =
            _tokenFromMarker(marker, 'consumerAdapterLuid') ??
            gameCaptureConsumerAdapterLuid;
        gameCaptureConsumerAdapterVendorId =
            _intFromMarker(marker, 'consumerAdapterVendorId') ??
            gameCaptureConsumerAdapterVendorId;
        gameCaptureConsumerAdapterDeviceId =
            _intFromMarker(marker, 'consumerAdapterDeviceId') ??
            gameCaptureConsumerAdapterDeviceId;
        gameCaptureSourceAdapterLuid =
            _tokenFromMarker(marker, 'sourceAdapterLuid') ??
            gameCaptureSourceAdapterLuid;
        gameCaptureCrossAdapterSuspected =
            _tokenFromMarker(marker, 'crossAdapterSuspected') ??
            gameCaptureCrossAdapterSuspected;

        final fps = _doubleFromMarker(marker, 'fps');
        if (fps != null && fps > 0) {
          gameCaptureFpsValues.add(fps);
          nativeFpsValues.add(fps);
          submittedFpsValues.add(fps);
        }

        gameCaptureSubmittedFrames = max(
          gameCaptureSubmittedFrames,
          _intFromMarker(marker, 'submitted') ?? 0,
        );
        gameCaptureRepeatedFrames = max(
          gameCaptureRepeatedFrames,
          _intFromMarker(marker, 'repeated') ?? 0,
        );
        gameCaptureDuplicateSkippedFrames = max(
          gameCaptureDuplicateSkippedFrames,
          _intFromMarker(marker, 'duplicateSkipped') ?? 0,
        );
        gameCaptureDeliveryQueuedFrames = max(
          gameCaptureDeliveryQueuedFrames,
          _intFromMarker(marker, 'deliveryQueued') ?? 0,
        );
        gameCaptureDeliverySubmittedFrames = max(
          gameCaptureDeliverySubmittedFrames,
          _intFromMarker(marker, 'deliverySubmitted') ?? 0,
        );
        gameCaptureDeliveryOverwrittenFrames = max(
          gameCaptureDeliveryOverwrittenFrames,
          _intFromMarker(marker, 'deliveryOverwritten') ?? 0,
        );
        gameCaptureDeliveryPacerResyncs = max(
          gameCaptureDeliveryPacerResyncs,
          _intFromMarker(marker, 'deliveryPacerResyncs') ??
              _intFromMarker(marker, 'resyncs') ??
              0,
        );
        gameCaptureDeliveryPacerLagMaxMs = max(
          gameCaptureDeliveryPacerLagMaxMs,
          _intFromMarker(marker, 'deliveryPacerLagMaxMs') ??
              _intFromMarker(marker, 'maxLagMs') ??
              _intFromMarker(marker, 'lagMs') ??
              0,
        );
        gameCaptureDeliveryRepeatNoQueuedFrames = max(
          gameCaptureDeliveryRepeatNoQueuedFrames,
          _intFromMarker(marker, 'deliveryRepeatNoQueued') ?? 0,
        );
        gameCaptureDeliverySkipNoQueuedFrames = max(
          gameCaptureDeliverySkipNoQueuedFrames,
          _intFromMarker(marker, 'deliverySkipNoQueued') ?? 0,
        );
        gameCaptureDeliveryFreshWakeAfterSkipFrames = max(
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
          _intFromMarker(marker, 'deliveryFreshWakeAfterSkip') ?? 0,
        );
        gameCaptureDeliveryFreshImmediateFrames = max(
          gameCaptureDeliveryFreshImmediateFrames,
          _intFromMarker(marker, 'deliveryFreshImmediate') ?? 0,
        );
        gameCaptureDeliveryRepeatPolicy =
            _tokenFromMarker(marker, 'deliveryRepeatPolicy') ??
            gameCaptureDeliveryRepeatPolicy;
        gameCaptureDeliveryQueueDepth =
            _intFromMarker(marker, 'deliveryQueueDepth') ??
            _intFromMarker(marker, 'queueDepth') ??
            gameCaptureDeliveryQueueDepth;
        addMarkerDouble(
          marker,
          'deliveryRepeatSourceAgeMs',
          gameCaptureDeliveryRepeatSourceAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryRepeatSourceAgeMaxMs',
          gameCaptureDeliveryRepeatSourceAgeMaxMsValues,
        );
        gameCaptureDeliveryRepeatSourceAgeSamples = max(
          gameCaptureDeliveryRepeatSourceAgeSamples,
          _intFromMarker(marker, 'deliveryRepeatSourceAgeSamples') ?? 0,
        );
        gameCaptureCopiedFrames = max(
          gameCaptureCopiedFrames,
          _intFromMarker(marker, 'copied') ?? 0,
        );
        gameCaptureDroppedFrames = max(
          gameCaptureDroppedFrames,
          _intFromMarker(marker, 'dropped') ?? 0,
        );
        gameCaptureOverwrittenFrames = max(
          gameCaptureOverwrittenFrames,
          _intFromMarker(marker, 'overwritten') ?? 0,
        );
        gameCaptureGpuScaledFrames = max(
          gameCaptureGpuScaledFrames,
          _intFromMarker(marker, 'gpuScaled') ?? 0,
        );
        gameCaptureGpuScaleFailures = max(
          gameCaptureGpuScaleFailures,
          _intFromMarker(marker, 'gpuScaleFailures') ?? 0,
        );
        gameCaptureCpuFallbackFrames = max(
          gameCaptureCpuFallbackFrames,
          _intFromMarker(marker, 'cpuFallback') ?? 0,
        );
        gameCaptureNativeNv12SubmittedFrames = max(
          gameCaptureNativeNv12SubmittedFrames,
          _intFromMarker(marker, 'nativeNv12Submitted') ?? 0,
        );
        gameCaptureNativeNv12QueuedFrames = max(
          gameCaptureNativeNv12QueuedFrames,
          _intFromMarker(marker, 'nativeNv12Queued') ?? 0,
        );
        gameCaptureNativeNv12ReadyFrames = max(
          gameCaptureNativeNv12ReadyFrames,
          _intFromMarker(marker, 'nativeNv12Ready') ?? 0,
        );
        gameCaptureNativeNv12NotReadyPolls = max(
          gameCaptureNativeNv12NotReadyPolls,
          _intFromMarker(marker, 'nativeNv12NotReadyPolls') ?? 0,
        );
        gameCaptureNativeNv12ReadyPolicy =
            _tokenFromMarker(marker, 'nativeNv12ReadyPolicy') ??
            gameCaptureNativeNv12ReadyPolicy;
        gameCaptureNativeNv12FenceAvailable =
            _boolFromMarker(marker, 'nativeNv12FenceAvailable') ??
            gameCaptureNativeNv12FenceAvailable;
        gameCaptureNativeNv12PendingPollMs =
            _intFromMarker(marker, 'nativeNv12PendingPollMs') ??
            gameCaptureNativeNv12PendingPollMs;
        gameCaptureNativeNv12MaxPendingSlots =
            _intFromMarker(marker, 'nativeNv12MaxPendingSlots') ??
            gameCaptureNativeNv12MaxPendingSlots;
        gameCaptureNativeNv12ReadyDrainDepth =
            _intFromMarker(marker, 'nativeNv12ReadyDrainDepth') ??
            gameCaptureNativeNv12ReadyDrainDepth;
        gameCaptureNativeNv12FrameOwnership =
            _tokenFromMarker(marker, 'nativeNv12FrameOwnership') ??
            gameCaptureNativeNv12FrameOwnership;
        gameCaptureNativeNv12WarmupI420Frames =
            _intFromMarker(marker, 'nativeNv12WarmupI420Frames') ??
            gameCaptureNativeNv12WarmupI420Frames;
        gameCaptureNativeNv12SingleInFlightEnabled =
            _boolFromMarker(marker, 'nativeNv12SingleInFlightEnabled') ??
            gameCaptureNativeNv12SingleInFlightEnabled;
        gameCaptureNativeNv12GpuQueueBackoffEnabled =
            _boolFromMarker(marker, 'nativeNv12GpuQueueBackoffEnabled') ??
            gameCaptureNativeNv12GpuQueueBackoffEnabled;
        gameCaptureNativeNv12GpuQueueBackoffThresholdFrames =
            _intFromMarker(
              marker,
              'nativeNv12GpuQueueBackoffThresholdFrames',
            ) ??
            gameCaptureNativeNv12GpuQueueBackoffThresholdFrames;
        gameCaptureNativeNv12GpuQueueBackoffDurationFrames =
            _intFromMarker(marker, 'nativeNv12GpuQueueBackoffDurationFrames') ??
            gameCaptureNativeNv12GpuQueueBackoffDurationFrames;
        gameCaptureNativeNv12OnFrameBackpressureEnabled =
            _boolFromMarker(marker, 'nativeNv12OnFrameBackpressureEnabled') ??
            gameCaptureNativeNv12OnFrameBackpressureEnabled;
        gameCaptureNativeNv12OnFrameBackpressureThresholdMs =
            _intFromMarker(
              marker,
              'nativeNv12OnFrameBackpressureThresholdMs',
            ) ??
            gameCaptureNativeNv12OnFrameBackpressureThresholdMs;
        gameCaptureNativeNv12OnFrameBackpressureFrameLimit =
            _intFromMarker(marker, 'nativeNv12OnFrameBackpressureFrameLimit') ??
            gameCaptureNativeNv12OnFrameBackpressureFrameLimit;
        gameCaptureNativeNv12LateReadyDropEnabled =
            _boolFromMarker(marker, 'nativeNv12LateReadyDropEnabled') ??
            gameCaptureNativeNv12LateReadyDropEnabled;
        gameCaptureNativeNv12LateReadyDropThresholdMs =
            _intFromMarker(marker, 'nativeNv12LateReadyDropThresholdMs') ??
            gameCaptureNativeNv12LateReadyDropThresholdMs;
        gameCaptureNativeNv12FenceSignaledFrames = max(
          gameCaptureNativeNv12FenceSignaledFrames,
          _intFromMarker(marker, 'nativeNv12FenceSignaled') ?? 0,
        );
        gameCaptureNativeNv12FenceReadyFrames = max(
          gameCaptureNativeNv12FenceReadyFrames,
          _intFromMarker(marker, 'nativeNv12FenceReady') ?? 0,
        );
        gameCaptureNativeNv12FenceSignalFailures = max(
          gameCaptureNativeNv12FenceSignalFailures,
          _intFromMarker(marker, 'nativeNv12FenceSignalFailures') ?? 0,
        );
        gameCaptureNativeNv12OwnedCopies = max(
          gameCaptureNativeNv12OwnedCopies,
          _intFromMarker(marker, 'nativeNv12OwnedCopies') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OwnedCopyMs',
          gameCaptureNativeNv12OwnedCopyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OwnedCopyMaxMs',
          gameCaptureNativeNv12OwnedCopyMaxMsValues,
        );
        gameCaptureNativeNv12OwnedCopySamples = max(
          gameCaptureNativeNv12OwnedCopySamples,
          _intFromMarker(marker, 'nativeNv12OwnedCopySamples') ?? 0,
        );
        gameCaptureNativeNv12OverwrittenFrames = max(
          gameCaptureNativeNv12OverwrittenFrames,
          _intFromMarker(marker, 'nativeNv12Overwritten') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OverwriteAgeMs',
          gameCaptureNativeNv12OverwriteAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OverwriteAgeMaxMs',
          gameCaptureNativeNv12OverwriteAgeMaxMsValues,
        );
        gameCaptureNativeNv12OverwriteAgeSamples = max(
          gameCaptureNativeNv12OverwriteAgeSamples,
          _intFromMarker(marker, 'nativeNv12OverwriteAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12OverwrittenFreshFrames = max(
          gameCaptureNativeNv12OverwrittenFreshFrames,
          _intFromMarker(marker, 'nativeNv12OverwrittenFresh') ?? 0,
        );
        gameCaptureNativeNv12ReadyDroppedFrames = max(
          gameCaptureNativeNv12ReadyDroppedFrames,
          _intFromMarker(marker, 'nativeNv12ReadyDropped') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ReadyDropAgeMs',
          gameCaptureNativeNv12ReadyDropAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ReadyDropAgeMaxMs',
          gameCaptureNativeNv12ReadyDropAgeMaxMsValues,
        );
        gameCaptureNativeNv12ReadyDropAgeSamples = max(
          gameCaptureNativeNv12ReadyDropAgeSamples,
          _intFromMarker(marker, 'nativeNv12ReadyDropAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12ReadyDroppedFreshFrames = max(
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
          _intFromMarker(marker, 'nativeNv12ReadyDroppedFresh') ?? 0,
        );
        gameCaptureNativeNv12LateReadyDroppedFrames = max(
          gameCaptureNativeNv12LateReadyDroppedFrames,
          _intFromMarker(marker, 'nativeNv12LateReadyDropped') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12LateReadyDropAgeMs',
          gameCaptureNativeNv12LateReadyDropAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12LateReadyDropAgeMaxMs',
          gameCaptureNativeNv12LateReadyDropAgeMaxMsValues,
        );
        gameCaptureNativeNv12LateReadyDropAgeSamples = max(
          gameCaptureNativeNv12LateReadyDropAgeSamples,
          _intFromMarker(marker, 'nativeNv12LateReadyDropAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12LateReadyDroppedFreshFrames = max(
          gameCaptureNativeNv12LateReadyDroppedFreshFrames,
          _intFromMarker(marker, 'nativeNv12LateReadyDroppedFresh') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12LateReadyDropBltToReadyMs',
          gameCaptureNativeNv12LateReadyDropBltToReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12LateReadyDropBltToReadyMaxMs',
          gameCaptureNativeNv12LateReadyDropBltToReadyMaxMsValues,
        );
        gameCaptureNativeNv12LateReadyDropBltToReadySamples = max(
          gameCaptureNativeNv12LateReadyDropBltToReadySamples,
          _intFromMarker(marker, 'nativeNv12LateReadyDropBltToReadySamples') ??
              0,
        );
        gameCaptureNativeNv12Failures = max(
          gameCaptureNativeNv12Failures,
          _intFromMarker(marker, 'nativeNv12Failures') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConvertMs',
          gameCaptureNativeNv12ConvertMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConvertMaxMs',
          gameCaptureNativeNv12ConvertMaxMsValues,
        );
        gameCaptureNativeNv12ConvertSamples = max(
          gameCaptureNativeNv12ConvertSamples,
          _intFromMarker(marker, 'nativeNv12ConvertSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BgraScaleDrawMs',
          gameCaptureNativeNv12BgraScaleDrawMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BgraScaleDrawMaxMs',
          gameCaptureNativeNv12BgraScaleDrawMaxMsValues,
        );
        gameCaptureNativeNv12BgraScaleDrawSamples = max(
          gameCaptureNativeNv12BgraScaleDrawSamples,
          _intFromMarker(marker, 'nativeNv12BgraScaleDrawSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitMaxMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltSubmitSamples = max(
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
          _intFromMarker(marker, 'nativeNv12VideoProcessorBltSubmitSamples') ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltCpuSubmitMs',
          gameCaptureNativeNv12VideoProcessorBltCpuSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltCpuSubmitMaxMs',
          gameCaptureNativeNv12VideoProcessorBltCpuSubmitMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples = max(
          gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltCpuSubmitSamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltToReadyMs',
          gameCaptureNativeNv12VideoProcessorBltToReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltToReadyMaxMs',
          gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltToReadySamples = max(
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
          _intFromMarker(marker, 'nativeNv12VideoProcessorBltToReadySamples') ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitToFenceMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitToFenceMaxMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples = max(
          gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltSubmitToFenceSamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltGpuExecutionMs',
          gameCaptureNativeNv12VideoProcessorBltGpuExecutionMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltGpuExecutionMaxMs',
          gameCaptureNativeNv12VideoProcessorBltGpuExecutionMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples = max(
          gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltGpuExecutionSamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs',
          gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMs',
          gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples = max(
          gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples',
              ) ??
              0,
        );
        gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures = max(
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltGpuTimestampFailures',
              ) ??
              0,
        );
        gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady = max(
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltGpuTimestampNotReady',
              ) ??
              0,
        );
        gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint = max(
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltGpuTimestampDisjoint',
              ) ??
              0,
        );
        gameCaptureNativeNv12ReadyObservedImmediateFrames = max(
          gameCaptureNativeNv12ReadyObservedImmediateFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedImmediate') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames = max(
          gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames,
          _intFromMarker(
                marker,
                'nativeNv12ReadyObservedPostFenceRegistration',
              ) ??
              0,
        );
        gameCaptureNativeNv12ReadyObservedFenceEventFrames = max(
          gameCaptureNativeNv12ReadyObservedFenceEventFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedFenceEvent') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedSourceEventFrames = max(
          gameCaptureNativeNv12ReadyObservedSourceEventFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedSourceEvent') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedWaitOtherFrames = max(
          gameCaptureNativeNv12ReadyObservedWaitOtherFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedWaitOther') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedLoopIdleFrames = max(
          gameCaptureNativeNv12ReadyObservedLoopIdleFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedLoopIdle') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames = max(
          gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedDuplicateSkip') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedPreSubmitFrames = max(
          gameCaptureNativeNv12ReadyObservedPreSubmitFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedPreSubmit') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames = max(
          gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedWriteSlotScan') ?? 0,
        );
        gameCaptureNativeNv12ReadyObservedUnknownFrames = max(
          gameCaptureNativeNv12ReadyObservedUnknownFrames,
          _intFromMarker(marker, 'nativeNv12ReadyObservedUnknown') ?? 0,
        );
        gameCaptureNativeNv12BltToReadyOver1xFrames = max(
          gameCaptureNativeNv12BltToReadyOver1xFrames,
          _intFromMarker(marker, 'nativeNv12BltToReadyOver1x') ?? 0,
        );
        gameCaptureNativeNv12BltToReadyOver2xFrames = max(
          gameCaptureNativeNv12BltToReadyOver2xFrames,
          _intFromMarker(marker, 'nativeNv12BltToReadyOver2x') ?? 0,
        );
        gameCaptureNativeNv12BltToReadyOver3xFrames = max(
          gameCaptureNativeNv12BltToReadyOver3xFrames,
          _intFromMarker(marker, 'nativeNv12BltToReadyOver3x') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BufferCreateMs',
          gameCaptureNativeNv12BufferCreateMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BufferCreateMaxMs',
          gameCaptureNativeNv12BufferCreateMaxMsValues,
        );
        gameCaptureNativeNv12BufferCreateSamples = max(
          gameCaptureNativeNv12BufferCreateSamples,
          _intFromMarker(marker, 'nativeNv12BufferCreateSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12FrameReadyToQueueMs',
          gameCaptureNativeNv12FrameReadyToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12FrameReadyToQueueMaxMs',
          gameCaptureNativeNv12FrameReadyToQueueMaxMsValues,
        );
        gameCaptureNativeNv12FrameReadyToQueueSamples = max(
          gameCaptureNativeNv12FrameReadyToQueueSamples,
          _intFromMarker(marker, 'nativeNv12FrameReadyToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConversionStartAgeMs',
          gameCaptureNativeNv12ConversionStartAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConversionStartAgeMaxMs',
          gameCaptureNativeNv12ConversionStartAgeMaxMsValues,
        );
        gameCaptureNativeNv12ConversionStartAgeSamples = max(
          gameCaptureNativeNv12ConversionStartAgeSamples,
          _intFromMarker(marker, 'nativeNv12ConversionStartAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12SingleInFlightDeferredFrames = max(
          gameCaptureNativeNv12SingleInFlightDeferredFrames,
          _intFromMarker(marker, 'nativeNv12SingleInFlightDeferred') ?? 0,
        );
        gameCaptureNativeNv12SingleInFlightDeferredFreshFrames = max(
          gameCaptureNativeNv12SingleInFlightDeferredFreshFrames,
          _intFromMarker(marker, 'nativeNv12SingleInFlightDeferredFresh') ?? 0,
        );
        gameCaptureNativeNv12SingleInFlightPendingMax = max(
          gameCaptureNativeNv12SingleInFlightPendingMax,
          _intFromMarker(marker, 'nativeNv12SingleInFlightPendingMax') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12SingleInFlightDeferredSourceAgeMs',
          gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12SingleInFlightDeferredSourceAgeMaxMs',
          gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMaxMsValues,
        );
        gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples = max(
          gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples,
          _intFromMarker(
                marker,
                'nativeNv12SingleInFlightDeferredSourceAgeSamples',
              ) ??
              0,
        );
        gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames = max(
          gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames,
          _intFromMarker(marker, 'nativeNv12GpuQueueBackoffTriggered') ?? 0,
        );
        gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames = max(
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames,
          _intFromMarker(marker, 'nativeNv12GpuQueueBackoffSuppressed') ?? 0,
        );
        gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames = max(
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames,
          _intFromMarker(marker, 'nativeNv12GpuQueueBackoffSuppressedFresh') ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffMs',
          gameCaptureNativeNv12GpuQueueBackoffMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffMaxMs',
          gameCaptureNativeNv12GpuQueueBackoffMaxMsValues,
        );
        gameCaptureNativeNv12GpuQueueBackoffSamples = max(
          gameCaptureNativeNv12GpuQueueBackoffSamples,
          _intFromMarker(marker, 'nativeNv12GpuQueueBackoffSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffTriggerBltToReadyMs',
          gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffTriggerBltToReadyMaxMs',
          gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMaxMsValues,
        );
        gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples = max(
          gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples,
          _intFromMarker(
                marker,
                'nativeNv12GpuQueueBackoffTriggerBltToReadySamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffSuppressedSourceAgeMs',
          gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12GpuQueueBackoffSuppressedSourceAgeMaxMs',
          gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMaxMsValues,
        );
        gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples = max(
          gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples,
          _intFromMarker(
                marker,
                'nativeNv12GpuQueueBackoffSuppressedSourceAgeSamples',
              ) ??
              0,
        );
        gameCaptureNativeNv12AdmissionMailboxEnabled =
            _boolFromMarker(marker, 'nativeNv12AdmissionMailboxEnabled') ??
            gameCaptureNativeNv12AdmissionMailboxEnabled;
        gameCaptureNativeNv12AdmissionMailboxPendingActive =
            _boolFromMarker(
              marker,
              'nativeNv12AdmissionMailboxPendingActive',
            ) ??
            gameCaptureNativeNv12AdmissionMailboxPendingActive;
        gameCaptureNativeNv12AdmissionMailboxStoredFrames = max(
          gameCaptureNativeNv12AdmissionMailboxStoredFrames,
          _intFromMarker(marker, 'nativeNv12AdmissionMailboxStored') ?? 0,
        );
        gameCaptureNativeNv12AdmissionMailboxReplacedFrames = max(
          gameCaptureNativeNv12AdmissionMailboxReplacedFrames,
          _intFromMarker(marker, 'nativeNv12AdmissionMailboxReplaced') ?? 0,
        );
        gameCaptureNativeNv12AdmissionMailboxSubmittedFrames = max(
          gameCaptureNativeNv12AdmissionMailboxSubmittedFrames,
          _intFromMarker(marker, 'nativeNv12AdmissionMailboxSubmitted') ?? 0,
        );
        gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames = max(
          gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames,
          _intFromMarker(marker, 'nativeNv12AdmissionMailboxStaleDropped') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12AdmissionMailboxPendingAgeMs',
          gameCaptureNativeNv12AdmissionMailboxPendingAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12AdmissionMailboxPendingAgeMaxMs',
          gameCaptureNativeNv12AdmissionMailboxPendingAgeMaxMsValues,
        );
        gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples = max(
          gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples,
          _intFromMarker(
                marker,
                'nativeNv12AdmissionMailboxPendingAgeSamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12AdmissionMailboxSubmitSourceAgeMs',
          gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12AdmissionMailboxSubmitSourceAgeMaxMs',
          gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMaxMsValues,
        );
        gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples = max(
          gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples,
          _intFromMarker(
                marker,
                'nativeNv12AdmissionMailboxSubmitSourceAgeSamples',
              ) ??
              0,
        );
        gameCaptureNativeNv12StaleBeforeQueueFrames = max(
          gameCaptureNativeNv12StaleBeforeQueueFrames,
          _intFromMarker(marker, 'nativeNv12StaleBeforeQueue') ?? 0,
        );
        gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure =
            _boolFromMarker(
              marker,
              'nativeNv12SuspendedAfterOnFrameBackpressure',
            ) ??
            gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure;
        gameCaptureNativeNv12OnFrameBackpressureFrames = max(
          gameCaptureNativeNv12OnFrameBackpressureFrames,
          _intFromMarker(marker, 'nativeNv12OnFrameBackpressureFrames') ?? 0,
        );
        gameCaptureNativeNv12OnFrameBackpressureStreak = max(
          gameCaptureNativeNv12OnFrameBackpressureStreak,
          _intFromMarker(marker, 'nativeNv12OnFrameBackpressureStreak') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OnFrameBackpressureMaxMs',
          gameCaptureNativeNv12OnFrameBackpressureMaxMsValues,
        );
        gameCaptureReadbackQueuedFrames = max(
          gameCaptureReadbackQueuedFrames,
          _intFromMarker(marker, 'readbackQueued') ?? 0,
        );
        gameCaptureReadbackReadyFrames = max(
          gameCaptureReadbackReadyFrames,
          _intFromMarker(marker, 'readbackReady') ?? 0,
        );
        gameCaptureReadbackNotReadyFrames = max(
          gameCaptureReadbackNotReadyFrames,
          _intFromMarker(marker, 'readbackNotReady') ?? 0,
        );
        gameCaptureReadbackOverwrittenFrames = max(
          gameCaptureReadbackOverwrittenFrames,
          _intFromMarker(marker, 'readbackOverwritten') ?? 0,
        );
        gameCaptureReadbackStaleDroppedFrames = max(
          gameCaptureReadbackStaleDroppedFrames,
          _intFromMarker(marker, 'readbackStaleDropped') ?? 0,
        );
        gameCaptureReadbackLatencyDroppedFrames = max(
          gameCaptureReadbackLatencyDroppedFrames,
          _intFromMarker(marker, 'readbackLatencyDropped') ?? 0,
        );
        gameCaptureReadbackMapAttempts = max(
          gameCaptureReadbackMapAttempts,
          _intFromMarker(marker, 'readbackMapAttempts') ?? 0,
        );
        gameCaptureSourceFrameIndex = max(
          gameCaptureSourceFrameIndex,
          _intFromMarker(marker, 'sourceFrameIndex') ?? 0,
        );
        gameCaptureLastSubmittedSourceFrameIndex = max(
          gameCaptureLastSubmittedSourceFrameIndex,
          _intFromMarker(marker, 'lastSubmittedSourceFrameIndex') ?? 0,
        );
        gameCaptureSourceFrameRegressions = max(
          gameCaptureSourceFrameRegressions,
          _intFromMarker(marker, 'sourceFrameRegressions') ?? 0,
        );
        gameCaptureSourceFrameDuplicates = max(
          gameCaptureSourceFrameDuplicates,
          _intFromMarker(marker, 'sourceFrameDuplicates') ?? 0,
        );
        gameCaptureSourceFrameGaps = max(
          gameCaptureSourceFrameGaps,
          _intFromMarker(marker, 'sourceFrameGaps') ?? 0,
        );
        gameCaptureSharedSlotMismatches = max(
          gameCaptureSharedSlotMismatches,
          _intFromMarker(marker, 'sharedSlotMismatches') ?? 0,
        );
        gameCaptureTimestampMode =
            _tokenFromMarker(marker, 'timestampMode') ??
            gameCaptureTimestampMode;
        gameCaptureTimestampSourceQpcFrames = max(
          gameCaptureTimestampSourceQpcFrames,
          _intFromMarker(marker, 'timestampSourceQpcFrames') ?? 0,
        );
        gameCaptureTimestampPacedFallbackFrames = max(
          gameCaptureTimestampPacedFallbackFrames,
          _intFromMarker(marker, 'timestampPacedFallbackFrames') ?? 0,
        );
        gameCaptureTimestampRepeatedFrames = max(
          gameCaptureTimestampRepeatedFrames,
          _intFromMarker(marker, 'timestampRepeatedFrames') ?? 0,
        );
        addMarkerDouble(
          marker,
          'timestampDeltaMs',
          gameCaptureTimestampDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'timestampDeltaMaxMs',
          gameCaptureTimestampDeltaMaxMsValues,
        );
        gameCaptureTimestampSamples = max(
          gameCaptureTimestampSamples,
          _intFromMarker(marker, 'timestampSamples') ?? 0,
        );
        gameCaptureTimestampAdjustments = max(
          gameCaptureTimestampAdjustments,
          _intFromMarker(marker, 'timestampAdjustments') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMs',
          gameCaptureDeliveryWallDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMaxMs',
          gameCaptureDeliveryWallDeltaMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMinMs',
          gameCaptureDeliveryWallDeltaMinMsValues,
        );
        gameCaptureDeliveryWallSamples = max(
          gameCaptureDeliveryWallSamples,
          _intFromMarker(marker, 'deliveryWallSamples') ?? 0,
        );
        gameCaptureDeliveryWallOver2xFrames = max(
          gameCaptureDeliveryWallOver2xFrames,
          _intFromMarker(marker, 'deliveryWallOver2x') ?? 0,
        );
        gameCaptureDeliveryWallOver3xFrames = max(
          gameCaptureDeliveryWallOver3xFrames,
          _intFromMarker(marker, 'deliveryWallOver3x') ?? 0,
        );
        gameCaptureDeliveryWallUnderHalfFrames = max(
          gameCaptureDeliveryWallUnderHalfFrames,
          _intFromMarker(marker, 'deliveryWallUnderHalf') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceQpcDeltaMs',
          gameCaptureSourceQpcDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceQpcDeltaMaxMs',
          gameCaptureSourceQpcDeltaMaxMsValues,
        );
        gameCaptureSourceQpcSamples = max(
          gameCaptureSourceQpcSamples,
          _intFromMarker(marker, 'sourceQpcSamples') ?? 0,
        );
        gameCaptureSourceQpcRegressions = max(
          gameCaptureSourceQpcRegressions,
          _intFromMarker(marker, 'sourceQpcRegressions') ?? 0,
        );
        gameCaptureSourceQpcOver2xFrames = max(
          gameCaptureSourceQpcOver2xFrames,
          _intFromMarker(marker, 'sourceQpcOver2x') ?? 0,
        );
        gameCaptureSourceQpcOver3xFrames = max(
          gameCaptureSourceQpcOver3xFrames,
          _intFromMarker(marker, 'sourceQpcOver3x') ?? 0,
        );
        gameCaptureSourceQpcUnderHalfFrames = max(
          gameCaptureSourceQpcUnderHalfFrames,
          _intFromMarker(marker, 'sourceQpcUnderHalf') ?? 0,
        );
        gameCaptureSourceLatestObservedFrames = max(
          gameCaptureSourceLatestObservedFrames,
          _intFromMarker(marker, 'sourceLatestObservedFrames') ?? 0,
        );
        gameCaptureSourceLatestFrameGaps = max(
          gameCaptureSourceLatestFrameGaps,
          _intFromMarker(marker, 'sourceLatestFrameGaps') ?? 0,
        );
        gameCaptureSourceLatestFrameRegressions = max(
          gameCaptureSourceLatestFrameRegressions,
          _intFromMarker(marker, 'sourceLatestFrameRegressions') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceLatestQpcDeltaMs',
          gameCaptureSourceLatestQpcDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceLatestQpcDeltaMaxMs',
          gameCaptureSourceLatestQpcDeltaMaxMsValues,
        );
        gameCaptureSourceLatestQpcSamples = max(
          gameCaptureSourceLatestQpcSamples,
          _intFromMarker(marker, 'sourceLatestQpcSamples') ?? 0,
        );
        gameCaptureSourceLatestQpcRegressions = max(
          gameCaptureSourceLatestQpcRegressions,
          _intFromMarker(marker, 'sourceLatestQpcRegressions') ?? 0,
        );
        gameCaptureSourceLatestQpcOver2xFrames = max(
          gameCaptureSourceLatestQpcOver2xFrames,
          _intFromMarker(marker, 'sourceLatestQpcOver2x') ?? 0,
        );
        gameCaptureSourceLatestQpcOver3xFrames = max(
          gameCaptureSourceLatestQpcOver3xFrames,
          _intFromMarker(marker, 'sourceLatestQpcOver3x') ?? 0,
        );
        gameCaptureSourceLatestQpcUnderHalfFrames = max(
          gameCaptureSourceLatestQpcUnderHalfFrames,
          _intFromMarker(marker, 'sourceLatestQpcUnderHalf') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceLatestObservationDeltaMs',
          gameCaptureSourceLatestObservationDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceLatestObservationDeltaMaxMs',
          gameCaptureSourceLatestObservationDeltaMaxMsValues,
        );
        gameCaptureSourceLatestObservationSamples = max(
          gameCaptureSourceLatestObservationSamples,
          _intFromMarker(marker, 'sourceLatestObservationSamples') ?? 0,
        );
        gameCaptureSourceLatestObservationOver2xFrames = max(
          gameCaptureSourceLatestObservationOver2xFrames,
          _intFromMarker(marker, 'sourceLatestObservationOver2x') ?? 0,
        );
        gameCaptureSourceLatestObservationOver3xFrames = max(
          gameCaptureSourceLatestObservationOver3xFrames,
          _intFromMarker(marker, 'sourceLatestObservationOver3x') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceLatestEventAgeMs',
          gameCaptureSourceLatestEventAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceLatestEventAgeMaxMs',
          gameCaptureSourceLatestEventAgeMaxMsValues,
        );
        gameCaptureSourceLatestEventAgeSamples = max(
          gameCaptureSourceLatestEventAgeSamples,
          _intFromMarker(marker, 'sourceLatestEventAgeSamples') ?? 0,
        );
        gameCaptureSourceLatestEventAgeOver1xFrames = max(
          gameCaptureSourceLatestEventAgeOver1xFrames,
          _intFromMarker(marker, 'sourceLatestEventAgeOver1x') ?? 0,
        );
        gameCaptureSourceLatestEventAgeOver2xFrames = max(
          gameCaptureSourceLatestEventAgeOver2xFrames,
          _intFromMarker(marker, 'sourceLatestEventAgeOver2x') ?? 0,
        );
        gameCaptureSourceLatestEventAgeOver3xFrames = max(
          gameCaptureSourceLatestEventAgeOver3xFrames,
          _intFromMarker(marker, 'sourceLatestEventAgeOver3x') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourcePublishObservationAgeMs',
          gameCaptureSourcePublishObservationAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'sourcePublishObservationAgeMaxMs',
          gameCaptureSourcePublishObservationAgeMaxMsValues,
        );
        gameCaptureSourcePublishObservationAgeSamples = max(
          gameCaptureSourcePublishObservationAgeSamples,
          _intFromMarker(marker, 'sourcePublishObservationAgeSamples') ?? 0,
        );
        gameCaptureSourcePublishObservationAgeOver1xFrames = max(
          gameCaptureSourcePublishObservationAgeOver1xFrames,
          _intFromMarker(marker, 'sourcePublishObservationAgeOver1x') ?? 0,
        );
        gameCaptureSourcePublishObservationAgeOver2xFrames = max(
          gameCaptureSourcePublishObservationAgeOver2xFrames,
          _intFromMarker(marker, 'sourcePublishObservationAgeOver2x') ?? 0,
        );
        gameCaptureSourcePublishObservationAgeOver3xFrames = max(
          gameCaptureSourcePublishObservationAgeOver3xFrames,
          _intFromMarker(marker, 'sourcePublishObservationAgeOver3x') ?? 0,
        );
        addMarkerDouble(
          marker,
          'producerPresentGapMs',
          gameCaptureProducerPresentGapMsValues,
        );
        addMarkerDouble(
          marker,
          'producerPresentGapMaxMs',
          gameCaptureProducerPresentGapMaxMsValues,
        );
        gameCaptureProducerPresentGapSamples = max(
          gameCaptureProducerPresentGapSamples,
          _intFromMarker(marker, 'producerPresentGapSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'producerCaptureGapMs',
          gameCaptureProducerCaptureGapMsValues,
        );
        addMarkerDouble(
          marker,
          'producerCaptureGapMaxMs',
          gameCaptureProducerCaptureGapMaxMsValues,
        );
        gameCaptureProducerCaptureGapSamples = max(
          gameCaptureProducerCaptureGapSamples,
          _intFromMarker(marker, 'producerCaptureGapSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'producerPresentToPublishMs',
          gameCaptureProducerPresentToPublishMsValues,
        );
        addMarkerDouble(
          marker,
          'producerPresentToPublishMaxMs',
          gameCaptureProducerPresentToPublishMaxMsValues,
        );
        gameCaptureProducerPresentToPublishSamples = max(
          gameCaptureProducerPresentToPublishSamples,
          _intFromMarker(marker, 'producerPresentToPublishSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'producerCopyMs',
          gameCaptureProducerCopyMsValues,
        );
        addMarkerDouble(
          marker,
          'producerCopyMaxMs',
          gameCaptureProducerCopyMaxMsValues,
        );
        gameCaptureProducerCopySamples = max(
          gameCaptureProducerCopySamples,
          _intFromMarker(marker, 'producerCopySamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'producerResolveMs',
          gameCaptureProducerResolveMsValues,
        );
        addMarkerDouble(
          marker,
          'producerResolveMaxMs',
          gameCaptureProducerResolveMaxMsValues,
        );
        gameCaptureProducerResolveSamples = max(
          gameCaptureProducerResolveSamples,
          _intFromMarker(marker, 'producerResolveSamples') ?? 0,
        );
        gameCaptureProducerThrottledFrames = max(
          gameCaptureProducerThrottledFrames,
          _intFromMarker(marker, 'producerThrottledFrames') ?? 0,
        );
        gameCaptureMaxReadbackLatencyFrames = max(
          gameCaptureMaxReadbackLatencyFrames,
          _intFromMarker(marker, 'readbackLatencyFramesMax') ?? 0,
        );
        gameCaptureMapFailures = max(
          gameCaptureMapFailures,
          _intFromMarker(marker, 'mapFailures') ?? 0,
        );
        gameCaptureConvertFailures = max(
          gameCaptureConvertFailures,
          _intFromMarker(marker, 'convertFailures') ?? 0,
        );
        gameCaptureProofFrames = max(
          gameCaptureProofFrames,
          _intFromMarker(marker, 'proofFrames') ?? 0,
        );
        gameCaptureVisibleProofFrames = max(
          gameCaptureVisibleProofFrames,
          _intFromMarker(marker, 'visibleProofFrames') ?? 0,
        );
        gameCaptureI420ProofFrames = max(
          gameCaptureI420ProofFrames,
          _intFromMarker(marker, 'i420ProofFrames') ?? 0,
        );
        gameCaptureVisibleI420ProofFrames = max(
          gameCaptureVisibleI420ProofFrames,
          _intFromMarker(marker, 'visibleI420ProofFrames') ?? 0,
        );
        gameCaptureInitialBlackSkippedFrames = max(
          gameCaptureInitialBlackSkippedFrames,
          _intFromMarker(marker, 'initialBlackSkipped') ??
              _intFromMarker(marker, 'skipped') ??
              0,
        );
        gameCaptureVisibleSourceSeen =
            _boolFromMarker(marker, 'visibleSourceSeen') ??
            gameCaptureVisibleSourceSeen;
        addMarkerDouble(marker, 'copyMs', gameCaptureCopyMsValues);
        addMarkerDouble(marker, 'mapMs', gameCaptureMapMsValues);
        addMarkerDouble(marker, 'convertMs', gameCaptureConvertMsValues);
        addMarkerDouble(marker, 'gpuScaleMs', gameCaptureGpuScaleMsValues);
        addMarkerDouble(
          marker,
          'deliveryOnFrameMs',
          gameCaptureDeliveryOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameMaxMs',
          gameCaptureDeliveryOnFrameMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'deliverySubmitPrepMs',
          gameCaptureDeliverySubmitPrepMsValues,
        );
        addMarkerDouble(
          marker,
          'deliverySubmitPrepMaxMs',
          gameCaptureDeliverySubmitPrepMaxMsValues,
        );
        gameCaptureDeliverySubmitPrepSamples = max(
          gameCaptureDeliverySubmitPrepSamples,
          _intFromMarker(marker, 'deliverySubmitPrepSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameCallMs',
          gameCaptureDeliveryOnFrameCallMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameCallMaxMs',
          gameCaptureDeliveryOnFrameCallMaxMsValues,
        );
        gameCaptureDeliveryOnFrameCallSamples = max(
          gameCaptureDeliveryOnFrameCallSamples,
          _intFromMarker(marker, 'deliveryOnFrameCallSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryPostOnFrameMs',
          gameCaptureDeliveryPostOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryPostOnFrameMaxMs',
          gameCaptureDeliveryPostOnFrameMaxMsValues,
        );
        gameCaptureDeliveryPostOnFrameSamples = max(
          gameCaptureDeliveryPostOnFrameSamples,
          _intFromMarker(marker, 'deliveryPostOnFrameSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeBufferReleaseMs',
          gameCaptureNativeBufferReleaseMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeBufferReleaseMaxMs',
          gameCaptureNativeBufferReleaseMaxMsValues,
        );
        gameCaptureNativeBufferReleaseSamples = max(
          gameCaptureNativeBufferReleaseSamples,
          _intFromMarker(marker, 'nativeBufferReleaseSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readyToQueueMs',
          gameCaptureReadyToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'readyToQueueMaxMs',
          gameCaptureReadyToQueueMaxMsValues,
        );
        gameCaptureReadyToQueueSamples = max(
          gameCaptureReadyToQueueSamples,
          _intFromMarker(marker, 'readyToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryQueueWaitMs',
          gameCaptureDeliveryQueueWaitMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryQueueWaitMaxMs',
          gameCaptureDeliveryQueueWaitMaxMsValues,
        );
        gameCaptureDeliveryQueueWaitSamples = max(
          gameCaptureDeliveryQueueWaitSamples,
          _intFromMarker(marker, 'deliveryQueueWaitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryOverwriteAgeMs',
          gameCaptureDeliveryOverwriteAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOverwriteAgeMaxMs',
          gameCaptureDeliveryOverwriteAgeMaxMsValues,
        );
        gameCaptureDeliveryOverwriteAgeSamples = max(
          gameCaptureDeliveryOverwriteAgeSamples,
          _intFromMarker(marker, 'deliveryOverwriteAgeSamples') ?? 0,
        );
        gameCaptureDeliveryOverwrittenFreshFrames = max(
          gameCaptureDeliveryOverwrittenFreshFrames,
          _intFromMarker(marker, 'deliveryOverwrittenFresh') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readyToSubmitMs',
          gameCaptureReadyToSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'readyToSubmitMaxMs',
          gameCaptureReadyToSubmitMaxMsValues,
        );
        gameCaptureReadyToSubmitSamples = max(
          gameCaptureReadyToSubmitSamples,
          _intFromMarker(marker, 'readyToSubmitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToSubmitMs',
          gameCaptureSourceToSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToSubmitMaxMs',
          gameCaptureSourceToSubmitMaxMsValues,
        );
        gameCaptureSourceToSubmitSamples = max(
          gameCaptureSourceToSubmitSamples,
          _intFromMarker(marker, 'sourceToSubmitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToReadbackReadyMs',
          gameCaptureSourceToReadbackReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToReadbackReadyMaxMs',
          gameCaptureSourceToReadbackReadyMaxMsValues,
        );
        gameCaptureSourceToReadbackReadySamples = max(
          gameCaptureSourceToReadbackReadySamples,
          _intFromMarker(marker, 'sourceToReadbackReadySamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readbackQueueToMapMs',
          gameCaptureReadbackQueueToMapMsValues,
        );
        addMarkerDouble(
          marker,
          'readbackQueueToMapMaxMs',
          gameCaptureReadbackQueueToMapMaxMsValues,
        );
        gameCaptureReadbackQueueToMapSamples = max(
          gameCaptureReadbackQueueToMapSamples,
          _intFromMarker(marker, 'readbackQueueToMapSamples') ?? 0,
        );
        addMarkerDouble(marker, 'mapToI420Ms', gameCaptureMapToI420MsValues);
        addMarkerDouble(
          marker,
          'mapToI420MaxMs',
          gameCaptureMapToI420MaxMsValues,
        );
        gameCaptureMapToI420Samples = max(
          gameCaptureMapToI420Samples,
          _intFromMarker(marker, 'mapToI420Samples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToI420ReadyMs',
          gameCaptureSourceToI420ReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToI420ReadyMaxMs',
          gameCaptureSourceToI420ReadyMaxMsValues,
        );
        gameCaptureSourceToI420ReadySamples = max(
          gameCaptureSourceToI420ReadySamples,
          _intFromMarker(marker, 'sourceToI420ReadySamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToQueueMs',
          gameCaptureSourceToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToQueueMaxMs',
          gameCaptureSourceToQueueMaxMsValues,
        );
        gameCaptureSourceToQueueSamples = max(
          gameCaptureSourceToQueueSamples,
          _intFromMarker(marker, 'sourceToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceDuplicateSkipAgeMs',
          gameCaptureSourceDuplicateSkipAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceDuplicateSkipAgeMaxMs',
          gameCaptureSourceDuplicateSkipAgeMaxMsValues,
        );
        gameCaptureSourceDuplicateSkipAgeSamples = max(
          gameCaptureSourceDuplicateSkipAgeSamples,
          _intFromMarker(marker, 'sourceDuplicateSkipAgeSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readbackLatencyMs',
          gameCaptureReadbackLatencyMsValues,
        );
        addMarkerDouble(
          marker,
          'readbackLatencyFramesAvg',
          gameCaptureReadbackLatencyFrameValues,
        );

        if (marker.toLowerCase().contains(' i420_proof ')) {
          gameCaptureI420ProofFrames = max(
            gameCaptureI420ProofFrames,
            _intFromMarker(marker, 'frame') ?? 0,
          );
          gameCaptureI420ProofVisible =
              _boolFromMarker(marker, 'visible') ?? gameCaptureI420ProofVisible;
          gameCaptureI420ProofMinLuma =
              _intFromMarker(marker, 'minLuma') ?? gameCaptureI420ProofMinLuma;
          gameCaptureI420ProofMaxLuma =
              _intFromMarker(marker, 'maxLuma') ?? gameCaptureI420ProofMaxLuma;
          gameCaptureI420ProofNonzeroSamples =
              _intFromMarker(marker, 'nonzeroSamples') ??
              gameCaptureI420ProofNonzeroSamples;
          gameCaptureI420ProofSamples =
              _intFromMarker(marker, 'samples') ?? gameCaptureI420ProofSamples;
          final path = _tokenFromMarker(marker, 'path');
          if (path != null) {
            gameCaptureI420ProofPath = path.replaceAll(RegExp(r'^"|"$'), '');
          }
        } else if (marker.toLowerCase().contains(' proof ')) {
          gameCaptureProofVisible =
              _boolFromMarker(marker, 'visible') ?? gameCaptureProofVisible;
          gameCaptureProofMinLuma =
              _intFromMarker(marker, 'minLuma') ?? gameCaptureProofMinLuma;
          gameCaptureProofMaxLuma =
              _intFromMarker(marker, 'maxLuma') ?? gameCaptureProofMaxLuma;
          gameCaptureProofNonzeroSamples =
              _intFromMarker(marker, 'nonzeroSamples') ??
              gameCaptureProofNonzeroSamples;
          gameCaptureProofSamples =
              _intFromMarker(marker, 'samples') ?? gameCaptureProofSamples;
          final path = _tokenFromMarker(marker, 'path');
          if (path != null) {
            gameCaptureProofPath = path.replaceAll(RegExp(r'^"|"$'), '');
          }
        }
      }

      if (marker.toLowerCase().contains(
        'webrtc sender handoff source_on_frame stats',
      )) {
        addMarkerDouble(marker, 'avg_ms', webrtcSourceOnFrameMsValues);
        addMarkerDouble(marker, 'max_ms', webrtcSourceOnFrameMaxMsValues);
        addMarkerDouble(marker, 'adapt_ms', webrtcSourceAdaptMsValues);
        addMarkerDouble(marker, 'adapt_max_ms', webrtcSourceAdaptMaxMsValues);
        addMarkerDouble(marker, 'scale_ms', webrtcSourceScaleMsValues);
        addMarkerDouble(marker, 'scale_max_ms', webrtcSourceScaleMaxMsValues);
        addMarkerDouble(marker, 'broadcast_ms', webrtcSourceBroadcastMsValues);
        addMarkerDouble(
          marker,
          'broadcast_max_ms',
          webrtcSourceBroadcastMaxMsValues,
        );
        webrtcSourceOnFrameSamples = max(
          webrtcSourceOnFrameSamples,
          _intFromMarker(marker, 'calls') ?? 0,
        );
        webrtcSourceAdapterDrops = max(
          webrtcSourceAdapterDrops,
          _intFromMarker(marker, 'adapter_drops') ?? 0,
        );
        webrtcSourceScaledFrames = max(
          webrtcSourceScaledFrames,
          _intFromMarker(marker, 'scaled') ?? 0,
        );
      }

      if (marker.toLowerCase().contains(
        'webrtc sender handoff video_broadcaster stats',
      )) {
        addMarkerDouble(marker, 'avg_ms', webrtcVideoBroadcasterMsValues);
        addMarkerDouble(marker, 'max_ms', webrtcVideoBroadcasterMaxMsValues);
        webrtcVideoBroadcasterSamples = max(
          webrtcVideoBroadcasterSamples,
          _intFromMarker(marker, 'frames') ?? 0,
        );
        addMarkerDouble(
          marker,
          'lock_wait_ms',
          webrtcVideoBroadcasterLockWaitMsValues,
        );
        addMarkerDouble(
          marker,
          'lock_wait_max_ms',
          webrtcVideoBroadcasterLockWaitMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'sink_dispatch_ms',
          webrtcVideoBroadcasterSinkDispatchMsValues,
        );
        addMarkerDouble(
          marker,
          'sink_dispatch_max_ms',
          webrtcVideoBroadcasterSinkDispatchMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'max_single_sink_ms',
          webrtcVideoBroadcasterMaxSingleSinkMsValues,
        );
        final slowSinkMs = _doubleFromMarker(marker, 'slow_sink_ms');
        if (slowSinkMs != null &&
            (webrtcVideoBroadcasterSlowSinkMs == null ||
                slowSinkMs >= webrtcVideoBroadcasterSlowSinkMs)) {
          webrtcVideoBroadcasterSlowSinkMs = slowSinkMs;
          webrtcVideoBroadcasterSlowSinkId =
              _intFromMarker(marker, 'slow_sink_id') ??
              webrtcVideoBroadcasterSlowSinkId;
          webrtcVideoBroadcasterSlowSinkLabel =
              _tokenFromMarker(marker, 'slow_sink_label') ??
              webrtcVideoBroadcasterSlowSinkLabel;
        }
        final slowestSinkMs = _doubleFromMarker(marker, 'slowest_sink_ms');
        if (slowestSinkMs != null &&
            (webrtcVideoBroadcasterSlowestSinkMs == null ||
                slowestSinkMs >= webrtcVideoBroadcasterSlowestSinkMs)) {
          webrtcVideoBroadcasterSlowestSinkMs = slowestSinkMs;
          webrtcVideoBroadcasterSlowestSinkId =
              _intFromMarker(marker, 'slowest_sink_id') ??
              webrtcVideoBroadcasterSlowestSinkId;
          webrtcVideoBroadcasterSlowestSinkAverageMs =
              _doubleFromMarker(marker, 'slowest_sink_avg_ms') ??
              webrtcVideoBroadcasterSlowestSinkAverageMs;
          webrtcVideoBroadcasterSlowestSinkFrames =
              _intFromMarker(marker, 'slowest_sink_frames') ??
              webrtcVideoBroadcasterSlowestSinkFrames;
          webrtcVideoBroadcasterSlowestSinkLabel =
              _tokenFromMarker(marker, 'slowest_sink_label') ??
              webrtcVideoBroadcasterSlowestSinkLabel;
        }
        webrtcVideoBroadcasterSinkCount = max(
          webrtcVideoBroadcasterSinkCount,
          _intFromMarker(marker, 'sink_count') ?? 0,
        );
        webrtcVideoBroadcasterMaxSinkCount = max(
          webrtcVideoBroadcasterMaxSinkCount,
          _intFromMarker(marker, 'max_sink_count') ?? 0,
        );
        webrtcVideoBroadcasterActiveSinks = max(
          webrtcVideoBroadcasterActiveSinks,
          _intFromMarker(marker, 'active_sinks') ?? 0,
        );
        webrtcVideoBroadcasterInactiveSinks = max(
          webrtcVideoBroadcasterInactiveSinks,
          _intFromMarker(marker, 'inactive_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRequestedSinks = max(
          webrtcVideoBroadcasterRequestedSinks,
          _intFromMarker(marker, 'requested_sinks') ?? 0,
        );
        webrtcVideoBroadcasterBlackFrameSinks = max(
          webrtcVideoBroadcasterBlackFrameSinks,
          _intFromMarker(marker, 'black_frame_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRotationAppliedSinks = max(
          webrtcVideoBroadcasterRotationAppliedSinks,
          _intFromMarker(marker, 'rotation_applied_sinks') ?? 0,
        );
        final inactiveNativeSinksBypassed = _intFromMarker(
          marker,
          'inactive_native_sinks_bypassed',
        );
        final inactiveNativeSinksBypassedLast = _intFromMarker(
          marker,
          'inactive_native_sinks_bypassed_last',
        );
        if (inactiveNativeSinksBypassed != null ||
            inactiveNativeSinksBypassedLast != null) {
          webrtcVideoBroadcasterInactiveNativeSinkBypassReported = true;
        }
        if (inactiveNativeSinksBypassed != null) {
          webrtcVideoBroadcasterInactiveNativeSinksBypassed = max(
            webrtcVideoBroadcasterInactiveNativeSinksBypassed,
            inactiveNativeSinksBypassed,
          );
        }
        if (inactiveNativeSinksBypassedLast != null) {
          webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = max(
            webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
            inactiveNativeSinksBypassedLast,
          );
        }
        final inactiveNativeSinksRefreshed = _intFromMarker(
          marker,
          'inactive_native_sinks_refreshed',
        );
        final inactiveNativeSinksRefreshedLast = _intFromMarker(
          marker,
          'inactive_native_sinks_refreshed_last',
        );
        if (inactiveNativeSinksRefreshed != null) {
          webrtcVideoBroadcasterInactiveNativeSinksRefreshed = max(
            webrtcVideoBroadcasterInactiveNativeSinksRefreshed,
            inactiveNativeSinksRefreshed,
          );
        }
        if (inactiveNativeSinksRefreshedLast != null) {
          webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast = max(
            webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast,
            inactiveNativeSinksRefreshedLast,
          );
        }
        webrtcVideoBroadcasterSinkRoster =
            _tokenFromMarker(marker, 'sink_roster') ??
            webrtcVideoBroadcasterSinkRoster;
        webrtcVideoBroadcasterBlackSinks = max(
          webrtcVideoBroadcasterBlackSinks,
          _intFromMarker(marker, 'black_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRotationDiscards = max(
          webrtcVideoBroadcasterRotationDiscards,
          _intFromMarker(marker, 'rotation_discards') ?? 0,
        );
        webrtcVideoBroadcasterUpdateRectCleared = max(
          webrtcVideoBroadcasterUpdateRectCleared,
          _intFromMarker(marker, 'update_rect_cleared') ?? 0,
        );
        webrtcVideoBroadcasterDiscardedFrames = max(
          webrtcVideoBroadcasterDiscardedFrames,
          _intFromMarker(marker, 'discarded_frames') ?? 0,
        );
      }

      if (marker.toLowerCase().contains(
        'webrtc sender handoff video_stream_encoder stats',
      )) {
        captureWebrtcFrameLineage(marker);
        addMarkerDouble(
          marker,
          'post_to_onframe_ms',
          webrtcVsePostToOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'post_to_onframe_max_ms',
          webrtcVsePostToOnFrameMaxMsValues,
        );
        addMarkerDouble(marker, 'onframe_ms', webrtcVseOnFrameMsValues);
        addMarkerDouble(marker, 'onframe_max_ms', webrtcVseOnFrameMaxMsValues);
        webrtcVseOnFrameSamples = max(
          webrtcVseOnFrameSamples,
          _intFromMarker(marker, 'onframe_calls') ?? 0,
        );
        webrtcVseQueueOverloadDrops = max(
          webrtcVseQueueOverloadDrops,
          _intFromMarker(marker, 'queue_overload_drops') ?? 0,
        );
        webrtcVseEncoderQueueDrops = max(
          webrtcVseEncoderQueueDrops,
          _intFromMarker(marker, 'encoder_queue_drops') ?? 0,
        );
        webrtcVseCwndDrops = max(
          webrtcVseCwndDrops,
          _intFromMarker(marker, 'cwnd_drops') ?? 0,
        );
        webrtcVseBadTimestampDrops = max(
          webrtcVseBadTimestampDrops,
          _intFromMarker(marker, 'bad_timestamp_drops') ?? 0,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_ms',
          webrtcVseMaybeEncodeMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_max_ms',
          webrtcVseMaybeEncodeMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_pre_encode_ms',
          webrtcVseMaybePreEncodeMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_pre_encode_max_ms',
          webrtcVseMaybePreEncodeMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_call_ms',
          webrtcVseMaybeEncodeCallMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_call_max_ms',
          webrtcVseMaybeEncodeCallMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_frame_size_ms',
          webrtcVseMaybeFrameSizeMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_frame_size_max_ms',
          webrtcVseMaybeFrameSizeMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_parameter_update_ms',
          webrtcVseMaybeParameterUpdateMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_parameter_update_max_ms',
          webrtcVseMaybeParameterUpdateMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_reconfigure_ms',
          webrtcVseMaybeReconfigureMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_reconfigure_max_ms',
          webrtcVseMaybeReconfigureMaxMsValues,
        );
        webrtcVsePendingReconfigureSignals = max(
          webrtcVsePendingReconfigureSignals,
          _intFromMarker(marker, 'pending_reconfigure_signals') ?? 0,
        );
        webrtcVsePendingReconfigureConfigureEncoder = max(
          webrtcVsePendingReconfigureConfigureEncoder,
          _intFromMarker(marker, 'pending_reconfigure_configure_encoder') ?? 0,
        );
        webrtcVsePendingReconfigureFrameInfoChange = max(
          webrtcVsePendingReconfigureFrameInfoChange,
          _intFromMarker(marker, 'pending_reconfigure_frame_info_change') ?? 0,
        );
        webrtcVsePendingReconfigureSourceRestriction = max(
          webrtcVsePendingReconfigureSourceRestriction,
          _intFromMarker(marker, 'pending_reconfigure_source_restriction') ?? 0,
        );
        webrtcVsePendingReconfigureUnknown = max(
          webrtcVsePendingReconfigureUnknown,
          _intFromMarker(marker, 'pending_reconfigure_unknown') ?? 0,
        );
        webrtcVsePendingReconfigureLastReason =
            _tokenFromMarker(marker, 'pending_reconfigure_last_reason') ??
            webrtcVsePendingReconfigureLastReason;
        addMarkerDouble(
          marker,
          'maybe_rate_update_ms',
          webrtcVseMaybeRateUpdateMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_rate_update_max_ms',
          webrtcVseMaybeRateUpdateMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_drop_checks_ms',
          webrtcVseMaybeDropChecksMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_drop_checks_max_ms',
          webrtcVseMaybeDropChecksMaxMsValues,
        );
        webrtcVseMaybeEncodeSamples = max(
          webrtcVseMaybeEncodeSamples,
          _intFromMarker(marker, 'maybe_encode_calls') ?? 0,
        );
        webrtcVsePendingReplacedDrops = max(
          webrtcVsePendingReplacedDrops,
          _intFromMarker(marker, 'pending_replaced_drops') ?? 0,
        );
        webrtcVseSizeDrops = max(
          webrtcVseSizeDrops,
          _intFromMarker(marker, 'size_drops') ?? 0,
        );
        webrtcVsePausedDrops = max(
          webrtcVsePausedDrops,
          _intFromMarker(marker, 'paused_drops') ?? 0,
        );
        webrtcVseMediaOptimizationDrops = max(
          webrtcVseMediaOptimizationDrops,
          _intFromMarker(marker, 'media_optimization_drops') ?? 0,
        );
        addMarkerDouble(
          marker,
          'encode_frame_ms',
          webrtcVseEncodeFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_frame_max_ms',
          webrtcVseEncodeFrameMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_pre_encoder_ms',
          webrtcVseEncodePreEncoderMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_pre_encoder_max_ms',
          webrtcVseEncodePreEncoderMaxMsValues,
        );
        addMarkerDouble(marker, 'encode_info_ms', webrtcVseEncodeInfoMsValues);
        addMarkerDouble(
          marker,
          'encode_info_max_ms',
          webrtcVseEncodeInfoMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_crop_scale_ms',
          webrtcVseEncodeCropScaleMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_crop_scale_max_ms',
          webrtcVseEncodeCropScaleMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_update_rect_ms',
          webrtcVseEncodeUpdateRectMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_update_rect_max_ms',
          webrtcVseEncodeUpdateRectMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_resource_ms',
          webrtcVseEncodeResourceMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_resource_max_ms',
          webrtcVseEncodeResourceMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_metadata_ms',
          webrtcVseEncodeMetadataMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_metadata_max_ms',
          webrtcVseEncodeMetadataMaxMsValues,
        );
        webrtcVseEncodeFrameSamples = max(
          webrtcVseEncodeFrameSamples,
          _intFromMarker(marker, 'encode_frame_calls') ?? 0,
        );
        addMarkerDouble(
          marker,
          'video_encoder_encode_ms',
          webrtcVideoEncoderEncodeMsValues,
        );
        addMarkerDouble(
          marker,
          'video_encoder_encode_max_ms',
          webrtcVideoEncoderEncodeMaxMsValues,
        );
        webrtcVideoEncoderEncodeSamples = max(
          webrtcVideoEncoderEncodeSamples,
          _intFromMarker(marker, 'video_encoder_encode_calls') ?? 0,
        );
        webrtcVseEncodeFailures = max(
          webrtcVseEncodeFailures,
          _intFromMarker(marker, 'encode_failures') ?? 0,
        );
        webrtcVseEncodeSkippedBeforeEncoder = max(
          webrtcVseEncodeSkippedBeforeEncoder,
          _intFromMarker(marker, 'encode_skipped_before_encoder') ?? 0,
        );
      }

      if (marker.toLowerCase().contains(
        'webrtc sender handoff frame_cadence_adapter stats',
      )) {
        captureWebrtcFrameLineage(marker);
        addMarkerDouble(
          marker,
          'post_delay_ms',
          webrtcFrameCadencePostDelayMsValues,
        );
        addMarkerDouble(
          marker,
          'post_delay_max_ms',
          webrtcFrameCadencePostDelayMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'callback_ms',
          webrtcFrameCadenceCallbackMsValues,
        );
        addMarkerDouble(
          marker,
          'callback_max_ms',
          webrtcFrameCadenceCallbackMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'frame_duration_ms',
          webrtcFrameCadenceFrameDurationMsValues,
        );
        addMarkerDouble(
          marker,
          'frame_duration_max_ms',
          webrtcFrameCadenceFrameDurationMaxMsValues,
        );
        webrtcFrameCadenceSends = max(
          webrtcFrameCadenceSends,
          _intFromMarker(marker, 'sends') ?? 0,
        );
        webrtcFrameCadenceRepeatedSends = max(
          webrtcFrameCadenceRepeatedSends,
          _intFromMarker(marker, 'repeated_sends') ?? 0,
        );
        webrtcFrameCadencePostDelaySamples = max(
          webrtcFrameCadencePostDelaySamples,
          _intFromMarker(marker, 'post_delay_samples') ?? 0,
        );
        webrtcFrameCadenceOverFrameDurationSends = max(
          webrtcFrameCadenceOverFrameDurationSends,
          _intFromMarker(marker, 'over_frame_duration_sends') ?? 0,
        );
        webrtcFrameCadenceOverloadTriggerSends = max(
          webrtcFrameCadenceOverloadTriggerSends,
          _intFromMarker(marker, 'overload_trigger_sends') ?? 0,
        );
        webrtcFrameCadenceOverloadActiveSends = max(
          webrtcFrameCadenceOverloadActiveSends,
          _intFromMarker(marker, 'overload_active_sends') ?? 0,
        );
        webrtcFrameCadenceOverloadDecaySends = max(
          webrtcFrameCadenceOverloadDecaySends,
          _intFromMarker(marker, 'overload_decay_sends') ?? 0,
        );
        webrtcFrameCadenceOverloadEnabledSeen =
            _boolFromMarker(marker, 'overload_enabled_seen') ??
            webrtcFrameCadenceOverloadEnabledSeen;
        webrtcFrameCadenceOverloadDisabledSeen =
            _boolFromMarker(marker, 'overload_disabled_seen') ??
            webrtcFrameCadenceOverloadDisabledSeen;
        webrtcFrameCadenceMaxScheduledForProcessing = max(
          webrtcFrameCadenceMaxScheduledForProcessing,
          _intFromMarker(marker, 'max_scheduled_for_processing') ?? 0,
        );
        webrtcFrameCadenceLastScheduledForProcessing = max(
          webrtcFrameCadenceLastScheduledForProcessing,
          _intFromMarker(marker, 'last_scheduled_for_processing') ?? 0,
        );
        webrtcFrameCadenceMaxQueueOverloadBefore = max(
          webrtcFrameCadenceMaxQueueOverloadBefore,
          _intFromMarker(marker, 'max_queue_overload_before') ?? 0,
        );
        webrtcFrameCadenceMaxQueueOverloadAfter = max(
          webrtcFrameCadenceMaxQueueOverloadAfter,
          _intFromMarker(marker, 'max_queue_overload_after') ?? 0,
        );
        webrtcFrameCadenceLastQueueOverloadBefore = max(
          webrtcFrameCadenceLastQueueOverloadBefore,
          _intFromMarker(marker, 'last_queue_overload_before') ?? 0,
        );
        webrtcFrameCadenceLastQueueOverloadAfter = max(
          webrtcFrameCadenceLastQueueOverloadAfter,
          _intFromMarker(marker, 'last_queue_overload_after') ?? 0,
        );
      }

      if (marker.toLowerCase().contains(
        'webrtc sender handoff frame_cadence_queue stats',
      )) {
        captureWebrtcFrameLineage(marker);
        addMarkerDouble(
          marker,
          'post_delay_ms',
          webrtcFrameCadenceQueuePostDelayMsValues,
        );
        addMarkerDouble(
          marker,
          'post_delay_max_ms',
          webrtcFrameCadenceQueuePostDelayMaxMsValues,
        );
        webrtcFrameCadenceQueueFrames = max(
          webrtcFrameCadenceQueueFrames,
          _intFromMarker(marker, 'frames') ?? 0,
        );
        webrtcFrameCadenceQueueOverloadFrames = max(
          webrtcFrameCadenceQueueOverloadFrames,
          _intFromMarker(marker, 'overload_frames') ?? 0,
        );
        webrtcFrameCadenceQueuePostDelaySamples = max(
          webrtcFrameCadenceQueuePostDelaySamples,
          _intFromMarker(marker, 'post_delay_samples') ?? 0,
        );
        webrtcFrameCadenceQueueMaxScheduledForProcessing = max(
          webrtcFrameCadenceQueueMaxScheduledForProcessing,
          _intFromMarker(marker, 'max_scheduled_for_processing') ?? 0,
        );
        webrtcFrameCadenceQueueLastScheduledForProcessing = max(
          webrtcFrameCadenceQueueLastScheduledForProcessing,
          _intFromMarker(marker, 'last_scheduled_for_processing') ?? 0,
        );
        webrtcFrameCadenceQueuePassthroughFrames = max(
          webrtcFrameCadenceQueuePassthroughFrames,
          _intFromMarker(marker, 'passthrough_frames') ?? 0,
        );
        webrtcFrameCadenceQueueZeroHertzFrames = max(
          webrtcFrameCadenceQueueZeroHertzFrames,
          _intFromMarker(marker, 'zero_hertz_frames') ?? 0,
        );
        webrtcFrameCadenceQueueVsyncFrames = max(
          webrtcFrameCadenceQueueVsyncFrames,
          _intFromMarker(marker, 'vsync_frames') ?? 0,
        );
        webrtcFrameCadenceQueueUnknownFrames = max(
          webrtcFrameCadenceQueueUnknownFrames,
          _intFromMarker(marker, 'unknown_frames') ?? 0,
        );
        webrtcFrameCadenceQueueCoalesceEnabledSeen =
            _boolFromMarker(marker, 'coalesce_enabled_seen') ??
            webrtcFrameCadenceQueueCoalesceEnabledSeen;
        webrtcFrameCadenceQueueCoalesceDisabledSeen =
            _boolFromMarker(marker, 'coalesce_disabled_seen') ??
            webrtcFrameCadenceQueueCoalesceDisabledSeen;
        webrtcFrameCadenceQueueCoalesceThreshold = max(
          webrtcFrameCadenceQueueCoalesceThreshold,
          _intFromMarker(marker, 'coalesce_threshold') ?? 0,
        );
        webrtcFrameCadenceQueueCoalescedDrops = max(
          webrtcFrameCadenceQueueCoalescedDrops,
          _intFromMarker(marker, 'coalesced_drops') ?? 0,
        );
        webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen =
            _boolFromMarker(marker, 'prepost_coalesce_enabled_seen') ??
            webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen;
        webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen =
            _boolFromMarker(marker, 'prepost_coalesce_disabled_seen') ??
            webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen;
        webrtcFrameCadenceQueuePrepostCoalescedDrops = max(
          webrtcFrameCadenceQueuePrepostCoalescedDrops,
          _intFromMarker(marker, 'prepost_coalesced_drops') ?? 0,
        );
        webrtcFrameCadenceQueuePrepostProcessingDrops = max(
          webrtcFrameCadenceQueuePrepostProcessingDrops,
          _intFromMarker(marker, 'prepost_processing_drops') ?? 0,
        );
        webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing = max(
          webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing,
          _intFromMarker(marker, 'prepost_max_scheduled_for_processing') ?? 0,
        );
        webrtcFrameCadenceQueueLastMode =
            _tokenFromMarker(marker, 'last_mode') ??
            webrtcFrameCadenceQueueLastMode;
        webrtcFrameCadenceQueueMailboxEnabledSeen =
            _boolFromMarker(marker, 'mailbox_enabled_seen') ??
            webrtcFrameCadenceQueueMailboxEnabledSeen;
        webrtcFrameCadenceQueueMailboxFrames = max(
          webrtcFrameCadenceQueueMailboxFrames,
          _intFromMarker(marker, 'mailbox_frames') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxProcessedFrames = max(
          webrtcFrameCadenceQueueMailboxProcessedFrames,
          _intFromMarker(marker, 'mailbox_processed_frames') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxReplacements = max(
          webrtcFrameCadenceQueueMailboxReplacements,
          _intFromMarker(marker, 'mailbox_replacements') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxStaleDrops = max(
          webrtcFrameCadenceQueueMailboxStaleDrops,
          _intFromMarker(marker, 'mailbox_stale_drops') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxProcessingActive =
            _boolFromMarker(marker, 'mailbox_processing_active') ??
            webrtcFrameCadenceQueueMailboxProcessingActive;
        webrtcFrameCadenceQueueMailboxProcessingActiveSeen =
            _boolFromMarker(marker, 'mailbox_processing_active_seen') ??
            webrtcFrameCadenceQueueMailboxProcessingActiveSeen;
        webrtcFrameCadenceQueueMailboxPendingDepthMax = max(
          webrtcFrameCadenceQueueMailboxPendingDepthMax,
          _intFromMarker(marker, 'mailbox_pending_depth_max') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxPendingDepthLast = max(
          webrtcFrameCadenceQueueMailboxPendingDepthLast,
          _intFromMarker(marker, 'mailbox_pending_depth_last') ?? 0,
        );
        addMarkerDouble(
          marker,
          'pending_frame_age_ms',
          webrtcFrameCadenceQueueMailboxPendingFrameAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'pending_frame_age_max_ms',
          webrtcFrameCadenceQueueMailboxPendingFrameAgeMaxMsValues,
        );
        webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples = max(
          webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples,
          _intFromMarker(marker, 'pending_frame_age_samples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'processing_frame_age_ms',
          webrtcFrameCadenceQueueMailboxProcessingFrameAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'processing_frame_age_max_ms',
          webrtcFrameCadenceQueueMailboxProcessingFrameAgeMaxMsValues,
        );
        webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples = max(
          webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples,
          _intFromMarker(marker, 'processing_frame_age_samples') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses = max(
          webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses,
          _intFromMarker(marker, 'admission_deadline_misses') ?? 0,
        );
        addMarkerDouble(
          marker,
          'enqueue_to_processing_start_ms',
          webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMsValues,
        );
        addMarkerDouble(
          marker,
          'enqueue_to_processing_start_max_ms',
          webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMaxMsValues,
        );
        webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples = max(
          webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples,
          _intFromMarker(marker, 'enqueue_to_processing_start_samples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'processing_start_to_vse_ms',
          webrtcFrameCadenceQueueMailboxProcessingStartToVseMsValues,
        );
        addMarkerDouble(
          marker,
          'processing_start_to_vse_max_ms',
          webrtcFrameCadenceQueueMailboxProcessingStartToVseMaxMsValues,
        );
        webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples = max(
          webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples,
          _intFromMarker(marker, 'processing_start_to_vse_samples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'vse_call_ms',
          webrtcFrameCadenceQueueMailboxVseCallMsValues,
        );
        addMarkerDouble(
          marker,
          'vse_call_max_ms',
          webrtcFrameCadenceQueueMailboxVseCallMaxMsValues,
        );
        webrtcFrameCadenceQueueMailboxVseCallSamples = max(
          webrtcFrameCadenceQueueMailboxVseCallSamples,
          _intFromMarker(marker, 'vse_call_samples') ?? 0,
        );
        webrtcFrameCadenceQueueMailboxStaleDropThresholdMs = max(
          webrtcFrameCadenceQueueMailboxStaleDropThresholdMs,
          _intFromMarker(marker, 'mailbox_stale_drop_threshold_ms') ?? 0,
        );
      }

      if (marker.toLowerCase().contains(
        'media foundation h.264 encoded callback timing',
      )) {
        addMarkerDouble(marker, 'callback_ms', encoderEncodedCallbackValues);
        addMarkerDouble(
          marker,
          'queue_wait_ms',
          encoderEncodedCallbackQueueWaitValues,
        );
        encoderMaxEncodedCallbackQueueDepth = max(
          encoderMaxEncodedCallbackQueueDepth,
          _intFromMarker(marker, 'queue_depth') ?? 0,
        );
        encoderMaxEncodedCallbackDrops = max(
          encoderMaxEncodedCallbackDrops,
          _intFromMarker(marker, 'callback_drops') ?? 0,
        );
        encoderMaxEncodedCallbackOutputs = max(
          encoderMaxEncodedCallbackOutputs,
          _intFromMarker(marker, 'callback_outputs') ?? 0,
        );
        if (_boolFromMarker(marker, 'async') == true) {
          encoderEncodedCallbackAsyncFrames++;
        }
      }

      final encoderMatch = _mediaFoundationTimingPattern.firstMatch(marker);
      if (encoderMatch != null) {
        final totalMs = _doubleGroup(encoderMatch, 1);
        if (totalMs != null && totalMs > 0) {
          encoderTotalValues.add(totalMs);
        }
        if ((_stringGroup(encoderMatch, 2) ?? '').toLowerCase() == 'yes') {
          encoderSlowFrameCount++;
        }
        final stage = _tokenFromMarker(marker, 'stage');
        if (stage != null) {
          encoderStages.add(stage);
        }
        encoderRateControlMode =
            _tokenFromMarker(marker, 'rate_control_mode') ??
            encoderRateControlMode;
        encoderTargetBitrateBps =
            _intFromMarker(marker, 'target_bitrate_bps') ??
            encoderTargetBitrateBps;
        final inputPath = _tokenFromMarker(marker, 'input_path');
        if (inputPath != null) {
          encoderInputPaths.add(inputPath);
        }
        final nativeInput = _boolFromMarker(marker, 'native_input');
        if (inputPath == 'native_nv12') {
          encoderNativeInputFrames++;
        } else if (inputPath == 'cpu_i420') {
          encoderCpuI420InputFrames++;
        } else if (nativeInput == true) {
          encoderNativeInputFrames++;
        } else if (nativeInput == false) {
          encoderCpuI420InputFrames++;
        }
        if (_boolFromMarker(marker, 'native_sample_failed') == true) {
          encoderNativeSampleFailures++;
        }
        if (_boolFromMarker(marker, 'native_suspended') == true) {
          encoderNativeSuspendedFrames++;
        }
        if (_boolFromMarker(marker, 'native_ready_fence') == true) {
          encoderNativeReadyFenceFrames++;
        }
        if (_boolFromMarker(marker, 'native_ready_fence_timeout') == true) {
          encoderNativeReadyFenceTimeoutFrames++;
        }
        addMarkerDouble(
          marker,
          'native_ready_fence_wait_ms',
          encoderNativeReadyFenceWaitValues,
        );
        encoderNativeSourceMode =
            _tokenFromMarker(marker, 'native_source_mode') ??
            encoderNativeSourceMode;
        encoderNativeSourceFormat =
            _intFromMarker(marker, 'native_source_format') ??
            encoderNativeSourceFormat;
        encoderNativeSourceFrameIndex = max(
          encoderNativeSourceFrameIndex,
          _intFromMarker(marker, 'native_source_frame') ?? 0,
        );
        addMarkerDouble(
          marker,
          'native_source_age_ms',
          encoderNativeSourceAgeValues,
        );
        addMarkerDouble(
          marker,
          'native_source_age_at_create_ms',
          encoderNativeSourceAgeAtCreateValues,
        );
        addMarkerDouble(
          marker,
          'native_buffer_age_ms',
          encoderNativeBufferAgeValues,
        );
        addMarkerDouble(
          marker,
          'native_sample_lifetime_ms',
          encoderNativeSampleLifetimeValues,
        );
        addMarkerDouble(
          marker,
          'native_sample_lifetime_max_ms',
          encoderNativeSampleLifetimeMaxValues,
        );
        encoderNativeSampleLifetimeSamples = max(
          encoderNativeSampleLifetimeSamples,
          _intFromMarker(marker, 'native_sample_lifetime_samples') ?? 0,
        );
        encoderNativeAdapterLuid =
            _tokenFromMarker(marker, 'native_adapter_luid') ??
            encoderNativeAdapterLuid;
        encoderNativeAdapterVendorId =
            _intFromMarker(marker, 'native_adapter_vendor_id') ??
            encoderNativeAdapterVendorId;
        encoderNativeAdapterDeviceId =
            _intFromMarker(marker, 'native_adapter_device_id') ??
            encoderNativeAdapterDeviceId;
        addMarkerDouble(marker, 'process_input_ms', encoderProcessInputValues);
        addMarkerDouble(
          marker,
          'process_output_ms',
          encoderProcessOutputValues,
        );
        addMarkerDouble(
          marker,
          'encoded_callback_ms',
          encoderEncodedCallbackValues,
        );
        addMarkerDouble(
          marker,
          'encoded_callback_enqueue_ms',
          encoderEncodedCallbackEnqueueValues,
        );
        if (_boolFromMarker(marker, 'encoded_callback_async') == true) {
          encoderEncodedCallbackAsyncFrames++;
        }
        encoderMaxEncodedCallbackQueueDepth = max(
          encoderMaxEncodedCallbackQueueDepth,
          _intFromMarker(marker, 'encoded_callback_queue_depth') ?? 0,
        );
        encoderMaxEncodedCallbackDrops = max(
          encoderMaxEncodedCallbackDrops,
          _intFromMarker(marker, 'encoded_callback_drops') ?? 0,
        );
        encoderOutputFrames += _intFromMarker(marker, 'outputs') ?? 0;
        encoderOutputBytes += _intFromMarker(marker, 'output_bytes') ?? 0;
        encoderMaxQueueDepth = max(
          encoderMaxQueueDepth,
          _intFromMarker(marker, 'queue') ?? 0,
        );
        encoderMaxRetainedSamples = max(
          encoderMaxRetainedSamples,
          _intFromMarker(marker, 'retained_samples') ?? 0,
        );
        encoderMaxEncodedOutputs = max(
          encoderMaxEncodedOutputs,
          _intFromMarker(marker, 'encoded_outputs') ?? 0,
        );
      }
    }

    return StreamTestNativeDiagnostics(
      captureBackendMode: captureBackendMode,
      observedCapturer: observedCapturer,
      observedCapturerId: observedCapturerId,
      dirtyRegionMode: dirtyRegionMode,
      windowGdiCaptureMode: windowGdiCaptureMode,
      sourceType: sourceType,
      nativeSourceWidth: nativeSourceWidth,
      nativeSourceHeight: nativeSourceHeight,
      requestedMaxWidth: requestedMaxWidth,
      requestedMaxHeight: requestedMaxHeight,
      nativeWindowRectWidth: nativeWindowRectWidth,
      nativeWindowRectHeight: nativeWindowRectHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      preEncodeWidth: preEncodeWidth,
      preEncodeHeight: preEncodeHeight,
      canvas: canvas,
      cropRegion: cropRegion,
      averageNativeFps: _average(nativeFpsValues),
      averageSubmittedFps: _average(submittedFpsValues),
      targetNativeFps: _average(targetFpsValues),
      averageCaptureCallMs: _average(captureCallValues),
      maxCaptureCallMs: _maxDouble(maxCaptureCallValues),
      averageSourceCaptureMs: sourceCaptureWeightedSampleCount > 0
          ? sourceCaptureWeightedTotalMs / sourceCaptureWeightedSampleCount
          : _average(sourceCaptureValues),
      maxSourceCaptureMs: _maxDouble(maxSourceCaptureValues),
      sourceCaptureSampleCount: sourceCaptureSampleCount,
      wgcCaptureCalls: wgcCaptureCalls,
      wgcCaptureSuccessCount: wgcCaptureSuccessCount,
      wgcSourceNotCapturableCount: wgcSourceNotCapturableCount,
      wgcEnsureFrameCalls: wgcEnsureFrameCalls,
      wgcEnsureSleepCount: wgcEnsureSleepCount,
      wgcProcessFrameCalls: wgcProcessFrameCalls,
      wgcProcessFrameSuccessCount: wgcProcessFrameSuccessCount,
      wgcFramePoolEmptyCount: wgcFramePoolEmptyCount,
      wgcFramePoolReuseCount: wgcFramePoolReuseCount,
      wgcCaptureFrameNullCount: wgcCaptureFrameNullCount,
      wgcMappedTextureCreateCount: wgcMappedTextureCreateCount,
      wgcResizeCount: wgcResizeCount,
      wgcFramePoolRecreateCount: wgcFramePoolRecreateCount,
      averageWgcGetFrameMs: _average(wgcGetFrameValues),
      maxWgcGetFrameMs: _maxDouble(wgcMaxGetFrameValues),
      averageWgcEnsureFrameMs: _average(wgcEnsureFrameValues),
      maxWgcEnsureFrameMs: _maxDouble(wgcMaxEnsureFrameValues),
      averageWgcProcessFrameMs: _average(wgcProcessFrameValues),
      maxWgcProcessFrameMs: _maxDouble(wgcMaxProcessFrameValues),
      averageWgcTryGetFrameMs: _average(wgcTryGetFrameValues),
      maxWgcTryGetFrameMs: _maxDouble(wgcMaxTryGetFrameValues),
      averageWgcSurfaceMs: _average(wgcSurfaceValues),
      maxWgcSurfaceMs: _maxDouble(wgcMaxSurfaceValues),
      averageWgcTextureMs: _average(wgcTextureValues),
      maxWgcTextureMs: _maxDouble(wgcMaxTextureValues),
      averageWgcContentSizeMs: _average(wgcContentSizeValues),
      maxWgcContentSizeMs: _maxDouble(wgcMaxContentSizeValues),
      averageWgcCopyTextureMs: _average(wgcCopyTextureValues),
      maxWgcCopyTextureMs: _maxDouble(wgcMaxCopyTextureValues),
      averageWgcMapTextureMs: _average(wgcMapTextureValues),
      maxWgcMapTextureMs: _maxDouble(wgcMaxMapTextureValues),
      averageWgcCopyRowsMs: _average(wgcCopyRowsValues),
      maxWgcCopyRowsMs: _maxDouble(wgcMaxCopyRowsValues),
      averageWgcMonitorScaleMs: _average(wgcMonitorScaleValues),
      maxWgcMonitorScaleMs: _maxDouble(wgcMaxMonitorScaleValues),
      averageWgcZeroHertzMs: _average(wgcZeroHertzValues),
      maxWgcZeroHertzMs: _maxDouble(wgcMaxZeroHertzValues),
      gdiCaptureCalls: gdiCaptureCalls,
      gdiCaptureSuccessCount: gdiCaptureSuccessCount,
      gdiTemporaryErrorCount: gdiTemporaryErrorCount,
      gdiPermanentErrorCount: gdiPermanentErrorCount,
      gdiHiddenOrMinimizedCount: gdiHiddenOrMinimizedCount,
      gdiRectFailCount: gdiRectFailCount,
      gdiDcFailCount: gdiDcFailCount,
      gdiFrameCreateFailCount: gdiFrameCreateFailCount,
      gdiPrintFullCallCount: gdiPrintFullCallCount,
      gdiPrintFullSuccessCount: gdiPrintFullSuccessCount,
      gdiPrintFallbackCallCount: gdiPrintFallbackCallCount,
      gdiPrintFallbackSuccessCount: gdiPrintFallbackSuccessCount,
      gdiBitBltCallCount: gdiBitBltCallCount,
      gdiBitBltSuccessCount: gdiBitBltSuccessCount,
      gdiFinalPrintFullCount: gdiFinalPrintFullCount,
      gdiFinalPrintFallbackCount: gdiFinalPrintFallbackCount,
      gdiFinalBitBltCount: gdiFinalBitBltCount,
      gdiFinalNoneCount: gdiFinalNoneCount,
      gdiBlackFrameCount: gdiBlackFrameCount,
      gdiLowVarianceFrameCount: gdiLowVarianceFrameCount,
      gdiOwnedWindowFrameCount: gdiOwnedWindowFrameCount,
      gdiOwnedWindowCaptureCallCount: gdiOwnedWindowCaptureCallCount,
      gdiOwnedWindowCaptureSuccessCount: gdiOwnedWindowCaptureSuccessCount,
      gdiOriginalWidth: gdiOriginalWidth,
      gdiOriginalHeight: gdiOriginalHeight,
      gdiCroppedWidth: gdiCroppedWidth,
      gdiCroppedHeight: gdiCroppedHeight,
      gdiFrameWidth: gdiFrameWidth,
      gdiFrameHeight: gdiFrameHeight,
      averageGdiTotalMs: _average(gdiTotalValues),
      maxGdiTotalMs: _maxDouble(gdiMaxTotalValues),
      averageGdiRectMs: _average(gdiRectValues),
      maxGdiRectMs: _maxDouble(gdiMaxRectValues),
      averageGdiVisibilityMs: _average(gdiVisibilityValues),
      maxGdiVisibilityMs: _maxDouble(gdiMaxVisibilityValues),
      averageGdiGetDcMs: _average(gdiGetDcValues),
      maxGdiGetDcMs: _maxDouble(gdiMaxGetDcValues),
      averageGdiGetDcSizeMs: _average(gdiGetDcSizeValues),
      maxGdiGetDcSizeMs: _maxDouble(gdiMaxGetDcSizeValues),
      averageGdiCreateFrameMs: _average(gdiCreateFrameValues),
      maxGdiCreateFrameMs: _maxDouble(gdiMaxCreateFrameValues),
      averageGdiMemDcMs: _average(gdiMemDcValues),
      maxGdiMemDcMs: _maxDouble(gdiMaxMemDcValues),
      averageGdiPrintFullMs: _average(gdiPrintFullValues),
      maxGdiPrintFullMs: _maxDouble(gdiMaxPrintFullValues),
      averageGdiPrintFallbackMs: _average(gdiPrintFallbackValues),
      maxGdiPrintFallbackMs: _maxDouble(gdiMaxPrintFallbackValues),
      averageGdiBitBltMs: _average(gdiBitBltValues),
      maxGdiBitBltMs: _maxDouble(gdiMaxBitBltValues),
      averageGdiCleanupMs: _average(gdiCleanupValues),
      maxGdiCleanupMs: _maxDouble(gdiMaxCleanupValues),
      averageGdiCropMs: _average(gdiCropValues),
      maxGdiCropMs: _maxDouble(gdiMaxCropValues),
      averageGdiOwnedEnumMs: _average(gdiOwnedEnumValues),
      maxGdiOwnedEnumMs: _maxDouble(gdiMaxOwnedEnumValues),
      averageGdiOwnedCaptureMs: _average(gdiOwnedCaptureValues),
      maxGdiOwnedCaptureMs: _maxDouble(gdiMaxOwnedCaptureValues),
      averageGdiOwnedCompositeMs: _average(gdiOwnedCompositeValues),
      maxGdiOwnedCompositeMs: _maxDouble(gdiMaxOwnedCompositeValues),
      averageCallbackEntryDelayMs: _average(callbackEntryDelayValues),
      maxCallbackEntryDelayMs: _maxDouble(maxCallbackEntryDelayValues),
      averageCaptureResultCallbackMs: _average(captureResultCallbackValues),
      maxCaptureResultCallbackMs: _maxDouble(maxCaptureResultCallbackValues),
      averageCaptureAcquireWaitMs: _average(captureAcquireWaitValues),
      maxCaptureAcquireWaitMs: _maxDouble(maxCaptureAcquireWaitValues),
      averagePostCallbackWaitMs: _average(postCallbackWaitValues),
      maxPostCallbackWaitMs: _maxDouble(maxPostCallbackWaitValues),
      averageUnaccountedWaitMs: _average(unaccountedWaitValues),
      maxUnaccountedWaitMs: _maxDouble(maxUnaccountedWaitValues),
      captureResultCallbackCount: captureResultCallbackCount,
      maxFrameIntervalMs: _maxDouble(maxFrameIntervalValues),
      p95FrameIntervalMs: _average(p95FrameIntervalValues),
      captureWaitTimeoutCount: parsedFrameCadence
          ? frameWaitTimeoutCount
          : scheduleWaitTimeoutCount,
      capturePermanentErrorCount: parsedFrameCadence
          ? framePermanentErrorCount
          : schedulePermanentErrorCount,
      duplicatedFrameCount: duplicatedFrameCount,
      staleFrameReuseCount: staleFrameReuseCount,
      averageFrameConvertMs: _average(frameConvertValues),
      averageFrameScaleMs: _average(frameScaleValues),
      averageFrameOnFrameMs: _average(frameOnFrameValues),
      averageFrameCallbackMs: _average(frameCallbackValues),
      maxFrameCallbackMs: _maxDouble(maxFrameCallbackValues),
      updatedRegionEmptyCount: updatedRegionEmptyCount,
      updatedRegionNonEmptyCount: updatedRegionNonEmptyCount,
      updatedRegionRectCount: updatedRegionRectCount,
      updatedRegionMaxRectCount: updatedRegionMaxRectCount,
      averageUpdatedRegionAreaRatio: updatedRegionAreaRatioWeightedFrames > 0
          ? updatedRegionAreaRatioWeightedTotal /
                updatedRegionAreaRatioWeightedFrames
          : _average(updatedRegionAreaRatioValues),
      maxUpdatedRegionAreaRatio: _maxDouble(maxUpdatedRegionAreaRatioValues),
      averageUpdatedRegionAnalysisMs: updatedRegionAnalysisWeightedFrames > 0
          ? updatedRegionAnalysisWeightedTotal /
                updatedRegionAnalysisWeightedFrames
          : _average(updatedRegionAnalysisValues),
      maxUpdatedRegionAnalysisMs: _maxDouble(maxUpdatedRegionAnalysisValues),
      updatedRegionFullFrameCount: updatedRegionFullFrameCount,
      updatedRegionTinyFrameCount: updatedRegionTinyFrameCount,
      latestFramePacerEnabled: latestFramePacerEnabled,
      averagePacerSubmittedFps: _average(pacerSubmittedFpsValues),
      averagePacerUniqueFps: _average(pacerUniqueFpsValues),
      p95PacerIntervalMs: _average(p95PacerIntervalValues),
      maxPacerIntervalMs: _maxDouble(maxPacerIntervalValues),
      averagePacerFrameAgeMs: _average(pacerFrameAgeValues),
      maxPacerFrameAgeMs: _maxDouble(maxPacerFrameAgeValues),
      averagePacerOnFrameMs: _average(pacerOnFrameValues),
      maxPacerOnFrameMs: _maxDouble(maxPacerOnFrameValues),
      pacerDuplicateSubmitCount: pacerDuplicateSubmitCount,
      pacerOverwrittenFrameCount: pacerOverwrittenFrameCount,
      pacerSkippedTickCount: pacerSkippedTickCount,
      gameCaptureSourceWidth: gameCaptureSourceWidth,
      gameCaptureSourceHeight: gameCaptureSourceHeight,
      gameCaptureOutputWidth: gameCaptureOutputWidth,
      gameCaptureOutputHeight: gameCaptureOutputHeight,
      gameCaptureFormat: gameCaptureFormat,
      gameCaptureBackendContractVersion: gameCaptureBackendContractVersion,
      gameCaptureSourceMode: gameCaptureSourceMode,
      gameCaptureSourceApi: gameCaptureSourceApi,
      gameCaptureSourceApiId: gameCaptureSourceApiId,
      gameCaptureSourceFormat: gameCaptureSourceFormat,
      gameCaptureSourceFormatId: gameCaptureSourceFormatId,
      gameCaptureColorSpace: gameCaptureColorSpace,
      gameCaptureSyncKind: gameCaptureSyncKind,
      gameCaptureReadyState: gameCaptureReadyState,
      gameCaptureFailureReason: gameCaptureFailureReason,
      gameCaptureNativeAdmissionStrictDeadlineEnabled:
          gameCaptureNativeAdmissionStrictDeadlineEnabled,
      gameCaptureNativeAdmissionSourceDrivenFreshDueFrames:
          gameCaptureNativeAdmissionSourceDrivenFreshDueFrames,
      gameCaptureNativeAdmissionSourceQpcDueFrames:
          gameCaptureNativeAdmissionSourceQpcDueFrames,
      gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames:
          gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames,
      gameCaptureNativeAdmissionDeadlineDueFrames:
          gameCaptureNativeAdmissionDeadlineDueFrames,
      averageGameCaptureNativeAdmissionDeadlineLatenessMs: _average(
        gameCaptureNativeAdmissionDeadlineLatenessMsValues,
      ),
      maxGameCaptureNativeAdmissionDeadlineLatenessMs: _maxDouble(
        gameCaptureNativeAdmissionDeadlineLatenessMaxMsValues,
      ),
      gameCaptureNativeAdmissionDeadlineLatenessSamples:
          gameCaptureNativeAdmissionDeadlineLatenessSamples,
      gameCaptureNativeAdmissionDeadlineOver1xFrames:
          gameCaptureNativeAdmissionDeadlineOver1xFrames,
      gameCaptureNativeAdmissionDeadlineOver2xFrames:
          gameCaptureNativeAdmissionDeadlineOver2xFrames,
      gameCaptureNativeAdmissionDeadlineOver3xFrames:
          gameCaptureNativeAdmissionDeadlineOver3xFrames,
      gameCaptureNativeAdmissionNoSourceOnDeadlineFrames:
          gameCaptureNativeAdmissionNoSourceOnDeadlineFrames,
      gameCaptureNativeAdmissionRepeatedOnDeadlineFrames:
          gameCaptureNativeAdmissionRepeatedOnDeadlineFrames,
      gameCaptureNativeAdmissionSubmitOnDeadlineFrames:
          gameCaptureNativeAdmissionSubmitOnDeadlineFrames,
      gameCaptureNativeAdmissionSubmitOnEarlySourceFrames:
          gameCaptureNativeAdmissionSubmitOnEarlySourceFrames,
      gameCaptureNativeNv12PendingOnDeadlineFrames:
          gameCaptureNativeNv12PendingOnDeadlineFrames,
      gameCaptureNativeNv12NoPendingOnDeadlineFrames:
          gameCaptureNativeNv12NoPendingOnDeadlineFrames,
      gameCaptureNativeNv12ReadyOnDeadlineFrames:
          gameCaptureNativeNv12ReadyOnDeadlineFrames,
      gameCaptureNativeNv12NoReadyOnDeadlineFrames:
          gameCaptureNativeNv12NoReadyOnDeadlineFrames,
      gameCaptureConsumerAdapterLuid: gameCaptureConsumerAdapterLuid,
      gameCaptureConsumerAdapterVendorId: gameCaptureConsumerAdapterVendorId,
      gameCaptureConsumerAdapterDeviceId: gameCaptureConsumerAdapterDeviceId,
      gameCaptureSourceAdapterLuid: gameCaptureSourceAdapterLuid,
      gameCaptureCrossAdapterSuspected: gameCaptureCrossAdapterSuspected,
      averageGameCaptureFps: _average(gameCaptureFpsValues),
      gameCaptureSubmittedFrames: gameCaptureSubmittedFrames,
      gameCaptureRepeatedFrames: gameCaptureRepeatedFrames,
      gameCaptureDuplicateSkippedFrames: gameCaptureDuplicateSkippedFrames,
      gameCaptureDeliveryQueuedFrames: gameCaptureDeliveryQueuedFrames,
      gameCaptureDeliverySubmittedFrames: gameCaptureDeliverySubmittedFrames,
      gameCaptureDeliveryOverwrittenFrames:
          gameCaptureDeliveryOverwrittenFrames,
      gameCaptureDeliveryPacerResyncs: gameCaptureDeliveryPacerResyncs,
      gameCaptureDeliveryPacerLagMaxMs: gameCaptureDeliveryPacerLagMaxMs,
      gameCaptureDeliveryRepeatNoQueuedFrames:
          gameCaptureDeliveryRepeatNoQueuedFrames,
      gameCaptureDeliverySkipNoQueuedFrames:
          gameCaptureDeliverySkipNoQueuedFrames,
      gameCaptureDeliveryFreshWakeAfterSkipFrames:
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
      gameCaptureDeliveryFreshImmediateFrames:
          gameCaptureDeliveryFreshImmediateFrames,
      gameCaptureDeliveryRepeatPolicy: gameCaptureDeliveryRepeatPolicy,
      gameCaptureDeliveryQueueDepth: gameCaptureDeliveryQueueDepth,
      averageGameCaptureDeliveryRepeatSourceAgeMs: _average(
        gameCaptureDeliveryRepeatSourceAgeMsValues,
      ),
      maxGameCaptureDeliveryRepeatSourceAgeMs: _maxDouble(
        gameCaptureDeliveryRepeatSourceAgeMaxMsValues,
      ),
      gameCaptureDeliveryRepeatSourceAgeSamples:
          gameCaptureDeliveryRepeatSourceAgeSamples,
      averageGameCaptureDeliveryOnFrameMs: _average(
        gameCaptureDeliveryOnFrameMsValues,
      ),
      maxGameCaptureDeliveryOnFrameMs: _maxDouble(
        gameCaptureDeliveryOnFrameMaxMsValues,
      ),
      averageGameCaptureDeliverySubmitPrepMs: _average(
        gameCaptureDeliverySubmitPrepMsValues,
      ),
      maxGameCaptureDeliverySubmitPrepMs: _maxDouble(
        gameCaptureDeliverySubmitPrepMaxMsValues,
      ),
      gameCaptureDeliverySubmitPrepSamples:
          gameCaptureDeliverySubmitPrepSamples,
      averageGameCaptureDeliveryOnFrameCallMs: _average(
        gameCaptureDeliveryOnFrameCallMsValues,
      ),
      maxGameCaptureDeliveryOnFrameCallMs: _maxDouble(
        gameCaptureDeliveryOnFrameCallMaxMsValues,
      ),
      gameCaptureDeliveryOnFrameCallSamples:
          gameCaptureDeliveryOnFrameCallSamples,
      averageGameCaptureDeliveryPostOnFrameMs: _average(
        gameCaptureDeliveryPostOnFrameMsValues,
      ),
      maxGameCaptureDeliveryPostOnFrameMs: _maxDouble(
        gameCaptureDeliveryPostOnFrameMaxMsValues,
      ),
      gameCaptureDeliveryPostOnFrameSamples:
          gameCaptureDeliveryPostOnFrameSamples,
      averageGameCaptureNativeBufferReleaseMs: _average(
        gameCaptureNativeBufferReleaseMsValues,
      ),
      maxGameCaptureNativeBufferReleaseMs: _maxDouble(
        gameCaptureNativeBufferReleaseMaxMsValues,
      ),
      gameCaptureNativeBufferReleaseSamples:
          gameCaptureNativeBufferReleaseSamples,
      averageGameCaptureReadyToQueueMs: _average(
        gameCaptureReadyToQueueMsValues,
      ),
      maxGameCaptureReadyToQueueMs: _maxDouble(
        gameCaptureReadyToQueueMaxMsValues,
      ),
      gameCaptureReadyToQueueSamples: gameCaptureReadyToQueueSamples,
      averageGameCaptureDeliveryQueueWaitMs: _average(
        gameCaptureDeliveryQueueWaitMsValues,
      ),
      maxGameCaptureDeliveryQueueWaitMs: _maxDouble(
        gameCaptureDeliveryQueueWaitMaxMsValues,
      ),
      gameCaptureDeliveryQueueWaitSamples: gameCaptureDeliveryQueueWaitSamples,
      averageGameCaptureDeliveryOverwriteAgeMs: _average(
        gameCaptureDeliveryOverwriteAgeMsValues,
      ),
      maxGameCaptureDeliveryOverwriteAgeMs: _maxDouble(
        gameCaptureDeliveryOverwriteAgeMaxMsValues,
      ),
      gameCaptureDeliveryOverwriteAgeSamples:
          gameCaptureDeliveryOverwriteAgeSamples,
      gameCaptureDeliveryOverwrittenFreshFrames:
          gameCaptureDeliveryOverwrittenFreshFrames,
      averageGameCaptureReadyToSubmitMs: _average(
        gameCaptureReadyToSubmitMsValues,
      ),
      maxGameCaptureReadyToSubmitMs: _maxDouble(
        gameCaptureReadyToSubmitMaxMsValues,
      ),
      gameCaptureReadyToSubmitSamples: gameCaptureReadyToSubmitSamples,
      averageGameCaptureSourceToSubmitMs: _average(
        gameCaptureSourceToSubmitMsValues,
      ),
      maxGameCaptureSourceToSubmitMs: _maxDouble(
        gameCaptureSourceToSubmitMaxMsValues,
      ),
      gameCaptureSourceToSubmitSamples: gameCaptureSourceToSubmitSamples,
      averageGameCaptureSourceToReadbackReadyMs: _average(
        gameCaptureSourceToReadbackReadyMsValues,
      ),
      maxGameCaptureSourceToReadbackReadyMs: _maxDouble(
        gameCaptureSourceToReadbackReadyMaxMsValues,
      ),
      gameCaptureSourceToReadbackReadySamples:
          gameCaptureSourceToReadbackReadySamples,
      averageGameCaptureReadbackQueueToMapMs: _average(
        gameCaptureReadbackQueueToMapMsValues,
      ),
      maxGameCaptureReadbackQueueToMapMs: _maxDouble(
        gameCaptureReadbackQueueToMapMaxMsValues,
      ),
      gameCaptureReadbackQueueToMapSamples:
          gameCaptureReadbackQueueToMapSamples,
      averageGameCaptureMapToI420Ms: _average(gameCaptureMapToI420MsValues),
      maxGameCaptureMapToI420Ms: _maxDouble(gameCaptureMapToI420MaxMsValues),
      gameCaptureMapToI420Samples: gameCaptureMapToI420Samples,
      averageGameCaptureSourceToI420ReadyMs: _average(
        gameCaptureSourceToI420ReadyMsValues,
      ),
      maxGameCaptureSourceToI420ReadyMs: _maxDouble(
        gameCaptureSourceToI420ReadyMaxMsValues,
      ),
      gameCaptureSourceToI420ReadySamples: gameCaptureSourceToI420ReadySamples,
      averageGameCaptureSourceToQueueMs: _average(
        gameCaptureSourceToQueueMsValues,
      ),
      maxGameCaptureSourceToQueueMs: _maxDouble(
        gameCaptureSourceToQueueMaxMsValues,
      ),
      gameCaptureSourceToQueueSamples: gameCaptureSourceToQueueSamples,
      averageGameCaptureSourceDuplicateSkipAgeMs: _average(
        gameCaptureSourceDuplicateSkipAgeMsValues,
      ),
      maxGameCaptureSourceDuplicateSkipAgeMs: _maxDouble(
        gameCaptureSourceDuplicateSkipAgeMaxMsValues,
      ),
      gameCaptureSourceDuplicateSkipAgeSamples:
          gameCaptureSourceDuplicateSkipAgeSamples,
      gameCaptureCopiedFrames: gameCaptureCopiedFrames,
      gameCaptureDroppedFrames: gameCaptureDroppedFrames,
      gameCaptureOverwrittenFrames: gameCaptureOverwrittenFrames,
      gameCaptureGpuScaledFrames: gameCaptureGpuScaledFrames,
      gameCaptureGpuScaleFailures: gameCaptureGpuScaleFailures,
      gameCaptureCpuFallbackFrames: gameCaptureCpuFallbackFrames,
      gameCaptureNativeNv12SubmittedFrames:
          gameCaptureNativeNv12SubmittedFrames,
      gameCaptureNativeNv12QueuedFrames: gameCaptureNativeNv12QueuedFrames,
      gameCaptureNativeNv12ReadyFrames: gameCaptureNativeNv12ReadyFrames,
      gameCaptureNativeNv12NotReadyPolls: gameCaptureNativeNv12NotReadyPolls,
      gameCaptureNativeNv12ReadyPolicy: gameCaptureNativeNv12ReadyPolicy,
      gameCaptureNativeNv12FenceAvailable: gameCaptureNativeNv12FenceAvailable,
      gameCaptureNativeNv12PendingPollMs: gameCaptureNativeNv12PendingPollMs,
      gameCaptureNativeNv12MaxPendingSlots:
          gameCaptureNativeNv12MaxPendingSlots,
      gameCaptureNativeNv12ReadyDrainDepth:
          gameCaptureNativeNv12ReadyDrainDepth,
      gameCaptureNativeNv12FrameOwnership: gameCaptureNativeNv12FrameOwnership,
      gameCaptureNativeNv12WarmupI420Frames:
          gameCaptureNativeNv12WarmupI420Frames,
      gameCaptureNativeNv12SingleInFlightEnabled:
          gameCaptureNativeNv12SingleInFlightEnabled,
      gameCaptureNativeNv12GpuQueueBackoffEnabled:
          gameCaptureNativeNv12GpuQueueBackoffEnabled,
      gameCaptureNativeNv12GpuQueueBackoffThresholdFrames:
          gameCaptureNativeNv12GpuQueueBackoffThresholdFrames,
      gameCaptureNativeNv12GpuQueueBackoffDurationFrames:
          gameCaptureNativeNv12GpuQueueBackoffDurationFrames,
      gameCaptureNativeNv12FenceSignaledFrames:
          gameCaptureNativeNv12FenceSignaledFrames,
      gameCaptureNativeNv12FenceReadyFrames:
          gameCaptureNativeNv12FenceReadyFrames,
      gameCaptureNativeNv12FenceSignalFailures:
          gameCaptureNativeNv12FenceSignalFailures,
      gameCaptureNativeNv12OwnedCopies: gameCaptureNativeNv12OwnedCopies,
      averageGameCaptureNativeNv12OwnedCopyMs: _average(
        gameCaptureNativeNv12OwnedCopyMsValues,
      ),
      maxGameCaptureNativeNv12OwnedCopyMs: _maxDouble(
        gameCaptureNativeNv12OwnedCopyMaxMsValues,
      ),
      gameCaptureNativeNv12OwnedCopySamples:
          gameCaptureNativeNv12OwnedCopySamples,
      gameCaptureNativeNv12OverwrittenFrames:
          gameCaptureNativeNv12OverwrittenFrames,
      averageGameCaptureNativeNv12OverwriteAgeMs: _average(
        gameCaptureNativeNv12OverwriteAgeMsValues,
      ),
      maxGameCaptureNativeNv12OverwriteAgeMs: _maxDouble(
        gameCaptureNativeNv12OverwriteAgeMaxMsValues,
      ),
      gameCaptureNativeNv12OverwriteAgeSamples:
          gameCaptureNativeNv12OverwriteAgeSamples,
      gameCaptureNativeNv12OverwrittenFreshFrames:
          gameCaptureNativeNv12OverwrittenFreshFrames,
      gameCaptureNativeNv12ReadyDroppedFrames:
          gameCaptureNativeNv12ReadyDroppedFrames,
      averageGameCaptureNativeNv12ReadyDropAgeMs: _average(
        gameCaptureNativeNv12ReadyDropAgeMsValues,
      ),
      maxGameCaptureNativeNv12ReadyDropAgeMs: _maxDouble(
        gameCaptureNativeNv12ReadyDropAgeMaxMsValues,
      ),
      gameCaptureNativeNv12ReadyDropAgeSamples:
          gameCaptureNativeNv12ReadyDropAgeSamples,
      gameCaptureNativeNv12ReadyDroppedFreshFrames:
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
      gameCaptureNativeNv12LateReadyDropEnabled:
          gameCaptureNativeNv12LateReadyDropEnabled,
      gameCaptureNativeNv12LateReadyDropThresholdMs:
          gameCaptureNativeNv12LateReadyDropThresholdMs,
      gameCaptureNativeNv12LateReadyDroppedFrames:
          gameCaptureNativeNv12LateReadyDroppedFrames,
      averageGameCaptureNativeNv12LateReadyDropAgeMs: _average(
        gameCaptureNativeNv12LateReadyDropAgeMsValues,
      ),
      maxGameCaptureNativeNv12LateReadyDropAgeMs: _maxDouble(
        gameCaptureNativeNv12LateReadyDropAgeMaxMsValues,
      ),
      gameCaptureNativeNv12LateReadyDropAgeSamples:
          gameCaptureNativeNv12LateReadyDropAgeSamples,
      gameCaptureNativeNv12LateReadyDroppedFreshFrames:
          gameCaptureNativeNv12LateReadyDroppedFreshFrames,
      averageGameCaptureNativeNv12LateReadyDropBltToReadyMs: _average(
        gameCaptureNativeNv12LateReadyDropBltToReadyMsValues,
      ),
      maxGameCaptureNativeNv12LateReadyDropBltToReadyMs: _maxDouble(
        gameCaptureNativeNv12LateReadyDropBltToReadyMaxMsValues,
      ),
      gameCaptureNativeNv12LateReadyDropBltToReadySamples:
          gameCaptureNativeNv12LateReadyDropBltToReadySamples,
      gameCaptureNativeNv12Failures: gameCaptureNativeNv12Failures,
      averageGameCaptureNativeNv12ConvertMs: _average(
        gameCaptureNativeNv12ConvertMsValues,
      ),
      maxGameCaptureNativeNv12ConvertMs: _maxDouble(
        gameCaptureNativeNv12ConvertMaxMsValues,
      ),
      gameCaptureNativeNv12ConvertSamples: gameCaptureNativeNv12ConvertSamples,
      averageGameCaptureNativeNv12BgraScaleDrawMs: _average(
        gameCaptureNativeNv12BgraScaleDrawMsValues,
      ),
      maxGameCaptureNativeNv12BgraScaleDrawMs: _maxDouble(
        gameCaptureNativeNv12BgraScaleDrawMaxMsValues,
      ),
      gameCaptureNativeNv12BgraScaleDrawSamples:
          gameCaptureNativeNv12BgraScaleDrawSamples,
      averageGameCaptureNativeNv12VideoProcessorBltSubmitMs: _average(
        gameCaptureNativeNv12VideoProcessorBltSubmitMsValues,
      ),
      maxGameCaptureNativeNv12VideoProcessorBltSubmitMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltSubmitSamples:
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
      averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs: _average(
        gameCaptureNativeNv12VideoProcessorBltCpuSubmitMsValues.isNotEmpty
            ? gameCaptureNativeNv12VideoProcessorBltCpuSubmitMsValues
            : gameCaptureNativeNv12VideoProcessorBltSubmitMsValues,
      ),
      maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltCpuSubmitMaxMsValues.isNotEmpty
            ? gameCaptureNativeNv12VideoProcessorBltCpuSubmitMaxMsValues
            : gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples:
          gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples == 0
          ? gameCaptureNativeNv12VideoProcessorBltSubmitSamples
          : gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples,
      averageGameCaptureNativeNv12VideoProcessorBltToReadyMs: _average(
        gameCaptureNativeNv12VideoProcessorBltToReadyMsValues,
      ),
      maxGameCaptureNativeNv12VideoProcessorBltToReadyMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltToReadySamples:
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
      averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs: _average(
        gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMsValues.isNotEmpty
            ? gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMsValues
            : gameCaptureNativeNv12VideoProcessorBltToReadyMsValues,
      ),
      maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMaxMsValues
                .isNotEmpty
            ? gameCaptureNativeNv12VideoProcessorBltSubmitToFenceMaxMsValues
            : gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples:
          gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples == 0
          ? gameCaptureNativeNv12VideoProcessorBltToReadySamples
          : gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples,
      averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs: _average(
        gameCaptureNativeNv12VideoProcessorBltGpuExecutionMsValues,
      ),
      maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltGpuExecutionMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples:
          gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples,
      averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs:
          _average(
            gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMsValues,
          ),
      maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs: _maxDouble(
        gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMsValues,
      ),
      gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples:
          gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples,
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures:
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures,
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady:
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady,
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint:
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint,
      gameCaptureNativeNv12ReadyObservedImmediateFrames:
          gameCaptureNativeNv12ReadyObservedImmediateFrames,
      gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames:
          gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames,
      gameCaptureNativeNv12ReadyObservedFenceEventFrames:
          gameCaptureNativeNv12ReadyObservedFenceEventFrames,
      gameCaptureNativeNv12ReadyObservedSourceEventFrames:
          gameCaptureNativeNv12ReadyObservedSourceEventFrames,
      gameCaptureNativeNv12ReadyObservedWaitOtherFrames:
          gameCaptureNativeNv12ReadyObservedWaitOtherFrames,
      gameCaptureNativeNv12ReadyObservedLoopIdleFrames:
          gameCaptureNativeNv12ReadyObservedLoopIdleFrames,
      gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames:
          gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames,
      gameCaptureNativeNv12ReadyObservedPreSubmitFrames:
          gameCaptureNativeNv12ReadyObservedPreSubmitFrames,
      gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames:
          gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames,
      gameCaptureNativeNv12ReadyObservedUnknownFrames:
          gameCaptureNativeNv12ReadyObservedUnknownFrames,
      gameCaptureNativeNv12BltToReadyOver1xFrames:
          gameCaptureNativeNv12BltToReadyOver1xFrames,
      gameCaptureNativeNv12BltToReadyOver2xFrames:
          gameCaptureNativeNv12BltToReadyOver2xFrames,
      gameCaptureNativeNv12BltToReadyOver3xFrames:
          gameCaptureNativeNv12BltToReadyOver3xFrames,
      averageGameCaptureNativeNv12BufferCreateMs: _average(
        gameCaptureNativeNv12BufferCreateMsValues,
      ),
      maxGameCaptureNativeNv12BufferCreateMs: _maxDouble(
        gameCaptureNativeNv12BufferCreateMaxMsValues,
      ),
      gameCaptureNativeNv12BufferCreateSamples:
          gameCaptureNativeNv12BufferCreateSamples,
      averageGameCaptureNativeNv12FrameReadyToQueueMs: _average(
        gameCaptureNativeNv12FrameReadyToQueueMsValues,
      ),
      maxGameCaptureNativeNv12FrameReadyToQueueMs: _maxDouble(
        gameCaptureNativeNv12FrameReadyToQueueMaxMsValues,
      ),
      gameCaptureNativeNv12FrameReadyToQueueSamples:
          gameCaptureNativeNv12FrameReadyToQueueSamples,
      averageGameCaptureNativeNv12ConversionStartAgeMs: _average(
        gameCaptureNativeNv12ConversionStartAgeMsValues,
      ),
      maxGameCaptureNativeNv12ConversionStartAgeMs: _maxDouble(
        gameCaptureNativeNv12ConversionStartAgeMaxMsValues,
      ),
      gameCaptureNativeNv12ConversionStartAgeSamples:
          gameCaptureNativeNv12ConversionStartAgeSamples,
      gameCaptureNativeNv12SingleInFlightDeferredFrames:
          gameCaptureNativeNv12SingleInFlightDeferredFrames,
      gameCaptureNativeNv12SingleInFlightDeferredFreshFrames:
          gameCaptureNativeNv12SingleInFlightDeferredFreshFrames,
      gameCaptureNativeNv12SingleInFlightPendingMax:
          gameCaptureNativeNv12SingleInFlightPendingMax,
      averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs: _average(
        gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMsValues,
      ),
      maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs: _maxDouble(
        gameCaptureNativeNv12SingleInFlightDeferredSourceAgeMaxMsValues,
      ),
      gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples:
          gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples,
      gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames:
          gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames,
      gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames:
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames,
      gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames:
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames,
      averageGameCaptureNativeNv12GpuQueueBackoffMs: _average(
        gameCaptureNativeNv12GpuQueueBackoffMsValues,
      ),
      maxGameCaptureNativeNv12GpuQueueBackoffMs: _maxDouble(
        gameCaptureNativeNv12GpuQueueBackoffMaxMsValues,
      ),
      gameCaptureNativeNv12GpuQueueBackoffSamples:
          gameCaptureNativeNv12GpuQueueBackoffSamples,
      averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs: _average(
        gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMsValues,
      ),
      maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs: _maxDouble(
        gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMaxMsValues,
      ),
      gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples:
          gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples,
      averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs:
          _average(
            gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMsValues,
          ),
      maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs: _maxDouble(
        gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMaxMsValues,
      ),
      gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples:
          gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples,
      gameCaptureNativeNv12AdmissionMailboxEnabled:
          gameCaptureNativeNv12AdmissionMailboxEnabled,
      gameCaptureNativeNv12AdmissionMailboxPendingActive:
          gameCaptureNativeNv12AdmissionMailboxPendingActive,
      gameCaptureNativeNv12AdmissionMailboxStoredFrames:
          gameCaptureNativeNv12AdmissionMailboxStoredFrames,
      gameCaptureNativeNv12AdmissionMailboxReplacedFrames:
          gameCaptureNativeNv12AdmissionMailboxReplacedFrames,
      gameCaptureNativeNv12AdmissionMailboxSubmittedFrames:
          gameCaptureNativeNv12AdmissionMailboxSubmittedFrames,
      gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames:
          gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames,
      averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs: _average(
        gameCaptureNativeNv12AdmissionMailboxPendingAgeMsValues,
      ),
      maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs: _maxDouble(
        gameCaptureNativeNv12AdmissionMailboxPendingAgeMaxMsValues,
      ),
      gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples:
          gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples,
      averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs: _average(
        gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMsValues,
      ),
      maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs: _maxDouble(
        gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMaxMsValues,
      ),
      gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples:
          gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples,
      gameCaptureNativeNv12StaleBeforeQueueFrames:
          gameCaptureNativeNv12StaleBeforeQueueFrames,
      gameCaptureNativeNv12HandoffDisabledReason:
          gameCaptureNativeNv12HandoffDisabledReason,
      gameCaptureNativeNv12OnFrameBackpressureEnabled:
          gameCaptureNativeNv12OnFrameBackpressureEnabled,
      gameCaptureNativeNv12OnFrameBackpressureThresholdMs:
          gameCaptureNativeNv12OnFrameBackpressureThresholdMs,
      gameCaptureNativeNv12OnFrameBackpressureFrameLimit:
          gameCaptureNativeNv12OnFrameBackpressureFrameLimit,
      gameCaptureNativeNv12OnFrameBackpressureFrames:
          gameCaptureNativeNv12OnFrameBackpressureFrames,
      gameCaptureNativeNv12OnFrameBackpressureStreak:
          gameCaptureNativeNv12OnFrameBackpressureStreak,
      gameCaptureNativeNv12OnFrameBackpressureMaxMs: _maxDouble(
        gameCaptureNativeNv12OnFrameBackpressureMaxMsValues,
      ),
      gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure:
          gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure,
      gameCaptureReadbackQueuedFrames: gameCaptureReadbackQueuedFrames,
      gameCaptureReadbackReadyFrames: gameCaptureReadbackReadyFrames,
      gameCaptureReadbackNotReadyFrames: gameCaptureReadbackNotReadyFrames,
      gameCaptureReadbackOverwrittenFrames:
          gameCaptureReadbackOverwrittenFrames,
      gameCaptureReadbackStaleDroppedFrames:
          gameCaptureReadbackStaleDroppedFrames,
      gameCaptureReadbackLatencyDroppedFrames:
          gameCaptureReadbackLatencyDroppedFrames,
      gameCaptureReadbackMapAttempts: gameCaptureReadbackMapAttempts,
      gameCaptureSourceFrameIndex: gameCaptureSourceFrameIndex,
      gameCaptureLastSubmittedSourceFrameIndex:
          gameCaptureLastSubmittedSourceFrameIndex,
      gameCaptureSourceFrameRegressions: gameCaptureSourceFrameRegressions,
      gameCaptureSourceFrameDuplicates: gameCaptureSourceFrameDuplicates,
      gameCaptureSourceFrameGaps: gameCaptureSourceFrameGaps,
      gameCaptureSharedSlotMismatches: gameCaptureSharedSlotMismatches,
      gameCaptureTimestampMode: gameCaptureTimestampMode,
      gameCaptureTimestampSourceQpcFrames: gameCaptureTimestampSourceQpcFrames,
      gameCaptureTimestampPacedFallbackFrames:
          gameCaptureTimestampPacedFallbackFrames,
      gameCaptureTimestampRepeatedFrames: gameCaptureTimestampRepeatedFrames,
      averageGameCaptureTimestampDeltaMs: _average(
        gameCaptureTimestampDeltaMsValues,
      ),
      maxGameCaptureTimestampDeltaMs: _maxDouble(
        gameCaptureTimestampDeltaMaxMsValues,
      ),
      gameCaptureTimestampSamples: gameCaptureTimestampSamples,
      gameCaptureTimestampAdjustments: gameCaptureTimestampAdjustments,
      averageGameCaptureDeliveryWallDeltaMs: _average(
        gameCaptureDeliveryWallDeltaMsValues,
      ),
      maxGameCaptureDeliveryWallDeltaMs: _maxDouble(
        gameCaptureDeliveryWallDeltaMaxMsValues,
      ),
      minGameCaptureDeliveryWallDeltaMs: _minDouble(
        gameCaptureDeliveryWallDeltaMinMsValues,
      ),
      gameCaptureDeliveryWallSamples: gameCaptureDeliveryWallSamples,
      gameCaptureDeliveryWallOver2xFrames: gameCaptureDeliveryWallOver2xFrames,
      gameCaptureDeliveryWallOver3xFrames: gameCaptureDeliveryWallOver3xFrames,
      gameCaptureDeliveryWallUnderHalfFrames:
          gameCaptureDeliveryWallUnderHalfFrames,
      averageGameCaptureSourceQpcDeltaMs: _average(
        gameCaptureSourceQpcDeltaMsValues,
      ),
      maxGameCaptureSourceQpcDeltaMs: _maxDouble(
        gameCaptureSourceQpcDeltaMaxMsValues,
      ),
      gameCaptureSourceQpcSamples: gameCaptureSourceQpcSamples,
      gameCaptureSourceQpcRegressions: gameCaptureSourceQpcRegressions,
      gameCaptureSourceQpcOver2xFrames: gameCaptureSourceQpcOver2xFrames,
      gameCaptureSourceQpcOver3xFrames: gameCaptureSourceQpcOver3xFrames,
      gameCaptureSourceQpcUnderHalfFrames: gameCaptureSourceQpcUnderHalfFrames,
      gameCaptureSourceLatestObservedFrames:
          gameCaptureSourceLatestObservedFrames,
      gameCaptureSourceLatestFrameGaps: gameCaptureSourceLatestFrameGaps,
      gameCaptureSourceLatestFrameRegressions:
          gameCaptureSourceLatestFrameRegressions,
      averageGameCaptureSourceLatestQpcDeltaMs: _average(
        gameCaptureSourceLatestQpcDeltaMsValues,
      ),
      maxGameCaptureSourceLatestQpcDeltaMs: _maxDouble(
        gameCaptureSourceLatestQpcDeltaMaxMsValues,
      ),
      gameCaptureSourceLatestQpcSamples: gameCaptureSourceLatestQpcSamples,
      gameCaptureSourceLatestQpcRegressions:
          gameCaptureSourceLatestQpcRegressions,
      gameCaptureSourceLatestQpcOver2xFrames:
          gameCaptureSourceLatestQpcOver2xFrames,
      gameCaptureSourceLatestQpcOver3xFrames:
          gameCaptureSourceLatestQpcOver3xFrames,
      gameCaptureSourceLatestQpcUnderHalfFrames:
          gameCaptureSourceLatestQpcUnderHalfFrames,
      averageGameCaptureSourceLatestObservationDeltaMs: _average(
        gameCaptureSourceLatestObservationDeltaMsValues,
      ),
      maxGameCaptureSourceLatestObservationDeltaMs: _maxDouble(
        gameCaptureSourceLatestObservationDeltaMaxMsValues,
      ),
      gameCaptureSourceLatestObservationSamples:
          gameCaptureSourceLatestObservationSamples,
      gameCaptureSourceLatestObservationOver2xFrames:
          gameCaptureSourceLatestObservationOver2xFrames,
      gameCaptureSourceLatestObservationOver3xFrames:
          gameCaptureSourceLatestObservationOver3xFrames,
      averageGameCaptureSourceLatestEventAgeMs: _average(
        gameCaptureSourceLatestEventAgeMsValues,
      ),
      maxGameCaptureSourceLatestEventAgeMs: _maxDouble(
        gameCaptureSourceLatestEventAgeMaxMsValues,
      ),
      gameCaptureSourceLatestEventAgeSamples:
          gameCaptureSourceLatestEventAgeSamples,
      gameCaptureSourceLatestEventAgeOver1xFrames:
          gameCaptureSourceLatestEventAgeOver1xFrames,
      gameCaptureSourceLatestEventAgeOver2xFrames:
          gameCaptureSourceLatestEventAgeOver2xFrames,
      gameCaptureSourceLatestEventAgeOver3xFrames:
          gameCaptureSourceLatestEventAgeOver3xFrames,
      averageGameCaptureSourcePublishObservationAgeMs: _average(
        gameCaptureSourcePublishObservationAgeMsValues,
      ),
      maxGameCaptureSourcePublishObservationAgeMs: _maxDouble(
        gameCaptureSourcePublishObservationAgeMaxMsValues,
      ),
      gameCaptureSourcePublishObservationAgeSamples:
          gameCaptureSourcePublishObservationAgeSamples,
      gameCaptureSourcePublishObservationAgeOver1xFrames:
          gameCaptureSourcePublishObservationAgeOver1xFrames,
      gameCaptureSourcePublishObservationAgeOver2xFrames:
          gameCaptureSourcePublishObservationAgeOver2xFrames,
      gameCaptureSourcePublishObservationAgeOver3xFrames:
          gameCaptureSourcePublishObservationAgeOver3xFrames,
      averageGameCaptureProducerPresentGapMs: _average(
        gameCaptureProducerPresentGapMsValues,
      ),
      maxGameCaptureProducerPresentGapMs: _maxDouble(
        gameCaptureProducerPresentGapMaxMsValues,
      ),
      gameCaptureProducerPresentGapSamples:
          gameCaptureProducerPresentGapSamples,
      averageGameCaptureProducerCaptureGapMs: _average(
        gameCaptureProducerCaptureGapMsValues,
      ),
      maxGameCaptureProducerCaptureGapMs: _maxDouble(
        gameCaptureProducerCaptureGapMaxMsValues,
      ),
      gameCaptureProducerCaptureGapSamples:
          gameCaptureProducerCaptureGapSamples,
      averageGameCaptureProducerPresentToPublishMs: _average(
        gameCaptureProducerPresentToPublishMsValues,
      ),
      maxGameCaptureProducerPresentToPublishMs: _maxDouble(
        gameCaptureProducerPresentToPublishMaxMsValues,
      ),
      gameCaptureProducerPresentToPublishSamples:
          gameCaptureProducerPresentToPublishSamples,
      averageGameCaptureProducerCopyMs: _average(
        gameCaptureProducerCopyMsValues,
      ),
      maxGameCaptureProducerCopyMs: _maxDouble(
        gameCaptureProducerCopyMaxMsValues,
      ),
      gameCaptureProducerCopySamples: gameCaptureProducerCopySamples,
      averageGameCaptureProducerResolveMs: _average(
        gameCaptureProducerResolveMsValues,
      ),
      maxGameCaptureProducerResolveMs: _maxDouble(
        gameCaptureProducerResolveMaxMsValues,
      ),
      gameCaptureProducerResolveSamples: gameCaptureProducerResolveSamples,
      gameCaptureProducerThrottledFrames: gameCaptureProducerThrottledFrames,
      averageGameCaptureCopyMs: _average(gameCaptureCopyMsValues),
      averageGameCaptureMapMs: _average(gameCaptureMapMsValues),
      averageGameCaptureConvertMs: _average(gameCaptureConvertMsValues),
      averageGameCaptureGpuScaleMs: _average(gameCaptureGpuScaleMsValues),
      averageGameCaptureReadbackLatencyMs: _average(
        gameCaptureReadbackLatencyMsValues,
      ),
      averageGameCaptureReadbackLatencyFrames: _average(
        gameCaptureReadbackLatencyFrameValues,
      ),
      gameCaptureMaxReadbackLatencyFrames: gameCaptureMaxReadbackLatencyFrames,
      gameCaptureMapFailures: gameCaptureMapFailures,
      gameCaptureConvertFailures: gameCaptureConvertFailures,
      gameCaptureProofFrames: gameCaptureProofFrames,
      gameCaptureVisibleProofFrames: gameCaptureVisibleProofFrames,
      gameCaptureProofVisible: gameCaptureProofVisible,
      gameCaptureProofPath: gameCaptureProofPath,
      gameCaptureProofMinLuma: gameCaptureProofMinLuma,
      gameCaptureProofMaxLuma: gameCaptureProofMaxLuma,
      gameCaptureProofNonzeroSamples: gameCaptureProofNonzeroSamples,
      gameCaptureProofSamples: gameCaptureProofSamples,
      gameCaptureI420ProofFrames: gameCaptureI420ProofFrames,
      gameCaptureVisibleI420ProofFrames: gameCaptureVisibleI420ProofFrames,
      gameCaptureInitialBlackSkippedFrames:
          gameCaptureInitialBlackSkippedFrames,
      gameCaptureVisibleSourceSeen: gameCaptureVisibleSourceSeen,
      gameCaptureI420ProofVisible: gameCaptureI420ProofVisible,
      gameCaptureI420ProofPath: gameCaptureI420ProofPath,
      gameCaptureI420ProofMinLuma: gameCaptureI420ProofMinLuma,
      gameCaptureI420ProofMaxLuma: gameCaptureI420ProofMaxLuma,
      gameCaptureI420ProofNonzeroSamples: gameCaptureI420ProofNonzeroSamples,
      gameCaptureI420ProofSamples: gameCaptureI420ProofSamples,
      gameCaptureVisualFreshnessSampleMode:
          gameCaptureVisualFreshnessSampleMode,
      gameCaptureVisualFreshnessSampleFrames:
          gameCaptureVisualFreshnessSampleFrames,
      gameCaptureVisualFreshnessUniqueFrames:
          gameCaptureVisualFreshnessUniqueFrames,
      averageGameCaptureVisualFreshnessUniqueFps: _average(
        gameCaptureVisualFreshnessUniqueFpsValues,
      ),
      gameCaptureVisualFreshnessLongestStaleMs: _maxDouble(
        gameCaptureVisualFreshnessLongestStaleMsValues,
      ),
      gameCaptureVisualFreshnessLongestStaleFrames:
          gameCaptureVisualFreshnessLongestStaleFrames,
      gameCaptureVisualFreshnessLowChangeFrames:
          gameCaptureVisualFreshnessLowChangeFrames,
      gameCaptureVisualFreshnessArtifactSet:
          gameCaptureVisualFreshnessArtifactSet,
      averageEncoderTotalMs: _average(encoderTotalValues),
      maxEncoderTotalMs: _maxDouble(encoderTotalValues),
      encoderSlowFrameCount: encoderSlowFrameCount,
      encoderSampleCount: encoderTotalValues.length,
      encoderRateControlMode: encoderRateControlMode,
      encoderTargetBitrateBps: encoderTargetBitrateBps,
      encoderInputPaths: List.unmodifiable(encoderInputPaths),
      encoderNativeInputFrames: encoderNativeInputFrames,
      encoderCpuI420InputFrames: encoderCpuI420InputFrames,
      encoderNativeSampleFailures: encoderNativeSampleFailures,
      encoderNativeSuspendedFrames: encoderNativeSuspendedFrames,
      encoderNativeReadyFenceFrames: encoderNativeReadyFenceFrames,
      encoderNativeReadyFenceTimeoutFrames:
          encoderNativeReadyFenceTimeoutFrames,
      averageEncoderNativeReadyFenceWaitMs: _average(
        encoderNativeReadyFenceWaitValues,
      ),
      maxEncoderNativeReadyFenceWaitMs: _maxDouble(
        encoderNativeReadyFenceWaitValues,
      ),
      encoderNativeReadyFenceWaitSamples:
          encoderNativeReadyFenceWaitValues.length,
      encoderNativeSourceMode: encoderNativeSourceMode,
      encoderNativeSourceFormat: encoderNativeSourceFormat,
      encoderNativeSourceFrameIndex: encoderNativeSourceFrameIndex,
      averageEncoderNativeSourceAgeMs: _average(encoderNativeSourceAgeValues),
      maxEncoderNativeSourceAgeMs: _maxDouble(encoderNativeSourceAgeValues),
      encoderNativeSourceAgeSamples: encoderNativeSourceAgeValues.length,
      averageEncoderNativeSourceAgeAtCreateMs: _average(
        encoderNativeSourceAgeAtCreateValues,
      ),
      maxEncoderNativeSourceAgeAtCreateMs: _maxDouble(
        encoderNativeSourceAgeAtCreateValues,
      ),
      averageEncoderNativeBufferAgeMs: _average(encoderNativeBufferAgeValues),
      maxEncoderNativeBufferAgeMs: _maxDouble(encoderNativeBufferAgeValues),
      encoderNativeBufferAgeSamples: encoderNativeBufferAgeValues.length,
      averageEncoderNativeSampleLifetimeMs: _average(
        encoderNativeSampleLifetimeValues,
      ),
      maxEncoderNativeSampleLifetimeMs: _maxDouble(
        encoderNativeSampleLifetimeMaxValues,
      ),
      encoderNativeSampleLifetimeSamples: max(
        encoderNativeSampleLifetimeSamples,
        encoderNativeSampleLifetimeValues.length,
      ),
      encoderNativeAdapterLuid: encoderNativeAdapterLuid,
      encoderNativeAdapterVendorId: encoderNativeAdapterVendorId,
      encoderNativeAdapterDeviceId: encoderNativeAdapterDeviceId,
      averageEncoderProcessInputMs: _average(encoderProcessInputValues),
      maxEncoderProcessInputMs: _maxDouble(encoderProcessInputValues),
      encoderProcessInputSamples: encoderProcessInputValues.length,
      averageEncoderProcessOutputMs: _average(encoderProcessOutputValues),
      maxEncoderProcessOutputMs: _maxDouble(encoderProcessOutputValues),
      encoderProcessOutputSamples: encoderProcessOutputValues.length,
      averageEncoderEncodedCallbackMs: _average(encoderEncodedCallbackValues),
      maxEncoderEncodedCallbackMs: _maxDouble(encoderEncodedCallbackValues),
      encoderEncodedCallbackSamples: encoderEncodedCallbackValues.length,
      averageEncoderEncodedCallbackQueueWaitMs: _average(
        encoderEncodedCallbackQueueWaitValues,
      ),
      maxEncoderEncodedCallbackQueueWaitMs: _maxDouble(
        encoderEncodedCallbackQueueWaitValues,
      ),
      encoderEncodedCallbackQueueWaitSamples:
          encoderEncodedCallbackQueueWaitValues.length,
      averageEncoderEncodedCallbackEnqueueMs: _average(
        encoderEncodedCallbackEnqueueValues,
      ),
      maxEncoderEncodedCallbackEnqueueMs: _maxDouble(
        encoderEncodedCallbackEnqueueValues,
      ),
      encoderEncodedCallbackEnqueueSamples:
          encoderEncodedCallbackEnqueueValues.length,
      encoderEncodedCallbackAsyncFrames: encoderEncodedCallbackAsyncFrames,
      encoderMaxEncodedCallbackQueueDepth: encoderMaxEncodedCallbackQueueDepth,
      encoderMaxEncodedCallbackDrops: encoderMaxEncodedCallbackDrops,
      encoderMaxEncodedCallbackOutputs: encoderMaxEncodedCallbackOutputs,
      encoderStages: List.unmodifiable(encoderStages),
      encoderOutputFrames: encoderOutputFrames,
      encoderOutputBytes: encoderOutputBytes,
      encoderMaxQueueDepth: encoderMaxQueueDepth,
      encoderMaxRetainedSamples: encoderMaxRetainedSamples,
      encoderMaxEncodedOutputs: encoderMaxEncodedOutputs,
      averageWebrtcSourceOnFrameMs: _average(webrtcSourceOnFrameMsValues),
      maxWebrtcSourceOnFrameMs: _maxDouble(webrtcSourceOnFrameMaxMsValues),
      webrtcSourceOnFrameSamples: webrtcSourceOnFrameSamples,
      averageWebrtcSourceAdaptMs: _average(webrtcSourceAdaptMsValues),
      maxWebrtcSourceAdaptMs: _maxDouble(webrtcSourceAdaptMaxMsValues),
      averageWebrtcSourceScaleMs: _average(webrtcSourceScaleMsValues),
      maxWebrtcSourceScaleMs: _maxDouble(webrtcSourceScaleMaxMsValues),
      averageWebrtcSourceBroadcastMs: _average(webrtcSourceBroadcastMsValues),
      maxWebrtcSourceBroadcastMs: _maxDouble(webrtcSourceBroadcastMaxMsValues),
      webrtcSourceAdapterDrops: webrtcSourceAdapterDrops,
      webrtcSourceScaledFrames: webrtcSourceScaledFrames,
      averageWebrtcVideoBroadcasterMs: _average(webrtcVideoBroadcasterMsValues),
      maxWebrtcVideoBroadcasterMs: _maxDouble(
        webrtcVideoBroadcasterMaxMsValues,
      ),
      webrtcVideoBroadcasterSamples: webrtcVideoBroadcasterSamples,
      averageWebrtcVideoBroadcasterLockWaitMs: _average(
        webrtcVideoBroadcasterLockWaitMsValues,
      ),
      maxWebrtcVideoBroadcasterLockWaitMs: _maxDouble(
        webrtcVideoBroadcasterLockWaitMaxMsValues,
      ),
      averageWebrtcVideoBroadcasterSinkDispatchMs: _average(
        webrtcVideoBroadcasterSinkDispatchMsValues,
      ),
      maxWebrtcVideoBroadcasterSinkDispatchMs: _maxDouble(
        webrtcVideoBroadcasterSinkDispatchMaxMsValues,
      ),
      maxWebrtcVideoBroadcasterSingleSinkMs: _maxDouble(
        webrtcVideoBroadcasterMaxSingleSinkMsValues,
      ),
      webrtcVideoBroadcasterSlowSinkId: webrtcVideoBroadcasterSlowSinkId,
      webrtcVideoBroadcasterSlowSinkMs: webrtcVideoBroadcasterSlowSinkMs,
      webrtcVideoBroadcasterSlowSinkLabel: webrtcVideoBroadcasterSlowSinkLabel,
      webrtcVideoBroadcasterSlowestSinkId: webrtcVideoBroadcasterSlowestSinkId,
      webrtcVideoBroadcasterSlowestSinkMs: webrtcVideoBroadcasterSlowestSinkMs,
      webrtcVideoBroadcasterSlowestSinkAverageMs:
          webrtcVideoBroadcasterSlowestSinkAverageMs,
      webrtcVideoBroadcasterSlowestSinkFrames:
          webrtcVideoBroadcasterSlowestSinkFrames,
      webrtcVideoBroadcasterSlowestSinkLabel:
          webrtcVideoBroadcasterSlowestSinkLabel,
      webrtcVideoBroadcasterSinkCount: webrtcVideoBroadcasterSinkCount,
      webrtcVideoBroadcasterMaxSinkCount: webrtcVideoBroadcasterMaxSinkCount,
      webrtcVideoBroadcasterActiveSinks: webrtcVideoBroadcasterActiveSinks,
      webrtcVideoBroadcasterInactiveSinks: webrtcVideoBroadcasterInactiveSinks,
      webrtcVideoBroadcasterRequestedSinks:
          webrtcVideoBroadcasterRequestedSinks,
      webrtcVideoBroadcasterBlackFrameSinks:
          webrtcVideoBroadcasterBlackFrameSinks,
      webrtcVideoBroadcasterRotationAppliedSinks:
          webrtcVideoBroadcasterRotationAppliedSinks,
      webrtcVideoBroadcasterInactiveNativeSinkBypassReported:
          webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
      webrtcVideoBroadcasterInactiveNativeSinksBypassed:
          webrtcVideoBroadcasterInactiveNativeSinksBypassed,
      webrtcVideoBroadcasterInactiveNativeSinksBypassedLast:
          webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
      webrtcVideoBroadcasterInactiveNativeSinksRefreshed:
          webrtcVideoBroadcasterInactiveNativeSinksRefreshed,
      webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast:
          webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast,
      webrtcVideoBroadcasterSinkRoster: webrtcVideoBroadcasterSinkRoster,
      webrtcVideoBroadcasterBlackSinks: webrtcVideoBroadcasterBlackSinks,
      webrtcVideoBroadcasterRotationDiscards:
          webrtcVideoBroadcasterRotationDiscards,
      webrtcVideoBroadcasterUpdateRectCleared:
          webrtcVideoBroadcasterUpdateRectCleared,
      webrtcVideoBroadcasterDiscardedFrames:
          webrtcVideoBroadcasterDiscardedFrames,
      averageWebrtcVsePostToOnFrameMs: _average(webrtcVsePostToOnFrameMsValues),
      maxWebrtcVsePostToOnFrameMs: _maxDouble(
        webrtcVsePostToOnFrameMaxMsValues,
      ),
      averageWebrtcVseOnFrameMs: _average(webrtcVseOnFrameMsValues),
      maxWebrtcVseOnFrameMs: _maxDouble(webrtcVseOnFrameMaxMsValues),
      webrtcVseOnFrameSamples: webrtcVseOnFrameSamples,
      webrtcVseQueueOverloadDrops: webrtcVseQueueOverloadDrops,
      webrtcVseEncoderQueueDrops: webrtcVseEncoderQueueDrops,
      webrtcVseCwndDrops: webrtcVseCwndDrops,
      webrtcVseBadTimestampDrops: webrtcVseBadTimestampDrops,
      averageWebrtcVseMaybeEncodeMs: _average(webrtcVseMaybeEncodeMsValues),
      maxWebrtcVseMaybeEncodeMs: _maxDouble(webrtcVseMaybeEncodeMaxMsValues),
      webrtcVseMaybeEncodeSamples: webrtcVseMaybeEncodeSamples,
      webrtcVsePendingReplacedDrops: webrtcVsePendingReplacedDrops,
      webrtcVseSizeDrops: webrtcVseSizeDrops,
      webrtcVsePausedDrops: webrtcVsePausedDrops,
      webrtcVseMediaOptimizationDrops: webrtcVseMediaOptimizationDrops,
      averageWebrtcVseEncodeFrameMs: _average(webrtcVseEncodeFrameMsValues),
      maxWebrtcVseEncodeFrameMs: _maxDouble(webrtcVseEncodeFrameMaxMsValues),
      averageWebrtcVseMaybePreEncodeMs: _average(
        webrtcVseMaybePreEncodeMsValues,
      ),
      maxWebrtcVseMaybePreEncodeMs: _maxDouble(
        webrtcVseMaybePreEncodeMaxMsValues,
      ),
      averageWebrtcVseMaybeEncodeCallMs: _average(
        webrtcVseMaybeEncodeCallMsValues,
      ),
      maxWebrtcVseMaybeEncodeCallMs: _maxDouble(
        webrtcVseMaybeEncodeCallMaxMsValues,
      ),
      averageWebrtcVseMaybeFrameSizeMs: _average(
        webrtcVseMaybeFrameSizeMsValues,
      ),
      maxWebrtcVseMaybeFrameSizeMs: _maxDouble(
        webrtcVseMaybeFrameSizeMaxMsValues,
      ),
      averageWebrtcVseMaybeParameterUpdateMs: _average(
        webrtcVseMaybeParameterUpdateMsValues,
      ),
      maxWebrtcVseMaybeParameterUpdateMs: _maxDouble(
        webrtcVseMaybeParameterUpdateMaxMsValues,
      ),
      averageWebrtcVseMaybeReconfigureMs: _average(
        webrtcVseMaybeReconfigureMsValues,
      ),
      maxWebrtcVseMaybeReconfigureMs: _maxDouble(
        webrtcVseMaybeReconfigureMaxMsValues,
      ),
      webrtcVsePendingReconfigureSignals: webrtcVsePendingReconfigureSignals,
      webrtcVsePendingReconfigureConfigureEncoder:
          webrtcVsePendingReconfigureConfigureEncoder,
      webrtcVsePendingReconfigureFrameInfoChange:
          webrtcVsePendingReconfigureFrameInfoChange,
      webrtcVsePendingReconfigureSourceRestriction:
          webrtcVsePendingReconfigureSourceRestriction,
      webrtcVsePendingReconfigureUnknown: webrtcVsePendingReconfigureUnknown,
      webrtcVsePendingReconfigureLastReason:
          webrtcVsePendingReconfigureLastReason,
      averageWebrtcVseMaybeRateUpdateMs: _average(
        webrtcVseMaybeRateUpdateMsValues,
      ),
      maxWebrtcVseMaybeRateUpdateMs: _maxDouble(
        webrtcVseMaybeRateUpdateMaxMsValues,
      ),
      averageWebrtcVseMaybeDropChecksMs: _average(
        webrtcVseMaybeDropChecksMsValues,
      ),
      maxWebrtcVseMaybeDropChecksMs: _maxDouble(
        webrtcVseMaybeDropChecksMaxMsValues,
      ),
      averageWebrtcVseEncodePreEncoderMs: _average(
        webrtcVseEncodePreEncoderMsValues,
      ),
      maxWebrtcVseEncodePreEncoderMs: _maxDouble(
        webrtcVseEncodePreEncoderMaxMsValues,
      ),
      averageWebrtcVseEncodeInfoMs: _average(webrtcVseEncodeInfoMsValues),
      maxWebrtcVseEncodeInfoMs: _maxDouble(webrtcVseEncodeInfoMaxMsValues),
      averageWebrtcVseEncodeCropScaleMs: _average(
        webrtcVseEncodeCropScaleMsValues,
      ),
      maxWebrtcVseEncodeCropScaleMs: _maxDouble(
        webrtcVseEncodeCropScaleMaxMsValues,
      ),
      averageWebrtcVseEncodeUpdateRectMs: _average(
        webrtcVseEncodeUpdateRectMsValues,
      ),
      maxWebrtcVseEncodeUpdateRectMs: _maxDouble(
        webrtcVseEncodeUpdateRectMaxMsValues,
      ),
      averageWebrtcVseEncodeResourceMs: _average(
        webrtcVseEncodeResourceMsValues,
      ),
      maxWebrtcVseEncodeResourceMs: _maxDouble(
        webrtcVseEncodeResourceMaxMsValues,
      ),
      averageWebrtcVseEncodeMetadataMs: _average(
        webrtcVseEncodeMetadataMsValues,
      ),
      maxWebrtcVseEncodeMetadataMs: _maxDouble(
        webrtcVseEncodeMetadataMaxMsValues,
      ),
      webrtcVseEncodeFrameSamples: webrtcVseEncodeFrameSamples,
      averageWebrtcVideoEncoderEncodeMs: _average(
        webrtcVideoEncoderEncodeMsValues,
      ),
      maxWebrtcVideoEncoderEncodeMs: _maxDouble(
        webrtcVideoEncoderEncodeMaxMsValues,
      ),
      webrtcVideoEncoderEncodeSamples: webrtcVideoEncoderEncodeSamples,
      webrtcVseEncodeFailures: webrtcVseEncodeFailures,
      webrtcVseEncodeSkippedBeforeEncoder: webrtcVseEncodeSkippedBeforeEncoder,
      webrtcFrameLineageStage: webrtcFrameLineageStage,
      webrtcFrameLineageFrameId: webrtcFrameLineageFrameId,
      webrtcFrameLineageSourceQpc: webrtcFrameLineageSourceQpc,
      webrtcFrameLineageStageQpc: webrtcFrameLineageStageQpc,
      webrtcFrameLineageFrameAgeMs: webrtcFrameLineageFrameAgeMs,
      webrtcFrameLineagePreviousFrameId: webrtcFrameLineagePreviousFrameId,
      averageWebrtcFrameCadencePostDelayMs: _average(
        webrtcFrameCadencePostDelayMsValues,
      ),
      maxWebrtcFrameCadencePostDelayMs: _maxDouble(
        webrtcFrameCadencePostDelayMaxMsValues,
      ),
      averageWebrtcFrameCadenceCallbackMs: _average(
        webrtcFrameCadenceCallbackMsValues,
      ),
      maxWebrtcFrameCadenceCallbackMs: _maxDouble(
        webrtcFrameCadenceCallbackMaxMsValues,
      ),
      averageWebrtcFrameCadenceFrameDurationMs: _average(
        webrtcFrameCadenceFrameDurationMsValues,
      ),
      maxWebrtcFrameCadenceFrameDurationMs: _maxDouble(
        webrtcFrameCadenceFrameDurationMaxMsValues,
      ),
      webrtcFrameCadenceSends: webrtcFrameCadenceSends,
      webrtcFrameCadenceRepeatedSends: webrtcFrameCadenceRepeatedSends,
      webrtcFrameCadencePostDelaySamples: webrtcFrameCadencePostDelaySamples,
      webrtcFrameCadenceOverFrameDurationSends:
          webrtcFrameCadenceOverFrameDurationSends,
      webrtcFrameCadenceOverloadTriggerSends:
          webrtcFrameCadenceOverloadTriggerSends,
      webrtcFrameCadenceOverloadActiveSends:
          webrtcFrameCadenceOverloadActiveSends,
      webrtcFrameCadenceOverloadDecaySends:
          webrtcFrameCadenceOverloadDecaySends,
      webrtcFrameCadenceOverloadEnabledSeen:
          webrtcFrameCadenceOverloadEnabledSeen,
      webrtcFrameCadenceOverloadDisabledSeen:
          webrtcFrameCadenceOverloadDisabledSeen,
      webrtcFrameCadenceMaxScheduledForProcessing:
          webrtcFrameCadenceMaxScheduledForProcessing,
      webrtcFrameCadenceLastScheduledForProcessing:
          webrtcFrameCadenceLastScheduledForProcessing,
      webrtcFrameCadenceMaxQueueOverloadBefore:
          webrtcFrameCadenceMaxQueueOverloadBefore,
      webrtcFrameCadenceMaxQueueOverloadAfter:
          webrtcFrameCadenceMaxQueueOverloadAfter,
      webrtcFrameCadenceLastQueueOverloadBefore:
          webrtcFrameCadenceLastQueueOverloadBefore,
      webrtcFrameCadenceLastQueueOverloadAfter:
          webrtcFrameCadenceLastQueueOverloadAfter,
      averageWebrtcFrameCadenceQueuePostDelayMs: _average(
        webrtcFrameCadenceQueuePostDelayMsValues,
      ),
      maxWebrtcFrameCadenceQueuePostDelayMs: _maxDouble(
        webrtcFrameCadenceQueuePostDelayMaxMsValues,
      ),
      webrtcFrameCadenceQueueFrames: webrtcFrameCadenceQueueFrames,
      webrtcFrameCadenceQueueOverloadFrames:
          webrtcFrameCadenceQueueOverloadFrames,
      webrtcFrameCadenceQueuePostDelaySamples:
          webrtcFrameCadenceQueuePostDelaySamples,
      webrtcFrameCadenceQueueMaxScheduledForProcessing:
          webrtcFrameCadenceQueueMaxScheduledForProcessing,
      webrtcFrameCadenceQueueLastScheduledForProcessing:
          webrtcFrameCadenceQueueLastScheduledForProcessing,
      webrtcFrameCadenceQueuePassthroughFrames:
          webrtcFrameCadenceQueuePassthroughFrames,
      webrtcFrameCadenceQueueZeroHertzFrames:
          webrtcFrameCadenceQueueZeroHertzFrames,
      webrtcFrameCadenceQueueVsyncFrames: webrtcFrameCadenceQueueVsyncFrames,
      webrtcFrameCadenceQueueUnknownFrames:
          webrtcFrameCadenceQueueUnknownFrames,
      webrtcFrameCadenceQueueCoalesceEnabledSeen:
          webrtcFrameCadenceQueueCoalesceEnabledSeen,
      webrtcFrameCadenceQueueCoalesceDisabledSeen:
          webrtcFrameCadenceQueueCoalesceDisabledSeen,
      webrtcFrameCadenceQueueCoalesceThreshold:
          webrtcFrameCadenceQueueCoalesceThreshold,
      webrtcFrameCadenceQueueCoalescedDrops:
          webrtcFrameCadenceQueueCoalescedDrops,
      webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen:
          webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen,
      webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen:
          webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen,
      webrtcFrameCadenceQueuePrepostCoalescedDrops:
          webrtcFrameCadenceQueuePrepostCoalescedDrops,
      webrtcFrameCadenceQueuePrepostProcessingDrops:
          webrtcFrameCadenceQueuePrepostProcessingDrops,
      webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing:
          webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing,
      webrtcFrameCadenceQueueLastMode: webrtcFrameCadenceQueueLastMode,
      webrtcFrameCadenceQueueMailboxEnabledSeen:
          webrtcFrameCadenceQueueMailboxEnabledSeen,
      webrtcFrameCadenceQueueMailboxFrames:
          webrtcFrameCadenceQueueMailboxFrames,
      webrtcFrameCadenceQueueMailboxProcessedFrames:
          webrtcFrameCadenceQueueMailboxProcessedFrames,
      webrtcFrameCadenceQueueMailboxReplacements:
          webrtcFrameCadenceQueueMailboxReplacements,
      webrtcFrameCadenceQueueMailboxStaleDrops:
          webrtcFrameCadenceQueueMailboxStaleDrops,
      webrtcFrameCadenceQueueMailboxProcessingActive:
          webrtcFrameCadenceQueueMailboxProcessingActive,
      webrtcFrameCadenceQueueMailboxProcessingActiveSeen:
          webrtcFrameCadenceQueueMailboxProcessingActiveSeen,
      webrtcFrameCadenceQueueMailboxPendingDepthMax:
          webrtcFrameCadenceQueueMailboxPendingDepthMax,
      webrtcFrameCadenceQueueMailboxPendingDepthLast:
          webrtcFrameCadenceQueueMailboxPendingDepthLast,
      averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs: _average(
        webrtcFrameCadenceQueueMailboxPendingFrameAgeMsValues,
      ),
      maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs: _maxDouble(
        webrtcFrameCadenceQueueMailboxPendingFrameAgeMaxMsValues,
      ),
      webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples:
          webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples,
      averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs: _average(
        webrtcFrameCadenceQueueMailboxProcessingFrameAgeMsValues,
      ),
      maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs: _maxDouble(
        webrtcFrameCadenceQueueMailboxProcessingFrameAgeMaxMsValues,
      ),
      webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples:
          webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples,
      webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses:
          webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses,
      averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs: _average(
        webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMsValues,
      ),
      maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs: _maxDouble(
        webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMaxMsValues,
      ),
      webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples:
          webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples,
      averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs: _average(
        webrtcFrameCadenceQueueMailboxProcessingStartToVseMsValues,
      ),
      maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs: _maxDouble(
        webrtcFrameCadenceQueueMailboxProcessingStartToVseMaxMsValues,
      ),
      webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples:
          webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples,
      averageWebrtcFrameCadenceQueueMailboxVseCallMs: _average(
        webrtcFrameCadenceQueueMailboxVseCallMsValues,
      ),
      maxWebrtcFrameCadenceQueueMailboxVseCallMs: _maxDouble(
        webrtcFrameCadenceQueueMailboxVseCallMaxMsValues,
      ),
      webrtcFrameCadenceQueueMailboxVseCallSamples:
          webrtcFrameCadenceQueueMailboxVseCallSamples,
      webrtcFrameCadenceQueueMailboxStaleDropThresholdMs:
          webrtcFrameCadenceQueueMailboxStaleDropThresholdMs,
    );
  }

  final String? captureBackendMode;
  final String? observedCapturer;
  final int? observedCapturerId;
  final String? dirtyRegionMode;
  final String? windowGdiCaptureMode;
  final String? sourceType;
  final int? nativeSourceWidth;
  final int? nativeSourceHeight;
  final int? requestedMaxWidth;
  final int? requestedMaxHeight;
  final int? nativeWindowRectWidth;
  final int? nativeWindowRectHeight;
  final int? contentWidth;
  final int? contentHeight;
  final int? preEncodeWidth;
  final int? preEncodeHeight;
  final String? canvas;
  final bool? cropRegion;
  final double? averageNativeFps;
  final double? averageSubmittedFps;
  final double? targetNativeFps;
  final double? averageCaptureCallMs;
  final double? maxCaptureCallMs;
  final double? averageSourceCaptureMs;
  final double? maxSourceCaptureMs;
  final int sourceCaptureSampleCount;
  final int wgcCaptureCalls;
  final int wgcCaptureSuccessCount;
  final int wgcSourceNotCapturableCount;
  final int wgcEnsureFrameCalls;
  final int wgcEnsureSleepCount;
  final int wgcProcessFrameCalls;
  final int wgcProcessFrameSuccessCount;
  final int wgcFramePoolEmptyCount;
  final int wgcFramePoolReuseCount;
  final int wgcCaptureFrameNullCount;
  final int wgcMappedTextureCreateCount;
  final int wgcResizeCount;
  final int wgcFramePoolRecreateCount;
  final double? averageWgcGetFrameMs;
  final double? maxWgcGetFrameMs;
  final double? averageWgcEnsureFrameMs;
  final double? maxWgcEnsureFrameMs;
  final double? averageWgcProcessFrameMs;
  final double? maxWgcProcessFrameMs;
  final double? averageWgcTryGetFrameMs;
  final double? maxWgcTryGetFrameMs;
  final double? averageWgcSurfaceMs;
  final double? maxWgcSurfaceMs;
  final double? averageWgcTextureMs;
  final double? maxWgcTextureMs;
  final double? averageWgcContentSizeMs;
  final double? maxWgcContentSizeMs;
  final double? averageWgcCopyTextureMs;
  final double? maxWgcCopyTextureMs;
  final double? averageWgcMapTextureMs;
  final double? maxWgcMapTextureMs;
  final double? averageWgcCopyRowsMs;
  final double? maxWgcCopyRowsMs;
  final double? averageWgcMonitorScaleMs;
  final double? maxWgcMonitorScaleMs;
  final double? averageWgcZeroHertzMs;
  final double? maxWgcZeroHertzMs;
  final int gdiCaptureCalls;
  final int gdiCaptureSuccessCount;
  final int gdiTemporaryErrorCount;
  final int gdiPermanentErrorCount;
  final int gdiHiddenOrMinimizedCount;
  final int gdiRectFailCount;
  final int gdiDcFailCount;
  final int gdiFrameCreateFailCount;
  final int gdiPrintFullCallCount;
  final int gdiPrintFullSuccessCount;
  final int gdiPrintFallbackCallCount;
  final int gdiPrintFallbackSuccessCount;
  final int gdiBitBltCallCount;
  final int gdiBitBltSuccessCount;
  final int gdiFinalPrintFullCount;
  final int gdiFinalPrintFallbackCount;
  final int gdiFinalBitBltCount;
  final int gdiFinalNoneCount;
  final int gdiBlackFrameCount;
  final int gdiLowVarianceFrameCount;
  final int gdiOwnedWindowFrameCount;
  final int gdiOwnedWindowCaptureCallCount;
  final int gdiOwnedWindowCaptureSuccessCount;
  final int? gdiOriginalWidth;
  final int? gdiOriginalHeight;
  final int? gdiCroppedWidth;
  final int? gdiCroppedHeight;
  final int? gdiFrameWidth;
  final int? gdiFrameHeight;
  final double? averageGdiTotalMs;
  final double? maxGdiTotalMs;
  final double? averageGdiRectMs;
  final double? maxGdiRectMs;
  final double? averageGdiVisibilityMs;
  final double? maxGdiVisibilityMs;
  final double? averageGdiGetDcMs;
  final double? maxGdiGetDcMs;
  final double? averageGdiGetDcSizeMs;
  final double? maxGdiGetDcSizeMs;
  final double? averageGdiCreateFrameMs;
  final double? maxGdiCreateFrameMs;
  final double? averageGdiMemDcMs;
  final double? maxGdiMemDcMs;
  final double? averageGdiPrintFullMs;
  final double? maxGdiPrintFullMs;
  final double? averageGdiPrintFallbackMs;
  final double? maxGdiPrintFallbackMs;
  final double? averageGdiBitBltMs;
  final double? maxGdiBitBltMs;
  final double? averageGdiCleanupMs;
  final double? maxGdiCleanupMs;
  final double? averageGdiCropMs;
  final double? maxGdiCropMs;
  final double? averageGdiOwnedEnumMs;
  final double? maxGdiOwnedEnumMs;
  final double? averageGdiOwnedCaptureMs;
  final double? maxGdiOwnedCaptureMs;
  final double? averageGdiOwnedCompositeMs;
  final double? maxGdiOwnedCompositeMs;
  final double? averageCallbackEntryDelayMs;
  final double? maxCallbackEntryDelayMs;
  final double? averageCaptureResultCallbackMs;
  final double? maxCaptureResultCallbackMs;
  final double? averageCaptureAcquireWaitMs;
  final double? maxCaptureAcquireWaitMs;
  final double? averagePostCallbackWaitMs;
  final double? maxPostCallbackWaitMs;
  final double? averageUnaccountedWaitMs;
  final double? maxUnaccountedWaitMs;
  final int captureResultCallbackCount;
  final double? maxFrameIntervalMs;
  final double? p95FrameIntervalMs;
  final int captureWaitTimeoutCount;
  final int capturePermanentErrorCount;
  final int duplicatedFrameCount;
  final int staleFrameReuseCount;
  final double? averageFrameConvertMs;
  final double? averageFrameScaleMs;
  final double? averageFrameOnFrameMs;
  final double? averageFrameCallbackMs;
  final double? maxFrameCallbackMs;
  final int updatedRegionEmptyCount;
  final int updatedRegionNonEmptyCount;
  final int updatedRegionRectCount;
  final int updatedRegionMaxRectCount;
  final double? averageUpdatedRegionAreaRatio;
  final double? maxUpdatedRegionAreaRatio;
  final double? averageUpdatedRegionAnalysisMs;
  final double? maxUpdatedRegionAnalysisMs;
  final int updatedRegionFullFrameCount;
  final int updatedRegionTinyFrameCount;
  final bool? latestFramePacerEnabled;
  final double? averagePacerSubmittedFps;
  final double? averagePacerUniqueFps;
  final double? p95PacerIntervalMs;
  final double? maxPacerIntervalMs;
  final double? averagePacerFrameAgeMs;
  final double? maxPacerFrameAgeMs;
  final double? averagePacerOnFrameMs;
  final double? maxPacerOnFrameMs;
  final int pacerDuplicateSubmitCount;
  final int pacerOverwrittenFrameCount;
  final int pacerSkippedTickCount;
  final int? gameCaptureSourceWidth;
  final int? gameCaptureSourceHeight;
  final int? gameCaptureOutputWidth;
  final int? gameCaptureOutputHeight;
  final int? gameCaptureFormat;
  final int? gameCaptureBackendContractVersion;
  final String? gameCaptureSourceMode;
  final String? gameCaptureSourceApi;
  final int? gameCaptureSourceApiId;
  final String? gameCaptureSourceFormat;
  final int? gameCaptureSourceFormatId;
  final String? gameCaptureColorSpace;
  final String? gameCaptureSyncKind;
  final String? gameCaptureReadyState;
  final String? gameCaptureFailureReason;
  final bool? gameCaptureNativeAdmissionStrictDeadlineEnabled;
  final int gameCaptureNativeAdmissionSourceDrivenFreshDueFrames;
  final int gameCaptureNativeAdmissionSourceQpcDueFrames;
  final int gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames;
  final int gameCaptureNativeAdmissionDeadlineDueFrames;
  final double? averageGameCaptureNativeAdmissionDeadlineLatenessMs;
  final double? maxGameCaptureNativeAdmissionDeadlineLatenessMs;
  final int gameCaptureNativeAdmissionDeadlineLatenessSamples;
  final int gameCaptureNativeAdmissionDeadlineOver1xFrames;
  final int gameCaptureNativeAdmissionDeadlineOver2xFrames;
  final int gameCaptureNativeAdmissionDeadlineOver3xFrames;
  final int gameCaptureNativeAdmissionNoSourceOnDeadlineFrames;
  final int gameCaptureNativeAdmissionRepeatedOnDeadlineFrames;
  final int gameCaptureNativeAdmissionSubmitOnDeadlineFrames;
  final int gameCaptureNativeAdmissionSubmitOnEarlySourceFrames;
  final int gameCaptureNativeNv12PendingOnDeadlineFrames;
  final int gameCaptureNativeNv12NoPendingOnDeadlineFrames;
  final int gameCaptureNativeNv12ReadyOnDeadlineFrames;
  final int gameCaptureNativeNv12NoReadyOnDeadlineFrames;
  final String? gameCaptureConsumerAdapterLuid;
  final int? gameCaptureConsumerAdapterVendorId;
  final int? gameCaptureConsumerAdapterDeviceId;
  final String? gameCaptureSourceAdapterLuid;
  final String? gameCaptureCrossAdapterSuspected;
  final double? averageGameCaptureFps;
  final int gameCaptureSubmittedFrames;
  final int gameCaptureRepeatedFrames;
  final int gameCaptureDuplicateSkippedFrames;
  final int gameCaptureDeliveryQueuedFrames;
  final int gameCaptureDeliverySubmittedFrames;
  final int gameCaptureDeliveryOverwrittenFrames;
  final int gameCaptureDeliveryPacerResyncs;
  final int gameCaptureDeliveryPacerLagMaxMs;
  final int gameCaptureDeliveryRepeatNoQueuedFrames;
  final int gameCaptureDeliverySkipNoQueuedFrames;
  final int gameCaptureDeliveryFreshWakeAfterSkipFrames;
  final int gameCaptureDeliveryFreshImmediateFrames;
  final String? gameCaptureDeliveryRepeatPolicy;
  final int? gameCaptureDeliveryQueueDepth;
  final double? averageGameCaptureDeliveryRepeatSourceAgeMs;
  final double? maxGameCaptureDeliveryRepeatSourceAgeMs;
  final int gameCaptureDeliveryRepeatSourceAgeSamples;
  final double? averageGameCaptureDeliveryOnFrameMs;
  final double? maxGameCaptureDeliveryOnFrameMs;
  final double? averageGameCaptureDeliverySubmitPrepMs;
  final double? maxGameCaptureDeliverySubmitPrepMs;
  final int gameCaptureDeliverySubmitPrepSamples;
  final double? averageGameCaptureDeliveryOnFrameCallMs;
  final double? maxGameCaptureDeliveryOnFrameCallMs;
  final int gameCaptureDeliveryOnFrameCallSamples;
  final double? averageGameCaptureDeliveryPostOnFrameMs;
  final double? maxGameCaptureDeliveryPostOnFrameMs;
  final int gameCaptureDeliveryPostOnFrameSamples;
  final double? averageGameCaptureNativeBufferReleaseMs;
  final double? maxGameCaptureNativeBufferReleaseMs;
  final int gameCaptureNativeBufferReleaseSamples;
  final double? averageGameCaptureReadyToQueueMs;
  final double? maxGameCaptureReadyToQueueMs;
  final int gameCaptureReadyToQueueSamples;
  final double? averageGameCaptureDeliveryQueueWaitMs;
  final double? maxGameCaptureDeliveryQueueWaitMs;
  final int gameCaptureDeliveryQueueWaitSamples;
  final double? averageGameCaptureDeliveryOverwriteAgeMs;
  final double? maxGameCaptureDeliveryOverwriteAgeMs;
  final int gameCaptureDeliveryOverwriteAgeSamples;
  final int gameCaptureDeliveryOverwrittenFreshFrames;
  final double? averageGameCaptureReadyToSubmitMs;
  final double? maxGameCaptureReadyToSubmitMs;
  final int gameCaptureReadyToSubmitSamples;
  final double? averageGameCaptureSourceToSubmitMs;
  final double? maxGameCaptureSourceToSubmitMs;
  final int gameCaptureSourceToSubmitSamples;
  final double? averageGameCaptureSourceToReadbackReadyMs;
  final double? maxGameCaptureSourceToReadbackReadyMs;
  final int gameCaptureSourceToReadbackReadySamples;
  final double? averageGameCaptureReadbackQueueToMapMs;
  final double? maxGameCaptureReadbackQueueToMapMs;
  final int gameCaptureReadbackQueueToMapSamples;
  final double? averageGameCaptureMapToI420Ms;
  final double? maxGameCaptureMapToI420Ms;
  final int gameCaptureMapToI420Samples;
  final double? averageGameCaptureSourceToI420ReadyMs;
  final double? maxGameCaptureSourceToI420ReadyMs;
  final int gameCaptureSourceToI420ReadySamples;
  final double? averageGameCaptureSourceToQueueMs;
  final double? maxGameCaptureSourceToQueueMs;
  final int gameCaptureSourceToQueueSamples;
  final double? averageGameCaptureSourceDuplicateSkipAgeMs;
  final double? maxGameCaptureSourceDuplicateSkipAgeMs;
  final int gameCaptureSourceDuplicateSkipAgeSamples;
  final int gameCaptureCopiedFrames;
  final int gameCaptureDroppedFrames;
  final int gameCaptureOverwrittenFrames;
  final int gameCaptureGpuScaledFrames;
  final int gameCaptureGpuScaleFailures;
  final int gameCaptureCpuFallbackFrames;
  final int gameCaptureNativeNv12SubmittedFrames;
  final int gameCaptureNativeNv12QueuedFrames;
  final int gameCaptureNativeNv12ReadyFrames;
  final int gameCaptureNativeNv12NotReadyPolls;
  final String? gameCaptureNativeNv12ReadyPolicy;
  final bool? gameCaptureNativeNv12FenceAvailable;
  final int? gameCaptureNativeNv12PendingPollMs;
  final int? gameCaptureNativeNv12MaxPendingSlots;
  final int? gameCaptureNativeNv12ReadyDrainDepth;
  final String? gameCaptureNativeNv12FrameOwnership;
  final int? gameCaptureNativeNv12WarmupI420Frames;
  final bool? gameCaptureNativeNv12SingleInFlightEnabled;
  final bool? gameCaptureNativeNv12GpuQueueBackoffEnabled;
  final int? gameCaptureNativeNv12GpuQueueBackoffThresholdFrames;
  final int? gameCaptureNativeNv12GpuQueueBackoffDurationFrames;
  final int gameCaptureNativeNv12FenceSignaledFrames;
  final int gameCaptureNativeNv12FenceReadyFrames;
  final int gameCaptureNativeNv12FenceSignalFailures;
  final int gameCaptureNativeNv12OwnedCopies;
  final double? averageGameCaptureNativeNv12OwnedCopyMs;
  final double? maxGameCaptureNativeNv12OwnedCopyMs;
  final int gameCaptureNativeNv12OwnedCopySamples;
  final int gameCaptureNativeNv12OverwrittenFrames;
  final double? averageGameCaptureNativeNv12OverwriteAgeMs;
  final double? maxGameCaptureNativeNv12OverwriteAgeMs;
  final int gameCaptureNativeNv12OverwriteAgeSamples;
  final int gameCaptureNativeNv12OverwrittenFreshFrames;
  final int gameCaptureNativeNv12ReadyDroppedFrames;
  final double? averageGameCaptureNativeNv12ReadyDropAgeMs;
  final double? maxGameCaptureNativeNv12ReadyDropAgeMs;
  final int gameCaptureNativeNv12ReadyDropAgeSamples;
  final int gameCaptureNativeNv12ReadyDroppedFreshFrames;
  final bool? gameCaptureNativeNv12LateReadyDropEnabled;
  final int? gameCaptureNativeNv12LateReadyDropThresholdMs;
  final int gameCaptureNativeNv12LateReadyDroppedFrames;
  final double? averageGameCaptureNativeNv12LateReadyDropAgeMs;
  final double? maxGameCaptureNativeNv12LateReadyDropAgeMs;
  final int gameCaptureNativeNv12LateReadyDropAgeSamples;
  final int gameCaptureNativeNv12LateReadyDroppedFreshFrames;
  final double? averageGameCaptureNativeNv12LateReadyDropBltToReadyMs;
  final double? maxGameCaptureNativeNv12LateReadyDropBltToReadyMs;
  final int gameCaptureNativeNv12LateReadyDropBltToReadySamples;
  final int gameCaptureNativeNv12Failures;
  final double? averageGameCaptureNativeNv12ConvertMs;
  final double? maxGameCaptureNativeNv12ConvertMs;
  final int gameCaptureNativeNv12ConvertSamples;
  final double? averageGameCaptureNativeNv12BgraScaleDrawMs;
  final double? maxGameCaptureNativeNv12BgraScaleDrawMs;
  final int gameCaptureNativeNv12BgraScaleDrawSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltSubmitMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltSubmitMs;
  final int gameCaptureNativeNv12VideoProcessorBltSubmitSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs;
  final int gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltToReadyMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltToReadyMs;
  final int gameCaptureNativeNv12VideoProcessorBltToReadySamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs;
  final int gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs;
  final int gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples;
  final double?
  averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs;
  final double?
  maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs;
  final int gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples;
  final int gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures;
  final int gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady;
  final int gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint;
  final int gameCaptureNativeNv12ReadyObservedImmediateFrames;
  final int gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames;
  final int gameCaptureNativeNv12ReadyObservedFenceEventFrames;
  final int gameCaptureNativeNv12ReadyObservedSourceEventFrames;
  final int gameCaptureNativeNv12ReadyObservedWaitOtherFrames;
  final int gameCaptureNativeNv12ReadyObservedLoopIdleFrames;
  final int gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames;
  final int gameCaptureNativeNv12ReadyObservedPreSubmitFrames;
  final int gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames;
  final int gameCaptureNativeNv12ReadyObservedUnknownFrames;
  final int gameCaptureNativeNv12BltToReadyOver1xFrames;
  final int gameCaptureNativeNv12BltToReadyOver2xFrames;
  final int gameCaptureNativeNv12BltToReadyOver3xFrames;
  final double? averageGameCaptureNativeNv12BufferCreateMs;
  final double? maxGameCaptureNativeNv12BufferCreateMs;
  final int gameCaptureNativeNv12BufferCreateSamples;
  final double? averageGameCaptureNativeNv12FrameReadyToQueueMs;
  final double? maxGameCaptureNativeNv12FrameReadyToQueueMs;
  final int gameCaptureNativeNv12FrameReadyToQueueSamples;
  final double? averageGameCaptureNativeNv12ConversionStartAgeMs;
  final double? maxGameCaptureNativeNv12ConversionStartAgeMs;
  final int gameCaptureNativeNv12ConversionStartAgeSamples;
  final int gameCaptureNativeNv12SingleInFlightDeferredFrames;
  final int gameCaptureNativeNv12SingleInFlightDeferredFreshFrames;
  final int gameCaptureNativeNv12SingleInFlightPendingMax;
  final double? averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs;
  final double? maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs;
  final int gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples;
  final int gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames;
  final int gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames;
  final int gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames;
  final double? averageGameCaptureNativeNv12GpuQueueBackoffMs;
  final double? maxGameCaptureNativeNv12GpuQueueBackoffMs;
  final int gameCaptureNativeNv12GpuQueueBackoffSamples;
  final double? averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs;
  final double? maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs;
  final int gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples;
  final double?
  averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs;
  final double? maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs;
  final int gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples;
  final bool? gameCaptureNativeNv12AdmissionMailboxEnabled;
  final bool? gameCaptureNativeNv12AdmissionMailboxPendingActive;
  final int gameCaptureNativeNv12AdmissionMailboxStoredFrames;
  final int gameCaptureNativeNv12AdmissionMailboxReplacedFrames;
  final int gameCaptureNativeNv12AdmissionMailboxSubmittedFrames;
  final int gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames;
  final double? averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs;
  final double? maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs;
  final int gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples;
  final double? averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs;
  final double? maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs;
  final int gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples;
  final int gameCaptureNativeNv12StaleBeforeQueueFrames;
  final String? gameCaptureNativeNv12HandoffDisabledReason;
  final bool? gameCaptureNativeNv12OnFrameBackpressureEnabled;
  final int? gameCaptureNativeNv12OnFrameBackpressureThresholdMs;
  final int? gameCaptureNativeNv12OnFrameBackpressureFrameLimit;
  final int gameCaptureNativeNv12OnFrameBackpressureFrames;
  final int gameCaptureNativeNv12OnFrameBackpressureStreak;
  final double? gameCaptureNativeNv12OnFrameBackpressureMaxMs;
  final bool? gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure;
  final int gameCaptureReadbackQueuedFrames;
  final int gameCaptureReadbackReadyFrames;
  final int gameCaptureReadbackNotReadyFrames;
  final int gameCaptureReadbackOverwrittenFrames;
  final int gameCaptureReadbackStaleDroppedFrames;
  final int gameCaptureReadbackLatencyDroppedFrames;
  final int gameCaptureReadbackMapAttempts;
  final int gameCaptureSourceFrameIndex;
  final int gameCaptureLastSubmittedSourceFrameIndex;
  final int gameCaptureSourceFrameRegressions;
  final int gameCaptureSourceFrameDuplicates;
  final int gameCaptureSourceFrameGaps;
  final int gameCaptureSharedSlotMismatches;
  final String? gameCaptureTimestampMode;
  final int gameCaptureTimestampSourceQpcFrames;
  final int gameCaptureTimestampPacedFallbackFrames;
  final int gameCaptureTimestampRepeatedFrames;
  final double? averageGameCaptureTimestampDeltaMs;
  final double? maxGameCaptureTimestampDeltaMs;
  final int gameCaptureTimestampSamples;
  final int gameCaptureTimestampAdjustments;
  final double? averageGameCaptureDeliveryWallDeltaMs;
  final double? maxGameCaptureDeliveryWallDeltaMs;
  final double? minGameCaptureDeliveryWallDeltaMs;
  final int gameCaptureDeliveryWallSamples;
  final int gameCaptureDeliveryWallOver2xFrames;
  final int gameCaptureDeliveryWallOver3xFrames;
  final int gameCaptureDeliveryWallUnderHalfFrames;
  final double? averageGameCaptureSourceQpcDeltaMs;
  final double? maxGameCaptureSourceQpcDeltaMs;
  final int gameCaptureSourceQpcSamples;
  final int gameCaptureSourceQpcRegressions;
  final int gameCaptureSourceQpcOver2xFrames;
  final int gameCaptureSourceQpcOver3xFrames;
  final int gameCaptureSourceQpcUnderHalfFrames;
  final int gameCaptureSourceLatestObservedFrames;
  final int gameCaptureSourceLatestFrameGaps;
  final int gameCaptureSourceLatestFrameRegressions;
  final double? averageGameCaptureSourceLatestQpcDeltaMs;
  final double? maxGameCaptureSourceLatestQpcDeltaMs;
  final int gameCaptureSourceLatestQpcSamples;
  final int gameCaptureSourceLatestQpcRegressions;
  final int gameCaptureSourceLatestQpcOver2xFrames;
  final int gameCaptureSourceLatestQpcOver3xFrames;
  final int gameCaptureSourceLatestQpcUnderHalfFrames;
  final double? averageGameCaptureSourceLatestObservationDeltaMs;
  final double? maxGameCaptureSourceLatestObservationDeltaMs;
  final int gameCaptureSourceLatestObservationSamples;
  final int gameCaptureSourceLatestObservationOver2xFrames;
  final int gameCaptureSourceLatestObservationOver3xFrames;
  final double? averageGameCaptureSourceLatestEventAgeMs;
  final double? maxGameCaptureSourceLatestEventAgeMs;
  final int gameCaptureSourceLatestEventAgeSamples;
  final int gameCaptureSourceLatestEventAgeOver1xFrames;
  final int gameCaptureSourceLatestEventAgeOver2xFrames;
  final int gameCaptureSourceLatestEventAgeOver3xFrames;
  final double? averageGameCaptureSourcePublishObservationAgeMs;
  final double? maxGameCaptureSourcePublishObservationAgeMs;
  final int gameCaptureSourcePublishObservationAgeSamples;
  final int gameCaptureSourcePublishObservationAgeOver1xFrames;
  final int gameCaptureSourcePublishObservationAgeOver2xFrames;
  final int gameCaptureSourcePublishObservationAgeOver3xFrames;
  final double? averageGameCaptureProducerPresentGapMs;
  final double? maxGameCaptureProducerPresentGapMs;
  final int gameCaptureProducerPresentGapSamples;
  final double? averageGameCaptureProducerCaptureGapMs;
  final double? maxGameCaptureProducerCaptureGapMs;
  final int gameCaptureProducerCaptureGapSamples;
  final double? averageGameCaptureProducerPresentToPublishMs;
  final double? maxGameCaptureProducerPresentToPublishMs;
  final int gameCaptureProducerPresentToPublishSamples;
  final double? averageGameCaptureProducerCopyMs;
  final double? maxGameCaptureProducerCopyMs;
  final int gameCaptureProducerCopySamples;
  final double? averageGameCaptureProducerResolveMs;
  final double? maxGameCaptureProducerResolveMs;
  final int gameCaptureProducerResolveSamples;
  final int gameCaptureProducerThrottledFrames;
  final double? averageGameCaptureCopyMs;
  final double? averageGameCaptureMapMs;
  final double? averageGameCaptureConvertMs;
  final double? averageGameCaptureGpuScaleMs;
  final double? averageGameCaptureReadbackLatencyMs;
  final double? averageGameCaptureReadbackLatencyFrames;
  final int gameCaptureMaxReadbackLatencyFrames;
  final int gameCaptureMapFailures;
  final int gameCaptureConvertFailures;
  final int gameCaptureProofFrames;
  final int gameCaptureVisibleProofFrames;
  final bool? gameCaptureProofVisible;
  final String? gameCaptureProofPath;
  final int? gameCaptureProofMinLuma;
  final int? gameCaptureProofMaxLuma;
  final int? gameCaptureProofNonzeroSamples;
  final int? gameCaptureProofSamples;
  final int gameCaptureI420ProofFrames;
  final int gameCaptureVisibleI420ProofFrames;
  final int gameCaptureInitialBlackSkippedFrames;
  final bool? gameCaptureVisibleSourceSeen;
  final bool? gameCaptureI420ProofVisible;
  final String? gameCaptureI420ProofPath;
  final int? gameCaptureI420ProofMinLuma;
  final int? gameCaptureI420ProofMaxLuma;
  final int? gameCaptureI420ProofNonzeroSamples;
  final int? gameCaptureI420ProofSamples;
  final String? gameCaptureVisualFreshnessSampleMode;
  final int gameCaptureVisualFreshnessSampleFrames;
  final int gameCaptureVisualFreshnessUniqueFrames;
  final double? averageGameCaptureVisualFreshnessUniqueFps;
  final double? gameCaptureVisualFreshnessLongestStaleMs;
  final int gameCaptureVisualFreshnessLongestStaleFrames;
  final int gameCaptureVisualFreshnessLowChangeFrames;
  final bool? gameCaptureVisualFreshnessArtifactSet;
  final double? averageEncoderTotalMs;
  final double? maxEncoderTotalMs;
  final int encoderSlowFrameCount;
  final int encoderSampleCount;
  final String? encoderRateControlMode;
  final int? encoderTargetBitrateBps;
  final List<String> encoderInputPaths;
  final int encoderNativeInputFrames;
  final int encoderCpuI420InputFrames;
  final int encoderNativeSampleFailures;
  final int encoderNativeSuspendedFrames;
  final int encoderNativeReadyFenceFrames;
  final int encoderNativeReadyFenceTimeoutFrames;
  final double? averageEncoderNativeReadyFenceWaitMs;
  final double? maxEncoderNativeReadyFenceWaitMs;
  final int encoderNativeReadyFenceWaitSamples;
  final String? encoderNativeSourceMode;
  final int? encoderNativeSourceFormat;
  final int encoderNativeSourceFrameIndex;
  final double? averageEncoderNativeSourceAgeMs;
  final double? maxEncoderNativeSourceAgeMs;
  final int encoderNativeSourceAgeSamples;
  final double? averageEncoderNativeSourceAgeAtCreateMs;
  final double? maxEncoderNativeSourceAgeAtCreateMs;
  final double? averageEncoderNativeBufferAgeMs;
  final double? maxEncoderNativeBufferAgeMs;
  final int encoderNativeBufferAgeSamples;
  final double? averageEncoderNativeSampleLifetimeMs;
  final double? maxEncoderNativeSampleLifetimeMs;
  final int encoderNativeSampleLifetimeSamples;
  final String? encoderNativeAdapterLuid;
  final int? encoderNativeAdapterVendorId;
  final int? encoderNativeAdapterDeviceId;
  final double? averageEncoderProcessInputMs;
  final double? maxEncoderProcessInputMs;
  final int encoderProcessInputSamples;
  final double? averageEncoderProcessOutputMs;
  final double? maxEncoderProcessOutputMs;
  final int encoderProcessOutputSamples;
  final double? averageEncoderEncodedCallbackMs;
  final double? maxEncoderEncodedCallbackMs;
  final int encoderEncodedCallbackSamples;
  final double? averageEncoderEncodedCallbackQueueWaitMs;
  final double? maxEncoderEncodedCallbackQueueWaitMs;
  final int encoderEncodedCallbackQueueWaitSamples;
  final double? averageEncoderEncodedCallbackEnqueueMs;
  final double? maxEncoderEncodedCallbackEnqueueMs;
  final int encoderEncodedCallbackEnqueueSamples;
  final int encoderEncodedCallbackAsyncFrames;
  final int encoderMaxEncodedCallbackQueueDepth;
  final int encoderMaxEncodedCallbackDrops;
  final int encoderMaxEncodedCallbackOutputs;
  final List<String> encoderStages;
  final int encoderOutputFrames;
  final int encoderOutputBytes;
  final int encoderMaxQueueDepth;
  final int encoderMaxRetainedSamples;
  final int encoderMaxEncodedOutputs;
  final double? averageWebrtcSourceOnFrameMs;
  final double? maxWebrtcSourceOnFrameMs;
  final int webrtcSourceOnFrameSamples;
  final double? averageWebrtcSourceAdaptMs;
  final double? maxWebrtcSourceAdaptMs;
  final double? averageWebrtcSourceScaleMs;
  final double? maxWebrtcSourceScaleMs;
  final double? averageWebrtcSourceBroadcastMs;
  final double? maxWebrtcSourceBroadcastMs;
  final int webrtcSourceAdapterDrops;
  final int webrtcSourceScaledFrames;
  final double? averageWebrtcVideoBroadcasterMs;
  final double? maxWebrtcVideoBroadcasterMs;
  final int webrtcVideoBroadcasterSamples;
  final double? averageWebrtcVideoBroadcasterLockWaitMs;
  final double? maxWebrtcVideoBroadcasterLockWaitMs;
  final double? averageWebrtcVideoBroadcasterSinkDispatchMs;
  final double? maxWebrtcVideoBroadcasterSinkDispatchMs;
  final double? maxWebrtcVideoBroadcasterSingleSinkMs;
  final int? webrtcVideoBroadcasterSlowSinkId;
  final double? webrtcVideoBroadcasterSlowSinkMs;
  final String? webrtcVideoBroadcasterSlowSinkLabel;
  final int? webrtcVideoBroadcasterSlowestSinkId;
  final double? webrtcVideoBroadcasterSlowestSinkMs;
  final double? webrtcVideoBroadcasterSlowestSinkAverageMs;
  final int webrtcVideoBroadcasterSlowestSinkFrames;
  final String? webrtcVideoBroadcasterSlowestSinkLabel;
  final int webrtcVideoBroadcasterSinkCount;
  final int webrtcVideoBroadcasterMaxSinkCount;
  final int webrtcVideoBroadcasterActiveSinks;
  final int webrtcVideoBroadcasterInactiveSinks;
  final int webrtcVideoBroadcasterRequestedSinks;
  final int webrtcVideoBroadcasterBlackFrameSinks;
  final int webrtcVideoBroadcasterRotationAppliedSinks;
  final bool webrtcVideoBroadcasterInactiveNativeSinkBypassReported;
  final int webrtcVideoBroadcasterInactiveNativeSinksBypassed;
  final int webrtcVideoBroadcasterInactiveNativeSinksBypassedLast;
  final int webrtcVideoBroadcasterInactiveNativeSinksRefreshed;
  final int webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast;
  final String? webrtcVideoBroadcasterSinkRoster;
  final int webrtcVideoBroadcasterBlackSinks;
  final int webrtcVideoBroadcasterRotationDiscards;
  final int webrtcVideoBroadcasterUpdateRectCleared;
  final int webrtcVideoBroadcasterDiscardedFrames;
  final double? averageWebrtcVsePostToOnFrameMs;
  final double? maxWebrtcVsePostToOnFrameMs;
  final double? averageWebrtcVseOnFrameMs;
  final double? maxWebrtcVseOnFrameMs;
  final int webrtcVseOnFrameSamples;
  final int webrtcVseQueueOverloadDrops;
  final int webrtcVseEncoderQueueDrops;
  final int webrtcVseCwndDrops;
  final int webrtcVseBadTimestampDrops;
  final double? averageWebrtcVseMaybeEncodeMs;
  final double? maxWebrtcVseMaybeEncodeMs;
  final int webrtcVseMaybeEncodeSamples;
  final int webrtcVsePendingReplacedDrops;
  final int webrtcVseSizeDrops;
  final int webrtcVsePausedDrops;
  final int webrtcVseMediaOptimizationDrops;
  final double? averageWebrtcVseEncodeFrameMs;
  final double? maxWebrtcVseEncodeFrameMs;
  final double? averageWebrtcVseMaybePreEncodeMs;
  final double? maxWebrtcVseMaybePreEncodeMs;
  final double? averageWebrtcVseMaybeEncodeCallMs;
  final double? maxWebrtcVseMaybeEncodeCallMs;
  final double? averageWebrtcVseMaybeFrameSizeMs;
  final double? maxWebrtcVseMaybeFrameSizeMs;
  final double? averageWebrtcVseMaybeParameterUpdateMs;
  final double? maxWebrtcVseMaybeParameterUpdateMs;
  final double? averageWebrtcVseMaybeReconfigureMs;
  final double? maxWebrtcVseMaybeReconfigureMs;
  final int webrtcVsePendingReconfigureSignals;
  final int webrtcVsePendingReconfigureConfigureEncoder;
  final int webrtcVsePendingReconfigureFrameInfoChange;
  final int webrtcVsePendingReconfigureSourceRestriction;
  final int webrtcVsePendingReconfigureUnknown;
  final String? webrtcVsePendingReconfigureLastReason;
  final double? averageWebrtcVseMaybeRateUpdateMs;
  final double? maxWebrtcVseMaybeRateUpdateMs;
  final double? averageWebrtcVseMaybeDropChecksMs;
  final double? maxWebrtcVseMaybeDropChecksMs;
  final double? averageWebrtcVseEncodePreEncoderMs;
  final double? maxWebrtcVseEncodePreEncoderMs;
  final double? averageWebrtcVseEncodeInfoMs;
  final double? maxWebrtcVseEncodeInfoMs;
  final double? averageWebrtcVseEncodeCropScaleMs;
  final double? maxWebrtcVseEncodeCropScaleMs;
  final double? averageWebrtcVseEncodeUpdateRectMs;
  final double? maxWebrtcVseEncodeUpdateRectMs;
  final double? averageWebrtcVseEncodeResourceMs;
  final double? maxWebrtcVseEncodeResourceMs;
  final double? averageWebrtcVseEncodeMetadataMs;
  final double? maxWebrtcVseEncodeMetadataMs;
  final int webrtcVseEncodeFrameSamples;
  final double? averageWebrtcVideoEncoderEncodeMs;
  final double? maxWebrtcVideoEncoderEncodeMs;
  final int webrtcVideoEncoderEncodeSamples;
  final int webrtcVseEncodeFailures;
  final int webrtcVseEncodeSkippedBeforeEncoder;
  final String? webrtcFrameLineageStage;
  final int? webrtcFrameLineageFrameId;
  final int? webrtcFrameLineageSourceQpc;
  final int? webrtcFrameLineageStageQpc;
  final double? webrtcFrameLineageFrameAgeMs;
  final int? webrtcFrameLineagePreviousFrameId;
  final double? averageWebrtcFrameCadencePostDelayMs;
  final double? maxWebrtcFrameCadencePostDelayMs;
  final double? averageWebrtcFrameCadenceCallbackMs;
  final double? maxWebrtcFrameCadenceCallbackMs;
  final double? averageWebrtcFrameCadenceFrameDurationMs;
  final double? maxWebrtcFrameCadenceFrameDurationMs;
  final int webrtcFrameCadenceSends;
  final int webrtcFrameCadenceRepeatedSends;
  final int webrtcFrameCadencePostDelaySamples;
  final int webrtcFrameCadenceOverFrameDurationSends;
  final int webrtcFrameCadenceOverloadTriggerSends;
  final int webrtcFrameCadenceOverloadActiveSends;
  final int webrtcFrameCadenceOverloadDecaySends;
  final bool? webrtcFrameCadenceOverloadEnabledSeen;
  final bool? webrtcFrameCadenceOverloadDisabledSeen;
  final int webrtcFrameCadenceMaxScheduledForProcessing;
  final int webrtcFrameCadenceLastScheduledForProcessing;
  final int webrtcFrameCadenceMaxQueueOverloadBefore;
  final int webrtcFrameCadenceMaxQueueOverloadAfter;
  final int webrtcFrameCadenceLastQueueOverloadBefore;
  final int webrtcFrameCadenceLastQueueOverloadAfter;
  final double? averageWebrtcFrameCadenceQueuePostDelayMs;
  final double? maxWebrtcFrameCadenceQueuePostDelayMs;
  final int webrtcFrameCadenceQueueFrames;
  final int webrtcFrameCadenceQueueOverloadFrames;
  final int webrtcFrameCadenceQueuePostDelaySamples;
  final int webrtcFrameCadenceQueueMaxScheduledForProcessing;
  final int webrtcFrameCadenceQueueLastScheduledForProcessing;
  final int webrtcFrameCadenceQueuePassthroughFrames;
  final int webrtcFrameCadenceQueueZeroHertzFrames;
  final int webrtcFrameCadenceQueueVsyncFrames;
  final int webrtcFrameCadenceQueueUnknownFrames;
  final bool? webrtcFrameCadenceQueueCoalesceEnabledSeen;
  final bool? webrtcFrameCadenceQueueCoalesceDisabledSeen;
  final int webrtcFrameCadenceQueueCoalesceThreshold;
  final int webrtcFrameCadenceQueueCoalescedDrops;
  final bool? webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen;
  final bool? webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen;
  final int webrtcFrameCadenceQueuePrepostCoalescedDrops;
  final int webrtcFrameCadenceQueuePrepostProcessingDrops;
  final int webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing;
  final String? webrtcFrameCadenceQueueLastMode;
  final bool? webrtcFrameCadenceQueueMailboxEnabledSeen;
  final int webrtcFrameCadenceQueueMailboxFrames;
  final int webrtcFrameCadenceQueueMailboxProcessedFrames;
  final int webrtcFrameCadenceQueueMailboxReplacements;
  final int webrtcFrameCadenceQueueMailboxStaleDrops;
  final bool? webrtcFrameCadenceQueueMailboxProcessingActive;
  final bool? webrtcFrameCadenceQueueMailboxProcessingActiveSeen;
  final int webrtcFrameCadenceQueueMailboxPendingDepthMax;
  final int webrtcFrameCadenceQueueMailboxPendingDepthLast;
  final double? averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs;
  final double? maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs;
  final int webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples;
  final double? averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs;
  final double? maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs;
  final int webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples;
  final int webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses;
  final double? averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs;
  final double? maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs;
  final int webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples;
  final double? averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs;
  final double? maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs;
  final int webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples;
  final double? averageWebrtcFrameCadenceQueueMailboxVseCallMs;
  final double? maxWebrtcFrameCadenceQueueMailboxVseCallMs;
  final int webrtcFrameCadenceQueueMailboxVseCallSamples;
  final int webrtcFrameCadenceQueueMailboxStaleDropThresholdMs;

  bool get hasEvidence =>
      captureBackendMode != null ||
      observedCapturer != null ||
      dirtyRegionMode != null ||
      nativeSourceWidth != null ||
      nativeWindowRectWidth != null ||
      contentWidth != null ||
      preEncodeWidth != null ||
      canvas != null ||
      averageNativeFps != null ||
      averageSubmittedFps != null ||
      averageCaptureCallMs != null ||
      averageSourceCaptureMs != null ||
      averageWgcGetFrameMs != null ||
      wgcCaptureCalls > 0 ||
      wgcFramePoolEmptyCount > 0 ||
      wgcFramePoolReuseCount > 0 ||
      gdiCaptureCalls > 0 ||
      averageGdiTotalMs != null ||
      averageCallbackEntryDelayMs != null ||
      averageCaptureAcquireWaitMs != null ||
      averagePostCallbackWaitMs != null ||
      averageUnaccountedWaitMs != null ||
      maxFrameIntervalMs != null ||
      averageFrameCallbackMs != null ||
      updatedRegionEmptyCount > 0 ||
      updatedRegionNonEmptyCount > 0 ||
      updatedRegionRectCount > 0 ||
      averageUpdatedRegionAreaRatio != null ||
      averageUpdatedRegionAnalysisMs != null ||
      latestFramePacerEnabled != null ||
      averagePacerSubmittedFps != null ||
      gameCaptureSourceMode != null ||
      gameCaptureSourceApi != null ||
      gameCaptureSourceFormat != null ||
      gameCaptureSyncKind != null ||
      gameCaptureReadyState != null ||
      gameCaptureFailureReason != null ||
      gameCaptureConsumerAdapterLuid != null ||
      gameCaptureSourceAdapterLuid != null ||
      gameCaptureCrossAdapterSuspected != null ||
      averageGameCaptureFps != null ||
      gameCaptureSubmittedFrames > 0 ||
      gameCaptureDuplicateSkippedFrames > 0 ||
      gameCaptureDeliveryQueuedFrames > 0 ||
      gameCaptureDeliverySubmittedFrames > 0 ||
      gameCaptureDeliveryPacerResyncs > 0 ||
      gameCaptureDeliveryRepeatNoQueuedFrames > 0 ||
      gameCaptureDeliverySkipNoQueuedFrames > 0 ||
      gameCaptureDeliveryFreshWakeAfterSkipFrames > 0 ||
      gameCaptureDeliveryFreshImmediateFrames > 0 ||
      gameCaptureDeliveryRepeatPolicy != null ||
      gameCaptureDeliveryQueueDepth != null ||
      gameCaptureDeliveryRepeatSourceAgeSamples > 0 ||
      gameCaptureDeliverySubmitPrepSamples > 0 ||
      gameCaptureDeliveryOnFrameCallSamples > 0 ||
      gameCaptureDeliveryPostOnFrameSamples > 0 ||
      gameCaptureNativeBufferReleaseSamples > 0 ||
      gameCaptureDeliveryOverwriteAgeSamples > 0 ||
      gameCaptureDeliveryOverwrittenFreshFrames > 0 ||
      gameCaptureGpuScaledFrames > 0 ||
      gameCaptureCpuFallbackFrames > 0 ||
      gameCaptureNativeNv12SubmittedFrames > 0 ||
      gameCaptureNativeNv12QueuedFrames > 0 ||
      gameCaptureNativeNv12ReadyFrames > 0 ||
      gameCaptureNativeNv12NotReadyPolls > 0 ||
      gameCaptureNativeNv12ReadyPolicy != null ||
      gameCaptureNativeNv12FenceAvailable != null ||
      gameCaptureNativeNv12PendingPollMs != null ||
      gameCaptureNativeNv12MaxPendingSlots != null ||
      gameCaptureNativeNv12ReadyDrainDepth != null ||
      gameCaptureNativeNv12FrameOwnership != null ||
      gameCaptureNativeNv12WarmupI420Frames != null ||
      gameCaptureNativeNv12SingleInFlightEnabled != null ||
      gameCaptureNativeNv12GpuQueueBackoffEnabled != null ||
      gameCaptureNativeNv12GpuQueueBackoffThresholdFrames != null ||
      gameCaptureNativeNv12GpuQueueBackoffDurationFrames != null ||
      gameCaptureNativeNv12FenceSignaledFrames > 0 ||
      gameCaptureNativeNv12FenceReadyFrames > 0 ||
      gameCaptureNativeNv12FenceSignalFailures > 0 ||
      gameCaptureNativeNv12OwnedCopies > 0 ||
      gameCaptureNativeNv12OwnedCopySamples > 0 ||
      gameCaptureNativeNv12OverwrittenFrames > 0 ||
      gameCaptureNativeNv12OverwriteAgeSamples > 0 ||
      gameCaptureNativeNv12OverwrittenFreshFrames > 0 ||
      gameCaptureNativeNv12ReadyDroppedFrames > 0 ||
      gameCaptureNativeNv12ReadyDropAgeSamples > 0 ||
      gameCaptureNativeNv12ReadyDroppedFreshFrames > 0 ||
      gameCaptureNativeNv12LateReadyDropEnabled != null ||
      gameCaptureNativeNv12LateReadyDropThresholdMs != null ||
      gameCaptureNativeNv12LateReadyDroppedFrames > 0 ||
      gameCaptureNativeNv12LateReadyDropAgeSamples > 0 ||
      gameCaptureNativeNv12LateReadyDroppedFreshFrames > 0 ||
      gameCaptureNativeNv12LateReadyDropBltToReadySamples > 0 ||
      gameCaptureNativeNv12Failures > 0 ||
      gameCaptureNativeNv12ConvertSamples > 0 ||
      gameCaptureNativeNv12BgraScaleDrawSamples > 0 ||
      gameCaptureNativeNv12SingleInFlightDeferredFrames > 0 ||
      gameCaptureNativeNv12SingleInFlightDeferredFreshFrames > 0 ||
      gameCaptureNativeNv12SingleInFlightPendingMax > 0 ||
      gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffSamples > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples > 0 ||
      gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples > 0 ||
      gameCaptureNativeNv12AdmissionMailboxEnabled != null ||
      gameCaptureNativeNv12AdmissionMailboxPendingActive != null ||
      gameCaptureNativeNv12AdmissionMailboxStoredFrames > 0 ||
      gameCaptureNativeNv12AdmissionMailboxReplacedFrames > 0 ||
      gameCaptureNativeNv12AdmissionMailboxSubmittedFrames > 0 ||
      gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames > 0 ||
      gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples > 0 ||
      gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltSubmitSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures > 0 ||
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady > 0 ||
      gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint > 0 ||
      gameCaptureNativeNv12ReadyObservedImmediateFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedFenceEventFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedSourceEventFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedWaitOtherFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedLoopIdleFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedPreSubmitFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames > 0 ||
      gameCaptureNativeNv12ReadyObservedUnknownFrames > 0 ||
      gameCaptureNativeNv12BltToReadyOver1xFrames > 0 ||
      gameCaptureNativeNv12BltToReadyOver2xFrames > 0 ||
      gameCaptureNativeNv12BltToReadyOver3xFrames > 0 ||
      gameCaptureNativeNv12BufferCreateSamples > 0 ||
      gameCaptureNativeNv12FrameReadyToQueueSamples > 0 ||
      gameCaptureNativeNv12ConversionStartAgeSamples > 0 ||
      gameCaptureNativeNv12StaleBeforeQueueFrames > 0 ||
      gameCaptureNativeNv12HandoffDisabledReason != null ||
      gameCaptureNativeNv12OnFrameBackpressureEnabled != null ||
      gameCaptureNativeNv12OnFrameBackpressureThresholdMs != null ||
      gameCaptureNativeNv12OnFrameBackpressureFrameLimit != null ||
      gameCaptureNativeNv12OnFrameBackpressureFrames > 0 ||
      gameCaptureNativeNv12OnFrameBackpressureStreak > 0 ||
      gameCaptureNativeNv12OnFrameBackpressureMaxMs != null ||
      gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure != null ||
      gameCaptureReadbackQueuedFrames > 0 ||
      gameCaptureReadbackReadyFrames > 0 ||
      gameCaptureReadbackStaleDroppedFrames > 0 ||
      gameCaptureSourceFrameIndex > 0 ||
      gameCaptureLastSubmittedSourceFrameIndex > 0 ||
      gameCaptureSourceFrameRegressions > 0 ||
      gameCaptureSharedSlotMismatches > 0 ||
      gameCaptureTimestampMode != null ||
      gameCaptureTimestampSourceQpcFrames > 0 ||
      gameCaptureTimestampPacedFallbackFrames > 0 ||
      gameCaptureTimestampRepeatedFrames > 0 ||
      gameCaptureTimestampSamples > 0 ||
      gameCaptureTimestampAdjustments > 0 ||
      gameCaptureDeliveryWallSamples > 0 ||
      gameCaptureSourceQpcSamples > 0 ||
      gameCaptureSourceQpcRegressions > 0 ||
      gameCaptureSourceLatestObservedFrames > 0 ||
      gameCaptureSourceLatestFrameGaps > 0 ||
      gameCaptureSourceLatestFrameRegressions > 0 ||
      gameCaptureSourceLatestQpcSamples > 0 ||
      gameCaptureSourceLatestObservationSamples > 0 ||
      gameCaptureSourceLatestEventAgeSamples > 0 ||
      gameCaptureSourcePublishObservationAgeSamples > 0 ||
      gameCaptureProducerPresentGapSamples > 0 ||
      gameCaptureProducerCaptureGapSamples > 0 ||
      gameCaptureProducerPresentToPublishSamples > 0 ||
      gameCaptureProducerCopySamples > 0 ||
      gameCaptureProducerResolveSamples > 0 ||
      gameCaptureProducerThrottledFrames > 0 ||
      gameCaptureSourceDuplicateSkipAgeSamples > 0 ||
      gameCaptureProofFrames > 0 ||
      gameCaptureI420ProofFrames > 0 ||
      hasGameCaptureVisualFreshnessEvidence ||
      gameCaptureInitialBlackSkippedFrames > 0 ||
      averageEncoderTotalMs != null ||
      encoderInputPaths.isNotEmpty ||
      encoderNativeReadyFenceWaitSamples > 0 ||
      encoderNativeSourceAgeSamples > 0 ||
      encoderNativeBufferAgeSamples > 0 ||
      encoderNativeSampleLifetimeSamples > 0 ||
      encoderNativeAdapterLuid != null ||
      encoderProcessInputSamples > 0 ||
      encoderProcessOutputSamples > 0 ||
      encoderEncodedCallbackSamples > 0 ||
      encoderEncodedCallbackQueueWaitSamples > 0 ||
      encoderEncodedCallbackEnqueueSamples > 0 ||
      encoderMaxEncodedCallbackQueueDepth > 0 ||
      encoderMaxEncodedCallbackDrops > 0 ||
      encoderOutputFrames > 0 ||
      encoderMaxQueueDepth > 0 ||
      webrtcSourceOnFrameSamples > 0 ||
      webrtcVideoBroadcasterSamples > 0 ||
      webrtcVseOnFrameSamples > 0 ||
      webrtcVseMaybeEncodeSamples > 0 ||
      webrtcVseEncodeFrameSamples > 0 ||
      webrtcVideoEncoderEncodeSamples > 0 ||
      webrtcFrameCadenceSends > 0 ||
      webrtcFrameCadenceQueueFrames > 0 ||
      webrtcFrameCadenceQueueMailboxFrames > 0;

  String get backendLabel => captureBackendMode ?? 'unknown';

  String get observedCapturerLabel => observedCapturer ?? 'unknown';

  String get dirtyRegionModeLabel => dirtyRegionMode ?? 'unknown';

  String get windowGdiCaptureModeLabel => windowGdiCaptureMode ?? 'unknown';

  String get encoderInputPathLabel =>
      encoderInputPaths.isEmpty ? 'unknown' : encoderInputPaths.join(',');

  String get encoderStageLabel =>
      encoderStages.isEmpty ? 'unknown' : encoderStages.join(',');

  bool get nativeEncoderFenceWaitMissing =>
      encoderInputPaths.contains('native_nv12') &&
      encoderNativeInputFrames > 0 &&
      encoderNativeReadyFenceWaitSamples == 0;

  int get gameCaptureNativeNv12ReadyObservedFrames =>
      gameCaptureNativeNv12ReadyObservedImmediateFrames +
      gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames +
      gameCaptureNativeNv12ReadyObservedFenceEventFrames +
      gameCaptureNativeNv12ReadyObservedSourceEventFrames +
      gameCaptureNativeNv12ReadyObservedWaitOtherFrames +
      gameCaptureNativeNv12ReadyObservedLoopIdleFrames +
      gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames +
      gameCaptureNativeNv12ReadyObservedPreSubmitFrames +
      gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames +
      gameCaptureNativeNv12ReadyObservedUnknownFrames;

  bool get hasWebrtcRawSenderBoundaryDiagnostics =>
      webrtcSourceOnFrameSamples > 0 ||
      webrtcVideoBroadcasterSamples > 0 ||
      webrtcVseOnFrameSamples > 0 ||
      webrtcVseMaybeEncodeSamples > 0 ||
      webrtcVseEncodeFrameSamples > 0 ||
      webrtcVideoEncoderEncodeSamples > 0 ||
      webrtcFrameCadenceSends > 0 ||
      webrtcFrameCadenceQueueFrames > 0 ||
      webrtcFrameCadenceQueueMailboxFrames > 0;

  String get webrtcRawSenderBoundaryLabel {
    if (!hasWebrtcRawSenderBoundaryDiagnostics) {
      return 'missing';
    }
    return 'source_on_frame='
        '${_milliseconds(averageWebrtcSourceOnFrameMs)}/'
        '${_milliseconds(maxWebrtcSourceOnFrameMs)} '
        'source_broadcast='
        '${_milliseconds(averageWebrtcSourceBroadcastMs)}/'
        '${_milliseconds(maxWebrtcSourceBroadcastMs)} '
        'broadcaster='
        '${_milliseconds(averageWebrtcVideoBroadcasterMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterMs)} '
        'broadcaster_lock='
        '${_milliseconds(averageWebrtcVideoBroadcasterLockWaitMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterLockWaitMs)} '
        'broadcaster_sink='
        '${_milliseconds(averageWebrtcVideoBroadcasterSinkDispatchMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterSinkDispatchMs)} '
        'broadcaster_single_sink='
        '${_milliseconds(maxWebrtcVideoBroadcasterSingleSinkMs)} '
        'broadcaster_slow_sink='
        '${webrtcVideoBroadcasterSlowSinkId ?? 'unknown'}:'
        '${webrtcVideoBroadcasterSlowSinkLabel ?? 'unknown'}/'
        '${_milliseconds(webrtcVideoBroadcasterSlowSinkMs)} '
        'broadcaster_slowest_sink='
        '${webrtcVideoBroadcasterSlowestSinkId ?? 'unknown'}:'
        '${webrtcVideoBroadcasterSlowestSinkLabel ?? 'unknown'}/'
        '${_milliseconds(webrtcVideoBroadcasterSlowestSinkMs)} '
        'avg:${_milliseconds(webrtcVideoBroadcasterSlowestSinkAverageMs)} '
        'frames:$webrtcVideoBroadcasterSlowestSinkFrames '
        'broadcaster_sinks=$webrtcVideoBroadcasterSinkCount/'
        '$webrtcVideoBroadcasterMaxSinkCount '
        'broadcaster_sink_types=active:$webrtcVideoBroadcasterActiveSinks '
        'inactive:$webrtcVideoBroadcasterInactiveSinks '
        'requested:$webrtcVideoBroadcasterRequestedSinks '
        'black:$webrtcVideoBroadcasterBlackFrameSinks '
        'rotation:$webrtcVideoBroadcasterRotationAppliedSinks '
        'inactive_native_bypass:'
        '$webrtcVideoBroadcasterInactiveNativeSinksBypassed '
        'last:$webrtcVideoBroadcasterInactiveNativeSinksBypassedLast '
        'inactive_native_refresh:'
        '$webrtcVideoBroadcasterInactiveNativeSinksRefreshed '
        'last:$webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast '
        'reported:$webrtcVideoBroadcasterInactiveNativeSinkBypassReported '
        'broadcaster_roster='
        '${webrtcVideoBroadcasterSinkRoster ?? 'unknown'} '
        'source_adapter_drops=$webrtcSourceAdapterDrops '
        'vse_post_to_onframe='
        '${_milliseconds(averageWebrtcVsePostToOnFrameMs)}/'
        '${_milliseconds(maxWebrtcVsePostToOnFrameMs)} '
        'vse_onframe='
        '${_milliseconds(averageWebrtcVseOnFrameMs)}/'
        '${_milliseconds(maxWebrtcVseOnFrameMs)} '
        'vse_maybe_encode='
        '${_milliseconds(averageWebrtcVseMaybeEncodeMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeEncodeMs)} '
        'vse_maybe_pre_encode='
        '${_milliseconds(averageWebrtcVseMaybePreEncodeMs)}/'
        '${_milliseconds(maxWebrtcVseMaybePreEncodeMs)} '
        'vse_maybe_encode_call='
        '${_milliseconds(averageWebrtcVseMaybeEncodeCallMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeEncodeCallMs)} '
        'vse_maybe_parameter_update='
        '${_milliseconds(averageWebrtcVseMaybeParameterUpdateMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeParameterUpdateMs)} '
        'vse_maybe_reconfigure='
        '${_milliseconds(averageWebrtcVseMaybeReconfigureMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeReconfigureMs)} '
        'vse_reconfigure_signals=$webrtcVsePendingReconfigureSignals '
        'vse_reconfigure_causes='
        'configure:$webrtcVsePendingReconfigureConfigureEncoder,'
        'frame_info:$webrtcVsePendingReconfigureFrameInfoChange,'
        'source_restriction:$webrtcVsePendingReconfigureSourceRestriction,'
        'unknown:$webrtcVsePendingReconfigureUnknown '
        'vse_reconfigure_last='
        '${webrtcVsePendingReconfigureLastReason ?? 'unknown'} '
        'vse_maybe_rate_update='
        '${_milliseconds(averageWebrtcVseMaybeRateUpdateMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeRateUpdateMs)} '
        'vse_maybe_drop_checks='
        '${_milliseconds(averageWebrtcVseMaybeDropChecksMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeDropChecksMs)} '
        'vse_encode_frame='
        '${_milliseconds(averageWebrtcVseEncodeFrameMs)}/'
        '${_milliseconds(maxWebrtcVseEncodeFrameMs)} '
        'vse_encode_pre_encoder='
        '${_milliseconds(averageWebrtcVseEncodePreEncoderMs)}/'
        '${_milliseconds(maxWebrtcVseEncodePreEncoderMs)} '
        'vse_encode_info='
        '${_milliseconds(averageWebrtcVseEncodeInfoMs)}/'
        '${_milliseconds(maxWebrtcVseEncodeInfoMs)} '
        'vse_encode_resource='
        '${_milliseconds(averageWebrtcVseEncodeResourceMs)}/'
        '${_milliseconds(maxWebrtcVseEncodeResourceMs)} '
        'video_encoder_encode='
        '${_milliseconds(averageWebrtcVideoEncoderEncodeMs)}/'
        '${_milliseconds(maxWebrtcVideoEncoderEncodeMs)} '
        'lineage='
        'stage:${webrtcFrameLineageStage ?? 'unknown'} '
        'frame:${webrtcFrameLineageFrameId ?? '?'} '
        'prev:${webrtcFrameLineagePreviousFrameId ?? '?'} '
        'source_qpc:${webrtcFrameLineageSourceQpc ?? '?'} '
        'stage_qpc:${webrtcFrameLineageStageQpc ?? '?'} '
        'age:${_milliseconds(webrtcFrameLineageFrameAgeMs)} '
        'active_split='
        'task_posted_start:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs)} '
        'task_start_adaptation:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs)} '
        'adaptation_vse:0.0ms/0.0ms '
        'vse_encoder_post:0.0ms/0.0ms '
        'encoder_post_start:'
        '${_milliseconds(averageWebrtcVsePostToOnFrameMs)}/'
        '${_milliseconds(maxWebrtcVsePostToOnFrameMs)} '
        'encoder_start_encode_entry:'
        '${_milliseconds(averageWebrtcVseEncodePreEncoderMs)}/'
        '${_milliseconds(maxWebrtcVseEncodePreEncoderMs)} '
        'encode_entry_return:'
        '${_milliseconds(averageWebrtcVideoEncoderEncodeMs)}/'
        '${_milliseconds(maxWebrtcVideoEncoderEncodeMs)} '
        'frame_cadence_callback='
        '${_milliseconds(averageWebrtcFrameCadenceCallbackMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceCallbackMs)} '
        'frame_cadence_post_delay='
        '${_milliseconds(averageWebrtcFrameCadencePostDelayMs)}/'
        '${_milliseconds(maxWebrtcFrameCadencePostDelayMs)} '
        'frame_cadence_queue=frames:$webrtcFrameCadenceQueueFrames '
        'overload:$webrtcFrameCadenceQueueOverloadFrames '
        'scheduled_max:'
        '$webrtcFrameCadenceQueueMaxScheduledForProcessing '
        'mode:${webrtcFrameCadenceQueueLastMode ?? 'unknown'} '
        'modes:passthrough:$webrtcFrameCadenceQueuePassthroughFrames,'
        'zero_hertz:$webrtcFrameCadenceQueueZeroHertzFrames,'
        'vsync:$webrtcFrameCadenceQueueVsyncFrames,'
        'unknown:$webrtcFrameCadenceQueueUnknownFrames '
        'coalesce:enabled:$webrtcFrameCadenceQueueCoalesceEnabledSeen '
        'threshold:$webrtcFrameCadenceQueueCoalesceThreshold '
        'drops:$webrtcFrameCadenceQueueCoalescedDrops '
        'prepost:enabled:'
        '$webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen '
        'drops:$webrtcFrameCadenceQueuePrepostCoalescedDrops '
        'processing_drops:'
        '$webrtcFrameCadenceQueuePrepostProcessingDrops '
        'scheduled_max:'
        '$webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing '
        'post_delay:'
        '${_milliseconds(averageWebrtcFrameCadenceQueuePostDelayMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueuePostDelayMs)} '
        'mailbox=enabled:$webrtcFrameCadenceQueueMailboxEnabledSeen '
        'frames:$webrtcFrameCadenceQueueMailboxFrames '
        'processed:$webrtcFrameCadenceQueueMailboxProcessedFrames '
        'replacements:$webrtcFrameCadenceQueueMailboxReplacements '
        'stale:$webrtcFrameCadenceQueueMailboxStaleDrops '
        'active:$webrtcFrameCadenceQueueMailboxProcessingActive '
        'active_seen:$webrtcFrameCadenceQueueMailboxProcessingActiveSeen '
        'pending_depth:$webrtcFrameCadenceQueueMailboxPendingDepthLast/'
        '$webrtcFrameCadenceQueueMailboxPendingDepthMax '
        'pending_age:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs)} '
        'processing_age:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs)} '
        'enqueue_to_start:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs)} '
        'start_to_vse:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs)} '
        'vse_call:'
        '${_milliseconds(averageWebrtcFrameCadenceQueueMailboxVseCallMs)}/'
        '${_milliseconds(maxWebrtcFrameCadenceQueueMailboxVseCallMs)} '
        'deadline_misses:'
        '$webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses '
        'stale_threshold:'
        '$webrtcFrameCadenceQueueMailboxStaleDropThresholdMs '
        'frame_cadence_overload=trigger:'
        '$webrtcFrameCadenceOverloadTriggerSends '
        'active:$webrtcFrameCadenceOverloadActiveSends '
        'decay:$webrtcFrameCadenceOverloadDecaySends '
        'over_frame:$webrtcFrameCadenceOverFrameDurationSends '
        'scheduled_max:$webrtcFrameCadenceMaxScheduledForProcessing '
        'queue_before_max:$webrtcFrameCadenceMaxQueueOverloadBefore '
        'queue_after_max:$webrtcFrameCadenceMaxQueueOverloadAfter '
        'drops=queue:$webrtcVseEncoderQueueDrops '
        'overload:$webrtcVseQueueOverloadDrops '
        'cwnd:$webrtcVseCwndDrops '
        'media:$webrtcVseMediaOptimizationDrops '
        'failures=$webrtcVseEncodeFailures';
  }

  bool get hasGameCaptureEvidence {
    final observed = observedCapturerLabel.toLowerCase();
    return observed.contains('game-d3d11-hook') ||
        gameCaptureSubmittedFrames > 0 ||
        gameCaptureGpuScaledFrames > 0 ||
        gameCaptureNativeNv12SubmittedFrames > 0 ||
        gameCaptureProofFrames > 0 ||
        gameCaptureI420ProofFrames > 0 ||
        hasGameCaptureVisualFreshnessEvidence ||
        gameCaptureSourceApi != null;
  }

  bool get hasGameCaptureVisualFreshnessEvidence =>
      gameCaptureVisualFreshnessSampleFrames > 0 ||
      gameCaptureVisualFreshnessUniqueFrames > 0 ||
      averageGameCaptureVisualFreshnessUniqueFps != null ||
      gameCaptureVisualFreshnessLongestStaleMs != null ||
      gameCaptureVisualFreshnessLongestStaleFrames > 0 ||
      gameCaptureVisualFreshnessLowChangeFrames > 0;

  String get gameCaptureVisualFreshnessLabel {
    if (!hasGameCaptureVisualFreshnessEvidence) {
      return 'missing';
    }
    return 'mode=${gameCaptureVisualFreshnessSampleMode ?? 'unknown'} '
        'unique_fps=${_number(averageGameCaptureVisualFreshnessUniqueFps)} '
        'frames=$gameCaptureVisualFreshnessUniqueFrames/'
        '$gameCaptureVisualFreshnessSampleFrames '
        'longest_stale='
        '${_milliseconds(gameCaptureVisualFreshnessLongestStaleMs)} '
        'longest_stale_frames='
        '$gameCaptureVisualFreshnessLongestStaleFrames '
        'low_change=$gameCaptureVisualFreshnessLowChangeFrames '
        'artifact=${gameCaptureVisualFreshnessArtifactSet ?? '?'}';
  }

  Map<String, Object?> get gameCaptureVisualFreshnessJson {
    return {
      'available': hasGameCaptureVisualFreshnessEvidence,
      'sampleMode': gameCaptureVisualFreshnessSampleMode,
      'sampleFrames': gameCaptureVisualFreshnessSampleFrames,
      'uniqueFrames': gameCaptureVisualFreshnessUniqueFrames,
      'averageUniqueFps': averageGameCaptureVisualFreshnessUniqueFps,
      'longestStaleMs': gameCaptureVisualFreshnessLongestStaleMs,
      'longestStaleFrames': gameCaptureVisualFreshnessLongestStaleFrames,
      'lowChangeFrames': gameCaptureVisualFreshnessLowChangeFrames,
      'artifactSet': gameCaptureVisualFreshnessArtifactSet,
      'label': gameCaptureVisualFreshnessLabel,
    };
  }

  String get reportWgcFrameSummaryLabel => hasGameCaptureEvidence
      ? 'not_applicable_game_hook'
      : wgcFrameSummaryLabel;

  String get reportGdiFrameSummaryLabel => hasGameCaptureEvidence
      ? 'not_applicable_game_hook'
      : gdiFrameSummaryLabel;

  double get encoderSlowSampleRatio => encoderSampleCount <= 0
      ? 0.0
      : (encoderSlowFrameCount / encoderSampleCount).clamp(0.0, 1.0).toDouble();

  bool isNativeEncoderOverBudgetFor(double? frameBudgetMs) {
    final average = averageEncoderTotalMs;
    if (average == null || encoderSampleCount <= 0) {
      return false;
    }
    final budget = frameBudgetMs ?? 33.0;
    return average > budget || encoderSlowSampleRatio >= 0.25;
  }

  bool get nativeEncoderHandoffNoOutput =>
      encoderInputPaths.contains('native_nv12') &&
      encoderNativeInputFrames > 0 &&
      encoderNativeSampleFailures == 0 &&
      encoderOutputFrames == 0 &&
      encoderMaxQueueDepth > 0;

  bool get gameCaptureGpuHandoffUnproven {
    final observed = observedCapturerLabel.toLowerCase();
    final gameHookObserved = observed.contains('game-d3d11-hook');
    final cpuI420EncoderFallback =
        encoderCpuI420InputFrames > 0 &&
        encoderNativeInputFrames == 0 &&
        encoderInputPaths.contains('cpu_i420');
    final readbackFallbackObserved =
        gameCaptureReadbackQueuedFrames > 0 ||
        gameCaptureReadbackReadyFrames > 0 ||
        gameCaptureReadbackNotReadyFrames > 0;
    return gameHookObserved &&
        gameCaptureGpuScaledFrames > 0 &&
        gameCaptureNativeNv12SubmittedFrames == 0 &&
        (gameCaptureNativeNv12HandoffDisabledReason != null ||
            cpuI420EncoderFallback) &&
        readbackFallbackObserved;
  }

  String get nativeSourceResolutionLabel =>
      _resolutionLabel(nativeSourceWidth, nativeSourceHeight);

  String get requestedMaxResolutionLabel =>
      _resolutionLabel(requestedMaxWidth, requestedMaxHeight);

  String get nativeWindowRectResolutionLabel =>
      _resolutionLabel(nativeWindowRectWidth, nativeWindowRectHeight);

  String get contentResolutionLabel =>
      _resolutionLabel(contentWidth, contentHeight);

  String get preEncodeResolutionLabel =>
      _resolutionLabel(preEncodeWidth, preEncodeHeight);

  String get gameCaptureSourceResolutionLabel =>
      _resolutionLabel(gameCaptureSourceWidth, gameCaptureSourceHeight);

  String get gameCaptureOutputResolutionLabel =>
      _resolutionLabel(gameCaptureOutputWidth, gameCaptureOutputHeight);

  String get canvasLabel => canvas ?? 'unknown';

  String get gameCaptureFrameSummaryLabel {
    if (averageGameCaptureFps == null &&
        gameCaptureSubmittedFrames == 0 &&
        gameCaptureProofFrames == 0 &&
        gameCaptureI420ProofFrames == 0) {
      return 'unknown';
    }
    final proofState = gameCaptureProofVisible == null
        ? '?'
        : gameCaptureProofVisible!
        ? 'visible'
        : 'not_visible';
    final i420ProofState = gameCaptureI420ProofVisible == null
        ? '?'
        : gameCaptureI420ProofVisible!
        ? 'visible'
        : 'not_visible';
    return 'source=$gameCaptureSourceResolutionLabel '
        'output=$gameCaptureOutputResolutionLabel '
        'format=${gameCaptureFormat ?? '?'} '
        'backend_contract=${gameCaptureBackendContractVersion ?? '?'} '
        'source_mode=${gameCaptureSourceMode ?? 'helper-d3d11'} '
        'source_api=${gameCaptureSourceApi ?? 'unknown'} '
        'source_format=${gameCaptureSourceFormat ?? 'unknown'} '
        'color_space=${gameCaptureColorSpace ?? 'unknown'} '
        'sync=${gameCaptureSyncKind ?? 'unknown'} '
        'ready=${gameCaptureReadyState ?? 'unknown'} '
        'failure=${gameCaptureFailureReason ?? 'unknown'} '
        'consumer_adapter=${gameCaptureConsumerAdapterLuid ?? 'unknown'} '
        'consumer_vendor=${gameCaptureConsumerAdapterVendorId ?? '?'} '
        'consumer_device=${gameCaptureConsumerAdapterDeviceId ?? '?'} '
        'source_adapter=${gameCaptureSourceAdapterLuid ?? 'unknown'} '
        'cross_adapter=${gameCaptureCrossAdapterSuspected ?? 'unknown'} '
        'fps=${_number(averageGameCaptureFps)} '
        'submitted=$gameCaptureSubmittedFrames '
        'repeated=$gameCaptureRepeatedFrames '
        'duplicate_skipped=$gameCaptureDuplicateSkippedFrames '
        'delivery=$gameCaptureDeliveryQueuedFrames/'
        '$gameCaptureDeliverySubmittedFrames '
        'delivery_overwritten=$gameCaptureDeliveryOverwrittenFrames '
        'delivery_pacer_resyncs=$gameCaptureDeliveryPacerResyncs '
        'delivery_pacer_lag_max='
        '${_milliseconds(gameCaptureDeliveryPacerLagMaxMs.toDouble())} '
        'delivery_repeat_no_queue=$gameCaptureDeliveryRepeatNoQueuedFrames '
        'delivery_skip_no_queue=$gameCaptureDeliverySkipNoQueuedFrames '
        'delivery_fresh_wake_after_skip='
        '$gameCaptureDeliveryFreshWakeAfterSkipFrames '
        'delivery_fresh_immediate=$gameCaptureDeliveryFreshImmediateFrames '
        'delivery_repeat_policy='
        '${gameCaptureDeliveryRepeatPolicy ?? 'skip-on-miss'} '
        'delivery_queue_depth=${gameCaptureDeliveryQueueDepth ?? '?'} '
        'delivery_repeat_source_age='
        '${_milliseconds(averageGameCaptureDeliveryRepeatSourceAgeMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryRepeatSourceAgeMs)} '
        'delivery_on_frame='
        '${_milliseconds(averageGameCaptureDeliveryOnFrameMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOnFrameMs)} '
        'delivery_submit_prep='
        '${_milliseconds(averageGameCaptureDeliverySubmitPrepMs)}/'
        '${_milliseconds(maxGameCaptureDeliverySubmitPrepMs)} '
        'delivery_on_frame_call='
        '${_milliseconds(averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOnFrameCallMs)} '
        'delivery_post_on_frame='
        '${_milliseconds(averageGameCaptureDeliveryPostOnFrameMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryPostOnFrameMs)} '
        'native_buffer_release='
        '${_milliseconds(averageGameCaptureNativeBufferReleaseMs)}/'
        '${_milliseconds(maxGameCaptureNativeBufferReleaseMs)} '
        'ready_to_queue='
        '${_milliseconds(averageGameCaptureReadyToQueueMs)}/'
        '${_milliseconds(maxGameCaptureReadyToQueueMs)} '
        'delivery_queue_wait='
        '${_milliseconds(averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryQueueWaitMs)} '
        'delivery_overwrite_age='
        '${_milliseconds(averageGameCaptureDeliveryOverwriteAgeMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOverwriteAgeMs)} '
        'delivery_overwritten_fresh='
        '$gameCaptureDeliveryOverwrittenFreshFrames '
        'ready_to_submit='
        '${_milliseconds(averageGameCaptureReadyToSubmitMs)}/'
        '${_milliseconds(maxGameCaptureReadyToSubmitMs)} '
        'source_to_submit='
        '${_milliseconds(averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(maxGameCaptureSourceToSubmitMs)} '
        'source_to_readback_ready='
        '${_milliseconds(averageGameCaptureSourceToReadbackReadyMs)}/'
        '${_milliseconds(maxGameCaptureSourceToReadbackReadyMs)} '
        'readback_queue_to_map='
        '${_milliseconds(averageGameCaptureReadbackQueueToMapMs)}/'
        '${_milliseconds(maxGameCaptureReadbackQueueToMapMs)} '
        'map_to_i420='
        '${_milliseconds(averageGameCaptureMapToI420Ms)}/'
        '${_milliseconds(maxGameCaptureMapToI420Ms)} '
        'source_to_i420_ready='
        '${_milliseconds(averageGameCaptureSourceToI420ReadyMs)}/'
        '${_milliseconds(maxGameCaptureSourceToI420ReadyMs)} '
        'source_to_queue='
        '${_milliseconds(averageGameCaptureSourceToQueueMs)}/'
        '${_milliseconds(maxGameCaptureSourceToQueueMs)} '
        'source_duplicate_skip_age='
        '${_milliseconds(averageGameCaptureSourceDuplicateSkipAgeMs)}/'
        '${_milliseconds(maxGameCaptureSourceDuplicateSkipAgeMs)} '
        'copied=$gameCaptureCopiedFrames '
        'dropped=$gameCaptureDroppedFrames '
        'overwritten=$gameCaptureOverwrittenFrames '
        'gpu_scaled=$gameCaptureGpuScaledFrames '
        'gpu_failures=$gameCaptureGpuScaleFailures '
        'cpu_fallback=$gameCaptureCpuFallbackFrames '
        'native_nv12=$gameCaptureNativeNv12SubmittedFrames '
        'native_nv12_async=$gameCaptureNativeNv12QueuedFrames/'
        '$gameCaptureNativeNv12ReadyFrames '
        'native_nv12_not_ready=$gameCaptureNativeNv12NotReadyPolls '
        'native_nv12_ready_policy='
        '${gameCaptureNativeNv12ReadyPolicy ?? 'unknown'} '
        'native_nv12_fence_available='
        '${gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'native_nv12_pending_poll_ms='
        '${gameCaptureNativeNv12PendingPollMs ?? '?'} '
        'native_nv12_max_pending_slots='
        '${gameCaptureNativeNv12MaxPendingSlots ?? '?'} '
        'native_nv12_ready_drain_depth='
        '${gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'native_nv12_frame_ownership='
        '${gameCaptureNativeNv12FrameOwnership ?? 'unknown'} '
        'native_nv12_warmup_i420_frames='
        '${gameCaptureNativeNv12WarmupI420Frames ?? '?'} '
        'native_nv12_single_in_flight='
        'enabled:${gameCaptureNativeNv12SingleInFlightEnabled ?? '?'} '
        'deferred:$gameCaptureNativeNv12SingleInFlightDeferredFrames '
        'fresh:$gameCaptureNativeNv12SingleInFlightDeferredFreshFrames '
        'pending_max:$gameCaptureNativeNv12SingleInFlightPendingMax '
        'source_age:${_milliseconds(averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs)} '
        'native_nv12_gpu_queue_backoff='
        'enabled:${gameCaptureNativeNv12GpuQueueBackoffEnabled ?? '?'} '
        'threshold_frames:${gameCaptureNativeNv12GpuQueueBackoffThresholdFrames ?? '?'} '
        'duration_frames:${gameCaptureNativeNv12GpuQueueBackoffDurationFrames ?? '?'} '
        'triggered:$gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames '
        'suppressed:$gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames '
        'fresh:$gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames '
        'backoff:${_milliseconds(averageGameCaptureNativeNv12GpuQueueBackoffMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12GpuQueueBackoffMs)} '
        'trigger_blt_to_ready:${_milliseconds(averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs)} '
        'source_age:${_milliseconds(averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs)} '
        'native_nv12_admission_mailbox='
        'enabled:${gameCaptureNativeNv12AdmissionMailboxEnabled ?? '?'} '
        'active:${gameCaptureNativeNv12AdmissionMailboxPendingActive ?? '?'} '
        'stored:$gameCaptureNativeNv12AdmissionMailboxStoredFrames '
        'replaced:$gameCaptureNativeNv12AdmissionMailboxReplacedFrames '
        'submitted:$gameCaptureNativeNv12AdmissionMailboxSubmittedFrames '
        'stale_dropped:$gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames '
        'pending_age:${_milliseconds(averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs)} '
        'submit_source_age:${_milliseconds(averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs)} '
        'native_nv12_fence='
        '$gameCaptureNativeNv12FenceSignaledFrames/'
        '$gameCaptureNativeNv12FenceReadyFrames/'
        '$gameCaptureNativeNv12FenceSignalFailures '
        'native_nv12_owned_copy='
        '$gameCaptureNativeNv12OwnedCopies '
        '${_milliseconds(averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12OwnedCopyMs)} '
        'native_nv12_overwritten=$gameCaptureNativeNv12OverwrittenFrames '
        'native_nv12_overwrite_age='
        '${_milliseconds(averageGameCaptureNativeNv12OverwriteAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12OverwriteAgeMs)} '
        'native_nv12_overwritten_fresh='
        '$gameCaptureNativeNv12OverwrittenFreshFrames '
        'native_nv12_ready_dropped='
        '$gameCaptureNativeNv12ReadyDroppedFrames '
        'native_nv12_ready_drop_age='
        '${_milliseconds(averageGameCaptureNativeNv12ReadyDropAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ReadyDropAgeMs)} '
        'native_nv12_ready_dropped_fresh='
        '$gameCaptureNativeNv12ReadyDroppedFreshFrames '
        'native_nv12_late_ready_drop='
        'enabled:${gameCaptureNativeNv12LateReadyDropEnabled ?? '?'} '
        'threshold:${gameCaptureNativeNv12LateReadyDropThresholdMs ?? '?'} '
        'dropped:$gameCaptureNativeNv12LateReadyDroppedFrames '
        'age:${_milliseconds(averageGameCaptureNativeNv12LateReadyDropAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12LateReadyDropAgeMs)} '
        'fresh:$gameCaptureNativeNv12LateReadyDroppedFreshFrames '
        'blt_to_ready:'
        '${_milliseconds(averageGameCaptureNativeNv12LateReadyDropBltToReadyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12LateReadyDropBltToReadyMs)} '
        'native_nv12_failures=$gameCaptureNativeNv12Failures '
        'native_nv12_convert='
        '${_milliseconds(averageGameCaptureNativeNv12ConvertMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ConvertMs)} '
        'native_nv12_samples=$gameCaptureNativeNv12ConvertSamples '
        'native_nv12_bgra_scale_draw='
        '${_milliseconds(averageGameCaptureNativeNv12BgraScaleDrawMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12BgraScaleDrawMs)} '
        'native_nv12_blt_submit='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltSubmitMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltSubmitMs)} '
        'native_nv12_blt_cpu_submit='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs)} '
        'native_nv12_blt_to_ready='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltToReadyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltToReadyMs)} '
        'native_nv12_blt_submit_to_fence='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs)} '
        'native_nv12_blt_gpu_execution='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs)} '
        'native_nv12_blt_estimated_gpu_queue_delay='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs)} '
        'native_nv12_blt_gpu_timestamp='
        'fail:$gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures/'
        'not_ready:$gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady/'
        'disjoint:$gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint '
        'native_nv12_ready_observed='
        'immediate:$gameCaptureNativeNv12ReadyObservedImmediateFrames '
        'post:$gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames '
        'event:$gameCaptureNativeNv12ReadyObservedFenceEventFrames '
        'source:$gameCaptureNativeNv12ReadyObservedSourceEventFrames '
        'idle:$gameCaptureNativeNv12ReadyObservedLoopIdleFrames '
        'duplicate:$gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames '
        'pre:$gameCaptureNativeNv12ReadyObservedPreSubmitFrames '
        'write:$gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames '
        'other:$gameCaptureNativeNv12ReadyObservedWaitOtherFrames '
        'unknown:$gameCaptureNativeNv12ReadyObservedUnknownFrames '
        'native_nv12_blt_to_ready_over='
        '$gameCaptureNativeNv12BltToReadyOver1xFrames/'
        '$gameCaptureNativeNv12BltToReadyOver2xFrames/'
        '$gameCaptureNativeNv12BltToReadyOver3xFrames '
        'native_nv12_buffer_create='
        '${_milliseconds(averageGameCaptureNativeNv12BufferCreateMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12BufferCreateMs)} '
        'native_nv12_frame_ready_to_queue='
        '${_milliseconds(averageGameCaptureNativeNv12FrameReadyToQueueMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12FrameReadyToQueueMs)} '
        'native_nv12_conversion_start_age='
        '${_milliseconds(averageGameCaptureNativeNv12ConversionStartAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ConversionStartAgeMs)} '
        'native_nv12_stale_before_queue='
        '$gameCaptureNativeNv12StaleBeforeQueueFrames '
        'native_nv12_onframe_backpressure='
        'enabled:${gameCaptureNativeNv12OnFrameBackpressureEnabled ?? '?'} '
        'threshold:${gameCaptureNativeNv12OnFrameBackpressureThresholdMs ?? '?'} '
        'frames:${gameCaptureNativeNv12OnFrameBackpressureFrames} '
        'streak:${gameCaptureNativeNv12OnFrameBackpressureStreak}/'
        '${gameCaptureNativeNv12OnFrameBackpressureFrameLimit ?? '?'} '
        'max:${_milliseconds(gameCaptureNativeNv12OnFrameBackpressureMaxMs)} '
        'suspended:'
        '${gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure ?? '?'} '
        'native_nv12_disabled='
        '${gameCaptureNativeNv12HandoffDisabledReason ?? 'none'} '
        'readback=$gameCaptureReadbackQueuedFrames/'
        '$gameCaptureReadbackReadyFrames '
        'readback_not_ready=$gameCaptureReadbackNotReadyFrames '
        'readback_overwritten=$gameCaptureReadbackOverwrittenFrames '
        'readback_stale_dropped=$gameCaptureReadbackStaleDroppedFrames '
        'readback_latency_dropped=$gameCaptureReadbackLatencyDroppedFrames '
        'readback_map_attempts=$gameCaptureReadbackMapAttempts '
        'readback_latency='
        '${_milliseconds(averageGameCaptureReadbackLatencyMs)} '
        'readback_latency_frames='
        '${_number(averageGameCaptureReadbackLatencyFrames)}/'
        '$gameCaptureMaxReadbackLatencyFrames '
        'source_frame=$gameCaptureSourceFrameIndex '
        'last_submitted_source_frame='
        '$gameCaptureLastSubmittedSourceFrameIndex '
        'source_regressions=$gameCaptureSourceFrameRegressions '
        'source_duplicates=$gameCaptureSourceFrameDuplicates '
        'source_gaps=$gameCaptureSourceFrameGaps '
        'shared_slot_mismatches=$gameCaptureSharedSlotMismatches '
        'timestamp=${gameCaptureTimestampMode ?? 'unknown'} '
        'timestamp_source_qpc=$gameCaptureTimestampSourceQpcFrames '
        'timestamp_paced_fallback='
        '$gameCaptureTimestampPacedFallbackFrames '
        'timestamp_repeated=$gameCaptureTimestampRepeatedFrames '
        'timestamp_delta=${_milliseconds(averageGameCaptureTimestampDeltaMs)}/'
        '${_milliseconds(maxGameCaptureTimestampDeltaMs)} '
        'timestamp_adjustments=$gameCaptureTimestampAdjustments '
        'delivery_wall_delta='
        '${_milliseconds(averageGameCaptureDeliveryWallDeltaMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryWallDeltaMs)} '
        'delivery_wall_min='
        '${_milliseconds(minGameCaptureDeliveryWallDeltaMs)} '
        'delivery_wall_samples=$gameCaptureDeliveryWallSamples '
        'delivery_wall_over2x=$gameCaptureDeliveryWallOver2xFrames '
        'delivery_wall_over3x=$gameCaptureDeliveryWallOver3xFrames '
        'delivery_wall_under_half=$gameCaptureDeliveryWallUnderHalfFrames '
        'source_qpc_delta='
        '${_milliseconds(averageGameCaptureSourceQpcDeltaMs)}/'
        '${_milliseconds(maxGameCaptureSourceQpcDeltaMs)} '
        'source_qpc_regressions=$gameCaptureSourceQpcRegressions '
        'source_latest=observed:$gameCaptureSourceLatestObservedFrames '
        'gaps:$gameCaptureSourceLatestFrameGaps '
        'regressions:$gameCaptureSourceLatestFrameRegressions '
        'qpc:${_milliseconds(averageGameCaptureSourceLatestQpcDeltaMs)}/'
        '${_milliseconds(maxGameCaptureSourceLatestQpcDeltaMs)} '
        'qpc_over:$gameCaptureSourceLatestQpcOver2xFrames/'
        '$gameCaptureSourceLatestQpcOver3xFrames '
        'observe:${_milliseconds(averageGameCaptureSourceLatestObservationDeltaMs)}/'
        '${_milliseconds(maxGameCaptureSourceLatestObservationDeltaMs)} '
        'observe_over:$gameCaptureSourceLatestObservationOver2xFrames/'
        '$gameCaptureSourceLatestObservationOver3xFrames '
        'event_age:${_milliseconds(averageGameCaptureSourceLatestEventAgeMs)}/'
        '${_milliseconds(maxGameCaptureSourceLatestEventAgeMs)} '
        'event_age_over:$gameCaptureSourceLatestEventAgeOver1xFrames/'
        '$gameCaptureSourceLatestEventAgeOver2xFrames/'
        '$gameCaptureSourceLatestEventAgeOver3xFrames '
        'source_publish_age:'
        '${_milliseconds(averageGameCaptureSourcePublishObservationAgeMs)}/'
        '${_milliseconds(maxGameCaptureSourcePublishObservationAgeMs)} '
        'publish_age_over:'
        '$gameCaptureSourcePublishObservationAgeOver1xFrames/'
        '$gameCaptureSourcePublishObservationAgeOver2xFrames/'
        '$gameCaptureSourcePublishObservationAgeOver3xFrames '
        'producer=present:'
        '${_milliseconds(averageGameCaptureProducerPresentGapMs)}/'
        '${_milliseconds(maxGameCaptureProducerPresentGapMs)} '
        'capture:${_milliseconds(averageGameCaptureProducerCaptureGapMs)}/'
        '${_milliseconds(maxGameCaptureProducerCaptureGapMs)} '
        'present_publish:'
        '${_milliseconds(averageGameCaptureProducerPresentToPublishMs)}/'
        '${_milliseconds(maxGameCaptureProducerPresentToPublishMs)} '
        'copy:${_milliseconds(averageGameCaptureProducerCopyMs)}/'
        '${_milliseconds(maxGameCaptureProducerCopyMs)} '
        'resolve:${_milliseconds(averageGameCaptureProducerResolveMs)}/'
        '${_milliseconds(maxGameCaptureProducerResolveMs)} '
        'throttled:$gameCaptureProducerThrottledFrames '
        'gpu_scale=${_milliseconds(averageGameCaptureGpuScaleMs)} '
        'copy=${_milliseconds(averageGameCaptureCopyMs)} '
        'map=${_milliseconds(averageGameCaptureMapMs)} '
        'convert=${_milliseconds(averageGameCaptureConvertMs)} '
        'failures=$gameCaptureMapFailures/$gameCaptureConvertFailures '
        'proof=$gameCaptureProofFrames/$gameCaptureVisibleProofFrames '
        '$proofState '
        'initial_black_skipped=$gameCaptureInitialBlackSkippedFrames '
        'visible_source_seen=${gameCaptureVisibleSourceSeen ?? '?'} '
        'luma=${gameCaptureProofMinLuma ?? '?'}/'
        '${gameCaptureProofMaxLuma ?? '?'} '
        'samples=${gameCaptureProofNonzeroSamples ?? '?'}/'
        '${gameCaptureProofSamples ?? '?'} '
        'path=${gameCaptureProofPath ?? 'none'} '
        'i420_proof=$gameCaptureI420ProofFrames/'
        '$gameCaptureVisibleI420ProofFrames '
        '$i420ProofState '
        'i420_luma=${gameCaptureI420ProofMinLuma ?? '?'}/'
        '${gameCaptureI420ProofMaxLuma ?? '?'} '
        'i420_samples=${gameCaptureI420ProofNonzeroSamples ?? '?'}/'
        '${gameCaptureI420ProofSamples ?? '?'} '
        'i420_path=${gameCaptureI420ProofPath ?? 'none'} '
        'visual_freshness=[$gameCaptureVisualFreshnessLabel]';
  }

  String get updatedRegionShapeLabel {
    final avgRatio = averageUpdatedRegionAreaRatio;
    final maxRatio = maxUpdatedRegionAreaRatio;
    if (updatedRegionRectCount <= 0 &&
        updatedRegionMaxRectCount <= 0 &&
        avgRatio == null &&
        maxRatio == null &&
        updatedRegionFullFrameCount == 0 &&
        updatedRegionTinyFrameCount == 0) {
      return 'unknown';
    }
    return 'rects=$updatedRegionRectCount max=$updatedRegionMaxRectCount '
        'area=${_ratioPercent(avgRatio)} avg / ${_ratioPercent(maxRatio)} max '
        'full=$updatedRegionFullFrameCount tiny=$updatedRegionTinyFrameCount';
  }

  String get fullSourceAcquisitionAttributionLabel {
    final hasSizeEvidence =
        nativeSourceWidth != null ||
        requestedMaxWidth != null ||
        contentWidth != null ||
        preEncodeWidth != null;
    if (!hasSizeEvidence && averageSourceCaptureMs == null) {
      return 'unknown';
    }
    final contentRatio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      contentWidth,
      contentHeight,
    );
    final preEncodeRatio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      preEncodeWidth,
      preEncodeHeight,
    );
    return 'source=$nativeSourceResolutionLabel '
        '(${_megapixels(nativeSourceWidth, nativeSourceHeight)}) '
        'requested_max=$requestedMaxResolutionLabel '
        'content=$contentResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'source_to_content=${_ratioMultiplier(contentRatio)} '
        'source_to_pre_encode=${_ratioMultiplier(preEncodeRatio)} '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max';
  }

  String get blockingAcquireAttributionLabel {
    if (averageCaptureAcquireWaitMs == null &&
        averageCallbackEntryDelayMs == null &&
        averageSourceCaptureMs == null &&
        averagePostCallbackWaitMs == null &&
        averageUnaccountedWaitMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantCaptureDelayStageLabel '
        'acquire_wait=${_milliseconds(averageCaptureAcquireWaitMs)} avg / '
        '${_milliseconds(maxCaptureAcquireWaitMs)} max '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max';
  }

  String get cpuReadbackAttributionLabel {
    final parts = <String>[];
    if (reportWgcFrameSummaryLabel != 'unknown' &&
        reportWgcFrameSummaryLabel != 'not_applicable_game_hook') {
      parts.add(
        'WGC map=${_milliseconds(averageWgcMapTextureMs)} avg / '
        '${_milliseconds(maxWgcMapTextureMs)} max '
        'copy_rows=${_milliseconds(averageWgcCopyRowsMs)} avg / '
        '${_milliseconds(maxWgcCopyRowsMs)} max '
        'copy_texture=${_milliseconds(averageWgcCopyTextureMs)} avg / '
        '${_milliseconds(maxWgcCopyTextureMs)} max '
        'try_get=${_milliseconds(averageWgcTryGetFrameMs)} avg / '
        '${_milliseconds(maxWgcTryGetFrameMs)} max',
      );
    }
    if (reportGdiFrameSummaryLabel != 'unknown' &&
        reportGdiFrameSummaryLabel != 'not_applicable_game_hook') {
      parts.add(
        'GDI mode=$windowGdiCaptureModeLabel '
        'final_methods=[$gdiFinalMethodMixLabel] '
        'black_frames=$gdiBlackFrameCount '
        'low_variance_frames=$gdiLowVarianceFrameCount '
        'print_full=${_milliseconds(averageGdiPrintFullMs)} avg / '
        '${_milliseconds(maxGdiPrintFullMs)} max '
        'print_fallback=${_milliseconds(averageGdiPrintFallbackMs)} avg / '
        '${_milliseconds(maxGdiPrintFallbackMs)} max '
        'bitblt=${_milliseconds(averageGdiBitBltMs)} avg / '
        '${_milliseconds(maxGdiBitBltMs)} max '
        'crop=${_milliseconds(averageGdiCropMs)} avg / '
        '${_milliseconds(maxGdiCropMs)} max',
      );
    }
    if (averageFrameConvertMs != null || averageFrameScaleMs != null) {
      parts.add(
        'wrapper convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)}',
      );
    }
    if (gameCaptureFrameSummaryLabel != 'unknown') {
      parts.add('game_capture=[$gameCaptureFrameSummaryLabel]');
    }
    return parts.isEmpty ? 'unknown' : parts.join('; ');
  }

  String get dirtyRegionProcessingAttributionLabel {
    final shape = updatedRegionShapeLabel;
    if (shape == 'unknown' && averageUpdatedRegionAnalysisMs == null) {
      return 'unknown';
    }
    return 'mode=$dirtyRegionModeLabel shape=$shape '
        'analysis=${_milliseconds(averageUpdatedRegionAnalysisMs)} avg / '
        '${_milliseconds(maxUpdatedRegionAnalysisMs)} max';
  }

  String get frameLifetimeSyncAttributionLabel {
    if (averageCallbackEntryDelayMs == null &&
        averagePostCallbackWaitMs == null &&
        averageUnaccountedWaitMs == null &&
        averagePacerFrameAgeMs == null) {
      return 'unknown';
    }
    return 'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max '
        'pacer_age=${_milliseconds(averagePacerFrameAgeMs)} avg / '
        '${_milliseconds(maxPacerFrameAgeMs)} max';
  }

  String get fullFrameCopyBeforeDownscaleAttributionLabel {
    final ratio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      contentWidth,
      contentHeight,
    );
    final hasFrameWork =
        averageFrameConvertMs != null || averageFrameScaleMs != null;
    if (ratio == null && !hasFrameWork) {
      return 'unknown';
    }
    final likelyFullFrameCopy =
        ratio != null && ratio > 1.05 && averageFrameConvertMs != null;
    return 'pre_scale_full_frame_copy='
        '${likelyFullFrameCopy ? 'likely' : 'not_indicated'} '
        'source=$nativeSourceResolutionLabel '
        'content=$contentResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'source_to_content=${_ratioMultiplier(ratio)} '
        'convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)} '
        'callback=${_milliseconds(averageFrameCallbackMs)} avg / '
        '${_milliseconds(maxFrameCallbackMs)} max';
  }

  Map<String, Object?> get captureCauseAttribution => {
    'fullSourceAcquisition': fullSourceAcquisitionAttributionLabel,
    'blockingAcquireWait': blockingAcquireAttributionLabel,
    'cpuReadbackOrCopy': cpuReadbackAttributionLabel,
    'dirtyRegionProcessing': dirtyRegionProcessingAttributionLabel,
    'frameLifetimeOrSynchronization': frameLifetimeSyncAttributionLabel,
    'fullFrameCopyBeforeDownscale':
        fullFrameCopyBeforeDownscaleAttributionLabel,
  };

  String get dominantWgcFrameStageLabel {
    final stages = <({String label, double value})>[
      if (averageWgcMapTextureMs != null)
        (label: 'map_texture', value: averageWgcMapTextureMs!),
      if (averageWgcCopyRowsMs != null)
        (label: 'copy_rows', value: averageWgcCopyRowsMs!),
      if (averageWgcZeroHertzMs != null)
        (label: 'zero_hertz_compare', value: averageWgcZeroHertzMs!),
      if (averageWgcCopyTextureMs != null)
        (label: 'copy_texture', value: averageWgcCopyTextureMs!),
      if (averageWgcTryGetFrameMs != null)
        (label: 'try_get_frame', value: averageWgcTryGetFrameMs!),
      if (averageWgcSurfaceMs != null)
        (label: 'surface', value: averageWgcSurfaceMs!),
      if (averageWgcTextureMs != null)
        (label: 'texture', value: averageWgcTextureMs!),
      if (averageWgcContentSizeMs != null)
        (label: 'content_size', value: averageWgcContentSizeMs!),
      if (averageWgcMonitorScaleMs != null)
        (label: 'monitor_scale', value: averageWgcMonitorScaleMs!),
    ];
    final framePoolMissCount =
        wgcFramePoolEmptyCount +
        wgcFramePoolReuseCount +
        wgcCaptureFrameNullCount;
    final framePoolMissRatio = wgcCaptureCalls <= 0
        ? 0.0
        : framePoolMissCount / max(1, wgcCaptureCalls);
    final ensureSleepRatio = wgcEnsureFrameCalls <= 0
        ? 0.0
        : wgcEnsureSleepCount / max(1, wgcEnsureFrameCalls);
    if (framePoolMissRatio >= 0.10) {
      stages.add((
        label: 'frame_pool_empty',
        value: averageWgcEnsureFrameMs ?? averageWgcProcessFrameMs ?? 0,
      ));
    }
    if (ensureSleepRatio >= 0.10) {
      stages.add((
        label: 'startup_wait',
        value: averageWgcEnsureFrameMs ?? averageWgcGetFrameMs ?? 0,
      ));
    }
    if (stages.isEmpty) {
      if (framePoolMissCount > 0) {
        return 'frame_pool_empty';
      }
      if (wgcEnsureSleepCount > 0) {
        return 'startup_wait';
      }
      return 'unknown';
    }
    stages.sort((a, b) => b.value.compareTo(a.value));
    return stages.first.label;
  }

  String get wgcFrameSummaryLabel {
    if (wgcCaptureCalls <= 0 &&
        averageWgcGetFrameMs == null &&
        averageWgcProcessFrameMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantWgcFrameStageLabel '
        'calls=$wgcCaptureCalls successes=$wgcCaptureSuccessCount '
        'source_not_capturable=$wgcSourceNotCapturableCount '
        'ensure=${_milliseconds(averageWgcEnsureFrameMs)} avg / '
        '${_milliseconds(maxWgcEnsureFrameMs)} max '
        'ensure_sleeps=$wgcEnsureSleepCount '
        'process=${_milliseconds(averageWgcProcessFrameMs)} avg / '
        '${_milliseconds(maxWgcProcessFrameMs)} max '
        'process_successes=$wgcProcessFrameSuccessCount/$wgcProcessFrameCalls '
        'try_get=${_milliseconds(averageWgcTryGetFrameMs)} avg / '
        '${_milliseconds(maxWgcTryGetFrameMs)} max '
        'map=${_milliseconds(averageWgcMapTextureMs)} avg / '
        '${_milliseconds(maxWgcMapTextureMs)} max '
        'copy_rows=${_milliseconds(averageWgcCopyRowsMs)} avg / '
        '${_milliseconds(maxWgcCopyRowsMs)} max '
        'zero_hertz=${_milliseconds(averageWgcZeroHertzMs)} avg / '
        '${_milliseconds(maxWgcZeroHertzMs)} max '
        'frame_pool_empty=$wgcFramePoolEmptyCount '
        'frame_pool_reuse=$wgcFramePoolReuseCount '
        'capture_frame_null=$wgcCaptureFrameNullCount '
        'resizes=$wgcResizeCount '
        'recreates=$wgcFramePoolRecreateCount';
  }

  String get gdiOriginalResolutionLabel =>
      _resolutionLabel(gdiOriginalWidth, gdiOriginalHeight);

  String get gdiCroppedResolutionLabel =>
      _resolutionLabel(gdiCroppedWidth, gdiCroppedHeight);

  String get gdiFrameResolutionLabel =>
      _resolutionLabel(gdiFrameWidth, gdiFrameHeight);

  int get gdiFinalFrameCount =>
      gdiFinalPrintFullCount +
      gdiFinalPrintFallbackCount +
      gdiFinalBitBltCount +
      gdiFinalNoneCount;

  double? get gdiBlackFrameRatio {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return null;
    }
    return (gdiBlackFrameCount / total).clamp(0.0, 1.0).toDouble();
  }

  double? get gdiLowVarianceFrameRatio {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return null;
    }
    return (gdiLowVarianceFrameCount / total).clamp(0.0, 1.0).toDouble();
  }

  bool get gdiOutputProbablyInvalid {
    final total = gdiFinalFrameCount;
    if (total < 10) {
      return false;
    }
    final blackThreshold = total * 0.8;
    final lowVarianceThreshold = total * 0.8;
    return gdiBlackFrameCount >= blackThreshold &&
        gdiLowVarianceFrameCount >= lowVarianceThreshold;
  }

  String get gdiOutputValidityLabel {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return 'unknown';
    }
    final blackRatio = gdiBlackFrameRatio ?? 0;
    final lowVarianceRatio = gdiLowVarianceFrameRatio ?? 0;
    final status = gdiOutputProbablyInvalid
        ? 'invalid_black_low_variance'
        : 'valid';
    return '$status black=$gdiBlackFrameCount/$total '
        '(${(blackRatio * 100).toStringAsFixed(1)}%) '
        'low_variance=$gdiLowVarianceFrameCount/$total '
        '(${(lowVarianceRatio * 100).toStringAsFixed(1)}%) '
        'final_methods=[$gdiFinalMethodMixLabel]';
  }

  String get gdiFinalMethodMixLabel {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return 'unknown';
    }
    return 'print_full=$gdiFinalPrintFullCount '
        'print_fallback=$gdiFinalPrintFallbackCount '
        'bitblt=$gdiFinalBitBltCount none=$gdiFinalNoneCount';
  }

  String get dominantGdiFrameStageLabel {
    final stages = <({String label, double value})>[
      if (averageGdiPrintFullMs != null)
        (label: 'print_full', value: averageGdiPrintFullMs!),
      if (averageGdiPrintFallbackMs != null)
        (label: 'print_fallback', value: averageGdiPrintFallbackMs!),
      if (averageGdiBitBltMs != null)
        (label: 'bitblt', value: averageGdiBitBltMs!),
      if (averageGdiOwnedCaptureMs != null)
        (label: 'owned_capture', value: averageGdiOwnedCaptureMs!),
      if (averageGdiOwnedCompositeMs != null)
        (label: 'owned_composite', value: averageGdiOwnedCompositeMs!),
      if (averageGdiOwnedEnumMs != null)
        (label: 'owned_enum', value: averageGdiOwnedEnumMs!),
      if (averageGdiCropMs != null) (label: 'crop', value: averageGdiCropMs!),
      if (averageGdiCreateFrameMs != null)
        (label: 'create_frame', value: averageGdiCreateFrameMs!),
      if (averageGdiGetDcSizeMs != null)
        (label: 'get_dc_size', value: averageGdiGetDcSizeMs!),
      if (averageGdiGetDcMs != null)
        (label: 'get_dc', value: averageGdiGetDcMs!),
      if (averageGdiRectMs != null)
        (label: 'window_rect', value: averageGdiRectMs!),
      if (averageGdiVisibilityMs != null)
        (label: 'visibility', value: averageGdiVisibilityMs!),
      if (averageGdiMemDcMs != null)
        (label: 'mem_dc', value: averageGdiMemDcMs!),
      if (averageGdiCleanupMs != null)
        (label: 'cleanup', value: averageGdiCleanupMs!),
    ];
    if (gdiPermanentErrorCount > 0 && gdiCaptureSuccessCount == 0) {
      return 'permanent_error';
    }
    if (gdiTemporaryErrorCount > 0 && gdiCaptureSuccessCount == 0) {
      if (gdiRectFailCount > 0) {
        return 'window_rect';
      }
      if (gdiDcFailCount > 0) {
        return 'get_dc';
      }
      if (gdiFrameCreateFailCount > 0) {
        return 'create_frame';
      }
      return 'temporary_error';
    }
    if (gdiHiddenOrMinimizedCount > 0 &&
        gdiHiddenOrMinimizedCount >= max(1, gdiCaptureCalls) * 0.25) {
      stages.add((label: 'hidden_or_minimized', value: averageGdiTotalMs ?? 0));
    }
    if (stages.isEmpty) {
      return 'unknown';
    }
    stages.sort((a, b) => b.value.compareTo(a.value));
    return stages.first.label;
  }

  String get gdiFrameSummaryLabel {
    if (gdiCaptureCalls <= 0 && averageGdiTotalMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantGdiFrameStageLabel '
        'mode=$windowGdiCaptureModeLabel '
        'calls=$gdiCaptureCalls successes=$gdiCaptureSuccessCount '
        'temp_errors=$gdiTemporaryErrorCount '
        'permanent_errors=$gdiPermanentErrorCount '
        'hidden=$gdiHiddenOrMinimizedCount '
        'rect_fail=$gdiRectFailCount dc_fail=$gdiDcFailCount '
        'frame_create_fail=$gdiFrameCreateFailCount '
        'original=$gdiOriginalResolutionLabel '
        'cropped=$gdiCroppedResolutionLabel '
        'frame=$gdiFrameResolutionLabel '
        'total=${_milliseconds(averageGdiTotalMs)} avg / '
        '${_milliseconds(maxGdiTotalMs)} max '
        'print_full=${_milliseconds(averageGdiPrintFullMs)} avg / '
        '${_milliseconds(maxGdiPrintFullMs)} max '
        'print_full_successes=$gdiPrintFullSuccessCount/$gdiPrintFullCallCount '
        'print_fallback=${_milliseconds(averageGdiPrintFallbackMs)} avg / '
        '${_milliseconds(maxGdiPrintFallbackMs)} max '
        'print_fallback_successes=$gdiPrintFallbackSuccessCount/'
        '$gdiPrintFallbackCallCount '
        'bitblt=${_milliseconds(averageGdiBitBltMs)} avg / '
        '${_milliseconds(maxGdiBitBltMs)} max '
        'bitblt_successes=$gdiBitBltSuccessCount/$gdiBitBltCallCount '
        'final_methods=[$gdiFinalMethodMixLabel] '
        'black_frames=$gdiBlackFrameCount '
        'low_variance_frames=$gdiLowVarianceFrameCount '
        'crop=${_milliseconds(averageGdiCropMs)} avg / '
        '${_milliseconds(maxGdiCropMs)} max '
        'owned_capture=${_milliseconds(averageGdiOwnedCaptureMs)} avg / '
        '${_milliseconds(maxGdiOwnedCaptureMs)} max '
        'owned_capture_successes=$gdiOwnedWindowCaptureSuccessCount/'
        '$gdiOwnedWindowCaptureCallCount '
        'owned_windows=$gdiOwnedWindowFrameCount';
  }

  String get dominantCaptureDelayStageLabel {
    final phases = <({String label, double value})>[
      if (averageSourceCaptureMs != null)
        (label: 'source_capture', value: averageSourceCaptureMs!),
      if (averageCallbackEntryDelayMs != null)
        (label: 'callback_entry', value: averageCallbackEntryDelayMs!),
      if (averageCaptureResultCallbackMs != null)
        (label: 'capture_callback', value: averageCaptureResultCallbackMs!),
      if (averagePostCallbackWaitMs != null)
        (label: 'post_callback', value: averagePostCallbackWaitMs!),
      if (averageUnaccountedWaitMs != null)
        (label: 'unaccounted_wait', value: averageUnaccountedWaitMs!),
    ];
    if (phases.isEmpty) {
      return 'unknown';
    }
    phases.sort((a, b) => b.value.compareTo(a.value));
    final dominant = phases.first.label;
    if (dominant == 'source_capture' &&
        !hasGameCaptureEvidence &&
        dominantWgcFrameStageLabel != 'unknown') {
      return '$dominant/$dominantWgcFrameStageLabel';
    }
    if (dominant == 'source_capture' &&
        !hasGameCaptureEvidence &&
        dominantGdiFrameStageLabel != 'unknown' &&
        gdiFrameSummaryLabel != 'unknown') {
      return '$dominant/$dominantGdiFrameStageLabel';
    }
    return dominant;
  }

  String get capturePhaseSummaryLabel {
    if (dominantCaptureDelayStageLabel == 'unknown') {
      return 'unknown';
    }
    return 'dominant=$dominantCaptureDelayStageLabel '
        'source=${_milliseconds(averageSourceCaptureMs)} '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} '
        'callback=${_milliseconds(averageCaptureResultCallbackMs)} '
        'post=${_milliseconds(averagePostCallbackWaitMs)} '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)}';
  }

  String get summaryLabel {
    if (!hasEvidence) {
      return 'unknown';
    }
    return 'backend=$backendLabel '
        'capturer=$observedCapturerLabel '
        'dirty_region_mode=$dirtyRegionModeLabel '
        'window_gdi_mode=$windowGdiCaptureModeLabel '
        'source=${nativeSourceResolutionLabel} '
        'requested_max=${requestedMaxResolutionLabel} '
        'window_rect=${nativeWindowRectResolutionLabel} '
        'content=${contentResolutionLabel} '
        'pre_encode=${preEncodeResolutionLabel} '
        'canvas=$canvasLabel '
        'native_fps=${_number(averageNativeFps)} '
        'submitted_fps=${_number(averageSubmittedFps)} '
        'capture_call=${_milliseconds(averageCaptureCallMs)} avg / '
        '${_milliseconds(maxCaptureCallMs)} max '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max '
        'source_capture_count=$sourceCaptureSampleCount '
        'wgc_frame=[$reportWgcFrameSummaryLabel] '
        'gdi_frame=[$reportGdiFrameSummaryLabel] '
        'game_capture=[$gameCaptureFrameSummaryLabel] '
        'capture_phase=$capturePhaseSummaryLabel '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'capture_callback=${_milliseconds(averageCaptureResultCallbackMs)} avg / '
        '${_milliseconds(maxCaptureResultCallbackMs)} max '
        'acquire_wait=${_milliseconds(averageCaptureAcquireWaitMs)} avg / '
        '${_milliseconds(maxCaptureAcquireWaitMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted_wait=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max '
        'callback_count=$captureResultCallbackCount '
        'frame_interval=${_milliseconds(p95FrameIntervalMs)} p95 / '
        '${_milliseconds(maxFrameIntervalMs)} max '
        'frame_callback=${_milliseconds(averageFrameCallbackMs)} avg / '
        '${_milliseconds(maxFrameCallbackMs)} max '
        'pacer=${latestFramePacerEnabled == null
            ? '?'
            : latestFramePacerEnabled!
            ? 'on'
            : 'off'} '
        'pacer_submit=${_number(averagePacerSubmittedFps)} '
        'pacer_unique=${_number(averagePacerUniqueFps)} '
        'pacer_interval=${_milliseconds(p95PacerIntervalMs)} p95 / '
        '${_milliseconds(maxPacerIntervalMs)} max '
        'pacer_age=${_milliseconds(averagePacerFrameAgeMs)} avg / '
        '${_milliseconds(maxPacerFrameAgeMs)} max '
        'pacer_on_frame=${_milliseconds(averagePacerOnFrameMs)} avg / '
        '${_milliseconds(maxPacerOnFrameMs)} max '
        'convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)} '
        'on_frame=${_milliseconds(averageFrameOnFrameMs)} '
        'updated_region=$updatedRegionNonEmptyCount dirty / '
        '$updatedRegionEmptyCount empty '
        'updated_region_shape=$updatedRegionShapeLabel '
        'updated_region_analysis=${_milliseconds(averageUpdatedRegionAnalysisMs)} avg / '
        '${_milliseconds(maxUpdatedRegionAnalysisMs)} max '
        'encoder_total=${_milliseconds(averageEncoderTotalMs)} avg / '
        '${_milliseconds(maxEncoderTotalMs)} max '
        'encoder_slow=$encoderSlowFrameCount/$encoderSampleCount '
        'encoder_rate_control=${encoderRateControlMode ?? 'unknown'} '
        'encoder_target_bitrate=${encoderTargetBitrateBps ?? '?'} '
        'encoder_input=$encoderInputPathLabel '
        'encoder_native_input=$encoderNativeInputFrames '
        'encoder_cpu_i420_input=$encoderCpuI420InputFrames '
        'encoder_native_sample_failures=$encoderNativeSampleFailures '
        'encoder_native_suspended=$encoderNativeSuspendedFrames '
        'encoder_native_ready_fence=$encoderNativeReadyFenceFrames '
        'encoder_native_ready_fence_timeout='
        '$encoderNativeReadyFenceTimeoutFrames '
        'encoder_native_ready_fence_wait='
        '${_milliseconds(averageEncoderNativeReadyFenceWaitMs)} avg / '
        '${_milliseconds(maxEncoderNativeReadyFenceWaitMs)} max '
        'encoder_native_ready_fence_wait_samples='
        '$encoderNativeReadyFenceWaitSamples '
        'encoder_native_source='
        '${encoderNativeSourceMode ?? 'unknown'}/'
        '${encoderNativeSourceFormat ?? '?'} '
        'encoder_native_source_frame=$encoderNativeSourceFrameIndex '
        'encoder_native_source_age='
        '${_milliseconds(averageEncoderNativeSourceAgeMs)} avg / '
        '${_milliseconds(maxEncoderNativeSourceAgeMs)} max '
        'encoder_native_source_age_at_create='
        '${_milliseconds(averageEncoderNativeSourceAgeAtCreateMs)} avg / '
        '${_milliseconds(maxEncoderNativeSourceAgeAtCreateMs)} max '
        'encoder_native_buffer_age='
        '${_milliseconds(averageEncoderNativeBufferAgeMs)} avg / '
        '${_milliseconds(maxEncoderNativeBufferAgeMs)} max '
        'encoder_native_sample_lifetime='
        '${_milliseconds(averageEncoderNativeSampleLifetimeMs)} avg / '
        '${_milliseconds(maxEncoderNativeSampleLifetimeMs)} max '
        'encoder_native_sample_lifetime_samples='
        '$encoderNativeSampleLifetimeSamples '
        'encoder_native_adapter=${encoderNativeAdapterLuid ?? 'unknown'} '
        'encoder_process_input='
        '${_milliseconds(averageEncoderProcessInputMs)} avg / '
        '${_milliseconds(maxEncoderProcessInputMs)} max '
        'encoder_process_input_samples=$encoderProcessInputSamples '
        'encoder_process_output='
        '${_milliseconds(averageEncoderProcessOutputMs)} avg / '
        '${_milliseconds(maxEncoderProcessOutputMs)} max '
        'encoder_process_output_samples=$encoderProcessOutputSamples '
        'encoder_encoded_callback='
        '${_milliseconds(averageEncoderEncodedCallbackMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackMs)} max '
        'encoder_encoded_callback_samples=$encoderEncodedCallbackSamples '
        'encoder_encoded_callback_wait='
        '${_milliseconds(averageEncoderEncodedCallbackQueueWaitMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackQueueWaitMs)} max '
        'encoder_encoded_callback_wait_samples='
        '$encoderEncodedCallbackQueueWaitSamples '
        'encoder_encoded_callback_enqueue='
        '${_milliseconds(averageEncoderEncodedCallbackEnqueueMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackEnqueueMs)} max '
        'encoder_encoded_callback_enqueue_samples='
        '$encoderEncodedCallbackEnqueueSamples '
        'encoder_encoded_callback_async=$encoderEncodedCallbackAsyncFrames '
        'encoder_encoded_callback_queue_max='
        '$encoderMaxEncodedCallbackQueueDepth '
        'encoder_encoded_callback_drops_max=$encoderMaxEncodedCallbackDrops '
        'encoder_encoded_callback_outputs_max='
        '$encoderMaxEncodedCallbackOutputs '
        'encoder_stages=$encoderStageLabel '
        'encoder_outputs=$encoderOutputFrames '
        'encoder_output_bytes=$encoderOutputBytes '
        'encoder_queue_max=$encoderMaxQueueDepth '
        'encoder_retained_max=$encoderMaxRetainedSamples '
        'encoder_encoded_outputs_max=$encoderMaxEncodedOutputs '
        'webrtc_raw_sender=[$webrtcRawSenderBoundaryLabel] '
        'crop_region=${cropRegion == null
            ? '?'
            : cropRegion!
            ? 'true'
            : 'false'} '
        'wait_timeouts=$captureWaitTimeoutCount '
        'stale=$staleFrameReuseCount/$duplicatedFrameCount '
        'pacer_dupes=$pacerDuplicateSubmitCount '
        'pacer_overwrites=$pacerOverwrittenFrameCount '
        'pacer_skips=$pacerSkippedTickCount';
  }

  bool isCaptureLimitedFor({
    required double targetFps,
    required double? frameBudgetMs,
  }) {
    if (!hasEvidence || targetFps <= 0) {
      return false;
    }

    final captureCallSlow =
        averageCaptureCallMs != null &&
        frameBudgetMs != null &&
        averageCaptureCallMs! > frameBudgetMs * 1.25;
    final nativeFpsSlow =
        averageNativeFps != null && averageNativeFps! < targetFps * 0.75;
    final p95GapSlow =
        p95FrameIntervalMs != null &&
        frameBudgetMs != null &&
        p95FrameIntervalMs! > frameBudgetMs * 1.5;
    final maxGapSlow =
        maxFrameIntervalMs != null &&
        frameBudgetMs != null &&
        maxFrameIntervalMs! > frameBudgetMs * 3;
    final hasStaleFrames = staleFrameReuseCount > 0;
    final encoderLooksFast =
        averageEncoderTotalMs == null ||
        frameBudgetMs == null ||
        (averageEncoderTotalMs! < frameBudgetMs * 0.75 &&
            encoderSlowFrameCount <= max(1, encoderSampleCount ~/ 10));
    return (captureCallSlow ||
            nativeFpsSlow ||
            p95GapSlow ||
            maxGapSlow ||
            hasStaleFrames) &&
        encoderLooksFast;
  }

  Map<String, Object?> toJson() {
    return {
      'captureBackendMode': captureBackendMode,
      'observedCapturer': observedCapturer,
      'observedCapturerId': observedCapturerId,
      'dirtyRegionMode': dirtyRegionMode,
      'windowGdiCaptureMode': windowGdiCaptureMode,
      'sourceType': sourceType,
      'nativeSourceWidth': nativeSourceWidth,
      'nativeSourceHeight': nativeSourceHeight,
      'requestedMaxWidth': requestedMaxWidth,
      'requestedMaxHeight': requestedMaxHeight,
      'nativeWindowRectWidth': nativeWindowRectWidth,
      'nativeWindowRectHeight': nativeWindowRectHeight,
      'contentWidth': contentWidth,
      'contentHeight': contentHeight,
      'preEncodeWidth': preEncodeWidth,
      'preEncodeHeight': preEncodeHeight,
      'canvas': canvas,
      'cropRegion': cropRegion,
      'averageNativeFps': averageNativeFps,
      'averageSubmittedFps': averageSubmittedFps,
      'targetNativeFps': targetNativeFps,
      'averageCaptureCallMs': averageCaptureCallMs,
      'maxCaptureCallMs': maxCaptureCallMs,
      'averageSourceCaptureMs': averageSourceCaptureMs,
      'maxSourceCaptureMs': maxSourceCaptureMs,
      'sourceCaptureSampleCount': sourceCaptureSampleCount,
      'wgcCaptureCalls': wgcCaptureCalls,
      'wgcCaptureSuccessCount': wgcCaptureSuccessCount,
      'wgcSourceNotCapturableCount': wgcSourceNotCapturableCount,
      'wgcEnsureFrameCalls': wgcEnsureFrameCalls,
      'wgcEnsureSleepCount': wgcEnsureSleepCount,
      'wgcProcessFrameCalls': wgcProcessFrameCalls,
      'wgcProcessFrameSuccessCount': wgcProcessFrameSuccessCount,
      'wgcFramePoolEmptyCount': wgcFramePoolEmptyCount,
      'wgcFramePoolReuseCount': wgcFramePoolReuseCount,
      'wgcCaptureFrameNullCount': wgcCaptureFrameNullCount,
      'wgcMappedTextureCreateCount': wgcMappedTextureCreateCount,
      'wgcResizeCount': wgcResizeCount,
      'wgcFramePoolRecreateCount': wgcFramePoolRecreateCount,
      'averageWgcGetFrameMs': averageWgcGetFrameMs,
      'maxWgcGetFrameMs': maxWgcGetFrameMs,
      'averageWgcEnsureFrameMs': averageWgcEnsureFrameMs,
      'maxWgcEnsureFrameMs': maxWgcEnsureFrameMs,
      'averageWgcProcessFrameMs': averageWgcProcessFrameMs,
      'maxWgcProcessFrameMs': maxWgcProcessFrameMs,
      'averageWgcTryGetFrameMs': averageWgcTryGetFrameMs,
      'maxWgcTryGetFrameMs': maxWgcTryGetFrameMs,
      'averageWgcSurfaceMs': averageWgcSurfaceMs,
      'maxWgcSurfaceMs': maxWgcSurfaceMs,
      'averageWgcTextureMs': averageWgcTextureMs,
      'maxWgcTextureMs': maxWgcTextureMs,
      'averageWgcContentSizeMs': averageWgcContentSizeMs,
      'maxWgcContentSizeMs': maxWgcContentSizeMs,
      'averageWgcCopyTextureMs': averageWgcCopyTextureMs,
      'maxWgcCopyTextureMs': maxWgcCopyTextureMs,
      'averageWgcMapTextureMs': averageWgcMapTextureMs,
      'maxWgcMapTextureMs': maxWgcMapTextureMs,
      'averageWgcCopyRowsMs': averageWgcCopyRowsMs,
      'maxWgcCopyRowsMs': maxWgcCopyRowsMs,
      'averageWgcMonitorScaleMs': averageWgcMonitorScaleMs,
      'maxWgcMonitorScaleMs': maxWgcMonitorScaleMs,
      'averageWgcZeroHertzMs': averageWgcZeroHertzMs,
      'maxWgcZeroHertzMs': maxWgcZeroHertzMs,
      'dominantWgcFrameStage': dominantWgcFrameStageLabel,
      'wgcFrameSummary': wgcFrameSummaryLabel,
      'reportWgcFrameSummary': reportWgcFrameSummaryLabel,
      'gdiCaptureCalls': gdiCaptureCalls,
      'gdiCaptureSuccessCount': gdiCaptureSuccessCount,
      'gdiTemporaryErrorCount': gdiTemporaryErrorCount,
      'gdiPermanentErrorCount': gdiPermanentErrorCount,
      'gdiHiddenOrMinimizedCount': gdiHiddenOrMinimizedCount,
      'gdiRectFailCount': gdiRectFailCount,
      'gdiDcFailCount': gdiDcFailCount,
      'gdiFrameCreateFailCount': gdiFrameCreateFailCount,
      'gdiPrintFullCallCount': gdiPrintFullCallCount,
      'gdiPrintFullSuccessCount': gdiPrintFullSuccessCount,
      'gdiPrintFallbackCallCount': gdiPrintFallbackCallCount,
      'gdiPrintFallbackSuccessCount': gdiPrintFallbackSuccessCount,
      'gdiBitBltCallCount': gdiBitBltCallCount,
      'gdiBitBltSuccessCount': gdiBitBltSuccessCount,
      'gdiFinalPrintFullCount': gdiFinalPrintFullCount,
      'gdiFinalPrintFallbackCount': gdiFinalPrintFallbackCount,
      'gdiFinalBitBltCount': gdiFinalBitBltCount,
      'gdiFinalNoneCount': gdiFinalNoneCount,
      'gdiFinalFrameCount': gdiFinalFrameCount,
      'gdiFinalMethodMix': gdiFinalMethodMixLabel,
      'gdiBlackFrameCount': gdiBlackFrameCount,
      'gdiBlackFrameRatio': gdiBlackFrameRatio,
      'gdiLowVarianceFrameCount': gdiLowVarianceFrameCount,
      'gdiLowVarianceFrameRatio': gdiLowVarianceFrameRatio,
      'gdiOutputProbablyInvalid': gdiOutputProbablyInvalid,
      'gdiOutputValidity': gdiOutputValidityLabel,
      'gdiOwnedWindowFrameCount': gdiOwnedWindowFrameCount,
      'gdiOwnedWindowCaptureCallCount': gdiOwnedWindowCaptureCallCount,
      'gdiOwnedWindowCaptureSuccessCount': gdiOwnedWindowCaptureSuccessCount,
      'gdiOriginalWidth': gdiOriginalWidth,
      'gdiOriginalHeight': gdiOriginalHeight,
      'gdiCroppedWidth': gdiCroppedWidth,
      'gdiCroppedHeight': gdiCroppedHeight,
      'gdiFrameWidth': gdiFrameWidth,
      'gdiFrameHeight': gdiFrameHeight,
      'averageGdiTotalMs': averageGdiTotalMs,
      'maxGdiTotalMs': maxGdiTotalMs,
      'averageGdiRectMs': averageGdiRectMs,
      'maxGdiRectMs': maxGdiRectMs,
      'averageGdiVisibilityMs': averageGdiVisibilityMs,
      'maxGdiVisibilityMs': maxGdiVisibilityMs,
      'averageGdiGetDcMs': averageGdiGetDcMs,
      'maxGdiGetDcMs': maxGdiGetDcMs,
      'averageGdiGetDcSizeMs': averageGdiGetDcSizeMs,
      'maxGdiGetDcSizeMs': maxGdiGetDcSizeMs,
      'averageGdiCreateFrameMs': averageGdiCreateFrameMs,
      'maxGdiCreateFrameMs': maxGdiCreateFrameMs,
      'averageGdiMemDcMs': averageGdiMemDcMs,
      'maxGdiMemDcMs': maxGdiMemDcMs,
      'averageGdiPrintFullMs': averageGdiPrintFullMs,
      'maxGdiPrintFullMs': maxGdiPrintFullMs,
      'averageGdiPrintFallbackMs': averageGdiPrintFallbackMs,
      'maxGdiPrintFallbackMs': maxGdiPrintFallbackMs,
      'averageGdiBitBltMs': averageGdiBitBltMs,
      'maxGdiBitBltMs': maxGdiBitBltMs,
      'averageGdiCleanupMs': averageGdiCleanupMs,
      'maxGdiCleanupMs': maxGdiCleanupMs,
      'averageGdiCropMs': averageGdiCropMs,
      'maxGdiCropMs': maxGdiCropMs,
      'averageGdiOwnedEnumMs': averageGdiOwnedEnumMs,
      'maxGdiOwnedEnumMs': maxGdiOwnedEnumMs,
      'averageGdiOwnedCaptureMs': averageGdiOwnedCaptureMs,
      'maxGdiOwnedCaptureMs': maxGdiOwnedCaptureMs,
      'averageGdiOwnedCompositeMs': averageGdiOwnedCompositeMs,
      'maxGdiOwnedCompositeMs': maxGdiOwnedCompositeMs,
      'dominantGdiFrameStage': dominantGdiFrameStageLabel,
      'gdiFrameSummary': gdiFrameSummaryLabel,
      'reportGdiFrameSummary': reportGdiFrameSummaryLabel,
      'dominantCaptureDelayStage': dominantCaptureDelayStageLabel,
      'capturePhaseSummary': capturePhaseSummaryLabel,
      'averageCallbackEntryDelayMs': averageCallbackEntryDelayMs,
      'maxCallbackEntryDelayMs': maxCallbackEntryDelayMs,
      'averageCaptureResultCallbackMs': averageCaptureResultCallbackMs,
      'maxCaptureResultCallbackMs': maxCaptureResultCallbackMs,
      'averageCaptureAcquireWaitMs': averageCaptureAcquireWaitMs,
      'maxCaptureAcquireWaitMs': maxCaptureAcquireWaitMs,
      'averagePostCallbackWaitMs': averagePostCallbackWaitMs,
      'maxPostCallbackWaitMs': maxPostCallbackWaitMs,
      'averageUnaccountedWaitMs': averageUnaccountedWaitMs,
      'maxUnaccountedWaitMs': maxUnaccountedWaitMs,
      'captureResultCallbackCount': captureResultCallbackCount,
      'maxFrameIntervalMs': maxFrameIntervalMs,
      'p95FrameIntervalMs': p95FrameIntervalMs,
      'captureWaitTimeoutCount': captureWaitTimeoutCount,
      'capturePermanentErrorCount': capturePermanentErrorCount,
      'duplicatedFrameCount': duplicatedFrameCount,
      'staleFrameReuseCount': staleFrameReuseCount,
      'averageFrameConvertMs': averageFrameConvertMs,
      'averageFrameScaleMs': averageFrameScaleMs,
      'averageFrameOnFrameMs': averageFrameOnFrameMs,
      'averageFrameCallbackMs': averageFrameCallbackMs,
      'maxFrameCallbackMs': maxFrameCallbackMs,
      'updatedRegionEmptyCount': updatedRegionEmptyCount,
      'updatedRegionNonEmptyCount': updatedRegionNonEmptyCount,
      'updatedRegionRectCount': updatedRegionRectCount,
      'updatedRegionMaxRectCount': updatedRegionMaxRectCount,
      'averageUpdatedRegionAreaRatio': averageUpdatedRegionAreaRatio,
      'maxUpdatedRegionAreaRatio': maxUpdatedRegionAreaRatio,
      'averageUpdatedRegionAnalysisMs': averageUpdatedRegionAnalysisMs,
      'maxUpdatedRegionAnalysisMs': maxUpdatedRegionAnalysisMs,
      'updatedRegionFullFrameCount': updatedRegionFullFrameCount,
      'updatedRegionTinyFrameCount': updatedRegionTinyFrameCount,
      'latestFramePacerEnabled': latestFramePacerEnabled,
      'averagePacerSubmittedFps': averagePacerSubmittedFps,
      'averagePacerUniqueFps': averagePacerUniqueFps,
      'p95PacerIntervalMs': p95PacerIntervalMs,
      'maxPacerIntervalMs': maxPacerIntervalMs,
      'averagePacerFrameAgeMs': averagePacerFrameAgeMs,
      'maxPacerFrameAgeMs': maxPacerFrameAgeMs,
      'averagePacerOnFrameMs': averagePacerOnFrameMs,
      'maxPacerOnFrameMs': maxPacerOnFrameMs,
      'pacerDuplicateSubmitCount': pacerDuplicateSubmitCount,
      'pacerOverwrittenFrameCount': pacerOverwrittenFrameCount,
      'pacerSkippedTickCount': pacerSkippedTickCount,
      'gameCaptureSourceWidth': gameCaptureSourceWidth,
      'gameCaptureSourceHeight': gameCaptureSourceHeight,
      'gameCaptureOutputWidth': gameCaptureOutputWidth,
      'gameCaptureOutputHeight': gameCaptureOutputHeight,
      'gameCaptureFormat': gameCaptureFormat,
      'gameCaptureBackendContractVersion': gameCaptureBackendContractVersion,
      'gameCaptureSourceMode': gameCaptureSourceMode,
      'gameCaptureSourceApi': gameCaptureSourceApi,
      'gameCaptureSourceApiId': gameCaptureSourceApiId,
      'gameCaptureSourceFormat': gameCaptureSourceFormat,
      'gameCaptureSourceFormatId': gameCaptureSourceFormatId,
      'gameCaptureColorSpace': gameCaptureColorSpace,
      'gameCaptureSyncKind': gameCaptureSyncKind,
      'gameCaptureReadyState': gameCaptureReadyState,
      'gameCaptureFailureReason': gameCaptureFailureReason,
      'gameCaptureNativeAdmissionStrictDeadlineEnabled':
          gameCaptureNativeAdmissionStrictDeadlineEnabled,
      'gameCaptureNativeAdmissionSourceDrivenFreshDueFrames':
          gameCaptureNativeAdmissionSourceDrivenFreshDueFrames,
      'gameCaptureNativeAdmissionSourceQpcDueFrames':
          gameCaptureNativeAdmissionSourceQpcDueFrames,
      'gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames':
          gameCaptureNativeAdmissionEarlySourceDueSuppressedFrames,
      'gameCaptureNativeAdmissionDeadlineDueFrames':
          gameCaptureNativeAdmissionDeadlineDueFrames,
      'averageGameCaptureNativeAdmissionDeadlineLatenessMs':
          averageGameCaptureNativeAdmissionDeadlineLatenessMs,
      'maxGameCaptureNativeAdmissionDeadlineLatenessMs':
          maxGameCaptureNativeAdmissionDeadlineLatenessMs,
      'gameCaptureNativeAdmissionDeadlineLatenessSamples':
          gameCaptureNativeAdmissionDeadlineLatenessSamples,
      'gameCaptureNativeAdmissionDeadlineOver1xFrames':
          gameCaptureNativeAdmissionDeadlineOver1xFrames,
      'gameCaptureNativeAdmissionDeadlineOver2xFrames':
          gameCaptureNativeAdmissionDeadlineOver2xFrames,
      'gameCaptureNativeAdmissionDeadlineOver3xFrames':
          gameCaptureNativeAdmissionDeadlineOver3xFrames,
      'gameCaptureNativeAdmissionNoSourceOnDeadlineFrames':
          gameCaptureNativeAdmissionNoSourceOnDeadlineFrames,
      'gameCaptureNativeAdmissionRepeatedOnDeadlineFrames':
          gameCaptureNativeAdmissionRepeatedOnDeadlineFrames,
      'gameCaptureNativeAdmissionSubmitOnDeadlineFrames':
          gameCaptureNativeAdmissionSubmitOnDeadlineFrames,
      'gameCaptureNativeAdmissionSubmitOnEarlySourceFrames':
          gameCaptureNativeAdmissionSubmitOnEarlySourceFrames,
      'gameCaptureNativeNv12PendingOnDeadlineFrames':
          gameCaptureNativeNv12PendingOnDeadlineFrames,
      'gameCaptureNativeNv12NoPendingOnDeadlineFrames':
          gameCaptureNativeNv12NoPendingOnDeadlineFrames,
      'gameCaptureNativeNv12ReadyOnDeadlineFrames':
          gameCaptureNativeNv12ReadyOnDeadlineFrames,
      'gameCaptureNativeNv12NoReadyOnDeadlineFrames':
          gameCaptureNativeNv12NoReadyOnDeadlineFrames,
      'gameCaptureConsumerAdapterLuid': gameCaptureConsumerAdapterLuid,
      'gameCaptureConsumerAdapterVendorId': gameCaptureConsumerAdapterVendorId,
      'gameCaptureConsumerAdapterDeviceId': gameCaptureConsumerAdapterDeviceId,
      'gameCaptureSourceAdapterLuid': gameCaptureSourceAdapterLuid,
      'gameCaptureCrossAdapterSuspected': gameCaptureCrossAdapterSuspected,
      'averageGameCaptureFps': averageGameCaptureFps,
      'gameCaptureSubmittedFrames': gameCaptureSubmittedFrames,
      'gameCaptureRepeatedFrames': gameCaptureRepeatedFrames,
      'gameCaptureDuplicateSkippedFrames': gameCaptureDuplicateSkippedFrames,
      'gameCaptureDeliveryQueuedFrames': gameCaptureDeliveryQueuedFrames,
      'gameCaptureDeliverySubmittedFrames': gameCaptureDeliverySubmittedFrames,
      'gameCaptureDeliveryOverwrittenFrames':
          gameCaptureDeliveryOverwrittenFrames,
      'gameCaptureDeliveryPacerResyncs': gameCaptureDeliveryPacerResyncs,
      'gameCaptureDeliveryPacerLagMaxMs': gameCaptureDeliveryPacerLagMaxMs,
      'gameCaptureDeliveryRepeatNoQueuedFrames':
          gameCaptureDeliveryRepeatNoQueuedFrames,
      'gameCaptureDeliverySkipNoQueuedFrames':
          gameCaptureDeliverySkipNoQueuedFrames,
      'gameCaptureDeliveryFreshWakeAfterSkipFrames':
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
      'gameCaptureDeliveryFreshImmediateFrames':
          gameCaptureDeliveryFreshImmediateFrames,
      'gameCaptureDeliveryRepeatPolicy': gameCaptureDeliveryRepeatPolicy,
      'gameCaptureDeliveryQueueDepth': gameCaptureDeliveryQueueDepth,
      'averageGameCaptureDeliveryRepeatSourceAgeMs':
          averageGameCaptureDeliveryRepeatSourceAgeMs,
      'maxGameCaptureDeliveryRepeatSourceAgeMs':
          maxGameCaptureDeliveryRepeatSourceAgeMs,
      'gameCaptureDeliveryRepeatSourceAgeSamples':
          gameCaptureDeliveryRepeatSourceAgeSamples,
      'averageGameCaptureDeliveryOnFrameMs':
          averageGameCaptureDeliveryOnFrameMs,
      'maxGameCaptureDeliveryOnFrameMs': maxGameCaptureDeliveryOnFrameMs,
      'averageGameCaptureDeliverySubmitPrepMs':
          averageGameCaptureDeliverySubmitPrepMs,
      'maxGameCaptureDeliverySubmitPrepMs': maxGameCaptureDeliverySubmitPrepMs,
      'gameCaptureDeliverySubmitPrepSamples':
          gameCaptureDeliverySubmitPrepSamples,
      'averageGameCaptureDeliveryOnFrameCallMs':
          averageGameCaptureDeliveryOnFrameCallMs,
      'maxGameCaptureDeliveryOnFrameCallMs':
          maxGameCaptureDeliveryOnFrameCallMs,
      'gameCaptureDeliveryOnFrameCallSamples':
          gameCaptureDeliveryOnFrameCallSamples,
      'averageGameCaptureDeliveryPostOnFrameMs':
          averageGameCaptureDeliveryPostOnFrameMs,
      'maxGameCaptureDeliveryPostOnFrameMs':
          maxGameCaptureDeliveryPostOnFrameMs,
      'gameCaptureDeliveryPostOnFrameSamples':
          gameCaptureDeliveryPostOnFrameSamples,
      'averageGameCaptureNativeBufferReleaseMs':
          averageGameCaptureNativeBufferReleaseMs,
      'maxGameCaptureNativeBufferReleaseMs':
          maxGameCaptureNativeBufferReleaseMs,
      'gameCaptureNativeBufferReleaseSamples':
          gameCaptureNativeBufferReleaseSamples,
      'averageGameCaptureReadyToQueueMs': averageGameCaptureReadyToQueueMs,
      'maxGameCaptureReadyToQueueMs': maxGameCaptureReadyToQueueMs,
      'gameCaptureReadyToQueueSamples': gameCaptureReadyToQueueSamples,
      'averageGameCaptureDeliveryQueueWaitMs':
          averageGameCaptureDeliveryQueueWaitMs,
      'maxGameCaptureDeliveryQueueWaitMs': maxGameCaptureDeliveryQueueWaitMs,
      'gameCaptureDeliveryQueueWaitSamples':
          gameCaptureDeliveryQueueWaitSamples,
      'averageGameCaptureDeliveryOverwriteAgeMs':
          averageGameCaptureDeliveryOverwriteAgeMs,
      'maxGameCaptureDeliveryOverwriteAgeMs':
          maxGameCaptureDeliveryOverwriteAgeMs,
      'gameCaptureDeliveryOverwriteAgeSamples':
          gameCaptureDeliveryOverwriteAgeSamples,
      'gameCaptureDeliveryOverwrittenFreshFrames':
          gameCaptureDeliveryOverwrittenFreshFrames,
      'averageGameCaptureReadyToSubmitMs': averageGameCaptureReadyToSubmitMs,
      'maxGameCaptureReadyToSubmitMs': maxGameCaptureReadyToSubmitMs,
      'gameCaptureReadyToSubmitSamples': gameCaptureReadyToSubmitSamples,
      'averageGameCaptureSourceToSubmitMs': averageGameCaptureSourceToSubmitMs,
      'maxGameCaptureSourceToSubmitMs': maxGameCaptureSourceToSubmitMs,
      'gameCaptureSourceToSubmitSamples': gameCaptureSourceToSubmitSamples,
      'averageGameCaptureSourceToReadbackReadyMs':
          averageGameCaptureSourceToReadbackReadyMs,
      'maxGameCaptureSourceToReadbackReadyMs':
          maxGameCaptureSourceToReadbackReadyMs,
      'gameCaptureSourceToReadbackReadySamples':
          gameCaptureSourceToReadbackReadySamples,
      'averageGameCaptureReadbackQueueToMapMs':
          averageGameCaptureReadbackQueueToMapMs,
      'maxGameCaptureReadbackQueueToMapMs': maxGameCaptureReadbackQueueToMapMs,
      'gameCaptureReadbackQueueToMapSamples':
          gameCaptureReadbackQueueToMapSamples,
      'averageGameCaptureMapToI420Ms': averageGameCaptureMapToI420Ms,
      'maxGameCaptureMapToI420Ms': maxGameCaptureMapToI420Ms,
      'gameCaptureMapToI420Samples': gameCaptureMapToI420Samples,
      'averageGameCaptureSourceToI420ReadyMs':
          averageGameCaptureSourceToI420ReadyMs,
      'maxGameCaptureSourceToI420ReadyMs': maxGameCaptureSourceToI420ReadyMs,
      'gameCaptureSourceToI420ReadySamples':
          gameCaptureSourceToI420ReadySamples,
      'averageGameCaptureSourceToQueueMs': averageGameCaptureSourceToQueueMs,
      'maxGameCaptureSourceToQueueMs': maxGameCaptureSourceToQueueMs,
      'gameCaptureSourceToQueueSamples': gameCaptureSourceToQueueSamples,
      'averageGameCaptureSourceDuplicateSkipAgeMs':
          averageGameCaptureSourceDuplicateSkipAgeMs,
      'maxGameCaptureSourceDuplicateSkipAgeMs':
          maxGameCaptureSourceDuplicateSkipAgeMs,
      'gameCaptureSourceDuplicateSkipAgeSamples':
          gameCaptureSourceDuplicateSkipAgeSamples,
      'gameCaptureCopiedFrames': gameCaptureCopiedFrames,
      'gameCaptureDroppedFrames': gameCaptureDroppedFrames,
      'gameCaptureOverwrittenFrames': gameCaptureOverwrittenFrames,
      'gameCaptureGpuScaledFrames': gameCaptureGpuScaledFrames,
      'gameCaptureGpuScaleFailures': gameCaptureGpuScaleFailures,
      'gameCaptureCpuFallbackFrames': gameCaptureCpuFallbackFrames,
      'gameCaptureNativeNv12SubmittedFrames':
          gameCaptureNativeNv12SubmittedFrames,
      'gameCaptureNativeNv12QueuedFrames': gameCaptureNativeNv12QueuedFrames,
      'gameCaptureNativeNv12ReadyFrames': gameCaptureNativeNv12ReadyFrames,
      'gameCaptureNativeNv12NotReadyPolls': gameCaptureNativeNv12NotReadyPolls,
      'gameCaptureNativeNv12ReadyPolicy': gameCaptureNativeNv12ReadyPolicy,
      'gameCaptureNativeNv12FenceAvailable':
          gameCaptureNativeNv12FenceAvailable,
      'gameCaptureNativeNv12PendingPollMs': gameCaptureNativeNv12PendingPollMs,
      'gameCaptureNativeNv12MaxPendingSlots':
          gameCaptureNativeNv12MaxPendingSlots,
      'gameCaptureNativeNv12ReadyDrainDepth':
          gameCaptureNativeNv12ReadyDrainDepth,
      'gameCaptureNativeNv12FrameOwnership':
          gameCaptureNativeNv12FrameOwnership,
      'gameCaptureNativeNv12WarmupI420Frames':
          gameCaptureNativeNv12WarmupI420Frames,
      'gameCaptureNativeNv12SingleInFlightEnabled':
          gameCaptureNativeNv12SingleInFlightEnabled,
      'gameCaptureNativeNv12GpuQueueBackoffEnabled':
          gameCaptureNativeNv12GpuQueueBackoffEnabled,
      'gameCaptureNativeNv12GpuQueueBackoffThresholdFrames':
          gameCaptureNativeNv12GpuQueueBackoffThresholdFrames,
      'gameCaptureNativeNv12GpuQueueBackoffDurationFrames':
          gameCaptureNativeNv12GpuQueueBackoffDurationFrames,
      'gameCaptureNativeNv12FenceSignaledFrames':
          gameCaptureNativeNv12FenceSignaledFrames,
      'gameCaptureNativeNv12FenceReadyFrames':
          gameCaptureNativeNv12FenceReadyFrames,
      'gameCaptureNativeNv12FenceSignalFailures':
          gameCaptureNativeNv12FenceSignalFailures,
      'gameCaptureNativeNv12OwnedCopies': gameCaptureNativeNv12OwnedCopies,
      'averageGameCaptureNativeNv12OwnedCopyMs':
          averageGameCaptureNativeNv12OwnedCopyMs,
      'maxGameCaptureNativeNv12OwnedCopyMs':
          maxGameCaptureNativeNv12OwnedCopyMs,
      'gameCaptureNativeNv12OwnedCopySamples':
          gameCaptureNativeNv12OwnedCopySamples,
      'gameCaptureNativeNv12OverwrittenFrames':
          gameCaptureNativeNv12OverwrittenFrames,
      'averageGameCaptureNativeNv12OverwriteAgeMs':
          averageGameCaptureNativeNv12OverwriteAgeMs,
      'maxGameCaptureNativeNv12OverwriteAgeMs':
          maxGameCaptureNativeNv12OverwriteAgeMs,
      'gameCaptureNativeNv12OverwriteAgeSamples':
          gameCaptureNativeNv12OverwriteAgeSamples,
      'gameCaptureNativeNv12OverwrittenFreshFrames':
          gameCaptureNativeNv12OverwrittenFreshFrames,
      'gameCaptureNativeNv12ReadyDroppedFrames':
          gameCaptureNativeNv12ReadyDroppedFrames,
      'averageGameCaptureNativeNv12ReadyDropAgeMs':
          averageGameCaptureNativeNv12ReadyDropAgeMs,
      'maxGameCaptureNativeNv12ReadyDropAgeMs':
          maxGameCaptureNativeNv12ReadyDropAgeMs,
      'gameCaptureNativeNv12ReadyDropAgeSamples':
          gameCaptureNativeNv12ReadyDropAgeSamples,
      'gameCaptureNativeNv12ReadyDroppedFreshFrames':
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
      'gameCaptureNativeNv12LateReadyDropEnabled':
          gameCaptureNativeNv12LateReadyDropEnabled,
      'gameCaptureNativeNv12LateReadyDropThresholdMs':
          gameCaptureNativeNv12LateReadyDropThresholdMs,
      'gameCaptureNativeNv12LateReadyDroppedFrames':
          gameCaptureNativeNv12LateReadyDroppedFrames,
      'averageGameCaptureNativeNv12LateReadyDropAgeMs':
          averageGameCaptureNativeNv12LateReadyDropAgeMs,
      'maxGameCaptureNativeNv12LateReadyDropAgeMs':
          maxGameCaptureNativeNv12LateReadyDropAgeMs,
      'gameCaptureNativeNv12LateReadyDropAgeSamples':
          gameCaptureNativeNv12LateReadyDropAgeSamples,
      'gameCaptureNativeNv12LateReadyDroppedFreshFrames':
          gameCaptureNativeNv12LateReadyDroppedFreshFrames,
      'averageGameCaptureNativeNv12LateReadyDropBltToReadyMs':
          averageGameCaptureNativeNv12LateReadyDropBltToReadyMs,
      'maxGameCaptureNativeNv12LateReadyDropBltToReadyMs':
          maxGameCaptureNativeNv12LateReadyDropBltToReadyMs,
      'gameCaptureNativeNv12LateReadyDropBltToReadySamples':
          gameCaptureNativeNv12LateReadyDropBltToReadySamples,
      'gameCaptureNativeNv12Failures': gameCaptureNativeNv12Failures,
      'averageGameCaptureNativeNv12ConvertMs':
          averageGameCaptureNativeNv12ConvertMs,
      'maxGameCaptureNativeNv12ConvertMs': maxGameCaptureNativeNv12ConvertMs,
      'gameCaptureNativeNv12ConvertSamples':
          gameCaptureNativeNv12ConvertSamples,
      'averageGameCaptureNativeNv12BgraScaleDrawMs':
          averageGameCaptureNativeNv12BgraScaleDrawMs,
      'maxGameCaptureNativeNv12BgraScaleDrawMs':
          maxGameCaptureNativeNv12BgraScaleDrawMs,
      'gameCaptureNativeNv12BgraScaleDrawSamples':
          gameCaptureNativeNv12BgraScaleDrawSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltSubmitMs':
          averageGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      'maxGameCaptureNativeNv12VideoProcessorBltSubmitMs':
          maxGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      'gameCaptureNativeNv12VideoProcessorBltSubmitSamples':
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs':
          averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
      'maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs':
          maxGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
      'gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples':
          gameCaptureNativeNv12VideoProcessorBltCpuSubmitSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltToReadyMs':
          averageGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      'maxGameCaptureNativeNv12VideoProcessorBltToReadyMs':
          maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      'gameCaptureNativeNv12VideoProcessorBltToReadySamples':
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
      'averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs':
          averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
      'maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs':
          maxGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
      'gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples':
          gameCaptureNativeNv12VideoProcessorBltSubmitToFenceSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs':
          averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
      'maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs':
          maxGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
      'gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples':
          gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs':
          averageGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
      'maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs':
          maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
      'gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples':
          gameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples,
      'gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures':
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures,
      'gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady':
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady,
      'gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint':
          gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint,
      'gameCaptureNativeNv12ReadyObservedImmediateFrames':
          gameCaptureNativeNv12ReadyObservedImmediateFrames,
      'gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames':
          gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames,
      'gameCaptureNativeNv12ReadyObservedFenceEventFrames':
          gameCaptureNativeNv12ReadyObservedFenceEventFrames,
      'gameCaptureNativeNv12ReadyObservedSourceEventFrames':
          gameCaptureNativeNv12ReadyObservedSourceEventFrames,
      'gameCaptureNativeNv12ReadyObservedWaitOtherFrames':
          gameCaptureNativeNv12ReadyObservedWaitOtherFrames,
      'gameCaptureNativeNv12ReadyObservedLoopIdleFrames':
          gameCaptureNativeNv12ReadyObservedLoopIdleFrames,
      'gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames':
          gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames,
      'gameCaptureNativeNv12ReadyObservedPreSubmitFrames':
          gameCaptureNativeNv12ReadyObservedPreSubmitFrames,
      'gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames':
          gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames,
      'gameCaptureNativeNv12ReadyObservedUnknownFrames':
          gameCaptureNativeNv12ReadyObservedUnknownFrames,
      'gameCaptureNativeNv12BltToReadyOver1xFrames':
          gameCaptureNativeNv12BltToReadyOver1xFrames,
      'gameCaptureNativeNv12BltToReadyOver2xFrames':
          gameCaptureNativeNv12BltToReadyOver2xFrames,
      'gameCaptureNativeNv12BltToReadyOver3xFrames':
          gameCaptureNativeNv12BltToReadyOver3xFrames,
      'averageGameCaptureNativeNv12BufferCreateMs':
          averageGameCaptureNativeNv12BufferCreateMs,
      'maxGameCaptureNativeNv12BufferCreateMs':
          maxGameCaptureNativeNv12BufferCreateMs,
      'gameCaptureNativeNv12BufferCreateSamples':
          gameCaptureNativeNv12BufferCreateSamples,
      'averageGameCaptureNativeNv12FrameReadyToQueueMs':
          averageGameCaptureNativeNv12FrameReadyToQueueMs,
      'maxGameCaptureNativeNv12FrameReadyToQueueMs':
          maxGameCaptureNativeNv12FrameReadyToQueueMs,
      'gameCaptureNativeNv12FrameReadyToQueueSamples':
          gameCaptureNativeNv12FrameReadyToQueueSamples,
      'averageGameCaptureNativeNv12ConversionStartAgeMs':
          averageGameCaptureNativeNv12ConversionStartAgeMs,
      'maxGameCaptureNativeNv12ConversionStartAgeMs':
          maxGameCaptureNativeNv12ConversionStartAgeMs,
      'gameCaptureNativeNv12ConversionStartAgeSamples':
          gameCaptureNativeNv12ConversionStartAgeSamples,
      'gameCaptureNativeNv12SingleInFlightDeferredFrames':
          gameCaptureNativeNv12SingleInFlightDeferredFrames,
      'gameCaptureNativeNv12SingleInFlightDeferredFreshFrames':
          gameCaptureNativeNv12SingleInFlightDeferredFreshFrames,
      'gameCaptureNativeNv12SingleInFlightPendingMax':
          gameCaptureNativeNv12SingleInFlightPendingMax,
      'averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs':
          averageGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs,
      'maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs':
          maxGameCaptureNativeNv12SingleInFlightDeferredSourceAgeMs,
      'gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples':
          gameCaptureNativeNv12SingleInFlightDeferredSourceAgeSamples,
      'gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames':
          gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames,
      'gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames':
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames,
      'gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames':
          gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames,
      'averageGameCaptureNativeNv12GpuQueueBackoffMs':
          averageGameCaptureNativeNv12GpuQueueBackoffMs,
      'maxGameCaptureNativeNv12GpuQueueBackoffMs':
          maxGameCaptureNativeNv12GpuQueueBackoffMs,
      'gameCaptureNativeNv12GpuQueueBackoffSamples':
          gameCaptureNativeNv12GpuQueueBackoffSamples,
      'averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs':
          averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
      'maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs':
          maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
      'gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples':
          gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples,
      'averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs':
          averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
      'maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs':
          maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
      'gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples':
          gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples,
      'gameCaptureNativeNv12AdmissionMailboxEnabled':
          gameCaptureNativeNv12AdmissionMailboxEnabled,
      'gameCaptureNativeNv12AdmissionMailboxPendingActive':
          gameCaptureNativeNv12AdmissionMailboxPendingActive,
      'gameCaptureNativeNv12AdmissionMailboxStoredFrames':
          gameCaptureNativeNv12AdmissionMailboxStoredFrames,
      'gameCaptureNativeNv12AdmissionMailboxReplacedFrames':
          gameCaptureNativeNv12AdmissionMailboxReplacedFrames,
      'gameCaptureNativeNv12AdmissionMailboxSubmittedFrames':
          gameCaptureNativeNv12AdmissionMailboxSubmittedFrames,
      'gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames':
          gameCaptureNativeNv12AdmissionMailboxStaleDroppedFrames,
      'averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs':
          averageGameCaptureNativeNv12AdmissionMailboxPendingAgeMs,
      'maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs':
          maxGameCaptureNativeNv12AdmissionMailboxPendingAgeMs,
      'gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples':
          gameCaptureNativeNv12AdmissionMailboxPendingAgeSamples,
      'averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs':
          averageGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs,
      'maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs':
          maxGameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeMs,
      'gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples':
          gameCaptureNativeNv12AdmissionMailboxSubmitSourceAgeSamples,
      'gameCaptureNativeNv12StaleBeforeQueueFrames':
          gameCaptureNativeNv12StaleBeforeQueueFrames,
      'gameCaptureNativeNv12HandoffDisabledReason':
          gameCaptureNativeNv12HandoffDisabledReason,
      'gameCaptureNativeNv12OnFrameBackpressureEnabled':
          gameCaptureNativeNv12OnFrameBackpressureEnabled,
      'gameCaptureNativeNv12OnFrameBackpressureThresholdMs':
          gameCaptureNativeNv12OnFrameBackpressureThresholdMs,
      'gameCaptureNativeNv12OnFrameBackpressureFrameLimit':
          gameCaptureNativeNv12OnFrameBackpressureFrameLimit,
      'gameCaptureNativeNv12OnFrameBackpressureFrames':
          gameCaptureNativeNv12OnFrameBackpressureFrames,
      'gameCaptureNativeNv12OnFrameBackpressureStreak':
          gameCaptureNativeNv12OnFrameBackpressureStreak,
      'gameCaptureNativeNv12OnFrameBackpressureMaxMs':
          gameCaptureNativeNv12OnFrameBackpressureMaxMs,
      'gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure':
          gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure,
      'gameCaptureGpuHandoffUnproven': gameCaptureGpuHandoffUnproven,
      'gameCaptureReadbackQueuedFrames': gameCaptureReadbackQueuedFrames,
      'gameCaptureReadbackReadyFrames': gameCaptureReadbackReadyFrames,
      'gameCaptureReadbackNotReadyFrames': gameCaptureReadbackNotReadyFrames,
      'gameCaptureReadbackOverwrittenFrames':
          gameCaptureReadbackOverwrittenFrames,
      'gameCaptureReadbackStaleDroppedFrames':
          gameCaptureReadbackStaleDroppedFrames,
      'gameCaptureReadbackLatencyDroppedFrames':
          gameCaptureReadbackLatencyDroppedFrames,
      'gameCaptureReadbackMapAttempts': gameCaptureReadbackMapAttempts,
      'gameCaptureSourceFrameIndex': gameCaptureSourceFrameIndex,
      'gameCaptureLastSubmittedSourceFrameIndex':
          gameCaptureLastSubmittedSourceFrameIndex,
      'gameCaptureSourceFrameRegressions': gameCaptureSourceFrameRegressions,
      'gameCaptureSourceFrameDuplicates': gameCaptureSourceFrameDuplicates,
      'gameCaptureSourceFrameGaps': gameCaptureSourceFrameGaps,
      'gameCaptureSharedSlotMismatches': gameCaptureSharedSlotMismatches,
      'gameCaptureTimestampMode': gameCaptureTimestampMode,
      'gameCaptureTimestampSourceQpcFrames':
          gameCaptureTimestampSourceQpcFrames,
      'gameCaptureTimestampPacedFallbackFrames':
          gameCaptureTimestampPacedFallbackFrames,
      'gameCaptureTimestampRepeatedFrames': gameCaptureTimestampRepeatedFrames,
      'averageGameCaptureTimestampDeltaMs': averageGameCaptureTimestampDeltaMs,
      'maxGameCaptureTimestampDeltaMs': maxGameCaptureTimestampDeltaMs,
      'gameCaptureTimestampSamples': gameCaptureTimestampSamples,
      'gameCaptureTimestampAdjustments': gameCaptureTimestampAdjustments,
      'averageGameCaptureDeliveryWallDeltaMs':
          averageGameCaptureDeliveryWallDeltaMs,
      'maxGameCaptureDeliveryWallDeltaMs': maxGameCaptureDeliveryWallDeltaMs,
      'minGameCaptureDeliveryWallDeltaMs': minGameCaptureDeliveryWallDeltaMs,
      'gameCaptureDeliveryWallSamples': gameCaptureDeliveryWallSamples,
      'gameCaptureDeliveryWallOver2xFrames':
          gameCaptureDeliveryWallOver2xFrames,
      'gameCaptureDeliveryWallOver3xFrames':
          gameCaptureDeliveryWallOver3xFrames,
      'gameCaptureDeliveryWallUnderHalfFrames':
          gameCaptureDeliveryWallUnderHalfFrames,
      'averageGameCaptureSourceQpcDeltaMs': averageGameCaptureSourceQpcDeltaMs,
      'maxGameCaptureSourceQpcDeltaMs': maxGameCaptureSourceQpcDeltaMs,
      'gameCaptureSourceQpcSamples': gameCaptureSourceQpcSamples,
      'gameCaptureSourceQpcRegressions': gameCaptureSourceQpcRegressions,
      'gameCaptureSourceQpcOver2xFrames': gameCaptureSourceQpcOver2xFrames,
      'gameCaptureSourceQpcOver3xFrames': gameCaptureSourceQpcOver3xFrames,
      'gameCaptureSourceQpcUnderHalfFrames':
          gameCaptureSourceQpcUnderHalfFrames,
      'gameCaptureSourceLatestObservedFrames':
          gameCaptureSourceLatestObservedFrames,
      'gameCaptureSourceLatestFrameGaps': gameCaptureSourceLatestFrameGaps,
      'gameCaptureSourceLatestFrameRegressions':
          gameCaptureSourceLatestFrameRegressions,
      'averageGameCaptureSourceLatestQpcDeltaMs':
          averageGameCaptureSourceLatestQpcDeltaMs,
      'maxGameCaptureSourceLatestQpcDeltaMs':
          maxGameCaptureSourceLatestQpcDeltaMs,
      'gameCaptureSourceLatestQpcSamples': gameCaptureSourceLatestQpcSamples,
      'gameCaptureSourceLatestQpcRegressions':
          gameCaptureSourceLatestQpcRegressions,
      'gameCaptureSourceLatestQpcOver2xFrames':
          gameCaptureSourceLatestQpcOver2xFrames,
      'gameCaptureSourceLatestQpcOver3xFrames':
          gameCaptureSourceLatestQpcOver3xFrames,
      'gameCaptureSourceLatestQpcUnderHalfFrames':
          gameCaptureSourceLatestQpcUnderHalfFrames,
      'averageGameCaptureSourceLatestObservationDeltaMs':
          averageGameCaptureSourceLatestObservationDeltaMs,
      'maxGameCaptureSourceLatestObservationDeltaMs':
          maxGameCaptureSourceLatestObservationDeltaMs,
      'gameCaptureSourceLatestObservationSamples':
          gameCaptureSourceLatestObservationSamples,
      'gameCaptureSourceLatestObservationOver2xFrames':
          gameCaptureSourceLatestObservationOver2xFrames,
      'gameCaptureSourceLatestObservationOver3xFrames':
          gameCaptureSourceLatestObservationOver3xFrames,
      'averageGameCaptureSourceLatestEventAgeMs':
          averageGameCaptureSourceLatestEventAgeMs,
      'maxGameCaptureSourceLatestEventAgeMs':
          maxGameCaptureSourceLatestEventAgeMs,
      'gameCaptureSourceLatestEventAgeSamples':
          gameCaptureSourceLatestEventAgeSamples,
      'gameCaptureSourceLatestEventAgeOver1xFrames':
          gameCaptureSourceLatestEventAgeOver1xFrames,
      'gameCaptureSourceLatestEventAgeOver2xFrames':
          gameCaptureSourceLatestEventAgeOver2xFrames,
      'gameCaptureSourceLatestEventAgeOver3xFrames':
          gameCaptureSourceLatestEventAgeOver3xFrames,
      'averageGameCaptureSourcePublishObservationAgeMs':
          averageGameCaptureSourcePublishObservationAgeMs,
      'maxGameCaptureSourcePublishObservationAgeMs':
          maxGameCaptureSourcePublishObservationAgeMs,
      'gameCaptureSourcePublishObservationAgeSamples':
          gameCaptureSourcePublishObservationAgeSamples,
      'gameCaptureSourcePublishObservationAgeOver1xFrames':
          gameCaptureSourcePublishObservationAgeOver1xFrames,
      'gameCaptureSourcePublishObservationAgeOver2xFrames':
          gameCaptureSourcePublishObservationAgeOver2xFrames,
      'gameCaptureSourcePublishObservationAgeOver3xFrames':
          gameCaptureSourcePublishObservationAgeOver3xFrames,
      'averageGameCaptureProducerPresentGapMs':
          averageGameCaptureProducerPresentGapMs,
      'maxGameCaptureProducerPresentGapMs': maxGameCaptureProducerPresentGapMs,
      'gameCaptureProducerPresentGapSamples':
          gameCaptureProducerPresentGapSamples,
      'averageGameCaptureProducerCaptureGapMs':
          averageGameCaptureProducerCaptureGapMs,
      'maxGameCaptureProducerCaptureGapMs': maxGameCaptureProducerCaptureGapMs,
      'gameCaptureProducerCaptureGapSamples':
          gameCaptureProducerCaptureGapSamples,
      'averageGameCaptureProducerPresentToPublishMs':
          averageGameCaptureProducerPresentToPublishMs,
      'maxGameCaptureProducerPresentToPublishMs':
          maxGameCaptureProducerPresentToPublishMs,
      'gameCaptureProducerPresentToPublishSamples':
          gameCaptureProducerPresentToPublishSamples,
      'averageGameCaptureProducerCopyMs': averageGameCaptureProducerCopyMs,
      'maxGameCaptureProducerCopyMs': maxGameCaptureProducerCopyMs,
      'gameCaptureProducerCopySamples': gameCaptureProducerCopySamples,
      'averageGameCaptureProducerResolveMs':
          averageGameCaptureProducerResolveMs,
      'maxGameCaptureProducerResolveMs': maxGameCaptureProducerResolveMs,
      'gameCaptureProducerResolveSamples': gameCaptureProducerResolveSamples,
      'gameCaptureProducerThrottledFrames': gameCaptureProducerThrottledFrames,
      'averageGameCaptureCopyMs': averageGameCaptureCopyMs,
      'averageGameCaptureMapMs': averageGameCaptureMapMs,
      'averageGameCaptureConvertMs': averageGameCaptureConvertMs,
      'averageGameCaptureGpuScaleMs': averageGameCaptureGpuScaleMs,
      'averageGameCaptureReadbackLatencyMs':
          averageGameCaptureReadbackLatencyMs,
      'averageGameCaptureReadbackLatencyFrames':
          averageGameCaptureReadbackLatencyFrames,
      'gameCaptureMaxReadbackLatencyFrames':
          gameCaptureMaxReadbackLatencyFrames,
      'gameCaptureMapFailures': gameCaptureMapFailures,
      'gameCaptureConvertFailures': gameCaptureConvertFailures,
      'gameCaptureProofFrames': gameCaptureProofFrames,
      'gameCaptureVisibleProofFrames': gameCaptureVisibleProofFrames,
      'gameCaptureProofVisible': gameCaptureProofVisible,
      'gameCaptureProofPath': gameCaptureProofPath,
      'gameCaptureProofMinLuma': gameCaptureProofMinLuma,
      'gameCaptureProofMaxLuma': gameCaptureProofMaxLuma,
      'gameCaptureProofNonzeroSamples': gameCaptureProofNonzeroSamples,
      'gameCaptureProofSamples': gameCaptureProofSamples,
      'gameCaptureI420ProofFrames': gameCaptureI420ProofFrames,
      'gameCaptureVisibleI420ProofFrames': gameCaptureVisibleI420ProofFrames,
      'gameCaptureInitialBlackSkippedFrames':
          gameCaptureInitialBlackSkippedFrames,
      'gameCaptureVisibleSourceSeen': gameCaptureVisibleSourceSeen,
      'gameCaptureI420ProofVisible': gameCaptureI420ProofVisible,
      'gameCaptureI420ProofPath': gameCaptureI420ProofPath,
      'gameCaptureI420ProofMinLuma': gameCaptureI420ProofMinLuma,
      'gameCaptureI420ProofMaxLuma': gameCaptureI420ProofMaxLuma,
      'gameCaptureI420ProofNonzeroSamples': gameCaptureI420ProofNonzeroSamples,
      'gameCaptureI420ProofSamples': gameCaptureI420ProofSamples,
      'gameCaptureVisualFreshness': gameCaptureVisualFreshnessJson,
      'gameCaptureVisualFreshnessSampleMode':
          gameCaptureVisualFreshnessSampleMode,
      'gameCaptureVisualFreshnessSampleFrames':
          gameCaptureVisualFreshnessSampleFrames,
      'gameCaptureVisualFreshnessUniqueFrames':
          gameCaptureVisualFreshnessUniqueFrames,
      'averageGameCaptureVisualFreshnessUniqueFps':
          averageGameCaptureVisualFreshnessUniqueFps,
      'gameCaptureVisualFreshnessLongestStaleMs':
          gameCaptureVisualFreshnessLongestStaleMs,
      'gameCaptureVisualFreshnessLongestStaleFrames':
          gameCaptureVisualFreshnessLongestStaleFrames,
      'gameCaptureVisualFreshnessLowChangeFrames':
          gameCaptureVisualFreshnessLowChangeFrames,
      'gameCaptureVisualFreshnessArtifactSet':
          gameCaptureVisualFreshnessArtifactSet,
      'gameCaptureFrameSummary': gameCaptureFrameSummaryLabel,
      'averageEncoderTotalMs': averageEncoderTotalMs,
      'maxEncoderTotalMs': maxEncoderTotalMs,
      'encoderSlowFrameCount': encoderSlowFrameCount,
      'encoderSampleCount': encoderSampleCount,
      'encoderRateControlMode': encoderRateControlMode,
      'encoderTargetBitrateBps': encoderTargetBitrateBps,
      'encoderInputPaths': encoderInputPaths,
      'encoderInputPathLabel': encoderInputPathLabel,
      'encoderNativeInputFrames': encoderNativeInputFrames,
      'encoderCpuI420InputFrames': encoderCpuI420InputFrames,
      'encoderNativeSampleFailures': encoderNativeSampleFailures,
      'encoderNativeSuspendedFrames': encoderNativeSuspendedFrames,
      'encoderNativeReadyFenceFrames': encoderNativeReadyFenceFrames,
      'encoderNativeReadyFenceTimeoutFrames':
          encoderNativeReadyFenceTimeoutFrames,
      'averageEncoderNativeReadyFenceWaitMs':
          averageEncoderNativeReadyFenceWaitMs,
      'maxEncoderNativeReadyFenceWaitMs': maxEncoderNativeReadyFenceWaitMs,
      'encoderNativeReadyFenceWaitSamples': encoderNativeReadyFenceWaitSamples,
      'encoderNativeSourceMode': encoderNativeSourceMode,
      'encoderNativeSourceFormat': encoderNativeSourceFormat,
      'encoderNativeSourceFrameIndex': encoderNativeSourceFrameIndex,
      'averageEncoderNativeSourceAgeMs': averageEncoderNativeSourceAgeMs,
      'maxEncoderNativeSourceAgeMs': maxEncoderNativeSourceAgeMs,
      'encoderNativeSourceAgeSamples': encoderNativeSourceAgeSamples,
      'averageEncoderNativeSourceAgeAtCreateMs':
          averageEncoderNativeSourceAgeAtCreateMs,
      'maxEncoderNativeSourceAgeAtCreateMs':
          maxEncoderNativeSourceAgeAtCreateMs,
      'averageEncoderNativeBufferAgeMs': averageEncoderNativeBufferAgeMs,
      'maxEncoderNativeBufferAgeMs': maxEncoderNativeBufferAgeMs,
      'encoderNativeBufferAgeSamples': encoderNativeBufferAgeSamples,
      'averageEncoderNativeSampleLifetimeMs':
          averageEncoderNativeSampleLifetimeMs,
      'maxEncoderNativeSampleLifetimeMs': maxEncoderNativeSampleLifetimeMs,
      'encoderNativeSampleLifetimeSamples': encoderNativeSampleLifetimeSamples,
      'encoderNativeAdapterLuid': encoderNativeAdapterLuid,
      'encoderNativeAdapterVendorId': encoderNativeAdapterVendorId,
      'encoderNativeAdapterDeviceId': encoderNativeAdapterDeviceId,
      'averageEncoderProcessInputMs': averageEncoderProcessInputMs,
      'maxEncoderProcessInputMs': maxEncoderProcessInputMs,
      'encoderProcessInputSamples': encoderProcessInputSamples,
      'averageEncoderProcessOutputMs': averageEncoderProcessOutputMs,
      'maxEncoderProcessOutputMs': maxEncoderProcessOutputMs,
      'encoderProcessOutputSamples': encoderProcessOutputSamples,
      'averageEncoderEncodedCallbackMs': averageEncoderEncodedCallbackMs,
      'maxEncoderEncodedCallbackMs': maxEncoderEncodedCallbackMs,
      'encoderEncodedCallbackSamples': encoderEncodedCallbackSamples,
      'averageEncoderEncodedCallbackQueueWaitMs':
          averageEncoderEncodedCallbackQueueWaitMs,
      'maxEncoderEncodedCallbackQueueWaitMs':
          maxEncoderEncodedCallbackQueueWaitMs,
      'encoderEncodedCallbackQueueWaitSamples':
          encoderEncodedCallbackQueueWaitSamples,
      'averageEncoderEncodedCallbackEnqueueMs':
          averageEncoderEncodedCallbackEnqueueMs,
      'maxEncoderEncodedCallbackEnqueueMs': maxEncoderEncodedCallbackEnqueueMs,
      'encoderEncodedCallbackEnqueueSamples':
          encoderEncodedCallbackEnqueueSamples,
      'encoderEncodedCallbackAsyncFrames': encoderEncodedCallbackAsyncFrames,
      'encoderMaxEncodedCallbackQueueDepth':
          encoderMaxEncodedCallbackQueueDepth,
      'encoderMaxEncodedCallbackDrops': encoderMaxEncodedCallbackDrops,
      'encoderMaxEncodedCallbackOutputs': encoderMaxEncodedCallbackOutputs,
      'encoderStages': encoderStages,
      'encoderStageLabel': encoderStageLabel,
      'nativeEncoderFenceWaitMissing': nativeEncoderFenceWaitMissing,
      'encoderOutputFrames': encoderOutputFrames,
      'encoderOutputBytes': encoderOutputBytes,
      'encoderMaxQueueDepth': encoderMaxQueueDepth,
      'encoderMaxRetainedSamples': encoderMaxRetainedSamples,
      'encoderMaxEncodedOutputs': encoderMaxEncodedOutputs,
      'nativeEncoderHandoffNoOutput': nativeEncoderHandoffNoOutput,
      'webrtcRawSenderBoundary': {
        'available': hasWebrtcRawSenderBoundaryDiagnostics,
        'sourceOnFrame': {
          'averageMs': averageWebrtcSourceOnFrameMs,
          'maxMs': maxWebrtcSourceOnFrameMs,
          'samples': webrtcSourceOnFrameSamples,
          'averageAdaptMs': averageWebrtcSourceAdaptMs,
          'maxAdaptMs': maxWebrtcSourceAdaptMs,
          'averageScaleMs': averageWebrtcSourceScaleMs,
          'maxScaleMs': maxWebrtcSourceScaleMs,
          'averageBroadcastMs': averageWebrtcSourceBroadcastMs,
          'maxBroadcastMs': maxWebrtcSourceBroadcastMs,
          'adapterDrops': webrtcSourceAdapterDrops,
          'scaledFrames': webrtcSourceScaledFrames,
        },
        'videoBroadcaster': {
          'averageMs': averageWebrtcVideoBroadcasterMs,
          'maxMs': maxWebrtcVideoBroadcasterMs,
          'samples': webrtcVideoBroadcasterSamples,
          'averageLockWaitMs': averageWebrtcVideoBroadcasterLockWaitMs,
          'maxLockWaitMs': maxWebrtcVideoBroadcasterLockWaitMs,
          'averageSinkDispatchMs': averageWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSinkDispatchMs': maxWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSingleSinkMs': maxWebrtcVideoBroadcasterSingleSinkMs,
          'slowSinkId': webrtcVideoBroadcasterSlowSinkId,
          'slowSinkMs': webrtcVideoBroadcasterSlowSinkMs,
          'slowSinkLabel': webrtcVideoBroadcasterSlowSinkLabel,
          'slowestSinkId': webrtcVideoBroadcasterSlowestSinkId,
          'slowestSinkMs': webrtcVideoBroadcasterSlowestSinkMs,
          'slowestSinkAverageMs': webrtcVideoBroadcasterSlowestSinkAverageMs,
          'slowestSinkFrames': webrtcVideoBroadcasterSlowestSinkFrames,
          'slowestSinkLabel': webrtcVideoBroadcasterSlowestSinkLabel,
          'sinkCount': webrtcVideoBroadcasterSinkCount,
          'maxSinkCount': webrtcVideoBroadcasterMaxSinkCount,
          'activeSinks': webrtcVideoBroadcasterActiveSinks,
          'inactiveSinks': webrtcVideoBroadcasterInactiveSinks,
          'requestedSinks': webrtcVideoBroadcasterRequestedSinks,
          'blackFrameSinks': webrtcVideoBroadcasterBlackFrameSinks,
          'rotationAppliedSinks': webrtcVideoBroadcasterRotationAppliedSinks,
          'inactiveNativeSinkBypassReported':
              webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
          'inactiveNativeSinksBypassed':
              webrtcVideoBroadcasterInactiveNativeSinksBypassed,
          'inactiveNativeSinksBypassedLast':
              webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
          'inactiveNativeSinksRefreshed':
              webrtcVideoBroadcasterInactiveNativeSinksRefreshed,
          'inactiveNativeSinksRefreshedLast':
              webrtcVideoBroadcasterInactiveNativeSinksRefreshedLast,
          'sinkRoster': webrtcVideoBroadcasterSinkRoster,
          'blackSinks': webrtcVideoBroadcasterBlackSinks,
          'rotationDiscards': webrtcVideoBroadcasterRotationDiscards,
          'updateRectCleared': webrtcVideoBroadcasterUpdateRectCleared,
          'discardedFrames': webrtcVideoBroadcasterDiscardedFrames,
        },
        'videoStreamEncoder': {
          'averagePostToOnFrameMs': averageWebrtcVsePostToOnFrameMs,
          'maxPostToOnFrameMs': maxWebrtcVsePostToOnFrameMs,
          'averageOnFrameMs': averageWebrtcVseOnFrameMs,
          'maxOnFrameMs': maxWebrtcVseOnFrameMs,
          'onFrameSamples': webrtcVseOnFrameSamples,
          'queueOverloadDrops': webrtcVseQueueOverloadDrops,
          'encoderQueueDrops': webrtcVseEncoderQueueDrops,
          'cwndDrops': webrtcVseCwndDrops,
          'badTimestampDrops': webrtcVseBadTimestampDrops,
          'averageMaybeEncodeMs': averageWebrtcVseMaybeEncodeMs,
          'maxMaybeEncodeMs': maxWebrtcVseMaybeEncodeMs,
          'maybeEncodeSamples': webrtcVseMaybeEncodeSamples,
          'averageMaybePreEncodeMs': averageWebrtcVseMaybePreEncodeMs,
          'maxMaybePreEncodeMs': maxWebrtcVseMaybePreEncodeMs,
          'averageMaybeEncodeCallMs': averageWebrtcVseMaybeEncodeCallMs,
          'maxMaybeEncodeCallMs': maxWebrtcVseMaybeEncodeCallMs,
          'averageMaybeFrameSizeMs': averageWebrtcVseMaybeFrameSizeMs,
          'maxMaybeFrameSizeMs': maxWebrtcVseMaybeFrameSizeMs,
          'averageMaybeParameterUpdateMs':
              averageWebrtcVseMaybeParameterUpdateMs,
          'maxMaybeParameterUpdateMs': maxWebrtcVseMaybeParameterUpdateMs,
          'averageMaybeReconfigureMs': averageWebrtcVseMaybeReconfigureMs,
          'maxMaybeReconfigureMs': maxWebrtcVseMaybeReconfigureMs,
          'pendingReconfigureSignals': webrtcVsePendingReconfigureSignals,
          'pendingReconfigureConfigureEncoder':
              webrtcVsePendingReconfigureConfigureEncoder,
          'pendingReconfigureFrameInfoChange':
              webrtcVsePendingReconfigureFrameInfoChange,
          'pendingReconfigureSourceRestriction':
              webrtcVsePendingReconfigureSourceRestriction,
          'pendingReconfigureUnknown': webrtcVsePendingReconfigureUnknown,
          'pendingReconfigureLastReason': webrtcVsePendingReconfigureLastReason,
          'averageMaybeRateUpdateMs': averageWebrtcVseMaybeRateUpdateMs,
          'maxMaybeRateUpdateMs': maxWebrtcVseMaybeRateUpdateMs,
          'averageMaybeDropChecksMs': averageWebrtcVseMaybeDropChecksMs,
          'maxMaybeDropChecksMs': maxWebrtcVseMaybeDropChecksMs,
          'pendingReplacedDrops': webrtcVsePendingReplacedDrops,
          'sizeDrops': webrtcVseSizeDrops,
          'pausedDrops': webrtcVsePausedDrops,
          'mediaOptimizationDrops': webrtcVseMediaOptimizationDrops,
          'averageEncodeFrameMs': averageWebrtcVseEncodeFrameMs,
          'maxEncodeFrameMs': maxWebrtcVseEncodeFrameMs,
          'encodeFrameSamples': webrtcVseEncodeFrameSamples,
          'averageEncodePreEncoderMs': averageWebrtcVseEncodePreEncoderMs,
          'maxEncodePreEncoderMs': maxWebrtcVseEncodePreEncoderMs,
          'averageEncodeInfoMs': averageWebrtcVseEncodeInfoMs,
          'maxEncodeInfoMs': maxWebrtcVseEncodeInfoMs,
          'averageEncodeCropScaleMs': averageWebrtcVseEncodeCropScaleMs,
          'maxEncodeCropScaleMs': maxWebrtcVseEncodeCropScaleMs,
          'averageEncodeUpdateRectMs': averageWebrtcVseEncodeUpdateRectMs,
          'maxEncodeUpdateRectMs': maxWebrtcVseEncodeUpdateRectMs,
          'averageEncodeResourceMs': averageWebrtcVseEncodeResourceMs,
          'maxEncodeResourceMs': maxWebrtcVseEncodeResourceMs,
          'averageEncodeMetadataMs': averageWebrtcVseEncodeMetadataMs,
          'maxEncodeMetadataMs': maxWebrtcVseEncodeMetadataMs,
          'averageVideoEncoderEncodeMs': averageWebrtcVideoEncoderEncodeMs,
          'maxVideoEncoderEncodeMs': maxWebrtcVideoEncoderEncodeMs,
          'videoEncoderEncodeSamples': webrtcVideoEncoderEncodeSamples,
          'encodeFailures': webrtcVseEncodeFailures,
          'encodeSkippedBeforeEncoder': webrtcVseEncodeSkippedBeforeEncoder,
          'lineage': {
            'lineage_stage': webrtcFrameLineageStage,
            'frame_id': webrtcFrameLineageFrameId,
            'source_qpc': webrtcFrameLineageSourceQpc,
            'stage_qpc': webrtcFrameLineageStageQpc,
            'frame_age_ms': webrtcFrameLineageFrameAgeMs,
            'previous_frame_id': webrtcFrameLineagePreviousFrameId,
          },
          'activeProcessingSplit': {
            'task_posted_to_task_starts_ms':
                averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
            'task_posted_to_task_starts_max_ms':
                maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
            'task_starts_to_adaptation_complete_ms':
                averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
            'task_starts_to_adaptation_complete_max_ms':
                maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
            'adaptation_complete_to_vse_entry_ms': 0.0,
            'adaptation_complete_to_vse_entry_max_ms': 0.0,
            'vse_entry_to_encoder_task_posted_ms': 0.0,
            'vse_entry_to_encoder_task_posted_max_ms': 0.0,
            'encoder_task_posted_to_started_ms':
                averageWebrtcVsePostToOnFrameMs,
            'encoder_task_posted_to_started_max_ms':
                maxWebrtcVsePostToOnFrameMs,
            'encoder_task_starts_to_video_encoder_encode_entry_ms':
                averageWebrtcVseEncodePreEncoderMs,
            'encoder_task_starts_to_video_encoder_encode_entry_max_ms':
                maxWebrtcVseEncodePreEncoderMs,
            'encode_entry_to_encode_return_ms':
                averageWebrtcVideoEncoderEncodeMs,
            'encode_entry_to_encode_return_max_ms':
                maxWebrtcVideoEncoderEncodeMs,
          },
        },
        'frameCadenceQueue': {
          'averagePostDelayMs': averageWebrtcFrameCadenceQueuePostDelayMs,
          'maxPostDelayMs': maxWebrtcFrameCadenceQueuePostDelayMs,
          'frames': webrtcFrameCadenceQueueFrames,
          'overloadFrames': webrtcFrameCadenceQueueOverloadFrames,
          'postDelaySamples': webrtcFrameCadenceQueuePostDelaySamples,
          'maxScheduledForProcessing':
              webrtcFrameCadenceQueueMaxScheduledForProcessing,
          'lastScheduledForProcessing':
              webrtcFrameCadenceQueueLastScheduledForProcessing,
          'passthroughFrames': webrtcFrameCadenceQueuePassthroughFrames,
          'zeroHertzFrames': webrtcFrameCadenceQueueZeroHertzFrames,
          'vsyncFrames': webrtcFrameCadenceQueueVsyncFrames,
          'unknownFrames': webrtcFrameCadenceQueueUnknownFrames,
          'coalesceEnabledSeen': webrtcFrameCadenceQueueCoalesceEnabledSeen,
          'coalesceDisabledSeen': webrtcFrameCadenceQueueCoalesceDisabledSeen,
          'coalesceThreshold': webrtcFrameCadenceQueueCoalesceThreshold,
          'coalescedDrops': webrtcFrameCadenceQueueCoalescedDrops,
          'prepostCoalesceEnabledSeen':
              webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen,
          'prepostCoalesceDisabledSeen':
              webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen,
          'prepostCoalescedDrops': webrtcFrameCadenceQueuePrepostCoalescedDrops,
          'prepostProcessingDrops':
              webrtcFrameCadenceQueuePrepostProcessingDrops,
          'prepostMaxScheduledForProcessing':
              webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing,
          'lastMode': webrtcFrameCadenceQueueLastMode,
          'mailboxEnabledSeen': webrtcFrameCadenceQueueMailboxEnabledSeen,
          'mailboxFrames': webrtcFrameCadenceQueueMailboxFrames,
          'mailboxProcessedFrames':
              webrtcFrameCadenceQueueMailboxProcessedFrames,
          'mailboxReplacements': webrtcFrameCadenceQueueMailboxReplacements,
          'mailboxStaleDrops': webrtcFrameCadenceQueueMailboxStaleDrops,
          'mailboxProcessingActive':
              webrtcFrameCadenceQueueMailboxProcessingActive,
          'mailboxProcessingActiveSeen':
              webrtcFrameCadenceQueueMailboxProcessingActiveSeen,
          'active_processing': webrtcFrameCadenceQueueMailboxProcessingActive,
          'pending_replaced': webrtcFrameCadenceQueueMailboxReplacements,
          'pending_age_ms':
              averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
          'pending_age_max_ms':
              maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
          'stale_before_processing': webrtcFrameCadenceQueueMailboxStaleDrops,
          'processing_duration_ms':
              averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
          'processing_duration_max_ms':
              maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
          'active_frame_source_age_ms':
              averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
          'active_frame_source_age_max_ms':
              maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
          'mailboxPendingDepthMax':
              webrtcFrameCadenceQueueMailboxPendingDepthMax,
          'mailboxPendingDepthLast':
              webrtcFrameCadenceQueueMailboxPendingDepthLast,
          'averageMailboxPendingFrameAgeMs':
              averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
          'maxMailboxPendingFrameAgeMs':
              maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
          'mailboxPendingFrameAgeSamples':
              webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples,
          'averageMailboxProcessingFrameAgeMs':
              averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
          'maxMailboxProcessingFrameAgeMs':
              maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
          'mailboxProcessingFrameAgeSamples':
              webrtcFrameCadenceQueueMailboxProcessingFrameAgeSamples,
          'mailboxAdmissionDeadlineMisses':
              webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses,
          'averageMailboxEnqueueToProcessingStartMs':
              averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
          'maxMailboxEnqueueToProcessingStartMs':
              maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
          'mailboxEnqueueToProcessingStartSamples':
              webrtcFrameCadenceQueueMailboxEnqueueToProcessingStartSamples,
          'averageMailboxProcessingStartToVseMs':
              averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
          'maxMailboxProcessingStartToVseMs':
              maxWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
          'mailboxProcessingStartToVseSamples':
              webrtcFrameCadenceQueueMailboxProcessingStartToVseSamples,
          'averageMailboxVseCallMs':
              averageWebrtcFrameCadenceQueueMailboxVseCallMs,
          'maxMailboxVseCallMs': maxWebrtcFrameCadenceQueueMailboxVseCallMs,
          'mailboxVseCallSamples': webrtcFrameCadenceQueueMailboxVseCallSamples,
          'mailboxStaleDropThresholdMs':
              webrtcFrameCadenceQueueMailboxStaleDropThresholdMs,
        },
        'frameCadenceAdapter': {
          'averagePostDelayMs': averageWebrtcFrameCadencePostDelayMs,
          'maxPostDelayMs': maxWebrtcFrameCadencePostDelayMs,
          'averageCallbackMs': averageWebrtcFrameCadenceCallbackMs,
          'maxCallbackMs': maxWebrtcFrameCadenceCallbackMs,
          'averageFrameDurationMs': averageWebrtcFrameCadenceFrameDurationMs,
          'maxFrameDurationMs': maxWebrtcFrameCadenceFrameDurationMs,
          'sends': webrtcFrameCadenceSends,
          'repeatedSends': webrtcFrameCadenceRepeatedSends,
          'postDelaySamples': webrtcFrameCadencePostDelaySamples,
          'overFrameDurationSends': webrtcFrameCadenceOverFrameDurationSends,
          'overloadTriggerSends': webrtcFrameCadenceOverloadTriggerSends,
          'overloadActiveSends': webrtcFrameCadenceOverloadActiveSends,
          'overloadDecaySends': webrtcFrameCadenceOverloadDecaySends,
          'overloadEnabledSeen': webrtcFrameCadenceOverloadEnabledSeen,
          'overloadDisabledSeen': webrtcFrameCadenceOverloadDisabledSeen,
          'maxScheduledForProcessing':
              webrtcFrameCadenceMaxScheduledForProcessing,
          'lastScheduledForProcessing':
              webrtcFrameCadenceLastScheduledForProcessing,
          'maxQueueOverloadBefore': webrtcFrameCadenceMaxQueueOverloadBefore,
          'maxQueueOverloadAfter': webrtcFrameCadenceMaxQueueOverloadAfter,
          'lastQueueOverloadBefore': webrtcFrameCadenceLastQueueOverloadBefore,
          'lastQueueOverloadAfter': webrtcFrameCadenceLastQueueOverloadAfter,
        },
        'label': webrtcRawSenderBoundaryLabel,
      },
      'captureCauseAttribution': captureCauseAttribution,
      'summary': summaryLabel,
    };
  }
}

const _nativeDiagnosticLogNeedles = [
  'desktop capture options',
  'desktop capture cadence',
  'desktop capture frame cadence',
  'desktop capture frame timing',
  'desktop capture frame size',
  'desktop capture latest-frame pacer',
  'desktop capture pipeline',
  'desktop capture bridge start',
  'wgc frame timing',
  'window gdi frame timing',
  'media foundation h.264 encoder timing',
  'media foundation h.264 accepted',
  'media foundation h.264 did not accept',
  'media foundation h.264 initialized',
  'media foundation h.264 using async event drain',
  'game_capture_webrtc_source',
  'webrtc sender handoff',
];

final _captureOptionsPattern = RegExp(
  r'desktop capture options type=([^\s]+).*?\bmode=([^\s]+)',
  caseSensitive: false,
);
final _captureBridgePattern = RegExp(
  r'desktop capture bridge start source_type=([^\s]+)\s+requested_max=(\d+)x(\d+)\s+fps=([0-9.]+)(?:\s+capture_backend=([^\s]+))?',
  caseSensitive: false,
);
final _captureFrameSizePattern = RegExp(
  r'desktop capture frame size source=(\d+)x(\d+)\s+max=(\d+)x(\d+)\s+output=(\d+)x(\d+)\s+crop_region=([^\s]+)',
  caseSensitive: false,
);
final _captureCadencePattern = RegExp(
  r'desktop capture cadence target_delay_ms=([0-9.]+)\s+avg_capture_call_ms=([0-9.]+)\s+max_capture_call_ms=([0-9.]+)\s+scheduled_delay_ms=([0-9.]+)\s+calls=(\d+)(?:\s+submitted_fps=([0-9.]+))?(?:\s+temp_errors=(\d+))?(?:\s+permanent_errors=(\d+))?',
  caseSensitive: false,
);
final _captureFrameCadencePattern = RegExp(
  r'desktop capture frame cadence new_fps=([0-9.]+)\s+submitted_fps=([0-9.]+)\s+max_interval_ms=([0-9.]+)\s+p95_interval_ms=([0-9.]+)\s+duplicated_frames=(\d+)\s+stale_reuse=(\d+)\s+wait_timeouts=(\d+)\s+permanent_errors=(\d+)',
  caseSensitive: false,
);
final _captureFrameTimingPattern = RegExp(
  r'desktop capture frame timing avg_convert_ms=([0-9.]+)\s+avg_scale_ms=([0-9.]+)\s+avg_on_frame_ms=([0-9.]+)\s+avg_callback_ms=([0-9.]+)\s+max_callback_ms=([0-9.]+).*?\bframes=(\d+)',
  caseSensitive: false,
);
final _mediaFoundationTimingPattern = RegExp(
  r'media foundation h\.264 encoder timing.*?\btotal_ms=([0-9.]+).*?\bslow=(yes|no)',
  caseSensitive: false,
);
final _diagnosticMarkerTimestampPattern = RegExp(
  r'^\[?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\]?',
);

final _keyValueTokenPattern = RegExp(r'\b([A-Za-z0-9_]+)=([^\s]+)');
final _privateDiagnosticKeyValuePattern = RegExp(
  r'\b(source_title|window_title|title|source_name|window_name|process_name|app_name|path|file_path|output_path|helper_path|proof_path)=("[^"]*"|[^\s]+)',
  caseSensitive: false,
);
final _privateDiagnosticPidPattern = RegExp(
  r'\b(pid|process_id|processId)=\d+\b',
  caseSensitive: false,
);
const _safeDiagnosticLabelPrefixes = <String>{'current-call'};

String _redactedFreeformLabel(
  String value, {
  String fallback = '[REDACTED_LABEL]',
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  if (_safeDiagnosticLabelPrefixes.contains(trimmed)) {
    return trimmed;
  }

  final prefixMatch = RegExp(r'^([A-Za-z0-9 _.-]{1,40}):').firstMatch(trimmed);
  final prefix = prefixMatch?.group(1);
  if (prefix != null && _safeDiagnosticLabelPrefixes.contains(prefix)) {
    return '$prefix:[REDACTED]';
  }
  return fallback;
}

String _redactedRoomId(String value) => '[MATRIX_ROOM_ID]';

String _redactedDiagnosticMarker(String marker) {
  var redacted = Log.redactSensitiveInfo(marker);
  redacted = redacted.replaceAllMapped(
    _privateDiagnosticKeyValuePattern,
    (match) => '[REDACTED_FIELD]',
  );
  redacted = redacted.replaceAllMapped(
    _privateDiagnosticPidPattern,
    (match) => '[REDACTED_FIELD]',
  );
  return redacted.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

List<String> streamTestDiagnosticMarkersFromText(
  String text, {
  int? limit = streamTestDefaultDiagnosticLogMarkerLimit,
}) {
  return _extractDiagnosticLogMarkers(text, limit: limit);
}

String redactStreamTestDiagnosticMarker(String marker) =>
    _redactedDiagnosticMarker(marker);

List<String> _extractDiagnosticLogMarkers(String text, {required int? limit}) {
  if (text.trim().isEmpty || limit == 0) {
    return const [];
  }
  final matches = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    for (final marker in _expandDiagnosticLogMarkerLine(line)) {
      final normalized = marker.toLowerCase();
      if (_nativeDiagnosticLogNeedles.any(normalized.contains)) {
        matches.add(marker);
      }
    }
  }
  if (limit == null || matches.length <= limit) {
    return List.unmodifiable(matches);
  }
  return _capDiagnosticLogMarkers(matches, limit: limit);
}

List<String> _expandDiagnosticLogMarkerLines(List<String> markers) {
  if (markers.isEmpty) {
    return const [];
  }
  final expanded = <String>[];
  for (final marker in markers) {
    expanded.addAll(_expandDiagnosticLogMarkerLine(marker));
  }
  return List.unmodifiable(expanded);
}

List<String> _expandDiagnosticLogMarkerLine(String marker) {
  if (marker.trim().isEmpty) {
    return const [];
  }
  final matches = <String>[];
  for (final line in const LineSplitter().convert(marker)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    matches.add(trimmed);
  }
  return List.unmodifiable(matches);
}

List<String> _capDiagnosticLogMarkers(
  List<String> markers, {
  required int limit,
}) {
  if (limit <= 0 || markers.isEmpty) {
    return const [];
  }
  if (markers.length <= limit) {
    return List.unmodifiable(markers);
  }
  final selectedIndexes = <int>{};
  for (var index = markers.length - 1; index >= 0; index--) {
    if (markers[index].toLowerCase().contains('game_capture_webrtc_source')) {
      selectedIndexes.add(index);
      if (selectedIndexes.length >= limit) {
        break;
      }
    }
  }
  for (
    var index = markers.length - 1;
    index >= 0 && selectedIndexes.length < limit;
    index--
  ) {
    selectedIndexes.add(index);
  }
  final orderedIndexes = selectedIndexes.toList(growable: false)..sort();
  return List.unmodifiable(orderedIndexes.map((index) => markers[index]));
}

List<String> _diagnosticMarkersForRange(
  List<String> markers, {
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  markers = _expandDiagnosticLogMarkerLines(markers);
  final withTimestamps = markers
      .map((marker) => (marker: marker, timestamp: _markerTimestamp(marker)))
      .where((entry) => entry.timestamp != null)
      .toList(growable: false);
  if (withTimestamps.isEmpty) {
    return markers;
  }

  final start = startedAt.toUtc();
  final end = endedAt.toUtc();
  final filtered = <String>[];
  DateTime? inheritedTimestamp;
  for (final marker in markers) {
    final timestamp = _markerTimestamp(marker);
    if (timestamp != null) {
      inheritedTimestamp = timestamp;
    }
    final effectiveTimestamp = timestamp ?? inheritedTimestamp;
    if (effectiveTimestamp == null) {
      continue;
    }
    if (!effectiveTimestamp.isBefore(start) &&
        !effectiveTimestamp.isAfter(end)) {
      filtered.add(marker);
    }
  }
  return List.unmodifiable(filtered);
}

DateTime? _markerTimestamp(String marker) {
  final match = _diagnosticMarkerTimestampPattern.firstMatch(marker);
  if (match == null) {
    return null;
  }
  return DateTime.tryParse(match.group(1)!);
}

int? _intGroup(RegExpMatch match, int group) {
  final value = match.group(group);
  return value == null ? null : int.tryParse(value);
}

double? _doubleGroup(RegExpMatch match, int group) {
  final value = match.group(group);
  return value == null ? null : double.tryParse(value);
}

String? _stringGroup(RegExpMatch match, int group) {
  final value = match.group(group)?.trim();
  return value == null || value.isEmpty ? null : value;
}

bool? _boolGroup(RegExpMatch match, int group) {
  final value = _stringGroup(match, group)?.toLowerCase();
  if (value == null) {
    return null;
  }
  if (value == 'true' || value == '1' || value == 'yes') {
    return true;
  }
  if (value == 'false' || value == '0' || value == 'no') {
    return false;
  }
  return null;
}

String? _stringFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleFromJson(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _boolFromJson(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase().trim();
  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }
  return null;
}

DateTime? _dateTimeFromJson(Object? value) {
  final text = _stringFromJson(value);
  return text == null ? null : DateTime.tryParse(text);
}

bool? _boolFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key)?.toLowerCase();
  if (value == null) {
    return null;
  }
  if (value == 'true' || value == '1' || value == 'yes') {
    return true;
  }
  if (value == 'false' || value == '0' || value == 'no') {
    return false;
  }
  return null;
}

bool? _boolFromMarkerAny(String marker, Iterable<String> keys) {
  for (final key in keys) {
    final value = _boolFromMarker(marker, key);
    if (value != null) {
      return value;
    }
  }
  return null;
}

double? _doubleFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  return value == null ? null : double.tryParse(value);
}

double? _doubleFromMarkerAny(String marker, Iterable<String> keys) {
  for (final key in keys) {
    final value = _doubleFromMarker(marker, key);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _intFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  return value == null ? null : int.tryParse(value);
}

int? _intFromMarkerAny(String marker, Iterable<String> keys) {
  for (final key in keys) {
    final value = _intFromMarker(marker, key);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _tokenFromMarker(String marker, String key) {
  final normalizedKey = key.toLowerCase();
  for (final match in _keyValueTokenPattern.allMatches(marker)) {
    if (match.group(1)?.toLowerCase() == normalizedKey) {
      final value = match.group(2)?.trim();
      return value == null || value.isEmpty ? null : value;
    }
  }
  return null;
}

String? _tokenFromMarkerAny(String marker, Iterable<String> keys) {
  for (final key in keys) {
    final value = _tokenFromMarker(marker, key);
    if (value != null) {
      return value;
    }
  }
  return null;
}

_MarkerDimensions? _dimensionsFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final width = _intGroup(match, 1);
  final height = _intGroup(match, 2);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return _MarkerDimensions(width, height);
}

class _MarkerDimensions {
  const _MarkerDimensions(this.width, this.height);

  final int width;
  final int height;
}

String? _legacyBackendLabelFromOptions(String marker) {
  final normalized = marker.toLowerCase();
  final directx =
      normalized.contains('directx=1') || normalized.contains('directx=true');
  final crop =
      normalized.contains('crop_window=1') ||
      normalized.contains('crop_window=true');
  final wgcScreen =
      normalized.contains('wgc_screen=1') ||
      normalized.contains('wgc_screen=true');
  final wgcWindow =
      normalized.contains('wgc_window=1') ||
      normalized.contains('wgc_window=true');
  final wgcFallback =
      normalized.contains('wgc_fallback=1') ||
      normalized.contains('wgc_fallback=true');
  if (wgcScreen && wgcWindow && !directx && !crop && !wgcFallback) {
    return WindowsScreenCaptureBackendMode.wgcOnly.constraintValue;
  }
  if (directx && !crop && !wgcScreen && !wgcWindow) {
    return WindowsScreenCaptureBackendMode.directxOnly.constraintValue;
  }
  if (directx && crop && !wgcScreen && !wgcWindow) {
    return WindowsScreenCaptureBackendMode.windowCrop.constraintValue;
  }
  if (directx || crop || wgcScreen || wgcWindow || wgcFallback) {
    return WindowsScreenCaptureBackendMode.platformDefault.constraintValue;
  }
  return null;
}
