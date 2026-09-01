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
}
