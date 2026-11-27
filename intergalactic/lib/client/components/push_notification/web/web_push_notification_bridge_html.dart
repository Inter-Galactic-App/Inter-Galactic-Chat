import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/hide_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:web/web.dart' as web;

bool _initialized = false;
JSExportedDartFunction? _serviceWorkerMessageHandler;

void initWebPushNotificationBridge() {
  if (_initialized) {
    return;
  }

  if (!web.window.navigator.has('serviceWorker')) {
    return;
  }

  final container = web.window.navigator.serviceWorker;

  _serviceWorkerMessageHandler ??= ((web.MessageEvent event) =>
      unawaited(_onServiceWorkerMessage(event))).toJS;

  container.addEventListener('message', _serviceWorkerMessageHandler!);

  _initialized = true;
}

Future<void> _onServiceWorkerMessage(web.MessageEvent event) async {
  try {
    final payload = event.data?.dartify();
    if (payload is! Map) {
      return;
    }

    if (payload['type'] != 'intergalactic-decrypt-notification') {
      return;
    }

    final requestId = payload['requestId']?.toString();
    if (requestId == null || requestId.isEmpty) {
      return;
    }

    final rawPushPayload = payload['payload'];
    final pushPayload = rawPushPayload is Map ? rawPushPayload : null;

    final notification = await _buildNotificationPayload(
      clientId: payload['client_id']?.toString(),
      roomId: payload['room_id']?.toString(),
      eventId: payload['event_id']?.toString(),
      pushPayload: pushPayload,
    );

    final source = event.source;
    if (source == null) {
      return;
    }

    source.callMethodVarArgs<JSAny?>('postMessage'.toJS, [
      {
        'type': 'intergalactic-decrypt-notification-response',
        'requestId': requestId,
        'notification': notification,
      }.jsify(),
    ]);
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Failed to build a decrypted web push notification preview',
    );
  }
}

Future<Map<String, dynamic>?> _buildNotificationPayload({
  required String? clientId,
  required String? roomId,
  required String? eventId,
  required Map? pushPayload,
}) async {
  if (roomId == null || roomId.isEmpty || eventId == null || eventId.isEmpty) {
    return null;
  }

  final room = _findRoom(clientId: clientId, roomId: roomId);
  if (room == null) {
    return null;
  }

  var timeline = room.timeline;
  var content = await _resolveNotificationContent(
    room: room,
    timeline: timeline,
    eventId: eventId,
  );
  if (content != null) {
    return _buildNotificationMap(content);
  }

  return _buildFallbackNotificationMap(
    room: room,
    eventId: eventId,
    pushPayload: pushPayload,
  );
}

Future<MessageNotificationContent?> _resolveNotificationContent({
  required Room room,
  required Timeline? timeline,
  required String eventId,
}) async {
  final cachedEvent = timeline?.tryGetEvent(eventId);
  return await _notificationContentFromEvent(cachedEvent, room);
}

Future<MessageNotificationContent?> _notificationContentFromEvent(
  TimelineEvent? event,
  Room room,
) async {
  if (event == null ||
      (event is! TimelineEventMessage && event is! TimelineEventSticker)) {
    return null;
  }

  final senderId = event.senderId;
  var senderName = senderId;

  try {
    final user = await room.fetchMember(senderId);
    senderName = user.displayName;
  } catch (_) {
    // Fall back to the raw sender ID when member data is not available yet.
  }

  String messageBody;
  try {
    messageBody = event.plainTextBody.trim();
  } catch (_) {
    messageBody = '';
  }

  if (messageBody.isEmpty && event is TimelineEventSticker) {
    messageBody = event.stickerName.trim();
  }

  if (messageBody.isEmpty) {
    messageBody = 'Sent a message';
  }

  bool isDirectMessage = false;
  try {
    isDirectMessage = room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(room) ??
        false;
  } catch (_) {
    isDirectMessage = false;
  }

  return MessageNotificationContent(
    senderName: senderName,
    senderId: senderId,
    roomName: room.displayName,
    content: messageBody,
    eventId: event.eventId,
    roomId: room.identifier,
    clientId: room.client.identifier,
    isDirectMessage: isDirectMessage,
    formatType: 'chat.commet.custom.matrix_plain',
    formattedContent: messageBody,
  );
}

Map<String, dynamic>? _buildFallbackNotificationMap({
  required Room room,
  required String eventId,
  required Map? pushPayload,
}) {
  if (preferences.usePrivateNotificationPreviews) {
    return {
      'title': NotificationModifierHideContent.genericNotificationTitle,
      'body': 'Open Inter Galactic to view this update.',
      'room_id': room.identifier,
      'client_id': room.client.identifier,
      'event_id': eventId,
    };
  }

  final source =
      pushPayload == null ? null : Map<String, dynamic>.from(pushPayload);
  final title = _firstNonEmpty([
    source?['title']?.toString(),
    source?['senderName']?.toString(),
    source?['sender']?.toString(),
    room.displayName,
  ]);
  final body = _firstNonEmpty([
    source?['body']?.toString(),
    source?['content']?.toString(),
    'Open Inter Galactic to view this update.',
  ]);

  if (title == null || body == null) {
    return null;
  }

  return {
    'title': title,
    'body': body,
    'room_id': room.identifier,
    'client_id': room.client.identifier,
    'event_id': eventId,
  };
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return null;
}

Map<String, dynamic> _buildNotificationMap(MessageNotificationContent content) {
  if (preferences.usePrivateNotificationPreviews) {
    return {
      'title': NotificationModifierHideContent.genericNotificationTitle,
      'body': NotificationModifierHideContent()
          .notificationModifiersPrivacyEnhanced,
      'room_id': content.roomId,
      'client_id': content.clientId,
      'event_id': content.eventId,
    };
  }

  return {
    'title': content.title,
    'body': content.content,
    'room_id': content.roomId,
    'client_id': content.clientId,
    'event_id': content.eventId,
  };
}

Room? _findRoom({required String? clientId, required String roomId}) {
  final manager = clientManager;
  if (manager == null) {
    return null;
  }

  if (clientId != null && clientId.isNotEmpty) {
    final client = manager.getClient(clientId);
    if (client?.hasRoom(roomId) == true) {
      return client?.getRoom(roomId);
    }
  }

  for (final client in manager.clients) {
    if (client.hasRoom(roomId)) {
      return client.getRoom(roomId);
    }
  }

  return null;
}
