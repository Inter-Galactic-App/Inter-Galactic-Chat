import 'dart:async';

import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite/model/sync_update.dart';

const String interGalacticDirectRoomsAccountDataKey =
    'chat.intergalactic.direct_rooms.v1';
const String interGalacticGroupRoomsAccountDataKey =
    'chat.intergalactic.group_rooms.v1';

class MatrixDirectMessagesComponent
    extends DirectMessagesComponent<MatrixClient>
    implements NeedsPostLoginInit, DisposableComponent {
  @override
  MatrixClient client;

  @override
  List<Room> directMessageRooms = [];

  @override
  List<Room> highlightedRoomsList = [];

  @override
  Stream<void> get onRoomsListUpdated => listUpdated.stream;

  @override
  Stream<void> get onHighlightedRoomsListUpdated =>
      highlightedListUpdated.stream;

  StreamController<void> listUpdated = StreamController.broadcast();

  StreamController<void> highlightedListUpdated = StreamController.broadcast();

  String currentRoomId = "";

  Timer? _roomsListRefreshTimer;
  StreamSubscription<SyncUpdate>? _onSyncSubscription;
  StreamSubscription? _onSelectedRoomSubscription;
  StreamSubscription<int>? _roomAddedSubscription;
  StreamSubscription<int>? _roomRemovedSubscription;
  final Map<String, StreamSubscription<void>> _roomUpdateSubscriptions = {};
  Set<String>? _localExplicitGroupRoomIds;
  bool _disposed = false;

  MatrixDirectMessagesComponent(this.client) {
    _onSyncSubscription = client.getMatrixClient().onSync.stream.listen(
      onMatrixSync,
    );
    _onSelectedRoomSubscription = EventBus.onSelectedRoomChanged.stream.listen((
      value,
    ) {
      if (_disposed) {
        return;
      }

      currentRoomId = value?.identifier ?? "";
    });
  }

  @override
  void postLoginInit() {
    initializeDirectMessageRooms();
  }

  @override
  void initializeDirectMessageRooms() {
    if (_disposed) {
      return;
    }

    updateRoomsList();
    updateNotificationsList();
    _roomAddedSubscription ??= client.onRoomAdded.listen(onRoomAdded);
    _roomRemovedSubscription ??= client.onRoomRemoved.listen(onRoomRemoved);
  }

  @override
  bool isRoomDirectMessage(Room room) {
    if (room is! MatrixRoom) {
      return false;
    }

    if (isRoomExplicitlyGroup(room)) {
      return false;
    }

    if (room.matrixRoom.isDirectChat) {
      return true;
    }

    if (_appDirectRoomPartnerId(room) != null) {
      return true;
    }

    return _getJoinedOneToOnePartnerId(room) != null;
  }

  /// Returns whether this account has explicitly classified [room] as a group.
  ///
  /// Matrix falls back to treating a complete one-to-one room as a direct
  /// message. This local marker lets someone intentionally keep such a room in
  /// the regular room list after removing its `m.direct` tag.
  bool isRoomExplicitlyGroup(MatrixRoom room) {
    return _explicitGroupRoomIds().contains(room.identifier);
  }

  /// Marks [room] as a direct message with [partnerId] for this account.
  Future<void> markRoomAsDirectMessage(
    MatrixRoom room, {
    required String partnerId,
  }) async {
    await room.matrixRoom.addToDirectChat(partnerId);
    await _setRoomExplicitlyGroup(room.identifier, false);
    updateRoomsList();
  }

  /// Marks [room] as a regular group room for this account.
  Future<void> markRoomAsGroup(MatrixRoom room) async {
    // The local classification is written first. Removing the `m.direct` entry
    // first would leave the room with neither marker if this write then failed,
    // and a complete one-to-one room is classified as a direct message again
    // on the next list update.
    await _setRoomExplicitlyGroup(room.identifier, true);

    try {
      await room.matrixRoom.removeFromDirectChat();
    } catch (_) {
      try {
        await _setRoomExplicitlyGroup(room.identifier, false);
      } catch (error, stackTrace) {
        // The caller still gets the original failure. This account keeps the
        // group classification while the `m.direct` entry survives.
        Log.w(
          'Failed to restore the direct classification (${error.runtimeType})',
          category: LogCategory.matrix,
          source: 'MatrixDirectMessagesComponent',
        );
        Log.d(stackTrace, category: LogCategory.matrix);
      }
      rethrow;
    }

    updateRoomsList();
  }

  @override
  String? getDirectMessagePartnerId(Room room) {
    if (room is! MatrixRoom) {
      return null;
    }

    // Mirrors the gate in [isRoomDirectMessage]. Consumers key direct-message
    // presentation on a non-null partner id, so a room this account has
    // explicitly classified as a group must report none.
    if (isRoomExplicitlyGroup(room)) {
      return null;
    }

    if (room.matrixRoom.directChatMatrixID != null) {
      return room.matrixRoom.directChatMatrixID;
    }

    final appMarkerPartnerId = _appDirectRoomPartnerId(room);
    if (appMarkerPartnerId != null) {
      return appMarkerPartnerId;
    }

    return _getJoinedOneToOnePartnerId(room);
  }

  String? _getJoinedOneToOnePartnerId(MatrixRoom room) {
    if (room.isSpecialRoomType) {
      return null;
    }

    final selfId = client.matrixClient.userID ?? client.self?.identifier;
    if (selfId == null) {
      return null;
    }

    return joinedOneToOnePartnerIdFromSnapshot(
      selfId: selfId,
      joinedMemberIds: room.memberIds,
      isMembersListComplete: room.isMembersListComplete,
      joinedMemberCount: room.matrixRoom.summary.mJoinedMemberCount,
      isRoomInSpace: _roomHasKnownSpaceRelationship(room),
    );
  }

  static String? joinedOneToOnePartnerIdFromSnapshot({
    required String selfId,
    required Iterable<String> joinedMemberIds,
    required bool isMembersListComplete,
    required int? joinedMemberCount,
    bool isRoomInSpace = false,
  }) {
    if (isRoomInSpace ||
        !isMembersListComplete ||
        (joinedMemberCount != null && joinedMemberCount != 2)) {
      return null;
    }

    final joinedMemberIdSet = joinedMemberIds.toSet();
    if (joinedMemberIdSet.length != 2 || !joinedMemberIdSet.contains(selfId)) {
      return null;
    }

    return joinedMemberIdSet.firstWhere((id) => id != selfId);
  }

  static Map<String, String> directRoomMarkersFromContent(
    Map<String, Object?>? content,
  ) {
    if (content == null || content['v'] != 1) {
      return const {};
    }

    final rawRooms = content['rooms'];
    if (rawRooms is! Map) {
      return const {};
    }

    final markers = <String, String>{};
    for (final entry in rawRooms.entries) {
      final roomId = entry.key;
      final value = entry.value;
      if (roomId is! String || !_looksLikeMatrixRoomId(roomId)) {
        continue;
      }

      final partnerId = _partnerIdFromMarkerValue(value);
      if (partnerId == null || !_looksLikeMatrixUserId(partnerId)) {
        continue;
      }

      markers[roomId] = partnerId;
    }

    return markers;
  }

  static Map<String, Object?> directRoomMarkersToContent(
    Map<String, String> markers,
  ) {
    return {
      'v': 1,
      'rooms': {
        for (final entry in markers.entries)
          if (_looksLikeMatrixRoomId(entry.key) &&
              _looksLikeMatrixUserId(entry.value))
            entry.key: {'partner': entry.value},
      },
    };
  }

  static Set<String> explicitGroupRoomIdsFromContent(
    Map<String, Object?>? content,
  ) {
    if (content == null || content['v'] != 1) {
      return const {};
    }

    final rawRooms = content['rooms'];
    if (rawRooms is! List) {
      return const {};
    }

    return rawRooms.whereType<String>().where(_looksLikeMatrixRoomId).toSet();
  }

  static Map<String, Object?> explicitGroupRoomIdsToContent(
    Iterable<String> roomIds,
  ) {
    return {
      'v': 1,
      'rooms': roomIds.where(_looksLikeMatrixRoomId).toSet().toList()..sort(),
    };
  }

  static String? _partnerIdFromMarkerValue(Object? value) {
    if (value is String) {
      return value;
    }

    if (value is Map && value['partner'] is String) {
      return value['partner'] as String;
    }

    return null;
  }

  static bool _looksLikeMatrixRoomId(String value) {
    return value.startsWith('!') && value.contains(':');
  }

  static bool _looksLikeMatrixUserId(String value) {
    return value.startsWith('@') && value.contains(':');
  }

  @override
  Future<Room?> createDirectMessage(String userId) async {
    var mx = client.getMatrixClient();
    var roomId = await mx.startDirectChat(userId);

    await _rememberAppDirectRoomMarker(roomId: roomId, partnerId: userId);
    updateRoomsList();

    return client.getRoom(roomId);
  }

  void onRoomAdded(int index) {
    if (_disposed) {
      return;
    }

    var room = client.rooms[index];
    if (isRoomDirectMessage(room)) {
      updateRoomsList();
    }
  }

  void updateRoomsList() {
    if (_disposed) {
      return;
    }

    directMessageRooms = client.rooms
        .where((r) => isRoomDirectMessage(r))
        .toList();
    _refreshRoomUpdateSubscriptions();
    updateNotificationsList();

    listUpdated.add(null);
  }

  void onMatrixSync(SyncUpdate event) {
    if (_disposed) {
      return;
    }

    if (event.accountData?.any(
          (e) =>
              e.type == "m.direct" ||
              e.type == interGalacticDirectRoomsAccountDataKey ||
              e.type == interGalacticGroupRoomsAccountDataKey,
        ) ==
        true) {
      _localExplicitGroupRoomIds = null;
      updateRoomsList();
    } else if (_syncShouldRefreshRoomsList(event)) {
      _scheduleRoomsListUpdate();
    }

    if (event.rooms?.join?.entries.any(
          (e) => e.value.unreadNotifications != null,
        ) ==
        true) {
      updateNotificationsList();
    }
  }

  void onRoomRemoved(int index) {
    if (_disposed) {
      return;
    }

    var room = client.rooms[index];
    directMessageRooms.remove(room);
    _roomUpdateSubscriptions.remove(room.identifier)?.cancel();
    updateNotificationsList();
    listUpdated.add(null);
  }

  void updateNotificationsList() {
    if (_disposed) {
      return;
    }

    highlightedRoomsList = directMessageRooms
        .where(
          (e) =>
              e.displayNotificationCount > 0 && e.identifier != currentRoomId,
        )
        .toList();

    highlightedListUpdated.add(null);
  }

  void _scheduleRoomsListUpdate() {
    if (_disposed) {
      return;
    }

    if (_roomsListRefreshTimer?.isActive == true) {
      return;
    }

    _roomsListRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_disposed) {
        updateRoomsList();
      }
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _roomsListRefreshTimer?.cancel();
    _roomsListRefreshTimer = null;
    await _onSyncSubscription?.cancel();
    await _onSelectedRoomSubscription?.cancel();
    await _roomAddedSubscription?.cancel();
    await _roomRemovedSubscription?.cancel();
    for (final subscription in _roomUpdateSubscriptions.values) {
      await subscription.cancel();
    }
    _roomUpdateSubscriptions.clear();
    _onSyncSubscription = null;
    _onSelectedRoomSubscription = null;
    _roomAddedSubscription = null;
    _roomRemovedSubscription = null;
    await listUpdated.close();
    await highlightedListUpdated.close();
  }

  bool _syncShouldRefreshRoomsList(SyncUpdate event) {
    return event.rooms?.join?.values.any((room) {
          return _hasRoomClassificationEvent(room.state) ||
              _hasRoomClassificationEvent(room.timeline?.events);
        }) ==
        true;
  }

  bool _hasRoomClassificationEvent(Iterable<dynamic>? events) {
    return events?.any(
          (e) =>
              e.type == matrix.EventTypes.RoomMember ||
              e.type == matrix.EventTypes.SpaceChild ||
              e.type == matrix.EventTypes.SpaceParent,
        ) ==
        true;
  }

  String? _appDirectRoomPartnerId(MatrixRoom room) {
    return _directRoomMarkers()[room.identifier];
  }

  Map<String, String> _directRoomMarkers() {
    return directRoomMarkersFromContent(_directRoomMarkerContent());
  }

  Map<String, Object?>? _directRoomMarkerContent() {
    final content = client
        .matrixClient
        .accountData[interGalacticDirectRoomsAccountDataKey]
        ?.content;
    if (content == null) {
      return null;
    }

    return Map<String, Object?>.from(content);
  }

  Set<String> _explicitGroupRoomIds() {
    final locallyUpdatedRoomIds = _localExplicitGroupRoomIds;
    if (locallyUpdatedRoomIds != null) {
      return locallyUpdatedRoomIds;
    }

    final content = client
        .matrixClient
        .accountData[interGalacticGroupRoomsAccountDataKey]
        ?.content;
    if (content == null) {
      return const {};
    }

    return explicitGroupRoomIdsFromContent(Map<String, Object?>.from(content));
  }

  Future<void> _setRoomExplicitlyGroup(String roomId, bool group) async {
    final selfId = client.matrixClient.userID ?? client.self?.identifier;
    if (selfId == null) {
      throw StateError('A signed-in Matrix account is required.');
    }

    final roomIds = Set<String>.from(_explicitGroupRoomIds());
    if (group) {
      roomIds.add(roomId);
    } else {
      roomIds.remove(roomId);
    }

    await client.matrixClient.setAccountData(
      selfId,
      interGalacticGroupRoomsAccountDataKey,
      explicitGroupRoomIdsToContent(roomIds),
    );
    _localExplicitGroupRoomIds = roomIds;
  }

  Future<void> _rememberAppDirectRoomMarker({
    required String roomId,
    required String partnerId,
  }) async {
    final selfId = client.matrixClient.userID ?? client.self?.identifier;
    if (selfId == null) {
      return;
    }

    try {
      final markers = Map<String, String>.from(_directRoomMarkers());
      markers[roomId] = partnerId;
      await client.matrixClient.setAccountData(
        selfId,
        interGalacticDirectRoomsAccountDataKey,
        directRoomMarkersToContent(markers),
      );
    } catch (error, stackTrace) {
      Log.w(
        'Failed to persist direct room marker (${error.runtimeType})',
        category: LogCategory.matrix,
        source: 'MatrixDirectMessagesComponent',
      );
      Log.d(stackTrace, category: LogCategory.matrix);
    }
  }

  bool _roomHasKnownSpaceRelationship(MatrixRoom room) {
    return _roomHasSpaceParentState(room) ||
        client.spaces.any((space) => space.containsRoom(room.identifier));
  }

  bool _roomHasSpaceParentState(MatrixRoom room) {
    return room.matrixRoom.states[matrix.EventTypes.SpaceParent]?.isNotEmpty ==
        true;
  }

  void _refreshRoomUpdateSubscriptions() {
    final activeIds = directMessageRooms.map((room) => room.identifier).toSet();
    for (final roomId in _roomUpdateSubscriptions.keys.toList()) {
      if (!activeIds.contains(roomId)) {
        _roomUpdateSubscriptions.remove(roomId)?.cancel();
      }
    }

    for (final room in directMessageRooms) {
      _roomUpdateSubscriptions.putIfAbsent(
        room.identifier,
        () => room.onUpdate.listen((_) {
          if (!_disposed) {
            updateNotificationsList();
          }
        }),
      );
    }
  }
}
