import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Favourite rooms, stored where every other Matrix client stores them.
///
/// Favourites used to be a device-local `SharedPreferences` string list, so a
/// room favourited on the phone was not favourited on desktop, and
/// `preferences.clear()` destroyed the list outright with no server copy to
/// restore from. Matrix covers this natively with the `m.favourite` room tag
/// (spec v1.19, room tagging), which syncs through per-room account data.
///
/// The contract this implements is
/// `docs/agent-control/review/favorite-room-sync-decision-2026-08-16.md`.
/// The parts worth restating here, because they are the ones a later change
/// could quietly break:
///
/// * Migration is PER MATRIX ACCOUNT and its marker is written only after
///   every tag request for that account has succeeded. A half-migrated
///   account must run again, not be recorded as done.
/// * Migration is a UNION. A favourite set in Element must never be removed
///   because this device had not heard of it.
/// * A failed tag write is a FAILURE, not a device-local favourite. Falling
///   back to the legacy list is exactly the "looks like it worked, syncs
///   nowhere" behaviour this replaces - and for a removal it would look like
///   the removal happened.
/// * Categories, collapse state and appearance stay local. They have no
///   standard Matrix equivalent, so a favourite learned from another client
///   legitimately shows up uncategorized.

/// The outcome of a single favourite membership or ordering write.
enum FavoriteWriteResult {
  /// The tag write (or, for a non-Matrix room, the local write) succeeded.
  applied,

  /// The request failed. The caller must surface this; it must NOT be
  /// presented as a favourite that merely has not synced yet.
  failed,
}

/// The outcome of the one-time per-account migration.
enum FavoriteMigrationOutcome {
  /// Tags were written (or there was nothing to write) and the marker is set.
  completed,

  /// The marker was already set for this account; nothing was done.
  alreadyMigrated,

  /// Not a Matrix account, not signed in, or initial sync has not finished.
  /// The marker is NOT set, so this is retried on a later sync.
  notReady,

  /// At least one tag request failed. The marker is NOT set.
  failed,
}

@immutable
class FavoriteMigrationResult {
  const FavoriteMigrationResult(
    this.outcome, {
    this.importedCount = 0,
    this.serverCount = 0,
  });

  final FavoriteMigrationOutcome outcome;

  /// How many local-only rooms were uploaded as new tags.
  final int importedCount;

  /// How many rooms already carried a server `m.favourite` tag.
  final int serverCount;

  bool get isComplete => outcome == FavoriteMigrationOutcome.completed;
}

/// Evenly spaced tag `order` values, strictly inside the spec's `[0, 1]`.
///
/// `(i + 1) / (count + 1)` leaves room at both ends, so a later client can
/// insert before the first or after the last entry without a rewrite.
@visibleForTesting
List<double> evenlySpacedOrders(int count) => [
  for (var i = 0; i < count; i++) (i + 1) / (count + 1),
];

/// The server's favourite rooms in their existing relative order.
///
/// Tags carrying an `order` sort ascending by it. The spec makes `order`
/// optional, and rooms without one have no defined position, so they are put
/// after the ordered ones and sorted by room id - arbitrary, but deterministic,
/// which is what matters for a migration that must produce the same answer on
/// every device.
@visibleForTesting
List<String> serverFavoritesInOrder(Map<String, double?> tagOrders) {
  final ordered = <String>[];
  final unordered = <String>[];
  for (final entry in tagOrders.entries) {
    (entry.value == null ? unordered : ordered).add(entry.key);
  }

  ordered.sort((a, b) {
    final byOrder = tagOrders[a]!.compareTo(tagOrders[b]!);
    return byOrder != 0 ? byOrder : a.compareTo(b);
  });
  unordered.sort();

  return [...ordered, ...unordered];
}

/// The migration's placement rule, as a pure function so it can be tested
/// without a homeserver.
///
/// Server-tagged rooms keep their membership and their relative order, and
/// come first. Local-only rooms are APPENDED, in the order the local list had
/// them. Appending is the deterministic rule this migration commits to: it
/// cannot reorder or drop anything another client set, which is the property
/// the decision record asks for. Interleaving by any local heuristic could.
@visibleForTesting
List<String> mergeFavoritesForMigration({
  required List<String> serverFavoriteRoomIds,
  required List<String> localFavoriteRoomIds,
}) {
  final seen = serverFavoriteRoomIds.toSet();
  return [
    ...serverFavoriteRoomIds,
    for (final id in localFavoriteRoomIds)
      if (seen.add(id)) id,
  ];
}

/// The single reader and writer of favourite membership and order.
///
/// UI must go through this rather than touching `Preferences` directly: after
/// migration the persisted list is not authoritative, and a widget that reads
/// it is reading a stale copy.
class FavoriteRoomStore {
  FavoriteRoomStore();

  final StreamController<void> _onChanged = StreamController.broadcast();

  /// Fires when a write lands or a migration completes. Remote `m.tag` changes
  /// arrive through the room's own `onUpdate`, which the favourites surfaces
  /// already listen to via `ClientManager`.
  Stream<void> get onChanged => _onChanged.stream;

  /// Writes the SDK does not echo back locally. `setRoomTag` performs the HTTP
  /// request but injects no synthetic `m.tag` sync event, so between the write
  /// and the next sync `matrixRoom.isFavourite` still reports the old value.
  /// Each entry is dropped as soon as the server agrees with it, which the
  /// next sync causes; it is never a second source of truth.
  final Map<String, bool> _pending = {};

  final Set<String> _migrating = {};

  bool isFavorite(Room room) {
    final pending = _pending[room.favoriteStorageId];
    if (pending != null) {
      final settled = _serverFavorite(room);
      if (settled == pending) {
        _pending.remove(room.favoriteStorageId);
      } else {
        return pending;
      }
    }

    if (_usesTags(room)) return _serverFavorite(room);

    return preferences.isRoomFavorite(
      room.favoriteStorageId,
      legacyRoomId: room.localId,
    );
  }

  Future<FavoriteWriteResult> setFavorite(Room room, bool favorite) async {
    if (!_usesTags(room)) {
      await preferences.setRoomFavorite(
        room.favoriteStorageId,
        favorite,
        legacyRoomId: room.localId,
      );
      _onChanged.add(null);
      return FavoriteWriteResult.applied;
    }

    final matrixRoom = (room as MatrixRoom).matrixRoom;
    try {
      if (favorite) {
        await matrixRoom.addTag(
          matrix.TagType.favourite,
          order: _appendOrderFor(room),
        );
      } else {
        await matrixRoom.removeTag(matrix.TagType.favourite);
      }
    } catch (error, trace) {
      Log.onError(error, trace);
      // Deliberately no local fallback: a device-only favourite is the
      // behaviour being removed, and for a removal it would show the room as
      // gone while the server still has it.
      return FavoriteWriteResult.failed;
    }

    _pending[room.favoriteStorageId] = favorite;
    _onChanged.add(null);
    return FavoriteWriteResult.applied;
  }

  /// Rooms in the order they should be shown.
  ///
  /// Matrix rooms sort by their tag `order`; a favourite with no order (one
  /// another client set without one) sorts last, by room id. Non-Matrix rooms
  /// keep the legacy local list's order.
  List<Room> sortFavorites(Iterable<Room> favorites) {
    final localOrder = preferences.getFavoriteRoomIds();
    final localIndex = <String, int>{
      for (var i = 0; i < localOrder.length; i++) localOrder[i]: i,
    };

    double? tagOrder(Room room) =>
        _usesTags(room) ? _favoriteTag(room)?.order : null;

    int localRank(Room room) =>
        localIndex[room.favoriteStorageId] ??
        localIndex[room.localId] ??
        localOrder.length;

    final rooms = favorites.toList();
    rooms.sort((a, b) {
      final orderA = tagOrder(a);
      final orderB = tagOrder(b);
      if (orderA != null && orderB != null) {
        final byOrder = orderA.compareTo(orderB);
        if (byOrder != 0) return byOrder;
        return a.identifier.compareTo(b.identifier);
      }
      // An ordered tag always precedes an unordered one, so a room another
      // client favourited without an order does not displace ours.
      if (orderA != null) return -1;
      if (orderB != null) return 1;

      final byLocal = localRank(a).compareTo(localRank(b));
      return byLocal != 0 ? byLocal : a.identifier.compareTo(b.identifier);
    });
    return rooms;
  }

  /// Writes [orderedStorageIds] as the favourite order.
  ///
  /// The ids are `favoriteStorageId`s, which is what the favourites surfaces
  /// already carry and which can name a room this device does not currently
  /// have loaded. The legacy list is written first so that un-migrated
  /// accounts, non-Matrix rooms and rooms not currently known keep a coherent
  /// order; then every KNOWN migrated Matrix room in that order gets an evenly
  /// spaced tag `order`, which is the part that syncs.
  ///
  /// Membership is untouched: no tag is added or removed here. A failure
  /// part-way leaves the rooms already written in their new order and reports
  /// [FavoriteWriteResult.failed] - the caller must not treat a partial
  /// reorder as applied. The same applies if [orderedStorageIds] is
  /// non-empty but none of it matches a known tag-migrated room: writing
  /// zero tags is not a working reorder, so that case reports
  /// [FavoriteWriteResult.failed] too rather than a vacuous
  /// [FavoriteWriteResult.applied].
  Future<FavoriteWriteResult> setFavoriteOrder({
    required List<String> orderedStorageIds,
    required Iterable<Room> knownRooms,
  }) async {
    await preferences.setFavoriteRoomOrder(orderedStorageIds);

    final byStorageId = <String, Room>{
      for (final room in knownRooms)
        if (_usesTags(room)) room.favoriteStorageId: room,
    };
    final taggedRooms = <Room>[
      for (final id in orderedStorageIds)
        if (byStorageId[id] case final room?) room,
    ];

    Log.d(
      'setFavoriteOrder: ${orderedStorageIds.length} id(s) in, '
      '${taggedRooms.length} matched a known tag-migrated room. ids=$orderedStorageIds '
      'matched=${taggedRooms.map((r) => r.favoriteStorageId).toList()}',
    );

    // A non-empty request that matches no known room is a total failure of
    // this write, not an ordering of zero rooms that happened to succeed -
    // see FavoriteWriteResult.applied's contract above.
    if (orderedStorageIds.isNotEmpty && taggedRooms.isEmpty) {
      Log.d(
        'setFavoriteOrder: no requested id matched a tag-migrated known '
        'room; reporting failed rather than a vacuous applied.',
      );
      return FavoriteWriteResult.failed;
    }

    final orders = evenlySpacedOrders(taggedRooms.length);
    for (var i = 0; i < taggedRooms.length; i++) {
      final room = taggedRooms[i];
      try {
        await (room as MatrixRoom).matrixRoom.addTag(
          matrix.TagType.favourite,
          order: orders[i],
        );
        Log.d(
          'setFavoriteOrder: addTag ok for ${room.favoriteStorageId} '
          'order=${orders[i]}',
        );
      } catch (error, trace) {
        Log.d(
          'setFavoriteOrder: addTag FAILED for ${room.favoriteStorageId} '
          'order=${orders[i]}: $error',
        );
        Log.onError(error, trace);
        return FavoriteWriteResult.failed;
      }
    }

    _onChanged.add(null);
    return FavoriteWriteResult.applied;
  }

  /// Runs the one-time migration for [client] if it is due.
  ///
  /// Safe to call on every sync: it is a no-op once the marker is set, and
  /// re-entrant calls for the same account are dropped rather than queued.
  Future<FavoriteMigrationResult> migrateClient(Client client) async {
    final userId = client.self?.identifier;
    if (userId == null || userId.isEmpty || userId == 'Error') {
      return const FavoriteMigrationResult(FavoriteMigrationOutcome.notReady);
    }
    if (preferences.isFavoriteRoomTagsMigrated(userId)) {
      return const FavoriteMigrationResult(
        FavoriteMigrationOutcome.alreadyMigrated,
      );
    }
    if (!_migrating.add(userId)) {
      return const FavoriteMigrationResult(FavoriteMigrationOutcome.notReady);
    }

    try {
      return await _migrate(client, userId);
    } finally {
      _migrating.remove(userId);
    }
  }

  Future<FavoriteMigrationResult> _migrate(Client client, String userId) async {
    // Only this account's current, known rooms. A stored id belonging to
    // another account must never become a tag write here.
    final knownRooms = <String, MatrixRoom>{
      for (final room in client.rooms)
        if (room is MatrixRoom) room.matrixRoom.id: room,
    };
    if (knownRooms.isEmpty) {
      return const FavoriteMigrationResult(FavoriteMigrationOutcome.notReady);
    }

    final serverOrders = <String, double?>{
      for (final entry in knownRooms.entries)
        if (entry.value.matrixRoom.tags[matrix.TagType.favourite]
            case final tag?)
          entry.key: tag.order,
    };

    final localFavorites = <String>[
      for (final id in preferences.getFavoriteRoomIds())
        if (_roomIdForStoredFavorite(id, knownRooms) case final roomId?) roomId,
    ];

    final merged = mergeFavoritesForMigration(
      serverFavoriteRoomIds: serverFavoritesInOrder(serverOrders),
      localFavoriteRoomIds: localFavorites,
    );
    final imported = merged.length - serverOrders.length;

    final orders = evenlySpacedOrders(merged.length);
    for (var i = 0; i < merged.length; i++) {
      try {
        final room = knownRooms[merged[i]]!;
        await room.matrixRoom.addTag(
          matrix.TagType.favourite,
          order: orders[i],
        );
        _pending[room.favoriteStorageId] = true;
      } catch (error, trace) {
        Log.onError(error, trace);
        // No marker: an account that failed part-way must run again.
        return FavoriteMigrationResult(
          FavoriteMigrationOutcome.failed,
          serverCount: serverOrders.length,
        );
      }
    }

    await preferences.markFavoriteRoomTagsMigrated(userId);
    _onChanged.add(null);
    return FavoriteMigrationResult(
      FavoriteMigrationOutcome.completed,
      importedCount: imported,
      serverCount: serverOrders.length,
    );
  }

  /// Resolves a stored favourite entry to a room id belonging to [userId].
  ///
  /// Entries are `"<user id>:<room id>"` since the stable-key change, and
  /// `"<client id>:<room id>"` before it. Either way the entry only resolves
  /// against a room THIS account currently knows, which is what keeps account
  /// A's leftovers from being written as account B's tags.
  String? _roomIdForStoredFavorite(
    String stored,
    Map<String, MatrixRoom> knownRooms,
  ) {
    for (final entry in knownRooms.entries) {
      final room = entry.value;
      if (stored == room.favoriteStorageId || stored == room.localId) {
        return entry.key;
      }
    }
    return null;
  }

  bool _usesTags(Room room) {
    if (room is! MatrixRoom) return false;
    final userId = room.client.self?.identifier;
    if (userId == null || userId.isEmpty) return false;
    return preferences.isFavoriteRoomTagsMigrated(userId);
  }

  matrix.Tag? _favoriteTag(Room room) =>
      (room as MatrixRoom).matrixRoom.tags[matrix.TagType.favourite];

  bool _serverFavorite(Room room) =>
      room is MatrixRoom && room.matrixRoom.isFavourite;

  /// A new favourite goes after everything currently ordered. Halving the gap
  /// to 1 keeps it inside the spec's range without rewriting other rooms.
  double _appendOrderFor(Room room) {
    var highest = 0.0;
    for (final other in room.client.rooms) {
      if (other is! MatrixRoom) continue;
      final order = other.matrixRoom.tags[matrix.TagType.favourite]?.order;
      if (order != null && order > highest) highest = order;
    }
    return highest + (1 - highest) / 2;
  }

  @visibleForTesting
  void clearForTesting() {
    _pending.clear();
    _migrating.clear();
  }
}

final FavoriteRoomStore favoriteRoomStore = FavoriteRoomStore();
