import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:intergalactic/client/components/message_effects/automatic_message_effects.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_formatting.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_types.dart';
import 'package:intergalactic/client/components/component_registry.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/components/user_color/user_color_component.dart';
import 'package:intergalactic/client/matrix/components/calendar_room_component/matrix_calendar_room_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:intergalactic/client/matrix/matrix_attachment.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_peer.dart';
import 'package:intergalactic/client/matrix/matrix_role.dart';
import 'package:intergalactic/client/matrix/matrix_room_display_name_state.dart';
import 'package:intergalactic/client/matrix/matrix_room_permissions.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_add_reaction.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_call.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_create_room.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_edit.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_edit_calendar.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_encrypted.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_pinned_messages.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_redaction.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_sticker.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/room_event_settings.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix_api_lite/model/stripped_state_event.dart';

// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

import '../attachment.dart';
import '../client.dart';
import 'package:matrix/matrix.dart' as matrix;

String _matrixRoomLogHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return MatrixClient.hash(text).substring(0, 12);
}

String _matrixRoomLogError(Object error) => error.runtimeType.toString();

Map<String, dynamic>? matrixThreadRelationExtraContent({
  required String? threadRootEventId,
  String? threadLastEventId,
}) {
  if (threadRootEventId == null) {
    return null;
  }

  return {
    'm.relates_to': {
      'event_id': threadRootEventId,
      'rel_type': matrix.RelationshipTypes.thread,
      'is_falling_back': true,
      if (threadLastEventId != null)
        'm.in_reply_to': {
          'event_id': threadLastEventId,
        },
    },
  };
}

void _applyAutomaticMessageEffect(
  Map<String, dynamic> event,
  String message,
  MessageEffectKind effect,
) {
  switch (effect) {
    case MessageEffectKind.confetti:
      event['msgtype'] = MessageEffectTypes.confetti;
      break;
    case MessageEffectKind.snowfall:
      event['msgtype'] = MessageEffectTypes.snowfall;
      break;
    case MessageEffectKind.spaceInvaders:
      event['msgtype'] = MessageEffectTypes.spaceInvaders;
      break;
    case MessageEffectKind.rainbow:
      event['msgtype'] = matrix.MessageTypes.Text;
      event['format'] = 'org.matrix.custom.html';
      event['formatted_body'] = rainbowFormattedBody(message);
      break;
  }
}

class MatrixRoom extends Room {
  late matrix.Room _matrixRoom;

  late String _displayName;

  late MatrixRoomPermissions _permissions;

  final StreamController<void> _onUpdate = StreamController.broadcast();

  final StreamController<void> onTimelineLoaded = StreamController.broadcast();

  late final List<RoomComponent<MatrixClient, MatrixRoom>> _components;

  ImageProvider? _avatar;

  @override
  String? get avatarId => _matrixRoom.avatar?.toString();

  late MatrixClient _client;

  MatrixTimeline? _timeline;

  matrix.Room get matrixRoom => _matrixRoom;

  @override
  String get displayName {
    if (!_hasExplicitRoomName) {
      final partnerId = client
          .getComponent<DirectMessagesComponent>()
          ?.getDirectMessagePartnerId(this);
      if (partnerId != null) {
        return getMemberOrFallback(partnerId).displayName;
      }
    }

    return _localizedDisplayName;
  }

  bool get _hasExplicitRoomName => _matrixRoom.name.trim().isNotEmpty;

  String get _localizedDisplayName =>
      _displayName.startsWith("#") ? _displayName.substring(1) : _displayName;

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isE2EE => _matrixRoom.encrypted;

  @override
  int get highlightedNotificationCount => _matrixRoom.highlightCount;

  @override
  int get notificationCount {
    final rawCount = _matrixRoom.notificationCount;
    if (rawCount <= 0) {
      return rawCount;
    }

    final latestReceiptMs =
        _matrixRoom.receiptState.global.latestOwnReceipt?.ts;
    final latestOwnReceiptAt = latestReceiptMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(latestReceiptMs, isUtc: true);
    final suppressed = _client
            .getComponent<StoryComponent>()
            ?.suppressedNotificationCountForRoom(
              roomId: identifier,
              latestOwnReceiptAt: latestOwnReceiptAt,
              rawNotificationCount: rawCount,
            ) ??
        0;
    return (rawCount - suppressed).clamp(0, rawCount).toInt();
  }

  bool _hasRoomWideMentionNotification = false;

  @override
  bool get hasRoomWideMentionNotification => _hasRoomWideMentionNotification;

  void notifyUpdate() {
    _onUpdate.add(null);
  }

  late DateTime _lastStateEventTimestamp;
  @override
  DateTime get lastEventTimestamp => lastEvent == null
      ? _lastStateEventTimestamp
      : lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);

  @override
  TimelineEvent? lastEvent;

  @override
  Iterable<String> get memberIds =>
      _matrixRoom.getParticipants([matrix.Membership.join]).map((e) => e.id);

  @override
  String get developerInfo =>
      const JsonEncoder.withIndent('  ').convert(_matrixRoom.states);

  Color? hashColor;
  @override
  Color get defaultColor {
    var comp = client.getComponent<DirectMessagesComponent>();
    if (comp?.isRoomDirectMessage(this) == true) {
      var user = comp?.getDirectMessagePartnerId(this);
      if (user != null) {
        var member = getMember(user);
        if (member != null) {
          return member.defaultColor;
        }
      }
    }

    if (hashColor != null) return hashColor!;

    hashColor = MatrixPeer.hashColor(identifier);

    return hashColor!;
  }

  // cache the result of push rule because this was becoming an expensive operation for ui stuff
  matrix.PushRuleState? _pushRule;
  @override
  PushRule get pushRule {
    if (_pushRule == null) {
      _pushRule = _readPushRuleState();
    }

    switch (_pushRule!) {
      case matrix.PushRuleState.notify:
        return PushRule.notify;
      case matrix.PushRuleState.mentionsOnly:
        return PushRule.mentionsOnly;
      case matrix.PushRuleState.dontNotify:
        return PushRule.dontNotify;
    }
  }

  @override
  Future<void> setPushRule(PushRule rule) async {
    final newRule = switch (rule) {
      PushRule.notify => matrix.PushRuleState.notify,
      PushRule.mentionsOnly => matrix.PushRuleState.mentionsOnly,
      PushRule.dontNotify => matrix.PushRuleState.dontNotify,
    };

    await _setPushRuleState(newRule);
    _pushRule = newRule;
    _onUpdate.add(null);
  }

  matrix.PushRuleState _readPushRuleState() {
    final globalPushRules = _matrixRoom.client.globalPushRules;
    if (globalPushRules == null) {
      return matrix.PushRuleState.notify;
    }

    final overridePushRules = globalPushRules.override;
    if (overridePushRules != null) {
      for (final pushRule in overridePushRules) {
        if (pushRule.ruleId != _matrixRoom.id) {
          continue;
        }

        final actions = List<Object?>.from(pushRule.actions)
          ..remove("dont_notify")
          ..remove("coalesce");
        if (actions.isEmpty) {
          return matrix.PushRuleState.dontNotify;
        }
        return matrix.PushRuleState.notify;
      }
    }

    final roomPushRules = globalPushRules.room;
    if (roomPushRules != null) {
      for (final pushRule in roomPushRules) {
        if (pushRule.ruleId != _matrixRoom.id) {
          continue;
        }

        final actions = List<Object?>.from(pushRule.actions)
          ..remove("dont_notify")
          ..remove("coalesce");
        if (actions.isEmpty) {
          return matrix.PushRuleState.mentionsOnly;
        }
        break;
      }
    }

    return matrix.PushRuleState.notify;
  }

  Future<void> _setPushRuleState(matrix.PushRuleState newState) async {
    final currentState = _pushRule ?? _readPushRuleState();
    if (newState == currentState) {
      return;
    }

    switch (newState) {
      case matrix.PushRuleState.notify:
        if (currentState == matrix.PushRuleState.dontNotify) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.override,
            _matrixRoom.id,
          );
        } else if (currentState == matrix.PushRuleState.mentionsOnly) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
          );
        }
        break;
      case matrix.PushRuleState.mentionsOnly:
        if (currentState == matrix.PushRuleState.dontNotify) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.override,
            _matrixRoom.id,
          );
          await _matrixRoom.client.setPushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
            [],
          );
        } else if (currentState == matrix.PushRuleState.notify) {
          await _matrixRoom.client.setPushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
            [],
          );
        }
        break;
      case matrix.PushRuleState.dontNotify:
        if (currentState == matrix.PushRuleState.mentionsOnly) {
          await _matrixRoom.client.deletePushRule(
            matrix.PushRuleKind.room,
            _matrixRoom.id,
          );
        }
        await _matrixRoom.client.setPushRule(
          matrix.PushRuleKind.override,
          _matrixRoom.id,
          [],
          conditions: [
            matrix.PushCondition(
              kind: matrix.PushRuleConditions.eventMatch.name,
              key: 'room_id',
              pattern: _matrixRoom.id,
            ),
          ],
        );
        break;
    }
  }

  @override
  RoomEventSettings get roomEventSettings {
    final state = _matrixRoom.getState(RoomEventSettings.stateEventType);
    return RoomEventSettings.fromStateContent(state?.content);
  }

  @override
  Future<void> setRoomEventSettings(RoomEventSettings settings) async {
    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      RoomEventSettings.stateEventType,
      '',
      settings.toStateContent(),
    );
    _onUpdate.add(null);
  }

  @override
  ImageProvider<Object>? get avatar {
    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp == null) {
      return _avatar;
    }

    if (comp.isRoomDirectMessage(this)) {
      final partner = comp.getDirectMessagePartnerId(this);
      if (partner != null) {
        return getMemberOrFallback(partner).avatar;
      }
    }

    return _avatar;
  }

  @override
  Client get client => _client;

  @override
  String get identifier => _matrixRoom.id;

  @override
  Timeline? get timeline => _timeline;

  final List<StreamSubscription> _subscriptions = [];

  MatrixRoom(
    MatrixClient client,
    matrix.Room room,
    matrix.Client matrixClient,
  ) {
    _matrixRoom = room;
    _client = client;

    _displayName = room.getLocalizedDisplayname();
    _components = ComponentRegistry.getMatrixRoomComponents(client, this);

    _matrixRoom.postLoad();

    _lastStateEventTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    matrix.Event? latest = room.lastEvent;

    if (latest != null) {
      lastEvent = convertEvent(latest);
    }

    updateAvatar();

    _subscriptions.add(
      _matrixRoom.client.onRoomState.stream
          .where((event) => event.roomId == _matrixRoom.id)
          .listen(onRoomStateUpdated),
    );

    _subscriptions.add(
      _matrixRoom.client.onSync.stream
          .where((i) => i.rooms?.join?.containsKey(_matrixRoom.id) == true)
          .listen(onRoomSyncUpdate),
    );

    _subscriptions.add(
      _matrixRoom.client.onTimelineEvent.stream
          .where((event) => event.roomId == _matrixRoom.id)
          .listen(onEvent),
    );

    _subscriptions.add(
      _matrixRoom.client.onNotification.stream
          .where((event) => event.roomId == _matrixRoom.id)
          .listen(onNotification),
    );

    _permissions = MatrixRoomPermissions(_matrixRoom);
  }

  String? _readLegacyMemberRoomDisplayName(String id) {
    final state = _matrixRoom.getState(
          matrixRoomDisplayNamesLegacyStateEventType,
          matrixRoomDisplayNamesLegacyStateKey(id),
        ) ??
        _matrixRoom.getState(matrixRoomDisplayNamesLegacyStateEventType, id);
    return readLegacyMatrixRoomDisplayNameFromContent(state?.content);
  }

  String? getMemberRoomDisplayName(String id) {
    final displayNames = matrixRoomDisplayNamesFromStateContent(
      _matrixRoom.getState(matrixRoomDisplayNamesStateEventType, '')?.content,
    );
    return displayNames[id] ?? _readLegacyMemberRoomDisplayName(id);
  }

  String? resolveMention(String mention) {
    final resolvedMention = _matrixRoom.getMention(mention);
    if (resolvedMention != null) {
      return resolvedMention;
    }

    final normalizedMention = normalizeMatrixMentionLabel(mention);
    if (normalizedMention.isEmpty) {
      return null;
    }

    final lowercaseMention = normalizedMention.toLowerCase();
    for (final memberId in memberIds) {
      final member = getMemberOrFallback(memberId);
      if (member.displayName == normalizedMention ||
          member.displayName.toLowerCase() == lowercaseMention) {
        return member.identifier;
      }
    }

    return null;
  }

  MatrixMember _memberFromUser(matrix.User user) {
    return MatrixMember(
      _client,
      user,
      roomDisplayName: getMemberRoomDisplayName(user.id),
    );
  }

  Future<void> _setMemberRoomDisplayName(
    String id,
    String? displayName, {
    String? updatedBy,
  }) async {
    final trimmedDisplayName = displayName?.trim();
    final currentDisplayName = getMemberRoomDisplayName(id);
    if ((trimmedDisplayName == null || trimmedDisplayName.isEmpty)
        ? currentDisplayName == null
        : currentDisplayName == trimmedDisplayName) {
      return;
    }

    final displayNames = Map<String, String>.from(
      matrixRoomDisplayNamesFromStateContent(
        _matrixRoom.getState(matrixRoomDisplayNamesStateEventType, '')?.content,
      ),
    );

    if (trimmedDisplayName == null || trimmedDisplayName.isEmpty) {
      displayNames.remove(id);
    } else {
      displayNames[id] = trimmedDisplayName;
    }

    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      matrixRoomDisplayNamesStateEventType,
      '',
      matrixRoomDisplayNamesToStateContent(
        displayNames,
        updatedBy: updatedBy,
        updatedAt: DateTime.now(),
      ),
    );
    await _matrixRoom.waitForRoomInSync();
    _onUpdate.add(null);
  }

  Future<void> _setLegacyMemberRoomDisplayName(
    String id,
    String? displayName, {
    String? updatedBy,
  }) async {
    final trimmedDisplayName = displayName?.trim();
    final currentDisplayName = _readLegacyMemberRoomDisplayName(id);
    if ((trimmedDisplayName == null || trimmedDisplayName.isEmpty)
        ? currentDisplayName == null
        : currentDisplayName == trimmedDisplayName) {
      return;
    }

    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      matrixRoomDisplayNamesLegacyStateEventType,
      matrixRoomDisplayNamesLegacyStateKey(id),
      buildLegacyMatrixRoomDisplayNameStateContent(
        trimmedDisplayName,
        updatedBy: updatedBy,
        updatedAt: DateTime.now(),
      ),
    );
    await _matrixRoom.waitForRoomInSync();
    _onUpdate.add(null);
  }

  Future<void> updateAvatar({bool fromCache = true}) async {
    if (_matrixRoom.avatar != null) {
      _avatar = MatrixMxcImage(
        _matrixRoom.avatar!,
        _matrixRoom.client,
        thumbnailHeight: 64,
        fullResHeight: 128,
        autoLoadFullRes: false,
      );
    } else if (_matrixRoom.isDirectChat) {
      var user = _matrixRoom.unsafeGetUserFromMemoryOrFallback(
        _matrixRoom.directChatMatrixID!,
      );
      var url = user.avatarUrl;
      if (url != null) {
        _avatar = MatrixMxcImage(
          url,
          _matrixRoom.client,
          thumbnailHeight: 64,
          fullResHeight: 128,
          autoLoadFullRes: false,
        );
      }
    }

    _onUpdate.add(null);
  }

  void onEvent(matrix.Event matrixEvent) async {
    if (matrixEvent.roomId != identifier) {
      return;
    }

    if (matrixEvent.type == matrix.EventTypes.Message) {
      var event = convertEvent(matrixEvent);
      if (lastEvent == null) {
        lastEvent = event;
        _onUpdate.add(null);
      } else if (event.originServerTs.isAfter(lastEvent!.originServerTs)) {
        lastEvent = event;
        _onUpdate.add(null);
      }
    }
  }

  void onNotification(matrix.Event matrixEvent) {
    var event = convertEvent(matrixEvent);

    updateRoomWideMentionNotification(event);
    handleNotification(event);
  }

  void updateRoomWideMentionNotification(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) {
      return;
    }

    if (!_hasRoomMention(event) || !shouldNotify(event)) {
      return;
    }

    if (_hasRoomWideMentionNotification) {
      return;
    }

    _hasRoomWideMentionNotification = true;
    _onUpdate.add(null);
  }

  Future<void> handleNotification(TimelineEvent event) async {
    if (!shouldNotify(event)) {
      return;
    }

    if (event is MatrixTimelineEventCall ||
        event is MatrixTimelineEventUnknown) {
      return;
    }

    if (event is TimelineEventMessage || event is TimelineEventSticker) {
      // let platform push handlers own message notifications on Android and Web
      if (BuildConfig.ANDROID || BuildConfig.WEB) {
        return;
      }

      var notification = await MessageNotificationContent.fromEvent(
        event,
        this,
      );
      if (notification != null) {
        NotificationManager.notify(notification);
      }
    }
  }

  @override
  bool shouldNotify(TimelineEvent event) {
    if ((client as MatrixClient).firstSyncComplete == false) {
      return false;
    }

    // never notify for a message that came from an account we are logged in to!
    if (clientManager?.clients.any(
          (element) => element.self?.identifier == event.senderId,
        ) ==
        true) {
      return false;
    }

    var timeDiff = DateTime.now().difference(event.originServerTs);

    // dont notify if we are receiving an old message
    if (timeDiff.inMinutes > 10) {
      return false;
    }

    if (event is! MatrixTimelineEvent) {
      return false;
    }

    final notificationMode = preferences.notificationMode.value;
    if (notificationMode == 'mute') {
      return false;
    }

    if (_hasRoomMention(event)) {
      return true;
    }

    var evaluator = _matrixRoom.client.pushruleEvaluator;
    var match = evaluator.match(event.event);

    if (!match.notify) {
      return false;
    }

    if (notificationMode == 'mentions') {
      return match.highlight;
    }

    return true;
  }

  bool _hasRoomMention(MatrixTimelineEvent event) {
    final mentions = event.event.content['m.mentions'];
    return mentions is Map && mentions['room'] == true;
  }

  @override
  Future<List<ProcessedAttachment>> processAttachments(
    List<PendingFileAttachment> attachments,
  ) async {
    final processedAttachments = await Future.wait(
      attachments.map(processAttachment),
    );

    return processedAttachments.whereType<ProcessedAttachment>().toList();
  }

  Future<MatrixProcessedAttachment?> processAttachment(
    PendingFileAttachment attachment,
  ) async {
    await attachment.resolve();
    if (attachment.data == null) return null;

    if (attachment.mimeType == "image/bmp") {
      var img = MemoryImage(attachment.data!);
      var image = await ImageUtils.imageProviderToImage(img);
      var bytes = await image.toByteData(format: ImageByteFormat.png);
      if (bytes == null) {
        Log.w("Failed to convert BMP image to PNG bytes");
        return null;
      }

      attachment.data = bytes.buffer.asUint8List();
      attachment.mimeType = "image/png";
    }

    var fileExtension = attachment.mimeType != null
        ? Mime.extensionFromMime(attachment.mimeType!)
        : null;
    if (fileExtension == null) {
      fileExtension = "";
    } else {
      fileExtension = ".${fileExtension}";
    }

    try {
      if (Mime.imageTypes.contains(attachment.mimeType)) {
        await decodeImageFromList(attachment.data!);

        final name = attachment.name ?? "unknown${fileExtension}";

        return MatrixProcessedAttachment(
          await matrix.MatrixImageFile.create(
            bytes: attachment.data!,
            name: name,
            mimeType: attachment.mimeType,
            nativeImplementations: (client as MatrixClient).nativeImplentations,
          ),
          spoiler: attachment.spoiler,
        );
      }
    } catch (error, stack) {
      // This image is probably corrupt, since it has a mime type we should be able to display,
      // But we can't decode the image. Just clear the mime type so clients dont try to display this bad file
      attachment.mimeType = 'application/octet-stream';
      Log.onError(error, stack);
    }

    matrix.MatrixImageFile? thumbnailImageFile;
    if (attachment.thumbnailFile != null) {
      var decodedImage = await decodeImageFromList(attachment.thumbnailFile!);

      thumbnailImageFile = matrix.MatrixImageFile(
        bytes: attachment.thumbnailFile!,
        width: decodedImage.width,
        height: decodedImage.height,
        mimeType: attachment.thumbnailMime,
        name: "thumbnail",
      );
    }

    final name = attachment.name ?? "Unknown${fileExtension}";

    if (Mime.videoTypes.contains(attachment.mimeType)) {
      return MatrixProcessedAttachment(
        matrix.MatrixVideoFile(
          bytes: attachment.data!,
          name: name,
          mimeType: attachment.mimeType,
          width: attachment.dimensions?.width.toInt(),
          height: attachment.dimensions?.height.toInt(),
          duration: attachment.length?.inMilliseconds,
        ),
        thumbnailFile: thumbnailImageFile,
        spoiler: attachment.spoiler,
      );
    }

    if (attachment.mimeType?.toLowerCase().startsWith('audio/') == true) {
      return MatrixProcessedAttachment(
        matrix.MatrixAudioFile(
          bytes: attachment.data!,
          name: name,
          mimeType: attachment.mimeType,
          duration: attachment.length?.inMilliseconds,
        ),
        thumbnailFile: thumbnailImageFile,
        spoiler: attachment.spoiler,
      );
    }

    return MatrixProcessedAttachment(
      matrix.MatrixFile(
        bytes: attachment.data!,
        name: name,
        mimeType: attachment.mimeType,
      ),
      thumbnailFile: thumbnailImageFile,
      spoiler: attachment.spoiler,
    );
  }

  String _spoilerFallbackBody(String text) {
    if (!text.contains('||')) {
      return text;
    }

    final result = StringBuffer();
    var cursor = 0;

    while (cursor < text.length) {
      final start = text.indexOf('||', cursor);
      if (start == -1) {
        result.write(text.substring(cursor));
        break;
      }

      final end = text.indexOf('||', start + 2);
      if (end == -1) {
        result.write(text.substring(cursor));
        break;
      }

      result.write(text.substring(cursor, start));

      final spoilerPayload = text.substring(start + 2, end);
      final reasonSeparator = spoilerPayload.indexOf('|');
      final reason = reasonSeparator > 0
          ? spoilerPayload.substring(0, reasonSeparator).trim()
          : '';
      result.write(reason.isEmpty ? '[spoiler]' : '[spoiler: $reason]');
      cursor = end + 2;
    }

    return result.toString();
  }

  @override
  Future<TimelineEvent?> sendMessage({
    String? message,
    TimelineEvent? inReplyTo,
    TimelineEvent? replaceEvent,
    String? threadRootEventId,
    String? threadLastEventId,
    Map<String, dynamic>? fileExtraContent,
    List<ProcessedAttachment>? processedAttachments,
  }) async {
    matrix.Event? replyingTo;

    if (inReplyTo != null) {
      replyingTo = await _matrixRoom.getEventById(inReplyTo.eventId);
    }

    if (processedAttachments != null) {
      await Future.wait(
        processedAttachments.whereType<MatrixProcessedAttachment>().map((e) {
          final extraContent = <String, dynamic>{
            ...?fileExtraContent,
            ...?matrixThreadRelationExtraContent(
              threadRootEventId: threadRootEventId,
              threadLastEventId: threadLastEventId,
            ),
            if (e.spoiler) 'chat.intergalactic.spoiler': true,
            if (e.spoiler) 'fi.mau.spoiler': true,
            if (e.spoiler) 'filename': e.file.name,
            if (e.spoiler) 'body': _spoilerFallbackBody(e.file.name),
            if (e.spoiler) 'format': 'org.matrix.custom.html',
            if (e.spoiler)
              'formatted_body':
                  '<span data-mx-spoiler="">${const HtmlEscape().convert(e.file.name)}</span>',
          };

          return _matrixRoom.sendFileEvent(
            e.file,
            threadLastEventId: threadLastEventId,
            threadRootEventId: threadRootEventId,
            extraContent: extraContent.isEmpty ? null : extraContent,
            thumbnail: e.thumbnailFile,
          );
        }),
      );
    }

    if (message != null && message.trim().isNotEmpty) {
      final event = <String, dynamic>{
        'msgtype': matrix.MessageTypes.Text,
        'body': _spoilerFallbackBody(message),
      };

      final potentialMentions = message
          .split('@')
          .map(
            (text) => text.startsWith('[')
                ? '@${text.split(']').first}]'
                : '@${text.split(RegExp(r'\s+')).first}',
          )
          .toList()
        ..removeAt(0);

      final hasRoomMention = potentialMentions.remove('@room');
      final mentionedUserIds = <String>{};
      for (final mention in potentialMentions) {
        final resolvedMention =
            mention.isValidMatrixId ? mention : resolveMention(mention);
        if (resolvedMention == null ||
            resolvedMention == _matrixRoom.client.userID) {
          continue;
        }

        mentionedUserIds.add(resolvedMention);
      }

      if (replyingTo != null) {
        if (replyingTo.senderId != _matrixRoom.client.userID) {
          mentionedUserIds.add(replyingTo.senderId);
        }
      }

      if (hasRoomMention || mentionedUserIds.isNotEmpty) {
        event['m.mentions'] = {
          if (hasRoomMention) 'room': true,
          if (mentionedUserIds.isNotEmpty)
            'user_ids': mentionedUserIds.toList(),
        };
      }

      var emoticons = getComponent<MatrixRoomEmoticonComponent>();
      final html = mx_markdown.markdown(
        message,
        getEmotePacks: emoticons != null
            ? () => emoticons.getEmotePacksFlat(matrix.ImagePackUsage.emoticon)
            : null,
        getMention: resolveMention,
      );

      if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
          event['body']) {
        event['format'] = 'org.matrix.custom.html';
        event['formatted_body'] = html;
      }

      final automaticEffect = detectAutomaticMessageEffect(
        message,
        enabled: replaceEvent == null &&
            preferences.messageEffectsEnabled.value &&
            preferences.automaticMessageEffectsEnabled.value,
      );
      if (automaticEffect != null) {
        _applyAutomaticMessageEffect(event, message, automaticEffect);
      }

      var id = await _matrixRoom.sendEvent(
        event,
        inReplyTo: replyingTo,
        editEventId: replaceEvent?.eventId,
        threadLastEventId: threadLastEventId,
        threadRootEventId: threadRootEventId,
      );

      if (id != null) {
        var event = await _matrixRoom.getEventById(id);
        if (event == null) {
          return null;
        }

        return convertEvent(event);
      }
    }

    return null;
  }

  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) {
    var c = client as MatrixClient;
    try {
      if (event.redacted) {
        return MatrixTimelineEventUnknown(event, client: c);
      }

      if (event.type == matrix.EventTypes.Message) {
        if (event.relationshipType == "m.replace")
          return MatrixTimelineEventEdit(event, client: c);
        if (event.content["chat.commet.type"] == "chat.commet.sticker" &&
            event.content['url'] is String)
          return MatrixTimelineEventSticker(event, client: c);

        if (event.messageType == "m.emote")
          return MatrixTimelineEventEmote(event, client: c);

        return MatrixTimelineEventMessage(event, client: c);
      }

      final result = switch (event.type) {
        matrix.EventTypes.Sticker =>
          event.content['url'] is String || event.content.containsKey('file')
              ? MatrixTimelineEventSticker(event, client: c)
              : null,
        matrix.EventTypes.Encrypted => MatrixTimelineEventEncrypted(
            event,
            client: c,
          ),
        matrix.EventTypes.RoomCreate => MatrixTimelineEventCreateRoom(
            event,
            client: c,
          ),
        matrix.EventTypes.Reaction => MatrixTimelineEventAddReaction(
            event,
            client: c,
          ),
        matrix.EventTypes.RoomMember => MatrixTimelineEventMembership(
            event,
            client: c,
          ),
        matrix.EventTypes.Redaction => MatrixTimelineEventRedaction(
            event,
            client: c,
          ),
        matrix.EventTypes.CallInvite => MatrixTimelineEventCall(
            event,
            client: c,
          ),
        matrix.EventTypes.CallAnswer => MatrixTimelineEventCall(
            event,
            client: c,
          ),
        matrix.EventTypes.CallHangup => MatrixTimelineEventCall(
            event,
            client: c,
          ),
        matrix.EventTypes.CallReject => MatrixTimelineEventCall(
            event,
            client: c,
          ),
        matrix.EventTypes.RoomPinnedEvents => MatrixTimelineEventPinnedMessages(
            event,
            client: c,
          ),
        "chat.commet.calendar_events" => MatrixTimelineEventEditCalendar(
            event,
            client: c,
          ),
        // Poll events are handled by the PollComponent display path.
        // Return null here so they fall through to MatrixTimelineEventUnknown,
        // which isPollEvent() can still identify by raw event type.
        "org.matrix.msc3381.poll.start" => null,
        "org.matrix.msc3381.poll.response" => null,
        "org.matrix.msc3381.poll.end" => null,
        _ => null,
      };

      if (result != null) {
        return result;
      } else {
        return MatrixTimelineEventUnknown(event, client: c);
      }
    } catch (err, trace) {
      Log.e(
        "Failed to parse Matrix event event=${_matrixRoomLogHash(event.eventId)} "
        "room=${_matrixRoomLogHash(event.roomId)} type=${event.type} "
        "error=${_matrixRoomLogError(err)}",
      );
      Log.onError(err, trace, content: "Failed to parse event: ${event.type}");
      return MatrixTimelineEventUnknown(event, client: c);
    }
  }

  @override
  Future<void> enableE2EE() async {
    await _matrixRoom.enableEncryption();
  }

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    _onUpdate.add(null);
    await _matrixRoom.setName(newName);
  }

  @override
  Color getColorOfUser(String userId) {
    return client.getComponent<UserColorComponent>()?.getColor(userId) ??
        MatrixPeer.hashColor(userId);
  }

  @override
  Future<TimelineEvent?> addReaction(
    TimelineEvent reactingTo,
    Emoticon reaction,
  ) async {
    var recent = client.getComponent<RecentEmoticonComponent>();
    recent?.reactedEmoticon(this, reaction);

    var id = await _matrixRoom.sendReaction(reactingTo.eventId, reaction.key);
    if (id != null) {
      var event = await _matrixRoom.getEventById(id);
      if (event == null) {
        return null;
      }

      return convertEvent(event);
    }

    return null;
  }

  @override
  Future<void> removeReaction(
    TimelineEvent reactingTo,
    Emoticon reaction,
  ) async {
    final currentTimeline = timeline;
    if (currentTimeline is! MatrixTimeline) {
      Log.w(
        "Unable to remove reaction because timeline is not initialized for $identifier",
      );
      return;
    }

    return currentTimeline.removeReaction(reactingTo, reaction);
  }

  @override
  T? getComponent<T extends RoomComponent>() {
    for (var component in _components) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T> getAllComponents<T extends RoomComponent<Client, Room>>() {
    return List.from(_components);
  }

  @override
  Future<void> close() async {
    await _onUpdate.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await timeline?.close();
  }

  @override
  Future<Timeline> getTimeline({String? contextEventId}) async {
    final matrixClient = client as MatrixClient;
    _timeline = MatrixTimeline(matrixClient, this, matrixRoom);
    await matrixClient.runWithSessionRepairOnUnknownToken(
      'loading room timeline for room=${_matrixRoomLogHash(matrixRoom.id)}',
      () => _timeline!.initTimeline(contextEventId: contextEventId),
    );
    onTimelineLoaded.add(null);
    return _timeline!;
  }

  @override
  Future<ImageProvider?> getShortcutImage() async {
    if (avatar != null) return avatar;

    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp?.isRoomDirectMessage(this) == true) {
      var user = await client.getComponent<UserProfileComponent>()!.getProfile(
            comp!.getDirectMessagePartnerId(this)!,
          );

      if (user.avatar != null) {
        return user.avatar;
      }
    }

    return client.spaces
        .where((space) => space.containsRoom(identifier))
        .firstOrNull
        ?.avatar;
  }

  @override
  Future<TimelineEvent?> getEvent(String eventId) async {
    var event =
        await (client as MatrixClient).runWithSessionRepairOnUnknownToken(
      'loading room event event=${_matrixRoomLogHash(eventId)} '
      'room=${_matrixRoomLogHash(_matrixRoom.id)}',
      () => _matrixRoom.getEventById(eventId),
    );
    if (event == null) {
      return null;
    }

    if (event.type == matrix.EventTypes.Encrypted) {
      try {
        await event.requestKey();
      } catch (error) {
        Log.i(
          "Failed to request room key for encrypted event "
          "event=${_matrixRoomLogHash(event.eventId)} "
          "room=${_matrixRoomLogHash(event.roomId)} "
          "error=${_matrixRoomLogError(error)}",
        );
      }
    }

    return convertEvent(event);
  }

  @override
  List<Member> membersList() {
    var users = _matrixRoom.getParticipants();
    return users.map(_memberFromUser).toList();
  }

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async {
    var results =
        await (client as MatrixClient).runWithSessionRepairOnUnknownToken(
      'loading room members for room=${_matrixRoomLogHash(_matrixRoom.id)}',
      () => _matrixRoom.requestParticipants(
        [matrix.Membership.join],
        true,
        cache,
      ),
    );

    return results.map(_memberFromUser).toList();
  }

  @override
  bool get isMembersListComplete => _matrixRoom.participantListComplete;

  @override
  Member getMemberOrFallback(String id) {
    return _memberFromUser(_matrixRoom.unsafeGetUserFromMemoryOrFallback(id));
  }

  @override
  Future<Member> fetchMember(String id) async {
    var member =
        await (client as MatrixClient).runWithSessionRepairOnUnknownToken(
      'loading room member user=${_matrixRoomLogHash(id)} '
      'room=${_matrixRoomLogHash(_matrixRoom.id)}',
      () => _matrixRoom.requestUser(id),
    );
    if (member != null) {
      return _memberFromUser(member);
    } else {
      return getMemberOrFallback(id);
    }
  }

  @override
  List<(Member, Role)> importantMembers() {
    var state = _matrixRoom.states["m.room.power_levels"]?[""];
    if (state == null) return [];

    var roles = (state.content["users"] as Map<String, dynamic>?);
    if (roles == null) return [];

    var ids = roles.keys;

    var result =
        ids.map((e) => (getMemberOrFallback(e), MatrixRole(roles[e]))).toList();

    result.removeWhere((element) => element.$2.rank == 0);

    result.sort((a, b) => b.$2.rank.compareTo(a.$2.rank));

    return result;
  }

  @override
  Role getMemberRole(String identifier) {
    return MatrixRole(_matrixRoom.getPowerLevelByUserId(identifier));
  }

  void onRoomStateUpdated(({String roomId, StrippedStateEvent state}) event) {
    _displayName = _matrixRoom.getLocalizedDisplayname();
    if (event.state.type == "m.room.name" ||
        event.state.type == "m.room.avatar" ||
        event.state.type == "m.room.topic" ||
        event.state.type == matrixRoomDisplayNamesStateEventType ||
        event.state.type == matrixRoomDisplayNamesLegacyStateEventType ||
        event.state.type == RoomEventSettings.stateEventType) {
      _onUpdate.add(null);
    }
  }

  @override
  Future<void> cancelSend(TimelineEvent event) async {
    if (event is! MatrixTimelineEvent) {
      Log.w(
        "Unable to cancel non-Matrix timeline event "
        "event=${_matrixRoomLogHash(event.eventId)}",
      );
      return;
    }

    await event.event.cancelSend();
  }

  @override
  Future<void> retrySend(TimelineEvent event) async {
    if (event is! MatrixTimelineEvent) {
      Log.w(
        "Unable to retry non-Matrix timeline event "
        "event=${_matrixRoomLogHash(event.eventId)}",
      );
      return;
    }

    await event.event.sendAgain();
  }

  @override
  Future<void> retryDecryptAll() async {
    final currentTimeline = timeline;
    if (currentTimeline is! MatrixTimeline) {
      return;
    }

    final matrixTimeline = currentTimeline.matrixTimeline;
    final encryption = (client as MatrixClient).getMatrixClient().encryption;
    if (matrixTimeline == null || encryption == null) {
      return;
    }

    var decryptedCount = 0;
    var requestedCount = 0;
    var updatedLastEvent = false;
    final requestedSessions = <String>{};
    final matrixEvents = matrixTimeline.events;
    for (var index = 0; index < matrixEvents.length; index++) {
      final event = matrixEvents[index];
      if (!_shouldRetryDecryptEvent(event)) {
        continue;
      }

      try {
        final retrySource = _decryptRetrySource(event);
        var decrypted = await encryption.decryptRoomEvent(
          retrySource,
          store: true,
          updateType: matrix.EventUpdateType.history,
        );

        if (_shouldRequestSessionForEvent(decrypted)) {
          final requested = await _requestMissingSessionKeyForEvent(
            decrypted,
            encryption,
            requestedSessions,
          );
          if (requested) {
            requestedCount++;
            decrypted = await encryption.decryptRoomEvent(
              retrySource,
              store: true,
              updateType: matrix.EventUpdateType.history,
            );
          }
        }

        if (decrypted.type == matrix.EventTypes.Encrypted) {
          continue;
        }

        matrixTimeline.removeAggregatedEvent(event);
        matrixEvents[index] = decrypted;
        matrixTimeline.addAggregatedEvent(decrypted);
        currentTimeline.onEventChanged(index);
        if (lastEvent?.eventId == event.eventId ||
            lastEvent?.eventId == decrypted.eventId) {
          lastEvent = convertEvent(decrypted, timeline: matrixTimeline);
          updatedLastEvent = true;
        }
        decryptedCount++;
      } catch (error) {
        Log.i(
          'retryDecryptAll: failed event=${_matrixRoomLogHash(event.eventId)} '
          'error=${_matrixRoomLogError(error)}',
        );
      }
    }

    if (decryptedCount > 0 || requestedCount > 0) {
      if (updatedLastEvent) {
        notifyUpdate();
      }
      Log.i(
        'retryDecryptAll: completed room=${_matrixRoomLogHash(identifier)} '
        'decrypted=$decryptedCount requested=$requestedCount',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
  }

  bool _shouldRetryDecryptEvent(matrix.Event event) {
    return event.type == matrix.EventTypes.Encrypted;
  }

  matrix.Event _decryptRetrySource(matrix.Event event) {
    final source = event.originalSource;
    return source is matrix.Event ? source : event;
  }

  bool _shouldRequestSessionForEvent(matrix.Event event) {
    return event.type == matrix.EventTypes.Encrypted &&
        event.messageType == matrix.MessageTypes.BadEncrypted &&
        event.content['can_request_session'] == true;
  }

  Future<bool> _requestMissingSessionKeyForEvent(
    matrix.Event event,
    dynamic encryption,
    Set<String> requestedSessions,
  ) async {
    final sessionId = event.content.tryGet<String>('session_id');
    final senderKey = event.content.tryGet<String>('sender_key');
    if (sessionId == null || senderKey == null) {
      return false;
    }

    final requestKey = '$sessionId|$senderKey';
    if (!requestedSessions.add(requestKey)) {
      return false;
    }

    await encryption.keyManager.request(
      _matrixRoom,
      sessionId,
      senderKey,
      tryOnlineBackup: true,
      onlineKeyBackupOnly: false,
    );
    return true;
  }

  @override
  bool get shouldPreviewMedia {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return preferences.previewMediaInPublicRooms.value;

      case matrix.JoinRules.knock:
      case matrix.JoinRules.invite:
      case matrix.JoinRules.private:
        return preferences.previewMediaInPrivateRooms.value;

      case matrix.JoinRules.restricted:
        if (_client.spaces.any(
          (e) =>
              e.visibility is RoomVisibilityPublic &&
              e.containsRoom(_matrixRoom.id),
        )) {
          // if any public space contains this room, consider the room public
          // this is kind of flawed, because there could be public spaces we are not a member of
          return preferences.previewMediaInPublicRooms.value;
        } else {
          return preferences.previewMediaInPrivateRooms.value;
        }

      default:
        return false;
    }
  }

  @override
  Member? getMember(String id) {
    final user = matrixRoom.getState(matrix.EventTypes.RoomMember, id);
    if (user != null) {
      return _memberFromUser(user.asUser(matrixRoom));
    }

    return null;
  }

  void onRoomSyncUpdate(matrix.SyncUpdate event) {
    var update = event.rooms?.join?[_matrixRoom.id];

    if (update == null) return;

    if (_matrixRoom.notificationCount == 0 && _hasRoomWideMentionNotification) {
      _hasRoomWideMentionNotification = false;
    }

    if (!_hasRoomWideMentionNotification &&
        update.timeline?.events?.any(_syncEventHasRoomMention) == true) {
      _hasRoomWideMentionNotification = true;
    }

    _onUpdate.add(null);
  }

  bool _syncEventHasRoomMention(matrix.MatrixEvent event) {
    final selfId = _matrixRoom.client.userID ?? _client.self?.identifier;
    if (event.senderId == selfId) {
      return false;
    }

    final content = event.content;
    final mentions = content['m.mentions'];
    return mentions is Map && mentions['room'] == true;
  }

  @override
  bool get isSpecialRoomType =>
      matrixRoom
          .getState(matrix.EventTypes.RoomCreate)
          ?.content
          .containsKey("type") ??
      false;

  @override
  Future<void> banUser(String id) {
    return matrixRoom.ban(id);
  }

  @override
  Future<void> kickUser(String id) {
    return matrixRoom.kick(id);
  }

  @override
  List<Role> get availableRoles => [
        MatrixRole(100),
        MatrixRole(50),
        if (getComponent<MatrixCalendarRoomComponent>()?.hasCalendar == true)
          MatrixRole(
            25,
            nameOverride: "Calendar Moderator",
            iconOverride: Icons.calendar_month,
          ),
        MatrixRole(0),
      ];

  @override
  Future<void> setMemberRole(String id, Role role) async {
    final changed =
        await _setMemberPowerLevel(id, (role as MatrixRole).powerLevel);

    if (changed) {
      await _matrixRoom.waitForRoomInSync();
    }
    _onUpdate.add(null);
  }

  Future<bool> _setMemberPowerLevel(String id, int powerLevel) async {
    final powerLevelState = _matrixRoom.getState(
      matrix.EventTypes.RoomPowerLevels,
    );
    final powerLevelContent =
        powerLevelState?.content.copy() ?? <String, Object?>{};
    final users = _copyPowerLevelUsers(powerLevelContent['users']);
    final immutableCreatorIds = _immutableCreatorIds;
    var removedCreatorEntries = 0;

    for (final creatorId in immutableCreatorIds) {
      if (users.remove(creatorId) != null) {
        removedCreatorEntries += 1;
      }
    }

    if (immutableCreatorIds.contains(id)) {
      final currentPowerLevel = _matrixRoom.getPowerLevelByUserId(id);
      final isAdminNoOp = currentPowerLevel > 100 && powerLevel >= 100;
      if (powerLevel != currentPowerLevel && !isAdminNoOp) {
        throw StateError(
          'Matrix room creators cannot be demoted in this room version. '
          'The server keeps creators at the maximum room privilege level.',
        );
      }

      if (removedCreatorEntries == 0) {
        return false;
      }
    } else {
      users[id] = powerLevel;
    }

    if (removedCreatorEntries > 0) {
      Log.i(
        'Removed immutable creator entries before updating room power levels '
        'room=${_matrixRoomLogHash(_matrixRoom.id)} '
        'removedCreators=$removedCreatorEntries '
        'target=${_matrixRoomLogHash(id)} '
        'targetPower=$powerLevel',
        category: LogCategory.matrix,
        source: 'room-permissions',
      );
    }

    powerLevelContent['users'] = users;
    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      matrix.EventTypes.RoomPowerLevels,
      '',
      powerLevelContent,
    );
    return true;
  }

  Set<String> get _immutableCreatorIds {
    final roomVersion = int.tryParse(_matrixRoom.roomVersion ?? '') ?? 0;
    if (roomVersion < 12) {
      return const <String>{};
    }

    return _matrixRoom.creatorUserIds;
  }

  Map<String, Object?> _copyPowerLevelUsers(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.from(value);
    }

    if (value is Map) {
      return value.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (value != null) {
      Log.w(
        'Repairing room power-level users map with invalid type '
        'type=${value.runtimeType}',
        category: LogCategory.matrix,
        source: 'room-permissions',
      );
    }

    return <String, Object?>{};
  }

  @override
  Future<void> setMemberNickname(String id, String? nickname) async {
    final selfId = _matrixRoom.client.userID ?? _client.self?.identifier;
    final isSelf = id == selfId;
    final canWriteRoomDisplayNames = _matrixRoom.canChangeStateEvent(
      matrixRoomDisplayNamesStateEventType,
    );
    final canWriteLegacyRoomDisplayNames = _matrixRoom.canChangeStateEvent(
      matrixRoomDisplayNamesLegacyStateEventType,
    );
    final canEditSelf =
        canWriteRoomDisplayNames || canWriteLegacyRoomDisplayNames;
    final canEditOthers = canEditSelf;

    if (isSelf ? !canEditSelf : !canEditOthers) {
      throw StateError(
        'Room display names require permission to edit '
        '$matrixRoomDisplayNamesStateEventType or '
        '$matrixRoomDisplayNamesLegacyStateEventType.',
      );
    }

    if (canWriteRoomDisplayNames) {
      await _setMemberRoomDisplayName(id, nickname, updatedBy: selfId);
      return;
    }

    if (canWriteLegacyRoomDisplayNames) {
      await _setLegacyMemberRoomDisplayName(id, nickname, updatedBy: selfId);
      return;
    }
  }

  @override
  String? get topic => matrixRoom.topic;

  @override
  Future<void> setTopic(String topic) async {
    await matrixRoom.setDescription(topic);
    _onUpdate.add(null);
  }

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {
    String name = "image";

    if (mimeType == null) mimeType = Mime.lookupType("", data: bytes);

    if (mimeType != null) {
      var extension = Mime.extensionFromMime(mimeType);
      name += ".$extension";
    }

    await matrixRoom.setAvatar(matrix.MatrixFile(bytes: bytes, name: name));
    _avatar = MemoryImage(bytes);
    _onUpdate.add(null);
  }

  @override
  Future<void> markAsRead() async {
    var tl = await matrixRoom.getTimeline();
    var readReceiptComponent = getComponent<MatrixReadReceiptComponent>();

    bool public = true;
    var presenceComp = client.getComponent<MatrixUserPresenceComponent>();

    if (presenceComp?.usePublicReadReceipts != null) {
      public = presenceComp!.usePublicReadReceipts;
    }

    if (readReceiptComponent?.usePublicReadReceiptsForRoom != null) {
      public = readReceiptComponent!.usePublicReadReceiptsForRoom!;
    }

    await tl.setReadMarker(public: public);
    if (_hasRoomWideMentionNotification) {
      _hasRoomWideMentionNotification = false;
      _onUpdate.add(null);
    }
  }

  @override
  RoomVisibility get visibility {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return RoomVisibilityPublic();
      case matrix.JoinRules.knock:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.invite:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.private:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.restricted:
        return RoomVisibilityRestricted(
          matrixRoom
                  .getState(matrix.EventTypes.RoomJoinRules)
                  ?.content
                  .tryGetList<Map<String, dynamic>>("allow")
                  ?.map((i) => i.tryGet<String>("room_id"))
                  .nonNulls
                  .toList() ??
              [],
        );
      case matrix.JoinRules.knockRestricted:
        return RoomVisibilityPrivate();
      case null:
        return RoomVisibilityPrivate();
    }
  }

  @override
  Future<void> setVisibility(RoomVisibility visibility) async {
    var state = switch (visibility) {
      final RoomVisibilityPrivate _ => matrix.StateEvent(
          content: {"join_rule": "invite"},
          type: matrix.EventTypes.RoomJoinRules,
        ),
      final RoomVisibilityPublic _ => matrix.StateEvent(
          content: {"join_rule": "public"},
          type: matrix.EventTypes.RoomJoinRules,
        ),
      final RoomVisibilityRestricted restricted => matrix.StateEvent(
          content: {
            "join_rule": "restricted",
            "allow": [
              for (var i in restricted.spaces)
                {"room_id": i, "type": "m.room_membership"},
            ],
          },
          type: matrix.EventTypes.RoomJoinRules,
        ),
      RoomVisibility() => throw UnimplementedError(),
    };

    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      state.type,
      "",
      state.content,
    );
  }
}
