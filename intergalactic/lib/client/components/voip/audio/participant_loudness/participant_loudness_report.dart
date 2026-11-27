import 'dart:math' as math;

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_config.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';

/// Per-participant summary statistics for an exported measurement session.
///
/// Everything here is derived. It carries hashed keys only, never raw Matrix
/// ids, room names, or audio.
class ParticipantLoudnessSummary {
  const ParticipantLoudnessSummary({
    required this.participantKey,
    required this.trackKey,
    required this.measurementSource,
    required this.medianActiveSpeechLevelDb,
    required this.lowActiveSpeechLevelDb,
    required this.highActiveSpeechLevelDb,
    required this.peakLevelDb,
    required this.estimatedNoiseFloorDb,
    required this.minimumSuggestedGainDb,
    required this.maximumSuggestedGainDb,
    required this.finalSuggestedGainDb,
    required this.manualOverrideDb,
    required this.hasManualOverride,
    required this.sampleCount,
    required this.speechSampleCount,
    required this.peakSpeechConfidence,
    required this.msSinceLastSpeech,
    required this.measurementResetCount,
    required this.sustainedRunAbandonCount,
    required this.measurementDurationMs,
    this.presentAtExport = true,
    this.mixedWindowRejectCount = 0,
    this.silentWindowCount = 0,
  });

  final String participantKey;
  final String trackKey;
  final ParticipantLoudnessMeasurementSource measurementSource;

  /// 50th percentile of confirmed active-speech levels.
  final double? medianActiveSpeechLevelDb;

  /// 10th percentile — how quiet this participant's quiet speech gets.
  final double? lowActiveSpeechLevelDb;

  /// 90th percentile — how loud their loud speech gets. The spread between
  /// low and high is what decides whether one static gain can work at all.
  final double? highActiveSpeechLevelDb;

  final double? peakLevelDb;
  final double? estimatedNoiseFloorDb;
  final double? minimumSuggestedGainDb;
  final double? maximumSuggestedGainDb;
  final double? finalSuggestedGainDb;
  final double manualOverrideDb;
  final bool hasManualOverride;
  final int sampleCount;
  final int speechSampleCount;

  /// Highest confidence reached during the session, not the value at export.
  /// The live figure decays during silence, so exporting after a talker went
  /// quiet reported 0.0 for a participant that had been measured perfectly
  /// well.
  final double peakSpeechConfidence;

  /// How long before the last sample this participant last spoke. Reads the
  /// summary's freshness: a large value means the numbers above describe
  /// something that stopped happening a while ago.
  final int? msSinceLastSpeech;

  /// How many times measurement restarted (track replacement, explicit reset).
  final int measurementResetCount;

  /// How many times a speech run was discarded for exceeding
  /// [ParticipantLoudnessConfig.maximumContinuousSpeechRun]. Non-zero means
  /// the counters above were wiped mid-session and describe only what was
  /// accumulated since — the difference between "this person barely spoke" and
  /// "the estimator threw the evidence away".
  final int sustainedRunAbandonCount;

  final int measurementDurationMs;

  /// False for a participant who left before the report was exported. Their
  /// measurement is retained rather than dropped, so a session report covers
  /// the session rather than whoever happened to still be in the call.
  final bool presentAtExport;

  /// Energy windows discarded because they contained silence as well as
  /// speech. Only meaningful for `inbound-rtp-energy`, and always 0 for
  /// `stream-audio-level`, whose samples are instantaneous rather than
  /// window-averaged.
  ///
  /// Read this beside [speechSampleCount]: a participant with few accepted
  /// samples and many rejects spoke in short bursts, which is a different
  /// situation from one who barely spoke at all.
  final int mixedWindowRejectCount;

  /// Energy windows discarded for containing no speech at all — seconds of the
  /// call in which this participant simply was not talking.
  ///
  /// Kept separate from [mixedWindowRejectCount] because most seconds of most
  /// calls are this, and folding them together made a correctly-working gate
  /// look pathological. Only [mixedWindowRejectCount] says anything about
  /// whether the gate is too strict.
  final int silentWindowCount;

  /// Spread between the loud and quiet ends of this participant's speech. A
  /// wide spread means a single suggested gain will not serve both ends.
  double? get activeSpeechSpreadDb {
    final low = lowActiveSpeechLevelDb;
    final high = highActiveSpeechLevelDb;
    if (low == null || high == null) {
      return null;
    }

    return high - low;
  }

  /// Distance between speech and the room behind it. Below roughly 10 dB the
  /// level signal cannot separate quiet speech from noise.
  double? get speechToNoiseFloorDb {
    final speech = medianActiveSpeechLevelDb;
    final floor = estimatedNoiseFloorDb;
    if (speech == null || floor == null) {
      return null;
    }

    return speech - floor;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'participantHash': participantKey,
      'trackHash': trackKey,
      'measurementSource': measurementSource.label,
      'medianActiveSpeechLevelDb': _round(medianActiveSpeechLevelDb),
      'lowActiveSpeechLevelDb': _round(lowActiveSpeechLevelDb),
      'highActiveSpeechLevelDb': _round(highActiveSpeechLevelDb),
      'activeSpeechSpreadDb': _round(activeSpeechSpreadDb),
      'speechToNoiseFloorDb': _round(speechToNoiseFloorDb),
      'peakLevelDb': _round(peakLevelDb),
      'estimatedNoiseFloorDb': _round(estimatedNoiseFloorDb),
      'minimumSuggestedGainDb': _round(minimumSuggestedGainDb),
      'maximumSuggestedGainDb': _round(maximumSuggestedGainDb),
      'finalSuggestedGainDb': _round(finalSuggestedGainDb),
      'manualOverrideDb': _round(manualOverrideDb),
      'hasManualOverride': hasManualOverride,
      'sampleCount': sampleCount,
      'speechSampleCount': speechSampleCount,
      'peakSpeechConfidence': _round(peakSpeechConfidence, 3),
      'msSinceLastSpeech': msSinceLastSpeech,
      'measurementResetCount': measurementResetCount,
      'sustainedRunAbandonCount': sustainedRunAbandonCount,
      'measurementDurationMs': measurementDurationMs,
      'presentAtExport': presentAtExport,
      'mixedWindowRejectCount': mixedWindowRejectCount,
      'silentWindowCount': silentWindowCount,
    };
  }

  static double? _round(double? value, [int places = 2]) {
    if (value == null || !value.isFinite) {
      return null;
    }

    final factor = math.pow(10, places);
    return (value * factor).roundToDouble() / factor;
  }
}

/// A complete, sanitized measurement session ready to be written to disk.
///
/// This is the artifact the "is LiveKit audioLevel good enough?" decision is
/// supposed to be made from, so it deliberately records the estimator
/// configuration alongside the numbers it produced.
class ParticipantLoudnessSessionReport {
  ParticipantLoudnessSessionReport({
    required DateTime generatedAtUtc,
    required this.measurementSource,
    required this.config,
    required this.participants,
    this.sessionDurationMs = 0,
    this.notes = const <String>[],
  }) : // Normalized rather than trusted. Dart only appends the Z suffix for a
       // UTC value, so a caller passing DateTime.now() would write a local
       // timestamp under a key named generatedAtUtc - and the file name would
       // inherit the same ambiguity, silently mixing zones when reports from
       // two machines are compared.
       generatedAtUtc = generatedAtUtc.toUtc();

  /// 2: `speechConfidence` became `peakSpeechConfidence` (the v1 field decayed
  /// to 0.0 during silence, so exported sessions understated it); added
  /// `msSinceLastSpeech`, `measurementResetCount`, `sustainedRunAbandonCount`
  /// and `measuredStreamCount`; `measuredParticipantCount` now counts distinct
  /// people rather than entries, which differ when someone joins twice.
  ///
  /// 3: two measurement sources now run concurrently, so a track can appear
  /// twice — once per source, distinguished by each entry's
  /// `measurementSource`. Added `measurementCount` and `measurementSources`;
  /// `measuredStreamCount` counts distinct tracks rather than entries. The
  /// top-level `measurementSource` is retained for readers of v1/v2 and names
  /// the first source only; read `measurementSources` instead.
  static const int schemaVersion = 3;

  final DateTime generatedAtUtc;
  final ParticipantLoudnessMeasurementSource measurementSource;
  final ParticipantLoudnessConfig config;
  final List<ParticipantLoudnessSummary> participants;
  final int sessionDurationMs;
  final List<String> notes;

  /// Distinct measured tracks - `participantKey:trackKey` pairs, not entries.
  /// A participant on two devices contributes two, however many sources
  /// measured each of those tracks. [measurementCount] is the entry count.
  int get measuredStreamCount => participants
      .map((p) => '${p.participantKey}:${p.trackKey}')
      .toSet()
      .length;

  /// One per track per measurement source. Two sources measure each track
  /// concurrently, so this exceeds [measuredStreamCount] whenever the
  /// inbound-rtp collector is running.
  int get measurementCount => participants.length;

  /// Every source that produced at least one entry in this report.
  List<ParticipantLoudnessMeasurementSource> get measurementSources =>
      participants.map((p) => p.measurementSource).toSet().toList()
        ..sort((a, b) => a.sortRank.compareTo(b.sortRank));

  /// Distinct people measured, however many devices each published from.
  int get measuredParticipantCount =>
      participants.map((p) => p.participantKey).toSet().length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'type': 'participant_loudness_measurement_session',
      'generatedAtUtc': generatedAtUtc.toIso8601String(),
      'measurementSource': measurementSource.label,
      'playbackModified': false,
      'sessionDurationMs': sessionDurationMs,
      'measuredParticipantCount': measuredParticipantCount,
      'measuredStreamCount': measuredStreamCount,
      'measurementCount': measurementCount,
      'measurementSources': [
        for (final source in measurementSources) source.label,
      ],
      'estimatorConfig': config.toDiagnosticMap(),
      'participants': [
        for (final participant in participants) participant.toJson(),
      ],
      'notes': notes,
    };
  }

  /// File name for this report. Colons are stripped so the name is valid on
  /// Windows.
  String get suggestedFileName {
    final timestamp = generatedAtUtc
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'participant-loudness-$timestamp.json';
  }
}
