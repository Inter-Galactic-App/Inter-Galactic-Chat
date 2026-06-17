import 'dart:async';

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts_linux.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart';

class SystemWideShortcuts {
  static void init() async {
    await reloadNavigationShortcuts();

    if (PlatformUtils.isLinux) {
      SystemWideShortcutsLinux.init();
    }

    for (var shortcut in registeredShortcuts.entries) {
      var hotkey = preferences.getSystemHotkey(shortcut.key);
      if (hotkey != null) {
        await shortcut.value.setHotkey(hotkey);
      }
    }
  }

  static bool get isSupported {
    if (PlatformUtils.isWindows) return true;

    if (PlatformUtils.isDisplayServer(DisplayServer.X11)) {
      return true;
    }

    if (PlatformUtils.isDesktopEnvironment(DesktopEnvironment.KDEPlasma)) {
      return true;
    }

    return false;
  }

  static String get shortcutNameMute => Intl.message(
        "Mute",
        name: "shortcutNameMute",
        desc: "name for the system wide shortcut to activate microphone mute",
      );

  static String get shortcutNameUnmute => Intl.message(
        "Unmute",
        name: "shortcutNameUnmute",
        desc: "name for the system wide shortcut to disable microphone mute",
      );

  static String get shortcutNameToggleMute => Intl.message(
        "Toggle Mute",
        name: "shortcutNameToggleMute",
        desc:
            "name for the system wide shortcut to toggle the microphone mute status",
      );

  static String get shortcutNamePushToTalk => Intl.message(
        "Push to Talk",
        name: "shortcutNamePushToTalk",
        desc: "name for the hold-to-talk microphone shortcut",
      );

  static String get shortcutNameToggleDesktopCompanion => Intl.message(
        "Toggle Desktop Companion",
        name: "shortcutNameToggleDesktopCompanion",
        desc:
            "name for the system wide shortcut to toggle the desktop notification companion",
      );

  static String get shortcutNameWrapComposerSelectionInBrackets => Intl.message(
        "Wrap Selection in Brackets",
        name: "shortcutNameWrapComposerSelectionInBrackets",
        desc:
            "name for the system wide shortcut to wrap selected composer text in brackets",
      );

  static Map<String, AppShortcut> shortcuts = {
    "mute": AppShortcut(
      getDisplayName: () => shortcutNameMute,
      callback: () => clientManager?.callManager.mute(),
    ),
    "unmute": AppShortcut(
      getDisplayName: () => shortcutNameUnmute,
      callback: () => clientManager?.callManager.unmute(),
    ),
    "toggle_mute": AppShortcut(
      getDisplayName: () => shortcutNameToggleMute,
      callback: () => clientManager?.callManager.toggleMute(),
    ),
    "push_to_talk": AppShortcut(
      getDisplayName: () => shortcutNamePushToTalk,
      callback: () => clientManager?.callManager.pushToTalkStart(),
      keyUpCallback: () => clientManager?.callManager.pushToTalkEnd(),
    ),
    if (PlatformUtils.isWindows)
      "toggle_desktop_companion": AppShortcut(
        getDisplayName: () => shortcutNameToggleDesktopCompanion,
        callback: () {
          unawaited(
            preferences.notificationCompanionEnabled.set(
              !preferences.notificationCompanionEnabled.value,
            ),
          );
        },
      ),
    if (BuildConfig.DESKTOP)
      "wrap_composer_selection_in_brackets": AppShortcut(
        getDisplayName: () => shortcutNameWrapComposerSelectionInBrackets,
        callback: () {
          EventBus.wrapComposerSelectionInBrackets.add(null);
        },
      ),
  };

  static final Map<String, AppShortcut> customShortcuts = {};

  static List<NavigationShortcutDefinition> customNavigationShortcuts = [];

  static Map<String, AppShortcut> get registeredShortcuts => {
        ...shortcuts,
        ...customShortcuts,
      };

  static Future<void> reloadNavigationShortcuts() async {
    final definitions = preferences
        .getCustomNavigationShortcuts()
        .map(NavigationShortcutDefinition.fromJson)
        .whereType<NavigationShortcutDefinition>()
        .toList(growable: false);
    await _applyNavigationShortcutDefinitions(definitions);
    await _restoreNavigationShortcutHotkeys(definitions);
  }

  static Future<void> saveNavigationShortcut(
    NavigationShortcutDefinition definition, {
    HotKey? hotkey,
    bool clearHotkey = false,
  }) async {
    final definitions = List<NavigationShortcutDefinition>.from(
      customNavigationShortcuts,
    );
    final existingIndex = definitions.indexWhere(
      (entry) => entry.id == definition.id,
    );
    final existingDefinition =
        existingIndex == -1 ? null : definitions[existingIndex];
    final existingShortcutHotkey =
        customShortcuts[definition.shortcutKey]?.hotkey;
    final effectiveHotkey = clearHotkey
        ? null
        : hotkey ?? existingShortcutHotkey ?? existingDefinition?.hotkey;
    final definitionToStore = definition.copyWith(hotkey: effectiveHotkey);
    if (existingIndex == -1) {
      definitions.add(definitionToStore);
    } else {
      definitions[existingIndex] = definitionToStore;
    }

    final previousDefinitions = customNavigationShortcuts;
    await _applyNavigationShortcutDefinitions(definitions);

    final shortcut = customShortcuts[definition.shortcutKey];
    if (shortcut == null) {
      return;
    }

    try {
      if (clearHotkey) {
        await shortcut.clearHotkey();
      } else if (hotkey != null) {
        await shortcut.setHotkey(hotkey);
      } else if (shortcut.hotkey == null && effectiveHotkey != null) {
        await shortcut.setHotkey(effectiveHotkey);
      } else {
        await storeHotkeys();
      }
      await preferences.setCustomNavigationShortcuts(
        definitions.map((entry) => entry.toJson()).toList(growable: false),
      );
    } catch (_) {
      await _applyNavigationShortcutDefinitions(previousDefinitions);
      rethrow;
    }
  }

  static Future<void> removeNavigationShortcut(
    NavigationShortcutDefinition definition,
  ) async {
    final shortcut = customShortcuts[definition.shortcutKey];
    await shortcut?.clearHotkey();

    final definitions = customNavigationShortcuts
        .where((entry) => entry.id != definition.id)
        .toList(growable: false);
    await preferences.setCustomNavigationShortcuts(
      definitions.map((entry) => entry.toJson()).toList(growable: false),
    );
    await _applyNavigationShortcutDefinitions(definitions);
  }

  static Future<void> _applyNavigationShortcutDefinitions(
    List<NavigationShortcutDefinition> definitions,
  ) async {
    final nextKeys = definitions.map((entry) => entry.shortcutKey).toSet();

    for (final entry in customShortcuts.entries.toList(growable: false)) {
      if (!nextKeys.contains(entry.key)) {
        await entry.value.clearHotkey();
      }
    }

    final nextShortcuts = <String, AppShortcut>{};
    for (final definition in definitions) {
      final existing = customShortcuts[definition.shortcutKey];
      if (existing != null) {
        existing.getDisplayName = () => definition.displayLabel;
        existing.callback = () => _openNavigationShortcut(definition);
        nextShortcuts[definition.shortcutKey] = existing;
      } else {
        nextShortcuts[definition.shortcutKey] = AppShortcut(
          getDisplayName: () => definition.displayLabel,
          callback: () => _openNavigationShortcut(definition),
        );
      }
    }

    customNavigationShortcuts = definitions;
    customShortcuts
      ..clear()
      ..addAll(nextShortcuts);
  }

  static Future<void> _restoreNavigationShortcutHotkeys(
    List<NavigationShortcutDefinition> definitions,
  ) async {
    for (final definition in definitions) {
      final shortcut = customShortcuts[definition.shortcutKey];
      if (shortcut == null || shortcut.hotkey != null) {
        continue;
      }

      final hotkey = preferences.getSystemHotkey(definition.shortcutKey) ??
          definition.hotkey;
      if (hotkey == null) {
        continue;
      }

      try {
        await shortcut.setHotkey(hotkey);
      } catch (_) {
        await preferences.setSystemHotkey(definition.shortcutKey, null);
      }
    }
  }

  static void _openNavigationShortcut(NavigationShortcutDefinition definition) {
    final target = (definition.targetAddress, definition.clientId);

    switch (definition.targetType) {
      case NavigationShortcutTargetType.room:
        EventBus.openRoomFromShortcut(target);
        break;
      case NavigationShortcutTargetType.space:
        EventBus.openSpaceFromShortcut(target);
        break;
    }
  }

  static Future<void> storeHotkeys() async {
    for (var i in registeredShortcuts.entries) {
      await preferences.setSystemHotkey(i.key, i.value.hotkey);
    }
  }
}

class AppShortcut {
  void Function() callback;
  void Function()? keyUpCallback;

  String Function() getDisplayName;

  HotKey? hotkey;

  AppShortcut({
    required this.getDisplayName,
    required this.callback,
    this.keyUpCallback,
  });

  Future<void> setHotkey(HotKey newHotkey) async {
    if (hotkey == newHotkey) {
      await SystemWideShortcuts.storeHotkeys();
      return;
    }

    final oldHotkey = hotkey;

    if (hotkey != null) {
      await hotKeyManager.unregister(hotkey!);
      hotkey = null;
    }

    for (var key in SystemWideShortcuts.registeredShortcuts.values) {
      if (identical(key, this)) {
        continue;
      }

      if (key.hotkey == newHotkey) {
        await key.clearHotkey();
      }
    }

    try {
      await _registerHotkey(newHotkey);
      hotkey = newHotkey;
      await SystemWideShortcuts.storeHotkeys();
    } catch (_) {
      if (oldHotkey != null) {
        try {
          await _registerHotkey(oldHotkey);
          hotkey = oldHotkey;
        } catch (_) {
          hotkey = null;
        }
      }

      await SystemWideShortcuts.storeHotkeys();
      rethrow;
    }
  }

  Future<void> _registerHotkey(HotKey value) async {
    await hotKeyManager.register(
      value,
      keyDownHandler: (hotKey) {
        callback();
      },
      keyUpHandler: keyUpCallback == null
          ? null
          : (hotKey) {
              keyUpCallback!();
            },
    );
  }

  Future<void> clearHotkey() async {
    if (hotkey != null) {
      await hotKeyManager.unregister(hotkey!);
      hotkey = null;
    }

    await SystemWideShortcuts.storeHotkeys();
  }
}
