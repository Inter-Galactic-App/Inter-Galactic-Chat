import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/hide_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NotificationModifierHideContent', () {
    test('redacts message preview fields while preserving routing metadata',
        () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final content = MessageNotificationContent(
        senderName: 'Nova',
        senderId: '@nova:test',
        roomName: 'Bridge',
        content: 'Launch codes',
        eventId: r'$event',
        roomId: '!room:test',
        clientId: 'client-a',
        isDirectMessage: false,
        formattedContent: '<b>Launch codes</b>',
        formatType: 'org.matrix.custom.html',
        roomImage: image,
        roomImageId: 'room-image',
        senderImage: image,
        senderImageId: 'sender-image',
        attachedImage: image,
      );

      final result = await NotificationModifierHideContent().process(content);

      expect(result, same(content));
      expect(content.title,
          NotificationModifierHideContent.genericNotificationTitle);
      expect(content.content, 'Sent a message');
      expect(content.roomName, NotificationModifierHideContent.genericRoomName);
      expect(content.senderId, '@nova:test');
      expect(content.eventId, r'$event');
      expect(content.roomId, '!room:test');
      expect(content.clientId, 'client-a');
      expect(content.formattedContent, isNull);
      expect(content.formatType, isNull);
      expect(content.roomImage, isNull);
      expect(content.roomImageId, isNull);
      expect(content.senderImage, isNull);
      expect(content.senderImageId, isNull);
      expect(content.attachedImage, isNull);
    });

    test('redacts story previews while preserving story routing metadata',
        () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final content = StoryNotificationContent(
        roomId: '!room:test',
        clientId: 'client-a',
        roomName: 'Bridge',
        senderId: '@nova:test',
        senderName: 'Nova',
        eventId: r'$event',
        storySenderId: '@nova:test',
        storyId: 'story-1',
        storyEventId: r'$story',
        playSound: true,
        title: 'Nova posted a story',
        content: 'Tap to view',
        senderImage: image,
        senderImageId: 'sender-image',
      );

      final result = await NotificationModifierHideContent().process(content);

      expect(result, same(content));
      expect(content.title,
          NotificationModifierHideContent.genericNotificationTitle);
      expect(content.content, NotificationModifierHideContent.genericStoryBody);
      expect(content.roomName, NotificationModifierHideContent.genericRoomName);
      expect(content.senderName,
          NotificationModifierHideContent.genericNotificationTitle);
      expect(content.roomId, '!room:test');
      expect(content.clientId, 'client-a');
      expect(content.storySenderId, '@nova:test');
      expect(content.storyId, 'story-1');
      expect(content.storyEventId, r'$story');
      expect(content.senderImage, isNull);
      expect(content.senderImageId, isNull);
    });

    test('redacts membership previews while preserving room routing metadata',
        () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final content = RoomMembershipNotificationContent(
        roomId: '!room:test',
        clientId: 'client-a',
        roomName: 'Bridge',
        senderId: '@nova:test',
        senderName: 'Nova',
        eventId: r'$knock',
        title: 'Join request',
        content: 'Nova requested to join Bridge',
        senderImage: image,
        senderImageId: 'sender-image',
      );

      final result = await NotificationModifierHideContent().process(content);

      expect(result, same(content));
      expect(content.title,
          NotificationModifierHideContent.genericNotificationTitle);
      expect(content.content,
          NotificationModifierHideContent.genericMembershipBody);
      expect(content.roomName, NotificationModifierHideContent.genericRoomName);
      expect(content.senderName,
          NotificationModifierHideContent.genericNotificationTitle);
      expect(content.senderId, '@nova:test');
      expect(content.eventId, r'$knock');
      expect(content.roomId, '!room:test');
      expect(content.clientId, 'client-a');
      expect(content.senderImage, isNull);
      expect(content.senderImageId, isNull);
    });

    test('leaves rich-preview installs unchanged', () async {
      SharedPreferences.setMockInitialValues({
        Preferences.registeredMatrixClients: <String>['client-a'],
      });
      await globals.preferences.init();

      final content = MessageNotificationContent(
        senderName: 'Nova',
        senderId: '@nova:test',
        roomName: 'Bridge',
        content: 'Launch codes',
        eventId: r'$event',
        roomId: '!room:test',
        clientId: 'client-a',
        isDirectMessage: true,
        formattedContent: '<b>Launch codes</b>',
        formatType: 'org.matrix.custom.html',
      );

      final result = await NotificationModifierHideContent().process(content);

      expect(result, same(content));
      expect(content.title, 'Nova');
      expect(content.content, 'Launch codes');
      expect(content.roomName, 'Bridge');
      expect(content.formattedContent, '<b>Launch codes</b>');
      expect(content.formatType, 'org.matrix.custom.html');
    });
  });
}
