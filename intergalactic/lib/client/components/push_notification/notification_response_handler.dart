import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/event_bus.dart';

typedef NotificationResponseAcknowledger = Future<void> Function(
  String responseId,
);

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
  });

  final _NotificationRouteTarget target;
  final String source;
  final String? responseId;
  final NotificationResponseAcknowledger? acknowledgeResponse;
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
  static const Duration _fastRetryDelay = Duration(milliseconds: 500);
  static const Duration _slowRetryDelay = Duration(seconds: 5);
  static const int _fastRetryLimit = 24;
  static const int _maxRetryAttempts = 120;
  static Future<void> _inlineReplyTail = Future<void>.value();
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

      final snoozeDuration =
          RoomNotificationSnoozeDurationOption.fromNotificationActionId(
        details.actionId,
      );
      if (snoozeDuration != null) {
        await _handleSnoozeRoomAction(details, snoozeDuration);
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
        final storyRoute =
            data == null ? null : _storyTargetFromPayloadData(data);
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

      final storyTarget = _storyTargetFromPayloadData(data);
      if (storyTarget != null) {
        _openNotificationStoryRoute(
          storyTarget,
          source: source,
          responseId: _responseIdFromPayloadData(data),
          acknowledgeResponse: acknowledgeResponse,
        );
        return;
      }

      final target = _targetFromPayloadData(data);
      if (target != null) {
        _openNotificationRoute(
          target,
          source: source,
          responseId: _responseIdFromPayloadData(data),
          acknowledgeResponse: acknowledgeResponse,
        );
      } else {
        _acknowledgeTerminalResponse(
          responseId: _responseIdFromPayloadData(data),
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

    final clientId = target.clientId!;
    if (!preferences.isInit) {
      await preferences.init();
    }

    await preferences.setRoomNotificationSnooze(
      clientId: clientId,
      roomId: target.roomId,
      duration: duration.duration,
      source: 'notification_action',
    );

    final room = _findRoom(clientId: clientId, roomId: target.roomId);
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

  static Room? _findRoom({
    required String clientId,
    required String roomId,
  }) {
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
    _dispatchNotificationRoute(target, source: source);
    _schedulePendingNavigationRetry(routeKey);
  }

  static void _dispatchNotificationRoute(
    _NotificationRouteTarget target, {
    required String source,
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
    EventBus.openRoomFromNotification(route);
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

    final delay =
        pending.attempts <= _fastRetryLimit ? _fastRetryDelay : _slowRetryDelay;
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

    final delay =
        pending.attempts <= _fastRetryLimit ? _fastRetryDelay : _slowRetryDelay;
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
    _selectedRoomSubscription ??=
        EventBus.onSelectedRoomChanged.stream.listen(_handleSelectedRoom);
  }

  static void _startStoryNavigationWatchers() {
    _startSelectedRoomWatcher();
    _openedStorySubscription ??=
        EventBus.onStoryOpened.stream.listen(_handleOpenedStory);
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
    final pending = _pendingNavigations.remove(routeKey) ??
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
        acknowledgeResponse(responseId).catchError(
          (Object error, StackTrace stackTrace) {
            Log.onError(
              error,
              stackTrace,
              content: "Failed to acknowledge iOS notification response",
              category: LogCategory.notifications,
              source: 'notification-routing',
            );
          },
        ),
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
  static void markStoryNavigationSucceededForTesting(
    StoryOpenRequest request,
  ) {
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

  static Future<void> _enqueueInlineReply(
    SendMessageUri uri,
    String? input,
  ) async {
    final previous = _inlineReplyTail;
    final next = previous.catchError((Object error, StackTrace stackTrace) {
      Log.w("Previous notification inline reply failed");
      Log.onError(error, stackTrace);
    }).then((_) => _handleInlineReply(uri, input));
    _inlineReplyTail = next;

    await next;
  }

  static Future<void> _handleInlineReply(
    SendMessageUri uri,
    String? input,
  ) async {
    final message = input?.trim();
    if (message == null || message.isEmpty) {
      return;
    }

    await _ensureClientManagerReady();

    final room = clientManager?.getClient(uri.clientId)?.getRoom(uri.roomId);
    if (room == null) {
      Log.w(
        "Failed to send notification reply because room ${uri.roomId} "
        "for client ${uri.clientId} was not available.",
      );
      return;
    }

    try {
      await room.sendMessage(message: message, processedAttachments: const []);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            "Failed to send notification reply to ${uri.roomId} for ${uri.clientId}",
      );
    }
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
