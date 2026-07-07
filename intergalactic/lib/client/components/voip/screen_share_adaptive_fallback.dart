import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

class ScreenShareAdaptiveFallbackDecision {
  const ScreenShareAdaptiveFallbackDecision({
    required this.profile,
    this.reason,
    this.changed = false,
  });

  final ScreenShareProfileConfig profile;
  final String? reason;
  final bool changed;
}

class ScreenShareAdaptiveFallbackController {
  ScreenShareAdaptiveFallbackController({
    this.degradeAfter = const Duration(seconds: 8),
    this.upgradeAfter = const Duration(seconds: 45),
  });

  final Duration degradeAfter;
  final Duration upgradeAfter;

  DateTime? _badSince;
  DateTime? _stableSince;
  ScreenShareProfileConfig? _effectiveProfile;
  String? _reason;

  ScreenShareProfileConfig? get effectiveProfile => _effectiveProfile;
  String? get reason => _reason;

  ScreenShareAdaptiveFallbackDecision evaluate({
    required ScreenShareProfileConfig requestedProfile,
    required VoipCallDiagnosticsSnapshot snapshot,
    required DateTime now,
  }) {
    _effectiveProfile ??= requestedProfile;

    final screenSender = snapshot.tracks.where((track) {
      return track.type == VoipStreamType.screenshare &&
          track.direction == VoipDiagnosticsTrackDirection.sender;
    }).fold<VoipTrackDiagnostics?>(null, (best, track) {
      if (best == null) return track;
      return (track.bitrateBps ?? 0) > (best.bitrateBps ?? 0) ? track : best;
    });

    if (screenSender == null) {
      _badSince = null;
      _stableSince = null;
      return ScreenShareAdaptiveFallbackDecision(
        profile: _effectiveProfile!,
        reason: _reason,
      );
    }

    final problem = _problemReason(screenSender);
    if (problem != null) {
      _stableSince = null;
      if (!_profileEncodingMatches(_effectiveProfile!, requestedProfile) &&
          _requestedResolutionNotApplied(screenSender)) {
        final reason = '$problem (${_resolutionNotAppliedLabel(screenSender)})';
        _reason = reason;
        _badSince = now;
        return ScreenShareAdaptiveFallbackDecision(
          profile: _effectiveProfile!,
          reason: reason,
        );
      }
      _badSince ??= now;
      if (now.difference(_badSince!) >= degradeAfter) {
        final degraded = _degrade(_effectiveProfile!, reason: problem);
        if (!_profileEncodingMatches(degraded, _effectiveProfile!)) {
          _effectiveProfile = degraded;
          _reason = problem;
          _badSince = now;
          return ScreenShareAdaptiveFallbackDecision(
            profile: degraded,
            reason: problem,
            changed: true,
          );
        }
      }
      _reason = problem;
      return ScreenShareAdaptiveFallbackDecision(
        profile: _effectiveProfile!,
        reason: problem,
      );
    }

    _badSince = null;
    _stableSince ??= now;
    if (!_profileEncodingMatches(_effectiveProfile!, requestedProfile) &&
        now.difference(_stableSince!) >= upgradeAfter) {
      _effectiveProfile = requestedProfile;
      _reason = null;
      _stableSince = now;
      return ScreenShareAdaptiveFallbackDecision(
        profile: requestedProfile,
        changed: true,
      );
    }

    _reason = null;
    return ScreenShareAdaptiveFallbackDecision(profile: _effectiveProfile!);
  }

  void reset() {
    _badSince = null;
    _stableSince = null;
    _effectiveProfile = null;
    _reason = null;
  }

  String? _problemReason(VoipTrackDiagnostics track) {
    final targetBitrate = track.targetBitrateBps ?? 0;
    final bitrate = track.bitrateBps ?? 0;
    final packetLoss = track.packetLossPercent ?? 0;
    final limitation = track.qualityLimitationReason?.toLowerCase();
    final captureCadenceLimited = _hasCorroboratedCaptureCadenceLimit(track);

    if (limitation == 'cpu') {
      if (captureCadenceLimited) {
        return 'capture FPS below target';
      }
      if (_hasCorroboratedEncodeOverload(track)) {
        return 'quality limited by cpu (encode overload)';
      }
      if (_hasSevereFpsCollapse(track)) {
        return 'quality limited by cpu (severe low FPS)';
      }
      if (!_hasEncodeOverloadCounters(track)) {
        return 'quality limited by cpu (sustained label)';
      }
    }
    if (captureCadenceLimited) {
      return 'capture FPS below target';
    }
    if (_hasCorroboratedEncodeOverload(track)) {
      return 'encoder overload';
    }
    if (limitation == 'bandwidth' && _hasCorroboratedBandwidthLimit(track)) {
      return 'quality limited by bandwidth';
    }
    if (targetBitrate > 0 &&
        bitrate > 0 &&
        bitrate < targetBitrate * 0.6 &&
        _hasCorroboratedBandwidthLimit(track)) {
      return 'bitrate below target';
    }
    if (packetLoss >= 4) {
      return 'packet loss ${packetLoss.toStringAsFixed(1)}%';
    }
    if (_hasSevereFpsCollapse(track)) {
      return 'low sender FPS';
    }

    return null;
  }

  bool _requestedResolutionNotApplied(VoipTrackDiagnostics track) {
    final requestedWidth = track.requestedWidth;
    final requestedHeight = track.requestedHeight;
    final encodedWidth = track.width;
    final encodedHeight = track.height;
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

    final widthTooLarge = encodedWidth > requestedWidth + 32 &&
        encodedWidth > requestedWidth * 1.1;
    final heightTooLarge = encodedHeight > requestedHeight + 18 &&
        encodedHeight > requestedHeight * 1.1;
    return widthTooLarge || heightTooLarge;
  }

  String _resolutionNotAppliedLabel(VoipTrackDiagnostics track) {
    return 'resolution limit not applied: '
        'req ${track.requestedWidth ?? '?'}x${track.requestedHeight ?? '?'} '
        'encoded ${track.width ?? '?'}x${track.height ?? '?'}';
  }

  bool _hasCorroboratedBandwidthLimit(VoipTrackDiagnostics track) {
    final packetLoss = track.packetLossPercent ?? 0;
    final roundTripTimeMs = track.roundTripTimeMs ?? 0;
    final nackCount = track.nackCount ?? 0;
    final packetsLost = track.packetsLost ?? 0;

    if (packetLoss >= 2 || packetsLost > 0) {
      return true;
    }
    if (roundTripTimeMs >= 250) {
      return true;
    }
    if (nackCount >= 8) {
      return true;
    }
    return false;
  }

  bool _hasEncodeOverloadCounters(VoipTrackDiagnostics track) {
    return track.averageEncodeTimeMs != null ||
        track.framesDroppedByEncoder != null ||
        track.framesDroppedBeforeEncode != null ||
        track.averagePacketSendDelayMs != null;
  }

  bool _hasCorroboratedEncodeOverload(VoipTrackDiagnostics track) {
    final encodeMs = track.averageEncodeTimeMs ?? 0;
    final requestedFps = track.requestedFps ?? 0;
    final observedFps = track.encodeFps ?? track.sendFps ?? track.fps ?? 0;
    final fpsForBudget = requestedFps > 0
        ? requestedFps
        : (observedFps > 0 ? observedFps : 30.0);
    final frameBudgetMs = 1000 / fpsForBudget.clamp(1.0, 60.0);
    final encodeOverBudget = encodeMs >= 80 || encodeMs >= frameBudgetMs * 1.5;
    final encoderDropped = (track.framesDroppedByEncoder ?? 0) > 0;
    final preEncodeDropped = (track.framesDroppedBeforeEncode ?? 0) > 0;
    final sendQueuePressure = (track.averagePacketSendDelayMs ?? 0) >= 200;

    return encodeOverBudget ||
        encoderDropped ||
        preEncodeDropped ||
        sendQueuePressure;
  }

  bool _hasCorroboratedCaptureCadenceLimit(VoipTrackDiagnostics track) {
    final requestedFps = track.requestedFps ?? 0;
    final captureFps = track.captureFps ?? 0;
    if (requestedFps <= 0 || captureFps <= 0) {
      return false;
    }
    if (captureFps >= requestedFps * 0.75) {
      return false;
    }
    if (!_hasCleanNetwork(track)) {
      return false;
    }

    final encodeFps = track.encodeFps;
    final sendFps = track.sendFps ?? track.fps;
    if (encodeFps != null && !_stageFpsTracks(encodeFps, captureFps)) {
      return false;
    }
    if (sendFps != null && !_stageFpsTracks(sendFps, encodeFps ?? captureFps)) {
      return false;
    }

    return encodeFps != null || sendFps != null;
  }

  bool _hasCleanNetwork(VoipTrackDiagnostics track) {
    final packetLoss = track.packetLossPercent ?? 0;
    final packetsLost = track.packetsLost ?? 0;
    final nackCount = track.nackCount ?? 0;
    final roundTripTimeMs = track.roundTripTimeMs ?? 0;

    return packetLoss <= 1 &&
        packetsLost == 0 &&
        nackCount <= 2 &&
        roundTripTimeMs < 150;
  }

  bool _stageFpsTracks(double value, double reference) {
    if (value <= 0 || reference <= 0) {
      return false;
    }
    return value >= reference * 0.8 && value <= reference * 1.25;
  }

  bool _hasSevereFpsCollapse(VoipTrackDiagnostics track) {
    final observedFps = track.encodeFps ?? track.sendFps ?? track.fps ?? 0;
    if (observedFps <= 0) {
      return false;
    }

    final requestedFps = track.requestedFps ?? 0;
    final absoluteFloor = track.hardwareEncodeActive == true ? 8.0 : 10.0;
    final threshold = requestedFps > 0
        ? [absoluteFloor, requestedFps * 0.25]
            .reduce((left, right) => left > right ? left : right)
        : absoluteFloor;

    return observedFps <= threshold;
  }

  bool _profileEncodingMatches(
    ScreenShareProfileConfig left,
    ScreenShareProfileConfig right,
  ) {
    return left.storageKey == right.storageKey &&
        left.codec == right.codec &&
        left.useSimulcast == right.useSimulcast &&
        left.hardwareEncodeFirst == right.hardwareEncodeFirst &&
        left.cpuRescueMode == right.cpuRescueMode &&
        _layerMatches(left.mainLayer, right.mainLayer) &&
        _optionalLayerMatches(left.lowLayer, right.lowLayer);
  }

  bool _optionalLayerMatches(
    ScreenShareVideoLayer? left,
    ScreenShareVideoLayer? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return _layerMatches(left, right);
  }

  bool _layerMatches(ScreenShareVideoLayer left, ScreenShareVideoLayer right) {
    return left.width == right.width &&
        left.height == right.height &&
        left.maxFramerate == right.maxFramerate &&
        left.targetFramerateForScoring == right.targetFramerateForScoring &&
        left.minBitrateBps == right.minBitrateBps &&
        left.maxBitrateBps == right.maxBitrateBps;
  }

  ScreenShareProfileConfig _degrade(
    ScreenShareProfileConfig current, {
    required String reason,
  }) {
    if (current.profile == ScreenShareQualityProfile.highQuality) {
      return _preserveEncodingPreference(
        target: ScreenShareProfileConfig.balanced,
        current: current,
      );
    }
    if (current.profile == ScreenShareQualityProfile.balanced) {
      return _preserveEncodingPreference(
        target: ScreenShareProfileConfig.smooth,
        current: current,
      );
    }
    if (reason == 'capture FPS below target' &&
        current.profile == ScreenShareQualityProfile.smooth) {
      return current;
    }
    if (current.profile == ScreenShareQualityProfile.smooth &&
        _isLowestSmoothFallback(current)) {
      return _cpuRescueProfile(current);
    }

    final currentLayer = current.mainLayer;
    final nextResolution = _nextFallbackResolution(currentLayer);
    final reducedResolution = nextResolution.width != currentLayer.width ||
        nextResolution.height != currentLayer.height;
    final bitrateCeiling = nextResolution.width >= 960 ? 1200000 : 700000;
    final nextBitrate = (currentLayer.maxBitrateBps * 0.7)
        .round()
        .clamp(350000, bitrateCeiling);
    final nextFramerate = reducedResolution
        ? currentLayer.maxFramerate.clamp(24, 30)
        : (currentLayer.maxFramerate <= 24 ? 20 : 24).clamp(15, 30);
    final nextLayer = ScreenShareVideoLayer(
      width: nextResolution.width,
      height: nextResolution.height,
      maxFramerate: nextFramerate.toInt(),
      targetFramerate: currentLayer.targetFramerateForScoring
          .clamp(1, nextFramerate.toInt())
          .toInt(),
      maxBitrateBps: nextBitrate.toInt(),
    );

    return current.copyWith(
      mainLayer: nextLayer,
      label: _labelWithMode(current.label, 'fallback'),
      description: '${current.description} Adaptive fallback is active.',
    );
  }

  bool _isLowestSmoothFallback(ScreenShareProfileConfig current) {
    return !current.cpuRescueMode &&
        current.mainLayer.width <= 640 &&
        current.mainLayer.height <= 360 &&
        current.mainLayer.maxFramerate <= 20 &&
        current.mainLayer.maxBitrateBps <= 350000;
  }

  ScreenShareProfileConfig _cpuRescueProfile(
    ScreenShareProfileConfig current,
  ) {
    final lowLayer = current.lowLayer ?? current.mainLayer;
    final rescueLayer = lowLayer.copyWith(
      maxFramerate: lowLayer.maxFramerate > 20 ? 20 : lowLayer.maxFramerate,
      maxBitrateBps:
          lowLayer.maxBitrateBps > 300000 ? 300000 : lowLayer.maxBitrateBps,
    );

    return current.copyWith(
      mainLayer: rescueLayer,
      label: _labelWithMode(current.label, 'CPU rescue'),
      description:
          '${current.description} CPU rescue is active: only the low sender layer is published.',
      cpuRescueMode: true,
    );
  }

  String _labelWithMode(String label, String mode) {
    final base =
        label.replaceAll(RegExp(r' \((fallback|CPU rescue)\)'), '').trim();
    return '$base ($mode)';
  }

  ScreenShareProfileConfig _preserveEncodingPreference({
    required ScreenShareProfileConfig target,
    required ScreenShareProfileConfig current,
  }) {
    return current.hardwareEncodeFirst
        ? target.withHardwareEncodingPreference()
        : target;
  }

  ({int width, int height}) _nextFallbackResolution(
    ScreenShareVideoLayer currentLayer,
  ) {
    final width = currentLayer.width.toDouble();
    final height = currentLayer.height.toDouble();
    ({double width, double height})? cap;

    if (currentLayer.width > 960 || currentLayer.height > 540) {
      cap = (width: 960, height: 540);
    } else if (currentLayer.width > 640 || currentLayer.height > 360) {
      cap = (width: 640, height: 360);
    } else {
      return (width: currentLayer.width, height: currentLayer.height);
    }

    final scale = [
      1.0,
      cap.width / width,
      cap.height / height,
    ].reduce((left, right) => left < right ? left : right);

    return (
      width: (width * scale).round(),
      height: (height * scale).round(),
    );
  }
}
