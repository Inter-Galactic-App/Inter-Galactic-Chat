import 'dart:io';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/desktop_window_bounds_persistence.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagement {
  static bool _isTogglingFullscreen = false;

  static Future<void> prepareDesktopChrome() async {
    if (!BuildConfig.DESKTOP || !PlatformUtils.isWindows) return;

    await windowManager.ensureInitialized();
    await _applyCustomWindowsChrome();
  }

  static Future<void> init() async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) return;

    if (PlatformUtils.isLinux) {
      await windowManager.ensureInitialized();
    }
    await prepareDesktopChrome();
    final boundsPersistence = DesktopWindowBoundsPersistence();
    _WindowListener listener = _WindowListener(boundsPersistence);

    await windowManager.setPreventClose(true);
    windowManager.addListener(boundsPersistence);
    windowManager.addListener(listener);
    await windowManager.waitUntilReadyToShow();
    try {
      await boundsPersistence.restore();
    } catch (_) {}

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    EventBus.onSelectedRoomChanged.stream.listen(_onSelectedRoomChanged);
    EventBus.onSelectedSpaceChanged.stream.listen(_onSelectedSpaceChanged);

    if (commandLineArgs.contains("--minimize")) {
      await windowManager.minimize();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  static bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    return false;
  }

  static Future<void> _toggleFullscreen() async {
    final isFullScreen = await WindowManagement.isFullScreen();
    await WindowManagement.setFullScreen(!isFullScreen);
  }

  static Future<bool> isFullScreen() async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) {
      return false;
    }

    return windowManager.isFullScreen();
  }

  static Future<void> setFullScreen(bool value) async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) {
      return;
    }

    if (_isTogglingFullscreen) {
      return;
    }

    _isTogglingFullscreen = true;
    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (isFullScreen == value) {
        return;
      }

      if (!value) {
        await windowManager.setFullScreen(false);
        if (PlatformUtils.isWindows) {
          try {
            await _applyCustomWindowsChrome();
          } catch (_) {
            await windowManager.setFullScreen(true);
            rethrow;
          }
        }
        return;
      }

      await windowManager.setFullScreen(true);
      if (PlatformUtils.isWindows) {
        try {
          await _applyCustomWindowsChrome();
        } catch (_) {
          await windowManager.setFullScreen(false);
          await _applyCustomWindowsChrome();
          rethrow;
        }
      }
    } finally {
      _isTogglingFullscreen = false;
    }
  }

  static String? _currentSpaceName;
  static String? _currentRoomName;

  static void _onSelectedRoomChanged(Room? event) {
    _currentRoomName = event?.displayName;
    _updateTitle();
  }

  static void _onSelectedSpaceChanged(Space? event) {
    _currentSpaceName = event?.displayName;
    _updateTitle();
  }

  static void _updateTitle() {
    final result = [
      _currentRoomName,
      _currentSpaceName,
      BuildConfig.app,
    ].whereNot((a) => a == null).join(" | ");
    windowManager.setTitle(result);
  }

  static Future<bool> isAlwaysOnTop() async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) {
      return false;
    }

    return windowManager.isAlwaysOnTop();
  }

  static Future<void> setAlwaysOnTop(bool value) async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) {
      return;
    }

    await windowManager.setAlwaysOnTop(value);
  }

  static Future<void> _applyCustomWindowsChrome() async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  }
}

class _WindowListener extends WindowListener {
  _WindowListener(this._boundsPersistence);

  final DesktopWindowBoundsPersistence _boundsPersistence;

  @override
  void onWindowClose() async {
    super.onWindowClose();
    try {
      await _boundsPersistence.saveNow();
    } catch (_) {}

    if (preferences.minimizeOnClose.value) {
      windowManager.minimize();
    } else {
      if (clientManager != null) {
        for (var client in clientManager!.clients) {
          await client.close();
        }
      }

      exit(0);
    }
  }
}
