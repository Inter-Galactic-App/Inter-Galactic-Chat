import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
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
      expect(fakeHotKeyPlatform.registeredIdentifiers, ['hotkey-nav-test']);
      expect(fakeHotKeyPlatform.unregisteredIdentifiers, isEmpty);

      await shortcut.setHotkey(hotkey);

      expect(shortcut.hotkey, same(hotkey));
      expect(fakeHotKeyPlatform.registeredIdentifiers, ['hotkey-nav-test']);
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
      expect(fakeHotKeyPlatform.registeredIdentifiers, ['hotkey-nav-test']);
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
      expect(fakeHotKeyPlatform.registeredIdentifiers, ['hotkey-nav-test']);
    },
  );

  test(
    'saving a custom navigation shortcut does not persist failed hotkey',
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

      await expectLater(
        SystemWideShortcuts.saveNavigationShortcut(
          definition,
          hotkey: hotkey,
        ),
        throwsException,
      );

      expect(preferences.getCustomNavigationShortcuts(), isEmpty);
      expect(
        SystemWideShortcuts.customShortcuts,
        isNot(contains('custom_navigation_nav_test')),
      );
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
      expect(
        fakeHotKeyPlatform.unregisteredIdentifiers,
        contains('hotkey-nav-test'),
      );
    },
  );

  test('push-to-talk shortcut is registered as a hold action', () {
    final shortcut = SystemWideShortcuts.shortcuts['push_to_talk'];

    expect(shortcut, isNotNull);
    expect(shortcut!.keyUpCallback, isNotNull);
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
  }

  Future<void> dispose() async {
    await _keyEventController.close();
  }
}
