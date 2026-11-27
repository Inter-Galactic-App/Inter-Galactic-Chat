import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';

class HotKeyDisplay {
  const HotKeyDisplay._();

  static String describe(HotKey hotKey) {
    return [
      for (final modifier in hotKey.modifiers ?? const <HotKeyModifier>[])
        modifierLabel(modifier),
      physicalKeyLabel(safePhysicalKey(hotKey)),
    ].join(' + ');
  }

  static String describeBinding(ShortcutBinding binding) {
    return [
      for (final modifier in binding.modifiers) modifierLabel(modifier),
      switch (binding.type) {
        ShortcutBindingType.keyboard => physicalKeyLabel(
          ShortcutBinding.safePhysicalKey(binding.hotKey!),
        ),
        ShortcutBindingType.mouseButton => ShortcutBinding.mouseButtonLabel(
          binding.mouseButton!,
        ),
      },
    ].join(' + ');
  }

  static bool equivalent(HotKey? first, HotKey? second) {
    return ShortcutBinding.equivalent(
      ShortcutBinding.fromHotKey(first),
      ShortcutBinding.fromHotKey(second),
    );
  }

  static bool equivalentBinding(
    ShortcutBinding? first,
    ShortcutBinding? second,
  ) {
    return ShortcutBinding.equivalent(first, second);
  }

  static String modifierLabel(HotKeyModifier modifier) {
    return switch (modifier) {
      HotKeyModifier.alt => 'Alt',
      HotKeyModifier.capsLock => 'Caps Lock',
      HotKeyModifier.control => 'Ctrl',
      HotKeyModifier.fn => 'Fn',
      HotKeyModifier.meta => 'Meta',
      HotKeyModifier.shift => 'Shift',
    };
  }

  static String physicalKeyLabel(PhysicalKeyboardKey? key) {
    if (key == null) {
      return 'Unsupported key';
    }

    final usage = key.usbHidUsage;
    if (usage >= 0x00070004 && usage <= 0x0007001d) {
      return String.fromCharCode('A'.codeUnitAt(0) + usage - 0x00070004);
    }
    if (usage >= 0x0007001e && usage <= 0x00070026) {
      return '${usage - 0x0007001d}';
    }
    if (usage == 0x00070027) {
      return '0';
    }
    if (usage >= 0x0007003a && usage <= 0x00070045) {
      return 'F${usage - 0x00070039}';
    }
    if (usage >= 0x00070068 && usage <= 0x00070073) {
      return 'F${usage - 0x0007005b}';
    }
    if (usage >= 0x00070059 && usage <= 0x00070061) {
      return 'Numpad ${usage - 0x00070058}';
    }
    if (usage == 0x00070062) {
      return 'Numpad 0';
    }

    return _physicalKeyLabels[key] ??
        'Physical 0x${usage.toRadixString(16).padLeft(8, '0')}';
  }

  static int? windowsVirtualKeyCodeForPhysicalKey(PhysicalKeyboardKey key) {
    final usage = key.usbHidUsage;
    if (usage >= 0x00070004 && usage <= 0x0007001d) {
      return 0x41 + usage - 0x00070004;
    }
    if (usage >= 0x0007001e && usage <= 0x00070026) {
      return 0x31 + usage - 0x0007001e;
    }
    if (usage == 0x00070027) {
      return 0x30;
    }
    if (usage >= 0x0007003a && usage <= 0x00070045) {
      return 0x70 + usage - 0x0007003a;
    }
    if (usage >= 0x00070068 && usage <= 0x00070073) {
      return 0x7c + usage - 0x00070068;
    }
    if (usage >= 0x00070059 && usage <= 0x00070061) {
      return 0x61 + usage - 0x00070059;
    }
    if (usage == 0x00070062) {
      return 0x60;
    }

    return _windowsVirtualKeyCodes[key];
  }

  static PhysicalKeyboardKey? safePhysicalKey(HotKey hotKey) {
    return ShortcutBinding.safePhysicalKey(hotKey);
  }
}

final Map<PhysicalKeyboardKey, String> _physicalKeyLabels = {
  PhysicalKeyboardKey.enter: 'Enter',
  PhysicalKeyboardKey.escape: 'Esc',
  PhysicalKeyboardKey.backspace: 'Backspace',
  PhysicalKeyboardKey.tab: 'Tab',
  PhysicalKeyboardKey.space: 'Space',
  PhysicalKeyboardKey.minus: '-',
  PhysicalKeyboardKey.equal: '=',
  PhysicalKeyboardKey.bracketLeft: '[',
  PhysicalKeyboardKey.bracketRight: ']',
  PhysicalKeyboardKey.backslash: r'\',
  PhysicalKeyboardKey.semicolon: ';',
  PhysicalKeyboardKey.quote: "'",
  PhysicalKeyboardKey.backquote: '`',
  PhysicalKeyboardKey.comma: ',',
  PhysicalKeyboardKey.period: '.',
  PhysicalKeyboardKey.slash: '/',
  PhysicalKeyboardKey.capsLock: 'Caps Lock',
  PhysicalKeyboardKey.printScreen: 'Print Screen',
  PhysicalKeyboardKey.scrollLock: 'Scroll Lock',
  PhysicalKeyboardKey.pause: 'Pause',
  PhysicalKeyboardKey.insert: 'Insert',
  PhysicalKeyboardKey.home: 'Home',
  PhysicalKeyboardKey.pageUp: 'Page Up',
  PhysicalKeyboardKey.delete: 'Delete',
  PhysicalKeyboardKey.end: 'End',
  PhysicalKeyboardKey.pageDown: 'Page Down',
  PhysicalKeyboardKey.arrowRight: 'Arrow Right',
  PhysicalKeyboardKey.arrowLeft: 'Arrow Left',
  PhysicalKeyboardKey.arrowDown: 'Arrow Down',
  PhysicalKeyboardKey.arrowUp: 'Arrow Up',
  PhysicalKeyboardKey.numLock: 'Num Lock',
  PhysicalKeyboardKey.numpadDivide: 'Numpad Divide',
  PhysicalKeyboardKey.numpadMultiply: 'Numpad Multiply',
  PhysicalKeyboardKey.numpadSubtract: 'Numpad Subtract',
  PhysicalKeyboardKey.numpadAdd: 'Numpad Add',
  PhysicalKeyboardKey.numpadEnter: 'Numpad Enter',
  PhysicalKeyboardKey.numpadDecimal: 'Numpad Decimal',
  PhysicalKeyboardKey.numpadEqual: 'Numpad Equal',
  PhysicalKeyboardKey.controlLeft: 'Ctrl',
  PhysicalKeyboardKey.controlRight: 'Ctrl',
  PhysicalKeyboardKey.shiftLeft: 'Shift',
  PhysicalKeyboardKey.shiftRight: 'Shift',
  PhysicalKeyboardKey.altLeft: 'Alt',
  PhysicalKeyboardKey.altRight: 'Alt',
  PhysicalKeyboardKey.metaLeft: 'Meta',
  PhysicalKeyboardKey.metaRight: 'Meta',
  PhysicalKeyboardKey.fn: 'Fn',
};

final Map<PhysicalKeyboardKey, int> _windowsVirtualKeyCodes = {
  PhysicalKeyboardKey.enter: 0x0d,
  PhysicalKeyboardKey.escape: 0x1b,
  PhysicalKeyboardKey.backspace: 0x08,
  PhysicalKeyboardKey.tab: 0x09,
  PhysicalKeyboardKey.space: 0x20,
  PhysicalKeyboardKey.minus: 0xbd,
  PhysicalKeyboardKey.equal: 0xbb,
  PhysicalKeyboardKey.bracketLeft: 0xdb,
  PhysicalKeyboardKey.bracketRight: 0xdd,
  PhysicalKeyboardKey.backslash: 0xdc,
  PhysicalKeyboardKey.semicolon: 0xba,
  PhysicalKeyboardKey.quote: 0xde,
  PhysicalKeyboardKey.backquote: 0xc0,
  PhysicalKeyboardKey.comma: 0xbc,
  PhysicalKeyboardKey.period: 0xbe,
  PhysicalKeyboardKey.slash: 0xbf,
  PhysicalKeyboardKey.capsLock: 0x14,
  PhysicalKeyboardKey.printScreen: 0x2c,
  PhysicalKeyboardKey.scrollLock: 0x91,
  PhysicalKeyboardKey.pause: 0x13,
  PhysicalKeyboardKey.insert: 0x2d,
  PhysicalKeyboardKey.home: 0x24,
  PhysicalKeyboardKey.pageUp: 0x21,
  PhysicalKeyboardKey.delete: 0x2e,
  PhysicalKeyboardKey.end: 0x23,
  PhysicalKeyboardKey.pageDown: 0x22,
  PhysicalKeyboardKey.arrowRight: 0x27,
  PhysicalKeyboardKey.arrowLeft: 0x25,
  PhysicalKeyboardKey.arrowDown: 0x28,
  PhysicalKeyboardKey.arrowUp: 0x26,
  PhysicalKeyboardKey.numLock: 0x90,
  PhysicalKeyboardKey.numpadDivide: 0x6f,
  PhysicalKeyboardKey.numpadMultiply: 0x6a,
  PhysicalKeyboardKey.numpadSubtract: 0x6d,
  PhysicalKeyboardKey.numpadAdd: 0x6b,
  PhysicalKeyboardKey.numpadEnter: 0x0d,
  PhysicalKeyboardKey.numpadDecimal: 0x6e,
  PhysicalKeyboardKey.numpadEqual: 0xbb,
  PhysicalKeyboardKey.controlLeft: 0x11,
  PhysicalKeyboardKey.controlRight: 0x11,
  PhysicalKeyboardKey.shiftLeft: 0x10,
  PhysicalKeyboardKey.shiftRight: 0x10,
  PhysicalKeyboardKey.altLeft: 0x12,
  PhysicalKeyboardKey.altRight: 0x12,
  PhysicalKeyboardKey.metaLeft: 0x5b,
  PhysicalKeyboardKey.metaRight: 0x5c,
};
