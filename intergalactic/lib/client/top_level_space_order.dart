import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';

/// MSC3230's stable event type. It is room account data on each top-level
/// Space, private to the user and therefore shared only between that user's
/// devices.
const matrixSpaceOrderAccountDataType = 'm.space.order';
const matrixSpaceOrderLegacyAccountDataType = 'org.matrix.msc3230.space_order';

class TopLevelSpaceOrderStore {
  final Map<String, ({String order, String? baseline})> _pendingOrders = {};
  final Map<String, String?> _lastSyncedOrders = {};

  String? orderFor(Space space) {
    if (space is! MatrixSpace) return null;
    return _pendingOrders[space.localId]?.order ?? _readRemoteOrder(space);
  }

  /// The SDK does not synthesize a room-account-data event for a local write.
  /// A later sync either confirms the optimistic rank or replaces it with the
  /// server's newer value from another device.
  bool onClientSync(Client client) {
    if (client is! MatrixClient) return false;
    var changed = false;
    for (final space in client.spaces.whereType<MatrixSpace>()) {
      final pending = _pendingOrders[space.localId];
      final remote = _readRemoteOrder(space);
      if (pending != null &&
          (pendingOrderMatchesRemote(pending.order, remote) ||
              pendingOrderShouldYieldToRemote(pending.baseline, remote))) {
        _pendingOrders.remove(space.localId);
        changed = true;
      }

      final effective = orderFor(space);
      final previous = _lastSyncedOrders[space.localId];
      if (!_lastSyncedOrders.containsKey(space.localId) ||
          previous != effective) {
        changed = true;
      }
      _lastSyncedOrders[space.localId] = effective;
    }
    return changed;
  }

  /// A room-account-data sync only confirms our optimistic write when it
  /// contains the exact rank we wrote. The SDK keeps the older cached event
  /// after a local write, so any other value is still a stale snapshot.
  @visibleForTesting
  static bool pendingOrderMatchesRemote(String pending, String? remote) =>
      pending == remote;

  @visibleForTesting
  static bool pendingOrderShouldYieldToRemote(
    String? baseline,
    String? remote,
  ) => baseline != remote;

  /// Applies remote order only within an account. The places occupied by other
  /// accounts remain stable, because Matrix has no cross-account ordering.
  List<Space> apply(Iterable<Space> spaces) {
    final result = spaces.toList();
    final matrixClients = result
        .whereType<MatrixSpace>()
        .map((space) => space.client)
        .toSet();
    for (final client in matrixClients) {
      final indexes = <int>[];
      final accountSpaces = <Space>[];
      for (var index = 0; index < result.length; index++) {
        final space = result[index];
        if (space is MatrixSpace && space.client == client) {
          indexes.add(index);
          accountSpaces.add(space);
        }
      }
      accountSpaces.sort((a, b) {
        final aOrder = orderFor(a);
        final bOrder = orderFor(b);
        if (aOrder == null && bOrder == null) return 0;
        if (aOrder == null) return 1;
        if (bOrder == null) return -1;
        return aOrder.compareTo(bOrder);
      });
      for (var index = 0; index < indexes.length; index++) {
        result[indexes[index]] = accountSpaces[index];
      }
    }
    return result;
  }

  /// Imports the existing local order only when this account has no MSC3230
  /// event yet. This is called after sync, never while account data is cold.
  Future<void> migrateClient(
    Client client,
    Iterable<Space> orderedSpaces,
  ) async {
    if (client is! MatrixClient) return;
    final userId = client.getMatrixClient().userID;
    if (userId == null ||
        userId.isEmpty ||
        preferences.isSpaceOrderMigrated(userId)) {
      return;
    }
    final spaces = orderedSpaces
        .whereType<MatrixSpace>()
        .where((space) => space.client == client)
        .toList();
    if (spaces.isEmpty) return;
    if (spaces.any((space) => _readRemoteOrder(space) != null)) {
      await preferences.markSpaceOrderMigrated(userId);
      return;
    }
    await _writeOrders(spaces);
    await preferences.markSpaceOrderMigrated(userId);
  }

  /// Writes only the moved Space in the usual case. If an older client used an
  /// incompatible rank format or there is no rank gap left, it deliberately
  /// re-spaces this one account rather than touching any other account.
  Future<void> saveReorder({
    required List<Space> previous,
    required List<Space> reordered,
  }) async {
    final clients = reordered
        .whereType<MatrixSpace>()
        .map((s) => s.client)
        .toSet();
    for (final client in clients) {
      final oldIds = previous
          .whereType<MatrixSpace>()
          .where((s) => s.client == client)
          .map((s) => s.localId)
          .toList();
      final next = reordered
          .whereType<MatrixSpace>()
          .where((s) => s.client == client)
          .toList();
      final nextIds = next.map((s) => s.localId).toList();
      if (_sameIds(oldIds, nextIds)) continue;
      final moved = _movedSpace(oldIds, next);
      if (moved == null) {
        await _writeOrders(next);
        continue;
      }
      final position = next.indexOf(moved);
      final before = position == 0 ? null : orderFor(next[position - 1]);
      final after = position == next.length - 1
          ? null
          : orderFor(next[position + 1]);
      if ((position > 0 && before == null) ||
          (position < next.length - 1 && after == null)) {
        await _writeOrders(next);
        continue;
      }
      final rank = _rankBetween(before, after);
      if (rank == null) {
        await _writeOrders(next);
      } else {
        await _writeOrder(moved, rank);
      }
    }
  }

  MatrixSpace? _movedSpace(List<String> oldIds, List<MatrixSpace> next) {
    final nextIds = next.map((space) => space.localId).toList();
    final movedId = movedSpaceIdForTesting(oldIds, nextIds);
    return movedId == null
        ? null
        : next.firstWhere((space) => space.localId == movedId);
  }

  @visibleForTesting
  static String? movedSpaceIdForTesting(
    List<String> oldIds,
    List<String> nextIds,
  ) {
    if (oldIds.length != nextIds.length || _sameIds(oldIds, nextIds)) {
      return null;
    }
    for (final candidate in nextIds) {
      final oldWithout = oldIds.where((id) => id != candidate).toList();
      final nextWithout = nextIds.where((id) => id != candidate).toList();
      if (_sameIds(oldWithout, nextWithout)) return candidate;
    }
    return null;
  }

  static bool _sameIds(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  String? _readRemoteOrder(MatrixSpace space) {
    for (final type in [
      matrixSpaceOrderAccountDataType,
      matrixSpaceOrderLegacyAccountDataType,
    ]) {
      final content = space.matrixRoom.roomAccountData[type]?.content;
      if (content case final Map data when data['order'] is String) {
        final order = data['order'] as String;
        if (order.isNotEmpty) return order;
      }
    }
    return null;
  }

  Future<void> _writeOrders(List<MatrixSpace> spaces) async {
    for (var index = 0; index < spaces.length; index++) {
      await _writeOrder(spaces[index], _initialRank(index, spaces.length));
    }
  }

  Future<void> _writeOrder(MatrixSpace space, String order) async {
    final matrixClient = space.matrixRoom.client;
    final userId = matrixClient.userID;
    if (userId == null)
      throw StateError('Cannot save Space order before login');
    try {
      await matrixClient.setAccountDataPerRoom(
        userId,
        space.matrixRoom.id,
        matrixSpaceOrderAccountDataType,
        {'order': order},
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to save top-level Space order',
      );
      rethrow;
    }
    _pendingOrders[space.localId] = (
      order: order,
      baseline: _readRemoteOrder(space),
    );
  }

  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _width = 10;

  @visibleForTesting
  static String initialRankForTesting(int index, int count) {
    final max = BigInt.from(36).pow(_width) - BigInt.one;
    return _encode(max * BigInt.from(index + 1) ~/ BigInt.from(count + 1));
  }

  String _initialRank(int index, int count) =>
      initialRankForTesting(index, count);

  @visibleForTesting
  static String? rankBetweenForTesting(String? before, String? after) =>
      _rankBetween(before, after);

  static String? _rankBetween(String? before, String? after) {
    final max = BigInt.from(36).pow(_width) - BigInt.one;
    final left = before == null ? BigInt.zero : _decode(before);
    final right = after == null ? max : _decode(after);
    if (left == null ||
        right == null ||
        left >= right ||
        right - left <= BigInt.one) {
      return null;
    }
    return _encode((left + right) ~/ BigInt.two);
  }

  static BigInt? _decode(String value) {
    if (value.length != _width) return null;
    var result = BigInt.zero;
    for (final code in value.codeUnits) {
      final digit = _alphabet.indexOf(String.fromCharCode(code));
      if (digit < 0) return null;
      result = result * BigInt.from(36) + BigInt.from(digit);
    }
    return result;
  }

  static String _encode(BigInt value) {
    var remaining = value;
    final chars = List<String>.filled(_width, '0');
    for (var index = _width - 1; index >= 0; index--) {
      final digit = (remaining % BigInt.from(36)).toInt();
      chars[index] = _alphabet[digit];
      remaining ~/= BigInt.from(36);
    }
    return chars.join();
  }
}

final topLevelSpaceOrderStore = TopLevelSpaceOrderStore();
