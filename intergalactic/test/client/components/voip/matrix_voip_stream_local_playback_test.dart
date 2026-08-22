import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_stream.dart';

void main() {
  group('MatrixVoipStream subscription cancellation', () {
    test('recovers stale stream subscription cancellation failures', () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelDirectCallStreamSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    });
  });

  group('MatrixVoipStream renderer operations', () {
    test('recovers stale renderer operation failures', () async {
      var attempts = 0;

      await expectLater(
        debugRunDirectCallRendererOperationForTesting(() async {
          attempts++;
          throw StateError('renderer already disposed');
        }),
        completes,
      );

      expect(attempts, 1);
    });
  });

  group('MatrixVoipStreamReceivePriorityState', () {
    test('updates receive priority and notifies while active', () async {
      var notifications = 0;
      final priority = MatrixVoipStreamReceivePriorityState(
        notifyChanged: () => notifications++,
      );

      await priority.setReceivePriority(VoipStreamReceivePriority.low);

      expect(priority.receivePriority, VoipStreamReceivePriority.low);
      expect(notifications, 1);

      await priority.setReceivePriority(VoipStreamReceivePriority.low);

      expect(priority.receivePriority, VoipStreamReceivePriority.low);
      expect(notifications, 1);
    });

    test('ignores receive priority changes after dispose', () async {
      var notifications = 0;
      final priority = MatrixVoipStreamReceivePriorityState(
        notifyChanged: () => notifications++,
      );

      await priority.setReceivePriority(VoipStreamReceivePriority.medium);
      priority.dispose();

      await priority.setReceivePriority(VoipStreamReceivePriority.disabled);

      expect(priority.receivePriority, VoipStreamReceivePriority.medium);
      expect(notifications, 1);
    });
  });

  group('MatrixVoipStreamLocalPlaybackState', () {
    test('applies local playback state and notifies while active', () async {
      final appliedVolumes = <double>[];
      var notifications = 0;
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () => notifications++,
      );

      await playback.setLocalVolume(0.25);

      expect(playback.localVolume, 0.25);
      expect(playback.locallyMuted, isFalse);
      expect(playback.hasLocalPlaybackVolumeOverride, isTrue);
      expect(appliedVolumes, [0.25]);
      expect(notifications, 1);

      await playback.setDefaultLocalVolume(0.75);

      expect(playback.localVolume, 0.25);
      expect(appliedVolumes, [0.25]);
      expect(notifications, 1);

      playback.clearLocalPlaybackVolumeOverride();
      await playback.setDefaultLocalVolume(0);

      expect(playback.localVolume, 0);
      expect(playback.locallyMuted, isTrue);
      expect(playback.hasLocalPlaybackVolumeOverride, isFalse);
      expect(appliedVolumes, [0.25, 0]);
      // Three, not two: the override clear rides the queue and notifies as its
      // own observable state change (matching the LiveKit implementation),
      // then the default-volume apply notifies again.
      expect(notifications, 3);
    });

    test('ignores local playback changes after dispose', () async {
      final appliedVolumes = <double>[];
      var notifications = 0;
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () => notifications++,
      );

      await playback.setLocalVolume(0.25);
      playback.dispose();

      await playback.setLocalVolume(0.75);
      await playback.setDefaultLocalVolume(1.25);
      playback.clearLocalPlaybackVolumeOverride();

      expect(playback.localVolume, 0.25);
      expect(playback.locallyMuted, isFalse);
      expect(playback.hasLocalPlaybackVolumeOverride, isTrue);
      expect(appliedVolumes, [0.25]);
      expect(notifications, 1);
    });

    test('reports a local mute and restores the prior gain', () async {
      // The direct-call deafen path used to write `track.enabled` straight
      // through, so this object reported locallyMuted == false while the user
      // was deafened - the LiveKit path and the direct path disagreed about
      // whether the call was silent. "Deafened at volume 1.10" has to be a
      // representable state here or nothing can observe the divergence.
      final appliedVolumes = <double>[];
      var notifications = 0;
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () => notifications++,
      );

      await playback.setLocalVolume(1.10);
      expect(playback.locallyMuted, isFalse);

      await playback.setLocalMute(true);

      expect(playback.locallyMuted, isTrue);
      expect(playback.localVolume, 1.10);
      expect(appliedVolumes, [1.10, 0.0]);
      expect(notifications, 2);

      await playback.setLocalMute(true);
      expect(appliedVolumes, [1.10, 0.0]);
      expect(notifications, 2);

      await playback.setLocalMute(false);

      expect(playback.locallyMuted, isFalse);
      expect(appliedVolumes, [1.10, 0.0, 1.10]);
      expect(notifications, 3);
    });

    test('a local mute release does not re-open a zero volume', () async {
      final appliedVolumes = <double>[];
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () {},
      );

      await playback.setLocalVolume(0);
      await playback.setLocalMute(true);
      await playback.setLocalMute(false);

      expect(playback.locallyMuted, isTrue);
      expect(appliedVolumes.last, 0.0);
    });

    test('applies the last of three overlapping mute requests', () async {
      // The requests are deliberately NOT awaited individually. Every other
      // test here awaits each call, so the queue is always empty before the
      // next request and the overlap case is never exercised. `setLocalMute`
      // used to compare the requested value against the APPLIED value before
      // queueing: with `mute -> unmute -> mute` issued back-to-back, the third
      // request saw `locallyMuted` still false (the first had not drained) and
      // was dropped, leaving the participant audible after the user had muted
      // them. The comparison now happens inside the queued operation, against
      // the state as of the moment that operation runs.
      final appliedVolumes = <double>[];
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async {
          await Future<void>.delayed(Duration.zero);
          appliedVolumes.add(volume);
        },
        notifyChanged: () {},
      );

      final requests = [
        playback.setLocalMute(true),
        playback.setLocalMute(false),
        playback.setLocalMute(true),
      ];
      await Future.wait(requests);

      expect(playback.locallyMuted, isTrue);
      // The full ordered sequence, not just the last value: `last == 0.0` is
      // also satisfied when the queue collapses the middle unmute, and a
      // dropped request is exactly the defect this test guards against.
      expect(appliedVolumes, [0.0, 1.0, 0.0]);
    });

    test('an override clear is ordered behind an already-queued set', () async {
      // The slider surfaces do exactly this sequence in one synchronous
      // frame: queue the volume write, then decide the value equals the
      // default and clear the override. A synchronous (unqueued) clear runs
      // BEFORE the queued write, whose `userOverride: true` re-latches the
      // flag - after which setDefaultLocalVolume is a silent no-op for this
      // participant for the rest of the call. The clear must ride the same
      // queue, as the LiveKit implementation always has.
      final appliedVolumes = <double>[];
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () {},
      );

      final pending = playback.setLocalVolume(1.0);
      playback.clearLocalPlaybackVolumeOverride();
      await pending;
      // Let the queued clear drain.
      await Future<void>.delayed(Duration.zero);

      expect(playback.hasLocalPlaybackVolumeOverride, isFalse);

      await playback.setDefaultLocalVolume(0.3);
      expect(appliedVolumes, [1.0, 0.3]);
    });

    test('ignores a local mute after dispose', () async {
      final appliedVolumes = <double>[];
      final playback = MatrixVoipStreamLocalPlaybackState(
        applyVolume: (volume) async => appliedVolumes.add(volume),
        notifyChanged: () {},
      );

      await playback.setLocalVolume(0.5);
      playback.dispose();
      await playback.setLocalMute(true);

      expect(playback.locallyMuted, isFalse);
      expect(appliedVolumes, [0.5]);
    });

    test(
      'does not notify if disposal happens while volume is applying',
      () async {
        final applyStarted = Completer<void>();
        final releaseApply = Completer<void>();
        var notifications = 0;
        final playback = MatrixVoipStreamLocalPlaybackState(
          applyVolume: (_) async {
            applyStarted.complete();
            await releaseApply.future;
          },
          notifyChanged: () => notifications++,
        );

        final applyFuture = playback.setDefaultLocalVolume(0.5);
        await applyStarted.future;

        playback.dispose();
        releaseApply.complete();
        await applyFuture;

        expect(playback.localVolume, 0.5);
        expect(playback.hasLocalPlaybackVolumeOverride, isFalse);
        expect(notifications, 0);
      },
    );
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  var cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('wrapped stream disposed'));
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future<E>.value(futureValue);

  @override
  bool get isPaused => false;

  @override
  void onData(void Function(void data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}
}
