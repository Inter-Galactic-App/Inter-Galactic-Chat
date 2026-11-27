import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/coalesce_photo_stack.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/hide_content.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/room_notification_snooze.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/suppress_active_room.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/suppress_extension_delivered.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:intergalactic/client/components/push_notification/notification_companion_controller.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/platform_notifier_factory.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_notifier.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:media_kit/media_kit.dart';

String? notificationMediaModifierDiagnostic({
  required bool hadAttachmentPresentation,
  required bool hasAttachmentPresentation,
  required bool privatePreviews,
}) {
  if (!hadAttachmentPresentation || hasAttachmentPresentation) {
    return null;
  }

  return 'notification_media_pipeline stage=modifiers '
      'result=attachment_redacted private_previews=$privatePreviews';
}

class NotificationManager {
  static Notifier? _notifier;

  static Notifier? get notifier => _notifier;

  static final List<NotificationModifier> _modifiers = List.empty(
    growable: true,
  );

  static Future<void>? notifierLoading;

  static Player? _player;
  static StreamSubscription<void>? _companionReadStateSubscription;

  static Player getSoundPlayer({String? roomLocalId}) {
    _player ??= Player(configuration: PlayerConfiguration());
    _player!.setVolume(
      preferences.getEffectiveRoomNotificationVolume(roomLocalId),
    );

    return _player!;
  }

  static Future<void> init({bool isBackgroundService = false}) async {
    Log.i("Initializing NotificationManager");
    Log.i("Existing notifier: $_notifier");
    final nextNotifier = _getNotifier(isBackgroundService: isBackgroundService);
    if (_notifier == null ||
        (!isBackgroundService &&
            nextNotifier != null &&
            _notifier.runtimeType != nextNotifier.runtimeType)) {
      _notifier = nextNotifier;
    }

    _modifiers.clear();
    addModifier(NotificationModifierRoomSnooze());
    addModifier(NotificationModifierSuppressActiveRoom());
    if (BuildConfig.ANDROID) {
      addModifier(NotificationModifierSuppressOtherActiveDevice());
    }
    if (PlatformUtils.isIOS) {
      addModifier(
        NotificationModifierSuppressExtensionDelivered(
          deliveredEventIds: IosNotifier.deliveredRemoteEventIds,
        ),
      );
    }

    // After the suppression modifiers, so a photo that would not have been
    // shown anyway never opens a stack, and before content rewriting.
    addModifier(NotificationModifierCoalescePhotoStack());

    addModifier(NotificationModifierHideContent());

    if (PlatformUtils.isLinux) {
      addModifier(NotificationModifierLinuxFormatting());
    }

    notifierLoading = _notifier?.init();
    _bindCompanionReadStateSync(isBackgroundService: isBackgroundService);
  }

  static Notifier? _getNotifier({bool isBackgroundService = false}) {
    if (PlatformUtils.isWeb) {
      return WebPushNotifier();
    }

    return getPlatformNotifier(isBackgroundService: isBackgroundService);
  }

  static void addModifier(NotificationModifier modifier) {
    _modifiers.add(modifier);
  }

  static void removeModifier(NotificationModifier modifier) {
    _modifiers.remove(modifier);
  }

  static Future<void> clearNotifications(Room room) async {
    await clearNotificationsByRoute(
      clientId: room.client.identifier,
      roomId: room.identifier,
      room: room,
    );
  }

  static Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
    Room? room,
  }) async {
    NotificationCompanionController.instance.clearRoom(
      roomId,
      clientId: clientId,
    );
    // The user has seen the room, so the next photo should notify again rather
    // than being folded into the stack they just read.
    for (final modifier in _modifiers) {
      if (modifier is NotificationModifierCoalescePhotoStack) {
        modifier.reset(clientId: clientId, roomId: roomId);
      }
    }
    if (room != null) {
      await notifier?.clearNotifications(room);
      return;
    }
    await notifier?.clearNotificationsByRoute(
      clientId: clientId,
      roomId: roomId,
    );
  }

  static void _bindCompanionReadStateSync({required bool isBackgroundService}) {
    _companionReadStateSubscription?.cancel();
    _companionReadStateSubscription = null;

    if (isBackgroundService) {
      return;
    }

    final manager = clientManager;
    if (manager == null) {
      return;
    }

    _companionReadStateSubscription = manager.onSync.stream.listen(
      (_) => unawaited(_reconcileCompanionReadState()),
    );
    unawaited(_reconcileCompanionReadState());
  }

  static Future<void> _reconcileCompanionReadState() async {
    final manager = clientManager;
    if (manager == null) {
      return;
    }

    final clearedMessages = NotificationCompanionController.instance
        .reconcileUnreadRooms((message) {
          final room = manager
              .getClient(message.clientId)
              ?.getRoom(message.roomId);
          return room != null && room.displayNotificationCount > 0;
        });

    if (!BuildConfig.DESKTOP || clearedMessages.isEmpty) {
      return;
    }

    final clearedRoutes = <String>{};
    for (final message in clearedMessages) {
      final routeKey = '${message.clientId}\n${message.roomId}';
      if (!clearedRoutes.add(routeKey)) {
        continue;
      }

      try {
        await notifier?.clearNotificationsByRoute(
          clientId: message.clientId,
          roomId: message.roomId,
        );
      } catch (_) {
        Log.w(
          "Failed to clear desktop notification during read-state sync",
          category: LogCategory.notifications,
          source: "notification-manager",
        );
      }
    }
  }

  static Future<void> notify(
    NotificationContent notification, {
    bool forceShow = false,
  }) async {
    if (_notifier == null) {
      Log.e("Failed to show notification, notifier has not been initialzied");
      return;
    }

    final hadAttachmentPresentation =
        notification is MessageNotificationContent &&
        notification.attachmentPresentation != null;
    NotificationContent? content = notification;

    if (preferences.enableNotifications.value == false) {
      return;
    }

    for (var modifier in _modifiers) {
      Log.d("Processing modifier: $modifier");
      if (forceShow) {
        if (modifier is NotificationModifierSuppressActiveRoom) continue;
        if (modifier is NotificationModifierSuppressOtherActiveDevice) continue;
        if (modifier is NotificationModifierSuppressExtensionDelivered)
          continue;
      }

      content = await modifier.process(content!);
      if (content == null) {
        Log.d("Modifier returned null notification, returning");
        return;
      }
    }

    final mediaDiagnostic = notificationMediaModifierDiagnostic(
      hadAttachmentPresentation: hadAttachmentPresentation,
      hasAttachmentPresentation:
          content is MessageNotificationContent &&
          content.attachmentPresentation != null,
      privatePreviews: preferences.usePrivateNotificationPreviews,
    );
    if (mediaDiagnostic != null) {
      Log.w(
        mediaDiagnostic,
        category: LogCategory.notifications,
        source: 'notification-manager',
      );
    }

    Log.i("Displaying notification content: $content");
    if (content is MessageNotificationContent) {
      NotificationCompanionController.instance.handleApprovedNotification(
        content,
      );
    }
    await _notifier!.notify(content!);
  }
}
