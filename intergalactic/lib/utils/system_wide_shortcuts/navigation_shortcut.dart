import 'package:hotkey_manager/hotkey_manager.dart';

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

class NavigationShortcutDefinition {
  const NavigationShortcutDefinition({
    required this.id,
    required this.targetType,
    required this.targetAddress,
    required this.label,
    this.clientId,
    this.hotkey,
  });

  final String id;
  final NavigationShortcutTargetType targetType;
  final String targetAddress;
  final String label;
  final String? clientId;
  final HotKey? hotkey;

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
  }) {
    return NavigationShortcutDefinition(
      id: id ?? this.id,
      targetType: targetType ?? this.targetType,
      targetAddress: targetAddress ?? this.targetAddress,
      label: label ?? this.label,
      clientId: identical(clientId, _clientIdNoChange)
          ? this.clientId
          : clientId as String?,
      hotkey:
          identical(hotkey, _hotkeyNoChange) ? this.hotkey : hotkey as HotKey?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetType': targetType.storageValue,
      'targetAddress': targetAddress,
      'label': label,
      if (clientId != null && clientId!.trim().isNotEmpty) 'clientId': clientId,
      if (hotkey != null) 'hotkey': hotkey!.toJson(),
    };
  }

  static HotKey? _hotKeyFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    try {
      return HotKey.fromJson(value.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static NavigationShortcutDefinition? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final targetAddress = json['targetAddress'];
    final targetType =
        NavigationShortcutTargetType.fromStorageValue(json['targetType']);

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
      clientId:
          clientId is String && clientId.trim().isNotEmpty ? clientId : null,
      hotkey: _hotKeyFromJson(json['hotkey']),
    );
  }
}
