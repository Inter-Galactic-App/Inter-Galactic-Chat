import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/hotkey_display.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/push_to_talk_hotkey_reader.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts_linux.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart';

class SystemWideShortcuts {
  static const pushToTalkShortcutKey = 'push_to_talk';
  static const _windowsPollingInterval = Duration(milliseconds: 35);

  static final DefaultHotkeyPollingReader _windowsHotkeyPollingReader =
      DefaultHotkeyPollingReader();
  static final Set<AppShortcut> _windowsPressedShortcuts = <AppShortcut>{};
  static final Set<String> _loggedUnreadableWindowsShortcuts = <String>{};
  static Timer? _windowsPollingTimer;
  static bool _loggedWindowsPollingFailure = false;

  /// Whether [init] runs the real Linux D-Bus setup. Production leaves this null
  /// and reads the actual OS. It is a test seam because the OS check below is
  /// `PlatformUtils.isLinux` (dart:io `Platform.isLinux`), which
  /// `debugDefaultTargetPlatformOverride` cannot influence — so a unit test
  /// running on a real Linux CI host still reached [SystemWideShortcutsLinux.init]
  /// and died on the missing session bus (`/run/user/<uid>/bus`) even though the
  /// file pins the platform to Windows. A test asserting platform-agnostic
  /// behaviour (default keybindings, binding restore) sets this false so it
  /// never touches D-Bus.
  @visibleForTesting
  static bool? debugRunLinuxInit;

  static Future<void> init() async {
    await reloadNavigationShortcuts();

    if (debugRunLinuxInit ?? PlatformUtils.isLinux) {
      SystemWideShortcutsLinux.init();
    }

    for (var shortcut in registeredShortcuts.entries) {
      final binding =
          preferences.getSystemShortcutBinding(shortcut.key) ??
          shortcut.value.defaultBinding;
      if (binding != null) {
        try {
          await shortcut.value.setBinding(binding);
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content:
                'Failed to restore shortcut binding for shortcut ${shortcut.key}',
            category: LogCategory.app,
            source: 'system-wide-shortcuts',
          );
        }
      }
    }
    _syncWindowsPollingMonitor();
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
    pushToTalkShortcutKey: AppShortcut(
      getDisplayName: () => shortcutNamePushToTalk,
      callback: () => clientManager?.callManager.pushToTalkStart(),
      keyUpCallback: () => clientManager?.callManager.pushToTalkEnd(),
      defaultHotkey: HotKey(
        identifier: 'push-to-talk-default',
        key: PhysicalKeyboardKey.numpadDecimal,
        modifiers: const [],
      ),
      shouldRegisterWithHotKeyManager: (_) => !PlatformUtils.isWindows,
      onHotkeyChanged: () =>
          clientManager?.callManager.applyPushToTalkPreference(),
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
    ShortcutBinding? binding,
    bool clearHotkey = false,
  }) async {
    final definitions = List<NavigationShortcutDefinition>.from(
      customNavigationShortcuts,
    );
    final existingIndex = definitions.indexWhere(
      (entry) => entry.id == definition.id,
    );
    final existingDefinition = existingIndex == -1
        ? null
        : definitions[existingIndex];
    final existingShortcutBinding =
        customShortcuts[definition.shortcutKey]?.binding;
    final effectiveHotkey = clearHotkey
        ? null
        : hotkey ??
              existingShortcutBinding?.hotKey ??
              existingDefinition?.hotkey;
    final effectiveBinding = clearHotkey
        ? null
        : binding ??
              ShortcutBinding.fromHotKey(hotkey) ??
              existingShortcutBinding ??
              existingDefinition?.binding ??
              ShortcutBinding.fromHotKey(effectiveHotkey);
    final definitionToStore = definition.copyWith(
      hotkey: effectiveBinding?.hotKey,
      shortcutBinding: effectiveBinding,
    );
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
      } else if (binding != null) {
        await shortcut.setBinding(binding);
      } else if (hotkey != null) {
        await shortcut.setHotkey(hotkey);
      } else if (shortcut.binding == null && effectiveBinding != null) {
        await shortcut.setBinding(effectiveBinding);
      } else {
        await _storeHotkeyForShortcut(shortcut);
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
      if (shortcut == null || shortcut.binding != null) {
        continue;
      }

      final binding =
          preferences.getSystemShortcutBinding(definition.shortcutKey) ??
          definition.binding;
      if (binding == null) {
        continue;
      }

      try {
        await shortcut.setBinding(binding);
      } catch (_) {
        await preferences.setSystemShortcutBinding(
          definition.shortcutKey,
          null,
        );
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
      await preferences.setSystemShortcutBinding(i.key, i.value.binding);
    }
  }

  static Future<void> _storeHotkeyForShortcut(AppShortcut shortcut) async {
    final key = _shortcutKeyFor(shortcut);
    if (key == null) {
      await storeHotkeys();
      return;
    }
    _loggedUnreadableWindowsShortcuts.remove(key);
    await preferences.setSystemShortcutBinding(key, shortcut.binding);
  }

  static String? _shortcutKeyFor(AppShortcut shortcut) {
    for (final entry in registeredShortcuts.entries) {
      if (identical(entry.value, shortcut)) {
        return entry.key;
      }
    }
    return null;
  }

  static void _syncWindowsPollingMonitor() {
    if (!PlatformUtils.isWindows || !_windowsHotkeyPollingReader.isSupported) {
      _stopWindowsPollingMonitor();
      return;
    }

    final hasPollableShortcut = registeredShortcuts.entries.any(
      _isWindowsShortcutPollable,
    );

    if (hasPollableShortcut) {
      _startWindowsPollingMonitor();
    } else {
      _stopWindowsPollingMonitor();
    }
  }

  static void _startWindowsPollingMonitor() {
    if (_windowsPollingTimer != null) {
      return;
    }
    _loggedWindowsPollingFailure = false;
    _windowsPollingTimer = Timer.periodic(
      _windowsPollingInterval,
      (_) => _pollWindowsShortcuts(),
    );
    _pollWindowsShortcuts();
  }

  static void _stopWindowsPollingMonitor() {
    _windowsPollingTimer?.cancel();
    _windowsPollingTimer = null;
    for (final shortcut in _windowsPressedShortcuts.toList(growable: false)) {
      _notifyWindowsPolledShortcutReleased(shortcut);
    }
    _windowsPressedShortcuts.clear();
  }

  static void _pollWindowsShortcuts() {
    try {
      final activeShortcuts = <AppShortcut>{};
      for (final entry in registeredShortcuts.entries.toList(growable: false)) {
        if (!_isWindowsShortcutPollable(entry)) {
          continue;
        }

        final shortcut = entry.value;
        final binding = shortcut.binding!;
        final pressed = _windowsHotkeyPollingReader.isBindingPressed(binding);
        if (pressed) {
          activeShortcuts.add(shortcut);
        }

        final wasPressed = _windowsPressedShortcuts.contains(shortcut);
        if (pressed && !wasPressed) {
          _windowsPressedShortcuts.add(shortcut);
          _notifyWindowsPolledShortcutPressed(shortcut);
        } else if (!pressed && wasPressed) {
          _windowsPressedShortcuts.remove(shortcut);
          _notifyWindowsPolledShortcutReleased(shortcut);
        }
      }

      for (final shortcut in _windowsPressedShortcuts.toList(growable: false)) {
        if (!activeShortcuts.contains(shortcut)) {
          _windowsPressedShortcuts.remove(shortcut);
          _notifyWindowsPolledShortcutReleased(shortcut);
        }
      }
    } catch (error, stackTrace) {
      _stopWindowsPollingMonitor();
      if (_loggedWindowsPollingFailure) {
        return;
      }
      _loggedWindowsPollingFailure = true;
      Log.onError(
        error,
        stackTrace,
        content:
            'Windows shortcut polling failed; non-exclusive shortcut polling stopped',
        category: LogCategory.app,
        source: 'system-wide-shortcuts',
      );
    }
  }

  static bool _isWindowsShortcutPollable(MapEntry<String, AppShortcut> entry) {
    if (entry.key == pushToTalkShortcutKey) {
      return false;
    }

    final shortcut = entry.value;
    final binding = shortcut.binding;
    if (binding == null || shortcut._registeredWithHotKeyManager) {
      return false;
    }

    if (_windowsHotkeyPollingReader.canReadBinding(binding)) {
      return true;
    }

    if (_loggedUnreadableWindowsShortcuts.add(entry.key)) {
      Log.w(
        'Windows shortcut ignored because its keybind cannot be polled: '
        'shortcut=${entry.key} binding="${HotKeyDisplay.describeBinding(binding)}"',
        category: LogCategory.app,
        source: 'system-wide-shortcuts',
      );
    }
    return false;
  }

  static void _notifyWindowsPolledShortcutPressed(AppShortcut shortcut) {
    try {
      shortcut.callback();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Windows shortcut callback failed',
        category: LogCategory.app,
        source: 'system-wide-shortcuts',
      );
    }
  }

  static void _notifyWindowsPolledShortcutReleased(AppShortcut shortcut) {
    final keyUpCallback = shortcut.keyUpCallback;
    if (keyUpCallback == null) {
      return;
    }
    try {
      keyUpCallback();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Windows shortcut release callback failed',
        category: LogCategory.app,
        source: 'system-wide-shortcuts',
      );
    }
  }
}

class AppShortcut {
  void Function() callback;
  void Function()? keyUpCallback;
  bool Function(HotKey hotkey) shouldRegisterWithHotKeyManager;
  VoidCallback? onHotkeyChanged;

  String Function() getDisplayName;

  final HotKey? defaultHotkey;
  ShortcutBinding? binding;
  bool _registeredWithHotKeyManager = false;

  AppShortcut({
    required this.getDisplayName,
    required this.callback,
    this.keyUpCallback,
    this.defaultHotkey,
    bool Function(HotKey hotkey)? shouldRegisterWithHotKeyManager,
    this.onHotkeyChanged,
  }) : shouldRegisterWithHotKeyManager =
           shouldRegisterWithHotKeyManager ?? ((_) => !PlatformUtils.isWindows);

  ShortcutBinding? get defaultBinding =>
      ShortcutBinding.fromHotKey(defaultHotkey);

  HotKey? get hotkey => binding?.hotKey;

  set hotkey(HotKey? value) {
    binding = ShortcutBinding.fromHotKey(value);
  }

  @visibleForTesting
  bool shouldRegisterWithHotKeyManagerForTesting(HotKey hotkey) {
    return shouldRegisterWithHotKeyManager(hotkey);
  }

  Future<void> setHotkey(HotKey newHotkey) async {
    await setBinding(ShortcutBinding.keyboard(newHotkey));
  }

  Future<void> setBinding(ShortcutBinding newBinding) async {
    if (_canReuseCurrentRegistration(newBinding)) {
      binding = newBinding;
      await SystemWideShortcuts._storeHotkeyForShortcut(this);
      SystemWideShortcuts._syncWindowsPollingMonitor();
      onHotkeyChanged?.call();
      return;
    }

    final oldBinding = binding;
    final oldRegisteredWithHotKeyManager = _registeredWithHotKeyManager;
    var oldBindingUnregistered = oldBinding == null;

    try {
      if (oldBinding != null) {
        if (_registeredWithHotKeyManager) {
          await hotKeyManager.unregister(oldBinding.hotKey!);
        }
        oldBindingUnregistered = true;
        binding = null;
        _registeredWithHotKeyManager = false;
      }

      for (var key in SystemWideShortcuts.registeredShortcuts.values) {
        if (identical(key, this)) {
          continue;
        }

        if (HotKeyDisplay.equivalentBinding(key.binding, newBinding)) {
          await key.clearHotkey();
        }
      }

      _registeredWithHotKeyManager = await _registerBinding(newBinding);
      binding = newBinding;
      await SystemWideShortcuts._storeHotkeyForShortcut(this);
      SystemWideShortcuts._syncWindowsPollingMonitor();
      onHotkeyChanged?.call();
    } catch (_) {
      await _restorePreviousBindingAfterFailedSet(
        oldBinding,
        oldRegisteredWithHotKeyManager: oldRegisteredWithHotKeyManager,
        oldBindingUnregistered: oldBindingUnregistered,
      );
      await SystemWideShortcuts._storeHotkeyForShortcut(this);
      SystemWideShortcuts._syncWindowsPollingMonitor();
      onHotkeyChanged?.call();
      rethrow;
    }
  }

  bool _canReuseCurrentRegistration(ShortcutBinding newBinding) {
    final currentBinding = binding;
    if (identical(currentBinding, newBinding)) {
      return true;
    }
    if (!HotKeyDisplay.equivalentBinding(currentBinding, newBinding)) {
      return false;
    }

    final currentHotKey = currentBinding?.hotKey;
    final newHotKey = newBinding.hotKey;
    if (currentHotKey == null || newHotKey == null) {
      return true;
    }

    return !_registeredWithHotKeyManager || identical(currentHotKey, newHotKey);
  }

  Future<void> _restorePreviousBindingAfterFailedSet(
    ShortcutBinding? oldBinding, {
    required bool oldRegisteredWithHotKeyManager,
    required bool oldBindingUnregistered,
  }) async {
    if (oldBinding == null) {
      binding = null;
      _registeredWithHotKeyManager = false;
      return;
    }

    if (!oldBindingUnregistered) {
      binding = oldBinding;
      _registeredWithHotKeyManager = oldRegisteredWithHotKeyManager;
      return;
    }

    try {
      _registeredWithHotKeyManager =
          oldRegisteredWithHotKeyManager && await _registerBinding(oldBinding);
      binding = oldBinding;
    } catch (_) {
      binding = null;
      _registeredWithHotKeyManager = false;
    }
  }

  Future<bool> _registerBinding(ShortcutBinding value) async {
    final hotKey = value.hotKey;
    if (hotKey == null || !shouldRegisterWithHotKeyManager(hotKey)) {
      return false;
    }

    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (hotKey) {
        callback();
      },
      keyUpHandler: keyUpCallback == null
          ? null
          : (hotKey) {
              keyUpCallback!();
            },
    );
    return true;
  }

  Future<void> clearHotkey() async {
    if (binding != null) {
      if (_registeredWithHotKeyManager) {
        await hotKeyManager.unregister(binding!.hotKey!);
      }
      binding = null;
      _registeredWithHotKeyManager = false;
    }

    await SystemWideShortcuts._storeHotkeyForShortcut(this);
    SystemWideShortcuts._syncWindowsPollingMonitor();
    onHotkeyChanged?.call();
  }
}
