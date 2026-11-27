import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/microphone_capture_liveness.dart';

/// BUG-325. A tester's capture showed the microphone published with its RTP
/// sender attached while the native capture hook had processed zero frames for
/// the whole call. Every existing microphone log line reported healthy,
/// because they all describe LiveKit and the failure is upstream of it. These
/// pin the probe that names it.
void main() {
  group('sampler', _samplerTests);

  test('Windows capture liveness monitoring is a no-op off Windows', () {
    expect(
      MicrophoneCaptureLivenessPlatformGate.shouldMonitor(isWindows: false),
      isFalse,
    );
    expect(
      MicrophoneCaptureLivenessPlatformGate.shouldMonitor(isWindows: true),
      isTrue,
    );
  });

  group('capture recovery gate', () {
    test('attempts one recovery for a stalled capture state', () {
      final gate = MicrophoneCaptureRecoveryGate();

      expect(
        gate.shouldAttempt(
          event: MicrophoneCaptureLivenessEvent.stalled,
          microphoneEnableGeneration: 4,
          captureDeviceId: 'input-a',
        ),
        isTrue,
      );
      expect(
        gate.shouldAttempt(
          event: MicrophoneCaptureLivenessEvent.stalled,
          microphoneEnableGeneration: 4,
          captureDeviceId: 'input-a',
        ),
        isFalse,
        reason: 'a stuck device must not republish on every probe tick',
      );
      expect(
        gate.shouldAttempt(
          event: MicrophoneCaptureLivenessEvent.captureAlive,
          microphoneEnableGeneration: 4,
          captureDeviceId: 'input-a',
        ),
        isFalse,
      );
    });

    test('allows one recovery after a fresh device or enable state', () {
      final gate = MicrophoneCaptureRecoveryGate();
      gate.shouldAttempt(
        event: MicrophoneCaptureLivenessEvent.stalled,
        microphoneEnableGeneration: 4,
        captureDeviceId: 'input-a',
      );

      expect(
        gate.shouldAttempt(
          event: MicrophoneCaptureLivenessEvent.stalled,
          microphoneEnableGeneration: 4,
          captureDeviceId: 'input-b',
        ),
        isTrue,
        reason: 'a device change creates a fresh capture state',
      );
      expect(
        gate.shouldAttempt(
          event: MicrophoneCaptureLivenessEvent.stalled,
          microphoneEnableGeneration: 5,
          captureDeviceId: 'input-b',
        ),
        isTrue,
        reason: 'a later explicit microphone enable deserves one retry',
      );
    });
  });

  final start = DateTime(2026, 9, 6, 20, 28);

  MicrophoneCaptureLivenessEvent tick(
    MicrophoneCaptureLivenessProbe probe, {
    required int frames,
    required int atSeconds,
    bool captureExpected = true,
    String? device,
  }) {
    return probe.evaluate(
      captureExpected: captureExpected,
      framesProcessed: frames,
      now: start.add(Duration(seconds: atSeconds)),
      captureDeviceId: device,
    );
  }

  test('a capture that never delivers a frame is reported once', () {
    final probe = MicrophoneCaptureLivenessProbe();

    expect(
      tick(probe, frames: 0, atSeconds: 0),
      MicrophoneCaptureLivenessEvent.none,
    );
    expect(
      tick(probe, frames: 0, atSeconds: 5),
      MicrophoneCaptureLivenessEvent.none,
      reason: 'five seconds is inside the grace window',
    );

    expect(
      tick(probe, frames: 0, atSeconds: 10),
      MicrophoneCaptureLivenessEvent.stalled,
    );
    expect(probe.isStalled, isTrue);
    expect(probe.lastElapsed, const Duration(seconds: 10));

    expect(
      tick(probe, frames: 0, atSeconds: 15),
      MicrophoneCaptureLivenessEvent.none,
      reason: 'one line per stall, not one per tick',
    );
  });

  test(
    'the first frames are reported once, and a healthy call stays quiet',
    () {
      final probe = MicrophoneCaptureLivenessProbe();

      tick(probe, frames: 0, atSeconds: 0);
      expect(
        tick(probe, frames: 240, atSeconds: 5),
        MicrophoneCaptureLivenessEvent.captureAlive,
      );
      expect(probe.lastElapsed, const Duration(seconds: 5));

      expect(
        tick(probe, frames: 740, atSeconds: 10),
        MicrophoneCaptureLivenessEvent.none,
      );
      expect(
        tick(probe, frames: 1240, atSeconds: 15),
        MicrophoneCaptureLivenessEvent.none,
      );
    },
  );

  test('capture that dies mid-call is caught, and its recovery reported', () {
    final probe = MicrophoneCaptureLivenessProbe();
    tick(probe, frames: 0, atSeconds: 0);
    expect(
      tick(probe, frames: 500, atSeconds: 5),
      MicrophoneCaptureLivenessEvent.captureAlive,
    );

    // The counter freezes: capture stopped without anything telling the app.
    expect(
      tick(probe, frames: 500, atSeconds: 10),
      MicrophoneCaptureLivenessEvent.none,
    );
    expect(
      tick(probe, frames: 500, atSeconds: 14),
      MicrophoneCaptureLivenessEvent.stalled,
    );
    expect(probe.lastElapsed, const Duration(seconds: 9));

    expect(
      tick(probe, frames: 520, atSeconds: 20),
      MicrophoneCaptureLivenessEvent.recovered,
    );
    expect(probe.isStalled, isFalse);
    expect(
      probe.lastElapsed,
      const Duration(seconds: 15),
      reason: 'the recovery line carries how long the stall lasted',
    );
  });

  test('silence is not a fault while capture is not expected', () {
    final probe = MicrophoneCaptureLivenessProbe();

    // Push to Talk between presses: the track is disabled on purpose.
    for (final seconds in <int>[0, 5, 10, 15, 20]) {
      expect(
        tick(probe, frames: 0, atSeconds: seconds, captureExpected: false),
        MicrophoneCaptureLivenessEvent.none,
      );
    }
    expect(probe.isStalled, isFalse);

    // And the grace window restarts from the press, rather than counting the
    // muted time against it.
    expect(
      tick(probe, frames: 0, atSeconds: 21),
      MicrophoneCaptureLivenessEvent.none,
    );
    expect(
      tick(probe, frames: 0, atSeconds: 25),
      MicrophoneCaptureLivenessEvent.none,
    );
    expect(
      tick(probe, frames: 0, atSeconds: 30),
      MicrophoneCaptureLivenessEvent.stalled,
    );
  });

  test('a mute in the middle does not count against the next grace window', () {
    // The case the "capture not expected" branch actually exists for. The
    // probe is already running with a baseline when the user releases Push to
    // Talk; if that baseline survived the muted stretch, the first tick after
    // the next press would compare against a timestamp from before the mute
    // and report a stall on a microphone that has had no chance to deliver
    // anything yet.
    final probe = MicrophoneCaptureLivenessProbe();
    tick(probe, frames: 0, atSeconds: 0);
    tick(probe, frames: 0, atSeconds: 4, captureExpected: false);

    expect(
      tick(probe, frames: 0, atSeconds: 10),
      MicrophoneCaptureLivenessEvent.none,
      reason: 'the window restarts at the press, not at the pre-mute baseline',
    );
    expect(
      tick(probe, frames: 0, atSeconds: 20),
      MicrophoneCaptureLivenessEvent.stalled,
      reason: 'and it does still fire, ten seconds after the press',
    );
  });

  test('a stall does not survive a mute as a phantom recovery', () {
    final probe = MicrophoneCaptureLivenessProbe();
    tick(probe, frames: 0, atSeconds: 0);
    expect(
      tick(probe, frames: 0, atSeconds: 10),
      MicrophoneCaptureLivenessEvent.stalled,
    );

    tick(probe, frames: 0, atSeconds: 12, captureExpected: false);
    expect(probe.isStalled, isFalse);
    expect(
      tick(probe, frames: 0, atSeconds: 15),
      MicrophoneCaptureLivenessEvent.none,
      reason: 'the stall belonged to the capture session that ended',
    );
  });

  group('a counter reset is a re-baseline, not capture', () {
    // THIS REVERSES AN EARLIER ASSERTION IN THIS FILE, deliberately. It used
    // to require a decrease to report `captureAlive`, on the reasoning that a
    // reset is itself evidence the capture path did something. That is not
    // safe. `frames_processed` only ever decreases when a fresh
    // `ProcessorSharedState` is constructed, which is a re-initialisation, and
    // treating it as movement means ANY re-init clears an outstanding stall.
    // `NoiseSuppressionService.refresh()` can itself trigger a re-init on a
    // retryable unavailable state, so under the old rule an instrument polling
    // it would manufacture the recovery it then reported - on precisely the
    // unhealthy path the probe exists for.

    test('a decrease reports nothing and re-baselines', () {
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 9000, atSeconds: 0);
      expect(
        tick(probe, frames: 0, atSeconds: 5),
        MicrophoneCaptureLivenessEvent.none,
      );
      // Re-baselined onto the new series, so real capture from here is
      // reported normally rather than measured against the old total.
      expect(
        tick(probe, frames: 40, atSeconds: 9),
        MicrophoneCaptureLivenessEvent.captureAlive,
      );
    });

    test('a re-init does NOT clear an outstanding stall', () {
      // The assertion that matters, and the one the old rule failed.
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 9000, atSeconds: 0);
      expect(
        tick(probe, frames: 9000, atSeconds: 10),
        MicrophoneCaptureLivenessEvent.stalled,
      );

      expect(
        tick(probe, frames: 0, atSeconds: 12),
        MicrophoneCaptureLivenessEvent.none,
        reason: 'a reset is not a recovery',
      );
      expect(
        probe.isStalled,
        isTrue,
        reason:
            'the microphone has not been shown to capture anything since the '
            'stall; a counter starting over says nothing about that',
      );
    });

    test('and the stall still clears on real frames after the reset', () {
      // The control. Without it, refusing to clear on a reset could have made
      // a post-re-init recovery unreportable.
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 9000, atSeconds: 0);
      tick(probe, frames: 9000, atSeconds: 10);
      tick(probe, frames: 0, atSeconds: 12);

      expect(
        tick(probe, frames: 300, atSeconds: 16),
        MicrophoneCaptureLivenessEvent.recovered,
      );
    });
  });

  test('a second call in the same process is judged on its own frames', () {
    // The counter is cumulative over the process, so a probe that tested for
    // zero would call a dead second call healthy on the first call's total.
    final probe = MicrophoneCaptureLivenessProbe();
    tick(probe, frames: 0, atSeconds: 0);
    tick(probe, frames: 5000, atSeconds: 5);
    probe.reset();

    expect(
      tick(probe, frames: 5000, atSeconds: 60),
      MicrophoneCaptureLivenessEvent.none,
    );
    expect(
      tick(probe, frames: 5000, atSeconds: 70),
      MicrophoneCaptureLivenessEvent.stalled,
    );
  });

  group('a capture-device change is not evidence of recovery', () {
    // FROM THE FIELD, 2026-09-07. The affected user's own logs showed
    // `stalled` at 1439 frames on one device, `recovered` at 14837 on another,
    // and `stalled` again at the same 14837. Nothing was captured between the
    // recovery and the stall after it: the counter moved because the device
    // changed and the native processor re-initialised onto its own series, not
    // because the microphone produced audio. The probe reported a recovery
    // that did not happen, on its first outing in the field.

    test('a switch while stalled reports nothing, and the stall stands', () {
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 1439, atSeconds: 0, device: 'A');
      expect(
        tick(probe, frames: 1439, atSeconds: 10, device: 'A'),
        MicrophoneCaptureLivenessEvent.stalled,
      );

      expect(
        tick(probe, frames: 14837, atSeconds: 12, device: 'B'),
        MicrophoneCaptureLivenessEvent.none,
        reason:
            'this is the exact field artifact: a jump caused by the switch '
            'must not read as frames flowing',
      );
      expect(
        probe.isStalled,
        isTrue,
        reason:
            'switching device is not evidence the microphone recovered, so '
            'the outstanding stall has to survive it',
      );
    });

    test('the new device gets its own stall clock, not the old one', () {
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 1439, atSeconds: 0, device: 'A');
      tick(probe, frames: 1439, atSeconds: 10, device: 'A');
      tick(probe, frames: 14837, atSeconds: 12, device: 'B');

      // Already stalled, so no second `stalled` - but the clock restarting is
      // what stops a working new device being condemned on the old one's
      // silence, and it is measurable through the next recovery's elapsed.
      expect(
        tick(probe, frames: 14900, atSeconds: 20, device: 'B'),
        MicrophoneCaptureLivenessEvent.recovered,
      );
      expect(
        probe.lastElapsed,
        const Duration(seconds: 8),
        reason:
            'elapsed must be measured from the switch at 12s, not from the '
            'original baseline at 0s, or the recovery reports a stall '
            'duration that spans a device it never observed',
      );
    });

    test('real movement on ONE device still recovers', () {
      // The control. If a device change were the only way to clear a stall,
      // this fix would have made the probe unable to report recovery at all.
      final probe = MicrophoneCaptureLivenessProbe();
      tick(probe, frames: 100, atSeconds: 0, device: 'A');
      expect(
        tick(probe, frames: 100, atSeconds: 10, device: 'A'),
        MicrophoneCaptureLivenessEvent.stalled,
      );
      expect(
        tick(probe, frames: 400, atSeconds: 14, device: 'A'),
        MicrophoneCaptureLivenessEvent.recovered,
      );
    });

    test('the first observation on any device is a baseline, not a switch', () {
      final probe = MicrophoneCaptureLivenessProbe();
      expect(
        tick(probe, frames: 500, atSeconds: 0, device: 'A'),
        MicrophoneCaptureLivenessEvent.none,
      );
      expect(
        tick(probe, frames: 900, atSeconds: 4, device: 'A'),
        MicrophoneCaptureLivenessEvent.captureAlive,
        reason: 'the device-change branch must not swallow first frames',
      );
    });
  });
}

/// The sampler, which exists because the probe was reading a cache.
///
/// WHAT WOULD MAKE THESE WRONG, and it is the whole point of the file. Every
/// test above injects `framesProcessed` directly, so all of them passed while
/// the production probe read `NoiseSuppressionService.instance.status` - a
/// cached field with no event channel and no periodic refresh, which during a
/// call moves only when the user touches an audio control. The probe measured
/// cache refreshes and reported them as capture. A test that injects the
/// number can never catch that, so these drive a source that DISTINGUISHES a
/// stale read from a fresh one: its counter advances only when refreshed.
void _samplerTests() {
  final start = DateTime(2026, 9, 7, 4, 30);

  test('the counter is read fresh on every sample, not once', () async {
    final source = _FakeStatusSource();
    final sampler = MicrophoneCaptureLivenessSampler(
      refreshStatus: source.refresh,
    );

    await sampler.sample(publicationLive: true, now: start);
    await sampler.sample(
      publicationLive: true,
      now: start.add(const Duration(seconds: 5)),
    );
    await sampler.sample(
      publicationLive: true,
      now: start.add(const Duration(seconds: 10)),
    );

    expect(
      source.refreshes,
      3,
      reason:
          'one refresh per sample. A sampler that read once and reused the '
          'value would report a stall on a microphone that never stopped, '
          'which is exactly the shipped defect',
    );
  });

  test('capture that is flowing is NOT reported as a stall', () async {
    // The regression. The fake advances its counter only on refresh, so a
    // sampler that reads a cached value sees it standing still and reports
    // `stalled` after the window - on live audio.
    final source = _FakeStatusSource();
    final sampler = MicrophoneCaptureLivenessSampler(
      refreshStatus: source.refresh,
    );

    final events = <MicrophoneCaptureLivenessEvent>[];
    for (var tick = 0; tick <= 6; tick++) {
      events.add(
        await sampler.sample(
          publicationLive: true,
          now: start.add(Duration(seconds: 5 * tick)),
        ),
      );
    }

    expect(
      events,
      isNot(contains(MicrophoneCaptureLivenessEvent.stalled)),
      reason: 'the counter advanced on every read; nothing stalled',
    );
    expect(events, contains(MicrophoneCaptureLivenessEvent.captureAlive));
  });

  test('a genuinely frozen counter still stalls', () async {
    // The control. Without it, a sampler that never reported anything would
    // pass the test above.
    final source = _FakeStatusSource(advanceBy: 0);
    final sampler = MicrophoneCaptureLivenessSampler(
      refreshStatus: source.refresh,
    );

    await sampler.sample(publicationLive: true, now: start);
    expect(
      await sampler.sample(
        publicationLive: true,
        now: start.add(const Duration(seconds: 10)),
      ),
      MicrophoneCaptureLivenessEvent.stalled,
    );
  });

  test(
    'the native half of captureExpected comes from the fresh read',
    () async {
      // `available`/`enabled` were previously read off the same cached status.
      // A source that reports the hook absent must silence the probe even
      // though the caller says the publication is live.
      final source = _FakeStatusSource(advanceBy: 0, available: false);
      final sampler = MicrophoneCaptureLivenessSampler(
        refreshStatus: source.refresh,
      );

      await sampler.sample(publicationLive: true, now: start);
      expect(
        await sampler.sample(
          publicationLive: true,
          now: start.add(const Duration(seconds: 30)),
        ),
        MicrophoneCaptureLivenessEvent.none,
        reason:
            'no hook installed means silence is not evidence, and that fact '
            'must come from this read rather than a remembered one',
      );
    },
  );

  test('an overlapping tick is dropped, not queued', () async {
    // The refresh is a platform round trip and the timer fires every 5 s. Two
    // in flight would evaluate out of order against one probe.
    final source = _FakeStatusSource(hold: true);
    final sampler = MicrophoneCaptureLivenessSampler(
      refreshStatus: source.refresh,
    );

    final first = sampler.sample(publicationLive: true, now: start);
    await Future<void>.delayed(Duration.zero);
    expect(sampler.isSampling, isTrue);

    final second = await sampler.sample(
      publicationLive: true,
      now: start.add(const Duration(seconds: 5)),
    );
    expect(second, MicrophoneCaptureLivenessEvent.none);
    expect(
      source.refreshes,
      1,
      reason: 'the overlapping tick must not refresh',
    );

    source.release();
    await first;
  });
}

class _FakeStatusSource {
  _FakeStatusSource({
    this.advanceBy = 100,
    this.available = true,
    this.hold = false,
  });

  final int advanceBy;
  final bool available;
  final bool hold;

  int refreshes = 0;
  int _frames = 0;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  Future<MicrophoneCaptureStatusReading> refresh() async {
    refreshes += 1;
    // The counter moves ONLY here. That is what makes a cached read
    // detectable: it would see the value standing still.
    _frames += advanceBy;
    if (hold) {
      await _gate.future;
    }
    return (available: available, enabled: true, framesProcessed: _frames);
  }
}
