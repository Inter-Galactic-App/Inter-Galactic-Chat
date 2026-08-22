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

    test(
      'routes the notification Mute action to room notification settings',
      () async {
        while (EventBus.takePendingOpenRoom() != null) {}

        final events = <(String, String?)>[];
        final subscription = EventBus.openRoom.stream.listen(events.add);
        const route = ('!mute:example.org', '@user:example.org');
        try {
          await NotificationResponseHandler.handleRemotePayload({
            'action_id': roomNotificationSnoozePickerActionId,
            'room_id': route.$1,
            'client_id': route.$2,
          });
          await pumpEventQueue();

          expect(events, [route]);
          expect(EventBus.hasNotificationOpenRoomSettings(route), isTrue);
        } finally {
          EventBus.consumeNotificationOpenRoomSettings(route);
          await subscription.cancel();
          while (EventBus.takePendingOpenRoom() != null) {}
        }
      },
    );

    test('acknowledges an empty iOS inline Reply without routing', () async {
      while (EventBus.takePendingOpenRoom() != null) {}
      final acknowledged = <String>[];
      await NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'reply-response',
          'action_id': richNotificationReplyActionId,
          'input': '   ',
          'room_id': '!reply:example.org',
          'client_id': '@user:example.org',
        },
        acknowledgeResponse: (responseId) async {
          acknowledged.add(responseId);
        },
      );
      await pumpEventQueue();

      expect(acknowledged, ['reply-response']);
      expect(EventBus.takePendingOpenRoom(), isNull);
    });

    Future<void> deliverReply(String message) =>
        NotificationResponseHandler.handleRemotePayload({
          'response_id': 'reply-response',
          'action_id': richNotificationReplyActionId,
          'input': message,
          'room_id': '!reply:example.org',
          'client_id': '@user:example.org',
        }, acknowledgeResponse: (_) async {});

    test(
      'sends an inline reply once when a cold launch delivers it repeatedly',
      () async {
        // A cold launch delivers the same response through the plugin
        // callback, the native pending handoff, and the launch details. Each
        // one used to send, so a reply typed with the app fully closed arrived
        // three times.
        NotificationResponseHandler.resetInlineReplyDedupeForTest();
        final sent = <String>[];
        NotificationResponseHandler.inlineReplySenderForTest =
            (_, message) async {
              sent.add(message);
              return true;
            };
        addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

        for (var i = 0; i < 3; i++) {
          await deliverReply('on my way');
        }
        await pumpEventQueue();

        expect(sent, ['on my way'], reason: 'three deliveries, one send');
      },
    );

    test('retries the reply when an earlier delivery failed to send', () async {
      // REGRESSION: the first version of this guard claimed the key on ATTEMPT,
      // so a delivery that arrived before the client was restored held the
      // claim, and the later delivery that could actually send was suppressed.
      // Backgrounded replies stopped sending entirely. The claim must survive
      // only a successful send.
      NotificationResponseHandler.resetInlineReplyDedupeForTest();
      final attempts = <String>[];
      var shouldSucceed = false;
      NotificationResponseHandler.inlineReplySenderForTest =
          (_, message) async {
            attempts.add(message);
            return shouldSucceed;
          };
      addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

      await deliverReply('on my way');
      shouldSucceed = true;
      await deliverReply('on my way');
      await pumpEventQueue();

      expect(
        attempts,
        ['on my way', 'on my way'],
        reason: 'a failed send must not block the delivery that can succeed',
      );
    });

    test(
      'withholds acknowledgement until an inline reply actually sends',
      () async {
        // Acknowledging is what removes the platform's redelivery path, so a
        // send that failed and was acknowledged anyway dropped the reply in
        // silence: nothing reached the room, and nothing would try again.
        NotificationResponseHandler.resetInlineReplyDedupeForTest();
        final acknowledged = <String>[];
        var shouldSucceed = false;
        NotificationResponseHandler.inlineReplySenderForTest =
            (_, message) async => shouldSucceed;
        addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

        Future<void> deliver() =>
            NotificationResponseHandler.handleRemotePayload(
              {
                'response_id': 'unsent-reply-response',
                'action_id': richNotificationReplyActionId,
                'input': 'on my way',
                'room_id': '!reply:example.org',
                'client_id': '@user:example.org',
              },
              acknowledgeResponse: (responseId) async {
                acknowledged.add(responseId);
              },
            );

        await deliver();
        await pumpEventQueue();
        expect(
          acknowledged,
          isEmpty,
          reason: 'a failed send must keep its native redelivery path',
        );

        shouldSucceed = true;
        await deliver();
        await pumpEventQueue();
        expect(acknowledged, ['unsent-reply-response']);
      },
    );

    test('releases the claim when preparing the client throws, so the '
        'redelivery still sends', () async {
      // A cold launch runs the whole client restore inside this path. When it
      // threw, the outcome never became `failed`, so the dedupe claim stayed
      // held, the redelivery came back `duplicate`, and the response was
      // acknowledged with nothing sent.
      NotificationResponseHandler.resetInlineReplyDedupeForTest();
      final acknowledged = <String>[];
      var shouldThrow = true;
      final attempts = <String>[];
      NotificationResponseHandler.inlineReplySenderForTest =
          (_, message) async {
            attempts.add(message);
            if (shouldThrow) throw StateError('client not restored');
            return true;
          };
      addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

      Future<void> deliver() => NotificationResponseHandler.handleRemotePayload(
        {
          'response_id': 'throwing-reply-response',
          'action_id': richNotificationReplyActionId,
          'input': 'on my way',
          'room_id': '!reply:example.org',
          'client_id': '@user:example.org',
        },
        acknowledgeResponse: (responseId) async {
          acknowledged.add(responseId);
        },
      );

      await deliver();
      await pumpEventQueue();
      expect(acknowledged, isEmpty);

      shouldThrow = false;
      await deliver();
      await pumpEventQueue();

      expect(attempts.length, 2, reason: 'the claim must have been released');
      expect(acknowledged, ['throwing-reply-response']);
    });

    test('allows the SAME text again as a new notification response', () async {
      // The maintainer hit this on device 2026-08-14: replying "ok" twice from
      // two different notifications is legitimate, and the text-based key
      // suppressed the second. Keying on response identity fixes it - one
      // response redelivered is a duplicate, two responses are not.
      NotificationResponseHandler.resetInlineReplyDedupeForTest();
      final sent = <String>[];
      NotificationResponseHandler.inlineReplySenderForTest =
          (_, message) async {
            sent.add(message);
            return true;
          };
      addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

      Future<void> deliver(String responseId, String message) =>
          NotificationResponseHandler.handleRemotePayload({
            'response_id': responseId,
            'action_id': richNotificationReplyActionId,
            'input': message,
            'room_id': '!reply:example.org',
            'client_id': '@user:example.org',
          }, acknowledgeResponse: (_) async {});

      await deliver('response-a', 'ok');
      await deliver('response-b', 'ok');
      await pumpEventQueue();

      expect(sent, ['ok', 'ok'], reason: 'two responses are not a duplicate');
    });

    test('allows a different inline reply to the same room', () async {
      // Two replies are two notification responses. This test previously reused
      // one response_id for both messages, which was harmless under the old
      // text-based key and is wrong now: a single response carries a single
      // input, so same-id-different-text does not occur in reality.
      NotificationResponseHandler.resetInlineReplyDedupeForTest();
      final sent = <String>[];
      NotificationResponseHandler.inlineReplySenderForTest =
          (_, message) async {
            sent.add(message);
            return true;
          };
      addTearDown(NotificationResponseHandler.resetInlineReplyDedupeForTest);

      Future<void> deliver(String responseId, String message) =>
          NotificationResponseHandler.handleRemotePayload({
            'response_id': responseId,
            'action_id': richNotificationReplyActionId,
            'input': message,
            'room_id': '!reply:example.org',
            'client_id': '@user:example.org',
          }, acknowledgeResponse: (_) async {});

      await deliver('response-first', 'first');
      await deliver('response-second', 'second');
      await pumpEventQueue();

      expect(sent, ['first', 'second']);
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

          final route = events.isEmpty
              ? EventBus.takePendingOpenRoom()
              : events.single;
          expect(route?.$1, '!data:example.org');
          expect(route?.$2, '@data:example.org');
        } finally {
          await subscription.cancel();
          while (EventBus.takePendingOpenRoom() != null) {}
        }
      },
    );

    test(
      'keeps iOS responses pending until room navigation succeeds',
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

        NotificationResponseHandler.markNavigationSucceededForTesting((
          '!pending:example.org',
          '@pending:example.org',
        ));
        await pumpEventQueue();

        expect(acknowledgedResponseIds, ['ios-response-1']);
        expect(NotificationResponseHandler.pendingNavigationCountForTesting, 0);
        while (EventBus.takePendingOpenRoom() != null) {}
        NotificationResponseHandler.resetForTesting();
      },
    );

    test(
      'keeps iOS story responses pending until story navigation succeeds',
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
      },
    );

    test(
      'acknowledges iOS story responses after fallback room navigation',
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

        NotificationResponseHandler.markNavigationSucceededForTesting((
          '!story-fallback:example.org',
          '@story-client:example.org',
        ));
        await pumpEventQueue();

        expect(acknowledgedResponseIds, ['ios-story-fallback-response-1']);
        expect(
          NotificationResponseHandler.pendingStoryNavigationCountForTesting,
          0,
        );
        while (EventBus.takePendingOpenStory() != null) {}
        NotificationResponseHandler.resetForTesting();
      },
    );

    test(
      'acknowledges terminal iOS responses that have no room route',
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
      },
    );

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
