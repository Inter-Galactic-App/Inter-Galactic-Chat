import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/notification_response_handler.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NotificationResponseHandler', () {
    test('routes direct open-room URI payloads', () async {
      final route = await _routeForPayload(
        OpenRoomURI(
          roomId: '!room:example.org',
          clientId: '@user:example.org',
        ).toString(),
      );

      expect(route?.$1, '!room:example.org');
      expect(route?.$2, '@user:example.org');
    });

    test('routes direct open-story URI payloads', () async {
      final route = await _storyRouteForPayload(
        OpenStoryURI(
          roomId: '!story-room:example.org',
          clientId: '@user:example.org',
          storySenderId: '@alice:example.org',
          storyId: 'story-123',
          storyEventId: r'$story-event',
        ).toString(),
      );

      expect(route?.roomId, '!story-room:example.org');
      expect(route?.clientId, '@user:example.org');
      expect(route?.storySenderId, '@alice:example.org');
      expect(route?.storyId, 'story-123');
      expect(route?.storyEventId, r'$story-event');
    });

    test('routes nested APNs payload maps', () async {
      final route = await _routeForPayload({
        'aps': {'alert': 'Message'},
        'custom': {
          'data': {
            'roomId': '!nested:example.org',
            'clientId': '@nested:example.org',
          },
        },
      });

      expect(route?.$1, '!nested:example.org');
      expect(route?.$2, '@nested:example.org');
    });

    test('routes nested story notification payload maps', () async {
      final route = await _storyRouteForPayload({
        'aps': {'alert': 'Story'},
        'custom': {
          'data': {
            'roomId': '!story-nested:example.org',
            'clientId': '@story-client:example.org',
            'storySenderId': '@alice:example.org',
            'storyId': 'story-nested',
            'storyEventId': r'$story-nested-event',
          },
        },
      });

      expect(route?.roomId, '!story-nested:example.org');
      expect(route?.clientId, '@story-client:example.org');
      expect(route?.storySenderId, '@alice:example.org');
      expect(route?.storyId, 'story-nested');
      expect(route?.storyEventId, r'$story-nested-event');
    });

    test('routes Matrix push gateway APNs alert payloads', () async {
      final route = await _routeForPayload({
        'response_id': 'test-response-id',
        'userInfo': {
          'aps': {
            'alert': {'title': 'Nick', 'body': 'New message'},
            'content-available': 1,
          },
          'event_id': r'$event:example.org',
          'room_id': '!gateway:example.org',
          'client_id': '@gateway:example.org',
        },
      });

      expect(route?.$1, '!gateway:example.org');
      expect(route?.$2, '@gateway:example.org');
    });

    test('routes JSON payload strings inside APNs payloads', () async {
      final route = await _routeForPayload({
        'payload': jsonEncode({
          'payload': OpenRoomURI(
            roomId: '!json:example.org',
            clientId: '@json:example.org',
          ).toString(),
        }),
      });

      expect(route?.$1, '!json:example.org');
      expect(route?.$2, '@json:example.org');
    });

    test(
      'routes selected notification response data when payload is empty',
      () async {
        while (EventBus.takePendingOpenRoom() != null) {}

        final events = <(String, String?)>[];
        final subscription = EventBus.openRoom.stream.listen(events.add);
        try {
          await NotificationResponseHandler.handle(
            const NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
              data: {
                'room_id': '!data:example.org',
                'client_id': '@data:example.org',
              },
            ),
          );
          await pumpEventQueue();

          final route =
              events.isEmpty ? EventBus.takePendingOpenRoom() : events.single;
          expect(route?.$1, '!data:example.org');
          expect(route?.$2, '@data:example.org');
        } finally {
          await subscription.cancel();
          while (EventBus.takePendingOpenRoom() != null) {}
        }
      },
    );

    test('keeps iOS responses pending until room navigation succeeds',
        () async {
      NotificationResponseHandler.resetForTesting();
      while (EventBus.takePendingOpenRoom() != null) {}

      var acknowledgedResponseIds = <String>[];
      await NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'ios-response-1',
          'userInfo': {
            'room_id': '!pending:example.org',
            'client_id': '@pending:example.org',
            'event_id': r'$pending-event',
          },
        },
        source: 'ios apns callback test',
        acknowledgeResponse: (responseId) async {
          acknowledgedResponseIds.add(responseId);
        },
      );

      expect(NotificationResponseHandler.pendingNavigationCountForTesting, 1);
      expect(acknowledgedResponseIds, isEmpty);

      NotificationResponseHandler.markNavigationSucceededForTesting(
        ('!pending:example.org', '@pending:example.org'),
      );
      await pumpEventQueue();

      expect(acknowledgedResponseIds, ['ios-response-1']);
      expect(NotificationResponseHandler.pendingNavigationCountForTesting, 0);
      while (EventBus.takePendingOpenRoom() != null) {}
      NotificationResponseHandler.resetForTesting();
    });

    test('keeps iOS story responses pending until story navigation succeeds',
        () async {
      NotificationResponseHandler.resetForTesting();
      while (EventBus.takePendingOpenRoom() != null) {}
      while (EventBus.takePendingOpenStory() != null) {}

      final acknowledgedResponseIds = <String>[];
      await NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'ios-story-response-1',
          'userInfo': {
            'room_id': '!story-pending:example.org',
            'client_id': '@story-client:example.org',
            'story_sender_id': '@alice:example.org',
            'story_id': 'story-pending',
            'story_event_id': r'$story-pending-event',
          },
        },
        source: 'ios apns callback test',
        acknowledgeResponse: (responseId) async {
          acknowledgedResponseIds.add(responseId);
        },
      );

      expect(
        NotificationResponseHandler.pendingStoryNavigationCountForTesting,
        1,
      );
      expect(acknowledgedResponseIds, isEmpty);

      NotificationResponseHandler.markStoryNavigationSucceededForTesting(
        const StoryOpenRequest(
          roomId: '!story-pending:example.org',
          clientId: '@story-client:example.org',
          storySenderId: '@alice:example.org',
          storyId: 'story-pending',
          storyEventId: r'$story-pending-event',
        ),
      );
      await pumpEventQueue();

      expect(acknowledgedResponseIds, ['ios-story-response-1']);
      expect(
        NotificationResponseHandler.pendingStoryNavigationCountForTesting,
        0,
      );
      while (EventBus.takePendingOpenStory() != null) {}
      NotificationResponseHandler.resetForTesting();
    });

    test('acknowledges iOS story responses after fallback room navigation',
        () async {
      NotificationResponseHandler.resetForTesting();
      while (EventBus.takePendingOpenRoom() != null) {}
      while (EventBus.takePendingOpenStory() != null) {}

      final acknowledgedResponseIds = <String>[];
      await NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'ios-story-fallback-response-1',
          'userInfo': {
            'room_id': '!story-fallback:example.org',
            'client_id': '@story-client:example.org',
            'story_sender_id': '@alice:example.org',
            'story_id': 'story-fallback',
          },
        },
        source: 'ios apns callback test',
        acknowledgeResponse: (responseId) async {
          acknowledgedResponseIds.add(responseId);
        },
      );

      expect(
        NotificationResponseHandler.pendingStoryNavigationCountForTesting,
        1,
      );
      expect(acknowledgedResponseIds, isEmpty);
      final pendingStory = EventBus.takePendingOpenStory();
      expect(pendingStory?.roomRoute, (
        '!story-fallback:example.org',
        '@story-client:example.org',
      ));
      expect(pendingStory?.storyId, 'story-fallback');

      NotificationResponseHandler.markNavigationSucceededForTesting(
        ('!story-fallback:example.org', '@story-client:example.org'),
      );
      await pumpEventQueue();

      expect(acknowledgedResponseIds, ['ios-story-fallback-response-1']);
      expect(
        NotificationResponseHandler.pendingStoryNavigationCountForTesting,
        0,
      );
      while (EventBus.takePendingOpenStory() != null) {}
      NotificationResponseHandler.resetForTesting();
    });

    test('acknowledges terminal iOS responses that have no room route',
        () async {
      NotificationResponseHandler.resetForTesting();
      while (EventBus.takePendingOpenRoom() != null) {}

      final acknowledgedResponseIds = <String>[];
      await NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'ios-response-no-route',
          'userInfo': {
            'aps': {
              'alert': {'title': 'No route'},
            },
          },
        },
        source: 'ios apns callback test',
        acknowledgeResponse: (responseId) async {
          acknowledgedResponseIds.add(responseId);
        },
      );
      await pumpEventQueue();

      expect(NotificationResponseHandler.pendingNavigationCountForTesting, 0);
      expect(acknowledgedResponseIds, ['ios-response-no-route']);
      while (EventBus.takePendingOpenRoom() != null) {}
      NotificationResponseHandler.resetForTesting();
    });

    test('stores room snooze from notification action payload', () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      await NotificationResponseHandler.handle(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId:
              RoomNotificationSnoozeDurationOption.oneHour.notificationActionId,
          payload: OpenRoomURI(
            roomId: '!snooze:example.org',
            clientId: '@alice:example.org',
          ).toString(),
        ),
      );

      final snooze = globals.preferences.getRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!snooze:example.org',
      );

      expect(snooze, isNotNull);
      expect(snooze!.source, 'notification_action');
      expect(
        snooze.snoozedUntil.difference(snooze.createdAt).inMinutes,
        RoomNotificationSnoozeDurationOption.oneHour.minutes,
      );
    });

    test('stores room snooze from story notification action payload', () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      await NotificationResponseHandler.handle(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId:
              RoomNotificationSnoozeDurationOption.oneHour.notificationActionId,
          payload: OpenStoryURI(
            roomId: '!story-snooze:example.org',
            clientId: '@alice:example.org',
            storySenderId: '@bob:example.org',
            storyId: 'story-snooze',
          ).toString(),
        ),
      );

      final snooze = globals.preferences.getRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!story-snooze:example.org',
      );

      expect(snooze, isNotNull);
      expect(snooze!.source, 'notification_action');
    });
  });
}

Future<(String, String?)?> _routeForPayload(Object? payload) async {
  NotificationResponseHandler.resetForTesting();
  while (EventBus.takePendingOpenRoom() != null) {}
  while (EventBus.takePendingOpenStory() != null) {}

  final events = <(String, String?)>[];
  final subscription = EventBus.openRoom.stream.listen(events.add);
  try {
    await NotificationResponseHandler.handleRemotePayload(payload);
    await pumpEventQueue();
    return events.isEmpty ? EventBus.takePendingOpenRoom() : events.single;
  } finally {
    await subscription.cancel();
    while (EventBus.takePendingOpenRoom() != null) {}
    while (EventBus.takePendingOpenStory() != null) {}
    NotificationResponseHandler.resetForTesting();
  }
}

Future<StoryOpenRequest?> _storyRouteForPayload(Object? payload) async {
  NotificationResponseHandler.resetForTesting();
  while (EventBus.takePendingOpenRoom() != null) {}
  while (EventBus.takePendingOpenStory() != null) {}

  final events = <StoryOpenRequest>[];
  final subscription = EventBus.openStory.stream.listen(events.add);
  try {
    await NotificationResponseHandler.handleRemotePayload(payload);
    await pumpEventQueue();
    return events.isEmpty ? EventBus.takePendingOpenStory() : events.single;
  } finally {
    await subscription.cancel();
    while (EventBus.takePendingOpenRoom() != null) {}
    while (EventBus.takePendingOpenStory() != null) {}
    NotificationResponseHandler.resetForTesting();
  }
}
