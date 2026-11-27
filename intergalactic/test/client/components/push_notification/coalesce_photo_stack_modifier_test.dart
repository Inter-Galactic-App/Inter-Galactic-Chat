import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/coalesce_photo_stack.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';

void main() {
  group('NotificationModifierCoalescePhotoStack', () {
    late DateTime now;
    late NotificationModifierCoalescePhotoStack modifier;

    setUp(() {
      now = DateTime.utc(2026, 7, 24, 12);
      modifier = NotificationModifierCoalescePhotoStack(clock: () => now);
    });

    test('shows the first photo of a stack and drops the rest', () async {
      final first = await modifier.process(_photo(eventId: '\$one'));
      expect(first, isNotNull);

      for (var index = 1; index < 5; index++) {
        now = now.add(const Duration(seconds: 3));
        expect(
          await modifier.process(_photo(eventId: '\$photo$index')),
          isNull,
          reason: 'photo $index should fold into the open stack',
        );
      }
    });

    test('keeps notifying for photos that are far apart', () async {
      expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

      now = now.add(const Duration(minutes: 5));

      expect(await modifier.process(_photo(eventId: '\$two')), isNotNull);
    });

    test(
      'starts a new stack once the burst outruns the maximum span',
      () async {
        expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

        // Each photo lands inside the rolling window, so only the total span
        // ends the stack.
        var eventId = 1;
        var suppressed = 0;
        while (now.difference(DateTime.utc(2026, 7, 24, 12)) <
            const Duration(minutes: 10)) {
          now = now.add(const Duration(minutes: 1));
          eventId++;
          if (await modifier.process(_photo(eventId: '\$photo$eventId')) ==
              null) {
            suppressed++;
          }
        }

        expect(suppressed, greaterThan(1));

        now = now.add(const Duration(minutes: 1));
        expect(
          await modifier.process(_photo(eventId: '\$after')),
          isNotNull,
          reason: 'the span cap should let a long trickle notify again',
        );
      },
    );

    test('does not fold a different sender into an open stack', () async {
      expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

      now = now.add(const Duration(seconds: 2));

      expect(
        await modifier.process(
          _photo(eventId: '\$two', senderId: '@carol:example.org'),
        ),
        isNotNull,
      );
    });

    test(
      'does not fold photos from a different room into an open stack',
      () async {
        expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

        now = now.add(const Duration(seconds: 2));

        expect(
          await modifier.process(
            _photo(eventId: '\$two', roomId: '!other:example.org'),
          ),
          isNotNull,
        );
      },
    );

    test('leaves captioned images and text messages alone', () async {
      final text = _photo(eventId: '\$one', isStackablePhoto: false);

      expect(await modifier.process(text), same(text));

      now = now.add(const Duration(seconds: 2));

      final alsoText = _photo(eventId: '\$two', isStackablePhoto: false);
      expect(await modifier.process(alsoText), same(alsoText));
    });

    test('a message between photos ends the stack', () async {
      expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

      now = now.add(const Duration(seconds: 2));
      await modifier.process(_photo(eventId: '\$two', isStackablePhoto: false));

      now = now.add(const Duration(seconds: 2));
      expect(
        await modifier.process(_photo(eventId: '\$three')),
        isNotNull,
        reason: 'the run of photos was broken, so this starts a new stack',
      );
    });

    test('re-suppresses a photo that is delivered twice', () async {
      expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

      now = now.add(const Duration(seconds: 2));
      expect(await modifier.process(_photo(eventId: '\$two')), isNull);

      // Same event again, past the rolling window.
      now = now.add(const Duration(minutes: 5));
      expect(await modifier.process(_photo(eventId: '\$two')), isNull);
    });

    test('reset lets the room notify again after it has been read', () async {
      expect(await modifier.process(_photo(eventId: '\$one')), isNotNull);

      now = now.add(const Duration(seconds: 2));
      expect(await modifier.process(_photo(eventId: '\$two')), isNull);

      modifier.reset(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
      );

      now = now.add(const Duration(seconds: 2));
      expect(await modifier.process(_photo(eventId: '\$three')), isNotNull);
    });

    test('passes through notifications that are not messages', () async {
      final content = ErrorNotificationContent(
        title: 'Error',
        content: 'Something went wrong',
      );

      expect(await modifier.process(content), same(content));
    });

    test('does not track more rooms than its limit', () async {
      for (
        var index = 0;
        index < NotificationModifierCoalescePhotoStack.maxTrackedRooms + 10;
        index++
      ) {
        await modifier.process(
          _photo(eventId: '\$event$index', roomId: '!room$index:example.org'),
        );
      }

      // The first room was evicted, so its next photo notifies instead of being
      // folded into a stack nobody can see any more.
      expect(
        await modifier.process(
          _photo(eventId: '\$late', roomId: '!room0:example.org'),
        ),
        isNotNull,
      );
    });
  });
}

MessageNotificationContent _photo({
  required String eventId,
  String senderId = '@bob:example.org',
  String roomId = '!room:example.org',
  bool isStackablePhoto = true,
}) {
  return MessageNotificationContent(
    senderName: 'Bob',
    senderId: senderId,
    roomName: 'Room',
    content: 'IMG_0001.jpeg',
    eventId: eventId,
    roomId: roomId,
    clientId: '@alice:example.org',
    isDirectMessage: false,
    isStackablePhoto: isStackablePhoto,
  );
}
