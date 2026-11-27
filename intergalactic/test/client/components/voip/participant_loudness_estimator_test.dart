import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_config.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_estimator.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';

/// Deterministic driver for the estimator.
///
/// Uses explicit timestamps only — no real timers and no fake-async — so
/// every fixture below is reproducible and order-independent.
class _LevelSequenceHarness {
  _LevelSequenceHarness({
    ParticipantLoudnessConfig config = const ParticipantLoudnessConfig(),
  }) : estimator = ParticipantLoudnessEstimator(
         participantKey: 'participant-under-test',
         trackKey: 'track-1',
         measurementSource:
             ParticipantLoudnessMeasurementSource.syntheticSamples,
         config: config,
       );

  final ParticipantLoudnessEstimator estimator;

  /// Sampling cadence the fixtures assume, matching the monitor's default.
  final int stepMs = 100;

  int timeMs = 0;

  ParticipantLoudnessState get state => estimator.state;

  /// Feeds a constant level for [durationMs].
  void feed(
    double level, {
    required int durationMs,
    bool muted = false,
    double? speechHint,
  }) {
    final steps = math.max(1, durationMs ~/ stepMs);
    for (var index = 0; index < steps; index++) {
      estimator.addSample(
        ParticipantLoudnessSample(
          timeMs: timeMs,
          level: level,
          muted: muted,
          speechHint: speechHint,
        ),
      );
      timeMs += stepMs;
    }
  }

  /// Feeds exactly one sample, for single-transient style fixtures.
  void feedOnce(double level) {
    estimator.addSample(
      ParticipantLoudnessSample(timeMs: timeMs, level: level),
    );
    timeMs += stepMs;
  }
}

/// Linear amplitude for a dBFS-equivalent level, so fixtures read in the same
/// units the estimator reasons in.
double _linearForDb(double db) => math.pow(10, db / 20).toDouble();

/// Quiet room tone every fixture opens with, so the noise floor has something
/// real to settle onto before speech arrives.
final double _roomTone = _linearForDb(-52);

void main() {
  group('ParticipantLoudnessEstimator', () {
    test('quiet stable speaker gets a positive suggested gain', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-32), durationMs: 6000);

      final state = harness.state;
      expect(state.speechState, ParticipantSpeechState.activeSpeech);
      expect(state.activeSpeechLevelDb, isNotNull);
      expect(state.activeSpeechLevelDb!, closeTo(-32, 1.5));
      expect(state.suggestedAutoGainDb, isNotNull);
      expect(
        state.suggestedAutoGainDb!,
        greaterThan(5),
        reason: 'a speaker 13 dB below target should be boosted',
      );
      expect(state.suggestedAutoGainDb!, lessThanOrEqualTo(12));
    });

    test('normal speaker at target gets a suggestion near 0 dB', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-19), durationMs: 8000);

      final state = harness.state;
      expect(state.suggestedAutoGainDb, isNotNull);
      expect(state.suggestedAutoGainDb!, closeTo(0, 2.0));
    });

    test('loud speaker gets a negative suggestion clamped at the floor', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-6), durationMs: 8000);

      final state = harness.state;
      expect(state.suggestedAutoGainDb, isNotNull);
      expect(state.suggestedAutoGainDb!, lessThan(0));
      expect(
        state.suggestedAutoGainDb!,
        greaterThanOrEqualTo(-9),
        reason: 'the reduction clamp must hold',
      );
    });

    test('silence never produces a climbing suggestion', () {
      final harness = _LevelSequenceHarness();

      harness.feed(0.0, durationMs: 30000);

      final state = harness.state;
      expect(state.speechState, ParticipantSpeechState.silence);
      expect(state.speechSampleCount, 0);
      expect(
        state.suggestedAutoGainDb,
        isNull,
        reason: 'no speech means no recommendation at all, not +12 dB',
      );
    });

    test('constant quiet background noise is not treated as quiet speech', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_linearForDb(-48), durationMs: 30000);

      final state = harness.state;
      expect(state.speechSampleCount, 0);
      expect(state.suggestedAutoGainDb, isNull);
      expect(state.speechState, isNot(ParticipantSpeechState.activeSpeech));
    });

    test('a zero relative threshold disables floor gating without touching '
        'the absolute floor', () {
      // The inbound-rtp preset zeroes speechAboveNoiseFloorDb because that
      // source's floor only ever contains speech (the config documents why).
      // The sentinel must bypass ONLY the relative comparison: the same
      // near-floor sequence accumulates speech samples under the sentinel and
      // none under the default positive threshold.
      final zeroThreshold = _LevelSequenceHarness(
        config: const ParticipantLoudnessConfig(speechAboveNoiseFloorDb: 0.0),
      );
      final positiveThreshold = _LevelSequenceHarness();

      for (final harness in [zeroThreshold, positiveThreshold]) {
        harness.feed(_roomTone, durationMs: 3000);
        // 4 dB over the settled floor: above absoluteSpeechFloorDb, but well
        // under the default floor + 9 dB requirement.
        harness.feed(_linearForDb(-48), durationMs: 4000);
      }

      expect(
        zeroThreshold.state.speechSampleCount,
        greaterThanOrEqualTo(
          const ParticipantLoudnessConfig().minimumSpeechSamples,
        ),
        reason:
            'the sentinel must let near-floor speech reach the publish '
            'threshold instead of starving it',
      );
      expect(
        positiveThreshold.state.speechSampleCount,
        0,
        reason: 'a positive threshold must still gate relative to the floor',
      );
    });

    test('a noise floor that steps up recovers instead of locking in a bogus '
        'recommendation', () {
      final harness = _LevelSequenceHarness();

      // Known limitation: an abrupt step from digital silence to steady room
      // tone looks exactly like speech starting, because at that instant the
      // floor is still describing the silence. What must not happen is that
      // the estimator believes it forever.
      harness.feed(0.0, durationMs: 1000);
      harness.feed(_linearForDb(-48), durationMs: 5000);
      expect(
        harness.state.speechSampleCount,
        greaterThan(0),
        reason: 'documents the transient misfire this test exists to bound',
      );

      harness.feed(_linearForDb(-48), durationMs: 20000);

      final state = harness.state;
      expect(
        state.speechSampleCount,
        0,
        reason: 'the sustained-run escape must discard the false speech',
      );
      expect(state.suggestedAutoGainDb, isNull);
      expect(state.estimatedNoiseFloorDb!, closeTo(-48, 1.0));

      // The counters that survive the discard are the only way to tell this
      // apart from a participant who simply never spoke. Without them an
      // exported session shows a small speech count with no explanation.
      final summary = harness.estimator.summarize();
      expect(summary.sustainedRunAbandonCount, greaterThan(0));
      expect(summary.speechSampleCount, 0);
      expect(
        summary.peakSpeechConfidence,
        greaterThan(0.0),
        reason: 'the session peak records that speech was once believed',
      );
    });

    test('the summary reports peak confidence, not the decayed live value', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-19), durationMs: 8000);
      final peakWhileSpeaking = harness.state.speechConfidence;
      expect(peakWhileSpeaking, greaterThan(0.9));

      // Long silence: exactly the shape of every session captured so far,
      // where the report was exported after the talker had stopped.
      harness.feed(0.0, durationMs: 60000);

      expect(
        harness.state.speechConfidence,
        lessThan(0.1),
        reason: 'the live value is meant to decay',
      );

      final summary = harness.estimator.summarize();
      expect(
        summary.peakSpeechConfidence,
        greaterThan(0.9),
        reason: 'the exported summary must not understate a good measurement',
      );
      expect(summary.msSinceLastSpeech, greaterThan(50000));
    });

    test('percentiles are withheld until there is a distribution', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      // Barely any speech: enough to register, nowhere near the publish
      // threshold. A live session reported a median of -6.22 with a spread of
      // 0.00 from exactly one sample before this was withheld.
      //
      // Derived from the config rather than written as a magic 400ms: a run
      // only becomes active after `minimumSpeechDuration`, so the feed has to
      // outlast that (plus one step, since the sample AT the boundary is the
      // first active one) while staying well under `minimumSpeechSamples`.
      final config = harness.estimator.config;
      final thinFeedMs =
          config.minimumSpeechDuration.inMilliseconds + 2 * harness.stepMs;
      expect(
        thinFeedMs ~/ harness.stepMs,
        lessThan(config.minimumSpeechSamples),
        reason: 'the thin fixture must stay below the publish threshold',
      );
      harness.feed(_linearForDb(-19), durationMs: thinFeedMs);

      final thin = harness.estimator.summarize();
      expect(thin.speechSampleCount, greaterThan(0));
      expect(thin.speechSampleCount, lessThan(config.minimumSpeechSamples));
      expect(thin.medianActiveSpeechLevelDb, isNull);
      expect(thin.lowActiveSpeechLevelDb, isNull);
      expect(thin.highActiveSpeechLevelDb, isNull);
      expect(thin.activeSpeechSpreadDb, isNull);
      expect(
        thin.peakLevelDb,
        isNotNull,
        reason: 'a peak is one observation and needs no distribution',
      );

      harness.feed(_linearForDb(-19), durationMs: 6000);

      final full = harness.estimator.summarize();
      expect(
        full.speechSampleCount,
        greaterThanOrEqualTo(config.minimumSpeechSamples),
      );
      expect(full.medianActiveSpeechLevelDb, isNotNull);
      expect(full.activeSpeechSpreadDb, isNotNull);
    });

    test('resetMeasurement is counted so a report can show it happened', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-19), durationMs: 6000);
      expect(harness.estimator.summarize().measurementResetCount, 0);

      harness.estimator.onTrackReplaced('another-track');

      final summary = harness.estimator.summarize();
      expect(summary.measurementResetCount, 1);
      expect(summary.sampleCount, 0);
      expect(
        summary.peakSpeechConfidence,
        greaterThan(0.9),
        reason: 'lifetime counters survive the reset they record',
      );
    });

    test('a single transient does not depress the recommendation', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-19), durationMs: 6000);
      final beforeTransient = harness.state.suggestedAutoGainDb;

      // One isolated full-scale spike, then speech resumes.
      harness.feedOnce(1.0);
      harness.feed(_linearForDb(-19), durationMs: 3000);

      final state = harness.state;
      expect(beforeTransient, isNotNull);
      expect(state.suggestedAutoGainDb, isNotNull);
      expect(
        state.suggestedAutoGainDb!,
        closeTo(beforeTransient!, 1.5),
        reason: 'one clipped peak must not rewrite the recommendation',
      );
      expect(
        state.peakLevelDb!,
        closeTo(0, 0.5),
        reason: 'the peak itself is still reported',
      );
    });

    test('a short spike is classified as a transient, not speech', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 3000);
      harness.feedOnce(_linearForDb(-10));
      harness.feed(_roomTone, durationMs: 300);

      expect(harness.state.speechSampleCount, 0);
    });

    test('intermittent speech holds the estimate between phrases', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 4000);
      final duringSpeech = harness.state.suggestedAutoGainDb;

      harness.feed(_roomTone, durationMs: 2000);
      final duringGap = harness.state.suggestedAutoGainDb;

      harness.feed(_linearForDb(-30), durationMs: 2000);
      final afterSecondPhrase = harness.state.suggestedAutoGainDb;

      expect(duringSpeech, isNotNull);
      expect(
        duringGap,
        closeTo(duringSpeech!, 0.01),
        reason: 'the estimate freezes during a gap rather than drifting',
      );
      expect(afterSecondPhrase, closeTo(duringSpeech, 2.0));
    });

    test('confidence decays over long silence but the estimate survives', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 6000);
      final speakingConfidence = harness.state.speechConfidence;
      final speakingSuggestion = harness.state.suggestedAutoGainDb;

      harness.feed(_roomTone, durationMs: 60000);

      final state = harness.state;
      expect(speakingConfidence, greaterThan(0.9));
      expect(state.speechConfidence, lessThan(0.1));
      expect(state.suggestedAutoGainDb, closeTo(speakingSuggestion!, 0.01));
    });

    test('muted samples are ignored and unmute resumes conservatively', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 6000);
      final beforeMute = harness.state;

      // Muted samples still arrive, carrying a level that must be discarded.
      harness.feed(_linearForDb(-6), durationMs: 4000, muted: true);
      final muted = harness.state;

      expect(muted.muted, isTrue);
      expect(muted.speechState, ParticipantSpeechState.silence);
      expect(
        muted.speechSampleCount,
        beforeMute.speechSampleCount,
        reason: 'muting stops speech accumulation',
      );
      expect(
        muted.suggestedAutoGainDb,
        closeTo(beforeMute.suggestedAutoGainDb!, 0.01),
      );

      // Unmuting must not immediately count as speech again.
      harness.feed(_linearForDb(-30), durationMs: 100);
      expect(
        harness.state.speechState,
        isNot(ParticipantSpeechState.activeSpeech),
      );
    });

    // The test above unmutes from an established follower, which is why it
    // never caught this: the crash needs the FIRST sample to be muted, so the
    // sample clock advances while `_smoothedLevelDb` is still null and the next
    // unmuted sample integrates from nothing. A participant who joins muted is
    // the ordinary case.
    test('unmuting after a muted first sample does not crash', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 200, muted: true);
      harness.feed(_linearForDb(-19), durationMs: 1000);

      expect(harness.state.sampleCount, greaterThan(0));
      expect(harness.state.muted, isFalse);
    });

    test('a muted first sample after a track swap also resynchronizes', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 4000);
      harness.estimator.onTrackReplaced('track-2');

      // Same shape as above, but reached through the reset path rather than
      // construction.
      harness.feed(_roomTone, durationMs: 200, muted: true);
      harness.feed(_linearForDb(-19), durationMs: 1000);

      expect(harness.state.sampleCount, greaterThan(0));
    });

    test('track replacement resets measurement but keeps the override', () {
      final harness = _LevelSequenceHarness();

      harness.estimator.setManualOverride(linearVolume: 1.6, hasOverride: true);
      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 6000);
      expect(harness.state.suggestedAutoGainDb, isNotNull);

      harness.estimator.onTrackReplaced('track-2');

      final state = harness.state;
      expect(state.trackKey, 'track-2');
      expect(state.suggestedAutoGainDb, isNull);
      expect(state.speechSampleCount, 0);
      expect(state.sampleCount, 0);
      expect(
        state.hasManualOverride,
        isTrue,
        reason: 'the user set this; a track flap must not discard it',
      );
      expect(state.manualOverrideLinear, closeTo(1.6, 0.001));
    });

    test('replacing with the same track key does not reset', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-19), durationMs: 6000);
      final before = harness.state.speechSampleCount;

      harness.estimator.onTrackReplaced('track-1');

      expect(harness.state.speechSampleCount, before);
    });

    test('combined gain adds the manual override to the suggestion', () {
      final harness = _LevelSequenceHarness();

      // 0.5 linear is -6.02 dB of manual reduction.
      harness.estimator.setManualOverride(linearVolume: 0.5, hasOverride: true);
      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 6000);

      final state = harness.state;
      expect(state.manualOverrideDb, closeTo(-6.02, 0.05));
      expect(
        state.futureCombinedGainDb,
        closeTo(state.suggestedAutoGainDb! + state.manualOverrideDb, 0.001),
      );
    });

    test(
      'a gap longer than the tolerance resynchronizes instead of integrating',
      () {
        final harness = _LevelSequenceHarness();

        harness.feed(_roomTone, durationMs: 2000);
        harness.feed(_linearForDb(-19), durationMs: 6000);
        final before = harness.state.suggestedAutoGainDb;

        // Ten seconds with no samples at all, then speech again.
        harness.timeMs += 10000;
        harness.feed(_linearForDb(-19), durationMs: 1000);

        final state = harness.state;
        expect(state.suggestedAutoGainDb, isNotNull);
        expect(
          state.suggestedAutoGainDb!,
          closeTo(before!, 2.0),
          reason:
              'the surviving estimate is reused, not recomputed from a hole',
        );
      },
    );

    test('an external speech hint outranks the level heuristic', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      // Loud, but the hint says it is not speech.
      harness.feed(_linearForDb(-12), durationMs: 5000, speechHint: 0.0);

      expect(harness.state.speechSampleCount, 0);
      expect(harness.state.suggestedAutoGainDb, isNull);
    });

    test('two samples sharing a timestamp cannot advance the filters', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      final before = harness.state.smoothedLevel;

      harness.estimator.addSample(
        ParticipantLoudnessSample(
          timeMs: harness.timeMs - harness.stepMs,
          level: 1.0,
        ),
      );

      expect(harness.state.smoothedLevel, closeTo(before, 0.0001));
    });

    test('a bad timestamp costs one sample, not the rest of the call', () {
      // Both directions are self-limiting because _lastSampleTimeMs follows the
      // newest sample unconditionally: the very next sample is measured against
      // the corrected clock. Pinned in both directions because CodeRabbit
      // (PR #87) read this the other way round and proposed clamping the clock
      // to move forward only - which is the change that WOULD freeze the
      // estimator permanently after one spurious future timestamp.
      for (final skewMs in [60000, -60000]) {
        final harness = _LevelSequenceHarness();

        harness.feed(_roomTone, durationMs: 2000);
        harness.estimator.addSample(
          ParticipantLoudnessSample(
            timeMs: harness.timeMs + skewMs,
            level: _roomTone,
          ),
        );
        final before = harness.state.smoothedLevel;

        harness.feed(_linearForDb(-12), durationMs: 2000);

        expect(
          harness.state.smoothedLevel,
          greaterThan(before),
          reason: 'skew ${skewMs}ms must not stall the filter',
        );
      }
    });

    test('summary reports percentiles and spread over observed speech', () {
      final harness = _LevelSequenceHarness();

      harness.feed(_roomTone, durationMs: 2000);
      harness.feed(_linearForDb(-30), durationMs: 4000);
      harness.feed(_linearForDb(-22), durationMs: 4000);

      final summary = harness.estimator.summarize();
      expect(summary.speechSampleCount, greaterThan(24));
      expect(summary.medianActiveSpeechLevelDb, isNotNull);
      expect(summary.lowActiveSpeechLevelDb, isNotNull);
      expect(summary.highActiveSpeechLevelDb, isNotNull);
      expect(
        summary.highActiveSpeechLevelDb!,
        greaterThan(summary.lowActiveSpeechLevelDb!),
      );
      expect(summary.activeSpeechSpreadDb, greaterThan(0));
      expect(summary.measurementDurationMs, greaterThan(9000));
      expect(summary.finalSuggestedGainDb, isNotNull);
    });
  });

  group('ParticipantLoudnessMath', () {
    test('linear and dB conversions round-trip', () {
      for (final db in const [-60.0, -30.0, -19.0, -6.0, 0.0]) {
        final linear = ParticipantLoudnessMath.dbToLinear(db);
        expect(ParticipantLoudnessMath.linearToDb(linear), closeTo(db, 0.001));
      }
    });

    test(
      'zero and negative amplitudes floor instead of returning infinity',
      () {
        expect(
          ParticipantLoudnessMath.linearToDb(0.0),
          ParticipantLoudnessConfig.minimumMeasurableDb,
        );
        expect(
          ParticipantLoudnessMath.linearToDb(-1.0),
          ParticipantLoudnessConfig.minimumMeasurableDb,
        );
      },
    );

    test('a unity manual override is 0 dB', () {
      expect(ParticipantLoudnessMath.linearGainToDb(1.0), closeTo(0, 0.0001));
      expect(ParticipantLoudnessMath.linearGainToDb(2.0), closeTo(6.02, 0.01));
    });

    test('smoothing does not move when no time has passed', () {
      expect(
        ParticipantLoudnessMath.smoothingFactor(
          0,
          const Duration(milliseconds: 500),
        ),
        0.0,
      );
      expect(ParticipantLoudnessMath.smoothingFactor(100, Duration.zero), 1.0);
    });
  });
}
