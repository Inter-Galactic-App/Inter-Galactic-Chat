import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/components/message_effects/automatic_message_effects.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_formatting.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_types.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/component_registry.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/components/user_color/user_color_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/calendar_room_component/matrix_calendar_room_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:intergalactic/client/matrix/matrix_attachment.dart';
import 'package:intergalactic/client/matrix/matrix_bad_encrypted_recovery.dart';
import 'package:intergalactic/client/components/push_notification/notification_mode_policy.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_peer.dart';
import 'package:intergalactic/client/matrix/matrix_role.dart';
import 'package:intergalactic/client/matrix/matrix_room_display_name_state.dart';
import 'package:intergalactic/client/matrix/matrix_room_permissions.dart';
import 'package:intergalactic/client/matrix/push_rule_state_cache.dart';
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
import 'package:intergalactic/client/timeline_events/local_media_send_event.dart';
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
import 'package:matrix/encryption.dart' as matrix_crypto;

/// The event that decryption should be attempted against.
///
/// A stored decrypt failure keeps the original ciphertext in `originalSource`,
/// so retrying against the failure placeholder itself would never succeed.
matrix.Event matrixRoomDecryptSourceForEvent(matrix.Event event) {
  final source = event.originalSource;
  return source is matrix.Event ? source : event;
}

/// Loads a single room event for a read-only surface, decrypting it when the
/// room is encrypted.
///
/// The pinned SDK's `Room.getEventById` returns database-backed events
/// verbatim - only its network fallback path decrypts - so an event that is
/// already in the local store (the common case for anything that has been in
/// the timeline, such as a pinned message) comes back still encrypted. A
/// caller that reads one event by id therefore has to decrypt it itself.
///
/// This is read-side only: `decryptRoomEvent` is called with the default
/// `store: false`, so nothing is persisted, no room state is written and no
/// stored key material is created, changed or evicted.
///
/// Decryption failure is not an error here. The still-encrypted event is
/// returned so the caller renders exactly the placeholder it renders today,
/// and one undecryptable event cannot take out a batch of reads.
Future<matrix.Event?> matrixRoomLoadDecryptedEvent({
  required Future<matrix.Event?> Function() fetchEvent,
  required matrix_crypto.Encryption? encryption,
  void Function(String message, Object error)? onLog,
}) async {
  final event = await fetchEvent();
  if (event == null || event.type != matrix.EventTypes.Encrypted) {
    return event;
  }

  var result = event;
  if (encryption != null && encryption.enabled) {
    try {
      result = await encryption.decryptRoomEvent(
        matrixRoomDecryptSourceForEvent(event),
      );
    } catch (error) {
      onLog?.call('Failed to decrypt event for read', error);
      result = event;
    }

    if (result.type != matrix.EventTypes.Encrypted) {
      return result;
    }
  }

  // Still encrypted. Ask the sender for the room key so that a later read can
  // succeed - the same fallback `getEvent` has always used. `requestKey`
  // throws when the failure is not a requestable missing-session one, which is
  // an expected outcome rather than a fault.
  try {
    await result.requestKey();
  } catch (error) {
    onLog?.call('Failed to request room key for encrypted event', error);
  }

  return result;
}

typedef MatrixRoomSessionRequestInfo = ({String sessionId, String senderKey});

MatrixRoomSessionRequestInfo? matrixRoomSessionRequestInfoForBadEncryptedEvent(
  matrix.Event event,
) {
  if (!_matrixRoomHasRequestableBadEncryptedSessionFailure(event)) {
    return null;
  }

  return _matrixRoomSessionRequestInfoFromEvent(event) ??
      _matrixRoomSessionRequestInfoFromOriginalSource(event);
}

bool matrixRoomShouldRequestSessionForBadEncryptedEvent(matrix.Event event) {
  return matrixRoomSessionRequestInfoForBadEncryptedEvent(event) != null;
}

bool _matrixRoomHasRequestableBadEncryptedSessionFailure(matrix.Event event) {
  if (event.type != matrix.EventTypes.Encrypted ||
      event.messageType != matrix.MessageTypes.BadEncrypted) {
    return false;
  }

  if (matrixBadEncryptedEventHasStructuredSessionRequestSignal(event)) {
    return true;
  }

  return matrixBadEncryptedBodyMentionsRequestableSessionFailure(
    event.content['body']?.toString(),
  );
}

MatrixRoomSessionRequestInfo? _matrixRoomSessionRequestInfoFromEvent(
  matrix.Event event,
) {
  return _matrixRoomSessionRequestInfoFromContent(event.content);
}

MatrixRoomSessionRequestInfo? _matrixRoomSessionRequestInfoFromContent(
  Map<String, Object?> content,
) {
  final sessionId = content.tryGet<String>('session_id');
  final senderKey = content.tryGet<String>('sender_key');
  if (sessionId == null || senderKey == null) {
    return null;
  }
  return (sessionId: sessionId, senderKey: senderKey);
}

MatrixRoomSessionRequestInfo? _matrixRoomSessionRequestInfoFromOriginalSource(
  matrix.Event event,
) {
  final originalSource = event.originalSource;
  if (originalSource == null) {
    return null;
  }
  return _matrixRoomSessionRequestInfoFromContent(originalSource.content);
}

String _matrixRoomLogHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return MatrixClient.hash(text).substring(0, 12);
}

String _matrixRoomLogError(Object error) => error.runtimeType.toString();

const int _maxMemberProfileAvatarFallbacksPerRoom = 100;
const int _inboxCachedEventScanLimit = 250;

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
        'm.in_reply_to': {'event_id': threadLastEventId},
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

/// Returns users that should be shown in the room's elevated-member list.
///
/// Room versions 12 and newer make creators implicit maximum-power users, so
/// they are not required (and may be rejected) in `m.room.power_levels.users`.
Set<String> matrixImportantMemberIds({
  required Map<Object?, Object?>? explicitUsers,
  required Iterable<String> immutableCreatorIds,
}) {
  return {...?explicitUsers?.keys.whereType<String>(), ...immutableCreatorIds};
}

bool matrixRoomHasReplacementId(String? replacementRoomId) {
  return replacementRoomId != null && replacementRoomId.trim().isNotEmpty;
}

class MatrixRoom extends Room
    implements
        PushRuleCacheHolder,
        InboxRoomSource,
        InboxSnapshotProvider,
        RoomJoinRequestActions,
        RoomPendingInviteActions {
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
  String get localRoomId => localId;

  @override
  Stream<void> get onInboxSourceUpdate => onUpdate;

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
  int get highlightedNotificationCount =>
      _projectUnreadCount(_matrixRoom.highlightCount, highlighted: true);

  @override
  int get notificationCount =>
      _projectUnreadCount(_notificationCountWithoutProjection);

  int get _notificationCountWithoutProjection {
    final rawCount = _matrixRoom.notificationCount;
    if (rawCount <= 0) {
      return rawCount;
    }

    final latestReceiptMs =
        _matrixRoom.receiptState.global.latestOwnReceipt?.ts;
    final latestOwnReceiptAt = latestReceiptMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(latestReceiptMs, isUtc: true);
    final suppressed =
        _client
            .getComponent<StoryComponent>()
            ?.suppressedNotificationCountForRoom(
              roomId: identifier,
              latestOwnReceiptAt: latestOwnReceiptAt,
              rawNotificationCount: rawCount,
            ) ??
        0;
    return (rawCount - suppressed).clamp(0, rawCount).toInt();
  }

  int _projectUnreadCount(int rawCount, {bool highlighted = false}) {
    final projection = _readMarkerProjection;
    if (projection == null) return rawCount;
    if (!projection.orderKnown) return rawCount;
    final baseline = highlighted
        ? projection.highlightBaseline
        : projection.notificationBaseline;
    var newer = projection.newerNotifications.values
        .where((notification) => !highlighted || notification.highlighted)
        .length;
    // A cached newer message may already be in the SDK baseline even if its
    // notification callback was not delivered to this room wrapper. Preserve
    // at least one unread indication until the confirming sync in that case.
    if (rawCount > 0 &&
        newer == 0 &&
        (highlighted
            ? projection.hasNewerDirectMention
            : projection.hasNewerInboundMessage)) {
      newer = 1;
    }
    // The SDK count still includes notifications before the accepted marker.
    // Its increase captures a concurrent arrival even before onNotification
    // fires; the bounded event ledger covers a frozen Inbox target that was
    // already stale before this request began.
    if (rawCount > baseline) {
      return rawCount - baseline > newer ? rawCount - baseline : newer;
    }
    if (rawCount < baseline &&
        (newer > 0 ||
            projection.newerEventIds.isNotEmpty ||
            (_matrixRoom.lastEvent?.eventId != null &&
                _matrixRoom.lastEvent?.eventId !=
                    projection.lastEventIdAtConfirmation))) {
      return rawCount > newer ? rawCount : newer;
    }
    return newer;
  }

  _ReadMarkerProjection? _readMarkerProjection;
  // Kept only for this room's lifetime; event IDs are never persisted.
  final Map<String, _RecentNotification> _recentNotifications = {};
  int _notificationSequence = 0;

  Future<void> _confirmReadMarker(
    String targetEventId,
    int notificationBaseline,
    int highlightBaseline,
    int requestStartSequence,
    String previousMarkerEventId,
  ) async {
    final ordered = await _orderedEventsAround(targetEventId);
    final newerNotifications = <String, _RecentNotification>{};
    if (ordered != null) {
      for (final eventId in ordered.newer) {
        final notification = _recentNotifications[eventId];
        if (notification != null) newerNotifications[eventId] = notification;
      }
      for (final entry in _recentNotifications.entries) {
        if (entry.value.sequence > requestStartSequence &&
            entry.key != targetEventId &&
            !ordered.atOrBefore.contains(entry.key)) {
          newerNotifications[entry.key] = entry.value;
        }
      }
    }
    _readMarkerProjection = _ReadMarkerProjection(
      targetEventId,
      previousMarkerEventId,
      notificationBaseline,
      highlightBaseline,
      ordered != null,
      ordered?.newer ?? <String>{},
      ordered?.atOrBefore ?? <String>{},
      ordered?.hasNewerInboundMessage ?? false,
      ordered?.hasNewerDirectMention ?? false,
      newerNotifications,
      _matrixRoom.lastEvent?.eventId,
    );
    if (ordered != null) {
      _hasRoomWideMentionNotification = newerNotifications.values.any(
        (event) => event.roomMention,
      );
    }
    _onUpdate.add(null);
  }

  Future<
    ({
      Set<String> newer,
      Set<String> atOrBefore,
      bool hasNewerInboundMessage,
      bool hasNewerDirectMention,
    })?
  >
  _orderedEventsAround(String targetEventId) async {
    try {
      final events = await _matrixRoom.client.database.getEventList(
        _matrixRoom,
        limit: _inboxCachedEventScanLimit,
      );
      final newer = <String>{};
      final atOrBefore = <String>{};
      var hasNewerInboundMessage = false;
      var hasNewerDirectMention = false;
      var foundTarget = false;
      final selfId = _matrixRoom.client.userID ?? _client.self?.identifier;
      for (final event in events) {
        if (!event.status.isSynced) continue;
        if (foundTarget || event.eventId == targetEventId) {
          foundTarget = true;
          atOrBefore.add(event.eventId);
        } else {
          newer.add(event.eventId);
          if (event.senderId != selfId &&
              (event.type == matrix.EventTypes.Message ||
                  event.type == matrix.EventTypes.Sticker)) {
            hasNewerInboundMessage = true;
            if (event.mentions.room ||
                (selfId != null && event.mentions.userIds.contains(selfId))) {
              hasNewerDirectMention = true;
            }
          }
        }
      }
      if (foundTarget) {
        return (
          newer: newer,
          atOrBefore: atOrBefore,
          hasNewerInboundMessage: hasNewerInboundMessage,
          hasNewerDirectMention: hasNewerDirectMention,
        );
      }
    } catch (_) {
      // The marker succeeded, but without ordering evidence we must preserve
      // SDK counts rather than risk hiding an unread event.
    }
    return null;
  }

  bool _hasRoomWideMentionNotification = false;
  final Set<String> _membershipKnockNotificationEventIds = <String>{};

  /// User ids that currently have a raised in-app join-request alert for this
  /// room, so the reconcile pass can clear alerts for requests that were
  /// approved, declined, or withdrawn.
  final Set<String> _knockRequestAlertUserIds = <String>{};
  final Map<String, Uri> _memberProfileAvatarFallbacks = <String, Uri>{};
  final Set<String> _memberProfileAvatarFallbackRequests = <String>{};
  final Set<String> _memberProfileAvatarFallbackChecked = <String>{};
  bool _memberProfileAvatarFallbackLimitReached = false;

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
  late final PushRuleStateCache _pushRuleCache = PushRuleStateCache(
    _readPushRuleState,
  );
  @override
  PushRule get pushRule {
    switch (_pushRuleCache.value) {
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
    _pushRuleCache.assign(newRule);
    _onUpdate.add(null);
  }

  /// Drops the cached push-rule state so the next read reflects synced rules.
  ///
  /// The cache was previously invalidated only by a local [setPushRule] on this
  /// instance, so a rule set on another device - or on a different wrapper for
  /// the same room - left this one reporting the state it first read. That is
  /// BUG-319. Returns whether the state actually changed, so a sync carrying
  /// `m.push_rules` does not rebuild every room for nothing.
  @override
  bool invalidatePushRuleCache() {
    if (!_pushRuleCache.invalidate()) {
      return false;
    }
    _onUpdate.add(null);
    return true;
  }

  @override
  RoomNotificationSnooze? get notificationSnooze =>
      _client.roomNotificationSnoozes.get(_matrixRoom.id);

  @override
  Future<void> setNotificationSnooze(
    Duration duration, {
    String source = 'room_settings',
  }) => _client.roomNotificationSnoozes.set(
    _matrixRoom.id,
    duration,
    source: source,
  );

  @override
  Future<void> clearNotificationSnooze() =>
      _client.roomNotificationSnoozes.clear(_matrixRoom.id);

  void notifyNotificationSnoozeChanged() {
    if (!_onUpdate.isClosed) {
      _onUpdate.add(null);
    }
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
    final currentState = _pushRuleCache.value;
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

    // Surface any knock request that was already pending when this room was
    // constructed (e.g. loaded at launch before a new membership event
    // arrives). onEvent only reconciles on live membership events, so without
    // this a pre-existing request would not raise its alert until the next one.
    // Safe/idempotent: no-ops when the alert manager is absent or the room is
    // not an approvable knock room.
    reconcileKnockRequestAlerts();
  }

  String? _readLegacyMemberRoomDisplayName(String id) {
    final state =
        _matrixRoom.getState(
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
    final avatarUrl = _avatarUrlForMember(user);
    if (avatarUrl == null) {
      _scheduleMemberProfileAvatarFallback(user);
    }

    return MatrixMember(
      _client,
      user,
      roomDisplayName: getMemberRoomDisplayName(user.id),
      avatarUrl: avatarUrl,
    );
  }

  Uri? _avatarUrlForMember(matrix.User user) {
    if (user.avatarUrl != null) {
      _memberProfileAvatarFallbacks.remove(user.id);
      return user.avatarUrl;
    }

    return _memberProfileAvatarFallbacks[user.id];
  }

  void _scheduleMemberProfileAvatarFallback(matrix.User user) {
    unawaited(_ensureMemberProfileAvatarFallback(user));
  }

  Future<void> _ensureMemberProfileAvatarFallback(matrix.User user) {
    if (!shouldHydrateMissingMemberAvatarsForJoinRules(_matrixRoom.joinRules) ||
        user.membership != matrix.Membership.join ||
        user.avatarUrl != null ||
        !user.id.isValidMatrixId ||
        _memberProfileAvatarFallbacks.containsKey(user.id) ||
        _memberProfileAvatarFallbackChecked.contains(user.id) ||
        _memberProfileAvatarFallbackLimitReached) {
      return Future<void>.value();
    }

    final attemptedIds = <String>{
      ..._memberProfileAvatarFallbacks.keys,
      ..._memberProfileAvatarFallbackChecked,
      ..._memberProfileAvatarFallbackRequests,
    };
    if (attemptedIds.length >= _maxMemberProfileAvatarFallbacksPerRoom) {
      _memberProfileAvatarFallbackLimitReached = true;
      return Future<void>.value();
    }

    if (!_memberProfileAvatarFallbackRequests.add(user.id)) {
      return Future<void>.value();
    }

    return _hydrateMemberProfileAvatarFallback(user.id);
  }

  Future<void> _hydrateMemberProfileAvatarFallback(String userId) async {
    try {
      final profile = await _matrixRoom.client.getUserProfile(userId);
      final avatarUrl = profile.avatarUrl;
      if (avatarUrl == null) {
        return;
      }

      final previous = _memberProfileAvatarFallbacks[userId];
      if (previous == avatarUrl) {
        return;
      }

      _memberProfileAvatarFallbacks[userId] = avatarUrl;
      _onUpdate.add(null);
    } catch (_) {
      // Keep room/member rendering best-effort. Missing profile permission or
      // network failures should leave the default avatar without surfacing UI
      // errors.
    } finally {
      _memberProfileAvatarFallbackRequests.remove(userId);
      _memberProfileAvatarFallbackChecked.add(userId);
    }
  }

  bool get _hasMissingHydratableMemberAvatars {
    if (!shouldHydrateMissingMemberAvatarsForJoinRules(_matrixRoom.joinRules) ||
        _memberProfileAvatarFallbackLimitReached) {
      return false;
    }

    return _matrixRoom
        .getParticipants([matrix.Membership.join])
        .any(
          (user) =>
              user.avatarUrl == null &&
              user.id.isValidMatrixId &&
              !_memberProfileAvatarFallbacks.containsKey(user.id) &&
              !_memberProfileAvatarFallbackChecked.contains(user.id),
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

    final event = convertEvent(matrixEvent);
    if (event is MatrixTimelineEventMembership) {
      await handleMembershipKnockNotification(event);
      reconcileKnockRequestAlerts();
    }

    if (matrixEvent.type == matrix.EventTypes.Message) {
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
    final selfId = _matrixRoom.client.userID ?? _client.self?.identifier;
    final notification = _RecentNotification(
      ++_notificationSequence,
      matrixEvent.mentions.room ||
          (selfId != null && matrixEvent.mentions.userIds.contains(selfId)),
      matrixEvent.mentions.room,
    );
    _recentNotifications[matrixEvent.eventId] = notification;
    if (_recentNotifications.length > 128) {
      _recentNotifications.remove(_recentNotifications.keys.first);
    }
    final projection = _readMarkerProjection;
    if (projection != null &&
        projection.orderKnown &&
        matrixEvent.eventId != projection.targetEventId &&
        !projection.atOrBeforeEventIds.contains(matrixEvent.eventId)) {
      projection.newerNotifications[matrixEvent.eventId] = notification;
      if (projection.newerNotifications.length > 128) {
        projection.orderKnown = false;
        projection.newerNotifications.clear();
      }
      _onUpdate.add(null);
    }
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

    if (event is MatrixTimelineEventMembership) {
      await handleMembershipKnockNotification(event);
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

  Future<void> handleMembershipKnockNotification(
    MatrixTimelineEventMembership event,
  ) async {
    if (!shouldNotifyMembershipKnock(event)) {
      return;
    }

    if (!_membershipKnockNotificationEventIds.add(event.eventId)) {
      return;
    }
    if (_membershipKnockNotificationEventIds.length > 128) {
      _membershipKnockNotificationEventIds.remove(
        _membershipKnockNotificationEventIds.first,
      );
    }

    try {
      final notification =
          await RoomMembershipNotificationContent.fromKnockEvent(event, this);
      if (notification != null) {
        NotificationManager.notify(notification);
      }
    } catch (error, trace) {
      _membershipKnockNotificationEventIds.remove(event.eventId);
      Log.onError(
        error,
        trace,
        content: 'Failed to surface room knock membership notification',
        category: LogCategory.matrix,
        source: 'room-membership-notification',
      );
    }
  }

  /// The mode that actually governs this room's account.
  ///
  /// NOT `preferences.notificationMode.value`. That preference is device-wide,
  /// so reading it raw made muting one account silence every other signed-in
  /// account, and made a migrated account obey a local value the server had
  /// already overridden. For a migrated account the SERVER master rule decides,
  /// which is both per-account and the same on every device.
  NotificationMode get _effectiveNotificationMode {
    final matrixClient = client as MatrixClient;
    final isMigrated = preferences.isGlobalMutePushRuleMigrated(
      matrixClient.identifier,
    );
    return resolveNotificationMode(
      isMigrated: isMigrated,
      serverMuted:
          isMigrated &&
          matrixClient.getMatrixClient().allPushNotificationsMuted,
      enableNotifications: preferences.enableNotifications.value,
      localModeValue: preferences.notificationMode.value,
    );
  }

  bool shouldNotifyMembershipKnock(MatrixTimelineEventMembership event) {
    if (!BuildConfig.DESKTOP) {
      return false;
    }

    if (!event.isKnockEvent) {
      return false;
    }

    if ((client as MatrixClient).firstSyncComplete == false) {
      return false;
    }

    if (clientManager?.clients.any(
          (element) => element.self?.identifier == event.senderId,
        ) ==
        true) {
      return false;
    }

    if (DateTime.now().difference(event.originServerTs).inMinutes > 10) {
      return false;
    }

    final notificationMode = _effectiveNotificationMode;
    if (notificationMode == NotificationMode.mute ||
        notificationMode == NotificationMode.mentions) {
      return false;
    }

    return pushRule == PushRule.notify;
  }

  /// Keeps the in-app "!" alert list in sync with the room's pending knock
  /// join requests. Idempotent: it raises one alert per outstanding request
  /// (keyed by room+user) and clears alerts for requests that have since been
  /// approved, declined, or withdrawn. Safe to call on every membership event.
  void reconcileKnockRequestAlerts() {
    final manager = clientManager?.alertManager;
    if (manager == null) {
      return;
    }

    final canApprove = permissions.canInviteUser;
    final joinRules = _matrixRoom.joinRules;
    final isKnockRoom =
        joinRules == matrix.JoinRules.knock ||
        joinRules == matrix.JoinRules.knockRestricted;

    if (!canApprove || !isKnockRoom) {
      _clearAllKnockRequestAlerts(manager);
      return;
    }

    final currentIds = <String>{};
    for (final member in joinRequestsList()) {
      final userId = member.identifier;
      currentIds.add(userId);
      if (_knockRequestAlertUserIds.contains(userId)) {
        continue;
      }
      final displayNameForMessage = member.displayName;
      manager.addAlert(
        Alert(
          AlertType.info,
          id: _knockRequestAlertId(userId),
          titleGetter: () => 'Join request',
          messageGetter: () =>
              '$displayNameForMessage asked to join $displayName',
          dismissible: false,
          actionLabel: 'Accept',
          action: (_) => _acceptKnockRequestFromAlert(userId),
        ),
      );
    }

    final resolved = _knockRequestAlertUserIds.difference(currentIds);
    for (final userId in resolved) {
      manager.clearAlertsById(_knockRequestAlertId(userId));
    }

    _knockRequestAlertUserIds
      ..clear()
      ..addAll(currentIds);
  }

  void _clearAllKnockRequestAlerts(AlertManager manager) {
    if (_knockRequestAlertUserIds.isEmpty) {
      return;
    }
    for (final userId in _knockRequestAlertUserIds) {
      manager.clearAlertsById(_knockRequestAlertId(userId));
    }
    _knockRequestAlertUserIds.clear();
  }

  String _knockRequestAlertId(String userId) {
    return 'knock-request-${MatrixClient.hash(identifier)}-'
        '${MatrixClient.hash(userId)}';
  }

  void _acceptKnockRequestFromAlert(String userId) {
    unawaited(() async {
      try {
        await approveJoinRequest(userId);
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to approve knock join request from alert',
          category: LogCategory.matrix,
          source: 'room-membership-notification',
        );
      }
    }());
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

    final notificationMode = _effectiveNotificationMode;
    if (notificationMode == NotificationMode.mute) {
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

    if (notificationMode == NotificationMode.mentions) {
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

      final potentialMentions =
          message
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
        final resolvedMention = mention.isValidMatrixId
            ? mention
            : resolveMention(mention);
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
        enabled:
            replaceEvent == null &&
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

  /// Sends a forward with already-normalized content. Unlike [sendMessage],
  /// this never derives Matrix mentions from text: attribution is visual-only
  /// and must not notify the original author.
  ///
  /// Each call targets one destination and must use that destination's stable
  /// transaction ID. Attachments are processed afresh here before the SDK
  /// encrypts and uploads them for this room.
  Future<String?> sendForwardedMessage({
    required MatrixForwardedMessage message,
    required String transactionId,
  }) async {
    if (!permissions.canSendMessage) {
      throw StateError('Cannot send a message to this room.');
    }

    if (!message.hasAttachments) {
      return _matrixRoom.sendEvent(
        Map<String, dynamic>.from(message.textContent),
        txid: transactionId,
      );
    }

    String? firstEventId;
    for (var index = 0; index < message.attachments.length; index++) {
      final pending = message.attachments[index].toPendingAttachment();
      final processed = await processAttachment(pending);
      if (processed == null) {
        throw StateError('Unable to process a forwarded attachment.');
      }
      // Matrix transaction IDs identify one event. Keep the stable destination
      // attempt ID for a single attachment and derive deterministic siblings
      // if a later source type exposes more than one attachment.
      final attachmentTxid = index == 0
          ? transactionId
          : '$transactionId-forward-$index';
      final eventId = await _matrixRoom.sendFileEvent(
        processed.file,
        txid: attachmentTxid,
        thumbnail: processed.thumbnailFile,
        extraContent: {
          ...message.attachmentExtraContent,
          if (processed.spoiler) 'chat.intergalactic.spoiler': true,
          if (processed.spoiler) 'fi.mau.spoiler': true,
        },
      );
      firstEventId ??= eventId;
      if (eventId == null) {
        return null;
      }
    }
    return firstEventId;
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
    for (final component in _components) {
      // Active calls can outlive room-view teardown for mobile backgrounding
      // and PiP, so VoIP room ownership stays with the call manager.
      if (component is! DisposableComponent || component is VoipRoomComponent) {
        continue;
      }

      try {
        await (component as DisposableComponent).dispose();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to dispose Matrix room component before room close',
        );
      }
    }

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await timeline?.close();
    await _onUpdate.close();
    await onTimelineLoaded.close();
  }

  @override
  Future<Timeline> getTimeline({String? contextEventId}) async {
    final matrixClient = client as MatrixClient;
    _timeline = MatrixTimeline(matrixClient, this, matrixRoom);
    await matrixClient.runWithSessionRepairOnUnknownToken(
      'loading room timeline for room=${_matrixRoomLogHash(matrixRoom.id)}',
      () => _timeline!.initTimeline(contextEventId: contextEventId),
    );
    if (!onTimelineLoaded.isClosed) {
      onTimelineLoaded.add(null);
    }
    return _timeline!;
  }

  @override
  Future<RoomTimelineLease> getTimelineForEventContext(
    String contextEventId,
  ) async {
    final matrixClient = client as MatrixClient;
    final contextTimeline = MatrixTimeline(matrixClient, this, matrixRoom);
    return RoomTimelineLease.initializeOwned(
      contextTimeline,
      () => matrixClient.runWithSessionRepairOnUnknownToken(
        'loading event-context timeline for room=${_matrixRoomLogHash(matrixRoom.id)}',
        () => contextTimeline.initTimeline(contextEventId: contextEventId),
      ),
    );
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
    var event = await _fetchMatrixEventById(eventId);
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

  Future<matrix.Event?> _fetchMatrixEventById(String eventId) {
    return (client as MatrixClient).runWithSessionRepairOnUnknownToken(
      'loading room event event=${_matrixRoomLogHash(eventId)} '
      'room=${_matrixRoomLogHash(_matrixRoom.id)}',
      () => _matrixRoom.getEventById(eventId),
    );
  }

  @override
  Future<TimelineEvent?> getDecryptedEvent(String eventId) async {
    final event = await matrixRoomLoadDecryptedEvent(
      fetchEvent: () => _fetchMatrixEventById(eventId),
      encryption: (client as MatrixClient).getMatrixClient().encryption,
      onLog: (message, error) => Log.i(
        "$message "
        "event=${_matrixRoomLogHash(eventId)} "
        "room=${_matrixRoomLogHash(_matrixRoom.id)} "
        "error=${_matrixRoomLogError(error)}",
      ),
    );

    if (event == null) {
      return null;
    }

    return convertEvent(event);
  }

  @override
  Future<InboxRoomSnapshot?> getInboxSnapshot() async {
    final visibleUnreadCount = displayNotificationCount > 0
        ? displayNotificationCount
        : displayHighlightedNotificationCount;
    if (visibleUnreadCount <= 0 || pushRule == PushRule.dontNotify) {
      return null;
    }

    // This reads only events already persisted by the Matrix SDK. It must not
    // create a MatrixTimeline: that mutates the active room timeline and can
    // trigger history loading/decryption work for every Inbox room.
    final cachedEvents = await _matrixRoom.client.database.getEventList(
      _matrixRoom,
      limit: _inboxCachedEventScanLimit,
    );
    final activeTimeline = timeline;
    // The SDK's m.fully_read cache can lag a successful marker request. Use
    // the same accepted target as the optimistic count projection so older
    // messages cannot re-enter the Inbox mention filter during that gap.
    final fullyReadEventId =
        _readMarkerProjection?.targetEventId ?? _matrixRoom.fullyRead;
    final selfId = _matrixRoom.client.userID;

    InboxEventSnapshot? newestUnread;
    InboxEventSnapshot? newestDirectMention;
    String? readTargetEventId;
    // The loop below depends on `getEventList` ordering, which is a property of
    // the SDK rather than something this code can assert: the local SENDING
    // fragment is emitted first, then the synced timeline fragment
    // **newest-first** (the store inserts each new event at index 0). Every
    // `??=` here therefore means "the newest one seen", and the `break` on
    // `fullyRead` means "stop at the read marker" only because everything after
    // it is older. Note also that `limit` bounds the synced slice only - the
    // sending events are added on top of it - which is why the `EventStatus`
    // filter is the first thing in the body. If the SDK's ordering changes,
    // this loop inverts silently and Inbox reports the oldest unread instead of
    // the newest. Verified against commetchat/matrix-dart-sdk
    // `upstream-v6.1.1` (`matrix_sdk_database.dart`) and the drift store used
    // here (`matrix_dart_sdk_drift_db`), which build the same order.
    for (final event in cachedEvents) {
      // Sending/sent local echoes are prepended by the SDK database. They are
      // not inbound unread content and cannot become a read-marker target.
      if (event.status != matrix.EventStatus.synced) {
        continue;
      }
      if (fullyReadEventId.isNotEmpty && event.eventId == fullyReadEventId) {
        break;
      }
      readTargetEventId ??= event.eventId;
      if (event.type != matrix.EventTypes.Message) {
        continue;
      }

      // Stored encrypted events participate only after the SDK has already
      // decrypted and persisted their message content. Inbox never requests a
      // key or retries decryption in the background.
      final timelineEvent = convertEvent(event);
      final isDirectMention =
          selfId != null &&
          InboxEventSnapshot.isStructuredDirectMention(
            mentionedUserIds: event.mentions.userIds,
            selfId: selfId,
          );
      final snapshot = InboxEventSnapshot(
        eventId: event.eventId,
        timestamp: event.originServerTs,
        senderId: event.senderId,
        plainTextBody: timelineEvent.plainTextBody,
        isDirectMention: isDirectMention,
        cachedImagePreview: _inboxCachedImagePreview(timelineEvent),
        cachedUrlPreview: _inboxCachedUrlPreview(timelineEvent),
        loadUrlPreview: _inboxUrlPreviewLoader(timelineEvent, activeTimeline),
      );
      newestUnread ??= snapshot;
      if (isDirectMention) {
        newestDirectMention ??= snapshot;
      }
    }

    if (newestUnread == null) {
      return null;
    }
    return InboxRoomSnapshot(
      clientIdentifier: client.identifier,
      roomId: identifier,
      roomName: displayName,
      unreadCount: visibleUnreadCount,
      isSidebarEligible: true,
      readTargetEventId: readTargetEventId!,
      newestUnreadEvent: newestUnread,
      newestDirectMention: newestDirectMention,
    );
  }

  ImageProvider? _inboxCachedImagePreview(TimelineEvent event) {
    if (event is! TimelineEventMessage) return null;
    final attachment = event.attachments?.firstOrNull;
    if (attachment is ImageAttachment && !attachment.spoiler) {
      return attachment.image;
    }
    if (attachment is VideoAttachment && !attachment.spoiler) {
      return attachment.thumbnail;
    }
    return null;
  }

  UrlPreviewData? _inboxCachedUrlPreview(TimelineEvent event) {
    final activeTimeline = timeline;
    if (activeTimeline == null) return null;

    // This only interrogates URL preview data already owned by the active
    // timeline. It does not create a timeline or call getPreview/warm APIs.
    return client.getComponent<UrlPreviewComponent>()?.getCachedPreview(
      activeTimeline,
      event,
    );
  }

  Future<UrlPreviewData?> Function()? _inboxUrlPreviewLoader(
    TimelineEvent event,
    Timeline? activeTimeline,
  ) {
    if (event is! TimelineEventMessage) return null;

    final component = client.getComponent<UrlPreviewComponent>();
    // Keep the same consent boundary as the timeline. In particular, a locked
    // Inbox card cannot use this callback because its widget never invokes it,
    // and an encrypted room remains opt-in through the existing component.
    if (component == null || !component.shouldGetPreviewsInRoom(this)) {
      return null;
    }

    // When the room already has a timeline, use its display-event projection
    // so an edit or relation cannot fetch a link from superseded content.
    final uri = event.getLinks(timeline: activeTimeline)?.firstOrNull;
    if (uri == null) return null;

    return () => component.getPreviewForUrl(this, uri);
  }

  @override
  Future<void> markInboxSnapshotRead(InboxRoomSnapshot snapshot) async {
    if (snapshot.clientIdentifier != client.identifier ||
        snapshot.roomId != identifier) {
      throw ArgumentError.value(
        snapshot.localRoomId,
        'snapshot',
        'Inbox snapshot does not belong to this Matrix room.',
      );
    }

    final notificationBaseline = _notificationCountWithoutProjection;
    final highlightBaseline = _matrixRoom.highlightCount;
    final requestStartSequence = _notificationSequence;
    final previousMarkerEventId = _matrixRoom.fullyRead;
    final public = _readMarkerIsPublic();
    await _matrixRoom.setReadMarker(
      snapshot.readTargetEventId,
      mRead: snapshot.readTargetEventId,
      public: public,
    );
    await _confirmReadMarker(
      snapshot.readTargetEventId,
      notificationBaseline,
      highlightBaseline,
      requestStartSequence,
      previousMarkerEventId,
    );
  }

  @override
  List<Member> membersList() {
    var users = _matrixRoom.getParticipants([matrix.Membership.join]);
    return users.map(_memberFromUser).toList();
  }

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async {
    var results = await (client as MatrixClient)
        .runWithSessionRepairOnUnknownToken(
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
  List<Member> joinRequestsList() {
    final users = _matrixRoom.getParticipants([matrix.Membership.knock]);
    return users.map(_memberFromUser).toList();
  }

  @override
  Future<List<Member>> fetchJoinRequests({bool cache = false}) async {
    final results = await (client as MatrixClient)
        .runWithSessionRepairOnUnknownToken(
          'loading room join requests for room=${_matrixRoomLogHash(_matrixRoom.id)}',
          () => _matrixRoom.requestParticipants(
            [matrix.Membership.knock],
            true,
            cache,
          ),
        );

    return results.map(_memberFromUser).toList();
  }

  @override
  List<Member> pendingInvitesList() {
    final users = _matrixRoom.getParticipants([matrix.Membership.invite]);
    return users.map(_memberFromUser).toList();
  }

  @override
  Future<List<Member>> fetchPendingInvites({bool cache = false}) async {
    final results = await (client as MatrixClient)
        .runWithSessionRepairOnUnknownToken(
          'loading room pending invites for room=${_matrixRoomLogHash(_matrixRoom.id)}',
          () => _matrixRoom.requestParticipants(
            [matrix.Membership.invite],
            true,
            cache,
          ),
        );

    return results.map(_memberFromUser).toList();
  }

  @override
  Future<void> revokePendingInvite(String id) {
    return matrixRoom.kick(id);
  }

  @override
  bool get isMembersListComplete =>
      _matrixRoom.participantListComplete &&
      !_hasMissingHydratableMemberAvatars;

  @override
  Member getMemberOrFallback(String id) {
    return _memberFromUser(_matrixRoom.unsafeGetUserFromMemoryOrFallback(id));
  }

  @override
  Future<Member> fetchMember(String id) async {
    var member = await (client as MatrixClient)
        .runWithSessionRepairOnUnknownToken(
          'loading room member user=${_matrixRoomLogHash(id)} '
          'room=${_matrixRoomLogHash(_matrixRoom.id)}',
          () => _matrixRoom.requestUser(id),
        );
    if (member != null) {
      await _ensureMemberProfileAvatarFallback(member);
      return _memberFromUser(member);
    } else {
      return getMemberOrFallback(id);
    }
  }

  @override
  List<(Member, Role)> importantMembers() {
    var state = _matrixRoom.states["m.room.power_levels"]?[""];
    final rawRoles = state?.content["users"];
    final roles = rawRoles is Map ? Map<Object?, Object?>.from(rawRoles) : null;
    final ids = matrixImportantMemberIds(
      explicitUsers: roles,
      immutableCreatorIds: _immutableCreatorIds,
    );
    if (ids.isEmpty) return [];

    var result = ids
        .map((e) => (getMemberOrFallback(e), getMemberRole(e)))
        .toList();

    result.removeWhere((element) => (element.$2 as MatrixRole).rank == 0);

    result.sort(
      (a, b) => (b.$2 as MatrixRole).rank.compareTo((a.$2 as MatrixRole).rank),
    );

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
    if (event is LocalMediaSendEvent) {
      await event.cancelSend();
      return;
    }

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
    if (event is LocalMediaSendEvent) {
      await event.retrySend();
      return;
    }

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
    return matrixRoomDecryptSourceForEvent(event);
  }

  bool _shouldRequestSessionForEvent(matrix.Event event) {
    return matrixRoomSessionRequestInfoForBadEncryptedEvent(event) != null;
  }

  Future<bool> _requestMissingSessionKeyForEvent(
    matrix.Event event,
    dynamic encryption,
    Set<String> requestedSessions,
  ) async {
    final requestInfo = matrixRoomSessionRequestInfoForBadEncryptedEvent(event);
    if (requestInfo == null) {
      return false;
    }

    final requestKey = '${requestInfo.sessionId}|${requestInfo.senderKey}';
    if (!requestedSessions.add(requestKey)) {
      return false;
    }

    await encryption.keyManager.request(
      _matrixRoom,
      requestInfo.sessionId,
      requestInfo.senderKey,
      tryOnlineBackup: true,
      onlineKeyBackupOnly: false,
    );
    return true;
  }

  @override
  bool get shouldPreviewMedia {
    final isRestrictedLike =
        _matrixRoom.joinRules == matrix.JoinRules.restricted ||
        _matrixRoom.joinRules == matrix.JoinRules.knockRestricted;
    final isContainedInPublicSpace =
        isRestrictedLike &&
        _client.spaces.any(
          (e) =>
              e.visibility is RoomVisibilityPublic &&
              e.containsRoom(_matrixRoom.id),
        );

    return shouldPreviewMediaForJoinRules(
      _matrixRoom.joinRules,
      previewPublicRooms: preferences.previewMediaInPublicRooms.value,
      previewPrivateRooms: preferences.previewMediaInPrivateRooms.value,
      containedInPublicSpace: isContainedInPublicSpace,
    );
  }

  static bool shouldPreviewMediaForJoinRules(
    matrix.JoinRules? joinRules, {
    required bool previewPublicRooms,
    required bool previewPrivateRooms,
    required bool containedInPublicSpace,
  }) {
    switch (joinRules) {
      case matrix.JoinRules.public:
        return previewPublicRooms;

      case matrix.JoinRules.knock:
      case matrix.JoinRules.invite:
      case matrix.JoinRules.private:
        return previewPrivateRooms;

      case matrix.JoinRules.restricted:
      case matrix.JoinRules.knockRestricted:
        if (containedInPublicSpace) {
          // if any public space contains this room, consider the room public
          // this is kind of flawed, because there could be public spaces we are not a member of
          return previewPublicRooms;
        } else {
          return previewPrivateRooms;
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

    final projection = _readMarkerProjection;
    if (projection != null) {
      final reportedMarker = update.accountData
          ?.lastWhereOrNull((event) => event.type == 'm.fully_read')
          ?.content['event_id'];
      final markerChangedElsewhere =
          reportedMarker is String &&
          reportedMarker != projection.targetEventId &&
          reportedMarker != projection.previousMarkerEventId;
      final markerConfirmed =
          reportedMarker == projection.targetEventId ||
          _matrixRoom.fullyRead == projection.targetEventId;
      final unread = update.unreadNotifications;
      final syncedNotifications = unread?.notificationCount;
      final syncedHighlights = unread?.highlightCount;
      final countReduced =
          unread != null &&
          ((syncedNotifications != null &&
                  syncedNotifications < projection.notificationBaseline) ||
              (syncedHighlights != null &&
                  syncedHighlights < projection.highlightBaseline));
      final countConverged =
          unread != null &&
          _notificationCountWithoutProjection <=
              _projectUnreadCount(_notificationCountWithoutProjection) &&
          _matrixRoom.highlightCount <=
              _projectUnreadCount(
                _matrixRoom.highlightCount,
                highlighted: true,
              );
      if (markerChangedElsewhere ||
          (markerConfirmed && (countReduced || countConverged))) {
        _readMarkerProjection = null;
      }
    }

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
  Future<void> approveJoinRequest(String id) {
    return matrixRoom.invite(id);
  }

  @override
  Future<void> declineJoinRequest(String id) {
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
    final changed = await _setMemberPowerLevel(
      id,
      (role as MatrixRole).powerLevel,
    );

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
    // This is a raw SDK timeline built purely to move the read marker - nothing
    // else ever holds it, and matrix.Timeline registers five subscriptions on
    // client-wide broadcast streams in its constructor. Without the cancel it
    // stays live for the rest of the session, re-scanning its own event list on
    // every incoming event and every megolm key received for this room.
    //
    // Deliberately NOT routed through this room's `_timeline`: that one is
    // owned and displayed by the open Chat, and replacing it here would leave
    // the chat subscribed to a timeline nobody updates.
    final tl = await matrixRoom.getTimeline();
    try {
      final target = tl.events.firstWhereOrNull(
        (event) => event.status.isSynced,
      );
      if (target == null) return;
      final notificationBaseline = _notificationCountWithoutProjection;
      final highlightBaseline = _matrixRoom.highlightCount;
      final requestStartSequence = _notificationSequence;
      final previousMarkerEventId = _matrixRoom.fullyRead;
      await tl.setReadMarker(
        eventId: target.eventId,
        public: _readMarkerIsPublic(),
      );
      await _confirmReadMarker(
        target.eventId,
        notificationBaseline,
        highlightBaseline,
        requestStartSequence,
        previousMarkerEventId,
      );
    } finally {
      tl.cancelSubscriptions();
    }
  }

  bool _readMarkerIsPublic() {
    final readReceiptComponent = getComponent<MatrixReadReceiptComponent>();
    var public = true;
    final presenceComp = client.getComponent<MatrixUserPresenceComponent>();

    if (presenceComp?.usePublicReadReceipts != null) {
      public = presenceComp!.usePublicReadReceipts;
    }
    if (readReceiptComponent?.usePublicReadReceiptsForRoom != null) {
      public = readReceiptComponent!.usePublicReadReceiptsForRoom!;
    }
    return public;
  }

  @override
  RoomVisibility get visibility {
    return visibilityFromMatrixJoinRules(
      _matrixRoom.joinRules,
      _matrixRoom.getState(matrix.EventTypes.RoomJoinRules)?.content,
    );
  }

  @override
  Future<void> setVisibility(RoomVisibility visibility) async {
    await _matrixRoom.client.setRoomStateWithKey(
      _matrixRoom.id,
      matrix.EventTypes.RoomJoinRules,
      "",
      joinRulesContentForVisibility(visibility),
    );
    await _matrixRoom.waitForRoomInSync();
    _onUpdate.add(null);
  }

  static RoomVisibility visibilityFromMatrixJoinRules(
    matrix.JoinRules? joinRules,
    Map<String, dynamic>? content,
  ) {
    return switch (joinRules) {
      matrix.JoinRules.public => RoomVisibilityPublic(),
      matrix.JoinRules.knock => RoomVisibilityKnock(),
      matrix.JoinRules.invite ||
      matrix.JoinRules.private ||
      null => RoomVisibilityPrivate(),
      matrix.JoinRules.restricted => RoomVisibilityRestricted(
        _allowRoomIdsFromJoinRulesContent(content),
      ),
      matrix.JoinRules.knockRestricted => RoomVisibilityKnockRestricted(
        _allowRoomIdsFromJoinRulesContent(content),
      ),
    };
  }

  @visibleForTesting
  static bool shouldHydrateMissingMemberAvatarsForJoinRules(
    matrix.JoinRules? joinRules,
  ) {
    return switch (joinRules) {
      matrix.JoinRules.knock || matrix.JoinRules.knockRestricted => true,
      _ => false,
    };
  }

  static Map<String, dynamic> joinRulesContentForVisibility(
    RoomVisibility visibility,
  ) {
    return switch (visibility) {
      final RoomVisibilityPrivate _ => {"join_rule": "invite"},
      final RoomVisibilityPublic _ => {"join_rule": "public"},
      final RoomVisibilityKnock _ => {"join_rule": "knock"},
      final RoomVisibilityRestricted restricted => _restrictedJoinRulesContent(
        "restricted",
        restricted.spaces,
      ),
      final RoomVisibilityKnockRestricted restricted =>
        _restrictedJoinRulesContent("knock_restricted", restricted.spaces),
      RoomVisibility() => throw UnimplementedError(),
    };
  }

  static Map<String, dynamic> _restrictedJoinRulesContent(
    String joinRule,
    List<String> spaces,
  ) {
    return {
      "join_rule": joinRule,
      "allow": [
        for (final space in spaces)
          {"room_id": space, "type": "m.room_membership"},
      ],
    };
  }

  static List<String> _allowRoomIdsFromJoinRulesContent(
    Map<String, dynamic>? content,
  ) {
    return content
            ?.tryGetList<Map<String, dynamic>>("allow")
            ?.map((item) => item.tryGet<String>("room_id"))
            .nonNulls
            .toList() ??
        [];
  }
}

class _ReadMarkerProjection {
  _ReadMarkerProjection(
    this.targetEventId,
    this.previousMarkerEventId,
    this.notificationBaseline,
    this.highlightBaseline,
    this.orderKnown,
    this.newerEventIds,
    this.atOrBeforeEventIds,
    this.hasNewerInboundMessage,
    this.hasNewerDirectMention,
    this.newerNotifications,
    this.lastEventIdAtConfirmation,
  );

  final String targetEventId;
  final String previousMarkerEventId;
  final int notificationBaseline;
  final int highlightBaseline;
  bool orderKnown;
  final Set<String> newerEventIds;
  final Set<String> atOrBeforeEventIds;
  final bool hasNewerInboundMessage;
  final bool hasNewerDirectMention;
  final Map<String, _RecentNotification> newerNotifications;
  final String? lastEventIdAtConfirmation;
}

class _RecentNotification {
  const _RecentNotification(this.sequence, this.highlighted, this.roomMention);

  final int sequence;
  final bool highlighted;
  final bool roomMention;
}
