import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/android/android_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';

void main() {
  test('Android rich Reply opens the app to deliver its RemoteInput', () {
    final action = androidRichNotificationReplyAction(
      actionId: richNotificationReplyActionId,
    );

    expect(action.id, richNotificationReplyActionId);
    expect(action.title, 'Reply');
    expect(action.showsUserInterface, isTrue);
    expect(action.semanticAction, SemanticAction.reply);
    expect(action.allowGeneratedReplies, isTrue);
    expect(action.inputs, hasLength(1));
  });

  test('Android uses one foreground Mute action for the duration picker', () {
    final actions = androidRoomNotificationSnoozeActions();

    expect(actions, hasLength(1));
    final action = actions.single;
    expect(action.id, roomNotificationSnoozePickerActionId);
    expect(action.title, 'Mute');
    expect(action.showsUserInterface, isTrue);
    expect(action.semanticAction, SemanticAction.mute);
  });

  test('Android stages image, GIF, and sticker notification previews', () {
    expect(
      androidNotificationAttachmentSupportsPreview(
        NotificationAttachmentType.image,
      ),
      isTrue,
    );
    expect(
      androidNotificationAttachmentSupportsPreview(
        NotificationAttachmentType.gif,
      ),
      isTrue,
    );
    expect(
      androidNotificationAttachmentSupportsPreview(
        NotificationAttachmentType.sticker,
      ),
      isTrue,
    );
    expect(
      androidNotificationAttachmentSupportsPreview(
        NotificationAttachmentType.video,
      ),
      isFalse,
    );
    expect(
      androidNotificationAttachmentSupportsPreview(
        NotificationAttachmentType.file,
      ),
      isFalse,
    );
  });

  test('Android media previews honour the independent image toggle', () {
    expect(
      androidNotificationAllowsMediaPreview(
        usePrivatePreviews: false,
        showMediaInNotifications: true,
      ),
      isTrue,
    );
    expect(
      androidNotificationAllowsMediaPreview(
        usePrivatePreviews: false,
        showMediaInNotifications: false,
      ),
      isFalse,
    );
    expect(
      androidNotificationAllowsMediaPreview(
        usePrivatePreviews: true,
        showMediaInNotifications: true,
      ),
      isFalse,
    );
  });

  test('retained messages keep their history without the media', () {
    // Turning "Show images" off used to drop the whole retained
    // MessagingStyle, so the notification shade lost the conversation and the
    // count reset to 1 - a preference about images silently became one about
    // message history. The history is kept and only the staged image goes.
    final person = Person(name: 'Alice', key: '@alice:example.org');
    final retained = [
      Message(
        'the first one',
        DateTime.utc(2026, 9, 7, 10),
        person,
        dataMimeType: 'image/png',
        dataUri: 'file:///cache/notification-preview.png',
      ),
      Message('the second one', DateTime.utc(2026, 9, 7, 10, 1), person),
    ];

    final sanitized = androidNotificationMessagesWithoutMedia(retained);

    expect(
      sanitized.map((m) => m.text),
      ['the first one', 'the second one'],
      reason: 'the retained conversation is what the shade shows as history',
    );
    final timestamps = sanitized.map((m) => m.timestamp).toList();
    expect(timestamps.first, DateTime.utc(2026, 9, 7, 10));
    expect(timestamps.last, DateTime.utc(2026, 9, 7, 10, 1));
    expect(sanitized.every((m) => m.person == person), isTrue);
    expect(
      sanitized.every((m) => m.dataUri == null && m.dataMimeType == null),
      isTrue,
      reason: 'an image staged before the preference changed must not persist',
    );
  });
}
