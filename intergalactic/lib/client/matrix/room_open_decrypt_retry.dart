import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/debug/log.dart';

const defaultRoomOpenDecryptRetryCooldown = Duration(minutes: 10);

String _roomOpenDecryptRetryHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return sha256.convert(utf8.encode(text)).toString().substring(0, 12);
}

class RoomOpenDecryptRetryCoordinator {
  RoomOpenDecryptRetryCoordinator({
    this.cooldown = defaultRoomOpenDecryptRetryCooldown,
    DateTime Function()? now,
    Future<void> Function(Room room)? retryDecryptAll,
  })  : _now = now ?? DateTime.now,
        _retryDecryptAll =
            retryDecryptAll ?? ((room) => room.retryDecryptAll());

  final Duration cooldown;
  final DateTime Function() _now;
  final Future<void> Function(Room room) _retryDecryptAll;
  final Map<String, DateTime> _lastRetryByRoom = <String, DateTime>{};

  @visibleForTesting
  void clearCooldowns() {
    _lastRetryByRoom.clear();
  }

  Future<bool> maybeRetryForLoadedTimeline(
    Timeline timeline, {
    String trigger = 'chat_open',
  }) async {
    final room = timeline.room;
    if (!room.isE2EE) {
      return false;
    }

    final encryptedCount =
        timeline.events.whereType<TimelineEventEncrypted>().length;
    if (encryptedCount == 0) {
      return false;
    }

    final roomKey = room.localId;
    final now = _now();
    final lastRetry = _lastRetryByRoom[roomKey];
    if (lastRetry != null && now.difference(lastRetry) < cooldown) {
      Log.d(
        'E2EE chat-open decrypt retry skipped reason=cooldown '
        'trigger=$trigger room=${_roomOpenDecryptRetryHash(roomKey)} '
        'encrypted=$encryptedCount loaded=${timeline.events.length} '
        'cooldown_seconds=${cooldown.inSeconds}',
        category: LogCategory.matrix,
        source: 'matrix-e2ee-chat-open',
      );
      return false;
    }

    _lastRetryByRoom[roomKey] = now;
    Log.i(
      'E2EE chat-open decrypt retry starting '
      'reason=loaded_encrypted_events trigger=$trigger '
      'room=${_roomOpenDecryptRetryHash(roomKey)} '
      'encrypted=$encryptedCount loaded=${timeline.events.length} '
      'cooldown_seconds=${cooldown.inSeconds}',
      category: LogCategory.matrix,
      source: 'matrix-e2ee-chat-open',
    );

    try {
      await _retryDecryptAll(room);
      Log.i(
        'E2EE chat-open decrypt retry completed '
        'reason=loaded_encrypted_events trigger=$trigger '
        'room=${_roomOpenDecryptRetryHash(roomKey)} '
        'encrypted=$encryptedCount loaded=${timeline.events.length}',
        category: LogCategory.matrix,
        source: 'matrix-e2ee-chat-open',
      );
      return true;
    } catch (error, stackTrace) {
      _lastRetryByRoom.remove(roomKey);
      Log.onError(
        error,
        stackTrace,
        content:
            'E2EE chat-open decrypt retry failed reason=loaded_encrypted_events '
            'trigger=$trigger room=${_roomOpenDecryptRetryHash(roomKey)} '
            'encrypted=$encryptedCount loaded=${timeline.events.length}',
        category: LogCategory.matrix,
        source: 'matrix-e2ee-chat-open',
      );
      return false;
    }
  }
}
