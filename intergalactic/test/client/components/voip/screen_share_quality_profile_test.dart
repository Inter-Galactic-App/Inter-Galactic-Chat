import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';

void main() {
  group('ScreenShareProfileConfig', () {
    test('maps smooth profile to stable gameplay defaults', () {
      final config = ScreenShareProfileConfig.forPreferenceKey('smooth');

      expect(config.profile, ScreenShareQualityProfile.smooth);
      expect(config.mainLayer.width, 1280);
      expect(config.mainLayer.height, 720);
      expect(config.mainLayer.maxFramerate, 36);
      expect(config.mainLayer.targetFramerateForScoring, 30);
      expect(config.mainLayer.maxBitrateBps, 1800000);
      expect(config.codec, 'vp8');
      expect(config.useSimulcast, isTrue);
      expect(config.lowLayer?.width, 426);
      expect(config.lowLayer?.height, 240);
      expect(config.lowLayer?.maxFramerate, 30);
      expect(config.lowLayer?.maxBitrateBps, 350000);
    });

    test('maps balanced and high quality profiles', () {
      final balanced = ScreenShareProfileConfig.forPreferenceKey('balanced');
      final highQuality =
          ScreenShareProfileConfig.forPreferenceKey('highQuality');

      expect(balanced.mainLayer.width, 1920);
      expect(balanced.mainLayer.maxFramerate, 36);
      expect(balanced.mainLayer.targetFramerateForScoring, 30);
      expect(balanced.mainLayer.maxBitrateBps, 4000000);
      expect(highQuality.mainLayer.width, 1920);
      expect(highQuality.mainLayer.maxFramerate, 60);
      expect(highQuality.mainLayer.targetFramerateForScoring, 60);
      expect(highQuality.mainLayer.maxBitrateBps, 6000000);
      expect(highQuality.experimental, isTrue);
    });

    test('legacy advanced values do not override smooth unless enabled', () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: false,
        allowSimulcast: true,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
      );

      expect(config.profile, ScreenShareQualityProfile.smooth);
      expect(config.mainLayer.width, 1280);
      expect(config.mainLayer.maxBitrateBps, 1800000);
      expect(config.codec, 'vp8');
    });

    test('hardware preference switches presets to H264 gameplay bitrates', () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: false,
        allowSimulcast: true,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
        preferHardwareEncoding: true,
      );

      expect(config.profile, ScreenShareQualityProfile.smooth);
      expect(config.mainLayer.width, 1280);
      expect(config.mainLayer.height, 720);
      expect(config.mainLayer.maxFramerate, 36);
      expect(config.mainLayer.targetFramerateForScoring, 30);
      expect(config.mainLayer.maxBitrateBps, 3000000);
      expect(config.mainLayer.minBitrateBps, 2500000);
      expect(config.codec, 'h264');
      expect(config.hardwareEncodeFirst, isTrue);
      expect(config.useSimulcast, isFalse);
      expect(config.description, contains('single-layer'));
      expect(config.description, contains('hardware-encode first'));
      expect(config.description, contains('30 FPS target'));
      expect(config.description, contains('36 FPS sender cap'));
      expect(config.description, contains('3.0 Mbps'));
      expect(config.description, contains('2.5 Mbps floor'));
    });

    test('hardware preference raises opt-in preset bitrate ceilings', () {
      final balanced = ScreenShareProfileConfig.forPreferenceKey(
        'balanced',
        preferHardwareEncoding: true,
      );
      final highQuality = ScreenShareProfileConfig.forPreferenceKey(
        'highQuality',
        preferHardwareEncoding: true,
      );

      expect(balanced.mainLayer.width, 1920);
      expect(balanced.mainLayer.maxFramerate, 36);
      expect(balanced.mainLayer.targetFramerateForScoring, 30);
      expect(balanced.mainLayer.maxBitrateBps, 8000000);
      expect(balanced.mainLayer.minBitrateBps, 4000000);
      expect(highQuality.mainLayer.width, 1920);
      expect(highQuality.mainLayer.maxFramerate, 60);
      expect(highQuality.mainLayer.maxBitrateBps, 18000000);
      expect(highQuality.mainLayer.minBitrateBps, 6000000);
    });

    test('hardware preference preserves explicit higher live-test bitrate', () {
      final cappedSmooth = ScreenShareProfileConfig.smooth.copyWith(
        mainLayer: ScreenShareProfileConfig.smooth.mainLayer.copyWith(
          maxBitrateBps: 12000000,
          minBitrateBps: 8000000,
        ),
        useSimulcast: false,
      );

      final hardware = cappedSmooth.withHardwareEncodingPreference();

      expect(hardware.profile, ScreenShareQualityProfile.smooth);
      expect(hardware.codec, 'h264');
      expect(hardware.hardwareEncodeFirst, isTrue);
      expect(hardware.useSimulcast, isFalse);
      expect(hardware.mainLayer.maxBitrateBps, 12000000);
      expect(hardware.mainLayer.minBitrateBps, 8000000);
    });

    test('advanced override can keep hardware H264 live-test controls', () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: true,
        allowSimulcast: true,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
        preferHardwareEncoding: true,
      );

      expect(config.advancedOverride, isTrue);
      expect(config.mainLayer.width, 1920);
      expect(config.mainLayer.height, 1080);
      expect(config.mainLayer.maxFramerate, 60);
      expect(config.mainLayer.maxBitrateBps, 8000000);
      expect(config.codec, 'h264');
      expect(config.hardwareEncodeFirst, isTrue);
      expect(config.useSimulcast, isFalse);
      expect(config.description, contains('single-layer'));
      expect(config.description, contains('hardware-encode first'));
      expect(config.description, contains('8.0 Mbps'));
    });

    test('advanced override keeps explicit codec when hardware is disabled',
        () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: true,
        allowSimulcast: true,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
        preferHardwareEncoding: false,
      );

      expect(config.advancedOverride, isTrue);
      expect(config.codec, 'vp9');
      expect(config.hardwareEncodeFirst, isFalse);
      expect(config.useSimulcast, isFalse);
    });

    test('presets keep simulcast even when old hidden preference is disabled',
        () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: false,
        allowSimulcast: false,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
      );

      expect(config.profile, ScreenShareQualityProfile.smooth);
      expect(config.codec, 'vp8');
      expect(config.useSimulcast, isTrue);
      expect(config.lowLayer, isNotNull);
    });

    test('Windows window capture compatibility disables simulcast only there',
        () {
      final balanced = ScreenShareProfileConfig.forPreferenceKey('balanced');
      final windowProfile = balanced.withWindowsWindowCaptureCompatibility(
        isWindowsWindowSource: true,
      );
      final displayProfile = balanced.withWindowsWindowCaptureCompatibility(
        isWindowsWindowSource: false,
      );
      final hardwareProfile = balanced
          .withHardwareEncodingPreference()
          .withWindowsWindowCaptureCompatibility(
            isWindowsWindowSource: true,
          );

      expect(windowProfile.codec, 'vp8');
      expect(windowProfile.useSimulcast, isFalse);
      expect(windowProfile.lowLayer, isNotNull);
      expect(windowProfile.mainLayer.width, balanced.mainLayer.width);
      expect(windowProfile.description, contains('single-layer'));

      expect(displayProfile.useSimulcast, isTrue);
      expect(hardwareProfile.codec, 'h264');
      expect(hardwareProfile.useSimulcast, isFalse);
      expect(hardwareProfile.description, contains('hardware-encode first'));
    });

    test('Windows display capture uses target FPS instead of headroom cap', () {
      final balanced = ScreenShareProfileConfig.forPreferenceKey(
        'balanced',
        preferHardwareEncoding: true,
      );
      final displayProfile =
          balanced.withWindowsDisplayCaptureCadenceCompatibility(
        isWindowsDisplaySource: true,
      );
      final windowProfile =
          balanced.withWindowsDisplayCaptureCadenceCompatibility(
        isWindowsDisplaySource: false,
      );

      expect(balanced.mainLayer.maxFramerate, 36);
      expect(displayProfile.mainLayer.maxFramerate, 30);
      expect(displayProfile.mainLayer.targetFramerateForScoring, 30);
      expect(displayProfile.mainLayer.maxBitrateBps, 8000000);
      expect(displayProfile.mainLayer.minBitrateBps, 4000000);
      expect(displayProfile.codec, 'h264');
      expect(displayProfile.useSimulcast, isFalse);
      expect(displayProfile.description, contains('Windows display sources'));

      expect(windowProfile.mainLayer.maxFramerate, 36);
      expect(windowProfile.mainLayer.targetFramerateForScoring, 30);
    });

    test('D3D11 game capture uses the measured 720p30 envelope', () {
      final balanced = ScreenShareProfileConfig.forPreferenceKey(
        'balanced',
        preferHardwareEncoding: true,
      );
      final highQuality = ScreenShareProfileConfig.forPreferenceKey(
        'highQuality',
        preferHardwareEncoding: true,
      );
      final gameProfile = balanced.withWindowsGameCaptureCadenceCompatibility(
        isExperimentalGameCaptureSource: true,
      );
      final highQualityGameProfile =
          highQuality.withWindowsGameCaptureCadenceCompatibility(
        isExperimentalGameCaptureSource: true,
      );
      final windowProfile = balanced.withWindowsGameCaptureCadenceCompatibility(
        isExperimentalGameCaptureSource: false,
      );

      expect(balanced.mainLayer.maxFramerate, 36);
      expect(gameProfile.mainLayer.width, 1280);
      expect(gameProfile.mainLayer.height, 720);
      expect(gameProfile.mainLayer.maxFramerate, 30);
      expect(gameProfile.mainLayer.targetFramerateForScoring, 30);
      expect(gameProfile.mainLayer.maxBitrateBps, 8000000);
      expect(gameProfile.mainLayer.minBitrateBps, 4000000);
      expect(gameProfile.codec, 'h264');
      expect(gameProfile.useSimulcast, isFalse);
      expect(gameProfile.description, contains('D3D11 game-hook'));
      expect(gameProfile.description, contains('1280x720@30'));
      expect(gameProfile.description, contains('async readback cadence'));
      expect(highQualityGameProfile.mainLayer.width, 1280);
      expect(highQualityGameProfile.mainLayer.height, 720);
      expect(highQualityGameProfile.mainLayer.maxFramerate, 30);
      expect(highQualityGameProfile.mainLayer.targetFramerateForScoring, 30);

      expect(windowProfile.mainLayer.maxFramerate, 36);
      expect(windowProfile.mainLayer.targetFramerateForScoring, 30);
    });

    test('advanced VP9 stays single layer', () {
      final config = ScreenShareProfileConfig.resolve(
        profileKey: 'smooth',
        advancedOverrideEnabled: true,
        allowSimulcast: true,
        advancedBitrateMbps: 8,
        advancedFramerate: 60,
        advancedCodec: 'vp9',
        advancedResolution: '1920x1080',
      );

      expect(config.advancedOverride, isTrue);
      expect(config.mainLayer.width, 1920);
      expect(config.mainLayer.maxFramerate, 60);
      expect(config.mainLayer.maxBitrateBps, 8000000);
      expect(config.codec, 'vp9');
      expect(config.useSimulcast, isFalse);
    });

    test('sender scale clamps ignored desktop capture resolution to smooth',
        () {
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 1920,
          observedHeight: 1080,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        1.5,
      );
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 2560,
          observedHeight: 1440,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        2,
      );
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 1280,
          observedHeight: 720,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        1,
      );
    });

    test('sender scale ignores null or invalid dimensions', () {
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: null,
          observedHeight: 1080,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        1,
      );
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 0,
          observedHeight: 720,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        1,
      );
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 1920,
          observedHeight: -1080,
          targetLayer: ScreenShareProfileConfig.smooth.mainLayer,
        ),
        1,
      );
      expect(
        ScreenShareSenderEncodingLimits.scaleResolutionDownBy(
          observedWidth: 1920,
          observedHeight: 1080,
          targetLayer: const ScreenShareVideoLayer(
            width: 0,
            height: 720,
            maxFramerate: 30,
            maxBitrateBps: 1000,
          ),
        ),
        1,
      );
    });

    test('contain fit always returns even encoder dimensions', () {
      final sourceWithinBounds = ScreenShareContainFit.fitWithin(
        sourceWidth: 1279,
        sourceHeight: 719,
        maxWidth: 1280,
        maxHeight: 720,
      );
      final tinyBounds = ScreenShareContainFit.fitWithin(
        sourceWidth: 5,
        sourceHeight: 5,
        maxWidth: 1,
        maxHeight: 1,
      );
      final downscaled = ScreenShareContainFit.fitWithin(
        sourceWidth: 1921,
        sourceHeight: 1081,
        maxWidth: 1280,
        maxHeight: 720,
      );
      final nonPositive = ScreenShareContainFit.fitWithin(
        sourceWidth: 0,
        sourceHeight: -10,
        maxWidth: 0,
        maxHeight: -1,
      );

      expect(sourceWithinBounds, (width: 1278, height: 718));
      expect(tinyBounds, (width: 2, height: 2));
      expect(nonPositive, (width: 2, height: 2));
      expect(downscaled.width.isEven, isTrue);
      expect(downscaled.height.isEven, isTrue);
      expect(downscaled.width, lessThanOrEqualTo(1280));
      expect(downscaled.height, lessThanOrEqualTo(720));
    });

    test('contain fit preserves ultrawide and tall aspect ratios within bounds',
        () {
      final ultrawide = ScreenShareContainFit.fitWithin(
        sourceWidth: 3440,
        sourceHeight: 1440,
        maxWidth: 1280,
        maxHeight: 720,
      );
      final tall = ScreenShareContainFit.fitWithin(
        sourceWidth: 1080,
        sourceHeight: 2400,
        maxWidth: 1280,
        maxHeight: 720,
      );

      expect(ultrawide, (width: 1280, height: 536));
      expect(tall, (width: 324, height: 720));
      expect(ultrawide.width.isEven, isTrue);
      expect(ultrawide.height.isEven, isTrue);
      expect(tall.width.isEven, isTrue);
      expect(tall.height.isEven, isTrue);
      expect(ultrawide.width, lessThanOrEqualTo(1280));
      expect(ultrawide.height, lessThanOrEqualTo(720));
      expect(tall.width, lessThanOrEqualTo(1280));
      expect(tall.height, lessThanOrEqualTo(720));
    });

    test('collapsed fallback profile publishes only the low layer', () {
      final collapsed =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      final rescue = collapsed.copyWith(
        label: 'Smooth (fallback)',
        mainLayer: const ScreenShareVideoLayer(
          width: 426,
          height: 240,
          maxFramerate: 20,
          maxBitrateBps: 300000,
        ),
        cpuRescueMode: true,
      );

      expect(collapsed.shouldPublishLowLayerOnly, isFalse);
      expect(rescue.shouldPublishLowLayerOnly, isTrue);
    });
  });
}
