import 'dart:ffi';

import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/hotkey_display.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';
// ignore: implementation_imports
import 'package:uni_platform/src/extensions/keyboard_key.dart';

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 virtualKeyCode);
typedef _GetAsyncKeyStateDart = int Function(int virtualKeyCode);

class DefaultHotkeyPollingReader {
  _GetAsyncKeyStateDart? _getAsyncKeyState;

  bool get isSupported => PlatformUtils.isWindows;

  bool canRead(HotKey hotKey) {
    return canReadBinding(ShortcutBinding.keyboard(hotKey));
  }

  bool canReadBinding(ShortcutBinding binding) {
    if (!isSupported) {
      return false;
    }
    final keyCode = _virtualKeyCodeForBinding(binding);
    if (keyCode == null) {
      return false;
    }
    return binding.modifiers.every(
      (modifier) => _modifierVirtualKeys(modifier).isNotEmpty,
    );
  }

  bool isPressed(HotKey hotKey) {
    return isBindingPressed(ShortcutBinding.keyboard(hotKey));
  }

  bool isBindingPressed(ShortcutBinding binding) {
    if (!isSupported) {
      return false;
    }

    final keyCode = _virtualKeyCodeForBinding(binding);
    if (keyCode == null || !_isVirtualKeyPressed(keyCode)) {
      return false;
    }

    for (final modifier in binding.modifiers) {
      if (!_isModifierPressed(modifier)) {
        return false;
      }
    }

    return true;
  }

  int? _virtualKeyCodeForBinding(ShortcutBinding binding) {
    return switch (binding.type) {
      ShortcutBindingType.keyboard => _virtualKeyCodeFor(binding.hotKey!),
      ShortcutBindingType.mouseButton =>
        ShortcutBinding.windowsVirtualKeyCodeForMouseButton(
          binding.mouseButton!,
        ),
    };
  }

  int? _virtualKeyCodeFor(HotKey hotKey) {
    try {
      final physicalKey = hotKey.physicalKey;
      return physicalKey.keyCode ??
          HotKeyDisplay.windowsVirtualKeyCodeForPhysicalKey(physicalKey);
    } catch (_) {
      return null;
    }
  }

  bool _isModifierPressed(HotKeyModifier modifier) {
    final virtualKeys = _modifierVirtualKeys(modifier);

    if (virtualKeys.isEmpty) {
      return false;
    }

    return virtualKeys.any(_isVirtualKeyPressed);
  }

  List<int> _modifierVirtualKeys(HotKeyModifier modifier) {
    return switch (modifier) {
      HotKeyModifier.alt => const [0x12],
      HotKeyModifier.capsLock => const [0x14],
      HotKeyModifier.control => const [0x11],
      HotKeyModifier.fn => const <int>[],
      HotKeyModifier.meta => const [0x5B, 0x5C],
      HotKeyModifier.shift => const [0x10],
    };
  }

  bool _isVirtualKeyPressed(int virtualKeyCode) {
    try {
      final state = _nativeGetAsyncKeyState(virtualKeyCode);
      return (state & 0x8000) != 0;
    } catch (_) {
      return false;
    }
  }

  _GetAsyncKeyStateDart get _nativeGetAsyncKeyState {
    return _getAsyncKeyState ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
          'GetAsyncKeyState',
        );
  }
}

typedef DefaultPushToTalkHotkeyReader = DefaultHotkeyPollingReader;
