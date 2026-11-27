import 'package:window_manager/window_manager.dart';

Future<bool> isDesktopWindowFocused() {
  return windowManager.isFocused();
}

