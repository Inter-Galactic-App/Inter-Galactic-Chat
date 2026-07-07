import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';

enum NavigationShortcutTargetType {
  room,
  space;

  String get storageValue => switch (this) {
    NavigationShortcutTargetType.room => 'room',
    NavigationShortcutTargetType.space => 'space',
  };

  String get label => switch (this) {
    NavigationShortcutTargetType.room => 'Room',
    NavigationShortcutTargetType.space => 'Space',
  };

  static NavigationShortcutTargetType? fromStorageValue(Object? value) {
    return switch (value) {
      'room' => NavigationShortcutTargetType.room,
      'space' => NavigationShortcutTargetType.space,
      _ => null,
    };
  }
}

const Object _clientIdNoChange = Object();
const Object _hotkeyNoChange = Object();
const Object _shortcutBindingNoChange = Object();

class NavigationShortcutDefinition {
  const NavigationShortcutDefinition({
    required this.id,
    required this.targetType,
    required this.targetAddress,
    required this.label,
    this.clientId,
    this.hotkey,
    this.shortcutBinding,
  });

  final String id;
  final NavigationShortcutTargetType targetType;
  final String targetAddress;
  final String label;
  final String? clientId;
  final HotKey? hotkey;
  final ShortcutBinding? shortcutBinding;

  ShortcutBinding? get binding =>
      shortcutBinding ?? ShortcutBinding.fromHotKey(hotkey);

  static String generateId() {
    return 'nav_${DateTime.now().microsecondsSinceEpoch}';
  }

  String get shortcutKey => 'custom_navigation_$id';

  String get displayLabel {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isNotEmpty) {
      return trimmedLabel;
    }

    return 'Open ${targetType.label.toLowerCase()}';
  }

  NavigationShortcutDefinition copyWith({
    String? id,
    NavigationShortcutTargetType? targetType,
    String? targetAddress,
    String? label,
    Object? clientId = _clientIdNoChange,
    Object? hotkey = _hotkeyNoChange,
    Object? shortcutBinding = _shortcutBindingNoChange,
  }) {
    return NavigationShortcutDefinition(
      id: id ?? this.id,
      targetType: targetType ?? this.targetType,
      targetAddress: targetAddress ?? this.targetAddress,
      label: label ?? this.label,
      clientId: identical(clientId, _clientIdNoChange)
          ? this.clientId
          : clientId as String?,
      hotkey: identical(hotkey, _hotkeyNoChange)
          ? this.hotkey
          : hotkey as HotKey?,
      shortcutBinding: identical(shortcutBinding, _shortcutBindingNoChange)
          ? this.shortcutBinding
          : shortcutBinding as ShortcutBinding?,
    );
  }

  Map<String, dynamic> toJson() {
    final legacyHotkey = hotkey ?? shortcutBinding?.hotKey;
    return {
      'id': id,
      'targetType': targetType.storageValue,
      'targetAddress': targetAddress,
      'label': label,
      if (clientId != null && clientId!.trim().isNotEmpty) 'clientId': clientId,
      if (legacyHotkey != null) 'hotkey': legacyHotkey.toJson(),
      if (binding != null) 'shortcutBinding': binding!.toJson(),
    };
  }

  static HotKey? _hotKeyFromJson(Object? value) {
    return ShortcutBinding.fromJson(value)?.hotKey;
  }

  static ShortcutBinding? _bindingFromJson(Object? value) {
    return ShortcutBinding.fromJson(value);
  }

  static NavigationShortcutDefinition? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final targetAddress = json['targetAddress'];
    final targetType = NavigationShortcutTargetType.fromStorageValue(
      json['targetType'],
    );

    if (id is! String ||
        id.trim().isEmpty ||
        targetAddress is! String ||
        targetAddress.trim().isEmpty ||
        targetType == null) {
      return null;
    }

    final label = json['label'];
    final clientId = json['clientId'];

    return NavigationShortcutDefinition(
      id: id,
      targetType: targetType,
      targetAddress: targetAddress,
      label: label is String ? label : '',
      clientId: clientId is String && clientId.trim().isNotEmpty
          ? clientId
          : null,
      hotkey: _hotKeyFromJson(json['hotkey']),
      shortcutBinding:
          _bindingFromJson(json['shortcutBinding']) ??
          _bindingFromJson(json['hotkey']),
    );
  }
}
