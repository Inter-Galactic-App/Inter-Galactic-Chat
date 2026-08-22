import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component_registry.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_room_permissions.dart';
import 'package:intergalactic/client/matrix/matrix_room_preview.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:intergalactic/client/space_child.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/exponential_backoff.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:intergalactic/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'matrix_peer.dart';

class MatrixSpace extends Space {
  late matrix.Room _matrixRoom;
  late matrix.Client _matrixClient;
  late MatrixClient _client;
  late MatrixRoomPermissions _permissions;
  late String _displayName;

  final StreamController<void> _onUpdate = StreamController.broadcast();
  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);
  final NotifyingList<RoomPreview> _previews =
      NotifyingList.empty(growable: true);

  NotifyingList<Space> _subspaces = NotifyingList.empty(growable: true);

  final StreamController<Room> _onChildUpdated = StreamController.broadcast();
  final Map<String, StreamSubscription> _roomUpdateSubscriptions = {};

  ImageProvider? _avatar;

  Uri? _avatarUrl;
  bool ignoreNextAvatarUpdate = false;

  bool _fullyLoaded = false;

  late final List<SpaceComponent<MatrixClient, MatrixSpace>> _components;

  matrix.Room get matrixRoom => _matrixRoom;
  @override
  String get topic => _matrixRoom.topic;

  @override
  String get developerInfo =>
      const JsonEncoder.withIndent('  ').convert(_matrixRoom.states);

  @override
  Color get color => MatrixPeer.hashColor(_matrixRoom.id);

  // cache the result of push rule because this was becoming an expensive operation for ui stuff
  matrix.PushRuleState? _pushRule;
  @override
  PushRule get pushRule {
    if (_pushRule == null) {
      _pushRule = _readPushRuleState();
    }

    switch (_pushRule!) {
      case matrix.PushRuleState.notify:
        return PushRule.notify;
      case matrix.PushRuleState.mentionsOnly:
        return PushRule.mentionsOnly;
      case matrix.PushRuleState.dontNotify:
        return PushRule.dontNotify;
    }
  }

  @override
  Future<void> setPushRule(PushRule rule) async {
    final newRule = switch (rule) {
      PushRule.notify => matrix.PushRuleState.notify,
      PushRule.mentionsOnly => matrix.PushRuleState.mentionsOnly,
      PushRule.dontNotify => matrix.PushRuleState.dontNotify,
    };

    await _setPushRuleState(newRule);
    _pushRule = newRule;
    _onUpdate.add(null);
  }

  matrix.PushRuleState _readPushRuleState() {
    final globalPushRules = _matrixRoom.client.globalPushRules;
    if (globalPushRules == null) {
      return matrix.PushRuleState.notify;
    }

    final overridePushRules = globalPushRules.override;
    if (overridePushRules != null) {
      for (final pushRule in overridePushRules) {
        if (pushRule.ruleId != _matrixRoom.id) {
          continue;
        }

        final actions = List<Object?>.from(pushRule.actions)
          ..remove("dont_notify")
          ..remove("coalesce");
        if (actions.isEmpty) {
          return matrix.PushRuleState.dontNotify;
        }
        return matrix.PushRuleState.notify;
      }
    }

    final roomPushRules = globalPushRules.room;
    if (roomPushRules != null) {
      for (final pushRule in roomPushRules) {
        if (pushRule.ruleId != _matrixRoom.id) {
          continue;
        }

        final actions = List<Object?>.from(pushRule.actions)
          ..remove("dont_notify")
          ..remove("coalesce");
        if (actions.isEmpty) {
          return matrix.PushRuleState.mentionsOnly;
        }
        break;
      }
    }

    return matrix.PushRuleState.notify;
  }

  Future<void> _setPushRuleState(matrix.PushRuleState newState) async {
    final currentState = _pushRule ?? _readPushRuleState();
    if (newState == currentState) {
      return;
    }

    switch (newState) {
      case matrix.PushRuleState.notify:
        if (currentState == matrix.PushRuleState.dontNotify) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.override,
            _matrixRoom.id,
          );
        } else if (currentState == matrix.PushRuleState.mentionsOnly) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
          );
        }
        break;
      case matrix.PushRuleState.mentionsOnly:
        if (currentState == matrix.PushRuleState.dontNotify) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.override,
            _matrixRoom.id,
          );
          await _matrixRoom.client.setPushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
            [],
          );
        } else if (currentState == matrix.PushRuleState.notify) {
          await _matrixRoom.client.setPushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
            [],
          );
        }
        break;
      case matrix.PushRuleState.dontNotify:
        if (currentState == matrix.PushRuleState.mentionsOnly) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
          );
        }
        await _matrixRoom.client.setPushRule(
          matrix.PushRuleKind.override,
          _matrixRoom.id,
          [],
          conditions: [
            matrix.PushCondition(
              kind: matrix.PushRuleConditions.eventMatch.name,
              key: 'room_id',
              pattern: _matrixRoom.id,
            ),
          ],
        );
        break;
    }
  }

  @override
  RoomVisibility get visibility {
    if (_matrixRoom.joinRules == null) {
      return RoomVisibilityPublic();
    }

    return MatrixRoom.visibilityFromMatrixJoinRules(
      _matrixRoom.joinRules,
      _matrixRoom.getState(matrix.EventTypes.RoomJoinRules)?.content,
    );
  }

  @override
  ImageProvider<Object>? get avatar => _avatar;

  @override
  List<RoomPreview> get childPreviews => _previews;

  @override
  Client get client => _client;

  @override
  String get displayName => _displayName;

  @override
  String get identifier => _matrixRoom.id;

  @override
  Stream<int> get onChildRoomPreviewAdded => _previews.onAdd;

  @override
  Stream<int> get onChildRoomPreviewRemoved => _previews.onRemove;

  @override
  Stream<void> get onChildRoomPreviewsUpdated => _previews.onListUpdated;

  @override
  Stream<Room> get onChildRoomUpdated => _onChildUpdated.stream;

  @override
  Stream<void> get onChildRoomsUpdated => _rooms.onListUpdated;

  @override
  List<Space> get subspaces => _subspaces;

  @override
  Stream<int> get onChildSpaceAdded => _subspaces.onAdd;

  @override
  Stream<int> get onChildSpaceRemoved => _subspaces.onRemove;

  @override
  Stream<int> get onRoomAdded => _rooms.onAdd;

  @override
  Stream<int> get onRoomRemoved => _rooms.onRemove;

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  void notifyUpdate() {
    _onUpdate.add(null);
  }

  @override
  Permissions get permissions => _permissions;

  @override
  List<Room> get rooms => _rooms;

  @override
  bool get fullyLoaded => _fullyLoaded;

  late List<StreamSubscription> _subscriptions;

  bool _isTopLevel = false;
  @override
  bool get isTopLevel => _isTopLevel;

  void _updateTopLevelStatus() {
    for (var room in _matrixClient.rooms.where((r) => r.isSpace)) {
      if (room.spaceChildren.any((child) => child.roomId == _matrixRoom.id)) {
        _isTopLevel = false;
        return;
      }
    }
    _isTopLevel = true;
  }

  MatrixSpace(
      MatrixClient client, matrix.Room room, matrix.Client matrixClient) {
    _matrixRoom = room;
    _matrixClient = matrixClient;
    _client = client;
    _displayName = room.getLocalizedDisplayname();
    _permissions = MatrixRoomPermissions(_matrixRoom);
    refresh();

    _matrixRoom.postLoad();
    _components = ComponentRegistry.getMatrixSpaceComponents(client, this);

    _subscriptions = List.from([
      client.onRoomAdded.listen((_) => updateRoomsList()),
      client.onRoomRemoved.listen(onClientRoomRemoved),
      client.matrixClient.onSync.stream.listen(onMatrixSync),
      client.matrixClient.onRoomState.stream
          .where((i) => i.roomId == room.id)
          .listen(onStateChanged),

      // Subscribe to all child update events
      _rooms.onAdd.listen(_onRoomAdded),
    ], growable: true);
  }

  void refresh() {
    _displayName = _matrixRoom.getLocalizedDisplayname();

    if (_matrixRoom.avatar != null && _matrixRoom.avatar != _avatarUrl) {
      updateAvatarFromRoomState();
    }

    updateRoomsList();
    _updateTopLevelStatus();
  }

  void onStateChanged(
      ({String roomId, matrix.StrippedStateEvent state}) event) {
    refresh();
  }

  @override
  Future<void> close() async {
    _rooms.close();
    _onChildUpdated.close();
    _onUpdate.close();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    for (var sub in _roomUpdateSubscriptions.values) {
      sub.cancel();
    }
    _roomUpdateSubscriptions.clear();
  }

  void updateAvatarFromRoomState() {
    _avatarUrl = _matrixRoom.avatar;
    if (ignoreNextAvatarUpdate) {
      ignoreNextAvatarUpdate = false;
      return;
    }

    if (_matrixRoom.avatar != null) {
      updateAvatar();
    }
  }

  void updateAvatar() {
    var avatar = MatrixMxcImage(_matrixRoom.avatar!, _matrixClient,
        doThumbnail: true,
        thumbnailHeight: 128,
        fullResHeight: 384,
        autoLoadFullRes: false);
    _avatar = avatar;
  }

  void onClientRoomRemoved(int index) {
    var leftRoom = client.rooms[index];
    if (containsRoom(leftRoom.identifier)) {
      _removeRoomUpdateSubscription(leftRoom.identifier);
      _rooms.remove(leftRoom);
      _onUpdate.add(null);

      // Update preview list
      _matrixClient.getSpaceHierarchy(identifier, maxDepth: 1).then((value) {
        var chunk = value.rooms
            .where((element) => element.roomId == leftRoom.identifier)
            .where((element) =>
                _matrixClient.getRoomById(element.roomId)?.membership !=
                matrix.Membership.join)
            .firstOrNull;
        if (chunk == null) return;

        var viaContent = _matrixRoom
            .getState(matrix.EventTypes.SpaceChild, chunk.roomId)
            ?.content["via"];

        List<String> via = const [];

        if (viaContent is List) {
          via = List.from(viaContent);
        }
        _previews
            .add(MatrixSpaceRoomChunkPreview(chunk, _matrixClient, via: via));
      }).catchError((Object error, StackTrace stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to refresh Matrix space preview after room removal',
          category: LogCategory.matrix,
          source: 'space-preview',
        );
      });
      _fullyLoaded = true;
    }
  }

  void updateRoomsList() {
    for (var child in _matrixRoom.spaceChildren) {
      var space = client.getSpace(child.roomId!);

      if (space == null) {
        subspaces.removeWhere((e) => e.identifier == child.roomId);
      }

      if (space != null) {
        if (!subspaces.any((s) => s.identifier == child.roomId)) {
          subspaces.add(space);

          _previews.removeWhere((p) => p.roomId == child.roomId);
        }
      } else {
        var room = client.getRoom(child.roomId!);

        if (room == null) {
          _removeRoomsWhere((e) => e.identifier == child.roomId);
        }

        if (room != null) {
          if (!containsRoom(room.identifier) &&
              !client.hasSpace(room.identifier)) {
            _rooms.add(room);
            _previews
                .removeWhere((element) => element.roomId == room.identifier);
          }
        }
      }
    }

    var orders = Map<String, String>.new();
    for (var child in _matrixRoom.spaceChildren) {
      if (child.roomId == null) continue;

      orders[child.roomId!] = child.order;
    }

    _rooms.sort((a, b) {
      var orderA = orders[a.identifier] ?? "";
      var orderB = orders[b.identifier] ?? "";

      return orderA.compareTo(orderB);
    });
  }

  void _onRoomAdded(int index) {
    var room = _rooms[index];
    _roomUpdateSubscriptions.putIfAbsent(
      room.identifier,
      () => room.onUpdate.listen((event) {
        _onChildUpdated.add(room);
        _onUpdate.add(null);
      }),
    );
  }

  void _removeRoomsWhere(bool Function(Room room) test) {
    final removedIds = _rooms
        .where(test)
        .map((room) => room.identifier)
        .toList(growable: false);
    for (final roomId in removedIds) {
      _removeRoomUpdateSubscription(roomId);
    }
    _rooms.removeWhere(test);
  }

  void _removeRoomUpdateSubscription(String roomId) {
    _roomUpdateSubscriptions.remove(roomId)?.cancel();
  }

  @override
  Future<Room> createRoom(String name, CreateRoomArgs args) async {
    var room = await client.createRoom(args);
    _matrixRoom.setSpaceChild(room.identifier);
    return room;
  }

  @override
  Future<List<RoomPreview>> fetchChildren() async {
    var response =
        await _matrixClient.getSpaceHierarchy(identifier, maxDepth: 5);

    return response.rooms
        .where((element) => element.roomId != identifier)
        .where((element) => !containsRoom(element.roomId))
        .map((e) => MatrixSpaceRoomChunkPreview(e, _matrixClient))
        .toList();
  }

  @override
  Future<void> changeAvatar(Uint8List bytes, String? mimeType) async {
    var avatar = Image.memory(bytes).image;
    ignoreNextAvatarUpdate = true;
    _avatar = avatar;

    await _matrixRoom.setAvatar(matrix.MatrixImageFile(
        bytes: bytes,
        name: "avatar",
        mimeType: mimeType == "" ? null : mimeType));
    _onUpdate.add(null);
  }

  @override
  Future<void> loadExtra() async {
    try {
      var response =
          await _matrixClient.getSpaceHierarchy(identifier, maxDepth: 1);

      // read child rooms
      response.rooms
          .where((element) => element.roomId != identifier)
          .where((element) =>
              _matrixClient.getRoomById(element.roomId)?.membership !=
              matrix.Membership.join)
          .forEach((element) {
        _previews.removeWhere((i) => i.roomId == element.roomId);

        var viaContent = _matrixRoom
            .getState(matrix.EventTypes.SpaceChild, element.roomId)
            ?.content["via"];

        List<String> via = const [];

        if (viaContent is List) {
          via = List.from(viaContent);
        }

        _previews
            .add(MatrixSpaceRoomChunkPreview(element, _matrixClient, via: via));
      });

      _fullyLoaded = true;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to load Matrix space hierarchy',
        category: LogCategory.matrix,
        source: 'space-load-extra',
      );
    }
  }

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    await _matrixRoom.setName(newName);
    _onUpdate.add(null);
  }

  @override
  Future<void> setSpaceChildRoom(Room room) async {
    await _matrixRoom.setSpaceChild(room.identifier);
    children.add(SpaceChildRoom(room));
    _onUpdate.add(null);
  }

  @override
  Future<void> setSpaceChildSpace(Space room) async {
    await _matrixRoom.setSpaceChild(room.identifier);
    children.add(SpaceChildSpace(room));
    _onUpdate.add(null);
  }

  @override
  bool containsRoom(String identifier) {
    return _rooms.any((element) => element.identifier == identifier);
  }

  @override
  T? getComponent<T extends SpaceComponent>() {
    for (var component in _components) {
      if (component is T) return component as T;
    }

    return null;
  }

  void onMatrixSync(matrix.SyncUpdate event) {
    final update = event.rooms?.join;
    if (update == null) return;

    var thisRoom = update[_matrixRoom.id];
    if (thisRoom != null) {
      if (thisRoom.timeline?.events
              ?.any((i) => i.type == matrix.EventTypes.SpaceChild) ==
          true) {
        Log.d(
          'A Matrix space child has been modified',
          category: LogCategory.matrix,
          source: 'space-load-extra',
        );
        unawaited(loadExtra());
      }
    }

    for (var id in update.keys) {
      if (roomsWithChildren.any((i) => i.identifier == id)) {
        _updateTopLevelStatus();
        _onUpdate.add(null);
      }
    }
  }

  @override
  List<SpaceChild> get children {
    List<SpaceChild> result = List.empty(growable: true);
    _matrixRoom.spaceChildren.sort((a, b) => a.order.compareTo(b.order));

    for (var child in _matrixRoom.spaceChildren) {
      var id = child.roomId;
      if (id == null) continue;

      var room = client.getRoom(id);
      if (room != null) {
        result.add(SpaceChildRoom(room));
        continue;
      }

      var space = client.getSpace(id);
      if (space != null) {
        result.add(SpaceChildSpace(space));
        continue;
      }
    }

    return result;
  }

  @override
  Future<void> setChildrenOrder(List<SpaceChild> ordered,
      {Function(double?)? onProgressChanged}) async {
    var orderKeys =
        List.generate(ordered.length, (i) => RandomUtils.getRandomString(10));
    orderKeys.sort();

    for (int i = 0; i < ordered.length; i++) {
      var item = ordered[i];

      var existing = _matrixRoom.spaceChildren
          .firstWhereOrNull((e) => e.roomId == item.id);

      var order = orderKeys[i];
      var suggested = existing?.suggested;
      var via = existing?.via;

      onProgressChanged?.call(i.toDouble() / ordered.length.toDouble());

      await exponentialBackoff(() async {
        await _matrixRoom.client.setRoomStateWithKey(
            _matrixRoom.id, matrix.EventTypes.SpaceChild, item.id, {
          'via': via,
          'order': order,
          if (suggested != null) 'suggested': suggested,
        });
      });
    }

    updateRoomsList();

    _onUpdate.add(());
  }

  @override
  Future<void> setTopic(String topic) async {
    await matrixRoom.setDescription(topic);
    _onUpdate.add(null);
  }

  @override
  Future<void> removeChild(SpaceChild<dynamic> child) async {
    await matrixRoom.removeSpaceChild(child.id);
  }
}
