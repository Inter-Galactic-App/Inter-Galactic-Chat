import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/notification_utils.dart';
import 'package:web/web.dart' as web;

bool _initialized = false;
final List<StreamSubscription> _subscriptions = [];

void initWebAppBadgeManager() {
  if (_initialized || clientManager == null) {
    return;
  }

  if (!_supportsBadging()) {
    return;
  }

  final manager = clientManager!;
  _subscriptions.addAll([
    manager.onSync.stream.listen((_) => updateWebAppBadge()),
    manager.onSpaceUpdated.stream.listen((_) => updateWebAppBadge()),
    manager.onSpaceChildUpdated.stream.listen((_) => updateWebAppBadge()),
    manager.onDirectMessageRoomUpdated.stream
        .listen((_) => updateWebAppBadge()),
    manager.directMessages.onHighlightedRoomsListUpdated
        .listen((_) => updateWebAppBadge()),
    manager.onClientAdded.stream.listen((_) => updateWebAppBadge()),
    manager.onClientRemoved.stream.listen((_) => updateWebAppBadge()),
  ]);

  _initialized = true;
  unawaited(updateWebAppBadge());
}

bool _supportsBadging() {
  final navigator = web.window.navigator;
  return navigator.has('setAppBadge') && navigator.has('clearAppBadge');
}

Future<void> updateWebAppBadge() async {
  if (!_supportsBadging() || clientManager == null) {
    return;
  }

  try {
    final count = NotificationUtils.getNotificationCounts().$2;
    final navigator = web.window.navigator;

    if (count > 0) {
      await navigator.setAppBadge(count).toDart;
    } else {
      await navigator.clearAppBadge().toDart;
    }
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Failed to update the web app badge',
    );
  }
}
