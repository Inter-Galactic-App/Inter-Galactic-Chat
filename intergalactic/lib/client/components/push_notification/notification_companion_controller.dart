import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';

class NotificationCompanionMessage {
  const NotificationCompanionMessage({
    required this.senderName,
    required this.roomName,
    required this.body,
    required this.roomId,
    required this.clientId,
    required this.eventId,
    required this.isDirectMessage,
    required this.bodyRedacted,
    required this.receivedAt,
  });

  static const String genericBody = "New message";

  final String senderName;
  final String roomName;
  final String body;
  final String roomId;
  final String clientId;
  final String eventId;
  final bool isDirectMessage;
  final bool bodyRedacted;
  final DateTime receivedAt;
}

class NotificationCompanionState {
  const NotificationCompanionState({
    required this.messages,
  });

  static const NotificationCompanionState empty =
      NotificationCompanionState(messages: []);

  final List<NotificationCompanionMessage> messages;

  int get count => messages.length;

  NotificationCompanionMessage? get latest =>
      messages.isEmpty ? null : messages.last;
}

class NotificationCompanionController {
  NotificationCompanionController();

  static final NotificationCompanionController instance =
      NotificationCompanionController();

  final StreamController<NotificationCompanionMessage> _messages =
      StreamController<NotificationCompanionMessage>.broadcast();
  final StreamController<NotificationCompanionState> _stateController =
      StreamController<NotificationCompanionState>.broadcast();

  bool Function()? _isScreenSharingOverride;
  bool _overlayHostAvailable = false;
  bool _overlayOpen = false;
  final List<NotificationCompanionMessage> _activeMessages =
      <NotificationCompanionMessage>[];

  Stream<NotificationCompanionMessage> get messages => _messages.stream;

  Stream<NotificationCompanionState> get stateChanges =>
      _stateController.stream;

  NotificationCompanionState get state => NotificationCompanionState(
        messages: List<NotificationCompanionMessage>.unmodifiable(
          _activeMessages,
        ),
      );

  NotificationCompanionMessage? get latest => state.latest;

  bool get isOverlayHostAvailable => _overlayHostAvailable;

  bool get isOverlayOpen => _overlayOpen;

  bool get shouldMuteNativeDesktopMessageNotifications =>
      _overlayHostAvailable && preferences.notificationCompanionEnabled.value;

  @visibleForTesting
  set isScreenSharingOverride(bool Function()? value) {
    _isScreenSharingOverride = value;
  }

  void setOverlayOpen(bool value) {
    _overlayOpen = value;
  }

  void setOverlayHostAvailable(bool value) {
    _overlayHostAvailable = value;
    if (!value) {
      _overlayOpen = false;
    }
  }

  void handleApprovedNotification(
    MessageNotificationContent content, {
    bool? enabled,
    bool? showPreviews,
    bool? hidePreviewsWhileScreenSharing,
    bool? isScreenSharing,
  }) {
    final effectiveEnabled =
        enabled ?? preferences.notificationCompanionEnabled.value;
    if (!effectiveEnabled) {
      return;
    }

    final message = buildMessage(
      content,
      showPreviews: showPreviews ??
          (!preferences.usePrivateNotificationPreviews &&
              preferences.notificationCompanionShowPreviews.value),
      hidePreviewsWhileScreenSharing: hidePreviewsWhileScreenSharing ??
          preferences.notificationCompanionHidePreviewsWhileScreenSharing.value,
      isScreenSharing: isScreenSharing ?? _isLocalScreenSharing(),
    );

    _activeMessages.removeWhere((entry) => entry.eventId == message.eventId);
    _activeMessages.add(message);
    _messages.add(message);
    _emitState();
  }

  @visibleForTesting
  NotificationCompanionMessage buildMessage(
    MessageNotificationContent content, {
    required bool showPreviews,
    required bool hidePreviewsWhileScreenSharing,
    required bool isScreenSharing,
  }) {
    final shouldRedactBody =
        !showPreviews || (hidePreviewsWhileScreenSharing && isScreenSharing);

    return NotificationCompanionMessage(
      senderName: content.senderName,
      roomName: content.roomName,
      body: shouldRedactBody
          ? NotificationCompanionMessage.genericBody
          : content.content,
      roomId: content.roomId,
      clientId: content.clientId,
      eventId: content.eventId,
      isDirectMessage: content.isDirectMessage,
      bodyRedacted: shouldRedactBody,
      receivedAt: DateTime.now(),
    );
  }

  void open(NotificationCompanionMessage message) {
    if (!preferences.notificationCompanionClickToOpen.value) {
      return;
    }

    Log.d(
      "Opening companion notification room ${message.roomId}",
      category: LogCategory.notifications,
      source: "notification-companion",
    );
    EventBus.openRoomFromNotification((message.roomId, message.clientId));
  }

  void clearRoom(String roomId, {String? clientId}) {
    _activeMessages.removeWhere(
      (message) =>
          message.roomId == roomId &&
          (clientId == null || message.clientId == clientId),
    );
    _emitState();
  }

  List<NotificationCompanionMessage> reconcileUnreadRooms(
    bool Function(NotificationCompanionMessage message) hasUnreadNotification,
  ) {
    final removedMessages = <NotificationCompanionMessage>[];
    _activeMessages.removeWhere((message) {
      final shouldRemove = !hasUnreadNotification(message);
      if (shouldRemove) {
        removedMessages.add(message);
      }
      return shouldRemove;
    });
    if (removedMessages.isNotEmpty) {
      _emitState();
    }
    return removedMessages;
  }

  void clearPending() {
    _activeMessages.clear();
    _emitState();
  }

  @visibleForTesting
  void clearAll() {
    clearPending();
  }

  void _emitState() {
    _stateController.add(state);
  }

  bool _isLocalScreenSharing() {
    final override = _isScreenSharingOverride;
    if (override != null) {
      return override();
    }

    return clientManager?.callManager.currentSessions
            .any((session) => session.isSharingScreen) ??
        false;
  }
}
