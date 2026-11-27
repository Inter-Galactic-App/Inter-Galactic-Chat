import 'dart:math' as math;

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_config.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_report.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';

/// Per-participant receive-side loudness estimator.
///
/// Measurement only: this class never touches playback. It consumes
/// timestamped level samples and produces a *suggested* automatic gain that a
/// later slice may or may not apply.
///
/// The estimator is deliberately reluctant. It reports no suggestion at all
/// until it has seen enough confirmed speech, it refuses to treat background
/// noise as quiet speech, and it freezes rather than drifting during silence.
/// An absent recommendation is a correct answer; a confident wrong one is not.
///
/// It takes no wall-clock time of its own — every input carries its own
/// timestamp — so unit tests are fully deterministic and need no fake timers.
class ParticipantLoudnessEstimator {
  ParticipantLoudnessEstimator({
    required this.participantKey,
    required String trackKey,
    this.measurementSource =
        ParticipantLoudnessMeasurementSource.streamAudioLevel,
    ParticipantLoudnessConfig config = const ParticipantLoudnessConfig(),
  }) : _config = config,
       _trackKey = trackKey;

  final String participantKey;
  final ParticipantLoudnessMeasurementSource measurementSource;
  final ParticipantLoudnessConfig _config;

  String _trackKey;

  // Automatic measurement state. All of this resets on track replacement.
  int? _lastSampleTimeMs;
  double? _smoothedLevelDb;
  double? _noiseFloorDb;
  double? _speechLevelDb;
  double? _peakDb;
  double? _suggestedGainDb;
  double _rawLevel = 0.0;
  int _sampleCount = 0;
  int _speechSampleCount = 0;
  int? _speechRunStartMs;
  double? _speechRunBaselineDb;
  double? _speechRunPeakDb;
  int? _lastSpeechTimeMs;
  double _peakConfidence = 0.0;
  bool _muted = false;
  ParticipantSpeechState _speechState = ParticipantSpeechState.unknown;

  // Session-summary accumulators. Bounded so a long call cannot grow this
  // without limit.
  int? _firstSampleTimeMs;
  final List<double> _speechLevelHistoryDb = <double>[];
  double? _minSuggestedGainDb;
  double? _maxSuggestedGainDb;

  /// Cap on retained speech-level observations per participant. At the
  /// monitor's default sampling rate this is roughly seven minutes of
  /// continuous speech, after which the oldest observations are dropped.
  static const int maximumSpeechHistorySamples = 4096;

  // Manual override state. Deliberately outside the automatic reset: the user
  // set this, and a track flap must not discard it.
  double _manualOverrideLinear = 1.0;
  bool _hasManualOverride = false;

  // Lifetime counters, also outside the reset — a counter cleared by the event
  // it counts is useless. The first captured sessions reported a plausible
  // -9 dB suggestion and a few hundred speech samples with no way to tell
  // whether that was a steady measurement or the remains of one that had been
  // discarded and rebuilt, so these make that distinction readable.
  double _sessionPeakConfidence = 0.0;
  int _measurementResetCount = 0;
  int _sustainedRunAbandonCount = 0;

  ParticipantLoudnessConfig get config => _config;

  String get trackKey => _trackKey;

  ParticipantLoudnessState get state {
    return ParticipantLoudnessState(
      participantKey: participantKey,
      trackKey: _trackKey,
      measurementSource: measurementSource,
      rawAudioLevel: _rawLevel,
      smoothedLevel: _smoothedLevelDb == null
          ? 0.0
          : ParticipantLoudnessMath.dbToLinear(_smoothedLevelDb!),
      activeSpeechLevelDb: _speechLevelDb,
      peakLevelDb: _peakDb,
      estimatedNoiseFloorDb: _noiseFloorDb,
      speechState: _speechState,
      speechConfidence: _confidenceAt(_lastSampleTimeMs),
      suggestedAutoGainDb: _hasEnoughSpeech ? _suggestedGainDb : null,
      manualOverrideDb: ParticipantLoudnessMath.linearGainToDb(
        _manualOverrideLinear,
      ),
      manualOverrideLinear: _manualOverrideLinear,
      hasManualOverride: _hasManualOverride,
      sampleCount: _sampleCount,
      speechSampleCount: _speechSampleCount,
      muted: _muted,
      lastUpdatedMs: _lastSampleTimeMs,
    );
  }

  bool get _hasEnoughSpeech =>
      _speechLevelDb != null &&
      _speechSampleCount >= _config.minimumSpeechSamples;

  /// Records the existing manual per-user volume override so diagnostics can
  /// show it beside the suggestion. Reading only — this never writes back to
  /// the stream, and it does not influence the estimate.
  void setManualOverride({required double linearVolume, bool? hasOverride}) {
    if (linearVolume.isFinite && linearVolume >= 0.0) {
      _manualOverrideLinear = linearVolume;
    }
    if (hasOverride != null) {
      _hasManualOverride = hasOverride;
    }
  }

  /// A new track arrived for the same participant. Automatic measurement
  /// restarts because the old level history describes a different encoder,
  /// device, or capture chain. The manual override survives.
  void onTrackReplaced(String trackKey) {
    if (trackKey == _trackKey) {
      return;
    }

    _trackKey = trackKey;
    resetMeasurement();
  }

  /// Clears everything the estimator inferred, keeping identity, the manual
  /// override, and the lifetime counters.
  void resetMeasurement() {
    _measurementResetCount++;
    _lastSampleTimeMs = null;
    _smoothedLevelDb = null;
    _noiseFloorDb = null;
    _speechLevelDb = null;
    _peakDb = null;
    _suggestedGainDb = null;
    _rawLevel = 0.0;
    _sampleCount = 0;
    _speechSampleCount = 0;
    _speechRunStartMs = null;
    _speechRunBaselineDb = null;
    _speechRunPeakDb = null;
    _lastSpeechTimeMs = null;
    _peakConfidence = 0.0;
    _muted = false;
    _speechState = ParticipantSpeechState.unknown;
    _firstSampleTimeMs = null;
    _speechLevelHistoryDb.clear();
    _minSuggestedGainDb = null;
    _maxSuggestedGainDb = null;
  }

  /// Feeds one observation and returns the resulting state.
  ParticipantLoudnessState addSample(ParticipantLoudnessSample sample) {
    final previousTimeMs = _lastSampleTimeMs;
    final elapsedMs = previousTimeMs == null
        ? 0
        : math.max(0, sample.timeMs - previousTimeMs);
    // `_smoothedLevelDb == null` is a resynchronize condition in its own right,
    // not a redundant guard: `_lastSampleTimeMs` is advanced below for muted
    // samples too, but `_smoothedLevelDb` is only ever assigned on the unmuted
    // path. A participant who joins muted therefore leaves a non-null previous
    // timestamp with no follower to integrate from, and the next unmuted sample
    // inside `maximumSampleGap` would take the else branch and dereference a
    // null `previousSmoothedDb`.
    final resynchronize =
        previousTimeMs == null ||
        _smoothedLevelDb == null ||
        elapsedMs > _config.maximumSampleGap.inMilliseconds;

    // Adopted unconditionally, including when it moves BACKWARDS. That is what
    // makes a bad timestamp self-limiting: the clock follows the newest sample,
    // so at most one sample is lost before the cadence is measured correctly
    // again. Clamping this to only ever move forward would be the change that
    // introduces a permanent freeze, not one that prevents it.
    _lastSampleTimeMs = sample.timeMs;
    _firstSampleTimeMs ??= sample.timeMs;
    _sampleCount++;
    _rawLevel = sample.clampedLevel;
    _muted = sample.muted;

    if (sample.muted) {
      // A muted participant produces no evidence. Freeze everything rather
      // than letting a floor of silence pull the noise estimate down, which
      // would make the next unmuted breath look like speech.
      _endSpeechRun();
      _speechState = ParticipantSpeechState.silence;
      return state;
    }

    final levelDb = ParticipantLoudnessMath.linearToDb(sample.clampedLevel);
    final previousSmoothedDb = _smoothedLevelDb;

    if (resynchronize) {
      // First sample, or a hole big enough that integrating across it would
      // be fiction. Re-seed the followers instead of interpolating.
      _smoothedLevelDb = levelDb;
      _noiseFloorDb ??= levelDb;
      _endSpeechRun();
    } else {
      _smoothedLevelDb =
          previousSmoothedDb! +
          (levelDb - previousSmoothedDb) *
              ParticipantLoudnessMath.smoothingFactor(
                elapsedMs,
                _config.shortTermSmoothingDuration,
              );
    }

    _peakDb = _peakDb == null ? levelDb : math.max(_peakDb!, levelDb);
    _updateNoiseFloor(levelDb: levelDb, elapsedMs: elapsedMs);

    final isCandidate = _isSpeechCandidate(levelDb: levelDb, sample: sample);
    if (isCandidate) {
      _advanceSpeechRun(
        levelDb: levelDb,
        timeMs: sample.timeMs,
        elapsedMs: elapsedMs,
        baselineDb: previousSmoothedDb ?? levelDb,
      );
    } else {
      _closeSpeechRun(timeMs: sample.timeMs);
    }

    return state;
  }

  void _updateNoiseFloor({required double levelDb, required int elapsedMs}) {
    final current = _noiseFloorDb;
    if (current == null) {
      _noiseFloorDb = levelDb;
      return;
    }

    if (levelDb < current) {
      _noiseFloorDb =
          current +
          (levelDb - current) *
              ParticipantLoudnessMath.smoothingFactor(
                elapsedMs,
                _config.noiseFloorFallDuration,
              );
      return;
    }

    // Never let confirmed speech drag the floor up behind it; that is how an
    // estimator convinces itself a loud talker is a noisy room.
    if (_speechState == ParticipantSpeechState.activeSpeech) {
      return;
    }

    // Before any speech has been confirmed, and while no candidate run is
    // open, settle onto the real room tone quickly. Once a run has started the
    // floor must stop chasing it, or it climbs behind the talker and reads
    // them out of their own speech.
    final warmingUp = _speechLevelDb == null && _speechRunStartMs == null;
    final riseDuration = warmingUp
        ? _config.noiseFloorWarmupRiseDuration
        : _config.noiseFloorRiseDuration;

    _noiseFloorDb =
        current +
        (levelDb - current) *
            ParticipantLoudnessMath.smoothingFactor(elapsedMs, riseDuration);
  }

  bool _isSpeechCandidate({
    required double levelDb,
    required ParticipantLoudnessSample sample,
  }) {
    if (levelDb < _config.absoluteSpeechFloorDb) {
      return false;
    }

    final hint = sample.speechHint;
    if (hint != null && hint.isFinite) {
      // An external speech probability, when one exists, outranks the
      // level heuristic. No current measurement source provides one.
      return hint >= 0.5;
    }

    // A zero threshold means "this source has no usable noise floor", not
    // "require zero headroom above it". The inbound-RTP energy source sets it
    // to 0.0 precisely because its `estimatedNoiseFloorDb` is not a measurement
    // of the room - but `levelDb >= floor + 0.0` still REJECTS anything below a
    // floor `_updateNoiseFloor` just moved, one line before this check. That
    // silently starves `minimumSpeechSamples` on a variable 1 Hz source.
    //
    // The absolute floor and the speech hint above still apply; only the
    // relative comparison is bypassed.
    if (_config.speechAboveNoiseFloorDb <= 0.0) {
      return true;
    }

    final floor = _noiseFloorDb;
    if (floor == null) {
      return false;
    }

    return levelDb >= floor + _config.speechAboveNoiseFloorDb;
  }

  void _advanceSpeechRun({
    required double levelDb,
    required int timeMs,
    required int elapsedMs,
    required double baselineDb,
  }) {
    if (_speechRunStartMs == null) {
      _speechRunStartMs = timeMs;
      _speechRunBaselineDb = baselineDb;
      _speechRunPeakDb = levelDb;
      _speechState = ParticipantSpeechState.possibleSpeech;
      return;
    }

    _speechRunPeakDb = math.max(_speechRunPeakDb ?? levelDb, levelDb);

    final runDurationMs = timeMs - _speechRunStartMs!;
    if (runDurationMs > _config.maximumContinuousSpeechRun.inMilliseconds) {
      _abandonSustainedRunAsNoise(levelDb);
      return;
    }

    if (runDurationMs < _config.minimumSpeechDuration.inMilliseconds) {
      _speechState = ParticipantSpeechState.possibleSpeech;
      return;
    }

    _speechState = ParticipantSpeechState.activeSpeech;
    _speechSampleCount++;
    _lastSpeechTimeMs = timeMs;
    _speechLevelHistoryDb.add(levelDb);
    if (_speechLevelHistoryDb.length > maximumSpeechHistorySamples) {
      // Drop in blocks rather than one per sample: removeAt(0) shifts the whole
      // 4096-element list, and once the cap is reached that would happen on
      // every speech sample for the rest of the call.
      _speechLevelHistoryDb.removeRange(
        0,
        _speechLevelHistoryDb.length - maximumSpeechHistorySamples + 512,
      );
    }

    final currentSpeechDb = _speechLevelDb;
    if (currentSpeechDb == null) {
      _speechLevelDb = levelDb;
    } else {
      _speechLevelDb =
          currentSpeechDb +
          (levelDb - currentSpeechDb) *
              ParticipantLoudnessMath.smoothingFactor(
                elapsedMs,
                _config.speechLevelAveragingDuration,
              );
    }

    _peakConfidence = math.max(
      _peakConfidence,
      math.min(1.0, _speechSampleCount / _config.minimumSpeechSamples),
    );
    _sessionPeakConfidence = math.max(_sessionPeakConfidence, _peakConfidence);

    _updateSuggestedGain(elapsedMs: elapsedMs);
  }

  void _closeSpeechRun({required int timeMs}) {
    final runStart = _speechRunStartMs;
    final runPeak = _speechRunPeakDb;
    final baseline = _speechRunBaselineDb;
    final wasActive = _speechState == ParticipantSpeechState.activeSpeech;

    _endSpeechRun();

    if (!wasActive &&
        runStart != null &&
        runPeak != null &&
        baseline != null &&
        timeMs - runStart < _config.minimumSpeechDuration.inMilliseconds &&
        runPeak - baseline >= _config.transientJumpDb) {
      // A big jump that did not last: a keypress, a click, a notification. It
      // contributed nothing to the speech average and it must not be allowed
      // to depress the recommendation either.
      _speechState = ParticipantSpeechState.transient;
      return;
    }

    _speechState = ParticipantSpeechState.silence;
  }

  /// A "speech" run that never paused for [ParticipantLoudnessConfig.
  /// maximumContinuousSpeechRun] is a steady tone, not a person. Re-seed the
  /// noise floor from it and discard everything it contributed, so a bad floor
  /// cannot lock itself in and keep publishing a recommendation built on it.
  void _abandonSustainedRunAsNoise(double levelDb) {
    _sustainedRunAbandonCount++;
    _endSpeechRun();
    _speechState = ParticipantSpeechState.silence;
    _noiseFloorDb = levelDb;
    _speechLevelDb = null;
    _speechSampleCount = 0;
    _speechLevelHistoryDb.clear();
    _suggestedGainDb = null;
    _minSuggestedGainDb = null;
    _maxSuggestedGainDb = null;
    _peakConfidence = 0.0;
    _lastSpeechTimeMs = null;
  }

  void _endSpeechRun() {
    _speechRunStartMs = null;
    _speechRunBaselineDb = null;
    _speechRunPeakDb = null;
  }

  void _updateSuggestedGain({required int elapsedMs}) {
    final speechDb = _speechLevelDb;
    if (speechDb == null) {
      return;
    }

    final target = (_config.targetSpeechLevelDb - speechDb).clamp(
      _config.maximumReductionDb,
      _config.maximumBoostDb,
    );

    final current = _suggestedGainDb;
    if (current == null) {
      _suggestedGainDb = target.toDouble();
    } else {
      // Moving down means the participant is too loud, which is the unpleasant
      // direction; react faster there than when proposing a boost.
      final timeConstant = target < current
          ? _config.attackDuration
          : _config.releaseDuration;

      _suggestedGainDb =
          current +
          (target - current) *
              ParticipantLoudnessMath.smoothingFactor(elapsedMs, timeConstant);
    }

    if (!_hasEnoughSpeech) {
      // The suggestion is not published yet, so it does not belong in the
      // reported range either.
      return;
    }

    final published = _suggestedGainDb!;
    _minSuggestedGainDb = _minSuggestedGainDb == null
        ? published
        : math.min(_minSuggestedGainDb!, published);
    _maxSuggestedGainDb = _maxSuggestedGainDb == null
        ? published
        : math.max(_maxSuggestedGainDb!, published);
  }

  /// Sanitized summary of everything observed for this participant, for the
  /// exportable measurement-session report.
  ParticipantLoudnessSummary summarize({
    bool presentAtExport = true,
    int mixedWindowRejectCount = 0,
    int silentWindowCount = 0,
  }) {
    final first = _firstSampleTimeMs;
    final last = _lastSampleTimeMs;

    // Percentiles need a distribution. Below the publish threshold there is no
    // distribution, only a handful of points, and _percentile will happily
    // return the single value it was given as all three of p10, p50 and p90 —
    // which is how a live session reported a median of -6.22 with a spread of
    // 0.00 from exactly one sample. A null says "not measured"; a number that
    // looks like a measurement and is not is worse than no answer.
    final sorted = _hasEnoughSpeech
        ? (List<double>.from(_speechLevelHistoryDb)..sort())
        : const <double>[];

    return ParticipantLoudnessSummary(
      participantKey: participantKey,
      trackKey: _trackKey,
      measurementSource: measurementSource,
      medianActiveSpeechLevelDb: _percentile(sorted, 0.5),
      lowActiveSpeechLevelDb: _percentile(sorted, 0.1),
      highActiveSpeechLevelDb: _percentile(sorted, 0.9),
      peakLevelDb: _peakDb,
      estimatedNoiseFloorDb: _noiseFloorDb,
      minimumSuggestedGainDb: _minSuggestedGainDb,
      maximumSuggestedGainDb: _maxSuggestedGainDb,
      finalSuggestedGainDb: _hasEnoughSpeech ? _suggestedGainDb : null,
      manualOverrideDb: ParticipantLoudnessMath.linearGainToDb(
        _manualOverrideLinear,
      ),
      hasManualOverride: _hasManualOverride,
      sampleCount: _sampleCount,
      speechSampleCount: _speechSampleCount,
      // Peak, not the live value. _confidenceAt decays during silence, so a
      // report exported after a talker went quiet recorded 0.0 no matter how
      // well the participant had been measured — which is what every session
      // captured on 2026-07-29/30 shows.
      peakSpeechConfidence: _sessionPeakConfidence,
      msSinceLastSpeech: (last == null || _lastSpeechTimeMs == null)
          ? null
          : math.max(0, last - _lastSpeechTimeMs!),
      measurementResetCount: _measurementResetCount,
      sustainedRunAbandonCount: _sustainedRunAbandonCount,
      measurementDurationMs: (first == null || last == null)
          ? 0
          : math.max(0, last - first),
      presentAtExport: presentAtExport,
      mixedWindowRejectCount: mixedWindowRejectCount,
      silentWindowCount: silentWindowCount,
    );
  }

  static double? _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) {
      return null;
    }
    if (sorted.length == 1) {
      return sorted.first;
    }

    final position = (sorted.length - 1) * fraction;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) {
      return sorted[lower];
    }

    final weight = position - lower;
    return sorted[lower] + (sorted[upper] - sorted[lower]) * weight;
  }

  double _confidenceAt(int? nowMs) {
    if (_peakConfidence <= 0.0) {
      return 0.0;
    }

    final lastSpeech = _lastSpeechTimeMs;
    if (nowMs == null || lastSpeech == null) {
      return _peakConfidence;
    }

    final silenceMs = nowMs - lastSpeech;
    final holdMs = _config.confidenceHoldDuration.inMilliseconds;
    if (silenceMs <= holdMs) {
      return _peakConfidence;
    }

    final decayMs = _config.confidenceDecayDuration.inMilliseconds;
    if (decayMs <= 0) {
      return 0.0;
    }

    final remaining = 1.0 - ((silenceMs - holdMs) / decayMs);
    return (_peakConfidence * remaining.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }
}
