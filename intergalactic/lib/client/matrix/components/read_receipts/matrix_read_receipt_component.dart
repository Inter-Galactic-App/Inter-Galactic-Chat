import 'dart:async';

import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:matrix/matrix_api_lite/model/sync_update.dart';

class MatrixReadReceiptComponent
    implements
        ReadReceiptComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener,
        DisposableComponent {
  @override
  MatrixClient client;
  @override
  MatrixRoom room;

  static const String publicReadReceiptsKey =
      "chat.commet.public_read_receipts";

  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  late final StreamSubscription<void> _timelineLoadedSubscription;
  bool _disposed = false;

  @override
  Stream<String> get onReadReceiptsUpdated => _controller.stream;

  MatrixReadReceiptComponent(this.client, this.room) {
    _timelineLoadedSubscription =
        room.onTimelineLoaded.stream.listen(onTimelineLoaded);
  }

  Map<String, String> userToPreviousReceipt = {};

  @override
  bool? get usePublicReadReceiptsForRoom {
    var publicReadReceiptsForRoom = room
        .matrixRoom.roomAccountData[publicReadReceiptsKey]?.content["enabled"];
    return publicReadReceiptsForRoom is bool ? publicReadReceiptsForRoom : null;
  }

  @override
  Future<void> setUsePublicReadReceiptsForRoom(bool? value) async =>
      await client.matrixClient.setAccountDataPerRoom(
        client.matrixClient.userID!,
        room.matrixRoom.id,
        publicReadReceiptsKey,
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

    for (var event in ephemeral) {
      if (event.type == "m.receipt") {
        for (var key in event.content.keys) {
          var e = (event.content[key]! as Map<String, dynamic>)["m.read"];
          if (e == null) continue;

          if (e is Map<String, dynamic>) {
            for (var k in e.keys) {
              var lastEvent = userToPreviousReceipt[k];
              if (lastEvent != null) {
                _emitReceiptUpdated(lastEvent);
              }

              userToPreviousReceipt[k] = key;
            }
          }

          _emitReceiptUpdated(key);
        }
      }
    }

    client.matrixClient.receiptsPublicByDefault = client
        .getComponent<MatrixUserPresenceComponent>()!
        .usePublicReadReceipts;
  }

  void handleEvent(String eventId, String userId) {
    if (_disposed) {
      return;
    }

    var lastEvent = userToPreviousReceipt[userId];
    if (lastEvent != null) {
      _emitReceiptUpdated(lastEvent);
    }

    userToPreviousReceipt[userId] = eventId;
    _emitReceiptUpdated(eventId);
  }

  void onTimelineLoaded(void event) {}

  @override
  List<String>? getReceipts(TimelineEvent event) {
    if (room.timeline == null) {
      return null;
    }

    var timeline = (room.timeline as MatrixTimeline);
    if (timeline.matrixTimeline == null) {
      return null;
    }

    if (event is! MatrixTimelineEvent) return [];

    var receipts = event.event.receipts;

    for (var receipt in receipts) {
      userToPreviousReceipt[receipt.user.id] = event.eventId;
    }

    return receipts
        .where((i) => i.user.id != client.self!.identifier)
        .map((i) => i.user.id)
        .toList();
  }

  void _emitReceiptUpdated(String eventId) {
    if (!_disposed && !_controller.isClosed) {
      _controller.add(eventId);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _timelineLoadedSubscription.cancel();
    userToPreviousReceipt.clear();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
