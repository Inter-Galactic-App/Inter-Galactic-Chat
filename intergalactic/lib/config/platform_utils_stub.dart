import 'package:flutter/foundation.dart';

class PlatformUtils {
  static bool get isLinux => false;

  static bool get isWindows => false;

  static bool get isAndroid => false;

  static bool get isIOS => false;

  static bool get isWeb => kIsWeb;

  static String get displayServer => 'unknown';

  static String? get desktopEnvironment => null;

  static bool isDesktopEnvironment(DesktopEnvironment desktopEnvironment) {
    return false;
  }

  static bool isDisplayServer(DisplayServer server) {
    return false;
  }
}

enum DisplayServer {
  Wayland,
  X11,
}

enum DesktopEnvironment {
  KDEPlasma,
  GNOME,
}
