import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/event_bus.dart';

typedef NotificationResponseAcknowledger =
    Future<void> Function(String responseId);

/// Why an inline-reply attempt finished.
///
/// Only [failed] is non-terminal. Acknowledging a platform response is what
/// removes its native redelivery path, so collapsing these back to a boolean is
/// how a reply that never sent gets reported to the user as handled.
enum InlineReplyOutcome {
  /// The message was accepted by the server.
  sent,

  /// Nothing was typed, so there is nothing to redeliver.
  empty,

  /// An identical reply is already in flight; that attempt owns the outcome.
  duplicate,

  /// The send did not land and should be delivered again.
  failed,
}

class _NotificationRouteTarget {
  const _NotificationRouteTarget({
    required this.roomId,
    required this.clientId,
    required this.eventId,
  });

  final String roomId;
  final String? clientId;
  final String? eventId;

  (String, String?) get route => (roomId, clientId);
}

class _NotificationStoryRouteTarget {
  const _NotificationStoryRouteTarget({
    required this.roomId,
    required this.clientId,
    required this.storySenderId,
    required this.storyId,
    required this.storyEventId,
  });

  final String roomId;
  final String clientId;
  final String storySenderId;
  final String storyId;
  final String? storyEventId;

  StoryOpenRequest get request => StoryOpenRequest(
    roomId: roomId,
    clientId: clientId,
    storySenderId: storySenderId,
    storyId: storyId,
    storyEventId: storyEventId,
  );

  _NotificationRouteTarget get roomTarget => _NotificationRouteTarget(
    roomId: roomId,
    clientId: clientId,
    eventId: storyEventId,
  );
}

class _PendingNotificationNavigation {
  _PendingNotificationNavigation({
    required this.target,
    required this.source,
    required this.responseId,
    required this.acknowledgeResponse,
    required this.openSettings,
  });

  final _NotificationRouteTarget target;
  final String source;
  final String? responseId;
  final NotificationResponseAcknowledger? acknowledgeResponse;
  final bool openSettings;
  int attempts = 0;
  Timer? retryTimer;
}

class _PendingStoryNotificationNavigation {
  _PendingStoryNotificationNavigation({
    required this.target,
    required this.source,
    required this.responseId,
    required this.acknowledgeResponse,
  });

  final _NotificationStoryRouteTarget target;
  final String source;
  final String? responseId;
  final NotificationResponseAcknowledger? acknowledgeResponse;
  int attempts = 0;
  Timer? retryTimer;
}

class NotificationResponseHandler {
  static const Duration _duplicateRouteWindow = Duration(seconds: 2);
  // A cold launch delivers the SAME notification response through several
  // independent paths: the plugin's onDidReceiveNotificationResponse callback,
  // the native pending-response handoff, and getNotificationAppLaunchDetails.
  // Navigation already tolerates that because it is deduplicated by
  // _lastOpenedRouteKey / _duplicateRouteWindow; inline replies were not, so a
  // reply typed from a notification while the app was fully closed sent the
  // message once per delivery path.
  //
  // The window spans app startup rather than the 2s used for navigation,
  // because these deliveries are separated by notifier initialisation rather
  // than by user input. The tradeoff is deliberate and narrow: replying with
  // identical text to the same message twice inside the window, from a
  // notification, collapses to one send. Typing in the app is unaffected.
  static const Duration _duplicateInlineReplyWindow = Duration(seconds: 30);
  static const Duration _fastRetryDelay = Duration(milliseconds: 500);
  static const Duration _slowRetryDelay = Duration(seconds: 5);
  static const int _fastRetryLimit = 24;
  static const int _maxRetryAttempts = 120;
  static Future<void> _inlineReplyTail = Future<void>.value();
  static final Map<String, DateTime> _recentInlineReplies = {};
  static String? _lastOpenedRouteKey;
  static DateTime? _lastOpenedRouteAt;
  static String? _lastOpenedStoryRouteKey;
  static DateTime? _lastOpenedStoryRouteAt;
  static final Map<String, _PendingNotificationNavigation> _pendingNavigations =
      {};
  static final Map<String, _PendingStoryNotificationNavigation>
  _pendingStoryNavigations = {};
  static StreamSubscription<Room?>? _selectedRoomSubscription;
  static StreamSubscription<StoryOpenRequest>? _openedStorySubscription;

  static Future<void> handle(NotificationResponse details) async {
    try {
      Log.i(
        "Got a notification response "
        "type=${details.notificationResponseType.name} "
        "action=${details.actionId == null ? 'none' : 'present'} "
        "payload=${details.payload == null ? 'none' : 'present'} "
        "dataKeys=${details.data.keys.join(',')}",
        category: LogCategory.notifications,
        source: 'notification-response',
      );
      await _awaitDatabaseEstablished('local response');

      final snoozeDuration =
          RoomNotificationSnoozeDurationOption.fromNotificationActionId(
            details.actionId,
          );
      if (snoozeDuration != null) {
        await _handleSnoozeRoomAction(details, snoozeDuration);
        return;
      }

      if (details.actionId == roomNotificationSnoozePickerActionId) {
        final target = _targetFromResponse(details);
        if (target != null) {
          _openNotificationRoute(
            target,
            source: 'local snooze picker action',
            openSettings: true,
          );
        }
        return;
      }

      if (details.actionId == richNotificationReplyActionId) {
        final target = _targetFromResponse(details);
        if (target?.clientId != null) {
          await _enqueueInlineReply(
            SendMessageUri(roomId: target!.roomId, clientId: target.clientId!),
            details.input,
          );
        }
        return;
      }

      final actionUri = _parseUri(details.actionId);
      if (actionUri != null) {
        Log.d(
          "Parsed notification action URI ${actionUri.runtimeType}",
          category: LogCategory.notifications,
          source: 'notification-response',
        );
      }

      if (actionUri case AcceptCallUri _) {
        final session = clientManager?.callManager.currentSessions
            .where(
              (e) =>
                  e.sessionId == actionUri.callId &&
                  e.client.identifier == actionUri.clientId,
            )
            .firstOrNull;

        await session?.acceptCall(withMicrophone: true);
        EventBus.openRoom.add((actionUri.roomId, actionUri.clientId));
      }

      if (actionUri case DeclineCallUri _) {
        final session = clientManager?.callManager.currentSessions
            .where(
              (e) =>
                  e.sessionId == actionUri.callId &&
                  e.client.identifier == actionUri.clientId,
            )
            .firstOrNull;

        await session?.declineCall();
      }

      if (actionUri case SendMessageUri _) {
        await _enqueueInlineReply(actionUri, details.input);
        return;
      }

      final payloadUri = _parseUri(details.payload);
      if (details.notificationResponseType ==
              NotificationResponseType.selectedNotification &&
          payloadUri is OpenStoryURI) {
        _openNotificationStoryRoute(
          _storyTargetFromUri(payloadUri),
          source: "local payload",
        );
        return;
      }

      if (details.notificationResponseType ==
              NotificationResponseType.selectedNotification &&
          payloadUri is OpenRoomURI) {
        _openNotificationRoute(
          _NotificationRouteTarget(
            roomId: payloadUri.roomId,
            clientId: payloadUri.clientId,
            eventId: null,
          ),
          source: "local payload",
        );
        return;
      }

      if (details.notificationResponseType ==
          NotificationResponseType.selectedNotification) {
        final data = _normalizePayload(details.data);
        final storyRoute = data == null
            ? null
            : _storyTargetFromPayloadData(data);
        if (storyRoute != null) {
          _openNotificationStoryRoute(
            storyRoute,
            source: "local response data",
          );
          return;
        }

        final dataRoute = data == null ? null : _targetFromPayloadData(data);
        if (dataRoute != null) {
          _openNotificationRoute(dataRoute, source: "local response data");
        }
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to handle a notification response",
      );
    }
  }

  static Future<void> handleRemotePayload(
    Object? payload, {
    String source = "remote payload",
    NotificationResponseAcknowledger? acknowledgeResponse,
  }) async {
    try {
      _logPayloadReceived(source, payload);
      await _awaitDatabaseEstablished(source);
      final directUri = _parseUri(_stringValue(payload));
      if (directUri is OpenStoryURI) {
        _openNotificationStoryRoute(
          _storyTargetFromUri(directUri),
          source: source,
          responseId: null,
          acknowledgeResponse: acknowledgeResponse,
        );
        return;
      }

      if (directUri is OpenRoomURI) {
        _openNotificationRoute(
          _NotificationRouteTarget(
            roomId: directUri.roomId,
            clientId: directUri.clientId,
            eventId: null,
          ),
          source: source,
          responseId: null,
          acknowledgeResponse: acknowledgeResponse,
        );
        return;
      }

      final data = _normalizePayload(payload);
      if (data == null) {
        _acknowledgeTerminalResponse(
          responseId: null,
          acknowledgeResponse: acknowledgeResponse,
          source: source,
          reason: 'without_route_payload',
        );
        Log.w(
          "Ignoring $source notification response without route payload",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
        return;
      }

      final responseId = _responseIdFromPayloadData(data);
      final actionId = _actionIdFromPayloadData(data);
      final target = _targetFromPayloadData(data);
      final snoozeDuration =
          RoomNotificationSnoozeDurationOption.fromNotificationActionId(
            actionId,
          );
      if (snoozeDuration != null) {
        if (target == null || target.clientId == null) {
          _acknowledgeTerminalResponse(
            responseId: responseId,
            acknowledgeResponse: acknowledgeResponse,
            source: source,
            reason: 'snooze_without_room_route',
          );
          return;
        }
        await _handleSnoozeRoomTarget(target, snoozeDuration);
        _acknowledgeTerminalResponse(
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
          source: source,
          reason: 'snooze_action_handled',
        );
        return;
      }

      if (actionId == roomNotificationSnoozePickerActionId) {
        if (target == null) {
          _acknowledgeTerminalResponse(
            responseId: responseId,
            acknowledgeResponse: acknowledgeResponse,
            source: source,
            reason: 'snooze_picker_without_room_route',
          );
          return;
        }
        _openNotificationRoute(
          target,
          source: source,
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
          openSettings: true,
        );
        return;
      }

      if (actionId == richNotificationReplyActionId) {
        if (target == null || target.clientId == null) {
          _acknowledgeTerminalResponse(
            responseId: responseId,
            acknowledgeResponse: acknowledgeResponse,
            source: source,
            reason: 'reply_without_room_route',
          );
          return;
        }
        final outcome = await _enqueueInlineReply(
          SendMessageUri(roomId: target.roomId, clientId: target.clientId!),
          _inputFromPayloadData(data),
          responseId: responseId,
        );
        // Acknowledging is what removes the platform's redelivery path, so a
        // send that did not land must stay unacknowledged. Everything else is
        // genuinely terminal: nothing was typed, or another attempt owns it, or
        // the message reached the room.
        if (outcome == InlineReplyOutcome.failed) {
          Log.w(
            "Notification inline reply did not send; leaving response "
            "$responseId unacknowledged for redelivery.",
            category: LogCategory.notifications,
            source: 'notification-response',
          );
          // Withholding the acknowledgement is what preserves redelivery, and
          // it is also what leaves the platform's reply spinner running: the
          // shade has nothing to update it with. Observed on device
          // 2026-08-18 - the spinner ran indefinitely while the app itself
          // correctly showed the message as undelivered, so the only surface
          // that failed to say so was the one the user was looking at.
          unawaited(
            NotificationManager.notify(
              ErrorNotificationContent(
                title: "Reply not sent",
                content: "Inter Galactic will try again.",
              ),
            ),
          );
          return;
        }
        _acknowledgeTerminalResponse(
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
          source: source,
          reason: 'inline_reply_${outcome.name}',
        );
        return;
      }

      final storyTarget = _storyTargetFromPayloadData(data);
      if (storyTarget != null) {
        _openNotificationStoryRoute(
          storyTarget,
          source: source,
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
        );
        return;
      }

      if (target != null) {
        _openNotificationRoute(
          target,
          source: source,
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
        );
      } else {
        _acknowledgeTerminalResponse(
          responseId: responseId,
          acknowledgeResponse: acknowledgeResponse,
          source: source,
          reason: 'without_room_route',
        );
        Log.w(
          "Ignoring $source notification response without room route",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to handle a remote notification response",
      );
    }
  }

  static _NotificationStoryRouteTarget _storyTargetFromUri(OpenStoryURI uri) {
    return _NotificationStoryRouteTarget(
      roomId: uri.roomId,
      clientId: uri.clientId,
      storySenderId: uri.storySenderId,
      storyId: uri.storyId,
      storyEventId: uri.storyEventId,
    );
  }

  static _NotificationStoryRouteTarget? _storyTargetFromPayloadData(
    Map<String, Object?> data, [
    int depth = 0,
  ]) {
    if (depth > 3) {
      return null;
    }

    final payloadUri = _firstUri(data, const [
      'payload',
      'route_payload',
      'routePayload',
      'deep_link',
      'deepLink',
      'url',
    ]);
    if (payloadUri is OpenStoryURI) {
      return _storyTargetFromUri(payloadUri);
    }

    final roomId = _firstString(data, const ['room_id', 'roomId', 'roomID']);
    final clientId = _firstString(data, const [
      'client_id',
      'clientId',
      'clientID',
    ]);
    final storySenderId = _firstString(data, const [
      'story_sender_id',
      'storySenderId',
      'story_owner_id',
      'storyOwnerId',
      'story_user_id',
      'storyUserId',
    ]);
    final storyId = _firstString(data, const ['story_id', 'storyId']);
    if (roomId != null &&
        clientId != null &&
        storySenderId != null &&
        storyId != null) {
      return _NotificationStoryRouteTarget(
        roomId: roomId,
        clientId: clientId,
        storySenderId: storySenderId,
        storyId: storyId,
        storyEventId: _firstString(data, const [
          'story_event_id',
          'storyEventId',
          'storyEventID',
        ]),
      );
    }

    for (final key in const [
      'notification',
      'data',
      'custom',
      'payload',
      'matrix',
      'm',
      'content',
      'userInfo',
      'aps',
    ]) {
      final nested = _normalizePayload(data[key]);
      if (nested == null) {
        continue;
      }

      final target = _storyTargetFromPayloadData(nested, depth + 1);
      if (target != null) {
        return target;
      }
    }

    return null;
  }

  static _NotificationRouteTarget? _targetFromPayloadData(
    Map<String, Object?> data, [
    int depth = 0,
  ]) {
    if (depth > 3) {
      return null;
    }

    final payloadUri = _firstUri(data, const [
      'payload',
      'route_payload',
      'routePayload',
      'deep_link',
      'deepLink',
      'url',
    ]);
    if (payloadUri is OpenStoryURI) {
      return _storyTargetFromUri(payloadUri).roomTarget;
    }
    if (payloadUri is OpenRoomURI) {
      return _NotificationRouteTarget(
        roomId: payloadUri.roomId,
        clientId: payloadUri.clientId,
        eventId: _firstString(data, const ['event_id', 'eventId', 'eventID']),
      );
    }

    final roomId = _firstString(data, const ['room_id', 'roomId', 'roomID']);
    if (roomId != null) {
      final clientId = _firstString(data, const [
        'client_id',
        'clientId',
        'clientID',
      ]);
      final eventId = _firstString(data, const [
        'event_id',
        'eventId',
        'eventID',
      ]);
      return _NotificationRouteTarget(
        roomId: roomId,
        clientId: clientId,
        eventId: eventId,
      );
    }

    for (final key in const [
      'notification',
      'data',
      'custom',
      'payload',
      'matrix',
      'm',
      'content',
      'userInfo',
      'aps',
    ]) {
      final nested = _normalizePayload(data[key]);
      if (nested == null) {
        continue;
      }

      final target = _targetFromPayloadData(nested, depth + 1);
      if (target != null) {
        return target;
      }
    }

    return null;
  }

  static _NotificationRouteTarget? _targetFromResponse(
    NotificationResponse details,
  ) {
    final payloadUri = _parseUri(details.payload);
    if (payloadUri is OpenStoryURI) {
      return _storyTargetFromUri(payloadUri).roomTarget;
    }
    if (payloadUri is OpenRoomURI) {
      return _NotificationRouteTarget(
        roomId: payloadUri.roomId,
        clientId: payloadUri.clientId,
        eventId: null,
      );
    }

    final data = _normalizePayload(details.data);
    return data == null ? null : _targetFromPayloadData(data);
  }

  static Future<void> _handleSnoozeRoomAction(
    NotificationResponse details,
    RoomNotificationSnoozeDurationOption duration,
  ) async {
    final target = _targetFromResponse(details);
    if (target == null || target.clientId == null) {
      Log.w(
        "Ignoring notification snooze action without complete room route",
        category: LogCategory.notifications,
        source: 'notification-snooze',
      );
      return;
    }

    await _handleSnoozeRoomTarget(target, duration);
  }

  static Future<void> _handleSnoozeRoomTarget(
    _NotificationRouteTarget target,
    RoomNotificationSnoozeDurationOption duration,
  ) async {
    final clientId = target.clientId!;
    final room = _findRoom(clientId: clientId, roomId: target.roomId);
    if (room == null) {
      Log.w(
        'Deferring notification snooze sync because the room is unavailable',
        category: LogCategory.notifications,
        source: 'notification-snooze',
      );
      if (!preferences.isInit) {
        await preferences.init();
      }
      await preferences.setRoomNotificationSnooze(
        clientId: clientId,
        roomId: target.roomId,
        duration: duration.duration,
        source: 'notification_action',
      );
      await NotificationManager.clearNotificationsByRoute(
        clientId: clientId,
        roomId: target.roomId,
      );
      return;
    }

    // The remote write reaches the network - a push rule plus per-room account
    // data - so it can fail on a flaky connection or a permission change. The
    // caller acknowledges the notification response either way, so an
    // unhandled throw here means the user taps "Snooze", the platform marks the
    // action handled, and no snooze exists anywhere. Falling back to the
    // device-local record keeps the user's intent, and reconcile() promotes it
    // once the room is reachable again.
    try {
      await room.setNotificationSnooze(
        duration.duration,
        source: 'notification_action',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Falling back to a device-local room snooze after the synced '
            'write failed',
      );
      if (!preferences.isInit) {
        await preferences.init();
      }
      await preferences.setRoomNotificationSnooze(
        clientId: clientId,
        roomId: target.roomId,
        duration: duration.duration,
        source: 'notification_action',
      );
    }
    await NotificationManager.clearNotificationsByRoute(
      clientId: clientId,
      roomId: target.roomId,
      room: room,
    );

    Log.i(
      "Room notifications snoozed from notification action "
      "duration=${duration.id}",
      category: LogCategory.notifications,
      source: 'notification-snooze',
    );
  }

  static Room? _findRoom({required String clientId, required String roomId}) {
    final client = clientManager?.getClient(clientId);
    return client?.getRoom(roomId);
  }

  static void _openNotificationStoryRoute(
    _NotificationStoryRouteTarget target, {
    required String source,
    String? responseId,
    NotificationResponseAcknowledger? acknowledgeResponse,
  }) {
    final request = target.request;
    final routeKey = request.routeKey;
    final now = DateTime.now();
    final lastOpenedAt = _lastOpenedStoryRouteAt;
    if (_lastOpenedStoryRouteKey == routeKey &&
        lastOpenedAt != null &&
        now.difference(lastOpenedAt) < _duplicateRouteWindow &&
        responseId == null) {
      Log.d(
        "Ignoring duplicate $source notification story route",
        category: LogCategory.notifications,
        source: 'notification-routing',
      );
      return;
    }
    _lastOpenedStoryRouteKey = routeKey;
    _lastOpenedStoryRouteAt = now;

    final sourceLabel = _diagnosticLabel(source);
    Log.i(
      "notification_story_route_extracted source=$sourceLabel "
      "room=${_diagnosticId(target.roomId)} "
      "story=${_diagnosticId(target.storyId)} "
      "story_event=${_diagnosticId(target.storyEventId)} "
      "story_sender=${_diagnosticId(target.storySenderId)} "
      "client=${_diagnosticClient(target.clientId)}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );

    if (acknowledgeResponse != null) {
      _startStoryNavigationWatchers();
      _pendingStoryNavigations[routeKey]?.retryTimer?.cancel();
      _pendingStoryNavigations[routeKey] = _PendingStoryNotificationNavigation(
        target: target,
        source: source,
        responseId: responseId,
        acknowledgeResponse: acknowledgeResponse,
      );
    }

    _dispatchNotificationStoryRoute(target, source: source);
    _schedulePendingStoryNavigationRetry(routeKey);
  }

  static void _dispatchNotificationStoryRoute(
    _NotificationStoryRouteTarget target, {
    required String source,
  }) {
    final readiness = _navigationReadiness(target.roomTarget);
    final sourceLabel = _diagnosticLabel(source);
    Log.i(
      "notification_story_navigation_attempted source=$sourceLabel "
      "room=${_diagnosticId(target.roomId)} "
      "story=${_diagnosticId(target.storyId)} "
      "story_event=${_diagnosticId(target.storyEventId)} "
      "story_sender=${_diagnosticId(target.storySenderId)} "
      "client=${_diagnosticClient(target.clientId)} "
      "matrix_client_ready=${readiness.clientReady} "
      "room_ready=${readiness.roomReady} "
      "router_ready=${EventBus.openStory.hasListener}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );
    EventBus.openStoryFromNotification(target.request);
  }

  static void _openNotificationRoute(
    _NotificationRouteTarget target, {
    required String source,
    String? responseId,
    NotificationResponseAcknowledger? acknowledgeResponse,
    bool openSettings = false,
  }) {
    final route = target.route;
    final routeKey = _routeKey(route);
    final now = DateTime.now();
    final lastOpenedAt = _lastOpenedRouteAt;
    if (_lastOpenedRouteKey == routeKey &&
        lastOpenedAt != null &&
        now.difference(lastOpenedAt) < _duplicateRouteWindow &&
        responseId == null) {
      Log.d(
        "Ignoring duplicate $source notification room route",
        category: LogCategory.notifications,
        source: 'notification-routing',
      );
      return;
    }
    _lastOpenedRouteKey = routeKey;
    _lastOpenedRouteAt = now;
    final sourceLabel = _diagnosticLabel(source);

    if (acknowledgeResponse != null) {
      _startSelectedRoomWatcher();
      _pendingNavigations[routeKey]?.retryTimer?.cancel();
      _pendingNavigations[routeKey] = _PendingNotificationNavigation(
        target: target,
        source: source,
        responseId: responseId,
        acknowledgeResponse: acknowledgeResponse,
        openSettings: openSettings,
      );
    }

    Log.i(
      "notification_route_extracted source=$sourceLabel "
      "room=${_diagnosticId(target.roomId)} "
      "event=${_diagnosticId(target.eventId)} "
      "client=${_diagnosticClient(target.clientId)}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );
    _dispatchNotificationRoute(
      target,
      source: source,
      openSettings: openSettings,
    );
    _schedulePendingNavigationRetry(routeKey);
  }

  static void _dispatchNotificationRoute(
    _NotificationRouteTarget target, {
    required String source,
    bool openSettings = false,
  }) {
    final route = target.route;
    final readiness = _navigationReadiness(target);
    final sourceLabel = _diagnosticLabel(source);
    Log.i(
      "notification_session_target_resolved source=$sourceLabel "
      "client=${_diagnosticClient(target.clientId)} "
      "matrix_client_ready=${readiness.clientReady} "
      "client_count=${clientManager?.clients.length ?? 0}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );
    Log.i(
      "notification_navigation_attempted source=$sourceLabel "
      "room=${_diagnosticId(target.roomId)} "
      "event=${_diagnosticId(target.eventId)} "
      "client=${_diagnosticClient(target.clientId)} "
      "matrix_client_ready=${readiness.clientReady} "
      "room_ready=${readiness.roomReady} "
      "router_ready=${EventBus.openRoom.hasListener}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );
    if (openSettings) {
      EventBus.openRoomSettingsFromNotification(route);
    } else {
      EventBus.openRoomFromNotification(route);
    }
  }

  static ({bool clientReady, bool roomReady}) _navigationReadiness(
    _NotificationRouteTarget target,
  ) {
    final manager = clientManager;
    if (manager == null) {
      return (clientReady: false, roomReady: false);
    }

    final client = target.clientId == null
        ? manager.clients
              .where((client) => client.getRoom(target.roomId) != null)
              .firstOrNull
        : manager.getClient(target.clientId!);

    return (
      clientReady: client != null,
      roomReady: client?.getRoom(target.roomId) != null,
    );
  }

  static void _schedulePendingNavigationRetry(String routeKey) {
    final pending = _pendingNavigations[routeKey];
    if (pending == null || pending.retryTimer != null) {
      return;
    }

    pending.attempts += 1;
    if (pending.attempts > _maxRetryAttempts) {
      pending.retryTimer?.cancel();
      pending.retryTimer = null;
      _pendingNavigations.remove(routeKey);
      final sourceLabel = _diagnosticLabel(pending.source);
      Log.w(
        "notification_navigation_failed_pending source=$sourceLabel "
        "room=${_diagnosticId(pending.target.roomId)} "
        "reason=max_retry_exceeded retrying=false",
        category: LogCategory.notifications,
        source: 'notification-routing',
      );
      _acknowledgeTerminalResponse(
        responseId: pending.responseId,
        acknowledgeResponse: pending.acknowledgeResponse,
        source: pending.source,
        reason: 'navigation_retry_exhausted',
      );
      return;
    }

    final delay = pending.attempts <= _fastRetryLimit
        ? _fastRetryDelay
        : _slowRetryDelay;
    pending.retryTimer = Timer(delay, () {
      pending.retryTimer = null;
      if (!_pendingNavigations.containsKey(routeKey)) {
        return;
      }
      if (pending.attempts == _fastRetryLimit + 1) {
        final sourceLabel = _diagnosticLabel(pending.source);
        Log.w(
          "notification_navigation_failed_pending source=$sourceLabel "
          "room=${_diagnosticId(pending.target.roomId)} "
          "reason=not_ready_after_fast_retries retrying=true",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
      }
      if (EventBus.openRoom.hasListener) {
        _dispatchNotificationRoute(
          pending.target,
          source: "${pending.source} retry",
          openSettings: pending.openSettings,
        );
      } else {
        final sourceLabel = _diagnosticLabel(pending.source);
        Log.i(
          "notification_navigation_retry_waiting source=$sourceLabel "
          "room=${_diagnosticId(pending.target.roomId)} router_ready=false",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
      }
      _schedulePendingNavigationRetry(routeKey);
    });
  }

  static void _schedulePendingStoryNavigationRetry(String routeKey) {
    final pending = _pendingStoryNavigations[routeKey];
    if (pending == null || pending.retryTimer != null) {
      return;
    }

    pending.attempts += 1;
    if (pending.attempts > _maxRetryAttempts) {
      pending.retryTimer?.cancel();
      pending.retryTimer = null;
      _pendingStoryNavigations.remove(routeKey);
      final sourceLabel = _diagnosticLabel(pending.source);
      Log.w(
        "notification_story_navigation_failed_pending source=$sourceLabel "
        "room=${_diagnosticId(pending.target.roomId)} "
        "story=${_diagnosticId(pending.target.storyId)} "
        "reason=max_retry_exceeded retrying=false",
        category: LogCategory.notifications,
        source: 'notification-routing',
      );
      _acknowledgeTerminalResponse(
        responseId: pending.responseId,
        acknowledgeResponse: pending.acknowledgeResponse,
        source: pending.source,
        reason: 'story_navigation_retry_exhausted',
      );
      return;
    }

    final delay = pending.attempts <= _fastRetryLimit
        ? _fastRetryDelay
        : _slowRetryDelay;
    pending.retryTimer = Timer(delay, () {
      pending.retryTimer = null;
      if (!_pendingStoryNavigations.containsKey(routeKey)) {
        return;
      }
      if (pending.attempts == _fastRetryLimit + 1) {
        final sourceLabel = _diagnosticLabel(pending.source);
        Log.w(
          "notification_story_navigation_failed_pending source=$sourceLabel "
          "room=${_diagnosticId(pending.target.roomId)} "
          "story=${_diagnosticId(pending.target.storyId)} "
          "reason=not_ready_after_fast_retries retrying=true",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
      }
      if (EventBus.openStory.hasListener) {
        _dispatchNotificationStoryRoute(
          pending.target,
          source: "${pending.source} retry",
        );
      } else {
        final sourceLabel = _diagnosticLabel(pending.source);
        Log.i(
          "notification_story_navigation_retry_waiting source=$sourceLabel "
          "room=${_diagnosticId(pending.target.roomId)} "
          "story=${_diagnosticId(pending.target.storyId)} router_ready=false",
          category: LogCategory.notifications,
          source: 'notification-routing',
        );
      }
      _schedulePendingStoryNavigationRetry(routeKey);
    });
  }

  static void _startSelectedRoomWatcher() {
    _selectedRoomSubscription ??= EventBus.onSelectedRoomChanged.stream.listen(
      _handleSelectedRoom,
    );
  }

  static void _startStoryNavigationWatchers() {
    _startSelectedRoomWatcher();
    _openedStorySubscription ??= EventBus.onStoryOpened.stream.listen(
      _handleOpenedStory,
    );
  }

  static void _handleSelectedRoom(Room? room) {
    if (room == null ||
        (_pendingNavigations.isEmpty && _pendingStoryNavigations.isEmpty)) {
      return;
    }

    final route = (room.identifier, room.client.identifier);
    _completePendingNavigation(route, clientIdForLog: room.client.identifier);
    _completePendingStoryNavigationForRoom(
      route,
      clientIdForLog: room.client.identifier,
    );
  }

  static void _handleOpenedStory(StoryOpenRequest request) {
    if (_pendingStoryNavigations.isEmpty) {
      return;
    }

    _completePendingStoryNavigation(
      request.routeKey,
      reason: 'story_navigation_succeeded',
    );
  }

  static void _completePendingNavigation(
    (String, String?) route, {
    String? clientIdForLog,
  }) {
    final routeKey = _routeKey(route);
    final autoRouteKey = _routeKey((route.$1, null));
    final pending =
        _pendingNavigations.remove(routeKey) ??
        _pendingNavigations.remove(autoRouteKey);
    if (pending == null) {
      return;
    }

    pending.retryTimer?.cancel();
    final sourceLabel = _diagnosticLabel(pending.source);
    Log.i(
      "notification_navigation_succeeded source=$sourceLabel "
      "room=${_diagnosticId(pending.target.roomId)} "
      "event=${_diagnosticId(pending.target.eventId)} "
      "client=${_diagnosticClient(clientIdForLog ?? route.$2)}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );

    final responseId = pending.responseId;
    final acknowledgeResponse = pending.acknowledgeResponse;
    _acknowledgeTerminalResponse(
      responseId: responseId,
      acknowledgeResponse: acknowledgeResponse,
      source: pending.source,
      reason: 'navigation_succeeded',
    );
  }

  static void _completePendingStoryNavigationForRoom(
    (String, String?) route, {
    String? clientIdForLog,
  }) {
    final routeKey = _routeKey(route);
    final matchingStoryRouteKeys = _pendingStoryNavigations.entries
        .where(
          (entry) => _routeKey(entry.value.target.roomTarget.route) == routeKey,
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    for (final storyRouteKey in matchingStoryRouteKeys) {
      _completePendingStoryNavigation(
        storyRouteKey,
        reason: 'story_fallback_room_selected',
        clientIdForLog: clientIdForLog ?? route.$2,
      );
    }
  }

  static void _completePendingStoryNavigation(
    String routeKey, {
    required String reason,
    String? clientIdForLog,
  }) {
    final pending = _pendingStoryNavigations.remove(routeKey);
    if (pending == null) {
      return;
    }

    pending.retryTimer?.cancel();
    final sourceLabel = _diagnosticLabel(pending.source);
    Log.i(
      "notification_story_navigation_succeeded source=$sourceLabel "
      "room=${_diagnosticId(pending.target.roomId)} "
      "story=${_diagnosticId(pending.target.storyId)} "
      "story_event=${_diagnosticId(pending.target.storyEventId)} "
      "story_sender=${_diagnosticId(pending.target.storySenderId)} "
      "client=${_diagnosticClient(clientIdForLog ?? pending.target.clientId)} "
      "reason=$reason",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );

    _acknowledgeTerminalResponse(
      responseId: pending.responseId,
      acknowledgeResponse: pending.acknowledgeResponse,
      source: pending.source,
      reason: reason,
    );
  }

  static void _acknowledgeTerminalResponse({
    required String? responseId,
    required NotificationResponseAcknowledger? acknowledgeResponse,
    required String source,
    required String reason,
  }) {
    if (responseId != null && acknowledgeResponse != null) {
      final sourceLabel = _diagnosticLabel(source);
      Log.i(
        "notification_response_acknowledging source=$sourceLabel "
        "reason=$reason",
        category: LogCategory.notifications,
        source: 'notification-routing',
      );
      unawaited(
        acknowledgeResponse(responseId).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          Log.onError(
            error,
            stackTrace,
            content: "Failed to acknowledge iOS notification response",
            category: LogCategory.notifications,
            source: 'notification-routing',
          );
        }),
      );
    }
  }

  static String _routeKey((String, String?) route) {
    return "${route.$2 ?? ''}\u0000${route.$1}";
  }

  static void _logPayloadReceived(String sourceLabel, Object? payload) {
    Log.i(
      "notification_payload_received source=${_diagnosticLabel(sourceLabel)} "
      "type=${payload.runtimeType} keys=${_payloadKeysDiagnostic(payload)}",
      category: LogCategory.notifications,
      source: 'notification-routing',
    );
  }

  static String _payloadKeysDiagnostic(Object? payload) {
    final data = _normalizePayload(payload);
    if (data == null || data.isEmpty) {
      return 'none';
    }
    return data.keys.take(12).join(',');
  }

  static String? _responseIdFromPayloadData(Map<String, Object?> data) {
    return _firstString(data, const ['response_id', 'responseId']);
  }

  static String? _actionIdFromPayloadData(Map<String, Object?> data) {
    return _firstString(data, const ['action_id', 'actionId']);
  }

  static String? _inputFromPayloadData(Map<String, Object?> data) {
    return _firstString(data, const ['input', 'user_text', 'userText']);
  }

  static String _diagnosticId(String? value) {
    if (value == null || value.isEmpty) {
      return 'none';
    }

    return MatrixClient.hash(value).substring(0, 12);
  }

  static String _diagnosticClient(String? value) {
    if (value == null || value.isEmpty) {
      return 'auto';
    }

    return _diagnosticId(value);
  }

  static String _diagnosticLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'unknown';
    }

    return trimmed.replaceAll(RegExp(r'\s+'), '_');
  }

  @visibleForTesting
  static int get pendingNavigationCountForTesting => _pendingNavigations.length;

  @visibleForTesting
  static int get pendingStoryNavigationCountForTesting =>
      _pendingStoryNavigations.length;

  @visibleForTesting
  static void markNavigationSucceededForTesting((String, String?) route) {
    _completePendingNavigation(route);
    _completePendingStoryNavigationForRoom(route);
  }

  @visibleForTesting
  static void markStoryNavigationSucceededForTesting(StoryOpenRequest request) {
    _completePendingStoryNavigation(
      request.routeKey,
      reason: 'story_navigation_succeeded',
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    for (final pending in _pendingNavigations.values) {
      pending.retryTimer?.cancel();
    }
    _pendingNavigations.clear();
    for (final pending in _pendingStoryNavigations.values) {
      pending.retryTimer?.cancel();
    }
    _pendingStoryNavigations.clear();
    unawaited(_selectedRoomSubscription?.cancel());
    _selectedRoomSubscription = null;
    unawaited(_openedStorySubscription?.cancel());
    _openedStorySubscription = null;
    _lastOpenedRouteKey = null;
    _lastOpenedRouteAt = null;
    _lastOpenedStoryRouteKey = null;
    _lastOpenedStoryRouteAt = null;
  }

  static CustomURI? _firstUri(Map<String, Object?> payload, List<String> keys) {
    for (final key in keys) {
      final uri = _parseUri(_stringValue(payload[key]));
      if (uri != null) {
        return uri;
      }
    }

    return null;
  }

  /// Identity for de-duplicating an inline reply.
  ///
  /// Prefers the **notification response id**, because that is what the repeated
  /// cold-launch deliveries actually share: one response redelivered, not two
  /// replies that happen to match. Keyed that way, sending the same text twice
  /// is two different responses and both send — which is legitimate user
  /// behaviour that the text-based key wrongly suppressed, as the maintainer hit
  /// on device on 2026-08-14.
  ///
  /// Falls back to client/room/text when no response id is available (the
  /// plugin-callback path carries none). That fallback keeps the original
  /// cold-launch protection, and keeps its original tradeoff, but it is now the
  /// exception rather than the rule.
  static String? _inlineReplyKey(
    SendMessageUri uri,
    String? input, {
    String? responseId,
  }) {
    final message = input?.trim();
    if (message == null || message.isEmpty) {
      return null;
    }
    if (responseId != null && responseId.isNotEmpty) {
      return "response|$responseId";
    }
    return "${uri.clientId}|${uri.roomId}|$message";
  }

  /// True when this exact reply is already in flight or already sent inside the
  /// dedupe window.
  ///
  /// Claiming is deliberately synchronous and happens before any await, so the
  /// several cold-launch delivery paths collapse even though they all enqueue
  /// during startup: on a single-threaded isolate the first caller records the
  /// key before any other can observe it. The claim is released again if the
  /// send fails, so a later delivery can still retry.
  static bool _claimInlineReply(String key) {
    final now = DateTime.now();
    _recentInlineReplies.removeWhere(
      (_, at) => now.difference(at) > _duplicateInlineReplyWindow,
    );

    final seenAt = _recentInlineReplies[key];
    if (seenAt != null &&
        now.difference(seenAt) <= _duplicateInlineReplyWindow) {
      Log.w(
        "Suppressed a duplicate notification inline reply; the same message "
        "was already sent or is in flight from another delivery path.",
        category: LogCategory.notifications,
        source: 'notification-response',
      );
      return true;
    }

    _recentInlineReplies[key] = now;
    return false;
  }

  /// Stands in for the real send so a test can make it succeed or fail.
  ///
  /// The dedupe contract is "at most one *successful* send", and a test has no
  /// live client, so without this seam every send fails and the retry path is
  /// the only reachable behaviour.
  @visibleForTesting
  static Future<bool> Function(SendMessageUri uri, String message)?
  inlineReplySenderForTest;

  @visibleForTesting
  static void resetInlineReplyDedupeForTest() {
    _recentInlineReplies.clear();
    inlineReplySenderForTest = null;
  }

  static Future<InlineReplyOutcome> _enqueueInlineReply(
    SendMessageUri uri,
    String? input, {
    String? responseId,
  }) async {
    final key = _inlineReplyKey(uri, input, responseId: responseId);
    if (key != null && _claimInlineReply(key)) {
      return InlineReplyOutcome.duplicate;
    }

    final previous = _inlineReplyTail;
    final next = previous
        .catchError((Object error, StackTrace stackTrace) {
          Log.w("Previous notification inline reply failed");
          Log.onError(error, stackTrace);
        })
        .then((_) => _handleInlineReply(uri, input))
        .then((outcome) {
          // Keep the claim only for a send that actually landed. The repeated
          // cold-launch deliveries are not merely duplicates: they arrive at
          // different points of startup, and an early one can fail because the
          // client is not restored yet. Holding a claim for a failed attempt
          // suppressed the later delivery that would have worked, which is how
          // the first version of this guard stopped backgrounded replies from
          // sending at all.
          if (outcome != InlineReplyOutcome.sent && key != null) {
            _recentInlineReplies.remove(key);
          }
          return outcome;
        });
    _inlineReplyTail = next;

    return next;
  }

  /// Reports why the attempt finished, not merely whether it sent.
  ///
  /// Two callers depend on the distinction: the duplicate claim is kept only
  /// for [InlineReplyOutcome.sent], so a delivery that arrived before the
  /// client was restored does not block the later one that can succeed; and the
  /// platform response is acknowledged for everything except
  /// [InlineReplyOutcome.failed], so a reply that did not send keeps its native
  /// redelivery path instead of being marked handled.
  static Future<InlineReplyOutcome> _handleInlineReply(
    SendMessageUri uri,
    String? input,
  ) async {
    final message = input?.trim();
    if (message == null || message.isEmpty) {
      // Nothing was typed. Redelivering it would only produce the same nothing,
      // so this is terminal even though it did not send.
      return InlineReplyOutcome.empty;
    }

    final sender = inlineReplySenderForTest;
    if (sender != null) {
      try {
        return await sender(uri, message)
            ? InlineReplyOutcome.sent
            : InlineReplyOutcome.failed;
      } catch (error, stackTrace) {
        Log.onError(error, stackTrace, content: 'Inline reply sender threw');
        return InlineReplyOutcome.failed;
      }
    }

    final Room room;
    try {
      // Inside the mapping on purpose. A cold launch runs the whole client
      // restore here, and when that threw, the outcome never became `failed` -
      // so the dedupe claim was never released, the redelivery that could have
      // worked came back `duplicate`, and the response was acknowledged with no
      // Matrix message ever sent.
      await _ensureClientManagerReady();
      final resolved = clientManager
          ?.getClient(uri.clientId)
          ?.getRoom(uri.roomId);
      if (resolved == null) {
        Log.w(
          "Failed to send notification reply because room ${uri.roomId} "
          "for client ${uri.clientId} was not available.",
        );
        return InlineReplyOutcome.failed;
      }
      room = resolved;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            "Failed to prepare the client for a notification reply to "
            "${uri.roomId}",
      );
      return InlineReplyOutcome.failed;
    }

    try {
      // The return value is the success signal, and discarding it was the bug.
      //
      // `sendMessage` does not throw for an ordinary failure: the SDK marks the
      // local echo `EventStatus.error` and returns null, rethrowing only for
      // `EventTooLarge` and `M_FORBIDDEN` (matrix `room.dart:1269-1295`). So a
      // bare try/catch that ignores the result reports every network failure,
      // 5xx and post-timeout ratelimit as a success.
      //
      // That is why the duplicate guard's release-on-failure path almost never
      // fired: nothing it watched for ever happened. Server-accepted is not
      // delivery-confirmed, but it is the strongest signal available on the
      // client, and it is the one that makes "at most one SUCCESSFUL send"
      // enforceable rather than aspirational.
      final sent = await room.sendMessage(
        message: message,
        processedAttachments: const [],
      );
      if (sent == null) {
        Log.w(
          "Notification reply was not accepted by the server; the local echo "
          "is in an error state and the reply will be retried.",
          category: LogCategory.notifications,
          source: 'notification-response',
        );
        return InlineReplyOutcome.failed;
      }
      return InlineReplyOutcome.sent;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            "Failed to send notification reply to ${uri.roomId} for ${uri.clientId}",
      );
      return InlineReplyOutcome.failed;
    }
  }

  /// Waits for the account database if B5 released it before suspension.
  ///
  /// A notification tap is a resume: the response arrives BEFORE the release
  /// trigger's own observer has scheduled the re-establish, and the room the
  /// route opens starts its timeline against a released connection, which
  /// throws by design (observed on the iPhone on 2026-09-04). The trigger arms
  /// its gate when it releases, so waiting is order-independent; it is already
  /// complete when nothing was released, and there is no trigger at all before
  /// attach (a cold launch, where nothing can be released yet).
  ///
  /// Delegates to [DatabaseReleaseTrigger.waitForDatabase], which is the shared
  /// implementation of this wait - this handler was one of the three copies it
  /// was extracted from. The label is sanitised BEFORE it crosses over, because
  /// `waitForDatabase` logs its `source` verbatim and the values here are
  /// caller-supplied strings that reach the redaction rules for notifications.
  ///
  /// The result is deliberately discarded: a failed re-establish is logged by
  /// the trigger and the tap STILL dispatches, because the pending-navigation
  /// retry is the recovery path and a tap that does nothing is worse than one
  /// that routes into a room which retries.
  static Future<void> _awaitDatabaseEstablished(String source) async {
    await DatabaseReleaseTrigger.waitForDatabase(_diagnosticLabel(source));
  }

  static Future<void> _ensureClientManagerReady() async {
    if (clientManager != null) {
      return;
    }

    ensureBindingInit();
    loading ??= initNecessary();
    await loading;
  }

  static CustomURI? _parseUri(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    return CustomURI.parse(value);
  }

  static Map<String, Object?>? _normalizePayload(Object? payload) {
    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        return _normalizePayload(decoded);
      } catch (_) {
        return null;
      }
    }

    if (payload is! Map) {
      return null;
    }

    return payload.map((key, value) => MapEntry(key.toString(), value));
  }

  static String? _firstString(Map<String, Object?> payload, List<String> keys) {
    for (final key in keys) {
      final value = _stringValue(payload[key]);
      if (value != null) {
        return value;
      }
    }

    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }

    final string = value.toString();
    return string.isEmpty ? null : string;
  }
}
