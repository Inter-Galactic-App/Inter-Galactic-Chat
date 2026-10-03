import 'dart:convert';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/matrix/matrix_peer.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_client.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_events.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_member.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/room_event_settings.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:drift/drift.dart';
import 'package:flutter/src/foundation/key.dart';
import 'package:flutter/src/painting/image_provider.dart';
import 'package:flutter/src/widgets/icon_data.dart';
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixBackgroundRoom implements Room {
  MatrixBackgroundClient backgroundClient;
  RoomDataData data;
  String roomId;
  List<PreloadRoomStateData> preloadState;
  List<NonPreloadRoomStateData> nonPreloadState;
  late List<matrix.BasicEvent> _stateEvents;

  MatrixBackgroundRoom(
    this.backgroundClient, {
    required this.roomId,
    required this.data,
    required this.preloadState,
    required this.nonPreloadState,
  }) {
    _stateEvents = List.empty(growable: true);
    for (var preload in preloadState) {
      _stateEvents.add(matrix.BasicEvent.fromJson(jsonDecode(preload.content)));
    }

    for (var postLoad in nonPreloadState) {
      _stateEvents.add(
        matrix.BasicEvent.fromJson(jsonDecode(postLoad.content)),
      );
    }
  }

  Future<void> init() async {
    var event = _stateEvents.firstWhereOrNull(
      (e) => e.type == matrix.EventTypes.RoomName,
    );

    if (event != null) {
      displayName = event.content["name"] as String;
    }

    var dms = client.getComponent<DirectMessagesComponent>();
    if (dms?.isRoomDirectMessage(this) == true) {
      var partnerId = dms?.getDirectMessagePartnerId(this);
      if (partnerId != null) {
        var partner = await fetchMember(partnerId);
        displayName = partner.displayName;
      }
    }

    if (displayName == "") {
      displayName = identifier;
    }

    if (avatarId != null) {
      avatar = await MatrixBackgroundMember.uriToCachedMxcImageProvider(
        Uri.parse(avatarId!),
      );
    }
  }

  String? get avatarId =>
      _stateEvents
              .firstWhereOrNull((e) => e.type == matrix.EventTypes.RoomAvatar)
              ?.content["url"]
          as String?;

  @override
  Future<TimelineEvent<Client>?> addReaction(
    TimelineEvent<Client> reactingTo,
    Emoticon reaction,
  ) {
    throw UnimplementedError();
  }

  @override
  ImageProvider<Object>? avatar;

  @override
  Future<void> cancelSend(TimelineEvent<Client> event) {
    throw UnimplementedError();
  }

  @override
  Client get client => backgroundClient;

  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  Color get defaultColor => getColorOfUser(identifier);

  @override
  String get developerInfo => throw UnimplementedError();

  @override
  int get displayHighlightedNotificationCount => throw UnimplementedError();

  @override
  bool get displayRoomWideMentionNotification => false;

  @override
  String displayName = "";

  @override
  int get displayNotificationCount => throw UnimplementedError();

  @override
  Future<void> enableE2EE() {
    throw UnimplementedError();
  }

  @override
  Future<Member> fetchMember(String id) async {
    var db = backgroundClient.database.db;
    var data =
        await (db.select(db.roomMembers)..where(
              (tbl) => tbl.roomId.equals(identifier) & tbl.userId.equals(id),
            ))
            .getSingleOrNull();

    MatrixBackgroundMember result = MatrixBackgroundMember(id);
    if (data != null) {
      result = MatrixBackgroundMember(id, data: data);
    }

    await result.init();
    return result;
  }

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) {
    throw UnimplementedError();
  }

  @override
  List<T> getAllComponents<T extends RoomComponent<Client, Room>>() {
    throw UnimplementedError();
  }

  @override
  Color getColorOfUser(String userId) {
    return MatrixPeer.hashColor(userId);
  }

  @override
  T? getComponent<T extends RoomComponent<Client, Room>>() {
    throw UnimplementedError();
  }

  @override
  Future<TimelineEvent<Client>?> getDecryptedEvent(String eventId) =>
      getEvent(eventId);

  @override
  Future<TimelineEvent<Client>?> getEvent(String eventId) async {
    var result = await backgroundClient.api.getOneRoomEvent(
      identifier,
      eventId,
    );
    if (result.type == matrix.EventTypes.Encrypted) {
      final decrypted = await _tryDecryptEvent(result);
      if (decrypted != null) {
        return _backgroundMessage(decrypted);
      }
    }

    if (matrixBackgroundEventIsNotificationCandidate(result)) {
      return _backgroundMessage(result);
    }

    return null;
  }

  Future<TimelineEvent> _backgroundMessage(matrix.MatrixEvent event) async {
    final hasMedia =
        event.content['url'] is String || event.content['file'] is Map;
    final isSticker = matrixBackgroundEventIsSticker(event);
    final isImageMessage =
        event.type == matrix.EventTypes.Message &&
        event.content['msgtype'] == 'm.image';
    if (!hasMedia || (!isSticker && !isImageMessage)) {
      return MatrixBackgroundTimelineEventMessage(event);
    }

    final mediaClient = await backgroundClient.getDecryptClient();
    if (mediaClient == null) {
      return MatrixBackgroundTimelineEventMessage(event);
    }

    final room =
        mediaClient.getRoomById(identifier) ??
        matrix.Room(id: identifier, client: mediaClient);
    final mediaEvent = matrix.Event.fromMatrixEvent(event, room);
    if (isSticker) {
      return MatrixBackgroundTimelineEventSticker.tryCreate(
            event,
            mediaClient: mediaClient,
            mediaEvent: mediaEvent,
          ) ??
          MatrixBackgroundTimelineEventMessage(event);
    }
    return MatrixBackgroundTimelineEventMessage(
      event,
      mediaClient: mediaClient,
      mediaEvent: mediaEvent,
    );
  }

  Future<matrix.MatrixEvent?> _tryDecryptEvent(matrix.MatrixEvent event) async {
    try {
      final decryptClient = await backgroundClient.getDecryptClient();
      final encryption = decryptClient?.encryption;
      if (decryptClient == null || encryption == null) {
        return null;
      }

      final room =
          decryptClient.getRoomById(identifier) ??
          matrix.Room(id: identifier, client: decryptClient);
      final timelineEvent = matrix.Event.fromMatrixEvent(event, room);
      final decrypted = await encryption.decryptRoomEvent(timelineEvent);
      if (decrypted.type == matrix.EventTypes.Encrypted) {
        Log.w(
          "Background notification event ${event.eventId} is still encrypted after wake sync.",
        );
        return null;
      }

      return decrypted;
    } catch (e, s) {
      Log.w("Failed to decrypt background notification event ${event.eventId}");
      Log.onError(e, s);
      return null;
    }
  }

  @override
  Member getMemberOrFallback(String id) {
    throw UnimplementedError();
  }

  @override
  Role getMemberRole(String identifier) {
    throw UnimplementedError();
  }

  @override
  Future<ImageProvider<Object>?> getShortcutImage() async {
    return null;
  }

  @override
  Future<Timeline> getTimeline({String? contextEventId}) {
    throw UnimplementedError();
  }

  @override
  Future<RoomTimelineLease> getTimelineForEventContext(
    String contextEventId,
  ) async => RoomTimelineLease.shared(
    await getTimeline(contextEventId: contextEventId),
  );

  @override
  int get highlightedNotificationCount => throw UnimplementedError();

  @override
  bool get hasRoomWideMentionNotification => false;

  @override
  IconData get icon => throw UnimplementedError();

  @override
  String get identifier => roomId;

  @override
  List<(Member, Role)> importantMembers() {
    throw UnimplementedError();
  }

  @override
  bool get isE2EE =>
      _stateEvents.any((e) => e.type == matrix.EventTypes.Encryption);

  @override
  bool get isMembersListComplete => throw UnimplementedError();

  @override
  Key get key => throw UnimplementedError();

  @override
  TimelineEvent<Client>? get lastEvent => throw UnimplementedError();

  @override
  DateTime get lastEventTimestamp => throw UnimplementedError();

  @override
  String get localId => throw UnimplementedError();

  @override
  String get favoriteStorageId {
    final userId = backgroundClient.self?.identifier;
    if (userId == null || userId.isEmpty || userId == "Error") {
      return "${backgroundClient.identifier}:$identifier";
    }

    return "$userId:$identifier";
  }

  @override
  Iterable<String> get memberIds => throw UnimplementedError();

  @override
  List<Member> membersList() {
    throw UnimplementedError();
  }

  @override
  int get notificationCount => throw UnimplementedError();

  @override
  Stream<void> get onUpdate => throw UnimplementedError();

  @override
  Permissions get permissions => throw UnimplementedError();

  @override
  Future<List<ProcessedAttachment>> processAttachments(
    List<PendingFileAttachment> attachments,
  ) {
    throw UnimplementedError();
  }

  PushRule get pushRule => throw UnimplementedError();

  @override
  RoomEventSettings get roomEventSettings => const RoomEventSettings();

  @override
  Future<void> setRoomEventSettings(RoomEventSettings settings) =>
      Future.value();

  @override
  Future<void> removeReaction(
    TimelineEvent<Client> reactingTo,
    Emoticon reaction,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> retrySend(TimelineEvent<Client> event) {
    throw UnimplementedError();
  }

  @override
  Future<void> retryDecryptAll() async {}

  @override
  Future<TimelineEvent<Client>?> sendMessage({
    String? message,
    TimelineEvent<Client>? inReplyTo,
    TimelineEvent<Client>? replaceEvent,
    List<ProcessedAttachment>? processedAttachments,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setDisplayName(String newName) {
    throw UnimplementedError();
  }

  @override
  Future<void> setPushRule(PushRule rule) {
    throw UnimplementedError();
  }

  @override
  bool shouldNotify(TimelineEvent<Client> event) {
    throw UnimplementedError();
  }

  @override
  bool get shouldPreviewMedia => throw UnimplementedError();

  @override
  Timeline? get timeline => throw UnimplementedError();

  @override
  Member? getMember(String id) {
    // TODO: implement getMember
    throw UnimplementedError();
  }

  @override
  // TODO: implement isSpecialRoomType
  bool get isSpecialRoomType => false;

  @override
  Future<void> banUser(String id) {
    // TODO: implement banUser
    throw UnimplementedError();
  }

  @override
  Future<void> kickUser(String id) {
    // TODO: implement kickUser
    throw UnimplementedError();
  }

  @override
  // TODO: implement availableRoles
  List<Role> get availableRoles => throw UnimplementedError();

  @override
  Future<void> setMemberRole(String id, Role role) {
    // TODO: implement setMemberRole
    throw UnimplementedError();
  }

  @override
  Future<void> setMemberNickname(String id, String? nickname) => Future.error(
    UnsupportedError(
      'MatrixBackgroundRoom is read-only and cannot change room display names.',
    ),
  );

  @override
  // TODO: implement topic
  String? get topic => throw UnimplementedError();

  @override
  Future<void> setTopic(String topic) {
    // TODO: implement setTopic
    throw UnimplementedError();
  }

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) {
    // TODO: implement setRoomAvatar
    throw UnimplementedError();
  }

  @override
  Future<void> markAsRead() {
    // TODO: implement markAsRead
    throw UnimplementedError();
  }

  @override
  // TODO: implement visibility
  RoomVisibility get visibility => throw UnimplementedError();

  @override
  Future<void> setVisibility(RoomVisibility visibility) {
    // TODO: implement setVisibility
    throw UnimplementedError();
  }

  /// The background isolate has no synced room account data, so it cannot see
  /// a snooze record. Returning null rather than throwing is deliberate:
  /// NotificationModifierRoomSnooze reads this getter on whatever Room the
  /// client manager returns, which in this isolate is always a
  /// MatrixBackgroundRoom, so throwing here would break every notification
  /// that passes through the modifier. Null falls through to the legacy
  /// device-local preference, and the server-side override push rule is what
  /// actually suppresses a synced snooze before it is ever pushed.
  @override
  RoomNotificationSnooze? get notificationSnooze => null;

  @override
  Future<void> setNotificationSnooze(
    Duration duration, {
    String source = 'room_settings',
  }) => Future.error(
    UnsupportedError('Temporary room snooze is not supported by this client'),
  );

  @override
  Future<void> clearNotificationSnooze() => Future.error(
    UnsupportedError('Temporary room snooze is not supported by this client'),
  );
}
