import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/client/components/push_notification/notification_companion_controller.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/app_icon/app_icon_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/shortcuts_manager.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win_toast/win_toast.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

class WindowsNotifier implements Notifier {
  @override
  bool get hasPermission => true;

  @override
  bool get enabled => true;

  @override
  bool get needsToken => false;

  static NotificationsClient client = NotificationsClient();

  static String xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  @override
  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    var file = p.join(
      dir.path,
      BuildConfig.windowsTempNamespace,
      "intergalactic_app_icon.png",
    );

    ByteData data =
        await rootBundle.load(AppIconUtils.transparentCroppedAssetPath());

    var imageFile = File(file);
    imageFile.createSync(recursive: true);
    imageFile.writeAsBytes(data.buffer.asInt8List());
    var uri = Uri.file(file, windows: true);

    await WinToast.instance().initialize(
      aumId: BuildConfig.windowsAumId,
      displayName: BuildConfig.app,
      iconPath: uri.toString(),
      clsid: BuildConfig.windowsToastClsid,
    );

    WinToast.instance().setActivatedCallback(onActivated);
    WinToast.instance().setDismissedCallback(onDismissed);
  }

  static void onActivated(ActivatedEvent event) {
    var text = Uri.decodeQueryComponent(event.argument);
    var args = Uri.splitQueryString(text);

    switch (args['action']) {
      case 'reply':
        var clientId = args['client_id'];
        var roomId = args['room_id'];
        var eventId = args['event_id'];
        var message = event.userInput['reply'];

        if (clientId == null) return;
        if (roomId == null) return;
        if (eventId == null) return;
        if (message == null) return;

        var client = clientManager!.getClient(clientId);

        if (client == null) return;

        if (message.trim().isNotEmpty) {
          client.getRoom(roomId)?.sendMessage(message: message.trim());
        }

        break;
      case 'open_room':
        var roomId = args['room_id'];
        if (roomId == null) return;

        EventBus.openRoom.add((roomId, null));
        windowManager.show();
        break;
      case 'open_story':
        final roomId = args['room_id'];
        final clientId = args['client_id'];
        final storySenderId = args['story_sender_id'];
        final storyId = args['story_id'];
        if (roomId == null ||
            clientId == null ||
            storySenderId == null ||
            storyId == null) {
          return;
        }

        EventBus.openStoryFromNotification(
          StoryOpenRequest(
            roomId: roomId,
            clientId: clientId,
            storySenderId: storySenderId,
            storyId: storyId,
            storyEventId: args['story_event_id'],
          ),
        );
        windowManager.show();
        break;
      case 'accept_call':
      case 'reject_call':
        final callId = args['call_id'];
        final clientId = args['client_id'];
        final session = clientManager?.callManager.currentSessions
            .where(
                (e) => e.sessionId == callId && e.client.identifier == clientId)
            .firstOrNull;

        if (args['action'] == "reject_call") {
          session?.declineCall();
        }

        if (args['action'] == "accept_call") {
          session?.acceptCall(withMicrophone: true);
        }

        break;
    }
  }

  static void onDismissed(DismissedEvent event) {
    Log.d("Notification dismissed");
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case StoryNotificationContent _:
        return displayStoryNotificationContent(notification);
      case RoomMembershipNotificationContent _:
        return displayRoomMembershipNotification(notification);
      case CallNotificationContent _:
        return displayCallNotificationContent(notification);
      case CalendarReminderNotificationContent _:
        return displayCalendarReminderNotification(notification);
    }
  }

  Future<void> displayCallNotificationContent(
      CallNotificationContent content) async {
    String? avatarFilePath;

    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.roomName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    avatarFilePath = avatar == null ? "" : avatar.toFilePath();

    // ignore: prefer_function_declarations_over_variables
    var f = (String string) => Uri.encodeComponent(string);

    final title = xmlEscape(content.roomName);
    final body = xmlEscape(content.content);
    final roomName = xmlEscape(content.roomName);
    final avatarPath = xmlEscape(avatarFilePath);

    var defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}";

    var header = '''<header
        id="${f(content.roomId)}"
        title="$roomName"
        arguments="$defaultAction"/>''';

    if (content.isDirectMessage) {
      header = "";
    }

    var xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   $header
   <visual>
      <binding template="ToastGeneric">
         <text>$title</text>
         <text>$body</text>
         <image placement='appLogoOverride' src='$avatarPath' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
   <actions>
      <action content="${CommonStrings.promptAccept}" activationType="background" arguments="action=accept_call&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}" />
      <action content="${CommonStrings.promptReject}" activationType="background" arguments="action=reject_call&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}" />
   </actions>
</toast>
  """;

    await WinToast.instance().showCustomToast(
      xml: xml,
      tag: _toastTag('call', content.callId),
      group: _toastRouteGroup(
        clientId: content.clientId,
        roomId: content.roomId,
      ),
    );
  }

  Future<void> displayStoryNotificationContent(
      StoryNotificationContent content) async {
    String? avatarFilePath;

    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    if (content.playSound) {
      _playRoomNotificationSound(content.roomId);
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    avatarFilePath = avatar == null ? "" : avatar.toFilePath();

    // ignore: prefer_function_declarations_over_variables
    var f = (String string) => Uri.encodeComponent(string);

    final title = xmlEscape(content.title);
    final body = xmlEscape(content.content);
    final roomName = xmlEscape(content.roomName);
    final avatarPath = xmlEscape(avatarFilePath);

    final storyEventId = content.storyEventId;
    var defaultAction =
        "action=open_story&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;story_sender_id=${f(content.storySenderId)}&amp;story_id=${f(content.storyId)}";
    if (storyEventId != null) {
      defaultAction += "&amp;story_event_id=${f(storyEventId)}";
    }

    var header = '''<header
        id="${f(content.roomId)}"
        title="$roomName"
        arguments="$defaultAction"/>''';

    if (room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(room) ==
        true) {
      header = "";
    }

    var xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   $header
   <visual>
      <binding template="ToastGeneric">
         <text>$title</text>
         <text>$body</text>
         <image placement='appLogoOverride' src='$avatarPath' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
</toast>
  """;

    await WinToast.instance().showCustomToast(
      xml: xml,
      tag: _toastTag('story', content.eventId),
      group: _toastRouteGroup(
        clientId: content.clientId,
        roomId: content.roomId,
      ),
    );
  }

  Future<void> displayMessageNotification(
      MessageNotificationContent content) async {
    String? avatarFilePath;

    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    _playRoomNotificationSound(content.roomId);
    if (NotificationCompanionController
        .instance.shouldMuteNativeDesktopMessageNotifications) {
      Log.d(
          "Suppressing Windows toast because notification companion overlay is open");
      return;
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    avatarFilePath = avatar == null ? "" : avatar.toFilePath();

    // ignore: prefer_function_declarations_over_variables
    var f = (String string) => Uri.encodeComponent(string);

    final title = xmlEscape(content.senderName);
    final body = xmlEscape(content.content);
    final roomName = xmlEscape(content.roomName);
    final avatarPath = xmlEscape(avatarFilePath);

    var defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;event_id=${f(content.eventId)}";

    var header = '''<header
        id="${f(content.roomId)}"
        title="$roomName"
        arguments="$defaultAction"/>''';

    if (content.isDirectMessage) {
      header = "";
    }

    var xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   $header
   <visual>
      <binding template="ToastGeneric">
         <text>$title</text>
         <text>$body</text>
         <image placement='appLogoOverride' src='$avatarPath' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
   <actions>
      <input id="reply" type="text" placeHolderContent="Send a reply..." />
      <action content="Reply" activationType="background" arguments="action=reply&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;event_id=${f(content.eventId)}" />
   </actions>
</toast>
  """;

    await WinToast.instance().showCustomToast(
      xml: xml,
      tag: _toastTag('message', content.eventId),
      group: _toastRouteGroup(
        clientId: content.clientId,
        roomId: content.roomId,
      ),
    );
  }

  void _playRoomNotificationSound(String roomId) {
    var player = NotificationManager.getSoundPlayer(
      roomLocalId: roomId,
    );
    player.open(Media(
      CustomSoundManager.notificationSoundUri(roomLocalId: roomId),
    ));
  }

  Future<void> displayRoomMembershipNotification(
      RoomMembershipNotificationContent content) async {
    final client = clientManager?.getClient(content.clientId);
    final room = client?.getRoom(content.roomId);
    if (room == null) {
      return;
    }

    _playRoomNotificationSound(content.roomId);

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    final avatarFilePath = avatar == null ? "" : avatar.toFilePath();
    final f = (String string) => Uri.encodeComponent(string);
    final defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;event_id=${f(content.eventId)}";
    final roomName = xmlEscape(content.roomName);
    final title = xmlEscape(content.title);
    final body = xmlEscape(content.content);
    final avatarPath = xmlEscape(avatarFilePath);

    final xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   <header
      id="${f(content.roomId)}"
      title="$roomName"
      arguments="$defaultAction"/>
   <visual>
      <binding template="ToastGeneric">
         <text>$title</text>
         <text>$body</text>
         <image placement='appLogoOverride' src='$avatarPath' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
</toast>
  """;

    await WinToast.instance().showCustomToast(
      xml: xml,
      tag: _toastTag('membership', content.eventId),
      group: _toastRouteGroup(
        clientId: content.clientId,
        roomId: content.roomId,
      ),
    );
  }

  Future<void> displayCalendarReminderNotification(
      CalendarReminderNotificationContent content) async {
    final client = clientManager?.getClient(content.clientId);
    final room = client?.getRoom(content.roomId);
    if (room == null) {
      return;
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.defaultColor,
        placeholderText: content.roomName,
        identifier: room.identifier,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: await room.getShortcutImage());

    final avatarFilePath = avatar == null ? "" : avatar.toFilePath();
    final f = (String string) => Uri.encodeComponent(string);
    final defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}";
    final roomName = xmlEscape(content.roomName);
    final title = xmlEscape(content.title);
    final body = xmlEscape(content.content);
    final avatarPath = xmlEscape(avatarFilePath);

    final xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   <header
      id="${f(content.roomId)}"
      title="$roomName"
      arguments="$defaultAction"/>
   <visual>
      <binding template="ToastGeneric">
         <text>$title</text>
         <text>$body</text>
         <image placement='appLogoOverride' src='$avatarPath' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
</toast>
  """;

    await WinToast.instance().showCustomToast(
      xml: xml,
      tag: _toastTag('calendar', content.eventUid),
      group: _toastRouteGroup(
        clientId: content.clientId,
        roomId: content.roomId,
      ),
    );
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) {
    return clearNotificationsByRoute(
      clientId: room.client.identifier,
      roomId: room.identifier,
    );
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) {
    return WinToast.instance().dismiss(
      tag: '',
      group: _toastRouteGroup(clientId: clientId, roomId: roomId),
    );
  }

  static String _toastRouteGroup({
    required String clientId,
    required String roomId,
  }) {
    final digest = sha1.convert(utf8.encode('$clientId\n$roomId')).toString();
    return 'ig${digest.substring(0, 14)}';
  }

  static String _toastTag(String namespace, String id) {
    final digest = sha1.convert(utf8.encode('$namespace\n$id')).toString();
    return '${namespace}_${digest.substring(0, 16)}';
  }
}
