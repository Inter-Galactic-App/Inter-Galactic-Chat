import 'dart:async';

import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix_api_lite/model/sync_update.dart';

class MatrixTypingIndicatorsComponent
    implements
        TypingIndicatorComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener,
        DisposableComponent {
  @override
  MatrixClient client;
  @override
  MatrixRoom room;

  MatrixTypingIndicatorsComponent(this.client, this.room);

  static const String publicTypingIndicatorKey =
      "chat.commet.private_typing_indicator";

  final StreamController<void> _controller = StreamController.broadcast();
  bool _disposed = false;

  /// Mirrors the SDK's own typing expiry so the UI cannot outlive it.
  ///
  /// `Room.setEphemeral` starts a `client.typingIndicatorTimeout` timer on
  /// every `m.typing` update and, when it fires, silently drops the ephemeral.
  /// Nothing observes that: [typingUsers] reads empty from then on, but this
  /// stream only fires on sync, so a listener that last heard "X is typing"
  /// keeps showing it until the next typing update for the room - which, if
  /// the stop update was missed, is whenever someone next types. Firing once
  /// more when the SDK clears makes the indicator leave on its own.
  Timer? _expiryNotification;

  @override
  bool? get typingIndicatorEnabledForRoom {
    var publicTypingIndicatorForRoom = room
        .matrixRoom
        .roomAccountData[publicTypingIndicatorKey]
        ?.content["enabled"];
    return publicTypingIndicatorForRoom is bool
        ? publicTypingIndicatorForRoom
        : null;
  }

  @override
  Future<void> setTypingIndicatorEnabledForRoom(bool? value) async =>
      await client.matrixClient.setAccountDataPerRoom(
        client.matrixClient.userID!,
        room.matrixRoom.id,
        publicTypingIndicatorKey,
        {"enabled": value},
      );

  @override
  onSync(JoinedRoomUpdate update) {
    if (_disposed) {
      return;
    }

    final ephemeral = update.ephemeral;

    if (ephemeral == null) {
      return;
    }

    if (ephemeral.any((e) => e.type == "m.typing")) {
      final typingCount = typingUsers.length;
      Log.d(
        'Typing update received users=$typingCount',
        category: LogCategory.matrix,
        source: 'typing-indicators',
      );
      _notifyTypingUsersUpdated();
      _scheduleExpiryNotification(typingCount);
    }
  }

  void _notifyTypingUsersUpdated() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  void _scheduleExpiryNotification(int typingCount) {
    _expiryNotification?.cancel();
    _expiryNotification = null;
    if (typingCount == 0) {
      return;
    }

    // Just after the SDK's timer, never before it: firing early would re-read
    // the same non-empty list and change nothing.
    _expiryNotification = Timer(
      client.matrixClient.typingIndicatorTimeout +
          const Duration(milliseconds: 100),
      () {
        _expiryNotification = null;
        if (_disposed) {
          return;
        }
        Log.d(
          'Typing indicator expired locally users=${typingUsers.length}',
          category: LogCategory.matrix,
          source: 'typing-indicators',
        );
        _notifyTypingUsersUpdated();
      },
    );
  }

  @override
  Stream<void> get onTypingUsersUpdated => _controller.stream;

  @override
  List<Member> get typingUsers => room.matrixRoom.typingUsers
      .where((element) => client.self?.identifier != element.id)
      .map((e) => MatrixMember(client, e))
      .toList();

  @override
  Future<void> setTypingStatus(bool status) async {
    if (_disposed) {
      return;
    }

    var typingIndicatorEnabled = client
        .getComponent<MatrixUserPresenceComponent>()!
        .typingIndicatorEnabled;
    if (typingIndicatorEnabledForRoom ?? typingIndicatorEnabled) {
      return room.matrixRoom.setTyping(status, timeout: 2000);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _expiryNotification?.cancel();
    _expiryNotification = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
