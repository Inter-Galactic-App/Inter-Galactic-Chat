import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimelineEventEncrypted extends MatrixTimelineEvent
    implements TimelineEventEncrypted {
  MatrixTimelineEventEncrypted(super.event, {required super.client});

  @override
  Future<TimelineEvent<Client>?> attemptDecrypt(Room room) async {
    if (room is! MatrixRoom) {
      return null;
    }

    final encryption = client.getMatrixClient().encryption;
    var retryEvent = event;
    final source = retryEvent.originalSource;
    final decryptSource = source is matrix.Event ? source : retryEvent;

    if (encryption != null && retryEvent.type == matrix.EventTypes.Encrypted) {
      retryEvent = await encryption.decryptRoomEvent(
        decryptSource,
        store: true,
        updateType: matrix.EventUpdateType.history,
      );

      if (retryEvent.type != matrix.EventTypes.Encrypted) {
        return room.convertEvent(retryEvent);
      }
    }

    final requestInfo = matrixRoomSessionRequestInfoForBadEncryptedEvent(
      retryEvent,
    );
    if (requestInfo != null && encryption != null) {
      await encryption.keyManager.request(
        room.matrixRoom,
        requestInfo.sessionId,
        requestInfo.senderKey,
        tryOnlineBackup: true,
        onlineKeyBackupOnly: false,
      );
      retryEvent = await encryption.decryptRoomEvent(
        decryptSource,
        store: true,
        updateType: matrix.EventUpdateType.history,
      );
      return room.convertEvent(retryEvent);
    }
    return room.getEvent(retryEvent.eventId);
  }
}
