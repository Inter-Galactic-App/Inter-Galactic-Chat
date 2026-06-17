import 'dart:io';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagement {
  static bool _isTogglingFullscreen = false;

  static Future<void> init() async {
    if (!(PlatformUtils.isLinux || PlatformUtils.isWindows)) return;

    await windowManager.ensureInitialized();
    _WindowListener listener = _WindowListener();

    windowManager.setPreventClose(true);
    windowManager.addListener(listener);

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    EventBus.onSelectedRoomChanged.stream.listen(_onSelectedRoomChanged);
    EventBus.onSelectedSpaceChanged.stream.listen(_onSelectedSpaceChanged);

    if (commandLineArgs.contains("--minimize")) {
      windowManager.minimize();
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
            await windowManager.setTitleBarStyle(
              TitleBarStyle.normal,
              windowButtonVisibility: true,
            );
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
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: false,
          );
        } catch (_) {
          await windowManager.setFullScreen(false);
          await windowManager.setTitleBarStyle(
            TitleBarStyle.normal,
            windowButtonVisibility: true,
          );
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
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    super.onWindowClose();

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
