import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/debug/log.dart';

/// iOS: do not show the app's own notification for an event the Notification
/// Service Extension has already rendered.
///
/// Two producers exist while the gateway still sends `content-available`:
/// the extension renders every alert push without the app, and the app,
/// when it is woken or opened, notifies for the same events from its sync.
/// The extension's notification keeps the gateway's routing ids in its
/// userInfo, so the app asks Notification Center which event ids the
/// extension RENDERED and are still delivered, and drops its own copy for
/// those. A generic fallback (the extension could not decrypt, usually a
/// room key the app had not yet received) is not in that set: the app's
/// decrypted copy goes through and replaces it (`IosNotifier.notify`). Only
/// message notifications are keyed by event; everything else passes. Any
/// failure to ask passes too: a duplicate is the pre-extension behaviour,
/// and the wrong direction to fail would be silence.
class NotificationModifierSuppressExtensionDelivered
    implements NotificationModifier {
  NotificationModifierSuppressExtensionDelivered({
    required Future<Set<String>> Function() deliveredEventIds,
  }) : _deliveredEventIds = deliveredEventIds;

  final Future<Set<String>> Function() _deliveredEventIds;

  static const String _source = 'notification-dedupe';

  @override
  Future<NotificationContent?> process(NotificationContent content) async {
    if (content is! MessageNotificationContent) {
      return content;
    }
    final Set<String> delivered;
    try {
      delivered = await _deliveredEventIds();
    } catch (error) {
      Log.w(
        'Extension-delivered lookup failed: ${error.runtimeType}; showing',
        category: LogCategory.notifications,
        source: _source,
      );
      return content;
    }
    if (delivered.contains(content.eventId)) {
      Log.i(
        'Suppressing notification: the extension already delivered this '
        'event (delivered=${delivered.length})',
        category: LogCategory.notifications,
        source: _source,
      );
      return null;
    }
    return content;
  }
}
