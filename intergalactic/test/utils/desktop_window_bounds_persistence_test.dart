import 'dart:ui';

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
    });

    test('drops bounds when the saved monitor is no longer present', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(2600, 100, 900, 700),
        visibleDisplayBounds: const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      expect(restored, isNull);
    });

    test('nudges mostly hidden bounds back onto the visible display', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(1880, 100, 900, 700),
        visibleDisplayBounds: const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      expect(restored, const Rect.fromLTWH(1840, 100, 900, 700));
    });

    test('preserves deliberately partially visible windows', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(1760, 100, 900, 700),
        visibleDisplayBounds: const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      expect(restored, const Rect.fromLTWH(1760, 100, 900, 700));
    });

    test('clamps tiny saved sizes to a restorable desktop size', () {
      final restored = DesktopWindowBoundsPersistence.resolveRestorableBounds(
        storedBounds: const Rect.fromLTWH(200, 100, 120, 90),
        visibleDisplayBounds: const [
          Rect.fromLTWH(0, 0, 1920, 1040),
        ],
      );

      expect(restored, const Rect.fromLTWH(200, 100, 360, 320));
    });
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
