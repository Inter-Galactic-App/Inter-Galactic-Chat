import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';

class StreamLiveTuningConfig {
  const StreamLiveTuningConfig({
    required this.enabled,
    this.experimentName,
    this.profile,
    this.maxWidth,
    this.maxHeight,
    this.maxFps,
    this.targetFps,
    this.bitrateKbps,
    this.minBitrateKbps,
    this.codec,
    this.preferHardwareEncoding,
    this.simulcast,
    this.singleLayer,
    this.dynacast,
    this.framePacing,
    this.fallbackMode,
    this.windowsCaptureBackendMode,
    this.applyProfileLive = true,
    this.loadError,
  });

  factory StreamLiveTuningConfig.disabled({String? loadError}) {
    return StreamLiveTuningConfig(
      enabled: false,
      loadError: loadError,
    );
  }

  factory StreamLiveTuningConfig.fromJson(Map<String, Object?> json) {
    return StreamLiveTuningConfig(
      enabled: _bool(json, 'enabled') ?? false,
      experimentName: _string(json, 'experimentName') ??
          _string(json, 'experiment') ??
          _string(json, 'name'),
      profile: _string(json, 'profile') ?? _string(json, 'preset'),
      maxWidth: _int(json, 'maxWidth') ?? _int(json, 'width'),
      maxHeight: _int(json, 'maxHeight') ?? _int(json, 'height'),
      maxFps: _int(json, 'maxFps') ??
          _int(json, 'fps') ??
          _int(json, 'maxFrameRate'),
      targetFps: _int(json, 'targetFps') ?? _int(json, 'targetFrameRate'),
      bitrateKbps: _int(json, 'bitrateKbps') ?? _int(json, 'maxBitrateKbps'),
      minBitrateKbps: _int(json, 'minBitrateKbps') ??
          _int(json, 'minBitrate') ??
          _intBpsAsKbps(json, 'minBitrateBps'),
      codec: _string(json, 'codec'),
      preferHardwareEncoding: _bool(json, 'preferHardwareEncoding') ??
          _bool(json, 'hardwareEncoding') ??
          _bool(json, 'hardware'),
      simulcast: _bool(json, 'simulcast'),
      singleLayer: _bool(json, 'singleLayer'),
      dynacast: _bool(json, 'dynacast'),
      framePacing: _bool(json, 'framePacing'),
      fallbackMode: _string(json, 'fallbackMode'),
      windowsCaptureBackendMode: _windowsBackend(json),
      applyProfileLive: _bool(json, 'applyProfileLive') ?? true,
    );
  }

  final bool enabled;
  final String? experimentName;
  final String? profile;
  final int? maxWidth;
  final int? maxHeight;
  final int? maxFps;
  final int? targetFps;
  final int? bitrateKbps;
  final int? minBitrateKbps;
  final String? codec;
  final bool? preferHardwareEncoding;
  final bool? simulcast;
  final bool? singleLayer;
  final bool? dynacast;
  final bool? framePacing;
  final String? fallbackMode;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final bool applyProfileLive;
  final String? loadError;

  bool get hasWindowsCaptureBackendOverride =>
      windowsCaptureBackendMode != null;

  bool get usesDirectxLiveBackend =>
      effectiveWindowsCaptureBackendMode ==
      WindowsScreenCaptureBackendMode.directxOnly;

  WindowsScreenCaptureBackendMode? get effectiveWindowsCaptureBackendMode {
    if (windowsCaptureBackendMode == null ||
        windowsCaptureBackendMode ==
            WindowsScreenCaptureBackendMode.platformDefault) {
      return null;
    }
    return windowsCaptureBackendMode;
  }

  bool get hasProfileOverrides {
    return profile != null ||
        maxWidth != null ||
        maxHeight != null ||
        maxFps != null ||
        targetFps != null ||
        bitrateKbps != null ||
        minBitrateKbps != null ||
        codec != null ||
        preferHardwareEncoding != null ||
        simulcast != null ||
        singleLayer != null;
  }

  List<String> get applicationNotes {
    final notes = <String>[];
    if (loadError != null) {
      notes.add('config_load_error=$loadError');
    }
    if (dynacast != null) {
      notes.add('dynacast_requires_room_reconnect');
    }
    if (framePacing != null) {
      notes.add('frame_pacing_is_native_build_or_app_default_only');
    }
    if (fallbackMode != null) {
      notes.add('fallback_mode_observe_only=$fallbackMode');
    }
    if (usesDirectxLiveBackend) {
      notes.add(
        'directx_live_backend_requires_stream_restart_before_next_backend',
      );
    }
    return List.unmodifiable(notes);
  }

  ScreenShareProfileConfig toScreenShareProfile(
    ScreenShareProfileConfig fallback,
  ) {
    if (!hasProfileOverrides) {
      return fallback;
    }

    final base = _profileForKey(profile) ?? fallback;
    final width = _clampDimension(maxWidth ?? base.mainLayer.width);
    final height = _clampDimension(maxHeight ?? base.mainLayer.height);
    final fps = _clampFps(maxFps ?? base.mainLayer.maxFramerate);
    final resolvedTargetFps = targetFps == null
        ? (maxFps == null ? base.mainLayer.targetFramerateForScoring : fps)
        : _clampFps(targetFps!).clamp(1, fps).toInt();
    final bitrate = _clampBitrateKbps(
      bitrateKbps ?? (base.mainLayer.maxBitrateBps / 1000).round(),
    );
    final preferHardware = preferHardwareEncoding ?? base.hardwareEncodeFirst;
    final minBitrate = _minBitrateBps(
      base: base,
      preferHardwareEncoding: preferHardware,
      maxBitrateBps: bitrate * 1000,
    );
    final normalizedCodec = (codec ?? base.codec).trim().toLowerCase();
    final useSingleLayer = singleLayer == true;
    final allowSimulcast = useSingleLayer
        ? false
        : (simulcast ?? base.useSimulcast) &&
            ScreenShareProfileConfig.codecSupportsSimulcast(normalizedCodec);

    var resolved = ScreenShareProfileConfig.advanced(
      bitrateMbps: bitrate / 1000,
      framerate: fps.toDouble(),
      codec: normalizedCodec.isEmpty ? base.codec : normalizedCodec,
      resolution: '${width}x$height',
      allowSimulcast: allowSimulcast,
    );
    if (preferHardware) {
      resolved = resolved.withHardwareEncodingPreference();
    }
    resolved = resolved.copyWith(
      mainLayer: resolved.mainLayer.copyWith(
        minBitrateBps: minBitrate,
        targetFramerate: resolvedTargetFps,
      ),
    );
    if (useSingleLayer) {
      resolved = resolved.copyWith(useSimulcast: false);
    }

    return resolved.copyWith(
      label: 'Stream Lab ${base.label}',
      description:
          '${resolved.mainLayer.resolutionLabel}, ${resolved.mainLayer.framerateDescription}, '
          '${resolved.codec.toUpperCase()}, '
          '${(resolved.mainLayer.maxBitrateBps / 1000000).toStringAsFixed(1)} Mbps, '
          '${resolved.useSimulcast ? 'simulcast' : 'single-layer'}.',
    );
  }

  String liveApplySignature({
    required ScreenShareProfileConfig profile,
    required String windowsCaptureBackendLabel,
  }) {
    return [
      profile.label,
      profile.mainLayer.width,
      profile.mainLayer.height,
      profile.mainLayer.maxFramerate,
      profile.mainLayer.targetFramerateForScoring,
      profile.mainLayer.maxBitrateBps,
      profile.mainLayer.minBitrateBps ?? 0,
      profile.codec,
      profile.useSimulcast,
      profile.hardwareEncodeFirst,
      windowsCaptureBackendLabel,
    ].join('|');
  }

  Map<String, Object?> toJson() {
    return {
      'schema': 'intergalactic.streamLiveTuningConfig.v1',
      'enabled': enabled,
      'experimentName': experimentName,
      'profile': profile,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'maxFps': maxFps,
      'targetFps': targetFps,
      'bitrateKbps': bitrateKbps,
      'minBitrateKbps': minBitrateKbps,
      'codec': codec,
      'preferHardwareEncoding': preferHardwareEncoding,
      'simulcast': simulcast,
      'singleLayer': singleLayer,
      'dynacast': dynacast,
      'framePacing': framePacing,
      'fallbackMode': fallbackMode,
      'windowsCaptureBackendMode': windowsCaptureBackendMode?.constraintValue,
      'applyProfileLive': applyProfileLive,
      'loadError': loadError,
      'applicationNotes': applicationNotes,
    };
  }

  static String? _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool? _bool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text == 'true' || text == 'yes' || text == 'on' || text == '1') {
      return true;
    }
    if (text == 'false' || text == 'no' || text == 'off' || text == '0') {
      return false;
    }
    return null;
  }

  static int? _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static int? _intBpsAsKbps(Map<String, Object?> json, String key) {
    final value = _int(json, key);
    if (value == null) {
      return null;
    }
    return (value / 1000).round();
  }

  int? _minBitrateBps({
    required ScreenShareProfileConfig base,
    required bool preferHardwareEncoding,
    required int maxBitrateBps,
  }) {
    final configuredMinKbps = minBitrateKbps;
    int? minBps;
    if (configuredMinKbps != null) {
      minBps = _clampBitrateKbps(configuredMinKbps) * 1000;
    } else if (preferHardwareEncoding) {
      minBps = base.withHardwareEncodingPreference().mainLayer.minBitrateBps;
    }
    if (minBps == null || minBps <= 0) {
      return null;
    }
    if (minBps > maxBitrateBps) {
      return maxBitrateBps;
    }
    return minBps;
  }

  static WindowsScreenCaptureBackendMode? _windowsBackend(
    Map<String, Object?> json,
  ) {
    final value = _string(json, 'windowsCaptureBackendMode') ??
        _string(json, 'windowsCaptureBackend') ??
        _string(json, 'captureBackend');
    if (value == null) {
      return null;
    }
    return WindowsScreenCaptureBackendModeDetails.fromConstraintValue(value);
  }

  static ScreenShareProfileConfig? _profileForKey(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'smooth' || '720' || '720p' => ScreenShareProfileConfig.smooth,
      'balanced' || '1080' || '1080p' => ScreenShareProfileConfig.balanced,
      'high' ||
      'highquality' ||
      'high-quality' ||
      'high_quality' =>
        ScreenShareProfileConfig.highQuality,
      _ => null,
    };
  }

  static int _clampDimension(int value) {
    return value.clamp(2, 7680).toInt();
  }

  static int _clampFps(int value) {
    return value.clamp(1, 120).toInt();
  }

  static int _clampBitrateKbps(int value) {
    return value.clamp(100, 64000).toInt();
  }
}

class StreamLiveTuningScore {
  const StreamLiveTuningScore({
    required this.stableFps,
    required this.targetResolution,
    required this.lowLoss,
    required this.lowRtt,
    required this.downgradePenalty,
  });

  factory StreamLiveTuningScore.fromSnapshot({
    required VoipCallDiagnosticsSnapshot snapshot,
    required ScreenShareProfileConfig profile,
  }) {
    final sender = bestSenderTrack(snapshot);
    if (sender == null) {
      return const StreamLiveTuningScore(
        stableFps: 0,
        targetResolution: 0,
        lowLoss: 0,
        lowRtt: 0,
        downgradePenalty: 30,
      );
    }

    final targetFps = profile.mainLayer.targetFramerateForScoring.toDouble();
    final fps = sender.sendFps ?? sender.encodeFps ?? sender.fps;
    final fpsRatio = fps == null || targetFps <= 0 ? 0.0 : fps / targetFps;
    final pixelRatio = _pixelRatio(
      width: sender.width,
      height: sender.height,
      targetWidth: profile.mainLayer.width,
      targetHeight: profile.mainLayer.height,
    );
    final penalty = _downgradePenalty(
      sender: sender,
      fpsRatio: fpsRatio,
      pixelRatio: pixelRatio,
    );

    return StreamLiveTuningScore(
      stableFps: _fpsScore(fpsRatio),
      targetResolution: _resolutionScore(pixelRatio),
      lowLoss: _lossScore(sender),
      lowRtt: _rttScore(sender),
      downgradePenalty: penalty,
    );
  }

  final int stableFps;
  final int targetResolution;
  final int lowLoss;
  final int lowRtt;
  final int downgradePenalty;

  int get total =>
      stableFps + targetResolution + lowLoss + lowRtt - downgradePenalty;

  Map<String, Object?> toJson() {
    return {
      'formula':
          'stable_fps + target_resolution + low_loss + low_rtt - downgrade_penalty',
      'stable_fps': stableFps,
      'target_resolution': targetResolution,
      'low_loss': lowLoss,
      'low_rtt': lowRtt,
      'downgrade_penalty': downgradePenalty,
      'total': total,
    };
  }

  static int _fpsScore(double ratio) {
    if (ratio >= 0.9) return 25;
    if (ratio >= 0.75) return 18;
    if (ratio >= 0.5) return 10;
    if (ratio > 0) return 4;
    return 0;
  }

  static int _resolutionScore(double? pixelRatio) {
    if (pixelRatio == null) return 0;
    if (pixelRatio >= 0.9) return 25;
    if (pixelRatio >= 0.75) return 18;
    if (pixelRatio >= 0.5) return 10;
    return 4;
  }

  static int _lossScore(VoipTrackDiagnostics sender) {
    final loss = sender.packetLossPercent;
    if (loss == null) return 0;
    final nack = sender.nackCount ?? 0;
    if (loss <= 0.5 && nack <= 2) return 25;
    if (loss <= 1.0 && nack <= 8) return 20;
    if (loss <= 3.0) return 12;
    return 0;
  }

  static int _rttScore(VoipTrackDiagnostics sender) {
    final rtt = sender.roundTripTimeMs;
    if (rtt == null) return 0;
    if (rtt <= 60) return 15;
    if (rtt <= 120) return 10;
    if (rtt <= 250) return 5;
    return 0;
  }

  static int _downgradePenalty({
    required VoipTrackDiagnostics sender,
    required double fpsRatio,
    required double? pixelRatio,
  }) {
    var penalty = 0;
    final limitation = sender.qualityLimitationReason?.trim().toLowerCase();
    if (limitation != null && limitation.isNotEmpty && limitation != 'none') {
      penalty += 10;
    }
    if (_isDowngradedLayer(sender.activeLayer ?? sender.rid)) {
      penalty += 10;
    }
    if (fpsRatio > 0 && fpsRatio < 0.5) {
      penalty += 10;
    }
    if (pixelRatio != null && pixelRatio < 0.5) {
      penalty += 10;
    }
    return penalty.clamp(0, 30).toInt();
  }

  static double? _pixelRatio({
    required int? width,
    required int? height,
    required int targetWidth,
    required int targetHeight,
  }) {
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      return null;
    }
    return (width * height) / (targetWidth * targetHeight);
  }

  static bool _isDowngradedLayer(String? layer) {
    final normalized = layer?.trim().toLowerCase();
    return normalized == 'q' ||
        normalized == 'l' ||
        normalized == 'low' ||
        normalized?.contains('low-layer') == true ||
        normalized?.contains('rescue') == true;
  }
}

VoipTrackDiagnostics? bestSenderTrack(VoipCallDiagnosticsSnapshot snapshot) {
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

Map<String, Object?> streamLiveTuningSnapshotToJson({
  required StreamLiveTuningConfig config,
  required VoipCallDiagnosticsSnapshot snapshot,
  required ScreenShareProfileConfig activeProfile,
  required bool activeScreenShare,
  required String windowsCaptureBackendLabel,
  required List<String> applicationNotes,
  Map<String, Object?>? nativeDiagnostics,
}) {
  final score = StreamLiveTuningScore.fromSnapshot(
    snapshot: snapshot,
    profile: activeProfile,
  );
  final bestSender = bestSenderTrack(snapshot);
  return {
    'schema': 'intergalactic.streamLiveStats.v1',
    'collectedAt': snapshot.collectedAt.toUtc().toIso8601String(),
    'activeScreenShare': activeScreenShare,
    'experimentName': config.experimentName,
    'windowsCaptureBackend': windowsCaptureBackendLabel,
    'applicationNotes': applicationNotes,
    'config': config.toJson(),
    'activeProfile': screenShareProfileToJson(activeProfile),
    'score': score.toJson(),
    'summary': {
      'bestSender':
          bestSender == null ? null : voipTrackDiagnosticsToJson(bestSender),
      'screenShareProfileLabel': snapshot.screenShareProfileLabel,
      'screenShareProfileDetails': snapshot.screenShareProfileDetails,
      'adaptiveFallbackReason': snapshot.adaptiveFallbackReason,
      'iceTransportSummary': snapshot.iceTransportSummary,
      'adaptiveStreamEnabled': snapshot.adaptiveStreamEnabled,
      'dynacastEnabled': snapshot.dynacastEnabled,
      'screenShareSimulcastEnabled': snapshot.screenShareSimulcastEnabled,
      'adaptiveFallbackEnabled': snapshot.adaptiveFallbackEnabled,
    },
    'shareSessionDiagnostics': _shareSessionDiagnosticsToJson(
      snapshot.shareSessionDiagnostics,
    ),
    'nativeDiagnostics': nativeDiagnostics,
    'tracks':
        snapshot.tracks.map(voipTrackDiagnosticsToJson).toList(growable: false),
  };
}

Map<String, Object?> screenShareProfileToJson(
  ScreenShareProfileConfig profile,
) {
  return {
    'storageKey': profile.storageKey,
    'label': profile.label,
    'description': profile.description,
    'profile': profile.profile?.name,
    'codec': profile.codec,
    'useSimulcast': profile.useSimulcast,
    'hardwareEncodeFirst': profile.hardwareEncodeFirst,
    'advancedOverride': profile.advancedOverride,
    'cpuRescueMode': profile.cpuRescueMode,
    'mainLayer': screenShareLayerToJson(profile.mainLayer),
    'lowLayer': profile.lowLayer == null
        ? null
        : screenShareLayerToJson(profile.lowLayer!),
  };
}

Map<String, Object?> screenShareLayerToJson(ScreenShareVideoLayer layer) {
  return {
    'width': layer.width,
    'height': layer.height,
    'maxFramerate': layer.maxFramerate,
    'targetFramerate': layer.targetFramerateForScoring,
    'maxBitrateBps': layer.maxBitrateBps,
    'minBitrateBps': layer.minBitrateBps,
  };
}

Map<String, Object?> voipTrackDiagnosticsToJson(VoipTrackDiagnostics track) {
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
    'retransmittedPacketsSent': track.retransmittedPacketsSent,
    'retransmittedBytesSent': track.retransmittedBytesSent,
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
    'totalFreezesDurationMs': track.totalFreezesDurationMs,
    'totalPausesDurationMs': track.totalPausesDurationMs,
  };
}

Map<String, Object?>? _shareSessionDiagnosticsToJson(
  ShareSessionDiagnosticSummary? summary,
) {
  if (summary == null) {
    return null;
  }
  return {
    'sourceType': summary.sourceType.name,
    'sourceIdHash': summary.sourceIdHash,
    'processId': summary.processId,
    'audioRequested': summary.audioRequested,
    'audioMode': summary.audioMode.name,
    'audioState': summary.audioState.name,
    'audioReason': summary.audioReason,
    'lifecycle': summary.lifecycle?.name,
    'sourceTitle': summary.sourceTitle,
  };
}
