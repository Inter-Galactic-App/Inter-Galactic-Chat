import 'dart:math' as math;

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_config.dart';

/// Where a measured level came from. Recorded on every state snapshot so a
/// diagnostic reader never has to guess which signal produced a number.
enum ParticipantLoudnessMeasurementSource {
  /// `VoipStream.audiolevel`, which on LiveKit is fed by the native audio
  /// visualizer and on direct Matrix calls by a thresholded WebRTC stat.
  ///
  /// Rejected as a leveling source on live evidence — it is display-normalised
  /// and reports a ceiling rather than a level. Retained so the two sources can
  /// be compared on the same call.
  streamAudioLevel,

  /// RMS amplitude derived from the transport's own `inbound-rtp`
  /// `totalAudioEnergy` / `totalSamplesDuration` counters. A real WebRTC
  /// statistic, upstream of local playback gain, on a documented scale.
  inboundRtpEnergy,

  /// A decoded PCM tap. Not implemented; reserved so diagnostics and reports
  /// do not need a schema change when it lands.
  decodedPcm,

  /// Deterministic samples fed by a test or replay harness.
  syntheticSamples,
}

extension ParticipantLoudnessMeasurementSourceLabel
    on ParticipantLoudnessMeasurementSource {
  /// Serialization order for reports. Declared explicitly rather than taken
  /// from `index`, so inserting a value into the enum (the reserved
  /// [ParticipantLoudnessMeasurementSource.decodedPcm] slot invites exactly
  /// that) cannot silently reorder an exported report's `measurementSources`.
  /// The switch is exhaustive, so a new source is a compile error here rather
  /// than an unnoticed ordering change.
  int get sortRank {
    switch (this) {
      case ParticipantLoudnessMeasurementSource.streamAudioLevel:
        return 0;
      case ParticipantLoudnessMeasurementSource.inboundRtpEnergy:
        return 1;
      case ParticipantLoudnessMeasurementSource.decodedPcm:
        return 2;
      case ParticipantLoudnessMeasurementSource.syntheticSamples:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case ParticipantLoudnessMeasurementSource.streamAudioLevel:
        return 'stream-audio-level';
      case ParticipantLoudnessMeasurementSource.inboundRtpEnergy:
        return 'inbound-rtp-energy';
      case ParticipantLoudnessMeasurementSource.decodedPcm:
        return 'decoded-pcm';
      case ParticipantLoudnessMeasurementSource.syntheticSamples:
        return 'synthetic';
    }
  }
}

/// Conservative speech classification. Anything the estimator is not sure
/// about stays [unknown] or [possibleSpeech] and does not feed the speech
/// level average.
enum ParticipantSpeechState {
  unknown,
  silence,
  possibleSpeech,
  activeSpeech,
  transient,
}

extension ParticipantSpeechStateLabel on ParticipantSpeechState {
  String get label {
    switch (this) {
      case ParticipantSpeechState.unknown:
        return 'unknown';
      case ParticipantSpeechState.silence:
        return 'silence';
      case ParticipantSpeechState.possibleSpeech:
        return 'possible';
      case ParticipantSpeechState.activeSpeech:
        return 'active';
      case ParticipantSpeechState.transient:
        return 'transient';
    }
  }
}

/// One timestamped level observation for a single remote participant.
///
/// [level] is linear amplitude in 0.0..1.0. The estimator never takes wall
/// clock time itself; [timeMs] is supplied by the caller so unit tests are
/// fully deterministic.
class ParticipantLoudnessSample {
  const ParticipantLoudnessSample({
    required this.timeMs,
    required this.level,
    this.muted = false,
    this.speechHint,
  });

  final int timeMs;
  final double level;
  final bool muted;

  /// Optional external speech probability in 0.0..1.0. No current measurement
  /// source provides one; the estimator uses it only when present.
  final double? speechHint;

  double get clampedLevel => level.isFinite ? level.clamp(0.0, 1.0) : 0.0;
}

/// Converts between the linear amplitude used by playback volume and the dB
/// domain the estimator reasons in.
class ParticipantLoudnessMath {
  const ParticipantLoudnessMath._();

  static const double _log10 = 2.302585092994046;

  /// Linear amplitude (0.0..1.0+) to dBFS-equivalent, floored at
  /// [ParticipantLoudnessConfig.minimumMeasurableDb].
  static double linearToDb(double linear) {
    if (!linear.isFinite || linear <= 0.0) {
      return ParticipantLoudnessConfig.minimumMeasurableDb;
    }

    final db = 20.0 * (math.log(linear) / _log10);
    if (!db.isFinite || db < ParticipantLoudnessConfig.minimumMeasurableDb) {
      return ParticipantLoudnessConfig.minimumMeasurableDb;
    }

    return db;
  }

  /// dB back to a linear multiplier. Used to show the manual override and the
  /// suggestion in the same units.
  static double dbToLinear(double db) {
    if (!db.isFinite) {
      return 0.0;
    }

    return math.exp(db / 20.0 * _log10);
  }

  /// The manual per-user override is stored as a linear multiplier where 1.0
  /// is unchanged; express it in dB so it can be added to a suggestion.
  static double linearGainToDb(double linearGain) {
    if (!linearGain.isFinite || linearGain <= 0.0) {
      return ParticipantLoudnessConfig.minimumMeasurableDb;
    }

    return 20.0 * (math.log(linearGain) / _log10);
  }

  /// One-pole smoothing coefficient for an elapsed time and a time constant.
  ///
  /// A non-positive time constant means "no smoothing", so the value jumps
  /// straight to the target. Zero elapsed time means nothing has moved yet, so
  /// the value must not change — two samples sharing a timestamp cannot be
  /// allowed to advance the filter.
  static double smoothingFactor(int elapsedMs, Duration timeConstant) {
    final tau = timeConstant.inMilliseconds;
    if (tau <= 0) {
      return 1.0;
    }
    if (elapsedMs <= 0) {
      return 0.0;
    }

    final factor = 1.0 - math.exp(-elapsedMs / tau);
    return factor.clamp(0.0, 1.0);
  }
}

/// Immutable snapshot of one participant's measurement state.
///
/// Identity is carried as opaque keys only. Callers hash raw Matrix user ids
/// and WebRTC track ids before they ever reach this class, so a snapshot can
/// be logged or exported without a redaction step.
class ParticipantLoudnessState {
  const ParticipantLoudnessState({
    required this.participantKey,
    required this.trackKey,
    required this.measurementSource,
    required this.rawAudioLevel,
    required this.smoothedLevel,
    required this.activeSpeechLevelDb,
    required this.peakLevelDb,
    required this.estimatedNoiseFloorDb,
    required this.speechState,
    required this.speechConfidence,
    required this.suggestedAutoGainDb,
    required this.manualOverrideDb,
    required this.manualOverrideLinear,
    required this.hasManualOverride,
    required this.sampleCount,
    required this.speechSampleCount,
    required this.muted,
    required this.lastUpdatedMs,
  });

  factory ParticipantLoudnessState.initial({
    required String participantKey,
    required String trackKey,
    required ParticipantLoudnessMeasurementSource measurementSource,
  }) {
    return ParticipantLoudnessState(
      participantKey: participantKey,
      trackKey: trackKey,
      measurementSource: measurementSource,
      rawAudioLevel: 0.0,
      smoothedLevel: 0.0,
      activeSpeechLevelDb: null,
      peakLevelDb: null,
      estimatedNoiseFloorDb: null,
      speechState: ParticipantSpeechState.unknown,
      speechConfidence: 0.0,
      suggestedAutoGainDb: null,
      manualOverrideDb: 0.0,
      manualOverrideLinear: 1.0,
      hasManualOverride: false,
      sampleCount: 0,
      speechSampleCount: 0,
      muted: false,
      lastUpdatedMs: null,
    );
  }

  final String participantKey;
  final String trackKey;
  final ParticipantLoudnessMeasurementSource measurementSource;

  /// Most recent linear level as delivered by the measurement source.
  final double rawAudioLevel;

  /// Short-term smoothed linear level.
  final double smoothedLevel;

  /// Averaged level of confirmed active speech. Null until enough speech has
  /// been observed to mean anything.
  final double? activeSpeechLevelDb;

  final double? peakLevelDb;
  final double? estimatedNoiseFloorDb;
  final ParticipantSpeechState speechState;

  /// 0.0..1.0. Rises with observed speech, decays over long silence.
  final double speechConfidence;

  /// Recommended automatic gain. Null while the estimator has insufficient
  /// evidence — the caller must render "none", not zero.
  final double? suggestedAutoGainDb;

  /// The existing manual per-user volume override, in dB. Read-only here.
  final double manualOverrideDb;

  /// The same override as the linear multiplier actually stored by the app.
  final double manualOverrideLinear;

  final bool hasManualOverride;
  final int sampleCount;
  final int speechSampleCount;
  final bool muted;
  final int? lastUpdatedMs;

  double get smoothedLevelDb =>
      ParticipantLoudnessMath.linearToDb(smoothedLevel);

  double get rawAudioLevelDb =>
      ParticipantLoudnessMath.linearToDb(rawAudioLevel);

  bool get hasSuggestion => suggestedAutoGainDb != null;

  /// What the combined adjustment would be if a later slice actually applied
  /// the suggestion ahead of the manual override. Nothing applies it today.
  double? get futureCombinedGainDb {
    final suggestion = suggestedAutoGainDb;
    if (suggestion == null) {
      return null;
    }

    return suggestion + manualOverrideDb;
  }

  int? estimatorAgeMs(int nowMs) {
    final updated = lastUpdatedMs;
    if (updated == null) {
      return null;
    }

    return math.max(0, nowMs - updated);
  }

  ParticipantLoudnessState copyWith({
    double? rawAudioLevel,
    double? smoothedLevel,
    double? activeSpeechLevelDb,
    bool clearActiveSpeechLevel = false,
    double? peakLevelDb,
    double? estimatedNoiseFloorDb,
    ParticipantSpeechState? speechState,
    double? speechConfidence,
    double? suggestedAutoGainDb,
    bool clearSuggestedAutoGain = false,
    double? manualOverrideDb,
    double? manualOverrideLinear,
    bool? hasManualOverride,
    int? sampleCount,
    int? speechSampleCount,
    bool? muted,
    int? lastUpdatedMs,
    String? trackKey,
  }) {
    return ParticipantLoudnessState(
      participantKey: participantKey,
      trackKey: trackKey ?? this.trackKey,
      measurementSource: measurementSource,
      rawAudioLevel: rawAudioLevel ?? this.rawAudioLevel,
      smoothedLevel: smoothedLevel ?? this.smoothedLevel,
      activeSpeechLevelDb: clearActiveSpeechLevel
          ? null
          : (activeSpeechLevelDb ?? this.activeSpeechLevelDb),
      peakLevelDb: peakLevelDb ?? this.peakLevelDb,
      estimatedNoiseFloorDb:
          estimatedNoiseFloorDb ?? this.estimatedNoiseFloorDb,
      speechState: speechState ?? this.speechState,
      speechConfidence: speechConfidence ?? this.speechConfidence,
      suggestedAutoGainDb: clearSuggestedAutoGain
          ? null
          : (suggestedAutoGainDb ?? this.suggestedAutoGainDb),
      manualOverrideDb: manualOverrideDb ?? this.manualOverrideDb,
      manualOverrideLinear: manualOverrideLinear ?? this.manualOverrideLinear,
      hasManualOverride: hasManualOverride ?? this.hasManualOverride,
      sampleCount: sampleCount ?? this.sampleCount,
      speechSampleCount: speechSampleCount ?? this.speechSampleCount,
      muted: muted ?? this.muted,
      lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
    );
  }

  /// Sanitized map for structured runtime diagnostics. Contains no raw ids.
  Map<String, Object?> toDiagnosticMap({int? nowMs}) {
    return <String, Object?>{
      'participantHash': participantKey,
      'trackHash': trackKey,
      'measurementSource': measurementSource.label,
      'rawAudioLevel': _round(rawAudioLevel, 4),
      'smoothedAudioLevel': _round(smoothedLevel, 4),
      'activeSpeechLevelDb': _round(activeSpeechLevelDb, 2),
      'peakLevelDb': _round(peakLevelDb, 2),
      'estimatedNoiseFloorDb': _round(estimatedNoiseFloorDb, 2),
      'speechState': speechState.label,
      'speechConfidence': _round(speechConfidence, 3),
      'suggestedAutoGainDb': _round(suggestedAutoGainDb, 2),
      'manualOverrideDb': _round(manualOverrideDb, 2),
      'futureCombinedGainDb': _round(futureCombinedGainDb, 2),
      'sampleCount': sampleCount,
      'speechSampleCount': speechSampleCount,
      'muted': muted,
      if (nowMs != null) 'estimatorAgeMs': estimatorAgeMs(nowMs),
    };
  }

  static double? _round(double? value, int places) {
    if (value == null || !value.isFinite) {
      return null;
    }

    final factor = math.pow(10, places);
    return (value * factor).roundToDouble() / factor;
  }
}
