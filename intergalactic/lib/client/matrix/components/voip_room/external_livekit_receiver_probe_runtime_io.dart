import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_ipc/dart_ipc.dart' as ipc;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_receiver_probe.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:window_manager/window_manager.dart';

const _diagnosticContract =
    'docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md';

Future<void> debugCancelExternalReceiverProbeWidgetSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelExternalReceiverProbeWidgetSubscription(subscription);
}

Future<void> _cancelExternalReceiverProbeWidgetSubscription(
  StreamSubscription? subscription,
) async {
  try {
    await subscription?.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'External receiver probe widget subscription cancel failed',
      category: LogCategory.webrtc,
      source: 'external-receiver-probe-widget',
      flush: true,
    );
  }
}

class ExternalLivekitReceiverProbeRuntime {
  static const _invocationFlag = '--receiver-probe';

  static bool isInvocation(List<String> args) => args.contains(_invocationFlag);

  static Future<int> run(List<String> args) async {
    final invocation = await _ReceiverProbeInvocation.fromArgs(args);
    final windowFrameCadence = _ReceiverWindowFrameCadenceProbe();
    final output = _ReceiverProbeOutput(invocation, windowFrameCadence);
    final controller = MatrixLivekitReceiverProbeController(
      options: MatrixLivekitReceiverProbeOptions(
        runId: invocation.runId,
        roomId: invocation.roomId,
        publisherIdentity: invocation.publisherIdentity,
        mode: invocation.mode,
        inProcess: false,
        frameDiagnosticsMode: invocation.frameDiagnosticsMode,
        connectTimeout: const Duration(seconds: 15),
      ),
    );
    windowFrameCadence.onFramePresented = () {
      controller.recordRendererScreenPresent(
        source: 'external_receiver_probe_flutter_frame_timing',
      );
    };

    StreamSubscription<MatrixLivekitReceiverProbeEvent>? eventsSub;
    try {
      await output.prepare();
      await _configureWindow(invocation);
      runApp(
        _ExternalLivekitReceiverProbeApp(
          controller: controller,
          mode: invocation.mode,
          visualFrameMarker: invocation.visualFrameMarker,
          windowFrameCadence: windowFrameCadence,
        ),
      );

      final credentials = await invocation.readCredentials();
      eventsSub = controller.events.listen(
        output.writeEvent,
        onError: (Object error, StackTrace stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'External receiver probe event stream failed',
            category: LogCategory.webrtc,
            source: 'external-receiver-probe',
            flush: true,
          );
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await controller.start(credentials);
      await Future<void>.delayed(invocation.duration);
      await _cancelEventsSubscription(eventsSub);
      eventsSub = null;
      await output.writeFinalArtifacts(
        controller.snapshot,
        statusOverride: null,
        blockingReason: '',
      );
      return 0;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'External receiver probe failed',
        category: LogCategory.webrtc,
        source: 'external-receiver-probe',
        flush: true,
      );
      await _cancelEventsSubscription(eventsSub);
      eventsSub = null;
      await output.writeFinalArtifacts(
        controller.snapshot,
        statusOverride: 'blocked_external_receiver_probe_runtime_failed',
        blockingReason: Log.redactSensitiveInfo(error.toString()),
      );
      return 1;
    } finally {
      await _cancelEventsSubscription(eventsSub);
      await controller.dispose();
      await Log.flush();
    }
  }

  static Future<void> _cancelEventsSubscription(
    StreamSubscription<MatrixLivekitReceiverProbeEvent>? eventsSub,
  ) async {
    try {
      await eventsSub?.cancel();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'External receiver probe event subscription cancel failed',
        category: LogCategory.webrtc,
        source: 'external-receiver-probe',
        flush: true,
      );
    }
  }

  static Future<void> _configureWindow(
    _ReceiverProbeInvocation invocation,
  ) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle(
        '${BuildConfig.app} Receiver Probe ${invocation.runId}',
      );
      final aspect = invocation.expectedWidth > 0
          ? invocation.expectedHeight / invocation.expectedWidth
          : 9 / 16;
      final targetWidth = math.min(
        math.max(invocation.expectedWidth.toDouble(), 640.0),
        1920.0,
      );
      final targetHeight = math.min(
        math.max(targetWidth * aspect, 360.0),
        1080.0,
      );
      await windowManager.setSize(Size(targetWidth, targetHeight));
      await windowManager.setMinimumSize(const Size(640, 360));
      await windowManager.show(inactive: true);
    } catch (_) {
      // Window shaping is diagnostic-only; the probe can still collect decode
      // evidence without window-manager support.
    }
  }
}

class _ReceiverProbeInvocation {
  _ReceiverProbeInvocation({
    required this.runId,
    required this.mode,
    required this.duration,
    required this.expectedWidth,
    required this.expectedHeight,
    required this.expectedFps,
    required this.visualFrameMarker,
    required this.frameDiagnosticsMode,
    required this.outputDir,
    required this.roomId,
    required this.publisherIdentity,
    required this.probeIdentity,
    required this.sfuUrl,
    required this.jwt,
    required this.expiresInSeconds,
  });

  final String runId;
  final MatrixLivekitReceiverProbeMode mode;
  final Duration duration;
  final int expectedWidth;
  final int expectedHeight;
  final int expectedFps;
  final bool visualFrameMarker;
  final MatrixLivekitReceiverProbeFrameDiagnosticsMode frameDiagnosticsMode;
  final Directory outputDir;
  final String roomId;
  final String publisherIdentity;
  final String probeIdentity;
  final String sfuUrl;
  final String jwt;
  final int? expiresInSeconds;

  static Future<_ReceiverProbeInvocation> fromArgs(List<String> args) async {
    final runId =
        _argValue(args, '--receiver-probe-run-id') ??
        _utcStamp(DateTime.now().toUtc());
    final mode = _parseMode(
      _argValue(args, '--receiver-probe-mode') ?? 'decode-only',
    );
    final durationSeconds = _intArg(
      args,
      '--receiver-probe-duration-seconds',
      60,
    ).clamp(1, 3600).toInt();
    final expectedWidth = _intArg(
      args,
      '--receiver-probe-expected-width',
      1280,
    ).clamp(1, 7680).toInt();
    final expectedHeight = _intArg(
      args,
      '--receiver-probe-expected-height',
      720,
    ).clamp(1, 4320).toInt();
    final expectedFps = _intArg(
      args,
      '--receiver-probe-expected-fps',
      30,
    ).clamp(1, 240).toInt();
    final visualFrameMarker = args.contains(
      '--receiver-probe-visual-frame-marker',
    );
    final frameDiagnosticsMode = _parseFrameDiagnosticsMode(
      _argValue(args, '--receiver-probe-frame-diagnostics-mode') ??
          MatrixLivekitReceiverProbeFrameDiagnosticsMode
              .nativeRendererHash
              .label,
    );
    final outputDirValue = _argValue(args, '--receiver-probe-output-dir');
    if (outputDirValue == null || outputDirValue.trim().isEmpty) {
      throw const FormatException('Missing --receiver-probe-output-dir.');
    }
    final controlPipe = _argValue(args, '--receiver-probe-control-pipe');
    if (controlPipe == null || controlPipe.trim().isEmpty) {
      throw const FormatException('Missing --receiver-probe-control-pipe.');
    }

    final envelope = await _readControlEnvelope(controlPipe.trim());
    final sfuUrl = _firstString(envelope, const [
      'sfu_url',
      'url',
      'livekit_url',
    ]);
    final jwt = _firstString(envelope, const ['jwt', 'livekit_jwt', 'token']);
    final roomId = _firstString(envelope, const ['room_id', 'room']);
    final publisherIdentity = _firstString(envelope, const [
      'publisher_identity',
      'publisher',
    ]);
    final probeIdentity =
        _firstString(envelope, const [
          'probe_identity',
          'receiver_identity',
          'identity',
        ]) ??
        'external-receiver-probe';
    if (sfuUrl == null || jwt == null) {
      throw const FormatException(
        'Protected IPC envelope must include LiveKit URL and subscribe-only JWT.',
      );
    }
    if (roomId == null || publisherIdentity == null) {
      throw const FormatException(
        'Protected IPC envelope must include raw room_id and publisher_identity.',
      );
    }

    return _ReceiverProbeInvocation(
      runId: runId,
      mode: mode,
      duration: Duration(seconds: durationSeconds),
      expectedWidth: expectedWidth,
      expectedHeight: expectedHeight,
      expectedFps: expectedFps,
      visualFrameMarker: visualFrameMarker,
      frameDiagnosticsMode: frameDiagnosticsMode,
      outputDir: Directory(outputDirValue),
      roomId: roomId,
      publisherIdentity: publisherIdentity,
      probeIdentity: probeIdentity,
      sfuUrl: sfuUrl,
      jwt: jwt,
      expiresInSeconds: _firstInt(envelope, const [
        'expires_in',
        'expires_in_seconds',
      ]),
    );
  }

  Future<MatrixLivekitReceiverProbeCredentials> readCredentials() async {
    return MatrixLivekitReceiverProbeCredentials(
      sfuUrl: sfuUrl,
      jwt: jwt,
      probeIdentity: probeIdentity,
      expiresInSeconds: expiresInSeconds,
    );
  }

  bool get sfuUrlReceived => sfuUrl.trim().isNotEmpty;

  bool get jwtReceived => jwt.trim().isNotEmpty;

  bool get credentialsReceived => sfuUrlReceived && jwtReceived;

  bool get expiresInSecondsReceived => expiresInSeconds != null;

  static Future<Map<String, Object?>> _readControlEnvelope(
    String pipeName,
  ) async {
    final path = _receiverProbeControlPipePath(pipeName);
    final socket = await ipc.connect(path).timeout(const Duration(seconds: 15));
    try {
      final chunks = await socket.toList().timeout(const Duration(seconds: 15));
      final raw = utf8.decode([for (final chunk in chunks) ...chunk]);
      if (raw.trim().isEmpty) {
        throw const FormatException(
          'Protected IPC control envelope was empty.',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException(
          'Protected IPC envelope must be a JSON map.',
        );
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } finally {
      socket.destroy();
    }
  }

  static String _receiverProbeControlPipePath(String pipeName) {
    if (!Platform.isWindows) {
      return pipeName;
    }
    if (pipeName.toLowerCase().startsWith(r'\\.\pipe\')) {
      return pipeName;
    }
    return r'\\.\pipe\' + pipeName;
  }
}

class _ReceiverProbeOutput {
  _ReceiverProbeOutput(this.invocation, this.windowFrameCadence);

  final _ReceiverProbeInvocation invocation;
  final _ReceiverWindowFrameCadenceProbe windowFrameCadence;
  final List<Map<String, Object?>> _events = [];
  Future<void> _pendingEventWrite = Future<void>.value();

  File get _eventsFile => File('${invocation.outputDir.path}/events.jsonl');

  Future<void> prepare() async {
    await invocation.outputDir.create(recursive: true);
    if (await _eventsFile.exists()) {
      await _eventsFile.delete();
    }
    await _eventsFile.writeAsString('', flush: true);
  }

  void writeEvent(MatrixLivekitReceiverProbeEvent event) {
    final json = _augmentEvent(event.toJson());
    _events.add(json);
    _pendingEventWrite = _pendingEventWrite.catchError((_) {}).then((_) {
      return _eventsFile.writeAsString(
        '${jsonEncode(json)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  Future<void> writeFinalArtifacts(
    MatrixLivekitReceiverProbeSnapshot snapshot, {
    required String? statusOverride,
    required String blockingReason,
  }) async {
    await invocation.outputDir.create(recursive: true);
    await _pendingEventWrite.catchError((_) {});
    final decodeEvents = _laneEvents('remote_decode');
    final renderEvents = _laneEvents(
      MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
    );
    final latestDecode = _preferredLaneEvent(decodeEvents);
    final latestRender = _preferredLaneEvent(
      renderEvents,
      requireVisibleRender: true,
    );
    final latestTarget =
        invocation.mode == MatrixLivekitReceiverProbeMode.render
        ? latestRender
        : latestDecode;
    final status =
        statusOverride ??
        _statusForEvents(
          decodeEvents: decodeEvents,
          renderEvents: renderEvents,
          latestTarget: latestTarget,
        );
    final reason = statusOverride == null
        ? _blockingReasonForStatus(status, latestTarget)
        : blockingReason;

    await _writeJsonFile(
      'decoded-freshness.json',
      _freshnessFromEvent(
        lane: 'remote_decode',
        event: latestDecode,
        status: status,
        reason: reason,
      ),
    );
    await _writeJsonFile(
      'rendered-freshness.json',
      _freshnessFromEvent(
        lane:
            MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
        event: latestRender,
        status: status,
        reason: reason,
      ),
    );
    await _writeJsonFile(
      'receiver-summary.json',
      _summary(
        status: status,
        reason: reason,
        snapshot: snapshot,
        latestDecode: latestDecode,
        latestRender: latestRender,
      ),
    );
    await _writeMarkdownSummary(status, reason);
  }

  List<Map<String, Object?>> _laneEvents(String lane) {
    return _events
        .where((event) => _laneMatches(event, lane))
        .toList(growable: false);
  }

  bool _laneMatches(Map<String, Object?> event, String lane) {
    final actual = _stringValue(event['lane']);
    if (actual == lane) {
      return true;
    }
    return lane ==
            MatrixLivekitReceiverProbePresentationStage
                .remoteRendererCallback &&
        actual == 'remote_render';
  }

  List<Map<String, Object?>> _stageEvents(String stage) {
    return _events
        .where((event) => _stageForEvent(event) == stage)
        .toList(growable: false);
  }

  List<Map<String, Object?>> _presentationStages() {
    return [
      for (final stage in const [
        MatrixLivekitReceiverProbePresentationStage.remoteDecode,
        MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
        MatrixLivekitReceiverProbePresentationStage.remoteTextureReady,
        MatrixLivekitReceiverProbePresentationStage.remoteUiPaint,
        MatrixLivekitReceiverProbePresentationStage.remoteScreenPresent,
      ])
        {
          'stage': stage,
          'status': _stageEvents(stage).isEmpty ? 'missing' : 'reported',
          'event_count': _stageEvents(stage).length,
        },
    ];
  }

  int _eventValueCount(String field) {
    return _events.where((event) => _stringValue(event[field]) != null).length;
  }

  Map<String, Object?> _sourceLineageSummary() {
    final frameIdEvents = _eventValueCount('frame_id');
    final previousFrameIdEvents = _eventValueCount('previous_frame_id');
    final sourceFrameMarkerIdEvents = _eventValueCount(
      'source_frame_marker_id',
    );
    final sourceQpcEvents = _eventValueCount('source_qpc');
    final stageQpcEvents = _eventValueCount('stage_qpc');
    final sourceLineageEvents = _events.where((event) {
      return _stringValue(event['frame_id']) != null ||
          _stringValue(event['previous_frame_id']) != null ||
          _stringValue(event['source_frame_marker_id']) != null ||
          _stringValue(event['source_qpc']) != null ||
          _stringValue(event['stage_qpc']) != null;
    }).length;
    final sourceFrameIdAvailable =
        frameIdEvents > 0 ||
        previousFrameIdEvents > 0 ||
        sourceFrameMarkerIdEvents > 0;
    final sourceLineageSource = frameIdEvents > 0
        ? 'source_frame_id'
        : previousFrameIdEvents > 0
        ? 'source_frame_id_observed_as_previous'
        : sourceFrameMarkerIdEvents > 0
        ? 'source_frame_content_marker'
        : null;
    final sourceLineageAvailable =
        sourceLineageSource != null &&
        sourceQpcEvents > 0 &&
        stageQpcEvents > 0;
    final reason = sourceLineageAvailable
        ? '${sourceLineageSource}_source_qpc_stage_qpc_present'
        : sourceFrameMarkerIdEvents > 0
        ? 'source_frame_content_marker_present_without_complete_lineage'
        : frameIdEvents > 0
        ? 'source_frame_id_present_without_complete_lineage'
        : previousFrameIdEvents > 0
        ? 'source_frame_id_observed_as_previous_without_complete_lineage'
        : _events.isEmpty
        ? 'events_empty'
        : 'source_frame_id_missing';

    return {
      'source_lineage_event_count': sourceLineageEvents,
      'source_frame_id_event_count': frameIdEvents,
      'previous_frame_id_event_count': previousFrameIdEvents,
      'source_frame_marker_id_event_count': sourceFrameMarkerIdEvents,
      'source_qpc_event_count': sourceQpcEvents,
      'stage_qpc_event_count': stageQpcEvents,
      'source_frame_id_available': sourceFrameIdAvailable,
      'source_lineage_available': sourceLineageAvailable,
      'source_lineage_reason': reason,
    };
  }

  Map<String, Object?>? _preferredLaneEvent(
    List<Map<String, Object?>> events, {
    bool requireVisibleRender = false,
  }) {
    if (events.isEmpty) {
      return null;
    }
    final reversed = events.reversed;
    if (requireVisibleRender) {
      for (final event in reversed) {
        if (_renderEventIsVisible(event) && _eventHasFrameHashTap(event)) {
          return event;
        }
      }
      for (final event in events.reversed) {
        if (_renderEventIsVisible(event)) {
          return event;
        }
      }
    }
    for (final event in events.reversed) {
      if (_eventHasFrameHashTap(event)) {
        return event;
      }
    }
    return events.last;
  }

  bool _eventHasFrameHashTap(Map<String, Object?> event) {
    return _stringValue(event['freshness_source']) == 'frame_hash_tap' &&
        _doubleValue(event['unique_fps']) != null;
  }

  Map<String, Object?> _augmentEvent(Map<String, Object?> event) {
    return {
      'schema_version': 1,
      ...event,
      'diagnostic_contract': _diagnosticContract,
      'protected_ipc': true,
      'frame_diagnostics_mode': invocation.frameDiagnosticsMode.label,
      'native_frame_hash_diagnostics_enabled':
          invocation.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash,
    };
  }

  String _statusForEvents({
    required List<Map<String, Object?>> decodeEvents,
    required List<Map<String, Object?>> renderEvents,
    required Map<String, Object?>? latestTarget,
  }) {
    if (_events.isEmpty) {
      return 'inconclusive_no_receiver_probe_events';
    }
    if (decodeEvents.isEmpty) {
      return 'inconclusive_missing_remote_decode_events';
    }
    if (invocation.mode == MatrixLivekitReceiverProbeMode.render &&
        renderEvents.isEmpty) {
      return 'inconclusive_missing_remote_renderer_callback_events';
    }
    if (invocation.mode == MatrixLivekitReceiverProbeMode.render &&
        !renderEvents.any(_renderEventIsVisible)) {
      return 'invalid_remote_renderer_callback_not_visible';
    }
    if (invocation.frameDiagnosticsMode ==
        MatrixLivekitReceiverProbeFrameDiagnosticsMode.statsOnly) {
      return 'completed_stats_only_receiver_probe_events';
    }
    if (_doubleValue(latestTarget?['unique_fps']) == null) {
      return 'inconclusive_frame_hash_tap_pending';
    }
    if (_stringValue(latestTarget?['freshness_source']) != 'frame_hash_tap') {
      return 'inconclusive_frame_hash_tap_pending';
    }
    return 'completed_receiver_probe_events';
  }

  String _blockingReasonForStatus(
    String status,
    Map<String, Object?>? latestTarget,
  ) {
    return switch (status) {
      'completed_receiver_probe_events' => '',
      'inconclusive_no_receiver_probe_events' =>
        'The external receiver probe produced no redacted events.',
      'inconclusive_missing_remote_decode_events' =>
        'No remote_decode receiver events were observed.',
      'inconclusive_missing_remote_renderer_callback_events' =>
        'Render mode did not produce remote_renderer_callback events.',
      'invalid_remote_renderer_callback_not_visible' =>
        'Render mode requires renderer_attached=true and renderer_visible=true.',
      'completed_stats_only_receiver_probe_events' => '',
      'inconclusive_frame_hash_tap_pending' =>
        _doubleValue(latestTarget?['unique_fps']) == null
            ? 'Receiver stats were observed, but frame hash taps did not report unique_fps.'
            : 'Receiver unique_fps was present, but freshness_source was not frame_hash_tap.',
      _ => 'External receiver probe reported a non-passing status.',
    };
  }

  Map<String, Object?> _freshnessFromEvent({
    required String lane,
    required Map<String, Object?>? event,
    required String status,
    required String reason,
  }) {
    return {
      'schema_version': 1,
      'marker': intergalacticStreamViewProbeMarker,
      'status': status,
      'blocking_reason': reason,
      'run_id': invocation.runId,
      'lane': lane,
      'stage': _stringValue(event?['stage']),
      'sample_time_utc':
          _stringValue(event?['sample_time_utc']) ??
          DateTime.now().toUtc().toIso8601String(),
      'diagnostic_contract': _diagnosticContract,
      'protected_ipc': true,
      'frame_diagnostics_mode': invocation.frameDiagnosticsMode.label,
      'native_frame_hash_diagnostics_enabled':
          invocation.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash,
      'in_process': false,
      'room_hash': _stringValue(event?['room_hash']) ?? 'unknown',
      'publisher_identity_hash':
          _stringValue(event?['publisher_identity_hash']) ?? 'unknown',
      'receiver_identity_hash':
          _stringValue(event?['receiver_identity_hash']) ?? 'unknown',
      'track_sid_hash': _stringValue(event?['track_sid_hash']) ?? 'unknown',
      'track_source': _stringValue(event?['track_source']) ?? 'screenshare',
      'subscription_state':
          _stringValue(event?['subscription_state']) ?? 'unknown',
      'subscribed_quality':
          _stringValue(event?['subscribed_quality']) ?? 'unknown',
      'simulcast_layer': _stringValue(event?['simulcast_layer']) ?? 'unknown',
      'codec': _stringValue(event?['codec']) ?? 'unknown',
      'decoder_implementation':
          _stringValue(event?['decoder_implementation']) ?? 'unknown',
      'hardware_decode': event?['hardware_decode'] ?? 'unknown',
      'renderer_attached': _boolValue(event?['renderer_attached']) ?? false,
      'renderer_visible': _boolValue(event?['renderer_visible']) ?? false,
      'renderer_width': _intValue(event?['renderer_width']) ?? 0,
      'renderer_height': _intValue(event?['renderer_height']) ?? 0,
      'bitrate_bps': _intValue(event?['bitrate_bps']),
      'inbound_bitrate_bps':
          _intValue(event?['inbound_bitrate_bps']) ??
          _intValue(event?['bitrate_bps']),
      'received_width': _intValue(event?['received_width']),
      'received_height': _intValue(event?['received_height']),
      'decoded_width': _intValue(event?['decoded_width']),
      'decoded_height': _intValue(event?['decoded_height']),
      'rendered_width': _intValue(event?['rendered_width']),
      'rendered_height': _intValue(event?['rendered_height']),
      'receiver_fps': _doubleValue(event?['receiver_fps']),
      'received_fps': _doubleValue(event?['received_fps']),
      'decoded_fps': _doubleValue(event?['decoded_fps']),
      'rendered_fps': _doubleValue(event?['rendered_fps']),
      'receiver_stats_sample_window_ms': _doubleValue(
        event?['receiver_stats_sample_window_ms'],
      ),
      'packets_received': _intValue(event?['packets_received']),
      'packets_lost': _intValue(event?['packets_lost']),
      'receiver_jitter_ms': _doubleValue(event?['receiver_jitter_ms']),
      'pli_count': _intValue(event?['pli_count']),
      'pli_delta': _intValue(event?['pli_delta']),
      'fir_count': _intValue(event?['fir_count']),
      'fir_delta': _intValue(event?['fir_delta']),
      'nack_count': _intValue(event?['nack_count']),
      'nack_delta': _intValue(event?['nack_delta']),
      'key_frames_decoded': _intValue(event?['key_frames_decoded']),
      'key_frames_decoded_delta': _intValue(event?['key_frames_decoded_delta']),
      'keyframe_interval_frames': _intValue(event?['keyframe_interval_frames']),
      'keyframe_interval_ms': _doubleValue(event?['keyframe_interval_ms']),
      'qp_sum': _intValue(event?['qp_sum']),
      'average_qp': _doubleValue(event?['average_qp']),
      'frames_received': _intValue(event?['frames_received']) ?? 0,
      'frames_decoded': _intValue(event?['frames_decoded']) ?? 0,
      'frames_rendered': _intValue(event?['frames_rendered']) ?? 0,
      'render_fps': _doubleValue(event?['render_fps']),
      'freshness_source': _stringValue(event?['freshness_source']),
      'frame_hash_algorithm': _stringValue(event?['frame_hash_algorithm']),
      'frame_hash_sample_count': _intValue(event?['frame_hash_sample_count']),
      'frame_hash_error_count': _intValue(event?['frame_hash_error_count']),
      'last_frame_captured_at_utc': _stringValue(
        event?['last_frame_captured_at_utc'],
      ),
      'unique_frames': _intValue(event?['unique_frames']),
      'duplicate_frames': _intValue(event?['duplicate_frames']),
      'unique_fps': _doubleValue(event?['unique_fps']),
      'p50_gap_ms': _doubleValue(event?['p50_gap_ms']),
      'p95_gap_ms': _doubleValue(event?['p95_gap_ms']),
      'max_gap_ms': _doubleValue(event?['max_gap_ms']),
      'longest_stale_run_ms': _doubleValue(event?['longest_stale_run_ms']),
      'frame_presentation_p50_gap_ms': _doubleValue(
        event?['frame_presentation_p50_gap_ms'],
      ),
      'frame_presentation_p95_gap_ms': _doubleValue(
        event?['frame_presentation_p95_gap_ms'],
      ),
      'frame_presentation_max_gap_ms': _doubleValue(
        event?['frame_presentation_max_gap_ms'],
      ),
      'frame_presentation_latest_gap_ms': _doubleValue(
        event?['frame_presentation_latest_gap_ms'],
      ),
      'perceptual_difference_score': _doubleValue(
        event?['perceptual_difference_score'],
      ),
      'native_frame_sequence': _intValue(event?['native_frame_sequence']),
      'native_frame_sequence_gaps': _intValue(
        event?['native_frame_sequence_gaps'],
      ),
      'native_frame_event_delay_ms': _doubleValue(
        event?['native_frame_event_delay_ms'],
      ),
      'native_frame_event_delay_max_ms': _doubleValue(
        event?['native_frame_event_delay_max_ms'],
      ),
      'dropped_or_replaced_texture_updates': _intValue(
        event?['dropped_or_replaced_texture_updates'],
      ),
      'upscaling_lower_layer_suspected': _boolValue(
        event?['upscaling_lower_layer_suspected'],
      ),
      'adaptive_stream_low_layer_suspected': _boolValue(
        event?['adaptive_stream_low_layer_suspected'],
      ),
      'stage_source': _stringValue(event?['stage_source']),
      'stage_observed_at_utc': _stringValue(event?['stage_observed_at_utc']),
      'stage_observed_gap_ms': _doubleValue(event?['stage_observed_gap_ms']),
      'stage_frame_age_ms': _doubleValue(event?['stage_frame_age_ms']),
      'stage_native_frame_sequence': _intValue(
        event?['stage_native_frame_sequence'],
      ),
      'stage_frame_captured_at_utc': _stringValue(
        event?['stage_frame_captured_at_utc'],
      ),
      'renderer_texture_id': _intValue(event?['renderer_texture_id']),
      'renderer_callback_to_stage_ms': _doubleValue(
        event?['renderer_callback_to_stage_ms'],
      ),
      'jitter_buffer_delay_ms': _doubleValue(event?['jitter_buffer_delay_ms']),
      'jitter_buffer_emitted_count': _intValue(
        event?['jitter_buffer_emitted_count'],
      ),
      'total_decode_time_ms': _doubleValue(event?['total_decode_time_ms']),
      'average_decode_time_ms': _doubleValue(event?['average_decode_time_ms']),
      'frames_dropped': _intValue(event?['frames_dropped']),
      'freeze_count': _intValue(event?['freeze_count']),
      'total_freeze_duration_ms': _doubleValue(
        event?['total_freeze_duration_ms'],
      ),
      'receive_to_decode_ms': _doubleValue(event?['receive_to_decode_ms']),
      'decode_to_render_ms': _doubleValue(event?['decode_to_render_ms']),
      'frame_id': _intValue(event?['frame_id']),
      'frame_id_source': _stringValue(event?['frame_id_source']),
      'source_frame_marker_id': _intValue(event?['source_frame_marker_id']),
      'source_frame_marker_decoded_frames': _intValue(
        event?['source_frame_marker_decoded_frames'],
      ),
      'source_frame_marker_unique_frames': _intValue(
        event?['source_frame_marker_unique_frames'],
      ),
      'source_frame_marker_duplicate_frames': _intValue(
        event?['source_frame_marker_duplicate_frames'],
      ),
      'source_frame_marker_unique_fps': _doubleValue(
        event?['source_frame_marker_unique_fps'],
      ),
      'source_frame_marker_longest_stale_run_ms': _doubleValue(
        event?['source_frame_marker_longest_stale_run_ms'],
      ),
      'source_qpc': _intValue(event?['source_qpc']),
      'stage_qpc': _intValue(event?['stage_qpc']),
      'frame_age_ms': _doubleValue(event?['frame_age_ms']),
      'previous_frame_id': _intValue(event?['previous_frame_id']),
      'sender_frame_id': _intValue(event?['frame_id']),
      'sender_to_render_ms': null,
    };
  }

  Map<String, Object?> _summary({
    required String status,
    required String reason,
    required MatrixLivekitReceiverProbeSnapshot snapshot,
    required Map<String, Object?>? latestDecode,
    required Map<String, Object?>? latestRender,
  }) {
    final targetEvent = invocation.mode == MatrixLivekitReceiverProbeMode.render
        ? latestRender
        : latestDecode;
    final windowFrameCadenceSummary = windowFrameCadence.summary();
    final targetEvents =
        invocation.mode == MatrixLivekitReceiverProbeMode.render
        ? _laneEvents(
            MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
          ).where(_renderEventIsVisible).toList()
        : _laneEvents('remote_decode');
    final uniqueFpsStats = _fieldStats(targetEvents, 'unique_fps');
    final sourceFrameMarkerUniqueFpsStats = _fieldStats(
      targetEvents,
      'source_frame_marker_unique_fps',
    );
    final receiverFpsStats = _fieldStats(targetEvents, 'receiver_fps');
    final receivedFpsStats = _fieldStats(targetEvents, 'received_fps');
    final decodedFpsStats = _fieldStats(targetEvents, 'decoded_fps');
    final renderedFpsStats = _fieldStats(targetEvents, 'rendered_fps');
    final presentationP95Stats = _fieldStats(
      targetEvents,
      'frame_presentation_p95_gap_ms',
    );
    final receivedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'received_width',
      heightField: 'received_height',
    );
    final decodedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'decoded_width',
      heightField: 'decoded_height',
    );
    final renderedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'rendered_width',
      heightField: 'rendered_height',
    );
    final targetSubscriptionState = _stringValue(
      targetEvent?['subscription_state'],
    );
    final summarySubscribed = targetSubscriptionState == null
        ? snapshot.subscribed
        : targetSubscriptionState == 'subscribed' ||
              targetSubscriptionState == 'local';
    final summarySnapshotStatus = targetSubscriptionState ?? snapshot.status;
    final sourceLineageSummary = _sourceLineageSummary();
    return {
      'schema_version': 1,
      'status': status,
      'blocking_reason': reason,
      'run_id': invocation.runId,
      'mode': invocation.mode.label,
      'duration_seconds': invocation.duration.inSeconds,
      'expected_width': invocation.expectedWidth,
      'expected_height': invocation.expectedHeight,
      'expected_fps': invocation.expectedFps,
      'visual_frame_marker': invocation.visualFrameMarker,
      'frame_diagnostics_mode': invocation.frameDiagnosticsMode.label,
      'native_frame_hash_diagnostics_enabled':
          invocation.frameDiagnosticsMode ==
          MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash,
      'created_utc': DateTime.now().toUtc().toIso8601String(),
      'diagnostic_contract': _diagnosticContract,
      'protected_ipc': true,
      'in_process': false,
      'credentials_received': invocation.credentialsReceived,
      'sfu_url_received': invocation.sfuUrlReceived,
      'jwt_received': invocation.jwtReceived,
      'expires_in_seconds_received': invocation.expiresInSecondsReceived,
      'event_count': _events.length,
      'remote_decode_event_count': _laneEvents('remote_decode').length,
      'remote_renderer_callback_lane_event_count': _laneEvents(
        MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
      ).length,
      'legacy_renderer_callback_lane_event_count': _events
          .where((event) => _stringValue(event['lane']) == 'remote_render')
          .length,
      'remote_renderer_callback_event_count': _stageEvents(
        MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
      ).length,
      'remote_texture_ready_event_count': _stageEvents(
        MatrixLivekitReceiverProbePresentationStage.remoteTextureReady,
      ).length,
      'remote_ui_paint_event_count': _stageEvents(
        MatrixLivekitReceiverProbePresentationStage.remoteUiPaint,
      ).length,
      'remote_screen_present_event_count': _stageEvents(
        MatrixLivekitReceiverProbePresentationStage.remoteScreenPresent,
      ).length,
      'receiver_presentation_stages': _presentationStages(),
      ...sourceLineageSummary,
      'visual_frame_marker_source_linked':
          invocation.visualFrameMarker &&
          sourceLineageSummary['source_frame_id_available'] == true,
      'connected': snapshot.connected,
      'subscribed': summarySubscribed,
      'sample_count': snapshot.sampleCount,
      'target_event_count': targetEvents.length,
      'snapshot_status': summarySnapshotStatus,
      'renderer_attached':
          _boolValue(latestRender?['renderer_attached']) ??
          _boolValue(latestDecode?['renderer_attached']) ??
          false,
      'renderer_visible':
          _boolValue(latestRender?['renderer_visible']) ??
          _boolValue(latestDecode?['renderer_visible']) ??
          false,
      'renderer_width':
          _intValue(latestRender?['renderer_width']) ??
          _intValue(latestDecode?['renderer_width']) ??
          0,
      'renderer_height':
          _intValue(latestRender?['renderer_height']) ??
          _intValue(latestDecode?['renderer_height']) ??
          0,
      'decode_freshness_source': _stringValue(
        latestDecode?['freshness_source'],
      ),
      'render_freshness_source': _stringValue(
        latestRender?['freshness_source'],
      ),
      'freshness_source': _stringValue(targetEvent?['freshness_source']),
      'decode_unique_fps': _doubleValue(latestDecode?['unique_fps']),
      'render_unique_fps': _doubleValue(latestRender?['unique_fps']),
      'unique_fps': _doubleValue(targetEvent?['unique_fps']),
      'unique_fps_min': uniqueFpsStats.min,
      'unique_fps_p50': uniqueFpsStats.p50,
      'unique_fps_average': uniqueFpsStats.average,
      'unique_fps_max': uniqueFpsStats.max,
      'decode_source_frame_marker_unique_fps': _doubleValue(
        latestDecode?['source_frame_marker_unique_fps'],
      ),
      'render_source_frame_marker_unique_fps': _doubleValue(
        latestRender?['source_frame_marker_unique_fps'],
      ),
      'source_frame_marker_id': _intValue(
        targetEvent?['source_frame_marker_id'],
      ),
      'source_frame_marker_decoded_frames': _intValue(
        targetEvent?['source_frame_marker_decoded_frames'],
      ),
      'source_frame_marker_unique_frames': _intValue(
        targetEvent?['source_frame_marker_unique_frames'],
      ),
      'source_frame_marker_duplicate_frames': _intValue(
        targetEvent?['source_frame_marker_duplicate_frames'],
      ),
      'source_frame_marker_unique_fps': _doubleValue(
        targetEvent?['source_frame_marker_unique_fps'],
      ),
      'source_frame_marker_unique_fps_min': sourceFrameMarkerUniqueFpsStats.min,
      'source_frame_marker_unique_fps_p50': sourceFrameMarkerUniqueFpsStats.p50,
      'source_frame_marker_unique_fps_average':
          sourceFrameMarkerUniqueFpsStats.average,
      'source_frame_marker_unique_fps_max': sourceFrameMarkerUniqueFpsStats.max,
      'source_frame_marker_longest_stale_run_ms': _doubleValue(
        targetEvent?['source_frame_marker_longest_stale_run_ms'],
      ),
      'subscription_state': targetSubscriptionState ?? 'unknown',
      'subscribed_quality':
          _stringValue(targetEvent?['subscribed_quality']) ?? 'unknown',
      'simulcast_layer':
          _stringValue(targetEvent?['simulcast_layer']) ?? 'unknown',
      'codec': _stringValue(targetEvent?['codec']) ?? 'unknown',
      'decoder_implementation':
          _stringValue(targetEvent?['decoder_implementation']) ?? 'unknown',
      'hardware_decode': targetEvent?['hardware_decode'] ?? 'unknown',
      'inbound_bitrate_bps':
          _intValue(targetEvent?['inbound_bitrate_bps']) ??
          _intValue(targetEvent?['bitrate_bps']),
      'received_width':
          receivedDimensions?.width ??
          _intValue(targetEvent?['received_width']),
      'received_height':
          receivedDimensions?.height ??
          _intValue(targetEvent?['received_height']),
      'decoded_width':
          decodedDimensions?.width ?? _intValue(targetEvent?['decoded_width']),
      'decoded_height':
          decodedDimensions?.height ??
          _intValue(targetEvent?['decoded_height']),
      'rendered_width':
          renderedDimensions?.width ??
          _intValue(targetEvent?['rendered_width']),
      'rendered_height':
          renderedDimensions?.height ??
          _intValue(targetEvent?['rendered_height']),
      'receiver_fps': _doubleValue(targetEvent?['receiver_fps']),
      'receiver_fps_min': receiverFpsStats.min,
      'receiver_fps_p50': receiverFpsStats.p50,
      'receiver_fps_average': receiverFpsStats.average,
      'receiver_fps_max': receiverFpsStats.max,
      'received_fps': _doubleValue(targetEvent?['received_fps']),
      'received_fps_min': receivedFpsStats.min,
      'received_fps_p50': receivedFpsStats.p50,
      'received_fps_average': receivedFpsStats.average,
      'received_fps_max': receivedFpsStats.max,
      'decoded_fps': _doubleValue(targetEvent?['decoded_fps']),
      'decoded_fps_min': decodedFpsStats.min,
      'decoded_fps_p50': decodedFpsStats.p50,
      'decoded_fps_average': decodedFpsStats.average,
      'decoded_fps_max': decodedFpsStats.max,
      'rendered_fps': _doubleValue(targetEvent?['rendered_fps']),
      'rendered_fps_min': renderedFpsStats.min,
      'rendered_fps_p50': renderedFpsStats.p50,
      'rendered_fps_average': renderedFpsStats.average,
      'rendered_fps_max': renderedFpsStats.max,
      'receiver_stats_sample_window_ms': _doubleValue(
        targetEvent?['receiver_stats_sample_window_ms'],
      ),
      'average_qp': _doubleValue(targetEvent?['average_qp']),
      'key_frames_decoded': _intValue(targetEvent?['key_frames_decoded']),
      'keyframe_interval_frames': _intValue(
        targetEvent?['keyframe_interval_frames'],
      ),
      'keyframe_interval_ms': _doubleValue(
        targetEvent?['keyframe_interval_ms'],
      ),
      'pli_count': _intValue(targetEvent?['pli_count']),
      'fir_count': _intValue(targetEvent?['fir_count']),
      'nack_count': _intValue(targetEvent?['nack_count']),
      'frame_presentation_p95_gap_ms': _doubleValue(
        targetEvent?['frame_presentation_p95_gap_ms'],
      ),
      'frame_presentation_p95_gap_ms_min': presentationP95Stats.min,
      'frame_presentation_p95_gap_ms_p50': presentationP95Stats.p50,
      'frame_presentation_p95_gap_ms_average': presentationP95Stats.average,
      'frame_presentation_p95_gap_ms_max': presentationP95Stats.max,
      'frame_presentation_max_gap_ms': _doubleValue(
        targetEvent?['frame_presentation_max_gap_ms'],
      ),
      'perceptual_difference_score': _doubleValue(
        targetEvent?['perceptual_difference_score'],
      ),
      'longest_stale_run_ms': _doubleValue(
        targetEvent?['longest_stale_run_ms'],
      ),
      'dropped_or_replaced_texture_updates': _intValue(
        targetEvent?['dropped_or_replaced_texture_updates'],
      ),
      'latest_target_stage': _stageForEvent(targetEvent),
      'stage_source': _stringValue(targetEvent?['stage_source']),
      'stage_observed_gap_ms': _doubleValue(
        targetEvent?['stage_observed_gap_ms'],
      ),
      'renderer_callback_to_stage_ms': _doubleValue(
        targetEvent?['renderer_callback_to_stage_ms'],
      ),
      'receiver_window_flutter_frame_count':
          windowFrameCadenceSummary.frameCount,
      'receiver_window_flutter_frame_gap_p50_ms':
          windowFrameCadenceSummary.gapP50Ms,
      'receiver_window_flutter_frame_gap_p95_ms':
          windowFrameCadenceSummary.gapP95Ms,
      'receiver_window_flutter_frame_gap_max_ms':
          windowFrameCadenceSummary.gapMaxMs,
      'receiver_window_flutter_frame_gap_latest_ms':
          windowFrameCadenceSummary.gapLatestMs,
      'receiver_window_flutter_frame_gaps_over_50ms':
          windowFrameCadenceSummary.gapsOver50Ms,
      'receiver_window_flutter_frame_gaps_over_100ms':
          windowFrameCadenceSummary.gapsOver100Ms,
      'receiver_window_flutter_frame_gaps_over_200ms':
          windowFrameCadenceSummary.gapsOver200Ms,
      'upscaling_lower_layer_suspected': _boolValue(
        targetEvent?['upscaling_lower_layer_suspected'],
      ),
      'adaptive_stream_low_layer_suspected': _boolValue(
        targetEvent?['adaptive_stream_low_layer_suspected'],
      ),
      'capabilities': {
        'livekit_connect': snapshot.connected,
        'decode_frame_hash_tap':
            _stringValue(latestDecode?['freshness_source']) == 'frame_hash_tap',
        'render_frame_hash_tap':
            _stringValue(latestRender?['freshness_source']) == 'frame_hash_tap',
        'renderer_callback_stage': _stageEvents(
          MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
        ).isNotEmpty,
        'texture_ready_stage': _stageEvents(
          MatrixLivekitReceiverProbePresentationStage.remoteTextureReady,
        ).isNotEmpty,
        'ui_paint_stage': _stageEvents(
          MatrixLivekitReceiverProbePresentationStage.remoteUiPaint,
        ).isNotEmpty,
        'screen_present_stage': _stageEvents(
          MatrixLivekitReceiverProbePresentationStage.remoteScreenPresent,
        ).isNotEmpty,
        'protected_ipc': true,
        'native_frame_hash_diagnostics_enabled':
            invocation.frameDiagnosticsMode ==
            MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash,
      },
      'outputs': [
        'receiver-summary.json',
        'receiver-summary.md',
        'events.jsonl',
        'decoded-freshness.json',
        'rendered-freshness.json',
      ],
    };
  }

  Future<void> _writeJsonFile(String name, Map<String, Object?> value) async {
    await File('${invocation.outputDir.path}/$name').writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  Future<void> _writeMarkdownSummary(String status, String reason) async {
    final decodeEvents = _laneEvents('remote_decode');
    final renderEvents = _laneEvents(
      MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback,
    );
    final latestDecode = _preferredLaneEvent(decodeEvents);
    final latestRender = _preferredLaneEvent(
      renderEvents,
      requireVisibleRender: true,
    );
    final targetEvent = invocation.mode == MatrixLivekitReceiverProbeMode.render
        ? latestRender
        : latestDecode;
    final windowFrameCadenceSummary = windowFrameCadence.summary();
    final targetEvents =
        invocation.mode == MatrixLivekitReceiverProbeMode.render
        ? renderEvents.where(_renderEventIsVisible).toList()
        : decodeEvents;
    final uniqueFpsStats = _fieldStats(targetEvents, 'unique_fps');
    final receivedFpsStats = _fieldStats(targetEvents, 'received_fps');
    final decodedFpsStats = _fieldStats(targetEvents, 'decoded_fps');
    final renderedFpsStats = _fieldStats(targetEvents, 'rendered_fps');
    final presentationP95Stats = _fieldStats(
      targetEvents,
      'frame_presentation_p95_gap_ms',
    );
    final receivedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'received_width',
      heightField: 'received_height',
    );
    final decodedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'decoded_width',
      heightField: 'decoded_height',
    );
    final renderedDimensions = _dominantDimensions(
      targetEvents,
      widthField: 'rendered_width',
      heightField: 'rendered_height',
    );
    final targetSubscriptionState = _stringValue(
      targetEvent?['subscription_state'],
    );
    final sourceLineageSummary = _sourceLineageSummary();
    final visualFrameMarkerSourceLinked =
        invocation.visualFrameMarker &&
        sourceLineageSummary['source_frame_id_available'] == true;
    final lines = [
      '# Receiver Probe ${invocation.runId}',
      '',
      '- status: $status',
      '- mode: ${invocation.mode.label}',
      '- protected_ipc: true',
      '- in_process: false',
      '- credentials_received: ${invocation.credentialsReceived}',
      '- sfu_url_received: ${invocation.sfuUrlReceived}',
      '- jwt_received: ${invocation.jwtReceived}',
      '- expires_in_seconds_received: ${invocation.expiresInSecondsReceived}',
      '- visual_frame_marker: ${invocation.visualFrameMarker}',
      '- frame_diagnostics_mode: ${invocation.frameDiagnosticsMode.label}',
      '- native_frame_hash_diagnostics_enabled: ${invocation.frameDiagnosticsMode == MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash}',
      '- visual_frame_marker_source_linked: $visualFrameMarkerSourceLinked',
      '- source_lineage: frame_id_events=${sourceLineageSummary['source_frame_id_event_count']}; previous_frame_id_events=${sourceLineageSummary['previous_frame_id_event_count']}; marker_id_events=${sourceLineageSummary['source_frame_marker_id_event_count']}; source_qpc_events=${sourceLineageSummary['source_qpc_event_count']}; stage_qpc_events=${sourceLineageSummary['stage_qpc_event_count']}; complete=${sourceLineageSummary['source_lineage_available']}; reason=${sourceLineageSummary['source_lineage_reason']}',
      '- events: ${_events.length}',
      '- remote_decode events: ${decodeEvents.length}',
      '- remote_renderer_callback lane events: ${renderEvents.length}',
      '- presentation_stages: ${_presentationStages().map((stage) => '${stage['stage']}=${stage['status']}').join('; ')}',
      '- decode_freshness_source: ${_stringValue(latestDecode?['freshness_source']) ?? ''}',
      '- render_freshness_source: ${_stringValue(latestRender?['freshness_source']) ?? ''}',
      '- decode_unique_fps: ${_doubleValue(latestDecode?['unique_fps']) ?? ''}',
      '- render_unique_fps: ${_doubleValue(latestRender?['unique_fps']) ?? ''}',
      '- decode_source_frame_marker_unique_fps: ${_doubleValue(latestDecode?['source_frame_marker_unique_fps']) ?? ''}',
      '- render_source_frame_marker_unique_fps: ${_doubleValue(latestRender?['source_frame_marker_unique_fps']) ?? ''}',
      '- source_frame_marker_longest_stale_run_ms: ${_doubleValue(targetEvent?['source_frame_marker_longest_stale_run_ms']) ?? ''}',
      '- target_event_count: ${targetEvents.length}',
      '- unique_fps p50/avg/min: ${uniqueFpsStats.p50 ?? ''}/${uniqueFpsStats.average ?? ''}/${uniqueFpsStats.min ?? ''}',
      '- subscription_state: ${targetSubscriptionState ?? ''}',
      '- subscribed_quality: ${_stringValue(targetEvent?['subscribed_quality']) ?? ''}',
      '- simulcast_layer: ${_stringValue(targetEvent?['simulcast_layer']) ?? ''}',
      '- inbound_bitrate_bps: ${_intValue(targetEvent?['inbound_bitrate_bps']) ?? _intValue(targetEvent?['bitrate_bps']) ?? ''}',
      '- received_size: ${_dimensionLabel(receivedDimensions, targetEvent, 'received')}',
      '- decoded_size: ${_dimensionLabel(decodedDimensions, targetEvent, 'decoded')}',
      '- rendered_size: ${_dimensionLabel(renderedDimensions, targetEvent, 'rendered')}',
      '- receiver_fps: ${_doubleValue(targetEvent?['receiver_fps']) ?? ''}',
      '- received_decoded_rendered_fps: ${_doubleValue(targetEvent?['received_fps']) ?? ''}/${_doubleValue(targetEvent?['decoded_fps']) ?? ''}/${_doubleValue(targetEvent?['rendered_fps']) ?? ''}',
      '- received_decoded_rendered_fps p50: ${receivedFpsStats.p50 ?? ''}/${decodedFpsStats.p50 ?? ''}/${renderedFpsStats.p50 ?? ''}',
      '- receiver_stats_sample_window_ms: ${_doubleValue(targetEvent?['receiver_stats_sample_window_ms']) ?? ''}',
      '- average_qp: ${_doubleValue(targetEvent?['average_qp']) ?? ''}',
      '- keyframe_interval_ms: ${_doubleValue(targetEvent?['keyframe_interval_ms']) ?? ''}',
      '- pli_fir_nack: ${_intValue(targetEvent?['pli_count']) ?? ''}/${_intValue(targetEvent?['fir_count']) ?? ''}/${_intValue(targetEvent?['nack_count']) ?? ''}',
      '- frame_presentation_p95_gap_ms: ${_doubleValue(targetEvent?['frame_presentation_p95_gap_ms']) ?? ''}',
      '- frame_presentation_p95_gap_ms p50/avg/max: ${presentationP95Stats.p50 ?? ''}/${presentationP95Stats.average ?? ''}/${presentationP95Stats.max ?? ''}',
      '- latest_target_stage: ${_stageForEvent(targetEvent) ?? ''}',
      '- renderer_callback_to_stage_ms: ${_doubleValue(targetEvent?['renderer_callback_to_stage_ms']) ?? ''}',
      '- longest_stale_run_ms: ${_doubleValue(targetEvent?['longest_stale_run_ms']) ?? ''}',
      '- receiver_window_flutter_frame_count: ${windowFrameCadenceSummary.frameCount}',
      '- receiver_window_flutter_frame_gap_p95_ms: ${windowFrameCadenceSummary.gapP95Ms ?? ''}',
      '- receiver_window_flutter_frame_gap_max_ms: ${windowFrameCadenceSummary.gapMaxMs ?? ''}',
      '- receiver_window_flutter_frame_gaps_over_100ms: ${windowFrameCadenceSummary.gapsOver100Ms}',
      '- perceptual_difference_score: ${_doubleValue(targetEvent?['perceptual_difference_score']) ?? ''}',
      '- upscaling_lower_layer_suspected: ${_boolValue(targetEvent?['upscaling_lower_layer_suspected']) ?? ''}',
      '- adaptive_stream_low_layer_suspected: ${_boolValue(targetEvent?['adaptive_stream_low_layer_suspected']) ?? ''}',
      '',
      'Blocking reason: $reason',
      '',
      'No LiveKit token, Matrix id, room id, track id, or raw video content is written by this probe runtime.',
    ];
    await File(
      '${invocation.outputDir.path}/receiver-summary.md',
    ).writeAsString('${lines.join('\n')}\n', flush: true);
  }
}

class _ExternalLivekitReceiverProbeApp extends StatefulWidget {
  const _ExternalLivekitReceiverProbeApp({
    required this.controller,
    required this.mode,
    required this.visualFrameMarker,
    required this.windowFrameCadence,
  });

  final MatrixLivekitReceiverProbeController controller;
  final MatrixLivekitReceiverProbeMode mode;
  final bool visualFrameMarker;
  final _ReceiverWindowFrameCadenceProbe windowFrameCadence;

  @override
  State<_ExternalLivekitReceiverProbeApp> createState() =>
      _ExternalLivekitReceiverProbeAppState();
}

class _ExternalLivekitReceiverProbeAppState
    extends State<_ExternalLivekitReceiverProbeApp> {
  StreamSubscription<MatrixLivekitReceiverProbeEvent>? _subscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    widget.windowFrameCadence.start();
    widget.controller.setRendererVisible(
      widget.mode == MatrixLivekitReceiverProbeMode.render,
    );
    _subscription = widget.controller.events.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.controller.setRendererVisible(false);
    widget.windowFrameCadence.stop();
    final subscription = _subscription;
    _subscription = null;
    unawaited(_cancelExternalReceiverProbeWidgetSubscription(subscription));
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: IgnorePointer(
          child: SizedBox.expand(
            child: _buildRenderer(widget.controller.renderer),
          ),
        ),
      ),
    );
  }

  void _recordTextureReady() {
    widget.controller.recordRendererTextureReady(
      source: 'external_receiver_probe_rtc_video_view',
    );
  }

  void _recordUiPaint() {
    widget.controller.recordRendererUiPaint(
      source: 'external_receiver_probe_custom_painter',
    );
  }

  Widget _buildRenderer(rtc.RTCVideoRenderer? renderer) {
    if (renderer == null) {
      return const ColoredBox(color: Colors.black);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recordTextureReady();
      }
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        rtc.RTCVideoView(
          renderer,
          objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
        CustomPaint(
          painter: _ReceiverProbePaintObserver(
            event: widget.controller.snapshot.lastEvent,
            onPainted: _recordUiPaint,
            visualFrameMarker: widget.visualFrameMarker,
          ),
        ),
      ],
    );
  }
}

class _ReceiverProbePaintObserver extends CustomPainter {
  _ReceiverProbePaintObserver({
    required this.event,
    required this.onPainted,
    required this.visualFrameMarker,
  });

  final MatrixLivekitReceiverProbeEvent? event;
  final VoidCallback onPainted;
  final bool visualFrameMarker;

  @override
  void paint(Canvas canvas, Size size) {
    if (visualFrameMarker) {
      _paintVisualFrameMarker(canvas, size);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => onPainted());
  }

  void _paintVisualFrameMarker(Canvas canvas, Size size) {
    final markerValue = _visualFrameMarkerValue(event);
    final markerWidth = math.min(240.0, math.max(120.0, size.width * 0.20));
    final markerHeight = markerWidth * 0.40;
    final origin = Offset(
      12.0,
      math.max(12.0, size.height - markerHeight - 12.0),
    );
    final bounds = origin & Size(markerWidth, markerHeight);
    final backgroundPaint = Paint()..color = const Color(0xE6000000);
    final borderPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(bounds, backgroundPaint);
    canvas.drawRect(bounds.deflate(1.0), borderPaint);

    const columns = 12;
    const rows = 4;
    final cellGap = math.max(1.0, markerWidth * 0.006);
    final cellWidth = (markerWidth - (cellGap * (columns + 1))) / columns;
    final cellHeight = (markerHeight - (cellGap * (rows + 1))) / rows;
    final brightPaint = Paint()..color = const Color(0xFFFFFFFF);
    final dimPaint = Paint()..color = const Color(0xFF202020);
    final accentPaint = Paint()..color = const Color(0xFF00E5FF);
    var mixed = markerValue & 0x7fffffff;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        mixed = (mixed * 1103515245 + 12345 + row + column) & 0x7fffffff;
        final cellOrigin = Offset(
          origin.dx + cellGap + column * (cellWidth + cellGap),
          origin.dy + cellGap + row * (cellHeight + cellGap),
        );
        final cellRect = cellOrigin & Size(cellWidth, cellHeight);
        final isAnchor = row == 0 && (column == 0 || column == columns - 1);
        final enabled = isAnchor || (mixed & 0x1) == 1;
        canvas.drawRect(
          cellRect,
          isAnchor
              ? accentPaint
              : enabled
              ? brightPaint
              : dimPaint,
        );
      }
    }
  }

  int _visualFrameMarkerValue(MatrixLivekitReceiverProbeEvent? event) {
    if (event == null) {
      return 0;
    }
    return event.frameId ?? 0;
  }

  @override
  bool shouldRepaint(_ReceiverProbePaintObserver oldDelegate) {
    return oldDelegate.onPainted != onPainted ||
        oldDelegate.visualFrameMarker != visualFrameMarker ||
        _visualFrameMarkerValue(oldDelegate.event) !=
            _visualFrameMarkerValue(event);
  }
}

class _ReceiverWindowFrameCadenceProbe {
  final List<double> _gapsMs = [];
  Duration? _lastFrameTimestamp;
  VoidCallback? onFramePresented;
  bool _running = false;
  int _frameCount = 0;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
    SchedulerBinding.instance.scheduleFrameCallback(_recordFrame);
  }

  void stop() {
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_recordFrameTimings);
  }

  void _recordFrame(Duration timestamp) {
    if (!_running) {
      return;
    }
    final previous = _lastFrameTimestamp;
    _lastFrameTimestamp = timestamp;
    _frameCount += 1;
    if (previous != null) {
      _gapsMs.add((timestamp - previous).inMicroseconds / 1000.0);
      if (_gapsMs.length > 10000) {
        _gapsMs.removeAt(0);
      }
    }
    SchedulerBinding.instance.scheduleFrameCallback(_recordFrame);
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    if (!_running || timings.isEmpty) {
      return;
    }
    final callback = onFramePresented;
    if (callback == null) {
      return;
    }
    for (var index = 0; index < timings.length; index++) {
      callback();
    }
  }

  _ReceiverWindowFrameCadenceSummary summary() {
    final gaps = List<double>.of(_gapsMs)..sort();
    return _ReceiverWindowFrameCadenceSummary(
      frameCount: _frameCount,
      gapP50Ms: _percentile(gaps, 0.50),
      gapP95Ms: _percentile(gaps, 0.95),
      gapMaxMs: gaps.isEmpty ? null : gaps.last,
      gapLatestMs: _gapsMs.isEmpty ? null : _gapsMs.last,
      gapsOver50Ms: _gapsMs.where((gap) => gap > 50.0).length,
      gapsOver100Ms: _gapsMs.where((gap) => gap > 100.0).length,
      gapsOver200Ms: _gapsMs.where((gap) => gap > 200.0).length,
    );
  }
}

class _ReceiverWindowFrameCadenceSummary {
  const _ReceiverWindowFrameCadenceSummary({
    required this.frameCount,
    required this.gapP50Ms,
    required this.gapP95Ms,
    required this.gapMaxMs,
    required this.gapLatestMs,
    required this.gapsOver50Ms,
    required this.gapsOver100Ms,
    required this.gapsOver200Ms,
  });

  final int frameCount;
  final double? gapP50Ms;
  final double? gapP95Ms;
  final double? gapMaxMs;
  final double? gapLatestMs;
  final int gapsOver50Ms;
  final int gapsOver100Ms;
  final int gapsOver200Ms;
}

_DoubleFieldStats _fieldStats(List<Map<String, Object?>> events, String field) {
  final values = <double>[];
  for (final event in events) {
    final value = _doubleValue(event[field]);
    if (value != null) {
      values.add(value);
    }
  }
  values.sort();
  if (values.isEmpty) {
    return const _DoubleFieldStats();
  }
  final total = values.fold<double>(0, (sum, value) => sum + value);
  return _DoubleFieldStats(
    min: values.first,
    p50: _percentile(values, 0.50),
    average: total / values.length,
    max: values.last,
  );
}

_DimensionPair? _dominantDimensions(
  List<Map<String, Object?>> events, {
  required String widthField,
  required String heightField,
}) {
  final counts = <String, _DimensionCount>{};
  for (final event in events) {
    final width = _intValue(event[widthField]);
    final height = _intValue(event[heightField]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      continue;
    }
    final key = '${width}x$height';
    final previous = counts[key];
    if (previous == null) {
      counts[key] = _DimensionCount(_DimensionPair(width, height), 1);
    } else {
      counts[key] = _DimensionCount(previous.dimensions, previous.count + 1);
    }
  }
  if (counts.isEmpty) {
    return null;
  }
  final ranked = counts.values.toList()
    ..sort((left, right) {
      final countComparison = right.count.compareTo(left.count);
      if (countComparison != 0) {
        return countComparison;
      }
      return right.dimensions.area.compareTo(left.dimensions.area);
    });
  return ranked.first.dimensions;
}

class _DimensionPair {
  const _DimensionPair(this.width, this.height);

  final int width;
  final int height;

  int get area => width * height;
}

class _DimensionCount {
  const _DimensionCount(this.dimensions, this.count);

  final _DimensionPair dimensions;
  final int count;
}

class _DoubleFieldStats {
  const _DoubleFieldStats({this.min, this.p50, this.average, this.max});

  final double? min;
  final double? p50;
  final double? average;
  final double? max;
}

double? _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) {
    return null;
  }
  final clamped = percentile.clamp(0.0, 1.0);
  final index = (clamped * (sortedValues.length - 1)).round();
  return sortedValues[index];
}

MatrixLivekitReceiverProbeMode _parseMode(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'render') {
    return MatrixLivekitReceiverProbeMode.render;
  }
  return MatrixLivekitReceiverProbeMode.decodeOnly;
}

MatrixLivekitReceiverProbeFrameDiagnosticsMode _parseFrameDiagnosticsMode(
  String value,
) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'stats-only') {
    return MatrixLivekitReceiverProbeFrameDiagnosticsMode.statsOnly;
  }
  return MatrixLivekitReceiverProbeFrameDiagnosticsMode.nativeRendererHash;
}

String? _argValue(List<String> args, String key) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == key && index + 1 < args.length) {
      return args[index + 1];
    }
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  return null;
}

int _intArg(List<String> args, String key, int fallback) {
  return int.tryParse(_argValue(args, key) ?? '') ?? fallback;
}

String _utcStamp(DateTime value) {
  return value
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String? _firstString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _stringValue(json[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _firstInt(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _intValue(json[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

bool _renderEventIsVisible(Map<String, Object?> event) {
  return _boolValue(event['renderer_attached']) == true &&
      _boolValue(event['renderer_visible']) == true;
}

String? _stageForEvent(Map<String, Object?>? event) {
  final explicitStage = _stringValue(event?['stage']);
  if (explicitStage != null) {
    return explicitStage;
  }
  final lane = _stringValue(event?['lane']);
  if (lane ==
          MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback ||
      lane == 'remote_render') {
    return MatrixLivekitReceiverProbePresentationStage.remoteRendererCallback;
  }
  return lane;
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _dimensionLabel(
  _DimensionPair? dimensions,
  Map<String, Object?>? fallbackEvent,
  String prefix,
) {
  final width =
      dimensions?.width ?? _intValue(fallbackEvent?['${prefix}_width']);
  final height =
      dimensions?.height ?? _intValue(fallbackEvent?['${prefix}_height']);
  if (width == null || height == null) {
    return '';
  }
  return '${width}x$height';
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}
