import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/hotkey_display.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/push_to_talk_hotkey_monitor.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/push_to_talk_hotkey_reader.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _ShortcutTestBinding.ensureInitialized();

  late _FakeHotKeyManagerPlatform fakeHotKeyPlatform;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();

    fakeHotKeyPlatform = _FakeHotKeyManagerPlatform();
    HotKeyManagerPlatform.instance = fakeHotKeyPlatform;
    await hotKeyManager.unregisterAll();
    fakeHotKeyPlatform.reset();

    SystemWideShortcuts.customShortcuts.clear();
    SystemWideShortcuts.customNavigationShortcuts = [];
  });

  tearDown(() async {
    await hotKeyManager.unregisterAll();
    SystemWideShortcuts.customShortcuts.clear();
    SystemWideShortcuts.customNavigationShortcuts = [];
    await fakeHotKeyPlatform.dispose();
  });

  test(
    'saving the existing hotkey again keeps the registration stable',
    () async {
      final shortcut = AppShortcut(
        getDisplayName: () => 'Open Lounge',
        callback: () {},
      );
      SystemWideShortcuts.customShortcuts['custom_navigation_nav_test'] =
          shortcut;

      final hotkey = HotKey(
        identifier: 'hotkey-nav-test',
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.control],
      );

      await shortcut.setHotkey(hotkey);

      expect(shortcut.hotkey, same(hotkey));
      expect(
        fakeHotKeyPlatform.registeredIdentifiers,
        _registeredIdentifiersForCurrentPlatform('hotkey-nav-test'),
      );
      expect(fakeHotKeyPlatform.unregisteredIdentifiers, isEmpty);

      await shortcut.setHotkey(hotkey);

      expect(shortcut.hotkey, same(hotkey));
      expect(
        fakeHotKeyPlatform.registeredIdentifiers,
        _registeredIdentifiersForCurrentPlatform('hotkey-nav-test'),
      );
      expect(fakeHotKeyPlatform.unregisteredIdentifiers, isEmpty);
    },
  );

  test(
    'custom navigation shortcut restores hotkey from definition fallback',
    () async {
      final hotkey = HotKey(
        identifier: 'hotkey-nav-test',
        key: PhysicalKeyboardKey.pageDown,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      final definition = NavigationShortcutDefinition(
        id: 'nav_test',
        targetType: NavigationShortcutTargetType.room,
        targetAddress: '#test-voice:example.com',
        label: 'Test Voice',
        hotkey: hotkey,
      );
      await preferences.setCustomNavigationShortcuts([definition.toJson()]);

      await SystemWideShortcuts.reloadNavigationShortcuts();

      final shortcut =
          SystemWideShortcuts.customShortcuts['custom_navigation_nav_test'];
      expect(shortcut, isNotNull);
      expect(shortcut!.hotkey?.identifier, 'hotkey-nav-test');
      expect(shortcut.hotkey?.key, PhysicalKeyboardKey.pageDown);
      expect(
        fakeHotKeyPlatform.registeredIdentifiers,
        _registeredIdentifiersForCurrentPlatform('hotkey-nav-test'),
      );
    },
  );

  test(
    'saving a custom navigation shortcut embeds its hotkey fallback',
    () async {
      final hotkey = HotKey(
        identifier: 'hotkey-nav-test',
        key: PhysicalKeyboardKey.pageDown,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      const definition = NavigationShortcutDefinition(
        id: 'nav_test',
        targetType: NavigationShortcutTargetType.room,
        targetAddress: '#test-voice:example.com',
        label: 'Test Voice',
      );

      await SystemWideShortcuts.saveNavigationShortcut(
        definition,
        hotkey: hotkey,
      );

      final stored = preferences.getCustomNavigationShortcuts();
      final parsed = NavigationShortcutDefinition.fromJson(stored.single);
      expect(parsed?.hotkey?.identifier, 'hotkey-nav-test');
      expect(parsed?.hotkey?.key, PhysicalKeyboardKey.pageDown);
      expect(
        fakeHotKeyPlatform.registeredIdentifiers,
        _registeredIdentifiersForCurrentPlatform('hotkey-nav-test'),
      );
    },
  );

  test(
    'saving a custom navigation shortcut avoids exclusive Windows registration',
    () async {
      fakeHotKeyPlatform.failRegister = true;
      final hotkey = HotKey(
        identifier: 'hotkey-nav-test',
        key: PhysicalKeyboardKey.pageDown,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      const definition = NavigationShortcutDefinition(
        id: 'nav_test',
        targetType: NavigationShortcutTargetType.room,
        targetAddress: '#test-voice:example.com',
        label: 'Test Voice',
      );

      final save = SystemWideShortcuts.saveNavigationShortcut(
        definition,
        hotkey: hotkey,
      );

      if (PlatformUtils.isWindows) {
        await save;

        final stored = preferences.getCustomNavigationShortcuts();
        final parsed = NavigationShortcutDefinition.fromJson(stored.single);
        expect(parsed?.hotkey?.identifier, 'hotkey-nav-test');
        expect(fakeHotKeyPlatform.registeredIdentifiers, isEmpty);
      } else {
        await expectLater(save, throwsException);

        expect(preferences.getCustomNavigationShortcuts(), isEmpty);
        expect(
          SystemWideShortcuts.customShortcuts,
          isNot(contains('custom_navigation_nav_test')),
        );
      }
    },
  );

  test(
    'clearing a custom navigation hotkey removes definition fallback',
    () async {
      final hotkey = HotKey(
        identifier: 'hotkey-nav-test',
        key: PhysicalKeyboardKey.pageDown,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      const definition = NavigationShortcutDefinition(
        id: 'nav_test',
        targetType: NavigationShortcutTargetType.room,
        targetAddress: '#test-voice:example.com',
        label: 'Test Voice',
      );

      await SystemWideShortcuts.saveNavigationShortcut(
        definition,
        hotkey: hotkey,
      );
      await SystemWideShortcuts.saveNavigationShortcut(
        definition,
        clearHotkey: true,
      );

      final stored = preferences.getCustomNavigationShortcuts();
      final parsed = NavigationShortcutDefinition.fromJson(stored.single);
      expect(parsed?.hotkey, isNull);
      if (PlatformUtils.isWindows) {
        expect(fakeHotKeyPlatform.unregisteredIdentifiers, isEmpty);
      } else {
        expect(
          fakeHotKeyPlatform.unregisteredIdentifiers,
          contains('hotkey-nav-test'),
        );
      }
    },
  );

  test('Windows shortcuts are non-exclusive by default', () {
    final shortcut = AppShortcut(
      getDisplayName: () => 'Open Lounge',
      callback: () {},
    );
    final hotkey = HotKey(
      identifier: 'hotkey-nav-test',
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control],
    );

    expect(
      shortcut.shouldRegisterWithHotKeyManagerForTesting(hotkey),
      !PlatformUtils.isWindows,
    );
  });

  test('push-to-talk shortcut is registered as a hold action', () {
    final shortcut = SystemWideShortcuts
        .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey];

    expect(shortcut, isNotNull);
    expect(shortcut!.keyUpCallback, isNotNull);
  });

  test('push-to-talk shortcut defaults to Numpad Decimal', () async {
    final shortcut = SystemWideShortcuts
        .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
    final previousHotkey = shortcut.hotkey;
    addTearDown(() {
      shortcut.hotkey = previousHotkey;
    });

    shortcut.hotkey = null;

    await SystemWideShortcuts.init();

    expect(shortcut.hotkey?.physicalKey, PhysicalKeyboardKey.numpadDecimal);
    expect(
      preferences
          .getSystemHotkey(SystemWideShortcuts.pushToTalkShortcutKey)
          ?.physicalKey,
      PhysicalKeyboardKey.numpadDecimal,
    );
    if (PlatformUtils.isWindows) {
      expect(fakeHotKeyPlatform.registeredIdentifiers, isEmpty);
    }
  });

  test('hotkey display labels Numpad Decimal without debug metadata', () {
    final hotkey = HotKey(
      identifier: 'hotkey-ptt-label-test',
      key: PhysicalKeyboardKey.numpadDecimal,
      modifiers: const [],
    );

    expect(HotKeyDisplay.describe(hotkey), 'Numpad Decimal');
    expect(
      HotKeyDisplay.windowsVirtualKeyCodeForPhysicalKey(
        PhysicalKeyboardKey.numpadDecimal,
      ),
      0x6e,
    );
  });

  test('shortcut binding labels and stores mouse buttons', () async {
    const binding = ShortcutBinding.mouseButton(
      button: 4,
      modifiers: [HotKeyModifier.control],
    );

    expect(HotKeyDisplay.describeBinding(binding), 'Ctrl + Mouse Button 4');

    await preferences.setSystemShortcutBinding('mouse_test', binding);

    final stored = preferences.getSystemShortcutBinding('mouse_test');
    expect(stored?.mouseButton, 4);
    expect(stored?.modifiers, [HotKeyModifier.control]);
    expect(preferences.getSystemHotkey('mouse_test'), isNull);
  });

  test('mouse button parser accepts Win32-readable buttons only', () {
    expect(ShortcutBinding.singleMouseButtonFromButtons(nthMouseButton(3)), 3);
    expect(ShortcutBinding.singleMouseButtonFromButtons(nthMouseButton(5)), 5);
    expect(
      ShortcutBinding.singleMouseButtonFromButtons(nthMouseButton(6)),
      isNull,
    );
    expect(
      ShortcutBinding.singleMouseButtonFromButtons(
        nthMouseButton(4) | nthMouseButton(5),
      ),
      isNull,
    );
  });

  test('mouse button bindings compare by button and modifiers', () {
    const first = ShortcutBinding.mouseButton(
      button: 5,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    );
    const second = ShortcutBinding.mouseButton(
      button: 5,
      modifiers: [HotKeyModifier.shift, HotKeyModifier.control],
    );

    expect(HotKeyDisplay.equivalentBinding(first, second), isTrue);
  });

  test('distinct hotkey instances compare by key and modifiers', () {
    final first = HotKey(
      identifier: 'hotkey-first',
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    );
    final second = HotKey(
      identifier: 'hotkey-second',
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.shift, HotKeyModifier.control],
    );

    expect(identical(first, second), isFalse);
    expect(HotKeyDisplay.equivalent(first, second), isTrue);
  });

  test('setting duplicate hotkey clears previous shortcut by value', () async {
    final firstShortcut = AppShortcut(
      getDisplayName: () => 'First',
      callback: () {},
    );
    final secondShortcut = AppShortcut(
      getDisplayName: () => 'Second',
      callback: () {},
    );
    SystemWideShortcuts.customShortcuts
      ..['custom_navigation_first'] = firstShortcut
      ..['custom_navigation_second'] = secondShortcut;

    await firstShortcut.setHotkey(
      HotKey(
        identifier: 'hotkey-first',
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.control],
      ),
    );
    await secondShortcut.setHotkey(
      HotKey(
        identifier: 'hotkey-second',
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.control],
      ),
    );

    expect(firstShortcut.hotkey, isNull);
    expect(secondShortcut.hotkey?.identifier, 'hotkey-second');
    expect(preferences.getSystemHotkey('custom_navigation_first'), isNull);
    expect(
      preferences.getSystemHotkey('custom_navigation_second')?.identifier,
      'hotkey-second',
    );
  });

  test(
    'setting duplicate mouse binding clears previous shortcut by value',
    () async {
      final firstShortcut = AppShortcut(
        getDisplayName: () => 'First',
        callback: () {},
      );
      final secondShortcut = AppShortcut(
        getDisplayName: () => 'Second',
        callback: () {},
      );
      SystemWideShortcuts.customShortcuts
        ..['custom_navigation_first'] = firstShortcut
        ..['custom_navigation_second'] = secondShortcut;

      const binding = ShortcutBinding.mouseButton(
        button: 4,
        modifiers: [HotKeyModifier.control],
      );

      await firstShortcut.setBinding(binding);
      await secondShortcut.setBinding(binding);

      expect(firstShortcut.binding, isNull);
      expect(secondShortcut.binding?.mouseButton, 4);
      expect(
        preferences.getSystemShortcutBinding('custom_navigation_first'),
        isNull,
      );
      expect(
        preferences
            .getSystemShortcutBinding('custom_navigation_second')
            ?.mouseButton,
        4,
      );
    },
  );

  test('init continues when one saved hotkey cannot be restored', () async {
    final shortcut = AppShortcut(
      getDisplayName: () => 'Always Register',
      callback: () {},
      shouldRegisterWithHotKeyManager: (_) => true,
    );
    SystemWideShortcuts.shortcuts['forced_restore_test'] = shortcut;
    addTearDown(() {
      SystemWideShortcuts.shortcuts.remove('forced_restore_test');
    });
    final hotkey = HotKey(
      identifier: 'hotkey-forced',
      key: PhysicalKeyboardKey.keyF,
      modifiers: [HotKeyModifier.control],
    );
    await preferences.setSystemHotkey('forced_restore_test', hotkey);
    fakeHotKeyPlatform.failRegister = true;

    await expectLater(SystemWideShortcuts.init(), completes);

    expect(shortcut.hotkey, isNull);
    expect(preferences.getSystemHotkey('forced_restore_test'), isNull);
  });

  test('setHotkey restores previous hotkey when unregister fails', () async {
    final shortcut = AppShortcut(
      getDisplayName: () => 'Always Register',
      callback: () {},
      shouldRegisterWithHotKeyManager: (_) => true,
    );
    SystemWideShortcuts.customShortcuts['custom_navigation_rollback'] =
        shortcut;
    final oldHotkey = HotKey(
      identifier: 'hotkey-old',
      key: PhysicalKeyboardKey.keyO,
      modifiers: [HotKeyModifier.control],
    );
    final newHotkey = HotKey(
      identifier: 'hotkey-new',
      key: PhysicalKeyboardKey.keyN,
      modifiers: [HotKeyModifier.control],
    );

    await shortcut.setHotkey(oldHotkey);
    fakeHotKeyPlatform.failUnregister = true;

    await expectLater(shortcut.setHotkey(newHotkey), throwsException);

    expect(shortcut.hotkey, same(oldHotkey));
    final storedHotkey = preferences.getSystemHotkey(
      'custom_navigation_rollback',
    );
    expect(storedHotkey?.identifier, 'hotkey-old');
    expect(storedHotkey?.physicalKey, PhysicalKeyboardKey.keyO);
  });

  test(
    'push-to-talk hotkey is stored without Windows exclusive registration',
    () async {
      final shortcut = SystemWideShortcuts
          .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
      final previousHotkey = shortcut.hotkey;
      addTearDown(() {
        shortcut.hotkey = previousHotkey;
      });

      final hotkey = HotKey(
        identifier: 'hotkey-ptt-test',
        key: PhysicalKeyboardKey.space,
        modifiers: const [],
      );

      await shortcut.setHotkey(hotkey);

      expect(shortcut.hotkey, same(hotkey));
      if (PlatformUtils.isWindows) {
        expect(fakeHotKeyPlatform.registeredIdentifiers, isEmpty);
      } else {
        expect(fakeHotKeyPlatform.registeredIdentifiers, ['hotkey-ptt-test']);
      }
    },
  );

  test(
    'push-to-talk mouse button is stored without exclusive registration',
    () async {
      final shortcut = SystemWideShortcuts
          .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
      final previousBinding = shortcut.binding;
      addTearDown(() {
        shortcut.binding = previousBinding;
      });

      const binding = ShortcutBinding.mouseButton(button: 4);

      await shortcut.setBinding(binding);

      expect(shortcut.binding, same(binding));
      expect(fakeHotKeyPlatform.registeredIdentifiers, isEmpty);
      expect(
        preferences
            .getSystemShortcutBinding(SystemWideShortcuts.pushToTalkShortcutKey)
            ?.mouseButton,
        4,
      );
    },
  );

  test(
    'push-to-talk monitor emits press and release from polling reader',
    () async {
      final events = <String>[];
      var pressed = false;
      final hotkey = HotKey(
        identifier: 'hotkey-ptt-monitor-test',
        key: PhysicalKeyboardKey.space,
        modifiers: const [],
      );
      final monitor = PushToTalkHotkeyMonitor(
        onPressed: () => events.add('pressed'),
        onReleased: () => events.add('released'),
        pollInterval: const Duration(milliseconds: 1),
        supportedForTesting: true,
        isHotkeyPressedForTesting: (_) => pressed,
      );
      addTearDown(monitor.dispose);

      monitor.configure(ShortcutBinding.keyboard(hotkey));
      monitor.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      pressed = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      pressed = false;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(events, ['pressed', 'released']);
    },
  );

  test(
    'push-to-talk monitor emits press and release from mouse button binding',
    () async {
      final events = <String>[];
      var pressed = false;
      const binding = ShortcutBinding.mouseButton(button: 5);
      final monitor = PushToTalkHotkeyMonitor(
        onPressed: () => events.add('pressed'),
        onReleased: () => events.add('released'),
        pollInterval: const Duration(milliseconds: 1),
        supportedForTesting: true,
        isHotkeyPressedForTesting: (_) => pressed,
      );
      addTearDown(monitor.dispose);

      monitor.configure(binding);
      monitor.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      pressed = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      pressed = false;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(events, ['pressed', 'released']);
    },
  );

  test('push-to-talk monitor stops when polling reader fails', () {
    final hotkey = HotKey(
      identifier: 'hotkey-ptt-monitor-test',
      key: PhysicalKeyboardKey.space,
      modifiers: const [],
    );
    final monitor = PushToTalkHotkeyMonitor(
      onPressed: () {},
      onReleased: () {},
      supportedForTesting: true,
      isHotkeyPressedForTesting: (_) => throw StateError('reader failed'),
    );
    addTearDown(monitor.dispose);

    monitor.configure(ShortcutBinding.keyboard(hotkey));

    expect(monitor.start, returnsNormally);
    expect(monitor.isRunning, isFalse);
  });

  test('push-to-talk monitor treats capability failures as unsupported', () {
    final hotkey = HotKey(
      identifier: 'hotkey-ptt-monitor-test',
      key: PhysicalKeyboardKey.space,
      modifiers: const [],
    );
    final monitor = PushToTalkHotkeyMonitor(
      onPressed: () {},
      onReleased: () {},
      supportedForTesting: true,
      reader: _ThrowingPushToTalkHotkeyReader(),
    );
    addTearDown(monitor.dispose);

    monitor.configure(ShortcutBinding.keyboard(hotkey));

    expect(monitor.canMonitorHotkey(hotkey), isFalse);
    expect(monitor.start, returnsNormally);
    expect(monitor.isRunning, isFalse);
  });

  test('push-to-talk monitor stops when press callback fails', () {
    final hotkey = HotKey(
      identifier: 'hotkey-ptt-monitor-test',
      key: PhysicalKeyboardKey.space,
      modifiers: const [],
    );
    final monitor = PushToTalkHotkeyMonitor(
      onPressed: () => throw StateError('press failed'),
      onReleased: () {},
      supportedForTesting: true,
      isHotkeyPressedForTesting: (_) => true,
    );
    addTearDown(monitor.dispose);

    monitor.configure(ShortcutBinding.keyboard(hotkey));

    expect(monitor.start, returnsNormally);
    expect(monitor.isRunning, isFalse);
  });

  test(
    'wrap composer selection shortcut publishes composer wrap event',
    () async {
      final shortcut =
          SystemWideShortcuts.shortcuts['wrap_composer_selection_in_brackets'];

      expect(shortcut, isNotNull);
      expect(shortcut!.keyUpCallback, isNull);

      final event = EventBus.wrapComposerSelectionInBrackets.stream.first;
      shortcut.callback();

      await expectLater(event, completes);
    },
  );
}

List<String> _registeredIdentifiersForCurrentPlatform(String identifier) {
  return PlatformUtils.isWindows ? const [] : [identifier];
}

class _ShortcutTestBinding extends BindingBase
    with SchedulerBinding, ServicesBinding, TestDefaultBinaryMessengerBinding {
  static void ensureInitialized() {
    try {
      TestDefaultBinaryMessengerBinding.instance;
    } catch (_) {
      _ShortcutTestBinding();
    }
  }
}

class _FakeHotKeyManagerPlatform extends HotKeyManagerPlatform {
  final _keyEventController =
      StreamController<Map<Object?, Object?>>.broadcast();

  final List<String> registeredIdentifiers = [];
  final List<String> unregisteredIdentifiers = [];
  bool failRegister = false;
  bool failUnregister = false;

  @override
  Stream<Map<Object?, Object?>> get onKeyEventReceiver =>
      _keyEventController.stream;

  @override
  Future<void> register(HotKey hotKey) async {
    if (failRegister) {
      throw Exception('registration failed');
    }
    registeredIdentifiers.add(hotKey.identifier);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    if (failUnregister) {
      throw Exception('unregistration failed');
    }
    unregisteredIdentifiers.add(hotKey.identifier);
  }

  @override
  Future<void> unregisterAll() async {
    registeredIdentifiers.clear();
    unregisteredIdentifiers.clear();
  }

  void reset() {
    registeredIdentifiers.clear();
    unregisteredIdentifiers.clear();
    failRegister = false;
    failUnregister = false;
  }

  Future<void> dispose() async {
    await _keyEventController.close();
  }
}

class _ThrowingPushToTalkHotkeyReader implements DefaultHotkeyPollingReader {
  @override
  bool get isSupported => true;

  @override
  bool canRead(HotKey hotKey) => throw StateError('capability failed');

  @override
  bool canReadBinding(ShortcutBinding binding) =>
      throw StateError('capability failed');

  @override
  bool isPressed(HotKey hotKey) => false;

  @override
  bool isBindingPressed(ShortcutBinding binding) => false;
}
