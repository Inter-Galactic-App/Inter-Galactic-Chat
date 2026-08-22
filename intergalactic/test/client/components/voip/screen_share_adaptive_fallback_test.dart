import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/screen_share_adaptive_fallback.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  group('ScreenShareAdaptiveFallbackController', () {
    test('degrades after sustained bad sender stats', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.highQuality,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.highQuality,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 18,
            bitrateBps: 2000000,
            targetBitrateBps: 6000000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 1200000,
            packetLossPercent: 3,
            packetsLost: 12,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.profile.profile, ScreenShareQualityProfile.balanced);
      expect(decision.reason, contains('bandwidth'));
    });

    test('waits for stable hysteresis before upgrading', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.balanced,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 12,
            bitrateBps: 1000000,
            targetBitrateBps: 4000000,
            limitation: 'cpu',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      final earlyStable = controller.evaluate(
        requestedProfile: ScreenShareProfileConfig.balanced,
        snapshot: _snapshot(
          now: start.add(const Duration(seconds: 40)),
          fps: 30,
          bitrateBps: 4000000,
          targetBitrateBps: 4000000,
        ),
        now: start.add(const Duration(seconds: 40)),
      );
      final lateStable = controller.evaluate(
        requestedProfile: ScreenShareProfileConfig.balanced,
        snapshot: _snapshot(
          now: start.add(const Duration(seconds: 86)),
          fps: 30,
          bitrateBps: 4000000,
          targetBitrateBps: 4000000,
        ),
        now: start.add(const Duration(seconds: 86)),
      );

      expect(earlyStable.changed, isFalse);
      expect(earlyStable.profile.profile, ScreenShareQualityProfile.smooth);
      expect(lateStable.changed, isTrue);
      expect(lateStable.profile.profile, ScreenShareQualityProfile.balanced);
    });

    test('smooth fallback reduces resolution before reducing framerate', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 18,
            bitrateBps: 800000,
            targetBitrateBps: 1800000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 900000,
            packetLossPercent: 3,
            packetsLost: 8,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.profile.mainLayer.width, 960);
      expect(decision.profile.mainLayer.height, 540);
      expect(decision.profile.mainLayer.maxFramerate, 30);
      expect(decision.profile.mainLayer.targetFramerateForScoring, 30);
      expect(decision.profile.mainLayer.maxBitrateBps, 1200000);
    });

    test('holds fallback when requested resolution is not encoded', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            requestedWidth: 1280,
            requestedHeight: 720,
            encodedWidth: 1280,
            encodedHeight: 720,
            fps: 12,
            requestedFps: 30,
            bitrateBps: 900000,
            targetBitrateBps: 3000000,
            averageEncodeTimeMs: 90,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );
      for (var seconds = 10; seconds <= 22; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            requestedWidth: 960,
            requestedHeight: 540,
            encodedWidth: 1280,
            encodedHeight: 720,
            fps: 12,
            requestedFps: 30,
            bitrateBps: 900000,
            targetBitrateBps: 1200000,
            averageEncodeTimeMs: 90,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.mainLayer.width, 960);
      expect(decision.profile.mainLayer.height, 540);
      expect(decision.profile.mainLayer.maxBitrateBps, 1200000);
      expect(decision.reason, contains('resolution limit not applied'));
      expect(controller.reason, contains('resolution limit not applied'));
    });

    test('clears resolution-not-applied reason after encoded size recovers',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            requestedWidth: 1280,
            requestedHeight: 720,
            encodedWidth: 1280,
            encodedHeight: 720,
            fps: 12,
            requestedFps: 30,
            bitrateBps: 900000,
            targetBitrateBps: 1800000,
            averageEncodeTimeMs: 90,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      final blocked = controller.evaluate(
        requestedProfile: ScreenShareProfileConfig.smooth,
        snapshot: _snapshot(
          now: start.add(const Duration(seconds: 10)),
          requestedWidth: 960,
          requestedHeight: 540,
          encodedWidth: 1280,
          encodedHeight: 720,
          fps: 12,
          requestedFps: 30,
          bitrateBps: 900000,
          targetBitrateBps: 1200000,
          averageEncodeTimeMs: 90,
        ),
        now: start.add(const Duration(seconds: 10)),
      );
      final recovered = controller.evaluate(
        requestedProfile: ScreenShareProfileConfig.smooth,
        snapshot: _snapshot(
          now: start.add(const Duration(seconds: 12)),
          requestedWidth: 960,
          requestedHeight: 540,
          encodedWidth: 960,
          encodedHeight: 540,
          fps: 30,
          requestedFps: 30,
          bitrateBps: 1200000,
          targetBitrateBps: 1200000,
        ),
        now: start.add(const Duration(seconds: 12)),
      );

      expect(blocked.reason, contains('resolution limit not applied'));
      expect(blocked.profile.mainLayer.width, 960);
      expect(recovered.changed, isFalse);
      expect(recovered.profile.mainLayer.width, 960);
      expect(recovered.reason, isNull);
      expect(controller.reason, isNull);
    });

    test('does not downshift hardware stream on clean bandwidth estimate only',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.highQuality.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 20; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 16,
            bitrateBps: 2400000,
            targetBitrateBps: 18000000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 7000000,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.highQuality);
      expect(decision.profile.mainLayer.maxBitrateBps, 18000000);
      expect(decision.reason, isNull);
    });

    test('preset fallback preserves hardware-first encoding preference', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.highQuality.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 18,
            bitrateBps: 2000000,
            targetBitrateBps: 6000000,
            limitation: 'cpu',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.profile.profile, ScreenShareQualityProfile.balanced);
      expect(decision.profile.codec, 'h264');
      expect(decision.profile.hardwareEncodeFirst, isTrue);
      expect(decision.profile.useSimulcast, isFalse);
    });

    test('degrades after sustained CPU limitation', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: null,
            targetBitrateBps: 1800000,
            limitation: 'cpu',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.reason, contains('cpu'));
      expect(decision.profile.mainLayer.width, 960);
      expect(decision.profile.mainLayer.height, 540);
    });

    test('ignores cpu limitation when healthy overload counters are present',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 12; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: 1800000,
            targetBitrateBps: 1800000,
            limitation: 'cpu',
            averageEncodeTimeMs: 12,
            framesDroppedBeforeEncode: 0,
            framesDroppedByEncoder: 0,
            averagePacketSendDelayMs: 20,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.smooth);
      expect(decision.reason, isNull);
    });

    test('degrades on cpu limitation with severe FPS collapse', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 6,
            requestedFps: 30,
            bitrateBps: 900000,
            targetBitrateBps: 3000000,
            limitation: 'cpu',
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
            averageEncodeTimeMs: 12,
            framesDroppedBeforeEncode: 0,
            framesDroppedByEncoder: 0,
            averagePacketSendDelayMs: 20,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.reason, contains('severe low FPS'));
      expect(decision.profile.mainLayer.width, 960);
      expect(decision.profile.mainLayer.height, 540);
    });

    test('does not degrade on healthy software encoder stats', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: 1600000,
            targetBitrateBps: 1800000,
            hardwareEncodeActive: false,
            encoderImplementation: 'SimulcastEncoderAdapter (OpenH264)',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.reason, isNull);
      expect(decision.profile.codec, 'h264');
      expect(decision.profile.hardwareEncodeFirst, isTrue);
      expect(decision.profile.mainLayer.width, 1280);
      expect(decision.profile.mainLayer.height, 720);
    });

    test('ignores uncorroborated bandwidth estimate on software encoder', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: 1600000,
            targetBitrateBps: 1800000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 4000000,
            hardwareEncodeActive: false,
            encoderImplementation: 'OpenH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.reason, isNull);
    });

    test('ignores uncorroborated bandwidth limitation without sender symptoms',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: 1800000,
            targetBitrateBps: 1800000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 4000000,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.reason, isNull);
    });

    test('enters CPU rescue after smooth reaches its lowest fallback', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 40; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 18,
            bitrateBps: 250000,
            targetBitrateBps: 1800000,
            limitation: 'cpu',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.reason, contains('cpu'));
      expect(decision.profile.cpuRescueMode, isTrue);
      expect(decision.profile.mainLayer.width, 426);
      expect(decision.profile.mainLayer.height, 240);
      expect(decision.profile.mainLayer.maxFramerate, 20);
      expect(decision.profile.mainLayer.maxBitrateBps, 300000);
      expect(decision.profile.label, 'Smooth (CPU rescue)');
    });

    test('does not treat missing bitrate alone as starvation', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: null,
            targetBitrateBps: 1800000,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.smooth);
      expect(decision.reason, isNull);
    });

    test('does not treat startup bandwidth estimate alone as network proof',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      ScreenShareAdaptiveFallbackDecision decision =
          const ScreenShareAdaptiveFallbackDecision(
        profile: ScreenShareProfileConfig.smooth,
      );

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: ScreenShareProfileConfig.smooth,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 30,
            bitrateBps: null,
            targetBitrateBps: 1800000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 300000,
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.smooth);
      expect(decision.reason, isNull);
    });

    test('keeps hardware preset on clean low-FPS sender stats', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 20; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 16,
            bitrateBps: 2400000,
            targetBitrateBps: 3000000,
            limitation: 'bandwidth',
            availableOutgoingBitrateBps: 8000000,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.mainLayer.width, 1280);
      expect(decision.profile.mainLayer.height, 720);
      expect(decision.profile.mainLayer.maxBitrateBps, 3000000);
      expect(decision.reason, isNull);
    });

    test('keeps hardware preset on clean low-FPS stats without limitation', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.highQuality.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 20; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 16,
            requestedFps: 60,
            bitrateBps: 8000000,
            targetBitrateBps: 18000000,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.highQuality);
      expect(decision.profile.mainLayer.width, 1920);
      expect(decision.profile.mainLayer.height, 1080);
      expect(decision.profile.mainLayer.maxBitrateBps, 18000000);
      expect(decision.reason, isNull);
    });

    test('degrades on sustained capture-stage FPS deficit', () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.balanced.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 8; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 19,
            captureFps: 20,
            encodeFps: 19,
            sendFps: 19,
            requestedFps: 30,
            bitrateBps: 4600000,
            targetBitrateBps: 8000000,
            availableOutgoingBitrateBps: 7800000,
            averageEncodeTimeMs: 65,
            packetLossPercent: 0,
            packetsLost: 0,
            nackCount: 0,
            roundTripTimeMs: 3,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isTrue);
      expect(decision.reason, 'capture FPS below target');
      expect(decision.profile.profile, ScreenShareQualityProfile.smooth);
    });

    test('does not shrink below smooth for capture-limited clean sender stats',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.smooth.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 20; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 16,
            captureFps: 16,
            encodeFps: 16,
            sendFps: 16,
            requestedFps: 30,
            bitrateBps: 1400000,
            targetBitrateBps: 3000000,
            availableOutgoingBitrateBps: 19000000,
            averageEncodeTimeMs: 65,
            packetLossPercent: 0,
            packetsLost: 0,
            nackCount: 0,
            roundTripTimeMs: 3,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.reason, 'capture FPS below target');
      expect(decision.profile.profile, ScreenShareQualityProfile.smooth);
      expect(decision.profile.mainLayer.width, 1280);
      expect(decision.profile.mainLayer.height, 720);
      expect(decision.profile.mainLayer.maxFramerate, 36);
      expect(decision.profile.mainLayer.targetFramerateForScoring, 30);
      expect(decision.profile.mainLayer.maxBitrateBps, 3000000);
      expect(decision.profile.mainLayer.minBitrateBps, 2500000);
    });

    test('does not treat capture-stage FPS deficit as clean when loss exists',
        () {
      final controller = ScreenShareAdaptiveFallbackController();
      final start = DateTime(2026);
      final requestedProfile =
          ScreenShareProfileConfig.balanced.withHardwareEncodingPreference();
      ScreenShareAdaptiveFallbackDecision decision =
          ScreenShareAdaptiveFallbackDecision(profile: requestedProfile);

      for (var seconds = 0; seconds <= 20; seconds += 2) {
        decision = controller.evaluate(
          requestedProfile: requestedProfile,
          snapshot: _snapshot(
            now: start.add(Duration(seconds: seconds)),
            fps: 19,
            captureFps: 20,
            encodeFps: 19,
            sendFps: 19,
            requestedFps: 30,
            bitrateBps: 8000000,
            targetBitrateBps: 8000000,
            packetLossPercent: 2,
            packetsLost: 1,
            nackCount: 1,
            roundTripTimeMs: 3,
            hardwareEncodeActive: true,
            encoderImplementation: 'MediaFoundationH264',
          ),
          now: start.add(Duration(seconds: seconds)),
        );
      }

      expect(decision.changed, isFalse);
      expect(decision.profile.profile, ScreenShareQualityProfile.balanced);
      expect(decision.reason, isNull);
    });
  });
}

VoipCallDiagnosticsSnapshot _snapshot({
  required DateTime now,
  required double fps,
  required int? bitrateBps,
  required int targetBitrateBps,
  int? requestedWidth,
  int? requestedHeight,
  int? encodedWidth,
  int? encodedHeight,
  double? requestedFps,
  double? captureFps,
  double? encodeFps,
  double? sendFps,
  String? limitation,
  int? availableOutgoingBitrateBps,
  double? packetLossPercent,
  int? packetsLost,
  int? nackCount,
  double? roundTripTimeMs,
  bool? hardwareEncodeActive,
  String? encoderImplementation,
  int? framesDroppedBeforeEncode,
  int? framesDroppedByEncoder,
  double? averageEncodeTimeMs,
  double? averagePacketSendDelayMs,
}) {
  return VoipCallDiagnosticsSnapshot(
    collectedAt: now,
    screenShareProfileLabel: 'test',
    adaptiveStreamEnabled: true,
    dynacastEnabled: true,
    screenShareSimulcastEnabled: true,
    adaptiveFallbackEnabled: true,
    participants: const [],
    tracks: [
      VoipTrackDiagnostics(
        streamId: 'share',
        label: 'share',
        type: VoipStreamType.screenshare,
        direction: VoipDiagnosticsTrackDirection.sender,
        requestedWidth: requestedWidth,
        requestedHeight: requestedHeight,
        requestedFps: requestedFps,
        captureFps: captureFps,
        width: encodedWidth,
        height: encodedHeight,
        fps: fps,
        encodeFps: encodeFps,
        sendFps: sendFps,
        bitrateBps: bitrateBps,
        targetBitrateBps: targetBitrateBps,
        availableOutgoingBitrateBps: availableOutgoingBitrateBps,
        packetsLost: packetsLost ?? 0,
        packetsReceived: 100,
        nackCount: nackCount,
        packetLossPercent: packetLossPercent ?? 0,
        roundTripTimeMs: roundTripTimeMs,
        qualityLimitationReason: limitation,
        hardwareEncodeActive: hardwareEncodeActive,
        encoderImplementation: encoderImplementation,
        framesDroppedBeforeEncode: framesDroppedBeforeEncode,
        framesDroppedByEncoder: framesDroppedByEncoder,
        averageEncodeTimeMs: averageEncodeTimeMs,
        averagePacketSendDelayMs: averagePacketSendDelayMs,
      ),
    ],
  );
}
