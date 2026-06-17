import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/utils/custom_uri.dart';

void main() {
  group('NotificationIdentity story notifications', () {
    test('uses the same room key as other room-routed notifications', () {
      final notification = _storyContent(
        clientId: 'client-a',
        roomId: '!room:example.org',
      );

      expect(
        NotificationIdentity.roomKeyForStory(notification),
        'client-a::!room:example.org',
      );
    });

    test('derives stable story ids from client room and event', () {
      final notification = _storyContent(
        clientId: 'client-a',
        roomId: '!room:example.org',
        eventId: r'$story-a',
      );
      final sameNotification = _storyContent(
        clientId: 'client-a',
        roomId: '!room:example.org',
        eventId: r'$story-a',
      );
      final otherEvent = _storyContent(
        clientId: 'client-a',
        roomId: '!room:example.org',
        eventId: r'$story-b',
      );
      final otherClient = _storyContent(
        clientId: 'client-b',
        roomId: '!room:example.org',
        eventId: r'$story-a',
      );

      expect(
        NotificationIdentity.storyNotificationId(notification),
        NotificationIdentity.storyNotificationId(sameNotification),
      );
      expect(
        NotificationIdentity.storyNotificationId(notification),
        isNot(NotificationIdentity.storyNotificationId(otherEvent)),
      );
      expect(
        NotificationIdentity.storyNotificationId(notification),
        isNot(NotificationIdentity.storyNotificationId(otherClient)),
      );
    });

    test('matches open-story payloads against their room route', () {
      final payload = OpenStoryURI(
        roomId: '!room:example.org',
        clientId: 'client-a',
        storySenderId: '@alice:example.org',
        storyId: 'story-1',
        storyEventId: r'$story',
      ).toString();

      expect(
        NotificationIdentity.matchesPayloadRoute(
          payload,
          clientId: 'client-a',
          roomId: '!room:example.org',
        ),
        isTrue,
      );
      expect(
        NotificationIdentity.matchesPayloadRoute(
          payload,
          clientId: 'client-a',
          roomId: '!different:example.org',
        ),
        isFalse,
      );
    });
  });
}

StoryNotificationContent _storyContent({
  String clientId = 'client-a',
  String roomId = '!room:example.org',
  String eventId = r'$story',
}) {
  return StoryNotificationContent(
    roomId: roomId,
    clientId: clientId,
    roomName: 'Story DM',
    senderId: '@alice:example.org',
    senderName: 'Alice',
    eventId: eventId,
    storySenderId: '@alice:example.org',
    storyId: 'story-1',
    storyEventId: eventId,
    playSound: true,
    title: 'Alice',
    content: 'Posted a story',
  );
}
