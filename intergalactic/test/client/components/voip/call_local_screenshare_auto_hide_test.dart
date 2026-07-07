import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_local_screenshare_auto_hide.dart';

void main() {
  group('CallLocalScreenshareAutoHideController', () {
    test('schedules one auto-hide timer per local screenshare tile', () {
      final scheduler = _FakeTimerScheduler();
      final hidden = <String>{};
      final shown = <String>{};
      final autoHidden = <String>{};
      final fired = <String>[];
      final controller = CallLocalScreenshareAutoHideController(
        previewDuration: const Duration(seconds: 30),
        timerFactory: scheduler.create,
      );

      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: fired.add,
      );
      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: fired.add,
      );

      expect(scheduler.createdDurations, [const Duration(seconds: 30)]);
      expect(controller.pendingTimerCount, 1);

      scheduler.fire('local-screen');

      expect(fired, ['local-screen']);
      expect(controller.pendingTimerCount, 0);
    });

    test(
      'cancels stale timers when participant or stream state removes a tile',
      () {
        final scheduler = _FakeTimerScheduler();
        final hidden = <String>{};
        final shown = <String>{};
        final autoHidden = <String>{};
        final fired = <String>[];
        final controller = CallLocalScreenshareAutoHideController(
          previewDuration: const Duration(seconds: 30),
          timerFactory: scheduler.create,
        );

        controller.sync(
          localScreenshareTileIds: {'gone-screen', 'kept-screen'},
          streamTestRunning: false,
          autoHiddenTileIds: autoHidden,
          hiddenTileIds: hidden,
          shownTileIds: shown,
          onAutoHide: fired.add,
        );
        autoHidden.add('old-auto-hidden-screen');
        controller.sync(
          localScreenshareTileIds: {'kept-screen'},
          streamTestRunning: false,
          autoHiddenTileIds: autoHidden,
          hiddenTileIds: hidden,
          shownTileIds: shown,
          onAutoHide: fired.add,
        );

        expect(autoHidden, isNot(contains('old-auto-hidden-screen')));
        expect(scheduler.timer('gone-screen')?.cancelled, isTrue);
        expect(controller.hasPendingTimer('gone-screen'), isFalse);
        expect(controller.hasPendingTimer('kept-screen'), isTrue);
      },
    );

    test('keeps local screenshares visible while stream test is running', () {
      final scheduler = _FakeTimerScheduler();
      final hidden = <String>{'local-screen'};
      final shown = <String>{};
      final autoHidden = <String>{};
      final controller = CallLocalScreenshareAutoHideController(
        previewDuration: const Duration(seconds: 30),
        timerFactory: scheduler.create,
      );

      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: (_) {},
      );
      autoHidden.add('local-screen');
      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: true,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: (_) {},
      );

      expect(scheduler.timer('local-screen')?.cancelled, isTrue);
      expect(autoHidden, isNot(contains('local-screen')));
      expect(hidden, isNot(contains('local-screen')));
      expect(shown, contains('local-screen'));
      expect(controller.pendingTimerCount, 0);
    });

    test('manual handling cancels the pending auto-hide timer', () {
      final scheduler = _FakeTimerScheduler();
      final hidden = <String>{};
      final shown = <String>{};
      final autoHidden = <String>{};
      final fired = <String>[];
      final controller = CallLocalScreenshareAutoHideController(
        previewDuration: const Duration(seconds: 30),
        timerFactory: scheduler.create,
      );

      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: fired.add,
      );
      controller.markHandled('local-screen', autoHiddenTileIds: autoHidden);
      scheduler.fire('local-screen');

      expect(scheduler.timer('local-screen')?.cancelled, isTrue);
      expect(autoHidden, contains('local-screen'));
      expect(fired, isEmpty);
    });

    test('manual reveal after auto-hide does not schedule another timer', () {
      final scheduler = _FakeTimerScheduler();
      final hidden = <String>{};
      final shown = <String>{};
      final autoHidden = <String>{};
      final controller = CallLocalScreenshareAutoHideController(
        previewDuration: const Duration(seconds: 30),
        timerFactory: scheduler.create,
      );

      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: (tileId) {
          autoHidden.add(tileId);
          hidden.add(tileId);
          shown.remove(tileId);
        },
      );
      scheduler.fire('local-screen');
      hidden.remove('local-screen');
      shown.add('local-screen');
      controller.markHandled('local-screen', autoHiddenTileIds: autoHidden);
      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: (_) {},
      );

      expect(scheduler.createdDurations, [const Duration(seconds: 30)]);
      expect(autoHidden, contains('local-screen'));
      expect(hidden, isNot(contains('local-screen')));
      expect(shown, contains('local-screen'));
      expect(controller.pendingTimerCount, 0);
    });

    test('dispose cancels timers and ignores late timer callbacks', () {
      final scheduler = _FakeTimerScheduler();
      final hidden = <String>{};
      final shown = <String>{};
      final autoHidden = <String>{};
      final fired = <String>[];
      final controller = CallLocalScreenshareAutoHideController(
        previewDuration: const Duration(seconds: 30),
        timerFactory: scheduler.create,
      );

      controller.sync(
        localScreenshareTileIds: {'local-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: fired.add,
      );
      controller.dispose();
      scheduler.fire('local-screen');
      controller.sync(
        localScreenshareTileIds: {'late-screen'},
        streamTestRunning: false,
        autoHiddenTileIds: autoHidden,
        hiddenTileIds: hidden,
        shownTileIds: shown,
        onAutoHide: fired.add,
      );
      controller.markHandled('late-screen', autoHiddenTileIds: autoHidden);

      expect(controller.isDisposed, isTrue);
      expect(scheduler.timer('local-screen')?.cancelled, isTrue);
      expect(fired, isEmpty);
      expect(scheduler.timers.keys, isNot(contains('late-screen')));
      expect(autoHidden, isNot(contains('late-screen')));
    });
  });
}

class _FakeTimerScheduler {
  final timers = <String, _FakeTimer>{};
  final createdDurations = <Duration>[];

  CallLocalScreenshareAutoHideTimer create(
    String tileId,
    Duration duration,
    void Function() onTimeout,
  ) {
    createdDurations.add(duration);
    final timer = _FakeTimer(onTimeout);
    timers[tileId] = timer;
    return timer;
  }

  _FakeTimer? timer(String tileId) => timers[tileId];

  void fire(String tileId) {
    timer(tileId)?.fire();
  }
}

class _FakeTimer implements CallLocalScreenshareAutoHideTimer {
  _FakeTimer(this._onTimeout);

  final void Function() _onTimeout;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  void fire() {
    if (!cancelled) {
      _onTimeout();
    }
  }
}
