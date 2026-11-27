/// Receiver-side audio energy read from the transport's own `inbound-rtp`
/// statistics.
///
/// This exists because the measurement source receiver-side loudness balancing
/// was built on - `VoipStream.audiolevel` - was rejected on live evidence.
/// On LiveKit that value is the native audio *visualizer* magnitude
/// (`createVisualizer`, barCount 1), which is display-normalised: across five
/// people on different hardware in different rooms it compressed peak level
/// into a 0.73 dB span and 90th-percentile speech into 1.42 dB, while real
/// participant loudness varies by 20-30 dB. A source that cannot separate
/// participants by more than 3 dB cannot rank them, which is the entire premise
/// of the feature. Full analysis:
/// `docs/audio/participant-loudness-first-capture-2026-07-30.md`.
///
/// `totalAudioEnergy` and `totalSamplesDuration` do not have that problem:
/// they are monotonic counters defined by the W3C WebRTC statistics spec,
/// accumulated from decoded samples normalised to [-1.0, 1.0], and they sit
/// upstream of local playback gain.
library;

import 'dart:math' as math;

/// One cumulative reading of a remote audio track's inbound-rtp counters.
///
/// A single reading carries no level information - both counters are totals
/// since the track began. The measurement is the *ratio of the deltas* between
/// two readings, which is why [VoipInboundAudioEnergy.intervalRmsAmplitude]
/// takes a pair. That ratio is poll-rate independent: a slow, jittery, or
/// skipped poll changes how much decoded audio a window covers, not the value
/// computed from it.
class VoipInboundAudioEnergySample {
  const VoipInboundAudioEnergySample({
    required this.capturedAtMs,
    this.totalAudioEnergy,
    this.totalSamplesDuration,
    this.audioLevel,
  });

  /// Wall clock at collection, used only to reject stale pairings. It is not
  /// the measurement window: [totalSamplesDuration] is, and the two differ
  /// whenever the receiver stalls or the poll is late.
  final int capturedAtMs;

  /// Linear sum of squared sample amplitudes, in units of amplitude-squared
  /// times seconds, since the track began.
  final double? totalAudioEnergy;

  /// Seconds of decoded audio the energy total was accumulated over.
  final double? totalSamplesDuration;

  /// The per-report instantaneous level from the same inbound-rtp record.
  ///
  /// Carried through for comparison only. It is a genuine WebRTC statistic
  /// here (unlike the visualizer magnitude), but it is a single-packet
  /// snapshot whose value depends on when the poll lands, so it is not the
  /// measurement - it exists so a diagnostics export can show both sources
  /// side by side.
  final double? audioLevel;

  bool get hasEnergyCounters =>
      totalAudioEnergy != null && totalSamplesDuration != null;
}

/// A stream that can report receiver-side inbound-rtp audio energy.
///
/// Deliberately a separate interface rather than a member on `VoipStream`:
/// only transports that expose WebRTC receiver statistics can answer it. Direct
/// Matrix/WebRTC calls threshold their audio level to 0.0/1.0 at 0.2 and are
/// excluded from this measurement entirely, so a consumer must test for this
/// interface and fall back rather than assume every stream provides it.
abstract class InboundAudioEnergyStream {
  /// Most recent reading, or null when nothing has been collected yet, the
  /// collector is disabled, or the track is not a subscribed remote audio
  /// track.
  VoipInboundAudioEnergySample? get inboundAudioEnergy;
}

/// Conversion from a pair of cumulative readings to a comparable level.
class VoipInboundAudioEnergy {
  const VoipInboundAudioEnergy._();

  /// Longest gap between two readings that still describes "now".
  ///
  /// The counters stay valid indefinitely, so an old pair yields a
  /// mathematically correct RMS - of a window minutes wide, averaging speech
  /// with every silence in it. That is a different quantity from the one the
  /// caller asked for, and it is worse than no answer because it looks like
  /// one.
  static const int maximumIntervalMs = 5000;

  /// Least decoded audio a window must contain to be worth measuring, in
  /// seconds. Below this the ratio is dominated by counter quantisation.
  static const double minimumSamplesDurationDeltaSeconds = 0.01;

  /// Root-mean-square amplitude of everything decoded between two readings,
  /// on the same linear 0.0-1.0 scale as `VoipStream.audiolevel`.
  ///
  /// Returns the value on that scale rather than in dB so it is a drop-in
  /// replacement for the rejected source: consumers that already convert a
  /// linear level to dB keep doing exactly that.
  ///
  /// Returns null - never a substituted zero - when the pair cannot support a
  /// measurement. A zero would be indistinguishable from true digital silence
  /// and would be averaged into a participant's history as if it were an
  /// observation.
  static double? intervalRmsAmplitude({
    required VoipInboundAudioEnergySample previous,
    required VoipInboundAudioEnergySample current,
    int maximumIntervalMs = maximumIntervalMs,
  }) {
    if (!previous.hasEnergyCounters || !current.hasEnergyCounters) {
      return null;
    }

    final elapsedMs = current.capturedAtMs - previous.capturedAtMs;
    if (elapsedMs <= 0 || elapsedMs > maximumIntervalMs) {
      return null;
    }

    final energyDelta = current.totalAudioEnergy! - previous.totalAudioEnergy!;
    final durationDelta =
        current.totalSamplesDuration! - previous.totalSamplesDuration!;

    // Both counters are monotonic, so a negative delta is not a quiet window -
    // it means the counters restarted underneath us (track republished, or the
    // receiver was replaced). The pair spans two different tracks and cannot be
    // subtracted.
    if (energyDelta < 0 || durationDelta < 0) {
      return null;
    }

    if (durationDelta < minimumSamplesDurationDeltaSeconds) {
      return null;
    }

    final meanSquare = energyDelta / durationDelta;
    if (!meanSquare.isFinite || meanSquare < 0) {
      return null;
    }

    // Samples are normalised to [-1.0, 1.0], so the mean square cannot exceed
    // 1.0. Clamping guards against a non-conforming implementation rather than
    // against normal signals.
    return math.sqrt(math.min(meanSquare, 1.0));
  }
}
