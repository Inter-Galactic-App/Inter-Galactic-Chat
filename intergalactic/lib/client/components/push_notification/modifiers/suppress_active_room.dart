import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/window_focus.dart';

import 'package:flutter/material.dart';

class NotificationModifierSuppressActiveRoom implements NotificationModifier {
  String? roomId = "";

  NotificationModifierSuppressActiveRoom() {
    EventBus.onSelectedRoomChanged.stream.listen((event) {
      roomId = event?.identifier;
    });
  }

  @override
  Future<NotificationContent?> process(NotificationContent content) async {
    if (preferences.suppressNotificationWhenRoomFocused.value == false) {
      return content;
    }

    if (content is MessageNotificationContent) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (BuildConfig.DESKTOP) {
        if (!await isDesktopWindowFocused()) {
          Log.d(
            'Active-room notification suppression skipped because desktop window is not focused',
            category: LogCategory.notifications,
            source: 'notification-suppression',
          );
          return content;
        }
      } else {
        if (lifecycleState != AppLifecycleState.resumed) {
          Log.d(
            'Active-room notification suppression skipped because app lifecycle is $lifecycleState',
            category: LogCategory.notifications,
            source: 'notification-suppression',
          );
          return content;
        }
      }

      if (content.roomId == roomId) {
        Log.i(
          'Suppressing notification for active room while app is focused/resumed',
          category: LogCategory.notifications,
          source: 'notification-suppression',
        );
        return null;
      }

      Log.d(
        'Active-room notification suppression passed: focusedRoomMatches=false lifecycle=$lifecycleState',
        category: LogCategory.notifications,
        source: 'notification-suppression',
      );
    }

    return content;
  }
}
