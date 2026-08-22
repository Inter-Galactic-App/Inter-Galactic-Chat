import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

enum ShortcutBindingType {
  keyboard,
  mouseButton;

  String get storageValue => switch (this) {
    ShortcutBindingType.keyboard => 'keyboard',
    ShortcutBindingType.mouseButton => 'mouse_button',
  };

  static ShortcutBindingType? fromStorageValue(Object? value) {
    return switch (value) {
      'keyboard' => ShortcutBindingType.keyboard,
      'mouse_button' => ShortcutBindingType.mouseButton,
      _ => null,
    };
  }
}

class ShortcutBinding {
  const ShortcutBinding.keyboard(this.hotKey)
    : type = ShortcutBindingType.keyboard,
      mouseButton = null,
      mouseModifiers = const [],
      mouseScope = HotKeyScope.system,
      mouseIdentifier = null;

  const ShortcutBinding.mouseButton({
    required int button,
    List<HotKeyModifier> modifiers = const [],
    HotKeyScope scope = HotKeyScope.system,
    String? identifier,
  }) : type = ShortcutBindingType.mouseButton,
       hotKey = null,
       mouseButton = button,
       mouseModifiers = modifiers,
       mouseScope = scope,
       mouseIdentifier = identifier;

  final ShortcutBindingType type;
  final HotKey? hotKey;
  final int? mouseButton;
  final List<HotKeyModifier> mouseModifiers;
  final HotKeyScope mouseScope;
  final String? mouseIdentifier;

  bool get isKeyboard => type == ShortcutBindingType.keyboard;
  bool get isMouseButton => type == ShortcutBindingType.mouseButton;

  String? get identifier => switch (type) {
    ShortcutBindingType.keyboard => hotKey?.identifier,
    ShortcutBindingType.mouseButton => mouseIdentifier,
  };

  HotKeyScope get scope => switch (type) {
    ShortcutBindingType.keyboard => hotKey?.scope ?? HotKeyScope.system,
    ShortcutBindingType.mouseButton => mouseScope,
  };

  List<HotKeyModifier> get modifiers => switch (type) {
    ShortcutBindingType.keyboard =>
      hotKey?.modifiers ?? const <HotKeyModifier>[],
    ShortcutBindingType.mouseButton => mouseModifiers,
  };

  Map<String, dynamic> toJson() {
    return switch (type) {
      ShortcutBindingType.keyboard => {
        'type': type.storageValue,
        'hotkey': hotKey!.toJson(),
      },
      ShortcutBindingType.mouseButton => {
        'type': type.storageValue,
        'button': mouseButton,
        'modifiers': mouseModifiers
            .map((modifier) => modifier.name)
            .toList(growable: false),
        'scope': mouseScope.name,
        if (mouseIdentifier != null) 'identifier': mouseIdentifier,
      },
    };
  }

  static ShortcutBinding? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }

    final map = value.cast<String, dynamic>();
    final type = ShortcutBindingType.fromStorageValue(map['type']);
    if (type == null) {
      return _legacyHotKeyFromJson(map);
    }

    try {
      return switch (type) {
        ShortcutBindingType.keyboard => _keyboardFromJson(map['hotkey']),
        ShortcutBindingType.mouseButton => _mouseButtonFromJson(map),
      };
    } catch (_) {
      return null;
    }
  }

  static ShortcutBinding? fromHotKey(HotKey? hotKey) {
    if (hotKey == null) {
      return null;
    }
    return ShortcutBinding.keyboard(hotKey);
  }

  static ShortcutBinding? _legacyHotKeyFromJson(Map<String, dynamic> map) {
    try {
      return ShortcutBinding.keyboard(HotKey.fromJson(map));
    } catch (_) {
      return null;
    }
  }

  static ShortcutBinding? _keyboardFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    return ShortcutBinding.keyboard(
      HotKey.fromJson(value.cast<String, dynamic>()),
    );
  }

  static ShortcutBinding? _mouseButtonFromJson(Map<String, dynamic> map) {
    final button = map['button'];
    if (button is! int || button < 3) {
      return null;
    }

    return ShortcutBinding.mouseButton(
      button: button,
      modifiers: _modifiersFromJson(map['modifiers']),
      scope: _scopeFromJson(map['scope']),
      identifier: map['identifier'] is String
          ? map['identifier'] as String
          : null,
    );
  }

  static List<HotKeyModifier> _modifiersFromJson(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((name) {
          try {
            return HotKeyModifier.values.firstWhere(
              (modifier) => modifier.name == name,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<HotKeyModifier>()
        .toList(growable: false);
  }

  static HotKeyScope _scopeFromJson(Object? value) {
    if (value is! String) {
      return HotKeyScope.system;
    }

    try {
      return HotKeyScope.values.firstWhere((scope) => scope.name == value);
    } catch (_) {
      return HotKeyScope.system;
    }
  }

  static bool equivalent(ShortcutBinding? first, ShortcutBinding? second) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null || first.type != second.type) {
      return false;
    }

    if (first.isKeyboard) {
      return _equivalentHotKeys(first.hotKey, second.hotKey);
    }

    return first.mouseButton == second.mouseButton &&
        _modifierNames(
          first.modifiers,
        ).containsAll(_modifierNames(second.modifiers)) &&
        _modifierNames(first.modifiers).length ==
            _modifierNames(second.modifiers).length &&
        first.scope == second.scope;
  }

  static bool _equivalentHotKeys(HotKey? first, HotKey? second) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null) {
      return false;
    }

    final firstKey = safePhysicalKey(first);
    final secondKey = safePhysicalKey(second);
    if (firstKey?.usbHidUsage != secondKey?.usbHidUsage) {
      return false;
    }

    final firstModifiers = _modifierNames(first.modifiers);
    final secondModifiers = _modifierNames(second.modifiers);
    return firstModifiers.length == secondModifiers.length &&
        firstModifiers.containsAll(secondModifiers) &&
        first.scope == second.scope;
  }

  static Set<String> _modifierNames(List<HotKeyModifier>? modifiers) {
    return (modifiers ?? const <HotKeyModifier>[])
        .map((modifier) => modifier.name)
        .toSet();
  }

  static PhysicalKeyboardKey? safePhysicalKey(HotKey hotKey) {
    try {
      return hotKey.physicalKey;
    } catch (_) {
      final key = hotKey.key;
      return key is PhysicalKeyboardKey ? key : null;
    }
  }

  static int? singleMouseButtonFromButtons(int buttons) {
    int? button;
    for (var candidate = 1; candidate <= 16; candidate++) {
      if ((buttons & nthMouseButton(candidate)) == 0) {
        continue;
      }
      if (button != null) {
        return null;
      }
      button = candidate;
    }

    if (button == null || windowsVirtualKeyCodeForMouseButton(button) == null) {
      return null;
    }
    return button;
  }

  static int? windowsVirtualKeyCodeForMouseButton(int button) {
    return switch (button) {
      3 => 0x04,
      4 => 0x05,
      5 => 0x06,
      _ => null,
    };
  }

  static String mouseButtonLabel(int button) => 'Mouse Button $button';
}
