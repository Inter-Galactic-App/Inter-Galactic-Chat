import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/desktop_window_bounds_persistence.dart';

void main() {
  group('DesktopWindowBoundsPersistence restore bounds', () {
    test(
      'keeps a saved window on a secondary monitor with negative coordinates',
      () {
        final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
          storedBounds: const Rect.fromLTWH(-1280, 120, 900, 700),
          visibleDisplayBounds: const [
            Rect.fromLTWH(0, 0, 1920, 1040),
            Rect.fromLTWH(-1440, 0, 1440, 860),
          ],
        );

        expect(restored, const Rect.fromLTWH(-1280, 120, 900, 700));
      },
    );

    test('drops bounds when the saved monitor is no longer present', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(2600, 100, 900, 700),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, isNull);
    });

    test('nudges mostly hidden bounds back onto the visible display', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(1880, 100, 900, 700),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, const Rect.fromLTWH(1840, 100, 900, 700));
    });

    test('preserves deliberately partially visible windows', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(1760, 100, 900, 700),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, const Rect.fromLTWH(1760, 100, 900, 700));
    });

    test('pulls a window whose title bar sits above the screen back down', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(400, -200, 900, 700),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, const Rect.fromLTWH(400, 0, 900, 700));
    });

    test('nudges a window hidden below the taskbar back into reach', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(400, 1000, 900, 700),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, const Rect.fromLTWH(400, 960, 900, 700));
    });

    test('clamps tiny saved sizes to a restorable desktop size', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(200, 100, 120, 90),
        visibleDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(restored, const Rect.fromLTWH(200, 100, 360, 320));
    });
  });

  group('DesktopWindowBoundsPersistence title bar reachability', () {
    test('accepts a window whose top strip is visible on any display', () {
      expect(
        DesktopWindowBoundsPersistence.isTitleBarReachable(
          const Rect.fromLTWH(-400, 120, 900, 700),
          const [Rect.fromLTWH(0, 0, 1920, 1040)],
        ),
        isTrue,
      );
    });

    test('rejects a window whose top edge is above every display', () {
      expect(
        DesktopWindowBoundsPersistence.isTitleBarReachable(
          const Rect.fromLTWH(400, -40, 900, 700),
          const [Rect.fromLTWH(0, 0, 1920, 1040)],
        ),
        isFalse,
      );
    });

    test('rejects a window with too little horizontal overlap', () {
      expect(
        DesktopWindowBoundsPersistence.isTitleBarReachable(
          const Rect.fromLTWH(1880, 120, 900, 700),
          const [Rect.fromLTWH(0, 0, 1920, 1040)],
        ),
        isFalse,
      );
    });

    test('pulls a fully off-screen window onto the nearest display', () {
      final repaired = DesktopWindowBoundsPersistence.resolveReachableBounds(
        const Rect.fromLTWH(3000, 2000, 900, 700),
        const [Rect.fromLTWH(0, 0, 1920, 1040)],
      );

      expect(repaired, const Rect.fromLTWH(1840, 960, 900, 700));
    });

    test('ensureWindowReachable repairs a stranded live window', () async {
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(500, -300, 900, 700),
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: _FakeDesktopWindowBoundsStore(),
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.ensureWindowReachable();

      expect(window.lastSetBounds, const Rect.fromLTWH(500, 0, 900, 700));
    });

    test('deduplicates concurrent reachability repairs', () async {
      final displays = Completer<List<Rect>>();
      var displayRequests = 0;
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(500, -300, 900, 700),
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: _FakeDesktopWindowBoundsStore(),
        window: window,
        displayBoundsProvider: () {
          displayRequests += 1;
          return displays.future;
        },
      );

      final first = persistence.ensureWindowReachable();
      final second = persistence.ensureWindowReachable();
      await Future<void>.delayed(Duration.zero);
      expect(displayRequests, 1);

      displays.complete(const [Rect.fromLTWH(0, 0, 1920, 1040)]);
      await Future.wait<void>([first, second]);

      expect(window.lastSetBounds, const Rect.fromLTWH(500, 0, 900, 700));
    });

    test('ensureWindowReachable leaves reachable windows alone', () async {
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(500, 100, 900, 700),
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: _FakeDesktopWindowBoundsStore(),
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.ensureWindowReachable();

      expect(window.lastSetBounds, isNull);
    });

    test('ensureWindowReachable skips maximized windows', () async {
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(500, -300, 900, 700),
        maximized: true,
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: _FakeDesktopWindowBoundsStore(),
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.ensureWindowReachable();

      expect(window.lastSetBounds, isNull);
    });

    test('unmaximizing repairs and persists reachable bounds', () async {
      final store = _FakeDesktopWindowBoundsStore();
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(500, -300, 900, 700),
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
        saveDebounce: Duration.zero,
      );

      persistence.onWindowUnmaximize();
      await pumpEventQueue();

      expect(window.lastSetBounds, const Rect.fromLTWH(500, 0, 900, 700));
      expect(store.state!.normalBounds, const Rect.fromLTWH(500, 0, 900, 700));
    });

    test(
      'unmaximizing cancels a stale debounce before delayed repair',
      () async {
        final store = _FakeDesktopWindowBoundsStore();
        final displays = Completer<List<Rect>>();
        final window = _FakeDesktopWindowAdapter(
          bounds: const Rect.fromLTWH(500, -300, 900, 700),
        );
        final persistence = DesktopWindowBoundsPersistence(
          store: store,
          window: window,
          displayBoundsProvider: () => displays.future,
          saveDebounce: Duration.zero,
        );

        persistence.onWindowMove();
        persistence.onWindowUnmaximize();
        await Future<void>.delayed(Duration.zero);
        expect(store.state, isNull);

        displays.complete(const [Rect.fromLTWH(0, 0, 1920, 1040)]);
        await pumpEventQueue();

        expect(store.state!.normalBounds, window.lastSetBounds);
        expect(
          DesktopWindowBoundsPersistence.isTitleBarReachable(
            store.state!.normalBounds!,
            const [Rect.fromLTWH(0, 0, 1920, 1040)],
          ),
          isTrue,
        );
      },
    );
  });

  group('DesktopWindowBoundsPersistence state saving', () {
    test('saves normal bounds and restores them before maximizing', () async {
      final store = _FakeDesktopWindowBoundsStore();
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(-1000, 80, 800, 600),
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(-1440, 0, 1440, 860),
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.saveNow();
      store.state = DesktopWindowBoundsState(
        normalBounds: store.state!.normalBounds,
        maximized: true,
      );

      await persistence.restore();

      expect(window.lastSetBounds, const Rect.fromLTWH(-1000, 80, 800, 600));
      expect(window.maximizeCount, 1);
    });

    test('does not overwrite normal bounds while maximized', () async {
      final store = _FakeDesktopWindowBoundsStore(
        DesktopWindowBoundsState(
          normalBounds: const Rect.fromLTWH(200, 120, 900, 700),
          maximized: false,
        ),
      );
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        maximized: true,
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.saveNow();

      expect(
        store.state!.normalBounds,
        const Rect.fromLTWH(200, 120, 900, 700),
      );
      expect(store.state!.maximized, isTrue);
    });

    test('does not overwrite saved bounds while minimized', () async {
      final store = _FakeDesktopWindowBoundsStore(
        DesktopWindowBoundsState(
          normalBounds: const Rect.fromLTWH(200, 120, 900, 700),
          maximized: false,
        ),
      );
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(40, 40, 400, 320),
        minimized: true,
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.saveNow();

      expect(
        store.state!.normalBounds,
        const Rect.fromLTWH(200, 120, 900, 700),
      );
      expect(store.state!.maximized, isFalse);
    });

    test('preserves saved bounds while fullscreen', () async {
      final store = _FakeDesktopWindowBoundsStore(
        DesktopWindowBoundsState(
          normalBounds: const Rect.fromLTWH(200, 120, 900, 700),
          maximized: true,
        ),
      );
      final window = _FakeDesktopWindowAdapter(
        bounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        maximized: true,
        fullScreen: true,
      );
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      await persistence.saveNow();

      expect(
        store.state!.normalBounds,
        const Rect.fromLTWH(200, 120, 900, 700),
      );
      expect(store.state!.maximized, isFalse);
    });
  });

  group('DesktopWindowBoundsPersistence listener wiring', () {
    const strandedBounds = Rect.fromLTWH(5000, 5000, 800, 600);
    const display = Rect.fromLTWH(0, 0, 1920, 1040);

    (
      _FakeDesktopWindowBoundsStore,
      _FakeDesktopWindowAdapter,
      DesktopWindowBoundsPersistence,
    )
    buildStranded() {
      final store = _FakeDesktopWindowBoundsStore();
      final window = _FakeDesktopWindowAdapter(bounds: strandedBounds);
      final persistence = DesktopWindowBoundsPersistence(
        store: store,
        window: window,
        displayBoundsProvider: () async => const [display],
      );
      return (store, window, persistence);
    }

    test('onWindowMoved saves immediately and repairs reachability', () async {
      final (store, window, persistence) = buildStranded();

      persistence.onWindowMoved();
      await pumpEventQueue();

      // saveNow ran without waiting for the move debounce.
      expect(store.state, isNotNull);
      // ensureWindowReachable pulled the stranded window back into reach.
      expect(window.lastSetBounds, isNotNull);
      expect(
        DesktopWindowBoundsPersistence.isTitleBarReachable(
          window.lastSetBounds!,
          const [display],
        ),
        isTrue,
      );
    });

    test(
      'onWindowMoved cancels a stale debounce before delayed repair',
      () async {
        final store = _FakeDesktopWindowBoundsStore();
        final displays = Completer<List<Rect>>();
        final window = _FakeDesktopWindowAdapter(bounds: strandedBounds);
        final persistence = DesktopWindowBoundsPersistence(
          store: store,
          window: window,
          displayBoundsProvider: () => displays.future,
          saveDebounce: Duration.zero,
        );

        persistence.onWindowMove();
        persistence.onWindowMoved();
        await Future<void>.delayed(Duration.zero);
        expect(store.state, isNull);

        displays.complete(const [display]);
        await pumpEventQueue();

        expect(store.state!.normalBounds, window.lastSetBounds);
        expect(
          DesktopWindowBoundsPersistence.isTitleBarReachable(
            store.state!.normalBounds!,
            const [display],
          ),
          isTrue,
        );
      },
    );

    test(
      'onWindowResized saves immediately and repairs reachability',
      () async {
        final (store, window, persistence) = buildStranded();

        persistence.onWindowResized();
        await pumpEventQueue();

        expect(store.state, isNotNull);
        expect(window.lastSetBounds, isNotNull);
        expect(
          DesktopWindowBoundsPersistence.isTitleBarReachable(
            window.lastSetBounds!,
            const [display],
          ),
          isTrue,
        );
      },
    );

    test('onScreenEvent repairs only after the 600ms settle debounce', () {
      fakeAsync((async) {
        final (_, window, persistence) = buildStranded();

        persistence.onScreenEvent('display-changed');
        async
          ..elapse(const Duration(milliseconds: 599))
          ..flushMicrotasks();
        expect(window.lastSetBounds, isNull);

        async
          ..elapse(const Duration(milliseconds: 2))
          ..flushMicrotasks();
        expect(window.lastSetBounds, isNotNull);
        expect(
          DesktopWindowBoundsPersistence.isTitleBarReachable(
            window.lastSetBounds!,
            const [display],
          ),
          isTrue,
        );
      });
    });

    test('a second screen event inside the debounce restarts it', () {
      fakeAsync((async) {
        final (_, window, persistence) = buildStranded();

        persistence.onScreenEvent('display-changed');
        async.elapse(const Duration(milliseconds: 400));
        persistence.onScreenEvent('display-changed');

        // The first timer would have fired by now; the restart holds it.
        async
          ..elapse(const Duration(milliseconds: 400))
          ..flushMicrotasks();
        expect(window.lastSetBounds, isNull);

        async
          ..elapse(const Duration(milliseconds: 201))
          ..flushMicrotasks();
        expect(window.lastSetBounds, isNotNull);
      });
    });

    test('a reachable window is left untouched by the screen-event repair', () {
      fakeAsync((async) {
        final window = _FakeDesktopWindowAdapter(
          bounds: const Rect.fromLTWH(120, 80, 900, 700),
        );
        final persistence = DesktopWindowBoundsPersistence(
          store: _FakeDesktopWindowBoundsStore(),
          window: window,
          displayBoundsProvider: () async => const [display],
        );

        persistence.onScreenEvent('display-changed');
        async
          ..elapse(const Duration(milliseconds: 601))
          ..flushMicrotasks();

        expect(window.lastSetBounds, isNull);
      });
    });
  });
}

class _FakeDesktopWindowBoundsStore implements DesktopWindowBoundsStore {
  _FakeDesktopWindowBoundsStore([this.state]);

  DesktopWindowBoundsState? state;

  @override
  Future<DesktopWindowBoundsState?> load() async {
    return state;
  }

  @override
  Future<void> save(DesktopWindowBoundsState state) async {
    this.state = state;
  }
}

class _FakeDesktopWindowAdapter implements DesktopWindowAdapter {
  _FakeDesktopWindowAdapter({
    required this.bounds,
    this.minimized = false,
    this.maximized = false,
    this.fullScreen = false,
  });

  Rect bounds;
  Rect? lastSetBounds;
  bool minimized;
  bool maximized;
  bool fullScreen;
  int maximizeCount = 0;

  @override
  Future<Rect> getBounds() async {
    return bounds;
  }

  @override
  Future<void> setBounds(Rect bounds) async {
    lastSetBounds = bounds;
    this.bounds = bounds;
  }

  @override
  Future<bool> isMinimized() async {
    return minimized;
  }

  @override
  Future<bool> isMaximized() async {
    return maximized;
  }

  @override
  Future<bool> isFullScreen() async {
    return fullScreen;
  }

  @override
  Future<void> maximize() async {
    maximized = true;
    maximizeCount += 1;
  }
}
