import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component_registry.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_space_link_validation.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_room_permissions.dart';
import 'package:intergalactic/client/matrix/push_rule_state_cache.dart';
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

class MatrixSpace extends Space implements PushRuleCacheHolder {
  late matrix.Room _matrixRoom;
  late matrix.Client _matrixClient;
  late MatrixClient _client;
  late MatrixRoomPermissions _permissions;
  late String _displayName;

  final StreamController<void> _onUpdate = StreamController.broadcast();
  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);
  final NotifyingList<RoomPreview> _previews = NotifyingList.empty(
    growable: true,
  );

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
  late final PushRuleStateCache _pushRuleCache = PushRuleStateCache(
    _readPushRuleState,
  );
  @override
  PushRule get pushRule {
    switch (_pushRuleCache.value) {
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
    _pushRuleCache.assign(newRule);
    _onUpdate.add(null);
    Log.i(
      'BUG-319 space setPushRule applied: $pushRuleDiagnostics',
      category: LogCategory.notifications,
      source: 'MatrixSpace',
    );
  }

  /// Drops the cached push-rule state so the next read reflects synced rules.
  ///
  /// The cache was previously invalidated only by a local [setPushRule] on this
  /// instance, so a space override could be set and still not appear in the
  /// app-wide notification settings until a restart built a fresh instance.
  /// That is BUG-319, confirmed by the owner's restart discriminator. Returns
  /// whether the state actually changed, so a sync carrying `m.push_rules`
  /// does not rebuild every space for nothing.
  @override
  bool invalidatePushRuleCache() {
    if (!_pushRuleCache.invalidate()) {
      return false;
    }
    _onUpdate.add(null);
    return true;
  }

  /// The three facts that separate the competing BUG-319 explanations, in one
  /// redaction-safe line: a stale cache shows `cached` disagreeing with
  /// `fresh`; a read-path mismatch shows both reading notify while `rules`
  /// names a rule; an enumeration mismatch shows an `instance` that differs
  /// from the one the matching `setPushRule` line reported.
  ///
  /// Added for BUG-319. It reads no state it does not already display and is
  /// safe to remove with that bug.
  String get pushRuleDiagnostics {
    final cached = _pushRuleCache.cachedValue?.name ?? 'unset';
    final fresh = _readPushRuleState().name;
    // Deliberately the read path's own client rather than _matrixClient: if
    // the two are ever different objects, that difference is the defect.
    final readClient = _matrixRoom.client;
    final globalPushRules = readClient.globalPushRules;
    final matches = <String>[];
    for (final entry in {
      'override': globalPushRules?.override,
      'room': globalPushRules?.room,
    }.entries) {
      for (final rule in entry.value ?? const <matrix.PushRule>[]) {
        if (rule.ruleId == _matrixRoom.id) {
          matches.add('${entry.key}(actions=${rule.actions.length})');
        }
      }
    }
    // Hashed, not raw: this line is written to the log file, and a raw room id
    // is private room metadata. Same shape as the notification routing logs.
    final space = MatrixClient.hash(_matrixRoom.id).substring(0, 12);
    return 'space=$space cached=$cached fresh=$fresh '
        'rules=${matches.isEmpty ? 'none' : matches.join('+')} '
        'instance=${identityHashCode(this)} '
        'sameClient=${identical(readClient, _matrixClient)}';
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
    final currentState = _pushRuleCache.value;
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
  List<Room> get rooms =>
      _rooms.where((room) => !_isTombstonedRoom(room)).toList(growable: false);

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
    MatrixClient client,
    matrix.Room room,
    matrix.Client matrixClient,
  ) {
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
    ({String roomId, matrix.StrippedStateEvent state}) event,
  ) {
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
    var avatar = MatrixMxcImage(
      _matrixRoom.avatar!,
      _matrixClient,
      doThumbnail: true,
      thumbnailHeight: 128,
      fullResHeight: 384,
      autoLoadFullRes: false,
    );
    _avatar = avatar;
  }

  void onClientRoomRemoved(int index) {
    var leftRoom = client.rooms[index];
    if (containsRoom(leftRoom.identifier)) {
      _removeRoomUpdateSubscription(leftRoom.identifier);
      _rooms.remove(leftRoom);
      _onUpdate.add(null);

      // Update preview list
      _matrixClient
          .getSpaceHierarchy(identifier, maxDepth: 1)
          .then((value) {
            var chunk = value.rooms
                .where((element) => element.roomId == leftRoom.identifier)
                .where(
                  (element) =>
                      _matrixClient.getRoomById(element.roomId)?.membership !=
                      matrix.Membership.join,
                )
                .firstOrNull;
            if (chunk == null) return;

            var viaContent = _matrixRoom
                .getState(matrix.EventTypes.SpaceChild, chunk.roomId)
                ?.content["via"];

            List<String> via = const [];

            if (viaContent is List) {
              via = List.from(viaContent);
            }
            _previews.add(
              MatrixSpaceRoomChunkPreview(chunk, _matrixClient, via: via),
            );
          })
          .catchError((Object error, StackTrace stackTrace) {
            Log.onError(
              error,
              stackTrace,
              content:
                  'Failed to refresh Matrix space preview after room removal',
              category: LogCategory.matrix,
              source: 'space-preview',
            );
          });
      _fullyLoaded = true;
    }
  }

  void updateRoomsList() {
    final childRoomIds = _matrixRoom.spaceChildren
        .map((child) => child.roomId)
        .whereType<String>()
        .toSet();
    _removeRoomsWhere(
      (room) =>
          !childRoomIds.contains(room.identifier) || _isTombstonedRoom(room),
    );

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

        if (room != null && !_isTombstonedRoom(room)) {
          if (!containsRoom(room.identifier) &&
              !client.hasSpace(room.identifier)) {
            _rooms.add(room);
            _previews.removeWhere(
              (element) => element.roomId == room.identifier,
            );
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
    await setSpaceChildRoom(room);
    return room;
  }

  @override
  Future<List<RoomPreview>> fetchChildren() async {
    var response = await _matrixClient.getSpaceHierarchy(
      identifier,
      maxDepth: 5,
    );

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

    await _matrixRoom.setAvatar(
      matrix.MatrixImageFile(
        bytes: bytes,
        name: "avatar",
        mimeType: mimeType == "" ? null : mimeType,
      ),
    );
    _onUpdate.add(null);
  }

  @override
  Future<void> loadExtra() async {
    try {
      var response = await _matrixClient.getSpaceHierarchy(
        identifier,
        maxDepth: 1,
      );

      // read child rooms
      response.rooms
          .where((element) => element.roomId != identifier)
          .where(
            (element) =>
                _matrixClient.getRoomById(element.roomId)?.membership !=
                matrix.Membership.join,
          )
          .forEach((element) {
            _previews.removeWhere((i) => i.roomId == element.roomId);

            var viaContent = _matrixRoom
                .getState(matrix.EventTypes.SpaceChild, element.roomId)
                ?.content["via"];

            List<String> via = const [];

            if (viaContent is List) {
              via = List.from(viaContent);
            }

            _previews.add(
              MatrixSpaceRoomChunkPreview(element, _matrixClient, via: via),
            );
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
    if (room is! MatrixRoom) {
      throw ArgumentError.value(room, 'room', 'Expected a Matrix room');
    }
    await setSpaceChildWithCanonicalParent(_matrixRoom, room.matrixRoom);
    children.add(SpaceChildRoom(room));
    _onUpdate.add(null);
  }

  @override
  Future<void> setSpaceChildSpace(Space room) async {
    if (room is! MatrixSpace) {
      throw ArgumentError.value(room, 'room', 'Expected a Matrix space');
    }
    await setSpaceChildWithCanonicalParent(_matrixRoom, room.matrixRoom);
    children.add(SpaceChildSpace(room));
    _onUpdate.add(null);
  }

  /// Repairs child links already created without a canonical parent. The
  /// action is explicit because it writes room state on the homeserver.
  bool get canRepairImagePackParentLinks =>
      canRepairSpaceImagePackParentLinks(_matrixRoom);

  Future<SpaceImagePackRepairResult> repairImagePackParentLinks() =>
      repairSpaceImagePackParentLinks(_matrixRoom);

  @override
  bool containsRoom(String identifier) {
    return _rooms.any(
      (element) =>
          element.identifier == identifier && !_isTombstonedRoom(element),
    );
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
      if (thisRoom.timeline?.events?.any(
            (i) => i.type == matrix.EventTypes.SpaceChild,
          ) ==
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
        if (_isTombstonedRoom(room)) continue;
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

  bool _isTombstonedRoom(Room room) {
    if (room is! MatrixRoom) return false;
    final replacement = room.matrixRoom.extinctInformations?.replacementRoom;
    return matrixRoomHasReplacementId(replacement);
  }

  @override
  Future<void> setChildrenOrder(
    List<SpaceChild> ordered, {
    Function(double?)? onProgressChanged,
  }) async {
    var orderKeys = List.generate(
      ordered.length,
      (i) => RandomUtils.getRandomString(10),
    );
    orderKeys.sort();

    for (int i = 0; i < ordered.length; i++) {
      var item = ordered[i];

      var existing = _matrixRoom.spaceChildren.firstWhereOrNull(
        (e) => e.roomId == item.id,
      );

      var order = orderKeys[i];
      var suggested = existing?.suggested;
      var via = existing?.via;

      onProgressChanged?.call(i.toDouble() / ordered.length.toDouble());

      await exponentialBackoff(() async {
        await _matrixRoom.client.setRoomStateWithKey(
          _matrixRoom.id,
          matrix.EventTypes.SpaceChild,
          item.id,
          {
            'via': via,
            'order': order,
            if (suggested != null) 'suggested': suggested,
          },
        );
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

/// Adds both sides of a Space link without replacing another primary Space.
/// The SDK's setSpaceChild writes the parent side without `canonical`, which
/// makes the Space's image packs disappear from rooms added through this UI.
@visibleForTesting
Future<void> setSpaceChildWithCanonicalParent(
  matrix.Room space,
  matrix.Room child,
) async {
  if (!space.isSpace) throw StateError('Parent room is not a Space');
  final via = [space.client.userID!.domain!];
  if (!hasValidSpaceVia(via)) throw StateError('No valid Space routing server');
  final makeCanonical =
      _hasCanonicalParent(child, space.id) || !_hasAnyCanonicalParent(child);

  final childContent = <String, Object?>{'via': via};
  await space.client.setRoomStateWithKey(
    space.id,
    matrix.EventTypes.SpaceChild,
    child.id,
    childContent,
  );
  _cacheSpaceLink(space, matrix.EventTypes.SpaceChild, child.id, childContent);

  final parentContent = <String, Object?>{
    'via': via,
    if (makeCanonical) 'canonical': true,
  };
  await space.client.setRoomStateWithKey(
    child.id,
    matrix.EventTypes.SpaceParent,
    space.id,
    parentContent,
  );
  _cacheSpaceLink(
    child,
    matrix.EventTypes.SpaceParent,
    space.id,
    parentContent,
  );
}

/// Sets a missing canonical parent for an existing valid Space child link.
@visibleForTesting
Future<void> setCanonicalSpaceParent({
  required matrix.Room space,
  required matrix.Room child,
  required List<String> via,
}) async {
  if (!hasValidSpaceVia(via)) throw ArgumentError.value(via, 'via');
  final content = <String, Object?>{'via': via, 'canonical': true};
  await space.client.setRoomStateWithKey(
    child.id,
    matrix.EventTypes.SpaceParent,
    space.id,
    content,
  );
  _cacheSpaceLink(child, matrix.EventTypes.SpaceParent, space.id, content);
}

bool _hasAnyCanonicalParent(matrix.Room child) =>
    child.states[matrix.EventTypes.SpaceParent]?.values.any(
      (state) => state.content['canonical'] == true,
    ) ??
    false;

bool _hasCanonicalParent(matrix.Room child, String spaceId) =>
    child
        .getState(matrix.EventTypes.SpaceParent, spaceId)
        ?.content['canonical'] ==
    true;

bool _hasCanonicalParentOtherThan(matrix.Room child, String spaceId) =>
    child.states[matrix.EventTypes.SpaceParent]?.entries.any(
      (entry) =>
          entry.key != spaceId && entry.value.content['canonical'] == true,
    ) ??
    false;

void _cacheSpaceLink(
  matrix.Room room,
  String type,
  String stateKey,
  Map<String, Object?> content,
) {
  (room.states[type] ??= <String, matrix.StrippedStateEvent>{})[stateKey] =
      matrix.StrippedStateEvent(
        type: type,
        content: content,
        senderId: room.client.userID!,
        stateKey: stateKey,
      );
}

class SpaceImagePackRepairResult {
  int repaired = 0;
  int alreadyCanonical = 0;
  int otherCanonicalParent = 0;
  int noPermission = 0;
  int unavailable = 0;
  int failed = 0;
}

/// MatrixRole labels power level 100 or higher as Admin. A Space moderator
/// might be allowed to edit child links, but cannot run a bulk room repair.
@visibleForTesting
bool canRepairSpaceImagePackParentLinks(matrix.Room space) {
  final userId = space.client.userID;
  return space.membership == matrix.Membership.join &&
      userId != null &&
      space.getPowerLevelByUserId(userId) >= 100;
}

@visibleForTesting
Future<SpaceImagePackRepairResult> repairSpaceImagePackParentLinks(
  matrix.Room space,
) async {
  if (!canRepairSpaceImagePackParentLinks(space)) {
    throw StateError('Space admin permission required for image-pack repair');
  }
  final result = SpaceImagePackRepairResult();
  final childLinks = space.states[matrix.EventTypes.SpaceChild]?.entries.toList(
    growable: false,
  );
  if (childLinks == null) return result;
  final userId = space.client.userID!;

  for (final entry in childLinks) {
    if (!hasValidSpaceVia(entry.value.content['via'])) continue;
    final child = space.client.getRoomById(entry.key);
    if (child == null || child.membership != matrix.Membership.join) {
      result.unavailable++;
      continue;
    }
    if (_hasCanonicalParentOtherThan(child, space.id)) {
      result.otherCanonicalParent++;
      continue;
    }
    if (_hasCanonicalParent(child, space.id)) {
      result.alreadyCanonical++;
      continue;
    }
    if (child.getPowerLevelByUserId(userId) < 100 ||
        !child.canChangeStateEvent(matrix.EventTypes.SpaceParent)) {
      result.noPermission++;
      continue;
    }
    try {
      await setCanonicalSpaceParent(
        space: space,
        child: child,
        via: List<String>.from(entry.value.content['via'] as List),
      );
      result.repaired++;
    } catch (_) {
      result.failed++;
    }
  }
  return result;
}
