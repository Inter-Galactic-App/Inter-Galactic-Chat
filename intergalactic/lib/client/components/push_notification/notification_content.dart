import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:flutter/material.dart';

enum NotificationPriority { normal, low }

class NotificationContent {
  String title;
  String content;
  NotificationPriority priority;

  NotificationContent(
      {required this.title,
      required this.content,
      this.priority = NotificationPriority.normal});
}

class ErrorNotificationContent extends NotificationContent {
  ErrorNotificationContent({required super.title, required super.content});
}

class GenericRoomInviteNotificationContent extends NotificationContent {
  GenericRoomInviteNotificationContent(
      {required super.title, required super.content});
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
  }) : super(title: senderName);

  static Future<MessageNotificationContent?> fromEvent(
      TimelineEvent msg, Room room) async {
    var user = await room.fetchMember(msg.senderId);

    if (msg is TimelineEventMessage) {
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.body ?? "Sent a message",
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage:
            msg.attachments?.whereType<ImageAttachment>().firstOrNull?.image ??
                msg.attachments
                    ?.whereType<VideoAttachment>()
                    .firstOrNull
                    ?.thumbnail,
        formatType: msg.bodyFormat,
        formattedContent: msg.formattedBody,
        isDirectMessage: room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    if (msg is TimelineEventSticker) {
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.stickerName,
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage: msg.stickerImage,
        formattedContent: "",
        formatType: "chat.commet.custom.matrix_plain",
        isDirectMessage: room.client
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
