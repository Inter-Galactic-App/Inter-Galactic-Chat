import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';

class InboundShareDestination {
  const InboundShareDestination({
    required this.room,
    required this.accountLabel,
  });

  final Room room;
  final String accountLabel;

  String get roomId => room.identifier;
  String get roomName => room.displayName;
  Client get client => room.client;
  bool get isDirect =>
      client.getComponent<DirectMessagesComponent>()?.isRoomDirectMessage(
        room,
      ) ==
      true;
  String get conversationTypeLabel =>
      isDirect ? 'Direct conversation' : 'Group conversation';

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        roomName.toLowerCase().contains(normalized) ||
        roomId.toLowerCase().contains(normalized) ||
        accountLabel.toLowerCase().contains(normalized);
  }
}

class InboundShareDestinations {
  static List<InboundShareDestination> fromClients(
    Iterable<Client> clients, {
    required String Function(Client client) accountLabel,
  }) {
    final destinations = <InboundShareDestination>[];
    for (final client in clients) {
      for (final room in client.rooms) {
        if (!room.permissions.canSendMessage) continue;
        destinations.add(
          InboundShareDestination(
            room: room,
            accountLabel: accountLabel(client),
          ),
        );
      }
    }
    return sortByRecentActivity(
      destinations,
      lastActivity: (destination) => destination.room.lastEvent == null
          ? null
          : destination.room.lastEventTimestamp,
      roomName: (destination) => destination.roomName,
      accountLabel: (destination) => destination.accountLabel,
    );
  }

  static List<T> sortByRecentActivity<T>(
    Iterable<T> values, {
    required DateTime? Function(T value) lastActivity,
    required String Function(T value) roomName,
    required String Function(T value) accountLabel,
  }) {
    final sorted = values.toList(growable: false);
    sorted.sort((left, right) {
      final leftActivity = lastActivity(left);
      final rightActivity = lastActivity(right);
      if (leftActivity != null && rightActivity != null) {
        final recent = rightActivity.compareTo(leftActivity);
        if (recent != 0) return recent;
      } else if (leftActivity != null) {
        return -1;
      } else if (rightActivity != null) {
        return 1;
      }

      final room = roomName(
        left,
      ).toLowerCase().compareTo(roomName(right).toLowerCase());
      if (room != 0) return room;
      return accountLabel(
        left,
      ).toLowerCase().compareTo(accountLabel(right).toLowerCase());
    });
    return List.unmodifiable(sorted);
  }

  static List<T> search<T>(
    Iterable<T> values,
    String query,
    bool Function(T, String) matches,
  ) => List.unmodifiable(values.where((value) => matches(value, query)));
}
