import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Keeps a temporary room snooze account-scoped without replacing that room's
/// permanent notification rule. Matrix has no expiring push-rule primitive, so
/// the next running client removes an expired rule and record.
class MatrixRoomNotificationSnoozes {
  MatrixRoomNotificationSnoozes({
    required matrix.Client client,
    required this.clientId,
    required this.onRoomChanged,
  }) : _client = client;

  static const accountDataType = 'chat.intergalactic.room_snooze.v1';
  static const _rulePrefix = 'chat.intergalactic.room_snooze.v1.';

  final matrix.Client _client;
  final String clientId;
  final void Function(String roomId) onRoomChanged;
  final Map<String, RoomNotificationSnooze> _pending = {};
  Timer? _expiryTimer;
  Future<void>? _operation;
  bool _disposed = false;

  RoomNotificationSnooze? get(String roomId, {DateTime? now}) {
    final snooze = _pending[roomId] ?? _fromAccountData(roomId);
    if (snooze == null || !snooze.isActive(now ?? DateTime.now())) {
      return null;
    }
    return snooze;
  }

  Future<void> set(
    String roomId,
    Duration duration, {
    required String source,
    DateTime? now,
  }) => _runSerialized(() async {
    final currentTime = now ?? DateTime.now();
    final snooze = RoomNotificationSnooze(
      clientId: clientId,
      roomId: roomId,
      snoozedUntil: currentTime.add(duration),
      createdAt: currentTime,
      source: source,
    );

    await _client.setPushRule(
      matrix.PushRuleKind.override,
      ruleId(roomId),
      [],
      conditions: [
        matrix.PushCondition(
          kind: matrix.PushRuleConditions.eventMatch.name,
          key: 'room_id',
          pattern: roomId,
        ),
      ],
    );
    try {
      await _writeAccountData(roomId, snooze.toSyncedJson());
    } catch (_) {
      try {
        await _client.deletePushRule(
          matrix.PushRuleKind.override,
          ruleId(roomId),
        );
      } catch (_) {
        // The record was not written, so a later reconciliation cannot safely
        // identify this failed write. Preserve the original account-data error.
      }
      rethrow;
    }

    _pending[roomId] = snooze;
    onRoomChanged(roomId);
    _scheduleExpiry();
  });

  Future<void> clear(String roomId) => _runSerialized(() async {
    await _deleteSnoozeRule(roomId);
    await _writeAccountData(roomId, const {});
    _pending.remove(roomId);
    onRoomChanged(roomId);
    _scheduleExpiry();
  });

  void onSync(matrix.SyncUpdate update) {
    if (_disposed) {
      return;
    }

    final joinedRooms = update.rooms?.join;
    if (joinedRooms == null) {
      return;
    }
    for (final entry in joinedRooms.entries) {
      final hasSnoozeUpdate = entry.value.accountData?.any(
        (event) => event.type == accountDataType,
      );
      if (hasSnoozeUpdate != true) {
        continue;
      }
      _pending.remove(entry.key);
      onRoomChanged(entry.key);
    }
    _scheduleExpiry();
  }

  /// Reconciles expiry from synced per-room account data. It is intentionally
  /// called after sync and by a local timer; a homeserver cannot expire a custom
  /// push rule by itself while every Inter Galactic client is offline.
  Future<void> reconcile({DateTime? now}) => _runSerialized(() async {
    final currentTime = now ?? DateTime.now();
    for (final room in _client.rooms) {
      final snooze = _pending[room.id] ?? _fromAccountData(room.id);
      if (snooze == null) {
        continue;
      }
      if (snooze.isActive(currentTime)) {
        await _ensurePushRule(room.id);
        continue;
      }

      await _deleteSnoozeRule(room.id);
      await _writeAccountData(room.id, const {});
      _pending.remove(room.id);
      onRoomChanged(room.id);
    }
    _scheduleExpiry();
  });

  Future<void> dispose() async {
    // Set first: it is what stops _runSerialized and _scheduleExpiry from
    // starting anything new while the await below is pending.
    _disposed = true;
    _expiryTimer?.cancel();
    _expiryTimer = null;

    // Cancelling the timer does not reach work already running.
    // MatrixClient starts reconcile() with `unawaited`, so without this await
    // an in-flight reconcile keeps calling setAccountDataPerRoom and
    // deletePushRule after matrix.Client.dispose() has torn the client down.
    final inFlight = _operation;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Teardown must not fail because the operation being drained failed.
      }
    }
  }

  String ruleId(String roomId) =>
      '$_rulePrefix${base64UrlEncode(utf8.encode(roomId)).replaceAll('=', '')}';

  RoomNotificationSnooze? _fromAccountData(String roomId) {
    final room = _client.getRoomById(roomId);
    final content = room?.roomAccountData[accountDataType]?.content;
    return RoomNotificationSnooze.fromSyncedJson(
      content,
      clientId: clientId,
      roomId: roomId,
    );
  }

  Future<void> _writeAccountData(
    String roomId,
    Map<String, Object?> content,
  ) async {
    final userId = _client.userID;
    if (userId == null) {
      throw StateError(
        'Cannot sync a room snooze before Matrix login completes',
      );
    }
    await _client.setAccountDataPerRoom(
      userId,
      roomId,
      accountDataType,
      content,
    );
  }

  bool _hasPushRule(String roomId) =>
      _client.globalPushRules?.override?.any(
        (rule) => rule.ruleId == ruleId(roomId),
      ) ??
      false;

  Future<void> _ensurePushRule(String roomId) async {
    if (_hasPushRule(roomId)) {
      return;
    }
    await _client.setPushRule(
      matrix.PushRuleKind.override,
      ruleId(roomId),
      [],
      conditions: [
        matrix.PushCondition(
          kind: matrix.PushRuleConditions.eventMatch.name,
          key: 'room_id',
          pattern: roomId,
        ),
      ],
    );
  }

  Future<void> _deleteSnoozeRule(String roomId) async {
    try {
      await _client.deletePushRule(
        matrix.PushRuleKind.override,
        ruleId(roomId),
      );
    } on matrix.MatrixException catch (error) {
      if (error.error != matrix.MatrixError.M_NOT_FOUND) {
        rethrow;
      }
    }
  }

  Future<void> _runSerialized(Future<void> Function() action) {
    if (_disposed) {
      return Future.value();
    }

    final inFlight = _operation;
    final operation = () async {
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // A failed operation must not leave future snooze changes blocked.
        }
      }
      await action();
    }();
    _operation = operation;
    return operation.whenComplete(() {
      if (identical(_operation, operation)) {
        _operation = null;
      }
    });
  }

  void _scheduleExpiry() {
    if (_disposed) {
      return;
    }

    _expiryTimer?.cancel();
    DateTime? nearest;
    for (final room in _client.rooms) {
      final snooze = _pending[room.id] ?? _fromAccountData(room.id);
      if (snooze == null) {
        continue;
      }
      if (nearest == null || snooze.snoozedUntil.isBefore(nearest)) {
        nearest = snooze.snoozedUntil;
      }
    }
    if (nearest == null) {
      return;
    }

    final delay = nearest.difference(DateTime.now());
    _expiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(reconcile()),
    );
  }
}
