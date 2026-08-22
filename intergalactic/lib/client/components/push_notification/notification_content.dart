import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:intergalactic/client/timeline_events/photo_stack_grouping.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum NotificationPriority { normal, low }

enum NotificationAttachmentType { image, video, file, gif, sticker }

class NotificationAttachmentPresentation {
  const NotificationAttachmentPresentation({
    required this.type,
    this.caption,
    this.preview,
  });

  final NotificationAttachmentType type;
  final String? caption;
  final ImageProvider? preview;

  /// The label a notification shows in place of the message body.
  ///
  /// Routed through `Intl.message` for the same reason
  /// `NotificationModifierHideContent` is: this becomes the notification body,
  /// the ticker and the MessagingStyle text, and it was the only notification
  /// text that stayed English in every locale.
  String get typeLabel => switch (type) {
    NotificationAttachmentType.image => Intl.message(
      'Sent an image',
      name: 'notificationAttachmentSentImage',
      desc: 'Notification body for a message whose content is an image.',
    ),
    NotificationAttachmentType.video => Intl.message(
      'Sent a video',
      name: 'notificationAttachmentSentVideo',
      desc: 'Notification body for a message whose content is a video.',
    ),
    NotificationAttachmentType.file => Intl.message(
      'Sent a file',
      name: 'notificationAttachmentSentFile',
      desc: 'Notification body for a message whose content is a file.',
    ),
    NotificationAttachmentType.gif => Intl.message(
      'Sent a GIF',
      name: 'notificationAttachmentSentGif',
      desc: 'Notification body for a message whose content is an animated GIF.',
    ),
    NotificationAttachmentType.sticker => Intl.message(
      'Sent a sticker',
      name: 'notificationAttachmentSentSticker',
      desc: 'Notification body for a message whose content is a sticker.',
    ),
  };

  String get displayText =>
      caption == null ? typeLabel : '$typeLabel\n$caption';

  static NotificationAttachmentPresentation? fromAttachments(
    List<Attachment>? attachments, {
    String? body,
  }) {
    if (attachments == null || attachments.isEmpty) return null;

    final attachment = attachments.first;
    final type = _typeFor(attachment);
    final caption = _captionFor(body, attachment.name);
    return NotificationAttachmentPresentation(
      type: type,
      caption: caption,
      preview: switch (attachment) {
        ImageAttachment(:final image) => image,
        VideoAttachment(:final thumbnail) => thumbnail,
        _ => null,
      },
    );
  }

  static NotificationAttachmentType _typeFor(Attachment attachment) {
    if (_isGif(attachment)) return NotificationAttachmentType.gif;
    return switch (attachment) {
      ImageAttachment() => NotificationAttachmentType.image,
      VideoAttachment() => NotificationAttachmentType.video,
      _ => NotificationAttachmentType.file,
    };
  }

  factory NotificationAttachmentPresentation.fromSticker({
    required ImageProvider preview,
    required bool isAnimated,
  }) {
    return NotificationAttachmentPresentation(
      type: isAnimated
          ? NotificationAttachmentType.gif
          : NotificationAttachmentType.sticker,
      preview: preview,
    );
  }

  static bool _isGif(Attachment attachment) {
    if (attachment is! FileAttachment) return false;
    return attachment.mimeType?.toLowerCase() == 'image/gif' ||
        attachment.name.toLowerCase().endsWith('.gif');
  }

  static String? _captionFor(String? body, String attachmentName) {
    final caption = body?.trim();
    // No empty-string check here on purpose: `looksLikeGeneratedImageBody`
    // already answers true for a null or blank body, so an added `isEmpty`
    // guard would be unreachable and would imply this path is exposed when it
    // is not. The test 'treats a whitespace-only body as no caption at all'
    // holds that invariant where it can actually fail.
    if (caption == null ||
        PhotoStackGrouping.looksLikeGeneratedImageBody(body, attachmentName)) {
      return null;
    }
    return caption;
  }
}

class NotificationContent {
  String title;
  String content;
  NotificationPriority priority;

  NotificationContent({
    required this.title,
    required this.content,
    this.priority = NotificationPriority.normal,
  });
}

class ErrorNotificationContent extends NotificationContent {
  ErrorNotificationContent({required super.title, required super.content});
}

class GenericRoomInviteNotificationContent extends NotificationContent {
  GenericRoomInviteNotificationContent({
    required super.title,
    required super.content,
  });
}

class RoomMembershipNotificationContent extends NotificationContent {
  String roomId;
  String clientId;
  String roomName;
  String senderId;
  String senderName;
  String eventId;
  ImageProvider? senderImage;
  String? senderImageId;

  RoomMembershipNotificationContent({
    required this.roomId,
    required this.clientId,
    required this.roomName,
    required this.senderId,
    required this.senderName,
    required this.eventId,
    required super.title,
    required super.content,
    this.senderImage,
    this.senderImageId,
  });

  static Future<RoomMembershipNotificationContent?> fromKnockEvent(
    MatrixTimelineEventMembership event,
    Room room,
  ) async {
    if (!event.isKnockEvent) {
      return null;
    }

    final user = await room.fetchMember(event.senderId);
    return RoomMembershipNotificationContent(
      roomId: room.identifier,
      clientId: room.client.identifier,
      roomName: room.displayName,
      senderId: user.identifier,
      senderName: user.displayName,
      eventId: event.eventId,
      title: 'Join request',
      content: '${user.displayName} requested to join ${room.displayName}',
      senderImage: user.avatar,
      senderImageId: user.avatarId,
    );
  }
}

class MessageNotificationContent extends NotificationContent {
  String get senderName => title;
  String senderId;
  String eventId;
  String roomId;
  String clientId;
  String roomName;
  String? formattedContent;
  String? formatType;
  bool isDirectMessage;
  ImageProvider? roomImage;
  String? roomImageId;
  ImageProvider? senderImage;
  String? senderImageId;
  ImageProvider? attachedImage;
  NotificationAttachmentPresentation? attachmentPresentation;
  bool allowsRichActions;

  /// True when this is a bare image upload that the timeline would fold into a
  /// photo stack, so a burst of them raises one notification instead of one per
  /// photo. See [PhotoStackGrouping].
  bool isStackablePhoto;

  MessageNotificationContent({
    required String senderName,
    required this.senderId,
    required this.roomName,
    required super.content,
    required this.eventId,
    required this.roomId,
    required this.clientId,
    required this.isDirectMessage,
    this.formattedContent,
    this.formatType,
    this.roomImage,
    this.roomImageId,
    this.senderImage,
    this.senderImageId,
    this.attachedImage,
    this.attachmentPresentation,
    this.allowsRichActions = true,
    this.isStackablePhoto = false,
  }) : super(title: senderName);

  static Future<MessageNotificationContent?> fromEvent(
    TimelineEvent msg,
    Room room,
  ) async {
    var user = await room.fetchMember(msg.senderId);

    if (msg is TimelineEventMessage) {
      final attachmentPresentation =
          NotificationAttachmentPresentation.fromAttachments(
            msg.attachments,
            body: msg.body,
          );
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        // `MatrixBackgroundTimelineEventMessage.body` is the raw event
        // content map. Legacy notification consumers need the normalized text
        // body instead; attachment presentation above still uses the parsed
        // TimelineEventMessage body when attachments are available.
        // With an attachment, the plain body IS the filename, so the four
        // notifiers that read `content` directly - macOS, Linux, Windows, web -
        // showed "photo_2024.jpg" where Android and iOS showed "Sent an
        // image". Resolving it here fixes all four at once and leaves their
        // `?? content.content` fallbacks correct.
        content: attachmentPresentation?.displayText ?? msg.plainTextBody,
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage: attachmentPresentation?.preview,
        attachmentPresentation: attachmentPresentation,
        isStackablePhoto: PhotoStackGrouping.isStackable(msg),
        formatType: attachmentPresentation == null ? msg.bodyFormat : null,
        formattedContent: attachmentPresentation == null
            ? msg.formattedBody
            : null,
        isDirectMessage:
            room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    if (msg is TimelineEventSticker) {
      final animatedSticker = msg is TimelineEventAnimatedSticker
          ? msg as TimelineEventAnimatedSticker
          : null;
      final attachmentPresentation =
          NotificationAttachmentPresentation.fromSticker(
            preview: msg.stickerImage,
            isAnimated: animatedSticker?.isAnimatedSticker ?? false,
          );
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: attachmentPresentation.displayText,
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage: attachmentPresentation.preview,
        attachmentPresentation: attachmentPresentation,
        formattedContent: "",
        formatType: "chat.commet.custom.matrix_plain",
        isDirectMessage:
            room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    return null;
  }
}

class StoryNotificationContent extends NotificationContent {
  String roomId;
  String clientId;
  String roomName;
  String senderId;
  String senderName;
  String eventId;
  String storySenderId;
  String storyId;
  String? storyEventId;
  bool playSound;
  ImageProvider? senderImage;
  String? senderImageId;

  StoryNotificationContent({
    required this.roomId,
    required this.clientId,
    required this.roomName,
    required this.senderId,
    required this.senderName,
    required this.eventId,
    required this.storySenderId,
    required this.storyId,
    this.storyEventId,
    required this.playSound,
    required super.title,
    required super.content,
    this.senderImage,
    this.senderImageId,
  });
}

class CallNotificationContent extends NotificationContent {
  String roomId;
  String senderId;
  String senderName;
  String roomName;
  String clientId;
  String callId;

  bool isDirectMessage;

  ImageProvider? roomImage;
  String? roomImageId;

  ImageProvider? senderImage;
  String? senderImageId;

  CallNotificationContent({
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.roomName,
    required this.clientId,
    required this.callId,
    required this.isDirectMessage,
    this.senderImage,
    this.senderImageId,
    required super.title,
    required super.content,
    this.roomImage,
    this.roomImageId,
  });
}

class CalendarReminderNotificationContent extends NotificationContent {
  String roomId;
  String clientId;
  String roomName;
  String eventUid;
  DateTime eventStart;
  int minutesBefore;

  ImageProvider? roomImage;
  String? roomImageId;

  CalendarReminderNotificationContent({
    required this.roomId,
    required this.clientId,
    required this.roomName,
    required this.eventUid,
    required this.eventStart,
    required this.minutesBefore,
    required super.title,
    required super.content,
    this.roomImage,
    this.roomImageId,
  });
}
