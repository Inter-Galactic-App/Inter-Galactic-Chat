import 'dart:async';
import 'package:collection/collection.dart';
import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_client.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/database/database_server.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class BackgroundNotificationsManager2 {
  ServiceInstance? instance;
  final bool stopServiceWhenIdle;

  BackgroundNotificationsManager2(
    this.instance, {
    this.stopServiceWhenIdle = true,
  });

  Timer? shutdownTimer;

  List<Map<String, dynamic>> queue = List.empty(growable: true);

  Future<void> init() async {
    if (fileCache == null || clientManager == null) {
      await initDatabaseServer();
    }

    if (fileCache == null) {
      fileCache = FileCache.getFileCacheInstance();

      if (fileCache != null) {
        await fileCache?.init();
      }
    }

    if (clientManager == null) {
      clientManager = ClientManager();

      final clients = preferences.getRegisteredMatrixClients();
      if (clients != null) {
        for (var id in clients) {
          var client = MatrixBackgroundClient(databaseId: id);
          Log.i("Adding background matrix client: ${id}");
          await client.init(true, isBackgroundService: true);
          clientManager!.addClient(client);
        }
      }
    }

    await NotificationManager.init(isBackgroundService: true);
  }

  void onReceived(Map<String, dynamic>? data) async {
    if (data != null) {
      queue.add(data);
      Log.i("[NEW] Received message, adding to queue: (${queue.length})");
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
          Log.i("Current queue length: ${queue.length}");
          queue.remove(entry);
          await handleMessage(entry);
        }
      }
    } catch (e, s) {
      Log.e("An error occured while processing the notification service loop");
      Log.onError(e, s);

      try {
        NotificationManager.notify(ErrorNotificationContent(
            title: "An error occurred while processing notifications",
            content: "${e} \n\n ${s}"));
      } catch (_) {}
    }

    if (stopServiceWhenIdle && instance != null) {
      Log.i("Stopping background service");
      instance?.stopSelf();
    }
  }

  Future<void> handleMessage(Map<String, dynamic> data) async {
    try {
      var roomId = data["room_id"] as String?;
      var eventId = data["event_id"] as String?;
      var counts = data["counts"];

      if (roomId == null || eventId == null) {
        Log.w("TODO: Handle counts: $counts");
        return;
      }

      var client = clientManager!.clients
          .firstWhereOrNull((element) => element.hasRoom(roomId));

      // If the room does not already belong to any of our clients, it must be an invite
      // I couldn't figure out a good way to determine which client received the invite
      // So we will just display a generic notification
      if (client == null) {
        var content = GenericRoomInviteNotificationContent(
          content: "You received an invitation to chat!",
          title: "Room Invite",
        );

        await NotificationManager.notify(content);
        return;
      }

      var directMessages = client.getComponent<DirectMessagesComponent>();

      Log.i("Found client: ${client.identifier}");
      var room = client.getRoom(roomId);

      if (room is MatrixBackgroundRoom) {
        await room.init();
      }

      final isDirectMessage =
          directMessages?.isRoomDirectMessage(room!) == true;

      TimelineEvent? event;
      Object? exception;

      for (int i = 0; i < 5; i++) {
        try {
          event = await room!.getEvent(eventId);
          break;
        } catch (e, s) {
          Log.onError(e, s);
          exception = e;
          await Future.delayed(Duration(seconds: i * 2));
        }
      }

      if (event == null) {
        throw Exception(
            "Unable to fetch room event for notification\n${exception}");
      }

      var member = await room!.fetchMember(event.senderId);

      var content = MessageNotificationContent(
          senderName: member.displayName,
          senderId: event.senderId,
          roomName: room.displayName,
          content: event.plainTextBody,
          eventId: eventId,
          roomId: roomId,
          clientId: client.identifier,
          senderImage: member.avatar,
          roomImageId: room.avatarId,
          senderImageId: member.avatarId,
          roomImage: room.avatar,
          isDirectMessage: isDirectMessage);

      await NotificationManager.notify(content);
    } catch (e, s) {
      Log.e("An error occured while processing the notification service loop");
      Log.onError(e, s);

      NotificationManager.notify(ErrorNotificationContent(
          title: "An error occurred while processing notifications",
          content: "${e} \n\n ${s}"));
    }
  }
}
