import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/push_notification/android/android_notification_image_resolver.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notification_response_handler.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:intergalactic/utils/shortcuts_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

@pragma('vm:entry-point')
void onAndroidBackgroundNotificationResponse(NotificationResponse details) {
  DartPluginRegistrant.ensureInitialized();
  unawaited(NotificationResponseHandler.handle(details));
}

AndroidNotificationAction androidRichNotificationReplyAction({
  required String actionId,
}) {
  return AndroidNotificationAction(
    actionId,
    'Reply',
    inputs: const [AndroidNotificationActionInput(label: 'Message')],
    allowGeneratedReplies: true,
    cancelNotification: false,
    // The pinned Android notification plugin dispatches non-UI RemoteInput
    // actions through a disposable background isolate and does not await or
    // replay them. Deliver Reply through the foreground activity instead so
    // startup receives the submitted RemoteInput before sending it.
    showsUserInterface: true,
    semanticAction: SemanticAction.reply,
  );
}

bool androidNotificationAttachmentSupportsPreview(
  NotificationAttachmentType type,
) =>
    type == NotificationAttachmentType.image ||
    type == NotificationAttachmentType.gif ||
    type == NotificationAttachmentType.sticker;

/// Whether Android may include media in a message notification.
///
/// Staging the new attachment only. It used to gate reuse of the active
/// [MessagingStyleInformation] as well, which meant turning "Show images" off
/// also threw away the conversation history in the shade - a preference about
/// images silently became a preference about message history. The image that
/// gate existed to suppress is removed by
/// [androidNotificationMessagesWithoutMedia] instead.
bool androidNotificationAllowsMediaPreview({
  required bool usePrivatePreviews,
  required bool showMediaInNotifications,
}) => !usePrivatePreviews && showMediaInNotifications;

/// The retained messages of an active notification, with staged media dropped.
///
/// Messages read back from the shade carry the `dataUri` they were posted
/// with, so replaying them verbatim would keep showing an image staged before
/// the user turned media previews off. Only the media fields go; the text,
/// timestamp and sender are what make the history a history.
List<Message> androidNotificationMessagesWithoutMedia(List<Message> retained) {
  return [
    for (final message in retained)
      Message(message.text, message.timestamp, message.person),
  ];
}

class AndroidNotifier implements Notifier {
  static const String notificationIcon = "ig_notification_icon";

  @override
  bool hasPermission = false;

  @override
  bool get needsToken => false;

  static const bool bubblesEnabled = true;
  static const MethodChannel _notificationDiagnosticsChannel = MethodChannel(
    "chat.intergalactic.app/notification_diagnostics",
  );
  static const MethodChannel _notificationPreviewChannel = MethodChannel(
    'chat.intergalactic.app/notification_preview',
  );
  static const Duration _notificationPreviewMaxAge = Duration(days: 2);

  /// Companion cap to [_notificationPreviewMaxAge]. Two days of a busy media
  /// room is thousands of PNG re-encodes, all of them inside the age limit.
  static const int _notificationPreviewMaxFiles = 64;
  static DateTime? _lastDiagnosticsLogAt;
  static const Duration _diagnosticsLogInterval = Duration(minutes: 10);

  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

  @override
  bool get enabled => true;

  @override
  Future<void> init() async {
    Log.i("Initializing notifier! is headless: $isHeadless");

    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const settings = AndroidInitializationSettings(notificationIcon);
    const initSettings = InitializationSettings(android: settings);

    await flutterLocalNotificationsPlugin?.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse:
          onAndroidBackgroundNotificationResponse,
      onDidReceiveNotificationResponse: onResponse,
    );

    if (!isHeadless) {
      final launchDetails = await flutterLocalNotificationsPlugin
          ?.getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchResponse != null) {
        await NotificationResponseHandler.handle(launchResponse);
      }

      await checkPermission();
      await logNotificationDiagnostics(reason: "android-notifier-init");
    } else {
      Log.i(
        "Skipping Android notification permission diagnostics in headless mode",
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
    }
  }

  static Future<void> onForegroundMessage(Map<String, dynamic> message) async {
    var roomId = message["room_id"] as String?;
    var eventId = message["event_id"] as String?;
    var counts = message["counts"];

    if (roomId == null || eventId == null) {
      Log.w(
        "Ignoring Android foreground notification without Matrix room/event "
        "identifiers ${_androidPushPayloadSummary(message)} "
        "countsAvailable=${counts != null}",
      );
      return;
    }

    var client = clientManager!.clients.firstWhereOrNull(
      (element) => element.hasRoom(roomId),
    );

    if (client == null) {
      client = clientManager!.clients.firstWhereOrNull(
        (client) =>
            client.getComponent<InvitationComponent>()?.invitations.any(
              (i) => i.roomId == roomId,
            ) ==
            true,
      );

      for (client in clientManager!.clients) {
        final comp = client.getComponent<InvitationComponent>();

        var invite = comp?.invitations.firstWhereOrNull(
          (i) => i.roomId == roomId,
        );

        if (invite != null) {
          var content = GenericRoomInviteNotificationContent(
            content: "You received an invitation to chat!",
            title: "Room Invite",
          );

          await NotificationManager.notify(content);

          return;
        }
      }

      return;
    }

    var room = client.getRoom(roomId);
    var event = await room!.getEvent(eventId);

    if (event is TimelineEventMessage || event is TimelineEventSticker) {
      final content = await MessageNotificationContent.fromEvent(event!, room);
      if (content != null) {
        await NotificationManager.notify(content);
      }
    }
  }

  Future<void> checkPermission() async {
    var android = flutterLocalNotificationsPlugin!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;

    hasPermission = await android.requestNotificationsPermission() ?? false;
    Log.i(
      "Android notification permission state: granted=$hasPermission",
      category: LogCategory.notifications,
      source: 'android-notifier',
    );
  }

  static Future<void> maybeLogNotificationDiagnostics({
    required String reason,
  }) async {
    final last = _lastDiagnosticsLogAt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < _diagnosticsLogInterval) {
      return;
    }

    _lastDiagnosticsLogAt = now;
    await logNotificationDiagnostics(reason: reason);
  }

  static Future<void> logNotificationDiagnostics({
    required String reason,
  }) async {
    try {
      final diagnostics = await _notificationDiagnosticsChannel
          .invokeMapMethod<String, dynamic>("getNotificationDiagnostics");
      Log.i(
        "Android notification diagnostics reason=$reason "
        "bubblesRequested=$bubblesEnabled "
        "state=${_notificationDiagnosticsSummary(diagnostics)}",
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
    } on MissingPluginException {
      Log.w(
        "Android notification diagnostics unavailable: native channel missing",
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to collect Android notification diagnostics",
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
    }
  }

  static String _notificationDiagnosticsSummary(Map<String, dynamic>? data) {
    if (data == null) {
      return "unavailable";
    }

    final channelSummaries = <String>[];
    final rawChannels = data["channels"];
    if (rawChannels is List) {
      for (final rawChannel in rawChannels) {
        if (rawChannel is! Map) {
          continue;
        }

        channelSummaries.add(
          "{id=${rawChannel["id"]},importance=${rawChannel["importance"]},"
          "canBubble=${rawChannel["canBubble"]}}",
        );
      }
    }

    return "sdk=${data["sdkInt"]} "
        "notificationsEnabled=${data["notificationsEnabled"]} "
        "appBubblesAllowed=${data["appBubblesAllowed"]} "
        "batteryOptimizationIgnored=${data["batteryOptimizationIgnored"]} "
        "channels=[${channelSummaries.join(",")}]";
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case StoryNotificationContent _:
        return displayStoryNotification(notification);
      case ErrorNotificationContent _:
        return displayErrorNotification(notification);
      case CallNotificationContent _:
        return displayCallNotification(notification);
      case GenericRoomInviteNotificationContent _:
        return displayGenericInviteNotification(notification);
      case CalendarReminderNotificationContent _:
        return displayCalendarReminderNotification(notification);
      default:
    }
  }

  Future<void> displayMessageNotification(
    MessageNotificationContent content,
  ) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    if (room is MatrixBackgroundRoom) {
      await room.init();
    }

    if (flutterLocalNotificationsPlugin == null) {
      Log.i(
        "Flutter local notifications plugin was null. Something went wrong",
      );
      return;
    }

    if (shortcutsManager.loading != null) {
      await shortcutsManager.loading;
    }

    final usePrivatePreviews = preferences.usePrivateNotificationPreviews;
    final allowsMediaPreview = androidNotificationAllowsMediaPreview(
      usePrivatePreviews: usePrivatePreviews,
      showMediaInNotifications: preferences.showMediaInNotifications.value,
    );

    Uri? userAvatar;
    if (!usePrivatePreviews) {
      userAvatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        imageId: content.senderImageId,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage,
      );
    }

    Uri? roomAvatar;
    if (!usePrivatePreviews) {
      roomAvatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.defaultColor,
        placeholderText: content.roomName,
        imageId: content.roomImageId,
        format: ShortcutIconFormat.png,
        identifier: room.identifier,
        imageProvider: await room.getShortcutImage(),
      );
    }

    if (!usePrivatePreviews) {
      await Future.wait([shortcutsManager.createShortcutForRoom(room)]);
    }

    final roomKey = NotificationIdentity.roomKeyForMessage(content);
    final id = NotificationIdentity.messageThreadNotificationId(content);
    // Gated on private previews alone: this style is the only source of the
    // thread's previous messages, and dropping it collapses the shade to the
    // one message being posted. Private previews are the case where the
    // retained text itself must not be replayed.
    var activeStyleInfo = usePrivatePreviews
        ? null
        : await AndroidFlutterLocalNotificationsPlugin()
              .getActiveNotificationMessagingStyle(id);

    final retained = activeStyleInfo?.messages;
    if (retained != null && !allowsMediaPreview) {
      retained.setAll(0, androidNotificationMessagesWithoutMedia(retained));
    }

    var person = Person(
      name: content.senderName,
      important: true,
      bot: false,
      key: usePrivatePreviews ? content.roomId : content.senderId,
      icon: userAvatar == null
          ? null
          : BitmapFilePathAndroidIcon(userAvatar.toFilePath()),
    );

    final displayContent =
        content.attachmentPresentation?.displayText ?? content.content;
    // `NotificationModifierHideContent` already removes media when private
    // previews are on. This renderer gate additionally honours the independent
    // "Show images" preference and protects direct notifier callers.
    final attachmentUri = content.allowsRichActions && allowsMediaPreview
        ? await _messageAttachmentUri(content.attachmentPresentation)
        : null;
    var message = Message(
      displayContent,
      DateTime.now(),
      person,
      dataMimeType: attachmentUri == null ? null : 'image/png',
      dataUri: attachmentUri,
    );

    var payload = OpenRoomURI(
      roomId: content.roomId,
      clientId: content.clientId,
    ).toString();
    var replyAction = SendMessageUri(
      roomId: content.roomId,
      clientId: content.clientId,
    ).toString();

    activeStyleInfo?.messages?.add(message);

    var style =
        activeStyleInfo ??
        MessagingStyleInformation(
          person,
          conversationTitle: content.isDirectMessage ? content.roomName : null,
          groupConversation: !content.isDirectMessage,
          messages: [message],
        );

    Log.i(
      "Preparing Android message notification "
      "channel=messages category=message bubble=$bubblesEnabled "
      "silent=${content.priority == NotificationPriority.low}",
      category: LogCategory.notifications,
      source: 'android-notifier',
    );

    var details = AndroidNotificationDetails(
      "messages",
      "Message Received",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
      number: style.messages!.length,
      largeIcon: usePrivatePreviews || roomAvatar == null
          ? null
          : FilePathAndroidBitmap(roomAvatar.toFilePath()),
      subText: content.roomName,
      groupKey: roomKey,
      groupAlertBehavior: GroupAlertBehavior.all,
      styleInformation: style,
      sound: RawResourceAndroidNotificationSound('message'),
      shortcutId: usePrivatePreviews ? null : content.roomId,
      silent: content.priority == NotificationPriority.low,
      ticker: displayContent,
      bubble: !usePrivatePreviews && bubblesEnabled
          ? BubbleMetadata(
              "chat.intergalactic.app.BubbleActivity",
              extra: payload,
              desiredHeight: 600,
            )
          : null,
      actions: [
        if (content.allowsRichActions)
          androidRichNotificationReplyAction(actionId: replyAction),
        ..._roomSnoozeActions(),
      ],
      color: const Color.fromARGB(0xff, 0x53, 0x4c, 0xdd),
    );

    await flutterLocalNotificationsPlugin?.show(
      id,
      null,
      displayContent,
      NotificationDetails(android: details),
      payload: payload,
    );
    unawaited(
      maybeLogNotificationDiagnostics(
        reason: "after-message-notification-show",
      ),
    );
  }

  Future<void> displayStoryNotification(
    StoryNotificationContent content,
  ) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    if (room is MatrixBackgroundRoom) {
      await room.init();
    }

    if (flutterLocalNotificationsPlugin == null) {
      Log.i(
        "Flutter local notifications plugin was null. Something went wrong",
      );
      return;
    }

    if (shortcutsManager.loading != null) {
      await shortcutsManager.loading;
    }

    Uri? senderAvatar = await ShortcutsManager.getCachedAvatarImage(
      placeholderColor: room.getColorOfUser(content.senderId),
      placeholderText: content.senderName,
      imageId: content.senderImageId,
      identifier: content.senderId,
      format: ShortcutIconFormat.png,
      shouldZoomOut: false,
      imageProvider: content.senderImage,
    );

    final roomKey = NotificationIdentity.roomKeyForStory(content);
    final payload = OpenStoryURI(
      roomId: content.roomId,
      clientId: content.clientId,
      storySenderId: content.storySenderId,
      storyId: content.storyId,
      storyEventId: content.storyEventId,
    ).toString();

    Log.i(
      "Preparing Android story notification "
      "channel=messages category=message sound=${content.playSound}",
      category: LogCategory.notifications,
      source: 'android-notifier',
    );

    var details = AndroidNotificationDetails(
      "messages",
      "Message Received",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
      largeIcon: senderAvatar == null
          ? null
          : FilePathAndroidBitmap(senderAvatar.toFilePath()),
      subText: content.roomName,
      groupKey: roomKey,
      groupAlertBehavior: GroupAlertBehavior.all,
      styleInformation: BigTextStyleInformation(content.content),
      playSound: content.playSound,
      sound: content.playSound
          ? const RawResourceAndroidNotificationSound('message')
          : null,
      silent: !content.playSound,
      ticker: content.content,
      category: AndroidNotificationCategory.message,
      actions: _roomSnoozeActions(),
      color: const Color.fromARGB(0xff, 0x53, 0x4c, 0xdd),
    );

    await flutterLocalNotificationsPlugin?.show(
      NotificationIdentity.storyNotificationId(content),
      content.title,
      content.content,
      NotificationDetails(android: details),
      payload: payload,
    );
    unawaited(
      maybeLogNotificationDiagnostics(reason: "after-story-notification-show"),
    );
  }

  Future<void> displayCallNotification(CallNotificationContent content) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    if (room is MatrixBackgroundRoom) {
      await room.init();
    }

    if (flutterLocalNotificationsPlugin == null) {
      Log.i(
        "Flutter local notifications plugin was null. Something went wrong",
      );
      return;
    }

    if (shortcutsManager.loading != null) {
      await shortcutsManager.loading;
    }

    Uri? roomAvatar = await ShortcutsManager.getCachedAvatarImage(
      placeholderColor: room.defaultColor,
      placeholderText: content.roomName,
      imageId: content.roomImageId,
      format: ShortcutIconFormat.png,
      identifier: room.identifier,
      imageProvider: await room.getShortcutImage(),
    );

    final roomKey = NotificationIdentity.roomKeyForCall(content);
    final id = NotificationIdentity.callNotificationId(content);

    var payload = OpenRoomURI(
      roomId: content.roomId,
      clientId: content.clientId,
    ).toString();

    var details = AndroidNotificationDetails(
      "incoming_calls_channel_1",
      "Incoming Call",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
      timeoutAfter: 60000,
      largeIcon: FilePathAndroidBitmap(roomAvatar.toString()),
      subText: content.roomName,
      fullScreenIntent: true,
      sound: RawResourceAndroidNotificationSound('ringtone_in'),
      groupKey: roomKey,
      actions: [
        AndroidNotificationAction(
          AcceptCallUri(
            roomId: content.roomId,
            callId: content.callId,
            clientId: content.clientId,
          ).toString(),
          "Accept",
          showsUserInterface: true,
          semanticAction: SemanticAction.call,
          titleColor: Colors.green,
        ),
        AndroidNotificationAction(
          DeclineCallUri(
            roomId: content.roomId,
            callId: content.callId,
            clientId: content.clientId,
          ).toString(),
          "Decline",
          showsUserInterface: true,
          semanticAction: SemanticAction.delete,
          titleColor: Colors.red,
        ),
      ],
      groupAlertBehavior: GroupAlertBehavior.all,
      shortcutId: content.roomId,
      silent: false,
      ticker: content.content,
      color: const Color.fromARGB(0xff, 0x53, 0x4c, 0xdd),
    );

    await flutterLocalNotificationsPlugin?.show(
      id,
      null,
      content.content,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  Future<Uint8List?> getImageBytes(ImageProvider? provider) async {
    if (provider != null) {
      final data = await resolveAndroidNotificationImage(
        provider,
        ImageUtils.imageProviderToImage,
      );
      var bytes = await data?.toByteData(format: ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    }
    return null;
  }

  Future<String?> _messageAttachmentUri(
    NotificationAttachmentPresentation? presentation,
  ) async {
    if (presentation == null) {
      Log.d(
        'android_notification_preview result=skipped reason=no_attachment',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
      return null;
    }
    if (!androidNotificationAttachmentSupportsPreview(presentation.type)) {
      Log.d(
        'android_notification_preview result=skipped '
        'reason=unsupported_type type=${presentation.type.name}',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
      return null;
    }
    if (presentation.preview == null) {
      Log.w(
        'android_notification_preview result=skipped reason=no_preview '
        'type=${presentation.type.name}',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
      return null;
    }

    try {
      final bytes = await getImageBytes(presentation.preview);
      if (bytes == null || bytes.isEmpty) {
        Log.w(
          'android_notification_preview result=skipped reason=empty_bytes '
          'type=${presentation.type.name}',
          category: LogCategory.notifications,
          source: 'android-notifier',
        );
        return null;
      }

      final cacheDirectory = await getTemporaryDirectory();
      final previewDirectory = Directory(
        path.join(cacheDirectory.path, 'shared_media', 'notification-previews'),
      );
      await previewDirectory.create(recursive: true);
      await _sweepNotificationPreviews(previewDirectory);

      final file = File(
        path.join(
          previewDirectory.path,
          'preview-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}.png',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      final uri = await _notificationPreviewChannel.invokeMethod<String>(
        'contentUriForNotificationPreview',
        {'path': file.path},
      );
      if (uri == null || uri.isEmpty) {
        Log.w(
          'android_notification_preview result=skipped reason=missing_content_uri '
          'type=${presentation.type.name}',
          category: LogCategory.notifications,
          source: 'android-notifier',
        );
        return null;
      }
      Log.i(
        'android_notification_preview result=staged type=${presentation.type.name} '
        'bytes=${bytes.length} uri_scheme=content',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
      return uri;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to stage Android notification image preview',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
      return null;
    }
  }

  /// Age is not enough on its own: every staged preview is a full PNG
  /// re-encode, and a media-heavy room can put thousands of them in this
  /// directory well inside the age limit. So the sweep also keeps the newest
  /// [_notificationPreviewMaxFiles] and deletes the rest oldest-first.
  Future<void> _sweepNotificationPreviews(Directory directory) async {
    final cutoff = DateTime.now().subtract(_notificationPreviewMaxAge);
    final survivors = <(DateTime, File)>[];
    // Collected so the native read grant can be released for each one. Staging
    // calls `grantUriPermission` and nothing revoked it, so every preview left
    // a grant behind for the life of the process - pointing, after this sweep,
    // at a file that no longer exists.
    final deleted = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final modified = (await entity.stat()).modified;
        if (modified.isBefore(cutoff)) {
          await entity.delete();
          deleted.add(entity.path);
          continue;
        }
        survivors.add((modified, entity));
      } catch (_) {
        // Best-effort cache cleanup; a preview must never block notification delivery.
      }
    }

    if (survivors.length > _notificationPreviewMaxFiles) {
      survivors.sort((a, b) => a.$1.compareTo(b.$1));
      for (final (_, file) in survivors.take(
        survivors.length - _notificationPreviewMaxFiles,
      )) {
        try {
          await file.delete();
          deleted.add(file.path);
        } catch (_) {
          // As above.
        }
      }
    }

    await _revokeNotificationPreviewGrants(deleted);
  }

  Future<void> _revokeNotificationPreviewGrants(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _notificationPreviewChannel.invokeMethod<int>(
        'revokeNotificationPreviewGrants',
        {'paths': paths},
      );
    } on MissingPluginException {
      // An older plugin build without the method. The files are already gone,
      // so the stale grants are inert; not worth failing the sweep for.
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to revoke Android notification preview grants',
        category: LogCategory.notifications,
        source: 'android-notifier',
      );
    }
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  static void onResponse(NotificationResponse details) {
    unawaited(NotificationResponseHandler.handle(details));
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) async {
    final plugin = flutterLocalNotificationsPlugin;
    if (plugin == null) {
      return;
    }

    final notifications = await plugin.getActiveNotifications();
    final roomKey = NotificationIdentity.roomKeyForRoom(room);

    await Future.wait([
      for (final noti in notifications)
        if (noti.groupKey == roomKey && noti.id != null)
          plugin.cancel(noti.id!),
    ]);
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {
    final plugin = flutterLocalNotificationsPlugin;
    if (plugin == null) {
      return;
    }

    final notifications = await plugin.getActiveNotifications();
    final roomKey = NotificationIdentity.roomKey(
      clientId: clientId,
      roomId: roomId,
    );

    await Future.wait([
      for (final noti in notifications)
        if (noti.groupKey == roomKey && noti.id != null)
          plugin.cancel(noti.id!),
    ]);
  }

  Future<void> displayErrorNotification(
    ErrorNotificationContent notification,
  ) async {
    var details = AndroidNotificationDetails(
      "errors",
      "Error Messages",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
      styleInformation: BigTextStyleInformation(notification.content),
    );

    await flutterLocalNotificationsPlugin?.show(
      Random().nextInt(1000000),
      notification.title,
      notification.content,
      NotificationDetails(android: details),
    );
  }

  Future<void> displayGenericInviteNotification(
    GenericRoomInviteNotificationContent notification,
  ) async {
    var details = AndroidNotificationDetails(
      "chat_invites",
      "Chat Invitations",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
    );

    await flutterLocalNotificationsPlugin?.show(
      Random().nextInt(1000000),
      notification.title,
      notification.content,
      NotificationDetails(android: details),
    );
  }

  Future<void> displayCalendarReminderNotification(
    CalendarReminderNotificationContent notification,
  ) async {
    final roomKey = NotificationIdentity.roomKeyForCalendar(notification);
    final details = AndroidNotificationDetails(
      "calendar_reminders",
      "Calendar Reminders",
      importance: Importance.high,
      priority: Priority.high,
      icon: notificationIcon,
      styleInformation: BigTextStyleInformation(notification.content),
      groupKey: roomKey,
      actions: _roomSnoozeActions(),
    );

    final payload = OpenRoomURI(
      roomId: notification.roomId,
      clientId: notification.clientId,
    ).toString();

    await flutterLocalNotificationsPlugin?.show(
      NotificationIdentity.calendarReminderNotificationId(notification),
      notification.title,
      notification.content,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  List<AndroidNotificationAction> _roomSnoozeActions() =>
      androidRoomNotificationSnoozeActions();
}

/// Android exposes only a small native action row. Opening the existing room
/// notification settings picker preserves every duration instead of pushing
/// later choices off-screen after Reply.
List<AndroidNotificationAction> androidRoomNotificationSnoozeActions() =>
    const [
      AndroidNotificationAction(
        roomNotificationSnoozePickerActionId,
        'Mute',
        showsUserInterface: true,
        semanticAction: SemanticAction.mute,
      ),
    ];

String _androidPushPayloadSummary(Map<String, dynamic> data) {
  final keys = data.keys.map((key) => key.toString()).toList()..sort();
  return "keys=${keys.join(',')} "
      "hasRoom=${data.containsKey("room_id")} "
      "hasEvent=${data.containsKey("event_id")}";
}
