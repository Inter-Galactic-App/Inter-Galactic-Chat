import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_config.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_estimator.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_report.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_report_writer.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';
import 'package:intergalactic/client/components/voip/voip_inbound_audio_energy.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Receiver-side participant loudness measurement.
///
/// Polls each subscribed remote microphone stream, feeds an independent
/// [ParticipantLoudnessEstimator] per participant, and publishes suggested
/// automatic gains for diagnostics.
///
/// **This never changes playback.** It reads levels and the existing manual
/// per-user volume override; it writes nothing back to any stream. The whole
/// system is gated behind a development flag and is inert when that flag is
/// off.
class ParticipantLoudnessMonitor {
  ParticipantLoudnessMonitor({
    ParticipantLoudnessConfig config = const ParticipantLoudnessConfig(),
    Duration samplingInterval = const Duration(milliseconds: 100),
    Duration diagnosticLogInterval = const Duration(seconds: 15),
    Duration followReconcileInterval = _defaultFollowReconcileInterval,
    bool Function()? isEnabled,
    int Function()? clockMs,
  }) : _config = config,
       _followReconcileInterval = followReconcileInterval,
       _samplingInterval = samplingInterval,
       _diagnosticLogIntervalMs = diagnosticLogInterval.inMilliseconds,
       _isEnabled =
           isEnabled ??
           (() => preferences.voipRemoteParticipantLoudnessMeasurement.value),
       _clockMs = clockMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static final ParticipantLoudnessMonitor instance =
      ParticipantLoudnessMonitor();

  final ParticipantLoudnessConfig _config;

  /// The same tuning retimed for the 1 Hz inbound-rtp cadence. Derived from
  /// [_config] so an injected test config still governs both sources.
  late final ParticipantLoudnessConfig _energyConfig = _config.copyWith(
    minimumSpeechSamples:
        ParticipantLoudnessConfig.inboundRtpEnergyDefaults.minimumSpeechSamples,
    maximumSampleGap:
        ParticipantLoudnessConfig.inboundRtpEnergyDefaults.maximumSampleGap,
    speechAboveNoiseFloorDb: ParticipantLoudnessConfig
        .inboundRtpEnergyDefaults
        .speechAboveNoiseFloorDb,
  );
  final Duration _samplingInterval;
  final int _diagnosticLogIntervalMs;
  final bool Function() _isEnabled;
  final int Function() _clockMs;

  final Map<String, ParticipantLoudnessEstimator> _estimators =
      <String, ParticipantLoudnessEstimator>{};

  /// Measurements for streams that have gone away, kept so an exported report
  /// describes the session rather than whoever is still in the call at the
  /// moment the button is pressed. Bounded — a long call with heavy join/leave
  /// churn must not grow this without limit.
  final Map<String, ParticipantLoudnessSummary> _departedSummaries =
      <String, ParticipantLoudnessSummary>{};

  static const int maximumRetainedDepartedSummaries = 64;

  /// How often [followSession] re-checks whether it should be measuring. Slow:
  /// it only has to notice a call connecting, ending, or the preference being
  /// toggled.
  static const Duration _defaultFollowReconcileInterval = Duration(seconds: 1);

  final Duration _followReconcileInterval;

  /// Last inbound-rtp reading consumed per energy estimator key. The
  /// measurement is a ratio between consecutive readings, so the previous one
  /// has to survive between passes.
  final Map<String, VoipInboundAudioEnergySample> _lastEnergySamples =
      <String, VoipInboundAudioEnergySample>{};

  /// Whether every pass since the last reading saw confirmed speech. A window
  /// containing any silence measures speech-plus-pause, not speech.
  final Map<String, bool> _energyWindowIsPureSpeech = <String, bool>{};

  /// Windows discarded for containing silence, per energy estimator key.
  final Map<String, int> _energyMixedWindowRejects = <String, int>{};

  /// Whether any pass since the last reading saw confirmed speech. Separates a
  /// window that mixed speech with silence from one that was simply silence.
  final Map<String, bool> _energyWindowHadSpeech = <String, bool>{};

  /// Windows discarded for containing no speech at all, per energy key.
  final Map<String, int> _energySilentWindows = <String, int>{};

  final StreamController<void> _onChanged = StreamController<void>.broadcast();

  VoipSession? _session;
  VoipSession? _followedSession;
  Timer? _followTimer;
  StreamSubscription<void>? _sessionSubscription;
  Timer? _samplingTimer;
  int? _sessionStartedMs;
  int? _lastDiagnosticLogMs;
  bool _disposed = false;

  ParticipantLoudnessConfig get config => _config;

  /// Fires after each sampling pass that changed anything observable.
  Stream<void> get onChanged => _onChanged.stream;

  bool get isEnabled => _isEnabled();

  bool get isAttached => _session != null;

  /// Number of measured audio streams. A participant publishing from two
  /// devices contributes two, which is why this is not the participant count.
  ///
  /// Counts distinct tracks, not estimators: two sources measure each track
  /// concurrently, so `_estimators.length` is a count of measurements.
  int get measuredStreamCount => _estimators.values
      .map((e) => '${e.participantKey}:${e.trackKey}')
      .toSet()
      .length;

  /// Number of running estimators — one per track per measurement source.
  int get measurementCount => _estimators.length;

  /// Number of distinct people being measured, regardless of how many devices
  /// each is publishing from.
  int get measuredParticipantCount =>
      _estimators.values.map((e) => e.participantKey).toSet().length;

  /// Current snapshots, ordered by participant key so a diagnostic table does
  /// not reshuffle between frames.
  List<ParticipantLoudnessState> get states {
    final keys = _estimators.keys.toList()..sort();
    return [for (final key in keys) _estimators[key]!.state];
  }

  /// Follows a call for its entire life, independent of any UI.
  ///
  /// Measurement used to begin only when the developer diagnostics view was
  /// built and end when it was disposed, so a four-hour call produced under
  /// two minutes of data — however long someone happened to be looking at the
  /// settings page. The measurement is the product here; a view that displays
  /// it is not what should decide whether it runs.
  ///
  /// Reconciles on a slow timer rather than once, so the preference can be
  /// turned on part-way through a call — which is exactly how someone reaches
  /// for a diagnostic — without having to rejoin.
  void followSession(VoipSession session) {
    if (_disposed) {
      return;
    }

    // Detach from the previous call before adopting the new one. Reconciliation
    // only attaches once the new session reaches `connected`, so following a
    // second call while the first is still attached left the sampling timer
    // running against the OLD session for the whole connect window - the
    // diagnostics view reported the call the user had already left. `attach`
    // clears the estimators, so no stale measurement survives into the new
    // report, but the window itself measured the wrong call.
    if (!identical(_followedSession, session) && isAttached) {
      detach();
    }

    _followedSession = session;
    _followTimer ??= Timer.periodic(
      _followReconcileInterval,
      (_) => _reconcileFollowedSession(),
    );
    _reconcileFollowedSession();
  }

  /// Stops following whatever call is current and tears down measurement.
  void unfollow() {
    _followTimer?.cancel();
    _followTimer = null;
    _followedSession = null;
    detach();
  }

  /// Public so tests can drive the follow lifecycle without a real timer.
  @visibleForTesting
  void reconcileFollowedSession() => _reconcileFollowedSession();

  void _reconcileFollowedSession() {
    final session = _followedSession;
    if (session == null || _disposed) {
      return;
    }

    if (session.state.isFinishing) {
      unfollow();
      return;
    }

    if (!isEnabled) {
      if (isAttached) {
        detach();
      }
      return;
    }

    if (session.state == VoipState.connected) {
      // attach() is a no-op for a session already attached.
      attach(session);
    }
  }

  /// Attaches to a live call. Safe to call repeatedly; a second attach to the
  /// same session is a no-op, and attaching to a different session tears the
  /// previous one down first so reconnects cannot leak listeners.
  void attach(VoipSession session) {
    if (_disposed || identical(_session, session)) {
      return;
    }

    detach();

    if (!isEnabled) {
      // The flag gates estimator creation itself, not just visibility.
      return;
    }

    _session = session;
    _sessionStartedMs = _clockMs();
    _sessionSubscription = session.onStateChanged.listen((_) {
      if (session.state.isFinishing) {
        detach();
      }
    });
    _samplingTimer = Timer.periodic(_samplingInterval, (_) => sampleOnce());

    Log.i(
      'Participant loudness measurement attached: '
      'interval=${_samplingInterval.inMilliseconds}ms '
      'target=${_config.targetSpeechLevelDb}dB (measurement only)',
      category: LogCategory.livekit,
      source: 'participant-loudness',
    );
  }

  /// Stops measuring and clears all estimator state.
  void detach() {
    _samplingTimer?.cancel();
    _samplingTimer = null;
    unawaited(_cancelSessionSubscription());
    _sessionSubscription = null;
    _session = null;
    _sessionStartedMs = null;
    _lastDiagnosticLogMs = null;

    // A new call starts from nothing: the previous session's departed
    // participants must not leak into the next session's report.
    final hadState = _estimators.isNotEmpty || _departedSummaries.isNotEmpty;
    _estimators.clear();
    _departedSummaries.clear();
    // Cumulative counters from the previous call cannot be differenced against
    // the next one's — a new receiver starts from zero, so a stale baseline
    // would produce a negative delta at best and a fabricated level at worst.
    _lastEnergySamples.clear();
    _energyWindowIsPureSpeech.clear();
    _energyMixedWindowRejects.clear();
    _energyWindowHadSpeech.clear();
    _energySilentWindows.clear();
    if (hadState) {
      _notifyChanged();
    }
  }

  Future<void> _cancelSessionSubscription() async {
    try {
      await _sessionSubscription?.cancel();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered participant loudness session unsubscribe failure',
        category: LogCategory.livekit,
        source: 'participant-loudness',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _followTimer?.cancel();
    _followTimer = null;
    _followedSession = null;
    detach();
    await _onChanged.close();
  }

  /// Runs a single measurement pass. Public so tests can drive the monitor
  /// deterministically without a real timer.
  @visibleForTesting
  void sampleOnce() {
    final session = _session;
    if (session == null || _disposed) {
      return;
    }

    if (!isEnabled) {
      detach();
      return;
    }

    final nowMs = _clockMs();
    final seenKeys = <String>{};

    for (final stream in session.streams) {
      if (!_isMeasurableStream(stream)) {
        continue;
      }

      final participantKey = participantKeyFor(stream.streamUserId);
      final trackKey = trackKeyFor(stream.streamId);
      final estimatorKey = estimatorKeyFor(
        participantKey: participantKey,
        trackKey: trackKey,
        source: ParticipantLoudnessMeasurementSource.streamAudioLevel,
      );
      seenKeys.add(estimatorKey);

      final estimator = _estimators.putIfAbsent(estimatorKey, () {
        // Leave then rejoin inside one call: the retained snapshot for this key
        // is SUPERSEDED by the estimator about to start measuring, not a second
        // entry beside it. Without this, buildReport emits the same
        // participant:track twice - once presentAtExport:false with the old
        // measurement, once live - which contradicts the report's own "one
        // entry per participant per track" note and inflates
        // measuredStreamCount.
        //
        // KNOWN LIMITATION (routed to AUDIO): the pre-rejoin samples are lost,
        // not merged, so a participant who leaves after 50 samples and rejoins
        // for 10 reports 10. Merging is deliberately NOT attempted here.
        // ParticipantLoudnessSummary carries percentiles - median, low and high
        // active speech level are p50/p10/p90 - and percentiles cannot be
        // recombined from two summaries without the underlying distributions,
        // which the departed estimator no longer has. Any weighted-average
        // stand-in would emit numbers that look authoritative and are not,
        // which is worse than a short measurement in a tool whose only job is
        // accurate measurement. The real fix is to retain the departed
        // ESTIMATOR (its speech-level history) rather than its summary, and
        // resume into it - an AUDIO call, because it trades memory for history
        // depth and changes what a "session" means across rejoins.
        _departedSummaries.remove(estimatorKey);
        Log.i(
          'Participant loudness estimator created: '
          'participant=$participantKey track=$trackKey',
          category: LogCategory.livekit,
          source: 'participant-loudness',
        );
        return ParticipantLoudnessEstimator(
          participantKey: participantKey,
          trackKey: trackKey,
          config: _config,
        );
      });

      // No onTrackReplaced call here: the track is part of the estimator key,
      // so a republished track is a new estimator and the old one is pruned
      // below. Resetting in place would be wrong for the case this keying
      // exists to fix — one user on two devices publishes two concurrent
      // tracks, and alternating between them is not a track replacement.

      if (stream is LocalPlaybackVolumeStream) {
        // The cast is NOT redundant: `stream` does not type-promote here, so
        // removing it stops the file compiling.
        final volumeStream = stream as LocalPlaybackVolumeStream;
        estimator.setManualOverride(
          linearVolume: volumeStream.localVolume,
          hasOverride: volumeStream.hasLocalPlaybackVolumeOverride,
        );
      }

      estimator.addSample(
        ParticipantLoudnessSample(
          timeMs: nowMs,
          level: stream.audiolevel,
          muted: stream.isMuted,
        ),
      );

      // Deliberately AFTER `addSample`. The RTP window is gated on the
      // audiolevel estimator's speech state, and reading it before the sample
      // for this poll was fed returned the PREVIOUS poll's classification - so
      // every speech transition was applied to the RTP window one poll late,
      // and a window straddling a transition was accepted or rejected on the
      // wrong side of it. The visualizer is a poor level meter but a
      // serviceable speech detector, and this is the instant it describes.
      _sampleInboundRtpEnergy(
        stream: stream,
        participantKey: participantKey,
        trackKey: trackKey,
        seenKeys: seenKeys,
        speechState: estimator.state.speechState,
      );
    }

    // Participants that left, or whose audio publication disappeared, must not
    // keep stale estimator state alive.
    final removedKeys = _estimators.keys
        .where((key) => !seenKeys.contains(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      final estimator = _estimators.remove(key);
      if (estimator != null) {
        _retainDepartedSummary(key, estimator);
      }
      // The next reading for this key comes from a fresh receiver whose
      // counters restart at zero.
      _lastEnergySamples.remove(key);
      _energyWindowIsPureSpeech.remove(key);
      _energyMixedWindowRejects.remove(key);
      _energyWindowHadSpeech.remove(key);
      _energySilentWindows.remove(key);
      Log.i(
        'Participant loudness estimator removed: $key',
        category: LogCategory.livekit,
        source: 'participant-loudness',
      );
    }

    // A baseline can outlive its stream WITHOUT ever creating an estimator: the
    // first energy reading only establishes the baseline and returns before an
    // estimator is created. Pruning against _estimators alone therefore never
    // visits that key, and a participant who leaves after exactly one collector
    // reading strands it for the rest of the call. Unlike _departedSummaries,
    // this map has no retention bound, so the leak grows with join/leave churn.
    //
    // The same reasoning applies to the two energy-window maps below, and the
    // original fix only covered `_lastEnergySamples`. A key can hold a baseline
    // or a rejection counter without ever owning an estimator, so the removal
    // loop above never visits it and these grew for departed streams too.
    // All three are keyed identically and must be pruned by the same predicate.
    _lastEnergySamples.removeWhere((key, _) => !seenKeys.contains(key));
    _energyWindowIsPureSpeech.removeWhere((key, _) => !seenKeys.contains(key));
    _energyMixedWindowRejects.removeWhere((key, _) => !seenKeys.contains(key));
    _energyWindowHadSpeech.removeWhere((key, _) => !seenKeys.contains(key));
    _energySilentWindows.removeWhere((key, _) => !seenKeys.contains(key));

    _maybeLogPeriodicSummary(nowMs);
    _notifyChanged();
  }

  /// Feeds the second measurement source: RMS amplitude derived from the
  /// transport's own `inbound-rtp` energy counters.
  ///
  /// This runs *beside* the audiolevel estimator rather than replacing it, so
  /// one exported session shows both sources measuring the same speech. That
  /// comparison is the whole point — the visualizer source was rejected on
  /// live evidence, and the replacement should have to demonstrate on the same
  /// call that it separates participants the visualizer compressed together.
  void _sampleInboundRtpEnergy({
    required VoipStream stream,
    required String participantKey,
    required String trackKey,
    required Set<String> seenKeys,
    required ParticipantSpeechState speechState,
  }) {
    if (stream is! InboundAudioEnergyStream) {
      return;
    }

    final energyKey = estimatorKeyFor(
      participantKey: participantKey,
      trackKey: trackKey,
      source: ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
    );

    // Any moment of non-speech inside the window contaminates it. Recorded on
    // every pass, not just when a reading arrives, because the window spans
    // roughly ten of these.
    if (speechState == ParticipantSpeechState.activeSpeech) {
      _energyWindowHadSpeech[energyKey] = true;
    } else {
      _energyWindowIsPureSpeech[energyKey] = false;
    }

    final sample = (stream as InboundAudioEnergyStream).inboundAudioEnergy;
    if (sample == null || !sample.hasEnergyCounters) {
      // The collector is off, or this transport has no receiver statistics.
      // Do not add the key to seenKeys: an estimator that stops being fed must
      // be pruned like any other, rather than freezing at its last value.
      //
      // Drop the baseline too. Pruning only walks _estimators, so a stream
      // that stopped reporting while still establishing its first pair would
      // otherwise leave its reading here permanently — and if the collector
      // came back, that stale reading would be differenced against counters
      // from a receiver that had restarted in between.
      _lastEnergySamples.remove(energyKey);
      _energyWindowIsPureSpeech.remove(energyKey);
      _energyWindowHadSpeech.remove(energyKey);
      return;
    }

    // The collector publishes at its own cadence, slower than this poll. The
    // same reading seen twice is not a second observation — feeding it again
    // would tell the estimator a level held steady when nothing new was
    // measured, inflating both the sample count and the apparent duration of
    // speech.
    final previous = _lastEnergySamples[energyKey];
    if (previous != null && previous.capturedAtMs == sample.capturedAtMs) {
      seenKeys.add(energyKey);
      return;
    }

    _lastEnergySamples[energyKey] = sample;
    seenKeys.add(energyKey);

    // The window that just closed is judged now; the next one starts from what
    // THIS pass observed, not unconditionally as pure. Seeding it `true` made
    // the closing poll contribute its own speech state to the window that had
    // just ended and never to the one it opened - so a window whose very first
    // observed instant was silence still started life as pure speech.
    final windowWasPureSpeech = _energyWindowIsPureSpeech[energyKey] ?? false;
    final windowHadSpeech = _energyWindowHadSpeech[energyKey] ?? false;
    _energyWindowIsPureSpeech[energyKey] =
        speechState == ParticipantSpeechState.activeSpeech;
    _energyWindowHadSpeech[energyKey] =
        speechState == ParticipantSpeechState.activeSpeech;

    if (previous == null) {
      // One cumulative reading carries no level. The measurement is the ratio
      // of deltas, so the first reading only establishes a baseline.
      return;
    }

    final rms = VoipInboundAudioEnergy.intervalRmsAmplitude(
      previous: previous,
      current: sample,
    );
    if (rms == null) {
      // Counters restarted, the window was too short, or the pair straddles a
      // gap too wide to describe "now". A substituted zero would enter the
      // participant's history as an observation of silence.
      return;
    }

    // A window is a whole second of decoded audio averaged together, speech
    // and pauses alike. A second that was 30% speech reads roughly 5 dB below
    // the speech in it, and one that was 3% speech reads 15 dB below — so an
    // ungated median tracks how continuously someone talks at least as much as
    // how loudly. The first live captures showed exactly that: peak-to-median
    // gaps of 5 to 38 dB within a single participant, and the same person
    // reading 20 dB apart across two sessions while the visualizer moved 1 dB.
    //
    // Only fully-voiced windows are measured. That discards most of them, and
    // the rejects are counted rather than dropped silently, because "few clean
    // windows" and "quiet participant" must stay distinguishable.
    if (!windowWasPureSpeech) {
      // A window with no speech in it at all is not evidence about the gate —
      // it is a second of a long call in which this person did not talk, and
      // most seconds of most calls are that. Folding the two together made a
      // correctly-working gate look pathological: a 166-minute capture
      // reported 9,720 "rejects" against 105 accepted for someone who had
      // spoken for about twelve minutes in total.
      //
      // Only partially-voiced windows say anything about whether the gate is
      // too strict, so only those count as rejects.
      if (windowHadSpeech) {
        _energyMixedWindowRejects[energyKey] =
            (_energyMixedWindowRejects[energyKey] ?? 0) + 1;
      } else {
        _energySilentWindows[energyKey] =
            (_energySilentWindows[energyKey] ?? 0) + 1;
      }
      // Create the estimator anyway, then return without adding a sample.
      //
      // Returning before `putIfAbsent` meant a participant whose windows were
      // ALL mixed never got an estimator for this key - and `buildReport` and
      // `_retainDepartedSummary` are both driven by estimator keys, so the
      // reject counter was incremented and then never read. The counter exists
      // precisely so "few clean windows" and "quiet participant" stay
      // distinguishable, and it went missing in the one case where that
      // distinction matters most: no clean windows at all.
      //
      // A zero-sample estimator summarizes as having insufficient data, which
      // is the honest answer, and now carries the reject count that explains
      // why.
      _ensureEnergyEstimator(energyKey, participantKey, trackKey);
      return;
    }

    final estimator = _ensureEnergyEstimator(
      energyKey,
      participantKey,
      trackKey,
    );

    if (stream is LocalPlaybackVolumeStream) {
      final volumeStream = stream as LocalPlaybackVolumeStream;
      estimator.setManualOverride(
        linearVolume: volumeStream.localVolume,
        hasOverride: volumeStream.hasLocalPlaybackVolumeOverride,
      );
    }

    estimator.addSample(
      ParticipantLoudnessSample(
        // The reading's own capture time, not this poll's clock. The window
        // being measured ended when the collector read the counters.
        timeMs: sample.capturedAtMs,
        level: rms,
        muted: stream.isMuted,
      ),
    );
  }

  /// The inbound-RTP estimator for [energyKey], created on first sight.
  ///
  /// Extracted so the reject path can create it too. Both paths must, because
  /// every downstream reader - `buildReport`, `_retainDepartedSummary` - walks
  /// estimator keys, so a key that exists only in `_energyMixedWindowRejects`
  /// is invisible.
  ParticipantLoudnessEstimator _ensureEnergyEstimator(
    String energyKey,
    String participantKey,
    String trackKey,
  ) {
    return _estimators.putIfAbsent(energyKey, () {
      _departedSummaries.remove(energyKey);
      Log.i(
        'Participant loudness estimator created: '
        'participant=$participantKey track=$trackKey source=inbound-rtp-energy',
        category: LogCategory.livekit,
        source: 'participant-loudness',
      );
      return ParticipantLoudnessEstimator(
        participantKey: participantKey,
        trackKey: trackKey,
        measurementSource:
            ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        config: _energyConfig,
      );
    });
  }

  /// Keeps a departing stream's measurement for the session report. A stream
  /// that leaves and rejoins overwrites its earlier entry rather than
  /// accumulating one per flap.
  void _retainDepartedSummary(
    String key,
    ParticipantLoudnessEstimator estimator,
  ) {
    // A zero-sample estimator is normally noise - a participant who never
    // produced a measurable window - and is dropped. It is NOT dropped when it
    // carries mixed-window rejects: that is a participant every one of whose
    // windows was rejected, which is precisely the case the reject counter
    // exists to describe, and the previous line would have thrown it away on
    // departure right after the reject path was taught to create the estimator.
    //
    // The same argument covers silent windows, which are the *expected* shape
    // of a listener: someone who joined, said nothing and left produces no
    // accepted sample and no reject, only silent windows. Dropping that entry
    // loses the one number that distinguishes "measured, and quiet" from "never
    // measured at all".
    final rejectCount = _energyMixedWindowRejects[key] ?? 0;
    final silentCount = _energySilentWindows[key] ?? 0;
    if (estimator.state.sampleCount == 0 &&
        rejectCount == 0 &&
        silentCount == 0) {
      return;
    }

    _departedSummaries.remove(key);
    _departedSummaries[key] = estimator.summarize(
      presentAtExport: false,
      mixedWindowRejectCount: rejectCount,
      silentWindowCount: silentCount,
    );

    while (_departedSummaries.length > maximumRetainedDepartedSummaries) {
      _departedSummaries.remove(_departedSummaries.keys.first);
    }
  }

  /// Only subscribed incoming microphone audio is measured. Screen-share
  /// audio and the RNNoise server loopback participant are excluded, matching
  /// the filter the call view already applies to per-participant volume.
  bool _isMeasurableStream(VoipStream stream) {
    if (stream.direction != VoipStreamDirection.incoming) {
      return false;
    }

    if (stream.type != VoipStreamType.audio) {
      return false;
    }

    if (stream is MatrixLivekitVoipStream) {
      if (!stream.isMicrophoneAudio) {
        return false;
      }
      if (stream.participantIdentity.contains('_rnnoise_loopback')) {
        return false;
      }
    }

    if (stream is LocalPlaybackVolumeStream &&
        !(stream as LocalPlaybackVolumeStream).hasLocalPlaybackAudio) {
      return false;
    }

    return true;
  }

  /// Periodic, bounded summary. Deliberately not one log line per sample:
  /// at the default interval that would be ten lines per second per talker.
  void _maybeLogPeriodicSummary(int nowMs) {
    final last = _lastDiagnosticLogMs;
    if (last != null && nowMs - last < _diagnosticLogIntervalMs) {
      return;
    }

    _lastDiagnosticLogMs = nowMs;
    if (_estimators.isEmpty) {
      return;
    }

    final entries = states
        .map((state) {
          final suggestion = state.suggestedAutoGainDb;
          final speech = state.activeSpeechLevelDb;
          return '${state.participantKey}'
              ' source=${state.measurementSource.label}'
              ' speech=${speech == null ? 'none' : speech.toStringAsFixed(1)}'
              ' state=${state.speechState.label}'
              ' auto=${suggestion == null ? 'none' : suggestion.toStringAsFixed(1)}'
              ' manual=${state.manualOverrideDb.toStringAsFixed(1)}'
              ' speechSamples=${state.speechSampleCount}';
        })
        .join('; ');

    // Every measured stream is tagged with its own source. Two sources now run
    // concurrently, so one participant appears once per source: a single
    // hardcoded source= on the header, and _estimators.length as a participant
    // count, both read as nonsense the moment the second source is enabled.
    Log.i(
      'Participant loudness measurement (no playback change): '
      'participants=$measuredParticipantCount '
      'measurements=${_estimators.length} $entries',
      category: LogCategory.livekit,
      source: 'participant-loudness',
    );
  }

  /// Sanitized fields for the structured call/audio diagnostic system.
  Map<String, Object?> toDiagnosticMap() {
    final nowMs = _clockMs();
    return <String, Object?>{
      'participantLoudnessMeasurementEnabled': isEnabled,
      'measurementSources': [
        for (final source
            in _estimators.values.map((e) => e.measurementSource).toSet())
          source.label,
      ],
      'measuredParticipantCount': measuredParticipantCount,
      'measuredStreamCount': measuredStreamCount,
      'measurementCount': measurementCount,
      'playbackModified': false,
      'participants': [
        for (final state in states) state.toDiagnosticMap(nowMs: nowMs),
      ],
    };
  }

  /// Compact one-line-per-participant text for the Call Diagnostics sheet.
  List<String> diagnosticLines() {
    if (!isEnabled) {
      return const <String>[];
    }

    final snapshots = states;
    if (snapshots.isEmpty) {
      return const <String>['Participant loudness: measuring, no participants'];
    }

    return [
      for (final state in snapshots)
        'Loudness ${state.participantKey}: '
            'state=${state.speechState.label} '
            'speech=${_formatDb(state.activeSpeechLevelDb)} '
            'peak=${_formatDb(state.peakLevelDb)} '
            'auto=${_formatDb(state.suggestedAutoGainDb)} '
            'manual=${_formatDb(state.manualOverrideDb)} '
            'combined=${_formatDb(state.futureCombinedGainDb)} '
            'n=${state.speechSampleCount}/${state.sampleCount}',
    ];
  }

  /// Builds the exportable measurement-session report.
  ParticipantLoudnessSessionReport buildReport({DateTime? generatedAtUtc}) {
    final keys = _estimators.keys.toList()..sort();
    final startedMs = _sessionStartedMs;
    final nowMs = _clockMs();

    return ParticipantLoudnessSessionReport(
      generatedAtUtc: generatedAtUtc ?? DateTime.now().toUtc(),
      // Derived, not hardcoded. Two sources now run concurrently, and the
      // documented contract for this field is "the first source" - hardcoding
      // streamAudioLevel made a report whose entries all came from
      // inbound-rtp-energy still announce itself as an audiolevel report. Same
      // class of defect as the periodic log that labelled every entry with one
      // source; per-entry measurementSource remains the authoritative answer.
      measurementSource: keys.isEmpty
          ? ParticipantLoudnessMeasurementSource.streamAudioLevel
          : _estimators[keys.first]!.measurementSource,
      config: _config,
      participants: [
        for (final key in keys)
          _estimators[key]!.summarize(
            mixedWindowRejectCount: _energyMixedWindowRejects[key] ?? 0,
            silentWindowCount: _energySilentWindows[key] ?? 0,
          ),
        ...(_departedSummaries.keys.toList()..sort()).map(
          (key) => _departedSummaries[key]!,
        ),
      ],
      sessionDurationMs: startedMs == null ? 0 : (nowMs - startedMs),
      notes: const <String>[
        'Measurement-only slice: no playback gain was applied.',
        'Two sources run concurrently and each track may appear twice - read '
            'each entry\'s measurementSource. stream-audio-level is '
            'VoipStream.audiolevel, the LiveKit visualizer magnitude, which '
            'live evidence rejected as display-normalised. '
            'inbound-rtp-energy is RMS from totalAudioEnergy / '
            'totalSamplesDuration, a real WebRTC statistic upstream of local '
            'playback gain. Comparing the two on the same speech is the point '
            'of this export.',
        'The two sources are not on a common calibration. Compare the SPREAD '
            'between participants within one source, not absolute dB across '
            'sources.',
        'inbound-rtp-energy is sampled at the collector cadence (1 Hz), so '
            'its sample counts are ~10x lower than stream-audio-level for the '
            'same speech. Its estimator is retuned to match.',
        'estimatorConfig below is the stream-audio-level tuning. '
            'inbound-rtp-energy entries were produced with the same tuning '
            'except for minimumSpeechSamples, maximumSampleGap and '
            'speechAboveNoiseFloorDb, which are retimed and retuned for the '
            '1 Hz cadence - so those entries are NOT exactly reproducible '
            'from the embedded config alone.',
        'Participant and track keys are truncated SHA-256 hashes.',
        'One entry per participant per track per source: a participant '
            'publishing from two devices appears twice per source.',
        'Entries with presentAtExport=false are participants who left before '
            'the export.',
      ],
    );
  }

  /// Writes the report to the local diagnostics folder and returns its path,
  /// or null when the export is unsupported or failed.
  Future<String?> exportReport() {
    return writeParticipantLoudnessSessionReport(buildReport());
  }

  void _notifyChanged() {
    if (_disposed || _onChanged.isClosed) {
      return;
    }

    try {
      _onChanged.add(null);
    } catch (_) {
      // Notification can race with call teardown.
    }
  }

  static String _formatDb(double? value) {
    if (value == null || !value.isFinite) {
      return 'none';
    }

    return '${value.toStringAsFixed(1)}dB';
  }

  /// Stable pseudonymous key for a participant. Raw Matrix ids never reach the
  /// estimator, diagnostics, logs, or the exported report.
  ///
  /// Pseudonymous, NOT non-reversible. [_shortHash] is an unsalted SHA-256 and
  /// the input space is a room's member list, so anyone holding a candidate id
  /// can hash it and confirm the match. What this buys is that a log or an
  /// exported report does not hand ids to a reader who does not already have
  /// them; it is not a de-identification guarantee, and it must not be relied
  /// on as one.
  ///
  /// NOTE for the S&C agent: if these reports are ever shared beyond the call's
  /// own participants, this needs a per-session salt to be worth anything.
  static String participantKeyFor(String userId) {
    return _shortHash(userId);
  }

  /// Stable pseudonymous key for a track/publication id — same caveat as
  /// [participantKeyFor], though track ids are far less guessable.
  static String trackKeyFor(String streamId) {
    return _shortHash(streamId);
  }

  /// Estimator identity: one estimator per participant, per track, per source.
  ///
  /// Keying on the participant alone collapsed a user present from two devices
  /// into a single estimator whose track then alternated on every sampling
  /// pass, resetting the estimate continuously so no suggestion was ever
  /// produced for that person. Including the track means two devices report as
  /// two entries instead of cancelling each other out.
  ///
  /// The source is part of the identity because the two measurement sources
  /// run concurrently on the same track and must not share state — they have
  /// different scales, different cadences, and different tuning.
  static String estimatorKeyFor({
    required String participantKey,
    required String trackKey,
    required ParticipantLoudnessMeasurementSource source,
  }) {
    return '$participantKey:$trackKey:${source.label}';
  }

  static String _shortHash(String value) {
    if (value.isEmpty) {
      return 'none';
    }

    return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
  }
}
