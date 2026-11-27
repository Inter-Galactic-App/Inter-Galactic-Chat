/// Capture-path liveness for the local microphone (BUG-325).
///
/// The publish side of the microphone is already well instrumented: the join
/// logs the enable, the publication, the RTP sender attachment and, since
/// BUG-320, a one-shot reconcile of that sender. All of it can report a
/// perfectly healthy microphone while the user is inaudible, because every one
/// of those facts is about LiveKit, and the failure seen on a tester's machine
/// is upstream of LiveKit: Windows capture delivered ZERO audio frames for a
/// whole call while the track was published and its sender attached.
///
/// The native suppression hook is installed with `SetCapturePostProcessing`
/// and runs once per captured frame, so its frame counter is a direct measure
/// of whether capture is producing audio at all. This probe watches that
/// counter and says which of three things is true, so a capture names the
/// failing stage instead of leaving it to be inferred.
///
/// It compares the counter against its own earlier reading rather than against
/// zero, for two reasons. The counter is cumulative over the process, so a
/// second call in the same session would start non-zero and a zero test would
/// be blind to it. And a delta also catches capture that starts and later
/// dies, which nothing detects today.
///
/// THE COUNTER IS MONOTONIC WITHIN ONE PROCESSOR, and that is the only thing
/// a delta can be read against. `ProcessorSharedState::frames_processed` is an
/// `std::atomic<int>` whose only writes anywhere in the plugin are
/// `fetch_add(1)`; it is never stored back to zero. A REPLACEMENT shared state
/// starts at 0, so re-initialising the processor makes the counter jump DOWN,
/// not onto some other rising series. A device change is the event that
/// replaces it, which is why a device change re-baselines here and reports
/// [none], leaving any outstanding stall outstanding.
///
/// A CORRECTION WORTH KEEPING, because the first two readings of this probe's
/// own field capture were both wrong. The 2026-09-07 capture showed a
/// `recovered` at 14837 frames followed by a `stalled` at the same 14837, and
/// it was read first as the probe working and then as a device-switch
/// artefact. Neither holds. 13,398 frames appearing in one 5 s tick, after 27
/// ticks of no movement, cannot come from a monotonic counter being sampled -
/// at 480 samples per 10 ms frame that is 134 s of audio, and the event's own
/// elapsed was 135000 ms. The audio WAS captured. It was not being READ: the
/// probe sampled a cached status that only a handful of user actions refresh.
/// A device change is one of them, which is how the correlation was
/// manufactured. Hence [MicrophoneCaptureLivenessSampler], which exists so
/// that the refresh cannot be forgotten again.
enum MicrophoneCaptureLivenessEvent {
  /// Nothing to report on this tick.
  none,

  /// The first frames of this capture session arrived. Logged once so a
  /// healthy call has a positive marker to compare a silent one against, and
  /// so time-to-first-frame is on the record.
  captureAlive,

  /// The counter has not moved for [MicrophoneCaptureLivenessProbe.stallAfter]
  /// while capture was expected to be running. Reported once per stall.
  stalled,

  /// Frames resumed after a stall was reported.
  recovered,
}

/// One reading of the native capture status, taken FRESH.
///
/// A record rather than the service's own status type so the pure probe file
/// does not depend on the noise-suppression service.
typedef MicrophoneCaptureStatusReading = ({
  bool available,
  bool enabled,
  int framesProcessed,
});

/// Refreshes the native status and returns it. MUST perform the platform read;
/// returning a cached value defeats the probe entirely.
typedef MicrophoneCaptureStatusRefresh =
    Future<MicrophoneCaptureStatusReading> Function();

/// Platform boundary for the Windows native capture-frame diagnostic and its
/// recovery. Other platforms do not expose this counter, so they must neither
/// poll it nor recreate a microphone based on it.
class MicrophoneCaptureLivenessPlatformGate {
  const MicrophoneCaptureLivenessPlatformGate._();

  static bool shouldMonitor({required bool isWindows}) => isWindows;
}

/// Drives [MicrophoneCaptureLivenessProbe] from a FRESH status read.
///
/// WHY THIS TYPE EXISTS AT ALL. The probe was originally fed
/// `NoiseSuppressionService.instance.status`, which is a plain cached field
/// updated only by explicit calls - there is no event channel and no periodic
/// refresh, so during a call it moves only when the user touches an audio
/// control. The probe therefore measured WHEN THE CACHE WAS REFRESHED and
/// never once measured capture, while reporting `stalled` and `recovered` as
/// though it had. Every unit test passed throughout, because they inject
/// `framesProcessed` directly and never exercise the read.
///
/// So the refresh is not left to the caller to remember. This owns it, it is
/// async by construction so a synchronous cache read cannot be passed without
/// visibly wrapping it, and [sample] is serialised because the timer that
/// drives it fires faster than a platform round trip can be relied on to
/// finish.
class MicrophoneCaptureLivenessSampler {
  MicrophoneCaptureLivenessSampler({
    required this.refreshStatus,
    MicrophoneCaptureLivenessProbe? probe,
  }) : probe = probe ?? MicrophoneCaptureLivenessProbe();

  final MicrophoneCaptureStatusRefresh refreshStatus;
  final MicrophoneCaptureLivenessProbe probe;

  bool _sampling = false;

  /// True while a refresh is in flight, so an overlapping tick is dropped
  /// rather than queued behind it.
  bool get isSampling => _sampling;

  /// Refreshes the native status, then evaluates.
  ///
  /// [publicationLive] is the LiveKit half of "capture is expected" - a live,
  /// unmuted, enabled microphone publication the user asked for. The native
  /// half comes from the reading this call takes, so a status that says the
  /// hook is not installed cannot be answered from a stale one.
  ///
  /// Returns [MicrophoneCaptureLivenessEvent.none] if a sample is already in
  /// flight.
  Future<MicrophoneCaptureLivenessEvent> sample({
    required bool publicationLive,
    required DateTime now,
    String? captureDeviceId,
  }) async {
    if (_sampling) {
      return MicrophoneCaptureLivenessEvent.none;
    }
    _sampling = true;
    try {
      final reading = await refreshStatus();
      return probe.evaluate(
        captureExpected:
            publicationLive && reading.available && reading.enabled,
        framesProcessed: reading.framesProcessed,
        now: now,
        captureDeviceId: captureDeviceId,
      );
    } finally {
      _sampling = false;
    }
  }
}

/// Allows one self-heal for a capture state that the liveness probe proved is
/// stalled.
///
/// Recreating a local microphone track is disruptive, so this must never run
/// on every diagnostic tick. A fresh enabled generation or a different capture
/// device represents a new capture state and earns one new attempt; repeating
/// the same stalled state does not. The caller still owns the actual refresh
/// and its normal mute/teardown checks.
class MicrophoneCaptureRecoveryGate {
  int? _attemptedGeneration;
  String? _attemptedCaptureDeviceId;
  var _hasAttempted = false;

  bool shouldAttempt({
    required MicrophoneCaptureLivenessEvent event,
    required int microphoneEnableGeneration,
    String? captureDeviceId,
  }) {
    if (event != MicrophoneCaptureLivenessEvent.stalled) {
      return false;
    }
    if (_hasAttempted &&
        _attemptedGeneration == microphoneEnableGeneration &&
        _attemptedCaptureDeviceId == captureDeviceId) {
      return false;
    }

    _hasAttempted = true;
    _attemptedGeneration = microphoneEnableGeneration;
    _attemptedCaptureDeviceId = captureDeviceId;
    return true;
  }
}

class MicrophoneCaptureLivenessProbe {
  MicrophoneCaptureLivenessProbe({
    this.stallAfter = const Duration(seconds: 8),
  });

  /// How long the frame counter may stand still before this is a stall.
  ///
  /// Long enough that a slow device open is not called a fault, short enough
  /// that a user who says "nobody could hear me" has the line in the window a
  /// bug report captures.
  final Duration stallAfter;

  int? _baselineFrames;
  DateTime? _baselineAt;
  String? _baselineDeviceId;
  bool _stalled = false;
  bool _sawCapture = false;
  Duration _lastElapsed = Duration.zero;

  /// Time the reported event covers: to the first frames for [captureAlive],
  /// the stalled duration for [stalled] and [recovered].
  Duration get lastElapsed => _lastElapsed;

  /// Whether a stall has been reported and not yet recovered.
  bool get isStalled => _stalled;

  MicrophoneCaptureLivenessEvent evaluate({
    required bool captureExpected,
    required int framesProcessed,
    required DateTime now,
    String? captureDeviceId,
  }) {
    if (!captureExpected) {
      // Push to Talk between presses, a deliberate mute, a call without a
      // microphone publication: capture is meant to be idle and silence is
      // not evidence of anything.
      reset();
      return MicrophoneCaptureLivenessEvent.none;
    }

    final baselineFrames = _baselineFrames;
    final baselineAt = _baselineAt;
    if (baselineFrames == null || baselineAt == null) {
      _baselineFrames = framesProcessed;
      _baselineAt = now;
      _baselineDeviceId = captureDeviceId;
      _lastElapsed = Duration.zero;
      return MicrophoneCaptureLivenessEvent.none;
    }

    if (captureDeviceId != _baselineDeviceId) {
      // A different device means a different counter series, so this tick
      // carries no information about whether audio is flowing. Re-baseline and
      // say nothing. The stall is deliberately NOT cleared: switching device
      // is not evidence that capture recovered, and if the new device works
      // the next tick reports `recovered` on a delta that was actually
      // measured. If it does not work, the stall clock restarts here and the
      // new device gets its own grace period, which is what it deserves.
      _baselineFrames = framesProcessed;
      _baselineAt = now;
      _baselineDeviceId = captureDeviceId;
      _lastElapsed = Duration.zero;
      return MicrophoneCaptureLivenessEvent.none;
    }

    if (framesProcessed < baselineFrames) {
      // A DECREASE is a re-initialised processor, not capture. Within one
      // `ProcessorSharedState` the counter only ever increases - every write
      // in the plugin is `fetch_add(1)` - so the only way to see a smaller
      // number is a fresh state whose counter starts at zero. Re-baseline and
      // say nothing, exactly as for a device change.
      //
      // This used to be treated as movement, on the reasoning that a reset is
      // itself evidence the capture path did something. That is not safe: any
      // re-initialisation would then CLEAR AN OUTSTANDING STALL, so an
      // instrument whose own polling could trigger a re-init - which
      // `NoiseSuppressionService.refresh()` can - would manufacture the
      // recovery it reports. The sampler polling `observeStatus()` is one half
      // of the answer; this is the other, because a reset must not be readable
      // as capture from ANY re-init path, including the health timers that
      // legitimately fire during a join.
      _baselineFrames = framesProcessed;
      _baselineAt = now;
      _lastElapsed = Duration.zero;
      return MicrophoneCaptureLivenessEvent.none;
    }

    if (framesProcessed > baselineFrames) {
      _lastElapsed = now.difference(baselineAt);
      _baselineFrames = framesProcessed;
      _baselineAt = now;
      if (_stalled) {
        _stalled = false;
        _sawCapture = true;
        return MicrophoneCaptureLivenessEvent.recovered;
      }
      if (!_sawCapture) {
        _sawCapture = true;
        return MicrophoneCaptureLivenessEvent.captureAlive;
      }
      return MicrophoneCaptureLivenessEvent.none;
    }

    final elapsed = now.difference(baselineAt);
    if (!_stalled && elapsed >= stallAfter) {
      _stalled = true;
      _lastElapsed = elapsed;
      return MicrophoneCaptureLivenessEvent.stalled;
    }
    return MicrophoneCaptureLivenessEvent.none;
  }

  void reset() {
    _baselineFrames = null;
    _baselineAt = null;
    _baselineDeviceId = null;
    _stalled = false;
    _sawCapture = false;
    _lastElapsed = Duration.zero;
  }
}
