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

/// Degrades the screen-share profile under sustained sender trouble and steps
/// it back up once the link has been quiet for a while.
///
/// BUG-324. The step UP used to jump straight back to the requested profile
/// after `upgradeAfter` of quiet, with no memory of the last attempt and no
/// look at the uplink estimate. On a persistently poor uplink that is a loop:
/// Smooth is quiet for 45 s, the share jumps to High Quality, fails in 8 s,
/// drops to Balanced, fails again, lands on Smooth, and repeats - and on
/// Windows every one of those profile changes recreates the capture and
/// republishes the share under a new track sid, which is what left observers
/// with stale duplicate tiles of one sharer (BUG-321's trigger). Three things
/// stop the loop: the step up climbs ONE preset at a time, a step up that
/// fails inside [upgradeFailureWindow] doubles the quiet time required before
/// the next one (up to [maxUpgradeHold]), and a step up is held while the
/// sender's own available-outgoing-bitrate estimate cannot carry the next
/// profile's minimum.
class ScreenShareAdaptiveFallbackController {
  ScreenShareAdaptiveFallbackController({
    this.degradeAfter = const Duration(seconds: 8),
    this.upgradeAfter = const Duration(seconds: 45),
    this.upgradeFailureWindow = const Duration(seconds: 60),
    this.maxUpgradeHold = const Duration(minutes: 10),
  }) : _upgradeHold = upgradeAfter;

  final Duration degradeAfter;
  final Duration upgradeAfter;

  /// A degrade this soon after a step up means the step up FAILED.
  final Duration upgradeFailureWindow;

  /// Ceiling for the doubled quiet time after repeated failed step ups.
  final Duration maxUpgradeHold;

  DateTime? _badSince;
  DateTime? _stableSince;
  ScreenShareProfileConfig? _effectiveProfile;
  String? _reason;
  Duration _upgradeHold;
  DateTime? _lastUpgradeAt;

  ScreenShareProfileConfig? get effectiveProfile => _effectiveProfile;
  String? get reason => _reason;

  /// Quiet time currently required before the next step up.
  Duration get upgradeHold => _upgradeHold;

  ScreenShareAdaptiveFallbackDecision evaluate({
    required ScreenShareProfileConfig requestedProfile,
    required VoipCallDiagnosticsSnapshot snapshot,
    required DateTime now,
  }) {
    _effectiveProfile ??= requestedProfile;

    final screenSender = snapshot.tracks
        .where((track) {
          return track.type == VoipStreamType.screenshare &&
              track.direction == VoipDiagnosticsTrackDirection.sender;
        })
        .fold<VoipTrackDiagnostics?>(null, (best, track) {
          if (best == null) return track;
          return (track.bitrateBps ?? 0) > (best.bitrateBps ?? 0)
              ? track
              : best;
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
          _badSince = now;
          final reason = _noteUpgradeFailedIfRecent(now)
              ? '$problem; upgrade held ${_upgradeHold.inSeconds}s after a '
                    'failed step up'
              : problem;
          _reason = reason;
          return ScreenShareAdaptiveFallbackDecision(
            profile: degraded,
            reason: reason,
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
    final lastUpgradeAt = _lastUpgradeAt;
    if (lastUpgradeAt != null &&
        now.difference(lastUpgradeAt) > upgradeFailureWindow) {
      // The last step up survived its window: back to the base quiet time.
      _upgradeHold = upgradeAfter;
      _lastUpgradeAt = null;
    }
    if (!_profileEncodingMatches(_effectiveProfile!, requestedProfile) &&
        now.difference(_stableSince!) >= _upgradeHold) {
      final candidate = _nextUpgradeProfile(
        _effectiveProfile!,
        requestedProfile,
      );
      final holdReason = _uplinkHoldReason(screenSender, candidate);
      if (holdReason != null) {
        // Not a reset of the quiet clock: the moment the estimate can carry
        // the next profile, the step up goes.
        _reason = holdReason;
        return ScreenShareAdaptiveFallbackDecision(
          profile: _effectiveProfile!,
          reason: holdReason,
        );
      }
      _effectiveProfile = candidate;
      _reason = null;
      _stableSince = now;
      _lastUpgradeAt = now;
      return ScreenShareAdaptiveFallbackDecision(
        profile: candidate,
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
    _upgradeHold = upgradeAfter;
    _lastUpgradeAt = null;
  }

  /// Doubles the quiet time when a degrade lands inside the failure window of
  /// the last step up. Returns whether it did.
  bool _noteUpgradeFailedIfRecent(DateTime now) {
    final lastUpgradeAt = _lastUpgradeAt;
    _lastUpgradeAt = null;
    if (lastUpgradeAt == null ||
        now.difference(lastUpgradeAt) > upgradeFailureWindow) {
      return false;
    }
    final doubled = _upgradeHold * 2;
    _upgradeHold = doubled > maxUpgradeHold ? maxUpgradeHold : doubled;
    return true;
  }

  /// The next profile ONE preset up the Smooth -> Balanced -> High Quality
  /// ladder, never above [requested]. A requested profile that is not a preset
  /// (advanced settings) has no ladder to climb and is returned directly, as
  /// is any current profile already at or above the requested rank.
  ScreenShareProfileConfig _nextUpgradeProfile(
    ScreenShareProfileConfig current,
    ScreenShareProfileConfig requested,
  ) {
    final requestedRank = _presetRank(requested);
    if (requestedRank == null) {
      return requested;
    }
    final currentRank = _presetRank(current);
    if (currentRank != null && currentRank >= requestedRank) {
      return requested;
    }
    final target = switch (currentRank) {
      null => ScreenShareProfileConfig.smooth,
      1 => ScreenShareProfileConfig.balanced,
      _ => ScreenShareProfileConfig.highQuality,
    };
    final step = _preserveEncodingPreference(target: target, current: current);
    if ((_presetRank(step) ?? 0) >= requestedRank) {
      return requested;
    }
    return step;
  }

  /// 1, 2 or 3 for the Smooth, Balanced and High Quality presets (in either
  /// encoding preference); null for a sub-preset fallback layer, CPU rescue,
  /// or advanced custom settings.
  int? _presetRank(ScreenShareProfileConfig profile) {
    final family = profile.profile;
    if (profile.cpuRescueMode || family == null) {
      return null;
    }
    final preset = switch (family) {
      ScreenShareQualityProfile.smooth => ScreenShareProfileConfig.smooth,
      ScreenShareQualityProfile.balanced => ScreenShareProfileConfig.balanced,
      ScreenShareQualityProfile.highQuality =>
        ScreenShareProfileConfig.highQuality,
    };
    final comparable = _preserveEncodingPreference(
      target: preset,
      current: profile,
    );
    if (!_profileEncodingMatches(profile, comparable)) {
      return null;
    }
    return switch (family) {
      ScreenShareQualityProfile.smooth => 1,
      ScreenShareQualityProfile.balanced => 2,
      ScreenShareQualityProfile.highQuality => 3,
    };
  }

  /// Why the step up to [candidate] must wait, or null when it may go. Uses
  /// the sender's own available-outgoing-bitrate estimate against the
  /// candidate's minimum (its `minBitrateBps`, else 60% of its maximum - the
  /// same fraction below which `_problemReason` calls the bitrate a problem).
  /// An unknown estimate never holds.
  String? _uplinkHoldReason(
    VoipTrackDiagnostics sender,
    ScreenShareProfileConfig candidate,
  ) {
    final availableOut = sender.availableOutgoingBitrateBps;
    if (availableOut == null || availableOut <= 0) {
      return null;
    }
    final layer = candidate.mainLayer;
    final needed = layer.minBitrateBps ?? (layer.maxBitrateBps * 0.6).round();
    if (availableOut >= needed) {
      return null;
    }
    return 'holding ${_effectiveProfile!.label}: uplink estimate '
        '${_mbps(availableOut)} below ${candidate.label} minimum '
        '${_mbps(needed)}';
  }

  String _mbps(int bps) => '${(bps / 1000000).toStringAsFixed(1)}Mbps';

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

    final widthTooLarge =
        encodedWidth > requestedWidth + 32 &&
        encodedWidth > requestedWidth * 1.1;
    final heightTooLarge =
        encodedHeight > requestedHeight + 18 &&
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
        ? [
            absoluteFloor,
            requestedFps * 0.25,
          ].reduce((left, right) => left > right ? left : right)
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
    final reducedResolution =
        nextResolution.width != currentLayer.width ||
        nextResolution.height != currentLayer.height;
    final bitrateCeiling = nextResolution.width >= 960 ? 1200000 : 700000;
    final nextBitrate = (currentLayer.maxBitrateBps * 0.7).round().clamp(
      350000,
      bitrateCeiling,
    );
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

  ScreenShareProfileConfig _cpuRescueProfile(ScreenShareProfileConfig current) {
    final lowLayer = current.lowLayer ?? current.mainLayer;
    final rescueLayer = lowLayer.copyWith(
      maxFramerate: lowLayer.maxFramerate > 20 ? 20 : lowLayer.maxFramerate,
      maxBitrateBps: lowLayer.maxBitrateBps > 300000
          ? 300000
          : lowLayer.maxBitrateBps,
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
    final base = label
        .replaceAll(RegExp(r' \((fallback|CPU rescue)\)'), '')
        .trim();
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

    return (width: (width * scale).round(), height: (height * scale).round());
  }
}
