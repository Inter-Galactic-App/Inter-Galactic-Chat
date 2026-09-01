import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';

class DefaultHotkeyPollingReader {
  bool get isSupported => false;

  bool canRead(HotKey hotKey) => false;

  bool canReadBinding(ShortcutBinding binding) => false;

  bool isPressed(HotKey hotKey) => false;

  bool isBindingPressed(ShortcutBinding binding) => false;
}

typedef DefaultPushToTalkHotkeyReader = DefaultHotkeyPollingReader;
