enum ScreenShareQualityProfile {
  smooth,
  balanced,
  highQuality,
}

extension ScreenShareQualityProfileDetails on ScreenShareQualityProfile {
  String get storageKey => switch (this) {
        ScreenShareQualityProfile.smooth => 'smooth',
        ScreenShareQualityProfile.balanced => 'balanced',
        ScreenShareQualityProfile.highQuality => 'highQuality',
      };

  String get label => switch (this) {
        ScreenShareQualityProfile.smooth => 'Smooth',
        ScreenShareQualityProfile.balanced => 'Balanced',
        ScreenShareQualityProfile.highQuality => 'High Quality',
      };

  String get description => switch (this) {
        ScreenShareQualityProfile.smooth =>
          '720p, 30 FPS target with sender headroom, 1.8 Mbps. Best default for multiple gameplay streams.',
        ScreenShareQualityProfile.balanced =>
          '1080p, 30 FPS target with sender headroom, 4 Mbps. Use when fewer streams are visible.',
        ScreenShareQualityProfile.highQuality =>
          '1080p, 60 FPS, 6 Mbps. Experimental and heavier on CPU/network.',
      };
}

ScreenShareQualityProfile screenShareQualityProfileFromStorageKey(
  String value,
) {
  return ScreenShareQualityProfile.values.firstWhere(
    (profile) => profile.storageKey == value,
    orElse: () => ScreenShareQualityProfile.smooth,
  );
}

class ScreenShareVideoLayer {
  const ScreenShareVideoLayer({
    required this.width,
    required this.height,
    required this.maxFramerate,
    required this.maxBitrateBps,
    this.minBitrateBps,
    this.targetFramerate,
  });

  final int width;
  final int height;
  final int maxFramerate;
  final int maxBitrateBps;
  final int? minBitrateBps;
  final int? targetFramerate;

  String get resolutionLabel => '${width}x$height';
  int get targetFramerateForScoring {
    final target = targetFramerate ?? maxFramerate;
    return target.clamp(1, maxFramerate).toInt();
  }

  bool get hasSenderFramerateHeadroom =>
      maxFramerate > targetFramerateForScoring;

  String get framerateDescription {
    if (!hasSenderFramerateHeadroom) {
      return '$maxFramerate FPS';
    }
    return '$targetFramerateForScoring FPS target / '
        '$maxFramerate FPS sender cap';
  }

  String get diagnosticFramerateLabel {
    if (!hasSenderFramerateHeadroom) {
      return '${maxFramerate}fps';
    }
    return '${targetFramerateForScoring}fps_target/'
        '${maxFramerate}fps_cap';
  }

  ScreenShareVideoLayer copyWith({
    int? width,
    int? height,
    int? maxFramerate,
    int? maxBitrateBps,
    int? minBitrateBps,
    int? targetFramerate,
  }) {
    return ScreenShareVideoLayer(
      width: width ?? this.width,
      height: height ?? this.height,
      maxFramerate: maxFramerate ?? this.maxFramerate,
      maxBitrateBps: maxBitrateBps ?? this.maxBitrateBps,
      minBitrateBps: minBitrateBps ?? this.minBitrateBps,
      targetFramerate: targetFramerate ?? this.targetFramerate,
    );
  }
}

class ScreenShareProfileConfig {
  const ScreenShareProfileConfig({
    required this.profile,
    required this.storageKey,
    required this.label,
    required this.description,
    required this.mainLayer,
    required this.codec,
    required this.useSimulcast,
    this.lowLayer,
    this.experimental = false,
    this.advancedOverride = false,
    this.hardwareEncodeFirst = false,
    this.cpuRescueMode = false,
  });

  final ScreenShareQualityProfile? profile;
  final String storageKey;
  final String label;
  final String description;
  final ScreenShareVideoLayer mainLayer;
  final ScreenShareVideoLayer? lowLayer;
  final String codec;
  final bool useSimulcast;
  final bool experimental;
  final bool advancedOverride;
  final bool hardwareEncodeFirst;
  final bool cpuRescueMode;

  bool get shouldPublishLowLayerOnly {
    if (cpuRescueMode) {
      return true;
    }

    final lowLayer = this.lowLayer;
    if (!useSimulcast || lowLayer == null) {
      return false;
    }

    return mainLayer.width <= lowLayer.width &&
        mainLayer.height <= lowLayer.height &&
        mainLayer.maxFramerate <= lowLayer.maxFramerate &&
        mainLayer.maxBitrateBps <= lowLayer.maxBitrateBps;
  }

  static const smooth = ScreenShareProfileConfig(
    profile: ScreenShareQualityProfile.smooth,
    storageKey: 'smooth',
    label: 'Smooth',
    description:
        '720p, 30 FPS target / 36 FPS sender cap, VP8, 1.8 Mbps. Best default for multiple gameplay streams.',
    mainLayer: ScreenShareVideoLayer(
      width: 1280,
      height: 720,
      maxFramerate: 36,
      targetFramerate: 30,
      maxBitrateBps: 1800000,
    ),
    lowLayer: ScreenShareVideoLayer(
      width: 426,
      height: 240,
      maxFramerate: 30,
      maxBitrateBps: 350000,
    ),
    codec: 'vp8',
    useSimulcast: true,
  );

  static const balanced = ScreenShareProfileConfig(
    profile: ScreenShareQualityProfile.balanced,
    storageKey: 'balanced',
    label: 'Balanced',
    description:
        '1080p, 30 FPS target / 36 FPS sender cap, VP8, 4 Mbps. Use when fewer streams are visible.',
    mainLayer: ScreenShareVideoLayer(
      width: 1920,
      height: 1080,
      maxFramerate: 36,
      targetFramerate: 30,
      maxBitrateBps: 4000000,
    ),
    lowLayer: ScreenShareVideoLayer(
      width: 640,
      height: 360,
      maxFramerate: 30,
      maxBitrateBps: 700000,
    ),
    codec: 'vp8',
    useSimulcast: true,
  );

  static const highQuality = ScreenShareProfileConfig(
    profile: ScreenShareQualityProfile.highQuality,
    storageKey: 'highQuality',
    label: 'High Quality',
    description:
        '1080p, 60 FPS, VP8, 6 Mbps. Experimental and heavier on CPU/network.',
    mainLayer: ScreenShareVideoLayer(
      width: 1920,
      height: 1080,
      maxFramerate: 60,
      maxBitrateBps: 6000000,
    ),
    lowLayer: ScreenShareVideoLayer(
      width: 640,
      height: 360,
      maxFramerate: 30,
      maxBitrateBps: 700000,
    ),
    codec: 'vp8',
    useSimulcast: true,
    experimental: true,
  );

  static ScreenShareProfileConfig forPreferenceKey(
    String value, {
    bool preferHardwareEncoding = false,
  }) {
    final preset = switch (screenShareQualityProfileFromStorageKey(value)) {
      ScreenShareQualityProfile.smooth => smooth,
      ScreenShareQualityProfile.balanced => balanced,
      ScreenShareQualityProfile.highQuality => highQuality,
    };
    return preferHardwareEncoding
        ? preset.withHardwareEncodingPreference()
        : preset;
  }

  static ScreenShareProfileConfig resolve({
    required String profileKey,
    required bool advancedOverrideEnabled,
    required bool allowSimulcast,
    required double advancedBitrateMbps,
    required double advancedFramerate,
    required String advancedCodec,
    required String advancedResolution,
    bool preferHardwareEncoding = false,
  }) {
    if (!advancedOverrideEnabled) {
      final preset = forPreferenceKey(
        profileKey,
        preferHardwareEncoding: preferHardwareEncoding,
      );
      return preset.copyWith(
        useSimulcast:
            preset.useSimulcast && codecSupportsSimulcast(preset.codec),
      );
    }

    return advanced(
      bitrateMbps: advancedBitrateMbps,
      framerate: advancedFramerate,
      codec: advancedCodec,
      resolution: advancedResolution,
      allowSimulcast: allowSimulcast,
    ).withOptionalHardwareEncodingPreference(preferHardwareEncoding);
  }

  static ScreenShareProfileConfig advanced({
    required double bitrateMbps,
    required double framerate,
    required String codec,
    required String resolution,
    required bool allowSimulcast,
  }) {
    final dimensions = _parseResolution(resolution);
    final normalizedCodec = codec.toLowerCase();
    final maxFramerate = framerate.clamp(1, 60).round();
    final clampedBitrateMbps = bitrateMbps.clamp(0.1, 64.0);
    final lowLayer = ScreenShareVideoLayer(
      width: dimensions.width >= 640 ? 640 : dimensions.width,
      height: dimensions.height >= 360 ? 360 : dimensions.height,
      maxFramerate: maxFramerate,
      maxBitrateBps: 700000,
    );

    return ScreenShareProfileConfig(
      profile: null,
      storageKey: 'advanced',
      label: 'Advanced Override',
      description:
          '${dimensions.width}x${dimensions.height}, $maxFramerate FPS, ${normalizedCodec.toUpperCase()}, ${clampedBitrateMbps.toStringAsFixed(1)} Mbps.',
      mainLayer: ScreenShareVideoLayer(
        width: dimensions.width,
        height: dimensions.height,
        maxFramerate: maxFramerate,
        maxBitrateBps: (clampedBitrateMbps * 1000000).round(),
      ),
      lowLayer: lowLayer,
      codec: normalizedCodec,
      useSimulcast: allowSimulcast && codecSupportsSimulcast(normalizedCodec),
      advancedOverride: true,
    );
  }

  ScreenShareProfileConfig copyWith({
    ScreenShareVideoLayer? mainLayer,
    ScreenShareVideoLayer? lowLayer,
    String? label,
    String? description,
    String? codec,
    bool? useSimulcast,
    bool? hardwareEncodeFirst,
    bool? cpuRescueMode,
  }) {
    return ScreenShareProfileConfig(
      profile: profile,
      storageKey: storageKey,
      label: label ?? this.label,
      description: description ?? this.description,
      mainLayer: mainLayer ?? this.mainLayer,
      lowLayer: lowLayer ?? this.lowLayer,
      codec: codec ?? this.codec,
      useSimulcast: useSimulcast ?? this.useSimulcast,
      experimental: experimental,
      advancedOverride: advancedOverride,
      hardwareEncodeFirst: hardwareEncodeFirst ?? this.hardwareEncodeFirst,
      cpuRescueMode: cpuRescueMode ?? this.cpuRescueMode,
    );
  }

  ScreenShareProfileConfig withHardwareEncodingPreference() {
    const hardwareFirstCodec = 'h264';
    final fittedLayer = ScreenShareContainFit.fitWithin(
      sourceWidth: mainLayer.width,
      sourceHeight: mainLayer.height,
      maxWidth: mainLayer.width,
      maxHeight: mainLayer.height,
    );
    final hardwareMaxBitrateBps = _hardwareFirstBitrateBps;
    final resolvedMaxBitrateBps =
        mainLayer.maxBitrateBps > hardwareMaxBitrateBps
            ? mainLayer.maxBitrateBps
            : hardwareMaxBitrateBps;
    final hardwareMinBitrateBps = _hardwareFirstMinBitrateBps;
    final requestedMinBitrateBps = mainLayer.minBitrateBps;
    final resolvedMinBitrateBps = requestedMinBitrateBps == null
        ? hardwareMinBitrateBps
        : requestedMinBitrateBps > resolvedMaxBitrateBps
            ? resolvedMaxBitrateBps
            : requestedMinBitrateBps;
    final hardwareLayer = mainLayer.copyWith(
      width: fittedLayer.width,
      height: fittedLayer.height,
      maxFramerate: _hardwareFirstFramerateCap,
      maxBitrateBps: resolvedMaxBitrateBps,
      minBitrateBps: resolvedMinBitrateBps,
    );
    return copyWith(
      mainLayer: hardwareLayer,
      codec: hardwareFirstCodec,
      useSimulcast: false,
      hardwareEncodeFirst: true,
      description: _hardwareEncodingPreferenceDescription(hardwareLayer),
    );
  }

  ScreenShareProfileConfig withOptionalHardwareEncodingPreference(
    bool enabled,
  ) {
    return enabled ? withHardwareEncodingPreference() : this;
  }

  ScreenShareProfileConfig withWindowsWindowCaptureCompatibility({
    required bool isWindowsWindowSource,
  }) {
    if (!isWindowsWindowSource || !useSimulcast) {
      return this;
    }

    return copyWith(
      useSimulcast: false,
      description: '$description Windows window sources publish single-layer '
          'to avoid fragile simulcast scaling for non-16:9 captured frames.',
    );
  }

  ScreenShareProfileConfig withWindowsDisplayCaptureCadenceCompatibility({
    required bool isWindowsDisplaySource,
  }) {
    final targetFramerate = mainLayer.targetFramerateForScoring;
    if (!isWindowsDisplaySource ||
        !mainLayer.hasSenderFramerateHeadroom ||
        targetFramerate >= mainLayer.maxFramerate) {
      return this;
    }

    final displayLayer = mainLayer.copyWith(
      maxFramerate: targetFramerate,
    );
    return copyWith(
      mainLayer: displayLayer,
      description: '$description Windows display sources use the target '
          'frame rate as the sender cap to avoid overdriving desktop '
          'capture cadence.',
    );
  }

  ScreenShareProfileConfig withWindowsGameCaptureCadenceCompatibility({
    required bool isExperimentalGameCaptureSource,
  }) {
    if (!isExperimentalGameCaptureSource) {
      return this;
    }

    const stableWidth = 1280;
    const stableHeight = 720;
    const stableFramerate = 30;
    final fittedLayer = ScreenShareContainFit.fitWithin(
      sourceWidth: mainLayer.width,
      sourceHeight: mainLayer.height,
      maxWidth: stableWidth,
      maxHeight: stableHeight,
    );
    final targetFramerate = mainLayer.targetFramerateForScoring;
    final effectiveFramerate =
        targetFramerate < stableFramerate ? targetFramerate : stableFramerate;
    final gameLayer = mainLayer.copyWith(
      width: fittedLayer.width,
      height: fittedLayer.height,
      maxFramerate: effectiveFramerate,
      targetFramerate: effectiveFramerate,
    );

    if (gameLayer.width == mainLayer.width &&
        gameLayer.height == mainLayer.height &&
        gameLayer.maxFramerate == mainLayer.maxFramerate &&
        gameLayer.targetFramerateForScoring ==
            mainLayer.targetFramerateForScoring &&
        !useSimulcast) {
      return this;
    }

    return copyWith(
      mainLayer: gameLayer,
      useSimulcast: false,
      description: '$description D3D11 game-hook sources use the target '
          '${gameLayer.resolutionLabel}@'
          '${gameLayer.targetFramerateForScoring} validation envelope to '
          'avoid overdriving async readback cadence while this debug backend '
          'is still CPU-readback based.',
    );
  }

  int get _hardwareFirstBitrateBps {
    return switch (profile) {
      ScreenShareQualityProfile.smooth => 3000000,
      ScreenShareQualityProfile.balanced => 8000000,
      ScreenShareQualityProfile.highQuality => 18000000,
      null => mainLayer.maxBitrateBps,
    };
  }

  int? get _hardwareFirstMinBitrateBps {
    return switch (profile) {
      ScreenShareQualityProfile.smooth => 2500000,
      ScreenShareQualityProfile.balanced => 4000000,
      ScreenShareQualityProfile.highQuality => 6000000,
      null => null,
    };
  }

  int get _hardwareFirstFramerateCap {
    return mainLayer.maxFramerate;
  }

  static bool codecSupportsSimulcast(String codec) {
    final normalized = codec.toLowerCase();
    return normalized == 'vp8' || normalized == 'h264';
  }

  static String _hardwareEncodingPreferenceDescription(
    ScreenShareVideoLayer layer,
  ) {
    final minBitrate = layer.minBitrateBps;
    final minBitrateLabel = minBitrate == null || minBitrate <= 0
        ? ''
        : ' with ${(minBitrate / 1000000).toStringAsFixed(1)} Mbps floor';
    return '${layer.resolutionLabel}, ${layer.framerateDescription}, '
        'single-layer H.264 hardware-encode first, '
        '${(layer.maxBitrateBps / 1000000).toStringAsFixed(1)} Mbps'
        '$minBitrateLabel. '
        'WebRTC may fall back to software if no Windows hardware encoder is available.';
  }

  static ({int width, int height}) _parseResolution(String value) {
    final parts = value.toLowerCase().split('x');
    if (parts.length != 2) {
      return (width: 1280, height: 720);
    }

    final width = int.tryParse(parts[0]) ?? 1280;
    final height = int.tryParse(parts[1]) ?? 720;
    return (
      width: width.clamp(320, 7680).toInt(),
      height: height.clamp(180, 4320).toInt(),
    );
  }
}

class ScreenShareSenderEncodingLimits {
  const ScreenShareSenderEncodingLimits._();

  static double scaleResolutionDownBy({
    required int? observedWidth,
    required int? observedHeight,
    required ScreenShareVideoLayer targetLayer,
  }) {
    if (observedWidth == null ||
        observedHeight == null ||
        observedWidth <= 0 ||
        observedHeight <= 0 ||
        targetLayer.width <= 0 ||
        targetLayer.height <= 0) {
      return 1.0;
    }

    final widthScale = observedWidth / targetLayer.width;
    final heightScale = observedHeight / targetLayer.height;
    final scale = widthScale > heightScale ? widthScale : heightScale;
    return scale > 1.0 ? scale : 1.0;
  }
}

class ScreenShareContainFit {
  const ScreenShareContainFit._();

  static ({int width, int height}) fitWithin({
    required int sourceWidth,
    required int sourceHeight,
    required int maxWidth,
    required int maxHeight,
  }) {
    final safeSourceWidth = sourceWidth < 2 ? 2 : sourceWidth;
    final safeSourceHeight = sourceHeight < 2 ? 2 : sourceHeight;
    final safeMaxWidth = maxWidth < 2 ? 2 : maxWidth;
    final safeMaxHeight = maxHeight < 2 ? 2 : maxHeight;
    final widthScale = safeMaxWidth / safeSourceWidth;
    final heightScale = safeMaxHeight / safeSourceHeight;
    final scale = [
      1.0,
      widthScale,
      heightScale,
    ].reduce((left, right) => left < right ? left : right);

    if (scale >= 1.0) {
      return (
        width: _evenDimension(safeSourceWidth.clamp(2, safeMaxWidth)),
        height: _evenDimension(safeSourceHeight.clamp(2, safeMaxHeight)),
      );
    }

    return (
      width: _evenDimension(
          (safeSourceWidth * scale).round().clamp(2, safeMaxWidth)),
      height: _evenDimension(
          (safeSourceHeight * scale).round().clamp(2, safeMaxHeight)),
    );
  }

  static int _evenDimension(num value) {
    final rounded = value.round();
    if (rounded <= 2) {
      return 2;
    }
    return rounded.isEven ? rounded : rounded - 1;
  }
}
