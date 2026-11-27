import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';

void main() {
  test(
    'navigation shortcut serializes room target with optional client scope',
    () {
      const definition = NavigationShortcutDefinition(
        id: 'nav_test',
        targetType: NavigationShortcutTargetType.room,
        targetAddress: '#lounge:example.com',
        label: 'Open Lounge',
        clientId: 'client-a',
      );

      final json = definition.toJson();
      final parsed = NavigationShortcutDefinition.fromJson(json);

      expect(parsed?.id, 'nav_test');
      expect(parsed?.targetType, NavigationShortcutTargetType.room);
      expect(parsed?.targetAddress, '#lounge:example.com');
      expect(parsed?.label, 'Open Lounge');
      expect(parsed?.clientId, 'client-a');
      expect(parsed?.shortcutKey, 'custom_navigation_nav_test');
    },
  );

  test('navigation shortcut serializes space target without account scope', () {
    const definition = NavigationShortcutDefinition(
      id: 'nav_space',
      targetType: NavigationShortcutTargetType.space,
      targetAddress: '#community:example.com',
      label: '',
    );

    final json = definition.toJson();
    final parsed = NavigationShortcutDefinition.fromJson(json);

    expect(json.containsKey('clientId'), isFalse);
    expect(parsed?.targetType, NavigationShortcutTargetType.space);
    expect(parsed?.displayLabel, 'Open space');
  });

  test('navigation shortcut preserves fallback hotkey metadata', () {
    final hotkey = HotKey(
      identifier: 'hotkey-nav-test',
      key: PhysicalKeyboardKey.pageDown,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    );
    final definition = NavigationShortcutDefinition(
      id: 'nav_hotkey',
      targetType: NavigationShortcutTargetType.room,
      targetAddress: '#test-voice:example.com',
      label: 'Test Voice',
      hotkey: hotkey,
    );

    final json = definition.toJson();
    final parsed = NavigationShortcutDefinition.fromJson(json);

    expect(json['hotkey'], isA<Map<String, dynamic>>());
    expect(parsed?.hotkey?.identifier, 'hotkey-nav-test');
    expect(parsed?.hotkey?.key, PhysicalKeyboardKey.pageDown);
    expect(parsed?.hotkey?.modifiers, [
      HotKeyModifier.control,
      HotKeyModifier.alt,
    ]);
  });

  test('navigation shortcut preserves mouse button binding metadata', () {
    const definition = NavigationShortcutDefinition(
      id: 'nav_mouse',
      targetType: NavigationShortcutTargetType.room,
      targetAddress: '#test-voice:example.com',
      label: 'Test Voice',
      shortcutBinding: ShortcutBinding.mouseButton(
        button: 4,
        modifiers: [HotKeyModifier.control],
      ),
    );

    final json = definition.toJson();
    final parsed = NavigationShortcutDefinition.fromJson(json);

    expect(json['shortcutBinding'], isA<Map<String, dynamic>>());
    expect(parsed?.binding?.mouseButton, 4);
    expect(parsed?.binding?.modifiers, [HotKeyModifier.control]);
    expect(parsed?.hotkey, isNull);
  });

  test('malformed navigation shortcut json is ignored safely', () {
    expect(
      NavigationShortcutDefinition.fromJson({
        'id': 'nav_bad',
        'targetType': 'room',
      }),
      isNull,
    );
    expect(
      NavigationShortcutDefinition.fromJson({
        'id': 'nav_bad',
        'targetType': 'unknown',
        'targetAddress': '#room:example.com',
      }),
      isNull,
    );
    expect(
      NavigationShortcutDefinition.fromJson({
        'id': 'nav_bad_hotkey',
        'targetType': 'room',
        'targetAddress': '#room:example.com',
        'hotkey': {'key': 'not-a-key'},
      })?.hotkey,
      isNull,
    );
  });
}
