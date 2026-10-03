import 'dart:async';

import 'package:intergalactic/client/matrix/components/emoticon/matrix_image_pack_compatibility.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixEmoticonStateManager {
  Map<String, dynamic> getState(String packKey);

  Map<String, dynamic> getAllStates();

  Future<void> setState(String packKey, Map<String, dynamic> content);

  Stream<void> get onStateChanged;

  String get id;
}

class MatrixEmoticonPersonalStateManager implements MatrixEmoticonStateManager {
  MatrixClient client;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonPersonalStateManager(this.client) {
    var mx = client.getMatrixClient();

    mx.onLoginStateChanged.stream
        .where((event) => event == matrix.LoginState.loggedIn)
        .listen((event) async {
          if (mx.accountDataLoading != null) {
            await mx.accountDataLoading;
          }

          onStateChangedController.add(null);
        });

    mx.onSync.stream.where((e) => e.accountData != null).listen((update) {
      if (update.accountData?.any(
            (e) =>
                e.type == "im.ponies.user_emotes" ||
                e.type == MatrixImagePackCompatibility.pickerOrderEventType ||
                e.type == MatrixImagePackCompatibility.legacyGlobalEventType ||
                e.type == MatrixImagePackCompatibility.stableGlobalEventType,
          ) ==
          true) {
        onStateChangedController.add(null);
      }
    });
  }

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  Map<String, dynamic> getAllStates() {
    var state = getState("im.ponies.user_emotes");
    if (state.isEmpty) return {};
    return {"im.ponies.user_emotes": state};
  }

  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) {
    return client.getMatrixClient().setAccountData(
      client.getMatrixClient().userID!,
      "im.ponies.user_emotes",
      content,
    );
  }

  @override
  Map<String, dynamic> getState(String packKey) {
    return client
            .getMatrixClient()
            .accountData['im.ponies.user_emotes']
            ?.content ??
        {};
  }

  @override
  String get id => client.identifier;
}

class MatrixEmoticonRoomStateManager implements MatrixEmoticonStateManager {
  matrix.Room room;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonRoomStateManager(this.room) {
    var mx = room.client;

    mx.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              (event.state.type ==
                      MatrixImagePackCompatibility.legacyRoomEventType ||
                  event.state.type ==
                      MatrixImagePackCompatibility.stableRoomEventType),
        )
        .listen((event) {
          onStateChangedController.add(null);
        });

    onStateChangedController.add(null);
  }

  @override
  Map<String, dynamic> getAllStates() {
    Map<String, dynamic> contents(String eventType) {
      final states = room.states[eventType];
      if (states is! Map) return {};
      return {
        for (final entry in (states as Map).entries)
          if (entry.key is String && entry.value is matrix.StrippedStateEvent)
            entry.key as String:
                (entry.value as matrix.StrippedStateEvent).content,
      };
    }

    return MatrixImagePackCompatibility.mergeRoomPackStates(
      legacy: contents(MatrixImagePackCompatibility.legacyRoomEventType),
      stable: contents(MatrixImagePackCompatibility.stableRoomEventType),
    );
  }

  @override
  Map<String, dynamic> getState(String packKey) {
    var states = getAllStates();
    var data = states[packKey];
    return data is Map<String, dynamic> ? data : {};
  }

  /// Writes the pack under both the stable and legacy event types.
  ///
  /// Each iteration is isolated. Sequential awaits with no isolation meant a
  /// failure on the stable write skipped the legacy one entirely, and readers
  /// that merge both formats then saw the two diverge - one carrying the new
  /// pack state and the other the old. Completing the second write and
  /// rethrowing afterwards keeps the formats agreeing on the common case where
  /// only one of them fails, and still surfaces the failure.
  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) async {
    Object? firstError;
    StackTrace? firstStack;
    var updatedLocalState = false;
    for (final eventType in [
      MatrixImagePackCompatibility.stableRoomEventType,
      MatrixImagePackCompatibility.legacyRoomEventType,
    ]) {
      try {
        final event = await room.client.setRoomStateWithKey(
          room.id,
          eventType,
          packKey,
          content,
        );
        final result = await room.getEventById(event);
        (room.states[eventType] ??=
                <String, matrix.StrippedStateEvent>{})[packKey] =
            result!;
        updatedLocalState = true;
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    // The state cache above is updated synchronously, but the previous code
    // waited for a later /sync echo before refreshing the component's pack
    // list. A just-created Space pack could therefore be visible in Settings
    // while `:shortcode:` still sent as plain text in its room.
    if (updatedLocalState) {
      onStateChangedController.add(null);
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  String get id => room.id;
}
