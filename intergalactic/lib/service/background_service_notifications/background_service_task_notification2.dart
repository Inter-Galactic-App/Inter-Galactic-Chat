import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/client_manager.dart';
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
        await addInitializedBackgroundClients(clientManager!, clients);
      }
    }

    await NotificationManager.init(isBackgroundService: true);
  }

  /// Adds each registered background client that finished initialising.
  ///
  /// Split out of [init] only so the skip below is reachable from a test.
  /// [init] opens the database server, the file cache and the notification
  /// manager, none of which a unit test can stand up, so the skip previously
  /// had no coverage at all - removing it left the suite green while the app
  /// went on to hold an unusable client.
  ///
  /// [createClient] exists for that test and defaults to the real construction.
  @visibleForTesting
  Future<void> addInitializedBackgroundClients(
    ClientManager manager,
    Iterable<String> databaseIds, {
    Future<MatrixBackgroundClient> Function(String databaseId)? createClient,
  }) async {
    final create = createClient ?? _initBackgroundClient;
    for (final id in databaseIds) {
      Log.i("Adding background matrix client: ${id}");
      final client = await create(id);
      // An account whose persisted credentials are unusable returns early from
      // init() and stays uninitialised. Adding it anyway puts a client in the
      // manager that cannot answer anything.
      if (!client.isInitialized) {
        continue;
      }
      manager.addClient(client);
    }
  }

  static Future<MatrixBackgroundClient> _initBackgroundClient(
    String databaseId,
  ) async {
    final client = MatrixBackgroundClient(databaseId: databaseId);
    await client.init(true, isBackgroundService: true);
    return client;
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
          // This isolate's preference cache was built when the service
          // started and does not see what the UI isolate has written since.
          // Rendering decisions below read preferences, so refresh first or a
          // setting changed during this service's lifetime is ignored until
          // the app is fully closed. Guarded on its own, as in the v1 manager:
          // outside a guard a transient read failure reaches the outer catch,
          // which abandons the loop and discards every entry still queued.
          // Rendering against the unrefreshed cache does not leak content: the
          // failed read is recorded on Preferences and
          // usePrivateNotificationPreviews fails closed while it stands, so a
          // preview setting the user has just changed cannot be defeated by an
          // unreadable preferences file.
          try {
            await preferences.refreshFromDisk();
          } catch (e, s) {
            Log.onError(e, s);
          }
          await handleMessage(entry);
        }
      }
    } catch (e, s) {
      Log.e("An error occured while processing the notification service loop");
      Log.onError(e, s);

      try {
        // Awaited: the service stops itself a few lines below, and a discarded
        // future let it stop before the platform had posted the fallback - so
        // the user got neither the message nor the notice that something went
        // wrong.
        await NotificationManager.notify(
          ErrorNotificationContent(
            title: "Notification needs attention",
            // The exception text and stack trace stay in Log.onError above; this
            // string is notification-shade content, so internal frames - and any
            // identifier an exception message happens to carry - would otherwise
            // be shown on the lock screen.
            content: "Open Inter Galactic to view the latest message.",
          ),
        );
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

      var client = clientManager!.clients.firstWhereOrNull(
        (element) => element.hasRoom(roomId),
      );

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

      Log.i("Found client: ${client.identifier}");
      var room = client.getRoom(roomId);

      if (room is MatrixBackgroundRoom) {
        await room.init();
      }

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
          "Unable to fetch room event for notification\n${exception}",
        );
      }

      final content = await MessageNotificationContent.fromEvent(event, room!);
      if (content != null) {
        await NotificationManager.notify(content);
      }
    } catch (e, s) {
      Log.e("An error occured while processing the notification service loop");
      Log.onError(e, s);

      // Awaited so handleMessage does not complete before the fallback is
      // posted; the background service can be torn down the moment it does.
      await NotificationManager.notify(
        ErrorNotificationContent(
          title: "Notification needs attention",
          // The exception text and stack trace stay in Log.onError above; this
          // string is notification-shade content, so internal frames - and any
          // identifier an exception message happens to carry - would otherwise
          // be shown on the lock screen.
          content: "Open Inter Galactic to view the latest message.",
        ),
      );
    }
  }
}
