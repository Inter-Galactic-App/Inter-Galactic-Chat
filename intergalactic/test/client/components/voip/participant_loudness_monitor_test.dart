import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_monitor.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';
import 'package:intergalactic/client/components/voip/voip_inbound_audio_energy.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

/// Levels in the same units the stream exposes: linear 0..1.
const double _roomTone = 0.00251; // about -52 dBFS-equivalent
const double _speech = 0.112; // about -19 dBFS-equivalent

void main() {
  group('ParticipantLoudnessMonitor', () {
    late _FakeSession session;
    late ParticipantLoudnessMonitor monitor;
    late int clockMs;
    late bool enabled;

    setUp(() {
      clockMs = 0;
      enabled = true;
      session = _FakeSession();
      monitor = ParticipantLoudnessMonitor(
        // Long enough that the real timer never fires; every pass below is
        // driven explicitly by sampleOnce() so the tests stay deterministic.
        samplingInterval: const Duration(hours: 1),
        followReconcileInterval: const Duration(hours: 1),
        isEnabled: () => enabled,
        clockMs: () => clockMs,
      );
      addTearDown(() => monitor.dispose());
    });

    /// Advances the injected clock and runs one measurement pass.
    void advance({int steps = 1, int stepMs = 100}) {
      for (var index = 0; index < steps; index++) {
        clockMs += stepMs;
        monitor.sampleOnce();
      }
    }

    test('creates one estimator per remote microphone participant', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a', level: 0.2),
        _FakeStream(userId: '@b:example.org', streamId: 'sid-b', level: 0.1),
      ];
      monitor.attach(session);

      advance(steps: 3);

      expect(monitor.measuredParticipantCount, 2);
      expect(
        monitor.states.map((state) => state.participantKey).toSet().length,
        2,
      );
    });

    test('never exposes a raw Matrix id', () {
      session.streams = [
        _FakeStream(userId: '@secret:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance();

      final serialized = monitor.toDiagnosticMap().toString();
      expect(serialized, isNot(contains('@secret:example.org')));
      expect(serialized, isNot(contains('sid-a')));
      expect(monitor.states.single.participantKey, hasLength(12));
    });

    test('ignores outgoing streams and non-audio streams', () {
      session.streams = [
        _FakeStream(
          userId: '@me:example.org',
          streamId: 'sid-local',
          direction: VoipStreamDirection.outgoing,
        ),
        _FakeStream(
          userId: '@screen:example.org',
          streamId: 'sid-video',
          type: VoipStreamType.video,
        ),
        _FakeStream(
          userId: '@share:example.org',
          streamId: 'sid-share',
          type: VoipStreamType.screenshare,
        ),
        _FakeStream(userId: '@voice:example.org', streamId: 'sid-voice'),
      ];
      monitor.attach(session);

      advance();

      expect(monitor.measuredParticipantCount, 1);
      expect(
        monitor.states.single.participantKey,
        ParticipantLoudnessMonitor.participantKeyFor('@voice:example.org'),
      );
    });

    test('ignores a stream that carries no local playback audio', () {
      session.streams = [
        _FakeStream(
          userId: '@empty:example.org',
          streamId: 'sid-empty',
          hasLocalPlaybackAudio: false,
        ),
      ];
      monitor.attach(session);

      advance();

      expect(monitor.measuredParticipantCount, 0);
    });

    test('removes estimator state when a participant leaves', () {
      final leaving = _FakeStream(
        userId: '@leaver:example.org',
        streamId: 'sid-leaver',
      );
      session.streams = [
        leaving,
        _FakeStream(userId: '@stays:example.org', streamId: 'sid-stays'),
      ];
      monitor.attach(session);
      advance(steps: 2);
      expect(monitor.measuredParticipantCount, 2);

      session.streams = [session.streams.last];
      advance(steps: 2);

      expect(monitor.measuredParticipantCount, 1);
      expect(
        monitor.states.single.participantKey,
        ParticipantLoudnessMonitor.participantKeyFor('@stays:example.org'),
      );
    });

    test('a late sample cannot resurrect a removed participant', () {
      session.streams = [
        _FakeStream(userId: '@gone:example.org', streamId: 'sid-gone'),
      ];
      monitor.attach(session);
      advance(steps: 2);

      session.streams = const [];
      advance(steps: 2);

      expect(monitor.measuredParticipantCount, 0);
      expect(monitor.states, isEmpty);
    });

    test('reads the manual override without writing it back', () {
      final stream = _FakeStream(
        userId: '@quiet:example.org',
        streamId: 'sid-quiet',
        localVolume: 1.5,
        hasLocalPlaybackVolumeOverride: true,
      );
      session.streams = [stream];
      monitor.attach(session);

      advance(steps: 3);

      final state = monitor.states.single;
      expect(state.hasManualOverride, isTrue);
      expect(state.manualOverrideLinear, closeTo(1.5, 0.001));
      expect(state.manualOverrideDb, closeTo(3.52, 0.05));
      expect(
        stream.setVolumeCalls,
        isEmpty,
        reason: 'measurement must never touch playback',
      );
    });

    test('a republished track resets measurement for that participant', () {
      final stream = _FakeStream(
        userId: '@flap:example.org',
        streamId: 'sid-first',
        level: 0.2,
      );
      session.streams = [stream];
      monitor.attach(session);
      advance(steps: 5);
      expect(monitor.states.single.sampleCount, greaterThan(0));

      stream.streamIdValue = 'sid-second';
      advance();

      final state = monitor.states.single;
      expect(
        state.trackKey,
        ParticipantLoudnessMonitor.trackKeyFor('sid-second'),
      );
      expect(
        state.sampleCount,
        1,
        reason: 'the new track starts its own measurement history',
      );
    });

    test('one user on two devices gets one estimator per device', () {
      session.streams = [
        _FakeStream(
          userId: '@dual:example.org',
          streamId: 'sid-desktop',
          level: 0.4,
        ),
        _FakeStream(
          userId: '@dual:example.org',
          streamId: 'sid-phone',
          level: 0.1,
        ),
      ];
      monitor.attach(session);

      advance(steps: 40);

      expect(monitor.measuredStreamCount, 2);
      expect(
        monitor.measuredParticipantCount,
        1,
        reason: 'two devices are still one person',
      );

      final states = monitor.states;
      expect(states.map((state) => state.participantKey).toSet(), {
        ParticipantLoudnessMonitor.participantKeyFor('@dual:example.org'),
      });
      expect(states.map((state) => state.trackKey).toSet(), {
        ParticipantLoudnessMonitor.trackKeyFor('sid-desktop'),
        ParticipantLoudnessMonitor.trackKeyFor('sid-phone'),
      });
    });

    test('two concurrent devices both accumulate instead of resetting', () {
      // The defect this keying fixes: both streams mapped to one estimator,
      // whose track then alternated on every pass, so the measurement was
      // discarded continuously and no suggestion could ever be produced.
      final desktop = _FakeStream(
        userId: '@dual:example.org',
        streamId: 'sid-desktop',
        level: _roomTone,
      );
      final phone = _FakeStream(
        userId: '@dual:example.org',
        streamId: 'sid-phone',
        level: _roomTone,
      );
      session.streams = [desktop, phone];
      monitor.attach(session);

      // Room tone first so a floor exists, then speech on both devices.
      advance(steps: 20);
      desktop.level = _speech;
      phone.level = _speech;
      advance(steps: 60);

      for (final state in monitor.states) {
        expect(
          state.sampleCount,
          80,
          reason: 'every pass must count for both devices',
        );
      }
      expect(
        monitor.states.every((state) => state.suggestedAutoGainDb != null),
        isTrue,
        reason:
            'a steady talker on two devices must still produce a '
            'suggestion for each',
      );
    });

    test('one device leaving does not disturb the other', () {
      final phone = _FakeStream(
        userId: '@dual:example.org',
        streamId: 'sid-phone',
        level: 0.3,
      );
      final desktop = _FakeStream(
        userId: '@dual:example.org',
        streamId: 'sid-desktop',
        level: 0.3,
      );
      session.streams = [desktop, phone];
      monitor.attach(session);
      advance(steps: 30);

      session.streams = [desktop];
      advance(steps: 5);

      expect(monitor.measuredStreamCount, 1);
      expect(
        monitor.states.single.trackKey,
        ParticipantLoudnessMonitor.trackKeyFor('sid-desktop'),
      );
      expect(
        monitor.states.single.sampleCount,
        35,
        reason: 'the surviving device keeps its own history',
      );
    });

    test('a participant who left is still in the exported report', () {
      final leaving = _FakeStream(
        userId: '@leaver:example.org',
        streamId: 'sid-leaver',
        level: 0.3,
      );
      session.streams = [
        leaving,
        _FakeStream(
          userId: '@stays:example.org',
          streamId: 'sid-stays',
          level: 0.3,
        ),
      ];
      monitor.attach(session);
      advance(steps: 40);

      session.streams = [session.streams.last];
      advance(steps: 5);

      final report = monitor.buildReport();
      expect(report.participants, hasLength(2));
      expect(report.measuredParticipantCount, 2);

      final departed = report.participants.singleWhere(
        (p) =>
            p.participantKey ==
            ParticipantLoudnessMonitor.participantKeyFor('@leaver:example.org'),
      );
      expect(departed.presentAtExport, isFalse);
      expect(
        departed.sampleCount,
        40,
        reason: 'their measurement is retained, not recomputed from nothing',
      );
      expect(
        report.participants
            .singleWhere((p) => p.participantKey != departed.participantKey)
            .presentAtExport,
        isTrue,
      );
    });

    test('a stream that leaves and rejoins reports once, live', () {
      // REGRESSION: the departed snapshot was retained on leave and nothing
      // cleared it on rejoin, so buildReport emitted the same participant:track
      // twice - one presentAtExport:false with the stale measurement and one
      // live - contradicting the report's own "one entry per participant per
      // track" note and inflating measuredStreamCount.
      final flapping = _FakeStream(
        userId: '@flap:example.org',
        streamId: 'sid-flap',
        level: 0.3,
      );
      session.streams = [flapping];
      monitor.attach(session);
      advance(steps: 40);

      // Leave...
      session.streams = [];
      advance(steps: 5);
      // ...and come back on the same track.
      session.streams = [flapping];
      advance(steps: 10);

      final report = monitor.buildReport();
      expect(report.participants, hasLength(1));
      expect(report.measuredStreamCount, 1);
      expect(report.participants.single.presentAtExport, isTrue);

      // Pins the KNOWN LIMITATION documented at the putIfAbsent in
      // participant_loudness_monitor.dart: the entry covers only the 10
      // post-rejoin samples, not all 50. This asserts the lossy behaviour on
      // purpose so the loss is visible in the suite rather than silent - if
      // AUDIO lands the estimator-retention fix, this expectation SHOULD fail
      // and be rewritten to assert the merged count. Bounded rather than
      // exact-matched so ordinary sampling jitter does not make it brittle;
      // what matters is that it reflects the short tail, not the full session.
      expect(report.participants.single.sampleCount, lessThan(40));
    });

    test('detach does not carry departed participants into the next call', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a', level: 0.3),
      ];
      monitor.attach(session);
      advance(steps: 30);
      session.streams = const [];
      advance(steps: 2);
      expect(monitor.buildReport().participants, hasLength(1));

      monitor.detach();
      final next = _FakeSession();
      addTearDown(next.dispose);
      next.streams = [
        _FakeStream(userId: '@b:example.org', streamId: 'sid-b', level: 0.3),
      ];
      monitor.attach(next);
      advance(steps: 2);

      final report = monitor.buildReport();
      expect(report.participants, hasLength(1));
      expect(
        report.participants.single.participantKey,
        ParticipantLoudnessMonitor.participantKeyFor('@b:example.org'),
      );
    });

    group('call-lifecycle following', () {
      test('measurement outlives the view that displays it', () {
        session.streams = [
          _FakeStream(userId: '@a:example.org', streamId: 'sid-a', level: 0.2),
        ];
        monitor.followSession(session);
        advance(steps: 5);
        expect(monitor.isAttached, isTrue);

        // Whatever built a diagnostics view has gone away. Nothing about that
        // should stop the call being measured — this is the defect that turned
        // a four-hour call into 105 seconds of data.
        expect(monitor.measuredParticipantCount, 1);
        advance(steps: 20);
        expect(monitor.isAttached, isTrue);
        expect(monitor.states.single.sampleCount, 25);
      });

      test(
        'a call joined before the flag is on starts measuring when it is',
        () {
          enabled = false;
          session.streams = [
            _FakeStream(
              userId: '@a:example.org',
              streamId: 'sid-a',
              level: 0.2,
            ),
          ];
          monitor.followSession(session);
          advance(steps: 5);
          expect(monitor.isAttached, isFalse);

          // Turned on mid-call, which is how anyone actually reaches for it.
          enabled = true;
          monitor.reconcileFollowedSession();
          advance(steps: 5);

          expect(monitor.isAttached, isTrue);
          expect(monitor.measuredParticipantCount, 1);
        },
      );

      test(
        'turning the flag off mid-call stops measuring but keeps following',
        () {
          session.streams = [
            _FakeStream(
              userId: '@a:example.org',
              streamId: 'sid-a',
              level: 0.2,
            ),
          ];
          monitor.followSession(session);
          advance(steps: 5);
          expect(monitor.isAttached, isTrue);

          enabled = false;
          monitor.reconcileFollowedSession();
          expect(monitor.isAttached, isFalse);

          enabled = true;
          monitor.reconcileFollowedSession();
          expect(
            monitor.isAttached,
            isTrue,
            reason: 'the session is still followed, so it can resume',
          );
        },
      );

      test('a call that ends stops the follow', () {
        session.streams = [
          _FakeStream(userId: '@a:example.org', streamId: 'sid-a', level: 0.2),
        ];
        monitor.followSession(session);
        advance(steps: 3);
        expect(monitor.isAttached, isTrue);

        session.state = VoipState.ended;
        monitor.reconcileFollowedSession();

        expect(monitor.isAttached, isFalse);
        expect(monitor.states, isEmpty);

        // And it stays stopped rather than re-attaching on the next tick.
        monitor.reconcileFollowedSession();
        expect(monitor.isAttached, isFalse);
      });
    });

    group('inbound-rtp energy source', () {
      /// Drives both the 10 Hz poll and the 1 Hz collector, the way the two
      /// actually interleave in a call.
      void advanceWithEnergy(
        _FakeStream stream, {
        required int seconds,
        required double rms,
      }) {
        for (var second = 0; second < seconds; second++) {
          stream.accumulateEnergy(rms: rms, capturedAtMs: clockMs + 1000);
          advance(steps: 10);
        }
      }

      test('measures the same track alongside the audiolevel source', () {
        final stream = _FakeStream(
          userId: '@dual:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);

        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 20, rms: 0.112);

        expect(
          monitor.measuredStreamCount,
          1,
          reason: 'one track, however many sources measure it',
        );
        expect(monitor.measurementCount, 2);
        expect(monitor.states.map((s) => s.measurementSource).toSet(), {
          ParticipantLoudnessMeasurementSource.streamAudioLevel,
          ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        });

        final energy = monitor.states.singleWhere(
          (s) =>
              s.measurementSource ==
              ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        );
        expect(
          energy.suggestedAutoGainDb,
          isNotNull,
          reason: 'the retuned config must confirm speech at 1 Hz',
        );
        // 0.112 RMS is about -19 dB, which is the target, so the suggestion
        // should sit near zero rather than against either clamp.
        expect(energy.suggestedAutoGainDb!, closeTo(0.0, 2.0));
      });

      test('a window containing silence is rejected, not measured', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);

        // Establish a floor, then talk continuously so the audiolevel
        // estimator confirms speech.
        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 15, rms: 0.112);

        final clean = monitor.states
            .singleWhere(
              (s) =>
                  s.measurementSource ==
                  ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
            )
            .sampleCount;
        expect(clean, greaterThan(0));

        // Now the participant pauses mid-window: the second still decodes
        // audio, but it is no longer all speech.
        stream.level = _roomTone;
        advance(steps: 4);
        stream.level = _speech;
        stream.accumulateEnergy(rms: 0.05, capturedAtMs: clockMs + 600);
        advance(steps: 6);

        expect(
          monitor.states
              .singleWhere(
                (s) =>
                    s.measurementSource ==
                    ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
              )
              .sampleCount,
          clean,
          reason: 'a mixed window must not enter the level history',
        );

        final summary = monitor.buildReport().participants.singleWhere(
          (p) =>
              p.measurementSource ==
              ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        );
        expect(
          summary.mixedWindowRejectCount,
          greaterThan(0),
          reason: 'rejections are counted, not silently dropped',
        );

        // And it survives serialization: the export artifact is the report
        // JSON, and a count held only on the in-memory summary would be
        // invisible in every exported diagnostic.
        final serialized =
            (monitor.buildReport().toJson()['participants'] as List<dynamic>)
                .cast<Map<String, Object?>>()
                .singleWhere(
                  (p) =>
                      p['measurementSource'] ==
                      ParticipantLoudnessMeasurementSource
                          .inboundRtpEnergy
                          .label,
                );
        expect(
          serialized['mixedWindowRejectCount'],
          summary.mixedWindowRejectCount,
          reason: 'the serialized count must match the tracked one',
        );
      });

      test('silent windows are counted apart from mixed ones', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);

        // Establish speech so an energy estimator exists at all.
        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 15, rms: 0.112);

        // Then a long stretch of not talking — most of any real call.
        stream.level = _roomTone;
        advanceWithEnergy(stream, seconds: 30, rms: 0.003);

        final summary = monitor.buildReport().participants.singleWhere(
          (p) =>
              p.measurementSource ==
              ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        );

        expect(
          summary.silentWindowCount,
          greaterThan(20),
          reason: 'seconds with no speech are counted as silent',
        );
        expect(
          summary.mixedWindowRejectCount,
          lessThan(summary.silentWindowCount),
          reason:
              'a quiet stretch is silence, not evidence the gate is '
              'too strict — folding the two together made a working gate look '
              'pathological at 9,720 rejects against 105 accepted',
        );

        // The exported artifact is the report JSON, so a count carried only on
        // the in-memory summary is invisible in every diagnostic anyone
        // actually reads. The reject count next door is asserted the same way.
        final serialized =
            (monitor.buildReport().toJson()['participants'] as List<dynamic>)
                .cast<Map<String, Object?>>()
                .singleWhere(
                  (p) =>
                      p['measurementSource'] ==
                      ParticipantLoudnessMeasurementSource
                          .inboundRtpEnergy
                          .label,
                );
        expect(serialized['silentWindowCount'], summary.silentWindowCount);
      });

      test('a participant who only ever listened is still exported', () {
        // The common case, not an edge one: someone who joins, says nothing and
        // leaves produces no accepted sample and no mixed-window reject - only
        // silent windows. Dropping that summary on departure lost the one
        // number distinguishing "measured, and quiet" from "never measured".
        final quiet = _FakeStream(
          userId: '@listener:example.org',
          streamId: 'sid-quiet',
          level: _roomTone,
        );
        session.streams = [quiet];
        monitor.attach(session);

        advanceWithEnergy(quiet, seconds: 20, rms: 0.003);

        final live = monitor.buildReport().participants.singleWhere(
          (p) =>
              p.measurementSource ==
              ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        );
        expect(live.sampleCount, 0);
        expect(live.mixedWindowRejectCount, 0);
        expect(live.silentWindowCount, greaterThan(0));

        // Now they leave.
        session.streams = const [];
        advance(steps: 5);

        final departed = monitor.buildReport().participants.where(
          (p) =>
              p.measurementSource ==
              ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
        );
        expect(
          departed,
          hasLength(1),
          reason: 'the departed session report must still carry them',
        );
        expect(departed.single.presentAtExport, isFalse);
        expect(departed.single.silentWindowCount, live.silentWindowCount);
      });

      test('a repeated reading is not counted as a new observation', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);

        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 5, rms: 0.112);
        final afterFive = monitor.states
            .singleWhere(
              (s) =>
                  s.measurementSource ==
                  ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
            )
            .sampleCount;

        // Thirty more polls with the collector stalled: same reading each time.
        advance(steps: 30);

        final afterStall = monitor.states
            .singleWhere(
              (s) =>
                  s.measurementSource ==
                  ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
            )
            .sampleCount;
        expect(
          afterStall,
          afterFive,
          reason: 'polling faster than the collector must not inflate counts',
        );
        expect(
          afterFive,
          lessThanOrEqualTo(5),
          reason: 'one sample per collector reading, not per poll',
        );
      });

      test('the first reading only establishes a baseline', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);

        // Exactly one reading exists. A cumulative counter on its own carries
        // no level, so there is nothing to measure yet.
        stream.accumulateEnergy(rms: 0.003, capturedAtMs: clockMs + 1000);
        advance(steps: 10);

        expect(
          monitor.states.where(
            (s) =>
                s.measurementSource ==
                ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
          ),
          isEmpty,
          reason: 'one cumulative reading carries no level',
        );

        // Further readings during confirmed speech do produce measurements.
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 12, rms: 0.112);

        expect(
          monitor.states.where(
            (s) =>
                s.measurementSource ==
                ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
          ),
          hasLength(1),
        );
      });

      test('restarted counters produce no sample rather than a false one', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);
        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 8, rms: 0.112);

        final before = monitor.states
            .singleWhere(
              (s) =>
                  s.measurementSource ==
                  ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
            )
            .sampleCount;

        // The receiver was replaced: totals restart from zero, so the delta
        // against the retained baseline goes negative.
        stream.energy = VoipInboundAudioEnergySample(
          capturedAtMs: clockMs + 1000,
          totalAudioEnergy: 0.0,
          totalSamplesDuration: 0.0,
        );
        advance(steps: 10);

        expect(
          monitor.states
              .singleWhere(
                (s) =>
                    s.measurementSource ==
                    ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
              )
              .sampleCount,
          before,
          reason: 'a negative delta is not a quiet window',
        );
      });

      test('a stream with no energy counters measures on audiolevel only', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _speech,
        );
        session.streams = [stream];
        monitor.attach(session);

        advance(steps: 40);

        expect(monitor.measurementCount, 1);
        expect(
          monitor.states.single.measurementSource,
          ParticipantLoudnessMeasurementSource.streamAudioLevel,
        );
      });

      test('the export carries both sources for the same track', () {
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);
        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 20, rms: 0.112);

        final json = monitor.buildReport().toJson();
        expect(json['schemaVersion'], 3);
        expect(json['measuredStreamCount'], 1);
        expect(json['measurementCount'], 2);
        expect(json['measurementSources'], [
          'stream-audio-level',
          'inbound-rtp-energy',
        ]);

        final participants = json['participants'] as List<Object?>;
        final tracks = participants
            .map((p) => (p as Map<String, Object?>)['trackHash'])
            .toSet();
        expect(tracks, hasLength(1), reason: 'both entries are one track');
        expect(json.toString(), isNot(contains('@a:example.org')));
      });

      test('detach drops the counter baselines', () {
        // Constructed at room tone, like every sibling test, so the switch to
        // speech below is a real transition. It used to be constructed at
        // `_speech`, which made the assignment after the room-tone feed a
        // no-op and fed the audiolevel estimator speech from the very first
        // sample - so the room-tone segment was not room tone at all.
        final stream = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _roomTone,
        );
        session.streams = [stream];
        monitor.attach(session);
        advanceWithEnergy(stream, seconds: 3, rms: 0.003);
        stream.level = _speech;
        advanceWithEnergy(stream, seconds: 6, rms: 0.112);
        monitor.detach();

        // A new call: the receiver restarts, so its totals are small again. If
        // the old baseline survived, the first pair would span two calls.
        final next = _FakeSession();
        addTearDown(next.dispose);
        final rejoined = _FakeStream(
          userId: '@a:example.org',
          streamId: 'sid-a',
          level: _speech,
        );
        next.streams = [rejoined];
        monitor.attach(next);
        rejoined.accumulateEnergy(rms: 0.112, capturedAtMs: clockMs + 1000);
        advance(steps: 5);

        expect(
          monitor.states.where(
            (s) =>
                s.measurementSource ==
                ParticipantLoudnessMeasurementSource.inboundRtpEnergy,
          ),
          isEmpty,
          reason: 'the new call must re-baseline, not difference across calls',
        );
      });
    });

    test('detach clears all estimator state', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance(steps: 2);
      expect(monitor.measuredParticipantCount, 1);

      monitor.detach();

      expect(monitor.isAttached, isFalse);
      expect(monitor.measuredParticipantCount, 0);
    });

    test('a session that ends detaches the monitor', () async {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance(steps: 2);

      session.state = VoipState.ended;
      session.notifyStateChanged();
      await Future<void>.delayed(Duration.zero);

      expect(monitor.isAttached, isFalse);
      expect(monitor.measuredParticipantCount, 0);
    });

    test('reattaching to a new session does not leak the previous one', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance(steps: 2);

      final second = _FakeSession()
        ..streams = [_FakeStream(userId: '@b:example.org', streamId: 'sid-b')];
      addTearDown(second.dispose);
      monitor.attach(second);
      advance(steps: 2);

      expect(monitor.measuredParticipantCount, 1);
      expect(
        monitor.states.single.participantKey,
        ParticipantLoudnessMonitor.participantKeyFor('@b:example.org'),
      );
      expect(session.stateListenerCount, 0);
    });

    test('attaching while disabled creates nothing', () {
      enabled = false;
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];

      monitor.attach(session);

      expect(monitor.isAttached, isFalse);
      expect(monitor.measuredParticipantCount, 0);
      expect(monitor.diagnosticLines(), isEmpty);
    });

    test('turning the flag off mid-call tears the measurement down', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance(steps: 2);
      expect(monitor.measuredParticipantCount, 1);

      enabled = false;
      advance();

      expect(monitor.isAttached, isFalse);
      expect(monitor.measuredParticipantCount, 0);
    });

    test('diagnostics report that playback was not modified', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a'),
      ];
      monitor.attach(session);
      advance(steps: 2);

      final map = monitor.toDiagnosticMap();
      expect(map['participantLoudnessMeasurementEnabled'], isTrue);
      expect(map['playbackModified'], isFalse);
      expect(map['measuredParticipantCount'], 1);
      expect(map['measurementSources'], ['stream-audio-level']);
    });

    test('the exported report carries config, notes and hashed keys', () {
      session.streams = [
        _FakeStream(userId: '@a:example.org', streamId: 'sid-a', level: 0.2),
      ];
      monitor.attach(session);
      advance(steps: 10);

      final report = monitor.buildReport(
        generatedAtUtc: DateTime.utc(2026, 7, 27, 12, 30),
      );
      final json = report.toJson();

      expect(json['schemaVersion'], 3);
      expect(json['playbackModified'], isFalse);
      expect(json['measuredParticipantCount'], 1);
      expect(json['measuredStreamCount'], 1);
      expect(json['estimatorConfig'], isA<Map<String, Object?>>());
      expect(json['notes'], isNotEmpty);
      expect(
        report.suggestedFileName,
        'participant-loudness-2026-07-27T12-30-00-000Z.json',
      );
      expect(json.toString(), isNot(contains('@a:example.org')));
    });
  });
}

class _FakeSession implements VoipSession {
  _FakeSession() {
    _stateController = StreamController<void>.broadcast(
      onListen: () => _listeners++,
      onCancel: () => _listeners--,
    );
  }

  late final StreamController<void> _stateController;

  int _listeners = 0;

  @override
  List<VoipStream> streams = const [];

  @override
  VoipState state = VoipState.connected;

  int get stateListenerCount => _listeners;

  @override
  Stream<void> get onStateChanged => _stateController.stream;

  void notifyStateChanged() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  void dispose() {
    unawaited(_stateController.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStream
    implements VoipStream, LocalPlaybackVolumeStream, InboundAudioEnergyStream {
  _FakeStream({
    required String userId,
    required String streamId,
    this.level = 0.1,
    this.type = VoipStreamType.audio,
    this.direction = VoipStreamDirection.incoming,
    this.localVolume = 1.0,
    this.hasLocalPlaybackVolumeOverride = false,
    this.hasLocalPlaybackAudio = true,
  }) : streamUserIdValue = userId,
       streamIdValue = streamId;

  String streamUserIdValue;
  String streamIdValue;
  double level;

  final List<double> setVolumeCalls = <double>[];

  @override
  final VoipStreamType type;

  @override
  final VoipStreamDirection direction;

  @override
  bool isMuted = false;

  @override
  double localVolume;

  @override
  bool hasLocalPlaybackVolumeOverride;

  @override
  bool hasLocalPlaybackAudio;

  @override
  String get streamUserId => streamUserIdValue;

  @override
  String get streamId => streamIdValue;

  @override
  double get audiolevel => level;

  VoipInboundAudioEnergySample? energy;

  @override
  VoipInboundAudioEnergySample? get inboundAudioEnergy => energy;

  /// Advances the cumulative counters as though [rms] had been decoded for
  /// [seconds], the way a real receiver's monotonic totals move.
  void accumulateEnergy({
    required double rms,
    required int capturedAtMs,
    double seconds = 1.0,
  }) {
    final previous = energy;
    energy = VoipInboundAudioEnergySample(
      capturedAtMs: capturedAtMs,
      totalAudioEnergy:
          (previous?.totalAudioEnergy ?? 0.0) + (rms * rms * seconds),
      totalSamplesDuration: (previous?.totalSamplesDuration ?? 0.0) + seconds,
    );
  }

  @override
  bool get locallyMuted => localVolume <= 0.0;

  @override
  Future<void> setLocalVolume(double volume) async {
    setVolumeCalls.add(volume);
    localVolume = volume;
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) => setLocalVolume(volume);

  @override
  void clearLocalPlaybackVolumeOverride() {
    hasLocalPlaybackVolumeOverride = false;
  }

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
