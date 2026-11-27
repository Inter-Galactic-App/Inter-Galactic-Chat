import 'dart:async';

import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixSoundboardRoomComponent
    extends RoomComponent<MatrixClient, MatrixRoom>
    implements MatrixRoomSyncListener {
  MatrixSoundboardRoomComponent(super.client, super.room);

  @override
  onSync(matrix.JoinedRoomUpdate update) {
    final events = update.timeline?.events;
    if (events == null || events.isEmpty) {
      return;
    }

    for (final event in events) {
      unawaited(
        _handleTimelineEvent(event)
            .catchError((Object error, StackTrace stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to handle soundboard play event',
          );
        }),
      );
    }
  }

  Future<void> _handleTimelineEvent(matrix.MatrixEvent event) async {
    final soundboardEvent = await _resolveSoundboardEvent(event);
    if (soundboardEvent == null) {
      return;
    }

    await soundboardPlaybackService.handleMatrixPlayEvent(
      client,
      room,
      soundboardEvent.content,
      originServerTs: soundboardEvent.originServerTs,
      senderId: soundboardEvent.senderId,
    );
  }

  Future<matrix.Event?> _resolveSoundboardEvent(
    matrix.MatrixEvent event,
  ) async {
    final timelineEvent = matrix.Event.fromMatrixEvent(event, room.matrixRoom);
    if (timelineEvent.type == SoundboardEventTypes.play) {
      return timelineEvent;
    }

    if (timelineEvent.type != matrix.EventTypes.Encrypted) {
      return null;
    }

    final shouldTryDecrypt = MatrixVoipRoomComponent.isVoipRoom(room);
    if (!shouldTryDecrypt) {
      return null;
    }

    matrix.Event? decrypted;
    try {
      decrypted =
          await client.matrixClient.encryption?.decryptRoomEvent(timelineEvent);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to decrypt possible soundboard play event in ${room.identifier}',
      );
      return null;
    }

    if (decrypted?.type == SoundboardEventTypes.play) {
      Log.i('Resolved encrypted soundboard play event in ${room.identifier}');
      return decrypted;
    }

    return null;
  }
}
