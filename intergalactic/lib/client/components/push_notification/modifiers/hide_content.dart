import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/main.dart';
import 'package:intl/intl.dart';

class NotificationModifierHideContent implements NotificationModifier {
  static const String genericNotificationTitle = "Inter Galactic";
  static const String genericRoomName = "Chat";
  static const String genericStoryBody = "New story";

  String get notificationModifiersPrivacyEnhanced => Intl.message(
      "Sent a message",
      name: "notificationModifiersPrivacyEnhanced",
      desc:
          "Placeholder text to put in a notification when the user has privacy enhanced notifications enabled.");

  @override
  Future<NotificationContent?> process(NotificationContent content) async {
    if (!preferences.usePrivateNotificationPreviews) {
      return content;
    }

    if (content is MessageNotificationContent) {
      content.title = genericNotificationTitle;
      content.roomName = genericRoomName;
      content.content = notificationModifiersPrivacyEnhanced;
      content.formattedContent = null;
      content.formatType = null;
      content.roomImage = null;
      content.roomImageId = null;
      content.senderImage = null;
      content.senderImageId = null;
      content.attachedImage = null;
    } else if (content is StoryNotificationContent) {
      content.title = genericNotificationTitle;
      content.roomName = genericRoomName;
      content.senderName = genericNotificationTitle;
      content.content = genericStoryBody;
      content.senderImage = null;
      content.senderImageId = null;
    }

    return content;
  }
}
