import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/screenshare_audio_visibility_grace.dart';

void main() {
  const window = Duration(milliseconds: 600);
  final t0 = DateTime.utc(2026, 8, 3, 12);

  ScreenshareAudioVisibilityGrace grace() =>
      ScreenshareAudioVisibilityGrace(window: window);

  group('ScreenshareAudioVisibilityGrace', () {
    test('a real surface is visible and starts the window', () {
      final g = grace();

      expect(g.resolve(streamId: 'a', realVisible: true, now: t0), isTrue);
      expect(g.graceRemaining('a', t0), window);
    });

    test('holds the previous verdict across a single-frame gap', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);

      // The tile vanished for one frame - a republish, popout transition, or
      // layout-slot key change. It must not mute.
      expect(
        g.resolve(
          streamId: 'a',
          realVisible: false,
          now: t0.add(const Duration(milliseconds: 16)),
        ),
        isTrue,
      );
    });

    test('mutes once the window closes', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);

      expect(
        g.resolve(streamId: 'a', realVisible: false, now: t0.add(window)),
        isFalse,
      );
    });

    test('repeated rebuilds inside the window still terminate (REVIEW P1)', () {
      // The defect this guards: the first version of the fix wrote the
      // "last visible" timestamp from the EFFECTIVE verdict, so every rebuild
      // inside the grace refreshed it. An active call rebuilds constantly, so
      // a genuinely hidden screenshare stayed audible indefinitely instead of
      // muting after the window.
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);

      // The real surface is gone from here on. Rebuild every 16 ms - far more
      // often than the window - for well past the window.
      var lastVerdict = true;
      var mutedAt = -1;
      for (var elapsedMs = 16; elapsedMs <= 2000; elapsedMs += 16) {
        lastVerdict = g.resolve(
          streamId: 'a',
          realVisible: false,
          now: t0.add(Duration(milliseconds: elapsedMs)),
        );
        if (!lastVerdict && mutedAt < 0) {
          mutedAt = elapsedMs;
        }
      }

      expect(
        lastVerdict,
        isFalse,
        reason: 'frequent rebuilds must not renew the grace window',
      );
      expect(
        mutedAt,
        inInclusiveRange(600, 616),
        reason: 'must mute at the window boundary, not later',
      );
    });

    test('a real sighting during the grace legitimately restarts it', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);
      g.resolve(
        streamId: 'a',
        realVisible: false,
        now: t0.add(const Duration(milliseconds: 300)),
      );

      // The tile came back. This is a real surface, so the window restarts.
      g.resolve(
        streamId: 'a',
        realVisible: true,
        now: t0.add(const Duration(milliseconds: 400)),
      );

      // 700 ms after t0 but only 300 ms after the last REAL sighting.
      expect(
        g.resolve(
          streamId: 'a',
          realVisible: false,
          now: t0.add(const Duration(milliseconds: 700)),
        ),
        isTrue,
      );
      expect(
        g.resolve(
          streamId: 'a',
          realVisible: false,
          now: t0.add(const Duration(milliseconds: 1001)),
        ),
        isFalse,
      );
    });

    test('a never-seen stream is hidden immediately, with no grace', () {
      final g = grace();

      expect(
        g.resolve(streamId: 'unseen', realVisible: false, now: t0),
        isFalse,
      );
      expect(g.graceRemaining('unseen', t0), isNull);
    });

    test('an expired stream does not get a second grace later', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);
      expect(
        g.resolve(streamId: 'a', realVisible: false, now: t0.add(window)),
        isFalse,
      );

      // A much later gap must not resurrect the original stale sighting.
      expect(
        g.resolve(
          streamId: 'a',
          realVisible: false,
          now: t0.add(const Duration(milliseconds: 700)),
        ),
        isFalse,
      );
    });

    test('graceRemaining counts down and stops being held at the boundary', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);

      expect(
        g.graceRemaining('a', t0.add(const Duration(milliseconds: 200))),
        const Duration(milliseconds: 400),
      );
      expect(g.graceRemaining('a', t0.add(window)), isNull);
    });

    test('streams are tracked independently', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);
      g.resolve(
        streamId: 'b',
        realVisible: true,
        now: t0.add(const Duration(milliseconds: 400)),
      );

      final at700 = t0.add(const Duration(milliseconds: 700));
      expect(g.resolve(streamId: 'a', realVisible: false, now: at700), isFalse);
      expect(g.resolve(streamId: 'b', realVisible: false, now: at700), isTrue);
    });

    test('retainOnly drops streams that no longer exist', () {
      final g = grace();
      g.resolve(streamId: 'a', realVisible: true, now: t0);
      g.resolve(streamId: 'b', realVisible: true, now: t0);
      expect(g.trackedCount, 2);

      g.retainOnly({'a'});
      expect(g.trackedCount, 1);

      // 'b' is gone, so it gets no grace if it reappears without a surface.
      expect(
        g.resolve(
          streamId: 'b',
          realVisible: false,
          now: t0.add(const Duration(milliseconds: 16)),
        ),
        isFalse,
      );
    });
  });
}
