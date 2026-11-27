import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/stream_live_tuning_harness_base.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';

void main() {
  group('StreamLiveTuningConfig', () {
    test('parses debug config fields and backend override', () {
      final config = StreamLiveTuningConfig.fromJson(const {
        'enabled': true,
        'experimentName': 'smooth-720-wgc',
        'profile': 'smooth',
        'maxWidth': 1280,
        'maxHeight': 720,
        'maxFps': 36,
        'targetFps': 30,
        'bitrateKbps': 3000,
        'minBitrateKbps': 2500,
        'codec': 'h264',
        'preferHardwareEncoding': true,
        'singleLayer': true,
        'captureBackend': 'wgc-only',
      });

      expect(config.enabled, isTrue);
      expect(config.experimentName, 'smooth-720-wgc');
      expect(config.hasWindowsCaptureBackendOverride, isTrue);
      expect(
        config.effectiveWindowsCaptureBackendMode,
        WindowsScreenCaptureBackendMode.wgcOnly,
      );

      final profile = config.toScreenShareProfile(
        ScreenShareProfileConfig.smooth,
      );
      expect(profile.mainLayer.width, 1280);
      expect(profile.mainLayer.height, 720);
      expect(profile.mainLayer.maxFramerate, 36);
      expect(profile.mainLayer.targetFramerateForScoring, 30);
      expect(profile.mainLayer.maxBitrateBps, 3000000);
      expect(profile.mainLayer.minBitrateBps, 2500000);
      expect(profile.codec, 'h264');
      expect(profile.hardwareEncodeFirst, isTrue);
      expect(profile.useSimulcast, isFalse);
    });

    test('derives hardware preset bitrate floor for live republish profiles',
        () {
      final config = StreamLiveTuningConfig.fromJson(const {
        'enabled': true,
        'profile': 'balanced',
        'maxWidth': 1920,
        'maxHeight': 1080,
        'maxFps': 36,
        'targetFps': 30,
        'bitrateKbps': 8000,
        'preferHardwareEncoding': true,
      });

      final profile = config.toScreenShareProfile(
        ScreenShareProfileConfig.balanced.withHardwareEncodingPreference(),
      );
      expect(profile.mainLayer.maxBitrateBps, 8000000);
      expect(profile.mainLayer.minBitrateBps, 4000000);
      expect(profile.mainLayer.targetFramerateForScoring, 30);
    });

    test('leaves profile untouched when only experiment metadata changes', () {
      final config = StreamLiveTuningConfig.fromJson(const {
        'enabled': true,
        'experimentName': 'label-only',
      });

      final profile = config.toScreenShareProfile(
        ScreenShareProfileConfig.balanced,
      );
      expect(identical(profile, ScreenShareProfileConfig.balanced), isTrue);
      expect(config.hasProfileOverrides, isFalse);
    });

    test('reports non-live settings as application notes', () {
      final config = StreamLiveTuningConfig.fromJson(const {
        'enabled': true,
        'dynacast': false,
        'framePacing': true,
        'fallbackMode': 'disabled',
      });

      expect(
        config.applicationNotes,
        containsAll([
          'dynacast_requires_room_reconnect',
          'frame_pacing_is_native_build_or_app_default_only',
          'fallback_mode_observe_only=disabled',
        ]),
      );
    });

    test('marks DirectX live backend runs as restart-boundary samples', () {
      final config = StreamLiveTuningConfig.fromJson(const {
        'enabled': true,
        'captureBackend': 'directx-only',
      });

      expect(config.usesDirectxLiveBackend, isTrue);
      expect(
        config.applicationNotes,
        contains(
          'directx_live_backend_requires_stream_restart_before_next_backend',
        ),
      );
    });
  });

  group('StreamLiveTuningScore', () {
    test('uses required comparison score formula', () {
      final score = StreamLiveTuningScore.fromSnapshot(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          sendFps: 30,
          lossPercent: 0,
          rttMs: 20,
        ),
        profile: ScreenShareProfileConfig.smooth,
      );

      expect(score.stableFps, 25);
      expect(score.targetResolution, 25);
      expect(score.lowLoss, 25);
      expect(score.lowRtt, 15);
      expect(score.downgradePenalty, 0);
      expect(score.total, 90);
      expect(score.toJson()['formula'], contains('stable_fps'));
    });

    test('penalizes low layer and quality limitation evidence', () {
      final score = StreamLiveTuningScore.fromSnapshot(
        snapshot: _snapshot(
          width: 426,
          height: 240,
          sendFps: 10,
          lossPercent: 0,
          rttMs: 20,
          activeLayer: 'q',
          qualityLimitationReason: 'cpu',
        ),
        profile: ScreenShareProfileConfig.smooth,
      );

      expect(score.downgradePenalty, 30);
      expect(score.total, lessThan(90));
    });
  });
}

VoipCallDiagnosticsSnapshot _snapshot({
  required int width,
  required int height,
  required double sendFps,
  required double lossPercent,
  required double rttMs,
  String? activeLayer,
  String? qualityLimitationReason,
}) {
  return VoipCallDiagnosticsSnapshot(
    collectedAt: DateTime.utc(2026, 5, 19, 22),
    screenShareProfileLabel: 'Smooth',
    adaptiveStreamEnabled: true,
    dynacastEnabled: true,
    screenShareSimulcastEnabled: false,
    adaptiveFallbackEnabled: false,
    participants: const [],
    tracks: [
      VoipTrackDiagnostics(
        streamId: 'sender',
        label: 'screenshare',
        type: VoipStreamType.screenshare,
        direction: VoipDiagnosticsTrackDirection.sender,
        requestedWidth: 1280,
        requestedHeight: 720,
        requestedFps: 30,
        requestedBitrateBps: 1800000,
        width: width,
        height: height,
        sendFps: sendFps,
        packetLossPercent: lossPercent,
        roundTripTimeMs: rttMs,
        activeLayer: activeLayer,
        qualityLimitationReason: qualityLimitationReason,
      ),
    ],
  );
}
