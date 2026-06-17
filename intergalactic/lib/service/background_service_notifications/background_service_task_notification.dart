import 'dart:async';
import 'dart:collection';

import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/service/background_service_task.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class BackgroundServiceTaskNotification extends BackgroundServiceTask {
  String roomId;
  String eventId;

  BackgroundServiceTaskNotification(this.roomId, this.eventId);
}

class BackgroundNotificationsManager {
  ServiceInstance? instance;

  BackgroundNotificationsManager(this.instance);

  Timer? shutdownTimer;

  List<Map<String, dynamic>> queue = List.empty(growable: true);

  Future<void> init() async {
    Log.i("Initializing Background Notifications Manager!");

    isHeadless = true;
    await NotificationManager.init(isBackgroundService: true);
    await NotificationManager.notifierLoading;

    if (fileCache == null) {
      fileCache = FileCache.getFileCacheInstance();

      if (fileCache != null) {
        await fileCache?.init();
      }
    }

    shortcutsManager.init();

    clientManager = await ClientManager.init(isBackgroundService: true);
  }

  void onReceived(Map<String, dynamic>? data) {
    if (data != null) {
      queue.add(data);
      final roomId = data["room_id"];
      final eventId = data["event_id"];
      Log.i(
        "Received message, adding to queue: (${queue.length}) "
        "room_id=$roomId event_id=$eventId",
      );
    }
  }

  Future<void> flushQueueLoop() async {
    try {
      while (true) {
        if (queue.isEmpty) {
          Log.i("Queue was empty, waiting a sec and double checking");
          await Future.delayed(const Duration(seconds: 1));

          if (queue.isEmpty) {
            Log.i("Queue clear, exiting");
            break;
          } else {
            Log.i("Something new came in, continuing");
          }
        }

        var entry = queue.firstOrNull;
        if (entry != null) {
          final roomId = entry["room_id"];
          final eventId = entry["event_id"];
          Log.i("Processing entry room_id=$roomId event_id=$eventId");
          Log.i("Current queue length: ${queue.length}");
          queue.remove(entry);
          try {
            await handleMessage(entry);
          } catch (e, s) {
            Log.e("An error occurred while processing a notification entry");
            Log.onError(e, s);
          }
        }
      }
    } catch (e, s) {
      Log.e("An error occurred while processing the notification service loop");
      Log.onError(e, s);
    }

    Log.i("Stopping background service");
    instance?.stopSelf();
  }

  Future<void> handleMessage(Map<String, dynamic> data) async {
    final roomId = data["room_id"];
    final eventId = data["event_id"];
    if (roomId is! String || eventId is! String) {
      Log.w("Ignoring background notification without room/event identifiers");
      return;
    }

    final manager = clientManager;
    if (manager == null) {
      Log.w("Ignoring background notification because client manager is null");
      return;
    }

    final client =
        manager.clients.where((element) => element.hasRoom(roomId)).firstOrNull;
    if (client == null) {
      Log.w("Ignoring background notification for unknown room $roomId");
      return;
    }

    Log.i("Found client: ${client.identifier}");
    var room = client.getRoom(roomId);
    if (room == null) {
      Log.w("Ignoring background notification for unavailable room $roomId");
      return;
    }

    Log.i("Found room: ${room.displayName}");

    var event = await room.getEvent(eventId);
    if (event == null) {
      Log.w("Ignoring background notification for unavailable event $eventId");
      return;
    }

    Member? user;
    try {
      user = await room.fetchMember(event.senderId);
    } catch (e, s) {
      Log.onError(
        e,
        s,
        content:
            "Failed to fetch notification sender ${event.senderId} in $roomId",
      );
    }

    Log.i("Got user: $user  ($user)");

    bool isDirectMessage = client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(room) ??
        false;

    if (event is TimelineEventEncrypted) {
      var decrypted = await event.attemptDecrypt(room);
      event = decrypted ?? event;
    }

    if (event is TimelineEventMessage ||
        event is TimelineEventSticker ||
        event is TimelineEventEncrypted) {
      var content = MessageNotificationContent(
          senderName: user?.displayName ?? event.senderId,
          senderId: user?.identifier ?? event.senderId,
          roomName: room.displayName,
          content: event.plainTextBody,
          eventId: eventId,
          roomId: room.identifier,
          clientId: client.identifier,
          senderImage: user?.avatar,
          roomImage: room.avatar,
          isDirectMessage: isDirectMessage);

      await NotificationManager.notify(content);
    }
  }
}
