part of 'stream_test_runner.dart';

enum StreamTestReceiverProbeMode {
  localPreview,
  decodeOnly,
  render,
}

extension StreamTestReceiverProbeModeLabel on StreamTestReceiverProbeMode {
  String get label => switch (this) {
        StreamTestReceiverProbeMode.localPreview => 'local-preview',
        StreamTestReceiverProbeMode.decodeOnly => 'decode-only',
        StreamTestReceiverProbeMode.render => 'render',
      };
}

const _receiverProbeLaneLocalPreview = 'local_preview';
const _receiverProbeLaneRemoteDecode = 'remote_decode';
const _receiverProbeLegacyLaneRemoteRender = 'remote_render';
const _receiverProbeLaneRemoteRendererCallback = 'remote_renderer_callback';
const _receiverProbeStageRemoteDecode = 'remote_decode';
const _receiverProbeStageRemoteRendererCallback = 'remote_renderer_callback';
const _receiverProbeStageRemoteTextureReady = 'remote_texture_ready';
const _receiverProbeStageRemoteUiPaint = 'remote_ui_paint';
const _receiverProbeStageRemoteScreenPresent = 'remote_screen_present';
const _receiverProbePresentationStageOrder = <String>[
  _receiverProbeStageRemoteDecode,
  _receiverProbeStageRemoteRendererCallback,
  _receiverProbeStageRemoteTextureReady,
  _receiverProbeStageRemoteUiPaint,
  _receiverProbeStageRemoteScreenPresent,
];

class StreamTestReceiverProbeConfig {
  const StreamTestReceiverProbeConfig({
    this.enabled = false,
    this.mode = StreamTestReceiverProbeMode.decodeOnly,
    this.inProcess = true,
    this.externalControlPipe,
    this.startBeforeShare = true,
    this.startDelay = Duration.zero,
  });

  final bool enabled;
  final StreamTestReceiverProbeMode mode;
  final bool inProcess;
  final String? externalControlPipe;
  final bool startBeforeShare;
  final Duration startDelay;

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'mode': mode.label,
      'inProcess': inProcess,
      'externalControlPipe': externalControlPipe,
      'startBeforeShare': startBeforeShare,
      'startDelayMs': startDelay.inMilliseconds,
    };
  }

  Map<String, Object?> toDiagnosticJson() {
    return {
      'enabled': enabled,
      'mode': mode.label,
      'inProcess': inProcess,
      'externalControlPipeSet':
          externalControlPipe != null && externalControlPipe!.trim().isNotEmpty,
      'startBeforeShare': startBeforeShare,
      'startDelayMs': startDelay.inMilliseconds,
    };
  }
}

class StreamTestReceiverProbeResult {
  StreamTestReceiverProbeResult({
    required this.enabled,
    required this.mode,
    required this.inProcess,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    this.blockingReason,
    this.error,
    this.snapshot,
    List<Map<String, Object?>> events = const [],
  }) : events = List.unmodifiable(
          events.map(_sanitizeReceiverProbeJson),
        );

  factory StreamTestReceiverProbeResult.notRequested() {
    return StreamTestReceiverProbeResult(
      enabled: false,
      mode: StreamTestReceiverProbeMode.decodeOnly,
      inProcess: true,
      startedAt: null,
      endedAt: null,
      status: 'not_requested',
    );
  }

  factory StreamTestReceiverProbeResult.startFailed({
    required StreamTestReceiverProbeMode mode,
    bool inProcess = true,
    required DateTime startedAt,
    required DateTime endedAt,
    required Object error,
  }) {
    final redacted = Log.redactSensitiveInfo(error.toString());
    return StreamTestReceiverProbeResult(
      enabled: true,
      mode: mode,
      inProcess: inProcess,
      startedAt: startedAt,
      endedAt: endedAt,
      status: inProcess
          ? 'blocked_in_process_receiver_probe_start_failed'
          : 'blocked_external_receiver_probe_handoff_failed',
      blockingReason: redacted,
      error: redacted,
    );
  }

  factory StreamTestReceiverProbeResult.stopFailed({
    required StreamTestReceiverProbeMode mode,
    bool inProcess = true,
    required DateTime startedAt,
    required DateTime endedAt,
    required Object error,
    List<Map<String, Object?>> events = const [],
    Map<String, Object?>? snapshot,
  }) {
    final redacted = Log.redactSensitiveInfo(error.toString());
    return StreamTestReceiverProbeResult(
      enabled: true,
      mode: mode,
      inProcess: inProcess,
      startedAt: startedAt,
      endedAt: endedAt,
      status: inProcess
          ? 'blocked_in_process_receiver_probe_stop_failed'
          : 'blocked_external_receiver_probe_handoff_stop_failed',
      blockingReason: redacted,
      error: redacted,
      events: events,
      snapshot: snapshot,
    );
  }

  factory StreamTestReceiverProbeResult.externalHandoff({
    required StreamTestReceiverProbeMode mode,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    return StreamTestReceiverProbeResult(
      enabled: true,
      mode: mode,
      inProcess: false,
      startedAt: startedAt,
      endedAt: endedAt,
      status: 'completed_external_receiver_probe_handoff',
    );
  }

  factory StreamTestReceiverProbeResult.fromEvents({
    required StreamTestReceiverProbeMode mode,
    required DateTime startedAt,
    required DateTime endedAt,
    required List<Map<String, Object?>> events,
    Map<String, Object?>? snapshot,
  }) {
    final sanitizedEvents =
        events.map(_sanitizeReceiverProbeJson).toList(growable: false);
    final decodeEvents = _receiverProbeLaneEvents(
      sanitizedEvents,
      _receiverProbeLaneRemoteDecode,
    );
    final renderEvents = _receiverProbeLaneEvents(
      sanitizedEvents,
      _receiverProbeLaneRemoteRendererCallback,
    );
    final localPreviewEvents = _receiverProbeLaneEvents(
      sanitizedEvents,
      _receiverProbeLaneLocalPreview,
    );
    final targetEvents = switch (mode) {
      StreamTestReceiverProbeMode.localPreview => localPreviewEvents,
      StreamTestReceiverProbeMode.render => renderEvents,
      StreamTestReceiverProbeMode.decodeOnly => decodeEvents,
    };
    final latestTargetEvent = _preferredTargetEvent(
      targetEvents,
      requireVisibleRender: mode == StreamTestReceiverProbeMode.render,
    );
    final uniqueFps = _doubleFromJson(latestTargetEvent?['unique_fps']);
    final freshnessSource =
        _stringFromJson(latestTargetEvent?['freshness_source']);

    String status;
    String? blockingReason;
    if (sanitizedEvents.isEmpty) {
      status = 'inconclusive_no_receiver_probe_events';
      blockingReason =
          'The in-process receiver probe produced no redacted events.';
    } else if (mode == StreamTestReceiverProbeMode.localPreview &&
        localPreviewEvents.isEmpty) {
      status = 'inconclusive_missing_local_preview_events';
      blockingReason = 'No local_preview probe events were observed.';
    } else if (mode != StreamTestReceiverProbeMode.localPreview &&
        decodeEvents.isEmpty) {
      status = 'inconclusive_missing_remote_decode_events';
      blockingReason = 'No remote_decode receiver events were observed.';
    } else if (mode == StreamTestReceiverProbeMode.render &&
        renderEvents.isEmpty) {
      status = 'inconclusive_missing_remote_renderer_callback_events';
      blockingReason =
          'Render mode did not produce remote_renderer_callback events.';
    } else if (mode == StreamTestReceiverProbeMode.render &&
        !targetEvents.any(_receiverProbeRenderEventIsVisible)) {
      status = 'invalid_remote_renderer_callback_not_visible';
      blockingReason =
          'Render mode requires renderer_attached=true and renderer_visible=true.';
    } else if (uniqueFps == null) {
      status = 'inconclusive_frame_hash_tap_pending';
      blockingReason =
          'Receiver stats were observed, but frame hash taps did not report unique_fps.';
    } else if (!_receiverProbeFreshnessSourceIsFrameHash(freshnessSource)) {
      status = 'inconclusive_frame_hash_tap_pending';
      blockingReason =
          'Receiver unique_fps was present, but freshness_source was not frame_hash_tap.';
    } else {
      status = mode == StreamTestReceiverProbeMode.localPreview
          ? 'completed_local_preview_probe_events'
          : 'completed_receiver_probe_events';
    }

    return StreamTestReceiverProbeResult(
      enabled: true,
      mode: mode,
      inProcess: true,
      startedAt: startedAt,
      endedAt: endedAt,
      status: status,
      blockingReason: blockingReason,
      events: sanitizedEvents,
      snapshot: snapshot,
    );
  }

  final bool enabled;
  final StreamTestReceiverProbeMode mode;
  final bool inProcess;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String status;
  final String? blockingReason;
  final String? error;
  final Map<String, Object?>? snapshot;
  final List<Map<String, Object?>> events;

  bool get hasEvents => events.isNotEmpty;

  int get remoteDecodeEventCount =>
      _receiverProbeLaneEvents(events, _receiverProbeLaneRemoteDecode).length;

  int get remoteRendererCallbackLaneEventCount => _receiverProbeLaneEvents(
        events,
        _receiverProbeLaneRemoteRendererCallback,
      ).length;

  int get remoteRendererCallbackEventCount =>
      receiverPresentationStageEventCount(
        _receiverProbeStageRemoteRendererCallback,
      );

  int get remoteScreenPresentEventCount => receiverPresentationStageEventCount(
        _receiverProbeStageRemoteScreenPresent,
      );

  int get localPreviewEventCount =>
      _receiverProbeLaneEvents(events, _receiverProbeLaneLocalPreview).length;

  double? get latestUniqueFps {
    return _doubleFromJson(latestTargetEvent?['unique_fps']);
  }

  String? get latestFreshnessSource {
    return _stringFromJson(latestTargetEvent?['freshness_source']);
  }

  Map<String, Object?>? get latestTargetEvent {
    final laneEvents = targetEvents;
    if (laneEvents.isEmpty) {
      return null;
    }
    return _preferredTargetEvent(
      laneEvents,
      requireVisibleRender: mode == StreamTestReceiverProbeMode.render,
    );
  }

  List<Map<String, Object?>> get targetEvents {
    final lane = switch (mode) {
      StreamTestReceiverProbeMode.localPreview =>
        _receiverProbeLaneLocalPreview,
      StreamTestReceiverProbeMode.render =>
        _receiverProbeLaneRemoteRendererCallback,
      StreamTestReceiverProbeMode.decodeOnly => _receiverProbeLaneRemoteDecode,
    };
    return _receiverProbeLaneEvents(events, lane);
  }

  String get latestTargetStage {
    final reportedStage = latestTargetEvent == null
        ? null
        : _receiverProbeStageForEvent(latestTargetEvent!);
    if (reportedStage != null) {
      return reportedStage;
    }
    return switch (mode) {
      StreamTestReceiverProbeMode.localPreview =>
        _receiverProbeLaneLocalPreview,
      StreamTestReceiverProbeMode.render =>
        _receiverProbeStageRemoteRendererCallback,
      StreamTestReceiverProbeMode.decodeOnly => _receiverProbeStageRemoteDecode,
    };
  }

  int receiverPresentationStageEventCount(String stage) {
    return _receiverProbeStageEvents(events, stage).length;
  }

  List<Map<String, Object?>> get receiverPresentationStages {
    return _receiverProbePresentationStageOrder.map(
      (stage) {
        final stageEvents = _receiverProbeStageEvents(events, stage);
        final latestStageEvent = stageEvents.isEmpty ? null : stageEvents.last;
        return {
          'stage': stage,
          'status': stageEvents.isNotEmpty ? 'reported' : 'missing',
          'eventCount': stageEvents.length,
          'latestSampleTimeUtc':
              _stringFromJson(latestStageEvent?['sample_time_utc']),
          'latestNativeFrameSequence':
              _intFromJson(latestStageEvent?['stage_native_frame_sequence']) ??
                  _intFromJson(latestStageEvent?['native_frame_sequence']),
          'latestStageObservedGapMs':
              _doubleFromJson(latestStageEvent?['stage_observed_gap_ms']),
          'latestRendererCallbackToStageMs': _doubleFromJson(
            latestStageEvent?['renderer_callback_to_stage_ms'],
          ),
          if (stage == _receiverProbeStageRemoteRendererCallback)
            'lane': _receiverProbeLaneRemoteRendererCallback,
        };
      },
    ).toList(growable: false);
  }

  Map<String, Object?>? get latestQualityDiagnostics {
    final target = latestTargetEvent;
    if (target == null) {
      return null;
    }
    return {
      'subscriptionState': _stringFromJson(target['subscription_state']),
      'subscribedQuality': _stringFromJson(target['subscribed_quality']),
      'simulcastLayer': _stringFromJson(target['simulcast_layer']),
      'inboundBitrateBps': _intFromJson(target['inbound_bitrate_bps']) ??
          _intFromJson(target['bitrate_bps']),
      'receivedSize': _receiverProbeSizeLabel(target, 'received'),
      'decodedSize': _receiverProbeSizeLabel(target, 'decoded'),
      'renderedSize': _receiverProbeSizeLabel(target, 'rendered'),
      'rendererCallbackSize': _receiverProbeSizeLabel(target, 'rendered'),
      'receiverFps': _doubleFromJson(target['receiver_fps']),
      'averageQp': _doubleFromJson(target['average_qp']),
      'keyframeIntervalMs': _doubleFromJson(target['keyframe_interval_ms']),
      'pliCount': _intFromJson(target['pli_count']),
      'firCount': _intFromJson(target['fir_count']),
      'nackCount': _intFromJson(target['nack_count']),
      'framePresentationP95GapMs':
          _doubleFromJson(target['frame_presentation_p95_gap_ms']),
      'framePresentationMaxGapMs':
          _doubleFromJson(target['frame_presentation_max_gap_ms']),
      'perceptualDifferenceScore':
          _doubleFromJson(target['perceptual_difference_score']),
      'longestStaleRunMs': _doubleFromJson(target['longest_stale_run_ms']),
      'droppedOrReplacedTextureUpdates':
          _intFromJson(target['dropped_or_replaced_texture_updates']),
      'upscalingLowerLayerSuspected':
          _boolFromJson(target['upscaling_lower_layer_suspected']),
      'adaptiveStreamLowLayerSuspected':
          _boolFromJson(target['adaptive_stream_low_layer_suspected']),
    };
  }

  String get latestQualityMarkdownLabel {
    final target = latestTargetEvent;
    if (target == null) {
      return 'quality=n/a';
    }
    final quality = _stringFromJson(target['subscribed_quality']) ?? '?';
    final layer = _stringFromJson(target['simulcast_layer']) ?? '?';
    final bitrate = _bitrate(
      _intFromJson(target['inbound_bitrate_bps']) ??
          _intFromJson(target['bitrate_bps']),
    );
    final received = _receiverProbeSizeLabel(target, 'received');
    final decoded = _receiverProbeSizeLabel(target, 'decoded');
    final rendered = _receiverProbeSizeLabel(target, 'rendered');
    final qp = _number(_doubleFromJson(target['average_qp']));
    final p95 = _milliseconds(
      _doubleFromJson(target['frame_presentation_p95_gap_ms']),
    );
    final stale = _milliseconds(
      _doubleFromJson(target['longest_stale_run_ms']),
    );
    return 'quality=$quality/$layer; bitrate=$bitrate; '
        'received=$received; decoded=$decoded; rendered=$rendered; '
        'qp=$qp; p95=$p95; stale=$stale';
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'mode': mode.label,
      'inProcess': inProcess,
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'endedAt': endedAt?.toUtc().toIso8601String(),
      'status': status,
      'blockingReason': blockingReason,
      'error': error,
      'eventCount': events.length,
      'localPreviewEventCount': localPreviewEventCount,
      'remoteDecodeEventCount': remoteDecodeEventCount,
      'remoteRendererCallbackLaneEventCount':
          remoteRendererCallbackLaneEventCount,
      'remoteRendererCallbackEventCount': remoteRendererCallbackEventCount,
      'remoteScreenPresentEventCount': remoteScreenPresentEventCount,
      'latestTargetStage': latestTargetStage,
      'receiverPresentationStages': receiverPresentationStages,
      'latestUniqueFps': latestUniqueFps,
      'latestFreshnessSource': latestFreshnessSource,
      'latestQualityDiagnostics': latestQualityDiagnostics,
      'snapshot':
          snapshot == null ? null : _sanitizeReceiverProbeJson(snapshot!),
      'events': events,
    };
  }

  String get markdownLabel {
    final unique = latestUniqueFps;
    final uniqueLabel = unique == null ? '?' : unique.toStringAsFixed(1);
    final sourceLabel = latestFreshnessSource ?? '?';
    return '$status; events=${events.length}; '
        'local=$localPreviewEventCount; decode=$remoteDecodeEventCount; '
        'rendererCallback=$remoteRendererCallbackEventCount; '
        'unique_fps=$uniqueLabel; source=$sourceLabel; '
        '$latestQualityMarkdownLabel';
  }
}

Map<String, Object?> _sanitizeReceiverProbeJson(Map<String, Object?> value) {
  return value.map(
    (key, object) => MapEntry(
      key,
      _sanitizeReceiverProbeJsonValue(object),
    ),
  );
}

Object? _sanitizeReceiverProbeJsonValue(Object? value) {
  if (value == null || value is num || value is bool) {
    return value;
  }
  if (value is String) {
    return Log.redactSensitiveInfo(value);
  }
  if (value is Map<String, Object?>) {
    return _sanitizeReceiverProbeJson(value);
  }
  if (value is Map) {
    return value.map(
      (key, object) => MapEntry(
        key.toString(),
        _sanitizeReceiverProbeJsonValue(object),
      ),
    );
  }
  if (value is Iterable) {
    return value.map(_sanitizeReceiverProbeJsonValue).toList(growable: false);
  }
  return Log.redactSensitiveInfo(value.toString());
}

List<Map<String, Object?>> _receiverProbeLaneEvents(
  List<Map<String, Object?>> events,
  String lane,
) {
  return events.where((event) {
    final actual = _stringFromJson(event['lane']);
    if (actual == lane) {
      return true;
    }
    return lane == _receiverProbeLaneRemoteRendererCallback &&
        actual == _receiverProbeLegacyLaneRemoteRender;
  }).toList(growable: false);
}

List<Map<String, Object?>> _receiverProbeStageEvents(
  List<Map<String, Object?>> events,
  String stage,
) {
  return events
      .where((event) => _receiverProbeStageForEvent(event) == stage)
      .toList(growable: false);
}

String? _receiverProbeStageForEvent(Map<String, Object?> event) {
  final explicitStage = _stringFromJson(event['stage']);
  if (explicitStage != null &&
      _receiverProbePresentationStageOrder.contains(explicitStage)) {
    return explicitStage;
  }
  final lane = _stringFromJson(event['lane']);
  if (lane == _receiverProbeLaneRemoteRendererCallback ||
      lane == _receiverProbeLegacyLaneRemoteRender) {
    return _receiverProbeStageRemoteRendererCallback;
  }
  if (lane == _receiverProbeLaneRemoteDecode) {
    return _receiverProbeStageRemoteDecode;
  }
  return lane;
}

bool _receiverProbeRenderEventIsVisible(Map<String, Object?> event) {
  return _boolFromJson(event['renderer_attached']) == true &&
      _boolFromJson(event['renderer_visible']) == true;
}

Map<String, Object?>? _preferredTargetEvent(
  List<Map<String, Object?>> events, {
  required bool requireVisibleRender,
}) {
  if (events.isEmpty) {
    return null;
  }
  if (requireVisibleRender) {
    for (final event in events.reversed) {
      if (_receiverProbeRenderEventIsVisible(event) &&
          _receiverProbeEventHasFrameHashTap(event)) {
        return event;
      }
    }
    for (final event in events.reversed) {
      if (_receiverProbeRenderEventIsVisible(event)) {
        return event;
      }
    }
  }
  for (final event in events.reversed) {
    if (_receiverProbeEventHasFrameHashTap(event)) {
      return event;
    }
  }
  return events.last;
}

bool _receiverProbeEventHasFrameHashTap(Map<String, Object?> event) {
  return _receiverProbeFreshnessSourceIsFrameHash(
        _stringFromJson(event['freshness_source']),
      ) &&
      _doubleFromJson(event['unique_fps']) != null;
}

bool _receiverProbeFreshnessSourceIsFrameHash(String? value) {
  return value == 'frame_hash_tap';
}

String _receiverProbeSizeLabel(Map<String, Object?> event, String prefix) {
  final width = _intFromJson(event['${prefix}_width']);
  final height = _intFromJson(event['${prefix}_height']);
  if (width == null || height == null) {
    return '?';
  }
  return '${width}x$height';
}
