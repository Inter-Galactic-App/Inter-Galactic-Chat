/// Centralized tuning constants for receiver-side participant loudness
/// measurement.
///
/// This slice is measurement-only: nothing here is applied to playback. The
/// values are experimental defaults chosen so the estimator errs toward "no
/// recommendation" rather than toward a confident wrong one. They are kept in
/// one place so tuning never has to happen inside UI or event code.
class ParticipantLoudnessConfig {
  const ParticipantLoudnessConfig({
    this.targetSpeechLevelDb = -19.0,
    this.maximumBoostDb = 12.0,
    this.maximumReductionDb = -9.0,
    this.minimumSpeechSamples = 24,
    this.minimumSpeechDuration = const Duration(milliseconds: 220),
    this.silenceHoldDuration = const Duration(milliseconds: 1500),
    this.confidenceHoldDuration = const Duration(seconds: 10),
    this.confidenceDecayDuration = const Duration(seconds: 30),
    this.attackDuration = const Duration(milliseconds: 400),
    this.releaseDuration = const Duration(milliseconds: 3000),
    this.shortTermSmoothingDuration = const Duration(milliseconds: 150),
    this.speechLevelAveragingDuration = const Duration(milliseconds: 2000),
    this.noiseFloorFallDuration = const Duration(milliseconds: 600),
    this.noiseFloorRiseDuration = const Duration(milliseconds: 8000),
    this.noiseFloorWarmupRiseDuration = const Duration(milliseconds: 1500),
    this.speechAboveNoiseFloorDb = 9.0,
    this.absoluteSpeechFloorDb = -55.0,
    this.transientJumpDb = 12.0,
    this.maximumContinuousSpeechRun = const Duration(seconds: 20),
    this.maximumSampleGap = const Duration(seconds: 3),
  });

  /// Defaults retuned for the `inbound-rtp` energy source, which arrives at
  /// 1 Hz rather than the visualizer's 10 Hz poll.
  ///
  /// Three values change: the sample-count thresholds, the gap tolerance, and
  /// [speechAboveNoiseFloorDb] - zeroed to disable relative noise-floor gating
  /// entirely, for the reason given at the field below. Everything expressed
  /// as a duration is already cadence-independent, because the estimator
  /// derives its smoothing from each sample's own timestamp.
  static const ParticipantLoudnessConfig inboundRtpEnergyDefaults =
      ParticipantLoudnessConfig(
        // 24 samples is ~2.4 s of confirmed speech at 10 Hz but would be 24 s
        // at 1 Hz, which no ordinary utterance survives. Eight keeps the same
        // intent — several seconds of speech before publishing anything.
        minimumSpeechSamples: 8,
        // Each reading already summarises a whole second of decoded audio, so
        // one lost poll is a 2 s gap that is still perfectly usable. The
        // collector also deliberately skips a tick when getStats() is slow.
        maximumSampleGap: Duration(seconds: 6),
        // This source never sees silence: the monitor only feeds it windows
        // the audiolevel estimator already confirmed as pure speech, so it
        // cannot build a noise floor and must not gate on one. Requiring 9 dB
        // above a floor that only ever contains speech is unsatisfiable — the
        // first accepted sample becomes the floor and nothing clears it.
        //
        // The division is deliberate: the visualizer decides WHEN someone is
        // speaking, which is the one thing it is good at, and the energy
        // counters decide HOW LOUD, which is the one thing it is not.
        //
        // Consequence: `estimatedNoiseFloorDb` on this source is not a
        // measurement of the room. Read it from the audiolevel entry instead.
        speechAboveNoiseFloorDb: 0.0,
      );

  /// Where a well-levelled speaker's active speech should sit. Experimental;
  /// the plan's starting window is roughly -20 to -18 dBFS-equivalent.
  final double targetSpeechLevelDb;

  /// Upper clamp on a suggested boost for a quiet participant.
  final double maximumBoostDb;

  /// Lower clamp on a suggested reduction for a loud participant. Negative.
  final double maximumReductionDb;

  /// Speech samples required before a suggestion is offered at all.
  final int minimumSpeechSamples;

  /// Continuous above-threshold time required before a run counts as speech
  /// rather than a transient.
  final Duration minimumSpeechDuration;

  /// How long the estimator holds its speech state after speech stops, so
  /// gaps between phrases do not read as silence.
  final Duration silenceHoldDuration;

  /// Silence tolerated before confidence begins to decay.
  final Duration confidenceHoldDuration;

  /// Silence after [confidenceHoldDuration] over which confidence decays to
  /// zero. The estimate itself is frozen, not reset.
  final Duration confidenceDecayDuration;

  /// Time constant applied when the suggestion moves down (participant is too
  /// loud). Deliberately faster than [releaseDuration].
  final Duration attackDuration;

  /// Time constant applied when the suggestion moves up (participant is too
  /// quiet). Deliberately slow so a boost is never recommended abruptly.
  final Duration releaseDuration;

  /// Time constant for the short-term level follower.
  final Duration shortTermSmoothingDuration;

  /// Time constant for the active-speech level average.
  final Duration speechLevelAveragingDuration;

  /// Time constant used when the noise floor tracks downward.
  final Duration noiseFloorFallDuration;

  /// Time constant used when the noise floor tracks upward. Much slower, so
  /// sustained speech cannot drag the floor up with it.
  final Duration noiseFloorRiseDuration;

  /// Upward time constant used before any speech has been confirmed.
  ///
  /// A cold start that opens on digital silence and then settles into real
  /// room tone would otherwise spend seconds with the floor stuck far too low,
  /// and read that room tone as quiet speech. Tracking up quickly until the
  /// first confirmed speech avoids that without letting a talker drag the
  /// floor along behind them later.
  final Duration noiseFloorWarmupRiseDuration;

  /// How far above the estimated noise floor a sample must sit to be a speech
  /// candidate.
  ///
  /// Zero or negative is a SENTINEL meaning "this source has no usable noise
  /// floor, so do not compare against one at all" - not "require zero
  /// headroom". Requiring zero headroom is unsatisfiable on a source whose
  /// floor is itself built from speech: the floor is raised by the sample
  /// being tested, so `level >= floor` fails on the very next one and speech is
  /// never confirmed. See the derived preset that sets this to `0.0` and the
  /// check in `ParticipantLoudnessEstimator._isSpeechCandidate`.
  ///
  /// A caller passing `0.0` through [copyWith] therefore turns the relative
  /// floor gate off. The absolute floor and the speech hint still apply.
  final double speechAboveNoiseFloorDb;

  /// Absolute floor below which nothing is treated as speech, regardless of
  /// how quiet the noise floor is.
  final double absoluteSpeechFloorDb;

  /// A jump this far above the short-term level that does not survive
  /// [minimumSpeechDuration] is classified as a transient and discarded.
  final double transientJumpDb;

  /// Longest single unbroken "speech" run the estimator will believe.
  ///
  /// Nobody talks this long without their level ever dipping back toward the
  /// room. A run this long is a steady tone — a fan, a hum, an open line — that
  /// happened to start above the floor. When it is exceeded the run is
  /// abandoned and the noise floor is re-seeded from the current level, which
  /// is the escape hatch that stops a bad floor from locking in permanently.
  final Duration maximumContinuousSpeechRun;

  /// Gap between samples beyond which continuity is abandoned and the
  /// estimator resynchronizes instead of integrating across the hole.
  final Duration maximumSampleGap;

  /// Lowest dB value the estimator will represent. Linear zero maps here.
  static const double minimumMeasurableDb = -90.0;

  ParticipantLoudnessConfig copyWith({
    double? targetSpeechLevelDb,
    double? maximumBoostDb,
    double? maximumReductionDb,
    int? minimumSpeechSamples,
    Duration? maximumSampleGap,
    double? speechAboveNoiseFloorDb,
  }) {
    return ParticipantLoudnessConfig(
      targetSpeechLevelDb: targetSpeechLevelDb ?? this.targetSpeechLevelDb,
      maximumBoostDb: maximumBoostDb ?? this.maximumBoostDb,
      maximumReductionDb: maximumReductionDb ?? this.maximumReductionDb,
      minimumSpeechSamples: minimumSpeechSamples ?? this.minimumSpeechSamples,
      minimumSpeechDuration: minimumSpeechDuration,
      silenceHoldDuration: silenceHoldDuration,
      confidenceHoldDuration: confidenceHoldDuration,
      confidenceDecayDuration: confidenceDecayDuration,
      attackDuration: attackDuration,
      releaseDuration: releaseDuration,
      shortTermSmoothingDuration: shortTermSmoothingDuration,
      speechLevelAveragingDuration: speechLevelAveragingDuration,
      noiseFloorFallDuration: noiseFloorFallDuration,
      noiseFloorRiseDuration: noiseFloorRiseDuration,
      noiseFloorWarmupRiseDuration: noiseFloorWarmupRiseDuration,
      speechAboveNoiseFloorDb:
          speechAboveNoiseFloorDb ?? this.speechAboveNoiseFloorDb,
      absoluteSpeechFloorDb: absoluteSpeechFloorDb,
      transientJumpDb: transientJumpDb,
      maximumContinuousSpeechRun: maximumContinuousSpeechRun,
      maximumSampleGap: maximumSampleGap ?? this.maximumSampleGap,
    );
  }

  /// Every tuning constant that can change a report's verdict.
  ///
  /// `ParticipantLoudnessSessionReport` embeds this so a report is
  /// reproducible, which only holds if it is complete: the noise-floor time
  /// constants, [maximumContinuousSpeechRun] and [maximumSampleGap] decide
  /// whether a run counts as speech at all, so omitting them let two reports
  /// from different tuning serialize identically. Add new fields here whenever
  /// one is added to the config.
  Map<String, Object?> toDiagnosticMap() {
    return <String, Object?>{
      'targetSpeechLevelDb': targetSpeechLevelDb,
      'maximumBoostDb': maximumBoostDb,
      'maximumReductionDb': maximumReductionDb,
      'minimumSpeechSamples': minimumSpeechSamples,
      'minimumSpeechDurationMs': minimumSpeechDuration.inMilliseconds,
      'silenceHoldDurationMs': silenceHoldDuration.inMilliseconds,
      'confidenceHoldDurationMs': confidenceHoldDuration.inMilliseconds,
      'confidenceDecayDurationMs': confidenceDecayDuration.inMilliseconds,
      'attackDurationMs': attackDuration.inMilliseconds,
      'releaseDurationMs': releaseDuration.inMilliseconds,
      'shortTermSmoothingDurationMs': shortTermSmoothingDuration.inMilliseconds,
      'speechLevelAveragingDurationMs':
          speechLevelAveragingDuration.inMilliseconds,
      'noiseFloorFallDurationMs': noiseFloorFallDuration.inMilliseconds,
      'noiseFloorRiseDurationMs': noiseFloorRiseDuration.inMilliseconds,
      'noiseFloorWarmupRiseDurationMs':
          noiseFloorWarmupRiseDuration.inMilliseconds,
      'speechAboveNoiseFloorDb': speechAboveNoiseFloorDb,
      'absoluteSpeechFloorDb': absoluteSpeechFloorDb,
      'transientJumpDb': transientJumpDb,
      'maximumContinuousSpeechRunMs': maximumContinuousSpeechRun.inMilliseconds,
      'maximumSampleGapMs': maximumSampleGap.inMilliseconds,
    };
  }
}
