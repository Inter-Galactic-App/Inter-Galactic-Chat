import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_inbound_audio_energy.dart';

VoipInboundAudioEnergySample _sample({
  required int capturedAtMs,
  double? totalAudioEnergy,
  double? totalSamplesDuration,
  double? audioLevel,
}) {
  return VoipInboundAudioEnergySample(
    capturedAtMs: capturedAtMs,
    totalAudioEnergy: totalAudioEnergy,
    totalSamplesDuration: totalSamplesDuration,
    audioLevel: audioLevel,
  );
}

void main() {
  group('intervalRmsAmplitude', () {
    test('computes the RMS amplitude of the window between two readings', () {
      // 0.5 amplitude-squared accumulated over 2 seconds of decoded audio is a
      // mean square of 0.25, so an RMS amplitude of 0.5.
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 1.0,
          totalSamplesDuration: 10.0,
        ),
        current: _sample(
          capturedAtMs: 3000,
          totalAudioEnergy: 1.5,
          totalSamplesDuration: 12.0,
        ),
      );

      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5, 1e-9));
    });

    test('is poll-rate independent for the same decoded audio', () {
      // The whole point of the source: one window sampled as a single 2s poll
      // and as two 1s polls must describe the same level.
      final single = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        ),
        current: _sample(
          capturedAtMs: 2000,
          totalAudioEnergy: 0.08,
          totalSamplesDuration: 2.0,
        ),
      );
      final secondHalf = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.04,
          totalSamplesDuration: 1.0,
        ),
        current: _sample(
          capturedAtMs: 2000,
          totalAudioEnergy: 0.08,
          totalSamplesDuration: 2.0,
        ),
      );

      expect(single, isNotNull);
      expect(secondHalf, isNotNull);
      expect(secondHalf!, closeTo(single!, 1e-9));
    });

    test('separates a quiet talker from a loud one by a usable margin', () {
      // The rejected visualizer source compressed five participants into a
      // 0.73 dB peak span. A 20 dB real difference must survive as ~20 dB.
      double? rmsFor(double energyDelta) {
        return VoipInboundAudioEnergy.intervalRmsAmplitude(
          previous: _sample(
            capturedAtMs: 0,
            totalAudioEnergy: 0.0,
            totalSamplesDuration: 0.0,
          ),
          current: _sample(
            capturedAtMs: 1000,
            totalAudioEnergy: energyDelta,
            totalSamplesDuration: 1.0,
          ),
        );
      }

      final loud = rmsFor(0.01)!; // RMS 0.1  -> -20 dBFS
      final quiet = rmsFor(0.0001)!; // RMS 0.01 -> -40 dBFS

      final separationDb = 20 * (math.log(loud / quiet) / math.ln10);
      expect(separationDb, closeTo(20.0, 1e-6));
    });

    test('returns null rather than zero when no audio was decoded', () {
      // A substituted zero is indistinguishable from true digital silence and
      // would be averaged into a participant's history as an observation.
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 1.0,
          totalSamplesDuration: 5.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 1.0,
          totalSamplesDuration: 5.0,
        ),
      );

      expect(rms, isNull);
    });

    test('rejects a window too short to measure even when energy moved', () {
      // Distinct from the zero-delta case above: energy advanced, so only the
      // minimum-duration guard can reject this pair. Without it the tiny
      // divisor gives a mean square of ~4.0, which the clamp would publish as
      // a full-scale 1.0 reading rather than as "no measurement".
      final halfOfMinimum =
          VoipInboundAudioEnergy.minimumSamplesDurationDeltaSeconds / 2;
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 1.0,
          totalSamplesDuration: 5.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 1.02,
          totalSamplesDuration: 5.0 + halfOfMinimum,
        ),
      );

      expect(rms, isNull);
    });

    test('honours an explicit maximumIntervalMs override', () {
      // The parameter's default is the same-named class constant, so a
      // resolution mistake there would silently pin every caller to 5000ms.
      // Both directions are asserted: a tighter override must reject a pair the
      // default accepts, and a looser one must accept a pair it rejects.
      VoipInboundAudioEnergySample previous() => _sample(
        capturedAtMs: 0,
        totalAudioEnergy: 0.0,
        totalSamplesDuration: 0.0,
      );
      VoipInboundAudioEnergySample currentAt(int capturedAtMs) => _sample(
        capturedAtMs: capturedAtMs,
        totalAudioEnergy: 0.04,
        totalSamplesDuration: 1.0,
      );

      expect(
        VoipInboundAudioEnergy.intervalRmsAmplitude(
          previous: previous(),
          current: currentAt(2000),
        ),
        isNotNull,
      );
      expect(
        VoipInboundAudioEnergy.intervalRmsAmplitude(
          previous: previous(),
          current: currentAt(2000),
          maximumIntervalMs: 1000,
        ),
        isNull,
      );

      final beyondDefault = VoipInboundAudioEnergy.maximumIntervalMs + 1000;
      expect(
        VoipInboundAudioEnergy.intervalRmsAmplitude(
          previous: previous(),
          current: currentAt(beyondDefault),
        ),
        isNull,
      );
      expect(
        VoipInboundAudioEnergy.intervalRmsAmplitude(
          previous: previous(),
          current: currentAt(beyondDefault),
          maximumIntervalMs: beyondDefault + 1,
        ),
        closeTo(0.2, 1e-9),
      );
    });

    test('rejects a pair that spans a counter restart', () {
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 4.0,
          totalSamplesDuration: 40.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.01,
          totalSamplesDuration: 1.0,
        ),
      );

      expect(rms, isNull);
    });

    test('rejects a stale pairing', () {
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        ),
        current: _sample(
          capturedAtMs: VoipInboundAudioEnergy.maximumIntervalMs + 1,
          totalAudioEnergy: 1.0,
          totalSamplesDuration: 30.0,
        ),
      );

      expect(rms, isNull);
    });

    test('rejects a non-advancing or reversed clock', () {
      // `elapsedMs <= 0` covers both. The reversed case is not hypothetical: a
      // wall-clock adjustment mid-call moves capturedAtMs backwards, and the
      // subtraction would then produce a negative interval.
      final sameTimestamp = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.04,
          totalSamplesDuration: 1.0,
        ),
      );
      final reversed = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 2000,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.04,
          totalSamplesDuration: 1.0,
        ),
      );

      expect(sameTimestamp, isNull);
      expect(reversed, isNull);
    });

    test('requires both readings to carry counters', () {
      final missing = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(capturedAtMs: 0, audioLevel: 0.5),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 0.04,
          totalSamplesDuration: 1.0,
        ),
      );

      expect(missing, isNull);
      expect(
        _sample(capturedAtMs: 0, audioLevel: 0.5).hasEnergyCounters,
        false,
      );
    });

    test('clamps a non-conforming mean square to full scale', () {
      final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
        previous: _sample(
          capturedAtMs: 0,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        ),
        current: _sample(
          capturedAtMs: 1000,
          totalAudioEnergy: 9.0,
          totalSamplesDuration: 1.0,
        ),
      );

      expect(rms, 1.0);
    });
  });
}
