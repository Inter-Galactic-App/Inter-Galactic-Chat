import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowBoundsPersistence extends WindowListener {
  DesktopWindowBoundsPersistence({
    DesktopWindowBoundsStore? store,
    DesktopWindowAdapter? window,
    Future<List<Rect>> Function()? displayBoundsProvider,
    Duration saveDebounce = const Duration(milliseconds: 350),
  })  : _store = store ?? SharedPreferencesDesktopWindowBoundsStore(),
        _window = window ?? WindowManagerDesktopWindowAdapter(),
        _displayBoundsProvider =
            displayBoundsProvider ?? _getVisibleDisplayBounds,
        _saveDebounce = saveDebounce;

  static const Size minimumRestoredSize = Size(360, 320);
  static const Size minimumVisibleSize = Size(80, 80);

  final DesktopWindowBoundsStore _store;
  final DesktopWindowAdapter _window;
  final Future<List<Rect>> Function() _displayBoundsProvider;
  final Duration _saveDebounce;

  Timer? _pendingSave;
  bool _restoring = false;
  bool _saving = false;
  DesktopWindowBoundsState? _lastState;

  Future<void> restore() async {
    _restoring = true;
    try {
      final state = await _store.load();
      if (state == null) {
        return;
      }

      _lastState = state;

      final normalBounds = state.normalBounds;
      if (normalBounds != null) {
        final restorableBounds = resolveRestorableBounds(
          storedBounds: normalBounds,
          visibleDisplayBounds: await _displayBoundsProvider(),
        );
        if (restorableBounds != null) {
          await _window.setBounds(restorableBounds);
        }
      }

      if (state.maximized) {
        await _window.maximize();
      }
    } finally {
      _restoring = false;
    }
  }

  Future<void> saveNow() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    await _saveCurrentState();
  }

  @override
  void onWindowMove() {
    _scheduleSave();
  }

  @override
  void onWindowResize() {
    _scheduleSave();
  }

  @override
  void onWindowMoved() {
    unawaited(saveNow());
  }

  @override
  void onWindowResized() {
    unawaited(saveNow());
  }

  @override
  void onWindowMaximize() {
    unawaited(_saveMaximizedState(true));
  }

  @override
  void onWindowUnmaximize() {
    _scheduleSave();
  }

  @override
  void onWindowMinimize() {
    _pendingSave?.cancel();
    _pendingSave = null;
  }

  @override
  void onWindowRestore() {
    _scheduleSave();
  }

  @override
  void onWindowEnterFullScreen() {
    _pendingSave?.cancel();
    _pendingSave = null;
  }

  @override
  void onWindowLeaveFullScreen() {
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_restoring) {
      return;
    }

    _pendingSave?.cancel();
    _pendingSave = Timer(_saveDebounce, () {
      unawaited(saveNow());
    });
  }

  Future<void> _saveCurrentState() async {
    if (_restoring || _saving) {
      return;
    }

    _saving = true;
    try {
      if (await _window.isMinimized()) {
        return;
      }

      final isFullScreen = await _window.isFullScreen();
      final isMaximized = await _window.isMaximized();
      final previous = _lastState ?? await _store.load();
      Rect? normalBounds;

      if (!isFullScreen && !isMaximized) {
        final bounds = await _window.getBounds();
        normalBounds = _normalizeStoredBounds(bounds);
      }

      final next = DesktopWindowBoundsState(
        normalBounds: normalBounds ?? previous?.normalBounds,
        maximized: isMaximized && !isFullScreen,
      );
      await _store.save(next);
      _lastState = next;
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveMaximizedState(bool maximized) async {
    if (_restoring) {
      return;
    }

    _pendingSave?.cancel();
    _pendingSave = null;
    final previous = _lastState ?? await _store.load();
    final next = DesktopWindowBoundsState(
      normalBounds: previous?.normalBounds,
      maximized: maximized,
    );
    await _store.save(next);
    _lastState = next;
  }

  static Rect? resolveRestorableBounds({
    required Rect storedBounds,
    required List<Rect> visibleDisplayBounds,
  }) {
    final normalized = _normalizeStoredBounds(storedBounds);
    if (normalized == null) {
      return null;
    }

    if (visibleDisplayBounds.isEmpty) {
      return normalized;
    }

    Rect? bestDisplay;
    var bestArea = 0.0;

    for (final display in visibleDisplayBounds) {
      final intersection = normalized.intersect(display);
      final area = _visibleArea(intersection);
      if (area > bestArea) {
        bestArea = area;
        bestDisplay = display;
      }
    }

    if (bestDisplay == null || bestArea <= 0) {
      return null;
    }

    final visibleIntersection = normalized.intersect(bestDisplay);
    if (visibleIntersection.width >= minimumVisibleSize.width &&
        visibleIntersection.height >= minimumVisibleSize.height) {
      return normalized;
    }

    return _nudgeIntoDisplay(normalized, bestDisplay);
  }

  static Rect? _normalizeStoredBounds(Rect bounds) {
    if (!_isFinite(bounds.left) ||
        !_isFinite(bounds.top) ||
        !_isFinite(bounds.width) ||
        !_isFinite(bounds.height) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }

    final width = bounds.width < minimumRestoredSize.width
        ? minimumRestoredSize.width
        : bounds.width;
    final height = bounds.height < minimumRestoredSize.height
        ? minimumRestoredSize.height
        : bounds.height;
    return Rect.fromLTWH(bounds.left, bounds.top, width, height);
  }

  static Rect _nudgeIntoDisplay(Rect bounds, Rect display) {
    final left = _clampDouble(
      bounds.left,
      display.left - bounds.width + minimumVisibleSize.width,
      display.right - minimumVisibleSize.width,
    );
    final top = _clampDouble(
      bounds.top,
      display.top - bounds.height + minimumVisibleSize.height,
      display.bottom - minimumVisibleSize.height,
    );
    return Rect.fromLTWH(left, top, bounds.width, bounds.height);
  }

  static double _visibleArea(Rect rect) {
    if (rect.width <= 0 || rect.height <= 0) {
      return 0;
    }
    return rect.width * rect.height;
  }

  static bool _isFinite(double value) {
    return !value.isNaN && value.isFinite;
  }

  static double _clampDouble(double value, double min, double max) {
    if (min > max) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  static Future<List<Rect>> _getVisibleDisplayBounds() async {
    final displays = await screenRetriever.getAllDisplays();
    return displays.map(_displayToVisibleBounds).toList();
  }

  static Rect _displayToVisibleBounds(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return position & size;
  }
}

class DesktopWindowBoundsState {
  const DesktopWindowBoundsState({
    required this.normalBounds,
    required this.maximized,
  });

  final Rect? normalBounds;
  final bool maximized;
}

abstract class DesktopWindowBoundsStore {
  Future<DesktopWindowBoundsState?> load();

  Future<void> save(DesktopWindowBoundsState state);
}

class SharedPreferencesDesktopWindowBoundsStore
    implements DesktopWindowBoundsStore {
  static const String _hasBoundsKey = 'desktop_window_bounds.v1.has_bounds';
  static const String _xKey = 'desktop_window_bounds.v1.x';
  static const String _yKey = 'desktop_window_bounds.v1.y';
  static const String _widthKey = 'desktop_window_bounds.v1.width';
  static const String _heightKey = 'desktop_window_bounds.v1.height';
  static const String _maximizedKey = 'desktop_window_bounds.v1.maximized';

  @override
  Future<DesktopWindowBoundsState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasBounds = prefs.getBool(_hasBoundsKey) == true;
    final maximized = prefs.getBool(_maximizedKey) == true;

    if (!hasBounds && !maximized) {
      return null;
    }

    Rect? normalBounds;
    if (hasBounds) {
      final x = prefs.getDouble(_xKey);
      final y = prefs.getDouble(_yKey);
      final width = prefs.getDouble(_widthKey);
      final height = prefs.getDouble(_heightKey);
      if (x != null && y != null && width != null && height != null) {
        normalBounds = Rect.fromLTWH(x, y, width, height);
      }
    }

    return DesktopWindowBoundsState(
      normalBounds: normalBounds,
      maximized: maximized,
    );
  }

  @override
  Future<void> save(DesktopWindowBoundsState state) async {
    final prefs = await SharedPreferences.getInstance();
    final normalBounds = state.normalBounds;

    if (normalBounds == null) {
      await prefs.setBool(_hasBoundsKey, false);
      await Future.wait([
        prefs.remove(_xKey),
        prefs.remove(_yKey),
        prefs.remove(_widthKey),
        prefs.remove(_heightKey),
      ]);
    } else {
      await Future.wait([
        prefs.setBool(_hasBoundsKey, true),
        prefs.setDouble(_xKey, normalBounds.left),
        prefs.setDouble(_yKey, normalBounds.top),
        prefs.setDouble(_widthKey, normalBounds.width),
        prefs.setDouble(_heightKey, normalBounds.height),
      ]);
    }

    await prefs.setBool(_maximizedKey, state.maximized);
  }
}

abstract class DesktopWindowAdapter {
  Future<Rect> getBounds();

  Future<void> setBounds(Rect bounds);

  Future<bool> isMinimized();

  Future<bool> isMaximized();

  Future<bool> isFullScreen();

  Future<void> maximize();
}

class WindowManagerDesktopWindowAdapter implements DesktopWindowAdapter {
  @override
  Future<Rect> getBounds() {
    return windowManager.getBounds();
  }

  @override
  Future<void> setBounds(Rect bounds) {
    return windowManager.setBounds(bounds);
  }

  @override
  Future<bool> isMinimized() {
    return windowManager.isMinimized();
  }

  @override
  Future<bool> isMaximized() {
    return windowManager.isMaximized();
  }

  @override
  Future<bool> isFullScreen() {
    return windowManager.isFullScreen();
  }

  @override
  Future<void> maximize() {
    return windowManager.maximize();
  }
}
