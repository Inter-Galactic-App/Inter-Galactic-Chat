import 'dart:async';

import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_aggregator.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/web/web_restore_snapshot.dart';
import 'package:intergalactic/client/stale_info.dart';
import 'package:intergalactic/client/tasks/client_connection_status_task.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/notifying_list.dart';

class ClientManager {
  WebRestoreSnapshot? webRestoreSnapshot;

  final Map<String, Client> _clients = {};

  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);

  final NotifyingList<Space> _spaces = NotifyingList.empty(growable: true);

  final AlertManager alertManager = AlertManager();
  late CallManager callManager;

  late final DirectMessagesAggregator directMessages;

  ClientManager() {
    directMessages = DirectMessagesAggregator(this);
    callManager = CallManager(this);
  }

  List<Room> get rooms => _rooms;

  List<Room> singleRooms({Client? filterClient}) {
    var result = List<Room>.empty(growable: true);
    for (var client in clients) {
      if (filterClient != null && client != filterClient) {
        continue;
      }

      var dmComp = client.getComponent<DirectMessagesComponent>();

      for (var room in client.rooms) {
        if (dmComp != null) {
          if (dmComp.isRoomDirectMessage(room)) {
            continue;
          }
        }

        if (client.spaces.any((space) => space.containsRoom(room.identifier))) {
          continue;
        }

        result.add(room);
      }
    }

    return result;
  }

  List<Space> get spaces => _spaces;

  final List<Client> _clientsList = List.empty(growable: true);
  final Map<Client, List<StreamSubscription>> _clientSubscriptions = {};

  List<Client> get clients => _clientsList;

  late StreamController<void> onSync = StreamController.broadcast();

  Stream<int> get onRoomAdded => _rooms.onAdd;

  Stream<int> get onRoomRemoved => _rooms.onRemove;

  Stream<int> get onSpaceAdded => _spaces.onAdd;

  Stream<int> get onSpaceRemoved => _spaces.onRemove;

  late StreamController<int> onClientAdded = StreamController.broadcast();

  late StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();

  late StreamController<Client> onClientUpdated = StreamController.broadcast();

  late StreamController<Space> onSpaceUpdated = StreamController.broadcast();
  late StreamController<Space> onSpaceChildUpdated =
      StreamController.broadcast();

  late StreamController<Room> onDirectMessageRoomUpdated =
      StreamController.broadcast();

  // int get directMessagesNotificationCount => directMessages.fold(
  //     0,
  //     (previousValue, element) =>
  //         previousValue + element.displayNotificationCount);

  static Future<ClientManager> init({bool isBackgroundService = false}) async {
    final newClientManager = ClientManager();

    newClientManager.webRestoreSnapshot = await MatrixClient.loadFromDB(
      newClientManager,
      isBackgroundService: isBackgroundService,
    );

    return newClientManager;
  }

  void addClient(Client client) {
    try {
      final existing = _clients[client.identifier];
      if (identical(existing, client)) {
        return;
      }

      if (existing != null) {
        Log.w(
          'Replacing an existing live client for ${client.identifier} so only one owner remains attached to that Matrix session.',
        );
        _detachClientSync(existing);
        unawaited(_detachClientInternal(existing, close: true));
      }

      _clients[client.identifier] = client;

      _clientsList
          .removeWhere((entry) => entry.identifier == client.identifier);
      _clientsList.add(client);

      for (int i = 0; i < client.rooms.length; i++) {
        _onClientAddedRoom(client, i);
      }

      for (int i = 0; i < client.spaces.length; i++) {
        _addSpace(client, i);
      }

      _clientSubscriptions[client] = [
        client.onSync.listen((_) => _synced()),
        client.onSelfUpdated.listen((_) => _clientUpdated(client)),
        client.onRoomAdded.listen((index) => _onClientAddedRoom(client, index)),
        client.onRoomRemoved
            .listen((index) => _onClientRemovedRoom(client, index)),
        client.onSpaceAdded.listen((index) => _addSpace(client, index)),
        client.onSpaceRemoved
            .listen((index) => _onClientRemovedSpace(client, index)),
        client.connectionStatusChanged.stream
            .listen((event) => _onClientConnectionStatusChanged(client, event)),
      ];

      onClientAdded.add(_clients.length - 1);
      if (client.self != null) {
        _clientUpdated(client);
      }
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to add client ${client.identifier} to ClientManager',
      );
    }
  }

  void _onClientConnectionStatusChanged(
      Client client, ClientConnectionStatusUpdate status) {
    if (status.status == ClientConnectionStatus.connected) {
      return;
    }

    if (backgroundTaskManager.tasks
        .whereType<ClientConnectionStatusTask>()
        .where((element) => element.client == client)
        .isEmpty) {
      backgroundTaskManager.addTask(ClientConnectionStatusTask(client, status));
    }
  }

  void _onClientAddedRoom(Client client, int index) {
    rooms.add(client.rooms[index]);
  }

  void _onClientRemovedRoom(Client client, int index) {
    var room = client.rooms[index];
    _rooms.remove(room);
  }

  void _onClientRemovedSpace(Client client, int index) {
    var space = client.spaces[index];
    _spaces.remove(space);
  }

  void _addSpace(Client client, int index) {
    var space = client.spaces[index];
    space.onUpdate.listen((_) => spaceUpdated(space));
    space.onChildRoomUpdated.listen((_) => spaceChildUpdated(space));
    spaces.add(client.spaces[index]);
  }

  void spaceUpdated(Space space) {
    onSpaceUpdated.add(space);
  }

  void spaceChildUpdated(Space space) {
    onSpaceChildUpdated.add(space);
  }

  void directMessageRoomUpdated(Room room) {
    onDirectMessageRoomUpdated.add(room);
  }

  Future<void> logoutClient(Client client) async {
    var closeDuringDetach = true;

    try {
      await client.logout();
    } catch (e, s) {
      // Server logout can fail when the account is in an error/disconnected
      // state (invalid token, unreachable homeserver).  Proceed with local
      // removal regardless — the client is already unusable and the user
      // cannot otherwise clear it from the account list.
      Log.onError(e, s,
          content:
              "logoutClient: server logout failed — force-removing account locally");
      closeDuringDetach = false;
      try {
        await client.close();
      } catch (e, s) {
        Log.onError(e, s,
            content:
                "logoutClient: fallback client.close() failed while force-removing account locally");
      }
    }

    await _detachClientInternal(
      client,
      close: closeDuringDetach,
      emitRemoved: true,
    );
  }

  void removeClient(Client client) {
    _detachClientFromCollections(client);
  }

  Future<void> disposeClientLocally(
    Client client, {
    bool emitRemoved = true,
  }) async {
    await _detachClientInternal(client, close: true, emitRemoved: emitRemoved);
  }

  bool isLoggedIn() {
    return _clients.values.any((element) => element.isLoggedIn());
  }

  Future<void> close() async {
    await Future.wait(
      _clients.values.map((client) => client.close()),
    );
  }

  void _synced() {
    onSync.add(null);
  }

  void _clientUpdated(Client client) {
    if (!identical(_clients[client.identifier], client)) {
      return;
    }

    onClientUpdated.add(client);
  }

  Client? getClient(String identifier) {
    return _clients[identifier];
  }

  Future<void> _detachClientInternal(
    Client client, {
    required bool close,
    bool emitRemoved = false,
  }) async {
    final clientInfo = emitRemoved
        ? _buildClientInfo(client, _staleClientIndex(client))
        : null;

    final subs = _clientSubscriptions.remove(client);
    if (subs != null) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }

    _removeClientRoomsAndSpaces(client);
    _detachClientFromCollections(client);

    if (close) {
      try {
        await client.close();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content:
              'Failed to close the local client ${client.identifier} while detaching it from ClientManager',
        );
      }
    }

    if (emitRemoved && clientInfo != null) {
      onClientRemoved.add(clientInfo);
    }
  }

  /// Synchronously removes [client]'s rooms/spaces from shared collections and
  /// detaches it from the identity maps.  Safe to call before scheduling the
  /// async close path via [_detachClientInternal].
  void _detachClientSync(Client client) {
    _removeClientRoomsAndSpaces(client);
    _detachClientFromCollections(client);
  }

  void _removeClientRoomsAndSpaces(Client client) {
    for (int i = rooms.length - 1; i >= 0; i--) {
      if (rooms[i].client == client) {
        rooms.removeAt(i);
      }
    }

    for (int i = spaces.length - 1; i >= 0; i--) {
      if (spaces[i].client == client) {
        spaces.removeAt(i);
      }
    }
  }

  void _detachClientFromCollections(Client client) {
    final current = _clients[client.identifier];
    if (identical(current, client)) {
      _clients.remove(client.identifier);
    }

    _clientsList.removeWhere((entry) => identical(entry, client));
  }

  int _staleClientIndex(Client client) {
    final clientIndex =
        _clientsList.indexWhere((entry) => identical(entry, client));
    if (clientIndex >= 0) {
      return clientIndex;
    }

    if (_clientsList.isEmpty) {
      return 0;
    }

    return _clientsList.length - 1;
  }

  StalePeerInfo _buildClientInfo(Client client, int index) {
    final self = client.self;
    return StalePeerInfo(
      index: index,
      displayName: self?.displayName,
      identifier: self?.identifier ?? client.identifier,
      avatar: self?.avatar,
    );
  }
}
