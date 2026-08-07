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
      expect(notifications, 2);
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
