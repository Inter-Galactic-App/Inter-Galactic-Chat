import 'package:intergalactic/client/client.dart';

class NavigationShortcutRoomOption {
  const NavigationShortcutRoomOption({
    required this.key,
    required this.targetAddress,
    required this.clientId,
    required this.displayName,
    required this.accountLabel,
    required this.roomIdentifier,
  });

  final String key;
  final String targetAddress;
  final String clientId;
  final String displayName;
  final String accountLabel;
  final String roomIdentifier;

  String get selectedLabel => '$displayName - $accountLabel';

  String get secondaryLabel => '$accountLabel - $roomIdentifier';
}

List<NavigationShortcutRoomOption> buildNavigationShortcutRoomOptions({
  required Iterable<Client> clients,
}) {
  final options = <NavigationShortcutRoomOption>[];

  for (final client in clients) {
    final accountLabel = navigationShortcutAccountLabel(client);
    for (final room in client.rooms) {
      final displayName = _fallbackLabel(room.displayName, room.identifier);
      options.add(
        NavigationShortcutRoomOption(
          key: room.localId,
          targetAddress: room.identifier,
          clientId: client.identifier,
          displayName: displayName,
          accountLabel: accountLabel,
          roomIdentifier: room.identifier,
        ),
      );
    }
  }

  options.sort((a, b) {
    final displayCompare =
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    if (displayCompare != 0) {
      return displayCompare;
    }

    final accountCompare =
        a.accountLabel.toLowerCase().compareTo(b.accountLabel.toLowerCase());
    if (accountCompare != 0) {
      return accountCompare;
    }

    return a.roomIdentifier.compareTo(b.roomIdentifier);
  });

  return options;
}

String navigationShortcutAccountLabel(Client client) {
  final self = client.self;
  final displayName = self?.displayName.trim();
  final userId = self?.identifier.trim();

  if (displayName != null &&
      displayName.isNotEmpty &&
      userId != null &&
      userId.isNotEmpty &&
      displayName != userId) {
    return '$displayName ($userId)';
  }

  if (userId != null && userId.isNotEmpty) {
    return userId;
  }

  return client.identifier;
}

NavigationShortcutRoomOption? findNavigationShortcutRoomOptionByKey(
  List<NavigationShortcutRoomOption> options,
  String key,
) {
  for (final option in options) {
    if (option.key == key) {
      return option;
    }
  }

  return null;
}

NavigationShortcutRoomOption? findNavigationShortcutRoomOptionForTarget({
  required List<NavigationShortcutRoomOption> options,
  required String targetAddress,
  String? clientId,
}) {
  final normalizedTarget = targetAddress.trim();
  final normalizedClientId = clientId?.trim();
  if (normalizedTarget.isEmpty) {
    return null;
  }

  NavigationShortcutRoomOption? fallback;
  for (final option in options) {
    if (option.targetAddress != normalizedTarget) {
      continue;
    }

    fallback ??= option;
    if (normalizedClientId == null ||
        normalizedClientId.isEmpty ||
        option.clientId == normalizedClientId) {
      return option;
    }
  }

  return fallback;
}

String _fallbackLabel(String value, String fallback) {
  final trimmed = value.trim();
  if (trimmed.isNotEmpty) {
    return trimmed;
  }

  return fallback;
}
