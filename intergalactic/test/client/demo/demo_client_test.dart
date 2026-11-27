import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';

void main() {
  group('DemoClient', () {
    late DemoClient client;

    setUp(() {
      client = DemoClient.createOfflineDemo();
    });

    tearDown(() async {
      await client.close();
    });

    test('seeds desktop-safe room emoticons for message input', () {
      final lounge = client.getRoom('!demo-lounge:intergalactic.local')!;
      final emoticons = lounge.getComponent<RoomEmoticonComponent>();

      expect(emoticons, isNotNull);
      expect(
        emoticons!.availableEmoji.map((pack) => pack.displayName),
        contains('Galaxy Emoji'),
      );
      expect(
        emoticons.availableStickers.map((pack) => pack.displayName),
        contains('Cosmic Cats'),
      );
    });

    test('seeds example direct messages', () async {
      final directMessages =
          client.getComponent<DirectMessagesComponent<DemoClient>>()!;

      expect(directMessages.directMessageRooms, hasLength(3));
      expect(
        directMessages.directMessageRooms.map((room) => room.displayName),
        containsAll(['Mira', 'Theo', 'Nova']),
      );

      for (final room in directMessages.directMessageRooms) {
        expect(directMessages.isRoomDirectMessage(room), isTrue);
        expect(directMessages.getDirectMessagePartnerId(room), isNotNull);

        final timeline = await room.getTimeline();
        expect(timeline.events.whereType<TimelineEventMessage>(), isNotEmpty);
      }
    });

    test('removes left rooms from direct message cache', () async {
      final directMessages =
          client.getComponent<DirectMessagesComponent<DemoClient>>()!;
      final room = directMessages.directMessageRooms.first;

      await client.leaveRoom(room);

      expect(directMessages.directMessageRooms, isNot(contains(room)));
      expect(directMessages.isRoomDirectMessage(room), isFalse);
      expect(directMessages.getDirectMessagePartnerId(room), isNull);
    });

    test('keeps forum post thread timelines available', () async {
      final forum = client.getRoom('!demo-forum:intergalactic.local')!;
      final forumComponent = forum.getComponent<ForumRoomComponent>()!;
      final threads = client.getComponent<ThreadsComponent<DemoClient>>()!;
      final roomTimeline = await forum.getTimeline();

      for (final post in forumComponent.posts) {
        final threadTimeline = await threads.getThreadTimeline(
          roomTimeline: roomTimeline,
          threadRootEventId: post.eventId,
        );

        expect(threadTimeline, isNotNull);
        expect(
          threadTimeline!.events.whereType<TimelineEventMessage>(),
          isNotEmpty,
        );
      }
    });

    test('created one-to-one rooms are treated as direct messages', () async {
      final directMessages =
          client.getComponent<DirectMessagesComponent<DemoClient>>()!;

      final room = await directMessages.createDirectMessage(
        '@guide:intergalactic.local',
      );

      expect(room, isA<Room>());
      expect(directMessages.isRoomDirectMessage(room!), isTrue);
      expect(
        directMessages.getDirectMessagePartnerId(room),
        '@guide:intergalactic.local',
      );
    });
  });
}
