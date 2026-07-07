import 'dart:async';

import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/stale_info.dart';

class DirectMessagesAggregator implements DirectMessagesInterface {
  ClientManager clientManager;
  bool _disposed = false;

  @override
  late List<Room> directMessageRooms;

  @override
  late List<Room> highlightedRoomsList;

  @override
  Stream<void> get onHighlightedRoomsListUpdated =>
      highlightedUpdateController.stream;

  @override
  Stream<void> get onRoomsListUpdated => updatedController.stream;

  final StreamController<void> updatedController = StreamController.broadcast();

  final StreamController<void> highlightedUpdateController =
      StreamController.broadcast();

  final List<StreamSubscription> _clientManagerSubscriptions = [];
  final Map<Object, List<StreamSubscription>> _componentSubscriptions = {};

  DirectMessagesAggregator(this.clientManager) {
    updateDirectMessageRooms();
    _syncClientComponentSubscriptions();

    _clientManagerSubscriptions.addAll([
      clientManager.onClientAdded.stream.listen(onClientAdded),
      clientManager.onClientRemoved.stream.listen(onClientRemoved),
    ]);
  }

  void updateDirectMessageRooms() {
    if (_disposed) {
      return;
    }

    var list = List<Room>.empty(growable: true);
    var highlightedList = List<Room>.empty(growable: true);

    for (var client in clientManager.clients) {
      final comp = client.getComponent<DirectMessagesComponent>();
      if (comp == null) continue;

      list.addAll(comp.directMessageRooms);
      highlightedList.addAll(comp.highlightedRoomsList);
    }

    directMessageRooms = list;
    highlightedRoomsList = highlightedList;

    if (!updatedController.isClosed) {
      updatedController.add(null);
    }
    if (!highlightedUpdateController.isClosed) {
      highlightedUpdateController.add(null);
    }
  }

  void onClientUpdatedList(void event) {
    updateDirectMessageRooms();
  }

  void onClientAdded(int index) {
    if (_disposed) {
      return;
    }

    _syncClientComponentSubscriptions();
    updateDirectMessageRooms();
  }

  void onClientRemoved(StalePeerInfo event) {
    if (_disposed) {
      return;
    }

    _syncClientComponentSubscriptions();
    updateDirectMessageRooms();
  }

  void onHighlightedListUpdated(void event) {
    updateDirectMessageRooms();
  }

  void _syncClientComponentSubscriptions() {
    final activeClients = clientManager.clients.toSet();
    final staleClients = _componentSubscriptions.keys
        .where((client) => !activeClients.contains(client))
        .toList();

    for (final staleClient in staleClients) {
      _cancelComponentSubscriptions(staleClient);
    }

    for (final client in clientManager.clients) {
      if (_componentSubscriptions.containsKey(client)) {
        continue;
      }

      final comp = client.getComponent<DirectMessagesComponent>();
      if (comp == null) {
        continue;
      }

      _componentSubscriptions[client] = [
        comp.onRoomsListUpdated.listen(onClientUpdatedList),
        comp.onHighlightedRoomsListUpdated.listen(onHighlightedListUpdated),
      ];
    }
  }

  void _cancelComponentSubscriptions(Object client) {
    final subscriptions = _componentSubscriptions.remove(client);
    if (subscriptions == null) {
      return;
    }

    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait(
      [
        ..._clientManagerSubscriptions,
        ..._componentSubscriptions.values.expand((subscriptions) {
          return subscriptions;
        }),
      ].map((subscription) => subscription.cancel()),
    );
    _clientManagerSubscriptions.clear();
    _componentSubscriptions.clear();
    // Broadcast close() futures only complete once every past subscriber has
    // cancelled after close, so awaiting them can hang dispose forever.
    if (!updatedController.isClosed) {
      unawaited(updatedController.close());
    }
    if (!highlightedUpdateController.isClosed) {
      unawaited(highlightedUpdateController.close());
    }
  }
}
