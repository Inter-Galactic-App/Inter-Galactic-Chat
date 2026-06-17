import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';

void main() {
  group('VoipDiagnosticsMath', () {
    test('calculates bitrate from byte and timestamp deltas', () {
      final bitrate = VoipDiagnosticsMath.bitrateBps(
        previousBytes: 1000,
        currentBytes: 2000,
        previousTimestamp: 0,
        currentTimestamp: 1000,
      );

      expect(bitrate, 8000);
    });

    test('normalizes native microsecond timestamp deltas', () {
      final bitrate = VoipDiagnosticsMath.bitrateBps(
        previousBytes: 3070573,
        currentBytes: 3260372,
        previousTimestamp: 1777860169481532,
        currentTimestamp: 1777860171482712,
      );

      expect(bitrate, inInclusiveRange(758000, 760000));
    });

    test('returns null when stats are missing or stale', () {
      expect(
        VoipDiagnosticsMath.bitrateBps(
          previousBytes: null,
          currentBytes: 2000,
          previousTimestamp: 0,
          currentTimestamp: 1000,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.bitrateBps(
          previousBytes: 2000,
          currentBytes: 1000,
          previousTimestamp: 0,
          currentTimestamp: 1000,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.bitrateBps(
          previousBytes: 1000,
          currentBytes: 2000,
          previousTimestamp: 1000,
          currentTimestamp: 1000,
        ),
        isNull,
      );
    });

    test('calculates packet loss and jitter fallbacks', () {
      expect(
        VoipDiagnosticsMath.packetLossPercent(
          packetsLost: 5,
          packetsReceived: 95,
        ),
        5,
      );
      expect(
        VoipDiagnosticsMath.packetLossPercent(
          packetsLost: null,
          packetsReceived: 95,
        ),
        isNull,
      );
      expect(VoipDiagnosticsMath.jitterMs(0.012), 12);
      expect(VoipDiagnosticsMath.secondsToMs(0.045), 45);
    });

    test('calculates jitter-buffer average from emitted-count deltas', () {
      expect(
        VoipDiagnosticsMath.jitterBufferDelayAverageMs(
          previousDelaySeconds: 1.0,
          currentDelaySeconds: 1.6,
          previousEmittedCount: 10,
          currentEmittedCount: 40,
        ),
        closeTo(20, 0.001),
      );
      expect(
        VoipDiagnosticsMath.jitterBufferDelayAverageMs(
          previousDelaySeconds: null,
          currentDelaySeconds: 1.6,
          previousEmittedCount: 10,
          currentEmittedCount: 40,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.jitterBufferDelayAverageMs(
          previousDelaySeconds: 1.6,
          currentDelaySeconds: 1.0,
          previousEmittedCount: 10,
          currentEmittedCount: 40,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.jitterBufferDelayAverageMs(
          previousDelaySeconds: 1.0,
          currentDelaySeconds: 1.6,
          previousEmittedCount: 40,
          currentEmittedCount: 40,
        ),
        isNull,
      );
    });

    test('calculates average duration from cumulative counters', () {
      expect(
        VoipDiagnosticsMath.averageDurationMs(
          previousTotalSeconds: 1.0,
          currentTotalSeconds: 1.5,
          previousCount: 10,
          currentCount: 35,
        ),
        closeTo(20, 0.001),
      );
      expect(
        VoipDiagnosticsMath.averageDurationMs(
          previousTotalSeconds: null,
          currentTotalSeconds: 1.5,
          previousCount: 10,
          currentCount: 35,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.averageDurationMs(
          previousTotalSeconds: 1.5,
          currentTotalSeconds: 1.0,
          previousCount: 10,
          currentCount: 35,
        ),
        isNull,
      );
      expect(
        VoipDiagnosticsMath.averageDurationMs(
          previousTotalSeconds: 1.0,
          currentTotalSeconds: 1.5,
          previousCount: 35,
          currentCount: 35,
        ),
        isNull,
      );
    });

    test('classifies common encoder implementation strings', () {
      expect(VoipDiagnosticsMath.isLikelyHardwareEncoder('libvpx'), isFalse);
      expect(
        VoipDiagnosticsMath.isLikelyHardwareEncoder('OpenH264'),
        isFalse,
      );
      expect(
        VoipDiagnosticsMath.isLikelyHardwareEncoder(
          'MediaFoundationVideoEncoder',
        ),
        isTrue,
      );
      expect(
        VoipDiagnosticsMath.isLikelyHardwareEncoder('NVIDIA NVENC H264'),
        isTrue,
      );
      expect(
        VoipDiagnosticsMath.isLikelyHardwareEncoder('MediaCodec H264'),
        isTrue,
      );
      expect(VoipDiagnosticsMath.isLikelyHardwareEncoder(null), isNull);
      expect(
        VoipDiagnosticsMath.isLikelyHardwareEncoder('unknown encoder'),
        isNull,
      );
    });
  });
}
